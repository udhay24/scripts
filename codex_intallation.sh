#!/bin/bash

# Define log file
LOG_FILE="/var/log/codex_installation.log"
USERNAME="codex"

# Function to execute a command and log output
execute_and_log() {
    echo "Executing: $1" | tee -a "$LOG_FILE"
    bash -c "$1" 2>&1 | tee -a "$LOG_FILE"
    echo "-----------------------------------------" | tee -a "$LOG_FILE"
}

# Step 1: Install User
execute_and_log "wget -qO- https://raw.githubusercontent.com/udhay24/scripts/main/create_user.sh | sudo bash"

# Step 2: Grant Passwordless Sudo for Specific Commands
echo "$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/wget, /bin/bash, /usr/bin/apt, /usr/bin/apt-get" | sudo tee /etc/sudoers.d/$USERNAME

# Step 3: Switch to User and Install Mender & Application
sudo -i -u "$USERNAME" bash <<EOF
    # Install Mender
    wget -qO- https://raw.githubusercontent.com/udhay24/scripts/main/install_mender_client.sh | sudo bash

    # Install Application
    sudo GIT_TOKEN=\$GIT_TOKEN bash -c 'wget -qO- https://raw.githubusercontent.com/udhay24/scripts/main/install_app.sh | bash'
EOF

# Completion message
echo "Installation process completed as user '$USERNAME'. Logs are stored in $LOG_FILE."
