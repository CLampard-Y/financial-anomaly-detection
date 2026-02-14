# 从零开始部署手册 — Distributed Financial Sentinel

> 本手册面向零基础用户，所有命令均可直接复制粘贴执行。
> 目标：在一台全新的 Linux 服务器上，从 SSH 登录到服务完全运行，全程约 10-15 分钟。

---

## 目录

1. [项目架构概览](#1-项目架构概览)
2. [环境要求](#2-环境要求)
3. [全新服务器部署（首次完整安装）](#3-全新服务器部署首次完整安装)
4. [日常更新部署（代码迭代）](#4-日常更新部署代码迭代)
5. [Worker 节点部署（HK/JP）](#5-worker-节点部署hkjp)
6. [健康验证与测试命令](#6-健康验证与测试命令)
7. [数据封闭性说明](#7-数据封闭性说明)
8. [常见问题排查](#8-常见问题排查)

---

## 1. 项目架构概览

```
┌─────────────────────────────────────────────┐
│              US Master Server               │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Postgres │  │ Airflow  │  │ Airflow   │  │
│  │   :5432  │  │ Web :8080│  │ Scheduler │  │
│  └─────────┘  └──────────┘  └───────────┘  │
└──────────────────┬──────────────────────────┘
                   │ SSH
        ┌──────────┴──────────┐
        ▼                     ▼
┌──────────────┐     ┌──────────────┐
│  HK-Primary  │     │  JP-Backup   │
│  (Crawler)   │     │  (Failover)  │
└──────────────┘     └──────────────┘
```

- **US Master**：运行 Airflow（调度）+ PostgreSQL（存储），是整个系统的中枢
- **HK-Primary**：主爬虫节点，负责从 Binance 抓取 K 线数据
- **JP-Backup**：备用节点，HK 故障时自动接管（熔断机制）

---

## 2. 环境要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Ubuntu 22.04 / Debian 12（推荐） |
| 权限 | root 或具有 sudo 权限的用户 |
| 预装软件 | 无特殊要求（初始化脚本会自动安装所有依赖） |
| 最低配置 | 2 核 CPU / 4GB 内存 / 20GB 磁盘 |
| 网络 | 能访问 Docker Hub 和 GitHub |

> 所有依赖（包括 git、curl、Docker、Docker Compose、openssl、ufw 等）均由初始化脚本自动安装。即使是刚重装完系统的最小化安装版，也无需手动预装任何软件。

---

## 3. 全新服务器部署（首次完整安装）

本项目支持两种部署路径，根据你的实际情况选择：

---

### 路径 A：配合 Server-Ops 仓库部署（推荐）

如果你同时使用 [Server-Ops](https://github.com/<your-org>/Server-Ops) 仓库管理服务器基础设施，请按此路径操作。Server-Ops 会预先完成 Docker 安装、BBR 加速、SSH 加固、Sysctl 调优等底层工作。

#### A-1：SSH 登录服务器

```bash
ssh root@<你的服务器IP>
```

#### A-2：安装 Git 并克隆两个仓库

```bash
apt-get update && apt-get install -y git

git clone <Server-Ops仓库地址> /home/Server-Ops

# 直接克隆整个仓库 (不推荐)
git clone <Data-Analysis仓库地址> /home/Data-Analysis-Projects

# Git 稀疏检出 (Sparse Checkout)
# 只克隆指定目录( 02_Distributed_Financial_Sentinel )
git clone --filter=blob:none --sparse <Data-Analysis仓库地址> /home/Data-Analysis-Projects
cd /home/Data-Analysis-Projects
git sparse-checkout set 02_Distributed_Financial_Sentinel
```

#### A-3：执行 Server-Ops 基础设施初始化

```bash
cd /home/Server-Ops
sudo bash setup.sh
```

在交互式菜单中选择 `1) Layer 1: 系统底层初始化`，等待完成后选择 `0) 退出`。

> 完成后 Docker、Docker Compose、BBR、Swap、SSH 加固等底层环境全部就绪。

#### A-4：执行 Sentinel 业务部署

```bash
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel
bash infra/setup_server_env.sh
```

> 脚本会自动检测到 Docker 已安装，智能跳过系统更新和基础包安装，直接进入 SSH 密钥生成和业务配置阶段，节省 2-3 分钟。

跳转到下方 [交互式输入说明](#交互式输入说明) 继续。

---

### 路径 B：独立部署（无 Server-Ops）

如果你不使用 Server-Ops，Sentinel 的初始化脚本会自行完成所有底层环境配置。

#### B-1：SSH 登录服务器

```bash
ssh root@<你的服务器IP>
```

#### B-2：获取项目代码

```bash
# 安装 git（最小化安装可能没有）
apt-get update && apt-get install -y git

cd /home
git clone <你的仓库地址> Data-Analysis-Projects
cd Data-Analysis-Projects/02_Distributed_Financial_Sentinel
```

> **重要**：所有运行时数据都会封闭在项目目录内，不会污染系统其他位置。

#### B-3：运行全自动初始化脚本

```bash
bash infra/setup_server_env.sh
```

> 此脚本会自动检测并安装所有缺失的系统依赖（curl、openssl、ufw、Docker 等），无需手动处理。

---

### 交互式输入说明

无论选择哪条路径，`setup_server_env.sh` 运行过程中会自动完成以下操作：

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1/8 | 系统更新 & 基础依赖 | 自动安装 curl、git、openssl、ufw 等基础包 |
| 2/8 | 安装 Docker & Compose | 自动检测，已安装则跳过 |
| 3/8 | 生成 SSH 密钥 | 用于连接 HK/JP Worker 节点 |
| 4/8 | 配置 Worker 节点 SSH | 交互式输入 HK/JP 节点 IP |
| 5/8 | 配置防火墙 (UFW) | 仅开放 22、8080、5432 端口 |
| 6/8 | 生成 Fernet Key & .env | 交互式输入数据库密码 |
| 7/8 | 启动 Docker 服务 | 自动创建目录、拉取镜像、启动容器 |
| 8/8 | 验证数据库初始化 | 检查 crypto 数据库是否创建成功 |

脚本运行过程中会提示你输入以下信息：

```
Enter HK node IP address:     ← 输入香港节点 IP
Enter JP node IP address:     ← 输入日本节点 IP
Enter PostgreSQL password:     ← 输入数据库密码（不会显示在屏幕上）
Confirm password:              ← 再次确认密码
```

### 记录输出的凭据

脚本结束后会输出类似以下信息，**请务必保存**：

```
==========================================
Setup Complete!
==========================================
Airflow Web UI: http://123.45.67.89:8080

IMPORTANT - Save credentials securely:
-----------------------------------
Airflow Admin Username: admin
Airflow Admin Password: xK9mP2nQ7wR5tY3z
-----------------------------------
```

---

## 4. 日常更新部署（代码迭代）

当你修改了代码并推送到 GitHub 后，在 US Master 上执行：

```bash
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel
bash scripts/deploy_us.sh
```

此脚本会自动完成：
- 检测 Docker 环境是否就绪
- `git pull` 拉取最新代码
- 确保 `.env` 存在（不存在则从 `.env.example` 复制）
- 创建必要的数据目录
- `docker compose up -d --build` 重建并启动服务
- 执行健康检查

> 这是一个幂等操作，可以安全地重复执行。

---

## 5. Worker 节点部署（HK/JP）

### 前提条件

- HK/JP 节点已安装 Docker
- US Master 已通过 `setup_server_env.sh` 配置好 SSH 免密登录

### 执行部署

```bash
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel
bash scripts/deploy_workers.sh
```

此脚本会自动：
1. 从 `.env` 读取 `HK_IP` 和 `JP_IP`
2. 在本地构建 `binance-crawler` Docker 镜像
3. 导出镜像为 tar 包
4. 通过 SCP 分发到 HK/JP 节点
5. 在远程节点加载镜像
6. 清理本地临时文件

### 激活爬虫（关键步骤）

Worker 镜像分发完成后，还需要在 US Master 上完成以下激活操作，爬虫才会正式开始工作：

#### 步骤 1：注册 Airflow 连接 & 激活 DAG

```bash
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel

# 容器是以 root 启动, docker exec 默认也以 root 进入
# 但 Airflow 装在 airflow 用户的 Python 环境里
# 需要加 -u airflow 来切换到 airflow 用户
docker exec -i -u airflow airflow-scheduler bash < airflow/dags/setup_airflow.sh

docker exec -i airflow-scheduler bash < airflow/dags/setup_airflow.sh
```

此脚本会一次性完成：
- 注册 `ssh_hk` 连接（SSH 到香港节点）
- 注册 `ssh_jp` 连接（SSH 到日本节点）
- 注册 `postgres_default` 连接（指向 crypto 业务数据库）
- 激活 `binance_global_sentinel` DAG（每小时爬取）
- 激活 `maintenance_data` DAG（每日清理）

#### 步骤 2：验证 DAG 已激活

```bash
# 查看 DAG 列表和状态
docker exec airflow-scheduler airflow dags list
```

期望输出中 `binance_global_sentinel` 和 `maintenance_data` 的 `paused` 列为 `False`。

或者打开浏览器访问 `http://<服务器IP>:8080`，确认两个 DAG 的开关为 ON（蓝色）。

#### 步骤 3：手动触发首次爬取（可选）

DAG 设定为每小时整点自动运行。如果不想等到下一个整点，可以手动触发：

```bash
# 同样记得加 -u airflow 来切换到 airflow 用户
docker exec -u airflow airflow-scheduler airflow dags trigger binance_global_sentinel

# 手动触发一次爬取
docker exec airflow-scheduler airflow dags trigger binance_global_sentinel
```

#### 步骤 4：验证爬虫已成功写入数据

等待任务完成后（约 1-2 分钟），检查数据库：

```bash
# 查询最新写入的数据
docker exec pipeline-db psql -U airflow -d crypto -c "
    SELECT symbol, source_region, close_price, 
           to_timestamp(open_time/1000) as time
    FROM crypto_data.crypto_klines 
    ORDER BY created_at DESC 
    LIMIT 5;
"
```

期望输出（示例）：

```
  symbol   | source_region | close_price |        time
-----------+---------------+-------------+---------------------
 BTC/USDT  | HK-Primary    | 67234.5600  | 2024-01-15 08:00:00
 ETH/USDT  | HK-Primary    |  3456.7800  | 2024-01-15 08:00:00
 SOL/USDT  | HK-Primary    |   123.4500  | 2024-01-15 08:00:00
 DOGE/USDT | HK-Primary    |     0.1234  | 2024-01-15 08:00:00
```

如果 `source_region` 显示 `HK-Primary`，说明主节点工作正常。如果显示 `JP-Backup`，说明 HK 节点故障，系统已自动切换到日本备用节点（熔断机制生效）。

#### 步骤 5：查看任务执行日志

```bash
# 查看最近的 DAG 运行记录
docker exec airflow-scheduler airflow dags list-runs -d binance_global_sentinel --limit 5

# 查看具体任务日志（在 Airflow UI 中更直观）
# 浏览器访问: http://<服务器IP>:8080 → 点击 DAG → Graph → 点击任务方块 → Log
```

---

## 6. 健康验证与测试命令

### 6.1 检查容器状态

```bash
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel
docker compose ps
```

期望输出（所有服务状态为 `running` 或 `healthy`）：

```
NAME                IMAGE                    STATUS
pipeline-db         postgres:13              running (healthy)
airflow-webserver   apache/airflow:2.7.1     running
airflow-scheduler   apache/airflow:2.7.1     running
```

### 6.2 验证数据库

```bash
# 检查 crypto 数据库是否存在
docker exec pipeline-db psql -U airflow -lqt | grep crypto

# 检查 crypto_data schema 和表是否创建
docker exec pipeline-db psql -U airflow -d crypto -c "\dt crypto_data.*"
```

期望输出：

```
              List of relations
   Schema    |     Name      | Type  | Owner
-------------+---------------+-------+---------
 crypto_data | crypto_klines | table | airflow
```

### 6.3 验证 Airflow Web UI

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health
```

期望输出：`200`

浏览器访问：`http://<服务器IP>:8080`，使用初始化时输出的 admin 账号密码登录。

### 6.4 验证数据目录封闭性

```bash
# 确认所有数据都在项目目录内
ls -la data/postgres/       # PostgreSQL 数据文件
ls -la airflow/logs/        # Airflow 日志
ls -la data_lake/           # 数据湖导出文件

# 确认没有使用 Docker Named Volume
docker volume ls | grep sentinel
# 期望输出：空（无任何匹配）
```

### 6.5 验证 Worker 节点连通性

```bash
# 从 Airflow 容器内测试 SSH 连接
docker exec airflow-scheduler ssh -o StrictHostKeyChecking=no root@<HK_IP> "echo 'HK OK'"
docker exec airflow-scheduler ssh -o StrictHostKeyChecking=no root@<JP_IP> "echo 'JP OK'"
```

---

## 7. 数据封闭性说明

本项目严格遵循数据封闭 (Data Containment) 原则：

| 数据类型 | 存储位置 | 说明 |
|----------|----------|------|
| PostgreSQL 数据 | `./data/postgres/` | Bind Mount，非 Named Volume |
| Airflow 日志 | `./airflow/logs/` | Bind Mount |
| Airflow DAGs | `./airflow/dags/` | Bind Mount |
| Airflow 插件 | `./airflow/plugins/` | Bind Mount |
| 数据湖快照 | `./data_lake/` | 脚本动态创建 |
| 环境配置 | `./.env` | 项目根目录 |

### 与 Server-Ops 的隔离性

如果同时部署了 Server-Ops 的 Layer 2/3 服务（如 Portainer、Komari 等），它们的数据与 Sentinel 完全隔离，互不干扰：

| 组件 | 数据根目录 | 端口 |
|------|-----------|------|
| Server-Ops Layer 2 | `/home/Basic-Ops/<服务名>/` | 9443 (Portainer), 3399 (Komari) |
| Server-Ops Layer 3 | `/home/App-Ops/<应用名>/` | 各应用自定义 |
| Sentinel | 项目目录内 `./data/`, `./airflow/` 等 | 8080 (Airflow), 5432 (PostgreSQL) |

### 完全卸载

只需删除项目目录，不会在系统中留下任何残留数据：

```bash
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel
docker compose down
cd /home
rm -rf Data-Analysis-Projects/02_Distributed_Financial_Sentinel
```

---

## 8. 常见问题排查

### Q: `docker compose up` 报错 "permission denied"

```bash
sudo usermod -aG docker $USER
# 重新登录 SSH 使权限生效
exit
ssh root@<服务器IP>
```

### Q: Postgres 容器启动失败，日志显示权限错误

```bash
chmod 700 data/postgres
# 如果目录内有残留数据导致冲突
rm -rf data/postgres/*
docker compose up -d
```

### Q: Airflow Web UI 无法访问

```bash
# 检查防火墙
sudo ufw status | grep 8080
# 如未放行
sudo ufw allow 8080/tcp

# 检查容器日志
docker logs airflow-webserver --tail 50
```

### Q: DAG 未出现在 Airflow UI 中

```bash
# 检查 DAG 文件是否正确挂载
docker exec airflow-scheduler ls /opt/airflow/dags/

# 检查 DAG 是否有语法错误
docker exec airflow-scheduler python -c \
  "from airflow.models import DagBag; db=DagBag('/opt/airflow/dags'); print(db.import_errors)"
```

### Q: Worker 节点 SSH 连接失败

```bash
# 在宿主机上测试
ssh root@<NODE_IP> "echo OK"

# 如果失败，重新复制密钥
ssh-copy-id -i ~/.ssh/id_rsa.pub root@<NODE_IP>
```

### Q: Server-Ops 的服务与 Sentinel 端口冲突

```bash
# 检查端口占用
ss -tlnp | grep -E '5432|8080'

# 如果 5432 被其他 Postgres 占用，修改 docker-compose.yaml 映射端口
# 例如改为 5433:5432，同时更新 .env 和 Worker 节点的连接配置
```

### Q: 需要完全重置项目

```bash
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel
docker compose down
rm -rf data/postgres/*
rm -rf airflow/logs/*
docker compose up -d    # 数据库会自动重新初始化
```

---

> 手册版本：v2.1 | 补充爬虫激活链路与数据验证流程