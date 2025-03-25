#!/bin/bash

# Define username and password
USERNAME="codex"
PASSWORD="codex"

# Check if the user already exists
if id "$USERNAME" &>/dev/null; then
    echo "User '$USERNAME' already exists."
    exit 1
fi

# Create the user and set the password
sudo useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | sudo chpasswd

# Add the user to the sudo group
sudo usermod -aG sudo "$USERNAME"

# Confirm user creation
echo "User '$USERNAME' created and added to sudo group."
id "$USERNAME"
