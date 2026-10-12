# 本轮功能边界补完（2026-10-12）

用户要求完成上一轮列出的“本轮功能仍有的边界”。六项均已实现并验收；本记录覆盖 [首批扩展交付](editor_extensions_20261012.md) 中对应的旧限制。未恢复历史标记“未解决-跳过”的性能专项，也未更改正式城镇摆放。

## 交付后代码审查与修复（2026-10-12）

用户要求复查上述新增代码并直接修复问题。本次检查共享业务、撤销/保存、派生几何及实例生命周期，确认并修复如下问题；下方首批 443 条验收保留为历史证据，不与本次检查混算。

|范围|确认的问题与修复|
|---|---|
|斜坡桥及道路|转桥裁路后旧路缘及其贴地模板仍可能穿过桥下，现同步按裁切区域截断，插值完整截面、UV 和封口。重铺只裁绑定边并检查交叠顶点的高度，保留其他交叉路；邻接路拓宽改变桥头坡线时整笔拒绝，修正坡道投影重复计算铺面抬高量。|
|河道恢复层|补齐保存配方 schema、身份、重复项、签名及快照不变字段校验；面板加载省略参数时回到后端默认值。不同河道不能重复占用同一河床样本或全块自然材质，以免删除其中一个破坏另一个。无交叠且关闭自然材质的河道可独立编辑。|
|河道材质保存|被覆盖的旧材质也纳入原生保存依赖；删除/改线恢复前检查实际纹理存在。真实自然材质另存到其他目录、重开再改线/删除通过；缺失旧贴图时保存和恢复均不改文档、历史或地图文件，补回后可恢复。沿用引用地图的外部资源根，不宣称跨机器打包。|
|混合网格与笔刷|补齐全部边界最终连续性检查，覆盖局部接边、T 接点、多块接边顺序与旋转误差。无法由双方公共格点表达的变化整笔拒绝，无关位置雕刻仍可用。补洞时拾取回退覆盖所有相连地块，保留前景遮挡与单块模式语义。|
|水关随地形|曲线 `water_crown` 上方的垛口/女墙以前会跟河床下沉，现使用实际冠顶多边形判定承托并保持与固定拱顶连接；普通墙段仍随地形。三孔六扇独立门栅、预览、撤销重做及保存重开均验证。|
|作物与共享网格|带灯光、独立显隐/显示距离、LOD 偏置、碰撞或活动组件的模型不再被错误压平入批；普通 BoxMesh 不调用不存在的 blend-shape API。材质分叉创建私有网格，不再修改共享源；复杂 BoxMesh 保留细分、翻面和 UV2。原生 ArrayMesh 的 16/32 位 LOD 索引在源释放、材质分叉和选择恢复后保留；城防 Art 单件生成器补传已有 LOD 到 CPU 缓存。|

本次 **14 份最终日志、388 条 PASS 检查、0 失败/引擎错误/警告**，另有 CPU 网格整套通过回执。包含重叠的 HTTP/GPU 检查，不称 388 个独立场景。所有 GPU 测试在不激活的独立桌面，截图无角色；所有写入使用临时地图和测试素材。最终三个临时图通过生产 `MapLoader → WorldStream` 加载，作物仍形成实际 MultiMesh。

|最终日志（位于 `D:/code/rmmo_runtime/`）|PASS|范围|
|---|---:|---|
|`review_structure_boundary_guards.log` / `review_structure_bridge_http_final.log` / `review_structure_bridge_gpu_live.log`|12 / 37 / 39|桥头、裁路缘、图更新失败原子性、HTTP、保存重开和画面|
|`river_boundary_review.log` / `river_material_save_review.log`|57 / 32|河道 schema、所有权、接边、真实自然材质、另存/恢复与缺图失败|
|`terrain_follow_review.log` / `terrain_follow_review_interaction_final.log`|19 / 12|混合格距、T 接点、拾取、松手重建和整笔回滚|
|`water_crown_follow_review_gpu.log`|40|冠顶承托、六扇门、冻结跟随、保存重开、单件 LOD 与四组 A/B 图|
|`crop_boundary_review_gpu_final_live.log` / `review_crop_http_gpu_live.log`|26 / 42|实例语义、复杂盒体、共享材质、实际作物批次与 LOD|
|`review_lod_retention_headless.log` / `review_ground_batch_lifetime_final.log`|33 / 35|LOD 派生数据、碰撞保留、删除卸载、异步过期结果和材质分组|
|`review_ground_cpu_final.log` / `review_extensions_runtime_final.log`|整套回执 / 4|CPU 几何恢复与生产游戏加载|

独立汇总为 `D:/code/rmmo_runtime/review_artifacts/editor_boundaries_review_20261012/verification.json`，含最终代码/日志/临时地图 SHA；复核脚本 `tools/summarize_editor_boundary_review.py`。局部模型审计为同目录 `structure_review.json`、`water_crown_review.json`，见 [模型复验](editor_extension_models_20261012.md)。正式地图 SHA 仍为文末记录值，源模型与默认素材库未修改。

