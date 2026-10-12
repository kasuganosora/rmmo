# 编辑器扩展模型验收（2026-10-12）

适用 `rmmo-model-review`。以下是新增可用素材和生成器自审，不代表用户已批准最终城镇美术，也没有把测试模型自动摆入正式地图。Godot 4.7.2 Forward+、RX 7900 XTX；固定脚本相机、相同日间编辑器环境，近/中/远及细节图。素材为原创项目补充设计；无优化前已获认可版本，不使用“无损优化”结论。

## 橡木栈桥模块库

- 实际 GLB：`D:/code/rmmo_runtime/packs/default/assets/bridges/timber_trestle/04dcd60b441943f078687ff70424b092547f3b90f39e7e0c704b3dedb5770dbe.glb`。
- SHA256：`04dcd60b441943f078687ff70424b092547f3b90f39e7e0c704b3dedb5770dbe`；母版 `art_sources/editor_extensions_20261012/timber_bridge_v2/timber_trestle.blend`，原 v1 保留但不选用。
- 参考 [Historic England / National Trust Tattershall 木桥](https://historicengland.org.uk/listing/heritage-gateway/results/record/c30a9cd9-4500-41f0-acda-ed2a4d72a681/MNA182238) 的横梁、橡木排架、斜撑及护栏关系；该实物为近代中世纪式木桥，不冒称原存中世纪构件。按第三人称通行设置宽度、1.1 米栏杆及通行坡度限制。
- 六模块三角数：纵梁/斜撑 1,620；桩架 648；桥台 432；桥面 12；栏杆 432；立柱 108。几何导出无内嵌图片，生成时复用默认包木材 PBR。每座桥按跨度复制构件，不把模块总和当任意跨度桥的实测面数。
- 首次截图发现桥面轴向错误，v1 退回。v2 修正桥面；生成器再修斜撑跨度，末端接桩，并给翼栏补端柱。图 `cache/world3d/structure_extensions_19090471/timber.png`、`timber_detail.png`、`far.png`。
- 资源审计：通过，独立锚点/模块保留，无相机/灯光/人物或历史高分辨率图片。运行时三表面共享材质，冻结几何复用既有桥梁 LOD 准备；没有另造重复的整桥 LOD 对象。减面评估保留斜撑、栏杆接点和倒角，不为了比例删除可见连接。
- 画质自审：通过本次视角，桥面、桩、梁、斜撑、翼栏连接可辨；磨损/苔藓为确定性的局部颜色变化，不宣称额外高精度苔藓几何。
- 运行管线 / 游戏与编辑器接入：通过临时图真实 HTTP、生成预览、冻结、撤销重做、保存重开和生产 MapLoader。两端相差 1 米的 20 米桥，两方向胶囊通行通过。默认桥梁预设已可用，正式城镇未替换。
- 整桥独立 RSS/VRAM、冷暖计时未测，不借此宣称整城提速。

## 小麦模型（首批 v1，两件独立资源）

本节保留首批时点数据；随后完成两件 v2 LOD、连续风验证及默认库发布，当前交付状态见文末“LOD 补完”。原 v1 不删除。

形体为五茎丛生、细长叶片、两列小穗与芒，单位米，底部原点。参考 [Weald & Downland：Bayleaf 中世纪农庄资料](https://www.wealddown.co.uk/wp-content/uploads/2020/12/The-Bayleaf-Medieval-Farmstead-booklet.pdf) 的农地/园地用途；具体植株与颜色为项目补充设计，不作精确年代品种重建。母版 `art_sources/editor_extensions_20261012/wheat_v1/wheat_master.blend`。

|资源|SHA256|GLB 字节|native 压缩字节|基础三角形 / 顶点|表面|
|---|---|---:|---:|---:|---:|
|成熟小麦 · 五茎|`ace41dcc2297297269a702c3c025901d4651ad17d599d8957e4fd8e66e79e31e`|445,756|300,839|4,165 / 8,035|2|
|青麦 · 五茎|`ef73f54f68b01d9dfc9494b6d3f4ad51ee35f0e642acae25697398e61be64901`|433,416|254,829|4,165 / 8,035|2|

实际文件为 `D:/code/rmmo_runtime/packs/default/assets/<SHA>.glb`，标签与“作物”分类已写入同目录 `library.json`。两件均有原生缩略图，按原生原子写入/冲突检测登记，没有覆盖既有素材。

- 每件两张 256² RGB 图，各含 mip 的解码字节 262,143；每件共 524,286 字节。无需 alpha 裁片，不把图像压缩字节当显存，也不把 56 株乘以图片开销。GPU 实际分配可能按 RGBA/驱动对齐，未单独测量。
- 原生准入描述符为约 71.6 MiB 的保守准备预算（分别 75,047,636 / 75,047,672 字节），不是这两张小图的显存或单株常驻净增；测量 JSON 保留口径。没有通过改预算绕过既有资源校验。
- 资源审计：两件通过真实导入及 native 重读，依赖自包含、PBR 可用、底面和约 1.33 米高度适配。薄茎与麦芒在远处逐渐低于像素，保留原始几何；没有声称远处无闪烁。当前没有单独艺术 LOD，4165 面/丛用于有界、空间裁剪的散布；更大规模麦田应另做密度/LOD 专项，不靠删除麦穗轮廓冒充本次无损优化。
- 画质自审：两件通过正常近、中、远及细节观察；图 `cache/world3d/crop_extensions_11265226/{field_near,field_mid,field_far,crop_detail}.png`。本次有意混种两个阶段以观察差异，不把该混种测试当成最终农田布置。
- 运行管线 / 游戏与编辑器接入：两件通过；真实 HTTP 区域散布、垄沟高度、缺额返回、选择、锁定失败、撤销重做、保存重开、游戏 MultiMesh 批次。开启单株 foliage 受风配置后自动退出静态合批，关闭会话预览不改保存内容。默认静态配置；未宣称完成连续风动画所有风速/方向的美术验收。
- 农耕生产、成长/采收、作物状态服务器同步不属于本次素材与摆放功能。

## 水关、坡墙及体积地形派生模型

水关参考 [Historic England / Norfolk：Norwich 水门遗址记录](https://www.heritagegateway.org.uk/Gateway/Results_Single.aspx?resourceID=1002&uid=MNF26053) 的过水防守用途，多跨拱券、中墩和每孔两扇平开铁栅是项目补充设计，不称某座古迹的精确复制。桥头翼墙参考 [Warkworth Bridge](https://historicengland.org.uk/listing/the-list/list-entry/1020741)。

这些是随用户参数生成并冻结保存的模型，身份由原生地图资源和生成器指纹确定，不伪造单一全局 GLB SHA。源入口为 `water_gate_mesh.gd`、`fortification_terrain.gd`、`terrain_volume.gd`；验收地图与日志见 [交付记录](editor_extensions_20261012.md)。

- 水关：真实三孔拱底、实体券顶、中墩；独立铰链和多孔关闭碰撞通过。加深河床测试额外发现旧“岸面标高支承”检查误拒水下墩，改为实际河床五点承托，轴销依附已验证门柱。资源与运行管线通过，所拍视角美术自审通过。
- 坡墙：按局部坡度改形、正确变换法线并重算切线，保持墙顶通道和 PBR；刚性城楼需整平台地。资源与运行管线通过，所拍坡墙视角自审通过；不会自动改写正式城墙。
- 体积地形：真实洞顶/隧道/堆积网格、CPU 后台准备、游戏流式几何及碰撞通过；PBR 与块边界有界。体素分辨率和正交 UV 切换会影响小尺度岩壁细节；验收方盒穿洞仅证明功能，不作为天然洞穴美术模型交付。

依赖不变的既有住宅室内、门窗与夜间灯光沿用之前验收；本轮只补室外观察。用户最终美术确认仍由用户给出。

## LOD 补完及环墙 / 斜坡桥复验

用户后续要求补完六项功能边界，按同一 `rmmo-model-review` 标准复验本次受影响项，见 [边界补完](editor_extension_boundaries_20261012.md)。

### 青麦与成熟小麦 v2

母版仍为 `art_sources/editor_extensions_20261012/wheat_v1/wheat_master.blend`，旧 GLB 保留。新源在 `art_sources/editor_extensions_20261012/wheat_lod_v2/`；添加 native LOD 生成元数据，源 BIN 块逐字节相同（证明在 `candidates.json`），没有删除近景叶片或麦芒，也没有重编码图片。

|资源|新 SHA256|GLB 字节|已发布 native 字节|基础三角形 / 顶点 / 表面|
|---|---|---:|---:|---|
|成熟小麦 · 五茎（LOD）|`471669ea645b302b49dd9799f402a8c35ae9a314b02bdf78ff8a26eb8bfab3a6`|445,788|313,999|4,165 / 8,035 / 2|
|青麦 · 五茎（LOD）|`5dde353b2492a61b3d362e12e7e515a41470f23d85f578a0e5d5ef14ef8cf5ce`|433,448|267,931|4,165 / 8,035 / 2|

实际文件为 `D:/code/rmmo_runtime/packs/default/assets/<新 SHA>.glb`。默认库已用上述中文标签、作物分类登记并产生真实缩略图。测试库 native 字节为 313,971 / 267,932，与正式发布内含路径不同，分别保存报告，不能混用其哈希或体积。

- **资源审计：两件通过。** 每件仍两张 256² RGB 图，含 mip 的解码估算合计 524,286 字节。正式 native 的保守准备预算 75,147,152 / 75,147,188 字节，非实际 RSS 或显存。两表面的 LOD 索引三角数分别为 287→35 和 1,650→660→30，由屏幕误差独立选择；不是五个级别同时绘制。新增索引使 native 小幅增加，这是远景减图元的存储成本。
- **画质自审：两件通过已测范围。** 同镜头、光照和曝光静态 A/B，特写 / 近景像素差为 0，中远景在正常尺度观察未发现明显麦穗轮廓或叶片成片损失。两风向各 48 连续帧、移动镜头跨 LOD 未发现突然消失、根部脱离或成片跳变。细茎麦芒亚像素闪烁不能承诺完全消除，有限序列不代表所有风速和光照。详细参数和像素差见补完记录。
- **运行管线：两件通过。** 真正执行 native 导入、重读、当前 3D HTTP 行列散布、选择、锁定、撤销 / 重做及保存重开。实际 MultiMesh 的源网格有 LOD 索引；生产游戏 `MapLoader → WorldStream` 加载后仍实际合批。受风实例沿既有语义退出静态批次；默认风预览关闭。
- **接入状态：已发布默认素材库。** 未自动替换旧 v1 实例或正式地图。来源、发布回执、依赖 / native 报告在 `review_artifacts/editor_boundaries_20261012/{crops,crops_published.json,verification.json}`（runtime 目录下）。
- 192 丛固定场景远景提交图元减少约 53.5%；未测独立峰值 RSS / VRAM 或完整整城加载收益，不把此数字等同 FPS 提升。

### 圆形 / 椭圆水关和道路绑定斜坡桥

- **资源审计：通过。** 复用已验收的水关拱券、中墩和活动铰链生成器；环形券顶补缺时减去直段覆盖范围，避免重叠共面。斜坡桥复用现有桥型，匹配道路真实高度，源模型和贴图不另复制。身份由最终临时地图 SHA 和生成器 SHA 记录，不伪造通用单模型 SHA。
- **画质自审：通过所拍视角。** `cache/world3d/extension_boundaries_10513833/{circle_water,ellipse_water,following_towers}.png`，检查券顶接合、曲线墙、独立双扇和地形跟随后的承托；`cache/world3d/sloped_road_bridge_10959935/sloped_bridge.png` 检查两岸坡线、桥面和护栏。水关环形夹具是几何展示草地，不冒称真实河流成景，水下墩承托和拱孔由独立回归覆盖。
- **运行管线 / 接入：通过。** 真正 HTTP 预览 / 生成 / 关栅 / 跟随开关、锁定或异常无副作用、撤销重做、原生保存重开及游戏加载。道路自定义 0.04 米偏移后续补验通过，重铺无桥下旧板；所有新增路径都接入已有冻结 / 批次 / 缓存失效流程。未重测无改动的住宅室内与夜间组件。

## 代码审查后的受影响项复验

本节对应 [边界审查修复](editor_extension_boundaries_20261012.md)，仍使用 `rmmo-model-review`；未改桥梁/作物源 GLB、材质贴图或默认素材库，原身份与母版保留。性能跳过项没有恢复执行。

- **道路转桥：资源、画面和运行管线通过本次范围。** 路缘裁切保留截面、UV、封口及贴地模板；真实 HTTP/撤销/重铺/保存重开共 88 条重叠检查通过。`cache/world3d/sloped_road_bridge_10881484/` 的桥面、中远景与路缘细节均已查看，无残留跨越桥下的旧路缘。固定参数、源 SHA 和派生几何/纹理统计见 runtime `review_artifacts/editor_boundaries_review_20261012/structure_review.json`。灰色测试岸台不代表正式城镇美术。
- **水关跟随：资源、画面和运行管线通过本次范围。** `cache/world3d/water_crown_follow_review_11764888/` 含固定镜头 detail/near/mid/far 的 baseline/lowered 共八图，河床降低 0.35 米后冠顶步道、垛口和三孔六扇门保持连接，截图无角色；预览只读、撤销重做、跟随开关和保存重开通过。局部审计 `review_artifacts/editor_boundaries_review_20261012/water_crown_review.json` 与夹具 `resource_audit.json` 记录实际资源、纹理、图元和来源，未测整城 FPS/RSS/VRAM 或加载 A/B。
- **LOD 结论限于实际路径。** 原生 ArrayMesh 捕获、共享材质分叉与选择恢复保留 16/32 位 LOD；真实作物散布及 MultiMesh 回归通过。城防 `Art.build` 实测单件墙的两表面有 2/3 级 LOD，CPU 恢复完整保留。但原有冻结城防合并只用基础几何，本水关图 29 份唯一冻结几何均无 LOD，近中远渲染提交图元同为 231,256；不宣称本次完成冻结城防 LOD 或产生远景性能收益。这属于已标记跳过的历史性能范围。
- **作物实例语义：通过。** 两件实际发布作物的 HTTP 散布、批次、风开关、选择、撤销及保存重开再验 42 条通过，图在 `cache/world3d/crop_extensions_10777411/`。本轮只改实例/缓存代码，沿用上节源模型静态与连续风的美术验收；不以盒体负例代替实际作物验证。
