#!/bin/bash

# --- !!! SECURITY WARNING !!! ---
# Hardcoding passwords is extremely insecure. Use with extreme caution.
# Replace "your_codex_password_here" with the actual password.
SUDO_PASSWORD="codex"
# --- !!! END SECURITY WARNING !!! ---


# Ensure the script is run as the 'codex' user
if [ "$(whoami)" != "codex" ]; then
  echo "[ERROR] This script must be run as the 'codex' user, not '$(whoami)'."
  exit 1
fi

# Define repository details
GIT_USERNAME="udhay24"
REPO_URL="https://github.com/Smart-Stream-Technologies/Orbit-Edge-Codex.git"
PROJECT_DIR="/home/codex/Orbit-Edge-Codex" # Explicitly use /home/codex
LOG_FILE="/home/codex/git_clone.log" # Explicitly use /home/codex

# Ensure log file exists and set appropriate permissions
touch "$LOG_FILE"
chown codex:codex "$LOG_FILE"
chmod 644 "$LOG_FILE"

# --- Sudo Authentication Check using hardcoded password ---
echo "[INFO] Checking sudo privileges using provided password..." | tee -a "$LOG_FILE"
echo "$SUDO_PASSWORD" | sudo -S -v
if [ $? -ne 0 ]; then
  echo "[ERROR] Sudo authentication failed using the provided password. Please check SUDO_PASSWORD variable." | tee -a "$LOG_FILE"
  # Avoid logging the password itself in case of failure capture
  exit 1
fi
echo "[INFO] Sudo privileges confirmed." | tee -a "$LOG_FILE"


# Ensure GIT_TOKEN is set (remains unchanged, assumes it's set in codex's environment)
if [ -z "$GIT_TOKEN" ]; then
  echo "[ERROR] GIT_TOKEN environment variable is not set for the 'codex' user!" | tee -a "$LOG_FILE"
  exit 1
fi

echo "[INFO] Updating system packages (requires sudo)..." | tee -a "$LOG_FILE"
# Use sudo -S for all sudo commands, redirect output appropriately
echo "$SUDO_PASSWORD" | sudo -S apt update >> "$LOG_FILE" 2>&1

# Check if Git is installed
if ! command -v git &> /dev/null; then
  echo "[INFO] Git not found. Installing Git (requires sudo)..." | tee -a "$LOG_FILE"
  echo "$SUDO_PASSWORD" | sudo -S apt install git -y >> "$LOG_FILE" 2>&1
  if [ $? -ne 0 ]; then
      echo "[ERROR] Failed to install Git." | tee -a "$LOG_FILE"
      exit 1
  fi
else
  echo "[INFO] Git is already installed." | tee -a "$LOG_FILE"
fi

# --- Git Configuration (as codex, no sudo needed) ---
GIT_CRED_FILE="/home/codex/.git-credentials"
# ... (rest of Git config remains the same as previous 'codex only' version) ...
if ! git config --global credential.helper | grep -q 'store'; then
  echo "[INFO] Configuring Git credentials for user 'codex'..." | tee -a "$LOG_FILE"
  git config --global credential.helper store
  echo "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com" > "$GIT_CRED_FILE"
  chmod 600 "$GIT_CRED_FILE"
else
   echo "[INFO] Git credential helper already configured for 'codex'." | tee -a "$LOG_FILE"
fi
echo "[INFO] Adding $PROJECT_DIR to Git safe directories for user 'codex'..." | tee -a "$LOG_FILE"
git config --global --add safe.directory "$PROJECT_DIR"


# --- Clone or Update Repository (as codex, no sudo needed) ---
if [ -d "$PROJECT_DIR/.git" ]; then
  echo "[INFO] Repository exists at '$PROJECT_DIR'. Checking integrity..." | tee -a "$LOG_FILE"
  cd "$PROJECT_DIR" || { echo "[ERROR] Failed to cd into $PROJECT_DIR"; exit 1; }

  if ! git fsck --full > /dev/null 2>&1; then
    echo "[WARNING] Git repository is corrupted. Deleting and recloning..." | tee -a "$LOG_FILE"
    cd /home/codex
    rm -rf "$PROJECT_DIR"
  else
    echo "[INFO] Git repository is healthy." | tee -a "$LOG_FILE"
  fi
fi



