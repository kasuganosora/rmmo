# MockServer 维护方式

MockServer 的入口是 `scripts/net/mock_server.gd`，仅负责启动、逐帧调用、性能计时和退出清理。业务实现与状态放在 `scripts/net/server/*_module.gd`；UI、Net、RequestPipeline 继续调用原有 MockServer 方法、信号与属性。

## 职责入口

| 职责 | 模块 |
| --- | --- |
| 目录及 HUD 模型初始化 | `bootstrap_module.gd` |
| 登录、角色、进入世界、退出 | `session_module.gd` |
| 模拟时钟、施法、AI、恢复及战斗调度 | `runtime_module.gd` |
| 二维地图加载、天气、安全区、传送 | `world_module.gd` |
| 三维世界、区块工作线程、天空与环境 | `world3d_module.gd` |
| NPC 互动及距离校验 | `interaction_module.gd` |
| 移动及复活、NPC AI | `movement_module.gd`、`npc_ai_module.gd` |
| 战斗、背包、装备、掉落、采集制作、任务、社交等 | 对应命名的业务模块 |

状态与实现归同一个业务模块所有。例如，队伍模块持有队员和邀请，背包模块持有 inventory，地图模块持有碰撞与地图信息。兼容属性直接转发 getter/setter，不复制 Dictionary/Array；已有调用者对集合的修改、整体替换和标量赋值都会写到同一份状态。每个 MockServer 实例分别构造模块与集合。

跨模块调用继续通过 `ctrl` 指向宿主，保留子类覆盖、测试替身、3D 适配器和真实服务器覆盖的语义。模块构造函数只接收宿主并创建自身对象，不能在宿主其余模块尚未构造完时读取它们。启动模型初始化由 bootstrap 显式执行。

## 修改或新增接口

业务文件中的声明是唯一手工维护的来源：

```gdscript
## @server-state
var members: Array = []

## @server-api
func try_example(id: String) -> Dictionary:
	return {"ok": true}
```

`@server-api` 导出方法，`@server-state` 导出兼容属性，`@server-constant` 导出既有常量；`@server-api public_name` 可以为模块方法指定兼容名称。未标记的方法保持模块内部使用。参数默认值、返回类型和参数顺序由声明生成；重复导出、错误标记会令生成失败。

修改声明后执行：

```sh
python3 tools/generate_mock_server_api.py
python3 tools/generate_remote_boundary.py
```

不要直接编辑生成的 `mock_server_api.gd` 和 `remote_boundary.gd`。前者生成模块装配及兼容转发，后者从同一份声明生成真实服务器请求隔离层。真实模式只由 `real_server.gd` 中已实现的适配器执行请求；其他 `try_*` 返回不支持，其他 `snapshot_*` 返回空快照。新增 Mock 请求也自动进入隔离层。

当前真实服务器仍共享这些 HUD 模型与模块装配；重构没有扩大真实服务已接入的业务范围，参见 [真实服务器连接](real_server_connection.md)。

## 模拟参数

以下 ProjectSettings 位于 `project.godot` 的 `[rmmo]` 下，可在项目设置或测试中修改：

| 设置 | 默认值 | 有效范围 |
| --- | --- | --- |
| `rmmo/mock/latency_sec` | 0.35 秒 | 0–30 |
| `rmmo/mock/ai_tick_interval_sec` | 0.45 秒 | 0.01–30 |
| `rmmo/mock/combat_tick_interval_sec` | 1.5 秒 | 0.01–30 |
| `rmmo/mock/chunk_view_radius_m` | 12 米 | 1–1024 |

`mock_config.gd` 校验类型、拒绝非有限数并限制范围。默认值保持原行为，调用时读取设置。原有常量别名为兼容保留；调节以上运行参数应修改设置。

## 纯代码验收

```sh
python3 tools/generate_mock_server_api.py --check
python3 tools/generate_remote_boundary.py --check
python3 tools/test_generate_mock_server_api.py
python3 tools/test_mock_server_regressions.py
python3 tools/test_network_regressions.py
godot --headless --path . --script res://tools/_validate_server.gd -- --backend=real
```

Mock 回归包含独立实例、状态兼容、异步登录/角色/3D 进入、互动权限距离、装备与道具、掉落、采集制作、商店回购、状态取消、队伍及战斗随机结果。业务流程使用显式注册的内存测试定义，不修改外部资源。另用 `tools/test_real_server_integration.py` 对实际 Go 进程验证通信与模式切换。

旧的 `test_party_food.gd`、`test_quest_journal.gd`、`test_quest_gather_fish.gd`、`test_quest_reach_gather.gd`、`test_equipment_server.gd` 和 `test_shop_buyback.gd` 未纳入这套独立回归：它们依赖当前云环境未提供的完整目录/演示地图，部分还含有过时的 HUD 源码断言。其试运行失败不算本次验收通过；需要完整运行资源及相应测试维护后单独验收。

本次对照：重构前 `0c78f19` 的临时副本中，装备测试同样失败 7 项，回购测试同样失败 8 项。新的模块测试用显式测试定义覆盖装备和回购流程，不修改生产目录来迎合旧测试。
