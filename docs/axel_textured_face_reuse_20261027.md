# 纹理阶段几何面复用与卸载呈现栈（2026-10-27）

接续主日志 §174。分支 `codex/latest-map-runtime-review`，计时仍为地图加载开始到
当前需求完整就绪；不把进程启动、entry 或第一次呈现混为同一边界。地图/prefab 纹理
开启，导入模型仍为无材质 native，尚不是完整游戏全部材质验收。本轮没有修改引擎、
模型资源、预算、worker 数量或需求范围。

证据目录（下文 Y）：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/origin_critical_path_20261027/`
引擎为 engine09，EXE SHA：
`40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`；
symbols SHA：`3039c3ba7fbb71f965ec42cb9100a483a439e95b6cfda3ed194cfae54989db76`。

## 从实际调用量选取工作

`origin_official02` 使用官方脚本/server/visual profiler 和引擎 native callers。
客户端、接收端及解码均退出 0，errors/failures 为空，源码/地图不变。它是诊断，
不并入普通加载时间、p95 或 low 数据。全局 profiler 包含后台函数，不能把其累计
耗时当作主线程独占时间，也不能相加推算完整加载节省。

入口后 `white_stream_origin` 的主要观察：

| 调用 | 次数 | profiler 累计 total ms | 所在链路 |
| --- | ---: | ---: | --- |
| `PrefabFaceArrays.build` | 1442 | 2417.942 | 后台索引三角面展开 |
| `House._decode_uncached` | 382 | 2494.016 | 后台解码；含 base64 1150.033ms |
| `Deferred._publish_ready` | 427 | 4083.685 | 主线程发布，含下游操作 |
| `House.tickets_valid` | 4391 | 400.004 | 发布与交接的材质代际检查 |
| `House._texture_scope_current` | 2932 | 389.540 | 分片材质 scope 恢复 |

官方 native caller 仍观察到真实 `surface_set_material`：该阶段 2005 次累计
515.042ms，一帧内最大 296.507ms。这是带 profiler 的观察，不冒称普通路径长帧。
这轮先处理已证实重复的几何准备，没有用增加 worker 或放大队列替代去重。

## 实现和复现出的正确性缺口

`House.raw_face_reuse_active` 原来同时要求 white_materials 和 discard_map_textures，
所以纹理阶段即使引用相同 prefab，也重复展开三角面。现在将既有的共享机制应用到
可信资源包的纹理模式。三角面与材质投影无关，纹理消费者仍取全部 mesh slots。

没有扩大缓存：仍为原 512MiB decode ceiling、按 digest 合并同时进行的工作、只读
容器和私有 PackedArray 输出；任务准入扣除同一个上限。元数据查询仍不展开面。
白模 source-only 与 binary prefab cache 的白模限制没有放宽，材质定义未替换。
缓存退出不破坏已准入任务，地图退出时继续走既有后台回收。

新回归先在旧实现复现：白模 source-only 请求可留下只有 collider 的部分面数组。
后续纹理请求只判断 `collision_faces` 是否存在，会把缺失 render slot 当作已经准备。
即使关闭 raw face reuse，这个错误也存在。现在逐 slot 检查 coverage，缺失的必要面
必须正常构建；full binary 产品无 coverage 字段时仍按其完整产品合同处理。

新增 `reference_prefab_faces_canonical_slots` 区分来自 canonical 的输出。
这个计数包括首次创建后取用，**不等于实际避免的展开次数**；真正减少的次数另用
官方 profiler 对照，避免拿 cache 命中输出数夸大去重。

## 独立测试

`tools/test_textured_prefab_face_reuse.gd` 用真实纹理模式开关、两份各 120000 个索引面
顶点和有色材质，覆盖四个并发任务只执行一次共享升级、完整 slot、输出私有性、
canonical 退出后输出存活、白模到纹理升级、关闭复用时缺失 slot 补齐，以及512MiB
预算预留。GPU 模式检查实际上传 channels 与有色材质，并不只检查 CPU 长度。

| 证据 | 结果 |
| --- | --- |
| face03_before | 18 条通过、7 条预期失败，无脚本错误 |
| face04_before（补关闭复用的缺面断言） | 18 条通过、8 条预期失败，无脚本错误 |
| face05_after | 新用例 26；raw_reuse 14；selected_faces 24；shadow_faces 34，全通过 |
| face06_gpu | 新用例 29；prepared_collision_faces 67，全通过 |
| face07_regression | geometry_identity 36；decode_lock_scope 9；face_preparation_work 8，全通过 |

固定 12 次 × 240000 面顶点的 CPU ABBA：旧 200.861 / 161.500ms，新 13.728 /
15.416ms；全部三角面顺序和材质字节一致。它说明重复相同数据时的工作收益，不能
直接折算成整图秒数或 FPS。所有夹具在外部临时目录，不改用户地图。

修改后再跑同配置官方 `origin_official15`，退出/解码均 0，errors/failures 为空、
源码和地图不变。相同阶段 face build **1442 → 758 次（少 684 次，47.4%）**；
解码仍 382 次。带 profiler 的 face 累计 2417.942 → 2155.380ms，仅作诊断。
`official17_face_comparison.json` 保留全部选择字段。全程次数 1446 → 763 与上面的
阶段次数不同，不混用。保留本改动的依据是正确性修复及实际工作量减少，并非已证明
整图稳定变快。

## 普通整图 ABBA

map10 使用正常优先级、新进程和私有桌面，不清 OS 缓存，无 GDB/官方 profiler/
timeline；不能称为严格冷 IO。A 关闭 raw face reuse，B 开启，其余相同。
后台 GPU 上传和完整建筑提前通知候选均关闭，§174 增量退出及末端纹理交接去重开启。

四条退出 0、functional_ok=true、errors/failures 为空、源码/地图不变。测量时796个
源文件 SHA 全部一致，并保存在 `map10_sources/`。原始分析为
`analysis11_summary.json`、`analysis11_peaks.json`、`verification12.json` 和
`faces13_summary.json`。

| 样本 | entry s | 完整就绪 s | 返回 1% low FPS | 重载 1% low FPS | 卸载/返回/重载 max ms |
| --- | ---: | ---: | ---: | ---: | --- |
| A1 旧 | 4.008971 | 9.943152 | 42.984 | 32.415 | 43.802 / 49.700 / 45.343 |
| B1 新 | 4.484028 | 10.955306 | 37.446 | 36.367 | 33.807 / 42.102 / 43.920 |
| B2 新 | 4.095683 | 10.212411 | 40.231 | 36.103 | 26.518 / 41.728 / 36.922 |
| A2 旧 | 4.268029 | 12.725417 | 29.467 | 34.209 | 35.508 / 48.681 / 39.710 |

所列卸载、返回、重载区间均 0 帧 >50ms。不能因此宣布所有加载/呈现/释放尖峰解决。
没有证明加载与 low 一致改善；两条新样本也仍 >10s，不以 A2 慢样本计算加速百分比。
A2 在 `white_origin_demand_settle` 才就绪，没有删掉超出固定 origin 窗口的收尾。

四条初始均 231 builds、3923 prepares、2724 packs、1442 面 slots、9731922 面顶点；
全程面输出均 2884 slots / 19463844 顶点。B 初始/全程 canonical slots 为1442/2884，
A 为0；实际去重次数见官方对照。B 的共享缓存仍从任务预算预留536870912字节，
不能宣称这部分复用没有内存成本。

初始主线程 covered service 累计（A1/B1/B2）3.641/3.811/3.736s，其中 publication
2.801/2.961/2.881s。它们包含与并行后台重叠的工作，不是能直接相加的阶段。
普通帧拆分只读取 interactive budget，cover 下显示0并不代表 cover 没有发布工作。

B1 实际命中上一轮增量退出重整，`retirement_prepares_avoided=816`；这是本轮首次
捕获该真实时序下的非零避免计数，不算本轮 face cache 的收益。其全程 prepare7859，
其余7851；动态路线不能用最终数量差额反推出每次退出的固定成本。

GPU 审计四条均3943 surfaces、3202 nonwhite、1502 textured、145 unique textures。
shared produced均146，最终 outputs/consumers/retained_bytes=0。map_freed=true，
worker、admission、资源回收队列、模板和临时加载渲染上下文均归零。
这是运行时数据与 GPU channels 回归，不是完整美术镜头验收。

host 1Hz 记录：A1 未观察到其他相关 Godot/Blender/编译/GDB 进程；B1、B2、A2 的
加载及若干游玩阶段有 Blender。仅记录进程存在，不直接归咎于它，也不据此排除样本。

## 卸载长间隔的原生现场

`unload08` 使用 GDB18.1 和 engine09。新增只在显式
`--frame-heartbeat-empty-unload` 下启用的 phase6 POST_DRAW 心跳；空场景高 FPS
每帧只发送一个64字节包，普通样本不启用。PID、进程创建时刻、EXE、主线程身份均
校验。只添加并归还本轮拥有的一个 SuspendThread 计数，有独立超时释放；没有调用
inferior 函数、修改优先级/QoS 或停止其他进程。

触发的最后 POST_DRAW 为相对60784.951ms，engine frame16009。冻结后再次清空已
到达 UDP 包，marker_current=true、sequence_gaps=0；GetThreadContext 的 RIP 与
GDB 一致。接收至冻结窗口32.3307ms、主线程 CPU 增量15.625ms（Windows粗粒度）；
触发至 context 0.5059ms。旧字段 local_gap_ms=47.4401 包含冻结后的处理，不能当成
冻结前停顿；GDB 介入后的长帧也不计普通性能。

实际栈是 `RenderingServerDefault::_draw → RenderingDevice::swap_buffers →
command_queue_execute_and_present → QueuePresentKHR → we-graphics-hook64 →
AMD IcdPresentBuffers → DXGI → RtlCaptureStackBackTrace`。
本地引擎源文件3322行确为已取得 submit_mutex 之后的 QueuePresentKHR 调用，
**该冻结时刻不是在等这把上传/提交锁，也不在释放资源或执行脚本**。
RenderingServer `create_thread=false`，这里主线程承担渲染提交。

相邻队列 demand/jobs/stream jobs/batch pending/draw 都为空；它们是相邻观测，不
冒称冻结瞬间的原子快照。完整上下文见 `unload08_context13.json`，冻结与归还证据见
`.trigger.json`、`.frozen.json`、`.release.json`、`.gdb.log`，引擎/GDB退出均0。

捕获 DLL 出现在栈上不等于它导致停顿。此处抓到的是新的约32ms呈现现场，不能
直接解释§174特定54.718ms process间隔或§173约100ms间隔，更没有解决旧无栈AV。
本地 implicit-layer manifest 的 disable_environment 为
`DISABLE_VULKAN_OBS_CAPTURE=1`；只在后续独立测试的子进程环境中使用，不改注册表
或全局环境，不禁用用户的捕获功能。

第一次独立隔离 `empty14` 未成立：A1运行通过，但B1虽然启动器设置了禁用变量，
引擎内实际读取为空、DLL仍在，runner按预期中止，不能算有效A/B。继续核对发现本地
引擎 `main.cpp:2160–2192` 在非editor/project-manager启动时主动清除包括该变量
在内的overlay禁用变量。单独用同一私有桌面runner启动Python子进程验证环境传递
正常，不能把这个问题错修到runner；也不能声称B1已关闭捕获层。

后续 `empty18` 使用仅对子进程设置的 `VK_LOADER_LAYERS_DISABLE=VK_LAYER_WEOBS_HOOK`，
配合 `VK_LOADER_DEBUG=layer`，核对实际layer链和DLL，而不只是检查命令行。机制依据
[Khronos loader调试说明](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderDebugging.md)
及[指定层过滤说明](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderLayerInterface.md#layer-filtering)。
没有修改引擎overlay策略，也没有全局关闭用户捕获功能。

`empty18` 四条正常退出，全部1440×900、Forward+ / Vulkan / RX7900XTX，MSAA/TAA
与项目设置一致，只有Camera的空场景，draw calls=0。预热5s后采30s，预分配数值
缓冲记录post-draw间隔，模块检查只在预热阶段执行。A确实插入instance/device
WEOBS层且DLL存在；B日志明确强制过滤、DLL缺席，引擎内变量值也正确。

| 样本 | capture层 | 帧数 | max ms | p95帧 ms | 1% low FPS | >50ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| A1 | 开 | 32745 | 16.999 | 1.681 | 288.249 | 0 |
| B1 | 关 | 31736 | 16.942 | 1.874 | 211.024 | 0 |
| B2 | 关 | 32356 | 7.716 | 1.821 | 253.959 | 0 |
| A2 | 开 | 32251 | 18.056 | 1.994 | 218.585 | 0 |

最大draw墙时依次16.974/16.928/7.694/18.007ms，process墙时最大均<0.5ms。
这是有效的层隔离，但**没有复现地图卸载的50–100ms尖峰，没有证明捕获层导致它**。
不采用全局禁用作为性能修复；空场景也不能代替实际地图退出/返回。失败的empty14
和有效empty18均保留。`closure19.json`确认8个普通地图/empty18自有进程已结束、
796个测量源文件仍一致；官方/GDB进程另由各自result记录正常退出。

## 下一条关键路径

- 主线程发布仍约2.8–3.0s累计，继续按实际调用链去重，而不是用后台累计时间解释全部
  入口后收尾。`MaterialPublication.step_prepared` 返回 READY 后，紧接着
  `House.publish_prepared` 又开启/检查/恢复同一 texture scope；应先在测试中证明
  同一个同步调用内可以复用，再合并最终一步。跨帧、回调换代及失效检查必须保留。
- 空场景层隔离未复现地图尖峰。后续若再遇实际地图长间隔，应对准该时刻抓栈；
  不再以仅出现capture DLL就优先改引擎同步或推给OS。
- 真实材质首次提交、首次3D呈现、独立纹理释放58–77ms和旧AV仍不在本轮修复范围。
- 目标保持 active。本轮保留有实际调用量证据的优化，不宣布加载稳定 <10s，也不
  宣布已经没有进一步优化空间。
