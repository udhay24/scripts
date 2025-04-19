#!/bin/bash

# Define repository details
GIT_USERNAME="udhay24"
REPO_URL="https://github.com/Smart-Stream-Technologies/Orbit-Edge-Codex.git"
LOG_FILE="$HOME/git_clone.log"

touch "$LOG_FILE"
chmod 666 "$LOG_FILE"

# Ensure GIT_TOKEN is set
if [ -z "$GIT_TOKEN" ]; then
  echo "[ERROR] GIT_TOKEN environment variable is not set!" | tee -a "$LOG_FILE"
  exit 1
fi

echo "[INFO] Updating system packages..." | tee -a "$LOG_FILE"
sudo apt update >> "$LOG_FILE" 2>&1

# Check if Git is installed
if ! command -v git &> /dev/null; then
  echo "[INFO] Git not found. Installing Git..." | tee -a "$LOG_FILE"
  sudo apt install git -y >> "$LOG_FILE" 2>&1
else
  echo "[INFO] Git is already installed." | tee -a "$LOG_FILE"
fi

# Configure Git credential storage
echo "[INFO] Configuring Git credentials..." | tee -a "$LOG_FILE"
git config --global credential.helper store

echo "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com" > /home/codex/.git-credentials
chmod 600 /home/codex/.git-credentials
chown codex:codex /home/codex/.git-credentials

git config --global --add safe.directory /home/codex/Orbit-Edge-Codex

# Check if repository already exists
if [ -d "/home/codex/Orbit-Edge-Codex/.git" ]; then
  echo "[INFO] Repository already exists. Skipping clone." | tee -a "$LOG_FILE"
  cd /home/codex/Orbit-Edge-Codex || { echo "[ERROR] Failed to enter repo directory." | tee -a "$LOG_FILE"; exit 1; }

  echo "[INFO] Fetching latest changes..." | tee -a "$LOG_FILE"
  git fetch origin >> "$LOG_FILE" 2>&1

  echo "[INFO] Checking out branch release/codex3..." | tee -a "$LOG_FILE"
  git checkout release/codex3 >> "$LOG_FILE" 2>&1

  echo "[INFO] Resetting local branch to match origin/release/codex3..." | tee -a "$LOG_FILE"
  git reset --hard origin/release/codex3 >> "$LOG_FILE" 2>&1
else
  echo "[INFO] Repository not found. Cloning..." | tee -a "$LOG_FILE"
  echo "[INFO] Cloning repository from $REPO_URL..." | tee -a "$LOG_FILE"
  if git clone --branch release/codex3 "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com/Smart-Stream-Technologies/Orbit-Edge-Codex.git" /home/codex/Orbit-Edge-Codex >> "$LOG_FILE" 2>&1; then
    echo "[SUCCESS] Repository cloned successfully!" | tee -a "$LOG_FILE"
  else
    echo "[ERROR] Failed to clone repository." | tee -a "$LOG_FILE"
    exit 1
  fi
fi


# Change ownership
echo "[INFO] Changing ownership of the repository directory..." | tee -a "$LOG_FILE"
sudo chown -R codex:codex /home/codex/Orbit-Edge-Codex

# Install dependencies
echo "[INFO] Installing dependencies..." | tee -a "$LOG_FILE"
cd /home/codex/Orbit-Edge-Codex/scripts/dependencies || { echo "[ERROR] Dependencies directory not found!" | tee -a "$LOG_FILE"; exit 1; }
chmod +x install_deps.sh

# Execute the script and print logs in real-time
if ./install_deps.sh 2>&1 | tee -a "$LOG_FILE"; then
  echo "[SUCCESS] Dependencies installed successfully!" | tee -a "$LOG_FILE"
else
  echo "[ERROR] Failed to install dependencies." | tee -a "$LOG_FILE"
  exit 1
fi

# Print MAC address
echo "[INFO] Retrieving MAC address..." | tee -a "$LOG_FILE"
MAC_ADDRESS=$(ip link show | awk '/ether/ {print $2}' | head -n 1)

if [ -n "$MAC_ADDRESS" ]; then
  echo "[SUCCESS] MAC Address: $MAC_ADDRESS" | tee -a "$LOG_FILE"
else
  echo "[ERROR] Failed to retrieve MAC Address." | tee -a "$LOG_FILE"
fi
