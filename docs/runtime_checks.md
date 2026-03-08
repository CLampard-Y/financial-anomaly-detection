# 运行检查与查询

本页收录常用的运行检查命令与样例 SQL，用于确认控制平面状态、业务表写入结果和主备切换痕迹。

相关文档：[`../README.md`](../README.md) · [`architecture_design.md`](architecture_design.md) · [`validation/README.md`](validation/README.md) · [`../DEPLOYMENT_GUIDE.md`](../DEPLOYMENT_GUIDE.md)

## 基础健康检查

### 1. 容器与服务状态

```bash
docker compose ps
docker exec pipeline-db pg_isready -U airflow
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health
```

用于确认 `pipeline-db`、`airflow-webserver`、`airflow-scheduler` 已启动，且 Airflow 健康接口返回 `200`。

### 2. DAG 解析检查

```bash
docker exec airflow-scheduler python -c "from airflow.models import DagBag; db=DagBag('/opt/airflow/dags'); print(db.import_errors)"
docker exec airflow-scheduler airflow dags list
```

第一条命令用于确认 DAG 无导入错误；第二条命令用于确认 `binance_global_sentinel` 与 `maintenance_data` 已被识别。

## 数据与表结构检查

### 1. 表是否存在

```bash
docker exec pipeline-db psql -U airflow -d crypto -c "\dt crypto_data.*"
```

### 2. 总行数与最新样例

```bash
docker exec pipeline-db psql -U airflow -d crypto -c "SELECT COUNT(*) FROM crypto_data.crypto_klines;"

docker exec pipeline-db psql -U airflow -d crypto -c "SELECT symbol, interval, source_region, close_price, to_timestamp(open_time/1000.0) AS candle_time, created_at FROM crypto_data.crypto_klines ORDER BY created_at DESC LIMIT 20;"
```

注意：`open_time` 为毫秒时间戳，转换时应使用 `/1000.0`。

## 运行指标查询

### 1. 新鲜度

```sql
SELECT
  symbol,
  now() - to_timestamp(max(open_time) / 1000.0) AS freshness_lag
FROM crypto_data.crypto_klines
GROUP BY symbol
ORDER BY freshness_lag DESC;
```

### 2. 近 24 小时完整性

```sql
SELECT
  symbol,
  COUNT(DISTINCT open_time) AS candles_24h
FROM crypto_data.crypto_klines
WHERE open_time >= (EXTRACT(EPOCH FROM now()) * 1000 - 24 * 3600 * 1000)
GROUP BY symbol
ORDER BY candles_24h ASC;
```

### 3. 近 24 小时备用节点占比

```sql
SELECT
  symbol,
  COUNT(*) AS candles,
  COUNT(*) FILTER (WHERE source_region ILIKE '%backup%') AS backup_candles,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE source_region ILIKE '%backup%') / NULLIF(COUNT(*), 0),
    2
  ) AS backup_pct
FROM crypto_data.crypto_klines
WHERE open_time >= (EXTRACT(EPOCH FROM now()) * 1000 - 24 * 3600 * 1000)
GROUP BY symbol
ORDER BY backup_pct DESC;
```

### 4. 重复行检查

```sql
SELECT symbol, interval, open_time, COUNT(*) AS n
FROM crypto_data.crypto_klines
GROUP BY symbol, interval, open_time
HAVING COUNT(*) > 1
ORDER BY n DESC
LIMIT 10;
```

## 主备切换验证

### 1. 查看最近 DAG 运行

```bash
docker exec airflow-scheduler airflow dags list-runs -d binance_global_sentinel --limit 5
```

### 2. 手动触发一轮抓取

```bash
docker exec -u airflow airflow-scheduler airflow dags trigger binance_global_sentinel
```

### 3. 在日志目录中查找审计信息

```bash
rg -n "Audit: Latest data from|Failover Alert" airflow/logs
```

### 4. 对照运行快照

如果需要图形化核对主备切换、数据库来源标签与 Dashboard 节点状态，可结合查看 [`validation/README.md`](validation/README.md)。

## 导出检查

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r dashboard/requirements.txt
pip install pyarrow
python exporter/export_data.py
ls -lh data_lake/binance_data_lake
```

导出成功后，目录下应出现当天日期对应的 `snapshot_YYYYMMDD.parquet` 文件。
