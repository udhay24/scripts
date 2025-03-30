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

# Create Mender state script directory
echo "Setting up Mender state scripts..."
sudo mkdir -p /var/lib/mender/scripts

# Copy commit enter trigger script
echo "Creating commit enter trigger script..."
cat << 'EOF' | sudo tee /var/lib/mender/scripts/ArtifactCommit_Enter_00_deploy.sh
#!/bin/bash
set -e

echo "Checking out application..."
cd /home/codex/Orbit-Edge-Codex

echo "Pulling changes"
git pull

echo "Installing dependencies..."
npm install

echo "Building application..."
npm run build

echo "Restarting application..."
systemctl restart orbit-edge-codex

echo "Deployment script executed successfully."
EOF

# Make the script executable
sudo chmod +x /var/lib/mender/scripts/ArtifactCommit_Enter_00_deploy.sh

# Restart Mender service
echo "Restarting Mender service..."
sudo systemctl restart mender-client

echo "Mender client installation and configuration complete."
