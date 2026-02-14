# 部署问题排查指南

## 问题复盘：Airflow 容器不断重启

### 问题现象
- 执行 `setup_server_env.sh` 后，Airflow 容器状态显示 `Restarting (1)`
- 日志中反复出现：`ERROR: You need to initialize the database. Please run 'airflow db init'`
- PostgreSQL 容器正常运行（`Up (healthy)`），但 Airflow 无法启动

### 根本原因分析

#### 1. 容器启动时机冲突
**问题代码（旧版）：**
```bash
# 同时启动所有容器
docker compose up -d

# 立即尝试在运行中的容器内执行命令
docker exec airflow-webserver airflow db migrate
```

**为什么会失败：**
- `docker compose up -d` 启动所有容器后立即返回
- Airflow 容器的 `command: webserver` 会立即启动 Airflow Web 服务
- Airflow 启动时会检查数据库是否已初始化
- 如果未初始化，Airflow 拒绝启动并退出（exit code 1）
- Docker 的 `restart: always` 策略导致容器不断重启
- 脚本中的 `docker exec` 命令在容器重启循环中无法成功执行

#### 2. `depends_on` 的局限性
```yaml
depends_on:
  postgres:
    condition: service_healthy
```

**误解：** 以为 `service_healthy` 就意味着数据库完全可用  
**真相：** 
- `pg_isready` 只检查 PostgreSQL 进程是否接受连接
- 不保证初始化脚本（`/docker-entrypoint-initdb.d/01_init.sh`）已执行完成
- 不保证 Airflow 元数据表已创建

#### 3. 数据库初始化的正确时机
Airflow 需要在 **服务启动前** 完成数据库初始化，而不是 **服务启动后**。

**错误流程：**
```
启动 PostgreSQL → 启动 Airflow 服务 → 尝试初始化数据库 ❌
                    ↓
                  服务检测到数据库未初始化
                    ↓
                  服务退出（exit 1）
                    ↓
                  容器重启（restart: always）
```

**正确流程：**
```
启动 PostgreSQL → 初始化 Airflow 数据库 → 启动 Airflow 服务 ✅
```

### 解决方案

#### 修复后的代码逻辑
```bash
# 1. 只启动 PostgreSQL
docker compose up -d postgres

# 2. 等待 PostgreSQL 完全就绪
until docker exec pipeline-db pg_isready -U airflow; do
    sleep 5
done

# 3. 使用一次性容器初始化数据库
docker compose run --rm airflow-webserver airflow db migrate

# 4. 初始化完成后，启动 Airflow 服务
docker compose up -d airflow-webserver airflow-scheduler
```

#### 关键改进点

**1. 使用 `docker compose run` 而不是 `docker exec`**
```bash
# ❌ 错误：在运行中的服务容器内执行
docker exec airflow-webserver airflow db migrate

# ✅ 正确：创建临时容器执行一次性任务
docker compose run --rm airflow-webserver airflow db migrate
```

**区别：**
- `docker exec`：在已运行的容器内执行命令，容器必须处于 `Up` 状态
- `docker compose run`：创建新的临时容器，执行命令后自动删除（`--rm`）
- `run` 模式下容器不会执行 `command: webserver`，而是执行我们指定的命令

**2. 分阶段启动容器**
```bash
# 阶段 1：只启动数据库
docker compose up -d postgres

# 阶段 2：初始化（使用临时容器）
docker compose run --rm airflow-webserver airflow db migrate

# 阶段 3：启动应用服务
docker compose up -d airflow-webserver airflow-scheduler
```

**3. 添加错误检测**
```bash
docker compose run --rm airflow-webserver airflow db migrate

if [ $? -ne 0 ]; then
    echo "✗ Airflow database migration failed!"
    echo "  Check connection string in .env file"
    exit 1
fi
```

### 其他相关问题

#### 问题 A：密码中的特殊字符
**现象：** 连接字符串显示 `postgresql+psycopg2://airflow:***@@postgres/airflow`（双 `@@`）

**原因：** 密码中包含 `@` 符号，导致 URL 解析错误
```bash
# 如果密码是 "pass@word"
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:pass@word@postgres/airflow
                                                                    ↑      ↑
                                                                  密码中的@  主机分隔符
```

**解决方案：**
- 移除密码复杂度验证
- 提示用户避免使用特殊字符：`@ : / # ? & =`
- 或者实现 URL 编码（更复杂）

#### 问题 B：权限问题
**现象：** `PermissionError: [Errno 13] Permission denied: '/opt/airflow/logs/scheduler'`

**原因：** Airflow 容器以 UID 50000 运行，但目录由 root（UID 0）创建

**解决方案：**
```bash
chown -R 50000:50000 airflow/logs
chown -R 50000:50000 airflow/plugins
```

### 最佳实践总结

#### 1. 容器初始化顺序
```
数据库容器 → 数据库初始化 → 应用容器
```

#### 2. 使用健康检查
```yaml
healthcheck:
  test: ["CMD", "pg_isready", "-U", "airflow"]
  interval: 5s
  retries: 5
```

#### 3. 一次性任务使用 `run`
```bash
# 数据库迁移
docker compose run --rm app python manage.py migrate

# 创建超级用户
docker compose run --rm app python manage.py createsuperuser
```

#### 4. 错误处理
```bash
command_that_might_fail

if [ $? -ne 0 ]; then
    echo "Command failed!"
    exit 1
fi
```

#### 5. 避免密码特殊字符
推荐字符集：`a-zA-Z0-9_-`

### 验证部署成功的标志

```bash
# 1. 所有容器都在运行
docker ps
# 应该看到：
# - pipeline-db: Up (healthy)
# - airflow-webserver: Up
# - airflow-scheduler: Up

# 2. 数据库连接正常
docker exec airflow-webserver airflow db check

# 3. Web UI 可访问
curl -I http://localhost:8080
# 应该返回 HTTP 200
```

### 快速诊断命令

```bash
# 查看容器状态
docker ps -a

# 查看容器日志
docker logs airflow-webserver --tail 50
docker logs pipeline-db --tail 50

# 检查数据库连接
docker exec pipeline-db psql -U airflow -c "\l"

# 检查 Airflow 数据库表
docker exec pipeline-db psql -U airflow -d airflow -c "\dt"

# 进入容器调试
docker exec -it airflow-webserver bash
```

### 参考资料
- [Docker Compose Run vs Exec](https://docs.docker.com/compose/reference/)
- [Airflow Database Initialization](https://airflow.apache.org/docs/apache-airflow/stable/howto/set-up-database.html)
- [PostgreSQL Docker Initialization](https://hub.docker.com/_/postgres)
