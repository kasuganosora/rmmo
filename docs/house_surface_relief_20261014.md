# 普通房屋屋顶与外墙表面层次 · 2026-10-14

用户要求：完成公会等模型导入后，改善普通房屋屋顶与墙面纹理过平、缺乏质感的问题；原来的地图不用处理。前序 64 件已全部正式导入并通过编辑器复验，见 [导入记录](../review_artifacts/guild_reference_recheck_20261013/formal_import/README.md)。本轮使用 `rmmo-model-review` 复验受影响的材质、资源与保存管线。

状态：完成。三个选定材质已写入正式材质库，并通过正式目录刷面、冻结样房保存重开及实际GPU贴图绑定复验。原地图与原共享贴图保持不变。

## 范围和原因

- 普通屋顶实际有 `terracotta_plain`、`terracotta_warm` 两款方形红陶叠瓦，颜色不同、法线与粗糙度相同。保留原色图、4×4 错缝布局与 1×0.72 米的铺贴范围，不移植公会的鱼鳞瓦图案。
- 默认浅米黄泥灰外墙 `earthen_plaster` 只有颜色图和固定粗糙度 0.98，没有法线图；保留米黄抹面身份及 2×2 米尺度，增加适度细砂和抹面受光层次。
- 其他七类外用墙面纳入近景斜光检查：手工灰泥、外墙石灰抹面、浅色石砌、风化石砖、古城石墙、红砖和暖色乱石。已有充分凹凸者保留，不统一放大所有法线。
- 蓝灰内墙、白刷内墙不属于本轮外表面优化范围。没有新增石板瓦、木瓦或修改房屋几何。

实际运行管线已接入法线、粗糙度和 AO，屋顶、墙面及刷面均生成切线，没有证据支持“所有法线都没生效”。DirectX 贴图按已有约定转换一次绿色通道；普通材质未启用几何位移是现有合同，法线优化不等于真实轮廓厚度或位移。

## 候选方法

屋瓦按实际色图接缝追踪错缝边界，在米制尺度下补瓦身缓弧及搭接边，归一法线并限制尖峰；保留颜色和粗糙度字节，不把高频噪声增强当成瓦片厚度。制作适中和较强两版供固定机位比较，最终版本由真实渲染判断。

泥灰墙复用已购 Construction Plaster 的扫描凹凸信息，保留低幅抹痕和砂粒，排除与现有色图不相符的大裂痕。1 米扫描在 2 米材质覆盖范围内正确重复，避免把抹痕放大两倍。粗糙度保持干燥泥灰特征。此项为项目复合材质，不宣称原色图与扫描凹凸来自同一次实物采集。

## 验收和发布边界

[原始身份与成本清单](../review_artifacts/house_surface_relief_20261014/baseline_inventory.json) 记录十族定义、各通道 SHA、尺寸、原图路径和回退定义；RGBA8 成本是预算口径，不是实测内存或显存。

在隔离内容根中通过真实材质目录、HTTP 刷面和冻结保存重开建立样房及实比例材质片。锁定相机、光照、曝光、尺寸和抗锯齿，检查近中远、斜光、细节与平铺边界。图像在发送 OpenAI 前使用 WebP。实际运行材质必须保留新通道、物理尺度和正常切线，不能只检查源图。

材质定义更新不会自动改变已冻结房屋的材质快照。本轮新通道使用新文件路径，保留原共享贴图；通过后更新材质库供新的刷面与制作使用，不迁移旧地图或用同路径覆盖暗改旧场景。门窗、碰撞、逐楼层和屋顶隐藏语义保持原有合同，只复验受本轮材质操作影响的部分。

雨天湿润覆盖另有既有着色路径，不能把干燥材质样片结果推广为所有天气。若近景中发现与本轮纹理有关的实际问题，再按受影响范围修复与复验，不用整城性能测试替代材质验收。

## 第一轮检查记录

十款原材质与三个重点样房完成基线；适中、较强候选均通过真实目录发现、刷面、撤销重做、非法操作无副作用及保存重开。第一轮目视未放行：屋瓦和泥灰墙的受光变化不够明确，不能用管线检查通过代替“质感改善”。

检查发现统一斜光适合朝 +Z 的材料片，但对细节相机看到的 +X 屋面及 -Z 外墙主要形成背光。追加诊断直接重开已保存样房，核对实际 GPU 纹理像素、法线开关/强度及切线，并使用各表面确实受到照射的固定斜光进行双向比较。原始截图与报告保留，不以补拍覆盖不充分的证据。

其他墙面目视：风化石砖、古城石墙已有清晰石块/灰缝层次；浅色石砌表现为厚石灰涂层覆盖的圆钝石块，不能当成裸石后继续放大粗糙度；暖色乱石本身凹凸明显。手工灰泥、石灰抹面和红砖保留各自表面身份，不把所有墙都做成粗糙岩石。

## 选定结果与对比

| 材质 | 选定版本 | 本轮效果与边界 |
| --- | --- | --- |
| 手工红陶叠瓦 `terracotta_plain` | strong | 增加瓦身缓弧和连续搭接边受光；保留原色、1254²尺寸和粗糙度。 |
| 暖橙陶瓦 `terracotta_warm` | strong | 共用同一新法线文件；保持暖色方案和原瓦片布局。 |
| 浅米黄泥灰 `earthen_plaster` | v2 | 原材质无凹凸通道；补扫描细砂及25–90mm尺度的柔和抹痕，保持干燥哑光。 |

