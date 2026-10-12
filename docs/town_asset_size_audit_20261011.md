# 城镇模型体积与纹理成本专项审计（2026-10-11）

状态：**资源侧首批候选与隔离验收完成，等待程序与模型合并后的整体验收。** 已审计全部32项，交付11个首选资源、10个严格无损回退版本，以及7个独立LOD拾取标记候选。正式地图、原hash资产、母版和生产缓存均未替换；本轮未修改加载预算、`load_job`、准备队列或驻留所有权代码。

最终选择与完整SHA以 [candidate_handoff.json](../review_artifacts/town_asset_size_audit_20261011/candidate_handoff.json) 为准，资源根目录另有同名副本。早期构建记录中的 `pending` 是构建时状态，不能代替此最终交接清单。11个首选共减少源文件 **1,497,622,136 B（约1.395GiB）**；其中10件纯无损清理贡献 **1,459,417,456 B（约1.359GiB）**。这是替换后可减少的资源读取量，不是当前已释放的磁盘空间或显存；原版仍保留。

## 口径与范围

当前地图SHA：`779c513dc5433ddbe66d018471a8a505260e161d1656c690a00cde2675fb7a7f`。交接清单为 [32项外部模型](../review_artifacts/town_large_asset_art_handoff_20261011.json)。已对全部源SHA复核；32份固定native外部模型共897个地图实例，另有3份小型石桥外部模型/5个实例，合计35条GLB路径/902实例。重复实例共用资源，不能把一份模型纹理内存乘以实例数；实例数影响绘制、剔除与碰撞。

彩旗 **2.480GiB是full-peak保守准入预算**，源GLB为75,581,472字节（72.08MiB），native文件100,047,566字节。现有footprint记录CPU图片264MiB、GPU RGBA含完整mip预算384MiB，几何相关不足1MiB。均与实测RSS/VRAM、完整地图打开时间区分，不以磁盘压缩率代替解压/显存收益。

现用GLB有18张2K图、6个网格、6材质、9,056份唯一三角面。九面旗帜的独立节点、风场、碰撞和全部几何保持。当前外部GLB直接导入及编译为ImageTexture，PNG字节解码为RGB/RGBA；本轮沿用已支持的PNG，不将WebP/JPEG文件压缩说成显存压缩。项目 `runtime_texture_cache` 的上传准备会将RGB8转为RGBA8，ORM的G通道才是粗糙度，不可直接换单通道图却继续读取G/B。尚未实施BCn/KTX2等额外格式管线。官方机制参考：[图像导入与压缩](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)、[GLTFDocument图像格式](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html)。

## 无损清理验收

输出根：`D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/`。母版和当前地图实际使用文件保留，未覆盖hash命名资产。审计脚本、证据位于 `review_artifacts/town_asset_size_audit_20261011/`。

|资源|源GLB MiB：原→无损候选|隔离SCN MiB：原→候选|结论|
|---|---:|---:|---|
|橡树 9ba5457e|210.53→41.22|53.01→53.01|Courtyard/Street是分组名；实际是橡树|
|StreetSpire 42028074|408.37→45.16|61.19→47.45|另合并7份逐字节相同的瓦片法线|
|花园墙 b3d6babb|143.86→20.08|26.19→26.19|保留29个地图实例的复用关系|
|高石柱 510592a4|142.74→19.66|26.01→26.01|材质、选择与碰撞语义不变|
|中石柱 389bb6a0|142.71→19.65|26.01→26.01|同上|
|蓝色长幡 83c1f150|142.50→19.37|30.65→30.65|保留独立风场节点|
|铺展灌木|130.21→20.87|35.63→35.63|同时保留本行无损版及下述纹理候选|
|高灌木|129.78→20.70|35.55→35.55|同上|
|圆灌木|129.35→20.53|35.48→35.48|同上|
|Foliage boxwood|56.74→17.74|34.72→34.72|同上|

10项全部通过引用图、buffer字节、节点/extras、网格及材质检查；真实导入后，12组固定相机/风时刻截图均逐像素相同。无损清理主要降低GLB读取、SHA校验和冷导入负担。原native已去除多数未用图片，不能按GLB压缩比例推算显存；StreetSpire的重复图合并是例外，CPU图片104→80MiB、GPU RGBA+mip预算144→112MiB。

完整366张图片声明均仍有texture.source引用；其中236张不从mesh实际材质可达，细分为106张仅旧材质使用、130张无任何材质使用，编码数据约938,435,365 B。按可达图成套清理及重映射，未按名字直接删图片。32项与程序侧新审计完全一致，见 [口径复核](../review_artifacts/town_asset_size_audit_20261011/reachability_reconciliation.md)。当前参与清理的资源没有活跃扩展对象或图片/几何共用bufferView；未把这点泛化为任意未知扩展/extras都安全支持。

## 纹理候选选择

|首选|源GLB MiB：原→候选|CPU图片 MiB|GPU RGBA+mip预算 MiB|full-peak准入 GiB|
|---|---:|---:|---:|---:|
|彩旗 quality|72.08→66.43|264→169|384→257.33|2.480→1.645|
|铺展灌木 pbr2k_albedo4k|130.21→13.18|192→96|256→128|1.776→0.932|
|高灌木 pbr2k_albedo4k|129.78→13.00|192→96|256→128|1.774→0.930|
|圆灌木 pbr2k_albedo4k|129.35→12.83|192→96|256→128|1.772→0.928|
|Foliage boxwood pbr2k_albedo4k|56.74→10.05|192→96|256→128|1.752→0.908|

