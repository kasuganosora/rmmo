# 地形坡度、河岸渐变与水渠材质

2026-10-03：在「地形雕刻」面板中选择浅水沙地、深水岩石，按水位及阈值应用到列表地形，或多选若干河床地形与水面后批量应用。整体地形底材用于岸上，局部手刷河床须先清除，避免覆盖人工绘制。启用后雕刻只改变真实高度，材质跟随高度实时变化；不会改几何、洞口、碰撞或河道保留区。

默认参数（米）：

| 参数 | 默认 | 含义 |
| --- | --- | --- |
| water_level | -1.5 | 世界坐标中的水面标高 |
| shore_start / shore_end | 0.25 / 1.3 | 水面以上，从沙开始接回岸上底材至完全恢复底材 |
| rock_start / rock_end | 0.6 / 2.2 | 水面以下，从沙开始混入岩石至完全岩石 |
| bank_profile | natural | 自然河岸：水深与坡度共同决定材质；depth 仅按水深，保留旧版对照 |
| steep_start / steep_end | 40 / 65 度 | 开始露岩 / 完全露岩的世界坡度，普通地形也使用相同默认值 |
| wet_height | 0.3 | 天然河岸及砌石护岸从水位向上恢复干燥外观的高度 |
| wet_darkening | 0 | 天然河岸沙、土、岩的湿润变暗程度（0～0.8）；0 关闭，旧地图保持原外观 |
| transition_width | 1.25 | 土层/碎石自然交错范围（米）；0 关闭，兼容早期坡度模式 |
| edge_noise | 0.3 | 世界空间中稳定的边界扰动强度（0～1） |
| height_blend_strength | 0.5 | 原始材质高度贴图参与混合的程度（0～1） |
| absorption | 0.45 | 水体吸收系数；越大越浑浊 |
| shallow_color / deep_color | [0.24,0.42,0.34] / [0.055,0.16,0.14] | 浅水与深水色调 |

使用同一组覆盖权重混合颜色、法线、粗糙度、AO、金属度，支持每层自己的米制重复尺寸和 DirectX 法线转向。三向投影的法线与材质覆盖规则分离：投影在近垂直面使用真实面方向防止拉伸；材质通过米制范围内的高度场采样计算连续坡度、岸顶与坡脚距离，加上世界空间扰动和土/碎石过渡层，再用各材质的 height_path 调整覆盖。避免把面法线突变直接变成草/岩硬切，也避免沿长三角面把草拖成长条。默认过渡材质为 `pack:default:terrain/natural_dirt/material`，可通过 transition_material_id 更换；没有高度图的材质使用中性值，不把颜色亮度冒充高度。

每块地形只增加与原高度网格对应的 RF 数据纹理（最多 65×65，约 17 KiB，不含驱动开销），雕刻后重建；PBR 贴图仍复用默认包 2K 资源。采样与纹理相位跟随实际坐标，不依赖相机。水位是绝对世界标高：单独升降河床会改变其水深；复制到其他标高后应同步调整 water_level。同分辨率且高度连续的相邻地形共享边缘法线和坡度采样；不同分辨率或真实高度断层不会被自动修补。

天然陡岸的坡度权重优先于沙层：浅水区的陡壁仍会露岩，平缓河床继续按水深混合沙与岩。砌石水渠使用独立 `bank_wetness`，保留墙与渠底原有铺砌材质、米制 UV 和 PBR 法线，只在水位以下变暗、变湿，并在水线上方平滑恢复；不会强行给垂直砌石墙铺沙。普通方块、无建筑/道路关联的河岸/渠底网格可作为护岸；建筑、道路、水面、不可见碰撞块及透明面材质拒绝。

旧地图缺少 bank_profile 时继续使用 depth 模式和原 XZ 投影；缺少 transition_width 时保持原坡度模式，避免自动改动已保存地图。新增配置默认 natural 与 1.25 米自然交错。材质规则只影响外观，不改变坡度、墙体厚度、碰撞和可通行性；这不是完整的水力侵蚀或落石模拟。

