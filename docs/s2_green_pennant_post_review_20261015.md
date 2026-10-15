# S2 绿色金丝带彩柱验收（2026-10-15）

选定 `v3`。资源、画质、管线与正式素材库接入均通过；实际 HTTP 编辑器复验 66 项通过、0 失败，保存前和重开后均确认柱身选取与行走碰撞。本任务交付素材库资产，未修改城镇地图；正式 S2 场景摆放仍由布景任务验收。

## 参考、设计与身份

- 镜头参考：[S2 窄街原图](references/town_required_shots_20261012/03_festival_residential_lane.webp)，要求近景绿色木柱、可辨纵向木纹、不规则顶缘和侧枝截桩。
- 用户明确的金黄色丝带要求优先于截图杂色绑带，依据 [城镇设定](medieval_town_visual_references.md) 的 S2 节。保留原柱交叉缠带、上固定圈、结与垂尾；这不是金属杆。
- 原木母版为正式原木柱 `c20c78874ba2a1693d2d474f43d0ea8bc47958fa08b610e3b703e5570883a6ad.glb`。S1 原木柱及其预制件不改色、不覆盖。
- 两处小枝桩为**项目补充设计**，不是从透视画面测得的精确官方尺寸。木纹来自已有 `wood/solid_timber` 材质（已购 Fab 木材包的既有项目资源），绿色涂层是本次派生色彩；保留原 OpenGL 法线，强度 0.45。
- 最终源：[v3/runtime.glb](D:/code/rmmo_runtime/art_sources/s2_green_pennant_post_20261015/v3/runtime.glb)。SHA256：`948e9f3cbd65f883c2da4a3fafe55f2502b8ede698b7764f6b91840635a148a8`。
- 未清理母版：[v3/master.glb](D:/code/rmmo_runtime/art_sources/s2_green_pennant_post_20261015/v3/master.glb)。SHA256：`8f4f01ddf8bee48d877144b6d3153559da0459afc87594e3e126451aa828460c`。v1/v2 均保留为拒收记录。
- 可复现制作：[build_s2_green_post.py](../tools/build_s2_green_post.py)；验收：[review_s2_green_post.gd](../tools/review_s2_green_post.gd)。

## 尺寸与场景使用

原柱高 **3.063523054 m**，脚底 Y=0；原柱节点变换保留。完整 AABB position=`[-0.318825543, 0, -0.283408642]`，size=`[0.651986063, 3.063523054, 0.566817522]` m，宽度包含新枝桩。几何不是按镜头透视推断的真实建筑尺寸。

当前布景计划的 scale=`[1.2, 2.1, 1.2]` 对应总高 **6.433398414 m**，沿用该计划的“顶下 0.20 m”绳挂点为 **6.233398414 m**（相对柱脚）。是否与具体道路和对侧柱组吻合由布景任务验收，不把单资产通过当作正式 S2 场景通过。

柱体与紧缠丝带保持既有静态语义；跨街风动旗仍是另一独立资产，没有并入本柱或取消其风场。没有活动门窗、骨骼、透明叶缘或灯光，相关专项不适用。

## 资源与优化

|项目|实测或审计值|口径|
|---|---:|---|
|未清理 v3 母版|42,220,660 B|保留完整回退源|
|运行 GLB|14,512,716 B|清理闲置依赖及旧 BIN 数据，节省 27,707,944 B，约 65.6%|
|三角面|5,468|原柱及丝带 5,212，新枝桩合计 256|
|节点 / 网格 / surfaces / 材质|4 / 4 / 4 / 2|原柱、缠带、两枝桩|
|正常全景可见 draw calls|5|包含 1 个验收地面；不是正式城镇批次数|
|有效贴图|6 张 2048×2048|两套 PBR；技术贴图没有转为有损 WebP|
|有效图片基础解码字节|83,886,080 B（80 MiB）|源图 RGB/RGBA 实际通道，不含 mip|
|RGBA8 全 mip 保守 GPU 预算|134,217,720 B（约 128 MiB）|不是实测 VRAM|
|隔离验收 native|31,980,127 B|正式管线 native 的身份与成本另见发布记录|
|单模型实际 RSS / VRAM / 整城 FPS|未测|不作性能提升宣称|

