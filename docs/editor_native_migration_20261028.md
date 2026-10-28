# 编辑器旧素材原生迁移（2026-10-28）

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

## 后续边界

后续两批各8件首次转换均成功，当前总计 **17/59 件已发布原生**，其中除首件外仍须逐件完成复验。第一件带纹理的 `garden_wall_short`（`0d00898aca5a…`）已完成源45/0、实际原生59/0：3张2K有效纹理的像素与完整几何/LOD/材质语义一致，近中远/细节4组画面像素相同，root已查看4张Q90；有限范围报告保存在同名 `model_reviews/.../attempt_01/model_review.md`。这两件都还没有完成正式库条目的实际编辑器集成验收。

剩余首次转换、161 件 metadata 补齐/重开及整库编辑器验证仍进行中。首件为无纹理模型，不能替代带纹理模型复验；树/花池/布旗须分别检查有效像素、LOD、透明投影与固定风样本。已发布的新原生和源均保留，完整闭包完成后再次验证地图/库输入与161件旧SCN/index未改。

UI/MCP 自动 DDS 导入在独立 `editor-texture-import` worktree 开发，目前只完成若干定向合同，尚未合并或称为编辑器整体交付。本记录不产生新的 axel_town 加载、FPS/low 或峰值内存结论。
