#!/bin/bash
# =============================================================================
# Odoo 15 Production Entrypoint Script
# Handles: PUID/PGID, config generation, package installs, DB init, auto-upgrade
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration Variables
# -----------------------------------------------------------------------------
ERP_CONF_PATH="${ERP_CONF_PATH:-/etc/odoo/erp.conf}"
ODOO_DATA_DIR="${ODOO_DATA_DIR:-/var/lib/odoo}"
ODOO_SOURCE="${ODOO_SOURCE:-/opt/odoo}"
STATE_DIR="${ODOO_DATA_DIR}/.state"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# -----------------------------------------------------------------------------
# Logging Functions
# -----------------------------------------------------------------------------
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# -----------------------------------------------------------------------------
# Step 1: Handle PUID/PGID - Adjust odoo user/group to match requested IDs
# -----------------------------------------------------------------------------
setup_user_permissions() {
    log_info "Setting up user permissions (PUID=${PUID}, PGID=${PGID})..."

    # Get current odoo user/group IDs
    CURRENT_UID=$(id -u odoo 2>/dev/null || echo "")
    CURRENT_GID=$(getent group odoo | cut -d: -f3 2>/dev/null || echo "")

    # Modify group if PGID differs
    if [ -n "$CURRENT_GID" ] && [ "$CURRENT_GID" != "$PGID" ]; then
        log_info "Changing odoo group GID from ${CURRENT_GID} to ${PGID}..."
        groupmod -o -g "$PGID" odoo
    fi

    # Modify user if PUID differs
    if [ -n "$CURRENT_UID" ] && [ "$CURRENT_UID" != "$PUID" ]; then
        log_info "Changing odoo user UID from ${CURRENT_UID} to ${PUID}..."
        usermod -o -u "$PUID" odoo
    fi

    # Ensure ownership of important directories
    log_info "Fixing ownership of Odoo directories..."
    chown -R odoo:odoo "$ODOO_DATA_DIR" || true
    chown -R odoo:odoo /etc/odoo || true
    chown -R odoo:odoo /var/log/odoo || true
    chown -R odoo:odoo /mnt/extra-addons 2>/dev/null || true

    # Ensure state directory exists
    mkdir -p "$STATE_DIR"
    chown odoo:odoo "$STATE_DIR"

    log_info "User permissions configured successfully."
}

# -----------------------------------------------------------------------------
# Step 2: Generate Odoo Configuration from conf.* Environment Variables
# -----------------------------------------------------------------------------
generate_config() {
    log_info "Generating Odoo configuration at ${ERP_CONF_PATH}..."

    # Ensure config directory exists
    mkdir -p "$(dirname "$ERP_CONF_PATH")"

    # Start config file with [options] section
    echo "[options]" > "$ERP_CONF_PATH"

    # Iterate through all environment variables starting with "conf."
    # Extract key-value pairs and write to config file
    while IFS='=' read -r name value; do
        # Check if variable starts with "conf."
        if [[ "$name" == conf.* ]]; then
            # Strip "conf." prefix to get the actual key
            key="${name#conf.}"
            # Write to config file in Odoo format (key = value)
            echo "${key} = ${value}" >> "$ERP_CONF_PATH"
            log_info "  Config: ${key} = ${value}"
        fi
    done < <(env)

    # Ensure config file is owned by odoo
    chown odoo:odoo "$ERP_CONF_PATH"
    chmod 640 "$ERP_CONF_PATH"

    log_info "Configuration file generated successfully."
}

