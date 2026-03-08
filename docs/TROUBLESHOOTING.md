# 问题排查

本页按“现象 -> 原因 -> 处理方式”的结构整理常见部署与运行问题。正常部署流程请参考 [`../DEPLOYMENT_GUIDE.md`](../DEPLOYMENT_GUIDE.md)，健康检查与样例 SQL 请参考 [`runtime_checks.md`](runtime_checks.md)。

## <a id="airflow-restart"></a>1. Airflow 容器不断重启

### 现象

- 执行 `setup_server_env.sh` 或 `docker compose up` 后，Airflow 容器显示 `Restarting (1)`
- 日志中反复出现 `ERROR: You need to initialize the database`
- PostgreSQL 容器已 `healthy`，但 Airflow 无法稳定启动

### 原因

- Airflow 的元数据库尚未初始化，就已经启动了 `webserver` / `scheduler`
- `depends_on: service_healthy` 只表示 PostgreSQL 进程可接受连接，不保证 Airflow 元数据表已创建
- 如果此时直接用 `docker exec airflow-webserver airflow db migrate`，容器可能正处于重启循环，命令无法稳定执行

### 处理方式

按以下顺序重新执行初始化：

```bash
docker compose up -d postgres

until docker exec pipeline-db pg_isready -U airflow; do
  sleep 5
done

docker compose run --rm airflow-webserver airflow db migrate
docker compose up -d airflow-webserver airflow-scheduler
```

### 说明

- 一次性初始化任务应使用 `docker compose run --rm ...`，而不是在正在重启的服务容器里执行 `docker exec`
- 这也是当前仓库文档默认采用的启动顺序

## <a id="password-special-chars"></a>2. 数据库密码中的特殊字符导致连接异常

### 现象

- 连接字符串中出现双 `@@` 或解析异常
- `airflow db migrate` 失败，但数据库进程本身正常

### 原因

密码中包含 `@ : / # ? & =` 等字符时，SQLAlchemy 连接字符串会把它们当作 URL 分隔符处理。

例如密码为 `pass@word` 时：

```text
postgresql+psycopg2://airflow:pass@word@postgres/airflow
```

### 处理方式

- 优先使用不含上述字符的密码
- 如果必须使用特殊字符，请确保连接字符串已正确 URL 编码

### 建议

- 当前项目最简单的做法是使用 `a-zA-Z0-9_-` 这类字符集

## <a id="airflow-permission"></a>3. Airflow 日志目录权限错误

### 现象

- 日志中出现 `PermissionError: [Errno 13] Permission denied`
- 常见路径为 `/opt/airflow/logs/...` 或 `/opt/airflow/plugins/...`

### 原因

- 宿主机目录由 `root` 创建，但 Airflow 进程在容器内以 `UID 50000` 运行
- bind mount 挂载后，容器内进程无法写入这些目录

### 处理方式

```bash
chown -R 50000:50000 airflow/logs
chown -R 50000:50000 airflow/plugins
```

处理后重启相关容器：

```bash
docker compose restart airflow-webserver airflow-scheduler
```

## <a id="web-ui"></a>4. Airflow Web UI 无法访问

### 现象

- 浏览器无法访问 `http://<US_IP>:8080`
- `curl http://localhost:8080/health` 未返回 `200`

### 处理方式

先按顺序检查：

```bash
docker compose ps
docker logs airflow-webserver --tail 50
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health
sudo ufw status | grep 8080
```

若防火墙未放行：

```bash
sudo ufw allow 8080/tcp
sudo ufw reload
```

## <a id="dag-missing"></a>5. DAG 未显示或导入失败

### 现象

- Airflow UI 中看不到 `binance_global_sentinel` 或 `maintenance_data`
- DAG 文件已存在，但页面没有显示

### 处理方式

```bash
docker exec airflow-scheduler ls /opt/airflow/dags/
docker exec airflow-scheduler python -c "from airflow.models import DagBag; db=DagBag('/opt/airflow/dags'); print(db.import_errors)"
docker exec airflow-scheduler airflow dags list
```

如果 DAG 已被识别但仍未启用，可重新执行：

```bash
docker exec -i -u airflow airflow-scheduler bash < airflow/dags/setup_airflow.sh
```

## <a id="worker-ssh"></a>6. Worker 节点 SSH 连接失败

### 现象

- `crawl_primary_hk` 或 `crawl_backup_jp` 任务在 SSH 阶段失败
- 连接测试返回 `Permission denied`、`Connection timed out` 或 `No route to host`

### 处理方式

先在宿主机测试基础连通性：

```bash
ssh root@<NODE_IP> "echo OK"
```

如果失败，可重新复制公钥：

```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub root@<NODE_IP>
```

随后在 Airflow 容器内验证：

```bash
docker exec airflow-scheduler ssh -o StrictHostKeyChecking=no root@<NODE_IP> "echo OK"
```

## <a id="postgres-permission"></a>7. Postgres 数据目录权限错误

### 现象

- Postgres 容器启动失败
- 日志中提示数据目录权限不正确或无法写入 `data/postgres`

### 处理方式

```bash
chmod 700 data/postgres
docker compose up -d postgres
```

如果目录内存在已损坏或不兼容的残留数据，需要先确认是否可以丢弃，再做清理。

## <a id="port-conflict"></a>8. 端口冲突

### 现象

- `5432`、`8080` 或 `8501` 无法绑定
- 已部署的其他服务占用了相同端口

### 处理方式

```bash
ss -tlnp | grep -E '5432|8080|8501'
```

如果确认端口冲突，需要调整 `docker-compose.yaml` 或相关服务配置，并同步更新：

- `.env` 中的连接信息
- worker 回写配置
- Dashboard 或反向代理的访问入口

## <a id="full-reset"></a>9. 完全重置项目

### 警告

以下操作会删除本地 Postgres 数据与 Airflow 日志，仅适用于确认可以丢弃现有状态的场景。

### 处理方式

```bash
cd /home/Data-Analysis-Projects/02_Distributed_Financial_Sentinel
docker compose down
rm -rf data/postgres/*
rm -rf airflow/logs/*
docker compose up -d postgres
docker compose run --rm airflow-webserver airflow db migrate
docker compose up -d airflow-webserver airflow-scheduler
```

如果是多节点部署，重置后还应重新执行：

```bash
docker exec -i -u airflow airflow-scheduler bash < airflow/dags/setup_airflow.sh
```

## 10. 快速诊断命令

以下命令适合在问题尚未定位时快速收集现场信息：

```bash
docker compose ps
docker ps -a
docker logs airflow-webserver --tail 50
docker logs airflow-scheduler --tail 50
docker logs pipeline-db --tail 50
docker exec pipeline-db psql -U airflow -c "\l"
docker exec pipeline-db psql -U airflow -d airflow -c "\dt"
```

若这些命令显示系统已恢复到正常状态，请回到 [`../DEPLOYMENT_GUIDE.md`](../DEPLOYMENT_GUIDE.md) 或 [`runtime_checks.md`](runtime_checks.md) 继续执行标准检查。
