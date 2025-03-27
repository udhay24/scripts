#!/bin/bash

# Define repository details
GIT_USERNAME="udhay24"
REPO_URL="https://github.com/Smart-Stream-Technologies/Orbit-Edge-Codex.git"

# Ensure GIT_TOKEN is set
if [ -z "$GIT_TOKEN" ]; then
  echo "Error: GIT_TOKEN environment variable is not set!"
  exit 1
fi

sudo apt update

# Install git
sudo apt install git -y

# Configure Git credential storage
git config --global credential.helper store

# Store Git credentials securely
echo "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com" > ~/.git-credentials
chmod 600 ~/.git-credentials  # Secure the file

# Clone the repository
git clone "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com/Smart-Stream-Technologies/Orbit-Edge-Codex.git"

echo "Repository cloned successfully!"