**保留的历史性能边界：** 原有 `house_prefab.bake → build_fortification` 只合并基础几何；本次水关冻结图仍没有派生 LOD，近中远提交图元均为 231,256。`Art.build` 单件 LOD 缓存修复不能表述为冻结城防 LOD 端到端完成或加载提速。该项归入既有“未解决-跳过”的冻结资源/远近分层性能范围；没有自动扩展本轮任务。

## 已完成能力

|事项|最终行为|UI / 当前 3D MCP|
|---|---|---|
|斜坡道路绑定转桥|支持不同高度桥头；道路路口的平段、连接边的最大路口宽度、坡线和实际铺面抬高量共同决定桥头。只裁切匹配高度的旧路面，插值新顶点高度；保留高架交叉道路；重铺不会重建桥下旧桥板。|桥面板“加载道路”及 `preview_bridge` / `generate_bridge` 的 `road_edge_id`。|
|圆形 / 椭圆水关|共享多孔真实拱券、中墩及独立双扇铁栅；补曲线环墙与直线券顶之间的接合，减去重叠面，避免共面闪烁。|城防 `shape=ellipse`（等半径即圆）、`gates[].kind=water`、`set_fortification_gate`。|
|河道非破坏改线|持久化生成前后地形差异和所属水面；同 ID 改线先还原旧河床，再计算新路线。删除会恢复旧床及原有相关材质；保留河道外的后续雕刻。保存重开后仍可操作。|河道面板加载 ID、替换选中控制点、更新 / 删除；`list_terrain_rivers`、`preview_terrain_river`、`generate_terrain_river`、`remove_terrain_river`。|
|不同格距跨块笔刷|细网格的边界约束到两块共同的分段直线；1/2 米及非倍数 2/3 米网格边缘连续，不受文档记录顺序影响。|既有“跨相邻地块”及 `sculpt_terrain` / `preview_terrain_stroke` 的 `cross_tiles`，默认开启。|
|冻结城防后续随地形|从原配方重新拟合墙段，城楼、城门及铰链保持刚性，再冻结并更新构件签名。已存在的冻结城防可开启或解除跟随。|城防面板“随地形雕刻联动（城楼保持刚性）”及应用按钮；`set_fortification_terrain_follow(id,enabled)`。|
|作物 LOD 与风验证|青麦、成熟小麦新增 LOD 资源，保留完整近景几何和原始贴图；共享 native 管线及实际 MultiMesh 保留 LOD。两种风向、96 连续帧及移动镜头跨 LOD 验证。|默认素材库“作物”内两项“（LOD）”，已生成缩略图；原散布 / 风场 UI 与 MCP 共用操作，无额外 LOD 专用工具。|

### 事务与保护

- UI、HTTP 共用业务路径和撤销事务；未重新注册旧二维工具。
- 地形拖动期间只预览地形；松开鼠标时统一重建相关冻结城防一次。最终承托失败会恢复整个手势之前的文档，不留下半笔或额外撤销历史。HTTP 单笔也在发布前完整校验。
- 墙顶坡度仍不超过 15%；刚性城楼 / 城门平台允许高差不超过 0.12 米。不会把楼梯或门轴剪切成斜体。锁定、隐藏、所属构件被手改、缺少承托时整笔拒绝。
- 河道只恢复本图层实际改变的高度 / 洞样本及外观字段，复核当前值仍与图层写入值一致；恢复记录重新经过原生保存和材质依赖校验。受影响样本、水面被手改，或地形网格 / 位姿改变时拒绝覆盖。不同河道重叠修改同一批样本时同样保护，不按猜测覆盖。
- 河道恢复层随地图保存；历史河道没有生成前快照时不能自动推断原始地形。不会将现状误当原始河床并宣称可还原。最多 64 层、单次最多 64 块地形，沿用采样和地图容量预算。
- 不同格距同步仍要求同方向、原本对齐的共享边界；不修复既有错位，不等同运行时地形 LOD 或跨块水力侵蚀。
- 道路绑定桥转化后，不能独立改变道路抬高量导致桥头错层；错误请求无副作用失败。既有河道配方桥保留它自己的固定铺面合同。
- 水关为平开栅，非升降闸或水动力模拟。上述是几何 / 数据有效性约束，不是未完成的六项功能。

## 验收证据

全部地图操作使用临时地图；GPU 测试通过 `tools/run_godot_background.py` 在不激活的独立桌面执行，截图场景没有角色人像。证据根目录为 `D:/code/rmmo_runtime/`。

`review_artifacts/editor_boundaries_20261012/verification.json` 汇总 **12 份最终日志、443 条通过检查、0 失败**，记录 22 个相关源文件 SHA、测试地图 SHA、正式地图 SHA 和两件已发布素材身份。包括重叠的 GPU / headless 复测，不宣称 443 个独立场景。开发中的失败日志不计入最终通过数。复核命令：`python -X utf8 tools/summarize_editor_boundaries.py`。

