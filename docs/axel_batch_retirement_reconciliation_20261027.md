# 来源退出后的合批准备去重（2026-10-27）

接续主日志 §173 的晚期额外准备访问。分支 `codex/latest-map-runtime-review`。
完整加载边界仍是地图加载开始到当前需求完整就绪；没有改预算、worker 数量、绘制范围
或就绪条件。地图/prefab 纹理开启，导入模型仍使用无材质 native，不是全材质游戏验收。
后台 GPU 上传与完整建筑提前通知候选继续默认关闭。

证据目录（下文 X）：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/batch_reconciliation_20261027/`
引擎仍为 engine09，EXE SHA
`40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`。
没有修改引擎或美术资源。

## 实际触发链

在现有 batch timeline 中增加 residency 请求的旧/新前缀、失效原因、owner 和调用栈。
所有细项仅在 `Timeline.enabled` 时收集，普通性能样本不收集调用栈。
`trace02` 退出 0、functional_ok=true、errors/failures 为空、源码/地图未变。
11,136 条 timeline 无丢弃。这是诊断样本，不计入性能对照。

`trace02_reload_reset_chain.json` 保存实际链：

1. 100210.999ms，来源从 911 追加到 914，旧前缀相同；request 134 完成 914 项。
2. 100352.657ms，`obj_82__arch_C_LOD0` 退出。`WorldStream._apply →
   _sync_work → sync` 调用 `retire_sources`，清空了包含其他来源的整份完成记录。
3. 其后 LOD1/LOD2 退出；100385.316ms 请求余下 911 个来源时，完成记录已为空。
   后续来源到达只能从这轮重新准备。

该诊断最终 8765 次 prepare，比常见 7851 多 914。176 次空逻辑退出在本次诊断中
均发生于空状态，不能把它们说成这次 914 次重复的触发原因。全程 4143 次 bin_reset
中，4140 次 retire 的准备/完成记录均为空，仅 2 次 retire 存在非空完成记录，另有
最后 clear。没有观测到退出打断非空准备游标。

这证明“单个来源退出使有效完成记录整体丢失”的真实路径；§173 的额外 3810 次访问
没有同样 timeline，不能声称已经拿到了那一帧的精确失效栈。

## 改动及所有权边界

`GroundBatcher.retire_sources` 默认开启增量退出。只有已完成、无待处理请求、明确为
immutable residency 的记录可保留；移除确切退出 Node 的描述及名字，把相应桶标脏。
原 `_release_groups` 仍立即移除受影响绘制并恢复应继续可见的成员。

下一次 residency 请求仍在原游标/预算中重新收集、删去缺席成员。只跳过名字与 Node
身份同时相同的不可变幸存者；新的来源、相同 UUID 下的新 Node 均重新准备。只对
受影响桶重新排序和打包，复用其他桶。没有把引擎 Node 访问移到不安全的后台线程。
原始桶只含成员/弱描述，没有持有已退休的 GPU 网格；没有新增资源池或无界队列。

空退出直接返回，避免取消尚未完成的准备。真正退出发生于未完成准备、编辑或普通
可变请求时，仍保留原失效重整路径。显式编辑 invalidation 会撤销复用资格。

独立复现又发现：退出后的 prune 游标正运行时若有新来源追加，原逻辑再次丢掉完成
记录。现在复用已有 `_next_residency`，先结束这个有预算的游标，再追加最新请求。
不是增加生产槽位；唯一待处理快照仍由原逻辑合并。这个 prune 修复在整图 A/B 两组
均开启，A/B 只切换增量退出。

新增计数为 `retirement_reconciliations`、`retirement_prepares_avoided`、
`empty_retirements_skipped`。`--without-incremental-source-retirement` 可运行旧退出
逻辑，开关写入 launch/report，结合实际计数确认执行路径。

## 独立复现与回归

`tools/test_batch_retirement_reconciliation.gd` 使用固定 32 栋 × 32 个来源，并与
全新完整排序重建的 oracle 比较成员、姿态、顶点计数、材质键和原点；GPU 模式进一步
比较实际上传网格的全部 surface arrays 和材质。使用独立测试内容，不改用户地图。

| 固定情形 | 旧 prepare / pack | 新 prepare / pack |
| --- | ---: | ---: |
| 3 个不可合批的晚到 LOD 退出，剩余 1024 来源不变 | 1024 / 1024 | 0 / 0 |
| 首/中/尾成员退出，加一个同桶较早名字 | 1022 / 1022 | 1 / 94 |
| 同 UUID 以新 Node 和新姿态返回 | 1023 / 1023 | 1 / 63 |
| 空逻辑退出 | 1024 / 1024 | 0 / 0 |
| prune 中途追加一个来源 | 1024 / 1024 | 1 / 32 |
| 退出来源从未进入当前完成集合 | 1024 / 1024 | 0 / 0 |

CPU `regress11_final`：新用例 69、completed_bins 102、partial_ledger 148、
covered_arrivals 62 条通过；GPU `unit12_gpu_final` 57 条通过，errors 为空。
根据 trace16 的无关退出观察补充固定新旧分支回归后，最终 CPU
`unit17_unrelated_final` 81 条、GPU `unit18_unrelated_gpu_final` 71 条全部通过。
这个补充只修改测试，不改变 map07 测量时的生产源码。
此前同轮 closed_preparation 19、stream_owned_removal 20、GPU stream_departure 10
条也通过。编辑失效、未完成准备中退出的安全重整均与 oracle 一致，不谎称去掉这部分
仍必要的工作。

固定 4096 来源的 CPU ABBA 压测（最终 `regress11_final`）：

| 样本 | 退出和重整墙时 ms | prepare | pack |
| --- | ---: | ---: | ---: |
| A1 旧 | 231.603 | 4096 | 4096 |
| B1 新 | 74.358 | 0 | 0 |
| B2 新 | 74.366 | 0 | 0 |
| A2 旧 | 201.511 | 4096 | 4096 |

四次最终成员完全一致。前一轮 stress09 为 A203.411/206.663、B74.874/75.633ms。
这是测试的完整重整墙时，包含 1µs 游标驱动开销，不是生产单帧，也不能直接从地图加载
墙时中扣除。保留约 75ms 本身说明成员收集/排序仍有成本，不代表无优化空间。

失败样本保留：unit03 的空游标断言只检查 Dictionary 身份，清空原对象也会误通过；
unit04 补查 phase，旧实现 24 条通过、7 条性能断言失败，功能 oracle 通过。
unit06 的 GPU 测试动态字典类型推断解析失败，改显式 bool 后通过；不是生产故障。
unit10_prune_before 的外部 runner 虽退出 0，日志明确 engine 退出 1、对应性能断言
失败，不能算成功。修复 prune 后最终回归通过。

## 实际地图对照

ABBA map07，普通优先级、新进程、私有桌面，OS 缓存不清空，无 GDB/timeline。
固定关闭后台 GPU 上传及建筑提前通知；上一轮末端纹理交接去重均开启。
A 关闭增量退出，B 开启；不将普通新进程样本称作严格冷 IO。

四条退出 0，functional_ok=true、errors/failures 为空，源码/地图不变。796 个匹配
SHA 的测量源文件保存在 `map07_sources/`。`analysis14_summary.json`、
`analysis14_peaks.json`、`verification15.json` 保留原始汇总及工作量变化。

| 样本 | entry s | 完整就绪 s | 返回 1% low FPS | 重载 1% low FPS | 卸载/返回/重载 max ms |
| --- | ---: | ---: | ---: | ---: | --- |
| A1 旧 | 4.112556 | 11.301600 | 39.381 | 31.682 | 31.317 / 41.293 / 44.720 |
| B1 新 | 3.940127 | 9.650422 | 45.839 | 30.806 | 39.369 / 33.953 / 41.437 |
| B2 新 | 4.198697 | 10.175870 | 44.788 | 34.219 | 54.718 / 49.604 / 40.216 |
| A2 旧 | 3.961431 | 9.819217 | 44.852 | 33.479 | 29.942 / 33.574 / 38.712 |

不能由四条得到加载 p95，也没有证明整体加载或 low 稳定改善。B2 卸载 1 帧 >50ms，
其余所列区间 0 帧 >50ms；不能宣布所有尖峰解决。该 54.718ms 在 58981.030ms，
附近 draw/stream jobs/batch pending 为 0，无 queue observer，previous_process_wall
53.170ms；官方 process 9.918ms 是采样值，不能作为本帧独占 CPU 时间。无原生栈，
不能直接归为 OS 空闲，现场标量见 `map07_B2_unload_context.json`。

| 样本 | 全程 prepare | pack | builds | 增量退出重整 | 跳过幸存来源准备 | 跳过空退出 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A1 | 7851 | 7518 | 632 | 0 | 0 | 0 |
| B1 | 7851 | 7191 | 605 | 1 | 0 | 176 |
| B2 | 7851 | 7275 | 608 | 1 | 0 | 169 |
| A2 | 11802 | 10221 | 620 | 0 | 0 | 0 |

A2 再次出现额外 3951 次准备，主要集中于 departure 的 23.6–24.6s 区间；和 §173
重载后期的额外访问不是同一时间段，原始变化见 `map07_A2_preparation_jumps.json`。
但 B 两条避免准备计数都是 0，只在完整退出后空集合
重整中命中新分支，**没有复现 trace02 的幸存来源退出时序**。不能把 B 的 7851 与
A2 的 11802 差额全部声称为这次修复的真实收益；固定测试已经证明该时序去重，整图
仍需按触发记录而非最终数字推断。动态路线中的 pack/build 数量也不能视为固定工作
对照。另补 `trace16_after` 诊断，专门检查实际触发计数。

`trace16_after` 退出 0、functional_ok=true、errors/failures 为空、源码/地图未变，
timeline 无丢弃，最终 prepare 7851。3963 条 retire_preserved，只有最终 clear
发生 bin_reset；163 次空退出跳过。22.660s 起 12 次退出保留 3923 个 named 来源，
说明退出来源未进入该集合；下次 residency 请求已到 47.339s 全部退出后的空需求。
不存在此期间幸存来源的重整请求，avoided 仍为 0，不能据此冒称实测省掉几千次准备。
真实“保留记录”已观测，“相同幸存退出时序去重”由固定测试证明，二者分开记录。
诊断链见 `trace16_departure_preserved.json`、`trace16_analysis.json`；其时间不计性能。

四条初始均 231 builds / 3923 prepares / 2724 packs / 228 worker surfaces；最终均
229 groups / 2564 sources / 361 surfaces。GPU 审计均 3943 surfaces、3202 nonwhite、
1502 textured、145 unique textures。纹理上传均 170 次 / 721332072 字节；shared
produced 146，最终 outputs/consumers/retained bytes 为 0，退出 map_freed=true，
worker/资源回收/配额/模板/临时渲染上下文均归零。

host 记录显示 A1 多个阶段有其他 Godot 进程，B1 加载开头有其他 Godot、重载有 Blender，
B2 加载/返回/重载有 Blender，A2 加载/返回/重载有 Blender；这是进程存在观察，不能
代替具体 CPU/GPU 竞争归因。B2 卸载未观测其他这些相关进程，也不代表整个 OS 空闲。
不删除这些样本、不终止不属于本轮的进程，不以 A1 慢值宣称加速。

## 剩余边界

- 未完成准备中发生真正退出，仍走原安全重整；本轮实际 trace 未观察到这个触发，后续
  应按真实调用量决定优先级，不为消除所有回退盲目增加状态机。
- §173 的空卸载约 100ms 间隔仍缺原生现场，不能因队列为空便归为 OS 空闲。
  下一轮优先对齐冻结后已接收心跳、线程 CPU 增量与实际 RIP，采集这一类 process
  间隔；不能再把最后一个 UDP 标记当作冻结瞬间正在执行的方法。
- 初始 231 builds / 3923 prepares 的工作完全相同，但入口后的完整收尾仍约 5.7–6.0s
  （A1 更慢）。后续重看这段的真实发布、合批和绘制时序，按关键路径选择后台任务，
  不继续以与初始路径无关的退出微测声称加载目标已完成。
- 独立纹理回收 58–77ms、首次真实材质提交、首个 3D 帧及旧无栈 AV 未被本轮修复。
- 目标仍 active：完整加载与 low 要看真实关键路径，去重收益可以累计保留，但不能
  将每个独立累计耗时直接相加当作整图收益。
