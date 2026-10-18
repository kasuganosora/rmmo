# axel_town 白模最大建筑发布链复查（2026-10-18）

本轮基线为 `8c64ead790d0e00e564206a5af27c0f5d18e3470`。保持此前累计修复；只研究白模几何加载、提交、卸载和返回。没有启用纹理、HUD、导航烘焙或角色系统，没有合并其他会话。正式地图 SHA 为 `2786d854c6fb1f2a9a2803f1227ab3ab07b7381e217e541e893e173b26f070f8`，最大建筑为 `asset:obj_1033`，共 2,151 个部件。GPU 测试均通过私有桌面运行。

证据根目录：`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/`。以下文件名相对此目录。完整路线不是完整游戏 FPS 测试：它保留真实几何需求、加载、索引、渲染/物理驻留和导航源目录，但不运行角色与导航烘焙。

## 官方 Profiler 与原生栈

`white_publish_official_baseline.bin` 由 Godot 官方调试协议接收；返回阶段才开启 servers/visual profiler，避免初始加载的无关观测开销。`white_publish_official_baseline_summary.json` 解码出 13,920 帧。最大建筑对应 frame 33587：

| 包含子调用的范围 | 观测耗时 |
| --- | ---: |
| 整帧 | 237.329 ms |
| Deferred._publish_items | 212.629 ms |
| WorldStream.append_specs / Index.append | 88.113 / 86.943 ms |
| Preparation.valid_for / signature | 42.503 / 31.639 ms |
| Index._valid_append_spec，2,151 次 | 18.307 ms |
| 测试 on_publication / Navigation.append_specs | 72.464 / 53.133 ms |
| NativeResidency.observe / AssetResidency.observe | 18.021 / 15.638 ms |
| 测试 whiten_spec，2,151 次 | 17.033 ms |
| 发布后 Deferred._discard_job | 21.261 ms |

上述包含关系会重叠，不能相加。官方 profiler 会放大脚本时间，不能拿 237ms 与无 profiler 基线的 158ms 比较。白模测试自身的材料归一化也单列，不能算作游戏修复收益。API 聚合调用数不能证明某个调用者重复读取了 Mesh。

`white_publish_gdb_followup_stacks.jsonl` 使用同一 Godot 提交 `ed1daf0bf` 的带符号构建，附加到启动器记录的唯一 PID/主线程，返回加载阶段采集 21 份栈；汇总为 `white_publish_gdb_followup_stack_summary.json`。抓到的链包括：

- `_publish_items → _remove_published_demand → Array.filter → GDScript lambda → Dictionary::getptr`。
- `tick_geometry → ensure_geometry → _in_clip → Dictionary::values / Variant::reference`，4 个主线程样本。
- `_discard_job → dispose_result → _dispose_owned_packet → HashMap::_clear_data`。

这批 GDB 全停采样累计暂停约 67.8 秒，首个含工作线程样本暂停 22.2 秒。该路线因此触发返回需求的 90 秒超时与稳态前置条件失败；最大建筑仍完成卸载和全部 UUID 返回，退出释放通过。此运行只用于调用归因，不能纳入性能结果或作为完整路线验收。启动器在进程完成后的 stdout 保存类型曾出错，原始引擎 live log、JSON 与 GDB 文件均保留；脚本已更正。

## 已排除的候选

1. 对最终 schema/signature/navigation 检查开 4 个读取线程：实际 2,151 部件 ABBA 的平均索引+导航耗时约 104ms，串行约 98ms；完整结果一致但无收益。实现和测试归档在 `publication_parallel_experiment/`，不保留生产线程改动。
2. 首版通用大数组探测器只沿 Dictionary 所有权字段查找，漏掉实际 `retained_resources = [导入包, PackedScene, Array[Resource]]` 中的小 Array 容器，实际触发数为 0。继续检查真实生产者后确认了这个缺口。按用户要求，最终移除形状探测器，重构生产者和消费者为显式类型，详见下文；没有保留新旧模型交接结构兼容适配。

## 当前实现与约束

- **默认关闭的实验候选**：在 owned 私有索引准备的分帧阶段保存完整深拷贝快照。最终使用 Godot 原生严格类型、深层值相等来证明 schema/作者字段没有改变；仍检查每个原始 spec 的对象身份、实时 Mesh AABB、共享 derived bounds/supports 的身份和内容。任何不匹配都退回原始完整校验；不是哈希命中即放行。公开索引的 UUID、命名空间、fixture、组冲突及原子提交继续检查。
- 初次 ABBA：索引提交平均 `101.624 → 69.909 ms`；准备平均 `123.148 → 185.632 ms`；同步销毁平均 `4.420 → 33.803 ms`。这证明只降低提交是不够的，因此新增快照的最终释放已转交既有主线程 1ms 回收预算。仅释放专属数组的引用，不递归改写作者数据。取消、隐式销毁和树退出均有覆盖。
- 几何就绪查询只寻找首个未发布交集，不再构造完整去重候选列表；不缓存 ready 状态，逐次检查实际 footprint、published 标记和边界。
- 发布需求过滤使用保序的直接循环，保留新数组语义，减少每行 GDScript lambda/Variant 调度。
- 非 fixture 部件不再构造门窗 UUID 回退链。导航登记复用已校验的 extras/door 分类；新 UUID 直接登记几何引用计数，旧别名仍按原重绑定路径处理，包围盒合并顺序不变。

