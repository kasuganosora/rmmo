# 给下一位接手者：axel 白模加载 10 秒与长帧复盘

这份文档不是又一轮优化日志，而是给已经在一周多的微优化里打转的 agent 的接手说明。
先给结论，再给“为什么之前打不穿”和“哪些做法可以复用”。

## 0. 一句话结论

2026-10-25复核：分组index preparation版本的warm 10次p95 **6.918s**、cold-index
10次p95 **7.918s**；仍按pipeline开始到当前需求完整就绪，不等同撤罩/首次可见。
这是接手前N10基线。本轮另保留一次cold 12.304s慢样本，后续诊断8.025s未复现；
慢段集中在hydrate与cold hints，原因未闭合，不能把旧N10回填为修改后的稳定成绩。
剩余问题和本轮修复见 `docs/axel_white_remaining_20261025.md`。历史32ms+批量removal
阶段warm/cold p95为9.937/8.871s，不能与后来的分组prep混为一个版本。

历史阶段的关键增量是从 `_remove_published_demand`
的逐 unit 移除改成 `_publish_ready` 末尾按帧批量；1514 个需求一次移除，
per-unit remove 从约 0.097s 降到约 0.002s。N=10 的 nearest-rank p95 就是最大值；
早期旧样本的 7.49/8.53/7.94 是错误地取第 9 个样本，不能引用。卸载/返回/重载的
旧 36.9/46.2/22.5 ms 是 **3D 关闭**下的数字；
3D 恢复后首次往返仍有 62.3/85.2/98.6 ms，后两次 0 帧 >50，但当前代码最新样本
又有卸载 51.3 ms（1 帧 >50），不能宣告稳定。关键不是又找到一个重复函数，而是把
**初始加载放进不透明 loading cover**，允许 cover 下用 32 ms publication 预算，
再对单个慢 source 做 10 ms 让帧。继续加 worker、加预算、抠 1–2 ms 工作，收益已经
很小。

## 1. 之前一周多为什么打不穿

### 1.1 一直在优化“工作量”，没有先画关键路径

记录里大量 ABBA 都能证明局部工作量下降，但整图 9.6→9.57 s，甚至 9.64→9.81 s
变慢。原因是 CPU 不是瓶颈：入口后平均存活 Deferred worker 只有约 0.9，进程只
相当于 1.2–1.5 核。真正的墙钟由**串行 publication、每帧预算、worker 结果到达、
present/OS 调度**决定。重复工作减少 ≠ 关键路径缩短。

### 1.2 目标边界漂移

“10 秒”同时被用于入口、full-ready、整进程、完整游戏；测试器还曾经多做生产不做
的 GPU 上传。跨轮数字不在同一合同里，不能直接比较。先冻结一个合同：
**pipeline begin → 当前需求 demand/job/stream/batch 连续三帧为空**。别用
`AXEL_MESH_READY` 代替 full-ready。

### 1.3 把“长帧”当成一类问题

至少分四类：

- 加载期高 CPU：publication、spec、collision；
- 加载期低 CPU：present/GPU/驱动/OS 调度；
- 卸载释放：单个大 Resource/Shape 析构；
- 测试宿主：navigation/residency 建立、帧监控。

混在一起会得出“再加预算/再加 worker”的错误结论。先按阶段、按 tick、按
stream/batch/deferred 拆开。

### 1.4 环境噪声被当成代码信号

private desktop 没有前台窗口优先级，Windows 可能对子进程做 EcoQoS/调度节流。
同一源码 warm 10 次可以 7.5 s 稳定，cold 10 次却出现 11–13 s；高优先级/关闭进程
节流后又会变。后来确认一部分慢样本是后台调度，不是 source 工作。基准必须记录
进程优先级/节流状态，最好固定环境；不要把单次慢样本删掉，也不要把一次快样本
当稳定结论。

### 1.5 多目标验收导致复杂度累积

“时间、帧、工作量任一有收益就保留”本身是有效的多维验收，不能自行改成只认
加载时间。真正要避免的是：**没有主指标、没有护栏、没有回滚条件**。保留多维收益
的同时，先冻结一个主验收指标（这里仍是 full-ready p95），FPS/帧峰值/工作量作为
并列收益记录；不改善任何一维的复杂度才不进主线。

## 2. 转折点：cover 是产品语义，不是作弊

白模初始加载时，玩家不需要看见逐渐长出来的 3D 场景。于是：

1. loader 启动前创建不透明 2D `InitialLoadingCover`；
2. `viewport.disable_3d=true`；
3. `DeferredAssetLoader` 在 cover 不透明且 3D 关闭期间使用 **32 ms** 主线程
   publication 预算（普通交互 2 ms、普通白模 6 ms、同地图 transfer 固定 16 ms）；
