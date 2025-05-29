#!/bin/bash

# Hi there, future automation wizard! 👋
# Let's get your N8N up and running with all the cool stuff. ✨
echo "============================================================================"
echo "                    n8n, ffmpeg, yt-dlp, puppeteer & caddy                  "
echo "                          ~ by @satriyabajuhitam ~                          "
echo "============================================================================"

# First things first: Are you root?
if [[ $EUID -ne 0 ]]; then
   echo "Hold up! ✋ This script needs root powers (sudo). Make sure you're running it with 'sudo ./your-script-name.sh' to let me do my magic! 🧙‍♂️"
   exit 1
fi

# Function to give your server some breathing room (swap memory)
setup_swap() {
    echo ""
    echo "💨 Let's check your server's memory situation. We might need some extra 'breathing room' (swap space) to keep N8N running smoothly."
    
    # Check if swap is already enabled
    if [ "$(swapon --show | wc -l)" -gt 1 ]; then # wc -l will be >1 if header + swap lines exist
        SWAP_SIZE_HUMAN=$(free -h | grep Swap | awk '{print $2}')
        echo "✅ Good news! Swap is already enabled with size ${SWAP_SIZE_HUMAN}. No need to mess with it."
        return
    fi
    
    RAM_MB=$(free -m | grep Mem | awk '{print $2}')
    
    local SWAP_SIZE_MB # Declare as local
    if [ "$RAM_MB" -le 2048 ]; then
        SWAP_SIZE_MB=$((RAM_MB * 2)) # Double RAM if it's 2GB or less
    elif [ "$RAM_MB" -gt 2048 ] && [ "$RAM_MB" -le 8192 ]; then
        SWAP_SIZE_MB=$RAM_MB # Match RAM if it's between 2GB and 8GB
    else
        SWAP_SIZE_MB=4096 # Cap swap size at 4GB for larger RAM systems
    fi
    
    local SWAP_GB=$(( (SWAP_SIZE_MB + 1023) / 1024 ))
    
    echo "Setting up a ${SWAP_GB}GB (${SWAP_SIZE_MB}MB) swap file for you. This might take a moment... ⏳"
    
    # Using fallocate for speed, with dd as a fallback
    if command -v fallocate &> /dev/null; then
        if ! fallocate -l ${SWAP_SIZE_MB}M /swapfile; then
            echo "⚠️ Uh oh, fallocate hit a snag. No worries, trying 'dd' instead (might be a bit slower)..."
            if ! dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB status=progress; then
                echo "❌ Fatal: Couldn't create swap file with either method. Please check your disk space!"
                exit 1
            fi
        fi
    else
        echo "No fallocate? No problem! Using 'dd' to create the swap file (might be a bit slower)..."
        if ! dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB status=progress; then
            echo "❌ Fatal: Couldn't create swap file. Please check your disk space!"
            exit 1
        fi
    fi
    
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    
    # Adjusting swappiness and cache pressure for better performance
    sysctl vm.swappiness=10
    sysctl vm.vfs_cache_pressure=50
    
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=10" >> /etc/sysctl.conf
    fi
    
    if ! grep -q "vm.vfs_cache_pressure" /etc/sysctl.conf; then
        echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
    fi
    
    echo "🎉 Swap setup complete! Your server is ready for action with ${SWAP_GB}GB swap."
    echo "   Swappiness is set to 10 and vfs_cache_pressure to 50 for optimal performance. ⚙️"
}

# Psst! Need a little help? Here's how to use me:
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help      Display this friendly help message"
    echo "  -d, --dir DIR   Tell me where N8N's home should be (default: /home/n8n)"
    echo "  -s, --skip-docker Skip Docker installation (if you already have it, cool!)"
    exit 0
}

# Let's handle your commands, boss!
N8N_DIR="/home/n8n"
SKIP_DOCKER=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -d|--dir)
            N8N_DIR="$2"
            shift 2
            ;;
        -s|--skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        *)
            echo "❓ Hmm, that option '$1' looks a bit unfamiliar to me. Let me show you what I know:"
            show_help
            ;;
    esac
done

