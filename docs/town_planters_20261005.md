# 街区花池 Blender 审阅样品

2026-10-05 最新用户确认：约 40% 减面的黄杨贴图版本“没问题，就这个版本”，美术版本选定为 `boxwood_review/optimized/town_planters_boxwood_optimized.blend`。用户再次明确先别接入游戏；此确认不包含游戏集成或地图摆放授权。

用户要求依照城镇设定及两张补充图制作花池，并明确：**先不要接入游戏；须用户确认无误并明确同意后才接入。** 当前仅为离线美术样品，未注册资源包、未修改地图、未新增 UI/MCP 能力。不得把 Blender 预览当作游戏内验收。

用户允许程序化生成；需要外部素材时先查 Fab 已购，没有合适素材再用生图制作。本版石块、叶片与花朵均为 Blender 生成的原创几何，没有使用外部资产或生成图片。

## 叶片真实性复核与 Fab 候选

用户指出当前叶片纹理不够真实，要求查 Fab。2026-10-05 已核对登录账户的库与商品详情：

- 优先候选：[Quixel Megascans Boxwood / rjepadp2](https://www.fab.com/listings/dfbfdeee-6a02-47c7-bac9-fa3a7eeffa03)。页面显示“已保存在我的库中”，4K 原包已下载并解压至 `D:/code/rmmo_runtime/art_sources/town_planters/sources/boxwood_rjepadp2/`。实包包含 BaseColor、Opacity、Normal、Roughness、Translucency、AO、Bump、Cavity、Displacement、Gloss、Specular 共 11 张图及元数据。ZIP 大小 10,283,955 字节，SHA-256 `4101e91dae258238d9341e91f2f3ddd79024144fb1ffcfb13e60fac644ac0e23`。扫描区 0.41 × 0.41 米来自商品说明。
- 该素材是带枝条的叶片图集。颜色图的轮廓外包含扩边颜色，必须结合 Opacity 使用；不能把整张颜色图直接贴到每片叶子。采用时应按枝簇裁区、建立 UV，核对叶片实际尺度、背面透光及透明排序；保留花池长度参数。
- 备选：[3DGardenPlants Glossy abelia 免费样品](https://www.fab.com/library/assets/2c009f5c-4fb1-476c-bbb4-0fba617de0cd)，已购页面显示产品下架但仍可下载，仅 Unreal 格式。本次未下载，未核实内部贴图通道，不作为首选 Blender 图集来源。

当前仅完成素材查找、已购核对和黄杨原包归档；尚未替换 Blender 花池的叶片，现有预览仍是原几何叶片版，未接入游戏。Fab 原始素材保留在审阅源目录，未注册到默认资源包。

### 黄杨贴图审阅版（后续用户授权应用并渲染）

制作脚本 `tools/render_town_planters_boxwood.py` 读取原始花池 Blender 文件，在独立的 `D:/code/rmmo_runtime/art_sources/town_planters/boxwood_review/` 输出候选。替换 01、03、05、06、07 的绿色植物；02、04 的花卉方案保留原版。原始 `.blend`、原始 GLB 和正式地图不变。

黄杨图集按枝条区域映射到弯曲枝簇，连接细木质茎。BaseColor、Opacity、Normal、Roughness、Translucency 五张 4K 贴图分别接入着色器，透明轮廓以阈值裁切。材质作适度提亮以配合街区美术；枝簇尺度为街景可读性放大，不声称与扫描标尺一致。池体尺寸从源 collection 读取，修改长度时先运行原参数生成器，再运行该审阅脚本。

候选源文件 `town_planters_boxwood.blend` 内嵌五张贴图；主视图 `boxwood_L_comparison.png` 对比暖砖与高绿篱 L 形；`boxwood_leaf_detail.png` 展示近景。已通过 Blender 重开、贴图打包/分辨率及 UV 存在性核对；Cycles 审阅材质尚未做 Godot/glTF 等效转换、性能或透明渲染验收，不属于游戏接入。

### 黄杨版本减面候选

用户要求在不降低质量的前提下减面。`tools/optimize_town_planters_boxwood.py` 从已认可质感的源文件生成独立 `boxwood_review/optimized/` 候选，未覆盖原版。每枝扫描卡片从 16 三角形降至 8，保留横向折痕、UV 和原采样顶点法线；细木茎从五边截面减至三边截面。枝簇数量、随机位置、五张 4K 贴图、材质、石砌倒角和土面不变。

| 款式 | 原整件三角面 | 减面后 | 减少 |
|---|---:|---:|---:|
| 浅石长条高绿篱 | 36,168 | 21,588 | 40.31% |
| 浅石转角绿植 | 34,736 | 20,696 | 40.42% |
| 暖砖长条低植被 | 24,494 | 14,774 | 39.68% |
| 暖砖 L 形低植被 | 34,736 | 20,696 | 40.42% |
| 浅石 L 形高绿篱 | 51,266 | 30,206 | 41.08% |

五款合计 181,400 → 107,960 三角形，减少 40.49%。面数为包含石砌和土面的整件统计，不是只统计植物；两款原花卉版本未处理。`geometry_report.json` 提供逐组件数据。

整体与近景均已完成目视对照，当前两个机位未见明显稀疏、轮廓破损或材质质感下降。全图 RGB 平均绝对差为 0.957/255，近景为 6.038/255（含采样、阴影及几何近似差异）；这不是视觉无损证明，也不能替代其他视角的用户美术确认。数值记录于 `render_difference.json`。

减面版 `town_planters_boxwood_optimized.blend` 已重开检查五组植物 UV、自定义法线和内嵌 4K 图。审阅采用与原版相同的灯光、相机、40 样本 Cycles 渲染，输出 `boxwood_L_optimized.png` 和 `boxwood_leaf_detail_optimized.png`。几何形状存在微小近似差异，不宣称数学无损；只能据渲染对比评估可见损失。透明枝卡数量与覆盖面积没有降低，不能把三角面下降等同于帧率或透明过绘开销同比改善。尚未接入游戏。

## 参考与解释

- `references/town_planters_20261005/01_stone_hedge.png`：用户截图；浅色错缝石墙、长条池体、浓密高绿篱。红框是参考区域，不是模型元素。
- `references/town_planters_20261005/02_brick_border.png`：用户截图；暖色砖砌矮花池、窄压顶、低矮阔叶绿植。背景树、房屋及旗幡不属于本次花池模型。
- 现有 `medieval_town_visual_references.md` 的 04、06、12、14 用于河岸、庭院和住宅墙脚空间关系。
- [RHS：How to make a raised bed](https://www.rhs.org.uk/garden-features/how-to-make-a-raised-bed) 用于石材围护、土层与排水的常识核对；不是中世纪历史原型证明。样品为落地开放底部，池内土面低于压顶。

尺寸全部是游戏街景比例的初拟值，不能从截图推导为实测尺寸；尚未进行角色、相机、碰撞或性能验收。

## 七款候选

| 文件名 | 设计 | 池体中心线范围（米） | 含压顶高度（米） |
|---|---|---|---|
| 01_wall_hedge | 浅石长条高绿篱，第一张图的主体方向 | 3.2 × 0.9 | 0.81 |
| 02_window_flowers | 浅石低花池，小花点缀的延伸方案 | 2.1 × 0.8 | 0.45 |
| 03_corner_garden | L 形庭院转角，延伸方案 | 2.5 × 2.5 | 0.63 |
| 04_octagon_flowers | 八角独立花池，延伸方案 | 约 1.8 × 1.8 | 0.63 |
| 05_brick_leaf_border | 暖砖矮墙、低阔叶植物，第二张图的主体方向 | 3.1 × 0.85 | 0.63 |
| 06_brick_leaf_corner | 用户追加：暖砖低植被 L 形款 | 2.5 × 2.5 | 0.63 |
| 07_tall_hedge_corner | 用户追加：浅石高绿篱 L 形款 | 2.5 × 2.5 | 0.81 |

新增两款沿用对应长条款的材质和高低关系，转角使用斜接压顶。独立对比图为同源目录下 `town_planters_L_variants_review.png`。仍只供审阅，不接入游戏。

## 长度调整

编辑 `tools/town_planters_parameters.json` 后重新运行生成脚本。长条款 `length_m` 控制长度；L 形款的 `length_m`、`depth_m` 分别控制两条边的外包络中心线长度，`arm_width_m` 控制池带宽度。砖块、压顶和植物数量按尺寸重新排布，不整体缩放叶片。长度上限 10 米，L 形每条边须至少比池带宽多 0.5 米；八角款本轮保持固定尺寸。

自定义配方通过 Blender 脚本参数 `-- --config <JSON路径> --output <审阅输出目录>` 传入；加 `--no-render` 可只生成模型。Blender collection 的同名属性用于记录尺寸，直接修改属性不会实时重建，须修改配方并重跑脚本。当前未提供游戏编辑器中的长度控件。

已用独立输出目录验证：长条长度 4.6 米、暖砖 L 形 3.8 × 2.1 米、高绿篱 L 形 2.2 × 3.6 米。重开生成的 Blender 文件，读取石砌网格实际包围盒，含压顶尺寸与参数加 0.245 米的预期一致（允许倒角交接 0.02 米误差）；未以整物体缩放代替重建。验证稿位于源目录下 `length_validation/`，默认审阅稿仍保持表内尺寸。

石墙沿中心线有厚度，实际外缘比表中范围大约 0.245 米；植物轮廓另有伸展。造型变体是本轮提案，不是用户已批准的设定。

## 文件与复现

- Blender：`D:/code/rmmo_runtime/art_sources/town_planters/town_planters.blend`。
- 总览：同目录 `town_planters_review.png`。
- 单件审阅 GLB：同目录 `review_exports/`，原点位于地面中心，glTF 为 Y 向上，米制。
- 统计：同目录 `mesh_stats.json`。
- 配方：`tools/build_blender_town_planters.py`，Blender 4.5 后台执行。

Blender 文件以七个独立 collection 排列展示，石砌、土壤、植物分别保留；`REVIEW_STAGE` 为审阅灯光、相机和地面，不进入单件 GLB。材质用真实几何叶片及基础色，不依赖 Blender 程序纹理。当前用途是造型审阅，后续接入时仍需按确认结果处理材质、LOD、碰撞、资源注册及实际街区验证。
# 2026-10-05 补充：高植物花坛离线样品

用户反馈缺少参考中明显高于池沿的高密灌木。新增直线 `08_tall_plant_straight` 和 L 形 `09_tall_plant_corner`，不覆盖之前确认的优化版，不接入游戏。

- 脚本：`tools/build_blender_town_tall_planters.py`，输入为已确认的 `boxwood_review/optimized/town_planters_boxwood_optimized.blend`。
- 输出：`D:/code/rmmo_runtime/art_sources/town_planters/boxwood_review/tall_plant_review/town_tall_planters.blend`，同目录总览、近景和几何报告。
- 延续已购 Quixel Boxwood 贴图和每枝 8 三角面的叶片卡，不缩放叶片；新增中上层枝叶，根部保持在土壤中，冠顶有高度变化。
- 总高实测直线 2.541 m、L 形 2.482 m。当前整体三角面分别 47,208、67,726；因增加植物体积而增加总面数，不声称与矮株版本同预算。
- `--extra-height` 控制相对原植被新增高度，默认 0.72 m，允许 0.2–1.2 m。池体长宽继续来自既有花坛参数，修改长宽后需重建原花坛、扫描叶片版及优化版，再运行本脚本。
- 美术待用户验收；未注册游戏资源、未改地图。
