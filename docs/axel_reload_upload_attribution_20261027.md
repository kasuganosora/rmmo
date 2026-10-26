# 返回重载：区分网格自身上传、后台命令积压与观测开销

## 结论与边界

本轮是定位进展，不是新的整图性能修复。§169 的普通样本 B2 曾出现重载
52.691ms 帧、geometry tick 35.356ms；道路 restore 27.377ms 和 Cpu surface
24.721ms 缺少时间戳，不能证明是同一调用。这项未关闭。

独立固定工作量压测已证实一种机制：后台逐面 ArrayMesh 上传排入 RenderingServer
命令队列，主线程下一次创建小网格时先清空该队列。它可以同时执行仍在进入队列的
工作。3/12 worker 的总工作均为 4096 次，主线程仍会被拖住 250–360ms。
原生整包创建的对照显著缩短此等待，原始/native GPU 数据及 AABB 完全一致。

但实际 native SCN 读取已经走整包创建。真实地图的现场没有证明这条后台逐面上传链
是原来的偶发长帧来源，不能据独立压测修改全局命令队列顺序、删同步或宣称修复地图。
本轮未改引擎、工作线程数量、队列容量、生产预算或资源。目标继续 active。

## 诊断实现

- `ground_cpu_mesh.gd` 的既有慢 surface profile 增加绝对起止 ticks、CPU instance
  ID 与帧号；保持既有 >=10ms 过滤。
- `prepared_cpu_upload.gd` 记录 >=1ms restore 的起止 ticks、CPU ID、UUID、顶点数
  和 prepared / ordinary 路由。既有 source generation、材质一致性、一次性 packet
  消费与复用语义不变。可选 scope callback 仅在 profile_enabled 下使用，正式游戏
  不设置 callback；不是生产调度器。
- `profile_axel_waits.gd` 可用 heartbeat 8/9 标记实际 Upload.restore 的范围。
  原 GEOMETRY_BEGIN/END 包住整段 probe tick，包含成员统计，不足以定位 GPU 提交。
  callback 在完整退出时清除。UDP 时间计入诊断样本，不当作无侵入测量。
- `run_axel_texture_phase.py --profile-procedural-uploads` 在保存 launch 前接入参数，
  正确标记 diagnostic。无此参数的普通运行保持原行为。

Cpu/Upload 的 at_us 为绝对 ticks；与地图数据对齐需减 begin_ticks_us。
frame_split 的 at_ms 已相对地图开始，不再额外加/减该起点。

## 独立复现与 GDB

`tools/stress_road_upload_contention.gd` 只读 axel_town 的
`pavement_1e991a89db78392fc875`，通过 MapResourceStore 解码引用。
使用 authored road 的原始、尚未 paint 的 4 个 surface，顶点数
168 / 168 / 912 / 1440，均无索引。这不是旧慢日志中 1080/1080 surface 的精确复现。

worker 私有持有最多 16 个 Mesh，ticket 总数固定 4096，3 与 12 worker 不增加总量；
输入数组只读。主线程每帧恢复同样网格并显示共享 unshaded 材质。0/3/12/0 worker
顺序、640×480、60 FPS、关闭 VSync。最少 60 帧，任务未完成时有最多 300 帧的观察，
之后停止接活并等待 worker 终止后 join。完成数必须为 4096，不能通过取消少做工作。

`stress04_gdb`、有效冻结 `stress07_frozen` 的主线程栈：

```text
RenderingDevice buffer initialization / VMA allocation
RendererRD::MeshStorage::mesh_add_surface
CommandQueueMT::_flush / flush_if_pending
RenderingServerDefault::mesh_set_blend_shape_mode
ArrayMesh::_create_if_empty / add_surface / add_surface_from_arrays
ground_cpu_mesh.gd::restore
prepared_cpu_upload.gd::restore
stress_road_upload_contention.gd::run
```

同时 worker 栈在 RenderingServer::mesh_create_surface_data_from_arrays 和相同 fixture
的 worker 方法。create_thread=false：主线程也是此 backend 的渲染 server 线程。
这里是主线程替队列执行工作，不能统称为“等待后台上传锁”。不同瞬间可能在
分配、拷贝、Vulkan transfer fence 等具体步骤。

源码依据（engine09 对应本地源）：

- `servers/server_wrap_mt_common.h` / `rendering_server_default.h`：逐面 mesh_add_surface
  等 generic wrapper 从 worker 调用时 push；server 线程调用时先 flush_if_pending。
- `core/templates/command_queue_mt.h::_flush`：循环边界读取动态 command_mem.size，
  执行 command 时解锁，因此 producer 可继续追加。
- `ArrayMesh::_set_surfaces` 首次创建走 mesh_create_from_surfaces；支持 async resource
  creation 时可直接在调用线程创建，而非把每个 surface 都压入主线程命令队列。
  已有 RID 的修改走另一分支，不能将本结论推广到任意 Mesh 编辑。

### 固定工作量 ABBA（stress13）

A：worker ArrayMesh.add_surface_from_arrays；B：同样数组每次 CPU pack 后通过新
ArrayMesh._surfaces 整包创建。两边均在计时前执行相同原生字节/AABB oracle。
不在 worker 内 GPU readback，不通过持久缓存或预打包减少 4096 次工作。

| 样本 | worker | 完成 Mesh 数 | 主线程 restore max ms | 观察帧 max ms |
| --- | ---: | ---: | ---: | ---: |
| A1 | 3 | 4096 | 257.168 | 259.571 |
| B1 | 3 | 4096 | 2.626 | 16.969 |
| B2 | 3 | 4096 | 2.234 | 16.949 |
| A2 | 3 | 4096 | 249.694 | 252.105 |
| A1 | 12 | 4096 | 355.155 | 358.607 |
| B1 | 12 | 4096 | 18.931 | 33.005 |
| B2 | 12 | 4096 | 8.297 | 18.228 |
| A2 | 12 | 4096 | 359.885 | 363.740 |