泥灰第一轮两版的中尺度受光不足，未发布。v2 在原 strong 细粒基础上增加约 −0.84～+0.97mm 的柔和抹痕，总合成高度约 −1.36～+1.56mm；这些是项目设计幅度，并非扫描绝对尺寸测量。只以法线表现，不改变墙面几何。屋瓦的更强版在迎光特写中厚边更连贯，瓦身仍为粗陶，没有增加塑料反光。

同光照对比（WebP）：

- 红陶瓦：[原版](D:/code/rmmo_runtime/review_artifacts/house_surface_relief_20261014/gallery/diagnostic/baseline/roofs/terracotta_plain/roof_facing_raking_close.webp) / [选定版](D:/code/rmmo_runtime/review_artifacts/house_surface_relief_20261014/gallery/diagnostic/strong/roofs/terracotta_plain/roof_facing_raking_close.webp)。
- 泥灰墙：[原版](D:/code/rmmo_runtime/review_artifacts/house_surface_relief_20261014/gallery/diagnostic/wall_v2/baseline/walls/earthen_plaster/facade_facing_raking_close.webp) / [选定版](D:/code/rmmo_runtime/review_artifacts/house_surface_relief_20261014/gallery/diagnostic/wall_v2/wall_v2/walls/earthen_plaster/facade_facing_raking_close.webp)。
- [组合样房](D:/code/rmmo_runtime/review_artifacts/house_surface_relief_20261014/gallery/candidate/wall_v2/walls/earthen_plaster/house_near.webp)；[根代理逐款视觉结论](../review_artifacts/house_surface_relief_20261014/selected_visual_review.json)。

迎光诊断直接核对实际 MeshInstance3D 使用的材质，GPU读取的颜色、法线、粗糙度像素与相应源图一致，法线开关、强度和切线完整。每张诊断图记录光照对表面法线的入射点积；背光截图不单独作为凹凸效果的放行依据。远处和环境光占主导时细节仍会弱化，没有为了远处可见而夸大高频颗粒。

泥灰原色图在右侧斜光样片中有既有的色调平铺边界，本轮保留原色图，没有宣称解决了这一旧问题，也没有以更强法线掩盖它。

## 成本、几何与发布记录

[成本清单](../review_artifacts/house_surface_relief_20261014/selected_resource_costs.json) 区分按材质、按唯一SHA和按实际引用路径统计。两款屋瓦不增加分辨率或每款通道数；泥灰增加2048²法线和粗糙度，实际基础图片解码增加16 MiB，保守RGBA8含mip预算增加约42.67 MiB。上述不是实测RSS/VRAM，也不按房屋实例数重复相乘。正式库保留全部旧纹理，新文件实际增加5,438,765字节（约5.19 MiB，不含JSON、母版及验收夹具）。

比较冻结前后逐通道几何：位置、顶点法线、UV、索引、碰撞、包围盒和LOD均保持一致。泥灰新增法线使样房四个渲染组补齐5,064个切线浮点数，共20,256字节解码数据；不是新三角面。v2与上一强版连切线也完全相同。现有LOD无需因本轮材质修改重新减面。证据：[首轮几何比较](../review_artifacts/house_surface_relief_20261014/gallery/geometry_comparison.json)、[v2几何比较](../review_artifacts/house_surface_relief_20261014/gallery/geometry_wall_v2_comparison.json)。

[正式发布收据](../review_artifacts/house_surface_relief_20261014/publication_receipt.json) 绑定选定候选、制作配方、GPU报告与视觉判定SHA。更新3份材质定义、新增3个技术图文件；两款屋瓦共用一个新法线。原有通道、另外7份外墙定义、正式模型目录和受保护的主地图SHA未变。其他旧地图不在写入范围，没有遍历全部旧地图后宣称逐一验证。小范围回退定义保存在 `rollback_material_definitions`，沿用原子写入与冲突保护，没有复制整份用户地图。

## 最终验收状态

| 项目 | 结论 | 证据 |
| --- | --- | --- |
| 资源 | 通过 | 实际源图/正式图/材质定义SHA一致，逐通道成本及回退版本齐全。 |
| 画质 | 通过本轮修改 | 根代理检查同机位近中远、迎光细节与双向斜光；既有色图限制如上记录。 |
| 运行管线 | 通过 | 实际渲染材质的纹理像素、法线强度及切线验证通过，冻结/保存不丢通道。 |
| 编辑器材质库接入 | 通过 | 从正式default目录读取3款材质，真实HTTP刷面、非法调用无副作用、撤销重做和保存重开，5,084项检查、0失败。 |
| 旧地图迁移 | 不适用 | 用户要求原地图不用处理；保留旧贴图，未迁移旧冻结材质快照。 |

[正式目录验收](../review_artifacts/house_surface_relief_20261014/gallery/published/report.json)、[与候选的逐项对照](../review_artifacts/house_surface_relief_20261014/gallery/published/comparison.json)、[最终逐款结论与管线SHA](../review_artifacts/house_surface_relief_20261014/review_summary.json)。近中远观察只覆盖记录的相机与照明，未将静态图或预算数字扩展为全天候、连续运动或实测显存结论。
