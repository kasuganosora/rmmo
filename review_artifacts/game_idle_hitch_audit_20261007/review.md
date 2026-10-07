# 游戏未归属 process 长帧：静态复核

2026-10-07。只读分析；没有修改生产逻辑、运行 GPU 或写入地图。目标是给下一轮定向计时提供插点，**尚未确认 62.264 ms 的根因**。

## 已验证的样本边界

输入 `D:/code/rmmo_runtime/review_artifacts/town_street_entry_20261005/river_bridge_surface_detail_20261007.json`，最大样本索引 1414。前后五条完整记录已复制为本目录 `peak_and_neighbors.json`。

- engine frame 3434，process 起止 83,529,406–83,591,670 usec，62.264 ms；绘制前间隔 0.138 ms、draw 6.510 ms。世界分段相加 0.294 ms、weather 0.285 ms、navigation background 0.018 ms，均属于 frame 3434。
- radar frame 3428、lamps frame 3425、collision/stream phases frame 3185，属于历史数据，不能与当前帧相加。batch_slice 136.457 ms 和 commit 2.410 ms 在前后五条记录完全相同，不能视为本帧重建。
- 该行的 physics 3766–3768 支撑查询在 83,598,814 usec 之后，即该 process 区间结束后。下一帧开始前补跑物理步不能解释前一帧的 process 时间。
- 五帧均为 8630 节点、3475 resident mesh、0 pending residency jobs，内存约 1785.213→1785.292 MiB 缓慢增加。当前这次没有观察到大规模卸载或内存骤降；不能套用历史另一次 RSS 降 184 MiB 的相关性。
- `tools/profile_town_street_entry.gd` 从 SceneTree.process_frame 信号开始，到 priority=1000000 的 ProcessMeter 为止；中间包含采样协程及未计时节点回调。该区间不是 CPU 使用时间。须用指定线程 CPU/周期证据区分真正计算与等待。

## 建议的计时优先级

| 优先级 | 位置 | 为什么仍可达且未覆盖 | 最小可验证插点 |
| --- | --- | --- | --- |
| 1 | `scripts/world3d/occlusion_outline.gd:_process` / `_blocked` | 每帧最多三个物理射线；每 0.5 s 遍历角色子树。`outline_active=false` 说明没有遮挡，不说明没有查询。World camera 分段不包含独立 outline 回调。 | 记录 callback begin/end、tag/cleanup、ray、viewport 同步端点及射线数量。保持现有提前退出、碰撞排除和显示。 |
| 1 | `scripts/char/character_model_3d.gd:_process` | 所有角色独立动画回调不在 World._process actor 分段内。imported 路径每帧 pose/blend/weapon/hair/garment。 | callback begin/end；pose、blend、axis_finish 或 imported grip/soft/hair/garment 分段。记录 instance_id、rig 类型，避免多个角色覆盖。 |
| 2 | `scripts/ui/game_hud.gd:_process` | 13 个 toast/cast/hotbar/status/quest/drop 更新仍执行；小地图 draw timing 不覆盖它们。 | callback 包装器总计，必要时 tick_visual、cooldowns、status、layout 分段。应把早退也纳入。 |
| 2 | `scripts/world3d/house_candle_lights.gd:_process` | 每 0.25 s 遍历 fixtures；独立节点，不属于 weather 自身分段。白天也遍历并写位置/visible；不代表有足够规模导致 62 ms。 | 本次是否 refresh、fixture 数量、refresh 起止、night/active 数。先测，不改白天语义。 |
| 2 | `scripts/world3d/ground_batcher.gd:_process` | 空闲仍有 32 项 lifetime audit；last_prepare_slice 是历史值，缺乏当前回调总计。 | callback begin/end、audit、prepare、finish_worker、pending/workers 数。最后一个 timestamp 之后的临时对象释放要由外层端点覆盖。 |
| 3 | `scripts/char/character_overhead_label.gd:_process` | 可见 NPC 名称/施法文本每帧求 skeleton pose、mesh bounds、skin binding；独立回调。 | 单实例 callback 起止；有慢项才深分 anchor。主测试玩家不一定带名称，必须同时记录实例数量。 |
| 3 | `scripts/net/mock_server.gd:_process` | 自身尚未计时，但当前路线默认 player_cell=-9999，预期只执行 _tick_weather 后早退。 | total/weather + early-return reason/player_cell；不要先给 2D AI 每函数加计时。 |