`white_publish_snapshot_abba.json` 的事务与等价检查全部通过，但该独立基准退出时仍有 3 个模板回收未在 15 秒内结束，因此整次运行有 1 个失败，不能作为退出验收。累计路线另行验收。ABBA 中导航路径未切换，因此两个分组的导航时间差不能归因于快照优化。

## 按实际应用重构交接数据

`model_resource_owners.gd` 为临时模型交接提供一个 RefCounted 类型：`document: GLTFDocument`、`state: GLTFState`、`packed: PackedScene`、`visuals: Array[Resource]`。正常 raw、取消、解析失败、后验 SHA 失败全部沿同一类型交接。借用的作者记录和索引不进入该类型；源文件内容和模型几何没有修改。

- `prepare_scene/_fallback_scene` 直接生成该类型。没有寻找“小数组中的大数组”的递归猜测，也没有新旧模型包转换适配分支。
- `defer_model_packet` 只移动一个明确的所有者引用；主线程 join + RenderingServer 同步后，既有回收预算分别处理模板、视觉资源和导入状态。
- 缓存确认接收同一个 PackedScene 后，移交模板所有权，不再在临时包中重复扫描该模板；未接受和取消路径继续保留完整模板回收。
- 嵌套 PackedScene 的回收仍属于同一 admission 预约。新增回归先复现了父包归还字节而子模板仍待释放的缺口，修复后检查 callback 当时的全部弱引用均已释放。
- `resource_owners` 是进程内临时交接格式，磁盘 GLB、RMRES、地图和编译缓存不含这个结构。因此本次没有需要转换的磁盘旧包；所有新加载直接产生新结构。其他在用的地图解析、原生读取失败包仍使用它们各自的现行接口，本轮未为旧模型交接新增兼容层。

### 可复现压力测试

`tools/stress_model_resource_owners.gd` 在测试内重建原来的短数组 + 大资源数组，按 ABBA 顺序与新类型对照；规模 2,151 和 21,510，另含真实 GPU 网格/ImporterMesh/PackedScene 的已发布、取消两种情况。构建夹具不计时，交接及全部回收 CPU 计时；每轮检查借用数据、最终弱引用、配额和队列。

- 首轮 `white_typed_owner_stress` 的旧结构夹具有 typed Array 赋值错误，不能作对照；已修复，并增加 16 轮必须全部执行的断言。
- `white_typed_owner_stress_v2`：74 项通过。2,151 部件交接由 5.49–6.48ms 降至 0.04–0.06ms；21,510 引用由 59.70ms 降至 0.037ms。但该版回收总 CPU 有增加，尚未完成缓存所有权转交，不能称为总工作量下降。
- `white_typed_nested_repro`：19 项中 1 项失败，明确复现嵌套模板提前归还配额；最终修复版 `white_typed_owner_contract_v3` 19 项全部通过。
- `white_typed_model_gpu` 的实际 GPU 生产者释放检查曾失败；保留失败日志。诊断重跑通过，最终与既有 GPU 回收测试一致，在 renderer sync 后再等待一帧检查引擎持有引用；`white_typed_model_gpu_final` 的真实 raw producer、预取消、native callback/源变更/失败清理全部通过。未把夹具成功等同于真实生产者已验证。

## 累计路线与最终检查

所有性能路线使用原版发布引擎；不启用 GDB 或官方 profiler。性能矩阵保留所有帧、失败、超时及实际工作量。完整白模优化门槛尚未通过，140ms 发布事务仍须继续处理。

快照候选的实际路线 `white_publish_verified_native` 最大发布 189.288ms，额外准备成本没有得到全路线收益支持；同代码关闭候选的 `white_publish_validation_control` 为 146.287ms。故该候选默认关闭，测试工具可显式启用作研究，不能把它算作生产收益。并行最终校验的撤回同理；既有有证据收益的修复均保留。

