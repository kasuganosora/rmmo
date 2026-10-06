# 程序化中世纪石桥

2026-10-03。入口：**城镇布局 → 写实石桥 · 预制件生成**。选桥型、点两个桥头、调宽度和拱高、预览实际网格、应用。内置多孔浅拱、尖拱、乡间石桥，支持保存用户桥型。一座桥是一条记录，整体选取、移动、复制、撤销和保存。

Blender 制作原创拼装模块，编辑器按现场参数生成整桥。默认资源包不存固定跨度的样桥。造型参考 [Stone Bridges Optimized](https://www.fab.com/listings/802b970a-ea78-4b26-bfcc-ed74f2347b0e)，没有使用该商品的网格、贴图或蓝图。砌石拱桥结构参考 [Warkworth Bridge](https://historicengland.org.uk/listing/the-list/list-entry/1020741) 和 [Cattal Bridge](https://historicengland.org.uk/listing/the-list/list-entry/1021018)。

## 参数

| 参数 | 范围和含义 |
| --- | --- |
| `start/end` | 桥头 XYZ，米；须同高，误差不超过 1 厘米；水平距离 6～120 米 |
| `prefab_id` | `stone_segmental`、`stone_pointed`、`stone_rustic` 或用户保存的桥型 ID |
| `width` | 总宽 3～16 米，保守通行净宽为总宽减 1.16 米 |
| `depth` | 基础距桥头平面向下 1.5～15 米；桥面拱起时基础不抬升 |
| `camber` | 中心桥面拱高 0～5 米；0 为平直，同时限制最大坡度 15% |
| `arches` | 0 自动计算，或指定 1～20 孔；净跨至少 2 米，最大净跨由桥型决定 |
| `deck/masonry/trim_material_id` | 分别覆盖铺装、承重砌石、拱券及压顶；省略时跟随桥型或已有材质 |

曲线为 `camber * sin(pi * t)^2`，两端高度及坡度归零；桥栏与桥身随曲线变形。端部必须有同高地面或道路承托；拒绝地形穿透桥面、物件碰撞及过期预览。隐藏物件也参加碰撞。更新保持 UUID 和组合元数据；隐藏、锁定、隔层及组内保护生效，手刷材质/事件阻止重生成覆盖。

当前为直线桥轴及纵向拱高，不支持弯桥、斜交桥、不等高桥头或结构受力计算，不自动挖河、削山、回填；深度需按河床选择。保存桥型是不可变库写入，不随地图撤销删除。外部模型须遵守六模块及材质槽约定，目前没有任意整桥 GLB 自动拆解导入。

## 模型、PBR、性能

`tools/build_medieval_stone_bridges.py` 用 Blender 4.5 构建 `arch/pier/abutment/deck/parapet/post` 六模块，保留石块倒角、拱券分缝、分水墩和压顶。Godot 装配为 **一个网格、三个材质面**。铺装和砌石按米连续贴图，装饰生成距离 LOD，简单桥面保持精确几何。相同参数复用缓存，最多六份装配网格。运行时用真实网格碰撞，拱孔不被包围盒填满。

默认复用已有 2K PBR：桥面 `paving/outdoor_flagstone`，桥身 `walls/castle_rubble`，拱券/压顶 `walls/stone_tiles_facade`，包含法线、粗糙度及 AO。GLB 模块不嵌入重复贴图，桥记录的材质依赖参加检查和资源打包。

模块在外部运行目录 `packs/default/assets/bridges/medieval_stone`，可编辑 `.blend` 在 `packs/default/sources/authored/bridges`。生成命令：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe' --background --factory-startup --python tools/build_medieval_stone_bridges.py -- --output D:/code/rmmo_runtime/packs/default/assets/bridges/medieval_stone
```

14/30/58 米样桥 LOD0 分别为 25,768 / 50,812 / 86,372 个三角面；58 米初版为 201,500，减少约 57%。这是样桥几何量，不代表整城帧率或显存改善比例。首轮构网与 LOD 约 0.7～1.5 秒，命中缓存后复用。超大桥逐面刷材质仍受通用工具单槽 50,000 面限制，可用三个材质 ID 整体调整。

## 当前 3D MCP

共 118 项工具，旧二维继续下线。UI 与 MCP 共用 `bridge_tools.gd` 的校验、预览、事务和保存。

| 工具 | 作用 |
| --- | --- |
| `list_bridge_prefabs` | 只读列出内置及保存的桥型 |
| `preview_bridge` | 只读返回 `plan_token`、拱孔数、净宽、最大坡度等 |
| `generate_bridge` | 同 ID 更新，相同请求无重复，整桥一次撤销 |
| `save_bridge_prefab` | `id/name` 保存桥型、模块路径及材质，不含现场位置与跨度 |

```json
{"name":"preview_bridge","arguments":{"id":"market_stone_bridge","prefab_id":"stone_segmental","start":[-25,0,0],"end":[25,0,0],"width":8,"depth":5,"camber":1.2,"arches":0}}
{"name":"generate_bridge","arguments":{"id":"market_stone_bridge","prefab_id":"stone_segmental","start":[-25,0,0],"end":[25,0,0],"width":8,"depth":5,"camber":1.2,"arches":0,"plan_token":"预览返回的令牌"}}
```

`preview_waterway/generate_waterway.bridges[]` 同步增加 `prefab_id/camber`，河道 UI 可选三种石桥。旧图缺省桥型按 `legacy_flat` 读取，不能指定非零拱高。新桥沿用 `connect_waterway_bridge` 接路，净宽扣除石栏，路面不重复覆盖桥面。归属河道配方的桥须从河道修改，独立桥工具拒绝直接覆盖。

### 既有道路转换（2026-10-03）

在石桥面板的道路下拉框选取一条已有直线桥梁道路，点击 **读取道路桥梁 / 转换旧桥面**，选桥型并预览/应用。已经接入的桥也从同一入口读取修改。`preview_bridge/generate_bridge` 增加可选 `road_edge_id`，仍为 118 个工具。

桥头坐标落在原道路中心线，Y 为道路标高加 0.025 米，两端各保留至少 2 米引道。桥宽至少为原道路宽加 1.16 米，不压缩原有通行净宽。当前只转换水平直线桥梁道路；河道配方桥继续用河道入口。

应用同一次事务写入石桥、裁掉桥下同高度的旧道路补片、保留剩余道路的逐面 UV 材质，并将原道路边关联到桥梁。道路节点、弯道、宽度及拓扑不变。以后重新铺路会避开石桥，不补回悬空路板。仅刷新桥体和受影响路面，不重建全城地形节点。隐藏、锁定、隔层、组合保护、事件、旧预览令牌均受检查；不支持的侧面刷材质/投影方式会明确拒绝，避免丢失美术调整。

接路后可修改桥型、材质、拱高和桥墩深度；当前禁止直接更改绑定跨度及宽度，需先撤销转换再调整。手工移动、删除或改形会使绑定诊断失败，重新铺路不会覆盖这类修改。保存重开保留道路边的 `stone_bridge`（对象 ID、桥头、总宽、签名和道路来源令牌）。

```json
{"name":"preview_bridge","arguments":{"id":"stone_old_crossing","road_edge_id":"old_crossing","start":[-20,0.025,0],"end":[20,0.025,0],"width":7.2,"depth":5,"camber":0.6}}
```

`tools/test_world3d_road_stone_bridges.gd` 经真实 HTTP 验证旧桥面转换、逐面材质、保护和无副作用失败、撤销重做、接路后再铺路不重复生成桥板、UI 读取和修改、保存重开、增量刷新及 2.1 米胶囊通行。正式城镇迁移通过 `tools/apply_medieval_town_stone_bridges.gd` 在验证地图生成，再由 `test_medieval_town_stone_bridges.gd` 检查五桥运行时通行，通过后以 `--publish` 原生原子保存。

## 验证与待办

### 主通航孔硬性净空（2026-10-03）

用户确认：主通航孔在至少 **2 米宽的连续范围**内，实际水面到拱券下缘不得低于 **2.5 米**；靠岸小拱孔作为泄水孔可较低。测量基于水面记录的几何标高，非桥面、栏杆或拱頂单点；当前不模拟船舶吃水、流速、潮汐或水面着色器波峰。

独立石桥及已有道路转换共用 `bridge_clearance.gd`。`auto_clearance` 默认开启，自动提高最终拱高并留 0.05 米余量；关闭时只检查，不能绕过 2.5 米下限。超过 15% 坡度或缺少水上的连续主孔时拒绝生成，不修改文档。实际水位来自现场水面，API 不允许用调用者填写的较低水位绕过检查。无水面的旱桥不强制抬拱。

先读取 Blender 实际模块组合的平桥下缘，求出所需抬拱量，再将变形后的全部三角面裁切到 2 米宽通航带，取整条通道的最低下缘。这一步包括拱券压边和桥宽外的构件，避免离散射线漏掉石块突起。几何轮廓和测量缓存各最多 8 份；当前水位每次重新读取，不缓存通航合格状态。预览 `navigation` 返回 `applicable/arch_index/center_x/width/clearance/water_level/required_height/adjusted`；`camber` 为实际应用值。

河道面板的石桥也必须满足该硬下限，但该入口保持明确填写的拱高，不自动改河道配方；可调整拱高、引道长度或水面落差后再次预览。旧地图可以打开，生成/修改石桥时检查；手工移动水面或桥体后需重新预览复核，不宣称通用自由变换会自动重建桥梁。

`test_world3d_road_stone_bridges.gd` 经真实 HTTP 验证自动抬拱、关闭自动后低桥拒绝、水位提高导致坡度超限时无副作用失败，以及撤销重做/保存重开。`test_medieval_town_stone_bridges.gd -- --clearance` 额外用 2 × 2.5 × 1 米盒体对完整运行时碰撞场景进行穿桥扫描，验证连续净空。水渠入口由 `test_world3d_stone_road_connections.gd` 覆盖合法及净空不足请求。

高效模块射线查询使用 Godot [TriangleMesh BVH](https://docs.godotengine.org/en/stable/classes/class_trianglemesh.html)，最终通航带最低值用连续三角面裁切复核。原始 Blender 模块未改写，调整保留在可编辑桥梁配方中。

`tools/test_world3d_bridges.gd` 使用临时地图及真实 HTTP，验证发现、三种桥型、无副作用失败、保护、碰撞、用户桥型复用、UI 预览/应用、撤销重做、保存重开、实际 PBR 和 LOD，并验证最浅/最深、最宽/最窄几何边界。运行时使用 2.1 米胶囊双向过桥，检查栏杆阻挡、拱孔净空。

`tools/test_world3d_stone_road_connections.gd` 用拱高 0.6 米石桥复用道路联动回归，检查河道生成、接路/解绑、无重复铺面、保护、保存重开与角色往返。旧式桥由 `test_world3d_road_connections.gd` 保留覆盖。所有 GPU 测试使用非激活独立桌面。

本轮提供可审阅美术版本，功能通过不代表用户已验收外观。木桥、桥头翼墙继续列待办。
# 固定桥梁网格（2026-10-04）

预览仍可调整跨度、拱孔、拱高、桥墩深度及材质。应用之后自动保存完整网格与精确三角面碰撞，成为固定预制件；进图直接读取数据，不再调用程序桥梁生成器。桥梁参数保留为只读来源及通行测量依据。桥面、桥墩、拱孔和护栏仍为一体网格；固定实例不可再修改参数、缩放或刷面。

已有桥梁使用面板“烘焙此桥为固定预制件”或真实 3D HTTP MCP `bake_bridge {id}` 迁移，同一事务同步道路/河道成员签名。锁定、隐藏、隔层、受保护桥头和失配的道路绑定拒绝操作，失败无副作用；支持撤销、重做、保存重开。新河道中的石桥也在应用时烘焙；含固定桥梁的河道不允许重生成破坏桥梁结构。

## 2026-10-06 桥侧浅色横带与细白边修复

桥板模块原先把侧面、底面和栏墙外露的上沿全部归入浅色铺装，形成宽横带；只修侧面仍会留下约 5 厘米宽的浅色外沿。共享生成器现在把侧面和底面归入砌石，并沿栏墙底部裁分顶面的材质区域，将外沿也归入砌石。材质边界藏在栏墙下，桥面通行区继续保留铺装。

`bridge_deck_rim.gd` 只拆分共面的纹理边界，不移动桥体；保持一个桥梁网格、三个共享材质表面及自动 LOD。`bridge_surface_repair.gd` 迁移已有固定桥的渲染数据，原始碰撞数据逐字节保留。`tools/repair_bridge_surfaces.gd` 对正式图五桥检查碰撞、渲染包围盒和总表面积、三个材质表面以及重复修复无变化，用相同镜头和灯光保存近景与整体对比。

真实 HTTP 回归 `tools/test_bridge_surface_mcp.gd` 已通过工具发现、预览/生成、铺装边界、撤销重做与保存重开，失败数 0；UI 和 MCP 使用同一个修正后的生成器，后续生成桥梁自动处理外缘。证据：`D:/code/rmmo_runtime/review_artifacts/bridge_rim_mcp.log`；近景和发布凭据：`D:/code/rmmo_runtime/review_artifacts/bridge_surfaces_rim_20261006/`。发布通过逐桥源记录校验、原生原子保存及重开比较完成，不替换其他物件记录。

最终正式图 SHA-256：`27a0fead90002ea87bfa961b25d6a962ffbd74018d8c313d53136b19423a524a`。`test_bridge_terrain_runtime.gd -- --formal` 完整游戏加载后，六次通行、桥头导航、两岸合批和 36 处岩岸碰撞查询全部通过，失败数 0，日志无错误或警告。最终游戏截图及报告位于 `D:/code/rmmo_runtime/review_artifacts/bridge_terrain_finish_20261006/formal/`，其中 `runtime_bridge_close.png` 是正式图桥侧近景。

`save_bridge_prefab` 仍保存“可在预览阶段调整跨度的桥型配方”，不是烘焙实例导出接口；实际已放置桥梁的固定网格保存在地图内。默认模块库及材质继续作为资源包依赖保留。桥体烘焙不填平拱孔、不用包围盒替代碰撞，不改变之前的桥头和 2 米宽 / 2.5 米高船只净空要求。

