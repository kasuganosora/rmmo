# 真实服务器通信分支

分支：`feat/real-server-transport`，基于客户端 `c333a6466009d910957b2b05d8fc58ad2f81741f`。
Go 服务端配套分支：`rmmo_server/master`。
协议源 SHA256：`afe728e0ab28e9ca84c44688302be8952a450438fd26f68e039e0857ad2283e8`。
本分支只修改功能代码、配置和测试；不修改地图、角色、模型或纹理资源。

## 开关与连接

登录页展开“连接设置”，勾选“连接真实服务器”并填写地址。未勾选时继续使用
MockServer。切换只在退出登录后进行；真实服务器断开或返回错误时保持真实模式。
真实账号由“注册真实服务器账号”按钮创建，登录失败不会自动注册。

也可以使用启动参数：

```sh
godot --path /path/to/rmmo -- --backend=real --server-url=http://127.0.0.1:7777
godot --path /path/to/rmmo -- --backend=mock
```

配置优先级：项目设置 < 环境变量 < 命令行。命令行参数放在 Godot 的 `--` 之后。
环境变量为 `RMMO_CLIENT_BACKEND=mock|real`、`RMMO_SERVER_URL`。账号密码、Bearer token
和世界票据只保留在内存，不写入项目、日志或用户配置。

| 项目设置 | 默认值 | 用途 |
| --- | --- | --- |
| `rmmo/network/use_real_server` | `false` | 启动连接模式 |
| `rmmo/network/server_url` | `http://127.0.0.1:7777` | 服务端源地址 |
| `rmmo/network/request_timeout_sec` | `10` | 连接、RPC 和 HTTP 超时，限制在 1–60 秒 |
| `rmmo/network/movement_hz` | `20` | 方向意图发送频率，限制在 5–30 Hz |
| `rmmo/network/snapshot_interval_sec` | `0.25` | 业务快照刷新间隔，限制在 0.1–5 秒 |
| `rmmo/network/environment_interval_sec` | `5` | 新服流式模式环境时钟采样间隔（秒，1–60）。 |
| `rmmo/network/runtime_fallback_interval_sec` | `2` | 新服容量不足时低频 HTTP 恢复（秒，1–30）。 |
| `rmmo/network/projection_retry_sec` | `1` | 定义临时失败后投影重试（秒，0.1–30）。 |
| `rmmo/network/event_resume_cache_entries` | `64` | 按服务器/账号/角色保存已应用事件游标数量（8–512）。 |
| `rmmo/network/snapshot_capacity_retry_sec` | `30` | 合法资源超过批次容量后，当前世界上下文重试批次的间隔，限制在 1–300 秒 |
| `rmmo/network/event_interval_sec` | `0.1` | 战斗事件轮询间隔，限制在 0.05–5 秒 |
| `rmmo/network/map_paths` | `{}` | 服务端地图身份到本地资源路径的显式映射 |

地址支持 `http` / `https` / `ws` / `wss`，不带路径；传输自动使用 `/ws` 和 `/v1/`。
HTTPS 对应 WSS，保留系统证书验证。HTTP 业务接口禁止跳转，避免跨源转发认证头。

## 地图配置

客户端和服务端必须安装对应资源包，但资源根可以不同。客户端从服务器返回的
`map_ref` 选择视觉地图，使用服务器的脚底米制位置加 0.9m 得到角色中心。
不能再以作者机器上的绝对路径、默认出生点或本地路径哈希替代服务器身份。

默认通过资源包目录查找唯一的 `pack_id/map_name`。存在不同版本、缓存地图或
自定义文件布局时，显式配置，例如在 `project.godot` 的 `[rmmo]` 段中：

```ini
network/map_paths={
"default/editor_yard": "packs/default/maps/editor_yard/map.gltf",
"prototype/shared_yard": "cache/world3d/p4_yard/map.gltf"
}
```

相对路径以客户端 `rmmo/content_root` 为根；绝对路径也必须位于该根内。
已有地图若声明 `map_ref`，必须与服务器返回值一致。缺失、歧义、越界或身份不同
会中止入场，不生成或覆盖用户地图。

服务端示例：

```sh
gameserver -content /path/to/server-content -map default/editor_yard
```

## 已接通的流程

### 距离视野同步（2026-10-28）

