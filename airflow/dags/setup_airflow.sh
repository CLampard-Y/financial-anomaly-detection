#!/bin/bash
# =========================================
# Airflow Connection & DAG Activation Script
# =========================================
# Run inside Airflow container to:
#   1. Register SSH connections to HK/JP worker nodes
#   2. Register Postgres connection to crypto database
#   3. Activate (unpause) production DAGs
#
# Usage: docker exec -i airflow-scheduler bash < airflow/dags/setup_airflow.sh
# =========================================

set -e

echo "==========================================="
echo "  Airflow Connection & DAG Activation"
echo "==========================================="

# -----------------------------------------
# 1. Register SSH connection (HK)
# -----------------------------------------
echo ">>> [1/4] Registering SSH connection: ssh_hk..."
airflow connections delete 'ssh_hk' 2>/dev/null || true
airflow connections add 'ssh_hk' \
    --conn-type 'ssh' \
    --conn-host "${HK_IP:-<HK_IP>}" \
    --conn-login 'root' \
    --conn-extra '{"key_file": "/home/airflow/.ssh/id_rsa", "no_host_key_check": true}'
echo "    ssh_hk -> ${HK_IP:-<HK_IP>}"

# -----------------------------------------
# 2. Register SSH connection (JP)
# -----------------------------------------
echo ">>> [2/4] Registering SSH connection: ssh_jp..."
airflow connections delete 'ssh_jp' 2>/dev/null || true
airflow connections add 'ssh_jp' \
    --conn-type 'ssh' \
    --conn-host "${JP_IP:-<JP_IP>}" \
    --conn-login 'root' \
    --conn-extra '{"key_file": "/home/airflow/.ssh/id_rsa", "no_host_key_check": true}'
echo "    ssh_jp -> ${JP_IP:-<JP_IP>}"

# -----------------------------------------
# 3. Register Postgres connection (crypto DB)
# -----------------------------------------
# Both binance_dag.py and maintenance_dag.py use postgres_conn_id='postgres_default'
# This connection points to the crypto database (not the airflow metadata DB)
echo ">>> [3/4] Registering Postgres connection: postgres_default..."
airflow connections delete 'postgres_default' 2>/dev/null || true
airflow connections add 'postgres_default' \
    --conn-type 'postgres' \
    --conn-host 'postgres' \
    --conn-port '5432' \
    --conn-login "${POSTGRES_USER:-airflow}" \
    --conn-password "${POSTGRES_PASSWORD:-airflow}" \
    --conn-schema 'crypto'
echo "    postgres_default -> postgres:5432/crypto (user: ${POSTGRES_USER:-airflow})"

# -----------------------------------------
# 4. Activate (unpause) production DAGs
# -----------------------------------------
echo ">>> [4/4] Activating production DAGs..."

# Wait for scheduler to parse DAGs
sleep 5

# Unpause the main crawling DAG
airflow dags unpause binance_global_sentinel 2>/dev/null && \
    echo "    binance_global_sentinel -> ACTIVE" || \
    echo "    [WARN] binance_global_sentinel not found yet, unpause manually in UI"

# Unpause the maintenance DAG
airflow dags unpause maintenance_data 2>/dev/null && \
    echo "    maintenance_data -> ACTIVE" || \
    echo "    [WARN] maintenance_data not found yet, unpause manually in UI"

# -----------------------------------------
# Summary
# -----------------------------------------
echo ""
echo "==========================================="
echo "  All connections registered & DAGs activated!"
echo "==========================================="
echo "  Connections:"
echo "    - ssh_hk     -> ${HK_IP:-<HK_IP>}"
echo "    - ssh_jp     -> ${JP_IP:-<JP_IP>}"
echo "    - postgres_default -> postgres:5432/crypto"
echo ""
echo "  Active DAGs:"
echo "    - binance_global_sentinel (hourly crawl)"
echo "    - maintenance_data (daily cleanup)"
echo ""
echo "  Next steps:"
echo "    1. Open Airflow UI: http://<US_IP>:8080"
echo "    2. Verify DAGs are 'Active' (toggle ON)"
echo "    3. Trigger first run manually or wait for next hour"
echo "==========================================="