水面根据当前视口的不透明深度重建水底位置；光程越长，水越不透明，近岸渐隐。法线复用原有水材质的波纹，UV 为世界坐标每 4 米重复；此轮不包含流向动画、折射、泡沫或水下相机效果。水面旧薄板的侧面/底面隐藏，避免透明后暴露分块侧边；水不投射实体板阴影，不改变现有碰撞配置。面向水平河道，非水平水面在配置时拒绝。

## UI 与当前 3D MCP

`set_river_materials` 接受 `terrain_ids`、`water_ids`、`bank_ids`（各 0～256 个，不得重复，合计至少一个）、`enabled` 及上表参数。启用河床时须提供 `sand_material_id` 和 `rock_material_id`，使用 `list_surface_materials` 返回的 ID。未提供的数值使用默认值，本操作提交完整配置，不是局部 patch。`enabled=false` 移除所选效果，恢复原底材和水材质。只传 water_ids 可以单独调整河水透光；只传 bank_ids 可以给已有护岸增加水线湿痕。

```json
{
  "terrain_ids": ["riverbed_patch"],
  "water_ids": ["river_surface"],
  "water_level": -1.5,
  "sand_material_id": "pack:default:terrain/bright_desert_sand/material",
  "rock_material_id": "pack:default:terrain/icelandic_jagged_slate/material",
  "rock_start": 0.6,
  "rock_end": 2.2,
  "absorption": 0.45
}
```

高度、深度和角度的结束阈值必须严格大于起始阈值。批量操作先验证所有目标、纹理读取、资源根、材质不透明、实际水面标高；任何失败不写记录、不产生撤销、不留下部分成功。锁定、隐藏、隔层、只读、试玩及未完成笔画沿用共享编辑保护。同时指定河床/护岸和水面时，water_level 必须与所有水面实际标高相差不超过 1 厘米。每次批量应用一次撤销；`list_terrains.depth_blend` 返回保存配置。

### 普通隆起地形

地形面板「通用地形 · 陡坡露岩」和 `set_terrain_slope_materials` 使用同一业务操作。参数为 terrain_ids（必填，1～256 个）、rock_material_id、steep_start、steep_end、enabled，以及 transition_material_id、transition_width、edge_noise、height_blend_strength。平缓处保留 `terrain_material`（或原色），陡处露岩，边缘为土层与碎石交错；完全不依赖水位，也不会产生沙滩。启用后继续隆起、下沉、平滑、整平，着色器即时跟随实际世界坡度。停止效果可恢复底材，已雕刻高度不受影响。

```json
{
  "terrain_ids": ["raised_hills"],
  "rock_material_id": "pack:default:terrain/icelandic_jagged_slate/material",
  "steep_start": 40,
  "steep_end": 65
}
```

记录字段为 `terrain_slope_blend`，`list_terrains.slope_blend` 可查询完整配置。局部手刷表面、独立坡度与河床渐变不能叠加，须先停用前一模式；natural 河床已经包含相同坡度规则。更换原有整体草/土材质仍受支持。不对普通地形强制启用此功能，以免改变既有地图的外观。

原生记录存储 `terrain_depth_blend` / `terrain_slope_blend` / `bank_wetness` / `water_depth_effect`。普通 glTF 网格导出保留标准底材作为静态回退；RMMO 的编辑器、同步原生加载器、运行时流式加载器按记录恢复渐变 Shader，分块也保留各表面材质覆盖。其他不识别 RMMO extras 的 glTF 软件只能看到静态回退，不能把它视为渐变材质烘焙导出。预制件依赖收集包含嵌套沙/岩全部 PBR 贴图，非法/缺失资源按原规则拒绝。

验证：`tools/test_world3d_river_materials.gd` 使用临时地图和后台 GPU 桌面，覆盖真实 HTTP 发现、正常/非法批量、保护、无副作用拒绝、幂等、一次撤销重做、UI 读写、雕刻后保留规则、保存重开、预制件贴图依赖、同步与流式运行时、实际法线光照差异及河床碰撞。结果位于 `D:/code/rmmo_runtime/review_artifacts/river_materials/`。

深度重建遵循 [Godot 官方深度纹理说明](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html)，处理反向 Z 及 Compatibility 与 Vulkan NDC 的差异；本轮 GPU 实测使用 Forward+。

## 独立验证地图

