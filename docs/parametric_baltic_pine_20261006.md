# Baltic Pine 参数化与减面 · 2026-10-06

## 编辑器原生树形参数（最新交付）

默认资源包提供“参数化松树·小型 / 成熟 / 倾斜”三款预制件。选中后在“属性”里的“参数化松树”面板调整数值，点击“应用树形参数”。用户要求移除固定版本以避免混淆，已从素材库移除三个旧固定预制件及三个旧模型入口，只保留三款参数化入口。已放置的旧树不会自动转换，其底层依赖文件保留以免地图失效。树形生成在 Godot 内完成，游戏运行与编辑不需要安装或启动 Blender。

| 参数 | 范围与语义 |
| --- | --- |
| 树高 | 2～25 m，模型局部高度；物件整体缩放另算 |
| 冠幅倍率 | 0.5～1.8 |
| 树干粗细倍率 | 0.5～2 |
| 裸干长度 | 0.1～8 m，按模板枝冠参考起点定义，必须小于树高的 80% |
| 顶部倾斜 | -2～2 m，模型局部 X 方向，可再旋转物件 |
| 枝簇密度 | 0.4～1.5；1 为验收版，低于 1 筛选完整枝簇，高于 1 增加枝簇副本并增加面数 |
| 随机种子 | 0～100000；0 保留原排列，其他值改变枝簇朝向和筛选，非全新植物学拓扑 |

这套能力沿用已验收的 Fab Baltic Pine 模板、583 个枝簇、贴图和三级 LOD；不是重新模拟树木生长。风动继续使用原有受风面板和环境风场。近中远三档采用同一枝簇筛选与形变规则，树干碰撞和包围盒同步生成。默认参数的近景仍约 4.83 万面；密度增加不能继续按这个面数估计。相同源模型和参数复用生成网格及材质，最多缓存 48 个网格结果；不同种子/参数需要不同几何，应复用有限变体来布置密集绿植。

MCP 新增 `get_tree_parameters {id}` 和 `set_tree_parameters {ids, settings}`；后者支持部分字段、1～32 棵，整批先校验再一次撤销，UI 共用同一实现。隐藏、锁定、固定建筑、缺失配方及非法值拒绝且地图无副作用。`tree_settings` 随地图和另存预制件保存；UV2 保存枝簇标签，显式 `rmmo_tree_recipe` v1 提供模板尺寸/枝簇连接点，不按文件名识别普通模型。

验收：`tools/test_parametric_tree.gd` 真实 HTTP 测试失败数 0，覆盖发现、参数修改、无副作用失败、保护、批量原子性、UI 应用、撤销精确恢复、重做确定性、参数预制件及依赖保存重开、相同参数共享几何、运行时两棵共六档 LOD 和更新后的树干碰撞。本机测试最大单次参数修改 460 ms；不是全部参数/32 棵不同模板的耗时保证。后台 GPU 自审检查原版、默认、修改及 1.5 密度四张同镜头图，默认与旧版平均 RGB 差约 0.23/255，轮廓/间隙未见明显变化，不宣称逐像素无损。

证据：`D:/code/rmmo_runtime/review_artifacts/pine_parametric/`。构建入口为 `export_pine_branch_map.py`（只读 Blender 母版）、`build_pine_parametric_assets.py`（保留原几何/贴图并附加枝簇数据），发布入口 `publish_parametric_pine.gd`；目录清理凭据 `retired_fixed_catalog.json`。发布后通过真实 HTTP 验证三款可搜索、可放置、参数面板可见，见 `library_check.json` 和 `inspector.png`。原高精度母版及固定资源文件未改，用户地图未修改。以下段落为之前各阶段的历史记录。

最新游戏交付为 V6：`D:/code/rmmo_runtime/art_sources/bridge_street_kit/baltic_pine_procedural/baltic_pine_game_v6.blend`，原生展开 48,308 三角面，583 个实例及程序化控制保留；三级 LOD 在导出时生成。三款已更新共享资源库，用户地图未修改。用户允许降低针叶微观精细度，以游戏视角不结块为重点；视觉取舍与性能证据见 [V6 验收](pine_editor_integration_20261006.md)。下文 V5 及母版为历史记录。

## 后续 V5 簇级减面与编辑器交付

已按用户“同层邻近叶子共用面”继续制作细叶簇版本，保留原母版。最终 V5 为 `baltic_pine_dense_cards_v5.blend`，每棵 2,195,732 三角面，三款已加入共享编辑器库，未布置进用户地图。薄叶透光、真实 HTTP 验收、原母版对照及较高的首次放置/保存耗时，统一见 [V5 接入与自审记录](pine_editor_integration_20261006.md)。下文“不接入”的描述为前期高精度母版阶段状态。

## 再次加密：V3