每条保留 `frame`, `begin_usec`, `end_usec`，默认关闭；下一轮仅显式诊断启用。计时累加必须按 process frame 配对，不把最新一份 metadata 自动算成本帧。若各 callback 总和很小而总区间仍大，使用绝对端点找相邻回调之间的空洞，再结合 OS 主线程采样；不将“未归属”直接命名为渲染锁。

## 排除与降低优先级

- `tools/world3d_test_character.gd` 只设置 male、空 customization。`character_model_3d.configure` 必须显式 `body_model=female_base_v2` 才创建 axis rig；本路线不能先归咎 axis GPU cloth 或 native source hair。真实用户女性新素体另需覆盖。
- `MockServer.player_cell` 初始化为 (-9999,-9999)，真实 `session_module.enter_world(...,true)` 也重置此值；当前测试不运行二维进入世界。没有证据表明 2D mob AI、respawn/combat tick 是该路线的长帧来源。
- `game_hud.bind_world_map_3d` 使用新的 WorldMapView3D，但 `_radar_player:Node2D` 保持 null，因此旧 `_sync_radar` / 2D blip 更新提前返回。3D radar 的独立 `_process` 每 0.1 s queue_redraw 并刷新打开地图的信息，应当单独轻量计时，而非修改旧适配器。
- GameSession、AssetManager、GameSettings 没有 `_process`。未发现游戏行走时启动 editor `document_safety` 自动保存。AssetManager deferred pump 是显式加载队列，不等于周期保存。
- MCP game_helper 在 debugger inactive 时 `_process` 提前返回，不能把它的日志批量发送当作默认路线热点。Logger 仍可能接收 print/error；当前无日志风暴证据，不改第三方插件。测量本身不应在长帧时同步打印大 JSON。
- 路线 watchdog Timer 是 540 s（soak 1200 s）结束测试；不是约 83 s 的周期任务。navigation `_publish` deferred 本身只设两个字段。未找到该位置明确触发的游戏定时保存。
- 地图 loader `_build_records` 在 finished.emit 后 `_retire` 等待缓存写入并 queue_free，确实可能在游戏已启动后释放临时数据。但这次节点/内存序列不支持巨大释放，而且 queue_free 常在 ProcessMeter 外。只建议测试脚本连接 loader `tree_exiting/tree_exited` 的绝对时间，若长帧前已消失便可排除；不建议猜测性延迟释放。

## Grok 初审状态

使用本机 `C:/Users/luna/.grok/bin/agent.exe` 与 `grok-agent` skill。首轮 `prompt.txt` 提供约 197 KB 源文本，Grok 试图继续取证，两轮限制耗尽，退出 1；`grok_report.txt` 仅有进度句，不是有效审计结论。保留 stderr，明确未把它当成功。

随后缩为 `prompt_compact.txt`，加入已验证样本和可达性，限制只基于给定文本给出最终意见。进程 19596 在 12:06:47 启动，超过五分钟仍无 stdout/stderr；12:12 核对命令行确为本审计后只停止该进程，未动共享 leader 或其他 Grok。此次没有取得 Grok 有效最终结论；不再重复调用或绕过权限。以下继续结论来自独立代码及实际路线日志复核。

## 新 callback 路线的独立复核

父 agent 新跑 `river_bridge_callbacks_20261007.json` 后，MockServer/Model/outline/HUD 这四个回调在两个新尖峰中都小于 1 ms，故降低上表这些候选的优先级，不再凭早期未计时状态继续猜测。

### 250.293 ms：不是已证明的 spawn/drop 热点

