# 当前 3D 地图编辑器 MCP

2026-10-07 引用地图 v2：UI 与当前 3D `save_world` 统一保存独立资源引用及实例状态，`timings.export.mode=reference_map`，返回 `resources_written/resources_reused`、`map_bytes_written`、`images_written=0`、`texture_export_passes=0`。新增、删除、移动均不整图导出；`open_world` 后台核验引用并恢复完整模型。通用 glTF 工具仅见定位方块；旧原生图先显式迁移。工具参数不新增二维入口，现有后台作业与冲突保护保持一致；见 [引用格式和迁移验收](reference_maps_20261007.md)。下文 full_export/pose_reuse/incremental_reuse 属迁移前历史记录。

2026-10-08 引用资源复用续修：`timings.export` 另报 `identity_cache_hits`、`serialized_raw_bytes`、`compression_count`、`identity_cache_entries`。冷开后普通移动/删除仍检查当前作者定义与磁盘资源完整 SHA，但不再重压缩未变资源；另存为或缺少目标资源仍按需压缩。UI 与 3D MCP 共用单次保存的路径去重和最终模型路径复核，参数 schema 与工具发现不变。真实 HTTP 整城移动/新增/删除后的保存约 7.158 / 7.441 / 7.250 秒，新增此前未用模型仅写 1 个定义，详见 [续修验收](reference_map_performance_20261008.md)。

2026-10-08 编辑器加载续修：`open_world` 与 UI 共用已验证定义身份复用、单操作模型路径检查及引用读取线程的 prefab CPU 解码预热。`timings.validation` 增加 `verified_paint_ids`、`verified_asset_paths`、`prefab_warm`；末尾资源与地图完整性复核仍保留。作用域建立后提前解析下一个唯一模型，最多一个未消费结果，主线程按原顺序创建场景/写缓存；`timings.asset_lookahead` 提供 `unique_paths/started/consumed/start_failures/ready_on_consume/peak_unconsumed`。`asset_wait` 现在是剩余等待，不能与完整后台 `asset_parse_worker` 相加。整城真实 HTTP 107.679 → 101.237 s，记录/拾取/选择及临时模型解析失败恢复回归通过；仍存在单次约 0.8 s 停顿，不声明 8 ms 为硬上限。

2026-10-07 房屋外观：新增 `list_building_windows {building_id}`、`set_building_window_style {building_id, window_id, style}`；style 为 `casement` / `cross_lattice` / `diamond_lattice`。UI 与 MCP 共用完整窗口（包含双扇）的事务，保持洞口、固定外框及开合状态；锁定、隐藏和楼层保护一致。`paint_surface` / `clear_surface_material` 同时开放已烘焙房屋的逐面材质替换。不会改变自动生成时的整栋统一窗型。限制、使用和真实 HTTP 验收见 [房屋局部外观](house_appearance_20261007.md)。

2026-10-07 胶囊行走：工具栏「胶囊行走 F6」在当前编辑场景内启用可见的第三人称胶囊，仍可选择、移动、摆放和保存物件。UI 与下列 3D MCP 工具共用 `walk_mode.gd`，胶囊及镜头状态不进入地图或撤销记录：

- `set_editor_walk_mode {enabled:boolean, position?:[x,y,z]}`：进入/退出；可选位置为地面脚点，需有可站立表面和 1.8 m 高、0.6 m 宽净空。省略位置从画布中心、观察中心、出生点附近查找；找不到则保持原视角并报错。退出不接受位置，恢复进入前的镜头。
- `move_editor_walk {direction:[right,forward], duration:number, fast?:boolean, jump?:boolean}`：沿镜头水平轴行走，方向各分量 −1～1，斜向归一化；持续 0.01～2 秒，普通 3.5 m/s、加速 7 m/s。异步物理运动，不等待走完才返回；新命令替换旧命令，零方向停止水平移动。键盘、失焦、输入框和编辑事务可打断运动。
- `set_editor_walk_view {yaw?:number, pitch?:number, distance?:number}`：偏航 −360～360°、俯仰 −75～55°、距离 1.5～12 m；遇墙自动收近。后两项工具只在行走模式可用，非法参数无副作用。
- `editor_state.walk`：`active`、`perspective:"third_person"`、脚点 `position`、`grounded`、`height/radius`、`yaw/pitch/distance` 和 `motion_remaining`。关闭时位置为空数组。

WASD 行走、Shift 加速、空格跳跃、右键拖动转向、滚轮调距离；松开右键继续左键编辑。W 此时用于前进，移动工具仍可点工具栏切换。F6/Esc 退出；画布事务进行中先由 Esc 取消该事务。打开新地图、切换俯视/聚焦/书签或开始 F5 试玩会退出行走；保存暂停运动并保留模式。碰撞复用实时编辑拾取形状和城防碰撞分块，单独掩码排除无碰撞装饰、隐藏/隔层构件，锁定实体仍阻挡；移动物件后同步更新。支持重力、最高 0.4 m 台阶和 45° 可站立坡面；不是游戏战斗、交互门或导航模拟。胶囊不被点选，不触发整城重建/导航烘焙，也不加入静态合批。

后台 GPU 与真实 HTTP 验收入口 `tools/test_editor_walk_mode.gd`：发现、非法调用、碰撞/镜头、台阶/跳跃、输入焦点、UI 拖放、撤销重做、保存重开及退出恢复已通过。`tools/test_editor_walk_town.gd` 对 4372 记录的 `medieval_river_town` 只读验证通过：出生点道路及 `(261.7,125.9)` 附近桥面均可站立行走，地形高度实时跟随；场景节点和碰撞批次未重建，文档/历史/正式源文件均未改变。两项日志在 `D:/code/rmmo_runtime/review_artifacts/editor_walk_mode_20261007.log`、`editor_walk_town_20261007.log`，截图路径见日志。该模式的功能验收不代表编辑器和游戏原有 P0 卡顿问题已解决。

