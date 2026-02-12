# ============================================
# Main Crawler Script: Rewrite construction and DB write logic
# Run in Airflow container
# ============================================
import os
import json
import ccxt
import psycopg2
import time
from datetime import datetime


# --------------------------------------------
# 1. Read server & API information from .env
# Prevent hard-coded code
# --------------------------------------------
# US Server information
DB_HOST = os.getenv("DB_HOST")                  # IP
DB_PORT = os.getenv("DB_PORT", "5432")          # database port
DB_NAME = os.getenv("DB_NAME", "crypto_data")   # database name
DB_USER = os.getenv("DB_USER", "airflow")       # database user
DB_PASS = os.getenv("DB_PASS", "airflow")       # database password

# Key information : Source region
SOURCE_REGION = os.getenv("SOURCE_REGION", "UNKNOWN")


# Catch BTC, ETH, SOL, DOGE 
DEFAULT_SYMBOLS = ['BTC/USDT', 'ETH/USDT', 'SOL/USDT', 'DOGE/USDT']
TIMEFRAME = '1h'    # 1 hour k lines

def get_target_symbols():
    # Get TARGET_SYMBOLS from .env
    env_sym = os.getenv("TARGET_SYMBOL")
    if env_sym:
        try:
            return json.loads(env_sym)
        except:
            print(f"Warning: Invalid JSON in TARGET_SYMBOLS, using default.")
            return DEFAULT_SYMBOLS
    return DEFAULT_SYMBOLS

# --------------------------------------------
# 2. Function:Fetch data
# Fetch data from Binance Global by CCXT
# --------------------------------------------
def fetch_binance_klines():
    print(f"[{SOURCE_REGION}] Initializing Binance Connection via CCXT (Routed)...")
    
    # Initialize Binance connection (redirect to data-api)
    exchange = ccxt.binance({
        'enableRateLimit': True,
        'options': {
            'defaultType': 'spot',
            'adjustForTimeDifference': False, # [关键] 禁用时间同步，防止请求被墙的接口
        },
        'urls': {
            'api': {
                # Enfore all API requests to data-api 
                'public': 'https://data-api.binance.vision/api/v3',
                'private': 'https://data-api.binance.vision/api/v3',
                'fapiPublic': 'https://data-api.binance.vision/api/v3',
                'fapiPrivate': 'https://data-api.binance.vision/api/v3',
                'dapiPublic': 'https://data-api.binance.vision/api/v3',
                'dapiPrivate': 'https://data-api.binance.vision/api/v3',
            }
        }
    })
    
    symbols = get_target_symbols()
    all_data = []

    for symbol in symbols:
        try:
            print(f"[{SOURCE_REGION}] Fetching {symbol} OHLCV...")
            
            # Key: Download  latest 24 hours candles
            # The most efficient way to get all data
            # Even crawler down few hours, next run will automatically fill in the gaps
            ohlcv = exchange.fetch_ohlcv(symbol, TIMEFRAME, limit=24)
            
            if not ohlcv:
                print(f"Warning: No data returned for {symbol}")
                continue

            # CCXT data structure:
            # [
            #     [open_time, open, high, low, close, volume],
            #     [open_time, open, high, low, close, volume],
            # ...
            # ]
            for candle in ohlcv:
                record = {
                    'symbol': symbol,
                    'interval': TIMEFRAME,
                    'open_time': candle[0],     # Unix timestamp (in milliseconds)
                    'open': candle[1],
                    'high': candle[2],
                    'low': candle[3],
                    'close': candle[4],
                    'volume': candle[5],
                    'close_time': candle[0] + 3600000 - 1, 
                    'raw': json.dumps(candle) # Store raw data
                }
                all_data.append(record)
                
        except Exception as e:
            print(f"Error fetching {symbol}: {e}")
            # [Failover Trigger]
            # 这里必须抛出异常，Airflow 才能捕获失败，从而触发切换日本节点！
            raise e 

    return all_data

# --------------------------------------------
# 3. Funciton: Idempotent upsert to DB (Postgres)
# --------------------------------------------
def save_to_db(data_list):
    if not data_list:
        print("No data to save.")
        return

    try:
        with psycopg2.connect(
            host=DB_HOST, 
            port=DB_PORT, 
            database=DB_NAME, 
            user=DB_USER, 
            password=DB_PASS
        ) as conn:
            cur = conn.cursor()
            
            # Upsert SQL
            # ON CONFLICT DO UPDATE: if data exists, update source_region
            # This means: if HK and JP both crawled data, the database will retain the last source tag
            sql = """
                INSERT INTO binance_klines 
                (symbol, interval_type, open_time, close_time, 
                open_price, high_price, low_price, close_price, volume, 
                source_region, raw_payload)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (symbol, interval_type, open_time) 
                DO UPDATE SET
                    source_region = EXCLUDED.source_region,
                    volume = EXCLUDED.volume,
                    updated_at = CURRENT_TIMESTAMP
            """
            
            inserted_count = 0
            for d in data_list:
                cur.execute(sql, (
                    d['symbol'], d['interval'], d['open_time'], d['close_time'],
                    d['open'], d['high'], d['low'], d['close'], d['volume'],
                    SOURCE_REGION, d['raw']
                ))
                inserted_count += 1
                
            conn.commit()
            cur.close()
            print(f"[{SOURCE_REGION}] Successfully upserted {inserted_count} Kline records to US DB.")
        
    except Exception as e:
        print(f"Database Error: {e}")
        # Database connection failed usually means US Master is down or firewall blocked
        raise e
    
if __name__ == "__main__":
    print(f"Starting Crawler. Region: {SOURCE_REGION}")
    
    # Safety Check: Ensure not running on US Master
    if 'US-Master' in SOURCE_REGION and os.getenv("TEST_MODE") != "true":
        print("Warning: Running on US Master. Ensure this is intentional.")

    try:
        data = fetch_binance_klines()
        save_to_db(data)
    except Exception as e:
        print("Crawler Execution Failed!")

        # return non-zero status code t
        # Inform Airflow that task failed
        exit(1) 
