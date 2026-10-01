# 当前 3D 地图编辑器 MCP

用户要求新增编辑器功能同时支持 MCP（2026-10-01）。项目约定见根目录 `AGENTS.md`。

## 入口与迁移

- 当前三维编辑器：**工具 → 启用 3D MCP**。地址 `http://127.0.0.1:18766/mcp`，工具菜单可复制地址或关闭服务。默认关闭；`RMMO_EDITOR_MCP=1` 或游戏参数 `--mcp` 可自动启用。
- 服务名称 `rmmo-world-editor`。MCP JSON-RPC HTTP 入口为 `/mcp`，健康检查为 `/health`。客户端先 `initialize`、`notifications/initialized`、`tools/list`，再 `tools/call`。支持协议版本 `2025-03-26`，工具清单以服务发现结果为准。
- **旧二维 MCP 已下线**：原 `18765` 服务不再启动，旧 `tools_list()` 为空，旧 `call_tool()` 返回停用错误。旧地图格子、MV 图层和二维图块审查等工具不注册到新服务。
- 历史代码保留在 `scripts/editor/adapters/editor_mcp.gd` 的 `_legacy_*` 方法、`editor_mcp_ops.gd` 及原二维模块中。新的服务仅复用 HTTP/JSON-RPC 通信框架。旧测试和 `accept_tileset_mcp.py` 为历史二维工作流，不属于当前服务验收。
- Godot 通用调试插件与本项目地图 MCP 是不同服务，本次没有卸载通用插件。

独立无窗口进程也可启动服务；它操作自己的地图文档，与正在运行的 UI 进程不共享内存：

```powershell
& 'D:/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path D:/code/rmmo --script res://tools/editor_mcp_host.gd -- --port=18766 --map=D:/实际内容根/资源包/maps/地图/map.gltf
```

`--map` 需指向内容根内已有地图；省略则使用编辑器默认地图。`--port` 可省略，端口占用明确失败，不会换端口后悄悄连接另一实例。无窗口渲染器不能提供 `preview_map` 或 `start_playtest`；需要预览/试玩时连接图形编辑器。自动化图形测试使用独立后台桌面，不能弹出前台窗口。

## 工具清单

| 能力 | 工具 |
| --- | --- |
| 状态、分页物件搜索、完整记录 | `editor_state`、`list_objects`、`get_object` |
| 精确选择、追加选择、整组选择、画布框选 | `select_objects`、`select_rectangle` |
| W/R/T、世界/局部轴、吸附设置 | `configure_transform` |
| 单物件 XYZ 位置、旋转、非等比尺寸/模型缩放 | `set_object_transform` |
| 共同中心平移、旋转、等比缩放 | `transform_selection` |
| 向下贴地、坡面法线和点选表面放置 | `drop_selection`、`snap_selection_to_surface` |
| XYZ 边缘/中心对齐、等中心距离/等边缘间隙分布 | `align_selection`、`distribute_selection` |
| 成组、解组、复制、删除 | `group_selection`、`ungroup_selection`、`duplicate_selection`、`delete_selection` |
| 改名、编辑器隐藏和锁定 | `set_object_properties` |
| 聚焦和渲染预览 | `focus_selection`、`preview_map` |
| 资源库、资源包、保存预制件、重复放置 | `list_assets`、`list_resource_packs`、`save_prefab`、`place_asset` |
| 墙/道路连接、草/土/浅水过渡、高台/楼梯/屋顶/桥栏杆、擦除 | `paint_auto_tiles` |
| 自定义自动拼接套件列表、导入 | `list_auto_tile_kits`、`import_auto_tile_kit` |
| 共享撤销栈、保存和重开 | `undo`、`redo`、`save_world`、`open_world` |
| 自动草稿设置、列表、保存、恢复、删除 | `configure_autosave`、`list_editor_drafts`、`save_editor_draft`、`restore_editor_draft`、`discard_editor_draft` |
| 保存/保留草稿/放弃修改后关闭，取消关闭 | `close_editor` |
| 表面材质库、导入贴图 | `list_surface_materials`、`import_surface_material` |
| 面列表与拾取、刷材质、恢复原材质 | `list_object_surfaces`、`pick_surface`、`paint_surface`、`clear_surface_material` |
| 五类事件模板与物品/商店目录 | `list_event_templates`、`list_event_resources` |
| 创建、挂载/修改、清除物件事件 | `create_event_template`、`set_event_template`、`clear_event_template` |
| 地图日夜、光照、雾与人物遮挡轮廓 | `get_environment`、`set_environment` |
| 楼层范围、隐藏/淡化、读取视图配置 | `get_editor_view`、`set_floor_view` |
| 指定或拾取试玩出生脚点 | `set_playtest_spawn`、`pick_playtest_spawn` |
| 临时副本试玩、结束、查询状态 | `start_playtest`、`stop_playtest`、`playtest_state` |
| 参数化建筑模板、批量预览/生成、实例列表 | `list_building_templates`、`preview_buildings`、`generate_buildings`、`list_buildings` |
| 建筑参数更新、删除、解除生成关联 | `update_building`、`delete_building`、`detach_building` |
| 沿街普通、中世纪、城中村建筑规划与生成 | `preview_street_buildings`、`generate_street_buildings` |
| 矩形区域内随机单栋/成片建筑，避让已有物体 | `preview_region_buildings`、`generate_region_buildings` |

