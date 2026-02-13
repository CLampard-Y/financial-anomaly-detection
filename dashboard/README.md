# Distributed Financial Sentinel - Dashboard

Real-time monitoring dashboard with failover visualization.

## Features
- Real-time cryptocurrency price tracking
- Failover detection and alerting
- Interactive candlestick charts
- Node health status visualization

## Installation

```bash
pip install -r requirements.txt
```

## Usage
### Development Mode
```bash
streamlit run app.py
```

### Production Mode (Background)
```bash
nohup streamlit run /home/distributed-financial-sentinel/dashboard/app.py \
  --server.port 8501 > dashboard.log 2>&1 &
```
Access: http://<US_IP>:8501

## Verification
1. Open browser: `http://<US_IP>:8501`
2. You should see:
    - 4 KPI metrics (Price, Volume, Node Status, Failover Count)
    - Candlestick chart (dark theme)
    - Node health status (green = HK-Primary, red = JP-Backup)

## Troubleshooting
### Check if dashboard is running
```bash
ps aux | grep streamlit
```
### View logs
```bash
tail -f dashboard.log
```
### Stop dashboard
```bash
pkill -f "streamlit run"
```

## Common Issues
### Port 8501 is already in use
```bash
# Find process using port 8501
lsof -i :8501
# Kill the process
kill <PID>
```
### Database connection error
- Check if PostgreSQL is running: `docker ps | grep pipeline-db`
- Verify credentials in app.py (L22)

## Architecture

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │ HTTP :8501
       ▼
┌─────────────┐
│  Streamlit  │
│  Dashboard  │
└──────┬──────┘
       │ SQL
       ▼
┌─────────────┐
│ PostgreSQL  │
│ crypto_data │
└─────────────┘
```

---