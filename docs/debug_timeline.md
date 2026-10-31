# 原生内存时序采集

入口是 `Performance.debug_trace_*`，项目封装位于 `scripts/util/debug_timeline.gd`。这是单独的 4.8 诊断构建；普通默认引擎仍是原 candidate10，不能混用性能成绩。未带完整补丁的引擎返回 `ERR_UNAVAILABLE`，不会偷偷切换到有共享锁的脚本日志。

采集使用 Godot 单调微秒时钟，所有线程共用时间基准。每个线程独占自己的事件分片；事件不持有 Resource、Node、RID、Dictionary 或模型数据。普通写入只有标量、时间戳及线程私有位置更新，没有日志 Mutex 或自旋锁。每次捕获预分配并预触碰事件内存；分片满后用一次原子操作领取下一片。线程首次加入时登记一个小描述符，这一步仍涉及一次通用内存分配，不能宣称操作系统及分配器内部也完全无锁。

`stop` 先关闭采集，再等正在写事件的短操作完成，不等待事件所描述的任务、资源加载、GPU 或仍未结束的 span。工作线程先声明正在写，再重新检查采集代号，避免停止/重启时访问已经替换的内存。跨捕获的旧 token 不得结束新捕获的事件。

如果调试器恰好暂停在事件写入内部，需要先恢复该线程，`stop` 才能完成一致性收尾；这与暂停在被观测任务内部不同。正常退出前必须显式 stop/export，进程崩溃时恢复尚在内存中的记录不在本版范围内。

已部署的诊断入口：`D:/tools/godot/debug-trace-4.8/godot.windows.editor.x86_64.exe`。同目录含匹配符号和 `patched_build_manifest.json`。候选 17r3 的 exe SHA256 为 `9f88c2f6a09fa1e164e9f25b1b8fabea89419d45f47a56e77b6b557a9b83ece6`；补丁及前置顺序见 `tools/engine_patches/godot-4.8-beta1-debug-trace-candidate17.json`。

## GDScript 接口

```gdscript
const Timeline = preload("res://scripts/util/debug_timeline.gd")

# 主线程上预先登记标签；将整数 ID 随任务传给 worker。
var prepare_label := Timeline.label("map.model.prepare")
var ready_label := Timeline.label("map.model.ready")
var err := Timeline.start(1048576, false)
assert(err == OK)

# 在执行该工作的线程上记录。task_id 是调用者已有的稳定整数任务标识。
var span := Timeline.begin(prepare_label, task_id)
prepare_model()
Timeline.end(span)
Timeline.mark(ready_label, task_id)

# 测量结束后，在主线程停止并导出；活跃采集期间导出会返回 ERR_BUSY。
var result := Timeline.stop()
assert(result.dropped == 0)
Timeline.export_capture("D:/code/rmmo_runtime/review_artifacts/example/load.rmtrace")
```

`label/start/stop/status/export_capture` 只允许主线程；`begin/end/mark` 可以从任意线程调用。`begin/end` 必须在同一线程内配对，不能跨 `await` 把等待误称为执行工作；跨线程或异步工作用相同 task ID 的入队、开始、完成、发布 mark 连接。控制接口不会创建目录，测试必须选外部隔离输出目录。

容量由调用者指定，按 256 条事件的分片向上取整。满后保留已有记录并统计 dropped，不循环覆盖旧数据；有丢失的样本必须标明不完整。关闭时 begin 返回 0。span 跨过停止边界时可能只有开始记录，分析器会列为 incomplete，不补造结束或零耗时。

原生标签包括主循环、渲染同步与 draw、worker 执行/等待、ResourceLoader、网格材质设置、管线等待、设备 stall、Vulkan fence 和提交/呈现。它们是已插桩的调用范围，不能将范围外空白认定为空闲或声称所有引擎方法都已覆盖。

原生 worker 另记录入队时刻，以 `(context, task)` 联结入队、执行、等待。context 是线程池身份并区分普通任务/任务组，避免不同池的同号 ID 被混为一项工作。任务组允许同一项任务由多个 worker 执行，不能将多个执行片段直接判为重复。自定义 `begin(label, task, context)` 也可传入整数上下文。

