-- =====================================================
-- Schema Design: Business Data
-- Implement ELT (Extract, Load, Transform) strategy
-- =====================================================
-- This schema store cryptocurrency market data
-- run before following scripts (get in Postgres container):
-- docker exec -it pipeline-db psql -U airflow -d crypto_data

-- run the following scripts (in SQL Shell):

-- --------------------------------------
-- 1. Create Schema & Table
-- --------------------------------------
-- 初始化 保证幂等性
DROP SCHEMA IF EXISTS crypto_data CASCADE;
DROP TABLE IF EXISTS crypto_data.crypto_prices;

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
    -- Stores raw API payload for debugging or feature discovery
    raw_payload JSONB,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
};

-- --------------------------------------
-- 2. Create Indices (time, symbol, price_usd)
-- --------------------------------------
-- Create Indices to speed up queries
CREATE INDEX IF NOT EXISTS idx_crypto_time 
    ON crypto_data.crypto_prices (captured_at);
CREATE INDEX IF NOT EXISTS idx_crypto_symbol 
    ON crypto_data.crypto_prices (symbol);

-- GIN index (Sutable for JSONB)
CREATE INDEX IF NOT EXISTS idx_crypto_raw_payload 
    ON crypto_data.crypto_prices
    USING GIN (raw_payload);

-- --------------------------------------
-- Why delete price index
-- Price is floating point number
-- Price search is usually by range
-- The index is not useful for range search
-- Example: 
-- SELECT * FROM crypto_data.crypto_prices
--    WHERE price_usd > 100;
--
-- SELECT * FROM crypto_data.crypto_prices
--	  WHERE (price_usd < 200) && (price_usd > 150);
-- --------------------------------------

--CREATE INDEX idx_crypto_price_usd IF NOT EXISTS idx_crypto_price_usd 
--    ON crypto_data.crypto_prices (price_usd);





