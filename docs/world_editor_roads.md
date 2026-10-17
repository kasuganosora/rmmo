# 道路铺面与保留区域（2026-10-02）

入口：**城镇布局 → 生成道路铺面与路口 / 禁建区与保留通道**。与参考底图、公里级视图、道路节点编辑配合使用，详见 [城镇布局](world_editor_city_layout.md)。道路批次交付时 3D MCP 共 84 项，新增五项；后续街区批次增至 88 项，植被批次增至 92 项。旧二维工具仍保持下线。

## 操作流程

1. 点选道路骨架，调整端点、宽度或曲线控制柄。
2. 点“拆分同层交叉点”。T、十字、Y 等路口共用节点；拆分保留曲线控制柄和宽度变化。不同高度的桥下穿越不会连接。
3. 选择铺路材质、厚度、地面偏移和净空，点“预览铺面变化”，再“应用铺面方案”。默认 UI 选用资源包里的历史鹅卵石街道（资源存在时）；MCP 首次未指定材质则使用原色，后续省略参数沿用上次设置。
4. 骨架修改后，旧实体道路保持原状，面板提示需要更新铺面。重新预览并应用。预览过期会拒绝应用，避免把较新的地图状态覆盖掉。
5. 禁建区 / 保留通道通过点选多边形绘制，Enter 闭合提交、Backspace 撤回一点、Esc 取消；支持属性修改、重绘、隐藏、锁定、删除。隐藏只影响辅助线，规则继续生效。

生成在编辑器内即时完成，不往默认资源包写入固定道路模型。默认包仅提供材质依赖。保存地图时导出真实网格、纹理引用和运行时碰撞数据。

## 几何与碰撞

- 支持水平直路、三次曲线、变宽道路、同层路口、圆角连接和圆端帽；现已增加带水平接头的直线坡道。独立水平桥面可以跨过地面道路，按真实铺面重叠范围检查桥下净空；河道桥梁可显式绑定，复用已有桥面，不重复铺设。详见 [道路桥梁联动](world_editor_road_connections.md)。
- 路面以世界坐标 **32 米分块**为起点；贴地后超过补片预算的块会自动细分，见下方 2026-10-14 更新。分块内保存互不重叠的凸多边形补片。环路中央、弯路外侧和分块空角保留空地；不会以整个分块包围盒代替道路碰撞。网格包含正面、背面、边缘，法线和切线有效；顶面使用连续世界米制 UV，支持资源包 PBR 法线、粗糙度与 AO。
- 曲线采样段在缓弯处共用偏移横截面，使两侧边缘连续，避免每个采样点叠加整圆后裁出大量碎片。锐角或相对路宽过短的段仍使用有界圆角；不会生成过长尖角。相连路口按交汇横截面收口，圆端帽只用于断头路，防止宽支路伸出窄主路。UI 与 MCP 仍共用 `road_plan.gd`，参数与撤销事务不变。
- 建筑预览、直接生成、区域随机生成、沿街生成、更新及整栋移动/旋转/复制共用占地检查。道路实际范围和上方净空都是障碍；普通地面支撑的豁免不适用于生成道路，包括解除关联后的道路。
- 生成道路前检查全部现有物件，包括隐藏、锁定物件；真正位于脚平面下的普通地面可作为支撑。障碍物落入路面或净空会整笔拒绝，不删除既有房屋、物件。
- 净空默认 3 米，可设 2.5～10 米；桥面高差须至少为净空加铺面厚度。厚度 0.1～0.5 米，默认 0.2；顶面高于道路节点 0.005～0.05 米，默认 0.025，以避免与平地重叠闪烁。

**边界：**不启用贴地时，直线高差道路仍按扣除水平接头后的 15% 坡度限制；独立曲线坡道、倾斜路口不在这条旧路径中支持。已实现的 `follow_terrain` 根据真实地形拟合道路，见下方 2026-10-14 更新。[河道工具](world_editor_waterways.md) 支持显式桥面绑定；现有参数化石桥及其结构边界见 [石桥工具](world_editor_stone_bridges.md)。自交、重叠中心线、不同类型的同层穿越及无法稳定求解的近切线交汇需先整理骨架。交叉候选来自 16～128 段曲线采样，再用曲线参数求精确交点，误差超限拒绝；不声称覆盖任意曲线的全部数学交点。

