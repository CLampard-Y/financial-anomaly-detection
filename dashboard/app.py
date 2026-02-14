# ==========================================
# Distributed Financial Sentinel - Dashboard
# ==========================================
# Quick start:
#   pip install -r requirements.txt
#   streamlit run app.py
#
# Production Deployment: See README.md
# ==========================================

import streamlit as st
import pandas as pd
import psycopg2
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import os

# ------------------------------------------
# 1. Database Configuration
# ------------------------------------------
# Dashboard runs on US Master, connect to localhost
DB_URI = "host=localhost dbname=crypto user=airflow password=airflow"

def get_data(symbol, limit=100):
    # Load data from crypto_data.crypto_klines
    try:
        with psycopg2.connect(DB_URI) as conn:
            query = """
                SELECT
                    open_time,
                    open_price,
                    high_price,
                    low_price,
                    close_price,
                    volume,
                    source_region
                FROM crypto_data.crypto_klines
                WHERE symbol = %s
                ORDER BY open_time DESC
                LIMIT %s
            """
            df = pd.read_sql(query, conn, params=(symbol, limit))
        
        # Type conversion
        df['dt'] = pd.to_datetime(df['open_time'], unit='ms')
        cols = ['open_price', 'high_price', 'low_price', 'close_price', 'volume']
        df[cols] = df[cols].astype(float)
        
        return df.sort_values('dt')     # sort by time
    except Exception as e:
        st.error(f"Database Error: {e}")  
        return pd.DataFrame()

# ------------------------------------------
# 2. Web UI Layout
# ------------------------------------------

st.set_page_config(page_title="Binance Sentinel", layout="wide", page_icon="🛡️")
st.title(" Distributed Financial Sentinel (Binance Global)")
st.markdown("### 实时熔断监控看板 | Real-time Failover Monitor")

# Sidebar filters
symbol = st.sidebar.selectbox("选择交易对 (Target Symbol)", ["BTC/USDT", "ETH/USDT", "SOL/USDT", "DOGE/USDT"])
limit = st.sidebar.slider("显示 K 线数量 ( K lines to display )", 24, 200, 50)

# Load data
df = get_data(symbol, limit)

if df.empty:
    st.warning(f"暂无 {symbol} 数据，请等待 Airflow 爬虫运行。")
else:
    # ------------------------------------------
    # 3. Core KPIs
    # ------------------------------------------
    latest = df.iloc[-1]
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        st.metric("最新价格 (Latest Price)", f"${latest['close_price']:,.2f}")
    with col2:
        st.metric("24H 成交量 (Volume)", f"{latest['volume']:,.0f}")
    with col3:
        # status judgement
        source = latest['source_region']
        is_backup = 'Backup' in source
        st.metric(
            "当前数据源 (Node)", 
            source, 
            delta="FAILOVER ACTIVE" if is_backup else "Normal",
            delta_color="inverse" if is_backup else "normal"
        )
    with col4:
        # Statistics: Failover count
        failover_count = df[df['source_region'].str.contains('Backup')].shape[0]
        st.metric("近期熔断次数 (Failover Count)", f"{failover_count}", help="日本节点接管任务的次数 (Backup Node run task Count)")

    # ------------------------------------------
    # 4. Plotly Chart
    # ------------------------------------------
    # Two-axis chart: K lines, node status
    fig = make_subplots(
        rows=2, cols=1,
        shared_xaxes=True, 
        vertical_spacing=0.05, 
        row_heights=[0.75, 0.25]
    )

    # [Layer 1] Candlestick
    fig.add_trace(go.Candlestick(
        x=df['dt'],
        open=df['open_price'], high=df['high_price'],
        low=df['low_price'], close=df['close_price'],
        name='OHLC'
    ), row=1, col=1)

    # [Layer 2] Failover Proof
    # Green = Primary (HK), Red = Backup (JP)
    colors = df['source_region'].apply(lambda x: 'red' if 'Backup' in x else 'green')
    
    fig.add_trace(go.Scatter(
        x=df['dt'], 
        y=[1] * len(df), # dot on the same line
        mode='markers',
        marker=dict(size=12, color=colors, line=dict(width=1, color='DarkSlateGrey')),
        name='Node Status',
        text=df['source_region'],
        hovertemplate="Time: %{x}<br>Source: %{text}"
    ), row=2, col=1)

    # Layout
    fig.update_layout(
        height=600,
        xaxis_rangeslider_visible=False,
        title_text=f"{symbol} 价格走势与分布式节点健康度",
        template="plotly_dark" # Dark theme
    )
    
    # Hide Y axis
    fig.update_yaxes(showticklabels=False, row=2, col=1)
    fig.update_yaxes(title_text="Price (USDT)", row=1, col=1)

    st.plotly_chart(fig, use_container_width=True)