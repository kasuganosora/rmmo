# 完整材质返回接收链：继续定位（2026-10-28）

接续 `ae142b8a` 和 [module/source-key 记录](axel_shader_module_share_20261028.md)。游戏材质优化仍未结束；用户要求的内容编辑器和当前 3D MCP 适配、优化及保存重开验收是随后必做任务。当前独立原型没有进入正式引擎，不能把候选工作量收益视为加载/low 验收。

## 当前主线程长帧的证据

重新检查 `full_source_key_workload_abba_20261028_01/` 四条普通工作量样本，最大的 reload 帧分别为 111.184、110.969、103.218、115.218 ms，其 Deferred acceptance 为 108.209、107.976、100.081、112.373 ms。同帧其余已记录 Deferred 子项均小于 0.2 ms。前后约 500 ms 的队列快照只有公会 fixed-native job 从 worker 活动转为 ready，models/compiled_hits 各增加 1，direct-template 计数从 0 到 1；这是关联证据，不是精确同帧路径事件。这四条仍为允许外部活动的工作量样本，不能据此宣布稳定耗时或 p95。

为补同帧归因，另跑 `D:/code/rmmo_runtime/review_artifacts/full_native_accept_trace_20261028_01/`。使用同一 GREEN 引擎 SHA `20d25131e638bb6cafa0c285e2cddbf09eb6e7e528ee4f8f22dc566adfd8fde8`、当前源代码、完整材质 fixture manifest `b350e4ded3c3666d4768f7695337fdbb0fc5147423d278a02c94d936a4ff6fbb`，direct-template、module/source-key 开启，worker-prepack 关闭。沿用私有 user/index；OS cache 不受控，存在其他 Blender 活动。诊断显式开启 monitor 和 texture profile，绝不作为普通计时样本。

完整路线、材质功能、fixture、源代码/引擎身份和最终回收检查通过。入口 12.080 s，当前需求完整就绪 39.661 s；这些诊断壁时不能与此前无监控臂直接比较。trace 共 9690 事件、0 丢弃，记录阈值 10000 μs。最大 reload 观察帧位于 135711.652 ms，帧间隔 209.744 ms，独立 Deferred acceptance 202.806 ms；同线程 id=1 的事件如下：

| 同线程区间 | wall ms | 说明 |
| --- | ---: | --- |
| `deferred.accept_template` | 202.399 | 精确 path 为公会逻辑 ID `7824a14b…09fd.glb`，运行不读取 GLB |
| `asset_library.cache_materials` | 141.508 | 接收内部的第一段 |
| `asset_library.cache_dispose` | 60.688 | 随后的第二段 |

两子区间相邻且包含于外层，不能再将三者相加。该 direct 路径没有重新 pack；整个接收窗口没有达到 10 ms 阈值的 `asset.transfer_sync`，这不等于同步总成本为零，也不证明渲染线程空闲。此帧 `process_ms=11.847` 是引擎监控值，不能当作同帧 CPU 时间来否定独立时间戳。

下一步独立细分 `_materials` 遍历、属性列表/读取/身份检查、共享池/属性设置，以及释放前后同步、视觉资源保留、`scene.free` 和清引用。当前优先评估由原私有 worker 只读准备材质使用计划，主线程继续完成共享池选择、必要替换和同步；计划的上限、额外预算、顺序、取消与原纹理释放须先通过测试。提前在 worker 释放节点是另一项生命周期改动，不因计划通过就顺带放行。

## 独立公会细分

`native_texture_seen_guild_20261028_01/direct_breakdown_01/sample_01/` 使用另建的外部诊断项目，原 engine09、同一 staged 公会及已有两实例语义夹具。高频计时仅在副本中累计，结束写报告；仓库、旧夹具和引擎没有改动。源码/引擎身份前后一致，两臂观测相等，0 fixture errors，原 owner/cache 弱引用释放，模拟完整 ledger 归零。

