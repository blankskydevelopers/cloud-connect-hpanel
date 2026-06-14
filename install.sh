#!/bin/bash

# ==============================================================================
# Cloud Connect by Aizenty Automated Installer (LiteSpeed Edition)
# Target OS: Ubuntu 22.04 LTS / Ubuntu 24.04 LTS
# ==============================================================================

LOG_FILE="install.log"
exec > >(tee -a ${LOG_FILE} ) 2>&1

export DEBIAN_FRONTEND=noninteractive

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

# --- Auto-configure Swap Space (To prevent OOM crash on low-resource VMs/VPS) ---
SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
if [ -z "$SWAP_TOTAL" ] || [ "$SWAP_TOTAL" -eq 0 ]; then
    log_step "No swap space detected. Creating a 2GB swap file to prevent Out of Memory (OOM) errors..."
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log_step "Swap file created and enabled successfully."
else
    log_step "Swap space is already active: ${SWAP_TOTAL}MB. Skipping swap creation."
fi

if [ "$FAST_UPDATE" = "false" ]; then
    # --- Step 1: Update System & Install Core Utilities ---
    log_step "Updating system packages..."
    apt-get update -y && apt-get upgrade -y
    handle_error $? false "System package upgrade"

    apt-get install -y wget curl git software-properties-common unzip ufw sudo fail2ban redis-server certbot python3-certbot-nginx acl postfix dovecot-imapd dovecot-pop3d dovecot-sieve spamassassin spamc spamd opendkim opendkim-tools \
        clamav clamav-daemon rkhunter chkrootkit lynis
    handle_error $? true "Installing core utilities, intrusion prevention, Redis, Certbot, Email Server, and Security Scanner packages"

    # --- Step 2: Configure PHP Repository ---
    log_step "Adding PHP Ondrej repository..."
    add-apt-repository -y ppa:ondrej/php
    handle_error $? true "Adding PHP Ondrej repository"

    # --- Step 3: Install Nginx Web Server ---
    log_step "Installing Nginx Web Server..."
    apt-get update -y && apt-get install -y nginx
    handle_error $? true "Installing Nginx"

    # Remove the default 'Welcome to nginx' site — it intercepts all port 80 requests
    # and shows the nginx default page instead of our hosted websites.
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default
    log_step "Nginx default site removed."

    # --- Step 4: Install PHP-FPM Versions (8.1, 8.2, 8.3, 8.4) ---
    log_step "Installing PHP-FPM Versions and extension modules..."
    for version in 8.1 8.2 8.3 8.4; do
        log_step "Installing PHP-FPM ${version} modules..."
        apt-get install -y php${version}-fpm php${version}-mysql php${version}-common \
        php${version}-curl php${version}-gd php${version}-imap \
        php${version}-opcache php${version}-redis php${version}-sqlite3 \
        php${version}-mbstring php${version}-xml php${version}-zip
        handle_error $? false "PHP-FPM ${version} installation"

        # Disable the default 'www' pool — it uses pm=dynamic and keeps idle workers alive.
        # Our panel and website pools handle their own workers efficiently (pm=ondemand).
        if [ -f /etc/php/${version}/fpm/pool.d/www.conf ]; then
            mv /etc/php/${version}/fpm/pool.d/www.conf /etc/php/${version}/fpm/pool.d/www.conf.disabled
            log_step "PHP ${version} default www pool disabled (no idle workers)."
        fi
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
DOWNLOAD_URL="https://license.aizenty.com/downloads/panel.zip"

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

# Ensure email server packages are installed (runs on both fresh install and fast updates)
if ! dpkg -s postfix &>/dev/null || ! dpkg -s dovecot-imapd &>/dev/null || ! dpkg -s opendkim &>/dev/null || ! dpkg -s spamassassin &>/dev/null || ! dpkg -s spamd &>/dev/null; then
    log_step "Email server packages not found. Installing postfix, dovecot, spamassassin, spamd, and opendkim..."
    apt-get install -y postfix dovecot-imapd dovecot-pop3d dovecot-sieve spamassassin spamc spamd opendkim opendkim-tools
    handle_error $? false "Installing email server packages"
