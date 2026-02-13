# ==========================================
#   Maintenance DAG for Binance Global OHLCV
# ==========================================
# 

RETENTION_DAYS = 365

default_args = {
    'owner': 'data_engineer',
    'depends_on_past': False,
    'email_on_failure': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

with DAG(

    tags=['binance', 'maintenance', 'nomal', 'CLEAN'],
) as dag: