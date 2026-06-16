# Cloud Connect by Aizenty (Nginx & PM2 Edition)

A high-performance, lightweight, and modern web hosting control panel built on Laravel, React, InertiaJS, and Nginx. Optimized specifically for Ubuntu 22.04 LTS and Ubuntu 24.04 LTS servers.

---

## 🚀 Key Features & Automation Engine

* **Nginx Reverse Proxy & PM2 Integration**: Lightning-fast static routing, integrated out of the box with Node.js/Python process management. Enabling Node/Python automatically configures Nginx to reverse proxy HTTP/HTTPS traffic to internal dynamic application ports.
* **Isolated Environment Boundaries**: Every website is placed inside its own Linux system user account under `/home/hosting/webusers/{username}` with security jails (restricted rbash locks) and isolated SFTP/SSH directory boundaries.
* **Multi-PHP Pools Engine**: Run PHP websites isolated on distinct PHP-FPM versions (PHP 8.1, 8.2, 8.3, or 8.4) with individual socket pools. Idle workers automatically exit after 10 seconds (`pm = ondemand`) to save system memory.
* **Databases Manager**: Instantly provision isolated MySQL databases and database users with auto-generated secure passwords.
* **Integrated Secure phpMyAdmin**: Automatic download, secure configuration with custom Blowfish Secret keys, and isolated database access out of the box via `/phpmyadmin` on the control panel port.
* **File Manager**: Comprehensive web-based file manager (CRUD, upload/download files, create folders, Zip/Unzip archives) within security borders.
* **Let's Encrypt SSL Integration**: Request and install free SSL certificates for domains with one click.
* **Service Daemon Management**: Track and start/stop/restart core system services (Nginx, MySQL, Cron, Redis, Postfix, Dovecot, Fail2ban, etc.).
* **Integrated Mail Server**: Full setup of Postfix and Dovecot for hosting secure email boxes with IMAP/SMTP SSL fallbacks.
* **Security & Firewall (UFW)**: Full firewall setup with automated dynamic active SSH port detection to prevent administrator lockouts.
* **Modern Premium UI/UX**: White/Slate minimal clean responsive dashboard using React + InertiaJS.

---

## 📂 Web Site Types Support (Fully Managed)

| Site Type | Description | Key Features |
| :--- | :--- | :--- |
| **PHP App** | Dynamic PHP application environment. | Isolated PHP-FPM socket pools, custom php.ini options configuration, PHP extensions updater, FastCGI Caching options. |
| **Node.js App** | Dynamic server daemon applications (Express, Nest, Next, Fastify, etc.) | Dynamic port auto-allocation (3000-9999), default template deployment (`app.js`), automatic PM2 process runner hookup (`www-data` context), real-time stdout/stderr console logs page. |
| **Python App** | Python WSGI/ASGI apps (Django, Flask, FastAPI) | Gunicorn runner, pip requirements installer, Virtualenv configuration. |
| **Static App** | Static websites (HTML, CSS, compiled JS, React/Vue bundles) | Straightforward Nginx server block routing, direct directory loading, Fast static response times. |

---

## ⚙️ Automated Server Installation

To deploy the control panel on a fresh, clean Ubuntu LTS (22.04 / 24.04) server, run the automated installation script as root:

```bash
curl -skSL -o install https://raw.githubusercontent.com/blankskydevelopers/cloud-connect-hpanel/main/install && chmod +x install && sudo ./install
```

### What the installer does:
1. Installs Nginx Web Server, MySQL Server, Redis, and Fail2ban.
2. Installs PHP-FPM (8.1, 8.2, 8.3, 8.4) and installs **Composer**.
3. Installs **Node.js & npm** and globally configures **PM2** with execution access rights.
4. Downloads, installs, and configures **phpMyAdmin** securely under the panel's public web root.
5. Deploys control panel codebase and builds React production frontend bundles (`npm run build`).
6. Configures secure sudoers privilege escalation rules for system tasks.
7. Sets up Postfix & Dovecot mail servers and enables Laravel Reverb websockets support.
8. Auto-detects the active SSH port dynamically and enables the UFW Firewall.
9. Prompts the administrator for default login credentials.

---

## 🖥️ Ports and Access Points

After the installer completes, access the control panel at:

* **Control Panel URL**: `http://<your-server-ip>:8099`
* **phpMyAdmin Web Access**: `http://<your-server-ip>:8099/phpmyadmin`
  *(Log in using database credentials created via the panel UI)*

---

## 🧪 Local Testing & Simulation Mode

For developmental testing on non-Linux (e.g. Windows/macOS) host environments, the backend automatically activates **Simulation Mode**.

Linux shell commands (e.g. `systemctl`, `ufw`, `mysql`, `useradd`, `certbot`, `pm2`) are simulated locally:
* Database records are created and deleted as normal.
* Shell executions are logged in local system outputs for testing.
* Frontend layout and API routes can be fully debugged without a virtual machine.

### Run Development Server:
1. Clone the codebase and copy `.env.example` to `.env`
2. Install dependencies:
   ```bash
   composer install
   npm install
   ```
3. Run the migrations:
   ```bash
   php artisan migrate
   ```
4. Start both development servers:
   ```bash
   # Run Laravel Backend
   php artisan serve --port=8001
   
   # Run Vite Frontend Watcher
   npm run dev
   ```

---

## 🛡️ License
Open-sourced software licensed under the [MIT license](LICENSE).