fi

# Ensure security scanner packages are installed (ClamAV, rkhunter, chkrootkit, lynis)
if ! dpkg -s clamav &>/dev/null || ! dpkg -s rkhunter &>/dev/null || ! dpkg -s chkrootkit &>/dev/null; then
    log_step "Security scanner packages not found. Installing ClamAV, rkhunter, chkrootkit, and lynis..."
    apt-get install -y clamav clamav-daemon rkhunter chkrootkit lynis
    handle_error $? false "Installing security scanner packages"
fi

# Update ClamAV virus definitions (non-blocking — runs in background)
if command -v freshclam &>/dev/null; then
    log_step "Updating ClamAV virus definitions in background..."
    # Stop clamav-freshclam service if running to avoid lock conflict
    systemctl stop clamav-freshclam 2>/dev/null || true
    freshclam --quiet &
    log_step "ClamAV definitions update started in background."
fi

# Enable ClamAV daemon
if systemctl list-unit-files --type=service | grep -q "clamav-daemon.service"; then
    systemctl enable clamav-daemon
    systemctl restart clamav-daemon 2>/dev/null || true
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

    # Detect server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="127.0.0.1"
    fi

    # Update .env configuration
    update_env_key "APP_URL" "http://${SERVER_IP}:8099"
    update_env_key "DB_CONNECTION" "mysql"
    update_env_key "DB_HOST" "localhost"
    update_env_key "DB_PORT" "3306"
    update_env_key "DB_DATABASE" "${PANEL_DB_NAME}"
    update_env_key "DB_USERNAME" "${PANEL_DB_USER}"
    update_env_key "DB_PASSWORD" "${PANEL_DB_PASS}"
fi

# Ensure storage and cache directories exist
mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/app/public bootstrap/cache

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
www-data ALL=(ALL) NOPASSWD: /usr/sbin/nginx *
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
www-data ALL=(ALL) NOPASSWD: /usr/bin/touch *
www-data ALL=(ALL) NOPASSWD: /usr/bin/setfacl *
www-data ALL=(ALL) NOPASSWD: /usr/sbin/postmap *
www-data ALL=(ALL) NOPASSWD: /usr/sbin/postconf *
www-data ALL=(ALL) NOPASSWD: /usr/bin/test *
www-data ALL=(ALL) NOPASSWD: /usr/bin/sed *
www-data ALL=(ALL) NOPASSWD: /usr/bin/sievec *
www-data ALL=(ALL) NOPASSWD: /usr/bin/opendkim-genkey *
EOF
chmod 0440 ${SUDOERS_FILE}

# --- Step 10: Setup Panel via Nginx + PHP-FPM (Production-grade, no php artisan serve) ---
log_step "Configuring panel Nginx virtual host on port 8099..."

# Detect current PHP CLI version for FPM
CLI_PHP=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

# Create PHP-FPM pool for panel
PANEL_POOL_FILE="/etc/php/${CLI_PHP}/fpm/pool.d/panel.conf"
cat << EOF > ${PANEL_POOL_FILE}
[panel]
user = www-data
group = www-data
listen = /run/php/php${CLI_PHP}-fpm-panel.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = ondemand
pm.max_children = 5
pm.process_idle_timeout = 10s
pm.max_requests = 500

php_admin_value[open_basedir] = ${PANEL_DIR}:/home/hosting/webusers:/tmp:/etc/postfix:/etc/dovecot:/etc/opendkim:/var/vmail:/var/log
php_admin_value[memory_limit] = 128M
EOF

# Reload PHP-FPM to register new pool
systemctl reload php${CLI_PHP}-fpm 2>/dev/null || systemctl restart php${CLI_PHP}-fpm

