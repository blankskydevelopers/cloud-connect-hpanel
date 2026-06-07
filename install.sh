#!/bin/bash

# ==============================================================================
# Cloud Connect by Aizenty Automated Installer (LiteSpeed Edition)
# Target OS: Ubuntu 22.04 LTS / Ubuntu 24.04 LTS
# ==============================================================================

LOG_FILE="install.log"
exec > >(tee -a ${LOG_FILE} ) 2>&1

echo "=========================================================="
echo " Starting Cloud Connect by Aizenty Installer (LiteSpeed)  "
echo "=========================================================="
echo "Logs are being written to ${LOG_FILE}"

# Check if run as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run this installer as root (sudo bash install.sh)"
    exit 1
fi

# Auto-configure interrupted packages
echo "Fixing any interrupted package installations..."
dpkg --configure -a

FAST_UPDATE="false"
# Check if already installed to prevent accidental overwrite
if [ -f "/etc/systemd/system/panel.service" ] || [ -d "/var/www/panel" ]; then
    echo "=========================================================="
    echo "WARNING: Cloud Connect by Aizenty is already installed!"
    echo "=========================================================="
    echo "Choose an action:"
    echo "1) Fast Update [Recommended]"
    echo "2) Clean Reinstall (Full installation, wipes databases and configs)"
    echo "3) Abort"
    read -p "Select option (1-3): " INSTALL_CHOICE < /dev/tty
    
    if [ "$INSTALL_CHOICE" = "1" ]; then
        FAST_UPDATE="true"
        echo "Starting Fast Update..."
    elif [ "$INSTALL_CHOICE" = "2" ]; then
        FAST_UPDATE="false"
        echo "Starting clean reinstall (Wiping existing installation)..."
    else
        echo "Installation aborted."
        exit 0
    fi
fi

# Helper functions
log_step() {
    echo -e "\n[$(date +'%Y-%m-%d %H:%M:%S')] ===> $1"
}

handle_error() {
    local exit_code=$1
    local is_critical=$2
    local message=$3

    if [ $exit_code -ne 0 ]; then
        if [ "$is_critical" = "true" ]; then
            echo "CRITICAL ERROR: ${message} (Exit Code: ${exit_code})"
            echo "Installation aborted. Check ${LOG_FILE} for details."
            exit $exit_code
        else
            echo "WARNING: ${message} failed. Ignoring and continuing..."
        fi
    fi
}

update_env_key() {
    local key=$1
    local value=$2
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    elif grep -q "^# ${key}=" .env; then
        sed -i "s|^# ${key}=.*|${key}=${value}|" .env
    elif grep -q "^#${key}=" .env; then
        sed -i "s|^#${key}=.*|${key}=${value}|" .env
    else
        echo "${key}=${value}" >> .env
    fi
}

if [ "$FAST_UPDATE" = "false" ]; then
    # --- Step 1: Update System & Install Core Utilities ---
    log_step "Updating system packages..."
    apt-get update -y && apt-get upgrade -y
    handle_error $? false "System package upgrade"

    apt-get install -y wget curl git software-properties-common unzip ufw sudo fail2ban redis-server certbot python3-certbot-nginx acl
    handle_error $? true "Installing core utilities, intrusion prevention, Redis, and Certbot"

    # --- Step 2: Configure PHP Repository ---
    log_step "Adding PHP Ondrej repository..."
    add-apt-repository -y ppa:ondrej/php
    handle_error $? true "Adding PHP Ondrej repository"

    # --- Step 3: Install Nginx Web Server ---
    log_step "Installing Nginx Web Server..."
    apt-get update -y && apt-get install -y nginx
    handle_error $? true "Installing Nginx"

    # --- Step 4: Install PHP-FPM Versions (8.1, 8.2, 8.3, 8.4) ---
    log_step "Installing PHP-FPM Versions and extension modules..."
    for version in 8.1 8.2 8.3 8.4; do
        log_step "Installing PHP-FPM ${version} modules..."
        apt-get install -y php${version}-fpm php${version}-mysql php${version}-common \
        php${version}-curl php${version}-gd php${version}-imap \
        php${version}-opcache php${version}-redis php${version}-sqlite3 \
        php${version}-mbstring php${version}-xml php${version}-zip
        handle_error $? false "PHP-FPM ${version} installation"
    done

    # Create global symlinks
    ln -sf /usr/bin/php8.3 /usr/bin/php
    handle_error $? false "Creating default PHP symlink"

    # --- Step 5: Install MySQL Server ---
    log_step "Installing MySQL Database Server..."
    apt-get install -y mysql-server
    handle_error $? true "MySQL Installation"

    # --- Step 6: Install Node.js & Composer ---
    if ! command -v node &> /dev/null; then
        log_step "Installing Node.js & npm..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
        handle_error $? true "Installing Node.js"
    else
        log_step "Node.js is already installed, skipping..."
    fi

    if ! command -v composer &> /dev/null; then
        log_step "Installing Composer..."
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
        if [ $? -ne 0 ]; then
            log_step "Installer failed, attempting apt-get fallback for Composer..."
            apt-get install -y composer
            handle_error $? true "Installing Composer via APT"
        fi
    else
        log_step "Composer is already installed, skipping..."
    fi

    # --- Step 7: Create Isolated Directory Boundaries ---
    log_step "Setting up webusers directories..."
    groupadd -f webusers
    mkdir -p /home/hosting/webusers
    chown -R nobody:nogroup /home/hosting/webusers
    chmod 755 /home/hosting/webusers

    mkdir -p /home/hosting/backups
    chown -R www-data:www-data /home/hosting/backups
    chmod 755 /home/hosting/backups
