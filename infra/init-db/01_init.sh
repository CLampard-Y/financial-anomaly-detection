#!/bin/bash
# ====================================
# Automatically created business database upon container startup
# ====================================
# This separates airflow metadata from actual business data
# Usage: Navigate to the script directory first, then run: bash 01_init.sh

set -e

echo ">>> Creating business database 'crypto_data'..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS crypto_data;
    GRANT ALL PRIVILEGES ON DATABASE crypto_data TO airflow;
EOSQL

echo ">>> Database 'crypto_data' created successfully."