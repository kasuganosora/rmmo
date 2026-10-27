# 完整材质 native 场景后台预打包候选（2026-10-28）

## 问题与范围

完整路线诊断 `full_native_trace_20261028_01` 返回阶段的 Trace 中，公会 `deferred.accept_template` 为 208.204 ms，同线程嵌套的 `asset_library.cache_materials`、`cache_pack`、`cache_dispose` 分别为 93.907、91.609、22.558 ms。这些是嵌套 wall time，不能相加或视作 CPU 时间。它与普通 full03 样本是不同进程。该候选仅处理其中的主线程 pack；不声称解决材质 intern、dispose 或完整地图加载。

候选由 `Deferred.full_native_worker_prepack_enabled` 控制，**默认关闭**，只适用游戏可信完整材质 fixed-native job。派发时把决定冻结在每个 job 上。worker 在已有私有 scene 和原始 native PackedScene 仍受同一 packet 持有时执行 pack；主线程仍按原顺序对同一 scene 做 `ModelTextureCache.apply`，然后发布已准备好的 PackedScene，最后回收 scene。白模、编辑器和其他加载路径保持既有流程。trace 的 `deferred.worker_native_pack` 与 `worker_prepacked_native_models` 用于识别实际运行的候选路径。

## 所有权与预算合同

旧 `cache_scene` 本就在此 job 的完整 reservation 内同时持有原始 PackedScene、scene 与新 PackedScene；该改动仅把同一峰值的 pack 提前至 worker，不复制材质、纹理或 GPU 资源，也不增加未计费 job。每个并发 job 仍按各自完整峰值占用 ledger，不提前 shrink；packet 内部的私有 preparation 仍保存 aliases，直到 drainer 清除并释放。这沿用原 `Footprint.estimate_stats` 的保守估算合同，包括解压体积、节点和容器等余量；它原本就不是严格 RSS 或 VRAM 上界。曾做全额重复收费试验，因会无依据地降低并发而撤回，最终候选不重复收取整份纹理/GPU 预算。

若未来 pack 路径引入新增资源副本，应重新计入；当前两 job 真实队列测试核对各自 reservation 及两者合计，发布、取消和驱逐后的 owner 与 lease 清零。ticket 的 prepack 决定在派发时冻结，避免开关变化造成预算与实际工作不一致。

## 可复现证据

产物均保留在 `D:/code/rmmo_runtime/review_artifacts/`。GPU 测试经 `tools/run_godot_background.py` 私有桌面运行，使用独立 userdata；这些小型正确性测试不作为真实地图性能结论。

- `deferred_worker_prepack_red01/godot.log`：旧实现真实 fixed-native 准备红测 **94/1**，唯一失败是没有 worker 私有 scene + 预打包模板。
- `deferred_worker_prepack_green06/godot.log`：真实 full native 构建、移除 GLB、后台准备、双 job 派发与发布、重复纹理 intern RID、取消后回收、错误 digest 和非法 owner 释放、stale 固定票据无 raw 回退，**117/0**；包含 dispatch 后改全局开关仍按票据快照运行、完整 reservation 最终归零。
- `deferred_worker_prepack_matrix02/godot.log`：独立合成资源矩阵对照旧 `cache_scene` 与实际 `cache_prepared_native_scene`，**318/0**。覆盖嵌套 mesh/material/texture、resource_local_to_scene、grass override、next_pass、同像素跨模板纹理共享、双实例和取消/替换/驱逐后的弱引用；这不是完整地图样本。
- `deferred_worker_prepack_regression01/`：native admission **493/0**、collision prefetch **19/0**、model preparation **25/0**；`deferred_worker_prepack_gpu_regression01/white.log`：白模 GPU **86/0**。
- `deferred_worker_prepack_gpu_regression01/fixed_native.log`：既有 GPU 测试在共享 content root 上的测试产品构建前置失败，未打印构建失败原因；不推断与候选有关，也不丢弃该样本。`deferred_worker_prepack_gpu_regression02/` 以独立 content root 运行同一测试，通过 **103 项 PASS，0 failures**。两次 root 不同，因此后者不能证明前者的根因。

上述测试中真实原生产品和地图均为临时数据，保留用户正式资源；正式地图和正常工作负载尚需独立对照。测试外部合成矩阵的资源引用与弱引用证明了所测资源类型合同，不替代完整城镇场景中材质和驻留的复测。

## 后续验收边界

正常引擎、相同完整材质地图与 fixture 的实际控制项下进行顺序 ABBA；记录每臂完整加载、返回/卸载帧分布、实际 `worker_prepacked_native_models` 和主线程 `cache_pack` 是否消失、worker 工作量、队列/内存预算与慢样本。仅在完整场景收益和生命周期验证成立后决定是否默认开启。该切片尚未处理同帧材质 intern、同步 dispose、native 大模型读取或编辑器专用优化。

## 首次整图对照未通过：保留默认关闭

`full_prepack_abba_20261028/` 协调器按 A1（关）、B1（开）、B2（开）、A2（关）计划执行，但在 B1 失败后停止，B2/A2 未启动：

