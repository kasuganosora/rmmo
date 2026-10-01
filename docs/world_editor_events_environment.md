# 三维地图事件、环境与遮挡轮廓

第三批基础功能包括五类事件模板、地图光照与雾、运行时玩家遮挡轮廓。UI 与当前 3D MCP 共用 `gameplay_tools.gd`，使用相同的校验、文档记录、撤销与保存流程。旧二维 MCP 继续停用。

## 事件模板

左侧 **事件** 页中，选择一个物件，选模板、填写参数，点击“应用到所选物件”。也可展开“在指定位置新建事件”，填写脚点坐标后创建独立标记。支持普通物件和导入模型；椅子、旧传送点、敌对或伙伴 NPC 有独立交互，不能直接附加模板。

| 模板 | 参数和行为 |
| --- | --- |
| 对话 `dialogue` | `text` 对话，`once` 是否只执行一次，`empty_text` 再次交互提示 |
| 宝箱 `chest` | `item_id`、`quantity`、`gold`；至少一种奖励；默认只领取一次 |
| 采集 `gather` | `item_id`、`quantity`；默认只采集一次 |
| 传送 `transfer` | 内容根内已有 `.gltf` 的 `map_path`，目标脚点 `spawn`；默认接触触发 |
| 商店 `shop` | 从现有商店目录选择 `shop_id`，沿用服务端价格、购买、出售、回购流程 |

公共参数：`name`、`enabled`、`trigger`（`action` 按 E 或 `player_touch` 接触）、`required_switch`、`required_item`、`required_quantity`、`set_switch`。前置物品仅检查持有数量，不消耗。填写的前置条件同时成立才执行，完成后可以打开一个全局开关。

空间参数都是米：`offset` 从物件原点偏移；`touch_size` 是接触盒的三轴尺寸；`radius` 为按键交互距离。偏移和盒朝向跟随物件旋转，尺寸不随模型缩放改变。新建位置与传送出生位置是脚点；普通标记的物件原点在盒体中心。

模板保存在 `record.event_template = {version: 1, template, parameters}`，完整参数经校验后编译为已有事件页和命令。模板优先于物件原来的事件数据；移除模板保留原数据和物件。生成预览仅展示命令，不执行奖励或传送。

- 锁定、隐藏物件不能修改或清除模板。隐藏依然只影响编辑器，运行时保留事件；要停用运行时事件请关闭 `enabled`。
- 物件复制、分组变换、预制件保存/放置会保留事件。每个副本有独立物件 ID，因此一次性奖励状态彼此独立；全局开关名称仍共享。
- 一次性状态使用已有运行时的地图 ID + 物件 ID + 自开关 A，跨地图往返保持，切换角色/新游戏会话按既有逻辑重置。本批未增加跨登录的存档服务。
- 领取奖励前用当前背包规则检查完整容量；满包或只能容纳一部分时，不发放部分奖励、不消耗一次性状态。
- 按 E 可以找到普通物件和多网格模型上的事件；模型自己的碰撞不会挡住自身交互，其他实体墙会阻挡。接触检测包含两帧脚点之间的线段，减少快速跨过小区域时漏触发。
- 传送目标沿用外部内容根约束，拒绝越界、链接目录和不存在的文件。目标地图是引用，保存预制件不会递归打包另一张地图；移动地图文件后应更新引用。

## 环境与轮廓

左侧 **环境** 页提供白天、黄昏、夜晚预设，以及主光方向/颜色/强度、环境光、背景色、雾开关/密度/颜色。点击“应用环境设置”即时预览；设置保存到 `map_meta.environment`，重开编辑器、进游戏、地图传送均会应用。改变预设会填入该时段的光照值，仍可继续修改。游戏中的 N 键临时切换昼夜，不写回地图文件。

玩家遮挡轮廓可设置启用、颜色和 1～6 像素宽度。游戏根据相机到玩家头、躯干、脚附近的射线判断是否被实体挡住；遮挡时绘制玩家实际几何的外轮廓。蒙版使用同一套角色网格，因此保留蒙皮、装备及 GPU 变形；换装新增的几何会自动加入。无遮挡或关闭时停止额外的蒙版渲染。3D **可见层 20** 为本地玩家蒙版保留，不能给场景物件使用。

编辑器没有可操控玩家，轮廓效果需在游戏中查看；雾与光照可以在编辑画布预览。无碰撞装饰不会触发遮挡检测；当前不是逐像素深度判定，极窄遮挡物可能落在三条检测射线之间。

## MCP

当前总计 65 个工具；协议与安全约束见 [world_editor_mcp.md](world_editor_mcp.md)。事件/环境批次新增：

| 工具 | 用法 |
| --- | --- |
| `list_event_templates` | 五类模板默认值及参数 schema |
| `list_event_resources` | `query`、`offset`、`limit` 分页返回物品/商店 ID；分别分页并返回各自总数 |
| `create_event_template` | `template`、`position` 脚点、可选 `parameters` |
| `set_event_template` | `id`、`parameters`、可选 `template`；同类型增量更新，切换类型重新用默认值 |
| `clear_event_template` | `id`；一次撤销，只清模板 |
| `get_environment` | 返回完整有效环境，包括旧地图默认值 |
| `set_environment` | 直接传需要修改的环境字段；`preset` 先填预设，同次显式字段再覆盖 |

```json
{"name":"create_event_template","arguments":{"template":"chest","position":[3,0,2],"parameters":{"name":"庭院宝箱","gold":25}}}
{"name":"set_event_template","arguments":{"id":"obj_2","template":"dialogue","parameters":{"text":"欢迎来到庭院。","set_switch":"met_gardener"}}}
{"name":"set_environment","arguments":{"preset":"sunset","fog_enabled":true,"fog_density":0.015,"outline_enabled":true,"outline_width":3}}
```

调用时使用真实物件/目录 ID。非法字段、数量、物品或商店、路径、保护状态均在修改前拒绝；无变化操作不增加撤销。文档、预制件、恢复草稿和运行时加载均校验模板/环境结构，损坏的已编写地图不会静默退化为无事件场景。

## 验收与后续范围

`tools/test_world3d_gameplay.gd` 通过真实 HTTP 验证全部新增工具、非法调用无副作用、锁定/隐藏、混合撤销重做、精度、预制件实例、草稿恢复和保存重开；图形模式检查两页界面。运行时验证条件、满包及部分容量、一次性奖励、跨图状态、多网格模型交互、墙体阻挡、接触传送和 3D 商店购买/出售/回购；实际三维场景另验收玩家轮廓挂载、按 E 对话及切换地图后的环境更新。

`tools/test_world3d_outline.gd` 在后台 GPU 场景中检查无遮挡、被墙完全遮挡、透明蒙版、开关、追加角色几何、释放后恢复可见层。截图和日志保存在外部 `review_artifacts/editor_gameplay/`。

2026-10-01：上述两项及 `test_world3d_mcp`、`test_world3d_height_terrain`、`test_world3d_surface_paint`、`test_world3d_recovery`、`test_world3d_groups_ui`、`test_world3d_editor` 六项回归均通过独立后台桌面的 GPU 测试。

本批提供基本条件和生成命令预览，尚无任意事件页/命令列表可视化编辑器、分支选择编辑或定时采集刷新。楼层隔离显示、临时副本试玩与指定试玩出生点已交付，见 [world_editor_playtest_floors.md](world_editor_playtest_floors.md)。
