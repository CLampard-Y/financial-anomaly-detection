# 安全说明

本页说明当前仓库在密钥、端口暴露、文件权限与部署操作上的安全边界。它不提供“已完全安全”的结论，而是列出当前控制、建议检查方式和剩余风险。

相关文档：[`../README.md`](../README.md) · [`architecture_design.md`](architecture_design.md) · [`../DEPLOYMENT_GUIDE.md`](../DEPLOYMENT_GUIDE.md)

## 当前控制

### 1. 密钥与凭据管理

- `docker-compose.yaml` 通过环境变量读取 `POSTGRES_USER`、`POSTGRES_PASSWORD` 与 `AIRFLOW_FERNET_KEY`
- 根目录 `.env` 已被 `.gitignore` 忽略，不应提交到版本控制
- `.env.example` 只提供占位符值，可安全提交
- `infra/setup_server_env.sh` 通过交互式输入获取数据库密码，并生成 Airflow 管理员密码与 Fernet key

### 2. 文件与目录权限

- 建议将 `.env` 权限设置为 `600`
- SSH 私钥建议设置为 `600`，SSH 目录建议设置为 `700`
- Postgres 持久化目录位于仓库下的 `data/postgres/`，便于配合主机层权限与备份策略统一管理

### 3. 网络边界

- `postgres:5432` 对 HK / JP worker 开放，用于远端回写数据
- Airflow Web 默认映射到 `8080`，Dashboard 默认映射到 `8501`
- 当前设计假设部署环境受控，主机层会使用防火墙、白名单或私网限制暴露面

## 建议检查命令

### 1. 检查 `.env` 是否被忽略

```bash
git check-ignore .env
```

### 2. 检查关键文件权限

```bash
ls -l .env
ls -l ~/.ssh/id_rsa
ls -ld ~/.ssh
```

### 3. 检查仓库中是否存在硬编码凭据

```bash
rg "POSTGRES_PASSWORD|AIRFLOW_FERNET_KEY|AIRFLOW_ADMIN_PASSWORD" docker-compose.yaml infra airflow dashboard exporter .env.example
```

### 4. 检查端口暴露与容器状态

```bash
docker compose ps
ss -lntp | rg ":5432|:8080|:8501"
```

## 当前假设

- HK / JP 节点与 US 节点之间的网络处于受控环境
- Airflow 与 Dashboard 不直接向公网开放，或已由额外代理层提供访问控制
- 服务器操作者具备 Linux、Docker 与 SSH 基础，不以“默认全开放”模式长期运行该系统

## 剩余风险

- `airflow/dags/setup_airflow.sh` 当前为 SSH 连接启用了 `no_host_key_check`，在非受信环境中存在中间人风险
- Postgres 对远端 worker 暴露 `5432`，如果主机层防火墙缺失，暴露面会明显扩大
- Airflow Web 与 Streamlit Dashboard 默认没有额外鉴权层，直接对公网开放并不安全
- Dashboard 若以 `root` 配置为 systemd 服务，仍需结合主机权限策略评估运行边界

## 建议加固方向

- 使用防火墙或私网，仅允许 HK / JP 的固定来源地址访问 `5432`
- 为 Airflow 与 Dashboard 增加 TLS、反向代理与访问控制
- 收紧 SSH 主机校验策略，避免长期依赖 `no_host_key_check`
- 将 worker 的数据库权限收敛为更小的写入集合，减少误操作与被攻破后的影响面
