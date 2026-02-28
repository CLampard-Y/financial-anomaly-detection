# ==========================================
# Data snapshot
# ==========================================
import os
from datetime import datetime
from pathlib import Path

import pandas as pd
import psycopg2

def _load_dotenv_if_present(dotenv_path: Path) -> None:
    """Load a local .env into os.environ (no extra dependency)."""

    if not dotenv_path.exists():
        return

    for raw_line in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def _get_db_dsn() -> str:
    """Return psycopg2 DSN/URI for the business database (crypto)."""

    database_url = os.getenv("DATABASE_URL")
    if database_url:
        return database_url

    host = (
        os.getenv("DFS_DB_HOST")
        or os.getenv("DB_HOST")
        or os.getenv("POSTGRES_HOST")
        or "localhost"
    )
    port = (
        os.getenv("DFS_DB_PORT")
        or os.getenv("DB_PORT")
        or os.getenv("POSTGRES_PORT")
        or "5432"
    )
    dbname = os.getenv("DFS_DB_NAME") or os.getenv("DB_NAME") or "crypto"
    user = (
        os.getenv("DFS_DB_USER")
        or os.getenv("DB_USER")
        or os.getenv("POSTGRES_USER")
        or "airflow"
    )
    password = (
        os.getenv("DFS_DB_PASS")
        or os.getenv("DB_PASS")
        or os.getenv("POSTGRES_PASSWORD")
    )
    if not password:
        raise RuntimeError(
            "Missing DB password. Set POSTGRES_PASSWORD (or DB_PASS/DFS_DB_PASS) "
            "in the environment or in the project root .env file."
        )

    return f"host={host} port={port} dbname={dbname} user={user} password={password}"

# Data lake directory (relative to project root for portability)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.join(SCRIPT_DIR, "..")
DATA_LAKE_DIR = os.path.join(PROJECT_ROOT, "data_lake", "binance_data_lake")

# Load secrets from repo root .env if present
_load_dotenv_if_present(Path(PROJECT_ROOT) / ".env")

# Export Postgres data to Parquet
# Use for tiered storage
def export_snapshot():
    print(">>> Starting Data Warehouse Snapshot...")
    try:
        dsn = _get_db_dsn()
        with psycopg2.connect(dsn) as conn:
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
    # Ensure data lake directory exists
    os.makedirs(DATA_LAKE_DIR, exist_ok=True)

    date_str = datetime.now().strftime('%Y%m%d')
    output_path = os.path.join(DATA_LAKE_DIR, f"snapshot_{date_str}.parquet")
    df.to_parquet(output_path, index=False)
    print(f" Data exported to Data Lake: {output_path}")

if __name__ == "__main__":
    export_snapshot()
