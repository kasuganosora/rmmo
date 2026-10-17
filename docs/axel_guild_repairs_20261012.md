# 公会及附属物件修复与复验 · 2026-10-12

本轮已修复上一轮报告中的堵窗、缺 mip、柜门与照明未接入、独立家具版本不同步，以及主楼未合批的问题。产物为 **repair_v2**；原母版和用户认可的入口平台版保持不变。执行 [rmmo-model-review](C:/Users/luna/.codex/skills/rmmo-model-review/SKILL.md)，不能将本轮候选及临时地图验证称为正式城镇完整交付。

## 产物与身份

- [主楼 GLB](D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/axel_guild_repaired.glb)，SHA256 `e920c0b39f8f7e9019d501e29b4c6ee78cbcc78413a2a3fc49a420a08a08b2a1`。
- [可编辑母版](D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/axel_guild_repaired.blend)。
- [51 类独立家具/陈设逐件索引](axel_guild_repaired_assets_20261012.md)，每件有完整 SHA、Native 身份及四项状态；[清单](D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/repair_manifest.json)。
- [告警塔 GLB](D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/guild_alarm_tower.glb)，SHA256 `a44045656a0f640f71e739f03437d71a58af8b2e4e6792bfa56a89e8606c743f`。
- 旧入口版 SHA `b5498b3278fc5f2e929bd1b8d410b6896b5c6f8bb3c58212e328b71220318567` 保留，原母版也通过 SHA 复核。新母版 SHA 及完整复核见 [delivery_integrity.json](../review_artifacts/axel_guild_finish_20261012/repair_review/delivery_integrity.json)。

## 修复结果

|问题|修复与证据|
|---|---|
|二楼四处堵窗|203/204 东窗、卫生间东/背窗贯通，增加薄玻璃。去掉与外墙重叠的四块冗余房间内衬，保留外墙完整开口和窗洞侧面。四条几何射线通过；客房、卫生间及外立面复看。生成器同步避免重建重复墙。|
|纹理缺 mip|在生产 Io.generate_scene 准备阶段生成并缓存 mip，法线单独处理，基础像素/alpha 保持；Native 重开保留。51 类家具全部通过，无贴图纯参数材质不适用。共享纹理回归 87 项通过。|
|柜门仅有标签|8 个储物柜补实际枢轴、门上金属件和内层板；加上 6 个客房柜，共 24 扇独立柜门，接入现有 fixture。主楼连同建筑门共 37 个动作组，147 个活动网格通过关/半开/全开/还原和碰撞随动。|
|照明未实际工作|6 盏大厅魔法石灯、8 处蜡烛、2 盏门口灯接入共享灯控制器；蜡烛复用已有火焰。最多 6 盏邻近实际灯、2 盏动态阴影，优先当前楼层。室内灯常亮，门口灯随昼夜；保留黑金属、玻璃片和暖白魔法石。|
|独立文件过时|从当前成品母版同步导出 51 类资产；雕像、吊挂骨架、灯、家具与主楼材质一致。徽幡包含布面、挂环及完整三角架，并修正独立版本挂墙原点。旧文件不删除。|
|主楼绘制成本|按部件用途、楼层/屋顶、物件和活动轴分组，接入共享派生合批；32 个合适的高面数实例使用 16 个唯一网格的派生 LOD。LOD0 顶点/表面保留，碰撞不用远景 LOD，布料/透明件不强制减面。|
|导入未命中编译|源模型的 clearcoat/IOR 材质扩展此前被边界合同拒绝。补齐这两种纯材质扩展的识别，不放宽未知几何扩展检查。真实生产 Compiled.build 已通过。|
|编辑器未扫描模型子部件|为导入模型提供显式子网格集合与每实例唯一身份；整体选择立即恢复源网格，复制实例互不排除，替换/删除清理旧批次。真实编辑器自动生成 95 个批次。|
|告警塔旧场景/边界|移除一个不可达旧节点和备用 scene，保留模型/材质/图片二进制；统一 LOD 边界增高 0.05 m 覆盖塔顶。未将保守保留的未用二进制数据称为文件压缩。|

