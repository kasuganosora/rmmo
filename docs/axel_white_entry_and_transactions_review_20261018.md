# axel_town 白模入口与提交/卸载链累计复查（2026-10-18）

本轮从 `269ec69` 继续，只处理白模加载、索引/导航源登记、区块卸载与返回。后续按用户新指示将重点转到加载入口。没有恢复纹理、HUD、角色、天气或 Recast 烘焙，没有合并其他会话，也没有修改模型、地图或用户设置。不是完整游戏模式的最终性能验收。

正式地图 SHA：`2786d854c6fb1f2a9a2803f1227ab3ab07b7381e217e541e893e173b26f070f8`。最大建筑 `obj_1033`：2,151 specs / 2,007 meshes。计时使用官方 Godot 4.7.2 `ed1daf0bf`、1440×900、RX 7900 XTX，GPU 进程均通过 `tools/run_godot_background.py` 的不激活私有桌面运行。各次均为新进程，保留 OS 文件缓存，派生缓存命中单独记录；不能称作冷盘测量。

证据根目录：`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/`。以下证据文件名均相对此目录。所有方法跨度包含子调用和等待，不能简单相加为独占 CPU 时间。

## 入口：先测量，再减少真实工作

`white_schema_final_native.json` 的入口为 20,283ms：MapLoader 返回 17,950ms，初始 streaming 就绪 19,567ms，批次就绪 20,281ms。首轮依赖目录读验 6,353ms，其中 `index.imported` 4,094ms、49 个模型的 manifest 检查 959ms、目录只读封存 497ms。随后单个模型准备 6,653ms。后台步骤占了主要入口时间，不能仅把问题归因于 GPU 或 60 FPS。

### 1. 消除建筑源检查的重复完整读取

原链为 `MapDependencyIndex._imported_sources_valid → get_sha256 → Imported.source_descriptor → 再次 get_sha256`。同一个源文件先完整散列、读取 JSON，再完整散列。`profile_entry_source_checks.gd` 对正式地图的 5 个相关源逐个复现，合计 357,912,912 字节（341.33 MiB），旧检查合计约 3.4 秒；描述符结构比较本身每件不足 1ms。

`Imported.read_source_descriptor` 现在从一个文件句柄读取头部、有界 JSON 和整个二进制块，对**同一批实际读取字节**计算 SHA。只保留 JSON 和最多 4 MiB 的当前二进制块；没有保留整个 GLB。每次都实际读取并验证完整内容，完成后才使用按摘要索引的描述符缓存。失败、长度变化、短读或摘要不匹配均不能返回可用结果。`verify_source` 和入口目录检查共用此路径。原有源变化校验、命名空间、模型成员和门窗语义继续保留。

这将该段冷进程的完整文件扫描从 10 次降为 5 次，减少约 341.33 MiB **逻辑读取/散列工作量**，不是物理磁盘流量或实测 RSS。瞬时缓冲较旧内置 SHA 的 32 KiB 更大，单个调用至多有 4 MiB JSON 加 4 MiB 二进制工作块。

同代码、同目录缓存、相同限帧与就绪条件的 ABBA（`white_entry_single_read_1_legacy`、`2_candidate`、`3_candidate`、`4_legacy`）：

| 指标 | 原检查 | 单次读取 | 变化 |
| --- | ---: | ---: | ---: |
| 完整白模入口，均值 | 17,142ms | 15,457ms | -1,685ms / -9.8% |
| 依赖目录读验，均值 | 5,376ms | 3,838ms | -1,538ms |
| 导入建筑源检查，均值 | 3,465ms | 1,870ms | -1,595ms |
| 此段完整源扫描 | 10 次 | 5 次 | -50% |

ABBA 的四次地图/代码不变、实际可见 GPU 白模和退出释放检查全部通过。`entry_single_read_comparison.json` 保存完整分段。`white_entry_single_read_0_candidate` 是代码生成器版本变化后的目录重建，33,976ms，**不混进缓存命中的 ABBA**。

