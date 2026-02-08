#!/bin/bash
# =================================
# US Master Server Setup Script
# =================================
# Complete initialization for Distributed Financial Sentinel
# Usage: bash setup_server_env.sh

set -e  # Exit on error

echo "==================================="
echo "US Master Server Setup"
echo "==================================="

# ----------------------------------------
# 1. System Update
# ----------------------------------------
echo "[1/7] Updating system packages..."
apt-get update && apt-get upgrade -y

# ----------------------------------------
# 2. Install Docker & Docker Compose
# ----------------------------------------
if ! command -v docker &> /dev/null; then
    echo "[2/7] Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
else
    echo "[2/7] Docker already installed."
fi

# ----------------------------------------
# 3. Generate SSH Keys
# ----------------------------------------
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "[3/7] Generating SSH keys..."


    ssh-keygen -t rsa -b 4096 -C "airflow-master" -f ~/.ssh/id_rsa -N ""

    # Set secure permissions for SSH private key:
    # Owner read/write only
    chmod 600 ~/.ssh/id_rsa
    echo "SSH private key permissions set to 600 (owner read/write only)"
else
    echo "[3/7] SSH keys already exist."
fi

# ----------------------------------------
# 4. Configure SSH to Worker Nodes
# ----------------------------------------
echo "[4/7] Configuring SSH to worker nodes..."
echo "Enter HK node IP address:"
read HK_IP
echo "Enter JP node IP address:"
read JP_IP

# Pre-populate known_hosts BEFORE ssh-copy-id to avoid interactive prompt:
# First SSH connection requires interactive prompt,disrupting the automation
echo "Adding worker nodes to known_hosts..."
ssh-keyscan -H $HK_IP >> ~/.ssh/known_hosts 2>/dev/null
ssh-keyscan -H $JP_IP >> ~/.ssh/known_hosts 2>/dev/null
chmod 644 ~/.ssh/known_hosts

# Copy SSH keys to worker nodes
echo "Copying SSH public key to HK node..."
ssh-copy-id -i ~/.ssh/id_rsa.pub root@$HK_IP

echo "Copying SSH public key to JP node..."
ssh-copy-id -i ~/.ssh/id_rsa.pub root@$JP_IP

# Verify passwordless SSH connections
echo "Verifying SSH connections..."
ssh -o StrictHostKeyChecking=no root@$HK_IP "echo 'HK Connection OK'"
ssh -o StrictHostKeyChecking=no root@$JP_IP "echo 'JP Connection OK'"

# Set secure permissions for .ssh directory
chmod 700 ~/.ssh
echo "SSH directory permissions secured (700)"

# ----------------------------------------
# 5. Configure Firewall
# ----------------------------------------
echo "[5/7] Configuring UFW firewall..."
ufw --force enable
ufw allow 22/tcp                                      # SSH
ufw allow 8080/tcp                                    # Airflow Web UI
ufw allow from $HK_IP to any port 5432 proto tcp     # PostgreSQL for HK
ufw allow from $JP_IP to any port 5432 proto tcp     # PostgreSQL for JP
echo "Firewall configured."

# ---------------------------------------
# 6. Generate Fernet Key & Create .env
# ---------------------------------------
echo "[6/7] Generating Fernet key and creating .env file..."
cd /opt/data-pipeline/infrastructure

FERNET_KEY=$(docker run --rm apache/airflow:2.7.1 python -c \
  "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")

cat > .env << EOF
POSTGRES_USER=airflow
POSTGRES_PASSWORD=airflow_secure_password_2024
FERNET_KEY=$FERNET_KEY
EOF

chmod 600 .env
echo ".env file created with secure permissions."

# ----------------------------------------
# 7. Start Infrastructure
# ----------------------------------------
echo "[7/7] Starting Docker services..."

# Pull latest images
docker compose pull

# Activate services
# -d: Detached mode (run in background)
docker compose up -d

# Wait for services to be healthy
sleep 15

# Create Airflow admin user
docker exec airflow-webserver airflow users create \
  --username admin \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com \
  --password admin_password_2024

echo ""
echo "==================================="
echo "Setup Complete!"
echo "==================================="
echo "Airflow Web UI: http://$(hostname -I | awk '{print $1}'):8080"
echo "Username: admin"
echo "Password: admin_password_2024"
echo ""
echo "HK Node: $HK_IP"
echo "JP Node: $JP_IP"
echo "==================================="