# =============================================================================
# Production Odoo 15 Docker Image with click-odoo Auto Upgrade
# Image: jaah/odoo:15
# =============================================================================

FROM python:3.10-slim

LABEL maintainer="jaah" \
      version="15.0" \
      description="Production Odoo 15 with click-odoo auto-upgrade support"

# -----------------------------------------------------------------------------
# Environment Variables (defaults)
# -----------------------------------------------------------------------------
ENV ODOO_VERSION=15.0 \
    ODOO_SOURCE=/opt/odoo \
    ERP_CONF_PATH=/etc/odoo/erp.conf \
    ODOO_DATA_DIR=/var/lib/odoo \
    ODOO_PORT=8069 \
    PUID=1000 \
    PGID=1000 \
    AUTO_UPGRADE=FALSE \
    ODOO_DB_NAME="" \
    INITDB_OPTIONS="" \
    PY_INSTALL="" \
    NPM_INSTALL=""

# -----------------------------------------------------------------------------
# System Dependencies
# -----------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # Build tools
        build-essential \
        gcc \
        g++ \
        # Version control
        git \
        # Network utilities
        curl \
        wget \
        ca-certificates \
        gnupg \
        # PostgreSQL client
        libpq-dev \
        postgresql-client \
        # XML/XSLT
        libxml2-dev \
        libxslt1-dev \
        # LDAP/SASL
        libldap2-dev \
        libsasl2-dev \
        # Image processing
        libjpeg-dev \
        zlib1g-dev \
        libpng-dev \
        libfreetype6-dev \
        liblcms2-dev \
        libtiff5-dev \
        libwebp-dev \
        libopenjp2-7-dev \
        # Text rendering (for complex scripts and RTL languages like Arabic)
        libharfbuzz-dev \
        libfribidi-dev \
        # X11 dependencies
        libxcb1-dev \
        # Fonts (for PDF generation)
        fonts-liberation \
        fonts-dejavu-core \
        fontconfig \
        # Other Odoo dependencies
        libffi-dev \
        libssl-dev \
        libblas-dev \
        liblapack-dev \
        # Utilities
        xz-utils \
        zip \
        unzip \
        sudo \
        gosu \
    ; \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install libssl1.1 (required by wkhtmltopdf but not available in newer Debian)
# We install it from Debian Bullseye (oldstable) repository
# -----------------------------------------------------------------------------
RUN set -eux; \
    # Add Debian Bullseye repository for libssl1.1
    echo "deb http://deb.debian.org/debian bullseye main" > /etc/apt/sources.list.d/bullseye.list; \
    # Set lower priority for bullseye to avoid unintended upgrades
    echo "Package: *\nPin: release n=bullseye\nPin-Priority: 100" > /etc/apt/preferences.d/bullseye; \
    apt-get update; \
    # Install libssl1.1 from bullseye
    apt-get install -y --no-install-recommends libssl1.1; \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install wkhtmltopdf (compatible version for Odoo 15)
# Using the Debian Bullseye build which works well with Odoo 15
# Now that libssl1.1 is installed, wkhtmltopdf will work correctly
# -----------------------------------------------------------------------------
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    case "$ARCH" in \
        amd64) WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.bullseye_amd64.deb" ;; \
        arm64) WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.bullseye_arm64.deb" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/wkhtmltox.deb "$WKHTMLTOPDF_URL"; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/wkhtmltox.deb; \
    rm -rf /tmp/wkhtmltox.deb /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install Node.js and npm (LTS version for Odoo 15 compatibility)
# Using Node.js 20 LTS (current stable LTS, compatible with Odoo 15)
# -----------------------------------------------------------------------------
RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; \
    apt-get install -y --no-install-recommends nodejs; \
    npm install -g npm@latest; \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Create odoo user and directories
# -----------------------------------------------------------------------------
RUN set -eux; \
    groupadd --gid ${PGID} odoo; \
    useradd --uid ${PUID} --gid odoo --shell /bin/bash --create-home odoo; \
    mkdir -p /opt/odoo \
             /etc/odoo \
             /var/lib/odoo \
             /var/lib/odoo/.state \
             /var/log/odoo \
             /mnt/extra-addons; \
    chown -R odoo:odoo /opt/odoo /etc/odoo /var/lib/odoo /var/log/odoo /mnt/extra-addons

# -----------------------------------------------------------------------------
# Clone Odoo 15 Source Code
# -----------------------------------------------------------------------------
RUN set -eux; \
    git clone --depth 1 --branch ${ODOO_VERSION} \
        https://github.com/odoo/odoo.git /opt/odoo; \
    chown -R odoo:odoo /opt/odoo

# -----------------------------------------------------------------------------
# Install Odoo Python Dependencies
# -----------------------------------------------------------------------------
RUN set -eux; \
    pip install --no-cache-dir --upgrade pip setuptools wheel; \
    pip install --no-cache-dir -r /opt/odoo/requirements.txt; \
    # Upgrade gevent to a version compatible with Python 3.10
    # The version in requirements.txt (21.8.0) is too old and fails to build
    pip install --no-cache-dir --upgrade gevent==23.9.1; \
    # Install additional common dependencies for Odoo 15
    pip install --no-cache-dir \
        phonenumbers \
        python-stdnum \
        vobject \
        xlrd \
        xlwt \
        num2words \
        passlib \
        pyopenssl \
        polib

# -----------------------------------------------------------------------------
# Install click-odoo and click-odoo-contrib
# -----------------------------------------------------------------------------
RUN set -eux; \
    pip install --no-cache-dir \
        click-odoo \
        click-odoo-contrib

# -----------------------------------------------------------------------------
# Set Odoo in PYTHONPATH so 'import odoo' works for click-odoo
# -----------------------------------------------------------------------------
ENV PYTHONPATH="${ODOO_SOURCE}:${PYTHONPATH}"

# -----------------------------------------------------------------------------
# Copy entrypoint script
# -----------------------------------------------------------------------------
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# -----------------------------------------------------------------------------
# Set working directory
# -----------------------------------------------------------------------------
WORKDIR /opt/odoo

# -----------------------------------------------------------------------------
# Expose Odoo ports
# -----------------------------------------------------------------------------
EXPOSE 8069 8071 8072

# -----------------------------------------------------------------------------
# Define volumes
# -----------------------------------------------------------------------------
VOLUME ["/var/lib/odoo", "/mnt/extra-addons", "/var/log/odoo"]

# -----------------------------------------------------------------------------
# Healthcheck
# -----------------------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
    CMD curl -f http://localhost:${ODOO_PORT:-8069}/web/login || exit 1

# -----------------------------------------------------------------------------
# Entrypoint and Command
# -----------------------------------------------------------------------------
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["odoo"]