上限：256 节点、512 边、8192 源轮廓、4096 路面块、每块 512 凸补片、100 万次裁切。单个刷面记录上限仍为 128；贴地道路的默认铺路材质会自动细分超预算块，见下方更新。达到最小块尺寸或总量上限仍整笔拒绝，不静默少生成。稳定身份和差异统计不等于整城增量渲染性能已经完成。

## 身份与编辑保护

`map_meta.editor_layout.road_surface` 保存设置、图内容哈希以及每个分块的稳定 key/UUID、几何签名与自动材质签名；实体保存在 `records` 的 `road_mesh/road_source/road_clearance` 中。数值签名使用微单位归一化，避免 JSON 浮点舍入被当成手改。

同一分块、同一高度沿用 UUID。远处新增道路不改变未受影响分块的身份和几何。某个分块内部形状变化后，属于整个分块的变更：该块若有手刷材质、手动清材质或事件，且几何签名改变，则明确拒绝，不猜测覆盖应映射到哪里。未变形的分块保留覆盖和事件。

锁定/隐藏/楼层隔离保护、构件手改或删除、ID 冲突、缺失材质依赖等均无副作用失败。“解除关联，保留实体路面”会解除生成配方，保留现有物件和材质；其后可手工整理。普通复制和快照预制件保留网格，但清除生成归属，避免冒充原配方成员。解除关联本身支持撤销。

## 区域规则

`editor_layout.zones`：最多 128 个区域，每区 3～64 个 XZ 顶点，简单多边形、无自交/重复点，面积至少 1 平方米；`min_y/max_y` 指定世界高度范围，最小高度差 0.1 米。

- `no_build`：阻止建筑生成与整栋移动进入该范围。
- `reserved_passage`：同样阻止建筑，并向未来植被散布提供排除区；它不自动生成道路。
- `no_vegetation`：可绘制、保存、编辑，并提供统一的植被障碍查询。已用于[区域植被散布](world_editor_vegetation.md)，会阻止自动散布；不会清除已有或阻止手动放置树木。

凹多边形使用三角剖分保留真实空角。隐藏、锁定不会关闭约束。已有物体不会因后来画了区域被删除；普通物件的手动摆放暂不受该建筑规划规则限制。

## MCP

| 工具 | 参数 / 结果 |
| --- | --- |
| `split_road_intersections` | 无参数；返回新增节点/边数；幂等、一次撤销 |
| `preview_road_surface` | 可选 `material_id/thickness/lift/clearance`；返回 `chunks/area/diff/plan_token`；只读 |
| `generate_road_surface` | 同上，可加预览的 `plan_token`；提交前重复校验，一次撤销；相同方案不增加历史 |
| `detach_road_surface` | 无参数，解除配方并保留几何 |
| `update_planning_zones` | 必需 `expected_token`，取自 `get_city_layout.zone_token`；`zones` 完整项增改，`remove` ID 列表 |

`get_city_layout` 同时返回 `runtime_geometry`（有已生成路面）和 `surface_stale`（骨架已变化）。`preview_map(include_layout:true)` 包含区域和骨架；普通预览只显示实际场景。UI/MCP 使用同一共享操作、参数校验、保护、撤销、草稿、保存与读取校验。

```json
{"name":"split_road_intersections","arguments":{}}
{"name":"preview_road_surface","arguments":{"material_id":"pack:default:paving/historic_cobble/material","clearance":3}}
{"name":"generate_road_surface","arguments":{"material_id":"pack:default:paving/historic_cobble/material","clearance":3,"plan_token":"使用上一调用返回的值"}}
{"name":"update_planning_zones","arguments":{"expected_token":"使用 get_city_layout.zone_token","zones":[{"id":"market","name":"集市预留","polygon":[[10,10],[30,10],[30,30],[10,30]],"min_y":-2,"max_y":100,"purpose":"no_build"}]}}
```

## 验证

- `tools/test_road_plan.gd`：十字/T/Y/锐角/曲线/环路，凸补片不重叠、朝上法线、真实留空、曲线拆分一致性、净空、合法斜坡/超坡拒绝、凹区域和自交校验。
- `tools/test_world3d_roads.gd`：真实 HTTP 发现与合法/非法调用、预览令牌、保护、无副作用失败、撤销重做、真实画布输入和 Enter 提交、默认 PBR、手动覆盖、稳定分块、草稿、保存重开、GPU 截图、运行时网格碰撞和 2.1 米胶囊穿越路口/接缝。
- `tools/test_world3d_road_protection.gd`：环路空地内的物件/房屋、整栋移动与禁建区、区域随机建筑避让、实物占路、事件/手改保护、普通复制/预制件、解除关联与保存重开。

