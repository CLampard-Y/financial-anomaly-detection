# ============================================
# Main Crawler Script: Rewrite construction and DB write logic
# Run in Airflow container
# ============================================
import os
import time
import json
import requests
import psycopg2
from datetime import datetime
import pytz

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

# Data API (read from .env)
API_URL = os.getenv("API_URL","FULL_URL")
API_PROVIDER = os.getenv("API_PROVIDER", "UNKONWN")

# --------------------------------------------
# 2. Fetch data from API
# --------------------------------------------
def fetch_prices():
    max_retries = 3
    # i = 0, 1, 2
    for i in range(max_retries):
        try:
            print(f"[{SOURCE_REGION}] Attempt {i+1}: Fetching data from [{API_PROVIDER}]...")
            
            # Send GET request to API_URL
            # Attention: requests.get() wont raise exception if API is down
            response = requests.get(API_URL, timeout=10)    # timeout=10 sec

            # Exam the response status code:
            response.raise_for_status()

            # Analysis JSON response if status code normal
            # If JSON valid, return JSONDecodeError
            return response.json()
        
        # print error message and sleep
        except Exception as e:
            print(f"Error fetching data: {e}")
            time.sleep(2)
    # If all retries failed, raise exception
    raise Exception("Failed to fetch data after retries")

# --------------------------------------------
# 3. Write to remote US database
# --------------------------------------------
def save_to_db(data):
    try:
        # Create connection by 'with' statement
        # After connnection closed,realative cursor close automatically
        with psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS
        ) as conn:
            cur = conn.cursor()

            #  Get current time in UTC
            utc_now = datetime.now(pytz.utc) 
        
            # Iterate through API response data structure:
            # {'bitcoin': {'usd': 42000, 'last_updated_at': ...}, ...}
            for symbol, details in data.items():
                price = details['usd']
                sql = """
                 INSERT INTO crypto_data.crypto_prices
                    (symbol, price_usd, captured_at, source_region, raw_payload)
                    VALUES (%s, %s, %s, %s, %s)
                """

                # Execute SQL statement
                cur.execute(sql, (
                    symbol.upper(),
                    price,
                    utc_now,
                    SOURCE_REGION,  # Source worker tag
                    json.dumps(details) # raw payload (JSONB)
                ))
                
            conn.commit()
            cur.close()
            print(f"[{SOURCE_REGION}] Successfully saved {len(data)} records to US DB.")
        
    except Exception as e:
        print(f"Database Error: {e}")
        raise e
        