第一版类型结构真实路线 `white_typed_owner_native`：入口 18.659s，原地额外需求 40.195s，返回额外需求 39.132s；发布事务仍 140.850ms，返回加载最大帧 146.489ms，卸载最大帧 134.748ms。49 个类型包实际进入回收，2,899 个视觉引用分帧释放；最大建筑 2,151 部件全部卸载/恢复，退出队列、工作线程、配额和模板全零。回收计数的 max_slice 同时包含退出时不受帧预算限制的 drain，不能直接等同于交互帧峰值。

最终版本的工作量、路线及官方工具复查见下方后续测量记录。


### 最终结构压力测试

`white_typed_final_stress.json`：16/16 轮、74 项检查通过。以下为 ABBA 中每组两次的算术平均；独立夹具 CPU 计时不是游戏 FPS。总 CPU 包括所有后续切片，未把工作移出提交帧就当作工作量消失。

| 夹具 | 旧交接 → 新交接 | 旧总 CPU → 新总 CPU |
| --- | ---: | ---: |
| 2,151 引用结构，未发布 | 8.337 → 0.075 ms | 180.019 → 204.428 ms |
| 21,510 引用结构，未发布 | 79.260 → 0.039 ms | 1843.407 → 1838.096 ms |
| 2,151 实际 GPU 部件，取消 | 6.092 → 0.051 ms | 178.784 → 177.156 ms |
| 2,151 实际 GPU 部件，已缓存/发布 | 5.648 → 0.052 ms | 195.695 → 187.845 ms |

结论是交接阻塞随引用数增长的问题已消除，不是所有夹具的 CPU 总量均下降。2,151 纯引用结构仍有额外总成本；GPU 场景的少量总 CPU 差异只有两次观测，不宣称稳定百分比收益。已缓存版本不再重复扫描模板的 2,151 个 Resource 属性，取消版本仍执行必要扫描。21,510 规模中导入器个别原生数组操作仍超过 1ms，软预算不是硬上限。

最终回归清单 `white_typed_final_manifest.json` 包括 13 组 headless 组件检查（866 项）、真实 GPU 模板回收（7 项）、真实 GPU 导入状态回收（18 项），合计 891 项；另有上述压力测试 74 项和真实模型生产者 GPU 测试。所有 final 清单均要求退出码 0，且拒绝脚本错误和 ObjectDB 泄漏消息。

### 完整路线结果（无官方 Profiler/GDB）

详表 `white_typed_final_comparison.json`。入口时间与需求收敛分开记录；卸载/返回峰值与稳态 FPS 分开记录。

| 运行 | 入口 s | 原地额外收敛 s | 返回额外收敛 s | 卸载最大帧 ms | 返回加载最大帧 ms | 返回稳态 FPS | 卸载/重载 spec 数 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `white_scan_verified_native` | 18.615 | 42.217 | 40.380 | 133.077 | 158.054 | 128.99 | 4480/4393 |
| `white_publish_validation_control` | 19.337 | 39.855 | 46.757 | 132.122 | 185.189 | 146.53 | 4471/4392 |
| `white_typed_owner_native` | 18.659 | 40.195 | 39.132 | 134.748 | 146.489 | 135.58 | 4477/4394 |
| `white_typed_final_native` | 20.267 | 44.807 | 44.456 | 170.575 | 166.061 | 135.56 | 4470/4392 |
| `white_scan_verified_walk` | 19.174 | 42.518 | 0.017 | 73.782 | 65.161 | 139.74 | 556/240 |
| `white_publish_verified_walk` | 19.941 | 43.710 | 0.039 | 66.302 | 54.086 | 161.40 | 521/240 |
| `white_typed_final_walk` | 18.442 | 39.544 | 0.019 | 72.588 | 76.448 | 156.63 | 561/240 |

最终 native/walk 两条路线均无失败，源代码与地图 SHA 在各自运行期间不变，实际 GPU 表面全白，退出时模板、GPU 回收队列、工作线程、admission/lookahead 字节和 loading render context 均为零。远行路线确认最大建筑完整卸载并恢复 2,151 部件；步行路线覆盖真实区块交界。

三维结论：

- **FPS/帧耗时**：不能宣称整条管线完成优化。首版类型路线返回加载峰值 146.489ms，最终版 166.061ms；最终卸载仍有 170.575ms 长帧。最终建筑提交 158.453ms，其中 final validation 22.742ms、fragment 33.207ms、白模测试材料归一化 12.934ms、导航 append 39.033ms。步行卸载/重载峰值 72.588/76.448ms，稳态 FPS 156.63、p99 18.346ms。FPS 为显式 uncapped、无外围系统的白模测量，不能冒称完整游戏 FPS。
- **时间**：最终 native 入口 20.267s/返回额外收敛 44.456s，与其他运行仍有波动，未证明整图加载耗时稳定下降。交接阻塞在受控夹具中明确下降。
- **工作量**：类型包直接交接，提交不再递归扫描视觉引用。最终 native 与第一版类型路线均处理 49 个模型包、85,035 个 importer 值、2,899 个 visual 引用；模板所有权转交后回收服务 Resource 计数从 35,491 降为 32,778，少处理 2,713 个 Resource。两次整图卸载数量有差异，不能把整图工作量变化全部归因于优化；上述固定类型包/导入值计数是单独列出的证据。