if git clone --branch release/codex3 "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com/Smart-Stream-Technologies/Orbit-Edge-Codex.git" "$PROJECT_DIR" >> "$LOG_FILE" 2>&1; then
  echo "[SUCCESS] Repository cloned successfully into '$PROJECT_DIR'!" | tee -a "$LOG_FILE"
  cd "$PROJECT_DIR" || { echo "[ERROR] Failed to enter newly cloned repo directory '$PROJECT_DIR'." | tee -a "$LOG_FILE"; exit 1; }
else
  echo "[ERROR] Failed to clone repository. Check logs and permissions." | tee -a "$LOG_FILE"
  exit 1
fi



# --- Ensure Correct Ownership (use sudo -S) ---
echo "[INFO] Ensuring correct ownership ('codex:codex') of '$PROJECT_DIR' (requires sudo)..." | tee -a "$LOG_FILE"
echo "$SUDO_PASSWORD" | sudo -S chown -R codex:codex "$PROJECT_DIR"

# --- Install Dependencies (runs as codex user, but will call sudo internally) ---
echo "[INFO] Changing to dependencies directory and running install_deps.sh..." | tee -a "$LOG_FILE"
DEPS_SCRIPT_PATH="$PROJECT_DIR/scripts/dependencies/install_deps.sh"
if [ -f "$DEPS_SCRIPT_PATH" ]; then
  cd "$PROJECT_DIR/scripts/dependencies" || { echo "[ERROR] Dependencies directory not found!" | tee -a "$LOG_FILE"; exit 1; }
  chmod +x install_deps.sh
  # Execute the script as codex. It will need the password defined within it too.
  if ./install_deps.sh 2>&1 | tee -a "$LOG_FILE"; then
    echo "[SUCCESS] Dependencies script executed successfully!" | tee -a "$LOG_FILE"
  else
    echo "[ERROR] Failed to execute dependencies script '$DEPS_SCRIPT_PATH'." | tee -a "$LOG_FILE"
    exit 1
  fi
  # Go back to project root
  cd "$PROJECT_DIR" || { echo "[ERROR] Failed return to project directory '$PROJECT_DIR'." | tee -a "$LOG_FILE"; exit 1; }
else
    echo "[ERROR] Dependency installation script not found at '$DEPS_SCRIPT_PATH'!" | tee -a "$LOG_FILE"
    exit 1
fi

# --- Source NVM (as codex, no sudo needed) ---
# ... (NVM sourcing logic remains the same as previous 'codex only' version) ...
echo "[INFO] Sourcing NVM for main script context..." | tee -a "$LOG_FILE"
export NVM_DIR="/home/codex/.nvm" # Use explicit path
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
  if command -v node &> /dev/null && command -v npm &> /dev/null; then
    echo "[INFO] NVM sourced. Node version: $(node -v), npm version: $(npm -v)" | tee -a "$LOG_FILE" # Verify
  else
    echo "[WARNING] NVM sourced, but node/npm commands not found. Check NVM installation in install_deps.sh." | tee -a "$LOG_FILE"
  fi
else
  echo "[WARNING] NVM script not found or empty at '$NVM_DIR/nvm.sh'. Cannot source NVM." | tee -a "$LOG_FILE"
fi


# --- Print MAC address (as codex, no sudo needed) ---
# ... (MAC address logic remains the same as previous 'codex only' version) ...
echo "[INFO] Retrieving MAC address..." | tee -a "$LOG_FILE"
MAC_ADDRESS=$(ip link show | awk '/ether/ {print $2}' | head -n 1)
if [ -n "$MAC_ADDRESS" ]; then
  echo "[SUCCESS] MAC Address: $MAC_ADDRESS" | tee -a "$LOG_FILE"
else
  MAC_ADDRESS=$(cat /sys/class/net/$(ip route show default | awk '/default/ {print $5}')/address)
  if [ -n "$MAC_ADDRESS" ]; then
     echo "[SUCCESS] MAC Address (alt method): $MAC_ADDRESS" | tee -a "$LOG_FILE"
  else
     echo "[ERROR] Failed to retrieve MAC Address." | tee -a "$LOG_FILE"
  fi
fi


echo "[INFO] Main installation script (install_app.sh) finished." | tee -a "$LOG_FILE"
# Be careful: Exiting here means the SUDO_PASSWORD variable is gone.
# install_deps.sh needs its own definition or it needs to be exported.
# Defining it in both places is simpler if they might run separately.

exit 0
