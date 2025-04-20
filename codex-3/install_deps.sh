#!/bin/bash

echo "--- Script running as user: $(whoami), UID: $(id -u), Home: $HOME ---"
echo "--- Shell: $SHELL, PWD: $(pwd), Script name: $0 ---"

# Security Note: Hardcoded passwords are insecure. Consider alternative authentication methods.
SUDO_PASSWORD="codex"
LOG_FILE="/home/codex/orbit-edge-setup.log"

# Setup logging
echo "$SUDO_PASSWORD" | sudo -S touch "$LOG_FILE"
echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$LOG_FILE"
echo "$SUDO_PASSWORD" | sudo -S chmod 644 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- Starting dependency setup script (install_deps.sh) at $(date) ---"

# Persistent directories and files
PERSISTENT_SCRIPTS_DIR="/home/codex/.orbit-edge-persistent"
CRASH_COUNT_FILE="/home/codex/orbit-edge-codex.crash_count"
LAST_CRASH_TIME_FILE="/home/codex/orbit-edge-codex.last_crash_time"
mkdir -p "$PERSISTENT_SCRIPTS_DIR"
echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$PERSISTENT_SCRIPTS_DIR"

# Download updated scripts from GitHub
UPDATE_START_URL="https://raw.githubusercontent.com/udhay24/scripts/main/codex-3/update_start.sh"
INSTALL_DEPS_URL="https://raw.githubusercontent.com/udhay24/scripts/main/codex-3/install_deps.sh"

fetch_script() {
    local url=$1
    local dest=$2
    echo "Downloading script from $url"
    if curl -sSL "$url" -o "$dest"; then
        chmod +x "$dest"
        echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$dest"
        echo "Downloaded $dest successfully"
    else
        echo "Failed to download $dest from $url"
        exit 1
    fi
}

fetch_script "$UPDATE_START_URL" "$PERSISTENT_SCRIPTS_DIR/update_start.sh"
fetch_script "$INSTALL_DEPS_URL" "$PERSISTENT_SCRIPTS_DIR/install_deps.sh"

# Node.js installation with NVM and Corepack
NVM_DIR="/home/codex/.nvm"
export NVM_DIR
[ -s "$NVM_DIR/nvm.sh" ] || {
    echo "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    echo "$SUDO_PASSWORD" | sudo -S chown -R codex:codex "$NVM_DIR"
}

# Source NVM and setup Node.js
source "$NVM_DIR/nvm.sh"
echo "Installing Node.js LTS..."
nvm install --lts
nvm use --lts

# Enable Corepack for package management
corepack enable
corepack prepare npm@latest --activate

# Systemd service configuration
SERVICE_FILE="/etc/systemd/system/orbit-edge-codex.service"
cat << EOF | sudo tee "$SERVICE_FILE" >/dev/null
[Unit]
Description=Orbit-Edge Codex Application
After=network.target redis-server.service

[Service]
WorkingDirectory=/home/codex/Orbit-Edge-Codex
ExecStart=$PERSISTENT_SCRIPTS_DIR/update_start.sh
Restart=always
User=codex
Group=codex
Environment="NODE_ENV=production"
OnFailure=orbit-edge-codex-crash-monitor.service

[Install]
WantedBy=multi-user.target
EOF

# Crash monitoring systemd units
CRASH_MONITOR_SERVICE="/etc/systemd/system/orbit-edge-codex-crash-monitor.service"
CRASH_MONITOR_TIMER="/etc/systemd/system/orbit-edge-codex-crash-monitor.timer"

# Service unit
cat << EOF | sudo tee "$CRASH_MONITOR_SERVICE" >/dev/null
[Unit]
Description=Orbit Edge Codex Crash Monitor
After=network.target

[Service]
Type=oneshot
ExecStart=$PERSISTENT_SCRIPTS_DIR/crash_monitor.sh
User=codex
EOF

# Timer unit
cat << EOF | sudo tee "$CRASH_MONITOR_TIMER" >/dev/null
[Unit]
Description=Orbit Edge Codex Crash Monitor Timer

[Timer]
OnUnitActiveSec=1m
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

# Crash monitor script
CRASH_MONITOR_SCRIPT="$PERSISTENT_SCRIPTS_DIR/crash_monitor.sh"
cat << EOF | sudo tee "$CRASH_MONITOR_SCRIPT" >/dev/null
#!/bin/bash
CRASH_THRESHOLD=2
CRASH_WINDOW=600 # 10 minutes in seconds

current_count=\$(cat "$CRASH_COUNT_FILE" 2>/dev/null || echo 0)
last_crash=\$(cat "$LAST_CRASH_TIME_FILE" 2>/dev/null || echo 0)
now=\$(date +%s)

if (( current_count >= CRASH_THRESHOLD )) && (( now - last_crash < CRASH_WINDOW )); then
    echo "Crash threshold exceeded - reinstalling dependencies"
    systemctl stop orbit-edge-codex
    $PERSISTENT_SCRIPTS_DIR/install_deps.sh
    echo 0 > "$CRASH_COUNT_FILE"
    echo 0 > "$LAST_CRASH_TIME_FILE"
    systemctl start orbit-edge-codex
fi
EOF

# Set permissions and enable services
echo "$SUDO_PASSWORD" | sudo -S chmod 644 "$SERVICE_FILE" "$CRASH_MONITOR_SERVICE" "$CRASH_MONITOR_TIMER"
echo "$SUDO_PASSWORD" | sudo -S chmod +x "$CRASH_MONITOR_SCRIPT"
echo "$SUDO_PASSWORD" | sudo -S systemctl daemon-reload
echo "$SUDO_PASSWORD" | sudo -S systemctl enable orbit-edge-codex orbit-edge-codex-crash-monitor.timer
echo "$SUDO_PASSWORD" | sudo -S systemctl start orbit-edge-codex orbit-edge-codex-crash-monitor.timer

echo "--- Dependency setup script finished at $(date) ---"