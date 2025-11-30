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
# Step 3: Python Package Installation (PY_INSTALL)
# Checks if packages are installed at each startup (stateless)
# -----------------------------------------------------------------------------
install_python_packages() {
    local py_install="${PY_INSTALL:-}"

    # Skip if PY_INSTALL is empty
    if [ -z "$py_install" ]; then
        log_info "PY_INSTALL not set, skipping Python package installation."
        return 0
    fi

    log_info "Checking Python packages: ${py_install}..."

    # Check each package to see if it needs installation
    local needs_install=false
    IFS=',' read -ra PKG_ARRAY <<< "$py_install"

    for pkg in "${PKG_ARRAY[@]}"; do
        pkg=$(echo "$pkg" | xargs)  # Trim whitespace

        if [ -z "$pkg" ]; then
            continue
        fi

        # Extract package name and version if specified
        if [[ "$pkg" == *"=="* ]]; then
            local pkg_name="${pkg%%==*}"
            local pkg_version="${pkg#*==}"

            # Check if installed with correct version
            if pip show "$pkg_name" 2>/dev/null | grep -q "Version: $pkg_version"; then
                log_info "  ✓ $pkg already installed"
            else
                log_info "  ✗ $pkg needs installation/upgrade"
                needs_install=true
            fi
        else
            # No version specified, just check if installed
            if pip show "$pkg" &>/dev/null; then
                local installed_version=$(pip show "$pkg" 2>/dev/null | grep "Version:" | awk '{print $2}')
                log_info "  ✓ $pkg already installed (version: $installed_version)"
            else
                log_info "  ✗ $pkg needs installation"
                needs_install=true
            fi
        fi
    done

    # Install only if needed
    if [ "$needs_install" = true ]; then
        log_info "Installing Python packages: ${py_install}..."

        # Convert comma-separated list to space-separated for pip
        local packages="${py_install//,/ }"

        if pip install --no-cache-dir $packages; then
            log_info "Python packages installed successfully."
        else
            log_error "Failed to install Python packages!"
            return 1
        fi
    else
        log_info "All Python packages already installed."
    fi
}

# -----------------------------------------------------------------------------
# Step 4: NPM Package Installation (NPM_INSTALL)
# Checks if packages are installed at each startup (stateless)
# -----------------------------------------------------------------------------
install_npm_packages() {
    local npm_install="${NPM_INSTALL:-}"

    # Skip if NPM_INSTALL is empty
    if [ -z "$npm_install" ]; then
        log_info "NPM_INSTALL not set, skipping NPM package installation."
        return 0
    fi

    log_info "Checking NPM packages: ${npm_install}..."

    # Check each package to see if it needs installation
    local needs_install=false
    IFS=',' read -ra PKG_ARRAY <<< "$npm_install"

    for pkg in "${PKG_ARRAY[@]}"; do
        pkg=$(echo "$pkg" | xargs)  # Trim whitespace

        if [ -z "$pkg" ]; then
            continue
        fi

        # Check if package is installed globally
        if npm list -g "$pkg" --depth=0 &>/dev/null; then
            local installed_version=$(npm list -g "$pkg" --depth=0 2>/dev/null | grep "$pkg" | sed -n 's/.*@\([0-9.]*\).*/\1/p')
            log_info "  ✓ $pkg already installed (version: $installed_version)"
        else
            log_info "  ✗ $pkg needs installation"
            needs_install=true
        fi
    done

    # Install only if needed
    if [ "$needs_install" = true ]; then
        log_info "Installing NPM packages: ${npm_install}..."

        # Convert comma-separated list to space-separated for npm
        local packages="${npm_install//,/ }"

        # Install packages globally
        if npm install -g $packages; then
            log_info "NPM packages installed successfully."
        else
            log_error "Failed to install NPM packages!"
            return 1
        fi
    else
        log_info "All NPM packages already installed."
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
    local auto_upgrade="${AUTO_UPGRADE:-TRUE}"
    local db_name="${ODOO_DB_NAME:-}"

    # Convert to uppercase for comparison
    auto_upgrade="${auto_upgrade^^}"

    # Skip if AUTO_UPGRADE is not TRUE
    if [ "$auto_upgrade" != "TRUE" ]; then
        log_info "AUTO_UPGRADE is not TRUE, skipping automatic upgrade."
        return 0
    fi

    # Auto-detect database if not specified
    if [ -z "$db_name" ]; then
        log_info "ODOO_DB_NAME not set, auto-detecting Odoo database..."

        # Get database connection details from conf.* environment variables
        local db_host=$(printenv 'conf.db_host' || echo 'db')
        local db_port=$(printenv 'conf.db_port' || echo '5432')
        local db_user=$(printenv 'conf.db_user' || echo 'odoo')
        local db_password=$(printenv 'conf.db_password' || echo 'odoo')

        # Find first non-system database
        db_name=$(PGPASSWORD="$db_password" psql -h "$db_host" -p "$db_port" -U "$db_user" -d postgres -t -c \
            "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres', 'template0', 'template1') ORDER BY datname LIMIT 1;" \
            2>/dev/null | xargs)

        if [ -z "$db_name" ]; then
            log_info "No Odoo database found yet, skipping automatic upgrade."
            return 0
        fi

        log_info "Auto-detected database: ${db_name}"
    fi

    log_info "Checking for modules that need upgrade in database: ${db_name}..."

    # First, list modules that will be upgraded (without actually upgrading)
    # This gives visibility into what changes will be applied
    log_info "=== Modules to be upgraded ==="
    if gosu odoo click-odoo-update -c "$ERP_CONF_PATH" -d "$db_name" --list-only 2>&1 | tee /tmp/upgrade-list.log; then
        log_info "=== End of modules list ==="

        # Check if there are any modules to upgrade
        if grep -q "to update" /tmp/upgrade-list.log 2>/dev/null; then
            log_info "Running automatic upgrade with translation overwrite..."

            # Run actual upgrade with --i18n-overwrite to update translations
            # This ensures translations are kept up-to-date with module changes
            if gosu odoo click-odoo-update -c "$ERP_CONF_PATH" -d "$db_name" --i18n-overwrite; then
                log_info "Automatic upgrade completed successfully."
            else
                local exit_code=$?
                log_warn "click-odoo-update exited with code ${exit_code}. Continuing startup..."
            fi
        else
            log_info "No modules need upgrading. System is up-to-date."
        fi
    else
        log_warn "Failed to check modules list. Skipping upgrade."
    fi

    # Cleanup
    rm -f /tmp/upgrade-list.log
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
