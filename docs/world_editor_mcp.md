# 当前 3D 地图编辑器 MCP

2026-10-03 城镇地表收尾：`set_river_materials` 增加 `wet_darkening`（0～0.8，默认 0），与 `wet_height` 一起控制天然岸沙/土/岩的湿痕；UI 同步提供参数，旧图不自动改变外观。仍为 114 个 3D 工具；泥路软边和逐面铺装分别复用 `paint_terrain_region` / `paint_surface`。

2026-10-03 农田垄沟：新增 `set_terrain_furrows`，与地形面板共用方向、垄距、高度、田边留白、保护与撤销操作；`list_terrains.ground_regions.regions[].furrows` 返回可编辑配方。详见 [农田垄沟和接缝](world_editor_furrows.md)。

2026-10-03 区域地表绘制：当前 **114 项** 3D 工具。新增 `paint_terrain_region`、`remove_terrain_region`；`set_terrain_material` 增加可选 `saturation`（0～1），保存为地形底材调色，法线与原贴图保持不变；UI 支持拖矩形或点选多边形，MCP 使用相同保护、验证、撤销和保存。`list_terrains.ground_regions` 返回区域、局部 XZ 坐标和 PBR 材质，`editor_state.ground_region_drawing` 表示待提交草案。详见 [地表材质区域](world_editor_ground_regions.md)。

