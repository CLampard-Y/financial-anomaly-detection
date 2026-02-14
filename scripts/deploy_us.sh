#!/bin/bash
# =========================================
# US Master Server - One-Click Deployment
# =========================================
# Fully automated deployment for Distributed Financial Sentinel
# Usage: bash scripts/deploy_us.sh
# Prerequisite: Docker & Docker Compose installed
#   (or run infra/setup_server_env.sh first on a fresh server)
# =========================================

set -e

# Resolve project root (script lives in scripts/)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT"

echo ">>> Starting US Master One-Click Deployment..."
echo ">>> Project root: $(pwd)"

# -----------------------------------------
# 0. Prerequisites Check
# -----------------------------------------
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed."
    echo "  Run: curl -fsSL https://get.docker.com | sh"
    echo "  Or run: bash infra/setup_server_env.sh"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "Error: Docker Compose plugin is not installed."
    echo "  Run: apt-get install -y docker-compose-plugin"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not running or permission denied."
    echo "  Run: sudo systemctl start docker && sudo usermod -aG docker \$USER"
    exit 1
fi

echo "[OK] Docker & Docker Compose detected."

# -----------------------------------------
# 1. Pull latest code (skip if not a git repo, e.g. first deploy)
# -----------------------------------------
if [ -d .git ]; then
    echo ">>> Pulling latest code from GitHub..."
    git pull || echo "Warning: git pull failed, continuing with local code."
else
    echo ">>> Not a git repo, skipping git pull."
fi

# -----------------------------------------
# 2. Ensure .env exists
# -----------------------------------------
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        echo ">>> .env not found. Copying from .env.example..."
        cp .env.example .env
        echo "[WARN] Please review and edit .env with your actual credentials."
    else
        echo ">>> .env not found. Generating default .env..."
        cat > .env << 'ENVEOF'
# === Distributed Financial Sentinel Environment ===
POSTGRES_USER=airflow
POSTGRES_PASSWORD=airflow
POSTGRES_DB=airflow
AIRFLOW_FERNET_KEY=
HK_IP=
JP_IP=
US_IP=
ENVEOF
        echo "[WARN] Default .env created. Please fill in AIRFLOW_FERNET_KEY, HK_IP, JP_IP, US_IP."
    fi
fi

# -----------------------------------------
# 3. Create required data directories
# -----------------------------------------
echo ">>> Creating data directories..."
mkdir -p data/postgres
mkdir -p airflow/logs
mkdir -p airflow/plugins
mkdir -p data_lake/binance_data_lake

# Set Postgres data dir permissions (required by postgres image)
chmod 700 data/postgres

# -----------------------------------------
# 4. Start Infrastructure
# -----------------------------------------
echo ">>> Starting Docker services..."
docker compose up -d --build

# -----------------------------------------
# 5. Health Check
# -----------------------------------------
echo ">>> Waiting for services to initialize..."
sleep 10

if docker compose ps | grep -q "healthy\|running"; then
    echo ""
    echo "=========================================="
    echo "  US Master Deployed Successfully!"
    echo "=========================================="
    echo "  Airflow UI: http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost'):8080"
    echo "  PostgreSQL: localhost:5432"
    echo "=========================================="
else
    echo "[WARN] Some services may not be healthy. Check with: docker compose ps"
fi