入场/重连请求 `visibility_protocol=1`，以服务端返回值确认是否启用距离 AOI。旧服务端或关闭该能力时保留原有同地图协议。视距、滞回、节流和人数上限由服务端配置，客户端不据本地预测擅自显示远处角色。

`remote/peer_visibility.gd` 维护当前世界上下文的同行集合与单调修订：进入/更新接收完整角色状态，隐藏只移除对应代次的显示，不写永久离开墓碑，因此同一身体可重新进入视野。完整快照替换集合；旧消息忽略，增量跳号通过带上下文的 `snapshot_actors` 恢复。传送、重连清空旧流，旧上下文不能凭更大的修订号覆盖新世界。HTTP 与 WebSocket 的重复快照也不会回退 Ready 或位置。

新增逻辑检查与真实双客户端联调：

```sh
godot --headless --path . --script res://tools/test_peer_visibility.gd -- --backend=real
python3 tools/test_real_server_integration.py \
  --server-bin /absolute/path/to/gameserver \
  --server-repo /absolute/path/to/rmmo_server --aoi
```

纯逻辑 18 项、真实双客户端 20 项通过，覆盖双方跨视距隐藏、滞回、同代次重入、晚到 HTTP、修订跳号实际 RPC 恢复、重连与永久离场后新身体入场。双客户端场景仅在临时示例副本移除游走 NPC，防止其碰撞阻断边界行走；不改正式资源。原有真实通信 56 项和玩法 125 项也通过。服务端的完整 tick、带宽及负载边界记录位于配套仓库 `docs/distance-aoi-results-20261028.md`。

- 二进制 Protobuf / WebSocket 注册、登录、角色列表和基础外观建角。
- `enter_world`、世界会话 v2、地图加载后的 Ready 票据、主动退出及重连。
- 服务器时间推进的方向、跑步和跳跃意图；客户端只显示服务器位置，不运行
  MockServer 的物理、重力、NPC AI、奖励和战斗模拟。点击寻路使用 Go 返回的路径。
- 自身/附近玩家快照、带实例 generation 的离开通知、服务器传送后的重新加载。
- 带 Bearer 的 JSON GET 和带完整 WorldContext 头的 POST 入口。
- 入场时恢复背包、属性、成长、生命、实体、技能、状态、区域、队伍、联盟、奖励、
  环境及附近地图交互快照；分页交互完成后再次核对世界会话，再允许 Ready。
- NPC/怪物的实际位置、生命和生成代次映射到可选择的运行时角色；普通攻击、单体/自身/地面技能、药水和施法取消调用真实接口。技能目录、冷却、属性与状态图标来自服务器定义和快照。
- NPC 对话、任务接受/交付/放弃、可信商店购买/出售/回购、背包整理/拆分/锁定/穿脱装备/分配属性；相同物品的不同堆叠使用独立实例 ID。
- E 键领取附近的服务器击杀掉落，或与附近 NPC/地图对象交互；掉落按服务器账本整组领取，满包失败保留账本。
- 死亡与复活状态来自服务器；复活后重新加载新代次的地图并确认 Ready。
- 门窗的服务器状态应用到运行时碰撞/表现；`set_building_component_state()` 在真实模式提交版本化交互，只接受 0/1，服务端确认前不改变本地姿态。
- E 键的环境菜单可以选择附近的门、窗、开关和房屋权限。个人房屋支持按角色名字共享进入、门窗操作或共同管理；公会驻地读取服务器可信名册，公共建筑允许任何人出入。私人入口打开时访客可进入，全部入口关闭后按授权准入；开窗不开放房屋。仅进入权限可开入口通行，屋内被撤权访客也可开门离开。
- 战斗事件按游标去重、确认；断线取消待处理请求，不重新发送旧业务。

Ready 前、断线后和错误世界代次下不发送移动。地图变化会取消旧路径/Ready 回调，
旧请求不会换上新上下文自动重放。Leave 错误时查询 `/v1/world/session` 恢复结果，
不会盲目重复 Leave。异步 HTTP 和 RPC 在断开时都会得到失败结果。

## 后续对接边界

本分支完成上述核心玩法与空间逻辑的双向接入，尚未适配全部 MMO 业务界面。
现有 Go 协议没有自定义捏脸字段，因此真实模式创建页使用基础外观；不会丢弃
用户编辑的捏脸数据后谎报已保存。附近玩家协议目前只有空间状态，角色表现使用
现有默认模型；完整外观、装备和表情广播仍需扩展协议。

