# ================================================
# Data Retention DAG - Archive and Purge Old Price Data
# ================================================
# Clean data regularly
# Archive turn into CSV first, then delete from DB

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from datetime import datetime, timedelta
import os

# ----------------------------------------------
# 1. Configuration
# ----------------------------------------------
# store data for 365 days
RETENTION_DAYS = 365 

# archive file storage path
ARCHIVE_PATH = "/opt/airflow/logs/archive"

default_args = {
    'owner': 'CLampard',
    'depends_on_past': False,
    'email_on_failure': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Define function: archive and purge data from DB
def archive_and_purge(**context):
    # connect to DB by PostgresHook (provided by Airflow)
    pg_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Step 1: calculate cut-off date
    cutoff_date = (datetime.now() - timedelta(days=RETENTION_DAYS)).strftime('%Y-%m-%d')
    print(f"Executing Retention Policy. Cutoff Date: {cutoff_date}")
    
    # Step 2: export old data to CSV
    if not os.path.exists(ARCHIVE_PATH):
        os.makedirs(ARCHIVE_PATH)
    
    # Name with date (e.g. crypto_prices_2023-01-01.csv)
    file_name = f"{ARCHIVE_PATH}/crypto_prices_{cutoff_date}.csv"
    
    # load-out by COPY command
    sql_export = f"SELECT * FROM crypto_prices WHERE captured_at < '{cutoff_date}'"
    conn = pg_hook.get_conn()
    cursor = conn.cursor()
    
    # load-out by COPY command
    with open(file_name, 'w') as f:
        cursor.copy_expert(f"COPY ({sql_export}) TO STDOUT WITH CSV HEADER", f)
    
    print(f"Archived cold data to: {file_name}")
    
    # Step 3: delete old data from DB
    sql_delete = f"DELETE FROM crypto_prices WHERE captured_at < '{cutoff_date}'"
    cursor.execute(sql_delete)
    conn.commit()
    
    # count deleted rows
    rows_deleted = cursor.rowcount
    print(f"Purged {rows_deleted} rows from Postgres.")
    
    cursor.close()
    conn.close()


# ------------------------------------------------
# 2. DAG Definition
# ------------------------------------------------
with DAG(
    'system_data_retention',    #DAG ID
    default_args=default_args,
    description='Lifecycle Management: Archive cold data and purge from DB',

    # run every day at 8:00 (Beijing Time - UTC+8)
    schedule_interval='0 0 * * *', 
    start_date=datetime(2023, 1, 1),

    # Not catchup: run only once
    catchup=False,
    tags=['maintenance', 'CL'],
) as dag:
    
    task_archive_purge = PythonOperator(
        task_id='archive_and_purge_cold_data',
        python_callable=archive_and_purge
    )