柜体内部层板、必要铰链、玻璃厚度与独立挂点是项目补充设计。保持用户确认的入口平台宽 6.9 m、下级踏步深 0.6 m、级高 0.16 m，以及布幡、三角撑、金色徽饰杆和既有屋面收口；不重新设计未受影响的室内布局。

## 同条件对比与成本

Godot 4.7.2 / Forward+ / RX 7900 XTX。GPU 测试均用隐藏独立桌面；临时地图不覆盖用户地图。A/B 为同一修复版、同相机与光照，对比未合批/未派生 LOD 和启用优化；结构修复不伪装成无损优化。

|视角|基线绘制 / 三角面|优化绘制 / 三角面|
|---|---:|---:|
|近景|1,740 / 480,298|428 / 417,268|
|中景|1,740 / 480,298|428 / 415,006|
|远景|1,746 / 480,298|434 / 398,338|

近景绘制约减少 75.4%。这是隔离视口计数，不含阴影 pass，不代表整城 FPS。95 个派生分组保留源对象；同步测试最大单组构建 31.56 ms，不宣称完全消除加载卡顿。实际编辑器导入、选择、门柜编辑和保存已验证，未测正式城市帧时。

20 个固定镜头/风时刻输出已对照：入口、屋顶、彩窗、布幡/支架、大厅、登记处、客房、楼梯、卫生间和后墙。修复前候选因冗余墙面产生的客房明暗差异被退回；最终对比不再有该明显变化。最终图像 RGB 平均差约 0.006–0.372/255，仅作定位辅助；LOD 有意改变远景索引，不称严格无损。原尺寸图及四张 A/B 联系表见 [final_building](../review_artifacts/axel_guild_finish_20261012/repair_review/final_building)。

主楼源文件 115,382,812 字节；隔离 Native 225,803,329 字节、未压缩 469,119,275 字节；41 张共享图片、141 个材质。`image_mip_bytes` 为 461,023,874，`gpu_rgba_bytes` 保守预算 608,174,028，准入峰值预算 4,407,478,864。增加 mip 使 Native/解码成本增加，不能说成显存优化；这些均不是实测 RSS/VRAM。最终生产编译文件因序列化为 225,730,746 字节，不假称不同进程 SCN 字节恒等。

塔的实际 LOD 三角面仍为 157,112 / 80,104 / 46,802，38/42/108/112/250 m 自动级别与强制单级一致，各 11 次绘制。Native 79,009,949 字节，图片含 mip 字节 156,587,332。塔顶、号角近景和远景已复看，砖/石/黄铜材质分区保留。

## 管线、功能与证据

