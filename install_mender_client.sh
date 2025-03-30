#!/bin/bash

set -e

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
  --device-type codex \
  --server-ip 43.204.205.12 \
  --inventory-poll 14400 \
  --retry-poll 600 \
  --update-poll 3600

# Restart Mender servicewhen
echo "Restarting Mender service..."
sudo systemctl restart mender-client

echo "Mender client installation and configuration complete."