GPU 测试在 `tools/run_godot_background.py` 的独立桌面运行，不激活用户窗口；使用临时地图及临时资源包。[街区闭合提取、临街地块与空位房屋](world_editor_blocks.md) 已在下一轮补齐；道路变化后自动替换建筑仍待实施，完整参考城镇尚未搭建。

本轮验收通过：`D:/code/rmmo_runtime/review_artifacts/roads_acceptance_live.log`（`WORLD3D_ROADS_FINISHED failures=0`）、`road_protection_live.log`（`ROAD_PROTECTION_FINISHED failures=0`），均无脚本错误。既有 city_layout、mcp、transform、groups_ui、editor 五组后台回归全部通过，日志前缀 `roads_regression_`。主测试地图及实际 PBR 近景在 `D:/code/rmmo_runtime/cache/world3d/roads_8562783/`，包括 `map.gltf`、`roads.png`、`road_material.png`；未覆盖用户地图。

## 2026-10-14：细地形自动分块与贴地桥口

UI 与当前 3D `preview_road_surface` / `generate_road_surface` 继续共用 [road_tools.prepare](../scripts/world_editor/road_tools.gd)，本次没有新增工具或参数。沿用已有 `follow_terrain`、路缘、材质、厚度及偏移设置，不启用历史二维入口。

- [road_plan.gd](../scripts/world3d/road_plan.gd) 在贴地模式下先合并统一的 XZ 道路轮廓，不再把普通地面道路当作需要两端平接头的独立坡道。最终每片高度与 15% 坡度限制仍由 [terrain_projection.gd](../scripts/world3d/terrain_projection.gd) 检查实际地形，未降低地形精度，也未放宽洞口、缺地、重叠承托及坡度校验。
- 原生石桥的桥面切口先按真实桥绑定 XYZ 裁切；随后才将道路轮廓置于临时平面。路缘开口使用同一平面的 portal 副本，避免拿高处桥端 Y 与临时平面比较而横封桥口。原桥端标高、绑定及道路图保持不变。两端侧缘保留端帽；石桥和河道桥均覆盖此路径。
- [road_terrain_fit.gd](../scripts/world3d/road_terrain_fit.gd) 在原生投影明确返回 512 片超限，或指定默认铺路材质后的刷面预算不足时，自动四叉细分派生道路块，最小块边长 0.25 米，总块数仍不超过 4096。其他错误直接原子失败。未超限块保持原 ID；相同内容的子块由父 key 和象限序列确定身份。子块保留世界铺面 UV、路缘米制 U、真实外端帽及原生 `terrain_follow` 作者轮廓，不在内部切分处新增端帽。
- 已经精确验证为道路承托的地形，提前跳过重复的逐片障碍裁切；远处障碍只通过保守 XZ 包围框粗筛，其余物件仍执行真实重叠检查。选择、碰撞、手刷和事件保护、共享渲染批次、撤销及原生保存语义保持不变。

地形雕刻后，[terrain_follow_tools.gd](../scripts/world_editor/terrain_follow_tools.gd) 仍按已生成的各子块作者轮廓重新投影，并更新清单签名。现有雕刻改变高度与洞格，不改变网格行列或地形 XZ 范围，因此不会增加同一子块的投影片数；这条路径不重新合并子块或改写父子身份。动态重采样已有地形不是本次新增能力。

[test_adaptive_terrain_roads.gd](../tools/test_adaptive_terrain_roads.gd) 在 0.5 米网格夹具中真实复现单块超过 512 片，并核对自动细分后的面积、地形高度、UV、路缘长度和端帽、稳定身份、真实洞口和陡坡拒绝。首轮 47 项通过，包含 loopback HTTP 工具发现、与 UI 共享预览结果、障碍和洞口的无副作用失败、生成幂等、撤销重做、保存重开及已绑定道路下挖洞的事务保护；原始日志为 `D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/adaptive_road_regression.log`。

最终补充复验 **60 项通过，0 失败**：两种高处桥口均无横封路缘、侧缘及端帽仍存在，原桥绑定未改；真实 HTTP `sculpt_terrain(mode:raise)` 后子块 ID、512 片限制与清单签名正确，地形和道路一起撤销重做并保存重开。日志 `D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/adaptive_road_regression_final.log`，临时地图 `D:/code/rmmo_runtime/cache/world3d/adaptive_terrain_roads_12032613/map.gltf`；未修改用户地图。