本轮仅完成模型交接结构和对应回收链的修复验收。约 140–170ms 的索引/发布/整块卸载事务仍未通过白模性能门槛；不启用纹理，不合并外围功能来掩盖这些问题。

### 最大建筑真实 GLB 的隔离 ABBA

进一步使用 `tools/stress_axel_model_resource_owners.gd` 直接调用生产 `Deferred.prepare_scene`，每轮重新准备同一真实源 GLB。保持白模/关闭纹理，源文件 SHA 前后相同，不写入地图或编译缓存。实际每轮 2,318 个 glTF 节点、2,007 个独立网格、2,151 个视觉引用、2,319 个 PackedScene 节点；构建耗时单列，不计入交接/回收范围。

`white_typed_actual_stress.json`：四轮 ABBA，28 项检查全部通过。旧包只在测试中复现，生产者始终生成新类型。

| 指标 | 原混合数组包（两次均值） | 新类型包（两次均值） |
| --- | ---: | ---: |
| 同步交接 | 4.305 ms | 0.034 ms |
| 完整回收 CPU，含所有后续切片 | 828.001 ms | 734.249 ms |
| 每轮 importer 值数 | 45,703 | 45,703 |

这是实际数据上的交接耗时变化，不是由缩小场景或减少网格获得；两次候选均完成全部资源弱引用释放。完整回收的四次原始耗时依次为旧 746.355、新 753.326、新 715.171、旧 909.647ms，存在明显波动；不能认定总 CPU 已稳定下降，也不把均值差异外推成整图加载或 FPS 的同等提升。这里的 CPU 计时是主线程执行区间累计的墙钟时间，包含系统调度影响。原生导入字段/析构的个别切片仍约 10–12ms，未宣称硬性 1ms 上限。

`white_typed_model_gpu_cancellation`：102 项通过，新增两条实际 raw 路径：解析后取消、生成场景后取消。均验证明确的导入状态/私有场景交接，主线程释放以及最终配额归零。

### 官方 Profiler 最终复核

`white_typed_final_official.bin` / `_summary.json`：49,902 个协议包、24,101 帧，解码成功；路线全部通过，退出所有者/配额归零。最大建筑发布位于 frame 26469，官方采样整帧 184.170ms。

| 官方采样的包含子调用范围 | 原始基线 frame 33587 | 中间复核 frame 26216 | 最终 frame 26469 |
| --- | ---: | ---: | ---: |
| `_publish_items` | 212.629ms | 174.047ms | 179.371ms |
| `Index.append` | 86.943ms | 64.366ms（快照开启） | 86.806ms（快照默认关闭） |
| `Navigation.append_specs` | 53.133ms | 31.584ms | 28.290ms |
| `_discard_job` | 21.261ms | 45.563ms | **1.428ms** |
| `dispose_result` | 16.816ms | 39.967ms | **0.052ms** |
| `_dispose_owned_value` 调用数 | 2,168 | 2,168 | **8** |
| 新 `defer_model_packet` | 不适用 | 不适用 | **0.052ms** |

这些是同种官方 profiler 的方法归因，不能拿含 profiler 的 184ms 当作游戏实测。包含范围不可相加。中间复核的 snapshot 开关不同，因此索引范围也明确列出配置，不归因于本次所有权重构。最终结构在真实最大建筑上命中，消除了发布帧内逐个扫描/销毁视觉引用的调用链，满足时间/提交工作量维度的收益要求；其他仍长的事务没有因此被宣称解决。

复现入口：

- 纯逻辑：`tools/test_owned_packet_retirement.gd`，headless。
- 真实 GPU/取消/失败：`tools/test_deferred_model_owners_gpu.gd`，通过 `tools/run_godot_background.py`。
- 等形 2,151/21,510 压测：`tools/stress_model_resource_owners.gd -- --output=<external.json>`。
- 实际最大建筑：`tools/stress_axel_model_resource_owners.gd -- --output=<external.json>`。
- 完整路线：`tools/profile_axel_white_streaming.gd` 配合 `--mesh-only --without-map-textures --white-material --without-hud --uncapped-runtime --settle-demands`，native 使用 `--native-only --native-departure`，步行使用 `--walk-only`；实际完整参数保存在证据目录的 runner/launch 文件。

所有 GPU 命令均由背景启动器放在不激活的私有桌面执行；原始日志、失败实验、完整 JSON 和捕获数据均留在外部 review_artifacts，不进入项目导入目录。
