# 楼层隔离与临时副本试玩

2026-10-01。当前 3D 编辑器 UI 与 MCP 共用配置、校验和撤销事务；旧二维 MCP 保持停用。

## 界面使用

左侧「楼层/试玩」页提供楼层起始高度、层高、其他楼层隐藏/淡化、上一层/下一层，以及试玩出生点 XYZ。点击「应用」提交数值；「点击地面选择出生点」可直接拾取画布中的朝上表面，Esc 取消。绿色圆盘标记出生脚点。

「从此处开始临时试玩」、右上「临时试玩」和 F5 使用当前内存中的地图，包括未保存修改。准备完成后进入独立试玩，顶部按钮结束并返回原编辑器。准备期间可点取消或按 Esc；点击窗口关闭会先结束试玩。楼层、出生点设置可撤销/重做，并随地图保存和草稿恢复。

## 楼层规则

- 起始高度 `base_height` 和范围高度 `floor_height` 确定当前层：下边界包含、上边界不包含，比较使用 0.001 米容差。默认关闭隔离，起始高度 0 米，层高 3 米，其他层隐藏。
- 自动瓦片按 `tile3d.elevation` 归层；厚度不超过 0.5 米的 `ground` 地板按顶面归层；其他物件按变换后包围盒底部归层。
- 其他楼层可隐藏或淡化，但均不能被鼠标拾取、框选或直接修改。物件列表保留全部记录；跨层整组选择会拒绝，需先关闭隔离。隐藏/锁定标记仍可独立管理。
- 同一物件跨楼层拖动时保持完整拖动事务，松开后重新归层并清理当前选择。数值移动后立即归层。
- 楼层隔离只影响编辑视图，不裁切网格、不改变正式游戏碰撞。试玩与运行时始终加载完整地图，包括编辑器隐藏物件。自动瓦片邻接仍按完整地图计算；直接擦改被隔离的已有块会跳过。
- 按明确坐标创建物件或放置跨层预制件可以产生范围外成员，切换楼层后即可编辑；MCP 返回全部创建 ID，不依赖当前选择。

单个 GLB 是一个物件，按整体包围盒归层，不能自动把内部楼板分开隐藏。多层建筑需拆成独立物件或预制件成员。本功能也不包含剖切平面、楼层命名或复杂房间可见性系统。

配置保存在 `map_meta.editor_view`，旧地图使用默认值。保存、打开、草稿和运行时加载均校验结构。`base_height` 范围为 ±10000 米，`floor_height` 为 0.1–1000 米，`outside` 为 `hide` 或 `dim`，`isolation` 为布尔值。

## 出生点与临时会话

出生点是**脚点**，Y 向上、单位米，默认 `[0,0,4]`，各轴范围 ±100000 米。鼠标拾取只接受法线 Y ≥ 0.7 的朝上表面。设置出生点时允许先存坐标，启动试玩时再检查完整运行地图：脚下 0.12 米内需有有效支撑，半径 0.3 米、高 1.8 米的角色胶囊空间不得被占用。没有支撑、位于物件内部等情况会失败并清理临时副本。

试玩将文档快照保存到内容根内的 `cache/world3d/playtests/<随机ID>/map.gltf`，不调用正式地图保存，不修改编辑器的磁盘版本基线、撤销历史或未保存状态。原编辑器实例保留，返回后镜头和选择不变。资源依赖继续引用授权内容根中的素材；其他地图从其现有文件读取，传送返回正在编辑的原地图时重定向到本次未保存副本。

试玩使用独立 3D 物理世界和内存服务端，暂停原服务端。已有角色时复制其背包和装备；没有角色时使用临时角色（需要角色资源可用）。事件开关、任务等使用试玩状态，不是正式存档的完整续玩。宝箱奖励、消耗、商店交易和跨图事件状态仅作用于本次试玩。退出后恢复原客户端会话和原服务端，正常退出/取消/失败均删除本次拥有的临时目录；进程异常崩溃可能留下缓存目录。

仅图形编辑器支持运行试玩；headless 可编辑楼层/出生点设置，但 `start_playtest` 会明确报错。地图快照保存仍同步执行，异步准备/加载阶段可取消。

## MCP

服务发现当前共 63 项工具。完整入口与安全约束见 [world_editor_mcp.md](world_editor_mcp.md)。楼层/试玩批次七项：

| 工具 | 参数与返回 |
| --- | --- |
| `get_editor_view` | 无参数；返回 `view`：完整楼层和出生点配置 |
| `set_floor_view` | 可选 `isolation`、`base_height`、`floor_height`、`outside`，增量更新，一次撤销 |
| `set_playtest_spawn` | 必填 `position:[x,y,z]` 脚点，更新地图设置，一次撤销 |
| `pick_playtest_spawn` | 必填 `screen:[x,y]`，相对编辑画布左上角的像素坐标，一次撤销 |
| `start_playtest` | 可选 `position:[x,y,z]`，只覆盖本次出生点，不修改地图设置；异步返回状态 |
| `stop_playtest` | 无参数；取消准备/加载或结束运行，通常先返回 `stopping` |
| `playtest_state` | 无参数；返回 `phase`、`active`、`error`、`source_path`、`temporary_path`、`spawn` |

状态流程为 `idle → preparing → loading → running → stopping → idle`；校验或加载失败进入 `failed`，可修正后重试。结构非法等同步拒绝返回 `ok:false`；接受启动后出现的异步失败需查看 `phase` 和 `error`，不能把初次启动返回的 `ok:true` 当作已经进入游戏。

```json
{"name":"set_floor_view","arguments":{"isolation":true,"base_height":3,"floor_height":3,"outside":"dim"}}
{"name":"set_playtest_spawn","arguments":{"position":[2,3,4]}}
{"name":"start_playtest","arguments":{}}
{"name":"playtest_state","arguments":{}}
{"name":"stop_playtest","arguments":{}}
```

以上为 `tools/call` 的 `params`。客户端等待 `running` 后才操作试玩；结束后等待 `idle` 再继续编辑。试玩期间 `preview_map` 返回游戏视图，只读查询保持可用，写工具仅允许 `stop_playtest`。UI 正在拾取出生点时，MCP 写操作返回忙碌。`editor_state` 包含 `editor_view`、`spawn_picking`、`playtest`；`list_objects.in_current_floor` 表示物件是否在当前显示范围内。

## 验收

`tools/test_world3d_playtest.gd` 使用临时地图和真实 HTTP MCP，覆盖工具发现、楼层隐藏/淡化、跨层与锁定保护、跨层放置返回 ID、非法调用无副作用、撤销/重做、保存/重开、出生点鼠标拾取与 Esc；图形模式进一步验证准备取消、无支撑/阻挡出生点拒绝、未保存地图和事件进入试玩、奖励状态隔离、跨地图往返、原文档/镜头/选择/历史恢复，以及临时文件清理。headless 分支验证运行限制。

Windows GPU 测试均由 `tools/run_godot_background.py` 在不激活的独立桌面运行。日志和截图位于外部 `review_artifacts/editor_playtest/`，不覆盖用户地图。

2026-10-01：本项 GPU/headless 验收及 `test_world3d_mcp`、`test_world3d_transform`、`test_world3d_groups_ui`、`test_world3d_placement`、`test_world3d_height_terrain`、`test_world3d_surface_paint`、`test_world3d_recovery`、`test_world3d_gameplay`、`test_world3d_editor` 九项后台 GPU 回归全部通过。
