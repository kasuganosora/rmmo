# 项目生成资源迁出（2026-10-17）

用户反馈 Godot 启动反复导入 `review.glb`。清点确认项目的 `review_artifacts/` 留有历史验收 GLB、Blender 母版、图片和 native 场景，且缺少 `.gdignore`；另有两份窗帘 Blender 文件留在 `assets/`。

已将 6,124 个文件迁出项目目录，共 24,315,501,821 字节（22.65 GiB），其中模型/母版 75 个（约 7.46 GiB）。范围包含生成图片、native 场景及对应 `.import` 旁文件。逐文件记录移动前后 SHA-256，全部一致。曾被编辑器占用的一份模型已在占用解除后成功迁移；最终没有待迁文件。

- 主要目的地：`D:/code/rmmo_runtime/review_artifacts/`，保留原目录结构。
- 目标已有文件时保留双方，迁入 `D:/code/rmmo_runtime/relocated_project_media_20261017/`，不覆盖同名内容。
- 旧窗帘工作文件：`D:/code/rmmo_runtime/art_sources/legacy_project/assets/models/curtains/`。
- [逐文件原位置、新位置、大小和 SHA](D:/code/rmmo_runtime/review_artifacts/project_media_relocation_20261017/moves.jsonl)。清单 SHA-256：`6e45092b0537ac5a20f72afeffb64fead18764443f95747baa006c2b8e9ac1bb`。
- [迁移计划](D:/code/rmmo_runtime/review_artifacts/project_media_relocation_20261017/plan.json)、[最终核对](D:/code/rmmo_runtime/review_artifacts/project_media_relocation_20261017/summary.json)、[工具/文档引用更新](D:/code/rmmo_runtime/review_artifacts/project_media_relocation_20261017/reference_updates.json)。

`review_artifacts/.gdignore` 隔离历史证据目录，防止意外生成物再次触发 Godot 导入；`.gitignore` 补充模型/母版/native 场景扩展名，避免误提交。美术生成与验收工具的历史项目输出路径已改到外部目录。原始 JSON 验收记录保持字节不变；供工具读取的支持元数据以相同字节随外部目录保留。无法由原历史报告直接解析的旧绝对路径以迁移清单为准，不能将迁移当作重做美术验收。

算法回归所需的非导入型 `.bin` 输入/结果证据及源代码仍在仓库；它们不是模型资源。插件自带的必要 UI 资源不在本次迁移范围。本次目录迁移没有改动正式资源包、模型字节和出生地图；迁移完成当时 `axel_town/map.gltf` 为 `f3009b1841c99174ce1bee6509a58fde814a921290ccb882f0c435478c54a2bc`。项目资源树重新清点（包含 Git 忽略文件，不计 `.git/.godot` 缓存）已无 GLB、GLTF、Blender、FBX、OBJ、DAE 或 native SCN 模型文件。

历史回归图与示例 GLTF 从项目资源树迁出，不删除 Git 历史；它们的外部位置和原 SHA 由清单保留。新验收继续使用原尺寸有损 WebP Q90，不因目录整理重编码旧证据。

引用修改后，31 个受影响 GDScript 实际加载/解析通过，改动 Python 文件的 AST 检查通过，代码与文档的 `git diff --check` 通过。目录迁移保留资源字节，不作为模型外观或性能改造，也不重复模型 GPU 验收。

后续道路贴地修复另有原生地图保存，不属于本次迁移，见 [道路修复验收](axel_road_kerb_conformity_20261017.md)。上述迁移时地图 SHA 是当时的证据，不代表后续正式地图版本。