frame 7481 世界 stream 213.632 ms、stream.apply 210.133 ms，JSON 中 collision_prepare 仅 0.077 ms。但外部日志 `D:/code/rmmo_runtime/review_artifacts/river_bridge_callbacks_20261007.log:37` 同帧明确为：

```
COLLISION_PREP_SLOW bridge_grass_0426__arch_B_LOD0 206.773 { "frame": 7481, "physics_frame": 7928, "uuid": "bridge_grass_0426__arch_B_LOD0", "ms": 0.077, "ready": true }
```

这意味着 _prepare_collision **整个调用**用时 206.773 ms，而内部局部 timing 覆盖段仅 0.077 ms。`_prepare_collision` 的最前面 profiling meta getter、get_node、profile_serial 读取不在 started 之后；末尾 profile meta 设置和函数返回临时量清理也不在 `timing.ms` 内。下一行 3 ms 预算检查会 break；本次没有 STREAM_SLOW 日志，不能把尖峰写成 mesh spawn/free 已被证明。

最窄下一步：把 outer prepare 的绝对 begin/end 和 wrapper 的前置/impl/metadata publish/return 端点配对，记录 profile_serial、uuid、frame，禁止在尖峰途中同步打印；若只有最后返回间隙长，再用主线程 CPU/周期采样辨别等待。逻辑段小不说明其他同名调用也小，更不能凭 0.077 排除这个 wrapper。

### 109.772 ms：sky 97.787 ms 尚未分到 provider/receive/提交

frame 4902 的 `weather._tick_night_sky(delta)` 97.787 ms，weather 总 97.916 ms。该函数包含：1 秒周期 provider.snapshot；NightSky.receive（schema/defaults 构建、事件校验、深复制）；revision 更新与信号；sample/Cycle；九项 sky shader 参数。其余四节点小于 1 ms，暂不动角色和 HUD。

应记录是否 poll、provider/receive/revision/sample/uniform 各绝对端点，结束在外层 callback 确保含 PackedArray 回收。没有足够证据把 97 ms 叫 shader 等待、JSON 验证或分配器等待。

确定存在另一项重复调用：开启 celestial_cycle 或 transition 时 `_process` 先 `_tick_night_sky(delta)`，后 `_apply` 又 `_tick_night_sky(0)`。但两者之间 `current` 会变化，并影响 star/meteor visibility；不能简单删除后一次。本次 apply 只有 0.007 ms，通常未执行 `_apply`，所以该重复并非本次尖峰的解释。若后续独立优化，宜拆分同步/采样和最终参数提交，同时覆盖直接 `_apply()` 外部入口、环境切换、流星与昼夜画面回归。

## 本轮新增的诊断（父 agent 授权实施）

仅改 `weather_controller.gd`、`world_stream.gd`、`tools/profile_town_street_entry.gd`。没有改变天气配置、碰撞几何、线程归属或导航容差。天空详情要求同时启用 profile_frame 与 profile_sky_details；路线 --collision-details 设置这两个标志。碰撞 wrapper 沿用 profile_collision_details。未开启时不创建时间槽。

- `sky_details`：每 frame 最多 4 个复用槽，溢出计 dropped。覆盖 `_process` 和 `_apply` 同帧重复调用，保留每次 polled/accepted/revision_changed/editor_preview。provider/receive 未执行时对应时间为 0。begin→setup 包含取时间、轮询阈值和编辑器预览配置；provider/receive 独立；revision 到 sample_begin 分离；sample_end 后分别为四项基本 sky uniform、五组 PackedArray 构建、五项流星 uniform；return_end 在实现函数返回之后，包含其临时数据释放。字段名即绝对 usec 的边界。
- `collision_wrapper`：每 frame 最多 32 个复用槽。outer_begin 在调用前，wrapper_begin 在 wrapper 内第一个计时点；impl_begin 之前包括元数据/节点/serial 读取；impl_end 后到 publish_begin 是 timing 构建及 preparer/旧元数据读取；publish_end 包含条件 set_meta；return_begin 到 outer_end 包含最后 return 和作用域清理。每条 uuid 单独关联，避免只保留最快/最后一次。详细模式不再在 COLLISION_PREP_SLOW 现场 print；原粗计时路径保留。
- 时间槽仅存整数及 uuid；采样函数才构造具名快照，快照不引用会被下一帧覆写的槽。必须匹配 `details.frame == engine.frame`。这些是墙钟区间，不是 CPU 执行时间。其他已有 STREAM_PHASES 输出仍可能带少量诊断成本。