单次 direct helper 总壁时 75.830 ms，其中材质收集 11.541 ms、149 材质；`get_property_list` 累计 34.547 ms，生成 26337 条属性描述，其中 18508 条 storage、2920 条 Object/Variant 被读取。273 次读取为纹理；plain/key/remember 各 60 次，累计 0.167/0.669/0.151 ms；只有 1 次 set（0.011 ms），同步 0.012 ms，seen.clear 0.067 ms。属性 get 累计 1.402 ms。其余约 27.263 ms 包含循环、容器操作和高频计时开销，不能当作已隔离的纯业务 CPU 时间。

direct 接收的第一次 `dispose_scene` 为 19.557 ms：首同步 0.002、保留 2176 个视觉资源引用 6.345、`scene.free` 13.043、末同步 0.016、清引用 0.149 ms。随后两个实例的释放分别 25.644/20.347 ms。上述是独立单次诊断，不是整图 141.508/60.688 ms 的精确拆分，亦不能据此宣称地图同步等待已不存在。

本轮证据优先支持准备阶段的材质/属性遍历和主线程节点销毁，而非继续重复 `_plain_texture` 校验微调或扩大 shader 队列。后台材质计划先作为独立原型验证；主线程弱池和 set 顺序必须保持，释放后旧纹理不能被计划拖延持有。

## 独立 CPU 原型的 TLS 夹具故障

`shader_parse_share_proto_20261028_01/` 首次 `0xC0000374` 不能再笼统标为 re-spirv 或解析共享错误。移除 RESPIRV、registry 和复杂 owner 后，纯 C++ 的 `thread_local std::array<std::vector<…>,5>` 仍可在 MinGW `std::thread`/`std::async` 退出时复现。

