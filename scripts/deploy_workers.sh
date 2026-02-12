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

# -----------------------------------------
# 1. Get IPs from .env
# -----------------------------------------
HK_IP=${HK_IP}
JP_IP=${JP_IP}

# -----------------------------------------
# 2. Disrtribute to HK/JP nodes
# -----------------------------------------
echo ">>> Starting Worker Deployment Pipeline..."

# Make sure in project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
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
    
    # Upload tar to node
    scp crawler.tar root@$NODE_IP:/home/DFS_Woker/
    
    # 远程加载镜像
    ssh root@$NODE_IP "docker load -i /home/DFS_Woker/crawler.tar"
    
    echo " $NODE_NAME Updated!"
}

# Deploy to HK/JP nodes
deploy_to_node $HK_IP "HK-Primary"
deploy_to_node $JP_IP "JP-Backup"

# Clean up
rm crawler.tar
echo " Cleaned up local artifacts."

echo " All Workers Deployed Successfully!"