4. cover 保持到 demand/job/stream/batch 连续稳定，再恢复 3D、输入并 retire；
5. `World3D` 的初始白模入口走同一路径；`is_world_ready` 在 cover 结束前为 false。

这一步把 tail 中位从约 5.5 s 降到约 4.0 s，full-ready p95 从 9.5–10.2 s 降到
7.5–8.5 s。它不是“少加载”：几何、碰撞、合批、GPU surface 全部仍在 cover 下
完成，结束前有白模 GPU 审计。

第二个小杠杆：`WorldStream` 对单个 `_apply` 超过 **10 ms** 的 source 立即让出
当前帧，不再把 batch/collision 收尾叠上去；下一帧从同一 cursor 继续。工作不丢，
只拆帧。

## 3. 可复用的方法

### 3.1 先 freeze，再 A/B

- 同一引擎 exe SHA、地图 SHA、源码 SHA、cache 开关、worker/job/预算、观察器开关；
- warm 与 cold-index 分开；cold-index 不等于物理冷盘；
- 每配置至少 10 次独立进程；报 median/p95/max，p95 用 nearest-rank；
- 保留失败、慢样本、无效隔离；不要用单次 9.3 s 宣布达标。

### 3.2 用“关键路径”而不是“热点列表”选下一刀

至少记录：

- `pipeline begin`、loader、entry、full-ready 四个锚点；
- 每个阶段的主线程 CPU/进程 CPU/墙钟；
- Deferred `publication_us`、`ready_scan_us`、acceptance、dispatch；
- Stream tick 的 prioritize/ensure/stream 子段；
- batch pending/workers/prepare/commit；
- 帧 >33/50/100 ms 的阶段、tick、stream jobs/cursor、batch pending。

`origin_spike_01` 就是一个例子：56.8 ms 帧 tick 0.2 ms、stream 0/0；52.5 ms 帧
已经 full-ready 且 tick 0.1 ms；真正 stream 工作帧是 48.9/48.0 ms。<50 的工作帧
和 >50 的空闲/启动帧必须分开，否则会继续优化错误对象。

### 3.3 先证明“是不是生产路径”

- 首帧约 380–443 ms 是 Forward+ 首次 3D shader/feature 预热：
  `--late-render-context` 把 loading 首帧降到 52.3 ms，但 origin 立刻出现
  436.7 ms；同一笔一次性初始化只是搬家。
- `white_traversal_setup` 约 140–165 ms 是探针新建 Navigation/Asset/Native
  residency；生产 World3D 已在入口流程内建好。
- 旧 3D 关闭样本的 0 帧 >50 ms 不是产品路径证据。3D 恢复后首次往返有
  62.3/85.2/98.6 ms，后两次 0 帧 >50；必须保留并继续采样，不能拿 3D 关闭数据
  混过去。

### 3.4 不要用“加资源”掩盖架构问题

试过：

- batch worker 3→6：tail 中位 5.49→5.47 s，噪声内；
- settled budget 6→8 ms：tail 反而慢约 96 ms；
- progressive batch：更差；
- 32 ms covered budget：在 cover 语义下才成立；warm p95 7.564 s，cold 普通优先级
  仍有 10.499 s 慢样本，高优先级/关闭节流 8.052 s。它不是无条件加速。

结论：**先问“这帧是否必须现在做、是否可见”，再问“用多少线程/预算”。**

## 4. 复现

环境：

- 引擎：`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/release169_build/baseline/godot.windows.editor.x86_64.exe`
  （c593 baseline，正常性能对照）；带符号引擎：`D:/tools/godot/godot.windows.editor.x86_64.exe`；
- GDB：`D:/tools/gdb-18.1-isolated/mingw64/bin/gdb.exe`；
- 地图：`D:/code/rmmo_runtime/...`，正式 axel_town；
- 所有运行走 `run_godot_background179_env.run_background`（private desktop，
  `CREATE_NO_WINDOW`），不能弹窗。

核心参数：

```
--script res://tools/profile_axel_worker_capacity.gd
--mesh-only --without-mock-server --without-map-textures --white-material
--without-hud --uncapped-runtime --runtime-seconds=0
--origin-seconds=12 --steady-seconds=0 --origin-only
--capacity-timeline --native-only --efficient-membership-probe
--uncapped-loading --without-derived-geometry-cache
--without-prefab-bounds-cache --without-model-metadata-cache
```

cold 口径加 `--cold-index`；full traverse 加 `--native-departure --settle-demands`。
warm/cold 各 10 次，不要并发跑其他 Godot/Python 分析。

## 5. 代码地图

- `scripts/world3d/initial_loading_cover.gd`
- `scripts/world3d/deferred_asset_loader.gd`：`begin_loading_cover` /
  `end_loading_cover` / `_covered_loading_ready` / `covered_loading_budget_usec`
