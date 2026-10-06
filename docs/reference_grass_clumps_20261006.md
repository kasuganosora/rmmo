# Blender 宽弧桥头草堆

2026-10-06。用于石桥参考镜头中密实、向外舒展的前景草缘，保留既有 11 款扫描草供零星混植。本轮不修改城镇地图。

素材以 Blender 4.5 创建真实曲面叶片、中脊和散生根部，使用已授权 Quixel Wild Grass / vlkhcbxia 的单片长叶扫描颜色、法线和粗糙度。不是扫描整株放大，也不是整丛公告板。未声称自然物种复原或逐叶复刻动画。

- 母版：`D:/code/rmmo_runtime/art_sources/reference_grass_clumps/reference_grass_clumps.blend`。三款保留 24 段叶弧母版与三档运行网格，每片叶为独立连通几何，可在 Blender 编辑、分离；原 Quixel 来源仍保留。
- 运行源：`D:/code/rmmo_runtime/assets/reference_grass_clumps/`。
- 草堆 A/B/C 高约 0.48/0.57/0.38 m，宽约 1.08–1.18 m。尺寸为本次桥头景观调整，不是参考图可精确量出的尺寸。
- 180–245 片叶，近景 14 段、中景 8 段、远景 4 段；每档保留全部叶片，仅减少曲面分段。近景 10,080–13,720 三角面，中景 5,760–7,840，远景 2,880–3,920。
- 每档单材质，三款共享相同 2K 扫描纹理；无碰撞，近中景原生风动，远景静态。现有 12/25/55 m LOD 与迟滞规则，没有将独立草丛合成不可编辑的整地图网格。

首版因成束直根、亮茎和种植行列感未通过视觉自审，未发布。第二版打散根部，加入 25% 低叶，从下部外弯并保留不齐冠缘，移除过亮茎段的 UV 取样。技术与视觉验收结果及发布清单随后记录于独立 review_artifacts/reference_grass_clumps 目录。

## 最终验收与发布

3 款已发布为默认资源包预制件“宽弧桥头草堆·A/B/C”；完整 `entry`、源 GLB SHA-256 和资源库模型 SHA-256 见 `D:/code/rmmo_runtime/review_artifacts/reference_grass_clumps/published.json`，可直接使用当前 3D 编辑器的原生预制件放置。正式地图未修改，最终街景布局由布置任务另行验收。

最终版对根部使用较暗顶点色，并加入轻微逐叶明度差异。发现 glTF 保留 COLOR_0 但材质未启用顶点色，由主任务修复 `grass_texture_cache.gd` 的草材质导入流程，只处理确有颜色数据的草表面，不改变共享的非草材质。`test_grass_vertex_colors.gd` 逻辑回归通过；本任务完整 GPU/HTTP 复验也已通过（`reference_grass_clumps_test_verified.log`，失败数 0）。保存重开后，三档 LOD 和根部顶点色继续生效。

验收包括：3 款真实导入，单材质面组，PBR/双面/透空，纹理共享，真实 HTTP 工具发现、放置、非法 ID 无副作用拒绝、撤销重做、预制件捕获/放置、保存重开、游戏加载器保留每丛 3 档 LOD、近中景原生风动。模型不带碰撞，发布预制件明确 `collision: none`。

已人工对照 Godot Forward+ 的三款近景、混植低机位、夜间图及 24 段母版/14 段近景同机位对照。散生根部和低叶避免作物行列感，保留宽弧叶的实体侧面与不齐冠缘。近景面数比母版减少约 41.7%，不是把叶片删成稀草；小量亚像素叶尖及高光差异仍存在，不宣称数学无损。对照整图平均 RGB 绝对差 A 约 0.195、C 约 0.218（0–255）；此指标仅为辅助。母版每片叶配有 `Leaf_000` 等命名顶点组，便于 Blender 选择和继续造型。

400 丛压力场景：RX 7900 XTX，1400×850、Forward+、MSAA4+TAA，可见 344 绘制调用、3,024,242 图元；GPU 中位 5.99 ms，风更新中位 1.75 ms。两时刻风动对照有 4,174 像素变化超过 12/255。夜间关主光后正常变暗，没有自发光。这是独立素材密集测试，不是整座城镇帧率保证；布景应使用较少、适量交叠的新草堆替代大量稀草。

证据目录 `D:/code/rmmo_runtime/review_artifacts/reference_grass_clumps/`：`validation.json`、`visual_review.json`、`density.json`、`arch_A.png`/`arch_B.png`/`arch_C.png`、`mixture_day_close.png`、`mixture_night.png` 和母版对照 PNG。所有 GPU 测试均由 `tools/run_godot_background.py` 在不激活独立桌面完成。

偏差：这里提供写实曲面长叶草堆，不复制动画的笔触、每片叶位置或具体植物物种；参考中还存在更低的碎草和灌木，应与既有 11 款素材、后续岸边布局共同形成过渡，不能单凭该密集测试视作街景已完成。

## 同日补充：真实天空下的粗糙度通道修正

完整城镇实机检查发现蓝灰色镜面叶边。独立预览没有实际天空反射，先前预览未暴露这个问题，因此前面的材质验收不能证明粗糙度正确。数据核对发现 Quixel 标量粗糙度实际存于源图 R 通道，Blender 直接把彩色输出连到 Roughness 时，导出的 ORM.G 取到接近零的 G 通道。新草与原野草的错误 ORM.G 均值约 0.28/255，矮草约 0.063/255；叶片因此近似镜面。候选地图 albedo 像素与源模型一致，metallicFactor=0，问题不是地图颜色贴图绑定丢失。

已在 Blender 中明确 `Separate Color: Red → Principled Roughness`。修复后长叶/野草 ORM.G 平均约 0.754，矮草约 0.883。3 款新草堆和原 11 款均保留原几何、叶色、风动及 LOD；14 款 albedo 解码像素逐款完全一致。实际重新打开修复前存档母版与当前母版，顶点/拓扑哈希一致；原件与修复材质节点记录见 `roughness_fix.json`，像素通道比对见 `roughness_channels.json`。两份 `*_before_roughness_fix.blend` 保留。

真实 `WeatherController` 天空、同太阳方向与固定镜头下，`sky_before.png` 重现蓝灰镜面叶边，`sky_after.png` 确认其消除。实机光照下草色仍比无天空局部预览暗，未为迎合预览而改叶色。3 款修复版通过新一轮 GPU/真实 HTTP/保存重开验收，新断言检查粗糙度有效值与运行纹理不超过 2K。3 款新版不可变 GLB 与预制件哈希已更新到 `published.json`，旧不可变文件仍保留，只从目录列表替换旧入口。

修复版 400 丛同配置测试：344 绘制调用、3,024,242 图元，GPU 中位约 5.764 ms，风更新约 1.697 ms。旧母版重开后部分运行图片会还原为 4K，已修正制作脚本的 2K PNG 保存/打包，保证本次材质修复不意外放大运行纹理；原 4K 母版仍保留。

同一粗糙度问题涉及原 11 款草，它们也已重新通过 GPU/HTTP 验收并发布到 `review_artifacts/town_grass/published.json`，完整过程见 [原草丛更新记录](town_grass_20261006.md)。两系列均可按新清单接入最终地图，不再使用修复前清单。