- `full_prepack_abba_A1_20261028/`：普通完整路线功能通过，entry 10.211 s、current-demand ready 20.547 s；实际开关关闭，源码和 fixture 身份一致。这只是一个样本。
- `full_prepack_abba_B1_20261028/`：入口 10.835 s，停在 `white_stream_origin`，未出现 full-ready。退出码 `0xC0000374`（heap corruption）；同 PID 60192 的 Windows Application Error 另记录 `0xC0000005`，engine09 offset `0x4A54EFA`。两个记录不是同一错误码，不合并成已知根因。没有 GDScript 错误不代表引擎运行成功；末尾材质/功能验证因崩溃未完成。
- 失败目录保留原始日志、结果、入口快照、前后身份记录，以及 `windows_events.xml.txt` / `windows_report.wer`；所有已启动进程已退出。不得只保留 A1、补一个成功 B1 后忽略本次失败，或据这两臂宣称性能收益。

独立静态审查发现 engine09 对应源码的并发风险：`PackedScene.pack → SceneState::_parse_node → PropertyUtils::get_property_default_value → ClassDB::class_get_default_property_value` 可访问未加锁的全局 `default_values` / `default_values_cached`。首次并发 pack 可能导致容器并发读写；目前只是可达风险，尚未证明是本次 B1 崩溃的原因。已有小测试先在主线程构建/pack 测试产品，可能提前初始化这份缓存，因此不能证明冷进程首次并发 pack 安全。后续先独立冷进程复现，并在真实路线用匹配符号 GDB 捕获异常。

另有明确测试边界：现有 pack 后取消测试直接调用 drainer，尚未覆盖真实 `_poll_jobs` 中结果已就绪但未发布的取消；white/editor 隔离尚缺候选开关显式开启的负向运行证据。318 项矩阵源脚本在外部 `axel_full_native_staging_20261027_01/test_worker_pack_reference.gd`，当前日志只记录总数，不能补写事后 SHA 冒充测试时身份。上述问题解决前不推广候选。

材质阶段完成后，内容编辑器和当前 3D MCP 的适配仍为必做后续：复核可变源导入、原生产品、预览、共享/退役、撤销和保存重开，不能直接套用游戏 trusted/native-only 合同。

## 冷进程并发实验与夹具问题

外部 `classdb_first_pack_repro_20261028/` 的空项目没有在脚本内先调用 build/pack，但引擎启动后 ClassDB 缓存是否尚未初始化仍未观测，不能仅凭新进程称缓存冷态已证明。

第一版双 worker 在 gate 后由主线程直接 `wait_to_finish`，约 60 秒超时。`hang_gdb01/stacks.log` 确认主线程正在 join，而两个 worker 位于 `PackedScene::pack → SceneState::_parse_node → GeometryInstance3D::_get_property_list → RenderingServerDefault::instance_geometry_get_shader_parameter_list → CommandQueueMT::push_and_sync`，等待主线程服务。这是夹具设计造成的等待，不是 ClassDB 竞态的复现。该栈也说明把 pack 移入 worker 不等于所有 pack 工作脱离主线程。

修正外部夹具为主线程持续同步渲染服务并推进帧、worker 结束后再 join。`samples03/summary.json` 保留全部 40 个独立进程、实际命令和前后身份：

| worker / 节点类型 | 正常退出及内容一致 | 异常 |
| --- | ---: | --- |
| 2 / 同类 | 10/10 | 无 |
| 2 / 混合 | 10/10 | 无 |
| 12 / 同类 | 9/10 | `w12_same_05` 退出 `0xC0000005`，无异常栈 |
| 12 / 混合 | 10/10 | 无 |

脚本 SHA `942356410ffd08c95751ae374c63608efab2e293e02b064c9ec6cbc73d20c4cf`，runner SHA `d4ca16880a379ae98ffeedf94a30a5b9be563b1d6c9ae76a2eff799041ee829b`；root 核对与记录一致后将脚本、项目、runner 副本留在 `samples03/`。这是独立并发实验出现异常的证据，尚未证明具体引擎缺陷或它与 B1 同因，不能宣称已经修复。

## 尝试直接省掉 pack 的差异研究

外部 `native_direct_reuse_study_20261028_01/sample_02/report.json`，SHA `e2991a904beebd3ec65990ce7ab697ef1ebd2bef54098a27c66b9903c803af4a`，比较旧 cache_scene 与直接复用原 PackedScene，24 种合成组合中 17 种存在观察字段差异：需要草地 COLOR_0 修正的第二实例可能丢失材质覆盖；local mesh 的私有 CPU 缓存无法自动传播回原模板；部分 local material 的共享纹理/next_pass 不一致。其余 7 种在所测字段相同，不代表所有资产安全。sample_01 的缺失 metadata 访问错误已保留，修正夹具后另建 sample_02，没有覆盖失败样本。

因此不能无条件直接发布原 PackedScene。后续只评估保守的离线已知分类，先验证真实大建筑的节点、全部材质/mesh/collision 数据、共享、实例化和回收，再讨论运行时省略重复打包；不把分类审查变成每次加载的全树认证。
