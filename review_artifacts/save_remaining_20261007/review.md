# 仅姿态保存剩余成本复核（2026-10-07）

范围：初始只读分析 `scripts/world3d/pose_save.gd`、实际保存作业 `scripts/world_editor/save_job.gd`、同步入口 `world_document.gd` 和完整导出 `gltf_map_io.gd`。父 agent 随后授权实施下面的单项候选；已修改 pose_save.gd 并增加小型 headless 回归，没有修改正式地图或执行全城/GPU 测试。Grok 初审退出 0，提示、报告、stderr、exit 状态保存在本目录。stderr 为遥测网络警告及上下文提示，没有登录/额度失败。

## 可实施候选：最终复核复用已发现的源文件闭包

`pose_save.gd:405` 当前再次调用 `source_files(records, content_root, io)`。该函数再次递归遍历所有记录 `_paths`、查找隐式门模型/木纹、读取并解析每个 GLTF/GLB 的依赖 JSON、逐级调度 SHA 线程。初次 source_files 已经建立完整闭包，随后通过可信 manifest 对照该闭包每个文件的路径和完整 SHA。

建议增加小型共享函数 `verify_source_files(sources, content_root)`，要求 sources.ok、generator 与当前 generator_key 一致，再调用 `hash_files(sources.files.keys(), content_root)`，且逐项与 sources.files 完全一致。仅替换复用分支最终的重复发现。所有文件仍重新做路径边界、存在性和完整 SHA256；不缓存摘要，不使用 mtime；保留最终地图两次 SHA、已发布依赖复核、staged 文件 SHA、故障注入及原子发布顺序。

若希望去重代码，完整导出 `install_manifest`（当前 416–424 行）已经采用上述闭包重新 SHA 策略，可让它使用同一函数，但保持检查位置和失败时“不安装 manifest”的既有行为。不要将初次 source_files 替换掉，不要把旧的 manifest 当作无需发现即可使用的闭包。

正确性依据：新增依赖、移除依赖、URI 改成缺失或越界目标，都改变父模型内容；父模型本身在初始闭包内，其最终完整 SHA 不同便拒绝，所以不需要解析修改后的模型寻找新的依赖。已有依赖变更/删除则由该文件自己的 SHA/存在性检查拒绝。无内容变化的父模型不能产生新 URI。该推论仅适用于一次保存期间已冻结的输入 records；当前异步 SaveJob 禁止 UI/MCP 编辑，同步保存不让出主线程，不能把此方法扩展为跨保存的持久依赖清单缓存。

收益边界：此前探针记录 `_paths` 遍历约 0.68 秒（不同轮次，不是本次 A/B）；还可减少依赖 JSON 解析和重复调度。源文件完整 SHA 本身仍约数秒，序列化约 4 秒、已发布依赖 SHA 和最终地图检查都仍保留，不能宣称 26 秒保存会变为即时。

## 建议验证

- 小型 GLTF + 外部 buffer/texture 闭包：未修改最终复核通过，并与旧 source_files 最终检查相等。
- 在 `before_publish` 修改父 GLTF：新增合法依赖、移除已有依赖、改为缺失文件、`../` 或绝对越界 URI，均 ERR_BUSY，地图 SHA 不变，失败不清 dirty，可重试。
- 修改父文件内容但保持长度与 mtime，仍拒绝；完整 SHA 已不依赖 mtime，测试需真实恢复 mtime而非仅命名声称。
- 删除或更改已有依赖、修改生成器 fingerprint，均拒绝。
- 初始闭包发现依然拒绝缺失/越界源，完整导出、首次保存、另存为以及旧/过期基线仍走原路径。
- 既有 pose-save、SHA、真实 HTTP 保存/undo/redo/reopen 测试；小图真实 HTTP 至少覆盖成功复用和父模型迟到修改失败。

## 暂不提出第二项

大型 JSON 解析和序列化确有数秒成本，但当前证据没有证明某一大段可以直接删除而保留作者数据、原生节点、64 位浮点和 checksum 语义。字节拼接/专用 JSON 写入器需要更大的兼容性工程；`updated_nodes == 0` 也不等于可以省略写入，因为 tolerant 比较可能接受微小数值差异，而现有保存仍写入当前作者数据。另一个全局 SHA 并行池可能改善负载分配，但无测量证明足够收益，本轮不作为可交付修复。

## Grok 具体复核与实施边界

- 采纳其“父模型完整 SHA 一致即可复核已发现闭包”的窄结论；与独立复核及既有 install_manifest 逻辑一致。
- 不采纳其将源/已发布依赖合为一个并行 hash 池的建议。本次保留原有先源后依赖的检查顺序和现有四线程上限，没有据估算承诺节省 2.5–3.5 秒。
- 报告自相矛盾：先承认 expected 原始文件摘要与 checksum 清零后的摘要是两种必要输入，随后又称 read path 可少算一个 SHA。该结论错误；本次保留两个不同输入的 SHA，也未改变完整性校验。
- 不采纳用内存摘要替代 staged 磁盘 SHA；flush/get_error 不等价于现有磁盘内容验证。
- 不采纳 JSON 节点字节拼接。浮点、Unicode、checksum 偏移、原生 GLTF 扩展等兼容性和收益未证明。
- 新测试 seed_map 仅创建自己的最小 GLTF+manifest 夹具，全部路径在独立临时 cache 子目录，不是重签旧城镇基线。

## 已实施及小型测量

新 helper `verify_source_files(sources, content_root)` 复核 generator 和闭包全部完整 SHA；`_attempt_locked` 与 `install_manifest` 共用。首次发现和失败/发布语义保持原样。`tools/test_pose_save_source_recheck.gd` headless 已退出 0（首轮），覆盖无重复 URI 解析、真实同长度/同 mtime 改字节、生成器失配、缺失/越界、依赖修改/删除、迟到父 URI 改动拒绝、原图 SHA 不变、成功位移发布与 checksum。

独立有界合成夹具使用 4372 条记录、5 个文件（四个 2 MiB buffer + 一个父 GLTF），初次发现后比较旧二次发现与新闭包复核，逐项 SHA 完全相等。“新增 URI”已加强为新增有效 extra.bin（实际闭包从 5 增到 6），最终运行退出 0、`POSE_SOURCE_RECHECK_FAILED=0`。最终两次 old/new：322.446/60.443 ms、280.122/70.612 ms，最终日志见本目录 test.log。该数值只表示该合成夹具，不能用于宣称实际城镇保存减少多少秒。未进行实际城镇 A/B，也未通过手工重签旧基线规避生成器指纹失效。