2026-10-07 素材分类：素材面板增加「全部分类」下拉框，`list_assets` 增加可选字符串 `category`（精确匹配）并返回完整 `categories`。与 `query` 组合筛选；未知分类返回空列表，非法类型经 schema 拒绝。UI/MCP 共用 `world_editor.asset_items`，筛选不导入模型、不修改地图和撤销历史。牌匾与旗帜发布到默认共享包的 `牌匾/旗帜` 分类，使用既有 `place_asset`/`save_prefab` 业务事务；没有新增二维入口。发布和 HTTP 验证脚本为 `tools/publish_signs_and_banners.gd`，结果见 `D:/code/rmmo_runtime/review_artifacts/signs_banners_20261007/publication.json`，以结果文件为准。

2026-10-07 打开地图分片校验：UI 与 `open_world` 共用主线程私有校验游标，每批约 8 ms 后让出一帧；文档同步读取与 MCP 仍使用同一组校验规则。`editor_state.load.timings.validation` 提供 `units`（次数/累计/最大耗时）、`max_unit_ms`、`max_slice_ms`、记录复制耗时及公共谓词调用数，另列 `asset_scope_ms` 和 `prepared_release_ms`。末尾 `final_check` 为 `bytes` 或 `sha256`：后台一次读取生成同源 JSON/SHA，256 MiB 以内保留原始字节，发布前同步分块完整比较，超限保留完整 SHA；不会依赖文件大小/时间戳或 JSON 中的成功标记。最终复核到发布之间不新增等待，磁盘冲突签名保持 SHA。单个复杂记录、旧格式导入和末尾复核仍不可抢占，8 ms 不是硬上限。加载期间所有写工具被拒绝，状态查询继续可用；失败保留旧文档、选择、材质目标及历史，成功全部校验后只替换一次。`test_document_source_snapshot.gd` 和真实 HTTP `test_editor_sliced_load.gd` 已通过；工具 schema/分发不变。见 [编辑器性能记录](editor_town_performance_20261006.md)。

2026-10-07 保存资源复用：`save_world` 与 UI Ctrl+S、原子保存共用同一保存操作。同路径未改变内容或仅改变安全物件的位置/旋转时，校验源资源、导出实现版本、已发布 glTF 和资源文件后，复用现有材质、贴图和网格；整栋建筑的楼层高度、生成登记和已打开门窗姿态一并保存。`timings.export.mode` 为 `pose_reuse` 或 `full_export`，`images_written` / `texture_export_passes` 明确实际导出次数；复用路径两项均为 0，进度阶段为 `reuse`。旧地图首次完整保存建立可信基线；改材质/几何/资源、另存为、依赖损坏及无法证明安全的类型自动完整导出。发布前再次检查地图冲突与资源；不会跳过 `.previous`、保存锁和恢复流程。见 [保存复用验收](editor_save_reuse_20261007.md)。

2026-10-06 编辑器补充：`open_world` 接入同 UI 的阶段加载，新增可选 `background`；默认 HTTP 等待完成，后台调用立即返回 `pending/job_id`，`editor_state.load` 返回阶段、计数、耗时及结果。加载中拒绝写操作，失败保留原文档。新增 `move_editor_camera {offset:[x,y,z]}`，与中键键盘导航共用世界坐标位移，Y 为升降；不改文档或撤销。`list_assets.assets[].thumbnail` 返回 `status/path/error`；可见缺图素材空闲时自动补生成，`repair_asset_thumbnails {asset_ids:[...]}` 和资源菜单可显式重试，需图形编辑器，headless 明确拒绝。自动草稿校验分帧、编码/压缩/原子发布后台执行，`editor_state.autosave.active` 可查询；格式和恢复边界见 [草稿说明](world_editor_recovery.md)。真实 HTTP/UI 回归入口 `tools/test_editor_navigation_loading.gd`。

2026-10-07 普通模型成员增量保存：现有 `save_world`、UI Ctrl+S 和同步文档保存共用增量规划。新增等价实例复用原资源；新增不同素材只导出新子集；删除不重导出未变材质/图片。`timings.export.mode` 增加 `incremental_reuse`，附 `added_instances`、`removed_instances`、`cloned_instances`、`exported_instances`，局部导出附 `partial_export`。增删仍完整业务校验、冲突检查和原子发布；失败保持原地图及脏状态。世界坐标/邻接相关的特殊地形、道路等变更和未知扩展仍报告 `reuse_fallback` 并完整导出；首次/生成器指纹失效也仍需建立基线。当前 3D 工具清单和参数 schema 无变化，真实 HTTP 测试 `test_world3d_incremental_save_http.gd` 145 PASS，见 [增量更新记录](editor_incremental_updates_20261007.md)。

2026-10-06 编辑器操作性能：选择使用保留源对象的增量渲染批次准备，刚性整栋移动更新原节点/碰撞姿态，不再重建整张地图；`select_objects`、`transform_selection` 与 UI 共用同一路径。新增 `set_editor_wind_preview {"enabled":true|false}`，`editor_state.wind_preview` 查询当前值。编辑器环境页的“编辑器风场预览”默认关闭；开关仅属于本次编辑会话，不修改地图风速、物件受风配置、撤销历史或游戏效果。关闭立即恢复原材质并停止受风物件扫描/更新，开启后重新绑定。工具输入只接受必填布尔值 `enabled`。真实 HTTP 和后台 GPU 验证入口为 `test_editor_overlay_cache.gd`、`test_editor_incremental_motion.gd`，详见 [本轮性能记录](editor_town_performance_20261006.md)。

2026-10-06 地图入口修正：资源包窗口的默认共享列表也收录内容根 `maps/` 中的既有 glTF（如 `medieval_river_town`），直接引用原路径，不复制／迁移／保存地图。`list_resource_packs` 的每个包新增 `maps: [{name,path}]`，与 UI 使用同一目录枚举；输入仍为空对象，非法参数无副作用。`open_world` 沿用原有内容根约束和未保存修改保护。正在运行的编辑器需重新启动编辑器运行实例加载新脚本，然后在“文件 → 资源包地图…”选择默认包并搜索地图名。`test_resource_pack_browser.gd` 验证发现、搜索、当前选择、原路径打开及未保存修改提示；`test_root_map_discovery_mcp.gd` 通过真实 loopback HTTP 验证发现与非法调用。此次未更改任何场景内容，彩柱和道路侧边纠正仍等待用户完成微调后再实施。