由 root 串行执行（本子任务未运行 Godot）：

```powershell
& D:/tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/code/rmmo --check-only --script res://tools/profile_town_street_entry.gd
& D:/tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/code/rmmo --script res://tools/test_stream_collision_profile.gd
& D:/tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/code/rmmo --script res://review_artifacts/game_idle_hitch_audit_20261007/test_detail_timeline.gd
python review_artifacts/game_idle_hitch_audit_20261007/analyze_boundaries.py D:/code/rmmo_runtime/review_artifacts/town_street_entry_20261005/river_bridge_boundaries_20261007.json
```

root 已回报前两项退出 0；轻量夹具最终 13 PASS、退出 0，覆盖默认关闭、poll/nonpoll/reject/修订、同帧多个 sky 调用、有界槽、快照独立、真实 paced stream sync 的外层区间。实际路线仍必须由 tools/run_godot_background.py 在私有桌面执行。

### 带边界和 CPU 采样的新路线结果

输入 `river_bridge_boundaries_20261007.json` 和 `river_bridge_boundaries_thread_20261007.json`。root 运行返回退出 0、通行失败 0、源未变；诊断首程 P95 22.677 ms、最大 143.782 ms、>50 ms 两帧。这不是同轮 A/B，不是新的帧率改善声明。

完整具名阶段汇总在 `boundary_analysis.json`，绝对时间关联 CPU 在 `boundary_cpu_analysis.json`。4391 次 collision wrapper 最大 5.295 ms，原 206 ms 尖峰未再现；前置/发布/return 都没有 >20 ms 的当前证据。5781 次 sky 调用、两个采集器 dropped 均为 0。

| 帧 | 位置 x,z | 整帧 | 精确长区间 | CPU 取样证据 |
| --- | --- | --- | --- | --- |
| 2804 | 2.389,18.050 | 143.782 ms | sky sample 128.618 ms，未 poll；provider/receive 未执行，基本+流星 uniform 0.026 ms、PackedArray 构建 0.026 ms | 外包 137.659 ms、内包 126.587 ms，主线程 CPU 时间增量均为 0；内包约 3126 万 cycles |
| 6875→6876 | 241.305,105.566 | 67.118 ms | 前一 process 仅 1.563 ms；下一 physics 内 wind refresh 50.702 ms，只有 1 个扫描元素、scan 0.025 ms | 精确 wind 外包 53.341 ms、内包 43.025 ms，CPU 时间增量均 0；内包约 701 万 cycles |

CPU 时间存在约 15.625 ms 粒度，不是证明零计算；cycles 也不能未经频率校准换算毫秒。但此处百毫秒/五十毫秒的主要墙钟成本不是同等主线程 CPU 工作。第一帧长段只含 `night_sky.sample`（clear/最多 8 项事件）、`Cycle.hours/sample`、visibility 运算和临时量赋值，已经排除该次网络/provider/schema 校验和 shader 参数提交。第二次 `_begin_refresh` 把 group 数组快照及初始化计入首片，而单元素扫描很短；尚未单独定位 get_nodes_in_group 的内部等待。

同时两个约 215 ms 的进程内存外包窗口分别 RSS 降约 156.63 / 176.80 MiB，缺页计数增 1780 / 3285。它们是相关性，缺页含软缺页，不能据此称磁盘换页或指定 allocator/driver 锁。

