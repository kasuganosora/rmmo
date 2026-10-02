# 城镇布局草案（2026-10-02）

入口：内容编辑器顶部 **城镇布局** 按钮 / 同名页签。包含公里级视图、参考底图、书签、导航概览和可保存的道路骨架。道路骨架是编辑辅助；可显式拆分交叉并生成真实路面与碰撞，建筑会避让已生成道路。多边形保留区见 [道路铺面与保留区域](world_editor_roads.md)；闭合街区、临街地块与分批房屋见 [街区与地块](world_editor_blocks.md)。现有道路自动瓦片与沿街建筑工具保持原有语义。

## 视图和底图

- **正交俯视**朝向北（−Z）；视野高度为 2～10000 米。透视环绕视距 2～10000 米，右键从正交切回透视；中键按实际米 / 像素平移，滚轮缩放。
- **适配全图 / 聚焦选择 / 区域定位**按包围盒和画布长宽比计算视野。全图包含隐藏、锁定物件、道路及底图；不会因楼层隔离漏掉地图范围。超出视野上限明确失败。选择、刷面、贴面和出生点射线沿用相机远平面，拉远后仍可命中物件。
- 右上概览是道路和物件包围盒示意，点按定位；黄色框表示正交视野。物件示意最多抽样 1024 个，并非完整渲染小地图。未使用布局功能且不在此页签时不显示。网格随视野改变间距，左下有比例尺。
- 导入 PNG / JPEG / WebP，单图不超过 16 MiB、4096×4096，路径须在外部内容根内。UI 与 MCP 使用同一操作；桌面文件需先复制到内容根。校验全部参数后复制为不可变 PNG：`<内容根>/cache/world3d/layout_references/<sha256>.png`，不更改原图，不放进默认素材包。
- 参考图只在正交视图叠加，图片中心是世界 XYZ 米；像素原点左上，X 向右、Y 向下。可设米 / 像素、Y 旋转、透明度和显示，覆盖范围最长 10000 米。两对像素点与同高世界点可同时标定平移、等比尺度和旋转，不做透视 / 地形扭曲。
- 锁定后允许改透明度 / 显示，位置、尺度、图片替换和删除需先单独解锁；不能在同次调用里解锁并变更标定。图片缺失提示重新导入，不阻止地图读取。当前引用外部内容库绝对路径，跨机器搬迁需连同内容库或重新导入，尚未打包成相对资源包依赖。
- 普通镜头操作不修改文档或撤销栈。**视图书签**保存投影、目标、距离、竖向范围和角度，最多 32 个；增改 / 删除使用共享撤销并随地图保存。临时视角不自动持久化，重新打开后可跳到书签。

## 道路骨架

在“绘制道路骨架”设置宽度、绘制平面标高和地面 / 桥梁，点击“开始点选道路”。左键连续点选，Enter 提交整笔，Backspace 退一点，Esc 取消；离开窗口取消临时操作。端点靠近已有可编辑节点会按屏幕距离吸附，提交时世界距离 0.25 米内复用节点。点在已有线段中部或穿过线段**不会**自动拆线 / 创建路口。

在此页签直接拖动已有节点，相连直线 / 曲线端点一同更新；Alt 暂停位置吸附，Esc 取消，松手只产生一次撤销。拖动中只修改辅助预览，文档保持原样；失败恢复原节点。标高、锁定 / 隐藏、起终点宽度和三次曲线的两个绝对世界控制柄可在属性里精调。移动节点不会自动平移曲线控制柄。

持久化位于 `map_meta.editor_layout`，版本 1，和物件 `records` 分离：

- `roads.nodes`：稳定 `id`、世界 `position`、可选 `locked/hidden`。
- `roads.edges`：稳定 `id`、端点 `from/to`、`width_start/width_end`（1～60 米）、`kind: ground|bridge`、可选名称、两个 `controls`、保护标记；绑定河道桥梁时附带 `bridge_ref:{waterway_id,bridge_id}`，其几何由桥梁配方保护。
- 多条边引用同一节点表示连接；可表达 T、Y、十字等拓扑，可显式生成路口铺面。桥梁用独立节点 / 高度跨越，不因投影相交而连接。
- 每图最多 256 节点 / 512 边；单次点选 64 点。线段至少 0.5 米；退化采样、缺失端点、重复 ID / 端点对、未知字段和超限整笔失败。平行路线可加中间节点以区分路径。
- 隐藏 / 锁定元素需先解除保护才能修改几何或删除。受保护线段同时保护端点移动 / 删除；受保护节点不能新增连接。删除节点必须同次显式删除全部关联边，避免悄悄断路。
- 空间分桶检测交叉；曲线用 16～128 段采样，直线检查分段最长 32 米。诊断包括未连接交叉、自交、重叠、桥梁跨越、地面高度冲突与大于 15% 的坡度。这些是可保存的**草案诊断**，不等于精确道路面碰撞 / 桥下净空证明。宽度边线只是走廊示意，实体铺面使用圆角连接处理急弯。
- 诊断预算最多 16384 采样段 / 1000000 对候选；超预算拒绝，不静默跳过。辅助刷新不重建物件场景；撤销仍使用全量文档快照，整城增量撤销 / 后台保存尚待后续实现。