fi

# --- Step 8: Deploy & Bootstrap Control Panel Application ---
PANEL_DIR="/var/www/panel"
DOWNLOAD_URL="https://wa.aizenty.com/downloads/panel.zip"

if [ "$FAST_UPDATE" = "true" ]; then
    log_step "Updating panel codebase..."
    mkdir -p /tmp/panel_update
    wget -q --no-check-certificate ${DOWNLOAD_URL} -O /tmp/panel_update/panel.zip
    handle_error $? true "Downloading panel package"
    unzip -o /tmp/panel_update/panel.zip -d ${PANEL_DIR}
    handle_error $? true "Extracting panel package"
    rm -rf /tmp/panel_update
    cd ${PANEL_DIR}
else
    log_step "Downloading panel codebase..."
    rm -rf ${PANEL_DIR}
    mkdir -p ${PANEL_DIR}
    wget -q --no-check-certificate ${DOWNLOAD_URL} -O /tmp/panel.zip
    handle_error $? true "Downloading panel package"
    unzip -o /tmp/panel.zip -d ${PANEL_DIR}
    handle_error $? true "Extracting panel package"
    rm -f /tmp/panel.zip
    cd ${PANEL_DIR}
fi

# Ensure certbot is installed (runs on both fresh install and fast updates)
if ! command -v certbot &> /dev/null; then
    log_step "Certbot not found. Installing certbot and Nginx certbot module..."
    apt-get update -y && apt-get install -y certbot python3-certbot-nginx
fi

# Ensure PHP extensions required for Composer are installed
CLI_PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
log_step "Ensuring PHP CLI extensions for PHP ${CLI_PHP_VERSION} are installed..."
apt-get update -y && apt-get install -y php${CLI_PHP_VERSION}-xml php${CLI_PHP_VERSION}-mbstring php${CLI_PHP_VERSION}-zip php${CLI_PHP_VERSION}-curl php${CLI_PHP_VERSION}-mysql php${CLI_PHP_VERSION}-gd php${CLI_PHP_VERSION}-fpm
handle_error $? false "Installing PHP CLI extensions"

# Install PHP dependencies
log_step "Installing backend dependencies (this may take a few minutes)..."
rm -f bootstrap/cache/config.php bootstrap/cache/routes.php bootstrap/cache/services.php bootstrap/cache/packages.php
composer install --no-dev -o --no-interaction
handle_error $? true "Backend dependency installation"

if [ "$FAST_UPDATE" = "false" ]; then
    # Setup configuration
    log_step "Configuring environment configuration..."
    if [ ! -f .env ]; then
        cp .env.example .env
    fi

    # Generate MySQL Credentials for Panel
    PANEL_DB_NAME="panel_db"
    PANEL_DB_USER="panel_user"
    PANEL_DB_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9')

    log_step "Starting and enabling MySQL database service..."
    systemctl start mysql
    systemctl enable mysql

    log_step "Creating MySQL Database and User for Panel..."
    mysql -e "CREATE DATABASE IF NOT EXISTS ${PANEL_DB_NAME};"
    mysql -e "DROP USER IF EXISTS '${PANEL_DB_USER}'@'localhost';"
    mysql -e "CREATE USER '${PANEL_DB_USER}'@'localhost' IDENTIFIED BY '${PANEL_DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${PANEL_DB_NAME}.* TO '${PANEL_DB_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    # Update .env configuration
    update_env_key "DB_CONNECTION" "mysql"
    update_env_key "DB_HOST" "localhost"
    update_env_key "DB_PORT" "3306"
    update_env_key "DB_DATABASE" "${PANEL_DB_NAME}"
    update_env_key "DB_USERNAME" "${PANEL_DB_USER}"
    update_env_key "DB_PASSWORD" "${PANEL_DB_PASS}"
fi