2026-10-06 大团灌木：圆团、横向铺展、高冠三款已加入默认预制件库；20m 内保留完整母版，远处使用约半面数枝簇，沿用现有 LOD、叶片背光、风场及非阻挡语义。真实 HTTP 工具发现、放置、非法调用无副作用、撤销重做和保存重开通过，游戏加载和无阻挡体检查通过。未新增 UI/schema 或在线株形参数。见 [灌木发布记录](street_shrub_mounds_20261006.md)。

2026-10-06 住宅石围墙与方柱：1.5m 墙高版本六款预制件已加入默认资源包，沿用 3D `save_prefab`、`list_assets`、`place_asset`、撤销/重做及保存重开，真实 HTTP 验证失败数 0。游戏加载与阻挡碰撞通过，修正静态合并时的石材 UV 通道；无新 UI/schema。见 [围墙发布记录](garden_boundary_20261006.md)。

2026-10-06 朱红苏联徽记燕尾长旗：用户授权后已通过既有 `save_prefab` 加入默认资源包，12,944 个三角面，独立刚性支架/布料，目录仅一个预制件。真实 HTTP 工具发现、放置、非法调用无副作用、撤销重做与保存重开通过；原生 PBR、风动和游戏加载通过，发布验证失败数 0。沿用既有 UI/MCP，没有新增徽记参数面板或 schema。见 [垂旗记录](wall_guild_banners_20261006.md)。

2026-10-06 写实路缘边石与踏步石：11 款用户批准的预制件通过既有 `save_prefab` 发布到默认资源包，复用 `list_assets`、`place_asset`、撤销/重做和保存重开；逐款真实 HTTP 和游戏碰撞体加载验证失败数 0。无新增工具/schema，离线长度/曲率配方不是编辑器在线参数接口。修复材质命名中的 Windows 非法路径字符，见 [发布记录](street_edge_stones_20261006.md)。

2026-10-06 写实宽冠粗干橡树：用户验收后通过现有 `save_prefab` 发布到默认资源包，沿用 `list_assets`、`place_asset`、撤销/重做和保存重开。真实 HTTP 验证通过，三级 LOD 与风动保留；未新增橡树参数 schema，不能将松树的树形接口适用范围扩大到此橡树。见 [橡树发布记录](street_oak_game_20261006.md)。

2026-10-06 写实草丛：11 个矮草/野草预制件沿用当前 `place_asset`、`save_prefab`、撤销及保存接口。带显式 `rmmo_grass` 元数据的扫描素材在原生 glTF 加载时按像素内容共享纹理，UI、MCP 和原生运行加载共用；三档 LOD、风动、非阻挡碰撞保留。真实 HTTP 与保存重开通过，详见 [草丛验收](town_grass_20261006.md)。未新增草地自动生成 API。

2026-10-06 参数化松树：当前 3D 接口新增 `get_tree_parameters {id}`（返回 supported/settings/schema）与 `set_tree_parameters {ids, settings}`（部分参数，1～32 棵）。参数有 `height`、`crown_scale`、`trunk_scale`、`bare_trunk`、`lean`、`density`、`seed`，范围见 [树形参数](parametric_baltic_pine_20261006.md)。只接受显式带 v1 枝簇配方的模型；使用“参数化松树”新版预制件。UI 属性面板与 MCP 共用 `tree_tools.gd`，整批预检、锁定/隐藏/固定建筑保护、一次撤销、保存重开和依赖打包一致。修改同步生成三级 LOD、包围盒与树干碰撞；材质/风动保留，不启用二维工具。`test_parametric_tree.gd` 真实 HTTP、原生 UI 和游戏运行时测试失败数 0。文内较早的工具总数是当时版本记录。

2026-10-06 密集植被运行优化：共享风场跳过 LOD 隐藏层的逐帧更新，镜头返回恢复当前风动时间，保留避风、材质恢复和原生保存语义；UI 与 3D MCP 无新参数或工具。`test_pine_runtime.gd -- --game-cards --reuse-imports` 真实 HTTP 回归失败数 0，独立风动测试覆盖流式卸载/重载。256 棵压力测试、视觉对照与适用范围见 [松树密集场景记录](pine_editor_integration_20261006.md)。

2026-10-06 资源 LOD：网格节点可携带 `extras.rmmo_visibility_range`，字段为 `begin`、`end`、`bounds`（六个有限数：位置 xyz 和正尺寸 xyz）。距离须为 0～100000 有限数，`end=0` 表示无上限，否则必须大于 `begin`；非法配置整体忽略，无副作用。统一导入与运行时流式加载恢复可见范围及共同包围盒中心，使用 1 m 滞回、无渐变。UI/MCP 沿用相同放置、撤销与保存流程，无新工具或参数面板。`test_asset_visibility_range.gd` 和 `test_pine_runtime.gd -- --game-cards` 已通过，后者含真实 HTTP 发现/放置/非法调用/撤销重做/保存重开，失败数 0。详见 [松树 V6 验收](pine_editor_integration_20261006.md)。

2026-10-06 松树薄叶材质：资源节点可携带 `extras.rmmo_leaf_backlight`（长度与表面槽相同，逐槽线性强度 0～1，0 表示不处理）。统一 glTF 场景加载路径恢复叶片背光，风场保留该设置及背光纹理；不以文件名猜测叶子，也不为树皮自动加透光。非法数组整体忽略且无材质修改。沿用现有 3D `list_assets`、`place_asset`、`get_object`、`set_object_properties.wind`、保存及撤销，无新工具/schema；这是带光学参数的资源转换，不新增 UI 参数面板。验收入口为 `tools/test_leaf_backlight.gd` 和 `tools/test_pine_runtime.gd -- --fine-clusters`，实际通过状态以测试日志为准。背光为实时近似，不等同于 Blender 的体积散射。

2026-10-06 街景道具接入：复用 `list_assets`、`place_asset`、`set_object_properties.wind`、`set_environment` 及保存/撤销操作，不新增工具或恢复二维入口。含自带风场标记的 GLB，显式 `wind.profile="off"` 现在保存关闭覆盖，避免删除配置后重新启用模型默认受风。UI 与 MCP 共用 `wind_tools.set_settings`。小壁灯随既有游戏时钟发暖光；接入范围、真实 HTTP 与游戏验证记录见 [街景道具接入](town_props_integration_20261006.md)。

