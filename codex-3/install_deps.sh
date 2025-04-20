#!/bin/bash

echo "--- Script running as user: $(whoami), UID: $(id -u), Home: $HOME ---"
echo "--- Shell: $SHELL, PWD: $(pwd), Script name: $0 ---"

# --- !!! SECURITY WARNING !!! ---
# Hardcoding passwords is extremely insecure. Use with extreme caution.
# Replace "your_codex_password_here" with the actual password.
# Ensure this matches the password in install_app.sh
SUDO_PASSWORD="codex"
# --- !!! END SECURITY WARNING !!! ---

# This script assumes it is run as the 'codex' user or as root using sudo with the 'codex' password.
# It will use 'sudo -S' with the hardcoded password for root or other user commands.

# Log file - Use explicit path for clarity
LOG_FILE="/home/codex/orbit-edge-setup.log"

# Ensure log file exists and has correct permissions/ownership
# Use sudo -S to ensure ownership if needed if the script is run as root somehow
echo "$SUDO_PASSWORD" | sudo -S touch "$LOG_FILE" || true
echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$LOG_FILE" || true
echo "$SUDO_PASSWORD" | sudo -S chmod 644 "$LOG_FILE" || true

# Redirect stdout/stderr to log file AND terminal
# This redirection happens *after* the password variable is set.
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- Starting dependency setup script (install_deps.sh) at $(date) ---"
echo "[WARNING] Using hardcoded sudo password. This is insecure."

# Create persistent directory (as codex)
PERSISTENT_SCRIPTS_DIR="/home/codex/.orbit-edge-persistent"
echo "Ensuring persistent scripts directory exists: $PERSISTENT_SCRIPTS_DIR"
mkdir -p "$PERSISTENT_SCRIPTS_DIR"
# Ensure ownership in case parent dir wasn't owned by codex
echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$PERSISTENT_SCRIPTS_DIR" || true


# --- NEW: Paths for crash counter and cron scripts ---
RESTART_SCRIPT="$PERSISTENT_SCRIPTS_DIR/restart-counter-script.sh"
CRON_SCRIPT="$PERSISTENT_SCRIPTS_DIR/check_crash_and_reset.sh"
CRASH_COUNT_FILE="/home/codex/orbit-edge-codex.crash_count"
LAST_CRASH_TIME_FILE="/home/codex/orbit-edge-codex.last_crash_time"
CRON_LOG_FILE="/home/codex/cron.log" # Log file for the cron job output


# --- NEW: Create the crash counter and timestamp files and set ownership ---
echo "Creating crash counter and timestamp files..."
# Use sudo -S to ensure ownership if the script starts as root
echo "$SUDO_PASSWORD" | sudo -S touch "$CRASH_COUNT_FILE" "$LAST_CRASH_TIME_FILE" "$CRON_LOG_FILE" || true
echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$CRASH_COUNT_FILE" "$LAST_CRASH_TIME_FILE" "$CRON_LOG_FILE" || true
echo "$SUDO_PASSWORD" | sudo -S chmod 644 "$CRASH_COUNT_FILE" "$LAST_CRASH_TIME_FILE" "$CRON_LOG_FILE" || true


# --- NEW: Create the restart counter script (triggered by OnFailure) ---
echo "Creating restart counter script: $RESTART_SCRIPT"
cat > "$RESTART_SCRIPT" << 'EOF_RESTART'
#!/bin/bash
# Script executed by systemd's OnFailure for orbit-edge-codex.service

# Define file paths relative to the user's home
CRASH_COUNT_FILE="/home/codex/orbit-edge-codex.crash_count"
LAST_CRASH_TIME_FILE="/home/codex/orbit-edge-codex.last_crash_time"
LOCK_FILE="/home/codex/orbit-edge-codex.lock" # Lock file path

# Ensure these files are owned by codex - important if script runs as root
chown codex:codex "$CRASH_COUNT_FILE" 2>/dev/null || true
chown codex:codex "$LAST_CRASH_TIME_FILE" 2>/dev/null || true
chown codex:codex "$LOCK_FILE" 2>/dev/null || true

