# 共享纹理图片回收：独立复现（2026-10-27）

证据目录 `D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/material_cache_pressure_20261027/`。先前官方 profiler `reload_official15` 的单帧中 `SharedPrefabImages.release` 包含耗时最高10.596ms；该数字不能单独证明图片析构是整帧根因。

`tools/test_shared_pixel_release_cost.gd` 使用真实 Pool.offer、reserve_bundle、commit、publish、producer/follower与最后consumer release；填充/上传不计入释放计时。弱引用验证共享消费者和可选外借者；借用者保留时 pool 的释放不代表实际像素已经销毁。子类逐项计时与原始 Pool 做 ABBA，分项本身有计时开销，不与普通实图帧混用。输出是对象计账/逻辑字节，不代表 RSS 或实际VRAM；16张 RGBA 样本触碰256MiB，不能与实图基准同时运行。

`reclaim20.log` headless 原池在16张 2048² RGBA8、256MiB 条件下最后释放为17.297/16.754ms；分项图片释放16.233/16.770ms。保留一张借用后最后 pool release 14.971/16.730ms，借用者随后释放约0.9ms。GPU关闭；不是实际地图纹理分布。

`reclaim22.log` 使用外部现存完整2048² DXT1 mip DDS的像素，16张共44,739,456字节；headless原池3.213/8.490ms，分项图片3.013/3.557ms。`reclaim23_gpu.log` 私有桌面同输入且启用真实 ImageTexture ticket，原池3.663/3.460ms，分项图片3.662/3.480ms，texture 0.153/0.160ms；包含分项计时开销，未证明整图同等分布，也未证明 GPU 释放总成本。两份检查均0失败；原始逐样本和慢结果保留。`reclaim19.log` 是测试脚本静态类型解析失败，已修正；`reclaim21.log` 使用的旧DDS不含完整mip链，预期检查失败，该次没有DDS测量。不能把失败样本当性能结果。

候选方向：Image/Texture/RID仍在主线程操作，仅转移纯CPU COW字节引用，合批且受统一线程及字节预算限制；同一逻辑binding的新旧代必须各自持有独立租约，旧代任务结束不能释放新代。后台停止持有自己的字节引用并不证明外部借用者已经释放；产品就绪、池内退休状态、账本、quiesce/关闭合同须分别验证。在反例、压测及整图对照完成前不宣称该候选已修复。

此外 `material_publication_scope_20261027/map16_draw20` 使用返回阶段 pre-draw 标记后25ms阈值，正常引擎与GDB退出0、源和地图一致，但没有触发、没有栈；不能作为已复现/已解决的draw长帧或普通性能数据。

## 候选实现和独立测试

候选为大于等于256KiB的池内Image保留 COW 字节引用，Image/Texture 本身仍在主线程释放；仅将纯 PackedByteArray交给退休服务。逻辑 binding 在最后consumer退出时转为当前账本内唯一的旧代租约，新代重新准入仍单独计费；后台完成后主线程才归还旧代租约。池统计和状态转换使用共享锁，析构不持锁。分批最多128个，使用同一个账本的空闲worker槽，不增加正常并发上限。产品需求idle不等待纯后台回收，历史测试full-ready额外等待账本内所有旧pool退休输出/字节清零。外借Image仍可持有数据，退休完成不能冒称物理内存回收。

独立审查先后发现队列首项等待独占/满槽而后项负责释放该槽、显式queue.shutdown遗留租约、池统计字典并发写，以及root退出传播时首次创建服务失败导致8MiB租约和节点泄漏；均先建立红测后修复。禁止worker时逐个同步释放；关闭队列对该ledger定向收尾、已满槽时同步fallback；服务在普通commit时deferred准备，release仅使用已挂载且未退出的服务，不可用则同步fallback。同步fallback仍可能卡主线程，已启动退休票据可能阻塞其他FIFO票据，必须结合实图评估。

最终 `reclaim_final2_contract.log` 186通过、0失败，覆盖共享与跨pool同binding两代、预算持续占用、独占/满槽 FIFO、worker_limit=0、quiesce、取消、外借Image、启动失败、129→128+1分批和真实queue.shutdown。`reclaim_final_shared_pixel_root_shutdown.log` 真root退出通过，红样本为 `reclaim_root_before.log`；相关root功能路径在最终计数锁调整前测过，未改其功能路径。私有GPU `reclaim_final2_gpu_retirement.log` 7/0、`reclaim_final2_gpu_shared.log` 39/0；另有headless shared/reclaim/final-handoff回归。

最终 `reclaim_bench_final.log` 同版本 ABBA：16张RGBA8共256MiB，pool.release旧19.780/24.301ms、新0.325/0.287ms；预算全部退还旧19.791/24.314ms、新35.243/42.008ms。16张完整mip DXT1共44,739,456字节，主线程release旧3.862/3.811ms、新0.265/0.270ms，预算退还旧3.872/3.819ms、新14.337/21.235ms。较长预算持有是明确代价，逻辑预约分别536,870,912和89,478,912字节，不是实际RSS/VRAM。测试是固定输入、不是整图长帧收益。

## 累计真实地图 ABBA

`map24` 两个候选一起切换：A同步图片退休且旧高度fallback，B后台退休且高度fallback惰性；既有 native cache sort 在四组均开启。私有桌面、新进程、普通优先级、不清系统缓存；完整就绪保留需求/作业/合批连续三次清空，且共享输出及跨pool退休租约均清零。