# Create Nginx virtual host for panel on port 8099
PANEL_NGINX_CONF="/etc/nginx/sites-available/panel"
cat << NGINXEOF > ${PANEL_NGINX_CONF}
server {
    listen 8099;
    server_name _;
    root ${PANEL_DIR}/public;
    index index.php;

    access_log /var/log/nginx/panel-access.log;
    error_log  /var/log/nginx/panel-error.log;

    client_max_body_size 50M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${CLI_PHP}-fpm-panel.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 120;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINXEOF

# Enable the panel nginx config
ln -sf ${PANEL_NGINX_CONF} /etc/nginx/sites-enabled/panel

# Test and reload Nginx
/usr/sbin/nginx -t && systemctl reload nginx
handle_error $? true "Panel Nginx configuration"

# Remove old php artisan serve systemd service if it exists
if [ -f /etc/systemd/system/panel.service ]; then
    systemctl stop panel.service 2>/dev/null || true
    systemctl disable panel.service 2>/dev/null || true
    rm -f /etc/systemd/system/panel.service
    systemctl daemon-reload
fi

log_step "Panel is now served via Nginx + PHP-FPM on port 8099 (production-grade)."

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
ufw allow 25/tcp            # SMTP (Incoming Mail)
ufw allow 143/tcp           # IMAP (Mail client access)
ufw allow 587/tcp           # SMTP Submission (Mail dispatching)
ufw allow 993/tcp           # IMAP SSL (Secure Mail client access)
ufw allow 465/tcp           # SMTP SSL (Secure Mail dispatching)
ufw allow 110/tcp           # POP3 (Mail retrieval)
ufw allow 995/tcp           # POP3 SSL (Secure Mail retrieval)
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
# Only enable the PHP-FPM version used by the panel (CLI version)
# Other versions are installed but NOT started by default to save RAM/CPU.
# They will be started automatically when a website using that version is created.
log_step "Enabling only the panel PHP-FPM version (${CLI_PHP})..."
for version in 8.1 8.2 8.3 8.4; do
    if systemctl list-unit-files --type=service | grep -q "php${version}-fpm.service"; then
        # Create systemd override to disable ProtectSystem and allow writing to nginx/php config directories
        mkdir -p /etc/systemd/system/php${version}-fpm.service.d/
        cat <<EOF > /etc/systemd/system/php${version}-fpm.service.d/override.conf
[Service]
ProtectSystem=false
ReadWritePaths=/etc/nginx /etc/php
EOF

        if [ "$version" = "${CLI_PHP}" ]; then
            # Enable and start only the panel's PHP version
            systemctl daemon-reload
            systemctl enable php${version}-fpm
            systemctl restart php${version}-fpm
            log_step "PHP ${version}-FPM started (panel version)."
        else
            # Install but keep stopped — started on-demand when a site needs it
            systemctl disable php${version}-fpm 2>/dev/null || true
            systemctl stop php${version}-fpm 2>/dev/null || true
            log_step "PHP ${version}-FPM installed but kept stopped (on-demand)."
        fi
    fi
done
systemctl enable mysql
systemctl restart mysql
systemctl enable redis-server
systemctl restart redis-server
systemctl enable cron
systemctl restart cron
systemctl enable postfix
systemctl restart postfix
systemctl enable dovecot
systemctl restart dovecot
    if [ -f /etc/default/spamassassin ]; then
        sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/spamassassin
    fi
    systemctl enable spamassassin
    systemctl restart spamassassin
systemctl enable opendkim
systemctl restart opendkim

# Configure scheduler cron job for panel background tasks
log_step "Configuring background task scheduler cron job..."
(crontab -u www-data -l 2>/dev/null | grep -v "schedule:run"; echo "* * * * * cd ${PANEL_DIR} && /usr/bin/php artisan schedule:run >> /dev/null 2>&1") | crontab -u www-data -
handle_error $? false "Task scheduler cron setup"

log_step "=========================================================="
log_step " Installation completed successfully! "
log_step "=========================================================="

# Final check of file and folder permissions to prevent 500 errors
log_step "Applying final secure folder permissions..."
groupadd -f webusers
usermod -a -G webusers www-data
chown -R :webusers /home/hosting/webusers 2>/dev/null || true
chmod 755 /home/hosting/webusers 2>/dev/null || true
find /home/hosting/webusers -mindepth 1 -maxdepth 1 -type d -exec chmod 770 {} + 2>/dev/null || true
find /home/hosting/webusers -type d -name ".ssh" -exec chmod 700 {} + 2>/dev/null || true
find /home/hosting/webusers -type f -name "authorized_keys" -exec chmod 600 {} + 2>/dev/null || true
chown -R www-data:www-data ${PANEL_DIR}
chmod -R 775 ${PANEL_DIR}/storage
chmod -R 775 ${PANEL_DIR}/bootstrap/cache
chmod -R 775 ${PANEL_DIR}/database

# Configure mail folders permissions (strictly owned by root/system users for Postfix/Dovecot security checks)
mkdir -p /etc/postfix /etc/dovecot /etc/opendkim /var/vmail
chown -R root:root /etc/postfix /etc/dovecot
chmod 755 /etc/postfix /etc/dovecot
find /etc/postfix /etc/dovecot -type f -exec chmod 644 {} +

if id "opendkim" &>/dev/null; then
    chown -R opendkim:opendkim /etc/opendkim
else
    chown -R root:root /etc/opendkim
fi
chmod 750 /etc/opendkim
if ! id "vmail" &>/dev/null; then
    groupadd -f vmail
    useradd -r -g vmail -d /var/vmail -s /sbin/nologin vmail
fi
mkdir -p /var/vmail
chown -R vmail:vmail /var/vmail
usermod -a -G vmail www-data
chmod 770 /var/vmail
if [ -x "$(command -v setfacl)" ]; then
    setfacl -R -m u:www-data:rwx /var/vmail 2>/dev/null || true
    setfacl -R -d -m u:www-data:rwx /var/vmail 2>/dev/null || true
fi

# Configure Postfix Virtual Mailbox settings out-of-the-box
if command -v postconf &>/dev/null; then
    log_step "Configuring Postfix virtual mailboxes, SASL auth, and TLS..."
    
    # Core mail routing
    postconf -e "virtual_mailbox_domains = hash:/etc/postfix/virtual_domains"
    postconf -e "virtual_mailbox_maps = hash:/etc/postfix/virtual_mailbox_maps"
    postconf -e "virtual_mailbox_base = /var/vmail"
    postconf -e "virtual_uid_maps = static:$(id -u vmail)"
    postconf -e "virtual_gid_maps = static:$(id -g vmail)"
    postconf -e "virtual_minimum_uid = 100"
    
    # SASL Authentication (Dovecot delegation)
    postconf -e "smtpd_sasl_type = dovecot"
    postconf -e "smtpd_sasl_path = private/auth"
    postconf -e "smtpd_sasl_auth_enable = yes"
    postconf -e "smtpd_recipient_restrictions = permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination"
    
    # TLS / SSL setup (default to snakeoil certificates so TLS connections don't error out-of-the-box)
    postconf -e "smtpd_use_tls = yes"
    postconf -e "smtpd_tls_security_level = may"
    postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem"
    postconf -e "smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key"
    
    # Touch mapping files if they don't exist so postmap doesn't fail
    touch /etc/postfix/virtual_domains /etc/postfix/virtual_mailbox_maps /etc/postfix/virtual_aliases /etc/postfix/sni_maps
    postconf -e "tls_server_sni_maps = hash:/etc/postfix/sni_maps"
    postmap /etc/postfix/virtual_domains 2>/dev/null || true
    postmap /etc/postfix/virtual_mailbox_maps 2>/dev/null || true
    postmap /etc/postfix/virtual_aliases 2>/dev/null || true
    postmap -F /etc/postfix/sni_maps 2>/dev/null || true
    
    # Enable SMTP Submission (587) and SMTPS (465) in master.cf
    # Clean any duplicate or commented submission/smtps lines first
    sed -i '/^\s*submission/d' /etc/postfix/master.cf
    sed -i '/^\s*smtps/d' /etc/postfix/master.cf
    
    # Append clean configurations to the end of master.cf
    cat << 'EOF' >> /etc/postfix/master.cf

submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_security_options=noanonymous
  -o smtpd_sasl_tls_security_options=noanonymous
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING

smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_security_options=noanonymous
  -o smtpd_sasl_tls_security_options=noanonymous
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
EOF

    systemctl restart postfix
fi

# Configure Dovecot for virtual mailboxes out-of-the-box
if [ -d /etc/dovecot ]; then
    log_step "Configuring Dovecot for virtual mailboxes, SSL, and SASL socket..."
    
    # Ensure ssl-cert utility package is installed (provides snakeoil certs)
    if ! dpkg -s ssl-cert &>/dev/null; then
        apt-get install -y ssl-cert
    fi
    
    # 1. Set mail_location to maildir in 10-mail.conf
    sed -i 's|^\s*#\?\s*mail_location\s*=.*|mail_location = maildir:/var/vmail/%d/%u|' /etc/dovecot/conf.d/10-mail.conf
    if ! grep -q "^mail_location" /etc/dovecot/conf.d/10-mail.conf; then
        echo "mail_location = maildir:/var/vmail/%d/%u" >> /etc/dovecot/conf.d/10-mail.conf
    fi
    
    # 2. Enable passwd-file auth in 10-auth.conf
    sed -i 's|^!include auth-system.conf.ext|#!include auth-system.conf.ext|' /etc/dovecot/conf.d/10-auth.conf
    sed -i 's|^#!include auth-passwdfile.conf.ext|!include auth-passwdfile.conf.ext|' /etc/dovecot/conf.d/10-auth.conf
    
    # Enable PLAIN and LOGIN mechanisms so SMTP clients can authenticate
    # (CRYPT-only scheme blocks SASL mechanism negotiation with Postfix)
    sed -i 's|^\s*#\?\s*auth_mechanisms\s*=.*|auth_mechanisms = plain login|' /etc/dovecot/conf.d/10-auth.conf
    if ! grep -q "^auth_mechanisms" /etc/dovecot/conf.d/10-auth.conf; then
        echo "auth_mechanisms = plain login" >> /etc/dovecot/conf.d/10-auth.conf
    fi
    
    # 3. Configure auth-passwdfile.conf.ext
    # Use SHA512-CRYPT scheme - compatible with PLAIN/LOGIN auth mechanisms
    cat << 'EOF' > /etc/dovecot/conf.d/auth-passwdfile.conf.ext
passdb {
  driver = passwd-file
  args = scheme=SHA512-CRYPT username_format=%u /etc/dovecot/users
}

userdb {
  driver = passwd-file
  args = username_format=%u /etc/dovecot/users
  default_fields = uid=vmail gid=vmail home=/var/vmail/%d/%u
}
EOF

    # 4. Configure SSL in 10-ssl.conf
    sed -i 's|^\s*#\?\s*ssl\s*=.*|ssl = yes|' /etc/dovecot/conf.d/10-ssl.conf
    sed -i 's|^\s*#\?\s*ssl_cert\s*=.*|ssl_cert = </etc/ssl/certs/ssl-cert-snakeoil.pem|' /etc/dovecot/conf.d/10-ssl.conf
    sed -i 's|^\s*#\?\s*ssl_key\s*=.*|ssl_key = </etc/ssl/private/ssl-cert-snakeoil.key|' /etc/dovecot/conf.d/10-ssl.conf

    # 5. Expose Dovecot SASL authentication socket to Postfix in 10-master.conf
    # Remove any existing unix_listener /var/spool/postfix/private/auth block or customize
    # We can safely append it as Dovecot will merge service settings
    cat << 'EOF' >> /etc/dovecot/conf.d/10-master.conf

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOF

    systemctl restart dovecot
fi

# Sync existing email configurations if panel is installed
if [ -f "artisan" ]; then
    log_step "Syncing existing mail domains and accounts..."
    php artisan tinker --execute="try { \$c = new \App\Http\Controllers\Api\EmailServerController(); \$r = new ReflectionMethod(\$c, 'syncPostfixDomains'); \$r->setAccessible(true); \$r->invoke(\$c); } catch (\Exception \$e) {}" 2>/dev/null || true
    php artisan tinker --execute="try { \$c = new \App\Http\Controllers\Api\EmailServerController(); \$r = new ReflectionMethod(\$c, 'syncMailboxConfigurations'); \$r->setAccessible(true); \$r->invoke(\$c); } catch (\Exception \$e) {}" 2>/dev/null || true
fi

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
