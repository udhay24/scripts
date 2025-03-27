#!/bin/bash

set -e

# Variables
MENDER_SERVER_IP="mender.s2tlive.com"
DEVICE_TYPE="codex"

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
            --server-ip $MENDER_SERVER_IP

# Restart Mender servicewhen
echo "Restarting Mender service..."
sudo systemctl restart mender client

echo "Mender client installation and configuration complete."
