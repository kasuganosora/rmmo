# 2026-10-27：重载低帧的合批准备屏障

承接 `axel_display_state_wait_20261027.md`，引擎仍为 engine09 / SHA256
`40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`。
本轮先独立复现，再实现并启用“完整建筑逐栋准备”。返回重载的绘制压力缩短，
初始加载尚无收益；来源加载阶段的到齐通知仍待接入，不能称作屏障已全部消除。

证据目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/reload_low_20261027/`。
普通样本源为上一轮 `first_draw_wait_20261027/map11_B.json`，该轮已验证无相关
Godot/Blender/GDB/编译进程重叠，原始帧不删除。

## 普通低帧的实际组成

`baseline01_tail.json` 将重载最慢 ceil(2932×1%)=30 帧对应到 frame-split 与
observer 区间。使用真实时间区间关联，不能直接累加最近一次 Deferred 数字，
也不能把 Performance.TIME_PROCESS 的缓存值当作本帧线程 CPU 时间。

- 最慢 46.835ms 帧：geometry tick 3.679ms、Deferred service 4.159ms、
  draw wall 7.390ms，仍有其他主线程区间待分段；不能声称三项已经解释整个帧。
- 后半段多条 34–39ms 帧：geometry tick 11–14ms、draw wall 16–20ms，
  此时 draw calls 约 2300–2412；其中某些还有 publication 约 3ms。
- 30 条中有 7 条包含 queue observer，平均摊入 2.610ms/尾帧。整个运行 observer
  共 268 次、累计 2.501s、max16.502ms。112.7MB 的原始 JSON 包含每 500ms 深拷贝
  的 1024-row stage_ring 和持续增大的 prefab_pixels.jobs；它有额外成本，但不是
  所有低帧的解释。下一轮优化工具时也不能删除历史慢帧或混用统计口径。

渲染增加与合批延后存在直接时间对应：

| 地图计时 | draw calls | 已完成分组 | 已合批源 | rebuild 总数 |
| --- | ---: | ---: | ---: | ---: |
| 100.697s | 363 | 71 | 342 | 394 |
| 106.794s | 1831 | 71 | 342 | 394 |
| 110.354s | 2313 | 71 | 342 | 394 |
| 115.435s | 2412 | 71 | 342 | 394 |
| 116.465s | 1714 | 100 | 1215 | 433 |
| 117.983s | 1056 | 222 | 2508 | 561 |
| 120.010s | 1038 | 229 | 2564 | 592 |

最终回到与初始相同的 229 groups、2564 sources、361 render surfaces。
中间不是最终地图永久加倍，而是新到达的源在较长时间内逐件绘制。

## 真实合批时间线

`map02_timeline` 通过正常优先级、独立桌面，打开已有 `--batch-timeline`，
无 GDB、无故障扩展、无 QoS。功能/源/地图检查通过，5242 条 timeline，dropped=0。
完整就绪 9.333213s 是带 timeline 的诊断结果，不加入上一轮普通 ABBA。
旧 runner 的 launch.diagnostic 当时只识别故障扩展，因此此文件该布尔仍为 false；
command、batch_timeline=true 和 host-meta.diagnostic=true 明确证明它是诊断。
本轮修正未来 runner 的标记，并在 result 中同步 diagnostic，旧证据不改写。

`timeline06_barrier.json` 显示：110.705412s 才发起本轮 3762 根的收集；
116.999496s 才排出第一组构建，中间 **6.294084s、0 次 commit**。
这段已记录的准备区间累计如下（不是各线程 CPU 占用率）：

| 阶段 | 区间数 | 累计区间 | 单段最大 |
| --- | ---: | ---: | ---: |
| collect | 55 | 67.616ms | 5.653ms |
| prepare | 188 | 373.016ms | 6.619ms |
| bin | 34 | 58.832ms | 5.723ms |
| unique | 2 | 1.583ms | 1.299ms |
| filter | 1 | 1.373ms | 1.373ms |
| drop | 9 | 41.200ms | 9.757ms |
| add | 1 | 2.289ms | 2.289ms |

合计 545.909ms 的准备工作跨越约 6.29s；每帧仍需绘制大量未合批源。分组直到
全局 collect/prepare/bin/unique/filter/drop 结束才能排入后台构建，因此即使某栋
房屋已完整到达，它也要等无关源的全局准备。已有 production_turn 能让已排出的
分组与新准备交替执行，却无法越过“尚无一个分组入队”的这段屏障。

## 为什么不直接打开旧渐进开关

`WorldStream.progressive_white_batches_enabled` 默认 false，注释明确保留其
“partial groups increase rebuild work”的诊断边界。它并非仅因纹理阶段而失效：
WhiteNativeAssetWriter.active() 也接受 native_geometry_only，当前纹理隔离路线
满足这个条件。此前口头提出白模条件可能挡住纹理只是待核对假设，现已排除。

新增 `tools/test_stream_batch_completion.gd`，在私有 GPU 桌面使用真正的
Stream/Index/Batcher、带纹理材质、64 栋各 16 件，按每轮给每栋一件的顺序交错
到达；只创建临时内存场景，不保存地图或导入资源。固定 60 FPS，只比较这份独立
负载的等待与工作量，不外推成真实地图 FPS。

| 控制 | 完整耗时 | 构建次数 | source prepare/pack | worker surfaces | 提前已合批源峰值 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 当前全局等待 | 2.455271s | 64 | 1024 / 1024 | 1 | 0 |
| 旧渐进检查点 | 2.983584s | 142 | 1024 / 1024 | 4 | 80 |

对应 `fixture03_wait`、`fixture05_progressive`，均 6/0。最后都是 1024 sources、
64 groups；完整同步 oracle 的成员和顺序完全一致，作者数组/纹理保留，live joins=0。
即便已实现 descriptor/packing 去重，旧策略仍多创建 78 次不完整几何分组。
不能仅看 prepare/pack 次数相等就宣称工作量没有增加。旧开关继续 false。

## 下一实现的严格边界

下一项是“完整来源单元尽早排入现有合批流水线”，不是扩大预算或开启旧渐进开关。

1. 用已有 `stream_building_groups` / 发布闭包明确一栋房屋的成员集合，建立只由
   主线程拥有的完成表。逐个源到达时更新，不能每次重新扫描整栋/整图，也不能以
   当前 stream_jobs 为空当作某栋完整：append_ready_jobs 每次只吸收 256 条，后面
   仍可能有同栋源。Deferred._stage_building 原子发布的合同可用，但原生模型、
   灯具、非建筑和分组扩展不能凭名称自行假设具有同样合同。
2. 已完整单元的收集/描述/分桶可独立推进，不让后来无关房屋不断重置其阶段。
   后台仍用现有 worker 和预算；节点与活动材质读取保留在必要的主线程切片，
   纯几何快照交给现有后台。保留现有分楼层、屋顶、天花板、fixture、材质、
   顶点上限和排序规则，不能通过改变最终分组或隐藏待处理源取得低帧收益。
3. 单元提交必须保留其他已完成分组。源删除/替换、编辑失效、返回重建、清空退出
   要撤销旧单元，不能让旧 GPU 结果覆盖新一代。全局最终对账必须仍能看到所有
   未完成单元，不能把新队列藏到 readiness 计数之外。
4. 独立测试同时覆盖交错到达和一栋先完整、另一栋长时间未完整。要求前者保持
   64 次最终构建，后者的完整栋先产生真实可见合批；有材质/身份变化时合理重建，
   对照完整同步 oracle。然后跑原有 partial ledger、边界/移除/重排测试，再做
   axel_town 正常对照及往返。未达到这些条件不启用候选。

显示设置修复继续保留，首个 3D 65–75ms 仍单列。此次没有修复原始 native AV，
也没有解除异步道路 paint 门控。完整目标仍 active；不把诊断完成当作优化完成。

## 已实施：先拆合批内部屏障

为了单独验证绘制压力是否来自准备屏障，先完成上面计划的第二项。WorldStream
请求时机暂不变：在 GroundBatcher 既有 collect 中顺便收集建筑成员，只接受同时
匹配 stream_by_id、render_building 和 ground_batch_record 的 ID。收集完成后，
用索引成员数量和身份确认完整单元；组件展开、未知结构和不完整房屋走原路径。
已有绘制分组保留完整 drop/add 对账，避免材质改变后旧 key 与新 key 同时绘制。

完整且尚未合批的建筑依次经过 prepare→bin→unit_add，立即进入原 pending / worker
队列。其他建筑继续准备，不再等整图 prepare/bin/unique/filter/drop 全部结束。
各部件仍只描述、打包一次；楼层、屋顶、fixture、材质、顶点限制和源排序沿用原逻辑。
新的来源追加在该有限单元计划完成后继续，仍复用完成的 raw-bin 账本；源编辑、
移除、清空及索引身份变化撤销旧单元。全部工作留在已有 _preparation 内，readiness
没有看不见的新队列。预算、worker 数、场景可见性和碰撞均不改变。

`closed_building_preparation_enabled` 最终默认 true；runner 的
`--without-closed-building-preparation` 保留旧路径对照，`--closed-building-preparation`
保留显式启用的重现参数。没有恢复旧渐进检查点。

### 独立验证与回归

- `fixture18_closed`：GPU 8/0；1024 sources、64 groups、64 builds，prepare/pack
  各 1024，早于全部 descriptor 完成就出现可见合批。完整同步 oracle 的成员与顺序
  一致，源数组/纹理保留，live joins=0。`fixture07_closed` 同为 8/0，2.455s 的原始
  控制与该小用例 3.185s 不能冒称时间收益；小地图更早合批没有足够绘制节省来覆盖切片。
- `test_closed_batch_preparation` 覆盖完整/未完整房屋并存、准备中追加、材质拆组、
  索引替换、移除以及 raw ledger 不持有 renderer/callback。初稿测试曾错误地用
  request_sync 的旧 descriptor 当作材质修改后的 oracle，以及在 unit_add 已经
  执行后才假设“尚未提交”；保留 units08 / regression12 失败记录，修正 oracle
  失效和中断点后 units09 / regression13 / regression19 通过，不冒称产品修复。
- completed_batch_bins、partial_batch_ledger、incremental_batch_bins、
  covered_batch_arrivals 连同新用例共 5 组通过。未删旧的乱序、限顶点、移除、
  返回、编辑与加载遮罩合同。

### 普通 ABBA（map14，完整往返）

同一 engine09、代码、预算、相机与资源，普通优先级，无 GDB、无 timeline、无 QoS。
四次均功能/源码/地图检查通过，host 观察未见其他 Godot/Blender/GDB/编译进程。
保持 native/index/texture 产品缓存，geometry cache disabled，OS cache untouched；
这是 map/prefab 纹理阶段，导入模型材质仍白，不能称作物理冷盘或全材质游戏验收。

| 样本 | 完整就绪 s | 重载 1% low FPS | 重载 max ms / >50ms 帧 | draw calls≥2000 的观察时长 s |
| --- | ---: | ---: | ---: | ---: |
| A1 原路径 | 9.240054 | 26.275 | 53.307 / 3 | 8.674 |
| B1 完整单元 | 9.331901 | 29.733 | 43.412 / 0 | 3.574 |
| B2 完整单元 | 9.267596 | 29.909 | 52.691 / 1 | 2.635 |
| A2 原路径 | 9.201032 | 29.146 | 42.327 / 0 | 6.808 |

高绘制时长由原 frame_split 相邻行间隔按上一行 draw_calls 累计，不是 GPU 占用时间。
early admission 初始 147 组、返回累计 294 组；prepare 单元数 148 / 296 包含不满足
最终合批条件的单元。完整房屋确实更早进入生产：两条 B 首次重载采样已 admitted179，
此时 descriptor visits 仅 4910 / 4917，而最终都是 7851。

初始工作四条完全相同：231 builds、3923 prepares、2724 packs、228 worker surfaces，
最终渲染都是 229 groups / 2564 sources / 361 surfaces，live joins=0。往返总工作有
时序波动：A builds556/572、packs6707/6970，B builds572/578、packs6717/6772。
不能说整图工作量稳定下降，更不能拿旧 map11 的 592 次单次比较冒充去重收益。
本次保留的依据是绘制压力明显缩短、两条 B 的重载 low 均优于两条 A，同时没有
改变最终内容；初始加载没有改善，不称作新的 p95 或稳定性能下限。

四条卸载和返回均 0 帧 >50ms。B2 的 52.691ms 帧（107683.732ms）不能归为 OS 空闲：
此前 geometry tick=35.356ms，下一条 previous_process_wall=38.376ms、draw=14.306ms，
该帧区间没有 queue observer。日志另有 pavement_1e991a89db78392fc875 的 restore
27.377ms / apply31.063ms；CpuMesh 记录一次 geometry24.721ms / material0.083ms。
缺少该条日志时间戳，**尚不能断言就是同一调用**；下一轮要加时间戳/抓栈确认并复现。
A1 的 3 条 >50ms 均叠有 9.8–13.4ms observer，仍有实际 geometry/render 成本，
不能整体删除。`abba16_peaks.json` 使用 frame_split 原生相对时间，不再加 began。

证据：`abba15_summary.json`、`abba16_peaks.json`、`abba17_draw_pressure.json`。
ABBA 用过的精确源码、SHA 与 tracked diff 保存于 `abba14_sources/`。最终仅把该候选
设为默认、增加关闭对照参数，并去掉 final add 已有私有字典后的冗余浅拷贝；只有
提前发布共享 raw-bin 时才复制。最终版本另以 regression19 和 map20_default 验证，
不把这条最终回归混入前面的 ABBA。

`map20_default` 最终默认版本：完整就绪 **9.240915s**；卸载/返回/重载 max
**49.001 / 31.862 / 43.763ms**，均0帧>50ms，重载1% low **28.770 FPS**。
这条 low 低于 A2，进一步说明不能把两条 B 的数值外推成稳定提升下限。
最终仍229groups/2564sources/361surfaces、live joins=0，early admission294，
功能/源码/地图检查通过，host未见其他相关进程。全部慢样本保留，原B2长帧没有因
这次未复现而被标记解决。摘要 `final21_summary.json`。

## 下一轮重点

1. 来源阶段仍等所有 stream jobs 完成才请求。按前述严格边界实现有索引闭包证明的
   到齐通知，接入本轮已验证的逐栋准备；保证无整图/整栋反复扫描、无半栋重复构建。
2. 确认 B2 的道路恢复长调用：加入绝对/相对时间，使用官方 profiler / GDB 区分
   小网格真实上传、队列等待和主线程工作，再做独立复现，不先归因资源或 OS。
3. observer 深拷贝仍污染一部分低帧，后续保留同等证据的历史快照语义后减少工具
   本身重复复制。此项是测量开销，不能作为游戏 FPS 提升。首个 3D 65–75ms、原始
   native AV 与道路 paint 门控仍未解决。
