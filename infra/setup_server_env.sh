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
# 1. System Update & Base Dependencies
# ----------------------------------------
# Smart detection: skip heavy apt-get upgrade if Docker is already present
# (indicates Server-Ops Layer 1 or prior setup has already run)
if command -v docker &> /dev/null && command -v curl &> /dev/null && command -v ufw &> /dev/null; then
    echo "[1/8] Base environment detected (Docker + core tools present). Skipping system upgrade."
else
    echo "[1/8] Updating system and installing base dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

    # Install essential packages that may be missing on minimal installations
    apt-get install -y \
        curl \
        git \
        openssh-client \
        openssl \
        ufw \
        ca-certificates \
        gnupg \
        lsb-release

echo "Base dependencies installed."
fi

# ----------------------------------------
# 2. Install Docker & Docker Compose
# ----------------------------------------
if ! command -v docker &> /dev/null; then
    echo "[2/8] Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh

    # Ensure Docker daemon is started and enabled on boot
    systemctl start docker
    systemctl enable docker
    echo "Docker installed and started."
else
    echo "[2/8] Docker already installed."
    # Ensure daemon is running even if Docker was pre-installed
    systemctl start docker 2>/dev/null || true
fi

# Verify Docker Compose plugin is available
if ! docker compose version &> /dev/null; then
    echo "Installing Docker Compose plugin..."
    apt-get install -y docker-compose-plugin
fi
echo "Docker Compose version: $(docker compose version --short)"

# ----------------------------------------
# 3. Generate SSH Keys
# ----------------------------------------
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "[3/8] Generating SSH keys..."

    ssh-keygen -t rsa -b 4096 -C "airflow-master" -f ~/.ssh/id_rsa -N ""

    # Set secure permissions for SSH private key
    chmod 600 ~/.ssh/id_rsa
    echo "SSH private key permissions set to 600 (owner read/write only)"
else
    echo "[3/8] SSH keys already exist."
fi

# ----------------------------------------
# 4. Configure SSH to Worker Nodes
# ----------------------------------------
echo "[4/8] Configuring SSH to worker nodes..."
echo "Enter HK node IP address:"
read HK_IP
echo "Enter JP node IP address:"
read JP_IP

# Pre-populate known_hosts BEFORE ssh-copy-id to avoid interactive prompt
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
echo "[5/8] Configuring UFW firewall..."
ufw --force enable
ufw allow 19140/tcp                                  # SSH port
ufw allow 8080/tcp                                   # Airflow Web UI
ufw allow from $HK_IP to any port 5432 proto tcp     # PostgreSQL for HK
ufw allow from $JP_IP to any port 5432 proto tcp     # PostgreSQL for JP
echo "Firewall configured."

# ----------------------------------------
# 6. Generate Fernet Key & Create .env
# ----------------------------------------
echo "[6/8] Generating Fernet key and creating .env file..."

# Resolve project root: script is in infra/, project root is one level up
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT"
echo "Project root: $(pwd)"

# Prompt for PostgreSQL password
echo ""
echo "==================================="
echo "Database Configuration"
echo "==================================="
echo "Enter PostgreSQL password for user 'airflow':"
echo ""
echo "⚠️  IMPORTANT: Avoid these special characters in password:"
echo "   @ : / # ? & = (they break database connection URLs)"
echo ""
echo "✓  Recommended: Use only letters, numbers, underscore, hyphen"
echo "   Example: airflow123, my_secure_pass, data-2024"
echo ""
read -s POSTGRES_PASSWORD
echo ""
echo "Confirm password:"
read -s POSTGRES_PASSWORD_CONFIRM
echo ""

# Validate password match
if [ "$POSTGRES_PASSWORD" != "$POSTGRES_PASSWORD_CONFIRM" ]; then
    echo "✗ Error: Passwords do not match!"
    exit 1
fi

