#!/bin/bash
# Server Initialization Script
# Usage: ./setup_server_env.sh

echo ">>> Starting Server Initialization..."

# 1. System Update
echo ">>> Updating system packages..."
apt-get update && apt-get upgrade -y

# 2. Install Docker & Docker Compose
if ! command -v docker &> /dev/null
then
    echo ">>> Docker not found. Installing..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
else
    echo ">>> Docker already installed."
fi

# 3. SSH Key Generation (Master Node Only)
# Warning: Do not run this on Worker nodes if keys already exist
if [ ! -f ~/.ssh/id_rsa ]; then
    echo ">>> Generating SSH keys for Master node..."
    ssh-keygen -t rsa -b 4096 -C "airflow-master" -f ~/.ssh/id_rsa -N ""
    echo ">>> SSH Keys generated."
else
    echo ">>> SSH Keys already exist. Skipping."
fi

echo ">>> Initialization Complete. Please configure 'known_hosts' manually for security."