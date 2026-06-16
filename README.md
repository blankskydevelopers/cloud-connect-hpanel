# Cloud Connect by Aizenty

A fully secured, high-performance, lightweight, and modern production web hosting control panel. Engineered for maximum security and optimized specifically for Ubuntu 22.04 LTS and Ubuntu 24.04 LTS servers.

---

## 🚀 Key Features & Automation Engine

* **Fully Secured Auto Jail System**: Strict security boundaries are enforced. Every website runs under its own isolated system user account with security jails (rbash locks) and isolated SFTP/SSH directory boundaries automatically applied to ensure absolute tenant isolation.
* **Application Reverse Proxy & Process Manager**: Lightning-fast static routing, integrated out of the box with application process management. Enabling web application daemons automatically configures the web server to reverse proxy traffic to internal dynamic application ports.
* **One-Click Web App Installer**: Instantly deploy popular applications with single-click automated database setup and domain configuration.
* **Multi-Version Runtime Engine**: Run web applications isolated on distinct execution pools. Idle workers automatically exit after 10 seconds to save system memory.
* **Email Server Manager**: Full setup of secure, custom email boxes with domain-based SSL mapping and certificate fallbacks.
* **Databases Manager**: Instantly provision isolated databases and database users with auto-generated secure passwords.
* **Integrated Database Administration Portal**: Automatic download, secure configuration with custom Blowfish Secret keys, and isolated database access out of the box.
* **File Manager**: Comprehensive web-based file manager (CRUD, upload/download files, create folders, Zip/Unzip archives) with multi-selection support, keyboard shortcuts (`Ctrl + A`, `Delete`), and a built-in text editor.
* **Let's Encrypt SSL Integration**: Request and install free SSL certificates for domains, subdomains, and mail servers with one click.
* **Service Daemon Management**: Track, start, stop, and restart core system services from the UI.
* **Security & Firewall (UFW & Fail2ban)**: Full firewall setup with automated dynamic active SSH port detection to prevent administrator lockouts, coupled with intrusion prevention settings.
* **Modern Premium UI/UX**: White/Slate minimal clean responsive control dashboard.

---

## 📂 Web Site Types Support (Fully Managed)

| Site Type | Description | Key Features |
| :--- | :--- | :--- |
| **Dynamic Apps** | Support for dynamic server-side applications. | Isolated socket execution pools, custom configuration management, and runtimes setup. |
| **Server Daemon Apps** | Support for background process applications. | Dynamic port auto-allocation, templates deployment, automatic process runner hookup, and real-time console log viewer. |
| **Static Apps** | Static websites (HTML, CSS, compiled JS, React/Vue bundles) | Straightforward web routing, direct directory loading, and fast static response times. |

---

## ⚙️ Automated Production Installation

To deploy the control panel on a fresh, clean Ubuntu LTS (22.04 / 24.04) server, run the automated installation script as root:

```bash
curl -skSL -o install https://raw.githubusercontent.com/blankskydevelopers/cloud-connect-hpanel/main/install && chmod +x install && sudo ./install
```

### What the installer does:
1. Installs web server, database server, caching, and intrusion prevention daemons.
2. Configures isolated runtime versions.
3. Configures global process manager with secure execution access rights.
4. Sets up database administration tools securely under the panel's public web root.
5. Deploys control panel codebase and compiles production frontend assets.
6. Configures secure privilege escalation rules for system tasks.
7. Sets up secure mail servers and enables real-time websocket updates.
8. Auto-detects the active SSH port dynamically and enables the firewall.
9. Prompts the administrator for default login credentials.

---

## 🖥️ Ports and Access Points

After the installer completes, access the control panel at:

* **Control Panel URL**: `http://<your-server-ip>:8099`
* **Database Manager Access**: `http://<your-server-ip>:8099/phpmyadmin`
  *(Log in using database credentials created via the panel UI)*

---

## 🛡️ License
Open-sourced software licensed under the [MIT license](LICENSE).