`task_name(task_id, context, name)` 可从执行线程登记可读名称。原生 WorkerThreadPool 自动记录已有 description，不解析 Callable 或保留任务对象；入队前与执行前都可观察，覆盖捕获开始前已入队的任务。每线程的重复字符串复用一个名称条目，没有共享名称表锁，但**首次遇到新名称会分配线程私有表项**。名称元数据与普通标量事件的成本分开看；不要每个顶点/迭代生成一个新字符串。事件容量耗尽后，名称表也停止增长。相同上下文/任务的名称冲突会显式报告，不静默合并。ResourceLoader 现有路径 hash 只作定位提示，不是无碰撞的资源身份或去重证据。

可选 `cpu_clock=true` 记录 Windows 累计线程 CPU 时间。GetThreadTimes 分辨率较粗，短 span 的 CPU 差值可能为 0，也可能大于该 span 的墙钟；不能据此判定短帧的具体锁或 GPU 等待。普通采集可关闭，先减少观测开销。

## 离线分析

```powershell
python tools/summarize_debug_timeline.py D:/code/rmmo_runtime/review_artifacts/example/load.rmtrace --output D:/code/rmmo_runtime/review_artifacts/example/decoded
```

- `events.csv`：每条原始事件，保留统一时钟、线程、任务、span 和数值。
- `spans.csv`：每次调用的开始、结束、墙钟、可选 CPU、父 span 和完整状态。
- `rankings.csv`：按线程和标签的调用量、累计时间、最大值；嵌套调用的 inclusive 时间不可相加。
- `task_rankings.csv`：进一步按可读任务名称分组，以调用量、累计独占墙钟和峰值选择下一步复现对象；独占墙钟仍可能包含等待，不等于 CPU。
- `jobs.csv` / `waits.csv`：原生任务入队至开始的延迟、执行片段数量和调用线程的等待范围；窗口外的入队保持未知。
- `dependencies.csv` / `dependencies.json`：每段 worker 等待对应的任务名称、排队延迟、执行线程/范围和 CPU 时间。任务组每个执行片段占一行，同一 wait 的耗时在多行重复，不能再次相加。窗口内未记录执行时保留空值，不认定没有工作。
- `summary.json`：容量、丢失、未闭合/孤立事件及证据边界。

采集和导出不同时进行。文件中保留完整记录，分析过程不删除慢值，也不从未观测的空白推断线程正在空闲。正常性能成绩与插桩采样分开记录。

CSV 通过 `(context, task)` 连接已捕获的入队、执行与等待。窗口外的入队不补造。当前 Vulkan 条目是 **CPU 端 API 调用/等待范围**，不是 GPU 硬件执行计时；准确 GPU 指令耗时仍需 GPU timestamp 或对应 profiler。没有插桩的业务阶段需要用 GD 接口补边界，不能把该工具宣称为全方法自动 profiler。

## 验证与成本（2026-10-31）

完整证据目录：`D:/code/rmmo_runtime/review_artifacts/axel_post_roads_perf_20261030_01/engine_debug_trace_candidate17r3`。`validation_index.json` 保存每次启动命令和源码 SHA，`validation_summary.json` 汇总三次独立进程。采集结束后才写原始记录，分析离线运行。按用户最新要求只交付 CSV/结构化分析，不交付或继续开发查看器。

- 三次均 **88/88**：每次 12 个写线程、147,456 条普通事件零丢失；暂停一个任务时其他线程仍完成；停止不等该任务结束；跨捕获旧 token、并发停止/重启不损坏记录。
- 名称测试每次 1,536 个任务、4,608 条记录，3 个线程各复用 2 个 Unicode 名称，共 6 个私有条目。容量 256 接收 300 次名称时保留 256、明确报告丢失 44，名称表不继续增长。
- Vulkan 测试 **229 条 / 13 线程 / 0 丢失**，原生普通任务、任务组及 ShaderCompilation/PipelineCompilation 能串联；采集开关前后渲染像素相同。2 个 span 跨过停止边界，保持未闭合，不能补零。
- 离线解码器 **11/11**；CSV 验证包含跨线程等待关系、任务组多执行段、Unicode/逗号/引号/换行名称、相同任务号不同线程池、嵌套耗时及不完整记录。

