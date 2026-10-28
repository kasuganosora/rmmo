# 编辑器旧素材原生迁移（2026-10-28）

## 最新补验：三棵树的 LOD 阈值

`test_native_migration_lod_gpu.gd` 对三棵实际发布的松树完成源/native 对照。在 34.75、35.25、84.75、85.25m 分别采集静止与固定风时刻 t=1/4，正常 authored ranges 必须与只强制显示预期 LOD 的像素及绘制计数一致；隐藏全部 ranged meshes 的负对照确认它们确实参与渲染。每棵 source 140/0、native 139/0，12/12 组画面逐像素相同，三棵共 36 张 native 的原尺寸 Q90 WebP 已查看。

| 模型 | 源 SHA 前缀 | 实际 native SHA 前缀 | 阈值复验 |
| --- | --- | --- | --- |
| mature | `191e57178860` | `a7fff5106286` | 通过 |
| compact | `9d3988f8bd0f` | `707f53fb135e` | 通过 |
| windswept | `ccd30347b1af` | `4cbcb09bda60` | 通过 |

证据为外部 `editor_native_migration_20261028_01/lod_review_summary_01.json` 及每件 `lod_attempt_*/manual_lod_review.json`、`model_review.md`。mature 使用 attempt 02，另两件 attempt 01；每臂输入、产品和代码身份保持不变，GPU 测试在私有桌面串行运行。首次 mature attempt 01 在渲染前因夹具比较 JSON 数值与原始浮点值失败；改为经过相同 JSON 数值往返后严格比较，没有增加 epsilon，失败样本保留。

这些截图仍能看见源模型已有的 LOD 叶片尺度/密度变化。结论仅为迁移保持既有选择、风时刻与画面，不宣称切换平滑、连续穿越已验或资产质量无需改善。未修改模型、地图或恢复普通消费 GLB；源臂 GLB 读取只用于离线 A/B。

完整模型画质验收仍是 **5/59**，其余 **54** 件未因本次阈值专项而提前升级为通过。旧素材已转换和真实编辑器操作 59/59 的状态保持，接下来补完其余固定画面与完整编辑器地图复测，再开始 4.8。

当前优先完成编辑器原生素材和贴图导入适配，再回到游戏加载/low 优化及 Godot 4.8 beta 评估。白模专项已在 `6b17a555` 退役，见 [退役记录](white_mode_retirement_20261028.md)。本轮不恢复白模分支，也不修改用户的地图布局。

## 固定范围与身份

最新计划同时包含正式 axel_town 地图、默认内容库及 99 个 prefab 的依赖闭包，共 **220 个逻辑模型**：161 个已有完整材质 SCN，59 个缺原生索引，需要首次转换。此前 catalog-only 的 218/159 是旧统计，不应用于本轮完整闭包。

外部证据根：`D:/code/rmmo_runtime/review_artifacts/editor_native_migration_20261028_01/`。

- `plan_01/plan.json`：只读计划成功，输入前后不变。
- `before/snapshot.json`：实际读取全部 220 个源和 161 个既有 SCN 的 SHA；源合计 10,542,232,584 bytes，既有 SCN 合计 6,733,900,629 bytes。只复制了受影响的小型发布元数据供恢复，没有复制整份地图或删除源/SCN。
- `evidence_audit.json`、`REPORT.md`：59 件按 14 类分组，包含 3 棵 LOD/风场树、6 件风场花池、4 件风场布幡及 1 件玻璃旗槽路灯；6 件使用 `KHR_materials_specular`。无 skins/animations/morph 是源 JSON 观察，不等于无运行时动态语义。
- `evidence_reuse_candidates.json`：只定点复核 15 件已有产品的历史报告和图片可用性；没有把未完成的全目录检索解释为其他模型不存在证据。保留同源不同 SCN、旧报告 pending、局部材质/结构未完成等边界。

普通游戏/编辑器消费继续只读原生产品。上述 GLB 读取和 SHA 属于这次明确授权的离线导入/迁移审计，不加回加载热路径。已有产品保留原 SCN/index/producer，缺 metadata 才补齐；不因当前 generator 不同重建整库。

## 可复用复验工具

新增 `tools/review_native_migration.gd`、`native_migration_review_contract.gd`、`test_native_migration_review_contract.gd`。源臂显式使用当前生产导入，原生臂读取已经发布的实际 SCN，不能生成替身替代验收目标；metadata 模式只重开同一产品检查 bounds/building/absence/预算。报告、PNG和相机只写外部新目录。

源臂冻结相机、灯光、曝光、分辨率、引擎/GPU/代码身份；原生臂必须完全复用。包含近/中/远/细节与适用的投影、亮暗背景、固定风时刻、夜间材质检查。截图输出不代表人工画质通过，查看前按 skill 生成有损 WebP quality=90 副本，精确像素差保留本地 PNG。

## 首个实际转换样本

`banner_streetlamp`（源 `095d9b9daa40…`）已发布原生 `5fe054cf57d0…scn`：417,240 → 49,682 bytes。原生重开后仍为 4 个 mesh 节点、2,976 个 LOD0 实例三角面、7 个有效材质，无图片纹理。磁盘变化不作为显存或加载性能收益。

