#!/bin/bash
# ====================================
# Automatically initialize database
# ====================================
# This separates airflow metadata from actual business data
# Usage: Navigate to the script directory first, then run: bash 01_init.sh

set -e

# ----------------------------------------
# 1. Create Database
# ----------------------------------------
# -lqt: list databases and exit silently
# cut: extract first column (database name)
# grep: exact match
DB_EXISTS=$(psql -lqt | cut -d \| -f 1 | grep -qw crypto && echo "yes" || echo "no")

# Ensure idempotency
if [ "$DB_EXISTS" == "no" ]; then
    echo ">>> Database 'crypto' does not exist."
    echo ">>> Creating database 'crypto'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        CREATE DATABASE crypto;
EOSQL
else
    echo ">>> Database 'crypto' already exists."
fi

# Grant Permissions
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    GRANT ALL PRIVILEGES ON DATABASE crypto TO airflow;
EOSQL
echo ">>> Database 'crypto' created successfully."


# ----------------------------------------
# 2. Create schema & tables & indices
# ----------------------------------------
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    
    -- Create Schema
    CREATE SCHEMA IF NOT EXISTS crypto_data;

    -- Create Table
    CREATE TABLE IF NOT EXISTS crypto_klines(
        id SERIAL PRIMARY KEY,
        symbol VARCHAR(20) NOT NULL,    -- Currency Symbol (e.g. BTC, ETH, USDT )
        interval VARCHAR(5) NOT NULL,   -- Interval (e.g. 1m, 5m, 15m, 1h, 4h, 1d)

        -- Key price data
        -- Many digits, requires high precision
        open_price NUMERIC(18,8) NOT NULL,
        high_price NUMERIC(18,8) NOT NULL,
        low_price NUMERIC(18,8) NOT NULL,
        close_price NUMERIC(18,8) NOT NULL,
        volume NUMERIC(30,8),

        -- K line time range 
        open_time BIGINT NOT NULL,
        close_time BIGINT NOT NULL,

        -- Source worker tag
        -- 'HK-Primary' or 'JP-Backup'
        source_region VARCHAR(20) NOT NULL,

        -- Retention of raw data (JSONB)
        -- Stores raw API payload for debugging or feature discovery
        raw_payload JSONB,

        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

        -- Idemopotency
        -- Ensure uniqueness of same symbol, interval, and time
        UNIQUE (symbol, interval, open_time)
    );

    -- Create Indices
    CREATE INDEX idx_crypto_klines_symbol_time 
        ON crypto.crypto_klines(symbol, open_time DESC);
    CREATE INDEX idx_crypto_klines_source 
        ON crypto.crypto_klines (source_region);
EOSQL
