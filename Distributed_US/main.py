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
# Read server information from .env
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




