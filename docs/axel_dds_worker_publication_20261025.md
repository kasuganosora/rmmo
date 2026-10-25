# DDS 后台准备与分帧发布

## 复现与归因

延续 `axel_texture_phase_20261025.md` 的 F2/F3 返回样本：帧长分别
73.794/73.664ms，Deferred publication 为 71.527/71.019ms。没有将它们归为
OS 空闲，也没有凭这两个时间认定主线程正在等上传锁。

本轮用相同已安装引擎 `52f532a05155b18e9614b48531e5fe136bea3a76fc240466adfe7110e0fbaee6`
和原代码，通过私有桌面运行真实地图及官方 profiler（原生调用按 caller 归因）。
`publication_official01` 共收到 7,352 帧，解码零错误，地图功能断言全部通过。
返回 frame 29474 为 83.172ms，Deferred publication 79.891ms；函数链为：

`Deferred._publish_ready → WorldDocument._mesh → SurfaceMaterials._texture`

同帧 `_texture` 累计 73.443ms，其中原生 DDS 文件读取 12 次 / 25.275ms，
`Image.load_dds_from_buffer` 12 次 / 13.517ms，`ImageTexture.create_from_image`
12 次 / 14.984ms。profiler 会加入开销，脚本/worker 的 inclusive 数字可能重叠；
这是一条归因证据，不能把函数总量全部相加或当作正常性能样本。

原因是三处入口主动跳过 DDS：Deferred 的像素请求、MapLoader 的初始预取、
编辑器的 TerrainTexturePreparation.requests。压缩减少了字节，但没有消除读取、
Image 构造和上传；跳过准备还绕开已有的“一次一个纹理”发布切片。此前只观测
`_publish_items` 的 publish_slow 未覆盖前面的 `_mesh`，因此漏掉了真实慢段。

## 修改范围

- 共享 `compressed_texture_source.gd` 只读 BC1/BC3/BC5 完整 mip 压缩块，后台
  直接创建压缩 Image，不展开 RGBA、不重新生成 mip、不另存像素缓存。
- DDS 纳入原来的源 ID、共享生产者/消费者、预算准入及取消合同。主线程逐张
  上传完整纹理，实际记录绑定沿用同一 Texture2D；未扩大队列或提高交互预算。
- 初始 MapLoader 复用编辑器 decode，消除同类旁路；白模仍零纹理准备。
- 保留 normal XY、alpha、来源身份和真实上传字节。1×1 完整 DDS 没有 mip 标记，
  也不调用不支持压缩图的 generate_mipmaps。
- 头部尺寸/格式/层数/长度检查用于限制分配。可信包沿用路径身份，没有新增
  DDS/原 PNG 全文件 SHA 认证。严格测试仍遵守原源身份检查。

没有修改正式 DDS、源 PNG、地图、模型几何或原生模型文件，也没有修改引擎。
BC5 shader 解码和已交付资源画质合同沿用上一轮；本次验证的是准备/发布方式。

## 独立红绿

`test_compressed_texture_publication.gd` 使用临时外部地图及 12 个唯一 DDS 纹理
角色，经过真实 CPU preparation、Deferred、WorldDocument 和 GPU 回读。

- `compressed_publication_red01.log`：90 通过 / 16 失败，复现 DDS 请求被删、
  PNG 被误准备、压缩块丢失及与普通 DDS 材质绑定不一致。
- `compressed_publication_green01.log`、`dds_worker_test_compressed_texture_publication_green02.log`：
  108 项通过。每次发布最多一个纹理，零主线程 DDS 重读；零 hot-cache 预算、
  取消、失效 ticket、CPU/GPU owner 释放及每张纹理完整 mip 指纹一致。
- 原 PNG streaming 103、prepared material publication 64、texture tickets 18、
  原 prefab texture preparation 63 项通过，无引擎/脚本错误。
- 随后追加 1×1 BC1/3/5 实际 GPU 完整块回读，`compressed_publication_green04.log`
  为 **115/115**，shader normal-XY 标记也纳入原/新指纹。
- 编辑器/helper 271 项通过，涵盖 24 个格式/头/尺寸组合和 18 类边界；完整
  证据见 `axel_editor_dds_adaptation_20261025.md` 的后续章节。

## 整图对照

首轮候选 `dds_worker_map_B1` **失败且已保留**，不能计入性能收益：共享池 offer
仍假定所有 row 都有 PNG 专用 `cache_limit`。新增 DDS 行没有此字段，GDScript
报错发生在持有共享 mutex 后，导致后续生产者不能继续。初始需求不能收齐，退出
未能完成回收，最终由测试宿主在 420s 截止；正式地图/源脚本未变。

GDB 对该已失败测试进程（PID 18372）抓取一组原生栈：主线程在退出树时 SleepEx
等待，多个 `GDScript::_prepare_job` 线程在 RtlEnterCriticalSection。该次 all-stop
收栈停顿约 7.281s，样本早已功能失败，完全不作正常耗时证据；没有靠减去调试停顿
计算收益，也没有把这个接入遗漏误报为引擎缺陷。

