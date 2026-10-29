# 真实任务日志与公会客户端（2026-10-29）

本轮客户端继续使用真实服务器的权威状态。普通移动、战斗命令、战斗事件及玩法资源更新沿用既有协商后的 WebSocket 通道；任务历史与公会管理仅在用户打开页面或提交操作时使用 HTTP，没有增加轮询任务。

## 任务页面

- “正在进行”读取 `progression.quests`；已交付任务从活跃登记簿移出。
- “已完成”按需调用 `GET /v1/gameplay/quest-history?cursor=...`，由服务器按 `min(20, quest_history_max_page)` 选择默认页长，显示冻结的完成名称、奖励数额、完成时间，并提供上一页、下一页、刷新；显式 API 页长仍可指定。
- 完成记录用 `history:<receipt-id>` 作为界面选择 ID，避免与重新接受的同一任务混淆；翻页不会污染任务追踪列表。
- 当前世界上下文变化时清空历史缓存，过期异步回包不覆盖新页面。旧服务器的 404/405 显示不支持提示，并记忆能力结果直到重连。
- 交付与放弃捕获服务器给出的 `acceptance_id`；放弃继续携带精确的 `accepted_at_key`。服务端拒绝不产生本地奖励。

`reach_level`、`environment_state`、`environment_operate`、`complete_instance` 的说明与权威进度接入既有任务追踪和详情页。环境目标展示操作/状态、对象及所属地图；等级和副本目标显示要求等级或目标副本。可交付状态只根据服务器进度计算，不在客户端累计环境操作或实例通关次数。

## 公会契约

真实适配器提供创建、邀请、接受/拒绝、踢出、退出、解散、会长转让及主动刷新。`snapshot_guild()` 包含服务端名册、邀请、费用、人数上限及客户端 `supported`/`loaded` 状态。操作通过现有 deferred `response_ready` 契约返回，界面动作仅在既有权威事件通道投递一次。

服务端实时公会状态放在既有 `progression.guild` 内，玩法资源仍为原来的 13 项。每个写请求使用服务端 `next_request_id`，并保留用户提交时看到的 `guild_id` 和 `expected_revision`；失败仅刷新状态，不自动重试写入。公会变动后的住房访问权限继续由服务器决定。

同一世界上下文中，公会 HTTP 请求发出后若 WebSocket 已发布新快照或其他 HTTP 已发布新名册，迟到回包保留已发布状态，避免已确认的踢出、邀请和 `next_request_id` 回退。

## 验证

- `tools/test_remote_quest_social.gd`：历史翻页投影、冻结名称、旧服务器降级、过期上下文、名册事件去重、身份/版本保留、新目标文本和可交付状态、详情选择、重连缓存清理。
- `tools/test_runtime_snapshots.gd`：既有 13 项资源、条件快照、迟到响应及异步 hydration 回归。
- `tools/test_request_pipeline.gd`：同步/异步请求关联与重复响应处理回归。
- `tools/test_guild_panel_authority.gd`：异步刷新、多个邀请、名册元数据、会长转让、重连、失败反馈以及 Mock 行为的单次投递。
- `tools/test_real_gameplay.gd` 与 `tools/real_gameplay_fixture.py`：临时内容副本中的真实任务、环境目标、历史分页、公会成员管理、实时邀请/踢出及重连。临时夹具不修改用户地图或美术资源。

扩展联调使用 `python3 tools/test_real_server_integration.py --server-bin <binary> --server-repo /workspace/rmmo_server --quest-social`。原 `--gameplay` / `--stream` 继续使用旧协议可识别的内容；对没有历史能力的旧服务器额外断言新功能明确返回不支持。

上一轮 Godot 4.7.2 headless 对 `gameserver-gameplay3-final` 实测：扩展真实玩法 214 项、WebSocket 流回归 15 项、基础协议联调 56 项、AOI 联调 20 项全部通过。普通战斗的 HTTP 状态/事件/写请求为 0。扩展夹具将历史页长上限设为 1，验证默认分页正常；同一场景实际挂起已收到的旧公会 HTTP 回包，在 WebSocket 发布踢出后再释放回包，验证旧名册不能恢复。

独立任务/公会/真实 3D HUD 转发测试 18 项通过，包含同上下文迟到回包、同值新发布及 `next_request_id` 不回退；公会面板测试 14 项通过。任务详情的交付和确认放弃已覆盖 3D 世界没有旧二维请求适配器的路径。

新客户端连接上一版 `gameserver-next-live-final` 的原玩法联调 132 项通过，包含新历史/公会路由不支持时的明确反馈。旧服的纯文本 404 使用无日志解析分支处理，不产生 Godot JSON 错误或调用 Mock 写入。

