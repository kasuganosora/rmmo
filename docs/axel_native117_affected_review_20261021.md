# 白模原生缓存受影响项复验（round 117）

本轮 CPU 网格代码身份变化导致外部派生原生缓存和预制件缓存重建。按 `rmmo-model-review` 复验导出、资源所有权和运行交接受影响项。源模型、母版和正式地图未修改；仍处于白模阶段。

49 件模型逐件实际重开、源与产品 SHA 校验、零序列化材质闭包检查通过。外部逐件报告位于 `D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/native117_model_reviews/`，以源 SHA 命名；各报告记录源/native 路径、SHA、字节量、网格与 surface 数量、生成器版本和四项验收范围。原始清单为同目录上层的 `conversion117_build_white_native_assets.json`、`check117_audit_white_native_products.json`；375 件预制件派生数据重建也通过，源文件及地图 SHA 未变。逻辑字节量不等于实测 RSS/VRAM。

最大建筑的新原生产品与当前 GLB 直接导入的结构、几何、碰撞指纹全部一致。历史 round 82 产品的法线、切线指纹则不同：99 个 surface 的 388 个法线数值最大绝对差 0.0000778436660766602；110 个 surface 的 610 个切线数值最大绝对差 0.0000781416893005371。位置、UV、索引、LOD、面数据和 AABB 未变化。尚未确认具体历史引擎/导入变更点，数值差是诊断数据，不是画质放行阈值。

- 源 SHA：`7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd`。
- 旧 native SHA：`1af7bfdd226eec7d90ae3ab306455aa1d12691ec27f63fef4351a2633bb1bf53`。
- 新 native SHA：`c9966f155fc9b567ed9bdf28d3b7adf5c088fcf4f5e2459aca78f8ead6386861`。
- 2319 节点、2007 mesh、2099 surface、1352412 碰撞面顶点保持一致。

回归测试改用同次当前 GLB 导入作为新转换的 oracle，同时输出历史差异；旧 golden、旧 native 和失败日志保留。当前原生共享、后台交接、三个剔除模式、真实门窗状态卸载/返回均通过。没有通过覆盖旧证据来消除差异，也不宣称相对历史原生严格无损或仅 metadata 修改。

资源审计与运行管线受影响项通过；画质没有新增同相机近中远截图，因此本报告不构成新的完整美术验收。纹理、风场、昼夜、骨骼与减面没有修改，不重复无关项目。独立候选用于隔离的真实地图性能路线，正式地图内容及资源包保存未改动，不能把候选验证写成新的正式内容接入验收。

共同证据：`check117_test_white_native_gpu_reuse.json`、`check117_test_white_native_handoff.json`、`check117_audit_white_native_channel_delta_production.json`、`check117_test_imported_building_retirement_gpu.json`。运行引擎与性能结论见 `axel_white_longframes_20261019.md` 第 90 节。
