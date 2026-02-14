# ==========================================
#   Maintenance DAG for Binance Global OHLCV
# ==========================================
# This DAG performs daily database maintenance tasks:
#   1. Delete old data beyond retention period (365 days)
#   2. Vacuum and analyze table to reclaim storage and update statistics
#
# Schedule: Daily at 00:00 UTC
# Purpose: Keep database healthy and prevent storage bloat
# ==========================================

from airflow import DAG
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.operators.empty import EmptyOperator
from airflow.utils.dates import days_ago
from datetime import timedelta

# ------------------------------------------
# 1. Configuration
# ------------------------------------------
RETENTION_DAYS = 365  # Keep data for 1 year

default_args = {
    'owner': 'data_engineer',
    'depends_on_past': False,
    'email_on_failure': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    'maintenance_data',
    default_args = default_args,
    description = 'Maintenance DAG for Binance Global OHLCV',
    schedule_interval = '0 0 * * *',  # Run every day
    start_date = days_ago(1),
    catchup = False,
    tags=['binance', 'maintenance', 'nomal', 'CLEAN'],
) as dag:
    
    # Start tag
    start = EmptyOperator(task_id='start')

    # [Task 1]. Delete old data
    # Logic: delete data ('open_time' older than RETENTION_DAYS)
    # Attention: 'open_time' is BIGINT (ms), need conversion
    task_delete_old_date = PostgresOperator(
        task_id = 'task_delete_old_data',
        postgres_conn_id = 'postgres_default',
        sql = """
            DELETE FROM crypto_data.crypto_klines
            WHERE open_time < (
                EXTRACT(EPOCH FROM NOW()) * 1000 - %(retention_days)s * 86400000
            )
        """,
        parameters = {'retention_days': RETENTION_DAYS}
    )

    # [Task 2]. Vacuum database
    task_vacuum_db = PostgresOperator(
        task_id = 'task_vacuum_db',
        postgres_conn_id = 'postgres_default',
        sql = """
            VACUUM ANALYZE crypto_data.crypto_klines
        """,
        # Vacuum need to run in autocommit mode
        autocommit = True
    )

    end = EmptyOperator(task_id='end')

    # Dependency graph
    start >> task_delete_old_date
    task_delete_old_date >> task_vacuum_db
    task_vacuum_db >> end

