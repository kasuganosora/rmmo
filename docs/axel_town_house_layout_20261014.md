# 阿克塞尔参考住宅布局（2026-10-14 建档，2026-10-16 更新）

计划 21 栋住宅，包含 S1、S2、S10、S12 四组参考及 7 栋街区补充住宅。当前构建记录包含 21 栋；整体结论：通过。

正式原子发布与重开已核对。正式文件 SHA：`caf2be8e67a937af63864143f8641f2fef709229a93c116499d116c1c17a56c5`。

住宅均为居民用途，保留整栋窗型、楼层/屋顶隐藏和活动门窗语义。S1 使用规整小砌块外墙与闭合留门院墙；S2 低宅有真实圆山墙窗；S12 采用真实通高拱洞、独立双柱外拱和山墙雕饰。不可见部分与游戏尺寸属于项目补充设计。

本轮没有补齐整城背景，也不能视为四个镜头完整还原。既有组件房室内不重复测试；运行验收覆盖本轮室外入口和通路。

用户于 2026-10-15 调整顺序：先完成水系、道路桥梁、功能区和住宅通路的整体布局，再统一调整植被密度、装饰与材质细节。当前街区扩展复用既有完整户型，不以无用途空房填满地图。

地标布局单独验收：目标 2 处，当前构建记录 2 处（冒险者公会、公会告警塔）。复用已交付的正式资源库模型，不代表新制作模型；原生布局、室外通路、画面、正式接入依次为：通过、通过、通过、通过。公会只验公共外部通路，告警塔不声明具有可进入的室内。

新城的警卫处、教会和磨坊尚未建设；城墙、城门及水关仍待布局。本轮住宅与两处地标阶段通过也不等于全城完成，五处特殊建筑保留区与公会前玩家摆摊留白继续保留。

S12 连续支流水系：通过；原生采样实际长度：248.464874774218 米。五处验收包括上游、全线、小桥、急流和汇口。

S1 桥左蓝柱、桥右浅原木柱保持用户修正。S2 近南柱已使用正式库绿色原木素材。三组跨街旗串复用原生风动素材，实际挂点与风姿态以本轮场景证据为准。

| 使用模板 | 资源 | 画质 | 管线 | 正式接入 |
|---|---|---|---|---|
| building_018342a9b86d17928fe5 | 通过 | 通过 | 通过 | 通过 |
| building_022e329edecce73ebbbc | 通过 | 通过 | 通过 | 通过 |
| building_083c47c0d96f3497f32d | 通过 | 通过 | 通过 | 通过 |
| building_10e2848ee287d056ac56 | 通过 | 通过 | 通过 | 通过 |
| building_16427952a2beef846990 | 通过 | 通过 | 通过 | 通过 |
| building_220586e9028ed6139243 | 通过 | 通过 | 通过 | 通过 |
| building_9fe0774e57e3a1da3653 | 通过 | 通过 | 通过 | 通过 |
| s12_arch_hall | 通过 | 通过 | 通过 | 通过 |
| s12_small_cottage | 通过 | 通过 | 通过 | 通过 |
| s1_narrow_stone | 通过 | 通过 | 通过 | 通过 |
| s2_oculus_home | 通过 | 通过 | 通过 | 通过 |

模型验收图在查看前采用原尺寸有损 WebP quality 90；图像存在不等于视觉通过。每条已审图必须保留实际路径、SHA 和逐模板结论。精确像素比较另用明确标注的无损 WebP。

