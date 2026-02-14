# Dashboard 生产环境部署指南

**项目**: Distributed Financial Sentinel - 实时监控看板  
**技术栈**: Streamlit + PostgreSQL + Plotly  
**部署方式**: 虚拟环境 + systemd 服务  
**文档版本**: v1.0

---

## 为什么需要持续运行？

Dashboard 是一个 **Web 应用服务**，需要 7x24 小时运行，用户才能随时访问实时数据可视化界面。与一次性脚本不同，它需要：

- ✅ 开机自动启动
- ✅ 后台持续运行
- ✅ 崩溃自动重启
- ✅ 日志持久化记录

---

## 为什么使用虚拟环境？

### 常见误解

> "虚拟环境是临时的，不适合生产环境"

**这是错误的！** 虚拟环境只是改变了 Python 解释器和依赖包的路径，通过 systemd 服务管理，可以实现与系统级安装完全相同的持续运行能力。

### 虚拟环境的优势

| 对比项 | 虚拟环境 + systemd | 系统级安装 |
|--------|-------------------|-----------|
| **环境隔离** | ✅ 不污染系统 Python | ❌ 可能破坏系统包管理 |
| **持续运行** | ✅ systemd 管理，开机自启 | ✅ 同样可以 |
| **版本冲突** | ✅ 不会与其他项目冲突 | ❌ 可能导致依赖冲突 |
| **易于维护** | ✅ 升级/回滚简单 | ❌ 影响全局环境 |
| **Debian 兼容** | ✅ 符合最佳实践 | ❌ 需要 `--break-system-packages` |
| **可移植性** | ✅ 易于迁移到其他服务器 | ❌ 依赖系统环境 |

### Debian 12 的 externally-managed-environment 保护

从 Debian 12 开始，系统不允许直接用 `pip` 安装包到系统 Python，会报错：

```
error: externally-managed-environment
```

这是为了防止破坏系统包管理。**虚拟环境是官方推荐的解决方案**。

---

## 完整部署流程

### 第一步：创建虚拟环境并安装依赖

```bash
# 进入 dashboard 目录
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard

# 创建虚拟环境
python3 -m venv venv

# 激活虚拟环境
source venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 验证安装
streamlit --version

# 退出虚拟环境
deactivate
```

**预期结果**：
- 在 `dashboard/` 目录下生成 `venv/` 文件夹
- 所有依赖包安装在 `venv/lib/python3.13/site-packages/`
- 不影响系统 Python

### 第二步：创建 systemd 服务文件

```bash
# 创建服务配置文件
cat > /etc/systemd/system/financial-dashboard.service << 'EOF'
[Unit]
Description=Distributed Financial Sentinel Dashboard
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard

# 关键：直接使用虚拟环境中的 streamlit 可执行文件（无需激活）
ExecStart=/home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard/venv/bin/streamlit run app.py --server.port 8501 --server.address 0.0.0.0

# 自动重启策略
Restart=always
RestartSec=10

# 环境变量（如果需要）
Environment="PATH=/home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF
```

**配置说明**：

- `After=docker.service`: 确保 PostgreSQL 容器先启动
- `ExecStart`: 使用虚拟环境中的完整路径，**无需激活虚拟环境**
- `Restart=always`: 进程崩溃时自动重启
- `RestartSec=10`: 重启前等待 10 秒
- `--server.address 0.0.0.0`: 允许外部访问

### 第三步：启动并设置开机自启

```bash
# 重载 systemd 配置
systemctl daemon-reload

# 启动服务
systemctl start financial-dashboard

# 查看服务状态
systemctl status financial-dashboard

# 设置开机自启
systemctl enable financial-dashboard

# 查看实时日志
journalctl -u financial-dashboard -f
```

**预期输出**：

