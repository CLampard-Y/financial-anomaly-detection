# Distributed Financial Sentinel (DFS) 🛡️

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)]() [![Python](https://img.shields.io/badge/Python-3.9-blue)]() [![Airflow](https://img.shields.io/badge/Airflow-2.7-orange)]()

**A high-availability distributed monitoring system designed for unstable network environments.**
Targeting Web3 financial data pipelines with automatic failover capabilities across US, HK, and JP regions.

[Read in English](README_EN.md) | [中文文档](#中文文档)

---

## <a id="中文文档"></a>项目背景与核心亮点

本项目针对 **跨国网络不稳定性（尤其是香港节点晚高峰丢包）** 问题，设计了一套基于 **Airflow + SSH 隧道** 的去中心化容灾架构。

### 核心架构 (Architecture)
* **多地部署**：
    * 🇺🇸 **US-Master (大脑)**: 负责调度 (Airflow) 与数据存储 (Postgres)。
    * 🇭🇰 **HK-Primary (主节点)**: 承担 90% 抓取任务，利用地理优势低延迟抓取亚洲数据。
    * 🇯🇵 **JP-Backup (备用节点)**: 当 HK 节点超时或断连时，自动接管任务。
* **容灾逻辑 (Failover Logic)**:
    * 采用 **Trigger Rule** 机制，实现 `HK Failed -> JP Activated` 的自动切换，确保数据不丢。

### 技术栈 (Tech Stack)
* **Infrastructure**: Docker, Docker Compose
* **Orchestration**: Apache Airflow (SSHOperator)
* **Database**: PostgreSQL (JSONB schema)
* **Monitoring**: Streamlit, Lark(Feishu) Webhook

---

## Quick Start (English)

### Prerequisites
- Docker & Docker Compose
- Python 3.9+

### Installation
```bash
git clone ...
docker compose up -d