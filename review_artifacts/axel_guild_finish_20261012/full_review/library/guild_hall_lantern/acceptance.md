# 大厅方柱落地灯 · library · 2026-10-12

- ID：`guild_hall_lantern`；范围：独立素材文件。原模型没有改动，不宣称压缩或严格像素无损。
- 实际源：[D:/code/rmmo_runtime/art_sources/axel_guild/furniture_v1/game/guild_hall_lantern.glb](D:/code/rmmo_runtime/art_sources/axel_guild/furniture_v1/game/guild_hall_lantern.glb)
- SHA256：`a097b346a132d41ce91c2c4fe3704f527204fc54399e17c436c1590b93fd8b52`
- 主楼节点：`不适用`；该类型实例数：1。
- Native SHA256：`e6eb65e15e91b65ef65e28edd1dcb3512689310607498fae32de898eb4cbf8cc`；generator：`50d0b3e04b372b98fac1762e185e71a37bdafb405099e4b8fd30395141d5e84f`。
- 参考：公会设定文档及其对应 U 图；卫生设备隐藏结构按项目补充设计。独立库存阶段见 inventory.json。

|项目|本轮实测/统计|
|---|---:|
|Native 压缩字节|51,971|
|实例展开三角面|2,808|
|Mesh 节点 / 材质 / 导入纹理资源|3 / 3 / 0|
|近景绘制次数（含测试地面）|4|
|纹理无 mip 的资源数|0|
|GPU RGBA 保守字节预算|动画合同不适用；未测|
|native 未压缩字节|113653|

源字节、独立源唯一几何/全部 LOD、逐图片 SHA/尺寸/编码字节见 inventory.json；主楼子树不能分摊整楼文件字节。共享图片不得按实例相乘。实际 RSS、单模型 VRAM、冷/暖 FPS 未测，保守预算不等于实占。

|验收层面|结论|
|---|---|
|资源审计|通过（身份与成本清单）|
|画质|不通过（旧版本）|
|运行管线|通过（导入/原生保存重开）|
|游戏/编辑器接入|不通过（照明接入未完成）|

实际查看近、中、远、背面、暗背景和反向照明联系表；重要家具另查看原尺寸细节/开门图。800×800、4×MSAA、ACES 曝光 1、FOV 40；相机和渲染计数见 report.json。这是固定静帧诊断环境，不是最终室内照明或全角度认证。

- 未发现仅为面数比例而需要立即降面的依据；先处理纹理过滤、共享资源及场景批次。大规模重复部署时重评。
- 日照、暗背景与反向光照画面已检查；自发光不等于照亮场景。实际点光源、阴影预算、昼夜绑定未接入。
- 这是被用户纠正的旧绿色灯柱/不透明灯片版本；选用 guild_hall_magic_lantern 或主楼中黑金属魔法石版本。
- 整楼与同 ID 独立文件的解析材质集合不完全相同；这是版本差异提示，不自动等于可见退化。

- [机器证据](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_hall_lantern/report.json)；[近景](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_hall_lantern/near.png)；[背面](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_hall_lantern/back.png)；[远景](D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review/library/guild_hall_lantern/far.png)。
- 实际游戏碰撞、实例选择/撤销、地图保存重开仍待正式接入验收。本轮没有覆盖用户地图。
- 独立资产保留原 master/Blender 文件与 game GLB；主楼保留 entry_extension 母版和先前 finish_v1 版本。
