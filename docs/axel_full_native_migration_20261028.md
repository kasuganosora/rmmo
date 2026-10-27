# Axel Town 完整材质 native 正式资源离线迁移（2026-10-28）

本次针对正式 `D:/code/rmmo_runtime` 根中 Axel Town 的 49 个模型，补全已发布的 full native 元数据与缺失产品，使当前 `NativeModelProduct.read` 可读取它们。原地图和源 GLB 不作改写，不引入运行时 GLB 回退。这个检查只覆盖元数据、身份和预算，不代表正式整图、画面、帧率或内容编辑器验收通过。

## 发布内容与结果

- 44 个已有产品：仅替换 footprint 补充 `model_metadata`；保留原 SCN 和 index。事后核对原 index 的 SHA、SCN 的文件大小及修改时间，均与计划一致；新 descriptor SHA 和原 descriptor 备份 SHA 与计划一致。没有重新通读这 44 个大 SCN，不能把 stat 核对说成重新计算的内容 SHA。
- 5 个缺失产品：复制并流式校验 SCN 的 SHA 和长度，再按 product → descriptor → index 顺序发布，目标已存在时拒绝覆盖。5 个 SCN 共 151,555,611 字节。事后按 journal 核对每个流式 SHA、发布顺序，检查最终 SCN 长度及 index/descriptor SHA；没有另做最终文件的第二次全量 SHA。
- 共 49 项完成，发布 journal 无 abort；`result.json` 为 `ok=true, completed=49`。迁移前未发现 Godot 进程，迁移和 headless 验证时占用独立测试窗口。非协作写入者仍可能在最后身份检查与替换之间发生竞态；本次依赖协调后的安静窗口，不声称提供跨进程原子 compare-and-swap 或全批事务。
- 正式地图 `packs/default/maps/axel_town/map.gltf` 在迁移后与 helper 检查前后 SHA 均为 `667091a1e0b299f44d0ad1e9bb5d247fd1bec74603b3ac9dd401d494f418e8e4`。计划中源 GLB 此次检查其 size/mtime 与之前离线 SHA 证据的绑定，未无条件重新读取全部源文件。

## 验证与证据

证据根：`D:/code/rmmo_runtime/review_artifacts/full_native_offline_migration_dryrun_20261028_01/`。

- `plan_01/plan.json` SHA `d158387ede84b78e0a98dae2619db0b591814ce984b93633060abfad9b48e2db`；每项列出正式路径、源及原产品身份、动作与待发布 metadata SHA。计划中要求对所有大文件重新读取的旧文字已由本次执行约束细化：44 件使用已有验证及不变 stat，5 件复制时校验流式 SHA，源使用已有 SHA 证据加不变 stat。
- `apply_migration.py` SHA `286b9d50eb8bb0e4ef239db83a75b02e591848f58c843ea057e859cf8abafb5d`，其小型合成测试 `synthetic_test_04.log` 为 9/9，覆盖已有目标拒绝、并发变化拒绝、发布顺序和失败记录。
- `publish_20261028_01/journal.jsonl`、`result.json` 和 `post_metadata_stat_audit.json` 保存逐项执行及事后核对；`publish_20261028_01/original_descriptors/` 和 `plan_01/backup_metadata/` 保留旧 metadata。既有 44 个 SCN 和 index 未替换。
- `publish_20261028_01/formal_metadata_probe.gd` 和 `.log` 是一次私有 headless 检查：full 模式调用 `NativeModelProduct.read`，44 个旧产品与 5 个新产品共 49/49 可读；检查 source/payload 身份、产品路径及长度、full 内存预算和 candidate，errors 为空，日志无脚本或引擎错误。此检查没有加载 SCN、执行地图加载或测 GPU，且正式源 GLB 仍存在；无源读取语义由此前隔离测试另行证明，不能把此处称为删除正式源的验证。

此前隔离完整材质地图的内容等同性及五件模型受影响项验收见 `axel_full_native_fixture_20261028.md`；当前入口及剩余问题见 `axel_full_native_runtime_20261028.md` 和 `axel_full_native_pipeline_20261028.md`。后续仍需正式游戏入口及完整材质加载、卸载、返回、low 帧验证，并在材质优化完成后适配和验收内容编辑器。