|日志|通过检查|主要证明|
|---|---:|---|
|`boundaries_guards.log`|6|2/3 米非倍数网格 49 个边界采样点、文档顺序稳定；匹配高度裁路、高架路保留；连接路口宽度。|
|`boundaries_structures.log`|68|既有木 / 石桥胶囊双向通行、坡墙、真实水关拱孔与关栅、河床墩基及保存回归。|
|`boundaries_contract_final.log`|81|最终代码真实 HTTP：工具发现、混合网格、河道只读预览 / 改线 / 删除 / 手改冲突、两种环墙水关、冻结跟随切换、锁定失败及精确撤销 / 重开。|
|`boundaries_final_visual_live.log`|85|上述边界 GPU 验收和四张无角色图；`cache/world3d/extension_boundaries_10513833/`。|
|`boundaries_interaction.log`|12|真实编辑器笔刷路径：每次拖动不冻结、松手一次更新、一笔撤销、承托失败整笔回滚；河道面板回填 / 替换控制点。|
|`boundaries_terrain_final.log`|66|原地形、洞穴、跟随道路、自然 PBR 河道回归；相同河道请求不重复挖低。|
|`boundaries_bridge_visual_live.log`|33|斜坡桥真实 HTTP 与 GPU 外观、重铺无旧桥板、UI、保存重开；`cache/world3d/sloped_road_bridge_10959935/sloped_bridge.png`。|
|`boundaries_bridge_lift_final.log`|34|后续定点复测 0.04 米自定义铺面抬高量；正常重铺通过，单独改偏移原子拒绝。|
|`boundaries_crop_batch_final_live.log`|42|两件新资源在实际编辑器导入、行列散布、共享实例批次保留 LOD、选择 / 受风退出批次、锁定、撤销及保存重开。|
|`boundaries_crop_lod_final_live.log`|11|真实 native 导入 / 重读、LOD 索引、固定镜头近中远图、96 帧连续风与跨 LOD 镜头。|
|`boundaries_runtime_final.log`|5|生产 `MapLoader → WorldStream` 加载环墙 / 河道 / 冻结城防、斜坡桥、作物测试图，独立闸扇和真实 MultiMesh 保留。|
|`boundaries_publish_live.log`|发布回执|默认库两个 LOD 素材、native 准备、原子目录保存、真实缩略图；`crops_published.json`。|

源码主要分布于 `terrain_river_layer.gd`、`terrain_stroke_batch.gd`、`terrain_follow_tools.gd`、`terrain_brush.gd`、`fortification_ring.gd` 及桥 / 道路共享业务路径；工具 schema、分发和 [MCP 文档](world_editor_mcp.md) 已同步。

## 作物画质与资源结果

完整逐件审计见 [扩展模型验收](editor_extension_models_20261012.md)。保留 v1 Blender 母版和旧 GLB，v2 只新增 `rmmo_auto_lod` 元数据，源 GLB 的 BIN 块逐字节不变。LOD 由现有 native 管线构建；新文件独立发布，未偷偷替换正式地图实例。

同相机 / 光照 / 曝光 / 1280×800 视口，静态 A/B 关闭 TAA 排除历史抖动，连续运动恢复项目 TAA。特写与近景的 A/B 像素差为 0；中景 / 远景全图平均绝对 RGB 差分别为 0.03489 / 0.05081（0～255 量程），最大单通道差 55 / 54。完整图片与自审共同判定，不能用全图平均值掩盖局部损失。

192 丛试验场渲染器提交图元：近景 799,682 → 799,682；中景 799,682 → 448,542；远景 799,682 → 371,906（约少 53.5%）。特写 470,647 保持相同。它是指定视口场景图元数，不是源模型三角形总和、FPS 或显存收益。

画质自审查看完整近 / 中 / 远 / 特写 A/B，以及两个方向各 48 帧的连续图序列：已测距离内未发现明显轮廓塌陷、突然成片消失、根部脱离或整片同步跳变。96 帧按 24 fps 采样；风向 `(10,0,2)` / `(-2,0,10)`，幅度 0.12、底部锚定，镜头距离参数 9→25 米。细麦芒远处仍属于亚像素细节；不把有限风向 / 光照验证表述成任意条件绝无闪烁。原图、`comparison.jpg`、`wind_0_all.jpg`、`wind_1_all.jpg`、`render.json` 和 `pixel_comparison.json` 均在 `review_artifacts/editor_boundaries_20261012/crops/`。

正式 `maps/medieval_river_town/map.gltf` SHA256 保持 `a2808a3fc088c601c4a5913ec8f97ea7603b4de49858c29ff7bd742861696f44`。本轮未覆写用户地图；美术自审不代替用户最终美术确认。