## 语义与示例

当前共 **67 个工具**。参数化建筑的外观/室内一致性、批量生成和修改保护见 [world_editor_buildings.md](world_editor_buildings.md)。楼层隔离、指定出生点和临时试玩见 [world_editor_playtest_floors.md](world_editor_playtest_floors.md)。事件模板、环境与人物遮挡轮廓见 [world_editor_events_environment.md](world_editor_events_environment.md)。高差、楼梯、屋顶、桥栏杆和自定义套件见 [world_editor_height_terrain.md](world_editor_height_terrain.md)。贴地、表面放置和排列的参数、完整组规则及接触精度边界见 [world_editor_placement.md](world_editor_placement.md)。这四项均使用当前选择，共享撤销事务，返回实际修改的 `changed_ids`。草稿/关闭工具见 [world_editor_recovery.md](world_editor_recovery.md)；材质库、选面、刷面及恢复原材质见 [world_editor_surface_materials.md](world_editor_surface_materials.md)。

XYZ 为米，Y 向上，欧拉旋转为度。`set_object_transform.size` 对基础物件为尺寸，对导入模型为三轴缩放倍率。精确数值操作不套用吸附。`transform_selection` 是世界轴增量，绕共同中心旋转/等比缩放，一次调用对应一次撤销。界面与 MCP 共用变换、分组、选择、自动瓦片和预制件业务逻辑。

`configure_transform` 的吸附值与界面一致：位置 `[0, 0.01, 0.1, 0.25, 0.5, 1]` 米；旋转 `[0, 1, 15, 45, 90]` 度；缩放 `[0, 0.1, 0.25, 0.5]`。`0` 表示关闭。状态同时返回选择的 `space` 和实际 `effective_space`：多选使用世界轴，单物件缩放使用局部轴。

