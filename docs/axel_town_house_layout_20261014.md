# 阿克塞尔参考住宅布局（2026-10-14）

计划 14 栋住宅，对应 S1、S2、S10、S12 四组参考。当前构建记录包含 0 栋；整体结论：待验。

本页当前记录候选制作与验收阶段，尚无完整正式接入通过结论。

住宅均为居民用途，保留整栋窗型、楼层/屋顶隐藏和活动门窗语义。S1 使用规整小砌块外墙与闭合留门院墙；S2 低宅有真实圆山墙窗；S12 采用真实通高拱洞、独立双柱外拱和山墙雕饰。不可见部分与游戏尺寸属于项目补充设计。

本轮没有补齐整城背景，也不能视为四个镜头完整还原。既有组件房室内不重复测试；运行验收覆盖本轮室外入口和通路。

S1 桥左蓝柱、桥右浅原木柱保持用户修正。S2 近南绿色柱缺少正式库素材，暂用已验收原木柱；未引入旧隔离缓存的绿色版本。三组跨街旗串复用原生风动素材，柱高约 6.43 m，CPU 沿地形最低旗底净高约 3.83 m，实际风姿态仍以本轮画面证据为准。

| 使用模板 | 资源 | 画质 | 管线 | 正式接入 |
|---|---|---|---|---|
| building_018342a9b86d17928fe5 | 通过 | 待验 | 未通过 | 待验 |
| building_022e329edecce73ebbbc | 通过 | 待验 | 未通过 | 待验 |
| building_083c47c0d96f3497f32d | 通过 | 待验 | 未通过 | 待验 |
| building_10e2848ee287d056ac56 | 通过 | 待验 | 未通过 | 待验 |
| building_16427952a2beef846990 | 通过 | 待验 | 未通过 | 待验 |
| building_220586e9028ed6139243 | 通过 | 待验 | 未通过 | 待验 |
| building_9fe0774e57e3a1da3653 | 通过 | 待验 | 未通过 | 待验 |
| s12_arch_hall | 通过 | 待验 | 未通过 | 待验 |
| s12_small_cottage | 通过 | 待验 | 未通过 | 待验 |
| s1_narrow_stone | 通过 | 待验 | 未通过 | 待验 |
| s2_oculus_home | 通过 | 待验 | 未通过 | 待验 |

模型验收图在查看前采用原尺寸有损 WebP quality 90；图像存在不等于视觉通过。每条已审图必须保留实际路径、SHA 和逐模板结论。精确像素比较另用明确标注的无损 WebP。

- [汇总及完整证据索引](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/house_layout_review.json)
- [实际模板与成本](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/house_template_resource_inventory.json)
- [道具净空](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/prop_clearance_audit.json)
- [旗串挂点与净高](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/festival_span_audit.json)
- [build.json](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/build.json) — 已记录
- [runtime/result.json](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/runtime/result.json) — 待生成
- [visual_acceptance.json](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/visual_acceptance.json) — 待生成
- [publication.json](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/publication.json) — 待生成