```
● financial-dashboard.service - Distributed Financial Sentinel Dashboard
     Loaded: loaded (/etc/systemd/system/financial-dashboard.service; enabled)
     Active: active (running) since Fri 2026-02-15 02:30:00 CST; 5s ago
   Main PID: 12345 (streamlit)
      Tasks: 3 (limit: 4915)
     Memory: 120.5M
        CPU: 2.345s
     CGroup: /system.slice/financial-dashboard.service
             └─12345 /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard/venv/bin/python...

Feb 15 02:30:00 debian systemd[1]: Started Distributed Financial Sentinel Dashboard.
Feb 15 02:30:01 debian streamlit[12345]: You can now view your Streamlit app in your browser.
Feb 15 02:30:01 debian streamlit[12345]: Network URL: http://0.0.0.0:8501
```

### 第四步：配置防火墙

```bash
# 开放 8501 端口
ufw allow 8501/tcp

# 重载防火墙规则
ufw reload

# 验证规则
ufw status numbered
```

### 第五步：访问 Dashboard

浏览器访问：`http://<US_IP>:8501`

应该看到实时监控看板，显示：
- 最新价格
- 24H 成交量
- 当前数据源（HK-Primary 或 JP-Backup）
- 近期熔断次数
- K 线图 + 节点健康度可视化

---

## 服务管理命令

### 基础操作

```bash
# 启动服务
systemctl start financial-dashboard

# 停止服务
systemctl stop financial-dashboard

# 重启服务
systemctl restart financial-dashboard

# 查看状态
systemctl status financial-dashboard

# 启用开机自启
systemctl enable financial-dashboard

# 禁用开机自启
systemctl disable financial-dashboard
```

### 日志查看

```bash
# 查看最近 50 条日志
journalctl -u financial-dashboard -n 50

# 实时查看日志（类似 tail -f）
journalctl -u financial-dashboard -f

# 查看今天的日志
journalctl -u financial-dashboard --since today

# 查看最近 1 小时的日志
journalctl -u financial-dashboard --since "1 hour ago"

# 查看错误日志
journalctl -u financial-dashboard -p err
```

### 故障排查

```bash
# 检查服务是否运行
systemctl is-active financial-dashboard

# 检查服务是否开机自启
systemctl is-enabled financial-dashboard

# 查看服务配置文件
systemctl cat financial-dashboard

# 测试配置文件语法
systemd-analyze verify /etc/systemd/system/financial-dashboard.service

# 手动运行（调试用）
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard
source venv/bin/activate
streamlit run app.py --server.port 8501 --server.address 0.0.0.0
```

---

## 常见问题与解决方案

### Q1: 服务启动失败，提示 "Address already in use"

**原因**: 8501 端口被占用

**解决方案**:

```bash
# 查看占用 8501 端口的进程
lsof -i :8501

# 或
netstat -tulnp | grep 8501

# 杀死占用进程
kill -9 <PID>

# 重启服务
systemctl restart financial-dashboard
```

### Q2: 服务运行但无法访问

**原因**: 防火墙未开放端口

**解决方案**:

```bash
# 检查防火墙状态
ufw status

# 开放 8501 端口
ufw allow 8501/tcp
ufw reload

# 验证端口监听
ss -tulnp | grep 8501
```

### Q3: 数据库连接失败

**原因**: PostgreSQL 容器未启动或连接配置错误

**解决方案**:

```bash
# 检查 PostgreSQL 容器状态
docker ps | grep postgres

# 如果未运行，启动容器
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel
docker compose up -d postgres

# 测试数据库连接
docker exec pipeline-db psql -U airflow -d crypto -c "SELECT 1;"

# 检查 app.py 中的连接配置（L22）
# DB_URI = "host=localhost dbname=crypto user=airflow password=airflow"
```

### Q4: 虚拟环境依赖包缺失

**原因**: 虚拟环境未正确安装依赖

**解决方案**:

```bash
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard

# 重新安装依赖
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
deactivate

# 重启服务
systemctl restart financial-dashboard
```

### Q5: 服务频繁重启

**原因**: 程序崩溃或配置错误

**解决方案**:

```bash
# 查看详细错误日志
journalctl -u financial-dashboard -n 100 --no-pager

# 手动运行查看错误
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard
source venv/bin/activate
streamlit run app.py --server.port 8501 --server.address 0.0.0.0

# 常见错误：
# - ModuleNotFoundError: 依赖包未安装
# - psycopg2.OperationalError: 数据库连接失败
# - PermissionError: 文件权限问题
```

