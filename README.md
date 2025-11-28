# Odoo 15 Production Docker Image

A production-grade Docker image for Odoo 15 with **click-odoo** integration for automatic database initialization and module upgrades.

**Image Tag:** `jaah/odoo:15`

## Features

- **Based on Python 3.10-slim** - Lightweight and secure base image
- **Odoo 15 Community Edition** - Full source code installation
- **click-odoo-initdb** - Automated database creation with module installation
- **click-odoo-update** - Automatic module upgrade on every container restart
- **Dynamic Configuration** - Generate Odoo config via `conf.*` environment variables
- **One-Time Package Installation** - Install Python/NPM packages via environment variables
- **PUID/PGID Support** - Flexible file permission management
- **Docker Healthcheck** - Built-in health monitoring
- **Production Ready** - Optimized for SaaS environments

## Quick Start

### 1. Clone or Create Project Structure

```bash
mkdir odoo15-docker
cd odoo15-docker
# Add Dockerfile, entrypoint.sh, docker-compose.yml (see below)
```

### 2. Build the Image

```bash
docker build -t jaah/odoo:15 .
```

### 3. Run with Docker Compose

```bash
# Create extra-addons directory for custom modules
mkdir -p extra-addons

# Start the stack
docker compose up -d

# View logs
docker compose logs -f odoo
```

### 4. Access Odoo

Open your browser and navigate to: `http://localhost:8069`

## Project Structure

```
odoo15-docker/
├── Dockerfile           # Main Docker image definition
├── entrypoint.sh        # Container entrypoint with startup logic
├── docker-compose.yml   # Example production stack configuration
├── README.md            # This documentation
└── extra-addons/        # Mount point for custom Odoo modules
```

## Configuration Reference

### Environment Variables Overview

| Variable | Description | Default |
|----------|-------------|---------|
| `PUID` | User ID for odoo user | `1000` |
| `PGID` | Group ID for odoo group | `1000` |
| `ERP_CONF_PATH` | Path to Odoo config file | `/etc/odoo/erp.conf` |
| `ODOO_PORT` | HTTP port for healthcheck | `8069` |
| `INITDB_OPTIONS` | Options for click-odoo-initdb | (empty) |
| `AUTO_UPGRADE` | Enable auto-upgrade on restart | `FALSE` |
| `ODOO_DB_NAME` | Database name for auto-upgrade | (empty) |
| `PY_INSTALL` | Python packages to install | (empty) |
| `NPM_INSTALL` | NPM packages to install | (empty) |
| `conf.*` | Dynamic Odoo configuration | (various) |

### Odoo Configuration via `conf.*` Variables

The container automatically generates `/etc/odoo/erp.conf` from environment variables prefixed with `conf.`.

**How it works:**
1. On container start, the entrypoint scans all environment variables
2. Variables starting with `conf.` are extracted
3. The `conf.` prefix is stripped, and key-value pairs are written to the config file

**Example Environment:**

```yaml
environment:
  conf.admin_passwd: admin
  conf.db_host: db
  conf.db_port: 5432
  conf.db_user: odoo
  conf.db_password: odoo
  conf.addons_path: /opt/odoo/addons,/mnt/extra-addons
  conf.logfile: /var/log/odoo/odoo.log
  conf.workers: 4
  conf.proxy_mode: True
```

**Generated Config (`/etc/odoo/erp.conf`):**

```ini
[options]
admin_passwd = admin
db_host = db
db_port = 5432
db_user = odoo
db_password = odoo
addons_path = /opt/odoo/addons,/mnt/extra-addons
logfile = /var/log/odoo/odoo.log
workers = 4
proxy_mode = True
```

### Database Initialization (`INITDB_OPTIONS`)

