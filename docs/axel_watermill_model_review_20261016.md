# Axel 下射水磨坊 · 制作与验收

这是新城磨坊的完整可进入候选模型，**项目补充设计**；当前没有找到用户给出的磨坊专用近景。不是 S12 河岸住宅，也不把现代实物的尺寸冒充动画设定。正式地图由布局聊天维护，本任务没有写入地图。当前交付主代理验收的候选是 **v11**，实际 GLB SHA `2343a78e8876302025e396d344f0328e809b71dbc750c7b2284c35af1b08ef9a`。

本件按 [rmmo-model-review](C:/Users/luna/.codex/skills/rmmo-model-review/SKILL.md) 执行。v11 已完成资源、GPU 画质、真实原生 HTTP 通路及正式素材库验收；历史版本的失败和修复经过保留如下。正式地图部署由布局任务另行验证。

## 参考与设计边界

- [Winchester City Mill，National Trust](https://www.nationaltrust.org.uk/visit/hampshire/winchester-city-mill/the-history-of-winchester-city-mill)：下射轮靠水流推动木桨，轮轴经齿轮带动磨石。采用这种低位受水关系，未凭空假设场景已有高位水槽。
- [Hockley Mill，Historic England Research Records](https://www.heritagegateway.org.uk/Gateway/Results_Single.aspx?resourceID=19191&uid=99a93adb-4fd2-4cad-9394-7e224c38d50f)：两层及屋顶阁层、瓦屋面、下射轮和保留的木机械；作为用途和构成资料，不复制十九世纪砖立面。
- [Houghton Mill 导览剖面，National Trust 2024](https://nt.global.ssl.fastly.net/binaries/content/assets/website/national/regions/cambridgeshire/places/houghton-mill-and-waterclose-meadows/pdf/nt-houghton-mill-welcome-leaflet-2024.pdf)：已查看第一页剖面和第二页场地关系图。采用水轮—坑轮—立轴齿轮—大齿轮—磨石的竖向关系，以及上层料斗、下层接料空间；原图的多层与大体量按本项目地块简化。
- [SPAB 水磨坊修复原则](https://www.spab.org.uk/sites/default/files/documents/MillsSection/Advice_Download_Principles_and_Practice_in_Watermill_Repair.pdf)：建筑与机械作为完整系统保留，木构连接、受水木件和维护通路同时考虑。游戏模型不是工程承载或水工效率认证。

剖面资料本地保存于 [houghton_reference.pdf](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/houghton_reference.pdf)；查看用图经过实际 Q90 有损 WebP，记录与原始栅格保留。网页字幕、导航、购买信息不属于建模指令。

## 占地和布局连接

[design.json](D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/watermill/design.json) 是布局接口。单位米，Godot +Y 上、+Z 正门、+X 侧轮。主楼 10.8×10.8 m，两层；楼层 Y=0/3.8 m。主入口净洞 2.4×3.0 m，后勤门 1.6×2.8 m。入口平台和低阶连续承托门前通路；库房、楼梯和设备区各有通路。

直径 4.6 m、宽 1.5 m 的下射轮中心 `[6.85,1.10,0]`，X 轴转动。设计水位 Y=−1.0 m、轮底约 −1.20 m、轮缘浸水约 0.20 m；首层世界 Y=4.0 m，对接世界水位 3.0 m。布局实采确认实际水流由局部 **−Z 向 +Z**，下部受水桨驱动 **−X** 旋转；旧版反向箭头已纠正。河床实采世界 Y=2.2～2.5241 m，轮底世界 Y=2.8 m，最小间隙约 0.2759 m，不需修改轮几何或填高河床。保留 `[5.75,−3.1,7.95,3.1]` XZ 水廊；最终接触由布局实际检验。

实采放置原点 `[305.422302246094,4,199.890441894531]`、yaw `−22.256907055609°`。主楼地形范围世界 Y=2.459865～3.942139 m，v8 补齐闭合四周石基与两处内柱墩，底部局部 Y=−1.70 m（世界 2.30 m）；外轴承处地形世界 Y=2.200733 m，独立基脚底部局部 −1.95 m（世界 2.05 m）。七件基础各自保留可编辑节点，并单独导出基础 GLB。实际承托范围是 design/manifest 中七个支承多边形的并集，**不把整栋 AABB 声称为满底支承**；轮廊没有被基础占用。

第三人称适配属于项目尺寸：楼梯净宽 1.65 m，20 级×0.19 m 升高、0.35 m 踏步；上下楼梯洞连续。CPU 逐踏步检测支撑和 2.35 m 头顶射线净空不等于完整角色控制器和镜头通行验收。

## 制作与可编辑内容

母版通过 Blender 4.5 后台 CPU 制作，不启动前台窗口或 GPU 渲染。生成器 [build_blender_axel_watermill_20261016.py](D:/code/rmmo/tools/build_blender_axel_watermill_20261016.py)；母版和各版本输出位于 [watermill](D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/watermill)。完整主楼有四面厚墙、真实内外贯通门窗洞、轴洞、首层石地基、二层木楼板、真实楼梯洞和护栏、木屋架、完整双坡屋顶、挑檐、山墙收口与脊瓦；不是仅正立面壳。

三扇木门分别以铰链轴为原点，保留铁带、铰链和把手。水轮、贯墙轴、轮架分别独立导出，整栋内仍保留独立节点；坑轮、立轴齿轮、大齿轮、小齿轮和上磨石保留旋转枢轴。其余静态件只按楼层/屋顶/碰撞用途合并，不整栋烘成一块。

首层有机械框架、齿轮防护、打包台和粮袋；二层有磨盘、围罩、四腿料斗、给料槽与粮箱。轮 24 桨、8 辐条/侧；设计齿数坑轮 48、立轴 12、大齿轮 60、小齿轮 20，总加速比 12。几何是可旋转装配，齿形为游戏用近似，未声称是精密渐开线机械或完成水动力模拟。

源 `semantic_group/author_floor/author_role` 是作者分组。v8 实际 GLB 根节点已有 `rmmo_model_components={version:1}`、`rmmo_building` 两层实际室内区域；每个网格都有 `rmmo_part={floor,floor_y,role,part}`。没有伪装旧公会的 `delivery_stage=textured_repair_v2`。三个门使用既有 `rmmo_hinge` 数据，运行消费者的通用 opt-in 和保存重开仍待主代理验证。静态缓存不支持的 GLB 动画未强行加入；轴和轮的持续转动由通用运行能力另行验证。

## 材质身份与资源成本

复用项目已购石材、抹面灰泥、整木 PBR，红陶瓦复用已验修正版 normal。石基与首层低墙是石材，上部填充墙为灰泥；木梁不是石砖，金属五金不是亮灰塑料。所有法线按 OpenGL 数据图，粗糙度为数据图，颜色图按 sRGB，UV 按米设置。屋顶保留原陶瓦色图和带层次的新版法线；不把普通民居瓦擅自换成公会鱼鳞瓦。

[candidate_manifest.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/candidate_manifest.json) 记录源定义、原贴图路径/SHA、母版和实际 GLB SHA、逐组尺寸和面数。解码与 mip 数字为保守图片预算，不是实测 RSS/VRAM；跨文件同图不自动算成运行时已共享。

本轮优先完整布局可用资产。v8 为 **55,120 三角面、37 个语义网格、58,117,140 B GLB**；12 张导出图片的 RGBA8 全 mip 预算 **226,478,796 B（215.99 MiB）**。该图片预算不是 native 文件大小或实测显存。没有无依据进行破坏性减面，也没有制造多个重复渲染的 LOD；此件成本主要来自 PBR 图片。轮的开孔、齿轮、门五金和楼梯均为识别/功能轮廓。后续若现场成本证据要求 LOD，需同镜头/光照比较，保留当前母版作为回退。

v10 材质复修后为 **55,768 三角面、37 个语义网格、55,761,844 B GLB**；新增木望板 648 面。灰泥改用已有暖色石灰刷面变体，取消不适合刷面的粗水泥色图，活跃图片为 11 张，RGBA8 全 mip 预算 **204,109,176 B（194.65 MiB）**。没有缩图、重绘 PBR 或以压缩比例替代视觉验收。独立水轮、轴、支架与基础的身份见当前清单。

v11 修通入口转梯，增加两根斜撑 88 面，总计 **55,856 三角面、37 个语义网格、55,770,900 B GLB**。图片成本和材质完全保持 v10；整体包围盒不变。

本轮明确 **不增加简化 LOD**。依据 [三栋 LOD 决策](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/lod_decisions.json)，v10 真实近/中/远机位的建筑 AABB 保守投影约为 828×679、474×381、295×236 px（1440×1080 图，八角投影，不是精确轮廓面积）；三机位均为 59 calls、55,986 rendered tris（含地面及玻璃 pass）。这是低频单实例、约 5.6 万源面建筑，水轮开孔、真实门窗洞及双层内部属于功能几何。v11 只增加 88 面，当前不为面数比例破坏这些结构。后续正式地图 profile 若显示几何瓶颈或新增多个实例，再验证保留轮廓与开洞的远距外壳 LOD；这一决定不等于已完成整城 FPS 验收。

v8 实际包围盒为 `[-6.03,-1.95,-6.07]` 至 `[8.65,9.5892,7.525]`，包含挑檐、阶台和轮架，XZ 占地约 **14.68×13.595 m**。布局保留范围为 `[-6.1,-6.1,9.0,7.6]`，未扩大实际建筑。

## 验收记录和待检范围

- v1 导出发现 n-gon 使部分法线材质缺切线，退回；保留版本。
- v2 补确定性三角化和楼梯落脚板。CPU 204 项通过、3 项失败：料斗过薄边倒角产生 16 个退化三角形/异常切线；另有保留范围没有含檐口厚度。退回后取消料斗薄边倒角，并按真实檐口更新保留范围，没有扩大实际建筑。
- v3 修复料斗退化，后续 v4 补通用建筑语义，v5/v6 修复屋面厚边及极小水轮倒角在 glTF float32 UV 转换后的塌陷。早期文件保留为回退/诊断资料。
- **v6 实际导出 CPU 240 项通过、0 失败**：几何退化 0，塌陷 UV 三角形 0，法线/切线有限且单位化；门口结构开洞射线、20 级踏步承托/净空、顶部落脚板、通用语义、独立转轴节点检查通过。证据 [cpu_audit_v6.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/cpu_audit_v6.json)。只覆盖资源与几何抽样，不替代 GPU 画质和控制器实际通行。
- v7 河侧基础模块通过 278 项；随后收到精确地形采样，升级 v8 的闭合周边支承。**v8 实际导出 CPU 310 项通过、0 失败**，新增基础实际支承多边形、基底埋深、轮扫掠/水廊避让、下游及转动符号检查；证据 [cpu_audit_v8.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/cpu_audit_v8.json)。与 v6 的全部 30 个原组逐三角形对比，位置/材质在 1e−5 精度一致，法线和 UV 的重新导出差异低于 1e−4；仅增加七个基础组。未把重排后的 accessor 冒称字节一致，详细差异见 [v6_v8_geometry_identity.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/v6_v8_geometry_identity.json)。
- **v9 CPU 311 项通过、0 失败**：按新增稳定 source UUID 合同，将 `/` 等非字母数字、下划线、连字符的标识字符规范化；37 个网格 UUID 合法且唯一。没有重新导出几何或贴图：五份 GLB 的整个 BIN 块与 v8 逐字节相同，JSON 除 `uuid` 字段外相同，见 [v8_v9_uuid_identity.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/v8_v9_uuid_identity.json)。母版另存时只改自定义 UUID。v8 画质证据可用于相同几何材质，native/HTTP 必须使用 v9 身份；证据 [cpu_audit_v9.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/cpu_audit_v9.json)。
- v9 实际 native/GPU 已由并行验收代理检查：源/native 语义等同、三扇门变换与碰撞跟随、18 条门洞净空射线通过，留下 17 张原尺寸 Q90 图及 [report.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/v9/gpu/report.json)。实际查看 `window_detail`、`upper_millstone` 后发现玻璃乳白、灰泥大尺度波纹、屋顶内侧误用红瓦，因此 **v9 画质未放行**。门洞射线不等于完整胶囊从入口转向楼梯已通过。
- **v10 CPU 317 项通过、0 失败**，见 [cpu_audit_v10.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/cpu_audit_v10.json)。玻璃加入生产已消费的 `rmmo_tinted_glass`，中性透射 `[0.97,0.985,0.98]`、粗糙度 0.09；源回退 alpha 0.035，不用自发光遮盖问题。灰泥采用 `walls/exterior_limewash`，UV 平铺 0.45 m、法线强度 0.18。主屋顶新增 54 块 30 mm 木望板，主屋和门廊向内表面改木材，CPU 确认没有露出的向下红瓦表面。33 个未影响组几何/材质名/法线/UV 对比通过，详见 [v9_v10_geometry_identity.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/v9_v10_geometry_identity.json)。窗、灰泥、屋顶和门廊内侧已交同镜头 GPU 复验，未自行启动 GPU，也未提前称画质通过。
- v10 随后由独立验收代理实际查看 **17/17 张 Q90** 图并接受画质：透亮玻璃、木望板、灰泥粒度的三项修复可见；基础与水轮形体通过。实际 [GPU/native report](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/v10/gpu/report.json) 通过，native **96,138,898 B**、SHA `836e0a96068ada4eefdcbc8b8382ad36c93ef768e0b98c76fc0cef8e2c25ccb8`；该摄影棚包含地面时为 59 calls、55,986 tris，不外推成正式地图成本。真实 HTTP 和胶囊转梯通行仍由后续专项测试覆盖，不能由门洞射线代替。
- v10 的真实 HTTP 胶囊测试随后发现入口转梯不通。单位尺度、双门全开、标准直径 0.6 m 的胶囊，按精确折点从 `[-2.1,0,3.95]` 前往 `[-3.4,0,3.95]` 时停在 `[-2.58353,0.00284,3.93224]`；重复输入不再移动。证据 [http_56637590.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/pipeline/http_56637590.json)。门叶末端与柱角约 0.59 m，不能用穿侧栏杆的绕行、缩胶囊或关闭柱碰撞放行。
- **v11 CPU 324/0 通过**，见 [cpu_audit_v11.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/cpu_audit_v11.json)。左前内柱沿原纵梁从 Z=3.5 后移至 Z=2.6，独立前柱墩同步移至 Z=2.2～3.0，保留原 X、基底和碰撞；补两根最低 Y=2.55 的梁下斜撑。名义门叶端至柱前缘净隙增至 1.49 m。仅 `timber_l0` 和 `river_foundation_inner_pier_front` 两组改变；[35 个未影响组几何对比](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/v10_v11_geometry_identity.json)、[全部材质/图片及玻璃合同对比](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/v10_v11_material_identity.json) 通过。已交同一路径真实 HTTP 胶囊复测及柱连接局部图审，尚未提前称运行通过。
- **v11 真实 native/HTTP 胶囊复测通过**：标准单位尺度、直径 0.6 m，双门全开后，主门进出、门内横穿原狭口、梯底、20 级直梯到 Y=3.8 上层站稳全部通过；没有跳跃、瞬移或碰撞例外。实际 verified PackedScene 三次加载通过。三栋本轮 HTTP 汇总为 **430/0**，这是三栋综合数量，不误记成磨坊独有 430 项；证据 [http_139526127.json](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/pipeline/http_139526127.json)。
- **v11 局部 GPU 画质通过**：独立图审代理实际查看全部 5 张原尺寸 Q90 图，柱、两根斜撑及纵梁连接完整，基础墩与移位后的柱对齐，入口转梯视野和通路没有新增穿插。其余 35 组几何及所有材质/图片由相同身份对比复用 v10 的 17 张图；见 [v11 签署图审报告](D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill/v11/gpu/report.json)。实际 native 为 **96,140,814 B**，SHA `1a8ceb951e5ac4574be6f3e891db889be03a25afb87c7421cb670ae02e6e4633`；唯一图片 RGBA8 全 mip **204,109,176 B**，保守加载预算 **1,496,314,164 B**，均不冒称实际 RSS/VRAM。源和 `v11/manifest.json` 已冻结，后续交付状态另写报告，不改其身份。

轮、轴、齿轮、转动上磨石为 `rmmo_collision=none`，首层机械木护栏、轮架与静态结构为 block；地板/踏步为 walk。室外轮位于河槽，布局集成仍需核查岸边通路和轮周防护，不能把 none 写成“不可选择”或“已验证玩家不能穿入”。

实际导出已完成 native 回读、近中远及材质细节图审、楼层隐藏、活动门和正式素材库保存重开。轮轴及传动轴心语义保留；自动水轮动画本轮未实现，不列为已通过。正式地图中的轮下接水、岸边通路及地形贴合由布局任务按实际部署复核。

|里程碑|状态|
|---|---|
|资源审计|v11 CPU 324/0、真实 native 与三次验证加载通过|
|画质|v10 17/17 图与 v11 柱、斜撑、基墩 5/5 局部图均通过|
|运行管线|v11 真实 HTTP 标准胶囊主门进出、转梯、20级上楼通过|
|素材库接入|正式发布及直接正式目录路径 HTTP 126/0（三栋合计）通过，见末节|
|正式地图部署|本任务未修改，交布局聊天完成|


## 最终正式素材库交付（根任务核验）

最终 `v11` 已通过正常 AssetLibrary 导入发布到共享默认库，目录分类“城镇地标建筑”。实际 asset_id 为 `D:/code/rmmo_runtime/packs/default/assets/2343a78e8876302025e396d344f0328e809b71dbc750c7b2284c35af1b08ef9a.glb`，GLB SHA `2343a78e8876302025e396d344f0328e809b71dbc750c7b2284c35af1b08ef9a`。该条目为完整导入建筑，不是参数化组件模板；`component_template_id` 不适用，门与楼层由源 `model_building v1` 合同保留。

[正式发布回执](../review_artifacts/axel_landmarks_20261016/publication/watermill_publish01.json) 记录源、正式目标、native/footprint、缩略图与原子目录保存；[正式目录使用回执](../review_artifacts/axel_landmarks_20261016/pipeline/http_57497240.json) 三栋合计126项通过、0失败。直接使用正式目录的原路径实例，无重导或临时源拷贝；实际选择、活动门碰撞、撤销重做、锁定拒绝及临时地图保存重开均通过，正式源与目录前后SHA不变。此前完整候选430项通过的几何/胶囊证据绑定相同源SHA。

正式库 native 实际为 **96,140,234 B**，payload SHA `6703fcb63e2329142e1ddbe08f788b90f5da47baa09ad603009cc21ff6931827`。它与上文隔离图审/HTTP 构建采用同一最终源 SHA，但构建路径及序列化元数据不同，文件字节不宣称相同；正式使用身份以发布和126项回执为准。

资源、画质、运行管线、正式素材库使用四项均通过；正式地图部署与整图玩法/性能由布局任务另行验证，本任务未修改地图。最终身份与布局锚点见 `D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016/blender_building_handoff.json`，此节取代前文历史阶段的待发布状态。
