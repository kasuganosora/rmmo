# 真实服务器玩法资源同步

入场协商 `gameplay_protocol=1` 后，客户端通过现有二进制 WebSocket 接收 13 类资源的条件差分和独立持久战斗事件，攻击、施法、取消、事件 ACK 均走 WS。正常新服不再每 250ms HTTP 轮询状态或事件。环境时间默认每 5 秒通过 HTTP 校准；首次入场、重连、传送保留最终世界快照和 Ready 屏障。

资源流每次只有一份待确认数据。客户端按完整世界上下文、服务器捕获修订和本地发布顺序接收，验证完整集合后 ACK；重复帧只确认一次投影，显式空集合清除旧对象，条件基丢失时全量重同步。冷技能/NPC 定义先准备数据，再检查发布代次，不能让旧加载覆盖新世界。定义临时读取失败有独立投影重试，无需等服务器再次改变状态。

战斗事件按持久游标去重和确认。重连保留当前 endpoint、账号、角色已应用的游标，重新订阅后补 ACK；缓存默认最多 64 个身份。只有明确的 `invalid_combat_cursor`（例如服务器数据库回档）才清此身份游标从 0 恢复。

WS 容量独立于 HTTP 8 MiB，超限小通知启动低频资源/分页 HTTP 恢复，默认 2 秒一次、30 秒后尝试 WS。小于 128 KiB 的服务器发送队列明确拒绝战斗事件订阅，事件收件箱也使用低频 HTTP。合法奖励不截断；新服恢复支持全部 1024 条未领取奖励。恢复沿用资源级一致性，并非整个分页集合原子快照。旧服缺少 WS 能力时保留旧 HTTP 接口，未支持批次和未领取筛选也按既有协议兼容。

本轮是资源级条件差分推送；NPC 资源变化仍发送新的附近 NPC 集合，不是 NPC 逐实体差分。服务器仍捕获并计算内容版本，不能把省下的请求/带宽称为等比例 CPU 收益。

| ProjectSettings（前缀 `rmmo/network/`） | 默认 | 范围 | 用途 |
| --- | ---: | --- | --- |
| `environment_interval_sec` | 5 | 1–60 | 独立环境时间校准 |
| `runtime_fallback_interval_sec` | 2 | 1–30 | 已协商新服容量降级读取 |
| `snapshot_capacity_retry_sec` | 30 | 1–300 | 同世界容量退避后尝试 WS/批次 |
| `projection_retry_sec` | 1 | 0.1–30 | 冷定义临时失败重试 |
| `event_resume_cache_entries` | 64 | 8–512 | 已应用事件游标身份缓存 |

纯逻辑及真实服务端验收：

```sh
godot --headless --path . --script res://tools/test_runtime_snapshots.gd -- --backend=real
godot --headless --path . --script res://tools/test_runtime_stream_client.gd -- --backend=real
godot --headless --path . --script res://tools/test_combat_stream_client.gd -- --backend=real
python3 tools/test_real_server_integration.py --server-bin /path/to/gameserver --server-repo ../rmmo_server --stream
```

`--stream` 使用独立临时测试数据，实际计数 HTTP：预 Ready 等待后推送连续有效、战斗与 ACK 使用 WS、正常战斗段 HTTP 为 0、重连恢复资源及事件游标。正式地图、美术资源不参与修改。