彩旗首选 `pennants/bridge_long_pennants_quality.glb`，SHA `0360c0152eb2495741e08837c80f3fc4c583b1334ee7e55c3eb89deabca02d3e`。保留全部2K基色和布料法线；结构恒值法线改为1像素，五张近乎相同的布料ORM共享并缩至512。ORM共享前仅8–11个通道值差一级，仍明确属于有界非无损改动。近景织物/白边暗纤维、静止和风动轮廓未发现可见退化；12张主视图和6张地面投影图最大RGB差均为1/255。原图的远景织纹摩尔纹仍存在，本轮没有解决过滤闪烁。

彩旗 `balanced` 虽可降到18.29MiB和97.33MiB纹理预算，但近景白色边框更亮、更平、织物微对比减弱，**不采用**。`detail/shared` 没有额外完成GPU验收，被quality方案取代，不能自行接入。见 [balanced退回记录](../review_artifacts/town_asset_size_audit_20261011/pennant_balanced_visual_review.json)。

四个植物首选保留4K基色及透明度的原始PNG字节，仅法线/ORM降到2K；alpha cutoff、几何、LOD及风场不变。近景检查保留叶脉、细枝、叶缘；数值上有法线/粗糙度着色差异，不能称无损。全图2K的 `all2k_coverage` 在铺展灌木近景中有叶脉变软和细叶缘变化，即使总透明覆盖率相近仍**不采用**；其余全2K变体未自动放行。完整人工观察及限制见 [画质记录](../review_artifacts/town_asset_size_audit_20261011/selected_visual_review.json)。

三种灌木的有效图片逐图相同，boxwood与它们共享法线/ORM但基色RGB不同。公共关系已记录，GLB继续内嵌PNG，没有改成不受支持的任意外链。现行跨资源纹理共享开关与最终收益由程序側验收，不能把以上单资产预算按实例数相乘，也不能在启用共享后简单求和当实际VRAM。

## LOD、碰撞与独立拾取候选

本轮没有盲目减面。彩旗唯一几何仅9,056三角形，其主要矛盾是纹理；现有植物LOD、树干和独立枝干保留。橡树高模及草实例的几何/遮挡成本仍在全32项排序中，待整图剖析确认后再单独做轮廓对比。

[editor_picking_manifest.json](D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/editor_picking/editor_picking_manifest.json) 提供7件仅新增元数据的候选：橡树树冠、三灌木、arch_A/B/C草。每组恰好一个LOD0 `canonical`，共7个canonical和11个 `render_lod`。协议为节点 `extras.rmmo_editor_picking={version:1,group:资产内唯一名,role:canonical或render_lod}`；其余render_lod本来都为 `rmmo_collision:none`。树干block、独立枝干和原始LOD字段未改；单网格boxwood没有伪造LOD组。

整个BIN逐字节相同，去掉新增字段后JSON与源完全相同。该组候选基于无损版，**与纹理候选分开测量**，不要用它替换纹理候选后误以为两种收益已经叠加。消费此协议的程序开关、HTTP选择/刷材质、保存重开仍待加载侧统一验收；`none`不等于不可选择，不能跳过原精确canonical。

## 已完成验证与接入边界

- Godot 4.7.2 Forward+、RX7900XTX，私有非激活桌面运行；没有抢焦点或角色遮挡。固定1400×1000、相机、灯光、曝光，近/中/远/细节各3个风状态；首选纹理版另拍6张地面投影对照。人工检查为记录中的视图抽查，未声称逐帧观看连续风动画。
- 各候选真实GLTF导入、生产后处理、SCN保存重开、资源依赖检查、Compiled/Footprint/Preparation读取及非纹理语义比较通过。隔离native报告记录真实图片数、CPU像素、GPU预算和draw/primitive计数；没有把进程全局纹理计数称为单资产实占显存。
- 彩旗quality另通过16项隔离失效检查：仅修改测试副本的合法JSON extras，使源SHA/长度变化，旧Compiled、Footprint、冻结Preparation均拒绝；恢复后再次可读，源文件SHA不变。见 [缓存失效记录](D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/review/pennant_quality/candidate_cache_invalidation.json)。早期旧generator被正确拒绝的记录保留，不重新标签冒充新缓存。
- 加载代码在本次验收期间并行变更，各报告保留当时generator。**本轮隔离数据不作为最终加载时间基准。** 最终固定代码和资源SHA后，加载侧统一离线生成native/footprint，分开测程序开关和资源替换，再做游戏/编辑器整城性能、保存重开及HTTP操作验收。本轮无整图FPS/RSS提升结论。

## 剩余优先级

1. 先完成上述11件候选与程序修复的联合验收，再替换正式引用；当前只交付可复查资源，未发布。
2. 高频草实例共631个，接下来评估剔除、LOD拾取及纹理共享的实际收益；不要先删LOD或合并为不可独立编辑的大块。
3. 其余小型布料/烛台等部分低面数资源仍有较高保守预算，可沿通道/尺寸审计继续优化；已有模型不需要一律减面。
4. 全32项逐项排序、原路径和SHA见 [完整清查](../review_artifacts/town_asset_size_audit_20261011/inventory_report.md)。额外59张独立纹理共216.30MiB、无逐字节重复；生成/冻结房屋地形定义另计，没有因不在本32项中遗漏其存在。