结论：此轮不支持把 Cycle.sample、shader、collision wrapper 或节点释放机制直接改为“修复”。稳定每秒 receive 约 1–2 ms 及日夜重复调用可作为独立确定性冗余审查，但不是所测长帧的根因。真正下一步是带调用栈的 OS 调度/等待取样或更细的原生调用端点，而非继续增删功能、改碰撞预算或复跑无新假设的整城 A/B。

轻量夹具首次前五项 PASS 后索引越界：单行 lambda 的分号后语句被包含在 lambda 体中、位于 return 之后，第三次测试调用未执行。已分行并加数组大小检查和 25 秒超时；首次中断由 root 精确停止，不计通过。第二次 12 PASS / 1 FAIL，原因是首次 await process_frame 可能仍处于 Engine frame 0；已改为等待实际 Engine frame 改变。root 最终重跑 13 PASS、退出 0。


### Windows WCT 只读候选与自测

新增 `profile_wait_chain.py`，只针对命令行精确 `--label=...` 的唯一 Godot 测试进程，按线程创建时间选择 main 候选，不注入、不挂起、不调整令牌、不提权。默认 25 ms 间隔、下限 10 ms；每次保留绝对 Unix 时间和查询自身耗时，以便与外部 CPU/route 诊断关联。最多每次 16 个 WCT 节点。若明确访问拒绝或不支持，写出错误后停止。