增加 `test_shared_compressed_images.gd`，使用真实 shared pool、两个 worker、
停放的 follower、生产者取消和续作。`shared_compressed_red02.log` 独立复现相同
字段错误。修复将单独/共享的 workspace 计算统一到 `PrefabTextures.workspace_bytes`，
并把输入字段解析、序列化身份和预算计算移到 mutex 外，锁内仅查共享 entry 和
填 offer。DDS 无需伪造 PNG cache_limit 或额外保留 RGBA 工作区。

`dds_worker_test_shared_compressed_images_green03.log` **27/27**，原共享池 **32/32**；
实际 MapLoader worker/缓存隔离测试也通过。随后 `dds_worker_smoke02` 正常初始
full-ready **15.791s**，零错误、完整回收、零主线程 DDS 重读；它只是功能确认，
不能由此宣称总加载提升。初次失败后的整组对照重新编号为 `dds_worker2_map_*`。

固定上述引擎及已安装 88 个 DDS，按 A1（旧）→B1（新）→B2（新）→A2（旧）
运行。仅在进程间替换六个生产文件，并保留旧/新原字节快照；其余生产脚本和
shader SHA 必须一致，结束恢复候选。无其他 GPU/CPU 压测并行，不修改优先级、
QoS 或 OS 缓存。几何、边界、模型元数据缓存仍按历史夹具禁用。

结果以本轮完整记录为准；两次候选不足以给出 cold p95 或稳定性结论。范围仍是
地图/预制件纹理，导入模型材质保持白色，HUD/MockServer 关闭，不能称全游戏完成。

### 正常引擎 ABBA 结果

| 样本 | 入口 | full-ready | 卸载 max / >50ms | 返回 max / >50ms | 重载 max / >50ms |
| --- | ---: | ---: | --- | --- | --- |
| A1 旧 | 6.595s | 14.655s | 32.068ms / 0 | 72.411ms / 1 | 47.539ms / 0 |
| B1 新 | 6.236s | 15.232s | 32.074ms / 0 | 41.344ms / 0 | 47.002ms / 0 |
| B2 新 | 4.676s | 13.400s | 32.192ms / 0 | 41.874ms / 0 | 51.271ms / 1 |
| A2 旧 | 7.437s | 17.923s | 41.203ms / 0 | 100.043ms / 9 | 57.376ms / 2 |

四轮功能断言全通过，源/地图未变，退休量同为 504 units / 3677 specs。
full-ready 两样本均值 **16.289s→14.316s**，差 1.972s；B1 仍比相邻 A1 慢，
不能据这组均值宣称稳定缩短 1.97s，更不能称 cold p95 已达标。

返回 publication 最大值 **70.156/97.175ms→29.325/24.166ms**；对应 service
为 70.631/97.768ms→33.106/27.493ms。主线程 DDS 文件重读新组为零，所有 170 次
上传都命中 prepared Image；主线程仍负责实际 Texture2D 提交，不宣称 GPU 上传
已经完全离开主线程。

工作量核对：

- 总上传次数旧/新均 170。DDS 从 124 次 / 430,617,304 B 变为 148 次 /
  508,911,392 B，原始像素从 46 次 / 564,742,192 B 变为 22 次 / 212,420,680 B。
  总提交 **995,359,496→721,332,072 B（-27.53%）**。这是已有 DDS 被一致采用，
  没有再转换资源；累计提交量也不是峰值 VRAM。
- 初始 MapLoader 的 texture_decode 旧组 493/490ms，新组 46/39ms。这段本来就
  与网格准备并行，所以不能把其差值直接加到整图 full-ready 收益上。
- 新组 worker compressed_reads 140/148 次，累计约 348/349ms；剩余原始像素
  cache_decode 约 552/506ms。这些是多 worker / 多阶段聚合，不是关键路径长度。
- 同时保留反向指标：material misses 80/76→144/140；最终来源身份检查
  265→4184/4170 次，final_sha_us 约 78ms→1061/1043ms，但 full-file SHA reads
  始终为零。重复路径检查、共享像素复用时的检查、材质失效范围仍需收窄。

### 剩余长帧与诊断边界

B2 重载 **51.271ms** 未解决，publication 最大 35.488ms、service 最大 37.468ms；
该帧 process 约 36.312ms，不能标成 OS 空闲。此前原生上传观测有约 29.7ms 的
单次跨度，仍需同帧归因，不能凭相近数值认定两者是同一次。

另跑 `dds_worker_subphases03`，仅增加 Trace 和 `--include-reload`；功能通过，
4570 events、零 dropped。诊断返回帧 145.440ms 中 collect_candidates 90.366ms、
rebuild_catalog 22.765ms；诊断重载帧 119.954ms 中 reference:36 的 instance_begin
52.579ms，观察器约 19.528ms。该次主线程纹理 upload 最大只有 7.068ms，未复现
正常 B2 的上传跨度，且 Trace 本身改变调度/记录开销。这些用于确定下一处观测范围，
不混入正常 ABBA、不与正常样本直接相减，也不声称需求刷新已修复。

