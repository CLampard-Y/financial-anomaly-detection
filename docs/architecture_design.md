# System Architecture Design Document

## 1. Executive Summary
This document defines the high-availability architecture for the **Distributed Financial Sentinel (DFS)**. The system is designed to maintain **99.9% data continuity** for cryptocurrency market data, ensuring robustness even during severe network partitions in the Asia-Pacific region.

---

## 2. Design Philosophy (设计理念)

为了解决 Web3 金融场景下的数据连续性问题，本项目放弃了传统的重型集群方案（如 K8s/Celery），转而采用 **"SSH Tunneling + Airflow"** 的轻量化去中心化架构。
* **Cost-Efficiency (高性价比)**: 避免了维护 K8s Control Plane 的高昂成本，利用 `SSHOperator` 实现了**无代理 (Agentless)** 的远程调度。
* **Network-Resilience (弱网对抗)**: 针对 **HK 节点晚高峰 (UTC+8 20:00-01:00)** 频繁丢包的特性，设计了基于 **CAP 定理** 的主备切换机制，优先保证可用性 (Availability)。

---

## 3. Physical Topology (物理拓扑)

The system utilizes a **Hub-and-Spoke** topology centered around the US Master node.
```mermaid
graph TD
    subgraph US_Region [🇺🇸 US-Master (The Commander)]
        Airflow[Airflow Scheduler]
        DB[(Postgres DB)]
    end

    subgraph HK_Region [🇭🇰 HK-Primary (The Sprinter)]
        WorkerHK[Docker Worker]
    end

    subgraph JP_Region [🇯🇵 JP-Backup (The Guard)]
        WorkerJP[Docker Worker]
    end

    Airflow -- "SSH (Primary Command)" --> WorkerHK
    Airflow -.-> |"SSH (Failover Command)"| WorkerJP
    WorkerHK -- "TCP 5432 (Data)" --> DB
    WorkerJP -- "TCP 5432 (Data)" --> DB

    style US_Region fill:#e1f5fe,stroke:#01579b
    style HK_Region fill:#e8f5e9,stroke:#2e7d32
    style JP_Region fill:#fff3e0,stroke:#ef6c00
```
### Node Roles & Specifications

#### US-Master (The Commander)
- **Role**: Control Plane & Data Warehouse.
- **Specs**: High-Stability Instance (US West / Colocrossing).
- **Responsibilities**:
    - **Airflow Scheduler**: 发送 SSH 指令指挥远端 Worker。
    - **Postgres DB**: 存储清洗后的核心业务数据 (JSONB Schema)。
    - **Auditor**: 监控数据来源，当发生切换时触发 Lark/Feishu 报警。
#### HK-Primary (The Sprinter)
- **Role**: Primary Compute Node.
- **Why HK?**: **Latency Advantage**. 物理距离离 Binance/OKX 等交易所服务器最近，API 响应速度最快 (<50ms)。
- **Risk**: 国际出口带宽在晚高峰极不稳定，是本系统主要防御的故障点。
#### JP-Backup (The Guard)
- **Role**: Failover Node.
- **Activation Condition**: 仅当 Airflow 无法通过SSH连接到HK节点（Timeout/Unreachable）时被激活。
- **Why JP?**: 拥有高稳定性的BG 线路，虽然延迟稍高，但作为“兜底”保障极其可靠。

---

## 4. Failover Mechanism (容灾逻辑)
This system implements a strict **Active-Passive Failover** strategy driven by Airflow's DAG logic.
### State 1: Normal Operation (正常模式)
1. **Instruction**: **Airflow (US)** 发起 SSH 连接至 **HK-Primary**。
2. **Execution**: **HK 节点** 拉取并运行 Docker 镜像 `crypto-crawler:latest`。
3. **Ingestion**: **HK 节点** 抓取数据 -> 通过 TCP 5432 直接回写至 **Postgres (US)**。
4. **Standby**: **JP 节点** 保持空闲以节省计算资源。
### State 2: Failover Operation (熔断模式)
_Trigger Condition: SSH Connection Timeout (>30s) or Connection Refused on HK Node.
1. **Detection (感知)**: Airflow 任务 `task_crawl_hk` 因网络分区抛出异常失败。
2. **Switching (切换)**: Airflow 的 **Trigger Rule (`all_failed`)** 被激活，自动触发下游任务 `task_crawl_jp`。
3. **Recovery (恢复)**: **JP 节点** 立即启动爬虫容器接管任务。
4. **Traceability (溯源)**: 业务数据成功入库，并被自动标记为 `source_region='JP-Backup'`，便于后续审计。
5. **Alerting (报警)**: 系统检测到数据源变更，立即向运维群组发送 "Failover Alert"。

---

## 5. Security & Isolation (安全架构)
- **Network Level (网络层)**:
    - **UFW Firewall**: 实施白名单机制，数据库端口 (5432) **仅** 对 HK 和 JP 的 IP 开放，彻底屏蔽公网扫描。
    - **SSH Tunneling**: 所有控制指令均通过 RSA-4096 密钥对加密传输。
- **Application Level (应用层)**:
    - **Least Privilege**: Worker 节点连接数据库时，使用仅具备 `INSERT` 权限的专用账户，禁止 `DROP/DELETE` 操作，防止被攻破后删库。