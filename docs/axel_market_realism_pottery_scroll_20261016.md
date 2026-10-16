# 阿克塞尔摊棚：陶器与纸卷货品写实修复候选

日期：2026-10-16。最终 `v6` 已完成真实 native、近中远及细节图审，发布到正式素材库，并通过实际目录放置、选择、撤销重做和保存重开。完整身份、资源成本和限定通过范围见[统一复验报告](axel_market_realism_review_20261016.md)。棚布微纤维、木材端纹仍独立待细化；本轮未替换正式地图实例。以下保留作者模块和旧候选的历史过程，旧“待验”按最终报告解释。

最终修正补充：作者四边面 CPU 间隙不等于 GLB 三角形间隙。v5 实际导出仍有包边穿插，v6 对真实导出三角形修复并重拍通过；纸卷端面另与卷面分离平滑法线。当前游戏 MSAA4 下的正常/侧光和近距离补拍已实际查看，纸层连续。未关闭阴影、删除卷层或改全局质量来通过验收。

## 范围与依据

用户要求继续修复四款摊棚的近景写实问题。本模块仅负责陶器和纸卷货品，保留原棚架、布面、台面、摆位语义和整摊占地。货品形制与纸面符号属于“项目补充设计”，不称为动画官方设定。

源母版为 `D:/code/rmmo_runtime/art_sources/town_market_stalls/town_market_stalls.blend`，SHA256 `07624a3241d64ac86f308955331d2e372312a994a92c3a7bc0f120f109f4fa73`。实际读取 `02_plum_vendor`（陶器，中心 X=-3.6）及 `04_scroll_vendor`（纸卷，中心 X=3.6）及其 `_CONTENTS`。旧图基线是 `D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016/gpu_ab02/` 下各自 `candidate/goods_detail.webp` 等已验有损 Q90、1400×1000 图；这些图只代表旧版外观，没有给新版授予通过。

已观察的旧版问题：七只陶器纵剖轮廓采样过稀，肩部出现折面；材质颜色与光泽过于统一。纸卷原来是实体圆柱加粗黑螺旋曲线，样纸墨迹是九条凸出规则线；后排纸卷高于台面，缺少实际支撑。

实物与材料参考（2026-10-16 查阅；只参考结构和材料，不复制馆藏图片）：

