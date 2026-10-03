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

独立石桥目前不自动绑定既有道路边；河道拥有的石桥支持上述路网绑定。正式城镇五条旧桥道路尚未自动替换，迁移须同时处理旧铺面与道路归属，避免叠放拱桥后留下悬空路板。

## 验证与待办

`tools/test_world3d_bridges.gd` 使用临时地图及真实 HTTP，验证发现、三种桥型、无副作用失败、保护、碰撞、用户桥型复用、UI 预览/应用、撤销重做、保存重开、实际 PBR 和 LOD，并验证最浅/最深、最宽/最窄几何边界。运行时使用 2.1 米胶囊双向过桥，检查栏杆阻挡、拱孔净空。

`tools/test_world3d_stone_road_connections.gd` 用拱高 0.6 米石桥复用道路联动回归，检查河道生成、接路/解绑、无重复铺面、保护、保存重开与角色往返。旧式桥由 `test_world3d_road_connections.gd` 保留覆盖。所有 GPU 测试使用非激活独立桌面。

本轮提供可审阅美术版本，功能通过不代表用户已验收外观。木桥、桥头翼墙、正式城镇五桥迁移继续列待办。
