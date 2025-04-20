#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define variables
ROOT_DIR="/home/codex/orbit-play"
DOWNLOAD_URL="https://github.com/bluenviron/mediamtx/releases/download/v1.11.0/mediamtx_v1.11.0_linux_armv7.tar.gz"
TAR_FILE="mediamtx_v1.11.0_linux_armv7.tar.gz"
SERVICE_NAME="orbit-play.service"
BINARY_NAME="mediamtx"
CONFIG_FILE="mediamtx.yml"
SCRIPT_DIR="$(pwd)"  # Store the current directory where the script is running

# Create the folder from root
if [ ! -d "$ROOT_DIR" ]; then
    echo "Creating directory at $ROOT_DIR"
    sudo mkdir -p "$ROOT_DIR"
fi

# Change to the directory
cd "$ROOT_DIR"

# Download the tar.gz file
if [ ! -f "$TAR_FILE" ]; then
    echo "Downloading $TAR_FILE"
    sudo wget "$DOWNLOAD_URL" -O "$TAR_FILE"
fi

# Extract the content of the tar.gz file
if [ -f "$TAR_FILE" ]; then
    echo "Extracting $TAR_FILE"
    sudo tar -xzf "$TAR_FILE"
fi

# Copy the configuration file from script directory to the media server folder
if [ -f "$SCRIPT_DIR/$CONFIG_FILE" ]; then
    echo "Copying $CONFIG_FILE to $ROOT_DIR"
    sudo cp "$SCRIPT_DIR/$CONFIG_FILE" "$ROOT_DIR/$CONFIG_FILE"
    echo "Configuration file copied successfully"
else
    echo "Warning: $CONFIG_FILE not found in script directory!"
    exit 1
fi

# Make the binary executable
if [ -f "$BINARY_NAME" ]; then
    echo "Making $BINARY_NAME executable"
    sudo chmod +x "$BINARY_NAME"
else
    echo "Binary $BINARY_NAME not found!"
    exit 1
fi

# Create the systemd service file
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
if [ ! -f "$SERVICE_PATH" ]; then
    echo "Creating systemd service file at $SERVICE_PATH"
    sudo bash -c "cat > $SERVICE_PATH" <<EOL
[Unit]
Description=MediaMTX Service
After=network.target

[Service]
ExecStart=$ROOT_DIR/$BINARY_NAME
Restart=always
User=root
WorkingDirectory=$ROOT_DIR

[Install]
WantedBy=multi-user.target
EOL
fi

# Reload systemd, enable, and start the service
echo "Reloading systemd daemon"
sudo systemctl daemon-reload

echo "Enabling $SERVICE_NAME"
sudo systemctl enable "$SERVICE_NAME"

echo "Starting $SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

# Confirm service status
echo "Checking service status"
sudo systemctl status "$SERVICE_NAME"