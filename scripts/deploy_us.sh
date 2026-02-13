#!/bin/bash
# =========================================
# US Master Server Deployment Script
# =========================================
# Complete initialization for Distributed Financial Sentinel
# Usage: bash deploy_us.sh
# Prerequisites:
#   1. User must be in docker group: sudo usermod -aG docker $USER
#   2. User must own project directory: sudo chown -R $USER:$USER /opt/data-pipeline
#   3. Git credentials configured (SSH key or HTTPS token)
# =========================================

set -e

# -----------------------------------------
# 0. Check prerequisites
# -----------------------------------------
# Check if in git repository
if [ ! -d .git ]; then
    echo "Error: Not in a git repository."
    echo "Please run this script from project root."
    exit 1
fi

echo ">>> Starting US Master Deployment..."

# -----------------------------------------
# 1. Get latest code from GitHub
# -----------------------------------------
echo ">>> Pulling latest code from GitHub..."
git pull

# -----------------------------------------
# 2. Exam .env file
# -----------------------------------------
if [ ! -f .env ]; then
    echo "Error: .env file not found."
    exit 1
fi

# -----------------------------------------
# 3. Restart Infrastructure
# -----------------------------------------
# --build: rebuild images if Dockerfile changed
echo ">>> Restarting Infrastructure..."
docker compose up -d --build

echo "✅ US Master Deployed!"