完整引用图清理前后，几何、材质及有效图片字节/像素相同；运行文件无孤立条目。未知索引引用拒绝清理，保留源文件。母版与运行版九个固定视角在本地无损 PNG 上逐像素完全一致，误差为 0；这项无损结论只针对 v3 重打包，不把 v1→v3 的材质修正称为无损优化。

未新增手工 LOD 或进一步减面：单件 5,468 面，计划只有少量柱组，近景缠带和树桩轮廓应保留。六张 2K 图用于前景近看，先清理明确的闲置资源；没有用缩图比例替代画质判断。磁盘节约不等于解码/显存节约，多实例也不能重复乘共享贴图预算。

## 问题闭环与画质

|问题|根因和修复|最终结果|
|---|---|---|
|旧绿色像荧光塑料、没有木纹|旧改色把黑色 atlas 空区计入均值，有效木面 99.76% 的 G 被截到 255；改为真实连续木纹与受控绿色派生|最终 G=255 比例为 0；常规、阴天和斜光均可辨木纹|
|枝桩出现黑色阶梯接缝|UV 三角形跨越原碎图集的空白区域；改为连续米制 UV 和有效木材通道|近景与上端特写无原黑缝|
|枝桩局部法线方向错误|v2 侧面 UV 折返导致同面切线手性混合；v3 每枝仅增加 4 个接缝顶点，柱状展开并重新生成切线|混合手性面和 UV 梯度错角均为 0；逐三角位置、法线及面数不变|
|误改 S1 原木色|独立派生新 SHA 路径，守卫既有源、预制件和原材质|原资产保持不变|

实际查看最终近、中、远、背面、木纹/丝带、上端连接、脚部、斜光和阴天九张画面。绿色木纹、金色非金属丝带、枝桩连接、顶缘和地面投影可辨，没有用自发光掩盖材质问题。运行材质的法线开关、强度、纹理数据与切线实际绑定已记录。

固定条件：Godot 4.7.2，Vulkan Forward+，AMD RX 7900 XTX；1000×1000，FOV 42°，MSAA 4×，TAA 关闭，ACES/曝光 1。默认环境光 0.58、方向光 1.5、旋转 `[-38,-28,0]`；斜光/阴天的单独参数和各相机坐标记录在 GPU 报告。所有 GPU 工作经独立未激活桌面运行，无角色遮挡。

验收图片在查看前均用 skill 编码为原尺寸 **有损 WebP quality=90**，已有压缩记录与 SHA。精确 A/B 在压缩前计算；迁移后更新报告路径/SHA并删除对应 PNG。查看工具保留 WebP 字节，仅修正其返回的 MIME 标签，没有转回 PNG 上传。

## 证据

- [制作与完整引用审计](../review_artifacts/s2_green_pennant_post_20261015/build_audit.json)
- [独立 CPU 审计：38 PASS / 0 FAIL](../review_artifacts/s2_green_pennant_post_20261015/independent_cpu_v3.json)
- [最终 GPU/native 报告](../review_artifacts/s2_green_pennant_post_20261015/runtime_v3/report.json)
- [九视角无损重打包对比](../review_artifacts/s2_green_pennant_post_20261015/repack_comparison_v3.json)
- [WebP 迁移与 SHA 记录](../review_artifacts/s2_green_pennant_post_20261015/screenshot_migration_v3.json)
- [最终候选验收凭据](../review_artifacts/s2_green_pennant_post_20261015/acceptance_v3_utf8.json)
- [近景](../review_artifacts/s2_green_pennant_post_20261015/runtime_v3/near.webp)、[枝桩与上端](../review_artifacts/s2_green_pennant_post_20261015/runtime_v3/upper_join_detail.webp)、[木纹斜光](../review_artifacts/s2_green_pennant_post_20261015/runtime_v3/grazing.webp)

## 正式接入记录

正式库分类为 **牌匾/旗帜**，名称为 **绿色金丝带彩柱**。`asset_id` 与正式 GLB 路径相同：

