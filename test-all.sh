#!/bin/bash
# ==============================================================================
# Odoo 15 Docker - Automated Testing Script
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
PASSED=0
FAILED=0

# Functions
print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

print_test() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    ((PASSED++))
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    ((FAILED++))
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ==============================================================================
# Test 1: Container Status
# ==============================================================================
test_container_status() {
    print_header "TEST 1: Container Status"

    print_test "Checking if odoo15-app is running..."
    if docker compose ps | grep -q "odoo15-app.*Up"; then
        print_success "Odoo container is running"
    else
        print_error "Odoo container is not running"
        return 1
    fi

    print_test "Checking if odoo15-db is running..."
    if docker compose ps | grep -q "odoo15-db.*Up"; then
        print_success "Database container is running"
    else
        print_error "Database container is not running"
        return 1
    fi
}

# ==============================================================================
# Test 2: Logs Verification
# ==============================================================================
test_logs() {
    print_header "TEST 2: Logs Verification"

    print_test "Checking entrypoint initialization logs..."
    if docker compose logs odoo | grep -q "Odoo 15 Production Container Starting"; then
        print_success "Entrypoint started successfully"
    else
        print_error "Entrypoint initialization failed"
    fi

    print_test "Checking configuration generation..."
    if docker compose logs odoo | grep -q "Configuration file generated successfully"; then
        print_success "Configuration generated"
    else
        print_error "Configuration generation failed"
    fi

    print_test "Checking Python packages installation..."
    if docker compose logs odoo | grep -q "Python packages installed successfully"; then
        print_success "Python packages installed"
    else
        print_error "Python packages installation failed"
    fi

    print_test "Checking NPM packages installation..."
    if docker compose logs odoo | grep -q "NPM packages installed successfully"; then
        print_success "NPM packages installed"
    else
        print_error "NPM packages installation failed"
    fi

    print_test "Checking if Odoo started..."
    if docker compose logs odoo | grep -q "Starting Odoo"; then
        print_success "Odoo started"
    else
        print_error "Odoo did not start"
    fi
}

# ==============================================================================
# Test 3: GitHubSyncer Volume
# ==============================================================================
test_githubsyncer_volume() {
    print_header "TEST 3: GitHubSyncer Volume Integration"

    print_test "Checking if githubsyncer_repo_storage volume exists..."
    if docker volume ls | grep -q "githubsyncer_repo_storage"; then
        print_success "GitHubSyncer volume exists"
    else
        print_error "GitHubSyncer volume not found"
        return 1
    fi

    print_test "Checking volume mount in container..."
    if docker compose exec odoo test -d /mnt/synced-addons; then
        print_success "Volume mounted at /mnt/synced-addons"
    else
        print_error "Volume not mounted"
        return 1
    fi

    print_test "Checking odoo-core-addons directory..."
    if docker compose exec odoo test -d /mnt/synced-addons/odoo-core-addons; then
        MODULE_COUNT=$(docker compose exec odoo ls -1 /mnt/synced-addons/odoo-core-addons | wc -l)
        print_success "odoo-core-addons found with $MODULE_COUNT modules"
    else
        print_error "odoo-core-addons directory not found"
        return 1
    fi
}

# ==============================================================================
# Test 4: Addons Path Configuration
# ==============================================================================
test_addons_path() {
    print_header "TEST 4: Addons Path Configuration"

    print_test "Checking addons_path in config..."
    ADDONS_PATH=$(docker compose exec odoo cat /etc/odoo/erp.conf | grep "^addons_path")

    if echo "$ADDONS_PATH" | grep -q "/opt/odoo/odoo/addons"; then
        print_success "Framework addons path configured"
    else
        print_error "Framework addons path missing"
    fi

    if echo "$ADDONS_PATH" | grep -q "/mnt/synced-addons/odoo-core-addons"; then
        print_success "GitHubSyncer addons path configured"
    else
        print_error "GitHubSyncer addons path missing"
    fi

    if echo "$ADDONS_PATH" | grep -q "/mnt/extra-addons"; then
        print_success "Custom addons path configured"
    else
        print_error "Custom addons path missing"
    fi

    print_info "Full addons_path: $ADDONS_PATH"
}

# ==============================================================================
# Test 5: Auto-Upgrade Feature
# ==============================================================================
test_auto_upgrade() {
    print_header "TEST 5: Auto-Upgrade Feature"

    print_test "Checking AUTO_UPGRADE logs..."

    if docker compose logs odoo | grep -q "AUTO_UPGRADE is not TRUE"; then
        print_info "AUTO_UPGRADE is disabled"
    elif docker compose logs odoo | grep -q "Auto-detected database:"; then
        DB_NAME=$(docker compose logs odoo | grep "Auto-detected database:" | tail -1 | awk '{print $NF}')
        print_success "Database auto-detected: $DB_NAME"

        if docker compose logs odoo | grep -q "Automatic upgrade completed successfully"; then
            print_success "Auto-upgrade executed successfully"
        elif docker compose logs odoo | grep -q "No Odoo database found yet"; then
            print_info "No database exists yet (expected on first run)"
        else
            print_error "Auto-upgrade failed"
        fi
    else
        print_info "AUTO_UPGRADE logs not found (may be first run)"
    fi
}

