#!/bin/bash

set -e

# Variables
MENDER_SERVER_IP="43.204.205.12"
DEVICE_TYPE="codex"
INVENTORY_POLL=14400  # 4 hours
RETRY_POLL=600        # 10 minutes
UPDATE_POLL=3600      # 1 hour

# Update and install dependencies
echo "Updating package lists and installing dependencies..."
sudo apt-get update
sudo apt-get install -y wget apt-transport-https ca-certificates gnupg

# Install Mender client
echo "Installing Mender client..."
sudo bash -c "$(curl -fLsS https://get.mender.io)"

# Configure Mender client
echo "Configuring Mender client..."
sudo mender setup \
            --device-type $DEVICE_TYPE \
            --server-ip $MENDER_SERVER_IP \
            --inventory-poll $INVENTORY_POLL \
            --retry-poll $RETRY_POLL \
            --update-poll $UPDATE_POLL

# Restart Mender servicewhen
echo "Restarting Mender service..."
sudo systemctl restart mender client

echo "Mender client installation and configuration complete."
