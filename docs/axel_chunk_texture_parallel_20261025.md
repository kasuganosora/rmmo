# 区块网格与纹理并行准备

## 范围与执行合同

接续 `axel_dds_worker_publication_20261025.md` 的 CPU 可行性试验，本轮将区块的
两段准备接入正式 Deferred 调度。范围是已有 native reference 的网格/碰撞/道路
CPU 数据与地图/预制件纹理；没有扩展到导入模型的完整材质，也没有修改资源或引擎。

- 整个区块仍先完成原来的 `reserve_bundle`，几何工作区、纹理工作区和唯一共享
  图片的总字节上界均已计入。若总 worker 上限还有一个槽位，原 entry 增加一个
  execution slot，两个任务同时开始；不再申请另一份图片或额外扩大预算。
- 只为 shared pool 本次确实产生唯一图片的 leader 拆分。全 resident、纯 follower、
  单 worker、无纹理、非 native 及严格可变源诊断路径继续原流程。
- 几何继续核对本次引用与目录的纹理绑定，但不再执行纹理准备。纹理任务消费同一
  计划和同一个共享 consumer，保留源角色、共享身份、解码和最终来源检查。
- `parallel_chunk_worker.gd` 由主线程管理两条 CPU Thread。每条完成后非阻塞 join，
  即时归还自己的执行槽；只有两条都完成后才合成原来的 publication packet。
  工作区和图片 owner 仍由原来的区块 lease 持有。follower 未就绪时仍沿用已有
  停放/续作，不重新读取或生成几何。
- 取消使用同一个 token；退出后把整个 join handle 交给既有 tree-owned drainer。
  任一半仍运行时都不能提前释放共享 consumer 或预算。没有后台任务调用场景/GPU
  发布，也没有在主线程等待活 worker。

主开关 `Deferred.parallel_texture_preparation_enabled` 默认开启。整图诊断通过
`run_axel_texture_phase.py --serial-chunk-textures` 运行同代码的串行对照。

## 先复现，再独立验证

`test_parallel_chunk_preparation.gd` 在临时外部目录创建真正的 native bridge 引用，
经实际 Index、Deferred、shared pool 和 admission。第一次 `red01` 为 11 通过 /
1 失败：停住几何 worker，两个纹理角色在 2 秒内无法产出，解除阻塞后才开始准备。
接入后 `green01` 为 12/12，停住几何时纹理已经完成，且释放了自己的 worker 槽位。

扩展后的 `parallel_png04` 与 `parallel_dds04` 均 **26/26**：

- 分别停住几何或纹理，另一个任务仍推进；半完成阶段不释放原来的内存预算。
- 12 个区块共享颜色/法线两个角色；像素被暂停时，另一个槽位让其余 11 份几何
  全部完成并停放；恢复后总共产生两张 Image，12 次引用读取，无几何重读。
- 12 个消费者实际拿到相同的两个 Image 对象，完成后 owner 和 ledger 全部释放。
- 活 worker 峰值不超过 2，预算不超过原上限。单 worker 自动串行完成。
- 普通 quiesce 和释放地图时仍有像素任务运行，两种场景都完整 join 后释放。
- DDS 保留完整 BC1/BC5 压缩 Image，PNG 保留原分支；没有 GPU 纹理创建。

`stress02`、`parallel_{png,dds}03` 的弱引用释放断言曾失败，已保留。原因是测试
在同一个 async 调用栈里遍历 images 字典，GDScript 迭代临时变量跨 await 持有它；
将只读观察封装为先返回弱引用的普通函数后，所有 Image 都释放。该修正只改测试，
没有用手动清空生产缓存掩盖资源泄漏。

`test_parallel_worker_lifetime.gd` **8/8**：同一 100 字节 bundle 分给两个 CPU
槽位，拒绝第三槽；活 sibling 不准 shrink；续作恢复为恰好一个槽；分别模拟第一/
第二条线程启动失败，确保已启动的任务仍被 join、预算没有提前归还。

既有回归：resource admission、shared serial、out-of-order、CPU shutdown 均通过，
原 native admission **493/493**。原共享池测试显式选择 serial，保留旧 follower
停放合同；新独立测试覆盖默认 parallel，不能用旧夹具的执行顺序假定否定并行行为。

## 整图对照协议

