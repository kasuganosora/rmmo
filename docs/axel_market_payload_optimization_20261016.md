# 市场四款预制件载荷优化与正式交付

四款原有摊棚已完成无损载荷优化，并正常发布到共享默认素材库。只清理未使用资源，几何、UV、实际材质和使用中的原始贴图保持不变；没有缩图或减面。旧 GLB、旧 prefab 与 Blender 母版全部保留，正式地图未修改。

**验收边界：无损替换通过，原基线最终写实画质仍待细化。** 28 张候选 Q90 图均实际查看，另查看 4 张基线货品特写；7×4 个相同镜头的本地无损像素比较全部零差异。这并不消除原有陶罐轮廓分段、卷轴纸面厚度、瓶体塑料感、矿石低模轮廓及棚布层次不足的问题，后续布局细化继续处理。

源文件合计 **285,338,528 → 88,531,364 B**，减少 **196,807,164 B（68.97%）**。隔离 A/B 的 native 合计 168,218,109 → 168,218,108 B，基本不变；每款活跃图片 RGBA8 全 mip 预算仍为 268,435,440 B。不能把源文件降幅称作显存、RSS 或 native 节省。正式生产导入的 native 合计 **168,967,429 B**，实际身份如下，不用隔离 A/B 字节冒充正式交付。

|资产|旧 GLB B|新 GLB B|正式 native B|正式目录槽位|
|---|---:|---:|---:|---:|
|陶器摊棚|59,172,076|18,354,216|34,762,851|29|
|卷轴摊棚|64,373,448|20,029,488|37,275,911|30|
|魔法药水摊棚|86,899,384|26,905,940|52,974,543|33|
|矿石摊棚|74,893,620|23,241,720|43,954,124|31|

正式 HTTP **280 项通过、0 失败**，4/4 prefab 从实际目录发现后直接以正式新路径放置，在临时地图完成选择、非法请求无副作用、撤销重做、保存和实际重开。放置/重做/重开均核对真实 PackedScene owner 的源 SHA，以及网格、材质和碰撞。引擎日志无 ERROR；正式目录、旧新资源/native/footprint、母版与 173 份正式地图文件前后 SHA 一致。

发布使用每件独立 staging 内容根完成 normal importer + Prefabs.capture，再不可变复制到正式目录、生成来源绑定的正式 native。最后读取最新目录，只替换原四个槽位，保留名称、分类与并发新增条目，调用一次原子 revision/lock 保存并重开。旧哈希文件没有原地改写。

- [准确 old→new asset_id、GLB 与 native SHA 清单](D:/code/rmmo_runtime/art_sources/axel_market_optimization_20261016/delivery.json)
- [正式发布回执](D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016/publication/publish03/publication.json)
- [正式 HTTP 回执](D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016/formal_http/http02/editor_verification.json)
- [引擎日志与最终运行结果](D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016/formal_http/http02/runner_result.json)
- [逐图接受范围及原基线问题](D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016/gpu_ab02/acceptance.json)

失败尝试保留：gpu_ab01 是审计时给源网格附加 CPU 缓存导致严格 native 校验拒绝；publish01/02 是科学计数与 float32 的测试预期表示问题，正式目录均未提交；http01 功能/SHA 全通过，但工具读取无 metadata 节点产生 ERROR，按门槛未放行，修复后以 http02 完整重跑。未放宽生产校验。

正式地图实例替换由布局任务通过自己的保存事务完成；本交付没有修改市场计划或旧地图；共享 handoff 已提供精确映射与验收证据，本结果不代表整城帧率验收。

三张原先缺失的目录缩略图现已通过生产 `AssetThumbnails.queue_import` 正常生成（96×80），52项检查通过，Q90副本均实际查看；药水原图保留。[缩略图回执](D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016/publication/thumbnail_repair01/receipt.json)记录输出和来源SHA。最终[独立交付审计](D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016/final_delivery_identity.json)124项通过、0失败。GPU已释放，本任务没有剩余发布或目录使用待验项。

后续更新：四款正式目录条目现已进入 [v6 近景材质细化交付](axel_market_realism_review_20261016.md)。本篇记录的压缩基线和原文件仍保留；新版本改变货品几何与材质、成本增加，不能继承本篇的无损优化结论。新正式 SHA、native、400 项 HTTP 检查及独立待细化项见新报告。
