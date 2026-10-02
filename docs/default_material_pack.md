# 默认资源包：写实建筑与中世纪城镇材质

2026-10-02。默认包已包含 10 套直接下载的 Fab 材质、从已购 Wood Material Pack3 原生导出的 3 套精选木材、1 套生成陶瓦，以及 4 个参数变体，共 18 项。运行材质均按用途分类。整木纹用于梁柱，拼板用于地板，外墙和室内使用不同的抹面；石材仅用于石砌结构、基座与铺地。

本机默认包为 `D:/code/rmmo_runtime/packs/default`，不使用历史二维包 `packs/map_pack/default/0.1.0`。美术数据保存在外部内容根，不写入源码仓库。其他地图使用共享默认包，无需逐图导入。

## 分类与用途

运行文件位于 `assets/materials/<用途>/<材质>/`，每套独立保存 `material.json`、`texture.jpg`、`normal.png`、`roughness.png`，以及原素材具备的 `metallic.png`、`ao.png`。

| 目录 | 编辑器分类与名称 | 适用位置 | 来源 |
| --- | --- | --- | --- |
| `walls/lime_plaster` | 墙面／浅色石砌 · 浅色石砌墙 | 外露浅色石墙、石基 | [Plaster Wall Material](https://www.fab.com/listings/b2d5ad89-b0cd-4f5e-b877-8424db90c31f) |
| `walls/castle_rubble` | 墙面／石砌城墙 · 古城石砌墙 | 城墙、塔楼、桥墩、房屋石基 | [Castle Wall / Quixel](https://www.fab.com/listings/c7bacf7e-8073-4f4f-aaf9-ef9fa357c11c) |
| `wood/worn_planks` | 木材／天然木板 · 天然风化木板 | 木地板、木桥、门板 | [Worn Wooden Planks / Quixel](https://www.fab.com/listings/7992bc73-2fd9-4b56-b25a-c549d7d9e1b5) |
| `wood/painted_weathered` | 木材／漆木 · 风化青漆木 | 门窗、围栏的局部旧漆装饰 | [Old Painted Wood Vol.02](https://www.fab.com/listings/4bb26fbd-a619-4d79-8dd9-9ce5783f6d0d) |
| `paving/sandstone_floor` | 铺装／石板 · 风化石板地面 | 庭院、教堂、城堡地面 | [Smooth Rock Floor Material](https://www.fab.com/listings/9bd35429-bb3f-4f72-91b9-454aebcde85b) |
| `paving/historic_cobble` | 铺装／鹅卵石 · 历史鹅卵石街道 | 街巷、广场、桥面 | [Cobblestone / Quixel](https://www.fab.com/listings/904d4710-9fe2-402d-853d-f042fe95b3f5) |
| `terrain/mud_pebbles` | 地表／泥土 · 湿泥碎石地 | 河岸、湿地、土路边缘 | [Muddy Ground](https://www.fab.com/listings/93d594e8-99f2-4ec6-8980-6135929338d8) |
| `terrain/moss_rock` | 地表／岩石苔藓 · 苔藓岩石地 | 河岸岩石、林缘，局部使用 | [Mossy Rocky Grass](https://www.fab.com/listings/eb3390a8-0f58-4d74-844a-a47a2c16bd29) |
| `roofs/terracotta_plain` | 屋顶／陶瓦 · 手工红陶叠瓦 | 中世纪民居坡屋顶 | 内置 image_gen 制作；颜色、OpenGL 法线、粗糙度三张图 |
| `wood/structural_oak` | 木材／天然木板 · 深色旧木板 | 旧木地板、门板；保留历史 ID | 复用天然风化木板原图；已退出示例梁柱配色 |
| `details/window_glass` | 门窗／玻璃 · 微绿旧窗玻璃 | 半透明窗片 | 标准材质颜色/透明度/粗糙度参数，无图片 |
| `walls/troweled_plaster` | 墙面／外墙抹面 · 手工抹面灰泥 | 外墙抹刀纹理基底 | [Construction Plaster / Quixel](https://www.fab.com/listings/c61bd44e-ce01-47ae-b0b8-eb0f4ff3cc60) |
| `walls/fine_plaster` | 墙面／内墙灰泥 · 细抹蓝灰墙面 | 室内细抹面基底 | [Fresh Wall Plaster / Quixel](https://www.fab.com/listings/b427a11b-5d79-41bc-af42-3cd3aadae25c) |
| `walls/exterior_limewash` | 墙面／外墙抹面 · 外墙石灰抹面 | 半木构外墙填充面 | 暖白刷面参数，使用外墙扫描法线、粗糙度、AO |
| `walls/interior_limewash` | 墙面／内墙灰泥 · 室内白刷细灰泥 | 内墙、天花和墙洞内侧 | 浅暖白参数，使用另一套细灰泥扫描法线、粗糙度、AO |
| `wood/solid_timber` | 木材／梁柱 · 棕色整木梁柱 | 梁、柱、木框 | Wood Material Pack3 的 MI_Wood8 |
| `wood/natural_joinery` | 木材／门窗木作 · 浅色天然木作 | 窗扇、楼梯 | Wood Material Pack3 的 MI_Wood2 |
| `wood/weathered_solid` | 木材／梁柱 · 灰褐风化整木 | 室外老木构件备选 | Wood Material Pack3 的 MI_Wood3 |

原始 ZIP 与来源记录对应存入 `sources/fab/<用途>/<材质>/`，不会混在运行贴图目录。`sources/fab/catalog.json` 是完整清单；`material_contact_sheet.jpg` 展示实际下载的颜色贴图。每套 `source.json` 记录商品链接、卖家、已购验证日期、许可链接、ZIP 的 SHA-256、原图成员名和运行图 SHA-256；灰泥商品标注 AI 生成，该标记已保留。

Fab 运行贴图统一为最大 2048 × 2048，保留原始高分辨率包。颜色使用高质量 JPEG，法线与标量通道使用 PNG；缩小法线后重新归一化。苔藓素材的 ORD 只拆出 R=AO、G=粗糙度，B 为置换，不作为金属度。没有金属图的石材/木材默认金属度为 0。高度/置换原图保留，尚未启用几何置换。

Quixel 三套采用扫描标注的 2 × 2 米范围和 OpenGL 法线，方向结合原高度图校验。灰泥、石板的 DirectX 法线方向也结合原高度图校验；漆木及两套地表按其引擎/导出工作流推定 DirectX。非扫描素材的 2 × 2 米为编辑建议尺寸，可以通过重复倍率调整，不宣称实测尺寸。材质的方向在元数据中保留，编辑器加载 DirectX 法线时仅转换一次绿色通道。

生成陶瓦的三张图均保留工具原生 **1254 × 1254 PNG**，没有放大冒充 2K。材质使用 `albedo.png`、`normal.png`、`roughness.png`；原件、每张图 SHA-256、完整生成/修改提示词保存在 `sources/generated/roofs/terracotta_plain/`。它们是 AI 制作并对齐的近似材质图，不是测量扫描。法线为 OpenGL +Y，强度 0.65，瓦片搭接处的凹凸和微表面随光照变化；金属度为 0。粗糙度图修正了过暗接缝，避免瓦缝产生不合适的光泽。颜色图保留轻微接触暗部，本轮不另叠加 AO。

陶瓦每张约 4 列、4 层，建议覆盖 `tile_size=[1.0,0.72]` 米。使用生成店屋的默认沿深度屋脊时，两侧坡面分别旋转 ±90°，`scale=[0.72,1.388889]` 补偿当前 UV 旋转的尺寸轴，使瓦层平行屋檐、搭接朝向檐口。法线仅提供表面凹凸，不修改房屋几何或碰撞。

## 编辑器与 MCP 使用

打开左侧 **材质** 页，按用途选择分类，再选材质。生成房屋的墙、地面等仍通过已有表面笔刷应用，建议选择 **按米重复（材质建议尺寸）**；例如 6 × 3 米墙面不会把石块拉伸到整个面。也可旋转木纹、设置重复和偏移。此轮没有给建筑生成配方新增自动材质分配规则。

当前 3D MCP 共用同一材质库与刷面操作：

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_surface_materials","arguments":{"category":"墙面／石砌城墙","limit":50}}}
```

返回的材质 ID 例如 `pack:default:walls/castle_rubble/material`。先用 `list_object_surfaces` 或 `pick_surface` 取得真实 `target`，再调用 `paint_surface`，传此 ID 和 `mapping:"meters"`。所有 PBR 通道一起保存在面材质快照中；撤销、重做、保存重开、运行时 glTF 和预制件打包均保留它们。缺失任一已引用通道会在绘制前失败，正式保存也检查依赖。单图导入入口 `import_surface_material` 仍只导入颜色图，不是多通道 ZIP 导入工具。

## 屋顶补齐与其他候选

写实红陶叠瓦现由生成材质 `pack:default:roofs/terracotta_plain/material` 补齐，可通过同一分类库和 `paint_surface` 使用。石板叠瓦可作为以后增加的屋顶变体。已购的 [9 Seamless Roof Materials Pack](https://www.fab.com/listings/791b0ad4-acfb-47cb-aa63-c3eb101609e4) 标注 Stylized，未纳入；已购扫描金属屋顶也不适合该城镇。天然岩石地表不能代替真实叠瓦。

[12 Stonebricks Materials](https://www.fab.com/listings/72c3d18a-e321-44a5-a17e-bcbfc52ddadb) 尚未下载验收；当前使用 Castle Wall 扫描覆盖石砌用途。仅提供 Unreal 格式已不再是导出障碍，见下方工具。青漆木限局部装饰，苔藓岩石限岩石/林缘，不能作为所有木梁或整片草坪的默认外观。

## 重建与验收

源码仅保存筛选清单 `tools/fab_default_materials.json` 和本地安装器 `tools/import_fab_materials.py`。安装器不访问网络、不执行下载包内容，仅读取指定图像成员并保留原 ZIP；运行时需已完成下载及存在外部默认包的 `metadata.json`。

```powershell
python tools/import_fab_materials.py --manifest tools/fab_default_materials.json --downloads C:/Users/luna/Downloads --pack D:/code/rmmo_runtime/packs/default
```

`test_world3d_pack_materials.gd` 通过真实 HTTP 验证分类、五通道 PBR、按米重复、法线转换与切线、无副作用失败、保护状态、撤销重做、保存重开、运行时和预制件；`test_world3d_surface_paint.gd` 回归原模型材质、中文路径、自动瓦片、模型预制件搬迁及鼠标刷面。两项 GPU 测试均使用不激活的独立桌面与临时地图，不覆盖用户地图。

`test_world3d_roof_material.gd` 用真实 HTTP 生成中世纪店屋、查询屋顶分类并刷两个坡面，检查法线/粗糙度连接、切线、撤销重做、非法目标无副作用、保存重开和运行时 glTF。后台 GPU 输出整栋、屋顶细节、关闭法线对照和另一光照方向，位于 `review_artifacts/generated_roof/`。原始生图和贴图配置保留在默认包，测试不覆盖用户地图。

早期 `generated_roof/house.png` 仅是屋顶测试，墙面和梁柱仍是纯色。完整材质示例由 `tools/build_medieval_material_demo.gd` 生成，使用外墙石灰抹面、整木梁柱、天然木地板、浅色木窗扇与楼梯、窗玻璃、陶瓦、石基、石板台阶和鹅卵石地面；同一墙体外面刷外墙抹面，里面刷细灰泥；楼板底面为天花，屋顶背面为木材；相邻墙片共享投影基准，木纹沿构件长轴。完整示例开启太阳投影与环境遮蔽，预览与地图路径记录在 `review_artifacts/material_house/`。该脚本是样例内容制作与验收，不会把所有新建筑自动改为同一材质。

历史深色木板、玻璃以及内外灰泥变体的可复原描述保存于 `tools/default_material_variants.json`；`path` 相对于默认包的 `assets/materials/`，`descriptor` 即该材质的 `material.json` 内容。参数变体不增加图片副本，继承各自基底来源。白刷灰泥覆盖原扫描的灰色／蓝灰基色，保留各自不同的法线、粗糙度和 AO；不是把外墙材质直接刷到内墙。


## Unreal 格式原生导出

[导出流程与命令](unreal_material_export.md) 对应 `tools/export_unreal_materials.py` 和 `tools/import_unreal_materials.py`。已通过 Epic 已购库下载 [Wood Material Pack3 / Stone Material](https://www.fab.com/listings/ff8612c9-a38f-4d8c-95d8-5d97282e7fe4)，用 Unreal 5.6 原生接口导出 40 张 4096×4096 PNG（10 组颜色、法线、粗糙度、高度）和 11 个材质的参数记录。精选三款安装为最大 2048×2048，原 `.uasset` 包归档于 `sources/fab/wood/wood_material_pack3/unreal_source.zip`，旁边保留完整导出清单与筛选配置。高度图留在源资产中，本轮不启用位移。

`tools/fab_unreal_wood_materials.json` 记录参数到运行通道的显式映射；使用名称标注 OpenGL 的原始法线，运行时金属度为 0。原材质的颜色、UV、Grunge 和粗糙度重映射参数都保留用于追溯，但复杂着色器未烘焙，Godot 使用经过检查的基础 PBR 图和米制重复。外墙新扫描的原范围为 1×1 米，室内扫描为 2×2 米。木材的 0.8×2.4 米是编辑建议尺寸。

导出和归档属于离线素材制作工具，不是新增 MCP 工具。安装后的材质经当前 3D `list_surface_materials`、`list_object_surfaces`、`paint_surface` 使用；完整示例用真实 HTTP 应用全部 10 种用途，并检验非法调用无副作用、撤销重做、保存重开和 PBR 依赖。

完整示例的窗框四边轻微覆盖洞口边缘，避免与墙洞内面共面；木构版的斜撑连接真实梁柱，立面木架位于外侧，不穿到室内灰泥。地板顶面用拼板，底面用天花灰泥，外露侧边用整木。编辑器与运行时共享太阳阴影偏移，减少薄墙近景的阴影条纹。

2026-10-02 按街屋参考更新了两张示例：默认包 `maps/medieval_material_house/map.gltf` 为灰泥石墙店屋（634 构件、3802 个绘制面），`maps/medieval_timber_house/map.gltf` 为石基木构店屋（606 构件、3634 个绘制面）。在编辑器“资源包地图 → 默认”打开对应名称。外观、室内和临时剖面截图分别位于 `review_artifacts/material_house/`、`review_artifacts/material_house_timber/`。后者可用脚本的 `--timber` 参数重建；两者都验证了真实 HTTP、绘制撤销重做、保存重开和材质依赖。旧示例完整备份于 `review_artifacts/material_house/previous_published_20261002/`，验证源图保留在 cache，每个发布副本的 26 个 glTF 文件引用均已检查。

蓝图 V5 的六栋对比场景位于 `maps/medieval_building_gallery/map.gltf`，由 `tools/build_medieval_building_gallery.gd` 制作。包含单层小店、灰泥石墙店屋、三层窄住宅、木构后院作坊、L 形翼楼和围院旅馆，使用上述十类 PBR 材质，保留颜色、法线及粗糙度等实际通道。新增地下 1 米基础、活动门窗、临街雨棚与老虎窗；房间墙面及楼板底面分别使用室内灰泥和天花材质。完整场景、各栋正背面、开闭对照、地基和室内剖面截图放在 `review_artifacts/building_v5/`。检查截图临时隐藏的地面、墙体和楼层不会写入地图。
