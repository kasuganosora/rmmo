# Axel 纹理头部读取异步化（2026-10-26）

接续 `axel_batch_tail_respv_20261025.md`，基线提交 `662800e3`。
目标仍为完整加载和 low 帧；本切片处理首次纹理元数据读取挡住主线程派发。
不变更源纹理、模型、地图、画面、编辑或保存合同。

## 原因与实现

此前 `timeline01` 的 `texture_dispatch.header_plan` 单次 2,133,834us，位于
`Deferred._estimate_job → _prefab_texture_plan → TexturePlanCatalog.estimate`。
缓存避免了后续重复读取，但第一次 DDS sidecar 探测、文件打开、PNG/JPEG/DDS
头部读取仍在几何任务 admission 之前同步执行。因此一个慢文件可以堵住整个派发。
这不是像素解码或 GPU 上传，也不能把它与嵌套耗时相加当作预期收益。

- `TexturePlanCatalog.prepare_async` 按同一来源/角色键共享 in-flight 读取。
  调用只派发，`poll` 仅 join 已结束的线程，任意顺序接收；一项未完成不会阻止
  其他已就绪候选进入几何/像素流程。负结果也缓存，避免每帧重读缺失文件。
- 直接使用现有 `ResourceAdmission`：每项占一个现有 worker 和 64KiB 临时
  元数据工作区。原有固定 16MiB/1024 行 catalog 预留不变，未增加总配额。
  worker 只接收私有来源数组，返回标量字典，不接触共享 cache、admission 或 RID。
- 完成 revision 加入 dispatch capacity，防止槽位数/字节数碰巧相同使调度游标
  错过新完成的数据。加载 idle/complete 包含尚未完成的元数据。
- 资源代次切换/地图退出把旧任务移交 SceneTree drainer，仍保留旧 admission
  charge，直到任务结束。旧结果不会写进新 catalog。CPU metadata 专用销毁路径
  不调用渲染同步；其他 worker 的原有资源 fence 保持不变。
- Thread.start 失败返回错误并归还配额，不无限重试或偷偷同步读取。
- 压测发现槽位耗尽后仍对余下来源逐项尝试 reserve；现在达到配额立即返回。
  不是增加队列容量，也未把未完成任务从 readiness 中排除。

现有严格诊断/独立同步 API、超出 1024 行缓存范围或 1024 字符键/根目录的
非典型来源继续保留原同步 fallback。本次实际地图初始 67 个、完整遍历 85 个键全部走异步路径；
不宣称所有可能资源包、初始导入器或所有文件 IO 都已经异步化。

## 独立复现与回归

