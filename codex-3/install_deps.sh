#!/bin/bash

echo "--- Script running as user: $(whoami), UID: $(id -u), Home: $HOME ---"
echo "--- Shell: $SHELL, PWD: $(pwd), Script name: $0 ---"

# --- SECURITY WARNING ---
SUDO_PASSWORD="codex"
# --- END WARNING ---

# Logging setup
LOG_FILE="/home/codex/orbit-edge-setup.log"
echo "$SUDO_PASSWORD" | sudo -S touch "$LOG_FILE"
echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$LOG_FILE"
echo "$SUDO_PASSWORD" | sudo -S chmod 644 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- Starting dependency setup script (install_deps.sh) at $(date) ---"

# Configuration paths
PERSISTENT_SCRIPTS_DIR="/home/codex/.orbit-edge-persistent"

# Remote script URLs
UPDATE_START_URL="https://raw.githubusercontent.com/udhay24/scripts/main/codex-3/update_start.sh"
MEDIA_SERVER_URL="https://raw.githubusercontent.com/udhay24/scripts/main/codex-3/install_media_server.sh"

# Systemd configuration
SERVICE_FILE="/etc/systemd/system/orbit-edge-codex.service"

# --- Helper Functions ---
safe_download() {
    local url=$1
    local dest=$2
    echo "Downloading $dest from GitHub..."

    if ! curl -fsSL "$url" -o "$dest"; then
        echo "[ERROR] Failed to download $dest"
        return 1
    fi

    if ! head -n1 "$dest" | grep -q '^#!/bin/bash'; then
        echo "[SECURITY] Invalid script format in $dest"
        rm -f "$dest"
        return 1
    fi

    chmod +x "$dest"
    echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$dest"
}

# --- Initial Setup ---
mkdir -p "$PERSISTENT_SCRIPTS_DIR"
echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$PERSISTENT_SCRIPTS_DIR"


# --- Systemd Service Configuration ---
cat > /tmp/orbit-edge-service.tmp << EOF
[Unit]
Description=Orbit-Edge Codex Application
After=network-online.target redis-server.service
Wants=network-online.target

[Service]
WorkingDirectory=/home/codex/Orbit-Edge-Codex
ExecStartPre=/usr/bin/sleep 3
ExecStart=/bin/bash -c 'curl -fsSL $UPDATE_START_URL | bash -s'
Restart=always
RestartSec=5
User=codex
Group=codex
Environment="NODE_ENV=production"
OnFailure=orbit-edge-codex-crash-monitor.service

[Install]
WantedBy=multi-user.target
EOF
echo "$SUDO_PASSWORD" | sudo -S mv /tmp/orbit-edge-service.tmp "$SERVICE_FILE"

# --- Dependency Installation ---
echo "Updating system packages..."
echo "$SUDO_PASSWORD" | sudo -S apt-get update -y

# Base dependencies
for pkg in curl gpg lsb-release; do
  if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
    echo "Installing $pkg..."
    echo "$SUDO_PASSWORD" | sudo -S apt-get install -y "$pkg" || exit 1
  fi
done

# Redis installation
install_redis() {
  REDIS_KEYRING="/usr/share/keyrings/redis-archive-keyring.gpg"
  REDIS_LIST="/etc/apt/sources.list.d/redis.list"

  # Fix malformed Redis APT source file, if any
  if [ -f "$REDIS_LIST" ]; then
    echo "[INFO] Removing malformed Redis source list..."
    echo "$SUDO_PASSWORD" | sudo -S rm -f "$REDIS_LIST"
  fi

  # Fix GPG key writing using tee, not broken piping
  echo "[INFO] Installing Redis GPG key..."
  curl -fsSL https://packages.redis.io/gpg | gpg --dearmor | sudo tee "$REDIS_KEYRING" >/dev/null || {
    echo "[ERROR] Failed to install GPG key"; exit 1;
  }

  # Now add correct Redis source list
  echo "[INFO] Writing proper Redis source entry..."
  DISTRO=$(lsb_release -cs)
  echo "deb [signed-by=$REDIS_KEYRING] https://packages.redis.io/deb $DISTRO main" | sudo tee "$REDIS_LIST" >/dev/null || {
    echo "[ERROR] Failed to write Redis source list"; exit 1;
  }

  # Install Redis from updated repo
  echo "[INFO] Updating APT and installing Redis..."
  echo "$SUDO_PASSWORD" | sudo -S apt-get update -y
  echo "$SUDO_PASSWORD" | sudo -S apt-get install -y redis || {
    echo "[ERROR] Failed to install Redis."; exit 1;
  }

  # Enable Redis
  echo "$SUDO_PASSWORD" | sudo -S systemctl enable redis-server
  echo "$SUDO_PASSWORD" | sudo -S systemctl start redis-server

  # Verify Redis is running
  if systemctl is-active --quiet redis-server; then
    echo "✅ Redis is now installed and running."
  else
    echo "[ERROR] Redis installation failed - service not running."
    return 1
  fi
}

# Check if Redis is installed and running
check_redis() {
  if command -v redis-server &>/dev/null; then
    if systemctl is-active --quiet redis-server; then
      echo "✅ Redis is installed and running."
      return 0
    else
      echo "⚠️ Redis is installed but not running."
      return 1
    fi
  else
    echo "Redis is not installed."
    return 2
  fi
}

