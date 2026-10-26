# Axel 完整建筑来源到齐通知，2026-10-27

## 问题与实现边界

承接主日志 §169/170。GroundBatcher 已能逐栋 prepare/bin/admit，但 WorldStream
仍在当前 stream_jobs 全部处理完之后才发 request。完整建筑已经可见时，其他来源、
碰撞的收尾仍能挡住它的后台合批。这里处理这个上游通知屏障；不恢复会反复构建半栋的
旧定时/数量 progressive checkpoint。

`stream_batch_arrivals.gd` 是主线程唯一写入的到齐账本。每次真正 spawn 成功后登记
UUID 和 Node；索引中整个建筑的成员都到齐、当前 Node/record 身份仍一致，才通知
原 GroundBatcher。每个已有 residency turn 最多发一个完整单元，计入同一 FrameBudget，
不新增 worker、并发额度、独立后台队列或更大预算。组件展开和未完整来源走最终对账。

提交保持 exact root prefix，最后只追加尚未提交的来源，复用已有 descriptor/raw-bin
账本。账本不持有 spec、Mesh 或索引成员 Array，避免延长退休资源寿命。来源替换、
编辑、真实 adoption、索引退休、mesh removal 和同步编辑调用撤销此前证明，随后完整
对账；纯 owned spawn 的子节点计数暂时滞后只推迟一次通知。完成退休计划时即使 visual
revision 没增加也重建账本，为返回加载建立新起点。永久 map disposal 移除账本。

`closed_building_arrivals_enabled` 以及 runner 两个互斥参数提供同代码对照。
首次 ABBA 时默认 false；候选明确开启才生效。最终启用状态和最终回归见下文结论。

## 独立复现与回归