`diagnostic_10_tls_watch/debug_attempt_02/stdout.log` 的硬件 watchpoint 抓到 TLS 首指针首次改写：`ucrt free → libgcc emutls_destroy → libwinpthread` 先释放对象存储，随后 C++ TLS 析构再访问该对象。小 host 的优化/静态部分库矩阵有调度敏感性，所有失败保留，不能挑一次成功作为修复。上游也有同类析构顺序讨论：[MinGW TLS 析构](https://sourceforge.net/p/mingw-w64/mailman/mingw-w64-public/thread/2e95f9b2-ec7b-7525-138a-8dc920777c3e%40126.com/)、[GCC 80816](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=80816)；本机结论以实际 watchpoint 为证据，并非只凭上游报告归因。

但引擎不是同一线程入口/链接方式。GREEN 和 engine09 的 PE 导入不含动态 libgcc/libstdc++/winpthread；构建使用 `-static`，Godot Thread 经 `mingw_stdthread` 使用 `_beginthreadex`。`diagnostic_12_native_static/` 用 `-O3 -static -fno-exceptions -fno-rtti` 和该原生入口，小 host 3/3 通过，watchpoint 实际观察先 `Scratch::~Scratch` 后 `emutls_destroy`，而同一 exe 的 std::thread/async 入口仍有失败。现成 MSVC `/MD`、`/MT` 的 thread/async 对照共 12/12 通过。不是通过泄漏、反转析构顺序或删除检查绕过崩溃。

当前构建树 re-spirv 对象符号含 `__emutls_get_address`/`__cxa_thread_atexit`；真实旧全图 GDB `full_map_gate_gdb_on_20261028_01/gdb_stacks.jsonl` seq24 也证明 Godot 后台线程实际进入 `respv::Shader::parse/sort`。这些证明可达性，不证明真实引擎退出发生同样 UAF，更不能据此解释历史无栈 AV。当前构建对象 SHA 也不能冒充旧保存 exe 内的对象身份。

后续独立解析共享原型采用与引擎一致的原生线程宿主，先重跑原完整合同，再决定是否运行 2240-stage 工作量回放。线程宿主修正不等于解析共享已经通过，更不等于游戏崩溃已修复；不改正式引擎或默认安装。

### 原生线程宿主 v3 的验证与反例收益

`shader_parse_share_proto_20261028_01/native_v3/` 已完成同源编译和三个独立进程合同。16 个真实 stage 在默认 specialization、`removeDeadCode=true` 下，旧解析与共享产品的 Optimizer 输出一致；生产捕获数据不再任意改写所有 scalar。另用不涉及数组/循环边界的受控 uint 加法 shader 检查 7/11 两组 specialization，输出不同且各自匹配旧路径，输入和两份输出通过现成 Vulkan SDK 的 `spirv-val`。同键/异键并发、暂停生产者时其他任务继续完成、失败解析、容量/条数回退、丢弃结果和最后 owner 释放均通过。

随后在一次进程内，以固定 2240 段、每 56 个 owner 为一组的合成生命周期执行 ABBA。每个新臂 Parse/compact 从 2240 降到 1806（434 次命中，减少 19.375%），无容量、条数或私有回退。每轮 2240 份解析产品的 17 数组 SHA256 与首轮相同，指纹计算时间单列，不重复调用 Parse；最终共享/私有 live 和 payload 均归零。固定索引仍活着时占 1376688 字节，不把此时 payload=0 称整个 registry 已释放。

但该保守原型**尚没有时间或内存收益**：旧准备累计 2.910/2.520 s，新 2.778/2.922 s。旧产品峰值 44944192 字节，新峰值计入 index 为 51202752 字节；新方还固定原始 decoded 数据并重复比较 raw。它们是按容器容量、对象和控制块估计得到的合成产品成本，不是游戏 RSS；整个回放进程观测到的峰值工作集 245481472 字节又包含了输入数据和 TLS，不能混用。工作量减少可保留研究价值，但不据此并入默认引擎。

下一独立切片核对 inline 成功时解析产品已经自带数据的合同，以及已成功完整解码的 source-key 是否可直接作为身份，去掉不必要的 raw 持有和重复扫描。仍要保留私有回退、强制 hash 碰撞的精确比较、有效 specialization、真实输入寿命和末尾回收测试；尚未接入游戏。

### v4：删除重复 raw 扫描与保留

`shader_parse_share_proto_20261028_01/native_v4/` 仅接受已成功完整解码的 source-key 和全部解码/解析参数；精确比较编码字节，hash 不充当身份。成功 inline 的解析产品自带 `inlinedSpirvWords`，此时将不再使用的 ext 指针/长度归零、解除 raw 保留；non-inline 和不适用输入继续私有回退。三个完整合同和三组官方 SPIR-V 验证通过，包含输入销毁、有效 specialization、并发/暂停生产者、弃置结果、容量回退和最后 owner 在线程上释放。未修改项目或引擎。

相同 2240/window56 的合成 ABBA：旧准备 2.894/2.700 s，新 2.612/2.501 s，均值减少 8.61%；解析/compact 2240→1806，减少 434 次（19.375%）。四臂每次产品指纹一致，且与 v3 一致。新计账峰值 45372360 字节（payload 43995672 + 固定弱索引 1376688），仍比旧 44944192 高 428168 字节；相较 v3 去掉 5830392 字节 raw 保留。原型输入自身仍持有约 169 MB raw，不能声称进程 RSS 降低。四次合成回放不是地图、实际生命周期或 p95 证据。

集成仍须保留引擎解析失败时使用原始 SPIR-V 的行为；解析 owner 必须由每个 ShaderInfo stage 持有，不能依赖可能更早销毁的 VkModule。64 MiB 仅限制共享索引与入表 owner 的估算成本，不包含并发尚未入表产品、私有回退、解码输入或 module registry。满表、局部存活与大量过期弱槽同时出现时，每次只扫 8 槽可能保守地私有回退；不影响结果正确性，须保留此工作量边界，不能为提高命中率在主线程引入长时间全表扫描。

## 后台材质计划接入与真实公会合同

新增 `model_texture_direct_plan.gd`，仅用于已离线证明 direct-safe 的私有 native 读取；整个 direct-template 候选仍默认关闭。派发时冻结计划开关，在原完整模型 reservation 上追加 12 MiB 调度估算；它不是实际 RSS 或已证明的分配上界。worker 沿原材质与属性顺序只读准备，不修改共享纹理池、材质或渲染服务器。主线程提交时才查询当前弱池、必要时替换并同步，之后清空计划及别名。超限回退原路径，取消继续由原 drainer 在完整 lease 内释放。白模和编辑器普通路径未改。

真实 Deferred 红测试只在“新增后台计划应存在”上失败（67/1），最终绿测试 90/0；覆盖两个并发 worker、派发后开关反转、预算、取消计划别名/资源和回退。probe 参数检查 38/0，Python fixture/isolated runner 测试分别 13/0 和 16/0。证据在 `native_texture_plan_20261028_01/`；参数输入错误的早期 probe 启动失败也保留，不计成通过。

`real_guild_plan_01/sample_01/` 的实际公会两臂合同通过，源码/引擎身份稳定、fixture errors=0。生产 worker 计划为 ready：149 materials、273 uses、60 unique textures；准备结束后插入的共享池 seed 在提交时被正确采用。两实例 2319 节点、2276 resources 分类及网格/材质/碰撞快照一致，提交后 packet/保留别名清空，owner/cache 弱引用释放。模拟 ledger 旧 5450944511、新 5463527423 字节，末尾均归零；这不是实际内存测量。

该单次诊断中，worker 准备计划 103.785 ms（线程 33），主线程 `cache_materials` 0.703 ms、`cache_dispose` 20.366 ms；三次同步总共 0.016 ms。准备 trace 3953 事件、cache trace 2 事件，均无丢弃。缓存和宿主未受控，不能跨之前样本外推整图收益。

随后完成 `full_material_plan_workload_abba_20261028_01/` 完整地图同源 ABBA，计划 off/on/on/off，固定 GREEN 引擎、direct-template、module/source-key、同一 fixture 和私有 user/index；不启用高频诊断。四臂功能、实际开关、源码/引擎、fixture 和退出回收全部通过，shader-cache size/mtime 不变。开启两臂各接受 1 份计划、273 uses、0 fallback，关闭两臂均为 0；direct reuse 均 1，compiled miss 均 0。

| 样本 | 入口 / 完整就绪 s | reload 接收峰值 ms | 卸载 max ms / >50 帧 | 返回 max ms / >50 帧 | 重载 max ms / >50 帧 | 返回 / 重载 1% low FPS |
| --- | --- | ---: | --- | --- | --- | --- |
| A1 关闭 | 11.708 / 38.100 | 100.055 | 33.432 / 0 | 50.770 / 1 | 103.107 / 4 | 35.556 / 23.280 |
| B1 开启 | 10.085 / 21.417 | 24.254 | 33.177 / 0 | 67.355 / 1 | 69.246 / 2 | 34.695 / 26.637 |
| B2 开启 | 10.370 / 20.472 | 34.119 | 31.739 / 0 | 54.655 / 1 | 66.388 / 3 | 31.463 / 24.289 |
| A2 关闭 | 10.381 / 21.320 | 102.058 | 45.426 / 0 | 67.074 / 3 | 105.305 / 3 | 30.619 / 24.697 |

接收峰值与帧峰值是独立量：B1 最大接收所在帧为 26.627 ms，并非该臂最大重载帧。B2 接收 34.119 ms 所在帧为 66.388 ms，不能把整个帧的剩余时间归为接收。周期采样 models=47/57/58/56、instances=3157/3205/3178/3181，不当成全程准确工作量。初始最终产物均 211 groups、2316 source objects、3349 source surfaces、2128385 source vertices，输出 359 surfaces / 2075484 vertices。后台计划不再在接收时重建材质和属性列表；该工作转到既有受预算约束的 private worker，仍只有一次池提交和必要同步，不宣称总扫描次数变成零。

本组显式允许外部 Blender 活动，所有慢样本保留；B1 还与本轮审计的两次目录搜索及定向历史 JSON 读取重叠，搜索已停止，准确边界和未记录的时间精度见 `host_external_audit_search.json`。**保留主线程工作转移和同源接收峰值下降的证据，但不以 B1 壁时、四臂均值或 A1 慢值计算整图加速比。加载和整体 low 尚未稳定验收；四条样本不是 p95，缓存审计也不等于物理冷读。**

### A1 加载波动与现存入口大帧

A1 入口→ready 为 26.392 s，旧 source-key B1/B2 为 12.785/11.324 s；入口前公会 native 读取约 4.172/4.053/4.057 s，主要差异在入口后。ready 前 fixed-native jobs/models 均 23、instances 均 1514，A1 累计 worker wall 为 105.164 s、旧 B1/B2 为 38.347/33.039 s；多线程壁时重叠并包含等待，不能当作 CPU 或相加到地图时间。A1 29.84/32.85/35.85 s 均有三个活跃 worker、ready=0，37.9 s 才观察到 jobs=0；不支持把此尾段主要解释为已完成结果堵在发布槽。

A1 初始完整就绪前 prepared_source_visits=34329、sync=11、rebuild=243；其余本轮三臂均 6396、2、213，最终产物一致。准备重复与慢生产互相交织，现有轻量数据不能证明因果方向。A1 两条约 1322/658 ms 帧，geometry tick 分别 1276/627 ms，内部 Stream.sync 分别 1273/623 ms；结束 cursor/jobs 为 4/49 与 5/56。相关时段 host 观察到活跃 Blender，但没有磁盘、GPU 或锁占用量化，不能只归咎宿主。

复用此前已完成的 `full_native_accept_trace_20261028_01/sample/sample.json`，可补另一进程同类长帧的内部归因，不重复跑图：最大 geometry tick 2042.379 ms，内部 sync 2037.086 ms，结束 cursor4/jobs41。主线程同一窗口先 `mesh.gpu_restore_total` 1600.641 ms（8 surfaces），再相隔 277 μs 的 `shadow.build` 433.850 ms（obj_1020，bind_2 为432.571 ms）。两区间不重叠，共2034.491 ms；restore 中 surface4/5/7 的实际材质提交为460.105/689.015/449.810 ms，几何分别0.295/0.168/0.063 ms。下一 geometry tick 666.002 ms 中，三表面网格 restore659.396 ms、surface0材质提交658.050 ms。第三条297.638 ms tick的 shadow.build 为290.860 ms。不能把另一次进程的 RID/UUID 或壁时直接当成 A1 的精确证据，也不能仅凭 material 标签判定编译、锁还是 I/O。

因此接下来仍优先真实材质首次提交和阴影绑定；解析共享是已独立验证的候选，须经真实引擎合同和 GDB/普通地图对照后再决定。后台计划之后的 `cache_dispose` 也保留下一候选：证明同一原始 native PackedScene 已持有全部视觉资源后，只省略重复收集，仍在主线程 free 并保留前后同步。

另有独立流程缺口：`world_stream._finish_loading_sources(...,0,false)` 在交互路径可无截止时间地恢复全部待处理源；现有测试甚至要求准备未完就恢复，未覆盖多源预算。修复必须让剩余 obligation 与 stream_chunk/ready 一起跨帧推进，保留 budget=0 的同步编辑器合同。但上述大帧 cursor 明显未到 jobs 末尾，full 阶段 checkpoint 又未启用，不能把这一潜在缺陷冒充已观察长帧根因。full-material 的增量合批同样不能直接取消白模开关：运行时材质、可见性和编辑失效合同须先验证。


## GREEN 定向 GDB：同一帧的材质与阴影

`D:/code/rmmo_runtime/review_artifacts/full_native_green_targeted_gdb_20261028_01/sample_01/` 是起始需求区域的诊断，而不是正常耗时样本。GREEN 可执行文件 SHA `20d25131e638bb6cafa0c285e2cddbf09eb6e7e528ee4f8f22dc566adfd8fde8`，调试符号 SHA `6aec02bb3d434fa83b12b1579d8205b64651ac7d59248e871e7d4c08d08ac833`；full fixture manifest SHA `b350e4ded3c3666d4768f7695337fdbb0fc5147423d278a02c94d936a4ff6fbb`。源码、引擎、符号、私有用户设置与 fixture 前后核对一致，脚本和 probe 均无错误。实际 controls 为 full-material、direct template 和 material plan 开启，worker-prepack 关闭；module/source-key 开启。诊断 overlay 仅在 MapLoader 前添加文件 gate，并给现有心跳添加需求收尾阶段标记；其余项目源码与冻结仓库逐文件一致。GDB 的 Vulkan/rendering 修改文件按 GREEN 已存档源码映射，未归档的引擎文件没有逐文件身份保证。

collector 在 gate 前装载符号，核验 owned PID 及创建时间后附加，只在较长的上传或 geometry 调用中最多暂停三次，并抓取主线程和其他线程。三次 all-stop 暂停约 **12.732、4.612、4.226 秒**，因此本次 66.015 秒 ready、任何被暂停覆盖的 Trace 耗时都不能用于性能比较。

- 第一次主线程停在 `GodotConcavePolygonShape3D::_fill_bvh` 链；后台多个线程同时可见 `FileAccessWindows::get_buffer → FileAccessCompressed::get_buffer → ResourceLoaderBinary::parse_variant`。
- 第二次落在 frame 4261 的 `obj_1020` CPU mesh 恢复内，surface 4 的材质提交区间及 `mesh.gpu_restore_total` 内；主线程栈为 `ArrayMesh::surface_set_material → BaseMaterial3D::_update_shader → shader_create_from_code → ShaderRD::_load_from_cache → FileAccessWindows::open_internal → CreateFileW`。
- 第三次同在 frame 4261，心跳显示上一个 upload 已结束；时间戳落入该对象后续 `shadow.build` 的 `bind_2` 子段，主线程也在上述 shader-cache 文件打开调用链中。这是两个先后执行的区间，不能合并成一次调用；进程内帧号、CPU ID 与事件时间是同次证据，不能与别次进程的 RID 直接对应。

某些后台线程也出现在原生资源读取或 shader-cache 读取栈。栈是瞬间位置，不能证明打开的具体路径、文件读取耗时、锁主或发生磁盘争用；也不能仅凭两次 CreateFileW 栈把整帧归因于磁盘。LoadTrace 记录 3704 个事件、0 丢弃；心跳接收序列未观察到缺号，但内存留存超过上限后有 **10010 条未保存**，尾部原始心跳不完整。采样期间的原始栈、MI 日志、状态、启动控制和身份见上述目录的 `collector/`、`sample.json`、`status.json`。

## 旧 engine09 文件 trace 的 open/read 口径补正

重新读取 `D:/code/rmmo_runtime/review_artifacts/full_shader_file_trace_origin_20261028_01/engine_file_trace.tsv`。文件共 9101 条、无格式错误；该 run LoadTrace 为 3734 事件、0 丢弃。`O` 行实际为十列 `kind, begin, end, thread, read_us, reads, bytes, length, open_cost_us, path`，旧分析未单独统计第九列（从 0 开始的索引 8）`open_cost_us`。以下使用同一主线程，材质真实区间 `[end_us - material_us, end_us]`，而不是把整个 surface 区间都当材质；各匹配的文件从打开到关闭前记录的完整生命周期均包含在对应区间内。

| 同次区间 | 区间 ms | shader-cache 文件数 | open 合计 ms | fread/check 合计 ms |
| --- | ---: | ---: | ---: | ---: |
| frame 3215 surface 4 材质 | 115.137 | 2 | 0.685 | 0.571 |
| frame 3215 surface 5 材质 | 151.313 | 2 | 0.681 | 0.476 |
| frame 3215 surface 7 材质 | 199.871 | 2 | 0.891 | 0.804 |
| `obj_1020` shadow.build | 67.373 | 2 | 0.987 | 17.813 |

这一旧样本中三个材质区间各自的 open 加读取小于 1.7 ms；阴影的两个读取分别为 11.075 和 6.738 ms，不能将“读取都很低”泛化到阴影。其余时间仍未由这组文件 trace 细分，包含其他工作及诊断开销。`open_cost_us` 从 `FileAccessWindows::open_internal` 开始，到 `_wfsopen` 返回，包含合法性判断、旧文件 `_close`、`fix_path`、`GetFileAttributesW`、符合条件时工具版大小写查找/缓存锁，以及 `_wfsopen`；不是单独的 `CreateFileW` 或磁盘时间。`read_us` 是该文件生命周期内 `fread` 与错误检查累计，open→close 的墙钟也不能当作读盘时间。

这些数值仅属于旧 engine09 的独立诊断与当时私有 user 缓存；当前私有 APPDATA 在 D 盘 HDD，正式默认 user 路径可能在 C 盘 SSD。不得把旧样本数值外推到上面的 GREEN GDB 栈、正式游戏或其他机器。

## 真实公会 owner 释放及 Deferred 接入

四次隔离夹具和全部失败保留在 `D:/code/rmmo_runtime/review_artifacts/native_owner_dispose_guild_20261028_01/` 至 `_04/`：

1. `_01` 两臂在 600 帧后 owner/cache 与 2012 个视觉资源仍存活，检查失败；尚无证据确定原因，独立弱引用小测的通过不能反推此失败原因。
2. `_02` 仅等待 owner/cache 释放后即检查视觉资源（35/23 帧），此时 scene retirement phase 1 尚在处理、资源和模拟 lease 仍被合法保留；这次观察过早，不能称为 600 帧永久滞留。
3. `_03` 改为等待 visual 与 retirement queue 后，两臂 77/81 帧均释放并令模拟 lease 归零；GPU 语义相同且无 fixture errors，但 runner 因报告缺少四个实际过程字段而失败，不能记为完整通过。
4. `_04` 补全实际过程字段后，runner/身份/语义/覆盖和回收检查通过。两臂覆盖 2176 个视觉资源引用、2012 个唯一资源；81/75 帧时 visual 存活数、retirement queue 和模拟 lease 均为 0，owner/cache 弱引用已释放。两实例的材质、网格与碰撞快照一致。帧数是该夹具的观察，不是帧耗时或整图收益。

真实 Deferred 接入合同 `D:/code/rmmo_runtime/review_artifacts/native_owner_dispose_integration_20261028_01/sample_01/` 已通过 **98/0**，对应实现与测试已按逐字节身份接入仓库；需保留 `gpu.log`、`result.json` 和身份快照作证据。该切片的真实整图加载、卸载和返回重载复测仍待执行，不把夹具通过等同于整图性能验收。

### owner 释放接入后的正常整图复测

随后 `D:/code/rmmo_runtime/review_artifacts/full_native_owner_disposal_20261028_01/` 完成普通完整纹理路径：固定 GREEN、direct template/material plan/module/source-key 开启，prepack/unlocked 关闭；没有 profiler/GDB 或高频 trace。代码、引擎、设置和 fixture 前后身份一致，功能与真实退出回收通过，errors/failures 均为 0。实际 direct reuse=1、material plan=1、uses=273、fallback=0；compiled miss=0。测试名称仍有 `white_*` 历史标签，实际 controls 为 full-material，不能与旧白模样本混用。

| 指标 | 本次普通样本 |
| --- | ---: |
| MapLoader → 入口 / 当前需求完整就绪 | 11.911 / 25.794 s |
| 卸载最大帧 / >50 ms 帧数 | 31.965 ms / 0 |
| 返回最大帧 / >50 ms 帧数 / 1% low | 77.293 ms / 2 / 29.518 FPS |
| 重载最大帧 / >50 ms 帧数 / 1% low | 63.957 ms / 6 / 21.938 FPS |
| 重载接收峰值 / 所在整帧 | 33.357 / 63.957 ms |

初始最终合批仍为 211 groups、2316 sources、3349 surfaces、2128385 vertices；输出 359 surfaces / 2075484 vertices，prepared visits=6396、packed visits=2634、rebuild=213、sync=2。实际遍历发生 257 crossings、4499 removals、4429 reloads；周期采样 models=51/instances=3147 不是精确全程工作量。module footer 的 live/retained 为零。

本次有外部 Blender 活动且只有一个样本，不是冷启动、ABBA 或 p95；不能把与旧样本的时间差归因为本改动。独立合同证明可省略 2176 个视觉资源引用的重复收集，同时保留主线程 free 和前后两次同步；整图证明这一接入功能成立，**尚未证明相较后台材质计划单独开启时有进一步帧时或总加载收益**。保留工作量收益，不宣称材质阶段稳定或完成。后续优先对照真实材质首次提交与 shader 解析共享的关键路径收益，内容编辑器及当前 3D MCP 的适配仍在游戏材质优化之后执行。
