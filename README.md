# 🌟 Automated N8N Deployment with FFmpeg, yt-dlp, Puppeteer, and Auto-SSL! 🚀

Tired of manual N8N installations? This script is your friendly helper to get N8N up and running on your VPS/server in a flash! It handles everything from Docker setup, custom N8N image building (with FFmpeg, yt-dlp, and Puppeteer), to automatic SSL with Caddy, plus daily backups and auto-updates. ✨

---

## 🤩 What This Script Does For You!

Think of this script as your personal DevOps buddy. It automates:

*   **⚡️ N8N Installation (via Docker):** Gets the core N8N platform running in a containerized environment.
*   **🛠️ Custom N8N Docker Image:** Builds a special N8N image pre-loaded with:
    *   `FFmpeg`: For all your video/audio processing needs.
    *   `yt-dlp`: The super handy tool for downloading videos (perfect for YouTube!).
    *   `Puppeteer` (`n8n-nodes-puppeteer` included): For powerful web scraping and browser automation.
*   **🔒 Automatic SSL/TLS:** Sets up Caddy as a reverse proxy, automatically securing your N8N instance with a free SSL certificate from Let's Encrypt (highly recommended!) or an internal one for testing.
*   **🧠 Smart Swap Memory Setup:** Checks your server's RAM and automatically configures swap space if needed, ensuring smoother performance for N8N.
*   **💾 Daily Automatic Workflow & Credentials Backup:** Protects your hard work by backing up all your N8N workflows, credentials, and database files daily.
*   **🔄 Auto-Update Mechanism:** Keeps your N8N instance and `yt-dlp` (both on host and in container) up-to-date automatically, without you lifting a finger!
*   **Persistent Data Storage:** Your N8N data (workflows, credentials, files) is safely stored on your host machine, even if containers are recreated.
*   **🗣️ User-Friendly & Interactive:** Guides you through the process with clear questions and helpful messages.
*   **🛡️ Idempotent:** You can safely run this script multiple times! It's smart enough to detect what's already installed/configured and will just update or skip.

---

## 🚀 Getting Started (It's Super Easy!)

Before we begin, make sure your server meets a few basic requirements:

### ✨ Prerequisites

*   **A Fresh VPS/Server:** Running a Debian or Ubuntu-based operating system (e.g., Ubuntu 20.04+, Debian 10+).
*   **Root or Sudo Access:** You'll need to run the script with `sudo` privileges.
*   **Active Domain/Subdomain:** Your chosen domain (e.g., `n8n.yourdomain.com`) must be pointed to your server's public IP address via an `A` record in your DNS settings. The script will double-check this for you!
*   **Open Ports:** Ensure ports **80 (HTTP)** and **443 (HTTPS)** are open on your server's firewall. Caddy needs these for SSL and web traffic.
    *   *Example for UFW firewall:*
        ```bash
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw enable # If UFW isn't active yet
        ```
*   **Internet Connection:** Your VPS needs to be connected to the internet to download packages.

### 🏃‍♂️ Installation Steps

Ready to get your N8N superpower? Follow these simple steps:

1.  **Connect to Your VPS:** Open your terminal and SSH into your server.
    ```bash
    ssh your_user@your_server_ip
    ```

2.  **Clone the Repository:** Grab the script from GitHub.
    ```bash
    git clone https://github.com/satriyabajuhitam/auto-n8n-complete.git
    ```

3.  **Navigate to the Script Directory:**
    ```bash
    cd auto-n8n-complete
    ```

4.  **Give the Script Permission to Run:**
    ```bash
    chmod +x complete-deploy-n8n.sh
    ```