- [最终主楼 baseline](../review_artifacts/axel_guild_finish_20261012/repair_review/final_building/baseline.json) / [candidate](../review_artifacts/axel_guild_finish_20261012/repair_review/final_building/candidate.json)：真实导入、生产静态 schema、Native 保存重开、Footprint/Preparation 和源 SHA。
- [运行组件](../review_artifacts/axel_guild_finish_20261012/repair_review/runtime.json)：四窗、37 动作组、碰撞与16灯；[客房灯光](D:/code/rmmo_runtime/review_artifacts/axel_guild_finish_20261012/repair_review/guest_lighting.png)。夜景图为低环境光测试，正式地图的整体夜景曝光仍由场景调校决定。
- [真实整楼 HTTP](../review_artifacts/axel_guild_finish_20261012/repair_guild_http_accepted.log)：自动合批95组、界面入口、工具发现、合法/非法调用、无副作用失败、一次撤销、重做、保存重开。临时图 `D:/code/rmmo_runtime/cache/world3d/model_components_10546320/map.gltf`；没有写正式地图。
- [生命周期回归](../review_artifacts/axel_guild_finish_20261012/repair_batch_regression.log)、[导入模型选择/删除](../review_artifacts/axel_guild_finish_20261012/repair_imported_batch.log)、[共享纹理](../review_artifacts/axel_guild_finish_20261012/repair_texture_regression.log)、[边界42项](../review_artifacts/axel_guild_finish_20261012/repair_bounds.log)、[估算44项](../review_artifacts/axel_guild_finish_20261012/repair_estimate.log)。
- [塔 LOD](../review_artifacts/axel_guild_finish_20261012/repair_review/tower/game_review.json)、[塔 Native](../review_artifacts/axel_guild_finish_20261012/repair_review/tower_native/baseline.json)、[家具逐件状态](../review_artifacts/axel_guild_finish_20261012/repair_review/acceptance_index.json)。
- 连续相机采样：屋顶/布幡、客房地板各 32 帧，保留 [序列](../review_artifacts/axel_guild_finish_20261012/repair_review/motion)。采样范围内查看细节变化；不推广为所有距离、风时刻和所有 GPU 均无闪烁。

原静态画面报告绑定 generator `69355a8b79ca02450ba947dd2f9201c525e0328c8cffd43c84fa8fee237cdf6d`。后续仅扩展材质资格检查及导入模型组件的运行接入，未改其几何/材质像素；最终生产编译和真实 HTTP 是新代码的独立证据，未给旧 manifest 改签名。失败诊断日志保留：第一次整楼测试提前操作了仍在加载的编辑器；第二次定位到子网格未被合批扫描；最终日志为零失败。

## 交付范围

|范围|资源审计|本轮画质|运行管线|接入|
|---|---|---|---|---|
|主楼修复版|通过|受影响静态样本/LOD 对比通过|通过编译、保存重开、组件|临时编辑器及运行组件通过；正式地图待部署|
|51类独立物件|逐件通过|材质同步/静态巡检通过|逐件 Native 通过|共享接入逻辑完成；独立正式部署待验|
|告警塔|通过|受影响近中远/材质通过|LOD/Native通过|正式地图待部署|

仍属于后续集成范围：整楼的正式房间成员登记与第三人称相机自动楼层/屋顶隐藏联动、四扇折叠工具间门的折叠动作、城市实际帧时/内存、彩窗透射光/焦散及最终夜景调校。源层级与合批分区已保留，但不据此冒称相机联动完成。告警塔可进入内部及声音告警、警卫处/教会不在本轮交付范围。没有删除这些缺口，也没有用候选通过覆盖旧报告的历史结论。

最终生产 generator：`d458f4e96899899314e616350910fe6f0db61817cede63fa5779af677c173d9d`；实际 Native payload SHA：`244b9727fc4414dcc25385f0c5f0c2aa28897754a0983a78ca331c1122ff80b8`。见 [真实编译身份](../review_artifacts/axel_guild_finish_20261012/repair_review/production_compile_identity.json)。该版本的 [缓存失效/恢复回归](../review_artifacts/axel_guild_finish_20261012/repair_cache_final.log)零失败，包括源变更、缺源、旧缓存拒绝与重建。最终连续采样使用白色环境光，早期暗场诊断不作为地板过滤通过证据；原始32帧PNG为准。

用户随后要求清理临时截图：删除早期候选/诊断截图和重复的联系表、拼图及浏览 GIF，共155件、211,693,479字节。保留最终A/B原图及四张对照表、51类家具六视角、连续镜头64帧、灯光与塔的验收图，以及文档直接引用的历史图片。原模型、贴图、设定参考和验收数据未列入清理；完整删除清单见 [清理记录](../review_artifacts/axel_guild_finish_20261012/screenshot_cleanup_20261012.json)。早期JSON中的截图路径仅作历史记录，对应被清理文件以该清单为准。
