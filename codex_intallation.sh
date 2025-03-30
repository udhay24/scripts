#!/bin/bash

# Define log file
LOG_FILE="/var/log/codex_installation.log"
USERNAME="codex"
PASSWORD="codex"

# Function to execute a command and log output
execute_and_log() {
    echo "Executing: $1" | tee -a "$LOG_FILE"
    bash -c "$1" 2>&1 | tee -a "$LOG_FILE"
    echo "-----------------------------------------" | tee -a "$LOG_FILE"
}

# Step 1: Install User
execute_and_log "wget -qO- https://raw.githubusercontent.com/udhay24/scripts/main/create_user.sh | sudo bash"

# Step 2: Switch to the created user and install Mender & Application
export SUDO_ASKPASS=/tmp/askpass

# Create a script to auto-fill the password
cat <<EOL > \$SUDO_ASKPASS
#!/bin/bash
echo "$PASSWORD"
EOL
chmod +x \$SUDO_ASKPASS

sudo -E -A -i -u "$USERNAME" bash <<EOF

# Step 2: Install Mender
wget -qO- https://raw.githubusercontent.com/udhay24/scripts/main/install_mender_client.sh | sudo -A bash

# Step 3: Install Application
sudo -A GIT_TOKEN=\$GIT_TOKEN bash -c 'wget -qO- https://raw.githubusercontent.com/udhay24/scripts/main/install_app.sh | bash'
EOF

# Remove the password script
rm -f \$SUDO_ASKPASS

# Completion message
echo "Installation process completed as user '$USERNAME'. Logs are stored in $LOG_FILE."
