#!/bin/bash

set -e  # Exit on any error
set -o pipefail  # Prevent errors in piped commands from being masked

# Log function
log() {
    echo -e "\n========== $1 ==========\n"
}

# Step 1: Create Codex User
log "Creating Codex user..."
wget -qO- https://raw.githubusercontent.com/udhay24/scripts/main/create_user.sh | sudo bash

# Step 2: Configure Sudo for Codex (No Password)
log "Configuring sudoers for Codex user..."
echo "$USER ALL=(ALL) NOPASSWD: /bin/su - codex" | sudo tee /etc/sudoers.d/codex_nopasswd >/dev/null

# Step 3: Switch to Codex User and Run Installations
log "Switching to Codex user and running installations..."
sudo -i -u codex bash << 'EOF'

set -e
set -o pipefail

echo -e "\n========== Installing Mender ==========\n"
wget -qO- https://raw.githubusercontent.com/udhay24/scripts/main/install_mender_client.sh | bash

echo -e "\n========== Installing Application ==========\n"
GIT_TOKEN=$GIT_TOKEN bash -c 'wget -qO- https://raw.githubusercontent.com/udhay24/scripts/main/install_app.sh | bash'

echo -e "\n========== All installations completed successfully! ==========\n"

EOF

log "Script execution completed!"
