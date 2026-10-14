# 大厅方柱落地灯 · guild_hall_lantern

参考：U02,U03,U05,U12

日/夜图保留黑金属、玻璃和暖白菱石。独立夜景只确认发光层；该机位邻近真光为0，真光预算须看运行专项。

目视：通过：参考与已授权补充设计、材质读感和同条件近中远/背面/高光检查未见阻塞缺陷
证据方式：本次 accepted_library 实际逐图复看
管线：通过：本轮GLB→Native保存/重开及几何、材质、extras等价，实际SHA与manifest一致
运行：日/夜可视项已看；邻近真光/昼夜逻辑/预算的整楼运行专项待最终汇总证据
接入：正式内容编辑器/地图部署尚未在此验收

最终源 SHA256：`9e83ddde3ff64a16d54b781240f5451e7bb8a1854323d905a2f79c9c95866eab`

[本轮原生报告](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_hall_lantern/report.json)

## 实际查看图像

- [back_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_hall_lantern/back_still.png) · `3764e2c849f6805051ee895b345052d980abb411c99d42b71a38035bde11da55`
- [far_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_hall_lantern/far_still.png) · `4670d88e0bba3115047926433af7e54f2de519e1219ffc54a7cc11b898cfee4d`
- [highlight_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_hall_lantern/highlight_still.png) · `0c9af463e89dabd2aba23b3d2e6c3c19c4f78bb1196565d8dcf387a6a44a6375`
- [medium_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_hall_lantern/medium_still.png) · `df07bb9b7c8a857fc472a0d9bdefaeca0f4893e3fc833c4b28f413afea8bc876`
- [near_night_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_hall_lantern/near_night_still.png) · `978153853b6ca065bed964b7496d00eafabe580f9a018d8bcfd79216f56d14c6`
- [near_still](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/guild_hall_lantern/near_still.png) · `36b0c17d5c76e17888eb2251a9fcd38bf01f9dedcf07889d1bb2af72107c3589`

前次缺陷、前次源SHA与复验记录保存在同名JSON的visual_history。

## 菱石灯运行修复复验

菱石自投影修复：20 项 CPU 回归和当前源整楼夜景通过；昼夜灯池/预算最终运行报告待汇总。

[修复及实图证据](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/lighting_visual_recheck.md)。原独立夜景保留原观察，不将旧截图改称修复后图。