证据根目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/async_headers_20261026/`。

`tools/test_async_texture_headers.gd` 用注入 reader 复现相同入口的 200ms 文件等待，
并用 Semaphore 保持一个线程暂停。这是确定性并发合同测试，不冒称真实 GDB 暂停
或物理冷盘测量。`unit05.log` 24 项通过：

- 同步入口 200,657us；异步派发两个任务 940us；移交取消任务 38us。
- 两 worker 中一个暂停，另一个完成、释放槽位后继续处理后续来源。
- 100 次共享 pending 请求只读取一次；负结果共享；新代次不接受旧结果。
- 取消、线程启动失败、最终 idle/ready 和 admission 归零。
- 256 来源压力场景恰好 256 次读取，peak workers=2，peak bytes=131072，
  完成后配额归零。该样本总耗时 888,339us、最长 dispatch 1,990us、
  最长 Thread.start 139us。修正耗尽后重复尝试前的 `unit04` 最长 dispatch
  为 23,180us，保留该样本，不把单样本差值外推成稳定整图收益。

`regression02.json`：texture plan reuse 17、admission 20、parallel lifetime 8、
parallel chunk 32、source identity 43、source coverage 8、admission priority 6、
map texture controls 10 项通过。GPU 私有桌面 `gpu03`：parallel DDS chunk 32、
prefab preparation/publication 75 项通过，无脚本/引擎错误。测试仅使用临时资源。

## 整图条件

安装引擎 SHA `0f0bf4469c70de8d051b1e6d22293ed508e077bf1c1a326c6291d50890e583e0`，
保持此前 TLS、UV 和 cover budget 的累计改动。`run_axel_texture_phase.py`
的唯一开关是 `--sync-texture-headers`，launch JSON 明确记录开关及源/地图 SHA。

使用原有私有桌面正常引擎，未附加 profiler/GDB，未改变 priority/QoS，未清 OS
缓存。geometry/bounds/model-metadata 派生缓存关闭，索引/native/纹理磁盘缓存
保留。范围仍是地图/预制件纹理，导入模型材质保持白模；不是完整游戏全部纹理。
完整就绪仍为当前需求连续三帧 demand/job/stream/batch 及共享像素输出清空，
不改为入口/cover 消失。1% low=1000/最慢 ceil(n*0.01) 帧的平均毫秒数。

入口试跑 `origin06` 正常退出，entry 4.433s，full-ready 11.576s。
catalog 67 miss / 67 async read / 0 pending，主线程 header_plan 最大 214us，
header_ready 最大 1314us，Thread.start 最大 127us；最终 admission/worker 归零。
只用于功能探路，不与完整遍历混为 p95。

## 完整 map07 ABBA

A 为同步头部、B 为异步头部，其余源代码与开关相同。四次正常退出、功能通过、
源文件/地图 SHA 不变。单位为秒和毫秒，所有慢样本保留。

| 样本 | 入口 s | 完整就绪 s | 卸载最大 ms | 返回最大 ms | 重载最大 ms / >50ms 帧数 | 重载 p99 ms | 重载 1% low FPS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A1 | 4.134 | 12.089 | 31.197 | 31.703 | 40.780 / 0 | 33.343 | 27.783 |
| B1 | 4.114 | 11.067 | 34.671 | 35.905 | 50.135 / 1 | 33.975 | 26.300 |
| B2 | 4.244 | 11.355 | 48.067 | 31.859 | 50.236 / 1 | 34.673 | 25.007 |
| A2 | 4.112 | 11.128 | 34.246 | 31.004 | 45.127 / 0 | 32.938 | 27.158 |

完整就绪均值 A 11.609s、B 11.211s，但 A1 明显比 A2 慢，且头部计划仅共
78–80ms，不能把约 0.397s 整体均值差归因给本改动。A2 与候选范围重叠，不能
宣称稳定缩短加载或 p95 已达标。**重载 1% low 均值 27.470 → 25.654 FPS，
本组有退步，必须继续查；不是整体 low 帧优化完成。** 卸载、返回各组均无 >50ms。

可直接确认的是主线程头部等待被拆开：A1/A2 的 header_plan 最大
16.897/12.613ms；B1/B2 的 header_plan 最大 0.391/0.396ms，加上独立异步
派发调用最大 1.112/1.714ms（两个最大值不必属于同一调用，不作为总帧耗时）。
候选 header_ready 累计 61.936/63.042ms、header_plan 累计 34.768/35.458ms；
同步原 header_plan 累计 78.281/80.155ms。异步增加了少量调度工作，不把并发
墙钟总和当作 CPU 工作降低；保留本改动的依据是解除不可控 IO 主线程阻塞及
独立复现中的并行推进，而不是宣称所有三个维度都获益。

工作量与回收：

- 各组 catalog 恰好 85 次 miss/85 个来源身份；B 各 85 次 async read。
  B 的 hits=4016，A hits=3931，差额正是原首次读取现变为已准备 metadata 命中，
  不是额外文件读取。
- 各组 GPU 上传 170 次 / 721,332,072 B，其中 DDS 148 次 / 508,911,392 B。
- A1/B1/B2/A2 shared produced 162/161/161/161；material cache miss
  146/146/140/142。生存期/时序会改变准备及缓存命中数，不能说所有 CPU 次数相同。
- 各组最终 admission bytes、workers、shared consumer/output/retained bytes、
  templates、retirements 归零。geometry logical retired bytes 均 167,884,640。
  B1/B2 private release 最长仍 23.355/22.505ms，未解决。

`abba07_summary.json` 保留全阶段分布与工作量，`map07_slow_splits.json` 保留
最慢帧邻域。B1 50.135ms 帧附近 geometry tick 31.414ms，随后记录 previous
process 36.775ms + previous draw 13.352ms；B2 50.236ms 附近 geometry tick
17.120ms，previous process 34.852ms + draw 15.370ms。两帧 Deferred join/sync
均为零，派发分别 0.229/1.103ms。只能据此确定需要继续查 geometry/process
链，不能只凭邻域计时给某个函数定罪，或把这些实际 CPU 帧标成 OS 空闲。

四组 post-ready steady 仍各一帧 >50ms，最大 54.789/53.577/52.038/54.340ms。
延续前轮 draw/presentation 等待疑点，需要栈证据；不是已修复引擎问题。

## 下一段定位

已完成独立官方 profiler `reload_official08`，正常引擎的安装 SHA 不变，开启
`RMMO_PROFILE_NATIVE_CALLERS=1`，记录 29,002 帧。游戏/接收端/解码均退出 0，
无引擎错误、源和地图 SHA 不变。它属于诊断样本，不混进上述性能 ABBA。
关键帧完整函数表另存 `official08_hot_frames.json`。

1. 卸载 frame 9920：43.305ms，其中主线程 native residency 41.244ms、
   retire_specs 39.864ms、retirement preflight 20.832ms。selection.prepare
   17.673ms，包含 7 次 Thread.wait_to_finish 共 10.670ms；导航移除 5.917ms。
   `rows` 八次累计 58.282ms 含后台线程，不能加到主线程上。这再次确认同步
   等待，而不是“后台任务已经完全拆好”。下一项优先检查索引自有 retirement
   描述能否在发布时复用、增量维护，避免卸载临时重扫和立即 join。
2. 返回 frame 25910：51.754ms，Deferred 主线程 39.186ms，需求刷新
   `_refresh_demanded` 37.787ms。同帧 prefab 解码/哈希还有后台活动，不能将其
   总和冒充主线程阻塞。
3. 重载 frame 27615：47.358ms，Deferred 主线程 27.869ms，painted_mesh
   15.140ms、geometry 5.058ms，world stream sync 7.432ms（存在嵌套关系）。
   同帧 terrain `_patch_context` 33.028ms、`_update` 56.843ms；调用点检查发现
   chunk preparation 的 `prepare_selected` 在后台，因此这些 worker 累计值
   不作为主线程归因。frame 27856 的 compact_terrain_sides 累计 62.962ms
   同样不能因为大于帧长就宣称主线程卡在那里。
4. 诊断还保留测试宿主观察/track_membership 的成本，后续逐帧与正常样本分开。

继续对 retirement selection、需求刷新、paint 构建做独立复现后修复，不扩大
worker 数或交互预算来掩盖。初次元数据本切片解决的是实际地图中的首次派发
阻塞；整个纹理阶段仍 >10s，重载 low 帧尚未改善，不能宣布总目标完成。
