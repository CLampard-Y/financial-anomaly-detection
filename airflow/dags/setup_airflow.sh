#!/bin/bash
# =========================================
# Airflow Connection Setup Script
# =========================================
# Run inside Airflow container
# Usage: docker exec -i airflow-scheduler bash < scripts/setup_connections.sh

set -e

echo ">>> Registering HK & JP Worker Connections..."

# -----------------------------------------
# 1. Register connection (HK)
# -----------------------------------------
# Use --ssh-private-key to point to the mounted path inside the container:
# Docker-compose: /root/.ssh:/home/airflow/.ssh:ro
# Note: Passwords and sensitive information should be passed via environment variables
airflow connections add 'ssh_hk' \
    --conn-type 'ssh' \
    --conn-host "${HK_IP:-<HK_IP>}" \
    --conn-login 'root' \
    --conn-extra '{"key_file": "/home/airflow/.ssh/id_rsa", "no_host_key_check": true}'

# -----------------------------------------
# 2. Register connection (JP)
# -----------------------------------------
airflow connections add 'ssh_jp' \
    --conn-type 'ssh' \
    --conn-host "${JP_IP:-<JP_IP>}" \
    --conn-login 'root' \
    --conn-extra '{"key_file": "/home/airflow/.ssh/id_rsa", "no_host_key_check": true}'

echo ">>> All connections registered successfully."