- helper 合同 **20/0**；源 GPU **52/0**；实际 native GPU **66/0**。
- 完整资源语义一致；11 组本地固定条件画面像素完全相同。
- root 已查看全部 11 张 Q90 WebP；转换相对旧导入基线的画质通过。旧纯色棱面风格未改，夜间未运行游戏路灯光源；旗槽替换/风场/灯光和实际编辑器操作仍待集成验证。
- 精确身份、成本、图片和状态见外部 `model_reviews/095d9b9daa40576e8457d359861ffa002aea186c639b05a097664bc0169ab3de/attempt_01/model_review.md`。

## 完整闭包转换与发布核对

**59/59 件缺失原生产品已生成，161/161 件已有产品已补齐所需元数据。** `publication_verification.json` 对全部 220 个模型实际复核：源文件不变；161 件旧 SCN 和发布 index 的 SHA 不变；地图、内容库及 prefab 输入不变；错误列表为空。新 SCN 合计 1,994,468,444 bytes，对应源合计 4,575,090,284 bytes；源和旧产品均保留，这不是磁盘净释放量、RSS/VRAM 或加载收益。

`preserve_migration_summary.json` 对 21 批保留操作复核：0 件重建 SCN，160 件复用已有 footprint、1 件补建；building sidecar 新建 161 件，其中12件有建筑描述、149件为合法 absence。bounds/footprint JSON 中111件更新、1件新增、49件不变。各批引擎、766份生产脚本和迁移工具身份一致，未运行普通消费 GLB 回退。

每件新产品的实际 SHA、批处理合同和待验边界在 `per_model_status/`，汇总在 `new_native_migration_summary.json`。转换/保存成功与画质、实际编辑器使用分别计数。

## 已执行的实际画面复验与剩余边界

- `garden_wall_short`（`0d00898aca5a…`）：源45/0、实际原生59/0；3张2K有效纹理像素与完整几何/LOD/材质语义一致，近中远/细节4组画面像素相同，root已查看4张Q90。有限范围报告见同名 `model_reviews/.../attempt_01/model_review.md`。
- 成熟松树（`191e57178860…`）：源73/0、实际原生87/0；实际原生60,793,148 bytes，5张纹理的有效像素和完整资源语义一致。27组固定画面源/native像素完全相同，root已查看其中12张Q90，覆盖近中远、细节、投影、亮暗叶缘与两个固定风时刻；没有发现转换新增的外观损失。精确LOD阈值两侧与无双重绘制补验仍待完成，不能用普通远景代替。见该模型 `manual_review.json` 的逐图路径与状态。

新增长L形树篱花池（`1885d634da0f…`）和节庆彩旗（`3009b1ed360b…`）固定视角复验，各27组 source/native 画面像素相同，root各查看9张Q90，覆盖近中远、细节、亮暗叶缘/布边、投影与两个风时刻。每件实际资源、图片SHA和有限范围结论在同目录 `manual_review.json`。目前5/59件有固定视角图审，54件仍待图审；松树LOD阈值专项未完成。

## 全部新产品的实际编辑器集成

**59/59件通过真实编辑器操作，9个独立进程共2768项检查，0失败。** 使用实际库入口（4个直接模型、55个预制件），临时地图与缩略图全部放在外部证据目录，不制造替代库条目或改写正式地图。

`tools/test_editor_native_migration_http.gd` 通过真实HTTP完成工具发现、放置、选择、变换、一次撤销事务、撤销重做、非法操作无副作用、保存重开，并核对实际SCN owner的源/产物身份、拾取体、实际调色板预览和缩略图。每件随后打开空地图，确认原物件及拾取登记消失，等待后台释放；正式library、目标prefab和小型产品元数据SHA保持不变。

证据为 `editor_http_pilot_01`、`editor_http_batch_{02,10,18,26,34,42,50,58}` 和 `editor_integration_summary_01.json`。源码、测试与候选引擎身份在各进程前后保持一致。引擎SHA为 `3d65b357ac8a14b8bf04b3a162d7dfea74eb0550ffb10a5a26764cea21958066`；此轮不是性能基线。初次parse中的两处测试变量类型错误保存在 `editor_http_parse_01`，修正后的 `editor_http_parse_02` 通过。并未执行完整消费者I/O追踪，不能把native owner断言扩大成系统调用级证明。

每件 `per_model_status` 已追加editor操作通过状态；图审、精确LOD及适用的旗槽/运行时灯光等仍单独待验，正式地图部署不由本测试放行。

UI/MCP自动DDS导入在独立 `editor-texture-import` worktree继续收口。新CPU编码接口及局部RenderingDevice修补已编译，并通过实际DDS HTTP/UI 32项检查，见[引擎合同](editor_dds_engine_contract_20261028.md)。任意尺寸限制、首次涂材质同步读取和缩略图共享预算仍在处理，分支尚未合并。完成编辑器后再开始4.8。本记录不产生新的 axel_town 加载、FPS/low 或峰值内存结论。

后续更新：DDS/PNG异步导入、尺寸准入、导入像素交接、共享缩略图与单次涂材质构建已由 `adda3ee3` 合并，并通过合并后真实 UI 回归；具体证据及冷 shader/跨进程发布/画质未完成边界见[首次涂材质记录](editor_first_paint_preparation_20261028.md)。本迁移的54件剩余图审与适用LOD验证仍须完成，没有由材质代码回归替代。