独立压测每轮固定 96,000 个工作单元，打开时均产生 288,000 条事件，校验和与工作量一致。下表每格是三个独立进程；每个进程的普通模式取前后两次中位数，CPU 模式仅一次。包含 GD 封装、线程启动/等待与可选 OS CPU 查询，不是纯 C++ 写事件开销，更不是整图性能收益。

| 写线程 | 不调用工具 ms | 关闭采集但调用 GD 接口 ms | 开启标量采集 ms | 加线程 CPU 时钟 ms |
|---|---|---|---|---|
| 1 | 9.335 / 13.823 / 19.376 | 145.968 / 146.660 / 156.443 | 224.104 / 230.876 / 223.902 | 460.799 / 457.049 / 412.831 |
| 2 | 13.384 / 14.406 / 9.118 | 103.500 / 110.624 / 108.449 | 149.862 / 158.912 / 161.684 | 247.116 / 278.193 / 299.338 |
| 12 | 8.644 / 7.935 / 6.718 | 88.161 / 111.431 / 90.194 | 170.026 / 155.558 / 149.706 | 124.455 / 140.534 / 160.647 |

开启标量采集相对关闭接口调用，固定工作量增加约 44–85ms；不能省略关闭状态下 GD 调用本身的成本。只插在任务/发布批次边界，避免逐顶点、逐数组元素记录。12 线程结果不证明线性扩展；线程调度和 GD 调用也包含在内。CPU 模式在部分 12 线程样本反而更短，保留原值，不因此宣称 CPU 查询能加速。默认先不用 CPU 时钟，必要时独立采样。

复跑组件（输出目录必须不存在）：

```powershell
python tools/run_debug_timeline_checks.py --output D:/code/rmmo_runtime/review_artifacts/debug_timeline_validation
python -m unittest discover -s tools -p test_summarize_debug_timeline.py
```

runner 默认三次 CPU 合同/压测加一次独立桌面 Vulkan；`--no-gpu` 仅作 CPU 检查，不能当完整集成验收。普通默认引擎不提供此接口，需使用上面的诊断入口。该构建继承 candidate11–16 的源代码，既有可选优化开关继续关闭；它的成绩不能直接替代默认 candidate10 的正常游戏成绩。


基础能力完成后，下一步只在冻结的 axel_town 测试副本补业务边界：需求/任务创建→网格/纹理准备→完成结果→主线程发布→回收。使用稳定任务 ID 连通上下游，做三次全局捕获；按排队、执行、等待和重复次数倒序选择独立复现对象。尚未用这些组件数据解释或关闭 100 秒加载问题。

### 渲染阶段细分 candidate18

三次真实地图和三次保留shader/pipeline缓存的重启已完成，见[整图日志](axel_post_roads_performance_20261031.md)。缓存命中后仍以`render.draw`为大头，因此新增独立候选18：在17r3上增加40个固定原生标签，细分begin/end frame、场景与脏资源更新、材质/骨架/实例数据、视口、剔除、阴影、绘制列表和主循环消息队列。没有逐顶点/逐draw写事件，也没有改变画质或调度。

新标签仍用原CSV格式。`render.viewport`/`viewport_3d`的task是视口RID；`render.cull_range`的task/context是区间起止；`render.draw_list`是候选列表元素数/pass mode，可能被内部过滤或实例化合并，不能直接当实际draw call；`render.rd_scene`是实例/灯光数量；`render.shadow_pass`是候选实例数量/阴影pass。这些字段是工作量描述，不是WorkerThreadPool任务ID。记录的CPU调用范围不等于GPU硬件执行时间。

补丁及源码SHA见`tools/engine_patches/godot-4.8-beta1-render-trace-candidate18.json`。候选独立入口位于外部证据根的`engine_render_trace_candidate18/engine/`，未替换任何默认入口。CPU合同88/88、固定工作量组件和真实Vulkan像素一致性通过；GPU854条、13线程、零丢失/孤立结束/交叉范围，3个停止边界未闭合span保留。旧标签ID不变，解码器无需升级。三次真实地图渲染细分及一次41份栈的GDB诊断已完成：绘制列表和帧末处理反复居前，见整图日志及`render_trace18_three_samples.json`。这仍是定位证据，不能以此宣称总加载或low优化通过。