# Use flock for basic concurrency safety
(
  # Acquire exclusive lock (file descriptor 200)
  flock 200

  # Read current count
  # Default to 0 if the file doesn't exist or is empty
  current_count=$(cat "$CRASH_COUNT_FILE" 2>/dev/null || echo 0)

  # Increment count
  new_count=$((current_count + 1))

  # Write new count back to the file
  echo "$new_count" > "$CRASH_COUNT_FILE"

  # Write current timestamp (seconds since epoch)
  date +%s > "$LAST_CRASH_TIME_FILE"

  echo "[$(date)] Service crash detected. Count: $new_count, Timestamp (epoch): $(cat "$LAST_CRASH_TIME_FILE")"

) 200>"$LOCK_FILE" # Associate file descriptor 200 with the lock file
EOF_RESTART
echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$RESTART_SCRIPT" || true
chmod +x "$RESTART_SCRIPT"


# --- NEW: Create the cron job script ---
echo "Creating cron job script: $CRON_SCRIPT"
cat > "$CRON_SCRIPT" << 'EOF_CRON'
#!/bin/bash
# Cron script to check service crash count and time, and reset/restart if needed.

CRASH_COUNT_FILE="/home/codex/orbit-edge-codex.crash_count"
LAST_CRASH_TIME_FILE="/home/codex/orbit-edge-codex.last_crash_time"
UPDATE_START_SCRIPT="/home/codex/.orbit-edge-persistent/update_start.sh"
RESET_THRESHOLD_SECONDS=300 # 5 minutes threshold for resetting counter

# Ensure files exist, owned by codex
touch "$CRASH_COUNT_FILE" 2>/dev/null || true
touch "$LAST_CRASH_TIME_FILE" 2>/dev/null || true
chown codex:codex "$CRASH_COUNT_FILE" 2>/dev/null || true
chown codex:codex "$LAST_CRASH_TIME_FILE" 2>/dev/null || true


# Read last crash time (seconds since epoch) and current time
last_crash_timestamp=$(cat "$LAST_CRASH_TIME_FILE" 2>/dev/null || echo 0)
current_timestamp=$(date +%s)

# Calculate time difference
time_difference=$((current_timestamp - last_crash_timestamp))

# Read current crash count
current_count=$(cat "$CRASH_COUNT_FILE" 2>/dev/null || echo 0)

# Check conditions:
# 1. Has a crash been recorded (count > 0)?
# 2. Has the last crash happened more than the threshold time ago?
#    OR is the last crash time 0 (meaning no crash recorded yet or it was reset)?
if [ "$current_count" -gt 0 ] && { [ "$time_difference" -gt "$RESET_THRESHOLD_SECONDS" ] || [ "$last_crash_timestamp" -eq 0 ]; }; then
  echo "[$(date)] CRON CHECK: Service crashed ($current_count times). Last crash was > $((RESET_THRESHOLD_SECONDS / 60)) mins ago ($time_difference seconds). Resetting counter and running update script."

  # Reset crash counter
  echo 0 > "$CRASH_COUNT_FILE"
  # Reset last crash time
  echo 0 > "$LAST_CRASH_TIME_FILE"

  # Run the update script as the codex user with their environment
  # Use su -l to simulate a login shell, which should pick up corepack and node from PATH
  # Run in background '&' so cron job doesn't hang waiting for the script to finish
  echo "[$(date)] Running update script: $UPDATE_START_SCRIPT"
  # Explicitly set PATH within su -l just to be safe
  su -l codex -c "
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH; # Ensure standard paths
    # Corepack should be available via PATH and enabled system-wide
    exec $UPDATE_START_SCRIPT # Use exec to replace the current shell process with the script
  " &


elif [ "$current_count" -gt 0 ]; then
    # Crash detected, but within the threshold time - likely systemd is handling rapid restarts
    echo "[$(date)] CRON CHECK: Service crashed ($current_count times). Last crash was within $((RESET_THRESHOLD_SECONDS / 60)) mins ($time_difference seconds). Not resetting/restarting via cron."
