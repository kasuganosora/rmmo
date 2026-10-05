# 连续城墙与活动城门

更新于 2026-10-03。入口：**城镇布局 → 连续城墙与城门**。当前 3D MCP 共 118 项，其中五项为城墙操作；UI 与 MCP 共用 `fortification_tools.gd`，所有实体即时生成到地图，默认资源包提供基础模块和材质，完整城墙按地图参数即时生成。

**美术状态：用户已要求继续优化，当前外观未验收。** 墙体层次、塔楼/城门比例、垛口和弧面纹理等已列入 [编辑器待办](world_editor_todo.md)，功能截图不代表最终城墙美术。

## 使用

1. 新建城墙，选择“点选折线”或“圆形 / 椭圆围城”，设定地面标高、墙高/厚度、向下延伸的地基，以及塔楼和垛口开关。
2. 折线模式点选中心线，Enter 完成、Backspace 撤一点、Esc 取消；勾选“闭合围城”连接末点与首点，不重复输入首点。环形模式可以直接设中心、两轴半径和朝向，或点选包围范围两个对角再 Enter；相等半径是圆形，不等为椭圆，始终闭合。
3. 折线城门按段号和比例定位（从 0 起，`t=0.5` 为中点）；环形城门按角度定位（0° 东、90° 南、180° 西、270° 北，再随城墙朝向旋转）。指定门洞宽高和初始开度。道路应从门洞内穿过，墙身和门楣不能占用道路及上方净空。
4. 选择石材和木材，预览并应用。默认 UI 在资源存在时使用城堡砌石和磨损木板，包含 PBR 法线及米制纹理重复。MCP 新建写实城墙省略材质使用同一默认 PBR，更新省略则沿用。
5. 选已有城墙修改参数并重新预览；“打开/关闭已生成的所选城门”控制双扇门并保存初始状态，单次撤销。运行时程序控制另见下文。

当前生成连续墙体、护墙/垛口、石拱门洞和双扇木门（plain 保留平顶及旧塔型）。新写实配方默认开启真实射击孔和登墙通路，统一使用中空圆楼：城内侧入口、内部旋梯、可行走塔顶及相连墙顶步道。弧线采用共享边界的曲面分段网格，圈内留空；不会用整圆实体堵住城内。旧配方保留原样，需显式启用新参数；升降闸门与随坡起伏城墙仍未实现。

新环形布局默认自动计算塔数，详见下节自动布局禁区；手动模式或历史配方可保留原先的等参数角布塔。墙顶护墙和垛口随曲线排列。圆/椭圆由每段不超过 3°、约 2 米弧长的凸补片近似，兼顾外观、物件避让、刷面和运行时碰撞。当前提供完整圆/椭圆与手绘折线，还不支持任意样条或多段局部圆弧混合边界。

## 几何、占地和保护

- 新建默认墙高 7.5 米、厚 3.5 米、地基向下 1 米（旧配方默认高 6 米、厚 2.5 米）。一般允许高 4～12 米、厚 1.5～4 米；开启登墙通路至少高 7.5 米、厚 3.2 米，并要求写实样式及塔楼。地基 0.5～3 米。每条线段至少为墙厚三倍，单组最长 1000 米、2～32 点，闭合至少三点。拒绝自交、过尖折角和过近非相邻墙段。
- 环形两轴半径各 15～200 米，默认均为 40 米，同时受单组周长 1000 米和 4096 构件预算约束；过扁椭圆、靠塔城门、重叠门洞、越出承托地面会拒绝。两点快捷选范围会将朝向归零，可再调整。切换形状后需更新或移除使用旧定位方式的城门草案。
- 每组最多 16 个城门、4096 构件，每图最多 64 组。公开生成请求门洞宽 3～10 米、高 5～9 米，门顶低于墙顶至少 0.5 米；门洞需避开角塔、墙端及其他门洞。历史 plain 低门可继续读取和开合。
- 墙体、角塔和城门活动范围都需要同标高的实际水平地面承托；不会在河槽、悬空地段生成。建筑、现有物件（含隐藏/锁定）、禁建区及保留通道都参与避让。活动门扇允许横过道路，静态砌体仍须留足道路净空。
- 完整门扇转动范围保守预留，后续建筑和植被生成不能占用。门扇闭合能阻挡角色，打开能通行；不会自动规划道路或把任意普通模型改造成门洞。
- `editor_layout.fortifications` 保存设置及成员 UUID/完整签名；记录附带 `fortification:{id,part,role}`。所有成员自动归为一组。配方重生成、开合、删除和解除关联使用共享事务。
- 任意成员被手改/刷面/移动/改名/挂事件/删除后拒绝重生成，不覆盖手工作品；隐藏、锁定及楼层隔离同样保护。`list_fortifications.modified_or_missing` 返回具体成员。移动既有组合不会自动改写中心线配方，重生成前需恢复或解除关联。
- 解除关联保留现场并把门扇烘焙为当前姿态的普通静态物件；删除要求成员未改。普通复制/快照预制件同样清除生成归属，避免原门控制到副本。上述操作均支持撤销。
- 预览不写文档，过期 `plan_token` 拒绝；保存/草稿/重开校验记录、配方及依赖。全量重建与快照撤销仍是当前实现，未承诺整城海量构件性能。

## MCP 与运行时