# Validate password does not contain problematic characters
if [[ "$POSTGRES_PASSWORD" =~ [@:/\#\?\&=] ]]; then
    echo "✗ Error: Password contains special characters that will cause connection issues!"
    echo "  Detected: @ : / # ? & or ="
    echo "  Please use only: a-z A-Z 0-9 _ -"
    exit 1
fi

echo "✓ Password validated successfully"

# Generate Fernet key
echo "Generating Fernet encryption key..."
FERNET_KEY=$(docker run --rm apache/airflow:2.7.1 python -c \
  "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" | tr -d '\n\r')

# Validate Fernet key was generated
if [ -z "$FERNET_KEY" ]; then
    echo "✗ Error: Failed to generate Fernet key"
    exit 1
fi

echo "✓ Fernet key generated successfully"

# Create .env file with proper formatting
cat > .env << EOF
POSTGRES_USER=airflow
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=airflow
AIRFLOW_FERNET_KEY=$FERNET_KEY
HK_IP=$HK_IP
JP_IP=$JP_IP
US_IP=$(hostname -I | awk '{print $1}')
EOF

chmod 600 .env
echo ".env file created with secure permissions (600)"

# ----------------------------------------
# 7. Start Infrastructure
# ----------------------------------------
echo "[7/8] Starting Docker services..."

# Create required data directories (all within project root for isolation)
echo "Creating data directories in project root: $(pwd)"
mkdir -p data/postgres
mkdir -p airflow/logs
mkdir -p airflow/plugins
mkdir -p data_lake/binance_data_lake

# Set PostgreSQL data directory permissions (required by postgres image)
chmod 700 data/postgres

# CRITICAL: Airflow container runs as UID 50000 (airflow user)
# Must set ownership for logs and plugins to avoid permission errors
echo "Setting Airflow directory ownership (UID 50000)..."
chown -R 50000:50000 airflow/logs
chown -R 50000:50000 airflow/plugins

echo "✓ All data directories created and secured within: $(pwd)"

# Pull latest images
docker compose pull

# ----------------------------------------
# CRITICAL: Start PostgreSQL first, then initialize Airflow database
# ----------------------------------------
echo "Starting PostgreSQL container..."
docker compose up -d postgres

# Wait for postgres container to be healthy (max 60 seconds)
echo "Waiting for PostgreSQL to be fully ready..."
RETRY_COUNT=0
MAX_RETRIES=12
until docker exec pipeline-db pg_isready -U airflow > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "✗ PostgreSQL failed to start after 60 seconds"
        echo "  Check logs: docker logs pipeline-db"
        exit 1
    fi
    echo "  Waiting for PostgreSQL... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 5
done

# Verify crypto database was created by init script
echo "Verifying business database 'crypto' exists..."
sleep 3  # Give init script time to complete
docker exec pipeline-db psql -U airflow -lqt | cut -d \| -f 1 | grep -qw crypto
if [ $? -eq 0 ]; then
    echo "✓ Business database 'crypto' initialized successfully"
else
    echo "✗ Warning: Business database 'crypto' not found"
    echo "  Init script may have failed. Check logs with: docker logs pipeline-db"
fi

# ----------------------------------------
# Initialize Airflow metadata database BEFORE starting services
# ----------------------------------------
echo "Initializing Airflow metadata database..."
echo "  This will create all required tables in the 'airflow' database..."

# Use 'docker compose run' to execute one-time initialization
# This creates a temporary container, runs the command, and exits
docker compose run --rm airflow-webserver airflow db migrate

if [ $? -ne 0 ]; then
    echo "✗ Airflow database migration failed!"
    echo "  Check connection string in .env file"
    echo "  Ensure password does not contain special characters: @ : / # ? &"
    exit 1
fi

echo "✓ Airflow metadata database initialized successfully"

# ----------------------------------------
# Now start all Airflow services
# ----------------------------------------
echo "Starting Airflow services (webserver and scheduler)..."
docker compose up -d airflow-webserver airflow-scheduler

# Wait for services to be fully running
echo "Waiting for Airflow services to start..."
sleep 10

# Generate random admin password
ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

# Create Airflow admin user
echo "Creating Airflow admin user..."
docker exec airflow-webserver airflow users create \
  --username admin \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com \
  --password "$ADMIN_PASSWORD" 2>/dev/null || echo "  (User may already exist, skipping)"

# ----------------------------------------
# 8. Verify Database Initialization
# ----------------------------------------
echo "[8/8] Verifying deployment status..."

# Check Airflow database connection
echo "Checking Airflow database connection..."
docker exec airflow-webserver airflow db check > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Airflow metadata database connected successfully"
else
    echo "✗ Warning: Airflow database connection failed"
    echo "  Check logs: docker logs airflow-webserver"
fi

echo ""
echo "==================================="
echo "Setup Complete!"
echo "==================================="
echo "Airflow Web UI: http://$(hostname -I | awk '{print $1}'):8080"
echo ""
echo " IMPORTANT - Save credentials securely:"
echo "-----------------------------------"
echo "Airflow Admin Username: admin"
echo "Airflow Admin Password: $ADMIN_PASSWORD"
echo "-----------------------------------"
echo ""
echo "Database Status:"
echo "  - Airflow metadata: airflow"
echo "  - Business data: crypto (schema: crypto_data)"
echo ""
echo "Worker Nodes:"
echo "  - HK Node: $HK_IP"
echo "  - JP Node: $JP_IP"
echo "==================================="
