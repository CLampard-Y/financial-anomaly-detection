#!/bin/bash
# =========================================
# Worker Node Deployment Script
# =========================================
# Run in Airflow container (US), send to HK/JP nodes (SSH)
# Usage: bash deploy_workers.sh
# Prerequisites:
#   1. User must be in docker group: sudo usermod -aG docker $USER
#   2. SSH keys configured for HK/JP nodes: ssh-copy-id root@<NODE_IP>
#   3. .env file with HK_IP and JP_IP variables
# =========================================

set -e

# Resolve project root (script lives in scripts/)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT"

# -----------------------------------------
# 1. Load .env and get IPs
# -----------------------------------------
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "Error: .env file not found in project root."
    exit 1
fi

if [ -z "$HK_IP" ] || [ -z "$JP_IP" ]; then
    echo "Error: HK_IP or JP_IP not set in .env"
    exit 1
fi

# -----------------------------------------
# 2. Distribute to HK/JP nodes
# -----------------------------------------
echo ">>> Starting Worker Deployment Pipeline..."
cd "$PROJECT_ROOT"

# Build crawler image
echo ">>> Building Crawler Image..."
docker build -t binance-crawler ./crawler

# Export image to tar
echo ">>> Exporting Image to tar..."
docker save -o crawler.tar binance-crawler

# Define function: deploy to node
deploy_to_node() {
    local NODE_IP=$1
    local NODE_NAME=$2
    
    echo "---------------------------------"
    echo ">>> Deploying to $NODE_NAME ($NODE_IP)..."
    
    # Ensure target directory exists on worker node
    echo "  Checking if /home/DFS_Worker exists on $NODE_NAME..."
    ssh root@$NODE_IP "mkdir -p /home/DFS_Worker"
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Directory ready on $NODE_NAME"
    else
        echo "  ✗ Failed to create directory on $NODE_NAME"
        return 1
    fi
    
    # Upload tar to node
    echo "  Uploading crawler image to $NODE_NAME..."
    scp crawler.tar root@$NODE_IP:/home/DFS_Worker/
    
    if [ $? -ne 0 ]; then
        echo "  ✗ Failed to upload image to $NODE_NAME"
        return 1
    fi
    
    # Load image to node
    echo "  Loading image on $NODE_NAME..."
    ssh root@$NODE_IP "docker load -i /home/DFS_Worker/crawler.tar"
    
    if [ $? -eq 0 ]; then
        echo "  ✓ $NODE_NAME deployment completed successfully!"
    else
        echo "  ✗ Failed to load image on $NODE_NAME"
        return 1
    fi
}

# Deploy to HK/JP nodes
deploy_to_node $HK_IP "HK-Primary"
deploy_to_node $JP_IP "JP-Backup"

# Clean up
rm crawler.tar
echo " Cleaned up local artifacts."

echo " All Workers Deployed Successfully!"