# Dashboard 部署与运行

本页说明 `dashboard/app.py` 的本地运行方式，以及在 Linux 服务器上通过 `systemd` 持续运行的最小配置。

相关文档：[`../README.md`](../README.md) · [`../docs/runtime_checks.md`](../docs/runtime_checks.md) · [`../docs/validation/README.md`](../docs/validation/README.md)

## 运行前提

- 已准备好根目录 `.env`，或通过环境变量提供数据库连接信息
- 服务器已安装 `python3`、`python3-venv` 与 `pip`
- 业务表 `crypto_data.crypto_klines` 已存在并有可读数据

Dashboard 读取的数据库配置优先级如下：

1. `DATABASE_URL`
2. `DFS_DB_*` / `DB_*` / `POSTGRES_*`
3. 根目录 `.env`

## 本地运行

在 `dashboard/` 目录下执行：

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
streamlit run app.py
```

默认访问地址为 `http://localhost:8501`。

## 服务器运行（systemd）

### 1. 创建虚拟环境

```bash
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate
```

### 2. 创建服务文件

若服务器上有专门的非特权运行用户，建议优先使用该用户；以下示例仍保留 `root`，仅为了与当前部署目录和权限配置保持一致。

```bash
cat > /etc/systemd/system/financial-dashboard.service <<'EOF'
[Unit]
Description=Distributed Financial Sentinel Dashboard
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard
ExecStart=/home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard/venv/bin/streamlit run app.py --server.port 8501 --server.address 0.0.0.0
Restart=always
RestartSec=10
Environment="PATH=/home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF
```

### 3. 启动与开机自启

```bash
systemctl daemon-reload
systemctl start financial-dashboard
systemctl enable financial-dashboard
systemctl status financial-dashboard
```

### 4. 查看日志

```bash
journalctl -u financial-dashboard -n 50
journalctl -u financial-dashboard -f
```

## 常用管理命令

```bash
systemctl start financial-dashboard
systemctl stop financial-dashboard
systemctl restart financial-dashboard
systemctl status financial-dashboard
systemctl disable financial-dashboard
```

## 运行检查

- 页面应显示最新价格、节点来源、failover 次数和节点状态点位
- 若 Dashboard 页面与数据库样例查询不一致，请先执行 [`../docs/runtime_checks.md`](../docs/runtime_checks.md) 中的样例 SQL
- 如需查看页面示例，可参考 [`../docs/validation/README.md`](../docs/validation/README.md) 中的 `07a` 与 `07b`

## 常见问题

### 1. `python: command not found`

Debian / Ubuntu 通常默认提供 `python3`，而不是 `python`。请使用 `python3 -m venv` 创建虚拟环境。

### 2. 缺少 `pandas` 或 `psycopg2`

说明虚拟环境依赖未安装完整，请重新激活 `venv` 后执行：

```bash
pip install -r requirements.txt
```

### 3. 页面提示数据库连接失败

优先检查：

- 根目录 `.env` 是否存在且密码正确
- `DATABASE_URL` 或 `POSTGRES_PASSWORD` 是否已设置
- `pipeline-db` 是否正在运行

### 4. 页面可访问但没有数据

这通常不是 Dashboard 本身的问题，建议按顺序检查：

1. `docker compose ps`
2. `docker exec pipeline-db psql -U airflow -d crypto -c "SELECT COUNT(*) FROM crypto_data.crypto_klines;"`
3. `docker exec airflow-scheduler airflow dags list-runs -d binance_global_sentinel --limit 5`

## 安全提示

- 若 Dashboard 对外提供访问，应补充反向代理、TLS 与访问控制
- `8501` 端口不建议长期直接暴露在公网
- 建议将运行用户与文件权限纳入主机安全策略统一管理
