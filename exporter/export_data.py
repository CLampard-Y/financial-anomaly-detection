# ==========================================
# Data snapshot
# ==========================================
import pandas as pd
import psycopg2
import os
from datetime import datetime, timedelta

# Database connection
DB_URI = "host=localhost dbname=crypto_data user=airflow password=airflow"

# Data lake directory
DATA_LAKE_DIR = "/home/02_Distributed_Financial_Sentinel/data_lake/binance_data_lake"

# Export Postgres data to Parquet
# Use for tiered storage
def export_snapshot():
    print(">>> Starting Data Warehouse Snapshot...")
    try:
        with psycopg2.connect(DB_URI) as conn:
            # Query data from Postgres
            sql = """
                SELECT
                    symbol,
                    open_time,
                    close_price,
                    volume,
                    source_region
                FROM crypto_data.crypto_klines

                -- Filter data (24 hours ago)
                -- EPOCH FORM NOW (): return now time in milliseconds (timestamp)
                -- 86400000: 24 hours in milliseconds
                WHERE open_time > (EXTRACT(EPOCH FROM NOW()) * 1000 - 86400000)
            """
            df = pd.read_sql(sql, conn)
    except Exception:
        print(" DB Connection skipped in demo mode.")
        return

    if df.empty:
        print(" No data to export.")
        return

    # Data type optimization:
    #   Better read performance
    #   Smaller size in Parquet
    df['datetime'] = pd.to_datetime(df['open_time'], unit='ms')
    
    # Parquet: columnar storage
    # Faster than CSV
    date_str = datetime.now().strftime('%Y%m%d')
    output_path = os.path.join(DATA_LAKE_DIR, f"snapshot_{date_str}.parquet")
    df.to_parquet(output_path, index=False)
    print(f" Data exported to Data Lake: {output_path}")

if __name__ == "__main__":
    export_snapshot()