| 样本 | 入口秒 | 完整就绪秒 | 返回 / 重载 1% low FPS | 卸载 / 返回 / 重载最大帧 ms | 三阶段 >50ms 帧数 |
| --- | ---: | ---: | --- | --- | --- |
| A1 | 4.759 | 12.775 | 48.719 / 36.754 | 31.710 / 31.792 / 51.197 | 0 / 0 / 1 |
| B1 | 3.853 | 9.730 | 38.760 / 32.989 | 32.676 / 41.956 / 40.159 | 0 / 0 / 0 |
| B2 | 3.769 | 9.442 | 45.920 / 29.840 | 30.375 / 52.921 / 45.663 | 0 / 1 / 0 |
| A2 | 4.025 | 9.897 | 38.823 / 33.330 | 54.106 / 43.686 / 43.840 | 1 / 0 / 0 |

四组 exit0、功能/共享输出/退休租约最终清空；主地图文件和796份被测脚本SHA一致，不证明外部所有DDS/native侧车、项目设置和插件未变。GPU审计均3943 surfaces、3202非白、1502带纹理、145独立纹理，不等于全部作者纹理通过。1Hz观察到其他Blender进程，无法剔除干扰或定量解释波动。A1慢样本保留；四组不足以计算p95或证实稳定小于10秒。开启组不证明返回或重载low改善，B2低于A2且仍有52.921ms返回帧，不能因为其他阶段无>50就算解决。

四组初始同为229组、2564对象、231次build、3923次prepare、2724次pack；全路线异步时序不同，不能把build/pack差异直接相减当优化收益。初始高度prepared命中63，旧路径fallback 63次、新路径0次；全路线prepared126，旧fallback126次、新0次。后台退休B1/B2各146份图片分12批，worker累计61.534/75.379ms、单批最大11.041/20.061ms；这是后台墙时，非额外CPU或可直接节约时间。B1/B2逻辑共享峰值531,189,304字节，A1为503,227,144、A2为531,189,304；不等于RSS/VRAM，不能断言长期峰值改善。两组同时切换，不能把加载差异归因于某一项。`analysis25_summary.json`、`analysis25_peaks.json`、`verification26.json`、`map24_sources/`和各样本原始文件保留。

`analysis25_peaks.json` 中 B2 返回52.921ms附近，publication相邻采样增量48.659ms、process墙时51.208ms、无同区间测试observer；两者是包含/相邻区间，不可相加或断定它们占满整帧，且缺同帧函数栈。A1重载51.197ms有12.171ms observer；A2卸载54.106ms附近process墙时51.989ms而该区间采样draw为0调用，仍缺细分归因。下一步对返回发布独立运行官方profiler与owned GDB，不能把另一条诊断路线的栈冒称map24的原帧证据。

实图后只读审查发现 DeferredAssets.active_workers 只计队列jobs和纹理头catalog，漏掉使用同一账本槽位的像素退休线程；调度使用ledger.active_workers而非该诊断接口，未发现因此超额调度。后续仅按退休stage补计，不双计catalog、不改变idle；`worker_visibility_before2.log`有4个预期失败、`worker_visibility_after.log` 26/0。同期通过真实旧queue退出、drainer持有旧worker和账本、新queue在独立账本重复申请同binding的交错：两账本各遵循自身限制、旧回调不释放新账本，最后均归零；这不证明两地图有全局共享上限。该监控修正发生在map24后，故不包含在map24源快照内，不冒称用map24验证其性能。

## 返回阶段的后续独立诊断

`material_publication_scope_20261027/map24_return27` GDB运行正常退出，主线程冻结RIP匹配、唯一suspend增量归还；但监视geometry-end后20ms时，冻结前已收到新的pre-draw标记，`marker_current=false`。主线程栈在诊断心跳UDP sendto，触发区间已过期，不能归因先前发布长帧；GDB暂停干扰该路线，不能作性能样本。

官方 `textured_direct_specs_20261027/return_official27` 调试客户端、接收器和解码均exit0，主地图及被测脚本未变；返回阶段采4551 profiler帧（engine_frame 29806–34356）。采集起点由日志标记触发，可能漏掉最初部分返回帧，且带profiler开销，不能冒称map24_B2原始帧的栈。frame 34343为50.103ms，Deferred._process包含43.000ms、_refresh_demanded包含40.225ms/自身23.284ms；同engine frame的测试宿主记录45.085ms、bookkeeping35.040ms，附近publication增量0且无queue observer。各边界不同、数值有包含关系不可相加。附近三个profiler帧的需求刷新各38–39ms；500ms观察快照区间记录11次刷新、29751输入行、16074距离计算、6541空间脚本扫描行及12次typed扫描21948行，这些是区间总工作量，并非单帧，也未记录需求clip不能说明每次刷新的原因。该返回阶段_publish_ready单帧最大包含19.026ms、shared图片release最大包含0.507ms，未复现map24_B2附近48.659ms发布增量。

证据路径 `return_official27.summary.json`/原始bin、phase report及receiver/decode日志在上述目录；另有在采集中记录的扩展脚本SHA：worker official `7a47eb102b4f8aff262ba4ce9561f00993aafe27c9316bdad118d413c4554f3d`，receiver `22f4b7ce54004120bf515bfbc9e5574117bb708b439f461f0cac88ce23f8d6a2`，decoder `e17a508f85dbf8fdf8fe995a49ffa93f363493af8131f8f489ac630199da5bd4`。它们不在runner默认的796文件散列清单内，该记录不表示已经核对其采集前后的独立快照。
