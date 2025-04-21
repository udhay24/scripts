#!/bin/bash
set -e

# --- SECURITY WARNING ---
SUDO_PASSWORD="codex"  # Replace with your actual password if different
# --- END WARNING ---

# Configuration
ROOT_DIR="/home/codex/orbit-play"
DOWNLOAD_URL="https://github.com/bluenviron/mediamtx/releases/download/v1.11.0/mediamtx_v1.11.0_linux_armv7.tar.gz"
CONFIG_FILE_URL="https://raw.githubusercontent.com/udhay24/scripts/main/mediamtx.yml"
SERVICE_NAME="orbit-play.service"
BINARY_NAME="mediamtx"

# Check if directory exists
if [ -d "$ROOT_DIR" ]; then
  echo "Directory already exists. Deleting..."
  rm -rf "$ROOT_DIR"
fi

# Create working directory
mkdir -p "$ROOT_DIR"
cd "$ROOT_DIR"

# Download and extract binary
if [ ! -f "${ROOT_DIR}/${BINARY_NAME}" ]; then
    echo "Downloading MediaMTX..."
    wget -q "$DOWNLOAD_URL" -O "${ROOT_DIR}/mediamtx.tar.gz"
    tar -xzf mediamtx.tar.gz
    rm mediamtx.tar.gz
fi

# Download configuration
echo "Downloading configuration..."
wget -q "$CONFIG_FILE_URL" -O "${ROOT_DIR}/mediamtx.yml"

# Set permissions
chmod +x "${ROOT_DIR}/${BINARY_NAME}"
chmod 644 "${ROOT_DIR}/mediamtx.yml"

# Create systemd service
echo "Creating systemd service..."
echo "$SUDO_PASSWORD" | sudo -S bash -c "cat > /etc/systemd/system/${SERVICE_NAME}" <<EOL
[Unit]
Description=Orbit Play Media Server
After=network.target

[Service]
User=codex
Group=codex
WorkingDirectory=${ROOT_DIR}
ExecStart=${ROOT_DIR}/${BINARY_NAME}
Restart=always
RestartSec=5
Environment="HOME=/home/codex"

[Install]
WantedBy=multi-user.target
EOL

# Systemd management
echo "Configuring service..."
{
    echo "$SUDO_PASSWORD" | sudo -S systemctl daemon-reload
    echo "$SUDO_PASSWORD" | sudo -S systemctl enable "${SERVICE_NAME}"
    echo "$SUDO_PASSWORD" | sudo -S systemctl restart "${SERVICE_NAME}"
} > /dev/null 2>&1

echo "Installation complete!"
echo "Service status:"
echo "$SUDO_PASSWORD" | sudo -S systemctl status "${SERVICE_NAME}" --no-pager