## 当前 3D MCP

布局十项，加上道路/区域五项、街区四项、植被四项、河道四项、道路联动三项及城墙五项，当前共 **104 项**。旧二维服务仍不注册。[河道、河岸与平桥](world_editor_waterways.md) 支持点选开槽、真实河床和齐平桥头；[道路联动](world_editor_road_connections.md) 支持显式接桥及直线坡道，[城墙城门](world_editor_fortifications.md) 支持连续绘制和活动门。当前桥梁外观列入 [待办](world_editor_todo.md)。

| 工具 | 用途 |
| --- | --- |
| `get_city_layout` | 布局、road_token、相机、世界范围、诊断和交互状态 |
| `set_editor_camera` | `projection: top/perspective`、`center`、`span`、`distance`、`yaw`、`pitch` |
| `focus_editor_view` | `target: all/layout/selection/region`；region 必须有 `from/to`；可指定投影 |
| `set_map_reference` | 导入 / 调整底图，或单独 `remove:true` |
| `calibrate_map_reference` | `pixels:[[x,y],[x,y]]` 与 `world:[[x,y,z],[x,y,z]]` |
| `save_view_bookmark` | `name` 必需；可带 `id` 更新原书签 |
| `delete_view_bookmark` / `recall_view_bookmark` | 删除 / 跳转 `id` |
| `update_road_graph` | `expected_token` 必需；节点 / 边完整项增改，`remove_nodes/remove_edges` 显式删除 |
| `create_road_path` | `points` 世界点列，选填 `width/kind`；与 UI 相同的整笔事务 |

现有 `preview_map` 加入 `include_layout:true`，截图包含底图、道路、概览、比例尺和编辑辅助。默认仍只返回 3D 场景，试玩仍返回游戏视图；headless 明确不支持图像。`editor_state` 新增 `editor_camera` 和 `road_drawing`；更完整的节点拖动状态见 `get_city_layout.road_node_drag`。

`update_road_graph` 使用 `get_city_layout.road_token`（当前图内容哈希），与当前草案不同即拒绝，防止覆盖后续修改。保持节点 / 边 ID 即可局部编辑，不需要替换整份图。绘图 / 拖动、物件变换、画笔、试玩等忙碌保护共用现有入口。元数据进入共享撤销、草稿、保存和读取校验；辅助线不生成 glTF 节点、碰撞体或导航面。

```json
{"name":"focus_editor_view","arguments":{"target":"region","from":[-600,0,-600],"to":[600,0,600],"projection":"top"}}
{"name":"create_road_path","arguments":{"points":[[-500,0,0],[0,0,0],[500,0,0]],"width":12}}
{"name":"create_road_path","arguments":{"points":[[0,0,0],[0,0,-400]],"width":8}}
{"name":"save_view_bookmark","arguments":{"id":"whole_city","name":"全城总览"}}
{"name":"preview_map","arguments":{"include_layout":true}}
```

## 验收与下一批

`tools/test_world3d_city_layout.gd` 使用临时 1.4 公里地图，通过真实 HTTP 验证发现、全图 / 区域定位、远距离拾取、底图路径与标定、保护、书签、T 型连接 / 未连接相交 / 桥梁跨越、曲线、身份、原子失败、撤销重做、真实鼠标点选 / 节点拖动、草稿和保存重开。保存后仍只有原始三件物体。后台独立桌面图形验收输出编辑器与 MCP 布局截图。

64 条直路 / 1.2 公里、2432 个检查分段的诊断实测约 60～85 毫秒（此电脑、开发构建），检测 900 处未连接交叉。该值不是整城渲染、海量物件编辑或运行时性能保证。

最终图形 / HTTP 验收日志：`D:/code/rmmo_runtime/review_artifacts/city_layout_acceptance_live.log`，`CITY_LAYOUT_FINISHED failures=0`，无脚本错误。同时通过既有 `test_world3d_mcp.gd`、`test_world3d_transform.gd`、`test_world3d_groups_ui.gd`、`test_world3d_editor.gd` 回归。参考图和地图夹具在 `D:/code/rmmo_runtime/cache/world3d/city_layout_8161005/`，未覆盖用户地图。

后续已补上交叉拆分、水平路面与路口、米制 UV / 碰撞、桥下净空，以及禁建 / 禁植被 / 保留通道多边形，见 [道路铺面](world_editor_roads.md)。闭合街区、保守临街地块与分批空位房屋见 [街区与地块](world_editor_blocks.md)，水平区域植被散布见 [植被散布](world_editor_vegetation.md)。河道之后已增加道路桥梁联动、直线坡道和连续城墙/活动城门；当前桥梁外观仍需重做。道路变更后的自动建筑替换尚未实现。本次按用户范围完成道路联动和城墙两轮，完整城镇参考图尚未重建，测试图不代表最终规划。