交易、邮件、公会创建/加入/退出、队伍管理、坐椅子、本地主动传送及其他尚未显式适配的业务继续返回 `unsupported_remote_operation`。公会驻地可绑定已有服务器名册；队伍/联盟原始读模型不等于完整界面接入。真实模式不会使用 Mock 数据补齐这些业务。

房屋界面只显示服务器返回的权限，管理者在房屋附近才能修改。版本冲突或保存失败显示错误并由玩家刷新，不自动重放；断线也不会本地授予权限。服务端通过 `-housing` / `RMMO_HOUSING` 配置真实建筑 UUID、入口组件 key 和保护范围，默认不替正式地图指定房主。完整部署说明见服务端 `docs/housing.md`。

业务请求由 `remote/gameplay.gd` 串行执行，统一分配当前序号并携带世界上下文。异步回调只返回请求结果，界面动作通过 `poll_combat_tick()` 交付一次，以兼容现有直接调用和 RequestPipeline 两种入口。操作成功但刷新失败时提示等待同步，不自动重放写请求。HTTP JSON 保留浮点全精度；放弃任务直接回传服务器 `accepted_at_key` 字符串，避免显示时间戳的解析误差改变任务身份。

角色胶囊参数由服务端 `body-profiles` 策略选择，经 `Actor3D.body_radius/body_height` 下发；旧服务端缺失参数会明确中止挂载。客户端离线导出命令：

```sh
godot --headless --path . --script res://tools/export_server_body_profiles.gd -- \
  --backend=real --manifest=/tmp/avatars.json --content-root=/path/to/rmmo_runtime \
  --output=/tmp/body-profiles.json
```

清单为 `[{"gender":"male","look_id":"1"},{"gender":"female","look_id":"tall","body_shapes":{"height":1}}]`。工具读取现有控制点和 morph JSON，复用客户端 `standing_height()` 规则，写出策略和来源 SHA；不加载渲染资源，也不改写资源。必须将实际发布的外观身份与对应配方一起管理。未配置身份沿用服务器默认尺寸。服务端配置示例见配套仓库 `docs/real_gameplay_connection.md`。

`remote_boundary.gd` 自动覆盖 MockServer 的所有 `try_*` / `snapshot_*`；真实实现
显式覆盖已支持的方法。复用的目录与 HUD 模型仅作为显示缓存，不构成服务器授权。
后续增加 Mock 接口必须重新生成并检查边界，避免继承到本地业务行为。

## 验证和复现

```sh
python3 tools/generate_server_protocol.py --check
python3 tools/generate_remote_boundary.py --check
python3 tools/test_network_regressions.py
python3 tools/test_mock_server_regressions.py
python3 tools/test_body_profile_export.py
godot --headless --path . --script res://tools/test_real_server.gd -- --backend=real
python3 tools/test_real_server_integration.py \
  --server-bin /absolute/path/to/gameserver \
  --server-repo /absolute/path/to/rmmo_server
# 同一命令加 --gameplay，执行临时玩法、门窗和策略的实际联调。
```

协议描述由所附 `scripts/net/protocol/game.proto` 生成，保留原文件 SHA256。
更新服务端协议后复制该文件并运行 `generate_server_protocol.py`，不要手工改描述表。
通信编解码限制帧大小、嵌套深度和字段数量；uint64 序号通过 Protobuf 整数传递。

集成脚本在临时目录复制服务端自带的合成示例资源，启动真正的 Go 服务，再运行
Godot。覆盖注册、基础建角、状态恢复、Ready、权威移动、服务器寻路、HTTP 鉴权和
世界请求头、旧代次隔离、断开回调、重连及退出后账号/角色仍可读取。
不会连接生产账号或修改用户资源；图形角色、完整真实地图和公网 TLS 部署仍需
在拥有对应资源的运行环境完成验收。

本轮真实 Go 联调：连接边界 56 项、核心玩法及房屋互动 125 项通过，覆盖门窗、双账号共享管理、任务、交易、背包、技能、事件 ACK、掉落、死亡复活及重连。现有 MockServer 177 项、网络/路径消费 50 项检查通过；协议与边界生成器同步检查、GDScript 解析和纯逻辑尺寸导出检查通过。所有玩法、地图与策略的测试修改均发生在临时目录，正式资源未改动。完整外部美术、图形界面实拍与公网 TLS 部署仍需在对应资源环境验收。