`D:/code/rmmo_runtime/packs/default/assets/948e9f3cbd65f883c2da4a3fafe55f2502b8ede698b7764f6b91840635a148a8.glb`

源、正式 GLB 与编辑器重开使用的 SHA256 均为 `948e9f3cbd65f883c2da4a3fafe55f2502b8ede698b7764f6b91840635a148a8`。正式入库后目录计数为 181；保留原 S1 原木柱和其他既有条目。正式库缩略图是编辑器所需产物，未作为 OpenAI 截图上传，也不属于可清理的临时验收图。

正式 native 为 `D:/code/rmmo_runtime/cache/world3d/compiled_assets_v1/5e831b080a407dde154b03c319ce71ec4f9e8e0f098406ef355f9935475a360d.scn`，payload SHA256 同文件名，磁盘大小 **31,985,746 B**；generator 为 `2a5b087e0b08c9cc74cc0b21217cc777f3d1535c0fcd27efe1c1d4eae50ff032`，与最终画质验收一致。

生产加载器验证的 footprint 记录：image mip 数据 **111,848,100 B**，GPU RGBA 保守预算 **134,217,720 B**，native 未压缩数据 **111,975,014 B**；管线完整准入预算为 **1,031,821,584 B**，`exclusive=false`。这些是资源解析与准入预算，不是实际 RSS/VRAM；也不将同一资源的预算按实例数量重复相加。详见 [生产 footprint 原始记录](../review_artifacts/s2_green_pennant_post_20261015/native_footprint_v3.json)。

|验收项|结论|证据边界|
|---|---|---|
|资源|通过|完整源/正式 GLB/native SHA、有效 PBR 依赖、成本与回退源齐全；CPU 38 项通过|
|画质|通过|最终九视角人工查看；母版与清理版在同条件无损图上逐像素一致|
|管线|通过|生产 importer 编译与有效 native 复用；真实编辑器选取、碰撞、撤销重做及保存重开|
|正式素材库接入|通过|真实 HTTP 发现并使用正式目录的精确资产；66 项检查通过、0 失败|
|正式地图摆放|未在本任务实施|只在隔离地图验证；由 S2 布景任务继续验收|

实际 HTTP 调用覆盖工具发现、素材查询、合法放置、非法放置无副作用、实例选取、撤销重做、保存重开和删除测试实例。保存前与重开后均有 4/4 真实 picking 射线命中、4/4 行走层射线命中，且单独要求 **PostBody 柱身**在两种 mask 下命中，不能以丝带碰撞代替柱身。正式目录、资产、凭据和用户地图在此测试中均未修改。

当前 3D MCP 没有通用外部 GLB 文件导入接口；本次入库使用与 UI 相同的 `AssetLibrary.import_file`，入库后的发现与使用通过真实 loopback HTTP MCP 验证。本次没有新增编辑器业务能力。

保留首次发布与首次 HTTP 失败证据：前者由专用验收工具对 JSON 浮点舍入的严格比较及凭据编码触发，修正后仅恢复同一 SHA 的获授权目录命名；后者因 Godot 单面碰撞采用 clockwise 正面，而测试从反向起射。最终专用测试增加反向查询并记录命中方向，未修改生产碰撞或放松柱身双 mask 门槛。

- [正式发布凭据](../review_artifacts/s2_green_pennant_post_20261015/publication_v3.json)，SHA256 `ad19b9ec34f48f5a8ba2f0c5ef205e5959adb5dc8cd2a796728cdc6c02822f5a`。
- [最终真实 HTTP 复验](../review_artifacts/s2_green_pennant_post_20261015/http_v3_retry/editor_verification.json)，SHA256 `c97174cde90aebce599d4a4dfba819f80cf5fe2c0141282d997be06a13c2e2a0`。
- [布景任务交接数据](../review_artifacts/s2_green_pennant_post_20261015/handoff.json)，含完整资产身份、尺寸、缩放建议和证据索引。

本任务 GPU 验收已结束并释放；没有修改布景 helper、房屋生成器或正式地图。