## 用户提出的“网格与纹理并行准备”

检查实际入口：MapLoader 在前台开始地形/模型准备前已经启动 texture prefetch，
最多三个 CPU decode worker，本轮补齐 DDS 后也走这里；初始入口不是完全串行。
但 `ChunkReferencePreparation.prepare` 仍在引用恢复、几何/碰撞/道路准备之后才
调用 PrefabTextures.prepare，区块返回有真实的串行尾巴。

用 `bench_chunk_geometry_texture_overlap.gd` 取真实地图的两个完整建筑组，每组
A1→B1→B2→A2→A3→B3→B4→A4：A 一个 worker 顺序调用同样的两项 CPU 工作，
B 两个固定 worker 各做一项。每次清空 prefab decoded cache，磁盘和 OS cache
保留；每个样本完整 join，再计算几何与每张图完整 mip 字节指纹；无 GPU、无全局
共享池 resident shortcut，合并预留上限 1 GiB。它是调度可行性试验，不是生产队列
参数或完整冷启动测试，尚未把这个分工接入区块调度器。

`geometry_texture_overlap01` 16 样本零失败，结果如下（各模式四样本中位数）：

| 真实建筑组 | 串行 | 并行 | 重叠时间范围 | 每次相同产出 |
| --- | ---: | ---: | ---: | --- |
| building_883dd20afc1eaef90960 | 316.682ms | 279.789ms | 64–102ms | 34 records、30 prefab、26 images / 134,195,380 B |
| building_061ac981f7e8922e09fa | 317.446ms | 189.704ms | 88–115ms | 66 records、59 prefab、28 images / 117,422,768 B |

每组几何 SHA 与像素 SHA 在所有 A/B 样本一致。前者每次 20 DDS + 6 原始缓存命中，
后者 24 DDS + 4 原始缓存命中，源解码零次；工作次数没有增加。合并预留分别
536,461,836 / 357,485,464 B，这些是预算上界，不是实测 RSS。

保留所有波动：第一组 A1 为 454.873ms，第二组 A4 为 464.188ms，未删除慢样本；
第二组部分 B 的 pixel step 约 193–195ms，高于相邻 A 的 154–165ms，说明并行确实
有竞争，不能只用“max(两段)”理想公式预测整图收益。下一实现应在原有总 worker /
内存准入内让唯一纹理生产任务提前可调度，并继续允许 follower 停放、取消和完成
乱序；不能每个建筑再开一个不受总额约束的线程。单组中位数收益不能累加成整图秒数。

## 白模回归与来源冻结

候选 `dds_worker_white03` 功能通过，但 full-ready **10.342s** 超过此前目标，
原样保留。随后同一六文件旧/新 ABBA、相同普通优先级和历史缓存范围：

| 样本 | 入口 | full-ready |
| --- | ---: | ---: |
| white A1 旧 | 6.944s | 14.297s |
| white B1 新 | 4.211s | 8.250s |
| white B2 新 | 2.900s | 7.113s |
| white A2 旧 | 4.261s | 8.740s |

四轮功能全通过，纹理计数为空。旧组也有明显慢样本，本组不能支持“DDS 后台接入
拖慢白模”的归因，也不把 B1/B2 当作重新证明白模稳定 p95；本轮白模没有开启新的
纹理工作。慢样本原因未定，不能随意归到 OS/GPU 空闲。白模回归只跑 origin，
不能由这些样本声称重新覆盖了白模全部卸载/返回阶段。

结束后候选生产脚本与 B2 的全部 source_before SHA 一致；88 个已安装 DDS
328,566,704 B 与发布凭据的 SHA 全部一致。详见 `dds_worker_final_sources_assets.json`。
本轮没有继续改动素材，也没有把单次首次缓存、诊断 instrument 或失败退出样本混成
正常时序收益。

证据根目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/material_submit_review_20261025/`。
官方 profiler：`publication_official01.*`；独立回归：`compressed_publication_*`、
`dds_worker_test_*`；编辑器：`compressed_editor_worker_01/`；整图：
`dds_worker2_map_{A1,B1,B2,A2}.*`、`dds_worker2_map_abba_summary.json`；
六个生产文件快照：`dds_worker2_abba_sources/`。首次失败原样保留在
`dds_worker_map_B1.*`，原生栈在 `dds_worker_failed01.stacks.jsonl`，初版源快照在
`dds_worker_abba_sources/`。
CPU 并行可行性：`geometry_texture_overlap01.{json,log,err.log}`；
白模：`dds_worker_white03.*`、`dds_worker_white_pair_{A1,B1,B2,A2}.*`；
诊断 Trace：`dds_worker_subphases03.*`。它们各自的用途与限制如上。