# Set up storage and bootstrap permissions (Run always to fix any permission issues)
chown -R www-data:www-data storage
chmod -R 775 storage
chmod -R 775 bootstrap/cache
chown -R www-data:www-data database
chmod -R 775 database

if [ "$FAST_UPDATE" = "false" ]; then
    # Generate Application Keys
    php artisan key:generate --ansi --force --quiet >/dev/null
fi

# Clear any cached configuration to prevent stale credentials
php artisan config:clear --quiet >/dev/null
php artisan cache:clear --quiet >/dev/null

# Run migrations (Safe to run always)
php artisan migrate --force --quiet >/dev/null

if [ "$FAST_UPDATE" = "false" ]; then
    # --- Step 8b: Install and Configure phpMyAdmin Securely ---
    PMA_VERSION="5.2.1"
    PMA_DIR="${PANEL_DIR}/public/phpmyadmin"

    if [ -d "${PMA_DIR}" ] && [ -f "${PMA_DIR}/config.inc.php" ]; then
        log_step "phpMyAdmin is already installed, skipping..."
    else
        log_step "Installing and configuring phpMyAdmin..."
        wget -q https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz -O /tmp/phpmyadmin.tar.gz
        handle_error $? false "Downloading phpMyAdmin"

        if [ -f /tmp/phpmyadmin.tar.gz ]; then
            mkdir -p ${PMA_DIR}
            tar -xzf /tmp/phpmyadmin.tar.gz -C ${PMA_DIR} --strip-components=1
            rm -f /tmp/phpmyadmin.tar.gz

            # Generate a random blowfish secret key
            BLOWFISH_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
            cp ${PMA_DIR}/config.sample.inc.php ${PMA_DIR}/config.inc.php
            sed -i "s/\$cfg\['blowfish_secret'\] = '';/\$cfg\['blowfish_secret'\] = '${BLOWFISH_SECRET}';/g" ${PMA_DIR}/config.inc.php
            
            # Use Single Sign-On (SSO) signon auth method
            sed -i "s/\$cfg\['Servers'\]\[\$i\]\['auth_type'\] = 'cookie';/\$cfg\['Servers'\]\[\$i\]\['auth_type'\] = 'signon';\n\$cfg\['Servers'\]\[\$i\]\['SignonSession'\] = 'PmaSignonSession';\n\$cfg\['Servers'\]\[\$i\]\['SignonURL'\] = 'signon.php';\n\$cfg\['CookieSecure'\] = false;/g" ${PMA_DIR}/config.inc.php

            # Set proper secure permissions
            chown -R www-data:www-data ${PMA_DIR}
            chmod -R 755 ${PMA_DIR}
            log_step "phpMyAdmin installed successfully at ${PMA_DIR}"
        else
            echo "WARNING: Could not download phpMyAdmin. Skipping phpMyAdmin setup."
        fi
    fi

    # Prompt for Admin Credentials from TTY
    echo -e "\n=== Set Control Panel Admin Credentials ==="
    read -p "Enter Admin Email: " ADMIN_EMAIL < /dev/tty
    read -s -p "Enter Admin Password: " ADMIN_PASSWORD < /dev/tty
    echo -e "\n=========================================="

    php artisan panel:create-admin --email="$ADMIN_EMAIL" --password="$ADMIN_PASSWORD"
fi

# --- Step 9: Configure Sudoers Privilege Escalation ---
log_step "Configuring passwordless sudo rules..."
SUDOERS_FILE="/etc/sudoers.d/panel-commands"
cat << 'EOF' > ${SUDOERS_FILE}
www-data ALL=(ALL) NOPASSWD: /usr/local/lsws/bin/lswsctrl *
www-data ALL=(ALL) NOPASSWD: /usr/sbin/service mysql reload
www-data ALL=(ALL) NOPASSWD: /usr/sbin/service mysql restart
www-data ALL=(ALL) NOPASSWD: /usr/sbin/service cron restart
www-data ALL=(ALL) NOPASSWD: /usr/bin/certbot
www-data ALL=(ALL) NOPASSWD: /usr/sbin/useradd *
www-data ALL=(ALL) NOPASSWD: /usr/sbin/userdel *
www-data ALL=(ALL) NOPASSWD: /usr/sbin/usermod *
www-data ALL=(ALL) NOPASSWD: /usr/bin/crontab *
www-data ALL=(ALL) NOPASSWD: /usr/sbin/ufw *
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl *
www-data ALL=(ALL) NOPASSWD: /usr/bin/ln *
www-data ALL=(ALL) NOPASSWD: /usr/bin/mv *
www-data ALL=(ALL) NOPASSWD: /usr/bin/rm *
www-data ALL=(ALL) NOPASSWD: /usr/bin/mkdir *
www-data ALL=(ALL) NOPASSWD: /usr/bin/chown *
www-data ALL=(ALL) NOPASSWD: /usr/bin/chmod *
www-data ALL=(ALL) NOPASSWD: /usr/sbin/chpasswd *
www-data ALL=(ALL) NOPASSWD: /usr/sbin/chpasswd
www-data ALL=(ALL) NOPASSWD: /usr/bin/mysql *
www-data ALL=(ALL) NOPASSWD: /usr/bin/mysql
www-data ALL=(ALL) NOPASSWD: /usr/bin/mysqldump *
www-data ALL=(ALL) NOPASSWD: /usr/bin/mysqldump
EOF
chmod 0440 ${SUDOERS_FILE}

