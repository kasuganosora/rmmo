# 根节点变化与重复区块计划（2026-10-26）

接续 `axel_material_cache_trim_20261026.md`，基线为 `3e365cf2`。本轮处理真实地图
重载诊断中的候选收集与网格重扫，目标仍是完整加载、low 帧和工作量三个维度。
证据目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/stream_adoption_20261026/`。

## 复现依据

前轮官方 `cache_trim_20261026/reload_official11` 的重载 frame 26771 为 65.859ms，
`world_stream._sync_work` inclusive 29.112ms，含 `_candidates` 17.397ms、
`_collect_meshes` 6.892ms（3266 次 `has_meta`）。这些是诊断运行的证据，不能
直接当作正常游戏耗时，或与其他 inclusive 子项再次相加。

代码路径：根节点数量变化 → `_adopt` 重扫场景 → 无条件丢弃旧区块增量计划 →
重新收集所有 live / spatial / whole-building 候选。它没有区分新增模型、已登记
的运行节点、辅助服务与移除节点。

`test_stream_child_adoption.gd` 初始复现：已有 3500 个对象时，仅新增无模型服务，
就重新选择 3500 个候选；baseline01 为 31.421ms，其中空 adoption 9.723ms。
baseline01 含测试自身读取不存在 metadata 的错误，原日志保留；修正读取后
同代码关闭优化的 control03 为 29.980ms / 空 adoption 8.922ms，且无报错。

## 实现与边界

- 根节点 `child_entered_tree` 仅登记未标记 `stream_instance` 的新增直接子树，
  使用 WeakRef，不持有场景资源。正常已登记视觉/服务无需再进入 adoption。
- 消费新增子树时保留外部子节点顺序与 internal-node 排除语义，只遍历新增
  子树；确有未标记新增根时才枚举直接子节点，不遍历已有后代或逐个查 metadata。
- 空 adoption 不再丢弃已有区块、候选数组、游标或碰撞任务。真实新增 spec、
  显式 `stream_children=-1`、初始/离树后重入、以及数量下降的修复路径仍重建。
- 数量下降继续保留旧修复计划，避免漏掉非预期销毁的 live owner；没有宣称所有
  移除情况下的全量候选计划均已消除。正常 `retire_specs` 仍维护既有登记与计数。
- 离树修改不产生 entered-tree 事件，重入强制一次完整核对，覆盖相同子节点
  数量下的替换。显式失效仍能发现既有容器下新增的模型。
- tracker 存于 `runtime_adoption_changes`，不进入供后台索引任务借用的 `stream_*`
  状态。无 package SHA/纹理校验、模型读取或上传方面的新工作。
- `--full-stream-adoption` 保留原路径，用于同代码对照；缓存裁剪等前轮有效
  优化在双方均开启。

## 独立压测与已修正的问题

unit05 的 20 次辅助节点变化：对照 441.354/427.420ms，候选 0.490/0.497ms；
重新选择候选合计 70000 → 0。3500 节点释放约 31.9–33.5ms，未额外增加逐节点
销毁回调。这是特定条件的独立复现，不作为整图 FPS/加载收益。
最终 unit13 再测：对照 437.982/436.651ms，候选 0.510/0.502ms；释放对照
32.654/28.247ms，候选 31.548/31.369ms。保留两轮结果，不用微测宣称地图帧率。

初版曾监听每个子节点退出以判定登记关系，unit04 整图销毁约 47–50ms，
对照 34–35ms，反而增加约 15ms。该方案撤去，保留失败数据；最终仅监听新增
和整根离树，移除走既有修复语义。

unit04 的门轴 fixture 缺少 `pivot`，以及断言使用已经被索引重建替换的旧 Dictionary，
均已修正测试。unit11_before 另外独立复现了候选代码真正的缺口：显式失效但无
新增模型时未重建候选。已补上 explicit rebuild 条件，未放宽断言。

功能覆盖新增嵌套模型的世界变换/共享 mesh/楼层/活动门元数据、入队后删除、内部
子节点排除、离树等数量替换、显式嵌套失效、最后 owner 释放、外部删除修复、
已有区块计划继续推进。最终独立检查与关联回归以 unit13 / logic13 记录为准。
最终 10 组逻辑回归共 170 项通过，其中本轮新增用例 18 项。

回归暴露三份旧测试签名滞后：QuietBatch 缺少 `immutable_append` 参数、
`_spawn` 调用缺少 map_root、GateDeferred 对动态 worker.start 的类型推断失败。
已按 HEAD 已存在的接口更新调用，业务断言保留；不是本轮引入的生产接口改动。

GPU08 建筑通行 20 项和资源卸载/返回 54 项通过；游戏入口首次候选 11 通过 / 2
失败，30 秒时尚未解锁，测试结束还留下导航协程恢复错误。关闭候选的 control09
13 项通过。上述 explicit-rebuild 缺口修复后 candidate12 同流程 13 项通过。
原超时保留，未得到其同帧调用栈，不把因果关系或 OS 归因写成已证明。

GPU10 的追加流式测试进一步暴露旧 fixture 只有 GLB、没有原生产物。关闭优化
后的 shared_control14 独立复现相同失败，MapLoader 明确返回“游戏模型缺少可用
原生产物 … (absent)”。测试现先用现有导入编译器生成 native，再进入游戏；
**没有恢复游戏 GLB fallback**。GPU15 全部 92 项通过，含近/远实例零重复模型
准备、发布期间连续追加、碰撞、共享身份和作者数据保持。最终 GPU 回归累计
179 项通过（入口 13、建筑通行 20、资源回收/返回 54、流式追加 92）。

## 整图与官方复测

沿用地图加载开始 → 当前需求连续三帧完整就绪、纹理输出与消费者排空的口径；
map/prefab 纹理开启，导入模型材质仍白模，HUD/MockServer 关闭。几何/包围盒/
模型元数据缓存禁用，native、依赖目录与纹理磁盘缓存保留，OS 缓存未控制。
不把该阶段等同完整游戏画面验收，也不以四次样本宣称 cold 或 p95 稳定性。

### 正常 map09 ABBA

| 样本 | 入口 s | 完整就绪 s | 卸载 max ms / >50 数 | 返回 max ms / >50 数 | 重载 max ms / >50 数 | 重载 1% low FPS |
|---|---:|---:|---:|---:|---:|---:|
| A1 全量 adoption | 4.229 | 11.456 | 31.895 / 0 | 36.611 / 0 | 49.061 / 0 | 26.819 |
| B1 增量 adoption | 4.153 | 10.904 | 42.948 / 0 | 29.294 / 0 | 50.920 / 1 | 27.699 |
| B2 增量 adoption | 4.095 | 10.766 | 30.081 / 0 | 33.796 / 0 | 47.073 / 0 | 26.867 |
| A2 全量 adoption | 4.151 | 11.217 | 31.230 / 0 | 39.569 / 0 | 53.399 / 1 | 23.228 |

本组完整就绪均值 **11.336 → 10.835s，减少 0.501s / 4.4%**，入口均值只相差
约 66ms；没有沿用上一轮首样本两秒多的入口差。重载 1% low 均值 **25.024 →
27.283 FPS（+9.0%）**；p99 对照 34.146/37.741ms，候选 33.467/33.973ms。
1% low 仍按 1000 / 最慢 ceil(N×1%) 帧耗时均值计算，各阶段单独统计。
两组每种模式仍不足以证明稳定 p95 或普遍收益；不是已经低于 10 秒的结论。

卸载 1% low 均值约 125.58 → 123.80 FPS，轻微退步；B1 卸载 max 42.948ms /
process 21.765ms，比对照峰值高。候选卸载/返回均无 >50ms，但 B1 重载还有
50.920ms / process 34.528ms。各相同阶段均保留慢样本，不宣称所有 low 均改善。

工作量证据：A1/A2 完整 adoption 扫描 **6/5 次**，B1/B2 **1/1 次**；四组
adoption 新发现 spec 均为 0。地图模型实际通过原生 specs 发布，重复树扫描没有
带来新记录。候选额外的 6/7 次 empty-adoption 通知不会重扫树或重置游标；
`avoided_replans` 也计入已更新计数但尚待消费的空通知，不能当作与旧路径严格
一一对应的省略次数，跨模式直接比较的是 `full_scans`。

所有样本 GPU 上传 **170 次 / 721,332,072 B**，其中 DDS 148 次 / 508,911,392 B；
source identities 均 85，pixel retries 均 0，shared produced 为 158–161。
instances 对照 3289/3311、候选 3322/3298；models 对照 66/68、候选 69/66；
worker CPU 累计对照 24.250/24.579s、候选 24.325/24.524s。异步顺序使这些数
略有变化，没有凭它们宣称模型读取减少或全部后台工作缩短。

四组功能检查通过、source/map SHA 不变；最终 admission、lookahead、retirement、
worker、retained template 和 shared pixels 全部归零。首轮候选不扩大缓存或预算。

就绪后静止段候选 56.058/57.837ms，process 11.724/6.453ms；对照 A1 也有
69.600ms / process 12.050ms，A2 max 47.827ms。尚无这些正常样本的同帧线程栈，
不能归为已确认 OS/GPU 问题，也不能计作本轮修复完成。

### 官方 profiler

`reload_official10` 使用同引擎、caller attribution 和 map09_B2 命令单独运行。
引擎、receiver、decoder 全部 exit 0；无 errors/failures，source/map SHA 不变。
与前轮 `cache_trim_20261026/reload_official11` 的同模式诊断比较：

| 函数 | 前轮次数 / 累计 inclusive ms | 本轮次数 / 累计 inclusive ms |
|---|---:|---:|
| `_collect_meshes` | 14 / 16.066 | 2 / 0.010 |
| `_adopt` | 7 / 16.402 | 7 / 0.373 |
| `_candidates` | 7 / 75.858 | 2 / 30.633 |

两次剩余完整候选计划是初始和卸载；重载段不再出现前轮 17.397ms 的重新收集。
卸载 frame 5799 仍为 34.163ms，`_candidates` 20.729ms，`_adopt` 0.114ms。
同帧 `_index_buildings` 调用 2 次，配合没有新 spec、没有再次 collect 的证据，
对应本轮保留的数量下降重建分支；前一帧 5798 正在 `_apply` / batch `_drop`。
下一步独立复现“受控删除完成，但 child-count 标记还未提交就切帧”的情况；
研究在已授权的删除事务内同步计数，仍保留外部删除的修复，不重新引入逐节点退出
监听。这条剩余路径尚未修复，不能把候选维护整体称为已解决。

其他未完成证据：

- 返回 frame 24640：44.146ms，需求刷新 37.530ms（self 25.380ms，1520 次距离
  计算 1.728ms）；相邻 frame 24601 的刷新 36.900ms，空间目录查询 8.790ms。
- 卸载 frame 8671：57.987ms，`Thread.wait_to_finish` 10.421ms、导航移除登记
  14.153ms、索引提交 8.502ms。`resident_retirement_selection.rows` 含 worker
  聚合（78.887ms 大于整帧），不能直接视作主线程时间或重复相加。
- 首次 cover 内 frame 1826：401.214ms，实际 `Mesh.surface_set_material`
  335.572ms；下一帧仍有 103.085ms 材质提交。这项与本轮场景树维护相互独立。
- 重载诊断 max 49.941ms，含测试工具 `track_membership` 12.266ms；另有帧的
  测试观测 13.246ms，不能把删除观测所得差值冒充游戏优化。
- 正常 B1 的 50.920ms 帧没有同帧栈；官方另一次运行没出现同样 >50ms 峰值，
  不等于该正常慢样本已定位或消除。

原始 trace 和 `official10_comparison.json` 保存详细证据。以上只作调用归因，
不把 profiler 开销、worker 聚合和正常 ABBA 混用。

## 复现入口

- `tools/test_stream_child_adoption.gd`：默认执行语义与 ABBA 压测，
  `--expect-baseline` 只复现原全量路径；支持 `--output=<external>/report.json`。
- `run_logic13.py`、`run_gpu10.py`、`run_world_candidate12.py`、`run_gpu15.py` 为
  外部执行清单，GPU 调用均通过 `tools/run_godot_background.py` 的不激活桌面。
- `run_abba09.py` / `summarize_abba09.py` 保留四次正常完整路线；正式仓库入口为
  `tools/run_axel_texture_phase.py --engine <engine> --output <external-prefix> --texture-profile --traverse`，对照加 `--full-stream-adoption`。
- `run_reload_official10.py` 保留原始 profiler `.bin`、逐帧报告、decoder summary
  与 source/engine/map SHA 清单；各次失败日志保留，不被最终结果覆盖。
