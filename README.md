# Cloud Connect by Aizenty (LiteSpeed Edition)

A high-performance, lightweight, and modern web hosting control panel built on Laravel, React, InertiaJS, and OpenLiteSpeed. Specifically optimized for Ubuntu 22.04 LTS and Ubuntu 24.04 LTS servers.

---

## 🚀 Key Features

* **OpenLiteSpeed Server Integration**: Lightning-fast caching and static file performance with dynamic PHP pool configuration.
* **Isolated Environment Boundaries**: Every website is placed inside its own Linux system user account under `/home/hosting/webusers/{username}` with security jails (restricted rbash locks).
* **Multi-PHP Pools Engine**: Run websites isolated on distinct LSPHP versions (PHP 8.1, 8.2, 8.3, or 8.4) with individual socket pools.
* **Databases Manager**: Instantly provision isolated MySQL databases and database users with auto-generated secure passwords.
* **Integrated secure phpMyAdmin**: Automatic download, secure configuration with custom Blowfish Secret keys, and isolated database access out of the box via `/phpmyadmin` on the control panel port.
* **File Manager**: Comprehensive web-based file manager (CRUD, upload/download files, create folders, Zip/Unzip archives) within security borders.
* **Let's Encrypt SSL Integration**: Request and install free SSL certificates for domains with one click.
* **Service Daemon Management**: Track and start/stop/restart core system services (Nginx/LiteSpeed, MySQL, Cron, etc.).
* **Security & Firewall (UFW)**: Full firewall setup with automated dynamic active SSH port detection to prevent administrator lockouts.
* **Modern Premium UI/UX**: White/Slate minimal clean responsive dashboard using React + InertiaJS.

---

## 🛠️ Tech Stack

* **Backend**: Laravel 11.x, PHP 8.3
* **Frontend**: React 18, Vite, Tailwind CSS, InertiaJS
* **Database**: SQLite (Panel internal settings), MySQL Server (Websites databases)
* **Web Server**: OpenLiteSpeed (LSPHP 8.1 - 8.4)

---

## ⚙️ Automated Server Installation

To deploy the control panel on a fresh, clean Ubuntu LTS (22.04 / 24.04) server, run the automated installation script as root:

```bash
sudo bash install.sh
```

### What the installer does:
1. Installs OpenLiteSpeed Web Server & LSPHP modules.
2. Installs MySQL Database Server.
3. Downloads, installs, and configures **phpMyAdmin** securely under the panel's public web root.
4. Downloads Node.js/npm and builds panel production frontend bundles.
5. Configures secure sudoers privilege escalation rules.
6. Sets up the Panel background systemd auto-start daemon (`panel.service`).
7. Auto-detects the active SSH port dynamically and enables the UFW Firewall.
8. Prompts the administrator for default login credentials.

---

## 🖥️ Ports and Access Points

After the installer completes, access the control panel at:

* **Control Panel URL**: `http://<your-server-ip>:8099`
* **phpMyAdmin Web Access**: `http://<your-server-ip>:8099/phpmyadmin`
  *(Log in using database credentials created via the panel UI)*

---

## 🧪 Local Testing & Simulation Mode

For developmental testing on non-Linux (e.g. Windows/macOS) host environments, the backend automatically activates **Simulation Mode**.

Linux shell commands (e.g. `systemctl`, `ufw`, `mysql`, `useradd`, `certbot`) are simulated locally:
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