# --- Step 10: Setup Systemd Panel Daemon ---
log_step "Configuring autostart Systemd service for Panel..."
SERVICE_FILE="/etc/systemd/system/panel.service"
cat << EOF > ${SERVICE_FILE}
[Unit]
Description=Cloud Connect by Aizenty Control Panel Daemon
After=network.target mysql.service nginx.service

[Service]
User=www-data
WorkingDirectory=${PANEL_DIR}
ExecStart=/usr/bin/php artisan serve --host=0.0.0.0 --port=8099
Restart=always
RestartSec=5
StandardOutput=append:/var/log/panel-service.log
StandardError=append:/var/log/panel-service.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable panel.service
systemctl restart panel.service
handle_error $? true "Restarting panel daemon service"

# --- Step 11: Configure System Firewall & Fail2Ban Jails ---
log_step "Configuring system firewalls..."

# Dynamically detect active SSH port to prevent lockouts
SSH_PORT=$(grep -i '^port' /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
if [ -z "$SSH_PORT" ]; then
    SSH_PORT="22"
fi

ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp  # Active SSH Port
ufw allow 80/tcp           # HTTP
ufw allow 443/tcp          # HTTPS
ufw allow 8099/tcp         # Control Panel / phpMyAdmin Port
ufw allow 7080/tcp         # LiteSpeed WebAdmin Console Port
ufw --force enable
handle_error $? false "Firewall enablement"

log_step "Configuring Fail2Ban SSH Brute-Force Jails..."
cat << EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 10m
bantime = 1h
action = ufw
EOF

systemctl enable fail2ban
systemctl restart fail2ban
handle_error $? false "Fail2Ban configuration"

# Start and enable all core hosting services on boot
log_step "Enabling and restarting core system services..."
systemctl enable nginx
systemctl restart nginx
if systemctl list-unit-files --type=service | grep -q "lsws.service"; then
    systemctl enable lsws
    systemctl restart lsws
fi
if systemctl list-unit-files --type=service | grep -q "litespeed.service"; then
    systemctl enable litespeed
    systemctl restart litespeed
fi
for version in 8.1 8.2 8.3 8.4; do
    if systemctl list-unit-files --type=service | grep -q "php${version}-fpm.service"; then
        systemctl enable php${version}-fpm
        systemctl restart php${version}-fpm
    else
        echo "PHP ${version} is not installed, skipping..."
    fi
done
systemctl enable mysql
systemctl restart mysql
systemctl enable redis-server
systemctl restart redis-server
systemctl enable cron
systemctl restart cron

# Configure scheduler cron job for panel background tasks
log_step "Configuring background task scheduler cron job..."
(crontab -u www-data -l 2>/dev/null; echo "* * * * * cd ${PANEL_DIR} && /usr/bin/php artisan schedule:run >> /dev/null 2>&1") | crontab -u www-data -
handle_error $? false "Task scheduler cron setup"

log_step "=========================================================="
log_step " Installation completed successfully! "
log_step "=========================================================="

# Final check of file and folder permissions to prevent 500 errors
log_step "Applying final secure folder permissions..."
groupadd -f webusers
usermod -a -G webusers www-data
chown -R :webusers /home/hosting/webusers 2>/dev/null || true
chmod -R 770 /home/hosting/webusers 2>/dev/null || true
find /home/hosting/webusers -type d -name ".ssh" -exec chmod 700 {} + 2>/dev/null || true
find /home/hosting/webusers -type f -name "authorized_keys" -exec chmod 600 {} + 2>/dev/null || true
chown -R www-data:www-data ${PANEL_DIR}
chmod -R 775 ${PANEL_DIR}/storage
chmod -R 775 ${PANEL_DIR}/bootstrap/cache
chmod -R 775 ${PANEL_DIR}/database
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="your_server_ip"
fi

echo "Access your panel: http://${SERVER_IP}:8099"
if [ -n "$ADMIN_EMAIL" ]; then
    echo "Administrator Credentials:"
    echo "Email: $ADMIN_EMAIL"
    echo "Password: $ADMIN_PASSWORD"
fi
echo "Verify logs: cat ${LOG_FILE}"
