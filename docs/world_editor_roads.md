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
- 路面按世界坐标 **32 米分块**，分块内保存互不重叠的凸多边形补片。环路中央、弯路外侧和分块空角保留空地；不会以整个分块包围盒代替道路碰撞。网格包含正面、背面、边缘，法线和切线有效；顶面使用连续世界米制 UV，支持资源包 PBR 法线、粗糙度与 AO。
- 曲线采样段在缓弯处共用偏移横截面，使两侧边缘连续，避免每个采样点叠加整圆后裁出大量碎片。锐角或相对路宽过短的段仍使用有界圆角；不会生成过长尖角。相连路口按交汇横截面收口，圆端帽只用于断头路，防止宽支路伸出窄主路。UI 与 MCP 仍共用 `road_plan.gd`，参数与撤销事务不变。
- 建筑预览、直接生成、区域随机生成、沿街生成、更新及整栋移动/旋转/复制共用占地检查。道路实际范围和上方净空都是障碍；普通地面支撑的豁免不适用于生成道路，包括解除关联后的道路。
- 生成道路前检查全部现有物件，包括隐藏、锁定物件；真正位于脚平面下的普通地面可作为支撑。障碍物落入路面或净空会整笔拒绝，不删除既有房屋、物件。
- 净空默认 3 米，可设 2.5～10 米；桥面高差须至少为净空加铺面厚度。厚度 0.1～0.5 米，默认 0.2；顶面高于道路节点 0.005～0.05 米，默认 0.025，以避免与平地重叠闪烁。

**边界：**直线高差道路支持扣除水平接头后不超过 15% 的坡度；曲线斜坡、随地形贴合、倾斜路口、自动桥墩尚未实现。[河道工具](world_editor_waterways.md) 可生成与两岸齐平的桥头和栏杆，显式接入道路图后支持引道联动；桥梁模型仍待重做。自交、重叠中心线、不同类型的同层穿越及无法稳定求解的近切线交汇需先整理骨架。交叉候选来自 16～128 段曲线采样，再用曲线参数求精确交点，误差超限拒绝；不声称覆盖任意曲线的全部数学交点。

上限：256 节点、512 边、8192 源轮廓、4096 路面块、每块 512 凸补片、100 万次裁切。单个刷面记录上限仍为 128，极复杂分块绑定默认材质可能因该限制被拒绝。复杂度超限保持原文档，不静默少生成。更新目前仍重新求解道路图、重建编辑场景及记录完整撤销快照；稳定身份和差异统计不等于整城增量渲染性能已经完成。

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