### 2. 元数据扫描只为容器安排递归和队列项

GDB 的入口线程栈抓到 `ModelParsePreparation.run → EmbeddedGlb.can_copy → _plain → Array::Array`，以及 `MapLoader._register_reference_pending → AssetMemoryEstimate.estimate → _bounded_plain`。原先数字、字符串、布尔值也要创建新的路径数组，或创建 `{value, depth}` 字典后入队。

保持 URI、扩展作用域、native 标记及完整计数规则：只让 Dictionary/Array 进入递归或显式栈；标量仍计入深度和总值上限。估算器使用容器栈和深度栈，移除每个值的包装字典。没有降低内存准入预估或放宽格式资格。

`entry_metadata_abba.json` 在实际最大建筑的同一 JSON 上交替 8 次：30,536 个容器、99,251 个标量叶、2,139,380 字节 JSON。每轮比较完整 bounds、所有 mesh nodes/transform、资格判定和全部 admission 字段，结果严格相同。

| 真实头部检查 | 原均值 | 新均值 |
| --- | ---: | ---: |
| Bounds manifest 完整计算 | 326.69ms | 264.96ms |
| Embedded 资格遍历 | 148.90ms | 86.16ms |
| 内存估算元数据遍历 | 191.87ms | 79.05ms |
| 整个内存估算（含文件读取） | 405.54ms | 305.00ms |

每次上述遍历省去对 99,251 个标量的递归调度/路径数组；估算遍历不再分配 129,787 个临时包装字典。该组件基准的收益不能直接相加成整张地图加载收益。累计入口两次为 15,501 / 15,178ms，和单次读取组均值差距较小，不把这一小差异宣称为稳定整图收益；工作量及组件耗时收益仍保留。

### 限帧与缓存控制

原测试在加载阶段明确 `Engine.max_fps=60`，`--uncapped-runtime` 仅在 playable 后关闭限帧/VSync。新增 `--uncapped-loading` 是诊断选项，不改游戏设置。四次 60/不限/不限/60 结果为 19,621 / 17,817 / 17,379 / 17,597ms；有明显运行间波动，不能把差值全算成限帧成本。解除限帧仍远离正常的快速入口。

累计代码改变生成器 key 后，`white_entry_final_warmup` 自动重建派生目录，耗时 30,395ms；缓存命中时的约 15 秒不能代替这个结果。重建仍只准备实际入口所需模型，不靠修改正式地图消除目录失效。缺失/失效目录路径仍有明显空间。

## 保留的提交、导航登记和卸载修复

这些修复在入口重点调整前已完成，并继续保留；没有因某一次整图变化不明显而撤回有效组件优化。

1. **避免恢复下一刻就要卸载的 GPU 网格。** GDB 实际栈为 `WorldStream._apply → GroundBatcher.retire_sources → _drop → restore → GroundCpuMesh.restore → ArrayMesh.add_surface_from_arrays → RenderingServer::_surface_set_data`。旧版逐个退出批次时，会把同组也即将退出的来源重新上传。现在只对有准确 spec、属于当前 map 且确定离开 draw 区的来源抑制恢复；需求返回时通过 suspended 标记补回。未知来源、native visual 保守恢复。实际路线避免 2,341 次无效恢复。
2. **预备并复用卸载 schema。** 大库校验在共享帧预算内分片，原子提交仍重新确认 pin、源身份、命名空间、geometry、导航和派生结构。普通物件的先行退出会压紧已验证的幸存前缀，不再每批使全库准备作废。真实路线从失败候选的 44 次准备 / 148,592 行降至 1 次 / 4,536 行，122 个切片，最大切片 1,155µs。
3. **索引快照只拥有真正被验证的可变字段。** 不再深拷贝不参与 schema/signature 的大型作者数组；fixture/fortification 的可变 ID 仍独立复制。最终使用原生严格相等与原始 spec 身份验证，Mesh AABB/派生共享所有者继续在主线程检查。大型纯读取比较使用最多 4 个线程，提交会等待并 join 全部线程；没有声称消除了同步等待。失配走原完整校验。
4. **减少重复分类与导航登记。** schema 的相邻共享字典复用仅在抽样确认共享时开启；作用域不跨 callback/Mesh getter。导航登记第一次校验直接收集几何引用计数，正常新 UUID 不再第二遍计算相同的 geometry；已存在别名仍按原顺序重绑定，保留导航 face cache 语义。
5. 私有 schema/snapshot 数组和已有 typed resource owners 继续经有预算的回收器释放。取消、失败、返回 pin、普通删除、部分准备及地图退出均有回归。