证据目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/source_arrivals_20261027/`

- fixture01_baseline：64 栋、每栋 16 部件、每轮最多 4 个来源，完整栋先到齐。
  首个合批 4.971s，此时剩余来源 0；完整 6.125s，8 checks/0 failures。
- fixture02_early：首个合批 0.518s，此时尚有 988 来源；完整 4.688s，提前合批
  最多 992 来源。与 A 同为最终 64 groups/builds、1024 prepare、1024 pack、
  live worker joins=0，8/0。这是显式 60 FPS 和来源数量限制的小用例，不是整图收益。
- fixture05_interleaved：所有建筑部件交错到达，仍可在全部来源之前合批 144 来源；
  最终还是 64 builds、prepare/pack 各 1024，8/0。与完整同步 oracle 的成员和顺序
  一致，原始数组字节和实际 textured material 保持。
- unit04_arrivals：10/0。覆盖重复事件、未完整建筑、追加 prefix、退休和同 UUID
  新节点、record 身份改变、旧 adopted 来源、首次空账本后 adoption、移除及弱引用
  寿命。unit03 的 9/0 是补上“首次空账本后 adoption”之前的记录，保留两者。
- 七组既有回归共 379 checks/0 failures：closed_batch_preparation19、
  completed_batch_bins102、partial_batch_ledger148、covered_batch_arrivals62、
  stream_child_adoption18、stream_owned_removal20、stream_batch_departure10。
  regression07 的 runner 误要求每项打印 PASS，把只打印汇总的 covered 用例当作零
  检查停止；该用例原日志就是 checks=62 failures=0。修 runner 识别汇总后
  regression08 完成余下四组；不冒称生产 bug 修复。

## 第一组普通往返：有外部竞争，保留但不作为干净验收

map09 为 A/B/B/A，同一代码、engine09、预算、资源、相机和路线，普通优先级，
无 GDB/timeline/QoS。功能、源码和地图检查均通过。产品 native/index/texture 缓存
保留，geometry cache disabled、OS caches untouched；map/prefab 纹理开启，导入
模型仍白，不是物理冷盘或所有模型纹理开启的最终游戏验收。

| 样本 | 完整就绪 s | 重载 1% low FPS | 重载 max ms | 高 draw 观察 s | 往返 builds / packs |
| --- | ---: | ---: | ---: | ---: | ---: |
| A1 | 11.131265 | 31.548 | 40.386 | 3.451 | 622 / 7316 |
| B1 | 11.133048 | 35.682 | 37.376 | 2.096 | 650 / 7640 |
| B2 | 9.855172 | 33.611 | 38.952 | 2.654 | 614 / 7226 |
| A2 | 9.578438 | 32.475 | 37.295 | 3.897 | 614 / 7356 |

初始四条工作完全相同：231 builds、3923 prepares、2724 packs、228 worker surfaces；
最终内容均229 groups/2564 sources/361 surfaces，累计 prepare7851，live joins0。
到齐通知 B1/B2 初始74/91次，返回累计205/224次，确实运行；最大单次通知3.409/
3.565ms。B1累计 arrivals7891，比其他 B 的7851多40，不能声称所有时序工作完全相同。
独立固定工作用例证明无半栋重复构建，不等于往返调度时序的所有工作计数固定。

1Hz host 记录：A1、B1、B2 期间均见其他 Blender 进程，A2未见。不能用它们宣称
稳定提速、解释全部波动，或把两个 B 的 load 当 p95。全部原始数据保留，后续另做
无上述观测竞争的对照。high draw 是 frame_split 相邻行按前一行 draw_calls>=2000
累计的 reload 观察时长，不是 GPU 占用时间；1% low 是最慢 ceil(N*1%) 帧的均值倒数。

B1 返回出现55.678ms（at99884.593ms），bookkeeping45.679ms，后续
previous_process_wall49.295ms。该帧没有内部 queue observer：恰好在 ending callback
at99884.593ms 的9.352ms observer 在记录该帧后才执行，影响下一段，不能倒算进本帧。
这是主线程服务整理长区间，尚未分解为需求重排、stale prepared disposal 或线程等待；
外部竞争也不能替代调用栈证据。没有称为 OS 空闲，也没有称为已修复。

分析脚本 analyze10.py，原始与峰值摘要 abba10_summary.json / abba10_peaks.json；
峰值分析修正了 observer 的半开区间归属，重算时保留原 map JSON。精确源码与 SHA
位于 abba09_sources/。本轮未修改引擎，也未改旧 native AV/road-paint 门控。

## 第二组对照、生命周期补测与决定

map11 仍保持完全相同代码/参数，只切换 arrival 开关。A1 完成后启动前守卫看到
Blender7020而停止后续启动，没有中断其他进程；稍后继续 B/B/A，host 记录照常保留。
没有把它称作无竞争的完整 ABBA。开始前的某次守卫也曾在任何样本启动前退出，未产生
性能样本。后续不以人为终止其他任务来制造“干净”数据。

| 样本 | 完整就绪 s | 重载 1% low FPS | 重载 max ms / >50ms | 高 draw 观察 s | 往返 builds / packs |
| --- | ---: | ---: | ---: | ---: | ---: |
| A1 | 9.419363 | 31.356 | 54.459 / 1 | 2.675 | 612 / 7381 |
| B1 | 12.345198 | 31.473 | 37.987 / 0 | 3.243 | 622 / 7371 |
| B2 | 9.744608 | 29.726 | 44.114 / 0 | 3.958 | 614 / 7342 |
| A2 | 10.200154 | 24.637 | 71.041 / 3 | 1.285 | 589 / 6974 |

四条初始工作仍与 map09 相同；最后内容均229/2564/361、live joins0。
B1 最终 prepares7846，其他7851；B1/B2 累计 arrivals7874/7879；完整移动路线仍有
不同的短暂来源到达和删除时序，不能把 pack 差值直接当稳定去重收益。两条 B 的
卸载/返回/重载均0帧>50ms，A2返回还有5帧>50ms；没有删掉这些慢样本。

按 cpu_time_anchor 对齐1Hz主机记录，并给 phase 边界加1秒观察余量：

- map09 的 reload：A1/A2未见其他相关进程；B1/B2都见Blender。
- map11 的 reload：B1/B2未见其他相关进程；A1/A2都见Blender。
- map11_B1 初始持续有两个Blender，前约20秒累计CPU时间约每秒增长3–4秒，
  确认有并行CPU工作，仍不能据此把全部额外加载耗时都归给它们。
- map11_B2整段未见其他相关进程；但重载low29.726低于map09两条A，且high-draw
  时长不再下降。主机观察不覆盖所有OS/驱动活动，也不是完整空闲证明。

因此：**候选保留，默认仍false；不宣布本轮整图加载或1% low已提升。** 独立用例证明
它能消除“完整建筑等其他来源”的屏障且不重复构建，但没有足够证据把机制收益外推
为当前地图稳定的实际收益。沿用原native阶段启用边界，未放开全材质游戏路径。
map11的摘要/峰值文件为 `analysis_map11_A1_map11_B1_map11_B2_map11_A2_*.json`。

fixture13_return补真实GPU生命周期，15条断言通过，但原日志有ERROR：测试 helper
在尚未settled时调用 get_meta("stream_chunk",null)，Godot把null视作未提供默认值。
旧fixture runner只检查退出码/断言漏掉这些日志错误，因此**不能列为无错误通过**。
已改为has_meta保护，并收紧外部fixture runner拒绝ERROR/SCRIPT ERROR/FAIL日志；
原始样本和旧result不覆写。返回增量64 builds、1024 prepares、1024 packs仍是该次
观察值，需待修正后重跑确认。该测试时长不混入前述初次计时。

修正后的fixture16_return：15 checks/0 failures，**errors=[]**，engine_exit0，源码/
fixture/地图SHA未变；返回增量仍64 builds、1024 prepares、1024 packs。旧独立
fixture01/02/05及unit03/04日志也逐一检索ERROR/SCRIPT ERROR/FAIL，未发现；只有
fixture13有上述测试helper错误。

随后补查可选adoption服务缺省的组合：unit17复现候选本身的同类metadata错误
（11断言通过，但runner因ERROR正确失败），world_stream改为has_meta后再读取。
unit18：11/0且errors=[]；最终源码fixture19_return：15/0且errors=[]，返回仍
64 builds/1024 prepares/1024 packs、源码/fixture/地图SHA未变。该最后修正只覆盖
可选服务不存在时的读取，普通两组ABBA仍是abba09_sources中已保存的版本，不混写。

## GDB新增现场：返回纹理上传的暂存缓冲分配

`map15_service`使用当前默认arrival=false，phase3返回、最后heartbeat为
GEOMETRY_END且超过25ms后冻结本机唯一owned主线程。心跳实际间隔35.663ms，
sequence_gaps0；GDB比对暂停前RIP后，先归还本机一个暂停计数，再在GDB all-stop下
解码栈。`freeze_valid=true`、engine/GDB退出均0、failures=[]、日志错误0、源码/
地图未变。脚本为run_gdb14_service.py，原始gdb.log与结构化map15_service.stacks.json
同目录保存。此样本明确diagnostic，不进入加载/low统计。

主线程实际栈：

`Deferred._process → _publish_ready → MaterialPublication.step_prepared/step →
SurfaceMaterials.texture/_texture → ImageTexture.create_from_image →
RenderingDevice._texture_initialize → _acquire_transfer_worker →
VMA AllocateVulkanMemory → AMD/Vulkan → NtGdiDdDDIWaitForSynchronizationObjectFromCpu`。

该次`p_transfer_size=22369728`（约21.33MiB），`buffer_create p_size=33554432`
（32MiB）、CPU memory allocation type。主线程现场是纹理传输暂存缓冲的原生分配/
驱动同步等待；不是眼前建筑的GDScript构建循环，也不是已证实的后台上传mutex等待。
`RenderingServerDefault.create_thread=false`；另外两个几何worker当时仍在road polygons/
point-in-polygon工作。捕获了生产调用中的真实等待点，但不能把整个heartbeat间隔
全部记到该次分配，不能倒推map09_B1的bookkeeping45.679ms就是同一原因。

代码复核：engine09对应源码`rendering_device.cpp:7258`在选中transfer worker容量
不足时按2次幂重建staging buffer。候选选择优先空闲而容量不足者，其次才是忙但可容纳
者；尚未记录当时完整pool状态，不断言发生了错误选取或不必要重建。没有修改引擎。
该GPU分配成本不会因为上游更早发建筑合批请求就自动消失。

该诊断paint.texture.upload共170次，max17.795秒包含GDB停顿，**不能作真实上传
耗时**；heartbeat63103次、累计1.998秒，也是诊断成本。尚未取得具体纹理路径/格式，
不能仅按字节数推断分辨率或声称DDS失效。

## 下一步与剩余边界

1. 不扩队列、不提升预算，先用已有 batch timeline 对齐来源通知、实际worker开始、
   commit、draw压力，区分“提前通知但仍等待”与非building来源占主导。没有关键路径
   收益证据前不把候选设默认；若通知只改变工作时机且代价更高，应简化或撤掉它。
2. 优先独立复现已抓到的纹理暂存分配：保持相同字节/数量/生命周期与GPU绘制，比较
   主线程创建和既有预算内后台创建，检查是否只是把等待搬到另一处锁；记录pool容量/
   选择、实际纹理路径与格式。若可复用暂存缓冲，应证明不增加无界常驻内存或重复上传。
   不盲目扩大缓存，不重试已撤回的隐藏mesh预热。
3. 55.678ms/bookkeeping45.679ms返回帧仍未解决。复用已有需求子阶段Trace和官方
   profiler入口，必要时把GDB触发范围进一步缩到该区间，再在测试重现。新的纹理栈
   不是对该旧帧的归因证明。
4. 首个3D帧、首次实际材质绑定、旧native AV与road-paint门控继续单列。
   当前map/prefab纹理阶段结果不代表所有导入模型纹理已恢复或最终游戏已验收。
