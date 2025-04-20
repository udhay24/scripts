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
CRASH_COUNT_FILE="/home/codex/orbit-edge-codex.crash_count"
LAST_CRASH_TIME_FILE="/home/codex/orbit-edge-codex.last_crash_time"

# Remote script URLs
UPDATE_START_URL="https://raw.githubusercontent.com/udhay24/scripts/main/codex-3/update_start.sh"
MEDIA_SERVER_URL="https://raw.githubusercontent.com/udhay24/scripts/main/codex-3/install_media_server.sh"

# Systemd configuration
SERVICE_FILE="/etc/systemd/system/orbit-edge-codex.service"
CRASH_MONITOR_SERVICE="/etc/systemd/system/orbit-edge-codex-crash-monitor.service"
CRASH_MONITOR_TIMER="/etc/systemd/system/orbit-edge-codex-crash-monitor.timer"

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

# Create crash tracking files
echo "$SUDO_PASSWORD" | sudo -S touch "$CRASH_COUNT_FILE" "$LAST_CRASH_TIME_FILE"
echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$CRASH_COUNT_FILE" "$LAST_CRASH_TIME_FILE"

# --- Crash Management System ---
cat > "$PERSISTENT_SCRIPTS_DIR/restart-counter.sh" << 'EOF'
#!/bin/bash
CRASH_COUNT_FILE="/home/codex/orbit-edge-codex.crash_count"
LAST_CRASH_TIME_FILE="/home/codex/orbit-edge-codex.last_crash_time"

(
  flock -x 200
  current_count=$(cat "$CRASH_COUNT_FILE" 2>/dev/null || echo 0)
  echo $((current_count + 1)) > "$CRASH_COUNT_FILE"
  date +%s > "$LAST_CRASH_TIME_FILE"
) 200>/var/lock/orbit-edge-crash.lock
EOF
chmod +x "$PERSISTENT_SCRIPTS_DIR/restart-counter.sh"

# --- Systemd Service Configuration ---
cat > /tmp/orbit-edge-service.tmp << EOF
[Unit]
Description=Orbit-Edge Codex Application
After=network.target redis-server.service

[Service]
WorkingDirectory=/home/codex/Orbit-Edge-Codex
ExecStart=/bin/bash -c 'curl -fsSL $UPDATE_START_URL | bash -s'
Restart=always
User=codex
Group=codex
Environment="NODE_ENV=production"
OnFailure=orbit-edge-codex-crash-monitor.service

[Install]
WantedBy=multi-user.target
EOF
echo "$SUDO_PASSWORD" | sudo -S mv /tmp/orbit-edge-service.tmp "$SERVICE_FILE"

# Update the crash monitor script in $PERSISTENT_SCRIPTS_DIR/crash_monitor.sh
cat > "$PERSISTENT_SCRIPTS_DIR/crash_monitor.sh" << 'EOF'
#!/bin/bash

# Configuration
MAX_CRASHES=2
TIME_WINDOW=600  # 10 minutes in seconds
CRASH_COUNT_FILE="/home/codex/orbit-edge-codex.crash_count"
LAST_CRASH_TIME_FILE="/home/codex/orbit-edge-codex.last_crash_time"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/udhay24/scripts/main/codex-3/install_deps.sh"
LOCK_FILE="/var/lock/orbit-edge-crash.lock"

# Use file descriptor 200 for locking
exec 200>"$LOCK_FILE"
flock -x 200

# Read crash data
current_count=$(cat "$CRASH_COUNT_FILE" 2>/dev/null || echo 0)
last_crash_time=$(cat "$LAST_CRASH_TIME_FILE" 2>/dev/null || echo 0)
current_time=$(date +%s)

# Calculate time difference
time_diff=$((current_time - last_crash_time))

# Check if we're in the monitoring time window
if [ "$current_count" -ge "$MAX_CRASHES" ] && [ "$time_diff" -le "$TIME_WINDOW" ]; then
    echo "Critical failure threshold reached ($MAX_CRASHES crashes in ${TIME_WINDOW}s). Initiating reinstallation..."

    # Reset crash counter
    echo 0 > "$CRASH_COUNT_FILE"

    # Stop the service
    sudo systemctl stop orbit-edge-codex
    sudo systemctl disable orbit-edge-codex

    # Reinstall from remote script
    echo "Starting fresh installation..."
    curl -fsSL "$INSTALL_SCRIPT_URL" | sudo -u codex bash -s --

    # Exit without restarting to prevent loop
    exit 0