- [Fitzwilliam Museum，Storage jar C.77-1928](https://data.fitzmuseum.cam.ac.uk/id/object/197233)：轮制陶体、外翻口沿、釉面与部分未上釉底部。该器为 1780–1820 年实物，仅作工艺和材料分区参照，不能作为中世纪造型的直接证据。
- [Science Museum Group，Earthenware storage jar A112972](https://collection.sciencemuseumgroup.org.uk/objects/co79703/earthenware-storage-jar)：釉陶储物容器，馆藏尺寸高 273 mm、最大直径 215 mm，用于核对桌面储物陶器的一般尺度；没有宣称模型是该实物复刻。
- [Getty，The Making of a Medieval Book](https://www.getty.edu/art/exhibitions/making/) 与 [Making a Medieval Manuscript](https://www.getty.edu/news/making-a-medieval-manuscript-from-raw-materials-to-illuminated-masterpiece/)：羊皮纸刮薄、拉伸及表面整理，保留轻微不匀和毛囊痕迹；书写在纸面而非浮雕。项目沿原资产 parchment 身份补写细薄哑光纸卷，不将所有历史纸卷一律解释为羊皮纸。

## 实现与烘焙合同

模块：`tools/axel_market_realism_pottery_scroll.py`，接口 `apply(asset_key, collection)`，仅支持 `pottery`、`scroll`。输入是新加载的原变体集合；模块检查唯一 `_CONTENTS`，拒绝已处理集合及货品跨集合共享的输入。仅删除该集合旧货品，再创建新货品。模块不保存母版、不渲染、不导出、不修改全局已有材质。这是货品模块的范围；统一任务另行调整了木架 UV/PBR、棚布和包边，因此完整交付并非只替换 Goods。最终范围与状态以[统一复验报告](axel_market_realism_review_20261016.md)为准。

|部件|候选结构|材料与实际烘焙要求|
|---|---|---|
|七只陶器|48 径向采样；单调三次曲线外轮廓每区间 3 采样、内腔 2 采样；闭合底、真实内壁与圆唇；名义壁厚 5.5 mm、口沿半径 4.2 mm；小于 0.33 mm 手工不匀|4 只裸陶、3 只上肩与口内局部釉面；裸陶 roughness .76–.92，蜂蜜/橄榄/铁棕釉 .28–.43；不使用全身清漆|
|九卷羊皮纸|12 圈真实薄片，厚 .45 mm，内部每圈 24、外侧 32/40 段；端部由纸片截面形成，无黑螺旋覆盖|暖灰黄纸色，roughness .81–.94；细微纤维/表面变化，无陶瓷式高光|
|九条绑绳|闭合细绳，管半径 1.7 mm、32×5 采样，落在原台面上|淡锈红亚麻，roughness .83–.95；无发光与金属度|
|展开样纸|32×24 网格，实体薄边 .6 mm；边缘轻卷 11–20 mm、浅缓起伏；无凸起墨线|原创 1024² 不可读笔划遮罩，只混入 Base Color；字符、行端和淡墨深浅有变化，不复制任何现实书稿|

所有新材料独立命名 `MarketRealism_*`。需要将 **Base Color、Roughness、OpenGL tangent Normal** 烘焙到游戏支持的 PBR。Metallic=0，Coat Weight=0，alpha=1，无 displacement、发光、透明或仅 Blender 生效的光学效果。裸陶 bump distance .28 mm，釉面 .07–.08 mm，纸 .035 mm；bump strength=.36。它们是项目设计振幅，不是扫描实测值。微纹理只补细表面，不代替几何口沿与薄边。模块 VERSION=3 将展开纸标为 `rmmo_export_group='PaperSheet'`，其余卷层和细绳仍为 `GoodsOpaque`；独立 PaperSheet 使用 1024 图集及 Specular IOR Level=.22。本次分组不改变作者几何。

程序 Noise 使用 Texture Coordinate 的 Object，按米制采样；几何顶点保留原母版世界偏移而新对象原点为零。合并烘焙前，主任务可将 Object 坐标固定引用原隐藏作者对象，原对象保留到烘焙结束。展开纸墨迹使用**显式 UVMap `GoodsUV`**，不能重命名此层；目标 atlas 必须另建 UV，保留 `GoodsUV` 供源材质读取。打包的 `MarketRealism_OriginalFadedManuscriptMask` 是原创墨迹遮罩，最终可随烘焙收敛到色图，不要求运行时第二张图。

纸卷保持九卷数量和原 X 列位置；为消除后排悬空及前后重叠，两排中心 Y 从 -.39/-.20 改为 -.62/-.30，绑绳下沿落在 Z=1.009 m 的原台面。后排纸边最多有约 7 mm 的正常悬边。样纸原 X/Y 范围保留。所有货品没有穿入台面，整摊 AABB 保持原值。

## CPU 审计与成本

实际运行 Blender 4.5.3 `-b -t 4`，没有启动 GPU、Cycles 或 Godot。`review_artifacts/axel_market_realism_20261016/pottery_scroll/cpu_check.py` 对当前模块执行 **135 项通过、0 失败**，检查所有新货品闭壳、正向有符号体积、无零面积三角形、UV 有限、无低于台面穿插；棚架/布/台面对象签名、全摊 AABB 和磁盘源母版 SHA 保持一致。封闭性和体积检查不是全局自交求交证明，最终仍看实际导出与近景。

|货品|高采样作者候选|当前合理精简候选|减少|当前数量|
|---|---:|---:|---:|---|
|陶器|64,512 tris|32,832 tris|49.107%|7 mesh|
|纸卷/绑绳/样纸|53,940 tris|31,556 tris|41.498%|19 mesh|

以上仅货品作者网格，不含棚架布面，不是 native、整摊每帧 draw 或真实 VRAM。内圈/内腔采样优先减少，保留外圆口、薄片与柔和轮廓。高采样版保存在 `goods_high_sampling.blend` 与 `high_sampling_module.py`，可供相同镜头、曝光和光照对比。当前没有新增模型 LOD：先由统一组装后的实际近中远投影和成本判定是否需要；不能仅依据此次三角面减少率放行精简版。此项在最终验收前仍待主任务作出结论。

当前证据身份：

- 模块 VERSION=3，SHA256 `87e2296c1eb2745f67e5137deacaf3bfd681e80b82fe627565285722c7a227f3`。
- `cpu_review.json` SHA256 `593b001b5460a83f051ebf99dafe372dcfc13aa4eebf97a960b17983cffd72af`。
- `goods_cpu_inspection.blend` SHA256 `831d09397991f647bd894648aa98c55d81b2a5ab0e638287ea1eb0b55d942aec`。
- 完整路径和高采样身份：`review_artifacts/axel_market_realism_20261016/pottery_scroll/integration_handoff.json`。

## 交接与未验项

资源审计：**作者 CPU 部分通过，游戏导出资源成本待验**。画质：**待验**。运行管线：**待统一导出后真实 native 导入保存重开**。游戏/编辑器接入：**未发布**，旧正式资源继续有效。

统一 GPU 复验重点：陶器轮廓没有纵向折线、口沿和内壁厚度清楚；裸陶与局部釉的反射有差异但不泛塑料清漆；纸卷卷层没有粗黑圈、端部没有重叠闪烁或明显多边形；纸卷、绳、样纸与台面接触成立；薄边和淡墨在正常近景可辨，墨迹没有因 atlas UV 变更而丢失；中远景无尖锐噪点或闪烁。实际截图发送查看前按技能转成原尺寸有损 WebP quality=90，绑定输出 SHA 与压缩记录。本阶段不将旧图审结果套到新候选。

## 统一烘焙脚本只读检查

`audit_root_bake_cpu.py` 仅在独立 Blender CPU 进程重现 evaluated-copy、join 与 Smart Project，不烘焙、不渲染、不保存源文件。实际检查的构建脚本 SHA 为 `74c563b9e2ec2252cb1bf273ceda9d876cdfe9acdccfd47dd877c6a55dbeb843`，结果在 `root_bake_readonly_audit.json`。

- 已确认修正后在原世界坐标烘焙，再统一移动最终输出；复制对象的程序坐标差为零。这样保留 Object 与 Geometry.Position 细节的原位置和米制尺度。
- 两款 join 前后按材质统计的面数一致，原 `GoodsUV` 数据完整保留。陶器 14、纸卷 20 个临时材质槽是每物件材质副本，不是最终运行槽数。
- 母版实际法线烘焙设置为 TANGENT，通道 POS_X/POS_Y/POS_Z。Roughness、Metallic、ORM 都以 Non-Color 处理，ORM G/B 直接读取线性数据；源码未发现 gamma 重编码错误，实际导出数据仍待核对。
- 已通知主任务并观察修正：最终陶器 Specular IOR Level 保持 .38，纸/绳 .22，避免合并后回到默认 .5；实际引擎导出与消费仍需验证。
- 发现待解决图集分配问题：纸卷全组 Smart Project、margin=.006 时，展开纸正面仅占 atlas 面积 .005324，在 2048² 中约为 131×172 像素。大量内部卷层和窄岛使淡墨分辨率不足。建议将展开纸单独烘焙，或重新分配可见面的 texel 密度；不能仅因为 `GoodsUV` 未丢便称墨迹完整保留。主任务已收到此数据，最终修正结果需以新版烘焙和画面证据关闭。

VERSION=3 随后落实了独立 PaperSheet。纯 CPU `scroll_atlas_cpu_probe.json` 实测 1024 图集正面约 **499×673 像素**。其余 GoodsOpaque 的有效 UV 利用率为 16.93%（margin .006）、31.34%（.003）及 48.67%（.0015），平均每卷可见最外层分别为 3,984、7,378、11,457 texels。内部被遮挡纸面占多数，统一比例分配仍有可优化空间。已向主任务建议先将 scroll 的 margin .003 作为候选，同时将 bake padding 从 12 像素相应降低（约 4 像素候选）并复看接缝，不能仅压窄间距而保留会跨岛的 padding。该建议尚不是 GPU 接缝通过。真实薄卷层由几何表现，不需要用粗黑纹弥补端面色图分辨率。

## 实际 v3 图审与增量修复

`gpu_realism_v3_01` 使用统一中性反射环境进行同镜头 A/B。本专项实际查看 29 张 Q90 原尺寸 WebP：陶器 9 机位的 A/B 共 18 张、纸卷候选 9 张及旧版货品正光/斜光 2 张。逐图 SHA 与范围在 `review_artifacts/axel_market_realism_20261016/pottery_scroll/visual_v3_review.json`。陶器的曲线轮廓、口沿和裸陶/局部釉面通过所见机位；整摊仍因背面包边斑纹未放行。纸卷的薄片轮廓与细绳改善，样纸墨迹却仍不能在正常近景辨认，继续修复。

样纸没有完全漏烘：按真实顶面 GoodsUV→GameAtlas 对应的 335,154 像素，mask 与烘焙亮度相关为 −0.859，旧墨区平均亮度 .534、无墨 .693。笔划太淡且细，经斜视和采样后近乎消失。模块 VERSION=4 改为 14 行较大原创笔划、约 2–2.7 px 主体线宽和深褪色棕墨；不加入凸起文字。模块 SHA `712323bbf876c141b4b82a4d7b4290f16649d93a7b0803c6d7e8331b06ae432c`。

仅重新 CPU 烘焙 PaperSheet，输出 `D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016/v4_scroll_sheet/delta.glb`，SHA `fe10e930cb371b53abbd7c00ce9c63fb6cb9b171fc311ef4107fc5309b9808a3`。19 项身份检查通过：几何、法线、切线、UV0、索引和节点变换与 v3 逐字节相同，normal/ORM/roughness/metallic 图不变，仅 albedo 改变。新墨区平均亮度 .403、无墨 .692，相关 −0.945；这些只是烘焙证据，最终正常机位可辨性仍待新版 GPU 图。

四款共享包边另以 `tools/patch_axel_market_canopy_trim_20261016.py` 做独立几何补丁，未改统一 builder。实际 v3 存在最深 3.562 mm 穿入与混合朝向。修复为约 0.4 mm 缝边间隙并统一向外 winding，重算 normal/tangent；每件 95,760 密集射线样本最小间隙约 .386 mm，穿入数与 BVH 三角相交数均为零。各件 2,736 tris 不变、原整体 AABB 在 1e−6 m 内相同、UV 顶点关联和所有材质/纹理字节不变，也没有禁用阴影。输出目录 `D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016/v4_canopy_trim/` 的 manifest、单件 CPU 报告和 `export_identity.json` 保存来源与 SHA。此补丁仍须实际背面/斜光复验。

布面细织纹在当前图中仍不能独立确认；本轮只确认宽缓褶皱和反光表现，不把程序参数存在当作微观织纹已还原。主任务已明确将进一步纤维细化留待后续，包边穿插及样纸墨迹则在本轮关闭后才能整摊通过。
