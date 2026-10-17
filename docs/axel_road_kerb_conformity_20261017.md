# Axel 教堂/拱门附近道路悬空路缘修复（2026-10-17）

## 结论与范围

用户报告的是游戏运行画面。定位在桥 2 东岸、S12 拱门南侧约 `(342, 170)`，最明显记录为 `pavement_b7bbe48deca3f7d2b741`。道路顶部已按地形三角面细分，但长路缘仅采样两个端点，中段跨过地形凹处，最大悬空 **0.477755 m**，形成横穿铺面的长台阶/双层路面错觉。

这是 UI 与当前 3D MCP 共用的道路贴地生成缺陷。编辑器使用 `Road.mesh`，游戏后台准备使用 `Road.arrays`；对同一修复记录，两者实际网格数组 SHA 都为 `3d24cbab9fc247b99a636358f088cb460eb496fdf23987c6de5cdf46ac7ec452`。加载和合批入口不同，不代表此处生成了不同道路。见 [实际数组核对](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/shared_geometry.json)。

已通过原生 `generate_road_surface` HTTP 操作重建全图同类派生路缘：2369 个实例保留，326 块道路中 323 块发生路缘变化。逐记录排除 `road_mesh.kerbs` 后完全相同；除派生道路清单外，元数据完全相同。道路顶部、UV、材料、地形、河流、桥、建筑、植物、镜头和道路图均未改动。S1 的用户手工微调不属于本轮修改。

## 实现与编辑语义

新增 `terrain_kerb_fit.gd`：沿六条轮廓纵线在实际地形网格边和对角线处切分，再交由现有采样投影流程贴地。原始控制数据保留在 `terrain_follow.kerbs`；重算不逐次增加细分。保留 UV 累计长度、原端点、外端封口；不在内部切分处新增端盖。合并近重合交点，拒绝超出每块 8192 段的结果并由既有道路分块流程处理。

UI 与当前 3D MCP 仍调用同一业务操作，无新增工具/schema。保留既有锁定、保护、材质、撤销重做、保存及自动合批。新增生成器源文件纳入派生缓存版本指纹。旧地图需要原生重建后保存；本次正式城镇已经完成该步骤。

## 受影响模型项复验

按 `rmmo-model-review` 执行程序化道路几何受影响项，不重复房屋室内或无关模型验收。参考为用户提供的错误运行截图及已有连续石质路缘方案；本轮修正贴地，不设计新建筑结构。

| 项目 | 结果与证据 |
| --- | --- |
| 资源与身份 | 派生地图、逐道路记录 SHA、实际生成三角形和材质指纹见 [几何审计](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/geometry_audit.json)；生成源代码 SHA 见 [接入清单](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/integration.json)。 |
| 接地/碰撞 | 重点区域内部采样最大误差由 0.477755 m 降至 0.000003281 m；无非有限顶点。普通 W 键两段室外实走通过，未支撑 tick 均为 0。 |
| 可编辑/管线 | 88 项回归检查通过，包含实际 HTTP 工具发现、合法/非法调用、保护失败无副作用、撤销重做、贴图和地形修改后保存重开。旧代码运行同一新增逻辑回归出现 2 项失败，修复后通过。 |
| 画质 | 相同相机、分辨率、环境和曝光的四处远景/中景/近景逐图对比：悬空边及下层楔形错觉消失，连续石材纹理保留，未发现新接缝。候选运行和画面通过。 |
| 正式接入 | 原生原子保存及冲突检测通过，正式重开与已验收候选逐记录/元数据一致。正式地图经普通 LoadingScene 加载复拍通过，见下述正式接入复核。 |
| 不适用项 | 无骨骼、活动件、透明叶片、风场；不重复角色、房屋室内和整城性能专项。 |

全图路缘实际三角形由 **24,088** 增为 **301,564**，用于保留起伏接地；这不是减面优化。没有另造逐块缘石实例或材质。当前简单轮廓不另建独立 LOD，仍受现有道路分块预算及派生批次约束。运行反向机位记录自动合批开启，3343 个来源 surface 合为 358 个渲染 surface，待合批组为 0；此处仅确认既有自动处理保留，不作为全城性能结论。