# -----------------------------------------------------------------------------
# Step 3: One-Time Python Package Installation (PY_INSTALL)
# Only runs once per instance (state tracked in volume)
# -----------------------------------------------------------------------------
install_python_packages() {
    local py_install="${PY_INSTALL:-}"
    local state_file="${STATE_DIR}/py_install.done"

    # Skip if PY_INSTALL is empty
    if [ -z "$py_install" ]; then
        log_info "PY_INSTALL not set, skipping Python package installation."
        return 0
    fi

    # Skip if already installed (state file exists)
    if [ -f "$state_file" ]; then
        log_info "Python packages already installed (found ${state_file}), skipping."
        return 0
    fi

    log_info "Installing Python packages: ${py_install}..."

    # Convert comma-separated list to space-separated for pip
    local packages="${py_install//,/ }"

    # Install packages
    if pip install --no-cache-dir $packages; then
        # Mark as done
        touch "$state_file"
        chown odoo:odoo "$state_file"
        log_info "Python packages installed successfully."
    else
        log_error "Failed to install Python packages!"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Step 4: One-Time NPM Package Installation (NPM_INSTALL)
# Only runs once per instance (state tracked in volume)
# -----------------------------------------------------------------------------
install_npm_packages() {
    local npm_install="${NPM_INSTALL:-}"
    local state_file="${STATE_DIR}/npm_install.done"

    # Skip if NPM_INSTALL is empty
    if [ -z "$npm_install" ]; then
        log_info "NPM_INSTALL not set, skipping NPM package installation."
        return 0
    fi

    # Skip if already installed (state file exists)
    if [ -f "$state_file" ]; then
        log_info "NPM packages already installed (found ${state_file}), skipping."
        return 0
    fi

    log_info "Installing NPM packages: ${npm_install}..."

    # Convert comma-separated list to space-separated for npm
    local packages="${npm_install//,/ }"

    # Install packages globally
    if npm install -g $packages; then
        # Mark as done
        touch "$state_file"
        chown odoo:odoo "$state_file"
        log_info "NPM packages installed successfully."
    else
        log_error "Failed to install NPM packages!"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Step 5: Database Initialization with click-odoo-initdb
# Uses --unless-initialized to skip if DB already exists
# -----------------------------------------------------------------------------
initialize_database() {
    local initdb_options="${INITDB_OPTIONS:-}"

    # Skip if INITDB_OPTIONS is empty
    if [ -z "$initdb_options" ]; then
        log_info "INITDB_OPTIONS not set, skipping database initialization."
        return 0
    fi

    log_info "Running click-odoo-initdb with options: ${initdb_options}..."

    # Run click-odoo-initdb as odoo user
    # The --unless-initialized flag (if provided) prevents re-initialization
    if gosu odoo click-odoo-initdb -c "$ERP_CONF_PATH" $initdb_options; then
        log_info "Database initialization completed successfully."
    else
        local exit_code=$?
        # Exit code 1 might mean DB already exists with --unless-initialized
        # We log a warning but don't fail the startup
        log_warn "click-odoo-initdb exited with code ${exit_code}. This may be normal if the database already exists."
    fi
}

# -----------------------------------------------------------------------------
# Step 6: Automatic Module Upgrade with click-odoo-update
# Runs on every container restart when AUTO_UPGRADE=TRUE
# click-odoo-update handles module hashing internally
# -----------------------------------------------------------------------------
run_auto_upgrade() {
    local auto_upgrade="${AUTO_UPGRADE:-FALSE}"
    local db_name="${ODOO_DB_NAME:-}"

    # Convert to uppercase for comparison
    auto_upgrade="${auto_upgrade^^}"

    # Skip if AUTO_UPGRADE is not TRUE
    if [ "$auto_upgrade" != "TRUE" ]; then
        log_info "AUTO_UPGRADE is not TRUE, skipping automatic upgrade."
        return 0
    fi

    # Skip if ODOO_DB_NAME is not set
    if [ -z "$db_name" ]; then
        log_warn "AUTO_UPGRADE is TRUE but ODOO_DB_NAME is not set, skipping upgrade."
        return 0
    fi

    log_info "Running click-odoo-update for database: ${db_name}..."

    # Run click-odoo-update as odoo user
    # click-odoo-update handles module hashing internally and only upgrades changed modules
    if gosu odoo click-odoo-update -c "$ERP_CONF_PATH" -d "$db_name"; then
        log_info "Automatic upgrade completed successfully."
    else
        local exit_code=$?
        log_warn "click-odoo-update exited with code ${exit_code}. Continuing startup..."
    fi
}

# -----------------------------------------------------------------------------
# Step 7: Start Odoo
# Uses exec to ensure Odoo receives Unix signals (SIGTERM, etc.)
# -----------------------------------------------------------------------------
start_odoo() {
    log_info "Starting Odoo..."

    cd "$ODOO_SOURCE"

    # Use exec with gosu to run as odoo user and replace shell process
    # This ensures proper signal handling
    exec gosu odoo python odoo-bin -c "$ERP_CONF_PATH" "$@"
}

# -----------------------------------------------------------------------------
# Main Entrypoint Logic
# -----------------------------------------------------------------------------
main() {
    log_info "=========================================="
    log_info "Odoo 15 Production Container Starting..."
    log_info "=========================================="

    # Check if we're running as root (required for user setup)
    if [ "$(id -u)" != "0" ]; then
        log_error "This entrypoint must be run as root for proper user/permission handling."
        exit 1
    fi

    # Step 1: Setup user permissions (PUID/PGID)
    setup_user_permissions

    # Step 2: Generate Odoo configuration from conf.* env vars
    generate_config

    # Step 3: Install Python packages (one-time)
    install_python_packages

    # Step 4: Install NPM packages (one-time)
    install_npm_packages

    # Step 5: Initialize database if INITDB_OPTIONS is set
    initialize_database

    # Step 6: Run automatic upgrade if AUTO_UPGRADE=TRUE
    run_auto_upgrade

    # Step 7: Start Odoo with any additional arguments
    # Pass through any command line arguments (excluding the first one if it's "odoo")
    if [ "${1:-}" = "odoo" ]; then
        shift
    fi

    start_odoo "$@"
}

# -----------------------------------------------------------------------------
# Execute Main Function
# -----------------------------------------------------------------------------
main "$@"