2026-10-04 房屋加载性能修复：工具仍为 **118 项**，schema、编辑事务及旧二维下线状态不变。CPU 刷面几何/切线实现由 UI、MCP 和运行时共用；不可变地图加载专用的校验及等价方块缓存不用于后续编辑事务，避免跨编辑复用过期校验。`paint_surface`、锁定保护、撤销重做、保存重开及非法调用通过真实 HTTP 回归；性能记录见 [房屋加载修复验证](world_editor_todo.md#房屋加载修复验证2026-10-04)。

2026-10-03 石桥通航净空：`preview_bridge/generate_bridge.auto_clearance` 缺省为 `true`，按实际水面自动增加拱高；主通航孔须保留 **2 米宽、至少 2.5 米高**的连续通道，靠岸小孔可较低。关闭自动调整仍校验硬下限，所需拱高超过 15% 坡度限制时原子拒绝。预览返回最终 `camber` 及 `navigation` 实测值。河道入口的石桥按填写拱高校验同一规则，当前仍为 118 项，旧二维保持下线。

2026-10-03 已有道路石桥转换：`preview_bridge/generate_bridge` 新增 `road_edge_id`，UI 可从已有桥梁道路读取、选择桥型并转换旧桥板；同事务保留引道、逐面 UV 材质和原道路拓扑。支持接路桥型/拱高/深度修改，增量刷新受影响物件，旧预览/保护/手改明确拒绝，当前仍为 118 项。见 [石桥与道路转换](world_editor_stone_bridges.md)。

2026-10-03 程序化写实石桥：当前 **118 项** 3D 工具。新增桥型列表、预览、生成及保存桥型；Blender 模块按长度装配，支持平直/拱起、三组 PBR、合并网格与 LOD。河道桥梁也可选择桥型，继续支持道路绑定。见 [石桥说明](world_editor_stone_bridges.md)。

2026-10-03 城镇地表收尾：`set_river_materials` 增加 `wet_darkening`（0～0.8，默认 0），与 `wet_height` 一起控制天然岸沙/土/岩的湿痕；UI 同步提供参数，旧图不自动改变外观。当时为 114 个 3D 工具；泥路软边和逐面铺装分别复用 `paint_terrain_region` / `paint_surface`。

2026-10-03 农田垄沟：新增 `set_terrain_furrows`，与地形面板共用方向、垄距、高度、田边留白、保护与撤销操作；`list_terrains.ground_regions.regions[].furrows` 返回可编辑配方。详见 [农田垄沟和接缝](world_editor_furrows.md)。

2026-10-03 区域地表绘制：该批交付时 **114 项** 3D 工具。新增 `paint_terrain_region`、`remove_terrain_region`；`set_terrain_material` 增加可选 `saturation`（0～1），保存为地形底材调色，法线与原贴图保持不变；UI 支持拖矩形或点选多边形，MCP 使用相同保护、验证、撤销和保存。`list_terrains.ground_regions` 返回区域、局部 XZ 坐标和 PBR 材质，`editor_state.ground_region_drawing` 表示待提交草案。详见 [地表材质区域](world_editor_ground_regions.md)。

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

`get_environment` / `set_environment` 新增 `interior_cutaway` 和 `indoor_camera_distance`（2～5 米）。2026-10-04 按用户要求，`interior_cutaway` 默认关闭，当前七款样房也显式保存为 false；开启该选项后，隐藏仅在第三人称角色室内，且相机到角色射线第一次碰到其上方楼板/天花板时触发。无障碍或先碰普通物体/墙不触发；第一人称和 VR 禁用。UI/MCP 共享 schema、环境记录和撤销，保存重开有效。相机效果需进入试玩；MCP 编辑的是配置，不强制更改玩家实时视角。详情见 [环境与相机](world_editor_events_environment.md)。

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
| 写实石桥及可复用桥型 | `list_bridge_prefabs`、`preview_bridge`、`generate_bridge`、`save_bridge_prefab` |
| 河道开槽、河岸、桥梁与桥头、恢复地面 | `list_waterways`、`preview_waterway`、`generate_waterway`、`remove_waterway` |
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
| 编辑器风场预览（会话设置，默认关闭） | `set_editor_wind_preview`；`editor_state.wind_preview` |
| 中键键盘镜头平移（会话操作） | `move_editor_camera {offset:[x,y,z]}` |
| 素材缩略图状态与补生成 | `list_assets` 的 `thumbnail`；`repair_asset_thumbnails {asset_ids:[...]}` |
| 地图加载作业及进度 | `open_world {path,discard_changes?,background?}`；`editor_state.load` |
| 楼层范围、隐藏/淡化、读取视图配置 | `get_editor_view`、`set_floor_view` |
| 指定或拾取试玩出生脚点 | `set_playtest_spawn`、`pick_playtest_spawn` |
| 临时副本试玩、结束、查询状态 | `start_playtest`、`stop_playtest`、`playtest_state` |
| 参数化建筑模板、批量预览/生成、实例列表 | `list_building_templates`、`preview_buildings`、`generate_buildings`、`list_buildings` |
| 固定建筑烘焙；旧建筑参数更新、删除、解除关联 | `bake_building`、`update_building`、`delete_building`、`detach_building` |
| 沿街普通、中世纪、城中村建筑规划与生成 | `preview_street_buildings`、`generate_street_buildings` |
| 矩形区域内随机单栋/成片建筑，避让已有物体 | `preview_region_buildings`、`generate_region_buildings` |

## 语义与示例

当前共 **104 个工具**。参数化建筑的外观/室内一致性、批量生成和修改保护见 [world_editor_buildings.md](world_editor_buildings.md)。楼层隔离、指定出生点和临时试玩见 [world_editor_playtest_floors.md](world_editor_playtest_floors.md)。事件模板、环境与人物遮挡轮廓见 [world_editor_events_environment.md](world_editor_events_environment.md)。高差、楼梯、屋顶、桥栏杆和自定义套件见 [world_editor_height_terrain.md](world_editor_height_terrain.md)。贴地、表面放置和排列的参数、完整组规则及接触精度边界见 [world_editor_placement.md](world_editor_placement.md)。这四项均使用当前选择，共享撤销事务，返回实际修改的 `changed_ids`。草稿/关闭工具见 [world_editor_recovery.md](world_editor_recovery.md)；材质库、选面、刷面及恢复原材质见 [world_editor_surface_materials.md](world_editor_surface_materials.md)。

XYZ 为米，Y 向上，欧拉旋转为度。`set_object_transform.size` 对基础物件为尺寸，对导入模型为三轴缩放倍率。精确数值操作不套用吸附。`transform_selection` 是世界轴增量，绕共同中心旋转/等比缩放，一次调用对应一次撤销。界面与 MCP 共用变换、分组、选择、自动瓦片和预制件业务逻辑。

`set_environment` 的 `sun_shadows`、`ambient_occlusion` 控制太阳投影和接缝环境遮蔽，与环境面板、运行时使用同一配置；均为布尔值并默认启用。SSAO 需要 Forward+。两字段沿用一次撤销、保存重开及非法调用无副作用语义。

`configure_transform` 的吸附值与界面一致：位置 `[0, 0.01, 0.1, 0.25, 0.5, 1]` 米；旋转 `[0, 1, 15, 45, 90]` 度；缩放 `[0, 0.1, 0.25, 0.5]`。`0` 表示关闭。状态同时返回选择的 `space` 和实际 `effective_space`：多选使用世界轴，单物件缩放使用局部轴。

2026-10-07 加载准备：UI 与 `open_world` 共用分阶段作业；`terrain` 阶段在私有后台上下文准备地形邻接、网格数组和区域遮罩，`asset` 阶段逐个解析首次使用的模型，场景生成及资源缓存写入仍在主线程。地形阶段使用活动条，不声明未实现的逐物件进度；模型和构建阶段保留记录计数。`timings.build.units` 区分后台 CPU、等待和主线程耗时（`terrain_prepare_wait` 是等待墙钟时间）。加载专用数组和遮罩只在单个物件构建时临时注入并立即恢复；后续雕刻、区域修改和撤销不复用旧快照。`textures` 阶段按需在后台准备地形及冻结预制件图片和法线翻转/多级纹理，主线程只创建纹理资源；Image 交接同样限本次物件构建，修图跨加载会失效对应材质/着色器及依赖这些图片的冻结预制件缓存，已存在但损坏的图片不能沿用旧图或被保存为退化材质。`picking` 阶段准备拾取碰撞：大网格精确三角数组在私有 worker 展开，主线程逐网格发布原单形状，保持独立拾取与原生面索引；隐藏/楼层/城防过滤与同步路径相同。`picking_faces_wait` 区分等待时间，`add_bodies` / `record` 排除这部分等待，单个物理形状原生构建仍不可抢占。地形几何至多四个私有工作线程并行，`terrain_geometry.wall_ms` 与 `worker_elapsed_sum_ms` 分别为墙钟时间及各工作线程计时间隔之和，不应相加或视为严格 CPU 周期。解析失败保持既有缺失素材占位，失败缓存只限本次加载，修复后重开会重新解析。小图真实 HTTP 回归见 `tools/test_editor_asset_preparation.gd`，含修改、撤销重做、保存重开与线程退出清理。

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
- 2026-10-07：`save_prefab` 与 UI 共用的模型依赖导入，对严格验证的自包含、无扩展 GLB 保持原字节并按内容哈希复制，避免跨库导入反复导出材质贴图。glTF/外链/不能证明安全的 GLB 仍走既有打包流程。通用源模型文件导入当前仍仅有 UI 入口，3D MCP 本次通过已有 `save_prefab` 覆盖共享业务，未新增通用导入工具。见 [GLB 导入验证](editor_import_bytes_20261007.md)。
- `place_asset.position` 是表面落点，底面自动对齐。自动瓦片需用 `paint_auto_tiles`，`family` 为 `wall/road/grass/dirt/water/cliff/stairs/roof/bridge`；格宽为 `1/2/4/8` 米。点的 Y 被 `height` 替代。高台同基底自动处理邻格高差，桥/道路按楼梯两端标高连接，其余跨高度独立。`erase=true` 擦除；一笔连同邻居重算共同撤销。自由变换自动块后脱离自动拼接。
- 普通 `place_asset`、`delete_selection`、`create_terrain` 与 UI 共用按 UUID 更新的编辑视图提交；普通增删及其撤销重做保留无关节点和碰撞，自动瓦片更新必要邻居，地形变化刷新实际受影响的地形邻接。派生渲染只失效受影响来源，再按帧准备；未变城防碰撞组保留。工具参数和返回结构不变，不启用二维接口。普通地面 UI 一笔内重复访问同格不再提交空更新。这里优化的是编辑视图，磁盘资源增量保存仍由独立保存流程负责；撤销快照和单个复杂模型/地形的生成成本没有因此消失。
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

鼠标拖动、框选、点选表面、拾取出生点或画笔事务正在进行时，MCP 修改返回忙碌，避免合并进用户未结束的撤销事务；只读查询仍可用。`editor_state.surface_placement_active` 表示正在点选表面。关闭确认期间只允许 `close_editor` 处理关闭，其余写操作拒绝。读取失败的地图禁止修改，但仍可打开其他地图、管理/恢复草稿或关闭。保存期间拒绝全部写操作（含重复保存、打开、关闭、草稿修改），保留只读查询；默认等待保存的 HTTP 连接不阻塞其他客户端，也不受普通 10 秒空闲超时限制，断开连接不会中断发布。`close_editor action=save` 同样等待后台保存成功才关闭。地图加载为分片校验与后台准备作业，草稿编码/压缩/发布在后台进行；单个复杂构建步骤仍可能阻塞，预制件打包仍同步。当前未提供保存取消接口，试玩的异步准备/加载可用 `stop_playtest` 取消。

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


### 写实城墙与城门净高（2026-10-03）

`preview_fortification` / `generate_fortification` 同步支持 `style=medieval_stone|plain`、`trim_material_id`；新建默认写实石城墙、墙高 7.5 米。现有 stone/door 材质字段继续使用。城门 `gates[].height` 最低 5 米，表示拱圈两侧最低通行净高而非拱顶；低于 5 米的请求在事务前拒绝。旧 plain 文档可读取，升级写实样式时同时提高旧门高度。开度控制仍使用 `set_fortification_gate`，包括铁箍和木板的视觉网格与碰撞一起运动。工具总数仍为 118，详见 `docs/world_editor_fortifications.md`。

新写实城墙默认墙厚 3.5 米，`wall_access` 启用中空圆楼、内侧门、楼内旋梯和可行走楼顶；城墙本身不设外置登墙梯。`arrow_slits` 控制圆楼外向射击孔，`tower_door_open` 控制圆楼内门初始开度，`interior_side` 指定开放路径城内侧。至少墙高 7.5 米、墙厚 3.2 米并保留塔楼；圆楼因游戏通行尺寸扩大，占地参与统一碰撞保护。预览 `access_routes` 返回入口/屋顶、门 ID、内部楼梯及射击孔位置。旧配方不自动升级；真实 HTTP、角色通行、撤销重做和保存重开验证使用 `tools/test_world3d_fortification_access.gd`。

城门铰链包含随门套筒与固定轴销/铁板：现有开度工具一并驱动，保存、撤销和运行时接口复用；固定件不参与旋转。旧 plain 门的仅开关操作保留历史尺寸。


2026-10-04 城墙生成参数：`tower_layout=automatic|manual`（新建默认 automatic，旧配方默认 manual）、`tower_spacing`（自动环形目标米数，默认 60）、`tower_count=0`（自动计算；手动模式为八座）、`floor_material_id`（圆楼石铺地面）。**50 米塔心距离和 10 米塔门保守净距仅限制自动布局，手动部署不受约束。** 自动规则覆盖不同城墙组；基础几何/物件保护检查仍共用。预览返回 `tower_count/layout_rules/layout_zones`，UI 展示相同禁放圈。新圆楼地基下延 foundation、石铺面抬高 3 厘米，入口保留 5 米净高，材质、模式、地面随原事务撤销和保存。工具数仍为 118，详见 [自动布局禁区与圆楼地面](world_editor_fortifications.md#自动布局禁区与圆楼地面2026-10-04)。


2026-10-04 不规则城墙描图扩展：工具数仍为 118。`preview_fortification` / `generate_fortification` 同步支持 `tower_indices`、`terrain_foundation` 与 `gates.kind=land|water`；细则、预算、保护语义见 [城防文档](world_editor_fortifications.md#不规则参考图描墙2026-10-04)。参考图的等比缩放、透明度和标定复用已有 3D 工具，不注册二维适配器。真实 HTTP 回归为 `tools/test_world3d_wall_trace.gd`。

同轮城防静态网格合并自动用于 UI 与运行时：`editor_state.fortification_batching` 返回城防源对象数、源/结果渲染面及顶点数、`instanced_groups`；`ground_batching` 保留地面统计。同空间块内重复几何实例化，其余兼容构件合并。活动门、交互构件独立；碰撞、选择、刷面、原生保存和撤销仍使用原始记录。工具数仍为 118。合并不是有损文档操作，无需独立 MCP 写入命令；`test_world3d_fortification_batching.gd` 覆盖真实 HTTP 查询、非法原子失败、编辑保护、选取、城门、撤销和保存重开，并检查同模型不同材质恢复互不影响。

同轮补齐首次缓存和碰撞分块：`editor_state.fortification_collision_batching` 返回 `source_objects/bodies/shapes/triangles/rebuild_count/last_sync_ms/max_group_ms` 及分阶段 `profile`。渲染统计增加 `last_sync_ms/max_commit_ms/sync_profile_us`；`max_build_ms` 含后台排队时间，不能当作主线程阻塞时间。UI 与 MCP 自动更新同一缓存，选中构件退出合并碰撞，射线按命中三角面返回原 UUID，门扇/事件仍独立；隐藏、隔层、变换和刷面沿用原事务。派生缓存不写入地图，不增加工具或启用二维适配器。

拖动/驻留优化补充：渲染统计提供 `sync_count/release_groups_visited`，碰撞统计提供 `shape_cache_groups/shape_cache_triangles/shape_cache_hits/shape_cache_misses`。城防纯位移/旋转复用原网格，选中件拖动不反复同步无关批次；有几何变化仍走完整失效逻辑。最近碰撞形状缓存最多 64 组 / 262144 个三角面，缓存形状不等于活动碰撞体，离开分块时 `bodies` 仍归零；文档重建清空缓存。现有变换、选择、刷面、隔层、撤销和保存工具保持相同业务校验。

后续刷新链修复：`set_object_transform` 与 `transform_selection` 和 UI 共用的变换操作完成后，面板只更新数值，避免重复触发全场景合批；当前已选城防件的数值变换仅同步一次，切换选中对象或几何变化仍保留必要失效。工具清单、参数 schema、返回值、保护规则与撤销/保存语义均不变。`test_world3d_fortification_batching.gd` 同时覆盖实际拖拽入口（包含面板更新）与真实 HTTP 数值变换，不能再用仅调用 `_sync_selected_transform` 的测试替代整条刷新链。


### 2026-10-04：住宅 v8

`list_building_templates` 返回的共享参数 schema 新增 `stair_layout: straight | switchback`、`base_height: 0..0.9`、`curtains: boolean`。`preview_buildings` / `generate_buildings` / `update_building` 与当前 3D 建筑表单使用同一校验和事务。中世纪默认样房采用折返楼梯、0.45 m 台基和窗帘；旧配方继续保留原尺寸与布局。门窗五金属于原有 fixture 身份，固定轴座不随门扇转动。保存的 `wall_grid` 是带真实门窗洞口的结构网格，不能当作实心包围盒处理碰撞。

新增参数的真实 HTTP、非法调用无副作用、撤销重做、保存重开验证见 `tools/test_house_revision_mcp.gd`。本次没有重新启用二维 MCP。

2026-10-04 后续样房修订：同一建筑生成业务现在包含圆杆布套安装、墙面支架、统一楼层立柱、共面接缝裁面和夜间烛台壁灯。`joined_box` 保存裁剪后的可见面片，游戏碰撞仍使用原完整实体；`candle_sconce` 保存壁灯造型。两者属于生成构件内部数据，不另增 UI/MCP 参数，旧地图打开时不自动重建。灯位按房间墙面生成，与窗帘至少相隔 1 米；运行时根据地图时钟启闭。真实 HTTP 已覆盖生成、非法输入无副作用、撤销重做、保存重开及内部形状签名稳定。详见 [样房修订](house_revision_20261004.md) 和 [烛台壁灯](house_candle_sconce_20261004.md)。


### 2026-10-04：生成后烘焙为固定建筑预制件

此约定替代上文新生成房屋可以逐件编辑或重新调整参数的说明。生成阶段的蓝图/参数/拼接保持可配置，`generate_buildings`、街道、区域及街区生成在提交时自动烘焙；落地后只允许整栋移动、Y 轴旋转、复制、删除，活动门窗仍用 `set_building_component_state`。保持逐楼层、屋顶/天花板和相机遮挡隐藏语义。

新增当前 **3D** 工具 `bake_building {id}`，与 UI“烘焙旧建筑为固定预制件”共用业务、保护校验和一次恢复事务。`list_buildings` 提供 `baked`、烘焙后的 `part_count` 与原 `source_part_count`；预览返回 `source_part_count`，不将它描述为落地组件数。`update_building` 和 `detach_building` 仅适用于未烘焙的旧建筑，固定预制件的内部变换、材质修改或解组均拒绝，`component_edit` 不会解锁它。`get_object` 返回几何摘要、版本、字节数，不返回不可编辑的 Base64。

`save_prefab` 支持完整固定房屋的资源包打包，保留建筑身份、地基标高和活动门窗；`place_asset` 创建独立固定实例并做保留区/已有物件碰撞检查。不能只保存固定房屋的部分组件。旧的普通物件预制件仍可编辑。撤销重做与保存重开保留这些语义。实现和实测见 [固定房屋预制件](house_prefab_20261004.md)，真实 HTTP 验收为 `tools/test_house_prefab_mcp.gd`，未启用旧二维适配器。
# 城防 / 桥梁固定预制件补充（2026-10-04）

当前 **3D** 工具新增 `bake_fortification {id}` 和 `bake_bridge {id}`，旧二维入口不注册。UI 与 HTTP MCP 共用业务操作、保护检查、原子事务及原生保存。`generate_fortification`、`generate_bridge` 和河道生成的石桥在应用后自动烘焙；预览不冻结，不产生写入。烘焙失败不提交半成品。

固定城防不能重生成、解除关联拆件、缩放或移动路径；`remove_fortification` 必须传 `keep_objects:false` 整体删除。城门通过 `set_fortification_gate` 修改保存姿态，不触发结构生成。固定桥的跨度、拱孔、材质不可重新调整。`list_fortifications` 增加 `baked`、`source_part_count`，`count` 是实际存储组件数。

真实 loopback HTTP 回归：`tools/test_structure_prefab_mcp.gd`，覆盖工具发现、合法/非法转换、无副作用失败、双门扇转轴、活动门状态与签名、原生保存重开、撤销重做、隐藏/锁定保护以及新放置自动烘焙。大型地图通行使用 `test_medieval_town_walls.gd` / `test_medieval_town_stone_bridges.gd --map=... --out=...` 在后台桌面验证。

## 参考城镇样式（2026-10-05）

`list_building_templates` 增加 `town_presets`，八款参数与编辑器按钮一致；用 `preview_buildings`、`generate_buildings` 原有参数和事务调用，无新增二维入口。旋转占地检查修正也由 UI、生成和预制件放置共同使用。真实 HTTP 验收入口：`tools/test_town_styles_mcp.gd`，覆盖发现、合法旋转生成、实际重叠无副作用失败、撤销重做及保存重开；材质库烘焙验收见 `tools/build_town_style_library.gd`。


### 2026-10-05 整栋窗口方案与三层商住楼

`list_building_templates.town_presets` 现为十一款，新增两款三层商住楼和紧凑双层住宅。`window_styles` 与共享参数 schema 公开 `window_style`：`casement`（旧式）、`cross_lattice`（细长斜撑）、`diamond_lattice`（菱格及托架窗台）、`round_arch`（圆拱分格）、`tall_shutter`（细长格窗及窗板）、`random`。房屋面板的“整栋窗口方案”与 3D MCP 使用同一蓝图、验证和撤销事务。

一个建筑实例只选一个窗口方案，含所有楼层、翼楼与老虎窗；老虎窗按空间缩小。`random` 以该实例 `seed_offset` 只抽取一次，保存解析后的明确方案。批量请求需要给实例不同 seed_offset 才能获得变化；没有逐窗随机。省略参数仍使用旧式，不强制改写已有房屋。新式仅 tall_shutter 配窗板。生成后可沿用 bake_building 冻结；冻结实例依旧遵守原有不可参数更新规则。

真实 HTTP 验收 `tools/test_town_styles_mcp.gd` 覆盖发现、圆拱三层楼旋转生成并冻结、非法窗口枚举/重叠失败无副作用、撤销重做、保存重开。结构和参考见 [窗口及街景实施记录](town_frontage_rhythm_20261005.md)。本图街区候选评分脚本仍是离线制作工具，不等于通用 UI/MCP 自动排布功能。


### 2026-10-05：木门与可换旗路灯

`generate_buildings` 与 UI 共用木门生成：外门为 846 三角面铁饰斜拼门，室内门为 576 三角面黄铜圆钮斜拼门扇及独立 36 三角面固定木框。室内门依据房间边界朝房间内开启，连接翼楼的门朝附属房开启；外门保持向室内开启。`set_building_component_state` 沿用原 schema 与事务，保存/复制/打包保留顶点色。无需额外门样式参数，固定旧建筑不会因加载自动重建。详见 [外门交付](timber_door_20261005.md)与[室内门交付](interior_timber_door_20261005.md)。真实 HTTP 回归 `test_house_prefab_mcp.gd` 已涵盖室内门状态、非法值无副作用、锁定、撤销重做、素材库打包和保存重开。

新增 3D 工具 `set_streetlamp_banner`（旧二维入口不注册）：

```json
{"ids":["obj_1","obj_2"],"settings":{"shape":"pointed","design":"emblem","color":[0.31,0.016,0.026],"texture_path":"D:/code/rmmo_runtime/assets/banner_streetlamp/designs/festival.png","wind_enabled":true}}
```

`shape`: pointed/rectangle/swallowtail；`design`: original/plain/flag/emblem。`flag` 为整面设计，`emblem` 为保留底色的独立图案；`trim_color` 为原版刺绣 RGB。批量 1～256 个，必须有独立旗帜插槽且可编辑；缺图、非法形状、越界路径、锁定/隐藏/隔层均无副作用失败。UI「路灯旗帜」与 MCP 调用同一业务方法，一次撤销并随地图保存；图片纳入依赖和素材库打包。用 `tools/test_streetlamp_banner_mcp.gd` 验证真实 HTTP、保存重开、资源重定位与 Vulkan 风场。


2026-10-05 旗幡路灯昼夜接入：现有 `set_environment` 直接驱动游戏/编辑器共用的 `streetlamp_lights`，20:00–06:00 开启蓝色晶石、轻微光晕及所有已加载路灯的无阴影蓝灯（已取消按距离选最近两盏的限制）。工具清单和 schema 无新增；环境事务、撤销重做和保存语义不变。`tools/test_streetlamp_banner_mcp.gd` 已通过真实 HTTP 夜间切换、撤销熄灭、重做恢复及保存重开点亮检查，原换旗操作检查继续通过。详见 `banner_streetlamp_20261005.md`。

2026-10-06 城防墙顶接缝：`generate_fortification` / `bake_fortification` 与 UI 共用的烘焙路径会裁除墙顶重复覆盖面，保留碰撞及活动门。没有新增工具或 schema；真实 HTTP 生成、非法调用无副作用、撤销重做和保存重开由 `tools/test_fortification_decks_mcp.gd` 验证。已烘焙地图不自动重生成；本次既有城镇修复通过专用维护脚本及原生原子保存完成，详见 `world_editor_fortifications.md`。
# 岩岸扩展（2026-10-06）

新增 `list_rock_banks`、`preview_rock_bank`、`set_rock_bank`、`remove_rock_bank`，同步地形面板“岩岸 / 岩壁”。参数、保护规则、保存及限制见 [原生岩岸说明](world_editor_rock_banks.md)。这些是当前 3D 服务工具，不启用旧二维适配器。
# 2026-10-06 红顶尖塔资源发布验证

“写实方形红顶尖塔·三层窗”复用当前 3D 的 `place_asset`、`select_objects`、`save_prefab`、`list_assets`、`undo`、`redo`、`save_world`、`open_world`，未增加新接口或参数面板。真实 HTTP 工具发现、合法与非法调用、无副作用失败、撤销重做和保存重开通过。报告 `D:/code/rmmo_runtime/review_artifacts/street_spire/publication.json`，失败 0，测试不修改用户地图。预制件为闭合外观地标，无内部楼梯及开门交互。

2026-10-07 高大导入构件远景：UI 与 `place_asset` 放置的同一原生实例，在后台空间索引中按完整资产世界包围盒自动识别高度至少 12 米、含实体且无 `rmmo_wind` 的构件，全部子网格共用城镇建筑远景及地形支撑依赖。普通短道具、树叶和布料仍用原驻留规则；碰撞仍在近处加载，独立编辑与保存记录不变。本项仅调整派生可见范围，不合并作者实例或新增 schema。已有运行缓存指纹覆盖 `stream_index.gd`。`tools/test_tall_prop_residency.gd` 真实 HTTP 放置、非法参数无副作用、撤销重做、保存重开和远近驻留检查全部通过；`test_landscape_residency.gd` 地形支撑回归通过。


冻结建筑派生阴影优化（2026-10-07）：UI/MCP 生成、重建、打开地图共用作者视图接入，稳定不透明冻结构件自动减少阴影表面提交；未增加工具或 schema。选择、整栋移动、楼层 dim/hide、undo/redo、风预览和保存重开通过真实 HTTP 回归。派生节点不参与拾取/材质枚举/地图导出，材质或几何资源变化即时恢复原投影；不满足稳定合同的构件使用原渲染路径。证据见 [编辑器镜头性能](editor_camera_performance_20261007.md)。


## 2026-10-07 连续道路自动路缘

`preview_road_surface` / `generate_road_surface` 新增 `kerb_enabled`（默认 false）、`kerb_width`（0.12–0.4 米，默认 0.28）、`kerb_height`（0.025–0.18 米，默认 0.055）及 `kerb_material_id`。预览返回 `kerb_length`。UI「生成道路铺面与路口」共用业务与参数；开启后 `update_road_graph` 和 UI 道路增删改自动连接同层交叉并更新外露边缘，失败整次回滚，仍支持稳定分块、锁定与手刷保护、一次撤销及原生保存。跨层不连接，桥头开口。默认材质 `pack:default:paving/automatic_limestone_kerb/material`。实际 HTTP/UI、合批和运行时验证见 [实现与验收](automatic_road_kerb_20261007.md)。不启用旧二维接口。

## 2026-10-08 加载诊断探针

`tools/profile_reference_editor_load.gd --monitor` 经真实 3D HTTP `open_world` 采集阶段/线程/模型/拾取构建及视口 CPU/GPU 数据，配合 `profile_load_hardware.py` 记录目标进程硬件数据。监控默认关闭，不改变业务事务、工具清单/schema、保存或撤销语义，不新增二维工具。原有 `editor_state.load` 作业计时继续可用；额外硬件与 trace 仅写探针报告，尚无通用 MCP 硬件仪表接口。整城真实 HTTP 打开、身份、射线和选择验证通过，复现方法及限制见 [本轮报告](reference_map_performance_20261008.md#加载监控实测与方案修订2026-10-08)。
