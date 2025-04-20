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
if ! command -v redis-server &>/dev/null; then
  echo "Installing Redis..."
  curl -fsSL https://packages.redis.io/gpg | echo "$SUDO_PASSWORD" | sudo -S gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | echo "$SUDO_PASSWORD" | sudo -S tee /etc/apt/sources.list.d/redis.list >/dev/null
  echo "$SUDO_PASSWORD" | sudo -S apt-get update -y
  echo "$SUDO_PASSWORD" | sudo -S apt-get install -y redis || exit 1
  if [ $? -ne 0 ]; then echo "[ERROR] Failed to install Redis."; exit 1; fi
      echo "Enabling Redis service (requires sudo)..."
      echo "$SUDO_PASSWORD" | sudo -S systemctl enable redis-server
      echo "$SUDO_PASSWORD" | sudo -S systemctl start redis-server
  # Disable Redis log file (uses sudo -S)
  REDIS_CONF="/etc/redis/redis.conf"
  # Use sudo -S with grep first to check condition
  if echo "$SUDO_PASSWORD" | sudo -S grep -qE "^logfile .+" "$REDIS_CONF"; then
      echo "Disabling Redis file logging in $REDIS_CONF (requires sudo)..."
      echo "$SUDO_PASSWORD" | sudo -S sed -i 's|^logfile .*|logfile ""|' "$REDIS_CONF"
      echo "$SUDO_PASSWORD" | sudo -S systemctl restart redis-server
  else
      echo "Redis file logging already disabled or not configured in $REDIS_CONF."
  fi
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
PROJECT_ROOT="/home/codex/Orbit-Edge-Codex"
cd "$PROJECT_ROOT" || exit 1

if [ -f package.json ]; then
  echo "Installing Node.js dependencies with pnpm..."
  echo "$SUDO_PASSWORD" | sudo -S -u codex bash -c "
    export NVM_DIR=\"/home/codex/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && source \"\$NVM_DIR/nvm.sh\"
    nvm use --lts

    # Add pnpm environment setup
    export PNPM_HOME=\"/home/codex/.local/share/pnpm\"
    export PATH=\"\$PNPM_HOME:\$PATH\"

    max_retries=2
    attempt=0

    cleanup() {
        echo 'Cleaning up pnpm artifacts...'
        rm -rf node_modules .pnpm-store pnpm-lock.yaml
        pnpm store prune
    }

    while [ \$attempt -lt \$max_retries ]; do
        ((attempt++))
        echo \"Installation attempt \$attempt/\$max_retries\"

        # Global packages
        pnpm add -g husky is-ci @nestjs/cli rimraf || {
            echo 'Global package installation failed'
            cleanup
            continue
        }

        # Local packages
        pnpm install || {
            echo 'Local package installation failed'
            cleanup
            continue
        }

        # Build packages
        echo 'Building packages...'
        pnpm run build && {
            echo 'Project build successfully'
            break
        }

        # Cleanup if installation failed
        echo 'pnpm install failed, cleaning up...'
        cleanup

        if [ \$attempt -eq \$max_retries ]; then
            echo 'Maximum installation attempts reached. Critical failure.'
            exit 1
        fi
    done
  " || {
    echo "[FATAL] Failed to install pnpm dependencies after multiple attempts"
    exit 1
  }
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