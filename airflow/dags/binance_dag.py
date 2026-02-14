# ==========================================
#   Core DAG for Binance Global OHLCV
# ==========================================
# This DAG crawls Binance Global OHLCV data

from airflow import DAG
import os
from airflow.providers.ssh.operators.ssh import SSHOperator
from airflow.operators.python import PythonOperator
from airflow.operators.empty import EmptyOperator
from airflow.utils.dates import days_ago
from airflow.utils.trigger_rule import TriggerRule
from airflow.models import Variable
from airflow.hooks.postgres_hook import PostgresHook
from datetime import timedelta
import json
import requests

# ------------------------------------------
# 1. Configuration
# ------------------------------------------
# Get configuration from environment (passed via docker-compose.yaml)
US_IP = os.getenv("US_IP")
DB_PASS = os.getenv("POSTGRES_PASSWORD", "airflow")

# Default parameters
default_args = {
    'owner': 'data_engineer',
    'depends_on_past': False,
    'email_on_failure': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
}

# ------------------------------------------
# 2. Def funciton: check failover and send alert
# ------------------------------------------
# Check latest data source
# If source is Backup, send alert
def check_failover_and_alert():

    pg_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # SQL : Query binance_klines table
    sql = """
        SELECT source_region, symbol, close_price 
        FROM crypto_data.crypto_klines
        ORDER BY created_at DESC 
        LIMIT 1
    """
    records = pg_hook.get_records(sql)
    
    if records:
        source, symbol, price = records[0]
        print(f"Audit: Latest data from {source}")
        
        # If source is Backup
        if 'Backup' in source:
            msg = f" [Failover Alert] Main woker node offline! Switch to {source}。\nSymbol: {symbol}\nPrice: {price}"
            print(msg)
            # Send alert to webhook if needed
            # requests.post(WEBHOOK_URL, json={"msg_type": "text", "content": {"text": msg}})

# ------------------------------------------
# 3. DAG definition
# ------------------------------------------
with DAG(
    'binance_global_sentinel',        # DAG Name
    default_args = default_args,
    description = 'Pipeline for Binance Global OHLCV',
    schedule_interval = '0 * * * *',  # Run every hour
    start_date = days_ago(1),         # Crawl data from yesterday
    catchup = False,
    tags=['binance', 'production', 'critical', 'ELT'],
) as dag:

    # Start tag
    start = EmptyOperator(task_id='start')
    
            # [Docker Command]
    # Runs binance-crawler container on remote worker node
    # NOTE: No comments or blank lines allowed inside the command string!
    #       SSHOperator sends this as a raw shell command to remote nodes.
    cmd_template = (
        "docker run --rm"
        " -e DB_HOST={db_host}"
        " -e DB_NAME=crypto"
        " -e DB_PASS={db_pass}"
        " -e SOURCE_REGION={region}"
        " binance-crawler"
    )
    # [Task 1]. HK Primary Node   
    task_crawl_hk = SSHOperator(
        task_id='crawl_primary_hk',
        ssh_conn_id='ssh_hk', # Same as the added connection
        command=cmd_template.format(db_host=US_IP, db_pass=DB_PASS, region='HK-Primary'),
        cmd_timeout=300 # timeout: 300 sec (5 min)
    )

    # [Task 2]. JP Backup Node (Failover)
    task_crawl_jp = SSHOperator(
        task_id='crawl_backup_jp',
        ssh_conn_id='ssh_jp',
        command=cmd_template.format(db_host=US_IP, db_pass=DB_PASS, region='JP-Backup'),
        
        # Logic: Only run when HK fails
        trigger_rule=TriggerRule.ALL_FAILED,
        cmd_timeout=300
    )

    # [Task 3]. Audit and Alert
    task_audit = PythonOperator(
        task_id='audit_failover',
        python_callable=check_failover_and_alert,

        # Run when: HK or JP succeeds
        trigger_rule=TriggerRule.ONE_SUCCESS
    )

    # End tag
    end = EmptyOperator(task_id='end')

    # [Dependency Graph]
    # Normal path: Start -> HK -> Audit -> End
    # Fault path: Start -> HK(X) -> JP -> Audit -> End
    start >> task_crawl_hk
    task_crawl_hk >> task_crawl_jp # Logic dependency
    
    task_crawl_hk >> task_audit
    task_crawl_jp >> task_audit
    
    task_audit >> end