# 纹理末端交接去重与重载渲染现场（2026-10-27）

接续 §172，仍使用 `codex/latest-map-runtime-review`。主目标是完整加载与 1% low，
不是只减少后台累计时间。地图/prefab 纹理启用，导入模型仍使用无材质 native；结果
不能外推为全材质游戏验收。后台 GPU 上传与完整建筑提前通知候选继续默认关闭。

## GDB：当前捕获没有证实后台上传锁等待

本轮证据目录为
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/texture_reload_wait_20261027/`
（下文 W）；独立交接测试放在相邻 `texture_transfer_20261027/`（V）。
沿用 engine09，EXE SHA `40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`。
两次 GDB 均打开后台上传候选，复制 map18_B2 的路线，使用心跳诊断适配器。

- `map01_draw`：phase2 重载，最后接收的标记为 PRE_DRAW；本地接收间隔20.8293ms。
  主线程栈为 `NtGdiDdDDISubmitCommandToHwQueue → AMD/Vulkan →
  RenderingDeviceDriverVulkan::command_queue_execute_and_present:3263 →
  RenderingDevice::execute_chained_cmds → _execute_frame → swap_buffers →
  RenderingServerDefault::_draw → Main::iteration`。3263是 `vkQueueSubmit`；此处
  已持有 submit_mutex，现场不是等待获取该锁，也不是 transfer-worker mutex 栈。
- `map02_service`：最后接收标记为 GEOMETRY_END，间隔21.9216ms，但实际暂停已在
  `RenderForwardClustered::_fill_instance_data:867`，随后栈无法继续展开。只能证明
  这个瞬间在填写渲染实例数据，不能声称捕获到了完整的绘制前服务链。UDP最后接收
  标记与实际冻结之间仍可能推进；不能把该接收间隔全部归给栈顶函数。

两次都有 PID/birth/EXE/主TID/FILETIME 身份核验、SuspendThread前后计数记录、
暂停时RIP与GDB RIP相同；归还本机一个暂停计数后在GDB all-stop下解码。两次
engine/GDB退出0、freeze_valid=true、failures/errors为空、源码/地图未变。主线程
与渲染执行角色仍共用线程，`RenderingServerDefault.create_thread=false`。
没有新增引擎修改，也没有以这些诊断样本计算加载或帧率收益。

map01冻结前28ms的队列快照已有146次后台上传完成，shared outputs/retained bytes
为0；geometry active_workers为0，6个结果已ready，仍有559个需求未发布。相邻真实
绘制约2170 draw calls。因此下一步应对齐主线程发布、合批commit和原始来源绘制的
持续时间；这只是候选方向，不足以认定全部低帧率的根因，更不证明上传锁从不等待。

独立渲染线程已有历史实验与引擎退出/字形修复。§120–121记录逐网格同步读回曾抵消
收益，后来已有批量读回/CPU桥接；不能直接引用旧14秒结论，也不能无复测直接启用。

## 可复现的重复工作与修改

`PrefabTexturePreparation.verify` 的 mounted/trusted 分支只比较内存中的来源标识，
却仍对每个路径在比较前后各调用一次 `Paths.allowed`。同一包的共同祖先反复访问，
共享池还为每个标识分别加锁。这里没有夹在两次检查之间的源文件读取。

新增默认开启的 `batched_final_handoff_enabled`：

- mounted 标识在 `SharedPrefabImages.source_identities_match` 的一次短锁内比较；
  锁内只有标量字典访问，不做文件/GPU工作，不等待生产者。
- 身份比较后使用已有 `Paths.allowed_many`，本次调用内每个路径/共同祖先只检查一次；
  不缓存跨调用的路径决定。错误根、目录链接、取消、失效 consumer 均继续拒绝。
- standalone trusted 同样比较路径标识后做批量边界检查。
- 实际读取 SHA 的 strict standalone 分支保持逐文件前后检查，prepare/read/decode/
  缓存写入、预算、共享身份代际、纹理像素和GPU上传数量均未改。

诊断参数 `--without-batched-texture-handoff` 保留旧实现；runner记录开关，实际
执行由 `final_identity_batches/final_path_batches/final_path_link_checks` 交叉验证。
`final_sha_us` 旧指标名保留以便历史比较；在mounted路径它仍不是SHA文件读取耗时。

## 独立复现与边界验证

`test_texture_final_handoff.gd` 创建外部临时标量来源，以6线程执行同一来源集。
没有纹理codec/GPU/地图成本；3来源各线程120轮，64来源各线程24轮。
旧源码先运行 `handoff24_before`：80条通过，重复末端检查可复现。

最终 `handoff26_final` 在同一进程 ABBA，88条通过、errors为空：

| 来源/线程轮数 | A1旧墙钟 ms | B1批量 ms | B2批量 ms | A2旧 ms |
| --- | ---: | ---: | ---: | ---: |
| 3 / 120 | 106.466 | 38.662 | 31.833 | 100.763 |
| 64 / 24 | 376.099 | 65.448 | 66.185 | 377.410 |

两组工作分别始终2160/9216次标识命中、0次SHA文件读取。批量实际祖先检查为5760/
9936次；共享父目录只在当前调用内复用。并行worker累计时间与墙钟不同，不相加解释
地图时间。以上只证明独立末端交接收益。

`test_texture_handoff_links.gd` + W/run_links03.py：9条通过、errors为空。先接受
真实目录，再由夹具把测试拥有的目录换成实际junction；新旧实现均拒绝相同路径的
后续mounted/standalone交接。不是伪造is_link的mock，也没有借复用跳过下一次检查。

既有CPU回归：source_identity43、preparation63、shared_images32、parallel_chunk32
全部通过。涵盖错误身份、缺失/取消consumer、空包取消、严格读取替换、两种法线变体、
源代际与缓存退休等原合同。本轮未新增材质/模型导出，无新增编辑器功能。

失败样本保留：handoff23测试直接在类常量上调用Script实例方法，解析失败；修正后
旧源码handoff24通过。handoff25虽功能通过，但反射未发现static属性，四组实际都跑
了新默认路径，不能算ABBA。handoff26改为直接设置static变量，并断言每轮实际批量
计数与开关相符；它才是上述ABBA数据来源。

## 实际地图对照

map04完成ABBA。统一关闭后台GPU上传和建筑提前通知候选；只切末端批量交接。
新进程、OS缓存不清空、普通优先级、私有桌面、没有GDB/原生调用追踪。四条均退出0、
functional_ok=true、errors/failures为空、源码/地图不变，自有进程均退出。
796个匹配SHA的测量源文件保存于 W/map04_sources；原始结果、host记录及
`analysis05_summary.json` / `analysis05_peaks.json` 同目录保留。

| 样本 | entry s | 完整就绪 s | 返回1% low FPS | 重载1% low FPS | 卸载/返回/重载 max ms |
| --- | ---: | ---: | ---: | ---: | --- |
| A1旧 | 5.412968 | 10.978213 | 43.528 | 28.656 | 33.393 / 44.938 / 47.424 |
| B1批量 | 4.043802 | 9.838119 | 42.753 | 29.713 | 36.245 / 36.658 / 37.258 |
| B2批量 | 3.977166 | 9.659616 | 39.547 | 32.380 | 99.981 / 46.456 / 37.500 |
| A2旧 | 4.001774 | 9.651346 | 41.996 | 31.719 | 33.359 / 43.763 / 53.893 |

B2卸载6帧>50ms，A2重载1帧>50ms，其他所列移动区间0帧>50ms。不能宣称全程无尖峰。
1% low仍是最慢ceil(N×1%)帧平均时长的倒数；四条样本不能作为加载p95。

| 样本 | 初始末端交接累计 ms | 全程末端交接累计 ms | 全程身份命中 | 批量调用/实际祖先检查 |
| --- | ---: | ---: | ---: | --- |
| A1 | 468.369 | 1042.115 | 4042 | 0 / 未单独计数 |
| B1 | 92.463 | 217.350 | 4102 | 387 / 8299 |
| B2 | 87.132 | 215.244 | 4112 | 389 / 8328 |
| A2 | 409.290 | 1018.762 | 4112 | 0 / 未单独计数 |

初始均1626次身份命中、0次final SHA读盘；新路径初始实际祖先检查3378次。全程该段
累计墙时减少约79%，但它属于并行worker，不能把约0.8秒直接从加载墙钟扣除。入口后
收尾A1/B1/B2/A2为5.565245/5.794317/5.682450/5.649572s，未稳定缩短。保留确定的
去重收益，不声称整体加载或low已经改善，也不按首条慢入口计算加速比。

四条实际纹理工作仍是170次上传/721332072字节，主线程upload累计305.694/309.079/
297.088/314.893ms，无后台上传；shared produced均146，最终outputs/consumers/
retained bytes为0。原生/地图渲染审计均3943 GPU surfaces、3202 nonwhite、1502
textured、145 unique textures；最终229 groups/2564 sources/361 surfaces，所有
retirement余额归零、map_freed=true。

初始几何工作一致：231 builds、3923 prepares、2724 packs、228 worker surfaces。
整路线builds为596/618/626/606，packs7120/7379/7371/9667；前三条prepares7851，
A2为11661。**A2额外3810次来源访问必须继续排查，不能被最终画面相同掩盖。** 它发生
在旧末端交接路径，不能算本轮去重的反向回归，也不能以移动时序变化直接豁免重复工作。
115.309s和115.819s两段快照新增2606/1099次prepare，晚期整批重扫的触发尚未定位。
证据 `map04_A2_preparation_jumps.json`；下一轮检查request/失效原因而非扩大预算。

draw_calls>=2000的观察时长3.779/3.958/2.878/2.496s，并未随交接成本单调改善。
host相关进程观察中A2重载有Blender，其余三个重载和四次初始加载未观测到；这不是
完整OS/GPU空闲证明，也不能把所有差值归给外部负载。分析工具同在本机，未宣称独占
性能测试主机。

## 未解决边界与下一步

1. B2卸载尖峰出现在62.052–64.600s，最大99.981ms；相邻快照active_workers/jobs/
   reserved bytes/shared outputs均0，batches groups/pending与draw calls均0。
   部分帧没有queue observer，最大帧附近observer9.016ms也不能解释全部100ms。
   previous_process_wall可见约90ms空档，官方TIME_PROCESS是采样值，不能直接当该帧
   独占CPU时间。仅能缩小范围，**没有栈，不归类为OS空闲，也没有算作修复**。
   完整6帧和相邻状态见 `map04_B2_unload_context.json`。
2. A2重载53.893ms附近draw wall约38.941ms，主线程仍在发布，另有8.132ms observer；
   没有对应原生栈，不能把各项跨帧/重叠数值直接相加归因。
3. 优先给A2晚期3810次重扫补batch timeline的请求、前缀失效和generation链，在固定
   到达/退出序列的测试里复现后消除重复扫描；同步对齐高draw区间的来源发布和commit。
   不提高预算掩盖工作量，不把默认关闭的候选当成已交付收益。
4. GDB若继续瞄准绘制前区间，需要在冻结后交叉核对后续已到达心跳，避免把最后接收的
   GEOMETRY_END当作冻结瞬间仍在该区间的证明。本轮两次实际栈仍保留。
5. 既有独立回收58–77ms、首次真实材质提交、首个3D帧、旧AV/road-paint门控没有被
   本轮解决；当前没有理由宣布主要剩余耗时合理或目标完成。
