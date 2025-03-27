#!/bin/bash

# Define repository details
GIT_USERNAME="udhay24"
REPO_URL="https://github.com/Smart-Stream-Technologies/Orbit-Edge-Codex.git"
LOG_FILE="/var/log/git_clone.log"

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

echo "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com" > ~/.git-credentials
chmod 600 ~/.git-credentials  # Secure the file

git config --global --add safe.directory /home/codex/Orbit-Edge-Codex

# Clone the repository
echo "[INFO] Cloning repository from $REPO_URL..." | tee -a "$LOG_FILE"
if git clone --branch release/stable "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com/Smart-Stream-Technologies/Orbit-Edge-Codex.git" >> "$LOG_FILE" 2>&1; then
  echo "[SUCCESS] Repository cloned successfully!" | tee -a "$LOG_FILE"
else
  echo "[ERROR] Failed to clone repository." | tee -a "$LOG_FILE"
  exit 1
fi

# Change ownership
echo "[INFO] Changing ownership of the repository directory..." | tee -a "$LOG_FILE"
sudo chown -R codex:codex /home/codex/Orbit-Edge-Codex

# Install dependencies
echo "[INFO] Installing dependencies..." | tee -a "$LOG_FILE"
cd /home/codex/Orbit-Edge-Codex/scripts/dependencies || { echo "[ERROR] Dependencies directory not found!" | tee -a "$LOG_FILE"; exit 1; }
chmod +x install_deps.sh
if ./install_deps.sh >> "$LOG_FILE" 2>&1; then
  echo "[SUCCESS] Dependencies installed successfully!" | tee -a "$LOG_FILE"
else
  echo "[ERROR] Failed to install dependencies." | tee -a "$LOG_FILE"
  exit 1
fi