四次均正常退出、failures=0、源码/fixture/地图未变。零 worker 首次绘制仍有
264.602–280.420ms 峰值，完整保留；它不是本表的并行上传阶段，也没有被本对照解决。
末尾零 worker 最大帧 17.012–17.148ms。总样本受最少 60 帧/60 FPS 限制，不能用其
约 1 秒下限推断真实地图吞吐。worker 的累计 wall time 也不是工作量或 CPU 时间。
本轮没有把 bulk 路径接入任何新的生产 worker。

## 真实地图与证据纪律

所有地图样本仍为 map/prefab 纹理阶段、导入模型白材质，不能称全材质游戏。
native/index/texture 产品缓存保留，geometry cache disabled，OS cache untouched；
不是物理冷盘。以下均 diagnostic，不能混入普通 p95 或 FPS 对比。

1. `map01_uploads` 功能检查通过，往返未出现 >=10ms surface 上传。
   当时 wrapper 在 runner 保存 launch 之后才追加 profiling 参数，launch 的
   diagnostic=false/command 缺参数；host-meta 的 diagnostic=true 和 wrapper 源保留。
   不改写历史证据，明确剔除普通性能样本；随后已修 runner 参数入口。
2. `map03_gdb` 在 geometry 心跳停顿后触发，但主线程栈已到其他 GDScript 方法；
   未冻结现场，不能声称捕获了目标 upload。
3. `stress06_frozen` 读取栈超过 5 秒 suspension guardian 时限；本机暂停计数已归还，
   engine 正常退出，但 gdb_exit=1 / freeze_valid=false，按无效冻结样本保留。
4. `stress07_frozen` 调整为 GDB 先验证暂停前保存的 RIP，立即归还本机一个暂停计数，
   再在 GDB all-stop 下解码栈。engine/GDB 均 0，freeze_valid=true；归还时 count=2，
   只归还自有一个，GDB 继续持有调试停止。不使用 inferior calls、优先级或 QoS 改动。
5. `map08_frozen` 同样通过 RIP/计数验证，零 heartbeat sequence gap。现场是
   Dictionary.has → profile_axel_white_streaming.track_membership，不是 mesh upload。
   只能说明采样瞬间在统计方法，不能把此前整个 18.292ms 心跳区间都归到该方法，
   也不能据此排除其他未复现的生产尖峰。功能、源码、地图和退出检查通过。
6. `map12_upload` 改用阶段 8/9，仅监听返回/重载的实际 Upload.restore。engine/GDB
   均正常结束、功能检查通过，没有达到 10ms 触发条件，未抓到栈。返回后记录最大
   restore 9.338ms（fort baked_55），无 >=10ms Cpu surface；不称原尖峰已修复。
   heartbeat 84758 次，发送累计 2.953s、max1.509ms，全程含高 FPS 空地图阶段；
   这是明确的诊断成本，不能拿此运行的总加载/low 作普通验收。

本轮没有新的普通整图对照。最近普通最终样本仍为 §169 的 map20_default：
完整就绪 9.240915s，卸载/返回/重载 max49.001/31.862/43.763ms，各 0 帧 >50ms，
重载 1% low28.770 FPS。这些旧数字不是当前诊断补丁后的新测量。

## 回归、证据位置与下一步

`regression14_upload` 保留旧 GPU 测试解析失败：测试还按旧接口只给 _spawn 一个
Dictionary，正式接口已要求 map_root、spec 两个参数。只修测试调用；随后
`regression15_upload` 49 PASS / 0 FAIL、engine_exit=0，包含 native bytes、LOD、
材质投影、共享 GPU 复用、失效、预算上限、取消和资源回收。不是生产性能修复。

证据根目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/reload_upload_20261027/`

- `stress13_*.launch.json/result.json/fixture.gd/json/log`、`stress13_summary.json`。
- `stress07_stacks.json`、`map08_stacks.json` 及对应 gdb.log、frozen、release、trigger。
- `run_gdb05_frozen.py`、`run_gdb07_frozen_fixture.py`、`run_gdb11_upload.py`，依赖
  上一级性能证据树的 `gdb166_frame_watchdog.py` 中 OwnedTarget/SuspendLease。
  不运行旧 draft 的主程序。`run_upload_compare.py` 记录每份 fixture 源码/SHA。
- `stress09_before.gd` 是 stress02/04/06/07 时的 fixture 快照，SHA
  `5a25a27686b32cabba66c86a1861964fb882048271132622df544d0a7e7bbf21`。
- engine09 SHA `40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`，
  GDB 为 `D:/tools/gdb-18.1-isolated/mingw64/bin/gdb.exe`，全部 GPU 运行使用
  `tools/run_godot_background.py` 的不激活独立桌面。

下一步回到 §169 已证明的持续绘制压力：逐栋准备目前仍等 WorldStream 的当前源队列
收尾后才收到 request。应先在现有交错到达测试中复现“完整栋已可见但其他碰撞/源阻塞
通知”，再以索引闭包和源到达事件提前接入。不能恢复定时/按数量发布未完整建筑的旧
checkpoint；须仍是 64 组/64 builds、每源 prepare/pack 一次，保留编辑/移除/返回代际。
旧 native AV 门控、首个 3D 帧及首次材质提交边界继续保留，不因本轮诊断成功而关闭。