# Let's make sure your domain knows where your server lives! 🗺️
check_domain() {
    local domain=$1
    echo "Checking domain '$domain' for proper DNS configuration..."

    # Try to get the server's public IP using multiple methods
    local server_ip
    server_ip=$(curl -s --max-time 10 https://api.ipify.org || curl -s --max-time 10 https://ifconfig.me)
    if [ -z "$server_ip" ]; then
        echo "❌ Oops! I couldn't figure out your server's public IP address. Are you connected to the internet?"
        return 1
    fi
    echo "Server public IP: $server_ip"

    # Resolve the domain's IP using dig, with fallback to nslookup
    local domain_ip
    domain_ip=$(dig +short "$domain" A 2>/dev/null || nslookup "$domain" | grep -A1 'Name:' | grep 'Address' | awk '{print $2}' | head -n 1)
    if [ -z "$domain_ip" ]; then
        echo "❌ Failed to resolve the IP for '$domain'. Please check your DNS settings or ensure 'dnsutils' is installed."
        return 1
    fi
    echo "Domain '$domain' resolves to: $domain_ip"

    # Handle multiple IPs (e.g., CDN) by checking if server_ip is in domain_ip
    if echo "$domain_ip" | grep -q "$server_ip"; then
        echo "✅ Domain '$domain' correctly points to this server's IP ($server_ip)."
        return 0
    else
        echo "❌ Domain '$domain' does not point to this server's IP ($server_ip). Resolved IPs: $domain_ip"
        return 1
    fi
}

# Time to grab some essential tools! Think of them as my trusty sidekicks. 🛠️
install_base_dependencies() {
    echo ""
    echo "Updating the APT repository to use archive.ubuntu.com... 🔄"
    cp /etc/apt/sources.list /etc/apt/sources.list.bak
    sed -i 's|azure.archive.ubuntu.com/ubuntu|archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list
    echo "Updating package lists..."
    apt-get update -y > /dev/null
    if [ $? -ne 0 ]; then
        echo "❌ Failed to update package lists. Please check your internet connection or APT sources."
        exit 1
    fi
    echo "Installing essential tools... 🔧"
    apt-get install -y dnsutils curl cron jq tar gzip python3-full python3-venv pipx net-tools bc
    if [ $? -ne 0 ]; then
        echo "❌ Oh no! I hit a snag installing some basic packages. Please check your internet or APT sources."
        exit 1
    fi
    echo "✅ Essential tools are all set!"
}

# Setting up Docker, N8N's cozy container home! 📦
install_docker() {
    echo ""
    if $SKIP_DOCKER && command -v docker &> /dev/null; then
        echo "Docker is already installed and you asked me to skip it. Cool! 😎"
        return
    fi

    if command -v docker &> /dev/null; then
        echo "Looks like Docker is already chilling on your server. Great! 👍"
    else
        echo "Time to get Docker installed! This might take a little while. ⏳"
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
        if [ $? -ne 0 ]; then
            echo "❌ Docker installation failed! This is a big one. Check for error messages above and your network connection."
            exit 1
        fi
        echo "✅ Docker engine is ready!"
    fi

    # And now for Docker Compose, so N8N and Caddy can talk to each other! 🗣️
    if command -v docker-compose &> /dev/null || (command -v docker &> /dev/null && docker compose version &> /dev/null); then
        echo "Docker Compose (or its fancy new plugin) is already on board. Awesome! 🚀"
    else
        echo "Let's grab Docker Compose plugin... ⚙️"
        apt-get install -y docker-compose-plugin
        if ! (command -v docker &> /dev/null && docker compose version &> /dev/null); then
            echo "⚠️ Hmm, Docker Compose plugin didn't quite make it. Trying the older package as a fallback..."
            apt-get install -y docker-compose
        fi
        echo "✅ Docker Compose is good to go!"
    fi

    if ! command -v docker &> /dev/null; then
        echo "❌ Docker is still playing hide-and-seek. I can't find it installed properly."
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! (command -v docker &> /dev/null && docker compose version &> /dev/null); then
        echo "❌ Docker Compose is feeling shy too. It's not installed correctly."
        exit 1
    fi

    # Adding your user to the docker group so you don't always need 'sudo' for docker commands! 😉
    if [ "$SUDO_USER" != "" ]; then
        echo "Adding user '$SUDO_USER' to the 'docker' group... This is handy! (You'll need to log out and back in, or run 'newgrp docker' for it to take effect.) 🧑‍💻"
        usermod -aG docker "$SUDO_USER"
    fi
    systemctl enable docker
    systemctl restart docker
    echo "🎉 Docker and Docker Compose are installed and ready to rock!"
}

# Getting yt-dlp ready for all your media needs! 🎬
install_yt_dlp() {
    echo ""
    echo "Installing yt-dlp... It's like a magic wand for video handling! ✨"
    if command -v pipx &> /dev/null; then
        pipx install yt-dlp
        pipx ensurepath
        echo "✅ yt-dlp installed via pipx. Super clean!"
    else
        echo "pipx is being shy, so I'll install yt-dlp in a virtual environment. No problem! 🌳"
        python3 -m venv /opt/yt-dlp-venv
        /opt/yt-dlp-venv/bin/pip install -U pip yt-dlp
        ln -sf /opt/yt-dlp-venv/bin/yt-dlp /usr/local/bin/yt-dlp
        chmod +x /usr/local/bin/yt-dlp
        echo "✅ yt-dlp installed in a virtual environment. Symlinked for easy access!"
    fi
    export PATH="$PATH:/usr/local/bin:/opt/yt-dlp-venv/bin:$HOME/.local/bin"
}

# Making sure our little time-teller (cron) is awake and ready for action. ⏰
ensure_cron_running() {
    echo ""
    echo "Checking on the cron service to make sure it's alive and kicking... 💖"
    systemctl enable cron
    systemctl start cron
    if systemctl is-active --quiet cron; then
        echo "✅ Cron service is active and enabled. Perfect for our automated tasks!"
    else
        echo "⚠️ Hmm, cron service seems a bit sleepy. Automatic backups and updates might not work as expected."
    fi
}

# --- Let the main show begin! ---

# Step 1: Memory check!
setup_swap

# Step 2: Essential tools first!
install_base_dependencies

# Step 3: Docker for the win!
install_docker

# Step 4: yt-dlp magic!
install_yt_dlp

# Step 5: Cron's ready!
ensure_cron_running

# Step 6: What's your N8N's address? 🌐
echo ""
read -p "Alright, what's the domain or subdomain you want to use for N8N (e.g., n8n.example.com)? Tell me! 👇 " DOMAIN
while ! check_domain "$DOMAIN"; do
    SERVER_IP=$(hostname -I | awk '{print $1}' || curl -s --max-time 10 https://api.ipify.org)
    echo "❌ Uh oh! Looks like your domain, '$DOMAIN', isn't quite pointing to this server's IP address yet ($SERVER_IP)."
    echo "   Please update your DNS records to point '$DOMAIN' to '$SERVER_IP'."
    echo "   (You might need to wait a few minutes for DNS changes to spread across the internet.)"
    read -p "Hit Enter once you've updated DNS, or type a different domain here: " NEW_DOMAIN
    if [ -n "$NEW_DOMAIN" ]; then
        DOMAIN="$NEW_DOMAIN"
    fi
done
echo "✅ Awesome! '$DOMAIN' is pointing correctly. Let's roll!"

# Step 7: Building N8N's cozy home! 🏡
echo ""
echo "Creating the directory structure for N8N at '$N8N_DIR'... "
mkdir -p "$N8N_DIR"
mkdir -p "$N8N_DIR/files"
mkdir -p "$N8N_DIR/files/temp"
mkdir -p "$N8N_DIR/files/youtube_data"
mkdir -p "$N8N_DIR/files/backup_full"
echo "✅ Directories are all set!"

# Step 8: Crafting the Dockerfile (this tells Docker how to build your custom N8N environment) 👷
echo ""
echo "Whipping up the Dockerfile... "
cat << 'EOF_DOCKERFILE' > "$N8N_DIR/Dockerfile"
FROM n8nio/n8n:latest
USER root
# Install packages for FFmpeg, yt-dlp, and Puppeteer (Chromium)
RUN apk update && \
    apk add --no-cache ffmpeg wget zip unzip python3 py3-pip jq tar gzip \
    chromium nss freetype freetype-dev harfbuzz ca-certificates ttf-freefont \
    font-noto font-noto-cjk font-noto-emoji dbus udev
# Install yt-dlp inside the container
RUN pip3 install --break-system-packages -U yt-dlp && \
    chmod +x /usr/bin/yt-dlp

# FIX: Install n8n-nodes-puppeteer globally to avoid "unsupported protocol workspace:*" error
RUN npm install -g n8n-nodes-puppeteer

# Configure Puppeteer to use the installed Chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
# Create and set permissions for n8n data directories
RUN mkdir -p /files/youtube_data /files/backup_full /files/temp && \
    chown -R node:node /files
USER node
WORKDIR /home/node
EOF_DOCKERFILE
echo "✅ Dockerfile created!"

# Step 9: Spinning up the docker-compose.yml (this is like the blueprint for N8N and Caddy) 📝
echo ""
echo "Generating docker-compose.yml... "
cat << 'EOF_COMPOSE' > "$N8N_DIR/docker-compose.yml"
services:
  n8n:
    build:
      context: .
      dockerfile: Dockerfile
    image: n8n-custom-ffmpeg:latest
    restart: always
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_HOST=__N8N_HOST_PLACEHOLDER__
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://__N8N_HOST_PLACEHOLDER__
      - GENERIC_TIMEZONE=Asia/Jakarta
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
      - N8N_BINARY_DATA_STORAGE=/files
      - N8N_DEFAULT_BINARY_DATA_FILESYSTEM_DIRECTORY=/files
      - N8N_DEFAULT_BINARY_DATA_TEMP_DIRECTORY=/files/temp
      - NODE_FUNCTION_ALLOW_BUILTIN=child_process,path,fs,util,os
      - N8N_EXECUTIONS_DATA_MAX_SIZE=304857600 # 300MB
      - PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
      - PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
    volumes:
      - __N8N_DIR_PLACEHOLDER__:/home/node/.n8n  # Mount the entire N8N_DIR to /home/node/.n8n for n8n data
      - __N8N_DIR_PLACEHOLDER__/files:/files      # Mount the files directory to /files inside the container
    user: "node"
    cap_add:
      - SYS_ADMIN # Required for Puppeteer to run properly in some environments

  caddy:
    image: caddy:latest
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - __N8N_DIR_PLACEHOLDER__/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n

volumes:
  caddy_data:
  caddy_config:
EOF_COMPOSE

sed -i "s|__N8N_HOST_PLACEHOLDER__|${DOMAIN}|g" "$N8N_DIR/docker-compose.yml"
sed -i "s|__N8N_DIR_PLACEHOLDER__|${N8N_DIR}|g" "$N8N_DIR/docker-compose.yml"
echo "✅ docker-compose.yml is ready!"

# Step 10: Whipping up the Caddyfile (this handles all the web magic and SSL for your domain) 🔑
echo ""
echo "Now, for the really important part: Security! 🔒"
read -p "Do you want a shiny, publicly trusted SSL certificate (from Let's Encrypt, highly recommended for public access)? (y/n): " USE_LETSENCRYPT_SSL

CADDYFILE_TLS_CONFIG="tls internal" # Default to internal for safety
if [[ "$USE_LETSENCRYPT_SSL" =~ ^[Yy]$ ]]; then
    read -p "Great choice! Please enter your email address for Let's Encrypt (they use it for expiry notices): " LETSENCRYPT_EMAIL
    if [ -n "$LETSENCRYPT_EMAIL" ]; then
        CADDYFILE_TLS_CONFIG="tls ${LETSENCRYPT_EMAIL}"
        echo "Cool! Using Let's Encrypt with your email: ${LETSENCRYPT_EMAIL}."
        echo "⚠️ Important: Make sure ports 80 and 443 are open on your server's firewall for Let's Encrypt to work its magic! ✨"
    else
        echo "No email? No problem, but I'll have to use an internal TLS certificate. Browsers might give you a privacy warning, just so you know! 😉"
    fi
else
    echo "Okay, we'll stick to an internal TLS certificate. Expect a privacy warning in your browser, but N8N will still work. 😉"
fi

cat << 'EOF_CADDY' > "$N8N_DIR/Caddyfile"
__CADDY_DOMAIN_PLACEHOLDER__ {
    reverse_proxy n8n:5678
    __CADDY_TLS_CONFIG_PLACEHOLDER__
}
EOF_CADDY

sed -i "s|__CADDY_DOMAIN_PLACEHOLDER__|${DOMAIN}|g" "$N8N_DIR/Caddyfile"
sed -i "s|__CADDY_TLS_CONFIG_PLACEHOLDER__|${CADDYFILE_TLS_CONFIG}|g" "$N8N_DIR/Caddyfile"
echo "✅ Caddyfile is set up!"

# Step 11: Creating the backup script (safety first!) 💾
echo ""
echo "Creating a special script to back up your N8N workflows and credentials. Super important! 📂"
cat << 'EOF_BACKUP_SCRIPT' > "$N8N_DIR/backup-workflows.sh"
#!/bin/bash

# Configuration for N8N backup script
N8N_DIR_VALUE="__N8N_DIR_VALUE__"
BACKUP_BASE_DIR="${N8N_DIR_VALUE}/files/backup_full"
LOG_FILE="${BACKUP_BASE_DIR}/backup.log"
DOMAIN_NAME="__DOMAIN_NAME__" # Domain name for logging purposes

DATE="$(date +"%Y%m%d_%H%M%S")"
BACKUP_FILE_NAME="n8n_backup_${DATE}.tar.gz"
BACKUP_FILE_PATH="${BACKUP_BASE_DIR}/${BACKUP_FILE_NAME}"
TEMP_DIR_HOST="/tmp/n8n_backup_host_${DATE}"
TEMP_DIR_CONTAINER_BASE="/tmp/n8n_workflow_exports"

# Friendly logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

mkdir -p "${BACKUP_BASE_DIR}"
log "Starting N8N workflow and credentials backup for domain: ${DOMAIN_NAME}..."

# Find the N8N container ID (our little N8N home)
N8N_CONTAINER_NAME_PATTERN="n8n"
N8N_CONTAINER_ID="$(docker ps -q --filter "name=${N8N_CONTAINER_NAME_PATTERN}" --format '{{.ID}}' | head -n 1)"

if [ -z "${N8N_CONTAINER_ID}" ]; then
    log "Error: Couldn't find a running N8N container. Backup failed. 😞"
    exit 1
fi
log "Found N8N container ID: ${N8N_CONTAINER_ID}"

# Create temporary folders on the host and inside the container for our backup goodies
mkdir -p "${TEMP_DIR_HOST}/workflows"
mkdir -p "${TEMP_DIR_HOST}/credentials"

TEMP_DIR_CONTAINER_UNIQUE="${TEMP_DIR_CONTAINER_BASE}/export_${DATE}"
docker exec "${N8N_CONTAINER_ID}" mkdir -p "${TEMP_DIR_CONTAINER_UNIQUE}"

log "Exporting workflows into a temporary spot (${TEMP_DIR_CONTAINER_UNIQUE}) inside the container..."
WORKFLOWS_JSON="$(docker exec "${N8N_CONTAINER_ID}" n8n list:workflow --json 2>>"$LOG_FILE")"

if [ -z "${WORKFLOWS_JSON}" ] || [ "${WORKFLOWS_JSON}" == "[]" ]; then
    log "Warning: No workflows found to back up. Is your N8N brand new? 🤔"
else
    echo "${WORKFLOWS_JSON}" | jq -c '.[]' | while IFS= read -r workflow_data; do
        id="$(echo "${workflow_data}" | jq -r '.id')"
        name="$(echo "${workflow_data}" | jq -r '.name' | tr -dc '[:alnum:][:space:]_-' | tr '[:space:]' '_')"
        safe_name="$(echo "${name}" | sed 's/[^a-zA-Z0-9_-]/_/g' | cut -c1-100)"
        output_file_container="${TEMP_DIR_CONTAINER_UNIQUE}/${id}-${safe_name}.json"
        log "Exporting workflow: '${name}' (ID: ${id}) to container: ${output_file_container}"
        if docker exec "${N8N_CONTAINER_ID}" n8n export:workflow --id="${id}" --output="${output_file_container}" >>"$LOG_FILE" 2>&1; then
            log "Successfully exported workflow ID ${id}. 👍"
        else
            log "Error exporting workflow ID ${id}. Something went wrong. Check container logs for clues! 🕵️‍♀️"
        fi
    done

    log "Copying all those lovely workflows from the container to your host machine... 📤"
    if docker cp "${N8N_CONTAINER_ID}:${TEMP_DIR_CONTAINER_UNIQUE}/." "${TEMP_DIR_HOST}/workflows/"; then
        log "Workflows copied successfully! 🎉"
    else
        log "Error copying workflows from container to host. This is a bit of a bummer. 😞"
    fi
fi

# Backup database and encryption key from host (these are super important!)
DB_PATH_HOST="${N8N_DIR_VALUE}/database.sqlite"
KEY_PATH_HOST="${N8N_DIR_VALUE}/encryptionKey"

log "Backing up your database and encryption key from the host... 🔑"
if [ -f "${DB_PATH_HOST}" ]; then
    cp "${DB_PATH_HOST}" "${TEMP_DIR_HOST}/credentials/database.sqlite"
    log "Backed up database.sqlite. Phew! 😌"
else
    log "Warning: database.sqlite not found at ${DB_PATH_HOST}. Skipping its backup. Is N8N running for the first time? 🤔"
fi

if [ -f "${KEY_PATH_HOST}" ]; then
    cp "${KEY_PATH_HOST}" "${TEMP_DIR_HOST}/credentials/encryptionKey"
    log "Backed up encryptionKey. Super important! ✨"
else
    log "Warning: encryptionKey not found at ${KEY_PATH_HOST}. Skipping its backup. Hope you don't need it later! 😬"
fi

log "Creating the final compressed backup file: ${BACKUP_FILE_PATH}. This might take a moment... 📦"
if tar -czf "${BACKUP_FILE_PATH}" -C "${TEMP_DIR_HOST}" . ; then
    log "Woohoo! Backup file '${BACKUP_FILE_NAME}' created successfully! ✅"
else
    log "❌ Oh no! I couldn't create the backup file '${BACKUP_FILE_PATH}'. Disk space issues, maybe? 📉"
fi

log "Cleaning up those temporary directories... gotta keep things tidy! 🧹"
rm -rf "${TEMP_DIR_HOST}"
docker exec "${N8N_CONTAINER_ID}" rm -rf "${TEMP_DIR_CONTAINER_UNIQUE}"

log "Keeping only the 30 most recent backups in ${BACKUP_BASE_DIR}. No digital hoarding here! 😉"
find "${BACKUP_BASE_DIR}" -maxdepth 1 -name 'n8n_backup_*.tar.gz' -type f -printf '%T@ %p\n' | \
sort -nr | tail -n +31 | cut -d' ' -f2- | xargs -r rm -f

log "Backup process completed! Your N8N is safe and sound. 💖"

exit 0
EOF_BACKUP_SCRIPT

sed -i \
    -e "s|__N8N_DIR_VALUE__|${N8N_DIR}|g" \
    -e "s|__DOMAIN_NAME__|${DOMAIN}|g" \
    "$N8N_DIR/backup-workflows.sh"
chmod +x "$N8N_DIR/backup-workflows.sh"
echo "✅ Backup script created and ready to protect your data!"

# Step 12: Adjusting permissions (we want N8N to feel right at home!) 🤝
echo ""
echo "Adjusting folder permissions for N8N's home at '$N8N_DIR'... "
sudo chown -R 1000:1000 "$N8N_DIR" # User ID 1000 is typically 'node' inside n8n container
sudo chmod -R u+rwX,g+rX,o+rX "$N8N_DIR"
sudo chown -R 1000:1000 "$N8N_DIR/files"
sudo chmod -R u+rwX,g+rX,o+rX "$N8N_DIR/files"
echo "✅ Permissions looking good!"

# Step 13: Time to bring N8N to life! 🚀
echo ""
echo "Alright, moment of truth! Let's build and start N8N and Caddy. This might take a few moments as we build the custom image. Grab a coffee! ☕"
cd "$N8N_DIR"

# Figure out which docker-compose command to use
local DOCKER_COMPOSE_CMD
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo "❌ Uh oh, I can't find 'docker-compose' or its plugin. Something went wrong with Docker installation. Can't proceed. 😟"
    exit 1
fi

echo "Attempting to stop any existing N8N/Caddy containers for a super clean build/start... 🛑"
# Ignore errors if containers aren't running
$DOCKER_COMPOSE_CMD down > /dev/null 2>&1 || true

echo "Building your custom N8N Docker image. This is where the magic happens! ✨"
if ! $DOCKER_COMPOSE_CMD build; then
    echo "❌ Argh! Docker image build failed. Scroll up to see the error messages. You might need to fix something in the Dockerfile. 🐛"
    exit 1
fi
echo "✅ Docker image built successfully!"

echo "Starting N8N and Caddy containers now... fingers crossed! 🤞"
if ! $DOCKER_COMPOSE_CMD up -d; then
    echo "❌ Oh no! Container startup failed. Check their logs to see what went wrong: '$DOCKER_COMPOSE_CMD logs'. 😔"
    exit 1
fi
echo "✅ Containers are starting up!"

echo "Giving them a little moment to wake up (about 30 seconds)... ⏰"
sleep 30

# Checking if they're actually awake and happy
echo "Checking container status... 👀"
if $DOCKER_COMPOSE_CMD ps | grep -q "n8n.* Up"; then
    echo "🎉 N8N container is awake and running successfully! Looking good!"
else
    echo "⚠️ Hmm, N8N container seems to be having trouble. Check its logs: '$DOCKER_COMPOSE_CMD logs n8n' for clues. 😩"
fi
if $DOCKER_COMPOSE_CMD ps | grep -q "caddy.* Up"; then
    echo "🎉 Caddy container is also up and running! Your SSL should be working! 👍"
else
    echo "⚠️ Caddy container is acting up. Check its logs: '$DOCKER_COMPOSE_CMD logs caddy'. If you chose Let's Encrypt, double-check your DNS and firewall! 🧐"
fi

# Step 14: Creating the auto-update script (set it and forget it!) 🔄
echo ""
echo "Setting up an auto-update script. Your N8N will stay fresh and new automatically! 🆕"
cat << 'EOF_UPDATE_SCRIPT' > "$N8N_DIR/update-n8n.sh"
#!/bin/bash
N8N_DIR_VALUE="__N8N_DIR_VALUE__"
LOG_FILE="${N8N_DIR_VALUE}/update.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
log "Starting N8N update check..."
cd "${N8N_DIR_VALUE}"

local DOCKER_COMPOSE_CMD
if command -v docker-compose &> /dev/null; then DOCKER_COMPOSE_CMD="docker-compose";
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then DOCKER_COMPOSE_CMD="docker compose";
else log "Error: Docker Compose not found. Cannot update N8N. 😥"; exit 1; fi

log "Updating yt-dlp on the host machine... 🎬"
if command -v pipx &> /dev/null; then pipx upgrade yt-dlp >> "$LOG_FILE" 2>&1;
elif [ -d "/opt/yt-dlp-venv" ]; then /opt/yt-dlp-venv/bin/pip install -U yt-dlp >> "$LOG_FILE" 2>&1; fi
log "yt-dlp on host updated!"

log "Pulling the latest N8N base image (n8nio/n8n:latest)... 📥"
docker pull n8nio/n8n:latest >> "$LOG_FILE" 2>&1

CURRENT_CUSTOM_IMAGE_ID="$(${DOCKER_COMPOSE_CMD} images -q n8n)"
log "Building your custom N8N image again... 👷"
if ! ${DOCKER_COMPOSE_CMD} build n8n >> "$LOG_FILE" 2>&1; then
    log "Error: Failed to build the custom image. Update aborted. Check logs for details. 🐛"
    exit 1
fi
NEW_CUSTOM_IMAGE_ID="$(${DOCKER_COMPOSE_CMD} images -q n8n)"

if [ "${CURRENT_CUSTOM_IMAGE_ID}" != "${NEW_CUSTOM_IMAGE_ID}" ]; then
    log "Yay! New N8N version detected! Time to update... 🥳"
    # Run backup before updating (safety first!)
    log "Running a quick backup before updating (just in case!)... 💾"
    if [ -x "${N8N_DIR_VALUE}/backup-workflows.sh" ]; then
        "${N8N_DIR_VALUE}/backup-workflows.sh" >> "$LOG_FILE" 2>&1
    else
        log "Warning: Backup script not found or not executable. Skipping pre-update backup. Fingers crossed! 🤞"
    fi
    log "Stopping and restarting N8N and Caddy containers... 🔄"
    ${DOCKER_COMPOSE_CMD} down >> "$LOG_FILE" 2>&1
    ${DOCKER_COMPOSE_CMD} up -d n8n caddy >> "$LOG_FILE" 2>&1 # Ensure caddy also restarted if needed
    log "N8N update completed successfully! 🎉"
else
    log "No new updates for your N8N custom image. You're already on the latest version! 👍"
fi

log "Updating yt-dlp inside the N8N container too... 🎬"
N8N_CONTAINER_FOR_UPDATE="$(${DOCKER_COMPOSE_CMD} ps -q n8n)"
if [ -n "${N8N_CONTAINER_FOR_UPDATE}" ]; then
    docker exec -u root "${N8N_CONTAINER_FOR_UPDATE}" pip3 install --break-system-packages -U yt-dlp >> "$LOG_FILE" 2>&1
    log "yt-dlp in container updated!"
else
    log "Warning: Couldn't find a running N8N container to update yt-dlp. Oh well. 🤷‍♀️"
fi
log "Update check completed. Everything's shiny! ✨"
EOF_UPDATE_SCRIPT

sed -i "s|__N8N_DIR_VALUE__|${N8N_DIR}|g" "$N8N_DIR/update-n8n.sh"
chmod +x "$N8N_DIR/update-n8n.sh"
echo "✅ Auto-update script created!"

# Step 15: Setting up cron jobs (your background helpers) 🤖
echo ""
echo "Setting up cron jobs so your N8N updates every 12 hours and backups run daily at 2 AM. Totally automated! 🕰️"
CRON_USER=$(whoami) # Run cron with the current user (root)
UPDATE_CRON="0 */12 * * * ${N8N_DIR}/update-n8n.sh"
BACKUP_CRON="0 2 * * * ${N8N_DIR}/backup-workflows.sh"
(crontab -u "$CRON_USER" -l 2>/dev/null | grep -v "update-n8n.sh" | grep -v "backup-workflows.sh"; echo "$UPDATE_CRON"; echo "$BACKUP_CRON") | crontab -u "$CRON_USER" -
echo "✅ Cron jobs configured. Your N8N is now a self-sufficient powerhouse!"

echo "======================================================================"
echo "🎉 Hooray! Your N8N adventure is ready to begin! 🎉"
echo "You can now visit your awesome N8N instance at:"
echo "👉 https://${DOMAIN}"
echo ""

if [ "$(swapon --show | wc -l)" -gt 1 ]; then
    SWAP_INFO=$(free -h | grep Swap | awk '{print $2}')
    echo "► Swap configured: ${SWAP_INFO} (extra memory helper) ✅"
fi
echo "► All N8N configuration and data are safely stored in: '$N8N_DIR' 📂"
echo "► Automatic update feature: I'll check for updates every 12 hours! Log: '$N8N_DIR/update.log' 🔄"
echo "► Workflow and credentials backup feature:"
echo "  - Daily automatic backup at 2 AM. ⏰"
echo "  - Backups go here: '$N8N_DIR/files/backup_full/n8n_backup_YYYYMMDD_HHMMSS.tar.gz' 💾"
echo "  - I'll keep the 30 most recent backups. No clutter! 🗑️"
echo "  - Backup log: '$N8N_DIR/files/backup_full/backup.log' 📝"
echo "► YouTube video download directory: $N8N_DIR/files/youtube_data/ 🎬"
echo "► Puppeteer is all set up inside your N8N container for web scraping magic! ✨"
echo ""
echo "A little note: If you want to use 'yt-dlp' directly from your server's command line,"
echo "you might need to manually add '~/.local/bin' to your PATH environment variable. Just a heads-up! 😉"
echo "======================================================================"
echo "Enjoy your N8N journey! If you have any more questions, just ask! 😊"