固定 `D:/tools/godot/godot.windows.editor.x86_64.exe` 与 88 个已发布 DDS，按
A1 serial → B1 parallel → B2 parallel → A2 serial 运行。代码和引擎 SHA 整组固定，
不在进程之间修改生产文件；只改变诊断开关。普通优先级，不修改 QoS 或 OS cache；
沿用关闭几何/边界/模型元数据缓存、保留 native 产品和像素磁盘缓存的历史范围。
没有其他压测与这组计时并发。

时间边界仍是地图 pipeline 开始到当前需求、worker、发布、render batch 连续三帧
完整就绪；纹理组还要求像素 consumer 交接完毕。记录入口、full-ready、卸载、返回
及重载最大帧和 >50ms 帧数，同时保留真实读取/上传量、共享图片数和 worker/预算峰值。
样本数量不足以宣称冷盘 p95 或稳定性，本轮不是完整游戏所有系统的验收。

证据目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/chunk_parallel_20261025/`。

独立测试为 `red01.*`、`green01.*`、`stress02.log`、`*03.log`、`parallel_{png,dds}04.log`；
完整地图为 `map01_{A1,B1,B2,A2}.*` 和 `map01_summary.json`。所有失败/慢样本保留。

## 第一轮没有证明总加载提升

| 样本 | 入口 | full-ready | 卸载 max / >50ms | 返回 max / >50ms | 重载 max / >50ms |
| --- | ---: | ---: | --- | --- | --- |
| map01 A1 serial | 10.779s | 25.577s | 33.783ms / 0 | 151.168ms / 79 | 387.409ms / 16 |
| map01 B1 parallel | 6.250s | 21.592s | 54.527ms / 1 | 45.107ms / 0 | 56.580ms / 2 |
| map01 B2 parallel | 6.363s | 19.064s | 37.458ms / 0 | 64.926ms / 14 | 62.812ms / 1 |
| map01 A2 serial | 4.780s | 14.272s | 30.577ms / 0 | 41.618ms / 0 | 49.109ms / 0 |

四轮功能通过，但 A1 的 `reference_index_hit=false / reason=stale_index`，额外
重建 1457 份引用并交接 1098 个记录，占用 268,426,368 B 的 reference handoff。
其余轮次该项为零，因此 A1 不能作为相同目录状态的 warm 对照。它仍保留为真实慢
样本，不能偷偷删除后宣称 ABBA 均值提升；后续先显式 prime 再检查 measured 样本
的 index_hit。这里也没有将 25.577→14.272s 的跨轮差全部归给任何一项优化。

B1/B2 实际拆分 14/19 个任务，记录到 994/687ms 的几何/像素重叠；这是多任务累计
交叠时间，不能相加为整图收益。两轮仍慢于 A2，单独并行未证明缩短完整加载。
四轮总上传始终 170 次 / 721,332,072 B，零 PNG 源解码；共享 pool produced 分别
170/163/176/163，说明真实预测/取消/回收时序仍有重建量波动。独立 12 消费者实验
证明同一批活消费者不重复生产，但不能据此宣称整次遍历绝不再读取已回收的图片。

## 继续排查出的重复头部读取

map01 A1 重载 387.409ms 帧的 Deferred dispatch 为 348.621ms，texture_dispatch
的 header_plan 最大 **346.950ms**，路径为 building_c7b762a5eb920bf82d4e。
同轮总共 473 次 header plan / 4016 个键 / 2.803s；A2 也有 1.712s 的累计头部
规划。返回 151.168ms 帧另有 bookkeeping 97.088ms，不把所有长帧都归到纹理上传。

原缓存按区块请求/需求 revision 保存且只留 16 项，同一个纹理给不同建筑、不同
需求重复做文件路径与头部读取。增加 `texture_plan_catalog.gd`，只在本次可信包
操作内按源角色复用不可变尺寸、格式与预算行，不保留 Image 或 GPU 资源；实际
解码仍检验同一次打开所得数据的分配边界。目录最多 1024 个有界键，预留 16 MiB
从同一个任务总预算扣除，绝非未计账的全局像素缓存。

显式 `SurfaceMaterials.refresh_sources()` 推进 generation；新加载、源刷新、格式
配置变化会清空元数据。严格可变源诊断继续原读取方式，白模零读取。另修复同一
需求/同一路径的旧 request-plan 在显式刷新后仍命中这一正确性缺口。

`test_texture_plan_reuse.gd` 的 `plan_red01` 原版三项失败：重复读头、同一需求
刷新后尺寸仍旧、刷新读取数错误。`plan_green01` 和加强 legacy plan 字典/预算
对照后的 `plan05` 均 **17/17**；12 个需求同两个角色从 24 次降为 2 次，刷新后
再读 2 次，严格诊断三次请求仍 6 次，白模为零。
目录接入后再次跑 PNG/DDS 并行各 26、生命周期 8、原共享 32、原准入 493 项，全过。

第二组先跑 `map02_prime`：功能通过、full-ready 17.953s，不进入 warm 对照。
随后 `map02_*` 对照累计修改：A 关闭 parallel 和 texture-plan reuse，B 开启两者。
全部 measured 样本要求 index_hit=true，代码/引擎 SHA 固定；两种路径的总预算
政策相同，B 从任务额度中预留目录的 16 MiB。结果只归因于累计组合，不把收益
全部算作增加一条像素线程的效果。

| 样本 | 入口 | full-ready | 卸载 max / >50ms | 返回 max / >50ms | 重载 max / >50ms |
| --- | ---: | ---: | --- | --- | --- |
| map02 A1 两项关闭 | 7.299s | 22.961s | 43.669ms / 0 | 52.999ms / 1 | 46.832ms / 0 |
| map02 B1 累计候选 | 5.095s | 15.081s | 30.827ms / 0 | 43.708ms / 0 | 68.246ms / 6 |
| map02 B2 累计候选 | 5.098s | 14.886s | 30.115ms / 0 | 42.445ms / 0 | 56.211ms / 2 |
| map02 A2 两项关闭 | 5.094s | 14.481s | 69.115ms / 1 | 72.390ms / 6 | 43.931ms / 0 |

四轮全部功能通过且目录命中。full-ready 均值 18.721→14.984s（-3.737s），但 A2
仍比 B1/B2 更快；不能用两个样本宣称稳定整图收益或 p95。候选卸载/返回全部零帧
>50ms，重载仍 6/2 帧，且比这组对照的零帧更多，不能宣称长帧全部解决。

更明确的工作量收益：A1/A2 规划 4022/4016 个角色键，header_plan 累计
2.028/1.961s；B1/B2 都是 85 个唯一 miss、3943 次复用，累计 89.087/89.132ms。
候选最大单次规划 13.602/15.694ms，尚未将唯一源首次头部读取移出主线程。
两轮并行 19/16 组，累计重叠 706/574ms；两者都有原任务总上限内的 6 worker
峰值。上传全部维持 170 次 / 721,332,072 B，零 PNG 源解码，零完整文件最终 SHA。
共享 produced 160/171/163/160，DDS 读取 138/149/141/138 次；整次遍历的回收后
重建量仍随调度变化，不把共享去重解释为跨卸载永久保留所有 CPU 图片。

byte_limit A=8,510,964,736 B，B=8,494,187,520 B，差值就是目录预留 16 MiB。
两组 peak 都比各自 limit 高 33,624,832 B，来自既有 exclusive oversize 政策，
不能声称整图峰值始终低于 nominal limit；拆分没有扩大总额度或取消该政策。
最后退休断言均确认 worker、consumer、output、reserved bytes 归零。

B1 重载 68.246ms 帧中，dispatch 0.170ms、bookkeeping 0.242ms、poll 0.097ms、
publication 1.916ms、service 3.189ms；大部分耗时没有被 Deferred 区间解释。
另两帧 63.327/63.234ms 有 publication 20.400/29.447ms。返回最慢 43.708ms
有 bookkeeping 35.086ms。保留这些区间差异，不默认归类为 OS 空闲。

## 取消后接替生产者的共享键缺口

追加 12 消费者取消生产者测试，`parallel_cancel_png06` 31 通过 / 1 失败，
同代码加计数后 `parallel_cancel_red07` 32/32、produced=2、unique_images=2。
这组时序相关现象本身没有稳定归因，不能靠一次通过结案。

独立 `test_shared_pixel_reclaim.gd` 固定旧生产者仍占据工作区、有存活 follower、
重试已经观察到源身份而新请求尚无 revision 的时序。`reclaim_red09` 稳定复现
两项失败：同一可信源产生两个 binding；失败产物不能原地接管，而要再分配输出。

修复：可信 mounted 源统一使用显式 source_generation 的绑定身份，首次请求和
重试不会仅因是否带 revision 而分裂；严格可变源诊断仍区分 revision。failed
pending 项可以在完整解码工作区重新准入后转移 owner，复用现存共享输出 lease。
旧 worker 的工作区直到 join 才释放，晚到 publish 被拒绝，旧 owner 退休不会
破坏新 owner。ready 项不转移生产权，也不重复生产。没有新增磁盘校验。

`reclaim_green10` / `reclaim11` **14/14**；PNG/DDS `parallel_*11` 各 **32/32**，
元数据目录 17、生命周期 8、既有共享 32、native admission 493 全通过。
取消用例的 `completed_reference_reads=12` 只统计最后 12 份成功 packet，不能
据此宣称取消失败的几何尝试没有重做；原无取消压测才证明恰好 12 次引用读取。
新 pool 修改后再单独运行 `map03_F1/F2`，不冒充 map02 的源 SHA 完全相同。

## 取消接管修复后的正常整图复测

| 样本 | 入口 | full-ready | 卸载 max / >50ms | 返回 max / >50ms | 重载 max / >50ms |
| --- | ---: | ---: | --- | --- | --- |
| map03 F1 | 7.816s | 25.159s | 45.323ms / 0 | 63.683ms / 8 | 57.582ms / 4 |
| map03 F2 | 6.998s | 19.951s | 45.593ms / 0 | 53.608ms / 1 | 47.583ms / 0 |

两轮功能全部通过，index_hit=true，source/map unchanged，无脚本/引擎错误，
普通优先级 32、无 QoS 修改。两个样本都没有 pixel retry，退出消费者和预算归零。
上传仍 170 次 / 721,332,072 B；header_plan 总计 106/91ms，缓存 85 个唯一角色。
共享 produced 159/164，实际拆分 14/16 组，累计几何/像素重叠 699/696ms。

这些慢样本说明本轮只能确认减少重复工作、支持真实并行和生命周期正确性，不能
宣称纹理整图加载已稳定加速，更不能沿用 map02 的两个约 15s 候选作为最终结果。
F1 返回 63.683ms 帧 bookkeeping 35.352ms；另有 56.853ms 帧 bookkeeping
47.557ms。F1 重载 57.582ms 有 publication 17.981ms 与 render CPU 20.384ms；
53.116ms 帧 publication 26.679ms。没有将这些生产代码耗时归为 OS 空闲。

初始收尾最后数秒，Deferred 的 demanded/job/active counts 已经是零，stream
jobs/cursor 也是零，剩余 pending_groups 属于 GroundBatcher。F1 在 24.585s
仍有 86 个 batch pending，25.086s 剩 8 个；F2 在 19.129s 有 1 个正在准备，
19.630s 后续有 43 个待提交。其 max_commit 历史峰值 572/558ms，仅能说明
加载 cover 内仍有昂贵提交，不能与当前最后一帧直接对齐，也不能视为后台纹理
没有满载。官方 profiler `parallel_official04` 从 AXEL_PIPELINE_BEGIN 开始记录，
专门区分初始合批尾段与交互返回/重载；不计入普通性能样本。

## 官方 profiler 与材质失效扫描

`parallel_official04` 正常结束、功能通过，官方服务器/visual profiler 保存 20,205
帧，解码成功、engine_errors=[]，source/map unchanged。启用已安装引擎的 native
caller attribution；没有改引擎。此记录包含后台线程的函数工作量，不能把累计
self/total 与等待时间相加为主线程耗时；frame phase 边界也可能跨一帧。

- 返回最慢的两帧为 47.461/47.225ms，`_refresh_demanded` total
  30.580/37.067ms，self 16.693/22.221ms；再次确认需求刷新是生产路径成本。
- 重载一帧 53.970ms 中 `invalidate_texture_materials` 18.884ms，
  `_uses_textures` 937 次 / total 16.889ms。这是同一次失效通知反复查看共享
  Material 的定义，和 GPU 上传量无关。另一帧 55.205ms 有测试
  `observe` 12.861ms、track_membership 10.154ms（包含关系），不能统归生产。
- 初始 cover 内仍有真实原生提交长帧：frame 1444 的 552.482ms 帧包含
  `Cpu.restore → Mesh.surface_set_material` 8 次 / 468.577ms；frame 1731
  的 175.562ms 包含同调用 3 次 / 158.449ms。frame 1369 的 319.152ms
  则有 `GroundBatchGeometry.upload → Object.set` 316.490ms。与所有 worker
  时间相加不是总加载归因；这些原生调用的内部仍需后续 GDB 栈确认。
- 保存报告的 JSON.stringify 3.387s / FileAccess.store_string 625ms 在
  outside_route，明确属于测试退出报告，不计入地图 full-ready 或交互尖峰。

针对 937 次材质扫描，先新增 `test_texture_invalidation_reuse.gd`：512 份缓存
网格共享 32 份材质，每份还有 source/render alias。`invalidation_red12` 功能
6 项通过，但定义检查实际 **1536 次**，唯一工作量断言失败；8 次压测中位数
12.254ms。修复只在一次同步通知内按 Material instance ID 复用命中/不命中结果，
不跨通知缓存，不保留额外材质或网格 owner。

`invalidation_green13` **7/7**，检查 **32 次**，8 次中位数 **2.958ms**。
覆盖无关 key、精确受影响的 16 份 alias、已持有几何不变、下一次通知观察编辑
后的材质、OpenGL/DirectX 法线角色区分。没有修改贴图或模型内容。

额外真实 GPU 回归：`editor_scope14` 包含 UI 共用操作、真实 HTTP open/save、
修复源后重开、保存失败不改作者数据等，failed=0；`test_prepared_material_publication15`
64/64、`test_material_publication15` 46/46。最后的累计整图为先显式 prime、再
`map05_F1/F2`；这轮才包含失效扫描复用，不能把 map03 数字写成最终代码结果。

计时完成后核对 `final_assets_verified.json`：88 份 DDS / 328,566,704 B 全部与
此前发布 SHA 一致；本轮优化没有通过改图、减少纹理或覆盖资源取得收益。

## 累计最终复测（map05）与未解决边界

prime 功能通过，full-ready 15.433s，不进入 measured 样本。F1/F2 均目录命中，
同代码/引擎/资源、普通优先级，功能、源一致性和地图一致性全部通过。

| 样本 | 入口 | full-ready | 卸载 max / >50ms | 返回 max / >50ms | 重载 max / >50ms |
| --- | ---: | ---: | --- | --- | --- |
| map05 F1 | 4.953s | 14.219s | 43.036ms / 0 | 61.040ms / 6 | 86.552ms / 7 |
| map05 F2 | 5.270s | 15.865s | 60.327ms / 1 | 53.151ms / 1 | 52.741ms / 2 |

两样本均值 15.042s，但并非最后一项改动的 ABBA，不能把与 map03 的差全部算为
材质失效扫描收益。整个正常样本系列仍有明显波动，没有宣称 cold/p95 或完整游戏
优化完成。此次明确保留的是并行功能、正确共享/取消预算与独立复现的重复工作削减。

最终工作量：header_plan 88.502/90.437ms、85 个唯一 miss；全部缓存失效通知
累计只检查 1524/1542 个唯一材质定义（每次通知重新计数）。170 次 GPU 上传 /
721,332,072 B 不变，零源 PNG 解码；没有 pixel retry。退出 map_freed=true，
worker、shared consumer/output、admission bytes、lookahead bytes 和 retirement
队列全部归零。明细为 `map05_final_review.json`，未把预算估计称作 RSS/VRAM。

仍需继续的具体证据：

1. 返回需求刷新。F1 一帧 56.364ms，bookkeeping 41.129ms；刷新仍同步收集、
   排序、重建候选与 dispatch。官方记录支持继续针对这一段，而非继续扩大队列。
2. 重载合批/发布/渲染。F1 的 86.552ms 帧附近 geometry tick 37.008ms、
   publication 26.372ms、render CPU 23.503ms、159 个 batch pending。采样时刻
   和上一帧 wall 范围不同，不能直接相加，但不能写成 OS/GPU 空闲样本。
3. F2 卸载 60.327ms 帧：Deferred service 0.092ms、geometry tick 0.294ms、
   draw=0，但 previous_process_wall 58.230ms；Performance 的 process 值
   12.025ms 是引擎采样值，单靠它不能排除其他主线程/测试宿主或等待耗时。
   此帧仍未明确归因，不宣称卸载零尖峰。
4. 初始完整就绪最后等待 GroundBatcher，cover 内原生材质/mesh 提交峰值见上。
   本轮没有再次尝试已撤回的隐藏三角形预热，也没有修改源资产来掩盖此问题。