# Uninstall Redis if needed
uninstall_redis() {
  echo "Uninstalling Redis..."
  echo "$SUDO_PASSWORD" | sudo -S systemctl stop redis-server || true
  echo "$SUDO_PASSWORD" | sudo -S apt-get purge -y redis-server || true
  echo "$SUDO_PASSWORD" | sudo -S apt-get autoremove -y
  echo "$SUDO_PASSWORD" | sudo -S rm -rf /etc/redis /var/lib/redis /var/log/redis* || true
}

# Main Redis setup logic
check_redis
STATUS=$?

if [ "$STATUS" -eq 0 ]; then
  echo "Redis is already installed and running properly."
elif [ "$STATUS" -eq 1 ]; then
  echo "Redis is installed but not running. Reinstalling..."
  uninstall_redis
  install_redis || exit 1
elif [ "$STATUS" -eq 2 ]; then
  echo "Redis not found. Installing..."
  install_redis || exit 1
fi

# FFmpeg installation
command -v ffmpeg &>/dev/null || {
  echo "Installing FFmpeg..."
  echo "$SUDO_PASSWORD" | sudo -S apt-get install -y ffmpeg || exit 1
}

# --- Node.js Environment ---
export NVM_DIR="/home/codex/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] || {
  echo "Installing NVM..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  echo "$SUDO_PASSWORD" | sudo -S chown -R codex:codex "$NVM_DIR"
}

source "$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts
corepack enable

# Install pnpm using corepack
echo "Installing pnpm with corepack..."
corepack prepare pnpm@latest --activate
pnpm setup
source /home/codex/.bashrc
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
export PATH="$PNPM_HOME:$PATH"

# --- Application Setup ---
# --- Application Setup ---
PROJECT_ROOT="/home/codex/Orbit-Edge-Codex"
cd "$PROJECT_ROOT" || { echo "[ERROR] Failed to change directory to $PROJECT_ROOT"; exit 1; } # Added error check

if [ -f package.json ]; then
  echo "Installing Node.js dependencies with pnpm..."
  # Use a here-document to execute the script as user 'codex' via sudo
  echo "$SUDO_PASSWORD" | sudo -S -u codex bash << 'EOF_SCRIPT'
    # The script content goes here, with proper indentation is optional but good practice

    export NVM_DIR="/home/codex/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # Use '\.' or 'source' with space for portability
    nvm use --lts || { echo "Failed to use LTS node version"; exit 1; } # Added error check

    # Add pnpm environment setup
    export PNPM_HOME="/home/codex/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"

    # Verify pnpm is in PATH
    if ! command -v pnpm &> /dev/null; then
        echo "pnpm command not found after setup."
        exit 1
    fi
    echo "pnpm found at: $(command -v pnpm)"
    echo "Current PATH: $PATH"


    max_retries=2
    attempt=0
    install_success=0

    cleanup() {
        echo 'Cleaning up pnpm artifacts...'
        # Ensure cleanup commands are robust
        rm -rf node_modules .pnpm-store pnpm-lock.yaml package-lock.json || echo "Warning: cleanup failed, continuing anyway"
        pnpm store prune || echo "Warning: pnpm store prune failed, continuing anyway"
    }

    cleanup

    while [ $attempt -lt $max_retries ]; do
        ((attempt++))
        echo "Installation attempt $attempt/$max_retries"

        # Global packages
        echo "Installing global packages..."
        if pnpm add -g husky is-ci @nestjs/cli rimraf; then
            echo "Global packages installed successfully."
        else
            echo 'Global package installation failed.'
            cleanup
            continue # Try again
        fi

        # Local packages
        echo "Installing local dependencies..."
        if pnpm install; then
            echo 'Local package installation successful.'
            install_success=1
            break # Exit loop on success
        else
            echo 'Local package installation failed.'
            cleanup
            continue # Try again
        fi
    done

    # Check if installation was successful after the loop
    if [ $install_success -eq 0 ]; then
        echo 'Maximum installation attempts reached. Critical failure.'
        exit 1
    fi


    # Build packages (only if install was successful)
    echo 'Building packages...'
    if pnpm run build; then
        echo 'Project build successfully'
    else
        echo '[ERROR] Project build failed.'
        exit 1 # Exit if build fails
    fi

EOF_SCRIPT

  # Check the exit status of the here-document script
  if [ $? -ne 0 ]; then
    echo "[FATAL] Failed to install pnpm dependencies after multiple attempts"
    exit 1
  fi
else
  echo "[WARNING] No package.json found in $PROJECT_ROOT. Skipping pnpm dependency installation."
fi

# --- Media Server Installation ---
echo "Installing media server from GitHub..."
# Run the script as root to avoid nested sudo
echo "$SUDO_PASSWORD" | sudo -S bash -c "bash <(curl -fsSL $MEDIA_SERVER_URL)" || exit 1

# --- Final Systemd Setup ---
echo "$SUDO_PASSWORD" | sudo -S systemctl daemon-reload
echo "$SUDO_PASSWORD" | sudo -S systemctl enable orbit-edge-codex
echo "$SUDO_PASSWORD" | sudo -S systemctl restart orbit-edge-codex

echo "--- Dependency setup completed at $(date) ---"