同日带材质补测发现另一项独立预算：起伏地面会把顶面分为许多不同共面组，`paint_default` 每组占一条原生刷面记录，可能未到 512 片投影上限便超过 `Paint.MAX_OVERRIDES=128`。现有共享材质缓存继续复用，未增加底材字段、提高刷面上限或改变逐面手刷格式。指定 `material_id` 时，自动细分额外保证每块顶面三角数不超过 128：即使日后雕刻让每个三角形变为独立面组，也有足够刷面预算，避免当前平面合组暂时通过、雕刻后失败。材质依赖错误和刷面超限的错误信息分开报告。

`test_adaptive_terrain_roads.gd -- --textured` 使用实际 `pack:default:paving/outdoor_flagstone/material` 和 0.5 米缓起伏网格，**70 项通过，0 失败**。夹具中原 4 个投影块的最大刷面数为 402；启用材质预算后为 28 个原生子块，最大刷面数 122，面积与路缘总长度不变。真实 HTTP 预览、生成、实际颜色/法线贴图绑定、重复生成、保存重开、雕刻后重新刷默认材质均通过，手动清除材质在重新生成时仍保留。证据：`D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/adaptive_road_textured_regression.log`，临时地图 `D:/code/rmmo_runtime/cache/world3d/adaptive_terrain_roads_15230943/map.gltf`。历史道路不会因打开地图自动重生成；已有道路更新仍走预览/应用及手改保护。

同日桥头实测补齐了桥翼墙的碰撞细化。原桥体包围框包含两侧翼墙之间的通路，会误拒绝正常引道。[road_bridge_approach.gd](../scripts/world3d/road_bridge_approach.gd) 仅在桥跨两端以外，将已拟合路面及其净空棱柱与保存的完整冻结碰撞三角形比较；使用实际变换，不取渲染 LOD，也不按新配方重建代替已保存几何。桥跨中央仍保守拒绝占用；真实翼墙、端柱碰撞仍拒绝。未知冻结布局、未冻结桥及倾斜桥保持原有保守保护。本次仅处理原生桥外端引道，未新增通用实体包含检测或忽略整座桥的开关。

生成预览与地形雕刻后的道路跟随更新共用该检查；碰撞缓存只在一次不可变预检内存续。[test_road_bridge_approach.gd](../tools/test_road_bridge_approach.gd) 实际 headless/HTTP **29 项通过，0 失败**：原生桥及真实铺路材质生成、包围框确实重叠的合法双端引道、未知冻结布局和桥跨主体保护、真实翼柱碰撞拒绝、UI 与 HTTP 预览一致、失败原子性、撤销重做、保存重开，以及重开后普通雕刻触发引道跟随更新。日志 `D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/road_bridge_approach_regression.log`，临时地图 `D:/code/rmmo_runtime/cache/world3d/road_bridge_approach_10123865/map.gltf`。候选桥 2 原北侧转弯另有真实端柱碰撞，需调整道路位置；碰撞修正不会自动放行这类内容错误。

上述是编辑器业务和 headless/HTTP 验证，不代表本轮城镇道路、桥梁已发布，也不替代实际桥头过渡、材质和室外镜头验收。小夹具运行时间不能作为整城加载或生成性能承诺。

2026-10-15 补充：桥端窄相的正向与逆向变换统一为 `rotation * local_scale`，与实际冻结桥 `Node3D` 一致，避免旋转叠加非均匀缩放时按世界轴误缩放。既有回归增加真实 `Frozen.visual` 的全部引道碰撞顶点对照，以及同姿态下合法中央通路/真实翼柱冲突，实际 HTTP 共 **32 项通过，0 失败**；日志 `D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/road_bridge_approach_scaled_http.log`。没有放宽桥跨主体保护或增加参数。

同日修复短边焊接的退化回环：浮点裁切在东北门路口留下约 1.39 毫米的 A→B→A 零面积边界；旧有方向映射形成循环，循环检测停止后仍保留往返边，误报“路缘内角过尖”。`road_kerb.gd` 现在将原有 2.5 厘米短边焊接范围内的节点合并到确定的公共根，消除双点及微小回环。阈值未扩大，正常尖角、分叉、路缘折叠保护均保留；没有关闭路缘或忽略合法面积区域。