工具调用示例（使用 `list_objects` 返回的真实 ID）：

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"select_objects","arguments":{"ids":["obj_1","obj_2"]}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"transform_selection","arguments":{"translation":[1.25,0,0],"rotation":[0,45,0],"scale":1.2}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"paint_auto_tiles","arguments":{"family":"road","points":[[0,0,0],[12,0,0],[12,0,8]],"cell_size":4,"height":0}}}
```

- `select_objects.ids` 指定成员，生成建筑默认扩展为整栋；开启 `configure_transform.component_edit` 后才精确指定其构件；`group_id` 选择整组，两者互斥。空 `ids` 清空选择。框选坐标相对于 3D 画布左上角，尺寸由 `editor_state.canvas_size` 查询。
- 隐藏或锁定物件不可选择/变换/改名；`set_object_properties` 可显式解锁或显示它们。先解锁显示，再改名。隐藏只影响编辑器，运行时内容仍保留。
- 楼层隔离时，范围外物件不能选择、直接变换、改名、刷材质或修改事件。`list_objects` 仍列出全部楼层，并返回 `in_current_floor`；锁定/隐藏标记可独立管理。跨层整组操作需先关闭隔离。`place_asset.ids` 返回全部新建成员，包括当前楼层范围外的成员。
- `save_prefab` 使用 `list_resource_packs` 返回的 `pack_root`，名称与依赖打包规则同 UI；返回稳定 `asset_id`，供 `place_asset` 重复放置。每次放置有独立的成员和组合 ID。预制件是快照，不包含实例联动更新。
- `place_asset.position` 是表面落点，底面自动对齐。自动瓦片需用 `paint_auto_tiles`，`family` 为 `wall/road/grass/dirt/water/cliff/stairs/roof/bridge`；格宽为 `1/2/4/8` 米。点的 Y 被 `height` 替代。高台同基底自动处理邻格高差，桥/道路按楼梯两端标高连接，其余跨高度独立。`erase=true` 擦除；一笔连同邻居重算共同撤销。自由变换自动块后脱离自动拼接。
- `save_world` 默认保存当前地图；另存为不覆盖已存在的其他地图。`open_world` 遇到未保存修改时拒绝打开，需先保存或显式传 `discard_changes=true`。
- `editor_state.autosave` 返回自动草稿状态。草稿默认每 60 秒保存，与正式地图分开；恢复到内存后保持未保存状态，并继续检查磁盘版本冲突。`restore_editor_draft` 的 `discard_changes=true` 会先备份当前修改。`close_editor` 会关闭当前进程，仅在用户明确要求关闭时调用。
- `paint_surface` 使用 `list_object_surfaces` 或 `pick_surface` 返回的目标和 `list_surface_materials` 返回的材质 ID；一次调用刷一个连通平面，保留未刷的原材质。`clear_surface_material` 可恢复单面或整物件。UI 刷面期间其余写操作返回忙碌，`editor_state.surface_brush_active` 可查询。
- `editor_state.editor_view` 返回楼层和出生点配置，`spawn_picking` 表示 UI 正在拾取出生点。试玩使用未保存文档的临时副本，`start_playtest` 返回准备状态后查询 `playtest_state`，直到 `phase=running` 或 `failed`。试玩期间可查询和 `preview_map`（返回游戏视图），写操作只允许 `stop_playtest`；结束后回到原编辑状态。
- 参数化建筑按 `building_id` 整体管理，不受普通多选 256 成员上限影响。一次最多生成 16 栋，房间/门窗/楼梯来自同一蓝图；整批校验并共享一次撤销。存在手改、保护或材质几何冲突时拒绝重生成，使用 `list_buildings` 查看详情。
- 整栋建筑的 `transform_selection` 仅支持 XYZ 平移、Y 轴旋转；同步原点/朝向/楼层/基线并检查碰撞，失败不改地图。`duplicate_selection` 寻找附近空地并保留独立配方，`delete_selection` 同时删除配方。改宽深/层数使用 `update_building`；单个组件变换需先 `configure_transform {"component_edit":true}`，完成后关闭。`editor_state` 返回 `building_component_edit` 和 `whole_building_selection`。不支持整栋缩放/XZ 倾斜、贴面/落地/排列及混合普通物件搬动；两种入口均明确拒绝。
- 城中村布局为 `parameters.layout="urban_village"`，`list_building_templates.urban_presets` 返回家庭自建房与底商住宅预设，支持 1～6 层、1～3 卧室、折返楼梯、阳台、屋顶露台、雨棚和水箱；不提供分租规则。`preview_buildings` 同时返回 `terraces/service_zones`，沿街工具支持相同参数。普通/中世纪仍最多三层，单栋上限 2000 构件；版本 1、2 地图仍可读取，更新写入版本 3。
- 区域快捷生成只需同高的两个世界坐标 `from/to`，可选 `style=urban_village/medieval/standard`、`mode=single/block`、`density=low/medium/high`、`yaw=0/90/180/-90`、`seed` 和 `max_buildings`。规划避让所有已有物体（含隐藏、锁定和导入模型），屋檐、阳台及雨棚计入占地。`preview_region_buildings` 返回 `plan_token`；相同参数连同该 token 交给 `generate_region_buildings`，保证应用同一份预览，否则无副作用失败。`editor_state.building_region_drawing` 表示 UI 正在拖框，这时写操作被阻止。
- 返回数据在 MCP `content` 的文本 JSON 中，含 `ok`；业务失败对应 `isError=true`。预览另有标准 `image/png` 内容。

## 边界与验收

仅绑定 loopback；校验 Host 和 Origin。文件操作限制在配置的外部内容根，拒绝越界路径及链接目录；不提供任意脚本、任意文件读写。请求体上限 4 MiB、最多 8 个连接、空闲连接 10 秒回收；普通选择/变换最多 256 个成员；整栋选择/变换/复制/删除最多 16 栋，不受构件数 256 的限制；MCP 预制件放置仍最多 256 个构件（既有批量限制），更大的房屋请用保留配方的整栋复制；UI 预制件快照可超过该数，尚未统一此限制，笔画最多 256 个控制点、1024 个经过格，分页最多 200 项。

鼠标拖动、框选、点选表面、拾取出生点或画笔事务正在进行时，MCP 修改返回忙碌，避免合并进用户未结束的撤销事务；只读查询仍可用。`editor_state.surface_placement_active` 表示正在点选表面。关闭确认期间只允许 `close_editor` 处理关闭，其余写操作拒绝。读取失败的地图禁止修改，但仍可打开其他地图、管理/恢复草稿或关闭。复杂保存/加载、草稿发布和预制件打包在主线程同步执行，目前没有进度取消接口；试玩的异步准备/加载可用 `stop_playtest` 取消。

当前 MCP 覆盖已交付的材质笔刷、第二批高差拼接、第三批事件模板/环境配置，以及楼层隔离和临时试玩。五类事件可用模板工具配置；旧 NPC/采集/传送记录的其他专有字段、模型资源导入/重命名等尚未提供专门工具。不要使用历史二维工具冒充这些三维接口。

`tools/test_world3d_mcp.gd` 通过实际 TCP/HTTP 完成工具发现、旧工具拒绝、变换/组合/列表属性/框选/预制件/两类自动瓦片、共享撤销重做、保存重开、非法参数无副作用、端口冲突、只读与交互忙碌保护。图形模式另外验证 PNG 图像响应，headless 验证明确的预览限制。修改共享业务后同时运行 `test_world3d_groups_ui.gd`、`test_world3d_transform.gd` 和 `test_world3d_editor.gd`。

`tools/test_world3d_placement.gd` 验证新增四个工具的 HTTP 调用、真实表面拾取、组/模型变换、失败原子性、撤销与保存重开，并在图形模式验证快捷键、鼠标和摆放面板。

`tools/test_world3d_recovery.gd` 验证六项草稿/关闭工具、自动草稿、无副作用失败、恢复撤销、保存冲突、强杀中断后的恢复和真实子进程关闭；图形模式另验收数值输入、恢复面板和关闭提示。

`tools/test_world3d_surface_paint.gd` 验证六项表面材质工具、UV 参数、原材质与实例隔离、预制件依赖搬迁、中文贴图路径、运行时 glTF、鼠标笔画、取消、撤销和材质面板。

`tools/test_world3d_height_terrain.gd` 验证第二批的真实 HTTP 接口、非法套件/参数、ID 与邻接、撤销、保存/重开、预制件依赖搬迁、鼠标操作和运行时楼梯通行。

`tools/test_world3d_gameplay.gd` 验证七项新工具、五种事件、目录查询、保护状态、无副作用失败、撤销/恢复/保存重开、精度、带事件的模型与预制件、实际事件运行和 3D 商店交易。`tools/test_world3d_outline.gd` 用后台 GPU 场景验证玩家轮廓蒙版、遮挡开关、动态几何及清理。

`tools/test_world3d_playtest.gd` 通过真实 HTTP 验证七项楼层/试玩工具、隔离显示与选择保护、完整放置 ID、参数失败原子性、撤销/保存重开、真实鼠标出生点拾取及取消；后台 GPU 验证准备取消、出生支撑与胶囊碰撞、未保存事件奖励、独立游戏进度、跨图往返和退出后的原编辑状态恢复。headless 明确拒绝运行试玩。

`tools/test_world3d_buildings.gd` 验证七项建筑工具、批量原子性、内外统一布局、更新冲突、材质保留、草稿与保存重开，以及实际运行时门窗碰撞、三层房间导航和胶囊连续上楼。

`tools/test_world3d_medieval.gd` 验证中世纪窄店屋/挑空大厅/附属房、逐栋参数、沿街预览与生成、版本 1 兼容、真实房间连通与碰撞；所有入口仍是当前 3D MCP。沿街工具只布置建筑，不替代道路绘制或完整城镇规划。

`tools/test_world3d_urban.gd` 验证城中村家庭/底商预设、阳台和屋顶摘要、非法户型/分租字段/超限无副作用、沿街生成、跨布局更新、锁定与撤销、版本 2 兼容、草稿/保存重开、六层隔离及实际胶囊上下楼。UI 和 HTTP 仍共用原有建筑工具与事务，不另开城中村专用服务。
