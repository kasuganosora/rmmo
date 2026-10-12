# 大幅壁挂织毯 · library · 2026-10-12

- ID：`guild_wall_tapestry`；范围：独立素材文件。原模型没有改动，不宣称压缩或严格像素无损。
- 实际源：[D:/code/rmmo_runtime/art_sources/axel_guild/textiles_sanitary_v1/game/guild_wall_tapestry.glb](D:/code/rmmo_runtime/art_sources/axel_guild/textiles_sanitary_v1/game/guild_wall_tapestry.glb)
- SHA256：`63f93d8354d0621e21418a435df63057de8b45232e4d86d36f888e64ad573f50`
- 主楼节点：`不适用`；该类型实例数：1。
- Native SHA256：`f25c109a666920d5e1c59687d71e39ef3710c6825f873eb4d5086beafb76ff2e`；generator：`50d0b3e04b372b98fac1762e185e71a37bdafb405099e4b8fd30395141d5e84f`。
- 参考：公会设定文档及其对应 U 图；卫生设备隐藏结构按项目补充设计。独立库存阶段见 inventory.json。

|项目|本轮实测/统计|
|---|---:|
|Native 压缩字节|27,199,092|
|实例展开三角面|8,596|
|Mesh 节点 / 材质 / 导入纹理资源|5 / 4 / 6|
|近景绘制次数（含测试地面）|6|
|纹理无 mip 的资源数|6|
|GPU RGBA 保守字节预算|动画合同不适用；未测|
|native 未压缩字节|54670381|

源字节、独立源唯一几何/全部 LOD、逐图片 SHA/尺寸/编码字节见 inventory.json；主楼子树不能分摊整楼文件字节。共享图片不得按实例相乘。实际 RSS、单模型 VRAM、冷/暖 FPS 未测，保守预算不等于实占。

|验收层面|结论|
|---|---|
|资源审计|通过（身份与成本清单）|
|画质|待验|
|运行管线|通过（导入/原生保存重开）|
|游戏/编辑器接入|待验|

实际查看近、中、远、背面、暗背景和反向照明联系表；重要家具另查看原尺寸细节/开门图。800×800、4×MSAA、ACES 曝光 1、FOV 40；相机和渲染计数见 report.json。这是固定静帧诊断环境，不是最终室内照明或全角度认证。

- 6 个导入纹理资源无 mip；本次没有用预览专用纹理替换，斜视/连续运动过滤质量未放行。
- 优先评估派生合批、远景 LOD/房间可见性；保留近景母版，不按固定比例强行减面。
- 静态垂坠与背面已看；室内静态悬挂允许，风场/连续动态不因已有布料几何而自动通过。
- 整楼与同 ID 独立文件的解析材质集合不完全相同；这是版本差异提示，不自动等于可见退化。

- [机器证据](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_wall_tapestry/report.json)；[近景](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_wall_tapestry/near.png)；[背面](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_wall_tapestry/back.png)；[远景](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_wall_tapestry/far.png)。
- 实际游戏碰撞、实例选择/撤销、地图保存重开仍待正式接入验收。本轮没有覆盖用户地图。
- 独立资产保留原 master/Blender 文件与 game GLB；主楼保留 entry_extension 母版和先前 finish_v1 版本。