### 入口优化前的累计路线

下表均为相同官方引擎、被动 monitor、白模、相同路线；不是官方 profiler/GDB 暂停运行的数据。

| 指标 | `white_typed_final_native`（本轮起点） | `white_schema_final_native` |
| --- | ---: | ---: |
| 入口 | 20,267ms | 20,283ms |
| 最大建筑发布 | 158.453ms | 114.008ms |
| 卸载区间最大帧 | 170.575ms | 125.603ms |
| 返回移动区间最大帧 | 102.346ms | 76.121ms |
| 返回加载区间最大帧 | 166.061ms | 119.877ms |
| 返回稳态平均 FPS | 135.56 | 143.61 |
| 返回稳态 p99 | 21.214ms | 18.750ms |
| 卸载/重新加载 specs | 4,470 / 4,392 | 4,469 / 4,392 |

稳态 FPS 是单次观测，有系统与驻留差异，不能宣称稳定提升。全部 2,151 个最大建筑部件都返回；地图不变、白模材质和退出资源所有权检查通过。仍有 >100ms 长帧，不能称白模通过。

正常步行 `white_schema_final_walk`：跨 17 个区块边界，退出 560 / 返回 240 specs；向外/卸载/返回/返回加载最大帧分别 36.374 / 66.476 / 51.609 / 60.990ms，没有 >100ms 的路线帧。该路线范围不同，不能替代最大建筑的 native 远离/返回测试。

### 两项入口修复后的最终累计路线

`white_entry_final_native.json`、`white_entry_final_walk.json`、`white_entry_official_final.json` 全部完成且 failures 为空；汇总为 `white_entry_cumulative_comparison.json`。原始 `frames` 用同一 `summarize_axel_white_scans.py` 计算区间分布。

| 最终 native 路线 | 结果 |
| --- | ---: |
| 入口 | 16,914.508ms |
| 最大建筑提交 | 117.144ms |
| 卸载最大帧 / p99 | 110.161 / 17.127ms |
| 返回移动最大帧 / p99 | 91.661 / 48.929ms |
| 返回加载最大帧 / p99 | 122.003 / 20.364ms |
| 返回稳态 FPS / p99 | 135.40 / 21.542ms |
| 卸载 / 返回 / 新发布 specs | 4,489 / 4,393 / 6,653 |
| 避免的 GPU 恢复 | 2,341 次 |
| 卸载 schema 准备 | 1 次 / 4,558 行 / 121 切片 |
| schema 最大切片 | 1.165ms |

初始仍是 323 条选定记录、1 个入口模型、2,473 个 specs，和本轮起点相同；全部 2,151 个最大建筑部件返回。无追加卸载等待窗口，地图退出后模板、worker、admission 和回收任务均为空。稳态 FPS 与起点基本相当，不宣称稳定 FPS 收益。工作量与入口时间的收益成立；卸载和返回仍各有一个 >100ms 帧。

最终步行入口 16,101.853ms，仍退出 560 / 返回 240 / 新发布 3,383 specs。向外、卸载、返回、返回加载最大帧为 40.202 / 70.635 / 33.662 / 56.996ms；这四个阶段均没有 >100ms 帧。步行稳态 FPS 139.93、p99 24.911ms，有一次 50.3ms 帧，不把“没有百毫秒帧”写成“没有卡顿”。

