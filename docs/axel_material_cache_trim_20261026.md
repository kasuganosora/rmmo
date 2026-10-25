# 材质热缓存增量预算（2026-10-26）

接续 `axel_retirement_selection_20261026.md`，目标仍是完整加载耗时与 low 帧，
不是只让单个函数的微测变快。基础提交 `3734d2a8`，运行引擎沿用 installed
4.7.2 ed1daf0bf / SHA `0f0bf4469c70de8d051b1e6d22293ed508e077bf1c1a326c6291d50890e583e0`。
（最终以各样本 launch.json 中实际计算的 engine_sha256 为准。）

证据目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/cache_trim_20261026/`。

## 证据与机制

前轮官方 profiler 的重载帧 22082：`trim_cached_resources` 16 次 / 23.745ms，
排序比较 8068 次，材质纹理属性读取 1512 次，成本读取 984 次。整段诊断中该函数
370 次 / 340.547ms，所以不能据单帧峰值推算首次加载可减少数秒。

原实现每次纹理/材质进入热缓存都遍历所有材质的六个纹理属性，重建唯一纹理成本及
依赖计数，并且没有超预算也排序。本轮：

- 新入缓存只登记纹理 instance ID 和成本，按唯一对象去重。删除缓存不逐项维护
  反向计数，保留保守上界；达到字节预算或元数据数量边界时，再做完整核算和淘汰。
- **256MiB 预算不扩大**；字节成本仍是 hot cache 所持唯一上传 footprint，
  不是实际 RSS/VRAM。零预算、单独大材质、失效估计和显式 trim 仍完整核算。
- 未超预算不排序；新增成本已有 runtime_upload_bytes 时，不再急切计算未使用的
  width×height 默认值。真正淘汰保持已有 LRU 顺序、弱目录及 live owner。
- 累积 ID/成本不持有资源；元数据按 1024 个纹理 ID / 256 个 recency key 的边界
  重新整理。删/清热字典只会使上界偏高，显式 trim 也支持旧调用者的原始字典写入。
- 纹理 changed 或 BaseMaterial3D.property_list_changed 使估计失效。
  本机引擎源码确认 BaseMaterial3D.set_texture 不 emit_changed，只通知属性列表。
  完整核算后仅为保留的资源补充监听，避免再为已淘汰对象做重复工作。
- prefab 交接已有 GPU ticket 时只登记弱引用；job 本身仍持有并计费，不再把整包
  ticket 重新塞入热缓存。真正的 texture() 消费者按需恢复热引用并执行预算。
  零热预算仍通过弱引用与 job owner 完成绑定；未改源纹理、模型、地图、材质值和
  采样语义。下文保留了先恢复全部 ticket 再裁剪所造成的反效果。
- `--full-cache-trims` 保留原全量核算及原 packet 原始交接，用于同代码 A/B；
  该控制不是额外扩大对照工作量的替代路径。

## 独立复现与回归

`test_incremental_material_cache.gd` 的最终 unit09：5780 项通过。逐次比较 320 次插入
的全部 hot membership、顺序、实际唯一引用成本，覆盖共享纹理、64MiB/5MiB/零
预算、live 材质换图、纹理原位更新、预算收紧、关闭再开启预算、原始字典显式核算、
无纹理材质反复替换、job ticket 弱交接不加入热预算，以及最后引用释放。

unit09 的 64MiB 场景两组 full-control / incremental：约 459/440ms → 4.49/4.29ms，
完整扫描 320 → 1，材质属性读取 172800 → 1440，成本读取 9878 → 32，排序候选
31248 → 0。这里用小 GPU 纹理与声明的逻辑成本复现记账工作，不把这组数字当作
地图 FPS 或实际显存变化。

5MiB 压力场景的候选仍有代价：约 14.33/14.23ms，对照 12.19/12.18ms；新增对象多数
会立即触发完整核算，成本读取 1600 → 2080。零预算仍完整扫描，没有跳过预算。
这部分负面数据保留，不宣称所有容量下都更快。unit05 的同一算法重复样本也保留：
64MiB 对照 585/587ms、候选 8.4/11.9ms；5MiB 对照 13.2/15.0ms、候选 16.5/16.8ms。

最终 GPU09 回归覆盖 material_residency_budget 8 项（实际 renderer memory 下降、
live owner 复用、零预算进度），纹理失效复用 7 项，编辑器 prefab 29 项、terrain
26 项（含真实 HTTP 保存/坏图修复），streamed publication 103 项，DDS publication
115 项，latest runtime 33 项。编辑器坏 PNG 用例的预期解码错误完整保留。

保留的失败：unit01 的类型推断 parse 错误；unit02 暴露的材质通知监听遗漏，以及
生命周期测试未退出 VM 参数临时引用作用域；首次 DDS 测试遗漏 --fixtures；旧
latest runtime 的内容 SHA 用例在默认 trusted 路径下四项失败，关闭候选也相同。
该测试已明确切到诊断字节身份读取，退出后恢复策略；**生产不恢复资源校验**。
unit08 因修改脚本默认 GBK 读取 UTF-8 失败造成调用名未同步，parse 失败原日志保留；
修正为显式 UTF-8 后 unit09 与 GPU09 全部通过。

## 整图对照

使用完整 ABBA；地图开始加载 → 当前需求连续三帧完整就绪，像素消费者与队列已
排空。map/prefab 纹理开启，导入模型材质仍白模，HUD/MockServer 关闭；不等同完整
游戏画面验收。几何/包围盒/模型元数据缓存禁用，native/依赖索引/磁盘纹理缓存保留，
OS 缓存未控制。正常样本与官方 profiler 分开记录，不以四次样本宣称 p95 稳定。

### 未采用的整包热引用恢复：map06

| 样本 | 完整就绪 s | 卸载 max ms / >50 数 | 返回 max ms / >50 数 | 重载 max ms / >50 数 | 重载 1% low FPS |
|---|---:|---:|---:|---:|---:|
| A1 全量核算 | 13.874 | 29.907 / 0 | 46.518 / 0 | 59.634 / 2 | 25.003 |
| B1 初版增量 | 12.171 | 77.472 / 2 | 158.255 / 59 | 61.075 / 9 | 19.921 |
| B2 初版增量 | 12.494 | 40.154 / 0 | 29.656 / 0 | 62.723 / 1 | 26.441 |
| A2 全量核算 | 11.468 | 45.176 / 0 | 44.926 / 0 | 94.263 / 1 | 24.267 |

A1 入口 6.097s，其余约 4.224–4.653s，不把首轮入口差全部算成候选收益。初版
完整扫描 A1/A2 为 370/368 次，B1/B2 反而 639/584 次；属性读取 9510/9588 →
33852/27120，排序候选 19076/19076 → 43545/39332。B1 的 158.255ms 帧包括
process 73.145ms / deferred bookkeeping 71.911ms；没有该正常样本的栈，不能
归为 OS 空闲。该版不接受为最终结果，`candidate06.patch` 与源码快照保留。

随后官方 profiler `reload_official07`：713 次完整扫描，其中 712 次是插入超过
预算触发；716 次 ticket 恢复，未出现资源变更/dirty-hit 触发。问题是初版把每个
已有 owner 的 ticket 放回热缓存时立即裁剪，重复制造压力，而不是材质变更信号。
因此改成上述弱交接，再跑 unit09、GPU09 和最终 map10。所有 map06 样本上传均
170 次 / 721,332,072 B，功能检查通过、最终配额归零；这不能掩盖帧耗时退步。

### 最终弱交接：map10

| 样本 | 入口 s | 完整就绪 s | 卸载 max ms / >50 数 | 返回 max ms / >50 数 | 重载 max ms / >50 数 | 重载 1% low FPS |
|---|---:|---:|---:|---:|---:|---:|
| A1 全量核算 | 6.027 | 13.384 | 36.291 / 0 | 26.954 / 0 | 49.580 / 0 | 26.669 |
| B1 最终增量 | 4.208 | 11.058 | 48.794 / 0 | 30.162 / 0 | 42.705 / 0 | 26.676 |
| B2 最终增量 | 4.203 | 11.240 | 45.197 / 0 | 35.670 / 0 | 50.235 / 1 | 26.282 |
| A2 全量核算 | 4.064 | 11.162 | 44.781 / 0 | 30.651 / 0 | 45.357 / 0 | 26.289 |

1% low = 1000 / 最慢 ceil(N×1%) 帧耗时的均值，各阶段单独计算。重载 1% low
两组均值对照/候选均约 **26.479 FPS**；p99 对照 33.898/33.615ms、候选
34.674/34.246ms。**没有证明总加载或整体 low 帧改善**，不能用 A1 慢入口制造
秒级收益。候选 B2 仍有一帧重载 50.235ms（process 37.610ms），尚未消除。

| 整段缓存工作 | A1 / A2 | B1 / B2 | 两组均值变化 |
|---|---:|---:|---:|
| 完整核算次数 | 386 / 378 | 35 / 35 | -90.8% |
| 纹理成本读取 | 18566 / 18060 | 2266 / 2252 | -87.7% |
| 材质纹理属性读取 | 9288 / 8484 | 3306 / 3372 | -62.4% |
| 参与排序的候选累计 | 20073 / 19362 | 2276 / 2241 | -88.5% |

候选每组完整核算为一次初始化 + 34 次预算触发；其余走 336/346 次增量检查。
所有样本上传相同：170 次 / 721,332,072 B，其中 DDS 148 次 / 508,911,392 B。
唯一 source identities 都为 85；共享像素 produced 对照 161/162、候选 158/158，
pixel retries 均 0。随行走/发布调度，实际 instances 为 3269–3330、models 64–71，
并非每轮所有异步工作数完全相等；不把这些波动算作模型去重收益。

全部功能检查通过，source/map SHA 不变；最终 worker、admission bytes、资源
retirement、retained templates、共享像素 outputs/consumers/bytes 全部为 0。
不增大预算、不增加 GPU 上传，缓存维护工作明确下降，按“时间/FPS/工作量任一
维度有效可保留”的要求保留此实现；加载低于 10 秒和剩余长帧仍未完成。

就绪后静止段：B1 62.270ms / process 9.203ms，B2 51.526ms / process 11.670ms；
A2 也有 52.887ms / process 8.947ms。没有对应线程栈，不能归为已确认 OS/GPU
问题。候选卸载/返回没有 >50ms，不代表所有工况稳定；最终私有数组释放 max
仍为 23.616/24.096ms，返回需求刷新 max 为 19.759/27.620ms，后续继续定位。

### 官方 profiler 复测

`reload_official11` 与正常 ABBA 分开运行，使用同引擎、候选及 caller attribution。
引擎/receiver/decoder 全部 exit 0、无 errors/failures，source/map SHA 不变。
对照为前轮 `retirement_selection_20261026/reload_official10`（原全量核算），
不是把已否定的 official07 当基线：

| 缓存维护 | 原全量核算 | 最终增量 |
|---|---:|---:|
| trim 调用次数 | 370 | 35 |
| trim 累计 inclusive ms | 340.547 | 56.468 |
| trim 最大单帧合计 ms | 23.745 | 11.593 |
| texture cost 调用次数 | 17388 | 2273 |

候选还包括 `_trim_after_insert` 累计 72.715ms（已含 trim，不能与 56.468 相加），
hot-hit 检查 2.527ms、ticket 弱交接 5.451ms。最大 trim 出现在重载 frame 26313，
整帧 28.404ms；缓存维护下降，但预算触发时的完整核算仍有可改空间。

剩余诊断线索按真实调用边界记录：

- 重载 frame 26771：65.859ms / process 65.700ms，`world_stream._sync_work`
  inclusive 29.112ms，含 `_candidates` 17.397ms、`_collect_meshes` 6.892ms；
  后者发生 3266 次 `Object.has_meta`。下一步先复现候选/网格注册的全量扫描，
  检查是否能复用已登记对象和变化集合，保留活动门窗、楼层与遮挡语义。
- 重载 frame 26905：64.955ms，其中测试工具 `track_membership` 16.042ms；
  此项属于测量开销。不能删观测后把耗时下降写成游戏优化，需保留可比口径。
- 返回 `_refresh_demanded` max 31.947ms；卸载 frame 10074 的线程 join 2.280ms。
  `resident_retirement_selection.rows` 等函数含 worker 聚合，不能用它的 44.940ms
  inclusive 直接解释 37.411ms 的主线程整帧。
- 首次加载 frame 1872 的 `Mesh.surface_set_material` 仍为 327.871ms（cover 内），
  是剩余首次提交成本；本轮缓存记账优化没有声称解决该项。

官方逐帧/累计数据含 profiler 开销与 worker 聚合，不能直接替代正常帧数据，
或把后台累计耗时相加到主线程。正常样本 50.235ms 的重载帧没有同帧栈，不能
仅凭另一诊断样本就认定它也是同一原因。`official11_comparison.json` 保存详细
累计函数与慢帧摘录，原始 `.bin` 可再次提取任意指定帧。

## 复现入口

- 独立测试：引擎 headless + `--path <worktree> --script res://tools/test_incremental_material_cache.gd -- --output=<external>/unit.json`。
- 真实 GPU 回归：外部 `run_gpu09.py`，七项测试全部通过 `run_godot_background.py`
  在不激活桌面运行；坏 PNG 的预期错误日志保留。
- 正常对照：`run_abba10.py` / `summarize_abba10.py`，只切换 `--full-cache-trims`。
  正式入口为仓库 `tools/run_axel_texture_phase.py --engine <engine> --output <external-prefix> --texture-profile --traverse`。
- 官方诊断：`run_reload_official11.py`；原始 `.bin`、逐帧 `.json`、`.summary.json`
  与 launch/result 清单独立保留。首次失败版官方诊断 `reload_official07` 不替换。
