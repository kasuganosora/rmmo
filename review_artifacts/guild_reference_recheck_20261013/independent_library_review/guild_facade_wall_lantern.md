# 入口壁灯 · guild_facade_wall_lantern

参考：U19,U35; 用户暖白菱形魔法石修正

新源已另查日/夜图：四玻璃片内暖白菱石可辨，夜景壳体受暖光照亮，金属与玻璃无材质回退。

目视：通过：参考与已授权补充设计、材质读感和同条件近中远/背面/高光检查未见阻塞缺陷
证据方式：本次 accepted_library 实际逐图复看
管线：通过：本轮GLB→Native保存/重开及几何、材质、extras等价，实际SHA与manifest一致
运行：日/夜可视项已看；邻近真光/昼夜逻辑/预算的整楼运行专项待最终汇总证据
接入：正式内容编辑器/地图部署尚未在此验收

最终源 SHA256：`84cfe93ecd6fe48aeeb7b4094242b3d3dc5e3adaa63245d7d475d924eadea0ed`

[本轮原生报告](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_facade_wall_lantern/report.json)

## 实际查看图像

- [back_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_facade_wall_lantern/back_still.png) · `b6ead12883a5b5a172da3c4cf543c0ff4069522df72fb982aede69e213d910de`
- [far_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_facade_wall_lantern/far_still.png) · `eadf52d2e865636f6559ee8c9a5385c48c1ae1937bd547778e90a48691e2cf15`
- [highlight_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_facade_wall_lantern/highlight_still.png) · `30a2946928ddc339305df86cbcdc4ed2a7085d779ba37d8a0d1791d76a961d73`
- [medium_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_facade_wall_lantern/medium_still.png) · `52c875fda0f8371013368be9920b61fc05606afe58afd8fcc85f25eb792c634d`
- [near_night_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_facade_wall_lantern/near_night_still.png) · `441d27d6c26e000116364f0fd20f6fcf602977019dbc36ed4d49050b18e5b616`
- [near_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_facade_wall_lantern/near_still.png) · `c609ec7e63871624aa98527f7448cc68bce873bcf0998e5f81f703ec7f91ad4b`

前次缺陷、前次源SHA与复验记录保存在同名JSON的visual_history。

## 菱石灯运行修复复验

菱石自投影修复：20 项 CPU 回归和当前源整楼夜景通过；昼夜灯池/预算最终运行报告待汇总。

[修复及实图证据](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/lighting_visual_recheck.md)。原独立夜景保留原观察，不将旧截图改称修复后图。