最终官方入口采集有 1,596 帧，验收全通过。frame 719 为 176.261ms：`PackedScene.pack` 89.716ms，`_build_records` self 51.952ms，2,319 次 `_retain_visual_resources` 共 30.855ms，另有递归 `_own` 11.729ms（存在包含关系）。frame 718 为 107.240ms，含 `RiverMaterials.apply` 52.528ms。frame 877 包含测试自己的 2,473 次 `whiten_spec`。因此下一步需要分别处理真实模板发布链与测试材料处理，不能混算。

## 诊断证据与失败记录

- `white_transactions_gdb_unload_stacks.jsonl`：实际重复 GPU 恢复链；`white_transactions_gdb_commit_stacks.jsonl`：卸载 schema 主循环和 worker 校验。GDB 全停采样时间只用于归因。
- `white_schema_final_gdb_publication_stacks.jsonl`：默认启用新快照的固定真实建筑发布；不将压测事务时间当成实景帧耗时。
- `white_transactions_official_summary.json`、`white_schema_final_official_summary.json`：官方 servers/visual profiler 原始包另有同名前缀 `.bin`。新卸载最大观测帧 138ms 中，仍见原子预检、线程 join 和退休源压紧；返回发布观测帧 203ms 仍包含导航登记、两类 residency observe 和测试自己的白模处理。带 profiler 数值不能与普通运行直接比。
- `white_entry_gdb_baseline_stacks.jsonl` / `_compact.json`：6 个全线程样本，包含目录封存、内存估算和 Embedded 递归分配；累计调试暂停约 66 秒。该运行不是加载速度证据，也没有抓到所有 raw append 原生栈。
- 首次入口官方采集误用了带稳态前置条件的路线 harness，入口成功，但后续因未等待所有外围 geometry demand 而有 1 条失败。证据 `white_entry_official_baseline` 保留，只用于入口归因，不作为整次验收。后续改用 `profile_axel_entry_frames.gd`，保持入口本身的就绪、材质和退出检查。
- 官方 profiler 的首帧可能含启用前已开始的函数，不用该帧巨大的累计 script time 推断 CPU 忙碌。后台原生方法有缺失/零计时，必须结合 trace 和隔离测试。
- 最初无条件共享 schema 缓存对真实不共享数据有额外开销，改为按分布启用；最初普通删除丢弃预备 schema 导致 44 次重建及额外卸载窗口，已通过保留幸存前缀修复。退化运行 `white_sliced_native.json` 的原窗口 72.9ms 不能单独当收益，其追加窗口还有 119.6ms。
- `test_asset_retirement_batching` 曾在并行功能测试中出现 2 个时间阈值失败；独立复跑 36 项通过，最终路线计时未和这些测试并发。

## 验证与尚未关闭的问题

提交/卸载验证清单见 `sliced_validation.json`（13 组）、`parallel_proof_validation.json`（7 组）、`snapshot_final_validation.json`（4 组）、`snapshot_default_validation.json`（7 组）；都通过，清单有重复组，不相加冒充不同测试数。

入口新测试：`test_imported_source_snapshot.gd` 17 项通过；`test_entry_metadata_policy.gd` 修改前后 22 项通过，涵盖深层 URI、native 标记、扩展位置、32/33 深度、200,000 总值边界、数组上限和循环结构。`entry_source_validation.json` 包含源检查后的既有 contract 回归；`white_entry_final_suite.json` 包含元数据修改后的 bounds、memory estimate、embedded import、model preparation 和 initial prefetch 回归，以及累计实际路线。正式地图不变、原始几何/transform/内存估算值不变，不以少加载来源来换取数字。

入口仍有约 15 秒，失效目录重建约 30 秒；单个 raw 模型准备仍约 5 秒，主线程 CPU 网格捕获约 1.5–1.7 秒。官方入口帧还显示 PackedScene.pack 和模板资源保留占用同一主线程长帧。这些问题没有被上述优化宣称解决。

最大建筑的原子提交/退出仍有百毫秒级帧，导航登记和 residency 回调、全库快照核对/压紧也仍占时。当前继续优先加载入口，白模门槛未关闭前不推进纹理或其他系统。
