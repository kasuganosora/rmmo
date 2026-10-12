# 拱饰低柜 · library · 2026-10-12

- ID：`guild_guest_low_cabinet`；范围：独立素材文件。原模型没有改动，不宣称压缩或严格像素无损。
- 实际源：[D:/code/rmmo_runtime/art_sources/axel_guild/guestroom_v1/game/guild_guest_low_cabinet.glb](D:/code/rmmo_runtime/art_sources/axel_guild/guestroom_v1/game/guild_guest_low_cabinet.glb)
- SHA256：`b9d1c22eefe1051a2d7a51726f9f4a1f5d207f5ad946de5ace23e60be593546e`
- 主楼节点：`不适用`；该类型实例数：1。
- Native SHA256：`0885175b5d6c12c3da84f3c8754b89a5ba23893aad76e0d0edbb90a2b06d9d04`；generator：`50d0b3e04b372b98fac1762e185e71a37bdafb405099e4b8fd30395141d5e84f`。
- 参考：公会设定文档及其对应 U 图；卫生设备隐藏结构按项目补充设计。独立库存阶段见 inventory.json。

|项目|本轮实测/统计|
|---|---:|
|Native 压缩字节|20,602,447|
|实例展开三角面|8,372|
|Mesh 节点 / 材质 / 导入纹理资源|10 / 3 / 3|
|近景绘制次数（含测试地面）|11|
|纹理无 mip 的资源数|3|
|GPU RGBA 保守字节预算|动画合同不适用；未测|
|native 未压缩字节|未测|

源字节、独立源唯一几何/全部 LOD、逐图片 SHA/尺寸/编码字节见 inventory.json；主楼子树不能分摊整楼文件字节。共享图片不得按实例相乘。实际 RSS、单模型 VRAM、冷/暖 FPS 未测，保守预算不等于实占。

|验收层面|结论|
|---|---|
|资源审计|通过（身份与成本清单）|
|画质|待验|
|运行管线|部分通过（动画往返通过；静态缓存不适用）|
|游戏/编辑器接入|待验（动画模型输入与碰撞）|

实际查看近、中、远、背面、暗背景和反向照明联系表；重要家具另查看原尺寸细节/开门图。800×800、4×MSAA、ACES 曝光 1、FOV 40；相机和渲染计数见 report.json。这是固定静帧诊断环境，不是最终室内照明或全角度认证。

- 3 个导入纹理资源无 mip；本次没有用预览专用纹理替换，斜视/连续运动过滤质量未放行。
- 未发现仅为面数比例而需要立即降面的依据；先处理纹理过滤、共享资源及场景批次。大规模重复部署时重评。
- Open/Close 动作、95° 角度、固定铰链与柜体通过；native 旋转值逐键相同，时间误差小于 1 微秒。静态缓存不支持 AnimationPlayer，不能删动作来绕过限制。活动碰撞/输入尚未接入。
- 整楼与同 ID 独立文件的解析材质集合不完全相同；这是版本差异提示，不自动等于可见退化。

- [机器证据](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_guest_low_cabinet/report.json)；[近景](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_guest_low_cabinet/near.png)；[背面](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_guest_low_cabinet/back.png)；[远景](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_guest_low_cabinet/far.png)。
- 实际游戏碰撞、实例选择/撤销、地图保存重开仍待正式接入验收。本轮没有覆盖用户地图。
- 独立资产保留原 master/Blender 文件与 game GLB；主楼保留 entry_extension 母版和先前 finish_v1 版本。