`tools/build_river_bank_lab.gd` 在临时地图中通过真实 HTTP MCP 构建、编辑、保存重开和运行时加载，验证成功后保存至 `D:/code/rmmo_runtime/maps/river_bank_lab/map.gltf`。这是独立测试地图，不覆盖 `medieval_river_town`；脚本校验原城镇 SHA256 保持不变。使用 `tools/run_godot_background.py` 在独立桌面运行，截图和日志位于 `D:/code/rmmo_runtime/review_artifacts/river_bank_lab/`。

场景包含 A 缓坡河道、B 旧版陡岸对照、C 自然陡岸、D 真正 90° 的砌石水渠，以及 E/F/G 用隆起笔刷生成的约 24° / 75° / 87° 地形。地图书签可直接定位各组。验证涵盖工具发现、保护与非法输入无副作用、撤销重做、UI、雕刻、预制件依赖、原生保存重开、运行时材质与水渠碰撞；GPU 色标采样检查同水深的沙/岩差异、陡崖顶部/中部/底部无草条带、平顶保留草地，以及水线湿痕。

地形仍是高度场：近垂直自然悬崖受网格分辨率限制，不能产生倒悬或洞穴；真正垂直的人工护岸使用独立网格。本功能不会增加几何细分或位移。2K PBR 贴图由材质库复用，无须为每块地形生成贴图。

## 研究依据与取舍（2026-10-03）