结构和枚举核对本机 Windows SDK `10.0.22621.0/um/wct.h`，并核对微软 [GetThreadWaitChain](https://learn.microsoft.com/en-us/windows/win32/api/wct/nf-wct-getthreadwaitchain)、[WAITCHAIN_NODE_INFO](https://learn.microsoft.com/en-us/windows/win32/api/wct/ns-wct-waitchain_node_info) 和 [Wait Chain Traversal](https://learn.microsoft.com/en-us/windows/win32/debug/wait-chain-traversal)。WCT 支持规定的 mutex、critical section、ALPC/COM 等等待；单节点既可能是运行中，也可能是 WCT 不支持的等待，不能据此排除 SRW/条件变量、驱动等等待。默认 flags 0，不跨进程追踪。同步调用可能阻塞采样器本身，不保证硬截止；没有覆盖所有原生等待的承诺。

仅执行 Python 自身 mutex 自测：`wct_self_test.json` 中 worker blocked → mutex owned → main running，三节点成功，退出 0；单次查询 13.17 ms，故采样不能视作零开销。此自测只验证结构布局和当前进程 API，不证明可以访问 Godot，也不是游戏根因证据。尚未由本子任务采样任何 Godot；父 agent 单独调度，不能影响正在进行的编辑器基准。

```powershell
python review_artifacts/game_idle_hitch_audit_20261007/profile_wait_chain.py --self-test
# 首次外部访问验证用一个专门允许采样的测试进程，先短跑；拒绝时不提权。
python review_artifacts/game_idle_hitch_audit_20261007/profile_wait_chain.py --label=EXACT_ROUTE_LABEL --out D:/code/rmmo_runtime/review_artifacts/route_wct.json --timeout 2 --interval-ms 25
```


### WCT flags 复核与外部临界区自测

新增 `--critical-sections` 仅设置 `WCT_OUT_OF_PROC_CS_FLAG=0x4`，不设置沿等待链进入其他进程的 `WCT_OUT_OF_PROC_FLAG=0x1` 或 COM 标志 0x2。官方文档对 0x4 明确为获取其他进程的临界区信息；现有 flags 0 结果不能用于排除未支持/未捕获的等待。此选项不修改已启动 sampler 的行为。

实际外部测试 `--external-cs-self-test` 创建自己的短生命 Python 子进程：主线程持有 Win32 CRITICAL_SECTION，worker 等待；2 秒后主线程正常释放、join、删除 CS，子进程退出 0。父进程分别读取 worker 的 flags 0 与 4，两者在本机均返回 waiter→critical_section→owner 三节点，无 stderr。这证明 0x4 路径有效，也证明不能声称本机 flags 0 完全不能读取外部 CS。完整可复跑结果在 `wct_external_cs_self_test.json`，没有采样任何 Godot 基准。

### 实际 WCT 路线独立关联

输入 `river_bridge_wait_chain_20261007.json`、`river_bridge_wait_chain_wct_20261007.json`、`river_bridge_wait_chain_thread_20261007.json`。5000 条 WCT 中单节点 running 4803、单节点 blocked 189、多节点 blocked 7、目标退出空结果 1。7 条多节点都是 thread_wait，只出现在约 50.95/52.69 秒加载期和 161.48 秒退出期，与路线中 5 个 >50 ms 尖峰均不重叠。不能用这些加载/退出链解释路线卡顿。

- frame 6580，57.152 ms：后续 physics 中 wind 45.331 ms，其中 `_scan_nodes.clear()` 28.494 ms、`_scan_cleanup.clear()` 16.562 ms。精确 wind 外包 48.943 ms 的 CPU 增量 0、cycles 1422 万，内包 37.852 ms 的 CPU 增量 0、cycles 704 万。区间内 WCT 两次都只给 running 单节点，不能排除未支持等待，也不证明清理有 45 ms 等量 CPU 工作。不建议无证据分帧/替换数组释放。
- frame 6617/7165/7275/7383，整帧分别 59.548/76.430/64.967/57.541 ms；radar draw 32.674/31.379/34.312/25.814 ms，terrain 26.170/25.920/30.854/22.609 ms，几乎覆盖各自 process_end→draw_begin 的 32.925/31.922/34.569/26.026 ms。四次都是同帧 metadata。后三区间 CPU 约 31.25 ms，cycles 约 1.1–1.3 亿，支持实质 CPU 构建/提交成本。GetThreadTimes 粒度/更新会造成短内包 CPU 大于墙钟，不能精确求利用率；第一帧 CPU 时间未跳变也不能忽视约 9211 万 cycles 的工作。
- 天空、碰撞 wrapper 本轮没有早前大峰，不能声明消失。父 agent 核对 terrain_layer/view 修改时间均为 2026-10-07 00:01 左右、早于本轮所有路线：当前每形状 RID 保留命令代码确实已被这轮测试。此前关于“旧加载版本”的推测已撤回，不作为分析前提。正在验证 bind_world 在 HUD radius 设置和容器最终布局前预制 width，随后 unseen 形状因 width 不同重录的假设；默认设置 11×2=22 与 View 默认相同，不能仅凭调用顺序认定本轮根因。
- WCT 查询自身 median 10.448 ms、P95 16.058 ms、max 32.733 ms；有额外系统取样干扰，本轮 max 76.430 ms 不能与无 WCT 的前轮 143.782 ms 直接称性能改善。

关联工具 `analyze_wait_chain.py` 与完整各段 CPU/内存/重叠查询证据 `wait_chain_analysis.json` 均已保存。工具只读已完成报告，不附加到进程。


### Radar 初始化宽度假设的修前诊断

已在 `world_map_terrain_layer.gd`/`world_map_view_3d.gd` 增加 profile_frame 下的录制增量、显示/隐藏增量、当前/prepare宽度、总录制数；没有增加逐形状计时。路线 collision-details 启动快照包含 radar size/radius/scale、prepare宽度和全宽度直方图。旧 HUD bind 顺序和渲染行为暂未更改。真实 HUD 小夹具 `test_radar_hud_lifecycle.gd` 覆盖未等待布局即 bind、最终布局、走入新覆盖区，以及默认11/非默认16设置，只临时更改内存、最终还原。

按父 agent 要求又调用一次本机 Grok，精简提示 `prompt_radar_width.txt`、工具关闭、plan、最多2轮、墙钟75秒，超时结束指定子进程；stdout0，stderr保存在 `grok_radar_width_stderr.txt`。没有有效分析结论，不继续等待/重试。后续验证独立进行。


### 实际 HUD 生命周期：两次红测与最终待验方案

父 agent 使用真实 `game_hud.tscn` 运行修前夹具：默认 radius setting=11，bind 时 size=(0,100)，prepare_width=44；layout 后 size=(146,133)，正确 width≈0.3308。144 个形状中114个离屏形状仍保留44；走到新区后 recorded 204→225。非默认16同样失败。两个panning FAIL、exit1是确认缺陷的红测，不是通过。

尝试只移到首次_draw后再次红测：首次prepare size=(146,100)、width=.44，后续layout仍变为(146,133)、width≈.3308；walk174→195，默认/非默认各失败。说明“首次_draw已是最终布局”的假设不成立。已撤回只延迟一次即可修复的结论。

父 agent 同时发现名为 radar_before 的整路测试在运行中动态 load HUD/View，而源码曾在该加载前改动，其3911形状宽度全正确且缺少first_preparation字段，存在混合版本风险。该路线不能作干净修前baseline或A/B。此后 profiler 针对View/Layer/HUD/World3D/nav/wind/weather/stream 记录起止SHA和 probe_sources_unchanged，避免此类误标。

最新实现（待父 agent 串行验收）：Layer 延迟创建RID、约1ms预算后台录制离屏命令，完成后关闭额外_process；View按当前size/scale/data/revision维护准备状态，至少跨2个process frame稳定，尺寸/缩放再次变更会重启预热；_draw只立即保障当前覆盖区精确轮廓。World3D在风/灯准备后、解除移动锁和ready之前等待当前可见radar完成。隐藏、零尺寸和退出不阻塞加载；同数修订、地图替换及重新入树走失效路径。后台切片以单个footprint为最小原子单元，不能承诺任何单项都严格小于1ms；诊断记录实际最大切片。

真实HUD fixture改为等待warm而非固定sleep，覆盖默认11/非默认16、zoom、revision、隐藏/恢复、零尺寸、预热中退出/重新入树。已有GPU draw-cache夹具保持原始/缓存截图对比，并在预热完成后验证轮廓宽度及首次/行走录制数量。本子任务尚未自行运行Godot，不能把这些新增检查称已通过。


最终预算预热方案的阶段验收：父 agent 已修正 Layer `changed` 的 bool 类型推断，并串行完成真实 HUD 生命周期测试 `HUD_LIFECYCLE_FINISHED failures=0`；默认11与非默认16的全部144形状均为最终正确宽度，行走后总录制数不增加，取消/隐藏/零尺寸/缩放/同数修订/重新入树均通过。GPU `test_world_map_draw_cache.gd` exit0、failures0；三组 original/cached PNG 所有通道逐字节相同。完整无WCT路线 `river_bridge_radar_warm_20261007` 仍运行中，尚无该路线结论。

独立静态复核：每片先复核代次；width改变重置cursor；data/revision/count变化清RID和重建索引；遍历完全部index才完成；完成停止额外_process。隐藏/零尺寸暂停、显示/resize恢复、退出清RID、重入重新prepare；World3D等待在input解锁和ready之前，含退出guard。1ms约束只针对后台录制循环，单footprint不可抢占，数据失效时clear/数组初始化不是严格硬预算，不把该数值宣称成所有地图操作的上限。


### 完整桥段预热修复验收

`river_bridge_radar_warm_20261007.json` 无WCT或外部CPU采样，父 agent 运行exit0，failures0；正式地图SHA与8个关键运行源码起止SHA均一致。独立提取证据保存 `radar_warm_analysis.json`。

最终 startup size=(146,133)、radius=22、width≈0.330827；3911个形状的宽度直方图只有该正确值。命令计数3920（加载中布局变化时额外9次重录），后续全程不增长。预热309片，测得最大切片1.795ms，最终代次跨5735.911ms墙钟，完成时ready_for_play=false，随后loading_profile.radar=58678ms。这里是跨帧、与其他加载工作部分重叠的准备时间，不是5735ms单帧CPU成本；加载等待不是免费的，不把它隐去。

885个同帧radar样本、42次同帧terrain更新中，recorded_delta全部0、commands_recorded固定3920；terrain最大2.824ms、整个radar最大9.116ms。结合真实HUD红/绿测，确认行走触发错误宽度二次录制已修复。修前WCT路线的25–31ms terrain重录有干扰采样，不能据此宣称严格整体A/B帧率提升，但逐帧零重录是直接功能与性能机制证据。

整体仍有3个>50ms帧：median16.706、P9522.825、P9933.067、max153.682ms；不能称所有游戏卡顿已解决。

| engine帧 | 整帧ms | 本轮实际长区间 | 排除/限制 |
| --- | --- | --- | --- |
| 2769 | 73.075 | 下一physics3082，角色navigation56.093ms、support56.165ms、physics56.904ms | 对应surface point_cache绝对69467167→69467175，仅8μs；radar是旧frame2767，不能归因UI |
| 6932 | 153.682 | 下一physics7251，navigation77.560ms、角色78.197ms；wind第一片59.994ms，scan仅0.024ms | 对应surface point_cache138939982→138939994，仅12μs；两段都在draw之后，不是本帧weather/stream。radar旧frame6926 |
| 7542 | 51.292 | draw30.194ms + process9.766ms + 后续3次physics合计8.635ms | nav source3.041ms，surface point_cache15–18μs；没有同帧UI重录，radar旧frame7541 |

前两帧外层导航支持查询和内层surface计时悬殊，类似此前变化位置的长间隙；没有这轮CPU/栈证据，不能写成本轮特定锁、GC、驱动或Recast算法根因。暂不为其盲改碰撞/导航容差或风场算法。


### 剩余 support/navigation 长区间的只读调用链复核

`world_authority.gd:60` 在 `_landing_below()` 返回后取 landing_done；第63行依次检查 landing.is_empty、`near_surface(next,.35,.65)`，仅第一次返回false才调用第二次 `near_surface(landing.position,.55,.65)`；第66行在 wish 分支结束后取 support_done。`navigation_ms=(support_done-landing_done)` 不是某个 NavigationServer API 的专属计时。

这两次只有一个 accepted=true 的 point_cache样本、dropped0，故第二次near_surface被短路；也未走 triangle_index、map_get_closest_point 或 find_path。`world_navigation.gd:453` 的 mesh.get_polygon_count 及第457行 `NavigationServer3D.map_get_iteration_id` 都在stamps[0]→stamps[1]内，本次分别仅4/5μs。`_record_surface_profile` 第447行把 end_us 作为字典最后一个字段取时间，之后的字典构造、Array.append、函数返回和局部临时量释放不在该 end_us 内。

绝对时间进一步限定间隙位置：frame2769 surface.end=69,467,175μs→sample.ticks=69,524,133μs，后段56.958ms，接近navigation外层56.093ms；frame6932 surface.end=138,939,994μs→后续wind.begin=139,018,122μs，后段78.128ms，接近navigation77.560ms加剩余角色动作。因此主要长段发生在内层记录终点之后，而不是其入口之前。

该后段可达的工作是 diagnostic Dictionary构造/append、surface_cache_hits递增、near_surface局部stamps Array退出、调用返回及move_intent中landing Dictionary/next局部作用域退出；其中没有直接调用NavigationServer同步查询、region发布、map_force_update或Thread.wait_to_finish。资源/变体分配释放可能在引擎内部等待，但未获原生栈，不能指定哪一个锁。

后台路径确实另有 `_submit_bake` 第234行 `bake_from_source_geometry_data_async`、`_step_nearby` 第103行 region_set_navigation_mesh、`_publish_full_mesh` 第433行 region_set_navigation_mesh；它们不在上述支持查询调用链。两峰同帧 nav_background仅0.012/0.030ms、publication0.005ms，tiles_remaining在邻帧分别恒136/109。可以说后台工作可能并发存在，不能说已找到前台等待全图导航同步锁。此前 Grok 未给出有效本轮结论，不再重试。
