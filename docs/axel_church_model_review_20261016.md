# 阿克塞尔教会 · Blender 模型验收 · 2026-10-16

当前正式版本 **v8**，源 CPU 207 项通过、0 项失败，native 编译回读和六张受影响机位图审通过；最终三建筑真实 HTTP 共 430 项通过、0 项失败，教会 v8 原生身份和胶囊通行已核实。v7 的 22 张实际图审提供完全相同几何及非玻璃材质证据；v8 彩窗已修复绿/青色差，根代理另外查看内视和门侧图确认接受。v7 不发布。正式素材库和地图部署分别验收。

## 身份和范围

- [制作脚本](../tools/build_blender_axel_church_20261016.py)、[专项参考 C01–C04](axel_church_visual_references_20261007.md)。S12 河岸住宅及右侧归属不明民居不属于教会。
- v8 GLB：`D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/church/v8/axel_church.glb`，70,953,208 字节，SHA256 `f58bc6e78410e7cd6e100fb3db9992a395f007726c5728015ec040b82ef519b0`。
- 母版：同目录 `axel_church_master.blend`，66,021,750 字节，SHA256 `c0c3b43067d5eaea1259705357d0998375bca0770e672bc9ae3a3ce926acb97e`。旧母版和候选保留回退。
- 现实结构依据：[English Heritage 实物说明](https://www.english-heritage.org.uk/visit/places/st-marys-church-studley-royal/history/description/)和[官方平面](https://www.english-heritage.org.uk/siteassets/home/visit/places-to-visit/st-marys-church-studley-royal/st-marys-studley-royal-phased-plan.pdf)。只借鉴功能及结构联系，原图圆弧窗顶优先，不复制其尖拱、历史尺寸或宗教图像。

## 完整结构与补充设计

主厅、低侧厅、左后方塔形成完整四面体量。墙厚约 0.44–0.48m，窗洞真实贯通；主厅有石铺地面、木屋架、内侧望板、双扇门、六排双列座椅、讲台、祭台及约 3.25m 中央通路。侧廊连接接待施济、办公、休息与储物盥洗区。塔内 90 级折返木梯、平台和双侧护栏通至顶部维护层。没有擅加钟体、十字架或圣人像。隐藏背面、内部功能及家具、灯内魔法石均为项目补充设计。

实际包围盒 `[-11.25,-0.02,-11.57]` 至 `[5.61,25.45,13.15]`，尺寸 XYZ `16.86 × 25.47 × 24.72m`。本地 +Z 正门，地图方向由布局旋转决定，主地面 Y=0.30m。主门净 2.4×3.25m；塔侧门在 `[-10.84,0.30,-4.85]`，净 1.55×2.95m。塔梯宽 1.35m、级高约 0.167m、踏深 0.27m。尺寸为第三人称适配，不冒称官方测量或法规认证。

## 材质与图审修复

复用项目石砖、实木、石板铺装 PBR 与已修复鱼鳞红陶瓦法线。坡面按实际长度做米制 UV；瓦厚、屋脊、檐口与纯陶边材分开，窄切石饰线不绘制砖灰缝。法线视觉凹凸不冒称几何位移。

v3 初审发现窗格过密、混入琥珀色、尖拱与原图不符、门板过浅、灯玻璃乳白、灯石过曝及屋架尖端穿瓦。v5–v7 已改中央竖梃/横档/交替三角片、圆弧顶、厚框凹板、真实透明灯片及明暗切面，降低屋架尖端避免穿瓦。灯壳黄铜，内部暖白魔法石；玻璃本体不发光。主厅夜景采用四盏壁灯形成低照度照明，没有提高彩窗 emission 假装透亮。

v7 全部 22 张原尺寸 Q90 图实际查看，包含近中远、前后立面、开关门、彩窗内外、灯昼夜、石瓦细节、塔顶、主厅昼夜、无顶结构、侧厅、接待、办公、休息和塔梯。再对 C04 发现绿色/青色在蓝天空前过近，v8 仅改透射 RGB 为绿 `(0.24,0.84,0.29)`、青 `(0.22,0.64,0.85)`、浅青绿 `(0.51,0.83,0.67)`、紫边 `(0.66,0.36,0.79)`；完整窗、透明、无自发光不变。[v8 六机位](../review_artifacts/axel_landmarks_20261016/church/v8/gpu/report.json)全部实际查看：near、glass_front、glass_inside、portal_closed、lantern_night、hall_night。在与 v7 相同天空、曝光、机位下，室内蓝天前绿/青片可辨，外视仍透出屋架，夜间没有发光涂层或塑料背板，色板接受。

## 源资源与 native 成本

| 项目 | v8 实际值 |
| --- | ---: |
| 三角面 / 导出顶点 | 74,902 / 177,153 |
| 网格 / primitive / 源材质 | 89 / 164 / 20 |
| 唯一嵌入纹理 | 18，12×2048、3×1024、3×512 |
| RGBA8 基础解码 | 217,055,232 字节 |
| RGBA8 含 mip 预算 | 289,406,952 字节 |

没有零面积、缺 UV、缺 PBR 切线或非有限坐标。[CPU 207 项](../review_artifacts/axel_landmarks_20261016/church/v8/source_geometry_semantic_checks.json)验证 8 个真实室内 region、89 个稳定部件、7 组门/柜门、入口与内廊通路。90 级踏步各有向上顶面和 2.35m 净空。源几何数学检查不代替实际胶囊。

v8 隔离 GPU 图审构建的 native 为 131,237,078 字节，SHA256 `6d747ad60de95d53f82e2b3c24e3d019ada6ffb6c8a37aedb3818647b20d11d9`，生成器 SHA `05285ae6e8f7436171c0c973edf9413fd77cea550a54a9cc5f79922ae8c97535`；89 mesh、164 surface、97 node、30 含光学 pass 材质、18 唯一纹理，native 解包资源 221,299,100 字节，碰撞面数据 2,696,472 字节。保守候选预算 2,095,832,882 字节不是实测 RSS/VRAM。v8 源 SHA 与 native 清单、实际重新读取的描述及材质身份一致。

## 减面与 LOD 决定

本轮 **暂不新增独立简化 LOD，也不对整栋破坏性减面**。约 7.5 万源三角面主要用于真实窗洞、塔梯、护栏和活动件，作为低频单实例地标可保留。v7 隔离近中远实测均为 187 draw calls、76,416 渲染三角面，包含地面与玻璃附加 pass；远景仍为完整几何。远景已目视检查，轮廓与细窗稳定，粗暴减少窗格或折返梯会损失参考和内部功能。当前资源成本重点是 PBR 纹理与分层/玻璃 surface，单纯减面不能解决这些成本。

这是候选资产的 LOD 决定，不是整城 FPS 通过结论。[屏幕投影与实测计数](../review_artifacts/axel_landmarks_20261016/lod_decisions.json)记录教会近/中/远的保守 AABB 投影为约 675×827、381×455、236×283 像素（1440×1080 画面，含空角区域，并非精确轮廓像素分割）。源部件按楼层/角色/部件/光学分组，保留生产自动合批、隐藏及独立门语义。若地标多实例复制，或正式地图 profile 显示几何处理瓶颈，再以固定机位评估建筑壳体远距 LOD；不能为比例损害近中景、门洞、楼层或活动件。纹理/批次及正式场景性能继续走生产管线，不将整栋合为不可编辑 mesh。

## 语义、通行与验收边界

根 `rmmo_model_components`、`rmmo_building.regions`，每 mesh `rmmo_part`、稳定 `uuid` 与真实轴 `rmmo_hinge` 由通用生产消费者处理，不伪装公会 delivery_stage。v7 实际 native 回读检查源身份、描述、材质与玻璃配方；生产活动件 0/0.5/1 姿态与门碰撞一致，18 条入口采样射线无遮挡。

[v7 GPU 报告](../review_artifacts/axel_landmarks_20261016/church/v7/gpu/report.json)中的 `physics_completed` 仅指原生碰撞/活动件/入口射线。[最终真实 HTTP 报告](../review_artifacts/axel_landmarks_20261016/pipeline/http_139526127.json)另验证 v8 的实际 `compiled.ok=true` 与三次场景中 verified native PackedScene owner，禁止原 GLB fallback 冒充 native 通过。三建筑共 430/0，教会真实胶囊已穿主门进出，经侧厅到塔内两跑楼梯，最终在 Y=3.30m 平台站稳；`walk_evidence` 保存连续脚点、目标与 grounded 状态。该临时编辑器回归还包括楼层/屋顶隐藏、活动件、撤销重做、保存重开与身份一致；报告明确正式地图和目录未修改。

[v7→v8 实际字节对比](../review_artifacts/axel_landmarks_20261016/church/v7_v8_palette_identity.json)证明整个 GLB BIN 完全一致；mesh、accessor、纹理、变换、门轴、房间、碰撞均不变，JSON 仅四种彩玻璃颜色与 extras 的 50 个数值变化。因此 v7 几何和非玻璃画质/胶囊证据可引用，v8 已另行完成新的 native 身份及玻璃昼夜实看。

| 验收项 | 当前状态 |
| --- | --- |
| 源资源/结构 | v8 CPU 207/207 通过 |
| 画质 | v8 六机位全部实看通过；v7 全 22 图提供未变结构与非玻璃证据 |
| native | v8 编译/回读/语义/碰撞通过，实际身份已绑定 |
| 编辑器 HTTP/胶囊 | v8 原生身份、主门、侧厅、两跑塔梯实际行走通过，统一报告 430/0 |
| 正式素材库 | 已发布，直接正式目录使用 HTTP 126/0（三栋合计）通过 |
| 正式地图 | 本任务未改地图，布局接入须独立验收 |

全部查看图先原尺寸有损 WebP quality=90 压缩，附源 PNG SHA、目标 SHA、质量参数和字节记录；旧图不能冒充新色板。v8 六图由 9,166,566 字节 PNG 压缩为 1,041,072 字节 WebP，减少约 88.64%，仍为原始 1440×1080。原始参考保留，普通 GPU PNG 在生成 Q90 副本后移除。


## 最终正式素材库交付（根任务核验）

最终 `v8` 已通过正常 AssetLibrary 导入发布到共享默认库，目录分类“城镇地标建筑”。实际 asset_id 为 `D:/code/rmmo_runtime/packs/default/assets/f58bc6e78410e7cd6e100fb3db9992a395f007726c5728015ec040b82ef519b0.glb`，GLB SHA `f58bc6e78410e7cd6e100fb3db9992a395f007726c5728015ec040b82ef519b0`。该条目为完整导入建筑，不是参数化组件模板；`component_template_id` 不适用，门与楼层由源 `model_building v1` 合同保留。

[正式发布回执](../review_artifacts/axel_landmarks_20261016/publication/church_publish01.json) 记录源、正式目标、native/footprint、缩略图与原子目录保存；[正式目录使用回执](../review_artifacts/axel_landmarks_20261016/pipeline/http_57497240.json) 三栋合计126项通过、0失败。直接使用正式目录的原路径实例，无重导或临时源拷贝；实际选择、活动门碰撞、撤销重做、锁定拒绝及临时地图保存重开均通过，正式源与目录前后SHA不变。此前完整候选430项通过的几何/胶囊证据绑定相同源SHA。

正式库 native 实际为 **131,240,852 B**，payload SHA `2bb628964cea448d583b0ca61cf98037b758bd5950667cd02be577ffce16bfbc`。它与上文隔离图审/HTTP 构建采用同一最终源 SHA，但构建路径及序列化元数据不同，文件字节不宣称相同；正式使用身份以发布和126项回执为准。

资源、画质、运行管线、正式素材库使用四项均通过；正式地图部署与整图玩法/性能由布局任务另行验证，本任务未修改地图。最终身份与布局锚点见 `D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016/blender_building_handoff.json`，此节取代前文历史阶段的待发布状态。
