-- =====================================================
-- Schema Design: Business Data
-- =====================================================
-- This schema is used to store cryptocurrency market data
-- Run on the Postgres container
-- run before following scripts (get in Postgres container):
-- docker exec -it pipeline-db psql -U airflow -d crypto_data

-- run the following scripts (in SQL Shell):

-- --------------------------------------
-- 1. Create Table
-- --------------------------------------
-- Create Schema
CREATE SCHEMA IF NOT EXISTS crypto_data;

CREATE TABLE IF NOT EXISTS crypto_data.crypto_prices{
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(20) NOT NULL,    -- Currency Symbol (e.g. BTC, ETH, USDT )

    -- Many digits, requires high precision
    price_usd  DECIMAL(18,8) NOT NULL,  -- USD Price
    captured_at TIMESTAMP NOT NULL,     -- capture time
    
    -- Source worker tag
    -- 'HK-Primary' or 'JP-Backup'
    source_region VARCHAR(20) NOT NULL,
    
    -- Retention of raw data (JSONB)
    -- Stores the original JSON returned by the API
    -- Useful for troubleshooting or feature discovery
    raw_payload JSONB,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------
-- 2. Create Indices
-- --------------------------------------





