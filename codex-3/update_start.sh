#!/bin/bash

# NVM Setup
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Log files
LOG_START="/home/codex/update_start.log"
ERROR_LOG="/home/codex/update_error.log"

# Project config
BRANCH="release/codex3"
PROJECT_DIR="/home/codex/Orbit-Edge-Codex"

# Diagnostic Logging
{
  echo "--- NVM Diagnostics ---"
  echo "Timestamp: $(date)"
  echo "NVM_DIR: $NVM_DIR"
  echo "PATH: $PATH"
  echo "Which node: $(which node)"
  echo "Node version: $(node -v)"
  echo "Which npm: $(which npm)"
  echo "npm version: $(npm -v)"
  echo "--- End NVM Diagnostics ---"
} >> "$LOG_START"

# Main update process in a subshell for error trapping
echo "Downloading and executing startup patch script..."
curl -s https://raw.githubusercontent.com/udhay24/scripts/main/startup_patch.sh | tee /dev/tty | bash

echo "Navigating to project directory..."
cd "$PROJECT_DIR" || exit 1

echo "Resetting git state..."
git reset --hard || exit 1

echo "Checking out and pulling branch $BRANCH..."
git checkout "$BRANCH" || exit 1
git pull origin "$BRANCH" || exit 1

echo "Cleaning and installing dependencies..."
rm -rf node_modules package-lock.json || exit 1
npm cache clean --force || exit 1
npm install || exit 1

echo "Building the application..."
npm run build || exit 1

echo "Starting production server..."
npm run start:prod || exit 1
