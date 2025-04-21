#!/bin/bash

# NVM Setup
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Log files
LOG_START="/home/codex/update_start.log"
ERROR_LOG="/home/codex/update_error.log"
EXIT_LOG="/home/codex/startprod_exits.log"  # Track service exits

# Project config
BRANCH="release/codex3"
PROJECT_DIR="/home/codex/Orbit-Edge-Codex"
LOCAL_VERSION_PATH="/home/codex/.orbit-edge-persistent/LOCAL_VERSION"

# Diagnostic Logging
{
  echo "--- NVM Diagnostics ---"
  echo "Timestamp: $(date)"
  echo "NVM_DIR: $NVM_DIR"
  echo "PATH: $PATH"
  echo "Which node: $(which node)"
  echo "Node version: $(node -v)"
  echo "Which pnpm: $(which pnpm)"
  echo "pnpm version: $(pnpm -v)"
  echo "--- End NVM Diagnostics ---"
} >> "$LOG_START"

# Version comparison function
check_versions() {
    echo "--- Version Check ---" | tee -a "$LOG_START"

    REMOTE_VERSION=$(curl -s https://raw.githubusercontent.com/udhay24/scripts/main/VERSION | tr -d '[:space:]')
    if [ $? -ne 0 ] || [ -z "$REMOTE_VERSION" ]; then
        echo "Failed to fetch remote version" | tee -a "$LOG_START"
        return 1
    fi
    echo "Remote version: $REMOTE_VERSION" | tee -a "$LOG_START"

    if [ -f "$LOCAL_VERSION_PATH" ]; then
        LOCAL_VERSION=$(cat "$LOCAL_VERSION_PATH" | tr -d '[:space:]')
        echo "Local version: $LOCAL_VERSION" | tee -a "$LOG_START"
    else
        echo "Local version file not found: $LOCAL_VERSION_PATH" | tee -a "$LOG_START"
        return 1
    fi

    if [ "$LOCAL_VERSION" == "$REMOTE_VERSION" ]; then
        echo "✅ Versions match. No update needed." | tee -a "$LOG_START"
        return 0
    else
        echo "⚠️  Version mismatch. Update required." | tee -a "$LOG_START"
        return 1
    fi
}


# Exit monitoring functions
check_exits() {
  echo "Running check_exits function..." >> "$LOG_START"

  current_time=$(date +%s)
  five_minutes_ago=$((current_time - 300))

  # Debug information
  echo "Current time: $current_time, Five minutes ago: $five_minutes_ago" >> "$LOG_START"

  # Check if log file exists
  if [ ! -f "$EXIT_LOG" ]; then
    echo "Exit log file doesn't exist yet. Creating it." >> "$LOG_START"
    touch "$EXIT_LOG"
    echo "0" >> "$EXIT_LOG"  # Initial entry
  fi

  # Debug - show current log content
  echo "Current EXIT_LOG content:" >> "$LOG_START"
  cat "$EXIT_LOG" >> "$LOG_START"

  # Filter entries within the last 5 minutes
  temp_file=$(mktemp)
  while read -r timestamp; do
    if [[ -n "$timestamp" && "$timestamp" =~ ^[0-9]+$ && "$timestamp" -gt "$five_minutes_ago" ]]; then
      echo "$timestamp" >> "$temp_file"
    fi
  done < "$EXIT_LOG"

  # Replace original with filtered content
  cat "$temp_file" > "$EXIT_LOG"
  rm "$temp_file"

  # Count remaining entries
  count=$(grep -c "^[0-9]" "$EXIT_LOG")

  echo "Recent exit count (last 5 minutes): $count" >> "$LOG_START"

  if [ "$count" -ge 3 ]; then
    echo "Detected 3 or more exits in the last 5 minutes" >> "$LOG_START"
    return 0
  else
    echo "Less than 3 exits detected in the last 5 minutes" >> "$LOG_START"
    return 1
  fi
}

run_start_prod() {
  echo "Starting production server..."
  cd "$PROJECT_DIR" || return 1
  pnpm run start:prod
  EXIT_CODE=$?

  if [ $EXIT_CODE -ne 0 ]; then
    echo "$(date +%s)" >> "$EXIT_LOG"

    if check_exits; then
      {
        echo "--- CRITICAL SERVICE FAILURE ---"
        echo "Service exited 3 times within 5 minutes"
        echo "Initiating recovery at $(date)"
      } >> "$ERROR_LOG"

      # Spawn recovery process
      (
        echo "Stopping service..." >> "$ERROR_LOG"
        echo "codex" | sudo -S systemctl stop orbit-edge-codex.service

        echo "Running reinstallation..." >> "$ERROR_LOG"
        bash -c 'wget -qO- https://raw.githubusercontent.com/udhay24/scripts/main/codex-3/install_app.sh | bash' >> "$ERROR_LOG" 2>&1

        echo "Killing parent process..." >> "$ERROR_LOG"
        echo "codex" | sudo -S systemctl disable orbit-edge-codex.service
        kill -9 $$
      ) &
    fi
    return 1
  fi
  return 0
}

 # Update process
echo "Downloading and executing startup patch script..."
curl -s https://raw.githubusercontent.com/udhay24/scripts/main/startup_patch.sh | bash

echo "Navigating to project directory..."
cd "$PROJECT_DIR" || exit 1

# Main execution flow
if check_versions; then
  echo "Starting existing version" >> "$LOG_START"
else
  echo "Resetting git state..."
  git reset --hard || exit 1

  echo "Checking out and pulling branch $BRANCH..."
  git checkout "$BRANCH" || exit 1
  git pull origin "$BRANCH" || exit 1

  echo "Cleaning and installing dependencies..."
  rm -rf node_modules pnpm-lock.yaml || exit 1
  pnpm store prune || exit 1
  pnpm install || exit 1

  echo "Building the application..."
  pnpm run build || exit 1

  echo "Fetching and storing remote version to $LOCAL_VERSION_PATH"
  REMOTE_VERSION=$(curl -s https://raw.githubusercontent.com/udhay24/scripts/main/VERSION | tr -d '[:space:]')
  if [ $? -eq 0 ] && [ -n "$REMOTE_VERSION" ]; then
      mkdir -p "$(dirname "$LOCAL_VERSION_PATH")"
      echo "$REMOTE_VERSION" > "$LOCAL_VERSION_PATH" || exit 1
      echo "Stored version: $REMOTE_VERSION"
  else
      echo "ERROR: Failed to fetch remote version for storage"
      exit 1
  fi
fi

# Start service with monitoring
run_start_prod || exit 1