else
    # Count is 0, service is assumed to be running fine or hasn't crashed since last reset/boot
    # No action needed
    : # Null command
fi
EOF_CRON
echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$CRON_SCRIPT" || true
chmod +x "$CRON_SCRIPT"


# Update package lists (requires sudo -S)
echo "Updating package lists (requires sudo)..."
echo "$SUDO_PASSWORD" | sudo -S apt-get update -y

# Install prerequisites (requires sudo -S)
echo "Checking/installing prerequisites (curl, gpg, lsb-release)..."
for pkg in curl gpg lsb-release; do
  if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
    echo "Installing $pkg (requires sudo)..."
    echo "$SUDO_PASSWORD" | sudo -S apt-get install -y "$pkg"
    if [ $? -ne 0 ]; then echo "[ERROR] Failed to install $pkg."; exit 1; fi
  else
    echo "$pkg is already installed."
  fi
done

# Function to add Redis repository (uses sudo -S)
add_redis_repo() {
  echo "Adding Redis repository (requires sudo)..."
  echo "$SUDO_PASSWORD" | sudo -S mkdir -p /usr/share/keyrings # Ensure dir exists
  # Pipe curl output directly to gpg run with sudo -S
  curl -fsSL https://packages.redis.io/gpg | echo "$SUDO_PASSWORD" | sudo -S gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg.new
  if [ $? -ne 0 ]; then echo "[ERROR] Failed to download/process Redis GPG key."; return 1; fi
  echo "$SUDO_PASSWORD" | sudo -S mv /usr/share/keyrings/redis-archive-keyring.gpg.new /usr/share/keyrings/redis-archive-keyring.gpg
  if [ $? -ne 0 ]; then echo "[ERROR] Failed to move Redis GPG key."; return 1; fi
  echo "$SUDO_PASSWORD" | sudo -S chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg
  if [ $? -ne 0 ]; then echo "[ERROR] Failed to set permissions on Redis GPG key."; return 1; fi

  # Pipe echo output to tee run with sudo -S
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | echo "$SUDO_PASSWORD" | sudo -S tee /etc/apt/sources.list.d/redis.list > /dev/null
  if [ $? -ne 0 ]; then echo "[ERROR] Failed to add Redis source list."; return 1; fi
  return 0 # Success
}

# Install Redis (uses sudo -S)
if ! command -v redis-server &> /dev/null; then
  echo "Redis not found."
  if add_redis_repo; then
      echo "Updating package list after adding Redis repo (requires sudo)..."
      echo "$SUDO_PASSWORD" | sudo -S apt-get update -y
      echo "Installing Redis (requires sudo)..."
      echo "$SUDO_PASSWORD" | sudo -S apt-get install -y redis
      if [ $? -ne 0 ]; then echo "[ERROR] Failed to install Redis."; exit 1; fi
      echo "Enabling Redis service (requires sudo)..."
      echo "$SUDO_PASSWORD" | sudo -S systemctl enable redis-server
      echo "$SUDO_PASSWORD" | sudo -S systemctl start redis-server
  else
      echo "[ERROR] Skipping Redis installation due to repository setup failure."
  fi
else
  echo "Redis is already installed."
fi

# Disable Redis log file (uses sudo -S)
REDIS_CONF="/etc/redis/redis.conf"
# Use sudo -S with grep first to check condition
if echo "$SUDO_PASSWORD" | sudo -S grep -qE "^logfile .+" "$REDIS_CONF"; then
    echo "Disabling Redis file logging in $REDIS_CONF (requires sudo)..."
    echo "$SUDO_PASSWORD" | sudo -S sed -i 's|^logfile .*|logfile ""|' "$REDIS_CONF"
    echo "Restarting Redis service after config change (requires sudo)..."
    echo "$SUDO_PASSWORD" | sudo -S systemctl restart redis-server
else
    echo "Redis file logging already disabled or not configured in $REDIS_CONF."
fi


