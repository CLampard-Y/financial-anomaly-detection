# 文档导航

本目录收录架构说明、运行检查、问题排查、安全说明与运行快照索引。建议按下面的阅读路径选择入口。

## 阅读入口

| 目标 | 文档 |
|---|---|
| 先理解系统拓扑与角色分工 | [`architecture_design.md`](architecture_design.md) |
| 查看本地或服务器上的检查命令 | [`runtime_checks.md`](runtime_checks.md) |
| 查看已部署环境的脱敏运行快照 | [`validation/README.md`](validation/README.md) |
| 排查启动顺序、容器重启等问题 | [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) |
| 查看密钥、端口与权限相关说明 | [`SECURITY.md`](SECURITY.md) |
| 回到仓库入口 | [`../README.md`](../README.md) |
| 查看完整多节点部署流程 | [`../DEPLOYMENT_GUIDE.md`](../DEPLOYMENT_GUIDE.md) |

## 说明

- `architecture_design.md` 负责解释设计目标、组件职责与主备切换语义
- `runtime_checks.md` 收录常用验证命令、样例 SQL 与检查口径
- `validation/README.md` 是运行快照索引，用于补充部署与切换结果的可视化证据
- `TROUBLESHOOTING.md` 与 `SECURITY.md` 属于运维型附录，建议在部署前后结合查看
