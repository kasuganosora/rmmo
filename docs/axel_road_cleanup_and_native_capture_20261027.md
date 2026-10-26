# 道路重复工作清理与普通 worker 异常取证（2026-10-27）

接续 `axel_road_paint_preparation_20261027.md`。目标仍 active，不把这一轮的
局部收益或未重现崩溃当作全部完成。正式地图、模型、纹理、引擎二进制均未修改。

## 范围与证据目录

- Worktree：`C:/Users/luna/.codex/worktrees/map-load-render-review/rmmo`。
- 起点提交：`639fe817`，分支 `codex/latest-map-runtime-review`。
- 以下 N 指
  `D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/native_fault_capture_20261027/`。
- 引擎继续使用同级 `collision_debug_20261026/engine09/godot.windows.editor.x86_64.exe`，
  SHA256 `40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`。
  符号 SHA256 `3039c3ba7fbb71f965ec42cb9100a483a439e95b6cfda3ed194cfae54989db76`。
  本轮没有重编译、安装或替换引擎。

## 确认的异常记录缺口，不等于原崩溃根因

对同一个 engine09，在单独 headless 子进程中调用一个原生空指针读，分别
由主线程和真正的 Godot Thread 执行。fixture02 原始日志、退出码、模块表
全部保留。错误注入只对这些明确的受控进程开放。

| 受控场景 | VEH | 退出 | Godot 自带 backtrace | 新采集展开帧 |
| --- | --- | --- | --- | ---: |
| noop | 开 | 0 | 无异常 | 0 |
| 主线程 read-null | 关 | 0xC0000005 | 有 | 0 |
| worker read-null | 关 | 0xC0000005 | 无 | 0 |
| 主线程 read-null | 开 | 0xC0000005 | 有 | 20 |
| worker read-null | 开 | 0xC0000005 | 无 | 13 |
| worker execute-null | 开 | 0xC0000005 | 无 | 14 |

`decode05_results.json` 进一步检查真实 OS 线程身份，离线 GDB 解析到对应的
`rmmo_test_read_null` / `rmmo_test_execute_null`；worker 链包含
`Thread::callback`。execute-null 的 PC=0、access=8，但返回地址仍能展开。
这证明了取证工具能抓这种故障，**没有证明 map07_B1 是同一原因或来自 worker**。

实现位于 `tools/native_fault_capture/`，通过外部临时 GDExtension 安装 Windows
vectored exception handler。正常帧不采样、不挂起线程、不运行调试器、不改
优先级/QoS；仅在首个 AV / illegal instruction 写出寄存器、原始栈、展开地址，
然后继续原异常处理。它是 first-chance 证据，若异常被程序自己恢复，后续异常
可能不会再次记录；模块表也不覆盖加载扩展后的新 DLL。不能用它代替完整 dump。

`tools/run_axel_texture_phase.py --fault-capture-extension <外部扩展路径>` 才
启用。命令和 DLL SHA 写入 launch，结果明确标记 diagnostic；wrapper 在加载
前关闭故障注入并检查测试类没有暴露。原始文件 CREATE_NEW，保留失败样本。
普通游戏不加载这个扩展。具体编译、重放与解码命令见
[`tools/native_fault_capture/README.md`](../tools/native_fault_capture/README.md)。

保留工具自身失败：build01 编译错误已修正；addr2line 解析 2.2GB 符号超时
120s，随后使用 GDB 离线读取，probe04 约 10.8s。它们不是地图崩溃/性能样本。
build13 验证入库 builder；fixture13 验证入库 noop 入口正常装载、卸载。

## 去掉无用途的顺序索引

`SurfaceMaterials.geometry_arrays` 在 `first_surface_only` 模式下，以前会给
未绘制的无索引槽先建立完整顺序索引，再跳过拓扑分组。现在直接用顶点数完成
原有范围检查，跳过后才为真正参与分组的槽生成索引，并一次 resize。
全量编辑器几何仍生成相同的索引、face ID、签名；不改变错误/拒绝语义。

`test_surface_topology_elision.gd` 94 项通过：索引/无索引输入、部分/全量
结果字节、共享输入不变、空槽、超限、自定义通道、骨骼通道与大槽压力。
每次压力调用含 4 个未绘制槽、合计 600,000 个无用途索引。

