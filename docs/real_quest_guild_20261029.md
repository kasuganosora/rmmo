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

Godot 4.7.2 headless 对最终 `gameserver-gameplay3-final` 实测：扩展真实玩法 214 项、WebSocket 流回归 15 项、基础协议联调 56 项、AOI 联调 20 项全部通过。普通战斗的 HTTP 状态/事件/写请求为 0。扩展夹具将历史页长上限设为 1，验证默认分页正常；同一场景实际挂起已收到的旧公会 HTTP 回包，在 WebSocket 发布踢出后再释放回包，验证旧名册不能恢复。

独立任务/公会/真实 3D HUD 转发测试 18 项通过，包含同上下文迟到回包、同值新发布及 `next_request_id` 不回退；公会面板测试 14 项通过。任务详情的交付和确认放弃已覆盖 3D 世界没有旧二维请求适配器的路径。

新客户端连接上一版 `gameserver-next-live-final` 的原玩法联调 132 项通过，包含新历史/公会路由不支持时的明确反馈。旧服的纯文本 404 使用无日志解析分支处理，不产生 Godot JSON 错误或调用 Mock 写入。

最终五组真实联调均退出 0，`ERROR` 与 `SCRIPT ERROR` 均为 0。日志保存在 `/workspace/.cloud-setup/gameplay3-complete-live-post-race-{quest-social,stream,legacy,basic,aoi}.log`；聚焦测试日志为同前缀的 `focused.log`。修复前的五组日志另保留为 `/workspace/.cloud-setup/gameplay3-complete-live-*.log`。

已有 `tools/test_quest_tracker.gd` 的纯追踪文本及界面断言通过；它的三个旧 MockServer 联动断言依赖本云环境缺少的 `content://map_pack/default`/`herb_gather` 数据，因此不能作为本轮真实后端的验收结果。