Uses [click-odoo-initdb](https://github.com/acsone/click-odoo-contrib) to create databases.

**Environment Variable:**
```yaml
INITDB_OPTIONS: "-n mydb -m base,web --unless-initialized"
```

**Common Options:**

| Option | Description |
|--------|-------------|
| `-n, --db-name` | Name of the database to create |
| `-m, --modules` | Comma-separated list of modules to install |
| `--unless-initialized` | Skip if database already exists |
| `--demo` | Load demo data |
| `--no-demo` | Don't load demo data (default) |

**Behavior:**
- If `INITDB_OPTIONS` is empty, database initialization is skipped
- The `--unless-initialized` flag prevents re-initialization on container restarts
- Relies on click-odoo-initdb's native database existence checking

**Examples:**

```yaml
# Create 'production' database with minimal modules
INITDB_OPTIONS: "-n production -m base,web --unless-initialized"

# Create database with demo data
INITDB_OPTIONS: "-n demo_db -m base,sale,purchase --demo --unless-initialized"

# Create without the skip flag (will error if DB exists)
INITDB_OPTIONS: "-n fresh_db -m base"
```

### Auto-Upgrade on Restart (`AUTO_UPGRADE`)

Uses [click-odoo-update](https://github.com/acsone/click-odoo-contrib) to automatically upgrade modules.

**Environment Variables:**
```yaml
AUTO_UPGRADE: "TRUE"
ODOO_DB_NAME: mydb
```

**Behavior:**
- Runs on **every** container restart when `AUTO_UPGRADE=TRUE`
- Requires `ODOO_DB_NAME` to be set
- click-odoo-update uses internal module hashing to detect changes
- Only modules that have actually changed are upgraded
- No custom version state is maintained - relies entirely on click-odoo-update's logic

**Important Notes:**
- This is designed for development and staging environments
- In production, you may want to run upgrades manually during maintenance windows
- Set `AUTO_UPGRADE=FALSE` to disable automatic upgrades

### One-Time Package Installation

#### Python Packages (`PY_INSTALL`)

```yaml
PY_INSTALL: "asn1crypto,Babel==2.9.1,phonenumbers"
```

**Behavior:**
- Packages are installed via `pip install`
- Only runs once per volume instance
- State tracked in `/var/lib/odoo/.state/py_install.done`
- Subsequent restarts skip installation if state file exists

#### NPM Packages (`NPM_INSTALL`)

```yaml
NPM_INSTALL: "rtlcss,less"
```

**Behavior:**
- Packages are installed globally via `npm install -g`
- Only runs once per volume instance
- State tracked in `/var/lib/odoo/.state/npm_install.done`
- Subsequent restarts skip installation if state file exists

**Note:** Since `/var/lib/odoo` is typically a Docker volume, the state files persist across container recreations, ensuring packages are only installed once.

### User Permissions (`PUID`/`PGID`)

```yaml
PUID: 1000
PGID: 1000
```

**Behavior:**
- The internal `odoo` user/group is modified to match these IDs
- All Odoo directories are chowned to the specified IDs
- Useful when mounting volumes from the host to ensure proper permissions

**Use Case:**
If your host user has UID 1001, set `PUID=1001` to avoid permission issues with mounted volumes.

## Volumes

| Path | Purpose |
|------|---------|
| `/var/lib/odoo` | Odoo data (filestore, sessions, state files) |
| `/mnt/extra-addons` | Custom Odoo modules |
| `/var/log/odoo` | Odoo log files |

**Example Docker Compose Volumes:**

```yaml
volumes:
  - odoo-data:/var/lib/odoo
  - ./extra-addons:/mnt/extra-addons:ro
  - odoo-logs:/var/log/odoo
```

## Mounting Extra Addons

To add custom Odoo modules:

1. Create a directory for your addons:
   ```bash
   mkdir -p extra-addons
   ```

2. Place your modules in the directory:
   ```
   extra-addons/
   ├── my_custom_module/
   │   ├── __init__.py
   │   └── __manifest__.py
   └── another_module/
       ├── __init__.py
       └── __manifest__.py
   ```

3. Mount the directory and update `addons_path`:
   ```yaml
   volumes:
     - ./extra-addons:/mnt/extra-addons:ro
   environment:
     conf.addons_path: /opt/odoo/addons,/opt/odoo/odoo/addons,/mnt/extra-addons
   ```

4. Restart the container and install your modules via the Odoo Apps menu.

## Healthcheck

The image includes a built-in healthcheck:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
    CMD curl -f http://localhost:${ODOO_PORT:-8069}/web/login || exit 1
```

**Parameters:**
- **Interval:** 30 seconds between checks
- **Timeout:** 5 seconds per check
- **Start Period:** 90 seconds grace period for startup
- **Retries:** 5 failed checks before unhealthy

**Check Status:**
```bash
docker inspect --format='{{.State.Health.Status}}' odoo15-app
```

## Startup Sequence

The entrypoint executes the following steps in order:

1. **User Setup** - Adjust `odoo` user/group to match `PUID`/`PGID`
2. **Config Generation** - Build `/etc/odoo/erp.conf` from `conf.*` variables
3. **Python Install** - Run `PY_INSTALL` (once per instance)
4. **NPM Install** - Run `NPM_INSTALL` (once per instance)
5. **Database Init** - Run `click-odoo-initdb` if `INITDB_OPTIONS` is set
6. **Auto-Upgrade** - Run `click-odoo-update` if `AUTO_UPGRADE=TRUE`
7. **Start Odoo** - Execute Odoo with `exec` for proper signal handling

## Production Recommendations

### Security

1. **Change admin password:**
   ```yaml
   conf.admin_passwd: use_a_strong_password_here
   ```

2. **Use secrets for sensitive data:**
   ```yaml
   environment:
     conf.db_password_file: /run/secrets/db_password
   secrets:
     - db_password
   ```

3. **Enable proxy mode behind reverse proxy:**
   ```yaml
   conf.proxy_mode: True
   ```

### Performance

1. **Configure workers based on CPU:**
   ```yaml
   conf.workers: 4  # Generally: (2 * CPU cores) + 1
   conf.max_cron_threads: 2
   ```

2. **Set appropriate limits:**
   ```yaml
   conf.limit_memory_hard: 2684354560  # 2.5 GB
   conf.limit_memory_soft: 2147483648  # 2 GB
   conf.limit_time_cpu: 600
   conf.limit_time_real: 1200
   ```

### Logging

1. **For container orchestration (use stdout):**
   ```yaml
   conf.logfile: False
   ```

2. **For file-based logging:**
   ```yaml
   conf.logfile: /var/log/odoo/odoo.log
   conf.log_level: info
   ```

## Troubleshooting

### Check Logs

```bash
# Container logs
docker compose logs -f odoo

# Odoo application logs (if file logging enabled)
docker compose exec odoo cat /var/log/odoo/odoo.log
```

### Access Container Shell

```bash
docker compose exec odoo bash
```

### Check Generated Config

```bash
docker compose exec odoo cat /etc/odoo/erp.conf
```

### Reset State Files

To re-run package installations:

```bash
docker compose exec odoo rm -f /var/lib/odoo/.state/py_install.done
docker compose exec odoo rm -f /var/lib/odoo/.state/npm_install.done
docker compose restart odoo
```

### Database Issues

Check PostgreSQL connectivity:
```bash
docker compose exec odoo psql -h db -U odoo -d postgres -c "SELECT 1"
```

## License

This Docker configuration is provided as-is. Odoo Community Edition is licensed under LGPL-3.

## Links

- [Odoo Documentation](https://www.odoo.com/documentation/15.0/)
- [click-odoo](https://github.com/acsone/click-odoo)
- [click-odoo-contrib](https://github.com/acsone/click-odoo-contrib)