- `topology07_before`：16 次/轮，五轮 174.269–179.750ms。
- `topology08_after`：16 次/轮，五轮 0.493–0.558ms。
- 这些是同输入独立测试，不是整图秒级收益；宿主可能有 Blender，保留原始
  日志和宿主记录，不以此建立整图 p95 结论。

## 原始道路与 paint 共享一次边界扫描

原流程先在 paint 里扫描输出顶点边界，随后 Chunk 又扫描原始道路边界。
现在 `for_road` 只对完整、无索引三角流授予共享边界：每个位置都归属某个
分组，UV/切线准备不改变位置。首先计算原始边界，paint 与原始 CPU mesh
共同使用；已有 native 缓存边界时两次扫描都省去。

索引输入或尾部不完整的三角流继续走普通路径，不能从未使用的源顶点推断
输出范围。普通 `prepare` 仍扫描实际输出，包含未引用远端顶点的反例验证。
预算、worker 数、材质身份、surface 次序、碎片字节、取消与释放合同不变。

- `bounds10_before`：94 检查通过，未共享，94,284 顶点道路每次扫两遍。
- `bounds11_after`：102 检查通过，共享；完整/部分 paint、法线切线、缓存
  边界、索引反例和残缺三角流均覆盖。
- `bounds13_paired`：166 检查通过。同进程 ABBA、每组 16 次，旧双扫描核
  240.440 / 240.071ms，新共享核 131.161 / 130.905ms。均值减少约 45.46%。
  两臂都用本轮同一拓扑核，排除道路生成/作者数据建立；不是整图收益。
- `paint11_regression`：151 项通过，新增实际 Chunk 只扫描一次、原始与
  paint 使用同一范围的检查。`bounds11_handoff` 4 项通过；道路材质验证通过。

工作量指标新增 `road_paint_bounds_scans` 与 `reused_paint_source_bounds`。
`scanned_surface_bounds` 只计 Chunk 最后的残余扫描；必须与 paint 的扫描数
一同看，不能把移到 paint 内的一次必要扫描说成消失了。

## 回归中的既存失败

`test_road_default_paint` 415 项中 13 个 full-prepare 冻结链字节对比失败。
先把本轮生成的报告/二进制逐字节归档 N/road12_current_outputs，再临时将
四个本轮生产脚本还原为 HEAD 内容，重跑同一个测试。13 个标签完全相同，
所有失败 actual / expected / input 二进制 SHA 也完全相同。
`road12_baseline_comparison.json` 记录 HEAD SHA、命令和恢复核对。

随后原样恢复本轮四个脚本；测试产生的仓内报告恢复到运行前字节，新失败
产物全部保存在外部证据目录，没有改写冻结期望来放行。本轮直接 paint、
全量/部分 geometry 及错误输入比较都通过。13 个既存失败仍是未归因项，
不能称整套旧测试通过，也不能将其归为本轮新回归。

## 地图复测口径

继续地图计时开始 → 当前需求完整就绪（三帧），保留 native/index/纹理磁盘
缓存，强制派生几何、bounds、模型 metadata miss，OS cache 不操作。
纹理阶段仍为地图/预制件材质，导入模型白模，不能称全纹理游戏验收。
所有 GPU 运行沿用私有桌面和实际 PID / 创建时间观察器，不抢焦点。

`map06` 因连续有其他相关进程，静默窗口未满足，没有启动样本。
随后两条 map09 明确作为有异常采集的诊断，允许并记录宿主干扰：

| 样本 | entry | full-ready | 结果 |
| --- | ---: | ---: | --- |
| B1 道路异步开 | 5.150737s | 10.563968s | 全遍历功能通过，未捕获异常 |
| A1 道路异步关 | 4.680717s | 12.207370s | 全遍历功能通过，未捕获异常 |

两条的源码/地图 SHA 不变、priority class 32、采集器成功启用。不能用这两条
建立普通性能成绩，不能据“未捕获”解除上轮的异常边界。

普通 map14 原计划 BAAB，B1 全遍历完成；A1 在 90s 静默等待内一直有 Blender，
未启动，A2/B2 也未启动。因此只保留一条普通新样本，**没有完成新 ABBA**，
不得将其与历史两条 B 的差值当作这一轮稳定收益或 p95。

