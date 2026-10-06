# 陶瓦色彩修订

用户指出屋顶相对设定图偏灰，并授权调整。参考 `references/town_bridge_street_20261005/01_bridge_to_festival_street.png` 的暖橘红屋面，仅调整陶瓦色图，不改建筑布局、几何、UV、碰撞、楼层隐藏或全局光照。

原材质为 `roofs/terracotta_plain`，平均色偏棕橙、灰褐斑驳较强。正式图粗糙度 ORM.G 平均约 0.77，基础乘色为白色，没有此前草素材的近零粗糙度错误。

使用内置 image_gen 编辑已有色图，新增独立资源 `D:/code/rmmo_runtime/packs/default/assets/materials/roofs/terracotta_warm/`；旧材质完整保留。新图保持原方形瓦片布局，法线及粗糙度逐字节复用，未新增着色器或渲染表面。生成图会有微小纹理细节变化，不宣称逐像素仅作色彩变换；固定机位屋顶近景检查瓦缝对应关系。

作者及验收脚本 `tools/adjust_town_roof_color.gd`：正式图中 34 栋建筑、51 条冻结预制件记录使用该陶瓦。逐条解码冻结数据，确认除指定 albedo 路径外所有数据相等，并验证依赖完整性。临时单栋使用正式地图相同太阳及环境光参数拍摄 before/after，包含近景、整栋和反面；这是局部材质对照，不是完整城镇运行截图。临时原生保存重开验证完成后才能发布；发布核验正式基线和新图哈希，整批撤销重做，原生原子保存并重开核对。

报告、对照图及发布凭据：`D:/code/rmmo_runtime/review_artifacts/roof_color_20261006/`。以 `published.json` 表示正式地图已完成更新。

原生发布及重开已通过：34 栋、51 条记录，失败数 0，正式图 SHA-256 `8b181564b95525083076292e511d3f6ea9189bbc9ddcabb29794185e1456fe3c`。新旧色图均为 1254×1254，平均 sRGB 从 (160.3,94.3,66.6) 调整至 (198.2,94.9,52.6)；法线和粗糙度文件 SHA-256 与原版相同。没有更改网格、表面数量或纹理分辨率。

发布后用 `tools/review_town_roof_color.gd` 从正式图启动完整游戏，哈希及加载检查通过，`game_review.json` 失败数 0。人工复核 `game_house_after.png` 和 `game_back_after.png`：前后屋面均保持暖色、受光与背光层次不同，周边多栋屋顶使用新版。所有 GPU 验收均通过不激活独立桌面的后台启动器运行。

## image_gen 提示词

Edit image 1 only: a production albedo texture for realistic red terracotta roof tiles. Image 2 is COLOR PALETTE reference only, specifically its warm vivid orange-red roofs. Preserve image 1 exact orthographic square composition, every tile edge, seam, chip, surface pore and tile arrangement pixel-aligned as closely as possible: its normal map must remain aligned. Change only coloration: make fired terracotta warmer, brighter, red-orange and more saturated, reduce gray-brown muddy mottling without removing realistic fine clay surface texture or gentle tile-to-tile variation. Target typical broad tile color around sRGB (195,87,47) to (212,104,56), warm copper orange-red, not neon or painted glossy. Preserve dark tile joints. Flat albedo, no new directional lighting, no sheen, no text, no borders, no perspective, no new tiles. Output same square texture only, not a scene or comparison. This is a color correction of existing realistic texture, not anime style.

输入 1：原 `terracotta_plain/albedo.png`；输入 2：上述桥街设定图。原始生成输出为 `C:/Users/luna/.codex/generated_images/01a10fd2-fe81-7772-8270-8bdcb713321f/exec-ee148206-3244-494b-a55d-1b0e567655ed.png`，项目使用资源包中的副本。
