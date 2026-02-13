#!/bin/bash
set -e

# ====================================
# Automatically created business database upon container startup
# ====================================
# This separates airflow metadata from actual business data

echo ">>> Creating business database 'crypto_data'..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE crypto_data;
    GRANT ALL PRIVILEGES ON DATABASE crypto_data TO airflow;
EOSQL

echo ">>> Database 'crypto_data' created successfully."