`test_automatic_kerb_geometry.gd` 新增实际微片坐标、三边微片、真实尖角拒绝和正常边界不变检查，连同直路、T/Y/十字路口、环路、坡道、曲线及桥口开口用例全部通过。完整城镇配方的真实 XZ 轮廓开启路缘后通过（暴露边界约 6344.23 米）。`test_kerb_sliver_mcp.gd` 使用临时平地及同位置斜接门路，通过真实 3D HTTP 工具发现、预览无副作用、带材质生成、非法宽度拒绝、撤销重做和原生保存重开，18 项通过、0 失败；日志 `D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/kerb_sliver_http.log`。UI/MCP 无新增 schema，继续共享相同路缘业务。

贴地超坡失败现在报告实际交叠位置、地形 ID、网格和三角序号及坡度百分比，避免只提示“坡度超过限制”而无法定位。返回 `code:terrain_projection_grade_limit`，并附 `record_id/road_source/terrain_id/position/cell/triangle_index/triangle_world/grade/max_grade`；位置在实际地形表面，未加铺面偏移。结构化坡度为比值（`.15` 即 15%）；近垂直面的 `grade` 为 `null`，不发送非有限 JSON 数值。原 15% 限制、数值容差、覆盖裁切及失败原子性不变，无新增工具参数。

[test_terrain_projection_bounds.gd](../tools/test_terrain_projection_bounds.gd) 的远坐标、旋转、孔洞、覆盖及诊断回归 **22 项通过**；[test_terrain_projection_diagnostics_http.gd](../tools/test_terrain_projection_diagnostics_http.gd) 使用独立已知 25% 坡面，真实 HTTP **12 项通过**，核对 UI 同结果、实际位置/三角/坡度、预览与生成错误一致及无副作用失败。日志同目录 `terrain_projection_bounds_diagnostics.log`、`terrain_grade_diagnostic_http.log`，临时地图 `D:/code/rmmo_runtime/cache/world3d/terrain_grade_diagnostic_10993134/map.gltf`。候选图实际首处失败为桥 5 西端附近 `(200,323.25)` 的 23.4395% 地形三角，已交内容配方局部整坡，未通过修改通行阈值放行。

### 2026-10-15 贴地默认材质的 JSON 数值兼容

`terrain_follow_tools.automatic_paint` 对零 UV 偏移逐元素进行数值判断，避免 JSON 读入的 `[0.0,0.0]` 与原生成的 `[0,0]` 因数组元素类型不同而误报手刷覆盖。允许的仍是统一材质、原 UV、零旋转/偏移和材质默认米制倍率；非零偏移、旋转、手改倍率或分面混材仍拒绝自动覆盖。没有增加工具或参数，UI 地形笔刷与 3D `sculpt_terrain` 共用此路径，坡度、碰撞、锁定及事务保护保持不变。

[test_terrain_follow_paint_http.gd](../tools/test_terrain_follow_paint_http.gd) 实际 headless/loopback HTTP **33 项通过，0 失败**：显式 JSON 往返复现浮点零偏移后雕刻成功，默认 PBR、撤销重做和保存重开保留；四类真实手刷变化均无副作用拒绝。日志 `D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/terrain_follow_paint_http.log`。该项是共享能力回归，不代表住宅布局或正式地图接入已经通过。

## 2026-10-16：道路准备与街区可靠性

UI「预览铺面变化／应用铺面方案」与当前 3D MCP `preview_road_surface`、`generate_road_surface` 继续共用 `road_tools.prepare`；`update_road_graph` 的自动铺面更新也走同一逻辑。已有参数、事务、保存格式及工具发现保持兼容。

沿地形铺面在严格零旋转且数值安全的高度场上，只构造可能与道路相交的格三角形；旋转、微小倾斜及远坐标微格使用原完整扫描。仍检查真实孔洞、连续覆盖、坡度、障碍、手刷及锁定保护，保持自动细分、路缘、UV 和稳定身份。无需新增开关。

保存重开后，JSON 的整数／浮点表示和字典顺序不再让同值道路被误判为更新。准备完成全部保护后，以精确数值比较确认整条记录相等，深复制原记录以保留字节；真实数值变化不做近似忽略。重复生成同时按相同规则核对清单，避免无改动操作写入撤销历史。