- `scripts/world3d/world_3d.gd`：初始白模 cover、full-ready settle、`is_world_ready`
- `scripts/world3d/world_stream.gd`：10 ms slow-source yield
- `tools/profile_axel_game_pipeline.gd`：白模默认 cover、`--without-white-load-cover`
- `tools/test_initial_loading_cover.gd`：7 项 cover/budget 合同
- `docs/axel_initial_loading_cover_20261024.md`：本专项记录

## 6. 交接 checklist

1. 先读 `docs/axel_initial_loading_cover_20261024.md` 和 `docs/axel_white_longframes_20261019.md` 的 §165，不要从 185 轮旧日志重新猜。
2. 冻结源码/引擎/地图 SHA，跑 warm 10 + cold 10，确认 p95。
3. 跑 `test_initial_loading_cover`、`test_entry_loading_contract`、
   `test_deferred_entry_prefetch`，再跑一次完整 cover traverse。
4. 若继续做长帧，先判断帧是否在 cover 下、是否 full-ready 后空闲、是否有
   stream tick；没有这些证据不要改 worker/预算。
5. cold崩溃：无外部优先级干预的白模探针23次未复现，不是完整游戏23次。
   早期优先级夹具2次异常与已撤回的并行hints/metadata mutex各1次AV分别保存；
   `coldpm_06`是退出原因未知的未完成attempt。没有dump/栈不能宣称根因已隔离，
   也不能由未复现宣布引擎已修复。

## 7. 不要做

- 不要用单次 9.3 s 宣称稳定；
- 不要把 cover 遮住的帧说成“引擎执行消失”；
- 不要在没有关键路径证据时继续加 worker/预算；
- 不要删除慢样本或把 cold-index 叫物理冷盘；
- 不要改正式地图/模型/纹理，不要恢复纹理/角色/HUD 阶段来做白模目标；
- 不要并发跑基准和 profiler 解码。
- 白模 core 的低风险批处理已经验证：`_remove_published_demand` 在
  `_publish_ready` 末尾按帧批量，1514 个需求一次移除；不要顺手把 HUD/camera
  回调也拉进来，超出白模加载范围。
- 3D 返回尖峰不能只归因于 `Drainer.synchronize_transfer`：把
  `_poll_jobs` 里的 `RenderingServer.force_sync` 去掉后，5 次里仍有返回
  90.9ms/13 帧 >50，且这属于资源生命周期风险；已恢复。后加的 stage 计时显示
  返回/重载干净，但一次 unload 54.6ms 的 `process_ms` 只有 17ms、Deferred
  poll/join/sync/dispatch 都是 0。后续 10 次 `stage_*` 里 7 次干净，
  `stage_03` unload 54.6ms、`stage_06` unload 85.7ms/返回 88.9ms、
  `stage_09` 返回 125ms；慢帧的这些 stage 多为 0，不能再用 force_sync 解释。
  跳过白模 prefab texture plan 的实验 unload 67.8ms/2 帧，无收益，已撤回。
  逐 unit trace 显示 publication 单次 `append_specs` 10–20ms、`emit` 6.5–10.6ms，
  单 unit 20.6–31.1ms（89-spec 甚至 2151-spec）；下一步应拆 append/emit 大 unit，
  不要继续把尖峰归因给 OS。
- 白模大 unit 的 `published.emit` 延迟到下一帧的实验（5 次）仍有返回
  78.2ms/5 帧 >50，且改变 observer 时序；已撤回。仅拆 emit 不够，`append_specs`
  的 10–20ms 仍在同一帧。
- 把 `StreamIndexPreparation` 阈值从 >256 降到 ≥32 的实验更差：return
  60.4ms/5 帧、reload 78.6ms/18 帧，37 个 preparation、203 slices、0.37s；
  已撤回。89-spec 组的 append 仍是 20ms，说明成本不在缺 preparation。
- 进一步拆 `stream.append_specs`：collision preflight 0–1µs、library 13–68µs、
  pending 6–74µs，几乎全部在 `StreamIndex.append` 的 5.5–10.8ms。再拆 index：
  89 specs 是 validate 1.7ms / fragment 5.1ms / commit 1.5ms；2151 specs 是
  validate 1.6ms / plan 2.9ms / commit 3.4ms；没有单一 20ms 黑盒。下一步只能
  优化这些子阶段或走 native/engine batch，拆 collision/library 无意义。
- 不要把 `_cold_model_hints` 直接扔到第二个 Thread：实测 5 次 cold 中 1 次
  `0xC0000005`（已打印入口就绪，不能归为loader阶段）。即使给
  `asset_source_metadata` 加全局 Mutex，随后
  6 次里仍有 1 次 `0xC0000005`；该实验已撤回。说明竞争不只在 metadata 磁盘缓存，
  还可能在 `PackagePolicy`/`_model_preparation` 或其他静态状态。要并行化冷 hints，
  必须先做完全无共享写的纯函数版本并逐项审计。
