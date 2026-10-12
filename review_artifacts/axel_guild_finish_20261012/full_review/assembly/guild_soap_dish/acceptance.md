# 陶制皂碟 · assembly · 2026-10-12

- ID：`guild_soap_dish`；范围：主楼中首个同类实例的独立子树。原模型没有改动，不宣称压缩或严格像素无损。
- 实际源：[D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/entry_extension/axel_guild_entry.glb](D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/entry_extension/axel_guild_entry.glb)
- SHA256：`b5498b3278fc5f2e929bd1b8d410b6896b5c6f8bb3c58212e328b71220318567`
- 主楼节点：`32_Furniture_L1/Guild_soap_dish_058`；该类型实例数：1。
- Native SHA256：`26c867215ba598b1f645c877b6f826c5372d9f4e703d6900d4d99777db33ac25`；generator：`50d0b3e04b372b98fac1762e185e71a37bdafb405099e4b8fd30395141d5e84f`。
- 参考：公会设定文档及其对应 U 图；卫生设备隐藏结构按项目补充设计。独立库存阶段见 inventory.json。

|项目|本轮实测/统计|
|---|---:|
|Native 压缩字节|881,422|
|实例展开三角面|2,124|
|Mesh 节点 / 材质 / 导入纹理资源|2 / 2 / 1|
|近景绘制次数（含测试地面）|3|
|纹理无 mip 的资源数|1|
|GPU RGBA 保守字节预算|动画合同不适用；未测|
|native 未压缩字节|3208441|

源字节、独立源唯一几何/全部 LOD、逐图片 SHA/尺寸/编码字节见 inventory.json；主楼子树不能分摊整楼文件字节。共享图片不得按实例相乘。实际 RSS、单模型 VRAM、冷/暖 FPS 未测，保守预算不等于实占。

|验收层面|结论|
|---|---|
|资源审计|通过（身份与成本清单）|
|画质|待验|
|运行管线|通过（导入/原生保存重开）|
|游戏/编辑器接入|待验|

实际查看近、中、远、背面、暗背景和反向照明联系表；重要家具另查看原尺寸细节/开门图。800×800、4×MSAA、ACES 曝光 1、FOV 40；相机和渲染计数见 report.json。这是固定静帧诊断环境，不是最终室内照明或全角度认证。

- 1 个导入纹理资源无 mip；本次没有用预览专用纹理替换，斜视/连续运动过滤质量未放行。
- 未发现仅为面数比例而需要立即降面的依据；先处理纹理过滤、共享资源及场景批次。大规模重复部署时重评。

- [机器证据](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/assembly/guild_soap_dish/report.json)；[近景](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/assembly/guild_soap_dish/near.png)；[背面](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/assembly/guild_soap_dish/back.png)；[远景](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/assembly/guild_soap_dish/far.png)。
- 实际游戏碰撞、实例选择/撤销、地图保存重开仍待正式接入验收。本轮没有覆盖用户地图。
- 独立资产保留原 master/Blender 文件与 game GLB；主楼保留 entry_extension 母版和先前 finish_v1 版本。