本轮性能方法、街区 UI／真实 HTTP、局部更新与远路字节、撤销／重做、保存重开、自动合批和运行时碰撞回归统一记录在[优化方案](seamless_streaming_optimization_plan_20261014.md#w0-e-道路准备与-t1-投影窗口街区回归2026-10-16)。性能数字仅适用于记录的 CPU 夹具，不代表正式地图发布或任意路线已通过角色通行。

### 2026-10-17：道路障碍准备提前粗筛

UI 与当前 3D MCP 继续共享 `road_tools.prepare`。展开地形格之前，逐条道路核对已验证承托或保守 XZ 分离；只有全部道路均无需该地形时才跳过展开。远处判定限严格零旋转且数值有效的高度场，旋转／倾斜地形回退完整检查。每次 prepare 只按需缓存道路包围矩形，不跨编辑复用；精确碰撞与首个冲突顺序、手刷保护、撤销保存保持。

完整结果字节对照、CPU 配对测量、街区与住宅 UI／HTTP、贴地道路雕刻跟随验收见[统一方案](seamless_streaming_optimization_plan_20261014.md#w0-e--t1道路障碍准备粗筛2026-10-17)。本次未新增 MCP 工具或参数，没有开启二维适配器。

### 2026-10-17：默认铺路材质的 CPU 准备

道路默认材质与地形雕刻后的自动重刷继续共用 `road_tools.paint_default`。候选分析直接使用原生全部 CPU 数组，只对铺面槽计算面组与签名；其余槽的通道及三角形预算仍检查。部分分析结果不会遮掉后续手工刷面的底面／侧面／路缘。原刷面数量、签名、UV、材质依赖、手刷保护与撤销保存保持；发布时仍生成完整网格并进入共享批次。

UI／当前 3D MCP 无新增参数，详细测量和回归见[统一方案](seamless_streaming_optimization_plan_20261014.md#w0-e--t1默认铺路材质准备2026-10-17)。CPU 准备收益不等于整体加载或纹理上传收益。


## 2026-10-17：贴地格点与路缘采样复用

`terrain_projection.fit` 在单次调用中使用两行惰性格点，复用相邻实心格的原生世界坐标；孔洞不构造格点。路缘沿用原来的采样、全部地形顺序和最高支撑高度，只复用地形变换及完全相同的原生世界坐标采样，最多缓存 4096 个坐标，超出后继续精确计算。每次道路预览、应用或雕刻跟随都会建立新的局部状态；不存在跨编辑、撤销或重开的旧高度复用。

裁剪顺序、坡度诊断、覆盖容差、512 片及 128 刷面预算、UV、路缘端帽和作者身份均保持。UI 与当前 3D MCP 继续共享道路准备和地形跟随入口，无新增 schema 或保存字段。典型细地形案例的原生格点构造由 8640 次减至 2632 次，世界变换由 12960 次减至 2632 次；远地形路缘采样由 7392 次减至 2912 次，格／三角访问数和完整输出字节不变。

本批严格差分 **505/0**；独立后台桌面的实际 UI／HTTP **263/0**、街区 **113/0**、住宅与入户路 **127/0**、带真实材质的自适应道路与雕刻 **70/0**、JSON 材质跟随保护 **33/0**、坡度诊断 **12/0**。验证失败原子性、独立拾取、共享合批、一次撤销重做及保存重开；只使用临时地图。新 UI 夹具保留 **18792 个顶点**，表面 **24→12**，派生队列清零。没有改变模型或导出资源；本轮不重做建筑室内或整城通行验收。

完整原始数据与失败测量说明见[证据索引](../review_artifacts/road_projection_20261017/evidence.json)，性能结论与下一项顺序统一记录在[优化方案](seamless_streaming_optimization_plan_20261014.md)。CPU 复用不等同于端到端 UI 提速；真实材质目录查找仍需独立优化。

## 2026-10-17：道路与路缘的批量材质查找

道路准备通过 `surface_material_library.find_many` 在一次同步操作内解析路面和路缘 ID。两者同时启用时只读取一次完整目录；只有一个材质时仍读取一次，两个都不用时不读取。继续使用原 `entries()`，保留目录深度／数量上限、资源包顺序、同 ID 首项、资源根与链接保护，以及自定义材质目录实现。返回材质为独立深复制，操作结束即释放，下一次预览或应用重新读取；不使用 UI 面板的旧目录快照提交。

UI 的预览／应用按钮、当前 3D MCP 的 `preview_road_surface`／`generate_road_surface` 以及住宅入户道路准备共用此逻辑。所选路缘的透明度、材质合法性、缺图检查及原失败顺序保留；描述文件或依赖在预览后发生变化时，原方案校验仍执行。没有新参数、保存字段或异步成功状态。验收与性能范围见[统一方案](seamless_streaming_optimization_plan_20261014.md)和[本批证据](../review_artifacts/material_lookup_20261017/evidence.json)。