# Install FFmpeg (requires sudo -S)
if ! command -v ffmpeg &> /dev/null; then
  echo "Installing FFmpeg (requires sudo)..."
  echo "$SUDO_PASSWORD" | sudo -S apt-get install -y ffmpeg
  if [ $? -ne 0 ]; then echo "[ERROR] Failed to install FFmpeg."; exit 1; fi
else
  echo "FFmpeg is already installed."
fi

# NPM install etc (as codex)
PROJECT_ROOT_DIR="/home/codex/Orbit-Edge-Codex"
echo "Changing directory to $PROJECT_ROOT_DIR..."
cd "$PROJECT_ROOT_DIR" || { echo "[ERROR] Failed to cd to project root '$PROJECT_ROOT_DIR'."; exit 1; }

if [ -f package.json ]; then
  echo "Found package.json. Installing npm dependencies (as codex)..."
  # --- MODIFIED: Use sudo -u codex to execute npm commands, ensure PATH ---
  echo "$SUDO_PASSWORD" | sudo -S -u codex bash -c "
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH; # Ensure standard paths
    export HOME=/home/codex; # Ensure HOME is correct
    export NVM_DIR=/home/codex/.nvm;
    [ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"; # Source NVM (adds NVM paths)
    cd '$PROJECT_ROOT_DIR' || exit 1; # Change to project dir

    echo 'Current Node (inside npm install sudo -u bash -c): \$(node -v), npm: \$(npm -v)';
    echo 'Current PATH (inside npm install sudo -u bash -c): \$PATH'; # Debugging

    echo 'Attempting to install global npm packages: husky, is-ci, @nestjs/cli, rimraf...';
    # Clean cache *inside* the bash -c environment where npm will run
    npm cache clean --force;
    GLOBAL_INSTALL_STATUS=\$?;
    if [ \$GLOBAL_INSTALL_STATUS -ne 0 ]; then
      echo '[WARNING] npm cache clean encountered issues, proceeding anyway.';
    fi

    npm install -g husky is-ci @nestjs/cli rimraf;
    GLOBAL_INSTALL_STATUS=\$?;
    if [ \$GLOBAL_INSTALL_STATUS -ne 0 ]; then
      echo '[ERROR] Failed to install global npm packages. Attempting to fix...';
      echo 'Cleaning up broken global installs manually...';
      # Get the global node_modules directory path from npm config
      GLOBAL_NPM_DIR=\$(npm config get prefix 2>/dev/null)/lib/node_modules;
      if [ -d \"\$GLOBAL_NPM_DIR\" ]; then
          for pkg in husky is-ci @nestjs/cli rimraf; do
            SAFE_PKG_NAME=\$(echo \"\$pkg\" | sed 's|@||;s|/|-|'); # handle scoped packages
            rm -rf \"\$GLOBAL_NPM_DIR/\$pkg\" \"\$GLOBAL_NPM_DIR/.\$SAFE_PKG_NAME\"* || true;
          done
          echo 'Retrying global npm install...';
          npm install -g husky is-ci @nestjs/cli rimraf;
          GLOBAL_INSTALL_STATUS=\$?;
          if [ \$GLOBAL_INSTALL_STATUS -ne 0 ]; then
            echo '[FATAL ERROR] Failed to install global npm packages even after cleanup.';
            exit 1 # Exit the bash -c block if this crucial step fails
          else
            echo 'Successfully installed global npm packages after cleanup.';
          fi
      else
         echo '[WARNING] Could not determine global npm directory to perform cleanup.';
         exit 1 # Exit the bash -c block if global install failed and cleanup wasn't possible
      fi
    else
      echo 'Successfully installed global npm packages.';
    fi

    echo 'Installing project npm dependencies (npm install)...';
    # Clean project dependencies directly
    rm -rf node_modules package-lock.json;
    npm cache clean --force; # Clean cache again before main install
    # Use the corepack-managed npm for project installs
    npm install; # No sudo needed for project dependencies
    if [ \$? -ne 0 ]; then echo '[ERROR] \"npm install\" failed.'; exit 1; fi # Exit the bash -c block if project install fails
    echo 'NPM dependencies installed successfully.';
  " # End of sudo -u codex bash -c block for NPM install
  NPM_INSTALL_STATUS=$?
  if [ $NPM_INSTALL_STATUS -ne 0 ]; then
      echo "[ERROR] NPM installation steps failed for user 'codex'. See logs above."
      exit 1 # Exit the main script if npm install fails
  fi
else
  echo "No package.json found in '$PROJECT_ROOT_DIR'; skipping npm install."
fi


# Copy environment file (as codex)
# Ensure we are back in the project directory if npm install changed it (unlikely with sudo -u bash -c)
cd "$PROJECT_ROOT_DIR" || { echo "[ERROR] Failed to cd back to project root '$PROJECT_ROOT_DIR'."; exit 1; }
if [ -f .env.production ]; then
  echo "Copying .env.production to .env (as codex)..."
  cp .env.production .env
  echo "$SUDO_PASSWORD" | sudo -S chown codex:codex .env || true
else
  echo ".env.production file not found in '$PROJECT_ROOT_DIR'; skipping environment setup."
fi

# Copy update_start.sh (as codex)
UPDATE_START_SRC="$PROJECT_ROOT_DIR/scripts/app/update_start.sh"
UPDATE_START_DEST="$PERSISTENT_SCRIPTS_DIR/update_start.sh"
if [ -f "$UPDATE_START_SRC" ]; then
  echo "Copying '$UPDATE_START_SRC' to '$UPDATE_START_DEST'..."
  cp "$UPDATE_START_SRC" "$UPDATE_START_DEST"
  echo "$SUDO_PASSWORD" | sudo -S chown codex:codex "$UPDATE_START_DEST" || true
  chmod +x "$UPDATE_START_DEST"
  echo "Update script copied and made executable."
else
  echo "Source update_start.sh not found at '$UPDATE_START_SRC'."
  if [ ! -f "$UPDATE_START_DEST" ]; then
    echo "[ERROR] update_start.sh not found in source or persistent dir. Service may fail!"
  else
    echo "Found existing update_start.sh in '$PERSISTENT_SCRIPTS_DIR'."
  fi
fi

# --- NEW: Create systemd service file ---
SERVICE_FILE="/etc/systemd/system/orbit-edge-codex.service"
echo "Creating/updating systemd service file: $SERVICE_FILE (requires sudo)..."

SERVICE_TEMP="/tmp/orbit-edge-codex.service.tmp"
cat > "$SERVICE_TEMP" << EOF_SERVICE
[Unit]
Description=Orbit-Edge Codex Application
After=network.target redis-server.service

[Service]
WorkingDirectory=/home/codex/Orbit-Edge-Codex
# ExecStart should find 'node' via PATH after NodeSource install
ExecStart=/home/codex/.orbit-edge-persistent/update_start.sh
Restart=always
User=codex
Group=codex
Environment="NODE_ENV=production"
# OnFailure directive to run our counter script when the service fails
OnFailure=$RESTART_SCRIPT # Use the variable defined earlier

[Install]
WantedBy=multi-user.target
EOF_SERVICE

# Move the temporary file to the systemd location with sudo
echo "$SUDO_PASSWORD" | sudo -S mv "$SERVICE_TEMP" "$SERVICE_FILE"
if [ $? -ne 0 ]; then echo "[ERROR] Failed to move service file."; exit 1; fi
echo "$SUDO_PASSWORD" | sudo -S chmod 644 "$SERVICE_FILE"
if [ $? -ne 0 ]; then echo "[ERROR] Failed to set permissions on service file."; return 1; fi


# --- NEW: Add cron job for the codex user ---
echo "Adding cron job for user 'codex' to run '$CRON_SCRIPT' every minute..."
# Use sudo -u codex to edit the codex user's crontab
# Use 'crontab -l' to list current jobs (suppressing errors if none exist)
# Use 'grep -v' to remove any existing line matching our script
# Use 'echo' to add the new line
# Pipe the result back to 'crontab -' to update the user's crontab
# Ensure sudo doesn't ask for a password again by piping SUDO_PASSWORD
(echo "$SUDO_PASSWORD" | sudo -S crontab -u codex -l 2>/dev/null | grep -v "$CRON_SCRIPT" ; echo "* * * * * $CRON_SCRIPT >> $CRON_LOG_FILE 2>&1") | echo "$SUDO_PASSWORD" | sudo -S crontab -u codex -
if [ $? -ne 0 ]; then echo "[ERROR] Failed to add cron job for user 'codex'."; fi

echo "Cron job configuration attempted for codex user. Check 'crontab -l -u codex' to verify."
echo "Cron job output will be logged to: $CRON_LOG_FILE"


# Reload systemd, enable and start service (requires sudo -S)
echo "Reloading systemd daemon (requires sudo)..."
echo "$SUDO_PASSWORD" | sudo -S systemctl daemon-reload
if [ $? -ne 0 ]; then echo "[WARNING] systemctl daemon-reload failed."; fi

echo "Stopping orbit-edge-codex service (if running)..."
# Use || true to prevent script exiting if service doesn't exist/isn't running
echo "$SUDO_PASSWORD" | sudo -S systemctl stop orbit-edge-codex || true

echo "Enabling orbit-edge-codex service (requires sudo)..."
echo "$SUDO_PASSWORD" | sudo -S systemctl enable orbit-edge-codex
if [ $? -ne 0 ]; then echo "[WARNING] systemctl enable failed."; fi

echo "Restarting orbit-edge-codex service (requires sudo)..."
echo "$SUDO_PASSWORD" | sudo -S systemctl restart orbit-edge-codex
if [ $? -ne 0 ]; then echo "[WARNING] systemctl restart failed. Check 'sudo systemctl status orbit-edge-codex'."; fi

sleep 5 # Give service a moment to start

echo "Checking service status (requires sudo)..."
# --no-pager prevents the output from opening in 'less'
echo "$SUDO_PASSWORD" | sudo -S systemctl status orbit-edge-codex --no-pager


# Install media server (as codex)
# Ensure we are in the project root before trying to find media server script
cd "$PROJECT_ROOT_DIR" || { echo "[ERROR] Failed to cd back to project root '$PROJECT_ROOT_DIR'."; exit 1; }
MEDIA_SERVER_SCRIPT_PATH="$PROJECT_ROOT_DIR/scripts/mediaserver/install_media_server.sh"
MEDIA_SERVER_DIR=$(dirname "$MEDIA_SERVER_SCRIPT_PATH")

if [ -f "$MEDIA_SERVER_SCRIPT_PATH" ]; then
  echo "Found media server install script. Running it as user 'codex'..."
  # --- MODIFIED: Use sudo -u codex to execute media server script, ensure PATH ---
  # Corepack should be active for the codex user
  echo "$SUDO_PASSWORD" | sudo -S -u codex bash -c "
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH; # Ensure standard paths including where nodejs installed
    export HOME=/home/codex; # Ensure HOME is correct
    # Corepack should now be active and manage 'npm' calls if used by the script

    echo 'Current PATH (inside media server sudo -u bash -c): \$PATH'; # Debugging
    cd '$MEDIA_SERVER_DIR' || exit 1; # Change to media server script dir
    chmod +x install_media_server.sh;
    echo '--- Running install_media_server.sh as codex via sudo -u ---';
    ./install_media_server.sh; # This script itself may use node/npm via corepack or use sudo if needed
    echo '--- install_media_server.sh finished ---';
  "
  MEDIA_SERVER_STATUS=$?
  if [ $MEDIA_SERVER_STATUS -ne 0 ]; then
      echo "[WARNING] Media server installation script failed."
  fi
  # Change back to project root after the sudo -u command finishes
  cd "$PROJECT_ROOT_DIR" || { echo "[ERROR] Failed to cd back to project root after media server install."; exit 1; }

else
  echo "install_media_server.sh not found at '$MEDIA_ROOT_DIR/install_media_server.sh'; skipping media server setup."
fi

echo "--- Dependency setup script (install_deps.sh) finished at $(date) ---"