elif [ "$time_diff" -gt "$TIME_WINDOW" ]; then
    # Reset counter if outside time window
    echo 0 > "$CRASH_COUNT_FILE"
fi

# Normal crash handling
echo $((current_count + 1)) > "$CRASH_COUNT_FILE"
echo "$current_time" > "$LAST_CRASH_TIME_FILE"

# Release lock
flock -u 200
EOF

# --- Crash Monitor Systemd Units ---
cat > /tmp/crash-monitor.service << EOF
[Unit]
Description=Orbit Edge Crash Recovery Service

[Service]
Type=oneshot
ExecStart=$PERSISTENT_SCRIPTS_DIR/crash_monitor.sh
User=codex
EOF

cat > /tmp/crash-monitor.timer << EOF
[Unit]
Description=Orbit Edge Crash Recovery Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

echo "$SUDO_PASSWORD" | sudo -S mv /tmp/crash-monitor.service "$CRASH_MONITOR_SERVICE"
echo "$SUDO_PASSWORD" | sudo -S mv /tmp/crash-monitor.timer "$CRASH_MONITOR_TIMER"

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
corepack prepare npm@latest --activate

# --- Application Setup ---
PROJECT_ROOT="/home/codex/Orbit-Edge-Codex"
cd "$PROJECT_ROOT" || exit 1

if [ -f package.json ]; then
  echo "Installing Node.js dependencies..."
  echo "$SUDO_PASSWORD" | sudo -S -u codex bash -c "
    export NVM_DIR=\"/home/codex/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && source \"\$NVM_DIR/nvm.sh\"
    nvm use --lts

    max_retries=2
    attempt=0

    cleanup() {
        echo 'Cleaning up npm artifacts...'
        GLOBAL_NPM_DIR=\$(npm config get prefix 2>/dev/null)/lib/node_modules
        SAFE_PKG_NAME=\$(echo \"\$pkg\" | sed 's|@||;s|/|-|')  # handle scoped packages
        rm -rf \"\$GLOBAL_NPM_DIR/\$pkg\" \"\$GLOBAL_NPM_DIR/.\$SAFE_PKG_NAME\"* || true
        rm -rf node_modules package-lock.json .npm .npmrc
        npm cache clean --force
    }

    while [ \$attempt -lt \$max_retries ]; do
        ((attempt++))
        echo \"Installation attempt \$attempt/\$max_retries\"

        # Global packages
        npm install -g husky is-ci @nestjs/cli rimraf || {
            echo 'Global package installation failed'
            cleanup
            continue
        }

        # Local packages
        npm install && {
            echo 'Dependencies installed successfully'
            break
        }

        # Cleanup if installation failed
        echo 'npm install failed, cleaning up...'
        cleanup

        if [ \$attempt -eq \$max_retries ]; then
            echo 'Maximum installation attempts reached. Critical failure.'
            exit 1
        fi
    done
  " || {
    echo "[FATAL] Failed to install npm dependencies after multiple attempts"
    exit 1
  }
fi

# --- Media Server Installation ---
MEDIA_SCRIPT_PATH="/tmp/install_media_server.sh"
echo "Installing media server from GitHub..."
curl -fsSL "$MEDIA_SERVER_URL" -o "$MEDIA_SCRIPT_PATH" || exit 1
chmod +x "$MEDIA_SCRIPT_PATH"
echo "$SUDO_PASSWORD" | sudo -S -u codex bash -c "$MEDIA_SCRIPT_PATH" || exit 1
rm -f "$MEDIA_SCRIPT_PATH"

# --- Final Systemd Setup ---
echo "$SUDO_PASSWORD" | sudo -S systemctl daemon-reload
echo "$SUDO_PASSWORD" | sudo -S systemctl enable orbit-edge-codex orbit-edge-codex-crash-monitor.timer
echo "$SUDO_PASSWORD" | sudo -S systemctl start orbit-edge-codex orbit-edge-codex-crash-monitor.timer

echo "--- Dependency setup completed at $(date) ---"