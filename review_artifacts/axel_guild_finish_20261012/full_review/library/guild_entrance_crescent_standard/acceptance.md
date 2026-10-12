# guild_entrance_crescent_standard · library · 2026-10-12

- ID：`guild_entrance_crescent_standard`；范围：独立素材文件。原模型没有改动，不宣称压缩或严格像素无损。
- 实际源：[D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/guild_entrance_crescent_standard.glb](D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/guild_entrance_crescent_standard.glb)
- SHA256：`66e890457aad8ad9057497da0050fb6e193cb9f261ac0fa5ec63380b2d852513`
- 主楼节点：`不适用`；该类型实例数：1。
- Native SHA256：`a95bf489ec364c3be0f7d39cb0b99de3ba5210e5d014edecdaa9a15830b6c37d`；generator：`50d0b3e04b372b98fac1762e185e71a37bdafb405099e4b8fd30395141d5e84f`。
- 参考：公会设定文档及其对应 U 图；卫生设备隐藏结构按项目补充设计。独立库存阶段见 inventory.json。

|项目|本轮实测/统计|
|---|---:|
|Native 压缩字节|27,206|
|实例展开三角面|3,222|
|Mesh 节点 / 材质 / 导入纹理资源|1 / 1 / 0|
|近景绘制次数（含测试地面）|2|
|纹理无 mip 的资源数|0|
|GPU RGBA 保守字节预算|动画合同不适用；未测|
|native 未压缩字节|46228|

源字节、独立源唯一几何/全部 LOD、逐图片 SHA/尺寸/编码字节见 inventory.json；主楼子树不能分摊整楼文件字节。共享图片不得按实例相乘。实际 RSS、单模型 VRAM、冷/暖 FPS 未测，保守预算不等于实占。

|验收层面|结论|
|---|---|
|资源审计|通过（身份与成本清单）|
|画质|通过（本轮固定静帧范围）|
|运行管线|通过（导入/原生保存重开）|
|游戏/编辑器接入|待验|

实际查看近、中、远、背面、暗背景和反向照明联系表；重要家具另查看原尺寸细节/开门图。800×800、4×MSAA、ACES 曝光 1、FOV 40；相机和渲染计数见 report.json。这是固定静帧诊断环境，不是最终室内照明或全角度认证。

- 未发现仅为面数比例而需要立即降面的依据；先处理纹理过滤、共享资源及场景批次。大规模重复部署时重评。

- [机器证据](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_entrance_crescent_standard/report.json)；[近景](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_entrance_crescent_standard/near.png)；[背面](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_entrance_crescent_standard/back.png)；[远景](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_entrance_crescent_standard/far.png)。
- 实际游戏碰撞、实例选择/撤销、地图保存重开仍待正式接入验收。本轮没有覆盖用户地图。
- 独立资产保留原 master/Blender 文件与 game GLB；主楼保留 entry_extension 母版和先前 finish_v1 版本。