---

## 性能优化建议

### 1. 数据库连接池

当前每次查询都创建新连接，高并发时可能导致性能问题。建议使用连接池：

```python
# 在 app.py 顶部添加
from psycopg2 import pool

# 创建连接池
connection_pool = pool.SimpleConnectionPool(
    1, 10,  # 最小 1 个，最大 10 个连接
    host='localhost',
    dbname='crypto',
    user='airflow',
    password='airflow'
)

# 修改 get_data 函数
def get_data(symbol, limit=100):
    conn = connection_pool.getconn()
    try:
        # ... 查询逻辑 ...
    finally:
        connection_pool.putconn(conn)
```

### 2. 数据缓存

使用 Streamlit 的缓存机制，减少数据库查询：

```python
@st.cache_data(ttl=60)  # 缓存 60 秒
def get_data(symbol, limit=100):
    # ... 原有逻辑 ...
```

### 3. 限制并发用户

在 systemd 服务文件中添加资源限制：

```ini
[Service]
# 限制内存使用
MemoryMax=512M

# 限制 CPU 使用
CPUQuota=50%
```

---

## 升级与回滚

### 升级依赖包

```bash
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard

# 激活虚拟环境
source venv/bin/activate

# 升级单个包
pip install --upgrade streamlit

# 升级所有包
pip install --upgrade -r requirements.txt

# 退出虚拟环境
deactivate

# 重启服务
systemctl restart financial-dashboard
```

### 回滚到旧版本

```bash
# 备份当前虚拟环境
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard
cp -r venv venv.backup

# 如果升级后出现问题，恢复备份
rm -rf venv
mv venv.backup venv

# 重启服务
systemctl restart financial-dashboard
```

---

## 监控与告警

### 1. 服务健康检查

```bash
# 创建健康检查脚本
cat > /usr/local/bin/check-dashboard.sh << 'EOF'
#!/bin/bash
if ! systemctl is-active --quiet financial-dashboard; then
    echo "Dashboard service is down!"
    systemctl restart financial-dashboard
    # 可以在这里添加告警通知（飞书/钉钉 Webhook）
fi
EOF

chmod +x /usr/local/bin/check-dashboard.sh

# 添加到 crontab（每 5 分钟检查一次）
crontab -e
# 添加以下行：
# */5 * * * * /usr/local/bin/check-dashboard.sh
```

### 2. 日志轮转

防止日志文件过大：

```bash
# 创建日志轮转配置
cat > /etc/logrotate.d/financial-dashboard << 'EOF'
/var/log/financial-dashboard/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF
```

---

## 安全加固

### 1. 使用非 root 用户运行

```bash
# 创建专用用户
useradd -r -s /bin/false streamlit-user

# 修改文件所有权
chown -R streamlit-user:streamlit-user /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel/dashboard

# 修改 systemd 服务文件
# 将 User=root 改为 User=streamlit-user
```

### 2. 启用 HTTPS（使用 Nginx 反向代理）

```bash
# 安装 Nginx
apt install -y nginx certbot python3-certbot-nginx

# 配置反向代理
cat > /etc/nginx/sites-available/dashboard << 'EOF'
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:8501;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

# 启用配置
ln -s /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# 申请 SSL 证书
certbot --nginx -d your-domain.com
```

---

## 总结

通过虚拟环境 + systemd 的部署方式，Dashboard 可以：

✅ **持续运行**: 7x24 小时提供服务  
✅ **开机自启**: 服务器重启后自动恢复  
✅ **自动重启**: 崩溃后 10 秒内自动恢复  
✅ **环境隔离**: 不污染系统 Python  
✅ **易于维护**: 升级/回滚简单  
✅ **生产级别**: 符合工业界最佳实践

这是 **Python Web 应用的标准部署方式**，与 Docker、Airflow、Nginx 等服务的部署理念完全一致。

---

**文档版本**: v1.0  
**最后更新**: 2026-02-15  
**维护者**: Data Engineering Team