| 工具 | 参数 / 结果 |
| --- | --- |
| `list_fortifications` | 无参数、只读；设置、成员数及手改/缺失成员 |
| `preview_fortification` | 折线新建需 `id/points`，环形需 `id/shape:ellipse`；返回设置、轮廓 `outline`、长度、构件数、门洞、`access_routes` 及 `plan_token` |
| `generate_fortification` | 同预览，可加令牌；同 ID 只传变化字段；幂等、一次撤销 |
| `set_fortification_gate` | `id/gate_id/open`，开度 0～1；更新两扇门初始状态 |
| `remove_fortification` | `id`；`keep_objects` 默认 true 保留现场，false 删除 |

`points` 是折线路径 XZ 二元数组；环形使用 `center_x/center_z/radius_x/radius_z/rotation/tower_count`，不需要 points。`base_height` 提供统一 Y。城门数组每项必须含 `id/width/height/open`，折线再加 `segment/t`，环形加 `angle`，不能混用定位方式。旧折线配方未含环形字段时仍可读取。`editor_state.fortification_drawing` 表示 UI 点选中。

```json
{"name":"preview_fortification","arguments":{"id":"city_wall","points":[[-30,-30],[30,-30],[30,30],[-30,30]],"closed":true,"gates":[{"id":"north","segment":0,"t":0.5,"width":6,"height":5.0,"open":1}],"stone_material_id":"pack:default:walls/castle_rubble/material","door_material_id":"pack:default:wood/worn_planks/material"}}
{"name":"set_fortification_gate","arguments":{"id":"city_wall","gate_id":"north","open":0}}
{"name":"preview_fortification","arguments":{"id":"round_city","shape":"ellipse","center_x":0,"center_z":0,"radius_x":90,"radius_z":75,"rotation":0,"tower_count":8,"gates":[{"id":"north","angle":270,"width":8,"height":5.0,"open":1}],"stone_material_id":"pack:default:walls/castle_rubble/material","door_material_id":"pack:default:wood/worn_planks/material"}}
```

用同一份参数调用 `generate_fortification` 应用预览，再调用开关门。游戏加载后复用 `building_fixtures.gd`，运行时 owner ID 为 `fortification:<城墙id>`：

```gdscript
var Fixtures = preload("res://scripts/world3d/building_fixtures.gd")
Fixtures.list_runtime(map_root, "fortification:city_wall")
Fixtures.set_runtime(map_root, "fortification:city_wall", "north", 1.0, 0.8)
```

最后两个参数是目标开度和动画秒数；可中断并改向，碰撞随门扇同步。运行时动画不改编辑器初始配置；MCP 工具修改的是文档初始状态，未新增游戏网络命令。

## 验收

`tools/test_fortification_plan.gd` 覆盖闭合城墙、角塔/垛口、门洞净空、角落及自交拒绝。`tools/test_world3d_fortifications.gd` 经真实 HTTP 验证 118 项工具发现、预览只读、合法/非法调用、无副作用失败、物件/道路避让、编辑保护、幂等、撤销重做、UI 点选与应用、草稿和保存重开，并检查实际石材法线。后台运行时测试动画开合，用 2.1 米角色胶囊验证关门阻挡和开门通行。

`tools/test_world3d_round_fortifications.gd` 经真实 HTTP 验证圆形、更新为椭圆、圆塔/城门冲突及道路净空、圈内已有物件保留、实际 PBR、撤销重做、草稿、保存重开及再次保存；通过真实画布输入验证两点快捷选范围。重新加载运行时后检查弧墙实体碰撞、内部无虚假填充，以及角色通过环形城门。

最终后台验收日志位于 `D:/code/rmmo_runtime/review_artifacts/`：

- `fortifications_final.log`：`FORTIFICATIONS_FINISHED failures=0`，包含普通复制门扇的姿态烘焙及归属隔离。
- `round_walls_final.log`：`ROUND_WALLS_FINISHED failures=0`；测试地图、圆形和椭圆截图在 `D:/code/rmmo_runtime/cache/world3d/round_walls_10347141/`。
- `walls_regression_fixtures.log`：既有房屋门窗动画、导航、流式重载回归通过。
- `round_walls_paint_regression.log`：完整刷面 UI / HTTP / 保存回归通过；单网格同 UV 参数刷面合并的几何/法线/UV 保真由 `tools/test_surface_uv_batch.gd` 验证。

最初未合并同 UV 刷面时，环形测试在再次保存阶段超过总时限；修正后完整重跑通过。当前只优化同一网格内的渲染面，跨构件静态合批与房屋拆件问题按用户要求另列待办，本轮不声称已完成。


## 写实城墙模块（2026-10-03）

新建城墙默认 `style=medieval_stone`，默认墙高 7.5 米；`plain` 保留旧版外观。UI「城墙外观」与现有 3D MCP 共用同一个生成事务和校验，不增加二维工具。`trim_material_id` 单独配置压顶和拱圈，`stone_material_id` / `door_material_id` 分别配置墙体与木门。空材质 ID 使用默认包的 castle_rubble、stone_tiles_facade 和 worn_planks，均保留法线；铁箍单独使用锻铁材质。

城门 `height` 是整个洞口的**最低净高**，新建/更新的门参数至少 5 米，拱頂更高；墙顶须再高至少 0.5 米。UI 默认 5 米，HTTP 低于 5 米直接拒绝且不修改地图。旧版已保存的 plain 配方仍可读取，不强行改写用户地图；切换到写实方案时须将旧门净高提升到 5 米。运行时以 3.5 米相机通道及全门宽 4.99 米射线验证，不只测拱顶。

