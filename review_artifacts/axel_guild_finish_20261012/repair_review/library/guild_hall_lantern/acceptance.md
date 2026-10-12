# guild_hall_lantern · 修复复验

- 阶段：贴图成品；来源：当前公会母版，参考及项目补充设计见 [本轮总报告](D:/code/rmmo/docs/axel_guild_repairs_20261012.md)。
- 文件：[guild_hall_lantern.glb](D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/library/guild_hall_lantern.glb)
- SHA256：`9e83ddde3ff64a16d54b781240f5451e7bb8a1854323d905a2f79c9c95866eab`
- 母版：`D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/axel_guild_repaired.blend`。原版本保留，不原地覆盖旧发布文件。
- Native SHA：`1b6e6aba8ec782414f96f1c8c31c598fcc4014f1cc46e4d9577999c3ca981bf1`；验收 generator：`69355a8b79ca02450ba947dd2f9201c525e0328c8cffd43c84fa8fee237cdf6d`。

|成本|本件数值/口径|
|---|---|
|源文件 / Native 压缩字节|203588 / 62224|
|Native 未压缩字节|130497|
|实例展开 LOD0 三角面 / Mesh 节点|2756 / 7|
|材质 / 图片|4 / 0|
|图片通道、尺寸、像素 SHA、mip|见 report.json 的 texture_diagnostics；没有贴图的纯参数材质为不适用|
|实际 RSS / 单模型 VRAM|未测；不将解码预算写成实占|

保留完整 LOD0，派生 1 个高面数网格的屏幕误差 LOD；合批跳过这些网格。

|验收项|结论|
|---|---|
|资源审计|通过，当前 SHA 与导入输入一致，依赖保留|
|画质|近景逐件巡检及主楼细节对比通过；六视角原图保留。与旧版本的材质同步属于有意修订，不宣称严格无损|
|运行管线|通过 Io.generate_scene、静态 schema、Native 保存重开、几何/材质/extras 一致|
|功能与接入|主楼共享组件、柜门碰撞、灯光按适用项见总报告；本件独立正式地图部署尚未验收|

相机、六视角（近/中/远、背面、暗背景、高光）、LOD 数据及预算限制见 [机器报告](report.json)。
当前版本不新增骨骼动画；雕像/吊挂骨架是静态陈设。布料保留原网格与风标签，不对所有风时刻作保证。
