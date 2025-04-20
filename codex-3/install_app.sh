#!/bin/bash

# === SECURITY WARNING ===
SUDO_PASSWORD="codex"
# === CONFIG ===
GIT_USERNAME="udhay24"
REPO_URL="https://github.com/Smart-Stream-Technologies/Orbit-Edge-Codex.git"
BRANCH="release/codex3"
PROJECT_DIR="/home/codex/Orbit-Edge-Codex"
TEMP_DIR="/home/codex/Orbit-Edge-Codex-TMP"
LOG_FILE="/home/codex/git_clone.log"
DEPS_SCRIPT_PATH="$PROJECT_DIR/scripts/dependencies/install_deps.sh"
GIT_CRED_FILE="/home/codex/.git-credentials"

# === Start ===
touch "$LOG_FILE"
chown codex:codex "$LOG_FILE"
chmod 644 "$LOG_FILE"

if [ "$(whoami)" != "codex" ]; then
  echo "[ERROR] Script must run as 'codex' not '$(whoami)'." | tee -a "$LOG_FILE"
  exit 1
fi

echo "[INFO] Checking sudo access..." | tee -a "$LOG_FILE"
echo "$SUDO_PASSWORD" | sudo -S -v
if [ $? -ne 0 ]; then
  echo "[ERROR] Sudo authentication failed." | tee -a "$LOG_FILE"
  exit 1
fi

# === Ensure GIT_TOKEN is set ===
if [ -z "$GIT_TOKEN" ]; then
  echo "[ERROR] GIT_TOKEN environment variable not set!" | tee -a "$LOG_FILE"
  exit 1
fi

# === Install Git if not present ===
if ! command -v git &> /dev/null; then
  echo "[INFO] Git not found. Installing..." | tee -a "$LOG_FILE"
  echo "$SUDO_PASSWORD" | sudo -S apt update >> "$LOG_FILE" 2>&1
  echo "$SUDO_PASSWORD" | sudo -S apt install git -y >> "$LOG_FILE" 2>&1
else
  echo "[INFO] Git already installed." | tee -a "$LOG_FILE"
fi

# === Git Credential Config ===
if ! git config --global credential.helper | grep -q 'store'; then
  echo "[INFO] Configuring Git credentials..." | tee -a "$LOG_FILE"
  git config --global credential.helper store
  echo "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com" > "$GIT_CRED_FILE"
  chmod 600 "$GIT_CRED_FILE"
else
  echo "[INFO] Git credentials already configured." | tee -a "$LOG_FILE"
fi
git config --global --add safe.directory "$PROJECT_DIR"

# === Repository Logic ===
if [ -d "$PROJECT_DIR/.git" ]; then
  echo "[INFO] Found existing repo. Verifying..." | tee -a "$LOG_FILE"
  cd "$PROJECT_DIR"
  if ! git fsck --full > /dev/null 2>&1; then
    echo "[WARNING] Repository is corrupted. Deleting..." | tee -a "$LOG_FILE"
    rm -rf "$PROJECT_DIR"
  else
    echo "[INFO] Repository healthy. Pulling latest changes..." | tee -a "$LOG_FILE"
    git fetch origin "$BRANCH" >> "$LOG_FILE" 2>&1
    git reset --hard origin/"$BRANCH" >> "$LOG_FILE" 2>&1
    echo "[SUCCESS] Repository updated." | tee -a "$LOG_FILE"
    REPO_READY=true
  fi
fi

# === Clone if not ready ===
if [ "$REPO_READY" != true ]; then
  echo "[INFO] Cloning fresh repo to temp dir..." | tee -a "$LOG_FILE"
  rm -rf "$TEMP_DIR"
  if git clone --branch "$BRANCH" "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com/Smart-Stream-Technologies/Orbit-Edge-Codex.git" "$TEMP_DIR" >> "$LOG_FILE" 2>&1; then
    rm -rf "$PROJECT_DIR"
    mv "$TEMP_DIR" "$PROJECT_DIR"
    echo "[SUCCESS] Cloned repo to '$PROJECT_DIR'." | tee -a "$LOG_FILE"
  else
    echo "[ERROR] Failed to clone repository." | tee -a "$LOG_FILE"
    rm -rf "$TEMP_DIR"
    exit 1
  fi
fi

# === Ownership Fix ===
echo "$SUDO_PASSWORD" | sudo -S chown -R codex:codex "$PROJECT_DIR"

# === Dependency Install ===
echo "[INFO] Running install_deps.sh..." | tee -a "$LOG_FILE"
if [ -f "$DEPS_SCRIPT_PATH" ]; then
  cd "$(dirname "$DEPS_SCRIPT_PATH")" || exit
  chmod +x install_deps.sh
  export SUDO_PASSWORD="$SUDO_PASSWORD"
  ./install_deps.sh 2>&1 | tee -a "$LOG_FILE"
else
  echo "[ERROR] Dependency script not found at $DEPS_SCRIPT_PATH" | tee -a "$LOG_FILE"
  exit 1
fi

# === MAC Address ===
echo "[INFO] Retrieving MAC address..." | tee -a "$LOG_FILE"
MAC_ADDRESS=$(ip link show | awk '/ether/ {print $2}' | head -n 1)
if [ -z "$MAC_ADDRESS" ]; then
  MAC_ADDRESS=$(cat /sys/class/net/$(ip route show default | awk '/default/ {print $5}')/address)
fi
if [ -n "$MAC_ADDRESS" ]; then
  echo "[SUCCESS] MAC Address: $MAC_ADDRESS" | tee -a "$LOG_FILE"
else
  echo "[ERROR] Failed to retrieve MAC address." | tee -a "$LOG_FILE"
fi

echo "[INFO] install_app.sh completed." | tee -a "$LOG_FILE"
exit 0