上一轮五组真实联调均退出 0，`ERROR` 与 `SCRIPT ERROR` 均为 0。日志保存在 `/workspace/.cloud-setup/gameplay3-complete-live-post-race-{quest-social,stream,legacy,basic,aoi}.log`；聚焦测试日志为同前缀的 `focused.log`。修复前的五组日志另保留为 `/workspace/.cloud-setup/gameplay3-complete-live-*.log`。

原有三个 Mock 任务联动断言的外部内容依赖已用测试专用临时夹具补齐；当前测试在 Godot 4.7.2 上 26 项通过，退出 0、零 ERROR。旧提交控制组与夹具清理证据见 [任务追踪 Mock 测试隔离验收](quest_tracker_fixture_review_20261029.md)。生产 Mock、正式地图和美术未因此修改。

## 副本任务完整链路补验

独立 `--instance-quest` 模式使用临时内容目录中的 `tutorial/instance_trial` 模板、单个最终遭遇及 `complete_instance` 任务。实际 Godot 客户端接取、放弃并重新接取任务，通过已有低层 HTTP 进入副本，再使用真实适配器准备地图、确认 Ready 和 WebSocket 战斗击杀最终遭遇。服务端发布权威通关后，任务进度达到 1；返回交付获得 37 金币与 2 个物品。再次读取通关状态不会增加进度，旧 `acceptance_id` 的交付被拒绝，当前接取身份的交付重放成功但不重复发奖。测试没有写入数据库、任务进度或死亡账本，也没有注入运行副本到资源路径的映射。

该链路先复现了运行副本身份 `_instance/...` 无法按普通地图文件解析的问题，日志为 `/workspace/.cloud-setup/gameplay3-instance-before-fix.log`。修复后，`prepare_authoritative_map()` 对副本异步读取服务端 `/v1/gameplay/instances` 顶层 `template_map`，校验根副本/附属地图身份及连接、世界上下文后，才发布本地资源路径。通信、Ready 继续使用运行副本身份。加载页面将验证时的上下文、连接和服务器实例写入待交接场景，世界入场再次核验，阻止旧场景跨实例或重连后被重新标记。普通旧地图缺少 authored `map_ref` 时仍仅允许同上下文成功准备的精确文件；副本必须携带模板身份。

`tools/test_instance_map_preparation.gd` 直接执行实际加载页面身份门及世界 Ready 前置门，覆盖根图/附属图、错误描述符、缺失资源、迟到 HTTP、同模板不同运行副本、连接替换、旧角色位置及普通地图兼容。最后补充的同连接入场取消分支释放入场锁，并发送一次失败信号；实际加载页面收到后隐藏进度、显示返回按钮，替换连接的旧请求则不通知新会话。

本轮 Godot 4.7.2 headless 实际结果如下，所有命令退出 0，`ERROR` 与 `SCRIPT ERROR` 均为 0。日志前缀为 `/workspace/.cloud-setup/gameplay3-instance-final-`。

| 测试 | 通过断言 | 日志后缀 | 代码验证时点 |
| --- | ---: | --- | --- |
| `--instance-quest` 副本任务完整链路 | 50 | `instance.log` | 最后取消通知补丁后复跑 |
| 基础真实协议 | 56 | `base.log` | 最后取消通知补丁后复跑 |
| `--stream` WebSocket 流 | 15 | `stream.log` | 地图准备/加载门修复后，最后取消通知补丁前 |
| 旧服 `--gameplay` | 132 | `legacy.log` | 地图准备/加载门修复后，最后取消通知补丁前 |
| `--quest-social` 原三项玩法 | 214 | `quest-social.log` | 地图准备/加载门修复后，最后取消通知补丁前 |
| `--aoi` 可见性 | 20 | `aoi.log` | 地图准备/加载门修复后，最后取消通知补丁前 |

地图准备与实际加载门聚焦测试最终 24 项通过，退出 0、零 ERROR，日志 `/workspace/.cloud-setup/gameplay3-instance-map-focused.log`。新服使用 `gameserver-gameplay3-final`，旧服使用 `gameserver-next-live-final`。本轮未改变服务器实现，也未重新运行 Go 测试；服务器既有验证由主任务报告记录。

本次覆盖真实 Godot 通信、服务器入退副本/战斗/通关/交付及 headless 加载身份门。副本入退由现有低层 API 驱动，未新增或验收专用副本 UI；没有进行 GPU 渲染或完整可视副本场景验收。正式地图与美术保持不变。