六张复用纹理原文件及 SHA 未变，文件总大小 12,786,015 字节。RGBA8 解码预算 60 MiB，含 mip 预算 80 MiB；这是保守估算，**不是实测 RSS/VRAM**。详见 [纹理审计](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/texture_audit.json)。无需新 GLB 或 Blender 母版；原生作者控制数据保留，Windows 原子保存保留 `.previous` 恢复版本，未另复制整份地图目录。

## 原生保存身份

| 内容 | SHA-256 |
| --- | --- |
| 修复前正式地图 | `f3009b1841c99174ce1bee6509a58fde814a921290ccb882f0c435478c54a2bc` |
| 已验收临时候选 | `6cb48037d3d0f1cd6dbdce2c7248c5c08e72fc54af7f373d1fcf7a3ab861e378` |
| 保存后正式地图 | `2786d854c6fb1f2a9a2803f1227ab3ab07b7381e217e541e893e173b26f070f8` |

候选与正式文件 SHA 因保存封装而不同；[发布核对](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/publication.json) 已通过记录和元数据全等核对。正式地图为 `D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf`，出生地图配置不变。[原生生成/撤销重做/候选重开](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/authoring/authoring.json)；[回归日志](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/conformity_test_retry.log)；[修复前回归失败证据](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/conformity_baseline.log)。

## 画面证据

截图通过私有不激活桌面、正式 LoadingScene 与正常流式加载拍摄，不扩大驻留半径、不改就绪条件，角色渲染临时隐藏并恢复。全部 1600×900、FOV 50，实际有损 WebP Q90；压缩凭证和图像 SHA 位于 [候选运行报告](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/fixed_runtime/result.json)，四图已经查看。参考图中的角色不在还原范围。

| 机位 | 图像 | SHA-256 |
| --- | --- | --- |
| bridge2_east_road | [Q90 实拍](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/fixed_runtime/images_1792237751_875/bridge2_east_road.webp) | `c56ee4f719fce14bfbf39abc9f4ff0f4b0f03b81697dc95e601d770c4de89161` |
| bridge2_east_reverse | [Q90 实拍](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/fixed_runtime/images_1792237751_875/bridge2_east_reverse.webp) | `69320c800d49b7b04493378623e26041706710916192bd48380e3a639b635c7b` |
| kerb_detail | [Q90 实拍](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/fixed_runtime/images_1792237751_875/kerb_detail.webp) | `733dc3c5c336db746c288b7796d2053788a43450b64f79c671e5d9cce7b89bdc` |
| s12_south_junction | [Q90 实拍](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/fixed_runtime/images_1792237751_875/s12_south_junction.webp) | `7561bd5cb06c3b3935e3049c5257591691493630e1ba1c25195c9a6426112abe` |

修复前同机位：[中景](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/baseline_c_retry/images_1792236752_638/bridge2_east_road.webp)、[近景](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/baseline_detail_safe/images_1792237561_264/kerb_detail.webp)。初次 `baseline_detail` 因不合适的定位点未完成；采用附近已有支撑的位置后保持原相机复拍，验收采用 `baseline_detail_safe`。早期导入/解析失败和中断运行保留为诊断，不计为通过证据。

本报告只关闭该道路问题，不宣称 S1/S2/S10/S12 所有构图与布景细节已完成。当前会话继续以布局和设定镜头为主。

## 正式接入复核

修复代码接入主工作目录后，使用更新后的缓存生成器指纹重新启动私有桌面游戏，加载上述正式地图。13 项实际运行检查通过，失败 0；同机位复拍已查看，悬空台阶消失、道路和桥接续正常，角色渲染/碰撞已恢复，源地图未被验证过程改写。没有复测房屋室内。

[正式运行报告](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/published_runtime/result.json)；[最终四项验收记录](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/final_acceptance.json)。正式图像 SHA 为 `4c41930f79fd930e3953cf626be69dc9a4c8890cf18c2b09593b4cee8e3f55b7`，1600×900，有损 WebP Q90。

![正式地图修复后游戏画面](D:/code/rmmo_runtime/review_artifacts/axel_road_junction_20261017/published_runtime/images_1792238541_923/bridge2_east_road.webp)