`map14_B1` entry **3.830217s**、完整就绪 **9.293251s**，功能/源/地图检查
全部通过，初始加载期间 observer 未发现其他相关进程。初始工作量仍为
231 builds、228 worker surfaces、2724 packed source visits、3923 prepares、
229 groups、2564 sources、2352429 source vertices、2299528 render vertices、
361 render surfaces，live joins 0。building hit/reuse 为 52+23=75，原始 road
生成 311、cache hit 0；没有靠重复生成或减少最终内容换时间。

- 311 份 paint、65,217,360 输出 bytes，与先前相同。
- `reused_paint_source_bounds=311`，`road_paint_bounds_scans=311`；
  `reference_scanned_surface_bounds=0`，末尾残余扫描总跨度仅 561us。
  即每条必要扫描保留一遍，确实省去第二遍，并非把新位置的扫描漏记。
- road paint（含一次必要边界扫描）后台累计 817.571ms，不能当作主线程
  或关键路径时间。covered publication 2.472097s，covered service 3.212300s，
  两者包含关系不能相加。
- 全遍历 paint 消费 637 / fallback 0，主线程绑定累计 449.035ms；637 包含
  合法卸载后重建，不是初始重复加载。

| 阶段 | 最大帧 | >50ms 帧 | 1% low |
| --- | ---: | ---: | ---: |
| 静止 | 51.927ms | 1 | 44.612 FPS |
| 卸载 | 31.544ms | 0 | 96.475 FPS |
| 返回 | 29.936ms | 0 | 47.780 FPS |
| 重载 | 50.808ms | 1 | 26.096 FPS |

静止/卸载/重载部分时间与其他 Blender 重叠，返回阶段未观察到其他相关进程。
slow 帧全部保留，不因宿主干扰排除。low 使用最慢 ceil(N×1%) 帧的平均耗时
倒数；此表不能证明 low 稳定改善。`summary15.json` 保留 map09 和 map14 的
逐阶段统计、工作量、宿主 PID+birth 与初始加载重叠；全测量结束后才解析。

## 下一轮的具体入口

道路纯 CPU 去重已经有独立与真实链路证据，继续保留；异步 paint 候选仍默认
false，普通游戏只立即获得共用拓扑核的索引精简。新边界复用随候选一起门控。
没有以这两条无异常诊断和一条普通样本宣告 map07_B1 已修复。

1. 当前静止 51.927ms 帧前后的原始记录已缩小范围：first draw 71.657ms，
   audit 所在帧 63.430ms；随后前两条 steady 帧分别 51.927 / 41.929ms。
   audit 自身 52.524ms，已经保留在前一阶段，不可直接说 steady 尖峰都是 audit。
   对应 frame-split 的 previous_draw_wall 为 **48.090 / 40.467ms**，geometry
   tick 为 **208 / 412us**，publication 均为 0。它们是 draw 信号跨度而非
   OS CPU 时间，仍需主/渲染线程栈与实际等待证据。不要再用 TIME_PROCESS
   的缓存峰值或空 Deferred 计数将它归为 OS/GPU 空闲；也不要删这两帧。
2. 主线程 covered publication 仍约 2.47s。接着既有 profiler 的真实
   `surface_set_material` 成本和实际网格/材质组合分析，不恢复已失败的隐藏
   mesh 预热，不通过扩大预算/队列假装去重。
3. `TerrainRegions.mask` 的剩余逐像素 point-in-polygon 调用可独立复现。
   当前 engine 的 Geometry2D 每次点判定重新扫描 polygon min/max 再做边
   相交；先测实际贡献和像素字节一致，再考虑按 polygon/行准备，不能因调用
   数高直接更换边界语义。map14 初始 Chunk terrain_mask_generations=0，
   应分别定位 entry 和流式阶段，不把历史 profiler 的累计时间套到本样本。
4. native 异常继续用本轮已验证的采集器；需要实际故障上下文才能归因修复。
   13 个冻结链既存字节差异单列，不改期望掩盖，也不扩成与当前渲染无关的
   编辑器重做。下一组普通对照择无相关进程窗口，不停止用户的其他工作。

目标保持 active，仍有可定位的主线程/渲染等待与首帧问题，不宣称已到下限。