用户圈出上部冠层的横向空隙，要求继续加密。当前修订为 `D:/code/rmmo_runtime/art_sources/bridge_street_kit/baltic_pine_procedural/baltic_pine_dense_v3.blend`，V2 保留供比较。三款预设将 rooted needle-bearing branch 的尺寸从 1.6 增至 2.5，扩大枝簇覆盖以缩小层间空隙；并非新增针叶数量。保持裸干缩短 0.50 m、583 个共享实例、原版/优化版切换及风动参数。原始独立网格与三角面数量没有因本轮放大而增加。生成脚本为 `tools/revise_blender_pine_dense_v3.py`；检查和同条件渲染文件使用 `dense_v3_` 前缀。

## 用户修订：加密树冠、裸干缩短 50 cm

新版文件为 `D:/code/rmmo_runtime/art_sources/bridge_street_kit/baltic_pine_procedural/baltic_pine_dense_v2.blend`，旧版单独保留。三款预设同步修改：从各自连接点将带针叶枝簇尺寸从 1.0 调至 1.6，扩大针叶覆盖、减少冠层空隙；不是新增 60% 的针叶数量。共享实例和原有减面模块保持不变。

新增 `Bare trunk shortening (m)` 参数，默认 0.5。根部保持地面原点，主干下段平滑压短，所有冠层及枝簇连接点统一降低 0.50 m，避免通过整体缩放压扁树冠。583 个枝簇的降低量逐个核验，误差为 0；三款预设均应用该值。修订脚本为 `tools/revise_blender_pine_dense.py`，检查记录与预览使用 `dense_v2_` 前缀。

## 来源与交付范围

用户要求补充松树形的写实树，并在找到后完成程序化和减面。已从 Fab 已购库下载 [Quixel Megaplants: Baltic Pine](https://www.fab.com/listings/a2b04e81-5075-479f-a9d2-4940022f330a)，USD ZIP 完整性检查通过。原始 A/B/C/D 和 Foliage USD 保留在 `D:/code/rmmo_runtime/art_sources/bridge_street_kit/sources/baltic_pine/`，本轮使用 D 型作为分层松冠模板。

母版：`D:/code/rmmo_runtime/art_sources/bridge_street_kit/baltic_pine_procedural/baltic_pine_parametric.blend`。选中 `BALTIC PINE | editable parameters`，修改原生 Geometry Nodes 参数，无需 Python 自动运行。构建和验证脚本为 `tools/build_blender_parametric_pine.py`、`tools/verify_blender_parametric_pine.py`。

## 参数和材质

- 树高、冠幅、树干粗细、带针叶枝簇大小、冠部抬升、倾斜、随机种子和不规则度均可调整。
- `Twig retention` 默认 1，保留全部 583 个枝簇；降低该参数是用户选择的疏密变化，不计入本轮减面结果。
- `Wind (m)` 默认 0；可设 0.03–0.06 并播放时间轴预览树体摆动。它不等于游戏风场已接入。
- `Optimized` 切换原版和减面版，同用材质和造型参数。原始模块保留，583 个枝簇共享网格，只有主干骨架实现网格。
- 种子改变连续形变和可选枝簇筛选，不生成全新的植物学分枝拓扑。三款预设是同一模板的形态变体。
- 源 USD 没有贴图。树皮复用项目已购 Fab `4K Realistic Outdoor Materials` 的 `outdoor_bark` 基色、法线；原图随母版打包。针叶采用原始实体轮廓，重建深浅绿、微表面、粗糙度与适度透光，不使用阔叶叶脉图案。重建材质不是 Quixel 原始扫描贴图，通用树皮也不是专门的 Baltic Pine 扫描树皮。

## 优化与验收边界

枝簇仅有限融并近乎共面的内部边，阈值 0.01 弧度，保护 UV 与材质边界；主骨架另保守减面。原版等效三角面 259,540,428，减面后 244,265,030，减少约 **5.89%**；共享独立网格合计 3,287,142 三角面。不能将共享几何量当作整树绘制面数。

该文件是 Blender 高细节母版。针叶数量巨大，即使保留共享实例，直接展开导出仍然很重；本次不是游戏 LOD、GPU 性能或游戏风场转换的验收，也没有将这株松树写入游戏资源库或地图。

与 `medieval_town_visual_references.md`、`bridge_street_asset_review_20261005.md` 对照：遵守写实、自然不规则轮廓、保留母版及光影对比的要求。松树是用户追加的树种方向，原动画截图没有提供明确树种测量依据。默认主冠约 10 m 和三款预设尺寸属于项目调整，不是实物测量值。

同条件全树、树干、逆光、针叶近景对比图及参数检查结果保存在母版目录。最终审查结果见 `optimization_review.json`；图像差异统计仅辅助目视验收，不宣称数学意义无损。
