# 原生几何与独立材质离线原型（2026-10-27）

当前纹理隔离测试只恢复地图/预制件paint；导入模型仍由 `native_geometry_only` 使用无材质白模，不能冒称完整游戏贴图。现有白模writer在导出前已白化/丢纹理，必须在内容编辑/离线cook时从源数据或有效完整native提取原始材质，再发布独立描述；游戏运行时不回退GLB或重复源SHA。

`tools/native_material_descriptor_prototype.gd` 是**仅研究、未接生产**的合成PackedScene原型。写出几何 `.scn` 与独立Variant描述后重开，在受限静态triangle ArrayMesh上验证多surface、共享mesh/material/texture、surface与node override/overlay、normal/alpha/cull、UV/UV2/tangent、像素字节和CPU几何元数据，restore不修改原来源或几何产品。headless 86/86（`native_material_signal_green02.log`），不是GPU或真实GLB/地图测试。

独立审查先发现local_to_scene、texture尺寸override、脚本材质、非网格节点、嵌套metadata资源、skin/blendshape/shadow mesh等13项原型误接收，已红测后保守拒绝。第二次审查发现持久信号绑定可把材质/纹理重新写进几何，6项红测后原型拒绝持久连接并拒绝Variant中的RID/Callable/Signal。当前仅允许精确Node3D/MeshInstance3D等有限范围，texture.resource_name尚未恢复；非法或结构不匹配descriptor的健壮性、其他引擎属性/资源、动画和复杂节点未闭合。不能把该原型当通用等价、正式资源包格式或生产实现。

下一步仍需覆盖真实源素材、GPU视觉、surface/node身份和共享/独立修改、DDS与normal/alpha、预制件/地图交互、共享去重/统一预算、取消和卸载；ImageTexture/RID与材质绑定需符合线程约束。内容编辑器与3D MCP的导入、保存、撤销和派生资源刷新还未实施。原型证据 `D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/material_cache_pressure_20261027/native_material_*`，失败样本保留。