2026-10-03 风化笔刷：`preview_terrain_stroke` / `sculpt_terrain` 新增 `mode=erode`，共享 `iterations`、`talus_angle`、`erosion_seed` 参数。保持体积、块边与洞边，超工作预算原子拒绝，水面无碰撞覆盖层不阻挡河床编辑。该批交付时工具总数为 111，旧二维工具保持下线。参见 [连续地形编辑](world_editor_terrain_sculpt.md#风化与性能2026-10-03)。

2026-10-03 地形与河岸材质：该批交付时共 **111 项** 3D 工具。`set_river_materials` 支持自然河岸水深与坡度渐变、缓岸草土沙交错、三向投影、垂直砌石护岸湿痕及水平水面透光；新增 `set_terrain_slope_materials`，给普通隆起地形按坡度自动露岩，无须水位。UI 与 HTTP 共用整批验证、保护、撤销和原生保存。`list_terrains` 返回完整 `depth_blend` / `slope_blend` 参数；水面和护岸配置通过物件记录读取。参见 [地形与河岸渐变](world_editor_river_materials.md)。

2026-10-02 连续地形：地形查询、新建/转换、笔画预览、雕刻和整体 PBR 材质五项。支持隆起、下沉、整平、平滑、贯穿洞口和补洞；UI/MCP 共用碰撞及承托保护、整笔撤销、草稿、保存重开。参见 [连续地形编辑](world_editor_terrain_sculpt.md)。

2026-10-02 道路桥梁联动与城墙城门：该批交付时共 **104 项** 3D 工具。新增桥梁接入/解绑、路网诊断三项，以及城墙查询/预览/生成/移除/开关城门五项。支持保留水平接头的直线坡道、连续折线城墙、圆形/椭圆围城、方塔/圆塔、垛口、双扇活动门；UI/MCP 共用校验、保护、撤销、草稿和保存。参数、限制和运行时接口见 [道路桥梁联动](world_editor_road_connections.md)、[城墙与城门](world_editor_fortifications.md)。

2026-10-02 河道与平桥：该批交付时共 **96 项** 3D 工具。新增查询、预览、生成、解除/恢复地面四项，包含平地开槽、河水/河床/两岸、齐平桥头、栏杆、PBR 及运行时碰撞；UI/MCP 共用原子校验、撤销、草稿和保存。当前桥梁外观未通过用户验收，已登记重做待办。具体边界见 [河道说明](world_editor_waterways.md)。

2026-10-02 区域植被散布：该批交付时共 **92 项** 3D 工具。新增区域/素材查询、预览、生成和解除/删除四项。水平地面承托、混合模型、种子复现、道路/建筑/禁植区避让、手改保护和运行时碰撞共用 UI/MCP；详见 [区域植被散布](world_editor_vegetation.md)。

2026-10-02 体积云已接入：共享环境新增 `cloud_altitude`、`cloud_thickness`、`cloud_scale`、`cirrus_amount`；客户端画质分档不进入服务器配置。资源安装、协议与真实 HTTP / GPU 验收见 [3D 体积云](world3d_clouds.md)。

2026-10-02 环境效果扩展：`set_environment` 新增连续昼夜、本地湿润/积水、室内外声音、空间雷电配置，字段与真实 HTTP 验收见 [环境效果扩展](world3d_environment_effects.md)。工具数量不变，仍复用共享校验、UI、撤销与保存；实时湿润不写服务端状态。

2026-10-02 星空与时间：环境 schema 新增 `star_intensity`、`meteors_enabled`、`meteor_frequency`、`time_hours`、`time_speed`；仍走共享环境校验和事务。游戏运行时由服务器同步天气、时钟、风场、星空种子、流星 / 火流星 / 流星雨与闪电；编辑器只编辑地图初始环境，服务脚本事件不属于玩家编辑器命令。协议与 Go 交接见 [3D 环境同步](world3d_environment_sync.md)。

2026-10-02 街区与地块更新：该批交付时共 **88 项** 3D 工具。新增街区识别、临街地块房屋预览/生成/解除关联四项；已关联房屋不自动覆盖，分批补充空位，保护材质、事件和手动移动。入口连接、碰撞、保留区、单事务撤销与保存共用 UI/MCP 实现，详见 [街区与地块](world_editor_blocks.md)。

上一轮道路与区域批次交付时为 84 项。在十项城镇布局操作基础上，新增交叉拆分、铺面预览/生成/解除关联、保留区更新五项。真实水平道路含 PBR 与碰撞，禁建区约束建筑生成及整栋移动。UI/MCP 共用校验、保护、草稿和撤销；边界与验收见 [道路铺面](world_editor_roads.md) 和 [城镇布局](world_editor_city_layout.md)。直线斜坡、桥头联动、区域植被及独立河道已在后续批次交付。下方 V5～V7 及天气批次的 69 项为各批次交付时数量。

2026-10-02 风场更新：`get_object` 返回 `wind_meshes`（相对网格路径、支持状态、原因），`set_object_properties` 新增嵌套 `wind`，与属性检查器共用植被 / 布料受风设置、原子校验和撤销。风向 / 风速沿用环境工具，工具数量不变。`wind` 不能与改名 / 隐藏 / 锁定混用；完整字段、材质边界及真实 HTTP / GPU 验收见 [3D 天气与美术](world3d_weather.md)。

2026-10-02 天气更新：`get_environment` / `set_environment` 增加 `weather`、`weather_intensity`、`wind_speed`、`wind_direction`、`weather_transition`、`sky_enabled`、`lightning_enabled`，仍使用现有 69 项工具及环境事务。编辑器、保存地图和游戏共用 3D 天气渲染，真实 HTTP、原子失败、撤销重做和 GPU 碰撞验收见 [3D 天气与美术](world3d_weather.md)。


2026-10-02 蓝图 V6：仍为 **69 项** 3D 工具。建筑 schema 新增 `door_height`（默认 2.5）、`door_width`（门洞最小宽，默认 1.5）、`stair_width`（默认 1.7）、`stair_landing`（转角平台深度，默认 2.0）、`corridor_width`（默认 2.2），单位米；新建及区域随机层高默认 4 米。全部沿用现有生成/预览/更新事务，旧配方更新补旧尺寸，不静默放大。

`get_environment` / `set_environment` 新增 `interior_cutaway` 和 `indoor_camera_distance`（2～5 米）。隐藏仅在第三人称角色室内，且相机到角色射线第一次碰到其上方楼板/天花板时触发。无障碍或先碰普通物体/墙不触发；第一人称和 VR 禁用。UI/MCP 共享 schema、环境记录和撤销，保存重开有效。相机效果需进入试玩；MCP 编辑的是配置，不强制更改玩家实时视角。详情见 [环境与相机](world_editor_events_environment.md)。

`tools/test_world3d_interior_camera.gd` 通过真实 HTTP 验证发现、合法/非法尺寸和环境调用、原子失败、UI 同步、撤销重做、保存重开，并运行相机、导航与 GPU 验收。楼梯矩阵见 `tools/audit_building_player_metrics.gd`，转角平台与普通梯段共用真实碰撞测试。

2026-10-02 蓝图 V5：当前共 **69 项** 3D 工具。新增 `list_building_components(id)` 和 `set_building_component_state(id, component_id, open)`，共用 UI 门窗开合、成员保护与单次撤销；状态保存重开。建筑 schema 增加 `foundation_depth`（默认向下 1 米）、`front_canopy` 和 `dormers`；中世纪预设七款。生成、区域与沿街规划、整栋移动均检查地基和门窗转动空间。运行时动画/碰撞接口与具体限制见 [建筑说明](world_editor_buildings.md#地基活动门窗与参考样屋2026-10-02蓝图版本-5)。旧二维入口保持下线。

用户要求新增编辑器功能同时支持 MCP（2026-10-01）。项目约定见根目录 `AGENTS.md`。

2026-10-02 建筑外观更新：`list_building_templates` 公开中世纪两套立面规则、`timber_width`（0.18～0.32 米）与 `chimney`（布尔值）；生成、区域/沿街预览与更新共用蓝图版本 4。预览的 `frame_joints` 提供斜撑端点和所连接梁柱的局部坐标信息。该次更新无新增独立工具（当时 67 项）；参数非法、构件保护、碰撞、撤销及保存语义与 UI 一致。详见 [建筑生成说明](world_editor_buildings.md#街屋外观规则2026-10-02蓝图版本-4)。

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

道路曲线继续通过 `update_road_graph.edges[].controls` 的两个世界坐标控制柄编辑；`preview_road_surface` / `generate_road_surface` 与 UI 共用连续边缘铺面，缓弯不再逐采样点叠加整圆。参数、锁定/隐藏保护、预览令牌与整笔撤销语义不变。源轮廓预算为 8192，裁切预算仍为 100 万次，超限整笔拒绝。参考城镇的广场与道路手工合并，保持解除生成关联；该图批量重铺使用 `tools/apply_medieval_town_road_curves.gd` 保留广场，不能直接追加一份生成铺面。

| 能力 | 工具 |
| --- | --- |
| 连续城墙、角塔、垛口、活动城门 | `list_fortifications`、`preview_fortification`、`generate_fortification`、`remove_fortification`、`set_fortification_gate` |
| 河道桥梁接入路网、解绑、连通及承托诊断 | `connect_waterway_bridge`、`disconnect_waterway_bridge`、`get_road_connectivity` |
| 河道开槽、河岸、平桥与桥头、恢复地面 | `list_waterways`、`preview_waterway`、`generate_waterway`、`remove_waterway` |
| 区域植被混合散布、重生成、保护与解除 | `list_vegetation_scatter`、`preview_vegetation_scatter`、`generate_vegetation_scatter`、`remove_vegetation_scatter` |
| 闭合街区、临街地块与空位房屋 | `get_city_blocks`、`preview_block_buildings`、`generate_block_buildings`、`detach_block_buildings` |
| 道路交叉拆分、真实铺面、保留区 | `split_road_intersections`、`preview_road_surface`、`generate_road_surface`、`detach_road_surface`、`update_planning_zones` |
| 公里级视图、参考图标定、导航书签、可保存道路骨架 | `get_city_layout`、`set_editor_camera`、`focus_editor_view`、`set_map_reference`、`calibrate_map_reference`、`save_view_bookmark`、`delete_view_bookmark`、`recall_view_bookmark`、`update_road_graph`、`create_road_path` |
| 状态、分页物件搜索、完整记录 | `editor_state`、`list_objects`、`get_object` |
| 精确选择、追加选择、整组选择、画布框选 | `select_objects`、`select_rectangle` |
| W/R/T、世界/局部轴、吸附设置 | `configure_transform` |
| 单物件 XYZ 位置、旋转、非等比尺寸/模型缩放 | `set_object_transform` |
| 共同中心平移、旋转、等比缩放 | `transform_selection` |
| 向下贴地、坡面法线和点选表面放置 | `drop_selection`、`snap_selection_to_surface` |
| XYZ 边缘/中心对齐、等中心距离/等边缘间隙分布 | `align_selection`、`distribute_selection` |
| 成组、解组、复制、删除 | `group_selection`、`ungroup_selection`、`duplicate_selection`、`delete_selection` |
| 改名、编辑器隐藏和锁定、独立物件受风 | `set_object_properties` |
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

当前共 **104 个工具**。参数化建筑的外观/室内一致性、批量生成和修改保护见 [world_editor_buildings.md](world_editor_buildings.md)。楼层隔离、指定出生点和临时试玩见 [world_editor_playtest_floors.md](world_editor_playtest_floors.md)。事件模板、环境与人物遮挡轮廓见 [world_editor_events_environment.md](world_editor_events_environment.md)。高差、楼梯、屋顶、桥栏杆和自定义套件见 [world_editor_height_terrain.md](world_editor_height_terrain.md)。贴地、表面放置和排列的参数、完整组规则及接触精度边界见 [world_editor_placement.md](world_editor_placement.md)。这四项均使用当前选择，共享撤销事务，返回实际修改的 `changed_ids`。草稿/关闭工具见 [world_editor_recovery.md](world_editor_recovery.md)；材质库、选面、刷面及恢复原材质见 [world_editor_surface_materials.md](world_editor_surface_materials.md)。

XYZ 为米，Y 向上，欧拉旋转为度。`set_object_transform.size` 对基础物件为尺寸，对导入模型为三轴缩放倍率。精确数值操作不套用吸附。`transform_selection` 是世界轴增量，绕共同中心旋转/等比缩放，一次调用对应一次撤销。界面与 MCP 共用变换、分组、选择、自动瓦片和预制件业务逻辑。

`set_environment` 的 `sun_shadows`、`ambient_occlusion` 控制太阳投影和接缝环境遮蔽，与环境面板、运行时使用同一配置；均为布尔值并默认启用。SSAO 需要 Forward+。两字段沿用一次撤销、保存重开及非法调用无副作用语义。

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
- `save_world` 默认等待原子保存完成，成功结果附带 `saved:true`、`timings` 保存分段耗时、静态网格写出数量和 CPU 几何缓存命中统计。可传 `background:true` 立即得到 `pending:true/saved:false/job_id/path`，再用 `editor_state.save` 查询 `active/phase/completed/total/elapsed_seconds/result`。`total=0` 表示该阶段不可计数，不是 0% 总进度；完成后保留最后一次结果及耗时。底部状态栏显示同一个任务，见 [保存性能](world_editor_save_performance.md)。
- `editor_state.autosave` 返回自动草稿状态。草稿默认每 60 秒保存，与正式地图分开；恢复到内存后保持未保存状态，并继续检查磁盘版本冲突。`restore_editor_draft` 的 `discard_changes=true` 会先备份当前修改。`close_editor` 会关闭当前进程，仅在用户明确要求关闭时调用。
- `list_surface_materials` 同时列出默认资源包分类 PBR、个人导入与内置材质；`category` 精确筛选，`query` 搜索名称、分类和 ID，返回全部 `categories`。默认包布局与来源见 [default_material_pack.md](default_material_pack.md)。`paint_surface` 使用 `list_object_surfaces` 或 `pick_surface` 返回的目标和列表返回的材质 ID；一次调用刷一个连通平面，保留未刷的原材质。颜色、法线、粗糙度、金属度、AO 共用材质快照、依赖校验和撤销；`mapping="meters"` 使用材质 `tile_size` 按局部米单位重复，`planar` 整面铺一张，`uv` 使用原 UV。`clear_surface_material` 可恢复单面或整物件。UI 刷面期间其余写操作返回忙碌，`editor_state.surface_brush_active` 可查询。
- `editor_state.editor_view` 返回楼层和出生点配置，`spawn_picking` 表示 UI 正在拾取出生点。试玩使用未保存文档的临时副本，`start_playtest` 返回准备状态后查询 `playtest_state`，直到 `phase=running` 或 `failed`。试玩期间可查询和 `preview_map`（返回游戏视图），写操作只允许 `stop_playtest`；结束后回到原编辑状态。
- 参数化建筑按 `building_id` 整体管理，不受普通多选 256 成员上限影响。一次最多生成 16 栋，房间/门窗/楼梯来自同一蓝图；整批校验并共享一次撤销。存在手改、保护或材质几何冲突时拒绝重生成，使用 `list_buildings` 查看详情。
- 整栋建筑的 `transform_selection` 仅支持 XYZ 平移、Y 轴旋转；同步原点/朝向/楼层/基线并检查碰撞，失败不改地图。`duplicate_selection` 寻找附近空地并保留独立配方，`delete_selection` 同时删除配方。改宽深/层数使用 `update_building`；单个组件变换需先 `configure_transform {"component_edit":true}`，完成后关闭。`editor_state` 返回 `building_component_edit` 和 `whole_building_selection`。不支持整栋缩放/XZ 倾斜、贴面/落地/排列及混合普通物件搬动；两种入口均明确拒绝。
- 城中村布局为 `parameters.layout="urban_village"`，`list_building_templates.urban_presets` 返回家庭自建房与底商住宅预设，支持 1～6 层、1～3 卧室、折返楼梯、阳台、屋顶露台、雨棚和水箱；不提供分租规则。`preview_buildings` 同时返回 `terraces/service_zones`，沿街工具支持相同参数。普通/中世纪仍最多三层，单栋上限 4096 构件；版本 1～6 地图仍可读取，更新写入当前版本 7（旧屋顶算法默认保留）。
- 区域快捷生成只需同高的两个世界坐标 `from/to`，可选 `style=urban_village/medieval/standard`、`mode=single/block`、`density=low/medium/high`、`yaw=0/90/180/-90`、`seed` 和 `max_buildings`。规划避让所有已有物体（含隐藏、锁定和导入模型），屋檐、阳台及雨棚计入占地。`preview_region_buildings` 返回 `plan_token`；相同参数连同该 token 交给 `generate_region_buildings`，保证应用同一份预览，否则无副作用失败。`editor_state.building_region_drawing` 表示 UI 正在拖框，这时写操作被阻止。
- 返回数据在 MCP `content` 的文本 JSON 中，含 `ok`；业务失败对应 `isError=true`。预览另有标准 `image/png` 内容。

## 边界与验收

仅绑定 loopback；校验 Host 和 Origin。文件操作限制在配置的外部内容根，拒绝越界路径及链接目录；不提供任意脚本、任意文件读写。请求体上限 4 MiB、最多 8 个连接、空闲连接 10 秒回收；普通选择/变换最多 256 个成员；整栋选择/变换/复制/删除最多 16 栋，不受构件数 256 的限制；MCP 预制件放置仍最多 256 个构件（既有批量限制），更大的房屋请用保留配方的整栋复制；UI 预制件快照可超过该数，尚未统一此限制，笔画最多 256 个控制点、1024 个经过格，分页最多 200 项。

鼠标拖动、框选、点选表面、拾取出生点或画笔事务正在进行时，MCP 修改返回忙碌，避免合并进用户未结束的撤销事务；只读查询仍可用。`editor_state.surface_placement_active` 表示正在点选表面。关闭确认期间只允许 `close_editor` 处理关闭，其余写操作拒绝。读取失败的地图禁止修改，但仍可打开其他地图、管理/恢复草稿或关闭。保存期间拒绝全部写操作（含重复保存、打开、关闭、草稿修改），保留只读查询；默认等待保存的 HTTP 连接不阻塞其他客户端，也不受普通 10 秒空闲超时限制，断开连接不会中断发布。`close_editor action=save` 同样等待后台保存成功才关闭。加载、草稿发布和预制件打包仍同步；当前未提供保存取消接口，试玩的异步准备/加载可用 `stop_playtest` 取消。

当前 MCP 覆盖已交付的材质笔刷、第二批高差拼接、第三批事件模板/环境配置，以及楼层隔离和临时试玩。五类事件可用模板工具配置；旧 NPC/采集/传送记录的其他专有字段、模型资源导入/重命名等尚未提供专门工具。不要使用历史二维工具冒充这些三维接口。

`tools/test_world3d_mcp.gd` 通过实际 TCP/HTTP 完成工具发现、旧工具拒绝、变换/组合/列表属性/框选/预制件/两类自动瓦片、共享撤销重做、保存重开、非法参数无副作用、端口冲突、只读与交互忙碌保护。图形模式另外验证 PNG 图像响应，headless 验证明确的预览限制。修改共享业务后同时运行 `test_world3d_groups_ui.gd`、`test_world3d_transform.gd` 和 `test_world3d_editor.gd`。

`tools/test_world3d_placement.gd` 验证新增四个工具的 HTTP 调用、真实表面拾取、组/模型变换、失败原子性、撤销与保存重开，并在图形模式验证快捷键、鼠标和摆放面板。

`tools/test_world3d_recovery.gd` 验证六项草稿/关闭工具、自动草稿、无副作用失败、恢复撤销、保存冲突、强杀中断后的恢复和真实子进程关闭；图形模式另验收数值输入、恢复面板和关闭提示。

`tools/test_world3d_surface_paint.gd` 验证六项表面材质工具、UV 参数、原材质与实例隔离、预制件依赖搬迁、中文贴图路径、运行时 glTF、鼠标笔画、取消、撤销和材质面板。

`tools/test_world3d_pack_materials.gd` 用实际默认包通过真实 HTTP 验证分类查询与 schema、PBR 通道、按米重复、法线转换、切线生成、非法调用无副作用、撤销重做、保存重开、运行时 glTF 与预制件依赖，并在后台 GPU 渲染材质展示。

`tools/test_world3d_roof_material.gd` 验证默认包生成陶瓦的分类发现，在真实生成店屋两侧坡面刷色图/法线/粗糙度，检查撤销重做、非法目标、保存重开、运行时贴图及实际光照凹凸。材质 ID 为 `pack:default:roofs/terracotta_plain/material`，沿用现有 69 个 3D 工具，不增加二维入口。

`tools/build_medieval_material_demo.gd` 用真实 HTTP 验证完整房屋的九类材质，并验收太阳阴影/环境遮蔽的 schema、合法/非法调用、UI 同步、撤销重做及保存重开，输出实际游戏渲染的外观预览。

`tools/test_world3d_height_terrain.gd` 验证第二批的真实 HTTP 接口、非法套件/参数、ID 与邻接、撤销、保存/重开、预制件依赖搬迁、鼠标操作和运行时楼梯通行。

`tools/test_world3d_gameplay.gd` 验证七项新工具、五种事件、目录查询、保护状态、无副作用失败、撤销/恢复/保存重开、精度、带事件的模型与预制件、实际事件运行和 3D 商店交易。`tools/test_world3d_outline.gd` 用后台 GPU 场景验证玩家轮廓蒙版、遮挡开关、动态几何及清理。

`tools/test_world3d_playtest.gd` 通过真实 HTTP 验证七项楼层/试玩工具、隔离显示与选择保护、完整放置 ID、参数失败原子性、撤销/保存重开、真实鼠标出生点拾取及取消；后台 GPU 验证准备取消、出生支撑与胶囊碰撞、未保存事件奖励、独立游戏进度、跨图往返和退出后的原编辑状态恢复。headless 明确拒绝运行试玩。

`tools/test_world3d_buildings.gd` 验证七项建筑工具、批量原子性、内外统一布局、更新冲突、材质保留、草稿与保存重开，以及实际运行时门窗碰撞、三层房间导航和胶囊连续上楼。

`tools/test_world3d_medieval.gd` 验证中世纪窄店屋/挑空大厅/附属房、逐栋参数、沿街预览与生成、版本 1 兼容、真实房间连通与碰撞；所有入口仍是当前 3D MCP。沿街工具只布置建筑，不替代道路绘制或完整城镇规划。

`tools/test_world3d_urban.gd` 验证城中村家庭/底商预设、阳台和屋顶摘要、非法户型/分租字段/超限无副作用、沿街生成、跨布局更新、锁定与撤销、版本 2 兼容、草稿/保存重开、六层隔离及实际胶囊上下楼。UI 和 HTTP 仍共用原有建筑工具与事务，不另开城中村专用服务。

原生 Unreal 材质导出使用离线 `tools/export_unreal_materials.py`，不增加任意外部路径执行接口。安装到默认包的整木、木作及内外灰泥，经现有 3D 材质分类发现与 `paint_surface` 操作；完整示例验证同墙内外不同材质、10 类用途、PBR 依赖、撤销重做和保存重开。详情见 [Unreal 导出流程](unreal_material_export.md)。


### V7 统一屋顶

`list_building_templates` 另返回 `roof_presets` 五款同高 L/T/U、四坡、单坡建筑。共用参数 schema 新增 `roof_solver: unified | legacy`、`annex_floors: 1..3`，`roof` 扩展 `hip / shed`，`compound` 扩展 `rear_wing`。城中村仍只接受可到达平屋顶。

`preview_buildings`（含 replace_id）、沿街 / 区域预览的建筑行附带 `roof_plan`：局部米制的模块、最终屋面多边形、分类边、真实开洞与诊断；旧算法及城中村为 `{}`。生成 / 更新复用同一求解器、占地检查、身份和撤销事务，非法交接或洞口整批拒绝。相机、表面绘制、保护、保存入口不另走屋顶特例。旧建筑显式请求 `roof_solver=unified` 才迁移；对已画材质的拓扑不兼容更新会拒绝。

例：`generate_buildings({parameters:{layout:"townhouse",width:14,depth:16,roof_axis:"width",compound:"courtyard",annex_floors:2,chimney:false},placements:[{position:[0,0,0]}]})`。详细限制与验证见 [建筑文档](world_editor_buildings.md#v7统一屋面交接与真实开洞)；真实 HTTP 测试 `tools/test_world3d_roofs.gd`。仍为当前 69 个 3D 工具，二维工具不启用。


### 城镇制作执行队列（2026-10-02 接收，未等同全部交付）

目标参考 `C:/Users/luna/Desktop/m.webp`：河流穿城、放射街巷与环路、不规则密集街区、城墙城门、多桥、庭院农田。1200 米见方 / 外围 1500 米是比例估算，不是图像实测或整城性能保证。保留既有房屋、活动门窗、楼梯、自动瓦片、材质、分组、试玩和 32 米运行时分块能力；当前 V7 屋顶是已实施基础，城市视野 / 底图 / 书签 / 概览与道路骨架已交付（见 [城镇布局](world_editor_city_layout.md)）；已补水平铺面、交叉拆分、桥下净空及多边形区域，见 [道路与保留区](world_editor_roads.md)；其余后续工作待实施。

| 阶段 | 待实施范围 | 独立验收要求 |
| --- | --- | --- |
| 城市布局基础（部分完成） | 已交付公里级正交视野、全图/区域定位、底图标定/锁定、概览/书签、可保存道路骨架及节点拖动。已补交叉拆分、水平路口、桥下净空、多边形区域、植被执行规则；现增加直线坡道、桥梁显式接入和连通诊断 | UI/MCP 与真实碰撞、保护、撤销和保存测试共用；弯曲坡道、任意曲线交点、随地形贴合和整城性能仍有明确边界 |
| 街区生成闭环（首批已交付） | 已有道路有界面提取、保守临街矩形地块、避让道路/保留区、入口净空、空位建筑批次与关联保护；待补河流专用扣除、桥头/城门通行、道路变化后的自动建筑替换与覆盖合并 | 现版本不替换已关联建筑，改边界需显式解除关联；后续目标为仅更新受影响内容并保留身份/种子/事件/材质，无法映射的覆盖明确拒绝 |
| 环境与批量外观 | 已有河床河岸、齐平桥头、折线与圆/椭圆城墙、塔楼/垛口/活动城门、基础区域植被。桥梁和城墙美术仍待优化；待补聚簇/局部刷除、地表/农田/布景、建筑用途材质方案、关联预制件和连接点元数据 | 功能验收不等于用户美术验收；需保留种子、交互配方、保护、事件和材质，UI/MCP 同步 |
| 整城承载 | 从第一阶段就测量分区/空间索引/增量刷新、列表虚拟化、增量撤销、后台保存与失败恢复、异步任务/取消、分区导航、轻量建筑/室内按需升级/LOD、预算与通行诊断 | 代表性弯路/Y口/不规则地块/河岸桥头/建筑植被街区逐级扩容；记录生成、编辑、保存、加载、导航、试玩成本；100000 记录上限不是性能承诺 |

本工作区还有 UI 和天气并行修改；实施时针对当前代码核实，不回退其他任务改动。所有阶段复用当前 3D MCP 与共享事务，使用临时地图和后台测试桌面。静态快照预制件不冒充关联模板，自动块刷面导致的脱离邻接保护也不能直接取消。

### 地面绘制合并统计（2026-10-03）

当前 `editor_state` 增加只读 `ground_batching`：合并组数、待处理组数、来源物件/材质面/顶点数、合并后的材质面/顶点数、累计重建次数及构建/提交耗时。使用原 `sculpt_terrain`、变换、材质、隐藏、楼层隔离、撤销和保存工具，自动更新同一派生缓存；没有额外合并事务或改变 UUID。返回材质面数不是整帧 GPU draw calls，首次后台构建完成前 `pending_groups` 可以非零。新增统计不增加工具，该批交付时为 111 个 3D 工具；详见 [地面分块合并](world_editor_terrain_sculpt.md#地面分块合并2026-10-03)。