- [汇总及完整证据索引](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/house_layout_review.json)
- [实际模板与成本](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/house_template_resource_inventory.json)
- [道具净空](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/prop_clearance_audit.json)
- [旗串挂点与净高](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/festival_span_audit.json)
- [build.json](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/build.json) — 已记录
- [runtime/result.json](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/runtime/result.json) — 已记录
- [visual_acceptance.json](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/visual_acceptance.json) — 已记录
- [publication.json](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/publication.json) — 已记录
- [验收图：near.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_018342a9b86d17928fe5/near.webp) — 已核对查看记录与 SHA
- [验收图：middle.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_018342a9b86d17928fe5/middle.webp) — 已核对查看记录与 SHA
- [验收图：far.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_018342a9b86d17928fe5/far.webp) — 已核对查看记录与 SHA
- [验收图：roof_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_018342a9b86d17928fe5/roof_detail.webp) — 已核对查看记录与 SHA
- [验收图：front_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_018342a9b86d17928fe5/front_detail.webp) — 已核对查看记录与 SHA
- [验收图：near.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_022e329edecce73ebbbc/near.webp) — 已核对查看记录与 SHA
- [验收图：middle.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_022e329edecce73ebbbc/middle.webp) — 已核对查看记录与 SHA
- [验收图：far.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_022e329edecce73ebbbc/far.webp) — 已核对查看记录与 SHA
- [验收图：roof_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_022e329edecce73ebbbc/roof_detail.webp) — 已核对查看记录与 SHA
- [验收图：front_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_022e329edecce73ebbbc/front_detail.webp) — 已核对查看记录与 SHA
- [验收图：near.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_083c47c0d96f3497f32d/near.webp) — 已核对查看记录与 SHA
- [验收图：middle.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_083c47c0d96f3497f32d/middle.webp) — 已核对查看记录与 SHA
- [验收图：far.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_083c47c0d96f3497f32d/far.webp) — 已核对查看记录与 SHA
- [验收图：roof_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_083c47c0d96f3497f32d/roof_detail.webp) — 已核对查看记录与 SHA
- [验收图：front_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_083c47c0d96f3497f32d/front_detail.webp) — 已核对查看记录与 SHA
- [验收图：near.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_10e2848ee287d056ac56/near.webp) — 已核对查看记录与 SHA
- [验收图：middle.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_10e2848ee287d056ac56/middle.webp) — 已核对查看记录与 SHA
- [验收图：far.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_10e2848ee287d056ac56/far.webp) — 已核对查看记录与 SHA
- [验收图：roof_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_10e2848ee287d056ac56/roof_detail.webp) — 已核对查看记录与 SHA
- [验收图：front_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_10e2848ee287d056ac56/front_detail.webp) — 已核对查看记录与 SHA
- [验收图：near.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_16427952a2beef846990/near.webp) — 已核对查看记录与 SHA
- [验收图：middle.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_16427952a2beef846990/middle.webp) — 已核对查看记录与 SHA
- [验收图：far.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_16427952a2beef846990/far.webp) — 已核对查看记录与 SHA
- [验收图：roof_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_16427952a2beef846990/roof_detail.webp) — 已核对查看记录与 SHA
- [验收图：front_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_16427952a2beef846990/front_detail.webp) — 已核对查看记录与 SHA
- [验收图：near.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_220586e9028ed6139243/near.webp) — 已核对查看记录与 SHA
- [验收图：middle.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_220586e9028ed6139243/middle.webp) — 已核对查看记录与 SHA
- [验收图：far.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_220586e9028ed6139243/far.webp) — 已核对查看记录与 SHA
- [验收图：roof_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_220586e9028ed6139243/roof_detail.webp) — 已核对查看记录与 SHA
- [验收图：front_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_220586e9028ed6139243/front_detail.webp) — 已核对查看记录与 SHA
- [验收图：near.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_9fe0774e57e3a1da3653/near.webp) — 已核对查看记录与 SHA
- [验收图：middle.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_9fe0774e57e3a1da3653/middle.webp) — 已核对查看记录与 SHA
- [验收图：far.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_9fe0774e57e3a1da3653/far.webp) — 已核对查看记录与 SHA
- [验收图：roof_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_9fe0774e57e3a1da3653/roof_detail.webp) — 已核对查看记录与 SHA
- [验收图：front_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/building_9fe0774e57e3a1da3653/front_detail.webp) — 已核对查看记录与 SHA
- [验收图：near.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/s2_oculus_home/near.webp) — 已核对查看记录与 SHA
- [验收图：middle.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/s2_oculus_home/middle.webp) — 已核对查看记录与 SHA
- [验收图：far.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/s2_oculus_home/far.webp) — 已核对查看记录与 SHA
- [验收图：roof_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/s2_oculus_home/roof_detail.webp) — 已核对查看记录与 SHA
- [验收图：front_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/s2_oculus_home/front_detail.webp) — 已核对查看记录与 SHA
- [验收图：near.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/s12_small_cottage/near.webp) — 已核对查看记录与 SHA
- [验收图：middle.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/s12_small_cottage/middle.webp) — 已核对查看记录与 SHA
- [验收图：far.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/s12_small_cottage/far.webp) — 已核对查看记录与 SHA
- [验收图：roof_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/s12_small_cottage/roof_detail.webp) — 已核对查看记录与 SHA
- [验收图：front_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015/s12_small_cottage/front_detail.webp) — 已核对查看记录与 SHA
- [验收图：near.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015_lightstone/s1_narrow_stone/near.webp) — 已核对查看记录与 SHA
- [验收图：middle.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015_lightstone/s1_narrow_stone/middle.webp) — 已核对查看记录与 SHA
- [验收图：far.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015_lightstone/s1_narrow_stone/far.webp) — 已核对查看记录与 SHA
- [验收图：roof_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015_lightstone/s1_narrow_stone/roof_detail.webp) — 已核对查看记录与 SHA
- [验收图：front_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015_lightstone/s1_narrow_stone/front_detail.webp) — 已核对查看记录与 SHA
- [验收图：near.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015_no_course/s12_arch_hall/near.webp) — 已核对查看记录与 SHA
- [验收图：middle.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015_no_course/s12_arch_hall/middle.webp) — 已核对查看记录与 SHA
- [验收图：far.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015_no_course/s12_arch_hall/far.webp) — 已核对查看记录与 SHA
- [验收图：roof_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015_no_course/s12_arch_hall/roof_detail.webp) — 已核对查看记录与 SHA
- [验收图：front_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/template_gallery_20261015_no_course/s12_arch_hall/front_detail.webp) — 已核对查看记录与 SHA
- [验收图：east_residential_overview.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/east_residential_overview.webp) — 已核对查看记录与 SHA
- [验收图：fruit_court_overview.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/fruit_court_overview.webp) — 已核对查看记录与 SHA
- [验收图：stream_houses_overview.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/stream_houses_overview.webp) — 已核对查看记录与 SHA
- [验收图：s1_reference_houses.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s1_reference_houses.webp) — 已核对查看记录与 SHA
- [验收图：s2_reference_houses.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s2_reference_houses.webp) — 已核对查看记录与 SHA
- [验收图：s10.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s10.webp) — 已核对查看记录与 SHA
- [验收图：s12.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s12.webp) — 已核对查看记录与 SHA
- [验收图：macro_west_gate_overview.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/macro_west_gate_overview.webp) — 已核对查看记录与 SHA
- [验收图：macro_guild_outer_overview.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/macro_guild_outer_overview.webp) — 已核对查看记录与 SHA
- [验收图：macro_guild_forecourt.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/macro_guild_forecourt.webp) — 已核对查看记录与 SHA
- [验收图：macro_guild_alarm_context.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/macro_guild_alarm_context.webp) — 已核对查看记录与 SHA
- [验收图：s1_bridge_close.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s1_bridge_close.webp) — 已核对查看记录与 SHA
- [验收图：s1_bank_close.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s1_bank_close.webp) — 已核对查看记录与 SHA
- [验收图：s12_stream_close.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s12_stream_close.webp) — 已核对查看记录与 SHA
- [验收图：s2_oculus_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s2_oculus_detail.webp) — 已核对查看记录与 SHA
- [验收图：s12_arch_detail.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s12_arch_detail.webp) — 已核对查看记录与 SHA
- [验收图：s12_watercourse_overview.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s12_watercourse_overview.webp) — 已核对查看记录与 SHA
- [验收图：s12_watercourse_source.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s12_watercourse_source.webp) — 已核对查看记录与 SHA
- [验收图：s12_stream_crossing.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s12_stream_crossing.webp) — 已核对查看记录与 SHA
- [验收图：s12_stream_rapid.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s12_stream_rapid.webp) — 已核对查看记录与 SHA
- [验收图：s12_stream_confluence.webp](D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/scene_reviews/4675e1a9fde8-8eda5763df/s12_stream_confluence.webp) — 已核对查看记录与 SHA