# ==============================================================================
# Test 6: Database Connection
# ==============================================================================
test_database() {
    print_header "TEST 6: Database Connection"

    print_test "Checking PostgreSQL connection..."
    if docker compose exec db pg_isready -U odoo > /dev/null 2>&1; then
        print_success "PostgreSQL is ready"
    else
        print_error "PostgreSQL is not ready"
        return 1
    fi

    print_test "Listing databases..."
    DBS=$(docker compose exec db psql -U odoo -d postgres -t -c "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres', 'template0', 'template1');" 2>/dev/null | xargs)

    if [ -n "$DBS" ]; then
        print_success "Odoo databases found: $DBS"
    else
        print_info "No Odoo databases yet (expected on first run)"
    fi
}

# ==============================================================================
# Test 7: Healthcheck
# ==============================================================================
test_healthcheck() {
    print_header "TEST 7: Container Healthcheck"

    print_test "Checking container health status..."
    HEALTH=$(docker inspect odoo15-app --format='{{.State.Health.Status}}' 2>/dev/null || echo "no healthcheck")

    if [ "$HEALTH" = "healthy" ]; then
        print_success "Container is healthy"
    elif [ "$HEALTH" = "starting" ]; then
        print_info "Container is starting (health check in progress)"
    else
        print_error "Container health: $HEALTH"
    fi

    print_test "Testing HTTP endpoint..."
    if curl -f -s http://localhost:8069/web/login > /dev/null 2>&1; then
        print_success "HTTP endpoint responding"
    else
        print_error "HTTP endpoint not responding (may still be starting)"
    fi
}

# ==============================================================================
# Test 8: File Permissions
# ==============================================================================
test_permissions() {
    print_header "TEST 8: File Permissions"

    print_test "Checking odoo user/group..."
    USER_INFO=$(docker compose exec odoo id odoo 2>/dev/null)

    if echo "$USER_INFO" | grep -q "uid=1000.*gid=1000"; then
        print_success "Odoo user has correct UID/GID (1000:1000)"
    else
        print_error "Odoo user permissions incorrect: $USER_INFO"
    fi

    print_test "Checking config file ownership..."
    CONFIG_OWNER=$(docker compose exec odoo stat -c '%U:%G' /etc/odoo/erp.conf 2>/dev/null)

    if [ "$CONFIG_OWNER" = "odoo:odoo" ]; then
        print_success "Config file owned by odoo:odoo"
    else
        print_error "Config file ownership incorrect: $CONFIG_OWNER"
    fi
}

# ==============================================================================
# Test 9: Extra Addons Directory
# ==============================================================================
test_extra_addons() {
    print_header "TEST 9: Extra Addons Directory"

    print_test "Checking extra-addons mount..."
    if docker compose exec odoo test -d /mnt/extra-addons; then
        print_success "extra-addons directory mounted"

        ADDON_COUNT=$(docker compose exec odoo ls -1 /mnt/extra-addons 2>/dev/null | wc -l)
        print_info "Found $ADDON_COUNT custom modules"
    else
        print_error "extra-addons directory not mounted"
    fi
}

# ==============================================================================
# Test 10: Volume Persistence
# ==============================================================================
test_volumes() {
    print_header "TEST 10: Docker Volumes"

    print_test "Checking odoo-data volume..."
    if docker volume ls | grep -q "odoo15-core_odoo-data"; then
        print_success "odoo-data volume exists"
    else
        print_error "odoo-data volume missing"
    fi

    print_test "Checking odoo-db-data volume..."
    if docker volume ls | grep -q "odoo15-core_odoo-db-data"; then
        print_success "odoo-db-data volume exists"
    else
        print_error "odoo-db-data volume missing"
    fi

}

# ==============================================================================
# Main Execution
# ==============================================================================
main() {
    print_header "Odoo 15 Docker - Automated Test Suite"
    print_info "Starting comprehensive tests..."
    echo ""

    # Run all tests
    test_container_status || true
    test_logs || true
    test_githubsyncer_volume || true
    test_addons_path || true
    test_auto_upgrade || true
    test_database || true
    test_healthcheck || true
    test_permissions || true
    test_extra_addons || true
    test_volumes || true

    # Summary
    print_header "Test Summary"
    echo -e "${GREEN}Passed: $PASSED${NC}"
    echo -e "${RED}Failed: $FAILED${NC}"
    echo ""

    if [ $FAILED -eq 0 ]; then
        print_success "All tests passed! 🎉"
        exit 0
    else
        print_error "Some tests failed. Check the output above."
        exit 1
    fi
}

# Run main function
main
