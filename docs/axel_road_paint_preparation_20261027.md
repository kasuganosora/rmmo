# 道路 paint 准备移出主线程（2026-10-27）

## 问题与边界

接续 `axel_publication_profile_20261026.md`：官方 profiler 将主线程道路
paint 的面分组、UV、切线和边界扫描定位为发布链的一部分。本轮先独立复现，
再接入已有 ChunkReferencePreparation worker。不新增 worker，不增加统一
字节预算，不修改地图、纹理、模型产物或引擎。

工作区 `codex/latest-map-runtime-review`，基线 `c3d32dc0`。
证据根 P：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/paint_preparation_20261027/`。
使用此前 engine09：SHA256
`40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`。

本轮仍是地图 / prefab 纹理开启，导入模型材质保持白模。计时边界保持地图
加载开始到当前需求连续三帧完整就绪，包含 shared pixel 消费者排空；不是
进程启动，也不是所有导入模型纹理的完整游戏验收。几何、边界、元数据派生
缓存强制 miss；native、目录和纹理磁盘缓存保留，OS 缓存未清。不能称为
物理冷盘。GPU 运行均经 `run_godot_background.py` 的不激活独立桌面。

## 实现和所有权

- `surface_materials.gd` 提取共享的纯数组拓扑算法 `geometry_arrays`；编辑器
  原来的节点检查、paint 语义和通用路径保留。
- `surface_paint_preparation.gd` 在后台执行面分组、UV / 切线、碎片压缩和
  输出边界计算。只读输入数组和声明，产生私有碎片，没有 Node、纹理文件、
  RID 或共享缓存操作。仅接无索引 native road；terrain grade 等依赖主线程
  几何变形的记录保留原路径。
- 不按声明提前合并材质。主线程仍使用真实 canonical material 对象和通道
  layout 合并，保持原 surface 顺序与 draw 数量；消费预计算边界，不再扫描
  输出顶点。输入数组 owner / 声明已变或法线启用状态不符时走通用路径。
- Deferred admission 对道路额外预留一个原有保守 road 工作区，覆盖拓扑
  临时结构、索引和 retained fragments。没有改全局上限；空间不足的独立
  调用不启动 paint 准备。原始无索引顶点只能属于一个碎片，输出通道 / 索引
  大小受该预留约束；它是调度估计，不能当作实际 RSS。
- 结果沿现有 job / document 交接。替换代际、取消、job discard 和 native
  retirement 同步释放 paint 借用；较大的私有包跟随既有延迟回收，不在登记
  阶段直接销毁。已发布的 CPU mesh 自己持有数组。
- 当前只接流式区块道路；初始 MapLoader 的 entry surface 阶段尚未接入。
  后续要先证明其工作区预算，不能无预留扩展。原生 `surface_set_material`
  首次提交也没有在本轮消除。

## 独立验证与失败记录

`test_surface_paint_preparation.gd` 比较新旧完整输出字节，包括 surface 顺序、
索引、位置、法线、UV、切线；验证真实材质实例相同、bounds 相同、源输入
未变。覆盖 UV / planar / meters、部分 face、不同 / 共享材质、normal，
以及 2048 个 kerb 的较大输入；验证取消、变更声明、替换数组 owner。通过
真实目录和 chunk worker 交接到 WorldDocument，检查 budget lease 释放与
已发布数组存活。

- `fixture01`：normal fixture 路径错误且文件不存在，113 项 / 1 失败。
  已修正为项目外真实 PNG；失败日志保留。
- `fixture02`：130 项通过，但 authoring fixture 预付了旧路径的 topology
  cache；这条的时间不能作为公平对比。
- `regression03`：显式清掉 authoring cache 后 130 项通过；native road、
  complete surface reuse、surface UV batch 通过。误用不存在的
  `test_native_residency.gd` 导致一次 script-not-found，属于夹具调用错误，
  保留日志，不称作通过或生产回归。
- `regression04`：加入实际生产交接后 137 项通过，procedural bounds 和
  native retirement contract 通过。native residency GPU 有 9 项失败。
- `native_disabled05` 关闭本次功能，同样 9 项失败。该 fixture 没有道路；
  调查发现它 `set_process(false)` 后只调用 `poll`，没有执行后来拆出的
  `_drain_cleanup`，两项待清理一直不推进，资源持有和返回请求因此滞留。
- 修正测试的手动时钟驱动，使其执行与生产 `_process` 相同的先 cleanup
  后 observation 次序；不缩短 grace、不弱化 WeakRef / 往返断言。
  `native_fixed06` 和 `native_disabled_fixed06` 均 **32 项 / 0 失败**，包含
  mesh、material、texture 最终释放和两次往返恢复。这是夹具修复，不冒称
  修复了游戏释放 bug。
- `fixture05` 145 项通过，并增加相同纯算法在主线程 / worker 的对照。
- `fixture13_parallel` **147 项通过**，增加两个 worker 同时读取同一份输入，
  输出碎片仍逐字节相同、输入未变。

`fixture05` 单次调用示例（毫秒，不是稳定统计）：

| 输入 | 旧主线程 | 同纯算法主线程 | worker | 新主线程绑定 |
| --- | ---: | ---: | ---: | ---: |
| UV / 128 kerb / 整面 | 1.408 | 0.875 | 3.009 | 0.628 |
| UV / 128 kerb / 部分面共享材质 | 28.632 | 25.458 | 49.099 | 3.523 |
| normal / 部分面 | 32.486 | 25.803 | 50.781 | 1.559 |
| UV / 2048 kerb / 整面 | 10.550 | 9.828 | 30.297 | 0.546 |

worker 的跨度明显更长，不能把主线程下降量直接当作总加载缩短量。相同纯
算法对照说明差别不只是新拆分多了一套算法；本条未取得对应引擎栈，尚不能
归因为某个锁或 Godot bug。测试时有其他 Blender 工作，单次数据不作稳定
吞吐结论。先看整图关键路径，再决定是否需要专项跟踪线程执行成本。

## 整图对照

使用 `P/run_observed05.py` / `P/matrix07.py`。每次启动前等连续 5 秒没有其他
Godot / Blender / GDB / 编译进程；之后按 PID + 创建时间以 1Hz 记录外部
负载。门禁不等于运行期间无干扰，不结束其他任务，不改 priority / QoS。

首次样本 `map07_first`：完整就绪 11.331942s，功能、源码和地图 SHA 检查
通过；保留首次派生状态重建样本。后续普通 ABBA 全遍历单独记录，不注入
header 延迟，也不开官方 profiler / GDB。A 为关闭 prepared road paint，
B 为开启；其余参数相同。1% low 使用最慢 ceil(N×1%) 帧的平均耗时倒数。

矩阵在 `map07_B1` **0xC0000005** 后自动停止，B2 / A2 没有启动，不能
写成完整 ABBA，也不能据此声称总加载或 low 已改善。

| 普通样本 | entry | 完整就绪 | covered publication 累计 | 状态 |
| --- | ---: | ---: | ---: | --- |
| map07_first / B | 5.902141s | 11.331942s | 2.446359s | 原点检查通过 |
| map07_A1 / A | 3.895308s | 10.267217s | 3.295615s | 全遍历通过 |
| map07_B1 / B | 未完成 | 未完成 | 未取得 | 18.343s 进程跨度后异常退出 |

前两条 settled 工作量相同：231 builds、228 worker surfaces、2724 packed
source visits、2564 sources、361 render surfaces、2299528 render vertices、
2352429 source vertices，live worker joins 为 0；后台生成原始 road 均为
311 次、road cache hits 0。B 另外准备 311 份 paint，后台累计跨度 866.034ms，
输出 65,217,360 bytes，311 次消费 / 0 fallback，主线程绑定累计 165.242ms。
没有多生成同一道路原始网格。增加的 paint 工作区沿原 lease 计费，B peak
reservation 7,887,488,968 bytes，A 为 6,509,721,888 bytes；动态 admission
limit 分别 8,225,761,152 / 8,494,187,520 bytes。它们不是实际 RSS，且可用
内存决定的上限并非固定值，不把首次样本当成受控稳定性能结论。

两条完整样本的 host observer 都没发现其他相关进程。B 原点静止最大帧
53.922ms / 1 帧 >50ms / low 40.945 FPS；A 静止 54.982ms / 1 / 40.479。
A 卸载 32.065ms / 0 / 107.574，返回 41.582ms / 0 / 45.938，重载
42.319ms / 0 / 28.153。缺少 B 全遍历，不能比较卸载 / 返回 / reload 收益。
完整指标在 `partial07_metrics.json`，覆盖加载帧和首帧 draw，未删慢帧。

## 普通样本异常与 GDB 边界

`map07_B1` 的源和地图 SHA 未变，普通 priority class 32，没有 QoS / 优先级
修改。日志停在初始恢复，未输出 AXEL_MESH_READY。Windows Application
Error 86361 对应同一 PID 3520 / 0xdc0；WER IntegratorReportIdentifier
`c4b37f9f-6ee9-4296-a552-8feade3cc3ed` 对应同一程序与进程创建时间。事件为
`c0000005`，模块 unknown / offset 0；WER 为 BEX64 / StackHash，异常数据
8。归档仅有 Report.wer，没有可用 dump；不能从这个 bucket 指认具体函数。
原始事件 XML / WER 已保存在 P。这不是以前外部高优先级夹具的同一结论，
也不能凭错误码把两次崩溃认定为同一个 bug。

- `gdb08_B` 由 GDB 默认方式启动。诊断运行严重变慢，158s 时需求 settle
  断言失败，之后退出清理也很慢。约 351s 后明确执行 DebugBreakProcess
  采样，主线程在 RtlFreeHeap → `_free_base` → CowData<Variant>::_unref；
  捕获的是**主动 SIGTRAP**，不是原来的访问异常。`interrupt.json` 记录
  PID + 创建时间。GDB exit 0 不代表游戏测试通过；本条不算完整遍历验收。
- `gdb09_B` 设置 `_NO_DEBUG_HEAP=1`，仅复测崩溃前涉及的原点加载，45s
  整体诊断正常退出，游戏 failures=0。该环境变量只用于诊断子进程，未改
  全局系统或生产环境；不能拿这条的时间作为普通性能成绩。
- 同条件 `gdb10_A1/B1/B2/A2` 均正常退出，没有再次捕获访问异常。这四条
  是诊断对照，不能证明原普通崩溃已修复。
- 改用正常启动后附加 GDB。`attach11_B1` 因 GDB 命令中的 Windows 路径
  转义错误未成功附加，游戏自行完成。该失败夹具保留，不称为带调试验证。
  修正为正斜线后 `attach12_B1/A1/B2/A2` 四条游戏和 GDB 均 exit 0，未触发
  异常；附加前再次核对 PID 创建 FILETIME，只操纵本轮拥有的进程。

上述共 **9 条带 GDB 的原点加载**未复现访问异常，不等于证明原普通异常
已经修复。引擎源码的 Windows 构建在 MinGW 下选择
`crash_handler_windows_signal.cpp`，MSVC 才选择 SEH 版本；下一轮先验证
普通子线程故障能否留下有效记录，再考虑只在异常时工作的诊断采集。尚未
证明本次错误来自该差异，未修改引擎，也没有指认外部 DLL 为原因。

## 补充普通全遍历 ABBA（map13）

9 条 GDB 运行未重现后，继续普通测量以评估候选，异常仍保留为稳定性边界。
`matrix13.py` 四条都通过功能、作者源、地图和生产源码 SHA 检查，未发生
新异常；没有 profiler / GDB / 人工 header 延迟，使用原来的统一预算策略。

| 样本 | entry | 完整就绪 | covered 主线程 publication | covered service 总跨度 |
| --- | ---: | ---: | ---: | ---: |
| A1 关闭候选 | 3.825977s | 10.193487s | 3.348423s | 4.152113s |
| B1 开启候选 | 3.928816s | 9.523801s | 2.548398s | 3.321899s |
| B2 开启候选 | 3.931571s | 9.511119s | 2.535939s | 3.310318s |
| A2 关闭候选 | 3.859280s | 10.128957s | 3.197028s | 3.953901s |

初始加载期间四条均未观察到其他相关进程。完整就绪均值 **10.161222s →
9.517460s**，减少 **0.643762s / 6.34%**；只是这组 ABBA 均值，不是 p95
或物理冷盘结论。service 包含 publication，不能两列相加。

四条 settled builds / packed / 最终几何与 map07 完整样本相同。building
cache 命中 / worker 复用分配随调度改变，但合计每条都是 75。原始 road
都生成 311 次、cache hits 0；B 初始 paint 都准备 311 份 / 65,217,360
bytes，后台累计跨度 883.415 / 867.848ms。全遍历含合法卸载后重建，B 均
消费 **637 份 / 0 fallback**，主线程绑定累计 430.872 / 433.259ms。
累计后台跨度不是主线程 CPU 时间，637 也不能误称初始重复加载。

| 阶段 | A1 最大帧 / >50ms / low | B1 最大帧 / >50ms / low | B2 最大帧 / >50ms / low | A2 最大帧 / >50ms / low |
| --- | --- | --- | --- | --- |
| 静止 | 53.555 / 1 / 41.875 | 51.286 / 1 / 41.748 | 66.916 / 1 / 38.986 | 65.122 / 1 / 41.750 |
| 卸载 | 33.461 / 0 / 106.003 | 32.183 / 0 / 107.930 | 37.879 / 0 / 98.474 | 38.734 / 0 / 118.723 |
| 返回 | 68.760 / 4 / 35.767 | 32.792 / 0 / 46.493 | 40.204 / 0 / 39.709 | 32.221 / 0 / 48.352 |
| 重载 | 38.647 / 0 / 33.747 | 41.716 / 0 / 27.538 | 43.949 / 0 / 30.967 | 47.603 / 0 / 27.019 |

帧时间单位 ms，low 单位 FPS。A1 卸载 / 返回 / 重载与两个 Blender 重叠，
B2 离开 / 卸载 / 返回 / 重载与一个 Blender 重叠，A2 重载与 Blender 重叠。
B1 全程未观察到其他相关进程。静止四条都没有相关进程重叠，却各有一条
>50ms 帧；B1 最大帧 process_ms 7.557、Deferred accept/join/sync 为 0，
这些监控值不足以证明是 OS / GPU 空闲，仍需逐帧栈 / CPU 证据。不能据
上述表格宣称 low 已稳定改善，也不删除被干扰的样本。

`summary13.json` / `summarize13.py` 保留各阶段帧数、低帧算法、PID + birth
重叠记录、ready 后 Deferred 快照和 settled 工作量。原始逐帧 JSON 全部
保留。普通矩阵结束后才运行汇总，避免解析大 JSON 干扰测量。

## 当前交付状态与下一步

已独立提交并推送手动 residency 测试修复 `7d93037d`。道路异步 paint 的
性能候选和测试保留，但 `SurfacePaintPreparation.enabled` 默认 **false**；
压测入口明确设置 true / false，普通游戏没有自动启用该候选。
`fixture14_gate` **149 项通过**，包含默认关闭和显式启用检查。矩阵记录
的是门控修改前同一算法；门控只改变默认选择，不改已测准备 / 发布逻辑。

目标保持 active，未认定“没有优化空间”。下一轮顺序：

1. 继续定位普通访问异常，补足线程 / 原生异常证据，不能因为 9 条 GDB 和
   后续 ABBA 通过就说已修复。稳定性边界明确后再解除候选默认门控。
2. 精简已确认的重复工作：first-surface-only 时，其他 surface 仍先生成
   整个顺序索引再跳过拓扑分组；计数校验不需要创建这些索引。保持尺寸 /
   通道拒绝语义，验证完整结果一致，再计数和压测。
3. 核对原始 road bounds 与 paint 输出 bounds 的重复扫描，只有证明无索引
   原始顶点全部保留时才共享；不能对任意 indexed / partial mesh 泛化。
4. 接入初始 entry surface 时先证明内存 admission；再处理剩余原生材质
   首次提交和后台 terrain mask。不增加 worker / 发布预算替代去重，也
   不将增加的后台工作说成免费。