- [GPU Gems 3，1.5 Texturing and Shading](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-1-generating-complex-procedural-terrains-using-gpu)：三向投影解决任意朝向表面的 UV 拉伸，但不能单独解决地表类型之间的分界。
- [Terrain3D Shader Design](https://terrain3d.readthedocs.io/en/stable/docs/shader_design.html) 与 [main.glsl 的 accumulate_material](https://github.com/TokisanGames/Terrain3D/blob/master/src/shaders/main.glsl)：参考其连续覆盖、贴图高度参与权重及 PBR 一致混合的设计。沿用本项目高度场和原生记录，未安装或替换为 Terrain3D。
- [Ferraris、Tian、Gatzidis 2012：Feature-based probabilistic texture blending](https://onlinelibrary.wiley.com/doi/full/10.1002/cav.1460)：论文指出线性混合会使石块等特征半透明，提出按特征整体选择。本实现采用较轻的高度混合与空间扰动，不声称复现其特征分割或概率算法。
- [Argudo 等 2017：Coherent Multi-Layer Landscape Synthesis](https://perso.liris.cnrs.fr/eric.galin/Articles/2017-landscape-synthesis.pdf)：研究高度、坡度、土壤、植被等层之间的一致性。我们的土层/碎石位置仅是受此启发的局部近似，未实现论文的样例字典合成。
- [Peytavie 等 2019：Procedural Riverscapes](https://www.cs.purdue.edu/cgvlab/www/publications/Peytavie19CGF/)：河床截面和水流应随河流类型变化，支持继续区分天然河道与人工水渠。侵蚀几何、沉积体积和复杂水流仍属于后续工作，不能用着色器冒充。

`tools/import_terrain_blend_heights.py` 从已购原始压缩包补出草地 Bump、沙地和岩石 Displacement 2K 图，原字节保留；不从颜色或法线猜测高度。height_path 同步纳入校验、资源根限制、预制件依赖和 MCP 材质目录。测试增加同机位、同几何、同 PBR 的 `edge_before.png` / `edge_after.png`，便于单独比较算法。


## 材质采样与缓存优化（2026-10-03）

先计算覆盖和高度混合，随后仅为权重大于 0.00001 的层采样完整 PBR。单层区域跳过高度混合；缺失的颜色/粗糙度/AO/金属度使用原默认值，非金属层不读取金属贴图，零法线强度不采样法线。纹理精度、法线方向、覆盖参数与三向投影保持原逻辑，不通过减少贴图分辨率换性能。

材质缓存上限仍为 128，但改为逐个淘汰最近最少使用项，避免达到上限后全部清空。地形缓存使用结构哈希索引并核对完整签名，哈希碰撞视作未命中，不会误用其他地形的高度场；命中不再将数千高度序列化为长 JSON。签名独立复制，雕刻后的记录修改不会污染旧缓存。

`tools/benchmark_terrain_materials.gd` 对捕获的前版 Shader 和当前 Shader 作同视口 GPU 计时，1080p、真实 2K PBR、固定几何/灯光、AB/BA 两轮，每次预热 60 帧后取 100 帧，并核对画面误差。包含草地近景、陡岸近景、49 个共享网格分块及 49 个独立高度场/网格/材质分块；测量范围不含天空、水、物理和编辑器，不能换算整城 FPS。基线 Shader 位于 review_artifacts 下，不参与产品运行；`performance.json` 保存基线哈希、GPU、median/p95、缓存命中耗时和结果。

风化造型通过 [共享地形笔刷](world_editor_terrain_sculpt.md) 实际搬移高度实现，保持原网格面数与同步碰撞；不能仅在 Shader 中位移而让玩家踩到旧地面。

地形网格重建预计算每个共享顶点的位置/法线，避免每个相邻格重复计算。保留原三角顺序及材质面结构，`tools/benchmark_terrain_mesh.gd` 对实心/带洞 64×64 地形逐项比较顶点、索引、UV、法线和切线完全一致，避免破坏已保存的手刷表面签名。CPU 重建仍在主线程，大笔刷、高格数以及碰撞重建仍可能造成停顿；这轮未实现后台网格构建或几何 LOD。


本机实测（2026-10-03，RX 7900 XTX / Forward+ / 1920×1080，GPU 中位耗时）：

| 场景 | 优化前 | 优化后 |
| --- | ---: | ---: |
| 草地近景 | 0.391 ms | 0.243 ms |
| 已风化陡岸近景 | 0.418 ms | 0.314 ms |
| 49 块共享网格/材质 | 0.397 ms | 0.305 ms |
| 49 块独立网格/高度场/材质（98 draw calls） | 0.449 ms | 0.312 ms |

配对画面平均通道误差最大约 0.0000141（0～1）。缓存命中平均 0.0536 ms；缓存压力测试通过。64×64 实心地形 CPU 网格重建中位数 205.249 → 99.041 ms，带洞 218.066 → 94.671 ms。独立河岸例子为 64×32 网格、半径 14 米、16 轮风化：风化 46.196 ms、网格重建 46.686 ms、碰撞构建 11.187 ms（单次样本，不含全部 UI/保护检查）；最大格数的交互停顿仍需后续优化，不能把 GPU 改善当成编辑笔刷已达到 60 FPS。


## 缓岸草土沙交界（2026-10-03）

自然模式原来的不规则土层只作用于陡坡，缓岸仍然是一条等高线沙带。现在 `bank_profile=natural` 且 `transition_width>0` 时，缓岸也在草地与浅水沉积物之间加入 `transition_material_id` 指定的泥土层，沿用世界坐标噪声与贴图高度混合。高度混合强度同时控制权重锐化，修复强度接近零时仍突然变成硬边的问题。扰动幅度有上限，岸上远端保持底材、深水保持岩石，不改变水位、岸线几何或碰撞。颜色、法线、粗糙度和 AO 使用同一覆盖权重。

UI 与 MCP 共用现有参数：`edge_noise=0` 关闭边缘扰动，`transition_width=0` 关闭交错土层，`bank_profile=depth` 保持旧外观。没有新增隐藏配置或二维工具。新增计算复用自然模式已经求出的噪声，不增加噪声或高度场采样；单层区域仍跳过无效 PBR 层。

`tools/test_gentle_bank_blend.gd` 用实际 GPU 覆盖权重检查缓岸泥土、同高不规则边界、干地/深水隔离，以及上述三个关闭途径。实际城镇的材质应用与 HTTP 验证入口为 `tools/apply_medieval_town_terrain.gd`，运行时验证为 `tools/verify_medieval_town_terrain_runtime.gd`。

天然岸湿痕使用真实世界水位与各材质权重，在水下变暗并轻微降低粗糙度；水线上方在 `wet_height` 内平滑恢复，不染暗岸上草地及农田区域。该效果复用现有着色器，不增加网格、贴图或透明绘制层；地面合批使用同一套世界坐标规则。编辑器面板与 `set_river_materials` 共用校验、保护和撤销。旧记录缺少 `wet_darkening` 时关闭；如需启用，提交完整河岸配置并设置该参数。