来源：已购 [Dexsoft Medieval Castle](https://www.fab.com/listings/94b2c6c1-93a7-4291-9af9-ecc84884e751)。复用其中 `SM_CastleWallSupport2` 的石扶壁，连续墙身、收坡墙脚、压顶、拱圈、木门与铁箍在 Blender 中制作适配模块。没有把成套场景或高塔整体拉伸。

- 默认包模型：`assets/fortifications/medieval_stone/medieval_wall.glb`，来源记录在相邻 `source.json`。
- Blender 源：`sources/authored/fortifications/medieval_wall.blend`。重建工具 `tools/build_medieval_wall_kit.py`；Unity 归档只提取 FBX/材质，不安装或执行包内脚本。
- 网格在编辑器按尺寸即时变形生成，圆/椭圆使用现有共享边界曲线；跨 0° 的门拱保持连续。新增扶壁、木板、铁箍没有拆成新的地图物件。
- 每个构件最多两个共享材质表面，自动生成 LOD，网格缓存按估算 32 MiB / 最多 1024 项限制（包含 LOD 余量），避免环墙数百构件反复挤出缓存。仍沿用原来的城墙构件身份与分组，**没有声称整圈城墙已合为单个网格**；跨构件合批仍属于后续性能工作。
- 沿起伏地形自动贴合、混合样条边界仍未实现；塔楼内部和登墙通路见下节。

`tools/test_fortification_art.gd` 验证模块外包围不超过规划碰撞范围、拱圈最低 5 米、环形跨零度门、材质表面数；既有折线和环形 HTTP 测试覆盖撤销重做、保护、保存重开以及门动画/角色通行。视觉结果须由用户验收，功能通过不代表城墙美术已验收。


城门每扇三组实体铰链：套筒并为一个随门运动的构件，轴销与墙侧铁板并为一个固定构件；每座双扇门增加四个构件，而不是逐颗铆钉生成物件。套筒中心与门扇 fixture 的世界转轴重合，固定件不设置 fixture。通过原来的 `set_fortification_gate` / `Fixtures.set_runtime` 一起控制，无新增独立 MCP 接口。

本轮最终证据在 `D:/code/rmmo_runtime/review_artifacts/wall_art/`：`path_5m_test.log`、`round_5m_test.log`、`geometry_test.log`、`legacy_gate_test.log`、`hinges_test.log`。折线/圆形/椭圆 HTTP、非法净高拒绝、撤销重做、保存重开、运行时门碰撞和 3.5 米相机射线通过；铰链额外验证 0 / 0.35 / 1 开度同轴、墙侧固定、运行时四个活动成员一起控制、全宽 4.99 米射线通行。旧 plain 低门仅开关时保留原尺寸，公开生成请求仍不接受低于 5 米。

加入圆楼内部通路前的模块基线测量（headless，含其他后台测试负载，不代表当前完整城墙或整编辑器帧率）：40 米半径圆墙含 528 构件、238480 三角形，首次约 12.76 秒，同进程缓存复用约 101 毫秒，估算缓存总量约 23.5 MiB。仍需要后续静态构件合批，不能把这些数字当作整城性能验收。

## 圆楼内部通行结构（用户纠正后）

**城墙本身不设登墙梯。** 城内侧门进入圆楼，沿圆楼内部旋梯到可行走楼顶，再从圆楼通向相邻墙顶。撤销外置长直梯及贴墙折返梯的方案；这些旧验证图不能作为最终交付图。

现实依据先于建模：

- [Cadw：Castell Conwy](https://cadw.gov.wales/visit/places-to-visit/castell-conwy) 明确记录塔内旋梯与城垛巡道的通行关系。
- [Cadw 官方 Conwy 平面图及说明](https://cadw.gov.wales/sites/default/files/2019-05/Conwyteachersnotes_EN.pdf) 展示圆塔、城墙、入口关系与外墙射击孔；不同高度的射击孔为防御提供覆盖。
- [English Heritage：Goodrich 通行说明](https://www.english-heritage.org.uk/visit/places/goodrich-castle/plan-your-visit/access/) 记录实际狭窄、陡峭的旋梯。游戏借用结构关系，扩大通行空间，不照搬历史尺寸，也不把现代游客加建步道误当原始中世纪结构。

`wall_access=true` 生成中空圆楼、城内侧双扇门及内部旋梯；圆楼半径至少为墙厚的 1.6 倍，并随较大墙高增加，以容纳游戏人物。`arrow_slits=true` 在圆楼朝城外墙面开三道真实贯穿射击孔。普通墙顶垛口恢复矮石垛，不再用高耸带孔板代替整段城垛。

门口净宽 3 米、最低净高 5 米；`tower_door_open`（0～1，默认 1）控制这一组圆楼的内门初始开度，UI/MCP 共用。运行时可用 `Fixtures.set_runtime` 的 `tower_entrance_<序号>` 分别控制每个圆楼的门，铰链与碰撞同步。旧配方不自动升级。

旋梯沿内壁上升，净通行宽约 2.64 米、踏步高不超过 0.18 米；这些为角色/相机舒适度作的游戏调整，不是 Conwy 的实测尺寸。每座楼梯合成一个共享 PBR 网格并复用有界缓存。楼顶留实际楼梯洞口，配护栏，连接墙顶的开口仍保留实体踏面。

`preview_fortification.access_routes` 列出各圆楼的 `entry/room/deck`、`door_id`、`stairs_bottom/stairs_top/stair_width`、`stair_layout=internal_spiral` 及外向 `arrow_ports`。所有门、楼梯、楼顶和射击孔随配方同事务保存/撤销。新字段及整体替换不得只在 UI 生效，当前 3D MCP 使用同一生成逻辑。

验收工具为 `tools/test_fortification_access_plan.gd` 与 `tools/test_world3d_fortification_access.gd`，包含真实 HTTP、射击孔穿透、入口、导航、角色胶囊上楼/楼顶往返/下楼、保存重开；最终日志必须使用本节新结构，之前外置楼梯的通过记录不代表这一结构已经验证。

新结构的直线/闭合折线后台实测：`D:/code/rmmo_runtime/review_artifacts/wall_art/internal_tower_final_path_closed.log`，`ACCESS_FINISHED failures=0`。角色使用实际碰撞、导航和移动控制，沿入口、内部旋梯、楼顶、相邻墙顶完整往返；不是仅以导航路径存在作为通行依据。测试图位于 `D:/code/rmmo_runtime/cache/world3d/wall_access_10617116/`。名称含 `internal_cutaway` 的图仅为解释结构临时隐藏塔楼外壳/屋顶，保存前恢复可见性，不能误认为外置楼梯。

圆形/椭圆记录在同目录 `internal_tower_final_round.log`：真实 HTTP、非法/障碍拒绝、撤销重做、保存重开、射击孔及角色完整往返均通过。该日志保留两条旧测试误判：关门射线穿过双扇门中央约 4 厘米拼缝。已将持续测试改为两侧门板射线，并用 `tools/test_fortification_tower_doors.gd` 从同一份保存记录提取实际门和地面，复用运行时网格、碰撞和开合代码补测：`internal_tower_doors.log` 为 `TOWER_DOORS_FINISHED failures=0`；两种形状均关闭挡住 2.1 米胶囊，打开可通过。这是针对门碰撞的独立补测，未将原日志改写成全绿。对应完整场景截图在 `D:/code/rmmo_runtime/cache/world3d/wall_access_10364099/`。正式城镇地图未被这些临时测试覆盖。


## 自动布局禁区与圆楼地面（2026-10-04）

这些约束用于本项目的城镇自动布局，**不是历史建筑的统一标准，也不限制手动部署**。现实对照为 [Cadw 的 Conwy 城墙记录](https://cadwpublic-api.azurewebsites.net/reports/sam/FullReport?id=3413&lang=en)：约 1.3 公里城墙有 21 座普通塔及三座双塔城门。双塔门楼与沿墙普通塔不能使用同一个间距规则；当前尚无双塔门楼专用配方。

- `tower_layout=automatic` 为 UI / MCP 新建默认：任意两座普通塔的水平中心距至少 50 米；塔外包围与门洞半宽之间保留至少 10 米保守净距。也检查其他城墙组的现有塔与城门，避免拆组绕过规则。新自动布局会避让已有手动放置的城墙塔。
- 环形 `tower_count=0` 按 `tower_spacing` 目标间距（默认 60 米，范围 50～120）计算数量，沿椭圆近似等弧长布置；尝试旋转相位避开城门，必要时减少塔数，最低三座。明确指定塔数时不悄悄减少，违规则报错。40 米半径圆圈自动使用四座，不再固定塞八座。
- 折线仍在端点/拐点设塔，自动模式检查节点间距，不会擅自删除用户路径节点或增加中间塔；密集路径可调整节点，或切换手动模式。没有实现通用折线自动补塔。
- `tower_layout=manual` 不检查上述 50 米 / 10 米布局禁区，也不做跨组布局距离限制。环形 `tower_count=0` 在手动模式等同八座，可指定 1～24 座；手动模式仍保留实际几何不相交、承托地面、既有物件、保护状态等原有检查。普通物件移动/摆放没有新增这些美术间距禁令。
- `preview_fortification` 返回实际 `tower_count`、`layout_rules.applied` 和 `layout_zones`。圈表示禁止放置其他塔心的区域，不是禁止地面、植被或所有建筑的全局禁建区。UI 预览画出橙色禁放圈；失败返回冲突距离和调整方向。计算在事务前完成，拒绝不写文档/历史。
- 历史地图缺少 `tower_layout` 时按手动保留，缺少 `layout_version` 时仍为旧几何；仅开关旧城门不触发升级。重新生成时写入内部版本 1，`layout_version` 不接受公开 MCP 参数；手动模式不被强制改成自动模式。

新建或重新生成的可通行圆楼含完整石铺地面/实体地基：顶面比室外基准高 0.03 米以避免与地形共面，下延沿用 `foundation`（默认 1 米）；入口净高同步上移，保留石铺面上方至少 5 米。`floor_material_id` 单独选择地面材质，默认已导入的 `pack:default:paving/sandstone_floor/material`，包含法线；楼顶铺面共用该材质，墙身继续用墙体砌石。完整地面、基座、模式和材质跟随原配方同事务保存、撤销、依赖校验。

验证脚本：`tools/test_fortification_spacing.gd`（间距、手动豁免、门区、跨组、旧配方、地基几何）和 `tools/test_world3d_fortification_spacing.gd`（真实 HTTP、工具发现、非法原子拒绝、自动/手动对照、UI 模式恢复、撤销重做、保存重开、实际石铺材质及入口碰撞）。


本轮验收日志：`D:/code/rmmo_runtime/review_artifacts/wall_art/spacing_geometry.log`（`SPACING_FINISHED failures=0`）与 `spacing_floor_http.log`（`SPACING_HTTP_FINISHED failures=0`）。真实 HTTP 对照自动四塔/手动八塔、门区和跨组失败原子性、模式和地面材质恢复、撤销重做、保存重开全部通过；运行时石铺碰撞顶面为 0.03 米、入口上方 5 米净高仍畅通，2.1 米胶囊可双向跨门槛。截图在 `D:/code/rmmo_runtime/cache/world3d/wall_spacing_8419409/`，`stone_floor_cutaway.png` 为临时隐藏塔壳和屋顶的结构剖视。正式城镇地图没有改写。


## 不规则参考图描墙（2026-10-04）

- 复用「城镇布局 → 参考底图与比例标定」和 `set_map_reference` / `calibrate_map_reference`。`meters_per_pixel` 是等比尺度；`opacity`、`visible`、`locked` 可保存、撤销。原图 1000×1000 在本城镇按 1.4 米/像素、中心原点、旋转 0° 标定。编辑参考图不进入游戏场景。
- 折线新增可选 `tower_indices`，索引从 0 起。省略保留旧的逐拐点布塔；显式数组只在这些节点布塔，`[]` 不布塔。UI 文本框可输入 `0,3,7`，留空恢复旧规则，`none` 代表空数组。拒绝重复、越界和非整数。自动模式仍检查选中塔楼间距、城门间隔；手动模式仍不受美术布局禁区限制。此字段仅适用于折线。
- 路径上限扩为 128 点；显式选择塔点的路径最多 5000 米、8192 构件，旧配方仍限制 1000 米。城墙并不会被拟合成圆或椭圆。
- `terrain_foundation=true` 允许碰撞地形在基准面以下、地基下延以内支撑墙体；不允许地形顶面高于基准面 3.5 厘米，不填平洞口或绕过碰撞。门扇悬挂于经过承托校验的门侧墙体，不要求整个扫掠区有地面；扫掠区与实体/道路净空的既有规则仍执行。默认为 false。空间索引只减少候选比较，保留多边形承托、实体/道路/保留区、锁定与隔层校验。
- `gates.kind` 默认 `land`，双扇活动门最大 32 米；`water` 为无门扇的过水拱道，最大 64 米，仅用于折线。仅高度在水关净高以上的构件可使用该洞口作为跨越支撑区；两侧墙脚仍需真实地面，且不会自动关闭规划保留区。水关的闸门、铁栅和独立多跨水关模型尚未实现。
- 现实参考仍采用 [Cadw Conwy town walls](https://cadw.gov.wales/visit/places-to-visit/conwy-town-walls) 的围城与墙顶通行关系；水上城防参考 [Historic England Warkworth Bridge and defensive gateway](https://historicengland.org.uk/listing/the-list/list-entry/1020741) 的跨河拱桥与防御入口组合。这不是实测复原；本图过水洞口按游戏现有河宽、最低 5 米净高适配，不能宣称结构工程验算或直接复刻文物。

独立 HTTP 验证：`tools/test_world3d_wall_trace.gd`；检查选择塔点、缓坡承托、缺少承托的原子失败、UI、撤销重做和保存重开。城镇制作与验证入口：`tools/apply_medieval_town_walls.gd`；描图坐标保存在 `tools/medieval_town_wall_trace.json`。整城最终状态以运行目录 `review_artifacts/medieval_town_walls/published.json` 为准。

城防活动门的占地按关闭至完全开启的实际角度计算：每不超过 5° 采样箱体八角，取水平凸包，再按弦弓高加保守余量；不再使用围绕铰链的 360° 方形占地。门扇完整运动与现有物件、保留区仍检查，凸包也可能保守覆盖部分未扫过区域。`tools/test_wall_trace_geometry.gd` 对正反开启、旋转门各检查 1001 个实际姿态，验证所有角点均被占地和三维边界覆盖。

更新已有配方时，MCP 省略 `tower_indices` 会保留原选择；UI 清空已保存的塔点输入则显式提交全部路径节点以恢复逐点布塔。城镇尺度的裁切几何采用局部原点的双精度面积计算，包围尺寸从实际存储中心重新测量，避免远离原点的小垛口因浮点误差反转或超出归一化边界。几何回归覆盖整圈 62 节点、27 座塔的全部原生记录校验。

## 城防静态网格合并（2026-10-04）

合批是编辑器/游戏加载时自动生成的派生缓存，不改变地图中的构件数量，不要求将旧地图重新导出成一整圈模型。物件列表中的逻辑构件数不能作为是否合批的判断依据；以 `editor_state.fortification_batching` 的已合批源对象/渲染表面数和 `fortification_collision_batching` 的实际碰撞体数为准。选择要编辑的构件会暂时恢复独立网格，取消选择后重新合批。正式城镇可用 `tools/verify_town_wall_batch_activation.gd` 只读检查实际编辑器与运行时加载，结果写入运行目录 `review_artifacts/medieval_town_walls/formal_batch_activation.json`，不会重绘或保存正式地图。

2026-10-04 正式地图直接验收通过：4,876 条城防逻辑记录中，4,572 个静态源构件使用 533 个空间渲染组（305 个实例组），这部分材质表面数从 9,859 降为 911；原源网格均为 CPU-only，没有重复 GPU 绘制。4,732 个静态碰撞来源合为 317 个碰撞体，144 条活动门/附属件记录保持独立。真实 HTTP `editor_state` 确认启用、待构建组为零；运行时北侧、东南侧及西北侧三个驻留区域均通过渲染/碰撞合批检查。`formal_batch_activation.log` 为零失败，无脚本错误，正式文件哈希不变。本次补充的是正式地图验收，合批实现沿用此前交付。

城防与地形复用渲染缓存，但分开编组和统计。静态城墙、垛口、塔楼砌体及楼梯按空间块、兼容材质、几何、阴影和渲染层合批：相同几何优先使用 MultiMesh，共享已有 GPU 网格与 LOD；同块内剩余不同形状再合并。城防基础分块 32 米，长墙段按尺寸使用更大的有界块，绝不将整圈合成一个网格。单组最多 256 个构件、65536 个源顶点。活动门扇及随门五金、事件、受风或不兼容材质不参与合并。

合并后的城防网格在具备法线/切线时启用 Godot 的 [ARRAY_FLAG_COMPRESS_ATTRIBUTES](https://docs.godotengine.org/en/stable/classes/class_mesh.html#enum-mesh-arrayformat)，限制显存增长；CPU 编辑与碰撞几何不压缩。共享原模型的不同刷面材质保存在各自 CPU 包装中，防止选取恢复时串材质。实例网格缓存只持弱引用，释放空间块后不额外保留 GPU 网格，失效键在同步时清理。

合并保留 UUID、原始 CPU 网格、物理碰撞表面、射击孔、门洞、楼梯、材质刷面数据及撤销事务。选中构件暂时退出批次；局部编辑、隐藏、楼层隔离会拆除受影响旧批次并重建。运行时按原流式范围加载、离开时释放批次，静止时不持续重建。保存导出独立逻辑构件，重开/运行时重新生成派生缓存，不写入合并物件。后续同轮已加入静态碰撞分块，见下节。

`editor_state.fortification_batching` 返回城防合并的源对象数、源/结果渲染面数、顶点数和 `instanced_groups`；`ground_batching` 继续只统计地面。等待队列、重建次数和耗时属于共享缓存。真实 HTTP 验证：`tools/test_world3d_fortification_batching.gd`；地面回归：`tools/test_world3d_ground_batching.gd`。整城实测脚本为 `tools/benchmark_town_fortification_batching.gd`，对比两侧都开启地形合批，只改变城防合批状态，避免将既有地形收益重复计算。

`render_vertices` 对实例批次只计基础网格一次，不跨空间批次去重；它是批次级几何规模统计，不代表每帧 GPU 实际处理的顶点数。`render_surfaces` 也不是整场景真实 draw calls，后者由渲染器实测。

最初整城候选实测（RX 7900 XTX，1920×1080）：4,572 个静态源对象进入 533 个空间批次，其中 305 个实例批次；源渲染面 9,859 → 911。整场景绘制调用 4,763 → 2,121（减少 55.47%），几何缓冲 133.33 → 132.13 MiB，纹理约 636.30 → 634.73 MiB。GPU 中位数 1.164 → 1.171 ms，P95 1.342 → 1.310 ms，不能宣称 GPU 帧耗时显著改善。该阶段全图首次构建约 21.95 秒且尚未减少碰撞体；这两项已继续优化，最新结果见下节，不再沿用该阶段作为最终结论。

平均 RGB 图像误差：全景 0.0000550、近景 0.0018525，并人工检查近景轮廓和材质。最终日志 `review_artifacts/medieval_town_walls/batch_http.log`、`ground_batch_regression.log`、`batch_benchmark.log` 均零失败。完整城镇运行时验证覆盖 27 座石铺塔楼、11 处门/水关、62 段墙的中点承托；10 个零宽射线恰落在分段浮点接缝上，用实际 2.1 米高、0.3 米半径胶囊下扫验证均有正确支撑，没有通过扩大碰撞体或修改地图来掩盖问题。完整内部旋梯双向行走沿用独立通行回归。

原生运行时加载只验证同一份不可变文档一次；材质和贴图路径检查在该次验证内复用结果，后续加载重新检查，保留资源根和文件存在性校验。`test_material_validation_scope.gd` 覆盖非法变更、不同资源根、贴图删除后再次加载和单条越界材质拒绝。

本轮不合并房屋。房屋后续必须按楼层、屋顶/天花板及相机遮挡语义分批，不能整栋合并后破坏第三人称隐藏。

## 首次缓存与静态碰撞分块（2026-10-04）

程序化城防在网格上传时保留已有 CPU 数组；刷面构件同时保留原始/刷后数组，避免首次合批再次同步读取 GPU。CPU 包装只弱引用 GPU 源；源资源变化会失效，恢复选中网格时可复用仍存活且材质相同的资源。不同刷面实例各自保留材质，不改变逻辑记录或导出格式。

渲染准备使用短材质摘要；三个有界后台任务处理独立、不可变数组快照，主线程按 2 ms 调度预算提交。实际 GPU 上传不能在中途打断，单次提交可超过预算。城防数组用原生 `SurfaceTool.append_from` 批量转换坐标、法线/切线及索引；GPU 资源仍在主线程创建，取消或编辑后的旧任务通过代次检查丢弃。线程边界依据 [Godot 线程安全说明](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)，CPU 数组来源见 [ImporterMesh](https://docs.godotengine.org/en/stable/classes/class_importermesh.html)。

`fortification_collision_batcher.gd` 将静态构件原三角面按空间块、碰撞类型、脚步表面分组，基础块长 32 m，每组最多 128 个构件 / 16384 个三角面（单个超大构件不强行切开）。每组一个 StaticBody3D 和一个 ConcavePolygonShape3D，保留门洞、射击孔与每级台阶，不用包围盒填充。三角面编号范围映射回原 UUID，供选取、刷面、脚步表面和交互射线使用。活动门、事件、NPC/传送等目标独立；选中构件恢复独立碰撞体以保留拖动自排除逻辑。新组安装后再移除旧组，失败的业务操作不触碰缓存；不变组不重建，离开流式范围释放。

碰撞顶点先转世界空间、再转分块局部空间，避免远离原点的圆楼扇形中心因浮点舍入出现点状漏检。整城对照射线取面内样本，原独立网格本身也可能漏掉恰在共边/共顶点的零宽射线；额外精确扇形中心回归和角色胶囊验证覆盖这些边界。不会扩大整块碰撞或封住孔洞来消除测试差异。

测量脚本：`tools/benchmark_town_fortification_batching.gd`，同一城镇和同机基线 `batching/cache_baseline.json`，最新结果 `batching/performance.json`。`build_ms` 包含同步准备与后台完成；`build_frame_*` **仅为后台等待阶段帧时间**，同步准备另报 `sync_ms`，不能将其称作整个打开地图流程的最大卡顿。同步碰撞构建亦单列计时；减少碰撞体不代表射线或 GPU 帧耗时必然下降。

验收入口：真实 HTTP `test_world3d_fortification_batching.gd`（发现、非法无副作用、选取刷面、移动、隔层、撤销、保存重开及流式返回）、`test_world3d_ground_batching.gd`（地形回归）、`test_world3d_fortification_access.gd`（真实角色双向内梯/塔顶/门洞/射击孔）、`test_fortification_collision_precision.gd`（远原点扇形中心）、`test_medieval_town_walls.gd`（整城 27 塔、11 门/水关和墙顶承托）。日志后缀为 `*_final.log`。

最终实测（RX 7900 XTX，1920×1080；网格已生成后的首次全城派生缓存，不包含地图文件读取和原始网格生成）：

| 项目 | 同机基线 | 本轮结果 |
| --- | ---: | ---: |
| 首次渲染缓存总时间 | 19.64 s | 7.38 s（减少 62.4%） |
| 其中同步准备 | 5.34 s | 1.30 s |
| 后台等待阶段帧时间 P95 / 最大 | 42.13 / 127.80 ms | 35.93 / 39.36 ms |
| 静态城防碰撞体 / shape 数 | 4732 / 4732 | 317 / 317（减少 93.3%） |
| 两侧均启用本轮 CPU 缓存后的碰撞构建 | 3.81 s | 3.61 s |
| 278 次碰撞射线合计 | 6.64 ms | 7.06 ms |

碰撞三角面仍为 2,594,940 个；本轮主要降低物理节点与 broad-phase 对象数量，并不声称三角面或射线耗时同步减少。碰撞构建仍同步，渲染同步准备和不可中断上传亦有一次性开销，不称作完全无卡顿。实际绘制调用仍为 4763 → 2121，GPU 几何缓冲 133.33 → 132.13 MiB，GPU 中位数 1.188 → 1.191 ms。最终平均 RGB 误差全景 0.00000656、近景 0.00022220。

最终上述五项回归与 `cache_verified_final.log` 全部零失败；整城 27 塔、11 门/水关和全部墙段角色胶囊承托通过，278 个面内射线无表面差异/缺失身份。整圈仍有 12 个恰落浮点共边的零宽射线接缝，实际胶囊承托缺失为 0，按明确测试口径记录，不把零宽射线当作角色通行结论。正式城镇文件 SHA-256 保持 `321ea3c6de68357d5b41ab45e54f4b20d2924a1c265f37bbb8e6bd314fa60ba8`，派生缓存优化不重写地图。

## 拖动刷新与碰撞重复驻留（2026-10-04）

进一步定位到两处交互热点：鼠标每次移动都会重新扫描全城渲染/碰撞分组；已刷材质的城防即使只改位置，也会重新生成网格。现在选择改变时仍正常退出批次，拖动期间只更新已独立的选中节点及碰撞体；地形、尺寸或其他实际几何重建仍请求完整同步，取消、结束、隐藏和隔层沿用原事务。城防纯位移/旋转保留网格、材质和面绑定；渲染释放改用成员到分组的反向索引，避免每个选中构件再次遍历全城批次。房屋楼层合并不在本次范围。

运行时返回最近的城防分块时，复用按原点、成员 UUID、几何摘要及变换精确匹配的 ConcavePolygonShape3D。缓存采用 LRU，最多 64 组及 262144 个三角面；未命中照常构建，超预算单组不保留，换图/文档重建清空。保留的是有界 CPU 物理资源，离开区域仍移除全部活动碰撞体，不留下远处碰撞或额外 GPU 网格。

诊断：渲染统计新增 `sync_count/release_groups_visited`；碰撞统计新增 `shape_cache_groups/shape_cache_triangles/shape_cache_hits/shape_cache_misses`。UI 与当前 3D MCP 复用实现，不添加写入工具，不改变存档。对照脚本为 `benchmark_editor_transform_hotspot.gd`（整城内存副本、12 次选中刷面构件拖动刷新）和 `benchmark_collision_residency.gd`（相同局部城防形状的冷建/回访各 5 次、LRU 淘汰和清空）；结果保存在 `review_artifacts/medieval_town_walls/transform_before.json`、`transform_after.json`、`collision_residency.json`。拖动指标仅指刷新调用，不冒充完整输入帧或游戏 FPS。

实测：5,876 条记录的整城中，单个已刷面城防构件的拖动刷新中位数 **1138.862 → 35.550 ms**，最大值 **1227.694 → 41.282 ms**；原先每步都重建该网格，现在复用同一网格，未重建无关渲染批次。这组旧指标仅覆盖 `_sync_selected_transform`，遗漏的属性面板刷新链见下一节。局部 103 个构件 / 7 个碰撞组 / 43,640 个三角面的重复驻留，中位数 **55.502 → 1.708 ms**；后者为最近缓存命中，首次进入或已淘汰区域仍需冷建，不能外推成整城首次加载耗时。

`hotspot_http.log`、`hotspot_ground.log`、`hotspot_precision.log` 及 `collision_residency.log` 全部零失败。覆盖真实 HTTP 发现/查询/变换、失败原子性、拖动不扫描全城与网格复用、移动碰撞及撤销、刷面、隔层、保存重开、流式离开和返回、地形回归、精确扇形接缝，以及缓存 LRU 淘汰/清空。两个整城拖动基准也均零失败，正式城镇 SHA-256 未改变。

## 变换后属性面板的重复刷新（2026-10-04）

继续沿真实拖拽调用链检查，发现 `transform_drag.update` 在变换刷新后调用 `inspector.refresh`，后者又刷新选框并同步全场景渲染/碰撞批次。上一节仅测变换函数，没有覆盖这次重复检查，不能据此认定真实拖动已经没有全城扫描。

现在变换后只更新面板数值，选框与碰撞由变换操作负责更新；取消拖动也使用同一路径。数值编辑和 MCP 的 `set_object_transform` / `transform_selection` 同步消除重复刷新；选择其他对象、实际网格变化、隔层及文档重建仍执行必要同步。选择记录只在本次调用内复用，空选择立即返回、找到全部 UUID 后停止查找，不保留可能在撤销/重生成后失效的记录引用。

相同整城、单个刷面城防构件、12 次位移的对照（私有桌面 Vulkan，RX 7900 XTX）：

| 测量项 | 修改前 | 修改后 |
| --- | ---: | ---: |
| 变换刷新中位数 | 34.271 ms | 11.213 ms |
| 后续面板刷新中位数 | 1115.235 ms | 1.704 ms |
| 两次调用合计中位数 | 1142.792 ms | 12.943 ms |
| 两次调用合计最大值 | 1296.388 ms | 30.219 ms |
| 12 次拖动中的全场景批次同步次数 | 12 | 0 |

结果：`review_artifacts/medieval_town_walls/interaction_before.json`、`interaction_after.json`。两组均复用原刷面网格、没有重建渲染批次。测量包含变换与面板刷新，仍不包含整个输入分发、布局和 GPU 帧时间，不能据此承诺固定 FPS。历史数字分别测中位数，分项中位数不必等于合计中位数。

验收：`interaction_http.log`、`interaction_input.log`、`interaction_ground.log`、`interaction_mcp.log` 全部通过，无脚本错误。涵盖真实鼠标 XYZ 移动/旋转/缩放、取消与单事务撤销、选中件碰撞跟随、真实 HTTP 单件/多选变换、非法调用无副作用、隐藏/锁定/隔层、刷面、地形及保存重开。属性栏按既有 0.001 米步长显示，验证允许半个显示步长的舍入误差；逻辑记录不为显示精度额外量化。已选城防件 MCP 数值修改实测仅一次全场景同步。正式城镇文件 SHA-256 仍为 `321ea3c6de68357d5b41ab45e54f4b20d2924a1c265f37bbb8e6bd314fa60ba8`。
# 固定预制件（2026-10-04）

新生成的城防在通过原有布局、实体碰撞、地基承托和保护校验后，立即把实际网格和原始三角面碰撞写入原生地图。保存的 settings 只保留来源信息，不在进图时生成构件。静态构件按 32 米空间桶合并（这是烘焙网格范围，不改变世界流式加载单元），塔心语义及每个门扇转轴独立保留；双扇门按角度区分，不能把反向开合的两扇合成一件。

已有地图可用面板“烘焙现有城防为固定预制件”或 3D HTTP MCP `bake_fortification {id}` 转换。两者使用同一事务和校验，支持撤销、重做、保存重开。`list_fortifications` 返回 baked、source_part_count 和合并后的 count。固定城防不能重新生成、缩放、拆件、复制路径身份或解除关联；目前也不支持整体迁移路径，须新建独立布局。整体删除与城门开合仍可用，`set_fortification_gate` 仅改变活动门姿态并同步清单签名，不重新生成城墙。

自动塔楼间距规则继续只约束自动布局；烘焙没有新增手动放置布局禁区。结构、楼内楼梯、地基石铺地面及射击孔沿用已经验收的模型。烘焙是性能/持久化改动，不构成新增建筑美术验收。