5.  **Run the Script!** This is the exciting part!
    ```bash
    sudo ./complete-deploy-n8n.sh
    ```
    *   The script will start chatting with you!
    *   It will ask you for your **domain or subdomain** (e.g., `n8n.example.com`). Type it in and hit Enter. The script will verify if it's pointing correctly.
    *   It will then ask if you want to use **Let's Encrypt for SSL**.
        *   **Highly Recommended (`y`):** Say `y` and provide your email address. Caddy will automatically handle getting and renewing your trusted SSL certificate.
        *   **For Testing (`n`):** If you say `n`, it will use an internal SSL certificate, and your browser will show a privacy warning. This is fine for testing but not for public access.

6.  **Sit Back and Relax:** The script will take care of the rest! It will install Docker, build your custom N8N image, set up Caddy, configure backups, and get everything running. This process might take a few minutes, so maybe grab a coffee! ☕

---

## 🎉 Post-Installation Goodies!

Once the script finishes, you'll see a success message. Here's what you need to know:

*   **Access N8N:** You can now open your web browser and visit:
    👉 **`https://YOUR.DOMAIN`** (replace `YOUR.DOMAIN` with the domain you entered)

*   **N8N's Home:** All your N8N configuration, database, and custom files are stored safely in:
    `$N8N_DIR` (default: `/home/n8n`)

*   **Auto-Update:** Your N8N instance will check for updates and update itself every 12 hours.
    *   Update Log: `$N8N_DIR/update.log`

*   **Backups:** Daily backups of your workflows and credentials run automatically at **2 AM** server time.
    *   Backup Files: `$N8N_DIR/files/backup_full/n8n_backup_YYYYMMDD_HHMMSS.tar.gz`
    *   The script keeps the 30 most recent backups.
    *   Backup Log: `$N8N_DIR/files/backup_full/backup.log`

*   **YouTube Data:** Any videos downloaded via `yt-dlp` through N8N will be saved in:
    `$N8N_DIR/files/youtube_data/`

*   **`yt-dlp` on Host:** If you want to use `yt-dlp` directly from your server's command line (outside of N8N), you might need to manually add `~/.local/bin` to your `PATH` environment variable after logging out and back in.

---

## 💡 Troubleshooting & Important Notes

*   **`Your connection is not private` / `ERR_CERT_AUTHORITY_INVALID`:** This happens if you chose `tls internal` for Caddy (or if Let's Encrypt failed).
    *   **Solution:** If you want a trusted SSL, re-run the script (`sudo ./complete-deploy-n8n.sh`), choose `y` for Let's Encrypt, and ensure your domain points correctly and ports 80/443 are open. Caddy will then attempt to get a proper certificate.
*   **"Error: Docker image build failed."**: If you encounter this, scroll up in your terminal output to find the specific error message from Docker or NPM. The script is designed to handle common issues, but unique server environments can sometimes throw curveballs.
*   **DNS Propagation Time:** After changing your domain's DNS records, it can take anywhere from a few minutes to a few hours (rarely 24-48 hours) for the changes to fully propagate across the internet. If the script's domain check fails, give it a little more time.
*   **Firewall:** Double-check your firewall settings if Caddy struggles to obtain a Let's Encrypt certificate. Ports 80 and 443 **must** be publicly accessible.
*   **Re-running the Script:** Don't worry if you need to run the script again (e.g., to change your SSL choice or after a previous error). It's idempotent and will safely update/reconfigure existing components without harming your N8N data.

---

## 🙏 Credits & Thanks

This script leverages the incredible work of many open-source projects and communities:

*   [N8N](https://n8n.io/)
*   [Docker](https://www.docker.com/) & [Docker Compose](https://docs.docker.com/compose/)
*   [Caddy](https://caddyserver.com/)
*   [Let's Encrypt](https://letsencrypt.org/)
*   [FFmpeg](https://ffmpeg.org/)
*   [yt-dlp](https://github.com/yt-dlp/yt-dlp)
*   [Puppeteer](https://pptr.dev/)

And to the entire open-source community for making these tools possible!

---

## 📄 License

This project is open-sourced under the MIT License. See the `LICENSE` file for more details.
