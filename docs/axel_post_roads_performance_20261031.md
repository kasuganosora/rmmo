# 街区完成后的加载与 low 帧复测（2026-10-31）

## 固定边界与证据

街区会话 `01a10fd2-fe81-7772-8270-8bdcb713321f` 完成后开始。没有修改正式地图。
证据根目录（以下简称 P）：
`D:/code/rmmo_runtime/review_artifacts/axel_post_roads_perf_20261030_01/`。

- 代码基线 `b52de516e47da4f9ed7ef92a90a34dc661c1e179`，加现场已有的道路/环境等工作区改动；`fixture.json` 保存逐文件身份，冻结副本位于 `P/project`。
- 临时地图 `P/map_snapshot/map.gltf`，SHA-256 `ee80500d6156c79d68a04315931c024319d92fb351567e5ced38d0ddb7c22697`；连同 2172 个定义文件冻结。不能与更早的小地图/白模数字直接相减。
- 默认补丁 Godot 4.8 beta1 candidate08，EXE SHA-256 `69fccbed237845e578fdb279d9951ac92c71a29d2a1c7c660903064296cb3303`。
- 正常 GPU 游戏模式、纹理/UI/HUD 开启，独立非激活桌面；每次私有用户目录，相同设置与六次 HUD 快照回放。OS 文件缓存、产品文件与 shader 缓存共享，**不是严格冷盘样本**。
- 完整就绪仍是地图 pipeline 开始，到当前 demand/jobs/stream/batches 连续三帧为空且游戏可操作；没有改成进入游戏瞬间，也不强制全部纹理 mip 常驻。
- 正常对照与官方 profiler/GDB 诊断分开；四次 ABBA 期间不并行运行其他 Godot/编译器，`host.json` 每 0.5 秒观察，四次其他引擎/编译器 PID 列表均为空。源码与地图运行前后相同。

## 测量器先去除重复复制

原观察器每 500ms 深复制整个 Deferred profile，包括最多 1024 条历史 stage。现在只取标量/小型预算账本，新观察到的 stage 每条复制一次，计时停止后才取完整嵌套 profile。队列实例 ID 隔离历史，最终游戏地图的 Deferred profile 也得到保存。

`test_deferred_profile_snapshot.gd` 9/9。探索样本 `baseline_on_00` 的观察器累计 2.532s；修改后 `baseline_on_01` 为 1.007s。这两次不是严格交错对照，**不把这个差值当游戏性能收益**。后续干净 ABBA 中观察器仍有 45–88ms 最大值，剩余观察成本/调度等待还须细分，不能称测量噪声已清零。

## 远景候选目录：去掉每次全图扫描

官方 profiler `baseline_loading_profiler_official.json` 的稳定段捕获：DistantBuildingProxy.tick 114 次、累计 2.239s、平均 19.64ms；相关 get_meta 199500 次、has_meta 182970 次。碰撞邻域优化后的查询已约 0.069ms/次，继续死扣碰撞不是本轮优先项。

新增 `distant_proxy_sources.gd`，在既有 WorldStream 发布/接管入口登记潜在建筑预制件。节点退出时同步移除；临时地图 detach/reenter 恢复；重新加载同名节点按新实例登记。目录不缓存 mesh/材质/可见性/姿态判断，因此冻结、恢复、材质覆盖和逐层隐藏仍立即生效。没有 runtime 所有者的通用地图沿用扫描。

独立 4160 来源、64 个候选、120 次 tick：访问量 **499200 → 7680**；示例总耗时 **836.5 → 59.4ms**（另一轮 85.2ms），不作为整图帧率。最终生命周期测试 17/17，既有 admission 测试 6/6。

干净交错对照（A 扫描、B 目录；代码完全相同、只有诊断开关不同）：

| 样本 | 入口 s | 完整就绪 s | 稳定段 p95 ms | 1% low FPS | 最大 ms | >50ms 帧 |
|---|---:|---:|---:|---:|---:|---:|
| catalog_A1 | 17.097 | 80.188 | 33.481 | 20.09 | 55.212 | 6 |
| catalog_B1 | 16.559 | 78.228 | 27.635 | 26.28 | 43.662 | 0 |
| catalog_B2 | 17.908 | 80.135 | 28.717 | 24.25 | 58.276 | 1 |
| catalog_A2 | 16.972 | 82.495 | 34.351 | 19.52 | 55.737 | 11 |

工作量：四次实例均 1505；batch 来源 2309、来源 surfaces 3314、render surfaces 358、来源 vertices 2161253、groups 216。候选访问 A 为 1861795/1887568，B 为 84534/85157，约减少 95.5%。本机位 active proxy 均为 0，收益来自移除无效扫描，不是少画建筑。调度造成 prepared visits 等小幅变化，不能说所有计数逐项相同。

稳定段 low 改善成立；完整加载均值约 81.34→79.18s，仅两对且有波动，**尚不主张稳定缩短总加载**。加载收尾最大帧仍 661–724ms；角色窗口首次打开仍 140–205ms。汇总见 `P/catalog_abba.json`，全量数据/日志保留在各样本目录。

## 实际 GPU 代理缺失 LOD：已修复

旧代码先打包上传数据，之后才加 LOD/改压缩标志；实际提交使用先前快照，导致 LOD 算了却没有上 GPU。现在只在最终 LOD/标志确定后打包一次。测试额外检查实际代理 GPU 索引，不再仅验证独立合成网格。

扫描与目录的旧上传路径都 23/24，失败项相同，八张对照图逐像素一致；修复后 `proxy_gpu_final_lods` **25/25**。远景实际三角形 82788→49008，draws 78→43；近中景保持原始模型。详见 [受影响模型/管线复验](distant_proxy_lod_review_20261031.md)。以上目录 ABBA 在 LOD 修复前完成，不能给它附会整城收益。

## 正在验证、尚未默认启用

1. 原生读入时已拿到的 CPU surface 字节此前没有交给 CPU 几何消费者，后者再次从 RenderingServer 取回。候选通过已安装引擎的 `load_native_scene_with_cpu_surfaces` 保留同一代输入，按需解码一次；原生模型身份、预算、worker 数量不变。几何修改必须回退当前数据，共享对象去重，取消释放没有使用的字节。`native_cpu_handoff_enabled=false`，真实地图交错对照未完成前不启用。
   - 最初两个用例因测试路径分隔符失败，保留，随后修正测试。
   - `native_handoff_red_02` 19 项中预期失败 1 项：旧路径 renderer_surfaces=2；green_02 为 19/19、native=2、renderer=0。
   - 增加 4 worker 并行/取消后，`native_handoff_parallel_03` 与 Vulkan `native_handoff_gpu_04` 均 **33/33**。
   - 预算原本包含 mesh_storage×4 与 decoded capture×4，候选不削减预留。该保守包络不是实测 RSS；仍须验证整图保留与释放。
2. GDB `loading_native_stacks_01` 127 个采样中，主线程样本 15/16 明确为 `ArrayMesh::_set_surfaces → RenderingServerDefault::mesh_create_from_surfaces → mesh_generate_pipelines → ShaderRD::version_is_valid → _compile_ensure_finished → WorkerThreadPool::wait_for_group_task_completion → Semaphore::wait`。这是 shader 编译等待，不是已证实的上传 mutex 争用。正常渲染/退出完成，捕获已 detach；GDB 样本耗时不计入性能对照。尚不能把每次 600ms 尖峰都归给这条栈；接下来须独立复现并关联阶段。
3. 原生公会仍是包含纹理的 281810329 字节 SCN；逻辑 GLB key 的 rawsource_reads=0，不能误称读取原 GLB。60 个内嵌图像 mip 数据约 563MB，后续考虑既有纹理拆分迁移，但需独立资源验收，尚未实施。

保留地图/道路等其他会话工作区改动；本轮只提交自己验证完成的代码。目标仍在进行，尚未宣称大块头成本合理。

## 继续定位：候选真实命中与后台提交边界

已验证的目录/LOD/观察器修改在 `a25de942` 提交并推送；以下为后续未完成候选，不能混入该提交的验收范围。

首版 `native_A1/B1/B2/A2` 正常完成，但公会 footprint 没有 `direct_template_reuse` 字段，候选错误地受该标记限制。公会始终 renderer=2099、native=0，入口 16.86–17.12s；因此这组不是 CPU handoff 对公会的有效对照。B2 期间另有一次约十余秒的目录枚举，已停止，保留其宿主干扰边界，不将该样本当严格时序证据。

CPU handoff 已改为按具体 mesh 身份/几何版本生效，去掉与整模板复用无关的门槛。又把请求限定为实际 CPU 几何消费者的显式参数；离线 import/audit/export 继续返回普通资源图，避免瞬态 hint 污染后续 footprint 审计。独立 `native_handoff_legacy_descriptor_05`、`legacy_gpu_05` 各 33/33；加普通读者隔离后 `native_handoff_scoped_gpu_06` **35/35**。默认仍关闭。

首个真实命中样本 `native_legacy_gate_B1`（显式调用范围收紧之前）：入口 **14.289s**、完整就绪 **74.670s**；2007 mesh / 2099 surfaces 全部由 native 输入交接，renderer_surfaces=0；capture 活跃 **254866us**、墙钟 **282085us**，此前 A1 对应 **2254467 / 2767299us**，collision faces 同为 16228944 字节。整图零失败/错误、其他引擎/编译器为空。它证明入口重复回读已去除；一对不同阶段代码样本不能用于宣称总加载 p95，收尾最大 **664.94ms** 仍未解决。

测量器还发现完整游戏每帧 Deferred 统计错误地读了仅 mesh fixture 使用的 `mesh_map`，因而一直为零；500ms 队列快照是正确地图。已统一观察来源，后续样本不能再根据旧的每帧零值判定 Deferred 空闲。

`probe_mesh_shader_submission.gd` 使用实际 terrain shader 和 `_surfaces` 接口，独立新 shader 变体仅用于诱发首次提交，不是相同内容的性能验收。`shader_submit_repro_01` 主线程调用 357–873ms；后台调用 732–790ms、主线程最终挂接约 0.06–0.10ms，但后台期间仍有 337–366ms 帧。不能直接把完整上传迁入后台当作问题解决。

细分后的 `shader_submit_stages_02` 确认：后台准备期仍有 **346.108/379.838ms** 帧，挂接后的 12 帧最大 **3.610/2.095ms**，验证读回仅 **0.865/0.717ms**。当前主要疑点是后台构建与正在运行的渲染主线程之间的引擎同步；用带符号 GDB 单独抓这个缩小后的用例，正式流水线暂未改成后台 GPU 上传。

`shader_worker_stacks_03` 正常结束，GDB 41 个样本、已 detach；主线程 **37–40** 明确为 `RtlEnterCriticalSection → recursive_mutex::lock → ShaderRD::version_get_shader → SceneShaderForwardClustered::MaterialData::update_parameters → MaterialStorage::_update_queued_materials → update_dirty_resources`。即使新 mesh 未挂接，全局 dirty material 队列也主动触碰仍在后台编译的 shader，并等待其版本锁。其余样本也出现驱动 Present/fence 等待及图形 hook，不能把所有帧归为同一原因。

继续审查后，没有采用全局 dirty 队列延期：这可能让已进入实际绘制的新材质缺少首帧 uniform。当前 candidate09 只在后台创建新材质 RID 时，先完成其 3D shader 编译，再执行 material_set_shader 登记 dirty 队列；主线程创建、既有材质改参数、实际绘制顺序均保留。四文件候选位于 `P/engine_material_queue_candidate09`；原始文件与已发布 candidate08/官方归档 SHA 核对后，已在独立源码树开始编译，默认引擎未替换。须先用独立复现和首帧/更新/取消合同证明，再考虑正式后台提交。

## CPU handoff 完整交错对照（仍待返回加载验证）

`native_final_A1/B1/B2/A2` 同一冻结工程、地图、默认 candidate08 引擎，A 关闭/B 开启 handoff；四次源码和地图未变、其他引擎/编译器 PID 为空、错误/失败均为空。汇总 `P/native_final_abba.json`。

| 样本 | 入口 s | 完整就绪 s | capture 活跃 ms | capture 墙钟 ms | native / renderer surfaces | 稳定段 p95 ms | 1% low FPS |
|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | 16.853 | 78.584 | 2301.696 | 2866.412 | 0 / 2099 | 28.706 | 24.45 |
| B1 | 13.911 | 74.588 | 229.716 | 254.831 | 2099 / 0 | 28.947 | 24.73 |
| B2 | 14.589 | 75.832 | 277.114 | 342.138 | 2099 / 0 | 28.652 | 24.37 |
| A2 | 16.833 | 79.820 | 2309.355 | 2844.746 | 0 / 2099 | 28.637 | 24.58 |

本组入口均值 **16.843→14.250s**，完整就绪 **79.202→75.210s**。仅两对，不声称总耗时 p95 已确定。2007 mesh、2099 surfaces、16228944 collision face 字节、2309 batch 来源、3314 来源 surfaces、358 render surfaces、2161253 来源 vertices、216 groups 均相同；调度相关重建/访问次数有波动。稳定段 low 基本不变，收益集中在去除 GPU 回读的入口关键路径。B 收尾仍有 **638.4/653.0ms** 最大帧。待真实远离/回收/返回流程验证后，才将 handoff 默认开启。

## 原生交接的实际释放/返回与引擎候选09

建筑可见距离为 1000m，城镇本身约 450×360m；仅传送到城镇另一端不能证明公会模板已释放。新增 `profile_axel_native_lifecycle.gd` 用正常游戏跨地图事务，进入外部临时落脚地图，验证旧地图/Deferred 的 WeakRef 失效，再回同一冻结城镇。没有改实际地图、放宽碰撞或强制驱逐。

首次试跑 B1 在启动前发现测试脚本的 Variant 类型推断错误，日志保留；明确 Vector3 后 B2 正常退出、零引擎/脚本错误、零其他引擎/编译器进程。入口 13.785s，初次完整需求就绪 72.452s。旧地图/Deferred 实际释放；返回后的 2007 mesh / 2099 surfaces 仍 native=2099、renderer=0，capture 活跃 248.017ms、墙钟 312.711ms。往返后的碰撞支撑、玩家解锁、队列完成、源码/地图身份检查均通过。

**遗留不能隐藏：**B2 跨地图卸载阶段最大帧 545.327ms；返回事务 6.343s、最大帧 295.799ms；事务后需求收尾 61.894s，最大帧 80.696ms，102 帧 >50ms；返回稳定段 p95 29.156ms、最大 70.216ms。传送阶段含正常 cover，不能直接冒充可见行走卡顿。下一对照补录完整计时原点，按 cover 里程碑拆分。该测试没有声称同地图区块移动已经覆盖。

candidate09 在独立源码树编译成功（549.875s），`source_unchanged=true`、`default_unchanged=true`，可执行/符号留在 `P/engine_material_queue_candidate09/runtime_01/engine`，默认 candidate08 未替换。

缩小复现 `shader_queue_A1` / `shader_queue_B1`：旧引擎后台准备期间主线程最大帧 **351.071/348.379ms**，候选 **11.123/12.992ms**；后台提交仍约 770–845ms，最后挂接 0.05–0.16ms，未偷掉准备工作。两者使用独立新 shader 变体诱发编译，因此只证明机制，不是相同内容的整图 A/B。候选第一次主线程 trial 存在 3.402s 帧，原主线程路径未改变，首个新可执行的缓存/驱动因素尚未细分；保留该样本，不用后台两项收益掩盖它。

实际 GPU 材质首帧、uniform 修改、shader 修改、共享 shader/独立材质、取消释放、重建 StandardMaterial 的像素/身份检查：`shader_contract_A1/B1` 均 **18/18**；候选原生 handoff **35/35**。候选 GDB `shader_worker_engine09_stacks` 41 个样本，正常结束并 detach；旧样本在主线程 4 次看到 dirty queue → version_get_shader 锁等待，候选本次未采到该链，但两次都存在 swapchain/Present 等待。没有采到不能单独证明彻底消除，以独立正常复现与功能检查共同判断。

下一步仍按证据链推进：先完成 CPU handoff 的卸载/返回对照并默认启用有效改动；再用候选引擎测正式加载链。若仍主要卡在合批主线程 `Geometry.upload`，将私有材质/mesh 构建迁入既有 worker，保留主线程 Node 挂接、代际检查、同结果复用和资源预算。必须先处理可变材质快照与废弃 worker 的资源归属，并测取消、重排、重返及编辑器同步路径，不能只删除主线程断言就当作完成。

## CPU handoff 默认启用；后续问题分开保留

补充的 `native_lifecycle_A1/B3` 两次均正常退出，零错误/失败，源码地图身份稳定、无其他引擎/编译器；两次都确认旧地图和 Deferred 已释放。与上述入口 ABBA、35 项 GPU 合同共同支持默认启用；诊断保留 `--without-native-cpu-handoff`。

| 项目 | A1 旧回读 | B3 原生交接 |
|---|---:|---:|
| 初次入口 / 完整需求就绪 s | 16.307 / 78.855 | 13.684 / 73.885 |
| 返回传送事务 s | 9.506 | 6.373 |
| 返回 capture 活跃 / 墙钟 ms | 2414.765 / 3394.581 | 273.641 / 350.930 |
| 返回 native / renderer surfaces | 0 / 2099 | 2099 / 0 |
| 返回后需求收尾 s | 63.251 | 58.077 |
| 卸载完全遮盖区间最大帧 ms | 540.887 | 537.960 |
| 卸载未完全遮盖或边界帧最大 ms | 39.871 | 41.814 |
| 返回完全遮盖区间最大帧 ms | 255.553 | 269.855 |
| 返回未完全遮盖或边界帧最大 ms | 56.183 | 60.353 |

数据和 cover 边界推导见 `P/native_lifecycle_comparison.json`。CPU 工作/碰撞字节不变；返回传送节省约 3.13s，卸载成本基本不变。本轮 **不是同地图区块往返验收**，后续仍须补齐。B3 返回收尾还保留一帧 **408.589ms**：附近 observer 1.154ms、Deferred stage 2.560ms、batch commit 0.677ms，现有脚本计时未解释其等待，证据 `long_frame_408.json`；不能直接标成 OS/GPU 空闲，也不声称 long frame 全部稳定。

第二次独立材质复现 `shader_queue_B2/A2` 正常结束：候选后台期间主线程最大 **5.954/7.762ms**，旧引擎 **331.107/391.261ms**；候选首个主线程 trial 为 1.126s，旧为 1.239s，前一候选 3.402s 慢样本继续保留。候选仍未替换默认入口，正在进行首个完整地图样本；该样本是引擎范围验证，不与 CPU handoff 的 ABBA 混算。

## 引擎候选整图首轮异常与复测边界

`engine09_map_first` 正常结束且功能检查通过，但入口 **44.673s**、完整就绪 **118.960s**；native parse 活跃 **35.047s**，playable 最大 **3982.935ms**，人物窗口首次打开 **3796.1ms**。这证明独立 dirty queue 修复不能直接等同于整图优化完成。

同源码、地图、候选引擎立即重复的 `engine09_map_second`：入口 **13.819s**、完整就绪 **75.975s**，playable 最大 **635.482ms**，稳定段 p95 **29.484ms**、1% low **24.29 FPS**。两次均零错误/失败、无其他引擎/编译器进程；首次慢样本完整保留。重复后恢复不能单独证明缓存归因，更不能与旧引擎的既有缓存样本直接对比。下一步用冻结测试工程的独立空 shader cache 分别测旧/新引擎，日常工程缓存和默认引擎保持原样。这里只隔离着色器缓存，不称作冷磁盘测试。

原生 CPU handoff 的最终默认源码同步后，`native_handoff_default_final` Vulkan **35/35**，包括并行、取消、共享、变更回退与普通审计读者隔离。该生产改动依赖已经安装的 candidate08 API，不依赖尚未验收的 candidate09 引擎补丁。

### 缓存口径复核

准备独立空 shader cache 对照时，前置检查发现冻结工程 `.godot/shader_cache` 实际不存在；检查中止在任何移动/删除之前。此前 runner 的“Project shader cache shared across samples”文字说明不准确。实际测试各自使用新的 `user://shader_cache` 和 Vulkan pipeline cache；OS 与驱动持久缓存没有隔离，所以仍不能称冷磁盘或冷驱动测试。新 runner 已记录启动前缓存是否存在；旧原始证据不改写，本段为更正。

`native_final_B1`、`engine09_map_first`、`engine09_map_second` 各自产生 183 个 shader 缓存文件、34454292 字节；候选首轮与次轮所有文件路径、SHA 均相同，详见 `P/engine_shader_cache_inventory.json`。次轮 native parse 回到 **3.383s**。这排除了“两次最终 shader 种类/字节不同”，但不能凭此证明驱动归因。继续以 SHA 不变、位于新路径的旧/新引擎首次运行作诊断对照，不清理用户驱动缓存，不把复制可执行文件等同于已严格隔离驱动缓存。

原生 CPU 交接已在 `2eb9912e` 提交推送。卸载约 540ms 与返回收尾 408.589ms 尚待栈归因；新增生命周期诊断参数只在抓栈时等待明确的卸载阶段，不计作正常性能样本。

### 新可执行路径的首轮对照与卸载诊断

`engine_path_new_A1/B1` 把旧08/候选09各复制到从未运行的新目录，文件 SHA 与各自原件一致，两者使用相同的新文件名、同一冻结工程/地图，空用户 shader/pipeline 缓存。旧引擎入口 **41.340s**、完整就绪 **112.420s**、native parse **30.901s**；候选对应 **43.209s / 113.151s / 31.991s**。playable 最大分别 **3196.099 / 3706.582ms**，人物窗口首次打开 **3514.044 / 3335.606ms**。两次均零失败/错误、源码地图未变、23 模型/1505 实例，无其他引擎/编译器。这种慢首轮可以在无候选补丁、字节不变的旧引擎上复现；支持继续检查可执行身份相关的首次驱动成本，但不是冷驱动隔离或驱动栈归因。候选不因此被宣称更快，默认引擎仍08。

candidate09 四文件增量补丁、构建与验证清单已保存至 `tools/engine_patches/godot-4.8-beta1-material-queue-candidate09.*`。它应在08之上应用，不能直接用于官方原始源码；测试重放禁用 autocrlf 后4/4源码 SHA吻合。首次重放因机器 autocrlf 转为CRLF，SHA检查拒绝，证据保留。尚未替换默认引擎或启用生产合批后台上传。

`native_unload_stacks_01` GDB 69样本、正常detach/退出，但人工SceneTreeTimer在all-stop暂停下推进太慢，采样都发生在卸载前等待，未命中真正释放；不作为释放成本归因。诊断工具改为监听旧combat主机的tree_exiting（紧接实际地图disposal之前），写阶段标记给外部sampler，不再加入人工等待。后续02使用该触发点。

## 卸载嵌套源记录的析构归因与分片回收

`native_unload_stacks_02` 58个采样正常detach/退出，23个采到嵌套Array/Dictionary释放，12个包含GDScriptInstance析构，6个包含Object元数据析构；未采到ShaderRD版本锁等待。增强只读栈导出，读取正在析构的脚本路径与StringName元数据键后，`native_unload_stacks_03` 101个采样进一步定位到：`world_navigation.gd`成员释放12个样本，`dependency_index_proof.gd` 1个，地图元数据`load_profile`、`author_reference_extras`各1个，另有runtime_concave_shape/ground_cpu_cache/terrain_heights。样本数不是耗时比例，调试运行不作正常帧率或加载验收。

本轮针对3个明确拥有者改动，沿用现有ResourceRetirement及其预算：

- 导航在所有后台/server消费者排空后，把源记录外层引用副本移交主线程分片队列，再销毁Node。覆盖旧快照、后来追加的目录、已移除但仍被门持有的记录；含Resource的源记录绝不进纯CPU线程，不修改共享子容器。
- 依赖证明对象在PREDELETE移交工厂签发的只读纯数据快照，证明身份立即失效，issuer与任意调用方对象不移交。
- 永久地图disposal为MapLoader的原始JSON元数据移交一个CPU回收拥有者，保留退出回调的读取，重复disposal不重复登记。其他可能包含资源的元数据未泛化处理。

CPU移交的logical_bytes=0表示**此路径未测量字节数**，不是零占用；不为估算大小重新扫描整图。未修改模型资源、工作线程数量或生产预算。load_profile及其他剩余析构仍待后续证据。

独立先失败再修复：`navigation_owner_retirement_red_02` 10项中2个预期失败，旧销毁9258us；`navigation_owner_retirement_green_02` **16/16**，销毁938us、22个释放切片、最大3567us。覆盖1536×512嵌套数组、共享引用、过期快照、目录/门独有记录、未完成worker，不将await墙钟当CPU成本。`dependency_snapshot_retirement`旧用例有2个预期失败，证明释放4035us；`authored_snapshot_retirement_green` **10/10**，证明释放39us、2个CPU任务合计15494us、主线程最大切片138us。数据只证明独立用例机制，不直接当整图收益。

回归：导航流式退休**43/43**，依赖证明**37/37**，同地图事务**28/28**；Vulkan永久地图合批释放6项通过，保留单对象删除和临时detach的恢复行为。同地图旧夹具因configure_geometry_provider/append_specs/set_demand_scope签名落后而报错，且真实落点已要求物理地面；补齐模拟接口、真实地面与发布水位，不放宽生产判断。第一个卡住用例被按精确进程身份停止，后续失败及最终通过日志均保留。

正常地图对照使用同一源码、地图、默认08引擎、native handoff开启，仅用`--without-source-retirement`切换上述3项。生命周期新增返回前回收队列pending/known均为空的断言，防止只把成本推到观察窗之后；仍不宣称同地图行走验收。

第一对`source_retirement_A1/B1`均零错误/失败、源码与地图未变、无其他引擎/编译器；汇总`P/source_retirement_comparison.json`：

| 项目 | 关闭 A1 | 开启 B1 |
|---|---:|---:|
| 初始入口 / 完整需求就绪 s | 14.914 / 74.537 | 13.969 / 75.798 |
| 卸载事务 ms | 1175.499 | 807.792 |
| 卸载完全遮盖内最大帧 ms | 601.782 | 244.767 |
| 卸载未完全遮盖/边界最大帧 ms | 167.801 | 37.434 |
| 卸载后12秒观察最大帧 ms | 45.012 | 39.171 |
| 返回事务 / 后续收尾 s | 6.075 / 61.936 | 6.081 / 60.069 |
| 返回完全遮盖内 / 外最大帧 ms | 266.330 / 62.042 | 259.946 / 115.584 |
| 返回稳定段1% low FPS | 24.37 | 21.35 |

旧地图/Deferred均消失，返回前回收pending=known=0。相同2007mesh/2099surface/16228944碰撞面字节，24场景/2372资源/61像素buffer完成回收；新路径将原先析构中的源记录计入分片队列，private_values从940变10424，不代表新增模型或重复构建。CPU回收任务364→370，worker累计156→242ms；拆分释放及不同最终拥有者会改变调度单位，不能声称总工作量均下降。首对明确降低卸载集中析构，但完整加载与稳定low无收益证据，返回仍有115.584ms暴露/边界帧；所有慢样本保留，继续抓剩余约245ms卸载的栈。

`native_unload_stacks_04` 成功采样126次并detach；本次没有采到旧的导航/证明析构链，仍看到native_residency、texture_plan_catalog各1次，运行地图`extras`释放1次，以及节点、物理BVH、渲染资源释放。不能将采样次数当耗时比例或把未采到当彻底消除。**该调试运行最终exit=1**：正常事务与返回均成功，但12秒观察后回收未排空，未通过新增断言；all-stop大幅改变实际可用帧与回收预算，保留为诊断失败，不加入正常性能对照，也未放宽正常样本的排空要求。

继续精简及修复：

- 同步导航快照已包含目录记录，只在`_spec_snapshot_dirty`时补目录引用，避免正常情况下重复登记。`navigation_owner_dedup_red`新增检查失败，green **17/17**，小用例25→18切片、最大3121→2898us；旧快照/后来追加/仅门持有/活worker覆盖保留。
- `extras.rmmo_records`可能含资源，故永久disposal只复制外层记录引用，进入主线程分片队列，绝不作为纯CPU JSON处理；退出回调仍见原始元数据。`map_record_retirement_red` 9项中4个预期失败，旧节点销毁5519us；green **9/9**、销毁27us、13切片、最大2496us。重复disposal不重复登记，共享记录及资源析构线程均验证。Vulkan真实mesh/material/texture最终释放`source_retirement_resource_gpu` **7/7**。

后续`source_retirement_B2/A2`为上述累计版本的反向对照；与第一对存在源码变化，不合并冒称严格四次ABBA。

最终反向对照已完成，源码/地图身份一致、零错误/失败、无其他引擎/编译器，旧拥有者和回收队列均在返回前清空：

| 项目 | 最终旧路径 A2 | 最终累计 B2 |
|---|---:|---:|
| 入口 / 完整需求就绪 s | 13.714 / 73.473 | 14.188 / 75.610 |
| 卸载事务 ms | 1073.345 | 827.194 |
| 卸载完全遮盖内 / 外最大帧 ms | 495.577 / 44.093 | 257.854 / 32.402 |
| 卸载后观察最大帧 ms | 55.292 | 49.057 |
| 返回事务 / 后续收尾 s | 6.341 / 61.885 | 6.043 / 61.152 |
| 返回完全遮盖内 / 外最大帧 ms | 257.762 / 65.673 | 274.100 / 73.918 |
| 返回稳定段1% low FPS | 22.97 | 21.88 |

最终版本的明确收益仍是卸载：集中长帧降低约48%，事务减少246ms。两个开启样本的遮盖外卸载均无>50ms帧；不外推为普通区块行走或所有返回长帧已解决。**完整加载没有改善，本对还增加2.14s，稳定low也未改善**；暂不将有限样本的差异归为确定回归或噪声，后续须分别追踪。依据用户“时间、FPS、工作量任一维度有效可累计保留”的要求保留已证实的卸载收益。

最终A2/B2均2007mesh、2099native surfaces、16228944碰撞面字节；24场景、2372资源、61像素buffer释放，CPU回收批次均373，worker累计242120→236043us。main private_values 650→7603是把原来无分片计数的析构纳入队列；相较未去重B1的10424，最终B2即使新增运行记录回收仍只7603，避免了同步快照的重复登记。变化的调度计数不等同于新增内容或重复构建。

下一步：给正常跨地图提交中的物理体退出、地图节点销毁、导航退役、渲染资源回收分别计时，先解释剩余约258ms，再评估能否分帧；总加载约75秒及返回约61秒收尾仍须回到主线程发布/实际GPU构建关键路径，candidate09尚未默认安装，不能以本轮回收收益替代该任务。同地图区块行走、返回暴露长帧和稳定low继续列为未完成，不恢复旧白模口径，也不修改正式地图来改变工作量。

## 提交链继续细分：节点、雷达、天气与相机

回收修复已在`e5fe8149`提交推送。随后增加仅在`profile_frame`模式下采集的同步提交阶段时钟；不改变事务顺序、数据路径、预算或就绪条件。生命周期输出`commit_stages`，包含地图HUD重绑、环境更新子阶段。无await的连续区间计时可以相加；子阶段和父区间不能重复相加。

`disposal_submit_timing_01`普通08引擎正常结束，所有就绪/资源排空/源码地图不变检查通过。卸载最大250.209ms，同步提交共235.209ms：旧地图销毁104.351、准备disposal33.541、物理体移除30.590、目标展示更新62.261ms；导航退役仅0.071ms。返回同步提交118.053ms，其中目标挂接33.968、展示更新80.012ms。说明原先导航集中析构移走后，余量由多项同步提交累加，不是单一上传锁。

进一步细分的`disposal_submit_timing_02`也零错误/失败，无其他引擎/编译器、源/地图不变、返回前回收排空。初次入口13.689s、完整就绪74.967s、卸载最大239.728ms、返回阶段最大264.040ms；观察段仍出现一次164.639ms长帧，尚未归因，不能按OS空闲样本排除。细分结果：

| 同步提交项目 | 城镇→临时落脚图 ms | 返回城镇 ms |
|---|---:|---:|
| 提交区间总计 | 228.073 | 113.384 |
| prepare_disposal | 30.307 | 0.112 |
| 旧物理体移除 | 28.565 | 0.049 |
| 旧地图节点销毁 | 101.138 | 0.435 |
| 目标节点挂接 | 0.149 | 32.312 |
| 目标地图展示（父区间） | 32.185 | 17.792 |
| └ 地图投影数据更新 | 4.222 | 17.036 |
| └ 雷达重建 | 27.947 | 0.735 |
| 目标环境更新（父区间） | 31.350 | 53.768 |
| └ 天气configure | 30.930 | 1.214 |
| └ 轮廓/相机绑定 | 0.082 | 52.013 |

确认可疑项：`game_hud.bind_world_map_3d`每次直接free旧雷达，再新建；`Weather.configure(...,true)`重置降水、湿表面、闪电等；`_camera.bind_map`重绑遮挡。尚未把其中任何一个宣称已修复。World3D和Weather重复调用Settings.apply也存在，但首遍设置仅0.194/0.263ms，先处理上述28–52ms及节点/合批销毁。下一轮用独立用例/官方脚本profiler确认内部细项，再决定复用、后台纯数据回收或预算切片，保留地图切换时状态立即失效和正确碰撞语义。不要先调大预算或减少地图内容。

## 官方 profiler：相机重复目录与雷达集中释放

`transfer_presentation_profiler_01` 用默认08、相同冻结地图与全HUD完成生命周期，零错误/失败。官方receiver输出7478帧、3754个函数签名，详见`P/transfer_presentation_profiler_01_official.json`。这是**插桩诊断**，270.453s运行墙钟不作正常验收。原始`launch.json`的diagnostic=false是runner只检查GDB开关造成的错误字段；远程debug命令和receiver证据不变，另存`diagnostic_correction.json`更正，后续runner已同时识别官方profiler。

- 返回提交时，`building_cutaway.bind`两次（含解绑）累计63.478ms，其中3次`_instances`扫描累计38.030ms；返回收尾的788次append_specs里，已有普通物件早退，但建筑发布仍触发30次目录扫描，累计438.986ms、最大21.437ms。
- 卸载时雷达`bind_world_map_3d`31.647ms，terrain_layer退出31.211ms，1563次`RenderingServer.free_rid`累计30.160ms。
- 天气configure84.909ms主要来自`weather_sound.stream`首次合成PCM的83.483ms，**不是重置天气对象的证据**。正常计时约31ms。声音生成仍待独立复现和后台准备，未删掉天气重置，也未动其他会话的weather_controller改动。
- 地图收尾仍有大量绘制排序更新：返回阶段canvas_item_set_draw_index 227207次/100.255ms，prepare 1414次/1010.814ms；这是后续候选，尚未优化，不将函数包含时间重复相加。

本轮两个生产修改：

1. 相机bind只建立一次建筑目录，传给初始记录与已加载部件登记；增量发布只读取涉及的建筑，普通记录在复制/合并前跳过。挂载且采用可信资源包策略的地图不再重复审核建筑的完整members表，显式诊断审核保留；房间索引只保存regions与位姿，不因无关成员注释变化复制/重建。每次仍读取当前作者数据，保留原地编辑房间/位姿立即生效，未以永久缓存冻结编辑器数据。
2. 雷达绘图使用单独拥有的canvas父RID。clear立即释放该父节点，使旧绘图脱离画布；子RID的实际销毁移交既有ResourceRetirement、沿用原有retire预算与退出同步排空。新图拥有新的RID，不共享或复用旧句柄；没有新worker或扩大预算，RID仍只在主线程释放。

独立复现与回归：

| 用例 | 旧路径 | 修复后 |
|---|---:|---:|
| 10001作者记录、2048建筑成员的首次bind | 255214us | 11425us |
| 同数据40次建筑追加 | 3390870us | 386081us |
| 实际雷达1563个绘图对象clear | 30228us | 336us |
| 实际雷达4096个绘图对象clear | 62725us | 720us |

`cutaway_catalog_red`保留2个预期失败，`cutaway_catalog_green_final` **11/11**，覆盖房间、位姿、无关成员、原数据不变、卸载与审核策略。盲review既有回归**19/19**；环境/相机回归**8/8**；建筑组件、实际射线遮挡、碰撞和重绑回归最终**74/74**。旧组件测试有1项还要求运行时verify_source回读GLB，已改为导入入口验证源描述，并明确运行时不能回退GLB；初始失败保留。为避免覆写历史验收，测试新增环境变量指定独立输出目录。

`canvas_retirement_probe_01`先比较父子拓扑但仍同步释放，1563项flat 24.5–25.1ms/group22.5–22.9ms，4096项flat62.5–65.6ms/group64.4–74.2ms，无稳定收益，因此没有仅靠拓扑宣称问题解决。实际layer的red→green才验证分片：**21/21**，旧画面在回收未完成时已消失，新图同时正常绘制，每个旧RID恰好释放一次，关闭时同步排空及无服务兜底通过。1563/4096项分别33/86帧排空，最大正常回收切片1025/3147us；切片存在不可分的单次引擎free调用，不能宣称严格1ms上限。累计回收123072us包含额外重绑/退出项，不能据此声称总释放工作降低。

既有雷达GPU回归零失败：平移、缩放、重叠透明图元、绘制顺序、同数量修订、替换、追加、离树再进入均通过；3组缓存绘制与原始绘制的RGB像素**完全一致**，见`P/canvas_draw_pixels/comparison.json`。独立压测只证明路径机制；正常固定地图`presentation_retirement_B1/A1`对照另记，不冒充整图加载或稳定low收益。

### 正常生命周期对照

按B1→A1顺序、同一份源码与固定地图、默认08引擎、native handoff开启、全部HUD/外围系统；仅`--without-presentation-retirement`切换本轮相机目录与雷达释放。两个样本均正常退出、零错误/失败、源与地图身份稳定、无其他引擎/编译器；旧地图/Deferred释放且返回前pending=known=0。各自空用户缓存，OS/驱动缓存未隔离，不称冷启动或p95。证据`P/presentation_retirement_comparison.json`。

| 项目 | 旧路径 A1 | 新路径 B1 |
|---|---:|---:|
| 入口 / 完整需求就绪 s | 13.769 / 73.271 | 13.844 / 74.012 |
| 卸载雷达重绑 ms | 29.728 | 0.441 |
| 返回轮廓/相机绑定 ms | 50.739 | 22.958 |
| 卸载同步提交 / 事务 ms | 244.118 / 839.307 | 201.037 / 804.821 |
| 卸载遮盖内 / 外最大帧 ms | 256.332 / 38.586 | 212.866 / 40.277 |
| 返回同步提交 ms | 110.186 | 85.816 |
| 返回事务 / 后续收尾 s | 6.247 / 63.919 | 6.253 / 62.818 |
| 返回遮盖内 / 外最大帧 ms | 272.683 / 77.919 | 268.736 / 63.758 |
| 返回稳定段1% low FPS | 20.85 | 21.92 |

独立归因得到实际路径收益：雷达重绑减少29.287ms，相机绑定减少27.781ms，卸载集中长帧减少43.466ms。新增canvas队列完整释放1563项、40个切片、最大1083us，未把拥有者留到返回之后。3D源工作相同，24个场景、2372个资源、61个像素buffer、7603个private_values均一致。CPU回收批次372→375、worker累计249399→316105us；调度/最终拥有者的差异保留，不能声称所有工作计数下降。**完整加载多0.741s，尚无总加载收益；两个有限样本也不足以确认稳定low改善。** 返回收尾仍有107帧>50ms，返回边界63.758ms、稳定段71.673ms，未解决。

下一步先用官方profiler复查新路径的实际调用量和剩余主线程成本，再处理首次天气音频合成、旧地图节点销毁约101ms。完整加载约74s的关键路径仍是重点，须回到实际合批GPU构建/首次提交及candidate09引擎验证；不能以本轮几十毫秒收益替代总加载目标。同地图区块行走还未由本次跨地图生命周期覆盖。

### profiler复查与下一关键路径更正

生产修复已提交推送`98f88a37`。`transfer_presentation_profiler_02`正常结束、功能检查通过，7587帧/3771签名/零引擎错误；唯一额外PID18404为官方receiver。此次diagnostic=true正确，266.250s墙钟及110.499s完整就绪**不加入普通性能对照**。

- 返回提交目录扫描由3次/38.030ms变为1次/3.813ms；bind累计63.478→28.906ms。
- 返回收尾仍30次按涉及建筑读取，但累计438.986→147.522ms；788次append_specs累计468.834→181.664ms，调用次数不靠少发布内容减少。
- 卸载terrain_layer.clear累计31.207→0.172ms；该同步路径仅释放1个父RID，1563个子RID由正常样本已验证的分片队列完整释放。天气首次PCM仍82.657ms（插桩），未修复。
- 地图局部就绪回归**9/9**、共享资源回收真实GPU回归**7/7**，未破坏已完成场景/材质/纹理资源的回收。

**更正上一段“回到GPU构建关键路径”的优先判断：不能把历史首次上传尖峰当成这轮六十多秒返回收尾的主因。** profiler01/02的返回收尾中，Geometry.upload分别204/196次、累计112.155/98.851ms；_commit累计256.805/230.358ms。初次正常加载仍有448.010ms的单次commit，须单独处理，但不是返回收尾总时间的充分解释。官方计时含线程交错/插桩开销，不能把不同线程或嵌套函数总时长直接相加为关键路径。

从正常B1取队列时间线，`P/presentation_retirement_B1/queue_tail_review.json`：返回后约98.6s时1505个实例待发布，110.1s仍1328个，140.3s仍575个，160.3s归零。110.1s处4个job全部ready、active_workers=0，预留610617668字节、预算7957316608字节；120.1s和150.1s也出现4个ready、无活动worker，最长job年龄约5.93s。`_dispatch_jobs`仍先以`_jobs.size() >= _job_limit()`限制准入，而结果保留到消费者发布完成才移除。**这是需要重新验证的调度/发布拥堵，不能直接归因于磁盘、增加worker或扩大队列。** task age包含准备/发布全过程，尚不能当作纯等待时间。

返回地图的普通主线程统计：interactive固定2000us，2649个处理帧累计6416649us，其中2590个publication单位4070127us、1763帧超软预算；这些计数包含返回稳定观察，不是只有收尾的精确区间。说明数秒实际主线程工作被分布到大量游戏帧，必须把调用量、发布吞吐和队列拥有者一起对齐，再在独立用例里去除重复操作。当前依据不足以宣称单改预算能解决，也不修改预算掩盖low问题。

下一轮优先顺序据新证据调整：

1. 对齐普通返回收尾每帧的publication/acceptance/ready任务，拆出主线程重复检查、结果保留和实际有用工作。profiler02里`house_prefab.tickets_valid`4379次/719.659ms、`begin_texture_publication`2124次/727.512ms、`_texture_scope_current`2097次/358.354ms，存在包含关系，不能相加；检查是否同一不可变纹理世代被重复读取，保留实际世代变化、取消和共享去重语义。
2. 复现4个已完成任务占槽但worker空闲的条件，查清限制的拥有者/字节含义和消费者推进；优先减少每个结果滞留的必要工作，不能只调大slot或重新读取相同模型。
3. 天气PCM约31ms普通长帧、旧节点销毁约101ms、首次合批448ms以及绘图排序重复更新继续保留。candidate09、同地图行走和所有剩余low问题均未宣布完成。

## 发布时合并同一纹理拥有者的重复读取

沿上轮官方profiler证据检查`house_prefab`：同一次`begin_texture_publication`先在`tickets_valid`读ticket与hot catalogue，再在`_texture_scope_current`读同一个hot/weak owner。多数路径三次元数据读取落在同一个Texture2D上，并没有跨帧的新信息。本轮把它合并为一次同步检查，同时返回ticket有效和catalogue同代两个状态；不同对象仍单独读取。结果仅作为本次函数局部参数传递，**不缓存到下一调用/下一帧**，原地修改sources、资源metadata、hot/weak替换仍立即生效。材质池、实际prefab资源、纹理representation检查保留；未增加队列/worker/发布预算。

独立复现`P/texture_checks_red_02`在96个key、500次publication下有1项预期工作量失败，读取owner 48000、catalogue 96000次，253287us；`texture_checks_green` **11/11**，分别48000/0次，222579us。首个`texture_checks_red`因测试常量表达式不合法未能运行，也保留，不冒充复现。测试还覆盖同一帧source/metadata替换、不同对象同SHA、weak-only新世代、LRU淘汰重装、借用packet不变及临时scope恢复。

实际GPU回归`fused_prepared_material_regression` **97/97**、`fused_streamed_texture_regression` **16/16**，无引擎错误：一轮只做一个昂贵上传、材质RID/原像素/mip/alpha、零hot预算、交错世代、取消与原子组重试均通过。真实HTTP编辑器`fused_editor_texture_scope`最终`EDITOR_TERRAIN_TEXTURE_SCOPE_FAILED=0`，打开/保存/替换/损坏/修复/缺失源图的断言全通过；**通用GPU wrapper退出1**，因为用例故意写入broken_png触发PNG解码错误。该异常边界保留，不把这份运行写成“零引擎错误”；错误路径均为独立fixture，不修改正式地图。

正常整图按B1→A1、同源码同冻结地图、默认08引擎和全部HUD进行，仅切换`--without-fused-texture-checks`。两个运行均正常退出、零错误/失败、无其他引擎/编译器，源码/地图身份稳定，旧地图释放且返回前回收排空。各自空用户缓存，但OS/驱动缓存保留；不是cold或p95。`P/fused_checks_comparison.json`：

| 项目 | 旧路径 A1 | 合并检查 B1 |
|---|---:|---:|
| 初始入口 / 完整需求就绪 s | 14.107 / 73.108 | 14.641 / 73.622 |
| 返回事务之后收尾 s | 60.202 | 62.227 |
| 全程ticket owner读取 | 153010 | 151918 |
| 全程catalogue额外读取 | 164566 | 0 |
| 返回发布实例 / reference读取 | 1505 / 1074 | 1505 / 1074 |
| 返回实例工作阶段 / direct prefab | 1884 / 116 | 1884 / 116 |
| 返回publication单位 / spec推进 | 2638 / 2457 | 2579 / 2436 |
| 返回加载最大帧 / >50ms帧数 | 77.787 / 97 | 85.620 / 94 |
| 返回稳定段1% low FPS | 23.87 | 20.47 |

结论仅是**重复工作减少**，不是总加载或low已改善。返回耗时与low较差的B1完整保留，不能从两个样本推断稳定提升或稳定退化；工作量收益满足用户独立收益维度，继续累计保留。为确认剩余约60s收尾的去向，下一步启用既有`CompletedTrace`与只读`completed_job_audit_probe`，按任务generation记录dispatch、worker结束、join、accept、私有实例准备、commit、slot和lease释放。HUD工具新增`--trace-completed-jobs`仅用于诊断，不改变生产调度；每500ms审计一次，结束后序列化，明确排除普通性能验收。

### 已完成任务滞留的实际生命周期

`P/publication_residence_trace_01`正常结束、零错误/失败、源与地图不变、回收排空。11262个事件、372个generation，dropped=0；初始/返回各186个任务，每个都有dispatch、worker_finished、joined、accepted、slot_released、lease_released；各1505个实例恰好private_started/private_finished/committed一次。带`.glb`的日志path是既有逻辑模型ID，实际仍走原生产品，不表示恢复GLB读取。

返回侧等待（墙钟区间，跨任务重叠，不能相加为CPU工作）：

| 区间 | 中位数 ms | p95 ms | 最大 ms |
|---|---:|---:|---:|
| worker执行 | 13.644 | 563.998 | 1483.746 |
| worker结束→主线程join | 19.625 | 34.840 | 52.862 |
| join→accept | 0.525 | 17.974 | 69.977 |
| accept→首次实例准备 | 51.923 | 2636.022 | 7336.422 |
| accept→最后实例commit | 138.114 | 4817.069 | 9438.660 |
| 最后commit→释放slot | 1.324 | 10.388 | 14.911 |
| slot→释放lease | 0.017 | 0.029 | 0.044 |

116次返回收尾抽样中88次已有job而无活动worker；剩余成员的9089次重复观察全部为eligible，未观察到support/collision阻塞。观察器自身累计199244us、最大3824us，作为诊断成本保留，这份72.669s完整就绪不混进正常对照。

最长持有者是34成员建筑：worker21.332ms，accept之后7079.700ms才首次实例准备，9438.660ms才最后commit；另一个34成员建筑首次准备等待7336.422ms。这与当前`_publication_ready`/`publication_order`只选择同优先级最早ready建筑的策略相符。另有58实例共享原生模型，首次准备74.229ms、最后commit8715.535ms。**不是后台未完成，也不是最后释放轮询**；当消费速度不足时，已完成且尚未消费的输出仍合法占用槽位。没有证据支持直接扩大队列或提前注销内存拥有者。

后续需同时审查发布选择与主线程有用工作：普通B1返回发布3896863us、主线程Deferred合计6201710us分布在2547帧，同时还承受全游戏渲染/物理；该统计包括返回稳定观察段。官方profiler另有`world_map_data.visible_shapes`528次/1108.498ms，绘制顺序比较lambda 641717次/606.451ms，以及角色同帧两轮手部避让，均是可单独复现的重复工作候选；这些仍有包含关系，不能相加。先减少这些有证据的工作，保留建筑原子发布、近处优先与内存背压；未据当前诊断更改调度策略，未宣布60s收尾或low合理。

## 雷达密集查询复用现有绘制顺序

上轮纹理检查与任务滞留诊断已提交推送`6b45174e`。按官方profiler的高调用量继续检查`WorldMapData.visible_shapes`：空间桶已经缩小候选，地图build/append也已维护唯一draw_order及反向`_paint_order`，但每次查询仍对所有候选调用GDScript comparator、重复取Dictionary顺序，排序后才做精确相交。新增路径先做同样相交筛选，再用PackedInt32Array的原生排序排序可见rank，直接映射回原shape。未改空间桶、边界判定、高度/相同高度顺序、地图内容、绘图RID及就绪条件；未索引数据的原有扫描/排序兜底保留。

`map_query_order_red`用4097个footprint、200次密集查询复现：返回126843项，脚本比较2643530次、1516513us，只有“不得重复脚本排序”断言失败。`map_query_order_green` **6/6**：同样126843项、脚本比较0、129309us，独立查询耗时减少约91.5%。同数量重建、原数据直接编辑后未索引兜底、巨大footprint、height/tie排序、空/非法矩形均覆盖。计数仅在诊断开关下累计，生产路径不做逐比较计数。

真实GPU验收最初发现`test_world_map_shape_index`总览像素不一致；`map_query_order_gpu_old_control`关闭新路径仍完全相同地失败。测试还使用“固定等待两帧”，未等待既有分片绘图队列结束，会比较两份不同完成度的总览。保留这两个失败运行，测试改为有上限地等待实际footprint准备完成再截图。`map_query_order_gpu_settled` **14/14**，1005个查询结果相等、三组雷达/总览RGBA字节完全一致。

`map_query_append_gpu`也零错误/失败：增量追加后的height/tie顺序等于完整重建，旧RID不重建、新图元只记录一次、重复追加无副作用失败、平移/缩放后像素完全相等，未完成时退出清空队列。其PNG只保存在该独立证据目录；测试新增输出前缀参数，不覆盖历史截图。固定地图正常B1/A1仍需独立完成，以上微测和像素回归不当作整图总时间或low提升。

进一步排除比较计数器自身开销：`map_query_order_uncounted_abba` **6/6**，关闭计数的同进程ABBA每份仍返回126843项：旧1532961us、新153107us、新127954us、旧1479053us。原生排序路径收益在关闭计数后仍成立。增量GPU用例共**23/23**，两份RGBA及PNG SHA均一致（`map_query_append_gpu/pixels.json`）。

### 正常整图对照与保留的长帧

`map_query_order_B1`→`map_query_order_A1`仅切换`--scripted-map-query-order`，其他累计修改均开启。两次零错误/失败、无其他引擎/编译器、源码与固定地图身份不变、旧地图/Deferred释放、返回前retirement排空。仍是各自空用户缓存、OS/驱动缓存保留，非cold、非p95。详细输出`P/map_query_comparison.json`。

| 项目 | 脚本排序 A1 | 原生rank排序 B1 |
|---|---:|---:|
| 初始入口 / 完整需求就绪 s | 14.132 / 74.450 | 13.678 / 72.567 |
| 返回事务后收尾 s | 61.052 | 59.010 |
| 初始可玩后雷达绘制累计 / 最大 ms | 1221.159 / 6.907 | 669.106 / 6.470 |
| 返回收尾雷达绘制累计 / 最大 ms | 1191.371 / 7.937 | 666.932 / 4.857 |
| 返回加载帧p95 / 最大 ms | 51.576 / 78.534 | 50.604 / 70.298 |
| 返回加载 >50ms 帧数 | 142 | 103 |
| 返回实例 / reference读取 | 1505 / 1074 | 1505 / 1074 |
| 返回稳定标记段1% low FPS | 21.85 | 15.48 |

雷达调用总次数随帧进度不同，初始655→638、返回520→501；不能把累计差额全当作单次函数加速。但独立同工作量ABBA、正常绘制总时长和最大值共同支持保留该优化。完整就绪少1.883s、返回收尾少2.042s只是这一对样本的结果，尚不是稳定分布结论。

**B1仍有208.265ms长帧，未豁免**：位于第一个`return_steady`标记帧，区间155604.414–155812.679ms跨越return settled标记155776.495ms。`publication_residence_trace_01`也在同类边界出现191.092ms；因此不能把它简单说成长期静止时每帧退化，也不能凭发生在测试边界就排除。旧A1该阶段最大70.480ms。普通运行没有启用LoadMonitor，不具备这两帧的GPU耗时或OS等待原因；Performance的process/physics数据还是上一统计窗口值，不能据此判断当帧CPU空闲。

下一轮先在诊断中给return settled检查、控制台输出及`return_map_profile.duplicate(true)`加边界时钟，同时启用现有LoadMonitor的viewport CPU/GPU时钟；需要时GDB抓main/render线程。确认宿主成本与真实等待后再处理，原样本保留。发布滞留最长约9.45s、剩余约59s返回收尾仍未解决；建筑顺序/原子提交、模型复用和字节背压不变。角色每帧重复骨骼扫描、天气PCM首次合成和地图节点集中销毁仍是后续已定位候选，不能把本轮约半秒的雷达工作减少当作总体目标完成。

## 测试输出强制刷盘：先修正测量宿主

`return_boundary_monitor_01`在原磁盘stdout捕获方式下启用`--trace-lifecycle-boundaries --monitor --trace-minimum-us=2000`，零错误/失败、完整就绪73.687s。主线程16172条trace，丢失0；LoadMonitor采样累计57175us、最大425us。它是诊断样本，不并入普通性能分布。此次未重现208ms：返回加载最大73.648ms、稳定标记段最大64.594ms。

边界分解：实际就绪判断13–25us，`return_map_profile.duplicate(true)`154us；返回`check()`含打印31704us，落地含打印30576us，最终临时地图SHA检查含打印34675us。64.594ms帧与最后一项34.675ms及渲染19.350ms重叠。**复制统计不是本次大头；检查本身与输出日志必须分开。** 其他返回加载长帧仍有32–54ms渲染span；附近viewport GPU约2.3–3.9ms，采样间隔200ms且viewport值来自上一渲染帧，不能据此精确归因每个长帧或宣布GPU/OS空闲。

源代码与GDB确认了测试stdout路径：`platform/windows/windows_terminal_logger.cpp:73`在DEBUG_ENABLED下每次输出后无条件`FlushFileBuffers(h)`；`run_godot_background.py`此前把磁盘TemporaryFile句柄直接继承为stdout/stderr。`log_capture_gdb_red`对独立打印用例取得78份主线程栈，65份包含`ZwFlushBuffersFile → FlushFileBuffers → WindowsTerminalLogger::logv → print → GDScriptFunction::call`。调试器样本仅证明调用链，不作为耗时成绩。引擎/游戏代码均未修改。

后台runner默认改为匿名管道，由独立读取线程写入原捕获文件；仍使用不激活的私有桌面，保留每个stdout/stderr字节、退出码和超时输出。保留显式`capture_mode='file'`仅用于复现旧测量宿主。启动失败/回调失败/超时都关闭本机拥有的子进程和捕获句柄；若后代意外继承管道、原进程结束后仍不关闭，取消本机读取并明确报错，不静默截断或终止非本机拥有的后代。取消遵守[Windows同步IO取消合同](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-cancelsynchronousio)，等待读取线程结束。

独立GPU用例`test_background_log_capture.gd`每帧打印一次、共80次，只计输出调用；`log_capture_comparison.json`：

| 捕获方式 | 输出调用中位数 / 最大 us | 80条输出、中文、stderr、最终标记 |
|---|---:|---|
| 旧磁盘句柄 `log_capture_file_red` | 31544 / 65017 | 字节完整 |
| 管道 `log_capture_pipe_green` | 36 / 359 | 字节完整 |

Python合同用例`tools/test_run_godot_background.py` **6/6**：1MiB二进制stdout与中文stderr字节精确、非零退出末尾字节、超时排空并结束拥有的进程、启动回调异常、无效EXE、意外继承写端；每项结束均无遗留捕获线程。输出`P/log_capture_contracts.txt`。

这项属于**测量器修正，不是生产游戏性能收益**。旧208.265ms/191.092ms样本没有该边界分解，仍保留原因待核实，不能用独立打印复现替代它们。后续runner保存capture_mode与后台helper SHA，整图对照须明确测量宿主变化；新旧宿主数字不能直接作为生产改动的AB对照。

### 相同边界诊断复测

`return_boundary_monitor_02`换用管道，其他条件与01相同。两份均零错误/失败、无其他引擎/编译器，源码与地图不变、旧拥有者释放、回收排空；返回各1505实例、1074次reference读取。02有16211条trace、丢失0，监视采样累计54324us、最大720us。

| 项目 | 旧磁盘宿主01 | 管道宿主02 |
|---|---:|---:|
| landing检查含打印 us | 30576 | 152 |
| return检查含打印 us | 31704 | 165 |
| profile复制 us | 154 | 211 |
| 最终landing SHA检查含打印 us | 34675 | 261 |
| 初始完整就绪 s | 73.687 | 72.561 |
| 返回事务后收尾 s | 59.293 | 61.281 |
| 返回加载最大帧 / >50ms帧数 | 73.648 / 92 | 73.583 / 88 |
| 返回稳定标记段最大帧 / >50ms帧数 | 64.594 / 1 | 43.187 / 0 |

仅日志边界的移除有直接复现证据；总加载没有据此稳定改善，较慢的02返回数据完整保留。02最大返回帧73.583ms同时有渲染32.719ms和66-spec提交22.750ms；其他长帧常有32–46ms渲染span，没有mesh/surface/draw pipeline编译增量。`P/log_host_map_comparison.json`与两份`boundary_analysis.json`保存逐帧和边界证据。继续按真实渲染/发布成本定位，不把稳定段这一次0帧>50ms推广为全部长帧已解决。

### 返回渲染的GDB证据与边界

`return_render_gdb_01`在返回事务完成、旧资源已经排空后附加，默认08引擎、管道捕获和LoadMonitor。43份主线程栈，定期同时采集其余线程；35s采样墙钟中，读取栈的暂停累计28.347s，覆盖的是返回早期的短执行窗口，**不是整个收尾的代表性CPU分布**。运行最终零错误/失败、退出0；host记录的额外PID9744正是该GDB。几秒的调试器长帧不纳入正常low数据。

栈的存在次数（类别可重叠）为SceneTree处理26、ForwardClustered绘图6、swap_buffers6、提交present3。present样本之一在`SleepEx → AMD Vulkan驱动 → IcdPresentBuffers → we-graphics-hook64 → command_queue_execute_and_present`，另两个在同一提交链内。没有捕获到stdout强制刷盘；当前证据不足以把所有渲染span归为上传锁、脚本或GPU耗时，也不足以把208ms旧样本归因给某个外部程序。原始栈和`stack_summary.json`完整保留。

只读检查确认该测试进程加载`C:/ProgramData/obs-studio-hook/we-graphics-hook64.dll`，292152字节，SHA-256 `6ab122945e5bbcca71313079bfeabb910d49e693b6798a42f67e41ed944b50f7`。文件描述OBS Graphics Hook、版本1.8.6.0、有效签名WeMod LLC。这只能证明外部图形hook存在，**不证明hook导致等待**；未关闭相关软件、未改系统/驱动/用户应用设置。后续需将纯游戏CPU工作和驱动present等待分开核实，保持这一证据边界。

### 管道宿主下的正常运行与下一步

`pipe_capture_normal_01`关闭GDB、LoadMonitor和边界时钟；默认08引擎、固定地图、全部UI/HUD，零错误/失败、无其他引擎/编译器。源码/地图不变、旧地图与队列真正释放、返回前回收排空，返回仍1505实例/1074次reference读取。外部只读模块清单检查确认同一图形hook存在，该次宿主检查耗时198.720ms，未暂停目标；不是关闭hook的对照。详细数据在`log_host_map_comparison.json`。

- 初始入口13.523s，完整需求就绪73.509s；返回事务后收尾57.969s。
- 初次稳定段最大36.437ms、0帧>50ms；返回稳定段最大45.815ms、0帧>50ms、1% low 24.82 FPS。
- 返回加载p95 49.180ms、最大69.620ms、76帧>50ms、1% low 16.97 FPS。
- 卸载/返回事务最大232.331/273.807ms；初次可玩但未完全就绪阶段仍有654.426ms长帧。保留这些慢样本，不以稳定段结果代替全生命周期。

这是修正宿主后的一个正常基准，**不是p95分布，也不是新增游戏加速的证明**。本轮完成日志刷盘复现、捕获修正与生命周期验证；73.5s初始就绪、58s返回收尾、发布滞留和剩余长帧均未完成。

下一轮继续以官方profiler的高调用量和正常长帧归因为依据：优先复现角色每帧重复骨骼名称/静态rest扫描，以及发布时临时Node构建→遍历→销毁，保留实际姿态修正、材质拥有者、原子发布和资源释放语义。驱动present等待另行取得无调试器的证据；不为排除第三方hook擅自关闭用户程序，不用加worker/预算或扩大队列掩盖消费者成本。candidate09仍仅有独立材质合同证据，尚未替换默认引擎；先明确同路径、相同缓存条件的整图比较，不能把初次654ms峰值凭推测标为已解决。

## 临时渲染节点释放为何等待着色器，以及带纹理交接的直接投影

重新对齐`return_boundary_monitor_02`初次可玩段：661.231ms帧包含`deferred.instance_specs`481.192ms和render span152.699ms；507.714ms帧则包含render489.716ms和6次mesh pipeline编译。不能把两类都归到合批上传。新增仅在LoadTrace开启时记录的`instance_spec.project`/`instance_spec.release_node`，分别计投影与子节点优先释放，不改变预算或生命周期。

`instance_projection_trace_01`整图诊断零错误/失败、源码地图稳定：投影4108次、累计342921us、最大688us；释放4980次、累计714774us、最大289827us（`arch_C_LOD2`），另一次65204us（路面）。本轮完整就绪73.667s、可玩段最大685.463ms；不能拿投影本身的小耗时宣称整个实例链已合理。逐项数据见`P/instance_projection_trace_01/projection_analysis.json`。

引擎`VisualInstance3D`析构调用`RendererSceneCull::free`，后者调用全局`update_dirty_instances`，继而更新全局脏材质。独立`probe_private_instance_release.gd`先创建一个无关的新terrain ShaderMaterial，再释放从未挂进场景、甚至没有mesh的空节点，最后强制绘制并一起计费。`private_release_red`：

| 节点 | 创建材质 us | 释放节点 us | 后续绘制 us | 合计 us |
|---|---:|---:|---:|---:|
| Node3D 0 | 28706 | 13 | 113210 | 141929 |
| 空MeshInstance3D 1 | 12242 | 99179 | 269 | 111690 |
| Node3D 2 | 13527 | 6 | 109869 | 123402 |
| 空MeshInstance3D 3 | 12465 | 107732 | 262 | 120459 |

每次shader代码刻意不同，只用于归因，不是相同资源的加速比较。它证明“释放”可以替别的材质付费，也证明取消该触发点可能只是把成本移到绘制，不能据此宣布FPS改善。

`private_release_gdb_01`取得37份主线程栈，其中16份处于`VisualInstance3D::~VisualInstance3D → RendererSceneCull::free → Utilities::update_dirty_resources → MaterialStorage::_update_queued_materials → MaterialData::update_parameters → ShaderRD::version_get_shader → _compile_version_end → WorkerThreadPool::wait_for_group_task_completion → Semaphore::wait`。该独立运行零错误、退出0；栈与分析在该目录`stacks.jsonl`/`release_stack_analysis.json`。默认引擎未改，candidate09也未安装；这条链与此前脏材质队列证据相符，但本次并没有假定所有首帧编译均由后台上传引起。

### 去除带纹理交接预制件的临时节点

原来直接prefab投影仅接受不带`streamed_texture_owners`的job，带交接的一律走`_mesh → MeshInstance3D → _spec → free`，即使纹理与原生几何均已准备。现在先进入同一个`begin_record_scope`，保留票据/代际/缓存失效和交接流程，再读取当前canonical prefab。符合既有不可变、可信、box、未局部绘制等条件的记录直接投影；不符合或缓存被失效的继续旧路径。两支均关闭同步scope后才交回调度，不延长借用、不提前释放预算、不增加worker/队列。

同时发现旧直接投影遗漏现有`fixture_sweep_bounds`字段。三个活动门窗模式的完整字段对照明确失败，补齐与`BuildingFixtures.prepare_spec`完全相同的边界；保留旋转、闭合变换、独立fixture元数据和碰撞拥有者。

`scoped_prefab_direct_red` **54项中4项失败**：三个活动门窗字段缺失，以及带交接job仍选择临时节点。首个green已修复这四项，但新增替换用例缺少生产调度必需的CPU packet，导致预制件重新发布失败；该失败样本保留，补齐真正的准备包并允许原有有界材质步骤后再验。

`scoped_prefab_direct_green_02` **68/68**，包括真实纹理拥有者交接、同代复用、过期票据拒绝、替换重建后采用新拥有者、早前活跃材质保持不变、scope恢复、逐字段oracle、实际GPU网格/材质/alpha/normal/roughness绑定。相同2048实例的ABBA投影微测：旧128944/131110us，新35019/42957us；投影数均2048，临时节点遍历/释放各2048→0。这是投影机制微测，不能当作本次整图时间差。

GPU通用cursor回归 **15/15**，包括取消、局部碰撞顺序、真正释放；真实调度逻辑回归 **16/16**，保留建筑原子发布、独立物件公平推进、失败清理和占用槽位释放。尚须用正常整图确认本次范围扩展实际命中和累计工作量，之后才报告整图收益。

### 带交接直接投影：正常整图对照

`scoped_prefab_map_B1`→`scoped_prefab_map_A1`均正常退出、零错误/失败、无其他引擎/编译器。A仅在冻结测试工程恢复上一版loader和prefab字段投影；结束后还原候选，不改正式地图或其他会话文件。两份均默认08引擎、全部UI/HUD、管道捕获，无profiler/GDB；源码与地图各自前后不变，旧地图/Deferred确实释放，返回前retirement排空。变量SHA与比较在`P/scoped_prefab_variants.json`、`P/scoped_prefab_comparison.json`。仍是各自空用户缓存、保留OS/驱动缓存，非cold磁盘、非加载时间p95分布。

| 项目 | 旧路径 A1 | 带交接直接投影 B1 |
|---|---:|---:|
| 初始入口 / 完整需求就绪 s | 14.647 / 74.427 | 13.544 / 69.429 |
| 返回事务后收尾 s | 61.543 | 58.625 |
| 返回直接prefab实例 | 120 | 742 |
| 返回临时节点遍历 / 释放 | 2492 / 2492 | 1870 / 1870 |
| 返回spec推进次数 / 累计 ms | 2413 / 410.597 | 1977 / 303.955 |
| 返回publication单位 | 2551 | 2136 |
| 返回实例 / 引用读取 / mesh投影 | 1505 / 1074 / 2176 | 1505 / 1074 / 2176 |
| 初次可玩段最大帧 ms | 668.160 | 678.073 |
| 卸载 / 返回事务最大帧 ms | 205.674 / 262.471 | 215.098 / 282.829 |
| 返回加载p95 / 最大帧 ms | 50.689 / 72.257 | 51.741 / 74.300 |
| 返回加载 >50ms 帧数 | 103 | 137 |
| 返回稳定段1% low FPS | 24.42 | 25.37 |

确定收益是每次返回少创建、遍历和释放622个临时渲染节点，且实例、mesh投影和碰撞face准备顶点数9731922不变。完整就绪少4.999s、返回收尾少2.918s只属于这一对样本；spec累计少106.642ms不能直接解释全部墙钟差额。返回加载长帧数量反而增加，保留原结果，不能宣称low已改善。两份初次/返回稳定观察段均0帧>50ms，也不能替代加载/卸载验收。此前普通`pipe_capture_normal_01`完整就绪73.509s、返回57.969s同样保留；不挑最快结果作为收益。

下一步针对仍有栈证据的材质编译与真实合批提交：`GroundBatchGeometry.build`已经后台准备CPU缓冲，`upload`仍在主线程创建分层纹理、派生材质和ArrayMesh。先用真实slot/material组合验证私有后台提交的首帧参数、共享纹理、输入变化、取消和拥有者释放；沿用现有worker/lease和代际检查，不扩队列或仅移除主线程断言。candidate09的独立shader等待修复尚未接入该正式路径，也未替换默认引擎。69s完整加载、58s返回收尾以及678ms/215ms尖峰仍待解决，不能将这轮工作量收益当作总体完成。

## 分层地形的真实后台提交候选（默认尚未启用）

上轮直接prefab投影已提交推送`45810861`。本轮按既有GDB证据拆分合批`upload`：共享的资源构建函数产生真正用于显示的ArrayMesh、分层纹理和材质，主线程单独执行`Cpu.remember`和Node挂接。新候选仅处理已有分层地形shader；主线程捕获私有ShaderMaterial参数，同一输入材质在一个现有任务内只复制一次，纹理、CPU packed数组和固定shader仍共享。沿用原3个worker、原输入lease、完成结果和group generation，不另建线程池/队列，不预热隐藏网格。StandardMaterial仍可能懒初始化共享shader/RID，尚未允许其跨worker竞态；该部分仍待解决。

`ground_batch_private_upload.gd`将真实GPU资源构建放入既有batch worker，完成后主线程登记CPU拥有者、检查实际group generation，再提交Node；取消仍由现有drainer接手，失败结果将私有资源交回main后走一次旧路径。编辑器仍沿用原流程。候选开关`private_layered_upload_enabled=false`，整图probe显式`--private-layered-upload`，默认08引擎未替换；GPU合同使用隔离candidate09。

独立证据保留：`layered_private_gpu_01`因新增测试的Variant推断错误在解析阶段退出；02–05的真实网格/像素检查通过，但取消时material WeakRef未失效。逐项排除后确认测试协程里的临时`Gate.work.bind(gate,copied)`仍持有参数，移到不暂停的小函数、让临时Callable退栈后，06的material/mesh WeakRef均失效，token、线程和输入lease结束。生产回收代码没有为通过测试而放宽判断或增加强制清理。

`layered_private_dispatch_01`进一步发现泛用`stream_instance`元数据由GroundBatcher自身自动设置，不能作为运行模式依据。已改成只由WorldStream显式设置的`runtime_private_upload`；普通编辑器batch不会启用候选。`layered_private_dispatch_02` **41/41**，包括真实调度选择、精确顶点/索引/LOD/AABB、原纹理身份、两层height数据、首个已提交帧RGBA完全相同、原材质不被worker修改、取消期间帧继续、真实拥有者释放、源节点退出立即失效、晚到结果禁止提交和编辑器路径保留。微测首个同步上传约106ms、随后worker上传0.22–0.33ms使用已暖shader，**两者不能作为冷编译加速对照**。

### 材质去重、缺失元数据与实际图层回归

第一版snapshot按输入Material对象复制；同一个合批key来自不同源对象时仍重复复制。已复用分组阶段确定的key，一个实际批次材质只复制一次。height/mask是每个源对象的图层，必须另外保留各自Image，不能随材质一起合并。`layered_private_equivalence_red`42项中1项失败，green 42/42，顶点/图层/画面和取消语义不变。

整图`layered_private_map_B2`暴露98条缺少ground_mask_image报错：Godot的`get_meta(key,null)`在缺失时仍报错，NIL不是有效的默认值。该样本退出0、完整需求就绪68.066s，但有引擎错误，**不纳入有效性能对照**。独立`layered_private_optional_red`46项中1项失败，准确复现高度和蒙版两个可选字段的报错。改为has_meta后读取，无高度时沿用原后台height_image生成，不增加校验地图或重建已有图层。

`layered_private_optional_green` **52/52**：在已有首帧、CPU缓冲、取消和真实调度检查之外，加入缺失元数据、相同key但不同height和region-mask内容、实际Texture2DArray各层字节与同步oracle完全一致、含region的首帧RGBA一致。未降低错误检查或比较精度。

默认08引擎的`layered_worker_retirement_regression` **49/49**；`layered_default_river_regression`首次发现旧测试仍调用单参数`Stream._spawn(spec)`，解析失败。仅将测试适配到现有`_spawn(viewport,spec)`接口，02 **138/138**，覆盖terrain、水面、CPU索引、编辑预览及真实GPU图像。默认生产引擎未修改。

### 同一candidate09路径的正常整图记录

以下均全部UI/HUD、固定地图、管道捕获、无profiler/GDB；空用户缓存、保留OS/驱动缓存。`layered_private_comparison.json`保存源码/地图SHA前后、实际资源释放、额外进程和工作量核对。A1、B1、B3均零错误/失败，旧地图与队列真实释放，返回前retirement排空；它们不是ABBA，也不是加载p95分布。

| 项目 | A1关闭候选 | B1逐对象复制 | B3按key复制并修复缺失字段 |
|---|---:|---:|---:|
| 入口 / 完整需求就绪 s | 13.874 / 70.850 | 13.597 / 69.202 | 14.143 / 65.628 |
| 返回事务后收尾 s | 58.178 | 61.701 | 53.411 |
| 初始 / 返回private jobs | 0 / 0 | 27 / 28 | 27 / 28 |
| 初始 / 返回主线程snapshot ms | 0 / 0 | 50.831 / 49.981 | 19.547 / 23.899 |
| 初始 / 返回worker GPU构建 ms | 0 / 0 | 45.445 / 12.066 | 46.597 / 12.572 |
| 初次最大batch commit ms | 453.587 | 454.885 | 459.540 |
| 初次可玩段最大帧 ms | 658.726 | 667.086 | 740.812 |
| 卸载 / 返回事务最大帧 ms | 224.428 / 275.073 | 1596.708 / 276.107 | 244.200 / 337.997 |
| 返回加载p95 / 最大帧 ms | 52.526 / 76.008 | 52.646 / 69.728 | 51.185 / 72.896 |
| 返回加载 >50ms帧数 | 155 | 159 | 100 |
| 返回稳定段1% low FPS | 25.77 | 25.00 | 24.63 |

B3每次实际复制27/28份材质，不重复复制同key的源材质；后台构建沿用原worker/预算。返回实例1505、引用读取1074、mesh投影2176、碰撞face准备顶点9731922、直接prefab742、临时节点释放1870均不变。最终返回batch观测的源对象2309、源顶点2161253、render顶点2095377、render surfaces358一致；batch重建次数与publication分片数受实际到达顺序影响，分别保留，不冒充减少地图内容。

主线程snapshot比B1减少约26–31ms有对应的去重机制；不能用这几十毫秒解释数秒整图差值，也不能以B3的单次较快结果宣布FPS改善。B1的1596.708ms卸载样本保留，尚未归因。三份正常运行的初次/返回稳定观察段均无>50ms帧，不代表初始加载或地图切换无尖峰。该路径只覆盖27–28个地形批次，最大约450ms提交并未改善，候选继续默认关闭，candidate09不安装。

新增仅LoadTrace开启时的资源图层创建、surface descriptor、实际surface安装、commit upload/attach/freeze分段时钟。`layered_private_attribution_01`使用官方profiler、LoadMonitor并在实际卸载处用新版GDB采栈，专门归因剩余大块头；调试器暂停不作为正常帧或加载验收数字。

### 分段计时结论与卸载索引遗漏

`layered_private_attribution_01`取得7123帧官方profiler、3805个signature，解码错误0；LoadTrace未丢事件。最大的主线程batch commit upload为486.271ms，其中`ArrayMesh._surfaces`安装485.891ms，3个surface、45264顶点、10个ground成员，属于旧的非private上传分支。全部582次commit的attach最大0.465ms、freeze最大5.604ms。**当前证据将该约450ms瓶颈收窄到实际surface安装，而非几何循环、Node挂接或源网格freeze**；还需捕获准确源对象及原生调用栈，不能把已完成的少量分层地形后台上传当作修复它。

真实卸载GDB采7份栈，采集暂停累计11.953s，采样时长设置12s（并非12s纯运行）。栈包含Node退出、信号/Callable拆卸、Dictionary/Array释放和VisualInstance RID释放；最后一份明确记录正在销毁名为`stream_append_state`的Node metadata。没有在这7份中捕获shader等待，但样本很少，不能据此排除其他等待，更不能解释另一次B1的1596.708ms长帧。原始`unload_stacks.jsonl`、`unload_stack_analysis.json`和`attribution_analysis.json`保存于该目录。

本诊断运行**退出1**：返回前12s固定观察窗口结束时retirement仍有53个ticket，违反drain检查；虽然旧地图/Deferred WeakRef已经释放、无引擎错误、返回最终就绪，仍保留失败，不算通过的生命周期样本。额外进程3704/6244为本轮profiler receiver/GDB。正常B3零错误且drain通过与此诊断失败分开记录，不用调试器样本的墙钟评估优化收益。

代码核对确认`stream_append_state`、`stream_known`、`stream_index`仅包含编号、坐标、标志、空间成员关系和顺序，构造源为StreamIndex及对应增量准备；`stream_by_id`、prop/collision等其他索引包含真实spec/Resource，不能一起交给CPU销毁。此前整图永久卸载只转移author JSON和runtime records，漏掉了这三个纯数据索引。

新增`test_map_index_retirement.gd`用实际`Index._append_state`生产32768条记录的索引，并在相邻metadata放置带主线程析构检查的Resource。`scalar_index_retirement_red`32项中8项失败，索引仍同步销毁约36.7–47.8ms。修复只在永久卸载时保留三个根引用，交给**一个**现有CPU回收ticket；无递归复制、无运行期全表类型校验、无新增线程池/每cell任务、不改退出回调看到的metadata，也不清空仍被借用的子容器。重复prepare幂等；CPU回收关闭/入队失败保留原同步路径。

`scalar_index_retirement_green` **32/32**，同一测试ABBA的主线程prepare+destroy为旧38.103/45.942ms、新0.275/0.295ms；新worker实际释放49.742/50.582ms，说明移除了主线程同步负担，**没有宣称总CPU工作消失**。其他spec Resource仍恰好在main释放一次，退出时完整索引仍可读，外部借用的索引在回收后字节不变。runtime record回归 **9/9**，永久batch卸载/单源移除/临时重挂回归 **6/6**。固定地图默认08引擎、private上传关闭的整图结果见下文。

本轮官方profiler还保留调用量候选：`Skeleton3D.get_bone_name`约278.7万次、相机`Time.get_ticks_usec`207.2万次、玩家`get_meta`201.6万次；调用次数高不等于独占大耗时，须分别核实不变量及每帧用途。它们不是本轮已修复项，也不替代当前surface安装与卸载的大块头。

### 补充失败边界与共享next-pass检查

候选review发现ShaderMaterial的next_pass仍可能引用一个共享的懒初始化StandardMaterial。只检查首层shader不足以证明整条RID创建链独占。`layered_private_next_pass_red`53项中1项失败；候选对有next_pass的材质保留原路径后，green **53/53**。只检查现有小材质列表，不复制纹理或扫描资源图；默认候选仍关闭。

`scalar_index_map_A1`是只撤掉纯索引回收、private上传关闭、默认08引擎的旧路径对照。初始日志记完整需求就绪72.075s，卸载、回收排空、返回就绪检查均已输出PASS，但计时结束后的报告整理期间进程以`3221225477/0xC0000005`退出，最终profile未写完，**不是通过样本，不采用其残缺报告作性能比较**。不能据此认定游戏内必现，也不能再仅凭历史结论把所有此类崩溃限定为旧外部优先级夹具；这次没有使用该夹具。

Windows Application 1000/1001确认故障PID15188（0x3B54）及默认引擎路径，模块unknown、偏移0，WER为BEX64/StackHash_ac46。完整`Report.wer`已复制到该样本目录；所列临时dump已被Windows移除，没有故障调用栈。host仅在末尾记录额外Godot PID13936（186.609–189.328s），cmdline不可读；不能凭此确定是外部测试、崩溃辅助进程或崩溃原因。没有改系统WER/驱动设置、没有终止用户应用。`scalar_index_map_A2`原参数重跑；外部`P/watch_owned_crash.py`已准备作为下一次异常专用GDB观察器，尚未执行，不声称已取得崩溃栈。

### 纯索引回收：默认引擎完整生命周期对照

实际顺序B1→A1崩溃→A2，保留全部样本；A2重跑正常退出。A2/B1仅`world_stream.gd`永久卸载中的三个纯索引引用转移不同，文件原始SHA（包括换行）记录在`scalar_index_variants.json`。共同采用默认08引擎，private layered候选关闭、全部UI/HUD、正常预算、无profiler/GDB、无其他引擎进程。两份地图和源码前后不变，旧地图/队列WeakRef释放、retirement排空、角色可用和完整需求就绪全部通过。比较保存在`scalar_index_comparison.json`，不会读取A1残缺报告来补数字。

| 项目 | 旧路径A2 | 三个纯索引后台回收B1 |
|---|---:|---:|
| 入口 / 完整需求就绪 s | 13.224 / 71.931 | 14.514 / 69.127 |
| 返回事务后收尾 s | 60.035 | 58.269 |
| 卸载prepare_disposal ms | 33.062 | 33.111 |
| 卸载outgoing_map ms | 105.524 | 94.112 |
| 卸载整个同步commit ms | 209.437 | 196.364 |
| 卸载最大帧 ms | 220.003 | 207.638 |
| 初次可玩段最大帧 ms | 672.075 | 670.711 |
| 返回事务最大帧 ms | 257.806 | 279.568 |
| 返回加载p95 / 最大帧 ms | 51.814 / 74.134 | 53.012 / 80.247 |
| 返回加载 >50ms帧数 | 142 | 156 |
| 返回稳定最大帧 / 1% low | 44.895ms / 24.88FPS | 53.947ms / 21.48FPS |

实例1505、引用读取1074、mesh投影2176、face准备顶点9731922、直接prefab742、临时节点释放1870完全相同。整图outgoing_map少11.412ms，与独立复现的释放机制一致；卸载尖峰仍207.638ms，不能称为已解决。初始加载发生在本改动触发之前，**71.931→69.127s不能归因于卸载修复**；返回耗时也只是一对观察，low指标反而较差，全部如实保留。主要确定收益是移走已确认的纯数据主线程释放，没有删除游戏工作或扩大队列。

补充时钟对齐：diagnostic里485.891ms surface安装发生在地图计时16.651s、入口18.584s之前，处于遮罩阶段，**不能直接拿它解释入口后约670ms尖峰**。后续按两个窗口分别抓真实调用栈：先明确这3个surface的准确源/材质和原生安装等待，再定位入口后绘制/发布长帧；卸载约94ms地图析构和末尾access violation也保留为未解决项。当前候选和默认引擎不互换，测试工程已恢复累计实现，其他会话的道路/灯光/编辑器WIP继续保留。

## 真实道路批次：身份、独立复现与原生等待链

累计代码`4d0364bf`后的`surface_identity_exception_01`开启边界Trace，并在返回阶段附加异常专用GDB观察器。地图、源码和释放检查通过，进程正常退出；观察器没有收到SIGSEGV/SIGABRT，**不能据此宣布上一轮access violation已解决**。GDB附加本身产生约2832ms返回帧，整份样本仅用于诊断，73.902s完整加载不参与正常性能比较。

新增诊断只在Trace开启时记录字符串身份：`batch.commit.begin`保留group类别及源节点名，超过20ms的`batch.upload.slow_materials`保留材质类、名称和路径，不查询lazy RID、不额外持有Resource。最大安装479.480ms再次对应3个surface、45264顶点，10个源均为`pavement_*`，不是此前private layered候选覆盖的ShaderMaterial地形。准确ID及3个StandardMaterial3D描述见`P/road_install_comparison.json`；这次仍发生在遮罩内，与入口后674.657ms峰值分开。

`tools/probe_road_batch_install.gd`只读同一固定地图的这10个资源引用，使用实际`Road.arrays → WorldDocument._mesh(CPU index) → GroundBatchGeometry.build → upload`，无GLB回退、无简化材质、无额外地图写入。独立重现准确3个surface/45264顶点。首次`road_install_red01`安装1157.192ms、后续首帧9.975ms；其三个解码浮点逐字节断言失败，样本保留，不作为通过样本。改为逐项检查引擎打包的vertex/attribute/skin/index字节及保留的原始CPU数组后全部通过；解码的量化法线/UV不应冒充原始浮点字节合同。

第一次`road_install_gdb01`用SceneTree计时器等待观察器，all-stop暂停扭曲simulation delta，97个样本错过安装窗口。这次只证明测试通过，不作为安装归因。`road_install_gdb02`改用文件握手和`ArrayMesh::_set_surfaces`实际入口断点；第1–5个主线程样本一致为：

`ArrayMesh::_set_surfaces → RenderingServerDefault::mesh_create_from_surfaces → RenderForwardClustered::mesh_generate_pipelines → ShaderData::is_valid → ShaderRD::version_is_valid → _compile_ensure_finished → _compile_version_end → WorkerThreadPool::wait_for_group_task_completion → Semaphore::wait`。

这将先前整图同类栈落实到一组可独立复现的真实道路数据。`mesh_generate_pipelines(..., background=true)`只取消最后的pipeline等待，前面的shader有效性检查仍同步等待。GDB暂停下的14.171s安装不算性能；正常独立测试与整图结果另行记录。早期probe帧采样未覆盖首次安装间隔，不能用其`max_frame`声称没有尖峰；已将起始时钟移到安装开始，后续版本同时记录整个安装到首帧的墙钟。

### 隔离candidate10与真实道路后台提交候选

没有简单跳过引擎的shader有效性检查：第一次实际绘制仍需可用shader，跳过可能只是把停顿移到下一帧。candidate10在09之上仅向脚本绑定已有原生`Material.get_shader_rid()`。主线程对每个批次唯一材质复制一次，调用getter完成私有StandardMaterial的shader key初始化，但不创建材质RID。这样main flush与worker后续getter都走相同key的只读早退；worker依托09的“先等shader、再进入dirty material队列”顺序创建**最终实际使用的**材质和网格。没有隐藏网格，没有重复纹理加载，几何准备仍用既有3个batch worker/lease/队列及generation检查。新增私有材质拥有者的成本明确计入snapshot，不能宣称总工作量零增长。

`private_road_upload_enabled=false`保持候选关闭，只有运行期全road_mesh且全为受支持StandardMaterial、无next_pass、有原生getter的批次才能显式启用；无API的默认08引擎、编辑器和其他类型保留原路径。layered候选仍独立开关。原生绑定的增量patch、源码SHA、432.0s构建回执、可执行及符号SHA存入`tools/engine_patches/godot-4.8-beta1-shader-rid-candidate10.*`。构建来源是原隔离09源码树，未替换`D:/tools/godot`，未改官方地图/素材/其他会话WIP。

`road_private_contract10` Vulkan **81/81**，覆盖原layered合同和新增道路合同：唯一key共享、纹理identity不变、源材质修改隔离、真实首帧像素一致、既有worker派发、取消不阻塞、lease与结果真正释放、源退出后拒绝迟到发布、编辑器排除，零引擎/脚本错误。

独立真实10-road实验按A1→B1→B2→A2串行、相同candidate10路径、每次新进程/用户缓存执行，均无调试器；OS/driver缓存保留，不宣称冷盘/冷driver。所有packed geometry与原始CPU数组合同通过，B两次实际画面A/B/A字节一致。

| 样本 | 安装/等待墙钟 ms | 初始化主线程 ms | worker上传 ms | 首帧绘制 ms | 安装至首帧 ms | 最大帧 ms / >50ms |
|---|---:|---:|---:|---:|---:|---:|
| A1主线程 | 193.448 | — | — | 1510.991 | 1704.539 | 1704.830 / 1 |
| B1后台 | 177.438 | 13.443 | 160.531 | 1.266 | 178.786 | 16.416 / 0 |
| B2后台 | 178.728 | 13.184 | 127.960 | 1.612 | 180.422 | 15.256 / 0 |
| A2主线程 | 165.546 | — | — | 4.336 | 169.992 | 170.390 / 1 |

B的主线程finish只有0.078/0.084ms，初始化还包括probe的值比较和输出。A1首次较慢绘制完整保留，不能挑它宣布十倍总加载收益；与后续A2相比，B墙钟略慢，确定收益是主线程等待被移走，实际首帧也没有重新出现长等待。只对这组独立批次成立，不用两份B估计p95，也不代表整图入口后尖峰和low已修复。正常整图关闭/开启对照继续，默认开关与引擎不变。

### candidate10正常整图ABBA：主线程提交改善，总加载尚无明确大幅改善

`road_map10_A1 → B1 → B2 → A2`已全部串行跑完。共同采用同一隔离candidate10路径、固定地图SHA、全UI/HUD、正常预算、无profiler/GDB或其他引擎/编译进程，唯一运行参数差异是`--private-road-upload`，layered始终关闭。四份源码前后SHA相同、地图不变、旧地图/队列owner释放、回收排空、返回完整需求就绪检查全部通过，进程正常退出、零错误。`P/road_map10_comparison.json`包含全部样本、阶段帧分布、工作量和提交分解。

| 项目 | A1关闭（首次慢样本） | B1开启 | B2开启 | A2关闭 |
|---|---:|---:|---:|---:|
| 入口 / 完整就绪 s | 39.377 / 106.822 | 13.178 / 68.732 | 13.442 / 70.201 | 13.326 / 70.245 |
| 返回收尾 s | 60.219 | 61.170 | 57.484 | 61.201 |
| 初次main batch最大commit ms | 637.224 | 15.619 | 24.033 | 430.629 |
| 初次可玩段最大帧 ms | 3429.965 | 685.326 | 657.869 | 629.135 |
| 卸载最大帧 ms | 1598.737 | 229.609 | 216.176 | 214.316 |
| 返回加载p95 / 最大帧 ms | 52.445 / 75.075 | 51.238 / 72.732 | 52.008 / 67.692 | 52.445 / 77.105 |
| 返回加载 >50ms帧数 | 148 | 122 | 137 | 154 |
| 初次稳定1% low FPS | 27.19 | 25.74 | 26.51 | 26.68 |
| 返回稳定1% low FPS | 24.71 | 24.73 | 25.51 | 25.15 |

不能用A1首次路径慢样本宣称38秒收益，也不能删掉它。A2对比两份B，约431ms的合批主线程提交降到16–24ms，与独立复现一致；68.732–70.201s完整加载与70.245s对照仍不足以证明明显总耗时收益，稳定low也未形成确定改善。入口后的约658–685ms和卸载约216–230ms继续存在，没有被道路提交修复覆盖。

四份返回实例1505、引用读取1074、直接prefab742、临时节点访问/释放1870、mesh投影2176、face准备顶点9731922相同。初次最后一份500ms合批观察中，A2准备访问30538行、重建291次，B1/B2为30512/30523行、289/290次；未因私有道路上传产生整批工作膨胀。B初次实际执行68/69个道路GPU任务，创建203/205个私有材质副本，snapshot累计53.927/58.977ms；返回61/46任务、182/137副本、50.878/35.629ms，均零fallback。副本用于独占初始化并共享纹理，成本保留；这些是最后一次周期观察，动态源/批次统计存在时序差异，不能当作每帧完全相同的最终census。

补验`road_private_default08` **55/55**，包括没有原生getter时回到旧路径；`road_install_pixel_final`确认真实道路画面包含足够多不同颜色，且候选/原材质/候选A/B/A像素完全一致，避免空画面假通过。candidate10增量patch经`git -c core.autocrlf=false apply --check`及真实重放，源码SHA与编译输入一致。

本切片保留默认关闭的已验证候选和复现工具；**默认引擎仍为08，没有声称已在日常游戏启用收益**。在替换默认引擎前继续补真实内容编辑器渲染/native导入的09/10兼容验证。下一主性能窗口仍是入口后约670ms，需按实际帧时钟用profiler/GDB抓栈；随后处理约210ms卸载和返回50–77ms长帧，以及约70s完整加载/58–61s返回收尾。此前access violation没有新栈，单独保留。同地图区块走动/返回还不能用本轮整图切换替代验收。不得以候选收益宣布目标完成或调整就绪边界。

### candidate10 编辑器验收、默认引擎安装与正式道路路径启用

接上轮候选，使用同一隔离 candidate10 对真实编辑器流程补验：`editor10_native_ui` **72/72**，`editor10_native_consumers` **26/26**，`editor10_streamed_paint` **69/69**，`editor10_native_join` **140/140**，`native_handoff10` **35/35**，均零引擎/脚本错误。涵盖真实 UI 预览/缩略图、HTTP MCP 导入和散布、撤销重做、保存重开、GLB 删除后的原生消费、源像素/alpha、流式纹理共享与取消、真实资源拥有者归零及原生网格 CPU 交接。仅使用一次性外部测试内容，没有改写正式模型、地图或混入其他会话的道路/灯光 WIP。

`engine_shader_rid_candidate10/installation_attempts/20261031_065704_076703/installation.json`记录完整安装：核验累计08+09+10源码、patch重放、构建输入和上述测试后，备份默认08到`D:/tools/godot/_backup/before_10_20261031_065704_076703`，逐文件核对备份及暂存SHA，再替换默认入口、别名和匹配符号。当前默认主程序SHA为`7a8029a67b0e0bbc442c12f5ebf0aa67baf2e53f65c8750dd5fbb6b4adabdb53`，符号SHA为`bd2749d59db19ef16b32351530922b81af52e7a6372a238a1331f0131b52c7c7`；manifest保留不可变安装前证据快照及安装结果，版本字符串仍为4.8.beta1.custom_build.4d10419ca，不用版本号代替实际二进制身份。

生产`private_road_upload_enabled`启用，分层地形候选继续关闭；仅 WorldStream 创建的运行期道路批次进入现有 worker，普通编辑器仍走已有路径，不支持的材质或缺少原生接口时沿用原有回退。probe 改为显式 on/off 覆盖，未传参数时保留生产默认值，避免测试悄悄把新路径关掉。

默认入口`road_private_installed10` **81/81**。`road_default10_01`不传道路覆盖参数，正常引擎、全部 UI/HUD、固定地图、无 profiler/GDB，退出0、零错误/失败、无其他引擎/编译进程；源码与地图SHA不变，旧地图/队列确实释放，返回前retirement排空。

| 项目 | 默认入口启用样本 |
|---|---:|
| 入口 / 完整需求就绪 | 14.002 / 69.434 s |
| 返回事务后收尾 | 61.097 s |
| 初次最大主线程 batch commit | 24.697 ms |
| 初次道路任务 / 材质副本 / fallback | 69 / 206 / 0 |
| snapshot 累计 | 54.545 ms |
| 可玩加载段最大帧 | 718.085 ms |
| 卸载 / 返回事务最大帧 | 198.839 / 243.331 ms |
| 返回加载 p95 / max / >50ms帧数 | 52.217 / 68.198 ms / 136 |
| 初次 / 返回稳定段 1% low | 26.66 / 24.29 FPS |

这是正式默认入口的生效验证，未用单次69.434s宣称总加载收益或p95改善。道路提交的主线程负担已转移；完整加载约70s、入口后718ms、卸载199ms及返回持续长帧仍需处理。后续现有官方profiler记录将入口后最大帧收窄到`asset_library.cache_scene → PackedScene.pack`，其中一个原生模型的主线程cache_pack约595.5ms；新的GDB/独立复现继续核实内部调用，尚未宣布修复。

### 入口后尖峰：独立 pack 未复现；捕获真实 shader 等待

重新核对既有`layered_private_attribution_01`：官方profiler第576帧727.579ms，原生`PackedScene.pack`595.347ms；LoadTrace的`asset_library.cache_pack`595.514ms对应逻辑模型键`packs/default/assets/2abd3fe0f222d1e7cf69fa26eb5a6f05e21aca2cf041beb7301bd1847bd16c15.glb`。这里GLB后缀只是既有逻辑身份，读取的是native product，不是恢复GLB运行时回退。

该模型既有native payload为`67d997c907631a231136c35b99e2a1f0a4bfabf38857fabbe1be369b4302cdef.scn`、25297056字节；历史footprint共4节点/3mesh/3surface、含3张嵌入式ImageTexture，没有texture_table/direct-template标记。仅只读观察，没有转换或修改正式资源。大耗时不能仅凭这些统计归咎于模型。

`post_entry_pack_diag10`使用正常累计代码、官方profiler和新版GDB，仅在真实可玩入口后对main的PackedScene.pack设断点，捕获20次入口/退出间的40份栈。入口断点后每次继续25ms时已不在pack内部；未捕获595ms的实际阻塞链。LoadTrace包含断点暂停，不能把每次2–6s的pack时钟当作游戏成本。官方解码7309帧/3795个signature、零解码错误；运行退出1，唯一失败是返回前12s回收排空未满足。旧地图/队列WeakRef释放及其他检查通过不抵消该失败；原始数据保留，未用于正常性能对照。

新增只读`probe_native_template_pack.gd`使用同一原生候选、真实后台`_prepare_fixed_scene`和主线程`AssetLibrary.cache_scene`，不加载整城、不导入GLB、不改产品。`native_pack_repro10_01`五项检查通过，保留完整4节点图；准备381.438ms、cache总2.857ms，其中pack仅0.453ms。**没有独立复现整图595ms，不能据此宣布修复或直接开启预打包候选。**该微测期间上一份官方报告的headless解码仍在收尾，因此仅用于“该路径能成功且未复现大阻塞”的判断，不作严格性能收益对照。

全部诊断进程结束后补跑`native_pack_repro10_02`，五项检查再次通过；准备371.002ms、cache总3.052ms、pack0.420ms。没有其他测试引擎/GDB/报告解码并行，同样未复现大阻塞，不据此推算整图收益。

随后`post_entry_sampling10`取消pack断点，入口后通过all-stop采样捕获61份栈，采集暂停累计43.551s。运行退出0、零错误/失败，旧owner与retirement检查全部通过，但依旧是诊断样本，125.835s完整就绪不是正常加载成绩。

样本47/49/50/52/54的可信顶部链为`RenderForwardClustered::_geometry_instance_add_surface → ShaderData::is_valid → ShaderRD::version_is_valid → _compile_ensure_finished → _compile_version_end → WorkerThreadPool::wait_for_group_task_completion → Semaphore::wait`。样本48是`RenderingServerDefault::_draw → RendererSceneCull::update → Utilities::update_dirty_resources → MaterialStorage::_update_queued_materials → MaterialData::update_parameters → ShaderRD::version_get_shader → _compile_version_end → group wait`。部分栈在`_fill_render_list`以下展开失败，保留未知帧，不拿错误下层帧推导脚本调用。

按`cpu_time_anchor`把GDB暂停前的Unix时钟映射到LoadTrace，以上六份均处于`monitor.render_frame_span`，并伴随surface pipeline计数变化；没有与`asset_library.cache_pack`重叠。这次pack也没有>30ms事件。由此可以确认入口后存在真实shader编译等待，但**尚不能把它直接等同于前一运行中的595ms pack**。断点/暂停改变了原本的并发时序，需保留两个问题的证据边界。

下一步优先在这两条已捕获的原生等待链上读取具体shader路径/代码身份，关联真实材质及其发布阶段，再用同一材质/网格首次提交复现。已有candidate09只保护后台新建material RID，candidate10道路路径不会自动覆盖主线程新材质或既有材质修改，不能假设整个渲染队列已不再等待。外部`shader_identity_export_candidate.py`是待验证的只读GDB扩展草稿，未替换正式采栈工具、未修改引擎或启用新的生产优化。继续保留未复现pack、约200ms卸载、返回长帧、完整加载/返回收尾及同图走动覆盖缺口。

### GDB 读到实际 shader：移除河道只绘制再 discard 的表面

`shader_identity10_01`用默认candidate10和固定地图，在入口后采集46份栈。外部`shader_identity_export_candidate.py`只读目标进程内存，按该4.8构建的CowData布局读取有界UTF-32 String，不调用目标函数。运行退出0、零错误/失败、旧owner释放及回收排空通过；123.313s完整就绪是带GDB的诊断时间，不计性能。

样本42/43分别读取1534/1505字符的生成式StandardMaterial3D shader；样本45的49字符shader是`shader_type spatial; void fragment() { discard; }`。实际代码保存在同目录按SHA命名的文本文件，后者SHA为`287dc0466564ee24514c3ec764bd0737ee40f0d87253b90aa5b8a765d36b3272`。该精确代码对应`RiverMaterials.hidden_slab`：河道侧面/底面上传、建立材质/管线并参与绘制，最终所有片元丢弃。两个StandardMaterial shader的具体源材质尚未确定，不能一并归因于河道；此前595ms pack仍未独立复现。

新运行期路径只为不可编辑的CPU水面建立可见表面投影，沿用原来的法线/槽位分类及最终水材质。原始完整几何继续供碰撞、paint_source和编辑器使用，原始数组和地图不改；可见投影直接借用CPU数组、LOD及已有packed upload行，不重算、不重打包，也不先安装用不到的原始材质。全局material_override/material_overlay继续保留完整表面。相同不可变源和最终材质使用同一投影，缓存只含标量材质ID与WeakRef，不长期占有CPU/GPU网格或材质。

独立测试`tools/test_water_visible_surfaces_gpu.gd`走真实WorldDocument cooked CPU→WorldStream spec/spawn。`water_visible_red02` **22通过/8失败**明确复现旧路径创建discard shader、保留隐藏表面和完整上传包；更早的red01因测试夹具未cook导致ArrayMesh类型错误，保留但不算有效复现。首次投影随后暴露重复放置不共享的问题，`water_projection_reuse_red` **34通过/2失败**；弱引用共享修复后 **36/36**。

补齐真实GPU同时持有/释放、材质变体隔离、过期投影清除、全局覆盖、全隐藏空网格后，`water_projection_default01` **52/52**、零引擎/脚本错误。平水面/斜坡水面各三机位的A/B/A像素差异全为0；原始碰撞三角形、变换、区块需求范围、编辑器全表面和作者数据保持不变。两实例只上传一次可见表面，释放一实例不影响另一个，全部释放后GPU WeakRef归零；目录仍活着时也不保活GPU网格。ownership01的测试类型声明错误、ownership02的空节点名错误均保留，修正夹具后的ownership03才计通过。原有CPU索引兼容套件显式关闭投影以验证原合同，`water_legacy_contract10` **138/138**；没有删除原断言。

补测`water_projection_worker_lod02` **80/80**：增加真实Thread首次生成的无cook缓存数组/边界/上传包，经正式文档索引、发布、释放及三机位像素对照；并以有索引的等价顶面检查原生LOD上传后读回。worker_lod01的78通过/1失败保留：夹具给无索引triangle soup附加LOD，引擎未生成LOD字节；修正为有索引基面并额外断言原生包确含LOD后通过，没有放宽或删除读回断言。这不等于整图严格冷盘测试。

生产默认启用可见投影，HUD probe提供显式关闭开关和build/reuse/hidden surface计数。正常整图`water_map10_A1→B1→B2→A2`已全部串行完成，使用同一默认引擎和地图、全HUD、正常预算，不带GDB/profiler，无其他引擎/编译进程；唯一参数差异是关闭水面投影。四份均退出0、零错误/失败、源码与地图SHA相同且前后不变，旧map/loader owner真正释放、retirement排空。汇总`P/water_map10_comparison.json`。独立测试里的首次绘制成本没有做冷缓存配平，不能拿其中的单次前后时间当作整图或冷启动收益；以下四份也不足以估计加载p95。

| 项目 | A1关闭 | B1开启 | B2开启 | A2关闭 |
|---|---:|---:|---:|---:|
| 入口 / 完整就绪 s | 15.901 / 67.260 | 15.406 / 67.850 | 17.529 / 80.353 | 17.313 / 77.130 |
| 返回事务后收尾 s | 56.761 | 60.098 | 58.529 | 50.526 |
| 可玩加载段最大帧 ms | 716.533 | 672.921 | 719.371 | 731.424 |
| 卸载最大帧 ms | 303.689 | 260.272 | 280.111 | 228.553 |
| 返回加载 p95 / max ms | 60.514 / 100.737 | 64.380 / 156.343 | 53.964 / 130.394 | 49.572 / 91.224 |
| 返回加载 >50ms 帧数 | 242 | 275 | 156 | 73 |
| 初次稳定 1% low FPS | 29.11 | 32.13 | 34.66 | 24.61 |
| 返回稳定 1% low FPS | 24.78 | 26.38 | 27.89 | 24.05 |

两份B均累计488次投影、976个隐藏表面槽位不再进入运行期网格，discard材质从头到尾未创建；这是初次及返回索引的累计工作量，不是“每帧减少976个draw call”。此地图每个源几何不同，reuse计数为0；重复源去重由独立实例测试证明。四份返回工作均为1505实例、1074引用读取、742直接prefab、1870临时节点访问/释放、2176网格投影、9731922面准备顶点。新路径没有增加上述模型/碰撞工作；新建轻量CPU投影和弱缓存的成本也存在，不能声称所有CPU操作都减少。

稳定low有一致改善迹象，样本较少且初次稳定窗仅5s，不夸大为稳定百分比收益。完整加载、返回收尾、返回长帧没有确定改善，两份B的返回最大帧更高，全部保留；不能把B2的80.353s删掉或无证据归为OS空闲。保留此优化的确定依据是无效表面/材质工作被移除，碰撞/画面/共享/释放合同通过；大停顿和总加载目标仍未解决。

### 新的收尾证据：4个已完成结果仍可挡住空闲worker

对齐`P/water_map10_queue_evidence.json`及原始500ms队列采样：B1→B2入口后收尾从52.445s变62.824s，初次deferred累计主线程记录6.755→7.229s，worker累计24.725→27.521s（并行且包含等待，不能与墙钟直接相加）。慢运行的可玩帧p50从26.336变29.792ms，帧数1745→1907，主线程publication单元2173→2207；A2同样变慢，所以不能直接断言由投影引起或没有影响。

B2的51.312s样本仍有852个需求，`active_workers=0`，4个结果全部ready、不再运行；其中native模型结果自派发已5.363s，总保留量867800600字节，低于7957316608字节预算。19.574/21.747/22.775s也出现4个ready占位、worker空闲、还有1444–1476个需求。任务age是派发年龄，不能当作完整ready等待时长。仅末尾需求已为0的空闲样本不算生产阻塞。

代码对应`DeferredAssetLoader._dispatch_jobs`的`_jobs.size()>=_job_limit()`；2worker默认任务上限仍为4，`_job_consumed`要等该源全部publication_ids消费后才释放。已完成任务虽park了worker lease，仍占总任务名额。此处并不等于已证明所有待处理源此时均可运行，但足以确定存在独立于worker数/字节预算的派发门槛。下一轮先用持有多实例的已完成结果复现，再查清结果交接、实例发布及释放阻塞；保留所有权、内存计费、取消和优先级合同，不靠调大ready_job_limit解决。

四份初次`max_instance_spec_unit_us`仍有498–544ms，和前述shader等待/pack是待进一步对齐的证据，尚未拿到该单元内精确栈。继续定位这条不可分片单元和准备/发布关键路径，随后处理卸载与同图区块走动；不能以本轮水面收益结束总目标。

### 完成结果乱序提交：真实阻塞、两 worker 复现与上下游合同

`completed_owner_followup10`用同一引擎、固定地图和HUD，启用官方profiler及只读完成结果观察。官方解码7039帧/3811 signatures、零解码错误；442个采样中87个可玩阶段样本出现4结果占满、执行worker为0、仍有未启动源。55.911410s时保留102434384字节、预算7957316608字节，另有128个未启动源；一个16成员建筑已私下完成15个但尚未提交，其他已接受结果也有eligible成员。字节数、eligible与任务计数不能证明全部128个源都已具备纹理/独占准入条件，记录没有这样推断。

这份诊断完整就绪109.445s，运行退出1：唯一失败为返回前12s资源回收排空；旧map/loader WeakRef确实释放，其余生命周期检查通过。零引擎/脚本错误不抵消该失败，诊断时间不参与正常性能对照。上轮498–544ms不可分片单元及原生shader等待仍未因此解决。

原因在主线程选择策略：后台结果可乱序join/accept，但同一视觉优先级仍只提供最近的ready建筑；一个任务要全部成员提交后才能释放结果名额。多个长任务留下已完成包，可以让后面的短任务和新生产任务继续等待。此次候选保留2worker、4结果上限和原字节计费，仅在真实dispatcher被结果数挡住、仍有执行余量时，允许所有已就绪建筑参加选择，优先完成剩余成员较少的结果。新到短结果可抢先，大结果有按任务generation计的防饥饿保护；负优先级安全需求立即抢占。其他时候仍沿用原来顺序，原帧预算不变。

`test_completed_result_service.gd`使用真实Thread、正式dispatch/join/accept/私有构建/整组发布/释放链，以轻量节点隔离材质开销，分组大小[16,1,16,16,1]。`completed_service_red01`12通过/2失败：第192个处理单元才释放第一个名额和启动第五个源，总600单元。候选`completed_service_green04`38/38：第12单元完成短任务、释放名额并启动第五源，总量仍600单元，50个成员各构建一次、5个源各准备一次。此处是确定性工作步数，不是毫秒或整图提速。

同一测试用Semaphore实际暂停一个worker，另一个仍完成三个源；先让大任务推进8单元，再解除暂停，后到的小任务在12单元内完成并补位。取消测试在仅有一个私有实例、尚未发布时撤销需求，资源和名额全部释放；返回后新generation发布5个完整分组，累计50个正式实例，仅重建了确实被取消的那一个私有实例。未扩大缓存或队列，也未把旧结果当作新结果提交。

`test_completed_result_order.gd`12/12覆盖后到短任务、安全优先级、阻塞/取消、同路径新generation、零剩余构建包、连续短任务下大任务不饥饿及压力消失后恢复原策略。开启候选的既有CPU回归分别为publication_order 29、backpressure 26、ready_backlog_capacity 47、ready_queue_width 16、collision_publication 32、private_publication_packet 23，全部通过。检查包括仍活着的worker不能提前释放、字节/独占约束、碰撞推进期间保留私有结果，以及整组原子发布。

真实私有桌面GPU回归：native_streamed_reference_publication 29/29、prepared_material_publication 102/102，覆盖零热缓存返回、同图像不同材质角色共享、原像素/mip、源版本交错、取消/失败/重试及无作用域泄漏。测试暴露两处旧夹具失配：streamed Document覆写未传新prepared_context参数，导致解析失败；旧断言要求streamed owner一定退回临时节点，但当前正式代码已支持其直接投影。关闭候选同样96通过/1失败。修正前者接口，并为后者分别显式测试直接投影和节点回退，保留旧路径及GPU像素检查。新增双路径夹具初稿重复借用会被job退休清空的packet，出现sources缺失；改为每例转交独立Dictionary容器后102项通过。所有失败日志保留，未修改生产逻辑以迁就测试。

上下游边界：碰撞/支撑检查发生在对象最终进入地图的提交门口，不是后台结果释放时的再次认证。`_job_consumed`仅确认活跃成员已提交/取消/失败；`_discard_job`处置私有游标、资源引用和原有计费。无依赖的不同结果可交换提交顺序，同一资源的准备、使用和释放仍有先后关系。另发现`_discard_job`与记录接收无条件清空碰撞查询缓存，可能造成无成员变化时重新扫描/提交ticket；后续应独立复现，不能把正在进行的乱序对照混入这项修改。

正常整图ABBA已按固定地图/源码、全HUD、正常预算串行完成。首次`completed_map10_A1`误用了历史白模已禁用的开关名，在入口前拒绝并退出2；还暴露测试宿主立即退出时autoload线程未收尾的错误，没有地图性能成绩。改用独立的`--completion-service`/`--without-completion-service`后运行`completed_map10r2_A1/B1/B2/A2`，四份均退出0、零引擎/脚本错误、零失败，无其他引擎/编译进程，地图/源码前后相同，旧owner释放且回收排空。汇总为`P/completed_map_comparison.json`。

| 项目 | A1关闭 | B1开启 | B2开启 | A2关闭 |
|---|---:|---:|---:|---:|
| 入口 / 完整就绪 s | 14.181 / 64.086 | 15.217 / 63.997 | 16.744 / 74.351 | 15.520 / 68.170 |
| 返回事务后收尾 s | 50.093 | 51.802 | 52.533 | 56.148 |
| 可玩加载段最大帧 ms | 714.008 | 639.857 | 705.387 | 695.300 |
| 卸载最大帧 ms | 247.682 | 279.913 | 273.559 | 307.187 |
| 返回加载 p95 / max ms | 49.876 / 87.065 | 50.086 / 86.778 | 50.257 / 80.625 | 56.198 / 86.034 |
| 返回加载 >50ms 帧 | 76 | 84 | 85 | 174 |
| 初次稳定 / 返回稳定 1% low FPS | 33.29 / 27.88 | 27.27 / 26.29 | 32.16 / 27.46 | 33.39 / 22.40 |
| 有未启动源时0 worker、4 ready的采样数 | 41 | 46 | 53 | 46 |

初次工作量均为1505实例、1074引用读取、742直接prefab、1870节点访问/释放、2176网格投影、9731922面准备顶点。B的调度额外评估623/630次、检查10215/10672个候选成员；独立夹具提前释放名额的收益没有转化为整图加载或worker空闲采样的改善。**候选默认继续关闭**，不称作已解决生产阻塞。用户进一步要求重点查明单项为什么处理慢，不再围绕顺序微调。

### 队列逐项时钟与三次固定条件排序

新增`--trace-queue-latency`：只开启有界队列时钟，不开启每500ms重建候选的CompletedAudit。每个实际worker调用（包括continuation）在私有结果里携带开始/结束时刻，主线程join后记录并移除；worker不写共享journal/文件。每个任务记录dispatch、worker完成、join、accept、私有构建、commit、slot释放、真实lease释放；主线程另记录accept、instance_begin/asset/spec、packet_commit、prefab_material及result_retirement的实际调用墙钟。生产默认关闭。

`tools/summarize_completed_job_latency.py`输出全部任务的时间戳、驻留时间、worker/main处理跨度、阶段和逐调用倒序CSV；以时间区间并集扣除已知工作，避免把并行/嵌套时间重复算成CPU。其余驻留时间仅标为未归因，不能直接称为CPU空闲。独立时钟fixture最终`completed_service_timing03` **41/41**，分析器Python **3/3**，包括缺失退出时刻、采样丢失、并行跨度和同源新generation。timing02唯一失败为测试误把合法负数Godot对象ID当作错误，改为非零判断，保留失败。

依用户要求，`queue_unit_latency10_01/02/03`三份完全相同条件串行诊断：默认candidate10，固定地图SHA `ee80500d…`，全HUD、候选关闭，同源码/开关，新进程与独立空用户缓存，保留系统/驱动缓存。三份均退出0、零错误/失败、无其他引擎/编译进程、两层journal均0丢失，旧owner释放及回收排空通过。不是严格冷盘样本，也不能以三份估计p95。完整就绪分别68.662 / 65.975 / 63.606s；每份372个任务，处理单元4972 / 5033 / 4946，分片数差异不等于重复模型工作。

`tools/compare_completed_job_latency.py`验证三份地图/源码/引擎/探针/参数相同及无失败，输出按资源累计、按资源阶段累计、按单次尖峰的倒序表，保留每次值及所有>50ms事件。单次按中位数排序之外，独立保留最大值，防止漏掉仅出现一次的511ms。初次和返回均纳入本表；嵌套LoadTrace只关联确认的主线程，不与外层相加。最终证据`P/queue_latency_three_run03/`，此前01/02保留。

| 主要处理阶段 | 第1次累计 / 最大 ms | 第2次累计 / 最大 ms | 第3次累计 / 最大 ms |
|---|---:|---:|---:|
| 实例开始（可能包含立即完成的spec） | 5158.207 / 111.684 | 5125.505 / 108.953 | 5154.897 / 120.478 |
| 分片spec投影/临时节点释放 | 1169.175 / 4.743 | 1803.395 / 511.544 | 1380.322 / 142.656 |
| 接收结果 | 538.838 / 119.779 | 416.084 / 23.781 | 852.930 / 463.652 |
| 发布整组 | 426.825 / 17.417 | 455.547 / 20.912 | 417.434 / 16.459 |
| 结果退休 | 180.015 / 3.138 | 181.296 / 4.545 | 179.226 / 3.413 |

最值得先复现的是逻辑资源ID `2abd3fe0…`：各阶段合计527.366 / 1104.900 / 869.967ms，三份累计资源榜均第一。实际走native `67d997c9….scn`，逻辑键`.glb`后缀不代表运行时导入GLB。第1次`obj_1583`的`arch_C_LOD2`释放110.620ms；第2次`obj_1302`的`arch_C_LOD1/0/2`释放511.306 / 122.452 / 54.971ms，另`obj_177`的LOD2释放107.945ms；第3次`obj_1577`的LOD2释放119.507ms。模板cache_pack也有114.136 / 458.108ms。这里只能说这些调用承担了长墙钟，不能说实际模型计算本身花了这些时间。

另一个三次一致热点是`reference:road_batch:137`中`pavement_28cfb38d30df3a942dcd`的instance_begin：88.809 / 69.364 / 85.300ms。三次均与逻辑模型`6b811b8f…`后台准备相交；时间重合本身不证明互锁。植被`5dde353b…`的224次instance_begin累计406.813 / 374.382 / 393.089ms，属于稳定的高调用量成本，保留在累计榜，不能只盯单次尖峰。

### 从排序提取真实对象，先验证能否独立复现

`tools/probe_native_instance_lifecycle.gd`只读冻结地图中`obj_1302`原记录，走实际native worker准备、交接同步、模板缓存、AssetInstancePreparation、InstanceSpecPreparation及临时节点释放；输出记录、原生产品身份、每个步骤与内层节点时钟。私有桌面真实GPU、无GLB导入、不改正式资源。`native_instance_lifecycle10_01/02`各做三次，后一份还按正式spec创建可见实例并绘制三帧再释放。均通过、零错误，spec单步最大仅0.542 / 0.584ms、模板缓存2.846 / 3.018ms，**尚未复现整图100–511ms停顿**；不据此宣称优化完成。

引擎源码显示`VisualInstance3D`析构进入`RenderingServerDefault::free_rid`，可先排空渲染命令；`RendererSceneCull::free`还在前后刷新全局dirty实例/资源。这是其他工作落到临时节点释放调用里的候选原因，需运行栈与独立场景证实。接着补全局待处理实例规模与后台上下文，不先删除安全同步或依赖处理，也不放大结果队列。

### 原生栈确认：实例释放夹带全局材质编译等待

`queue_node_release_gdb10_01`首次全线程抓样在早期ResourceLoader入口停留，12份样本没有命中目标；后续同进程补84份主线程样本也未抓到实例释放。正常退出、零错误/失败，180.334s就绪含调试停顿，不作为正常成绩。没有删除这份未命中证据。

改在日志`AXEL_ENTRY_READY`之后开始采样，`queue_node_release_gdb10_02`得到271份主线程栈。样本62准确命中：`VisualInstance3D::~VisualInstance3D → RendererSceneCull::free:4434 → RendererRD::Utilities::update_dirty_resources → MaterialStorage::_update_queued_materials → SceneShaderForwardClustered::MaterialData::update_parameters → ShaderRD::version_get_shader → _compile_version_end → WorkerThreadPool::wait_for_group_task_completion`。这是实例释放内部等待shader编译的直接证据，不是仅以时间重合推测互锁。

通过同次报告的`cpu_time_anchor`对齐，此栈位于`reference:road_batch:140 / pavement_22ba80fe55bb8374d462`的`instance_spec.release_node`内；外层实例spec诊断跨度1.823s包含约1.7s调试器暂停，绝不当作普通帧耗时。并发worker正在准备`2abd3fe0…`，但没有把它的嵌套worker跨度误算为主线程工作。对齐结果`P/queue_node_release_gdb10_02/node_release_attribution.json`。该栈证明这类释放等待机制，尚不能单凭它把三份普通运行里的全部pack/LOD尖峰逐一归因。

只读GDB从被等待的材质读出1534字符shader，UTF-8文本SHA `c5e1a70937b76a69dea70413e0b2956f12cdb1fb4592084ec0ff46b40506a75e`，是使用顶点色的StandardMaterial生成代码。保存为`P/captured_<文本SHA>.gdshader`；Windows文本输出转成CRLF后的文件SHA为 `a591fa57b3c7488f94efec41586da86fb6c79d6a66b1faf40ddf55ab7de8efff`，所有基线/候选均使用这份未改动字节，报告记录文件SHA。`captured_shader_provenance.json`验证换行归一后与GDB代码完全一致，不把文本SHA冒充文件SHA。不修改任何作者模型或材质。完整诊断零错误/失败、旧owner释放及回收排空，162.609s完整就绪仍只作调试证据。

独立复现增加两种上下文：`native_instance_dirty10_01`借用原模型mesh创建4096个无关私有实例，在原图释放前保持未更新，spec最大从不到0.6ms升到6.125ms；这说明全局实例队列确实影响局部释放，但不能解释100–511ms。进一步在原对象释放前创建一个**未绑定到它的**ShaderMaterial，使用上述现场shader，触发真实dirty材质队列，无sleep/假工作。`native_instance_shader10_01/02/03`三个独立进程均成功，`arch_C_LOD2`释放分别 **93.391 / 70.106 / 79.474ms**；其余节点及准备逻辑不变，三次均零错误/失败，地图SHA不变。原孤立对象不足1ms的失败复现与新增上下文均保留。

据此建立引擎candidate11，输出在`P/engine_instance_release_candidate11/`。改动仅把`RendererSceneCull::free`前后两次“dirty实例+全局资源”刷新改为原有dirty实例列表刷新；保留实例依赖、解绑、两次列表排空及所有渲染命令同步。全局材质/资源仍在正常渲染更新阶段处理。这是候选，当前尚待首次绘制像素、共享材质释放、取消及整图验收；即使局部释放变快，也要检查是否仅把编译停顿移到draw。默认candidate10尚未替换。

构建407.406s，运行文件SHA `a0516deb4b8a89ee09d2ad933db9b5c9fe3b9604cd4f300816ec523e6b52a501`，匹配符号SHA `59bc871822768fabd0af4883be064df51bde331ddf1d3345d952d787694c67a6`，源码构建期间不变、默认引擎文件不变。增量patch、前后源码SHA及复验记录归档`tools/engine_patches/godot-4.8-beta1-instance-release-candidate11.*`。

`native_instance_shader11_01/02/03`同样三个独立进程、相同shader和实际原记录，节点释放最大 **0.114 / 0.138 / 0.129ms**，完整spec单步最大 **1.350 / 0.904 / 0.812ms**，三份均无错误/失败。候选首份native准备2.594s，比其他约0.37–0.42s慢，保留且不能用于宣称总加载收益。

新增`test_instance_release_material_gpu.gd`，旧引擎与候选各 **25/25**：实际非空绿色首帧、释放无关/共享材质实例后像素与显式预先刷新一致、更新尚待提交时取消owner、后继材质继续正确显示。只在此逐像素夹具关闭TAA，普通整图设置不变。候选回归：instance_spec_preparation **15/15**、asset_instance_preparation **10/10**、native_streamed_reference_publication **29/29**、prepared_material_publication **102/102**，均真实GPU、零引擎/脚本错误。

局部快不等于整帧快：首帧夹具的无关实例释放从6.940ms变0.028ms，但后续绘制从5.751ms变12.113ms；共享材质对应6.376→0.034ms和7.271→12.673ms。这是材质工作转回正常渲染阶段的直接证据，尚未证明shader工作本身被消除。正式整图ABBA继续验证发布关键路径与卸载/返回，不安装未经比较的候选。

### candidate11正常整图ABBA：释放解耦有效，加载/low尚不能验收

`instance_release_map11_A1/B1/B2/A2`串行全部完成，A为默认candidate10，B为隔离candidate11。游戏源码、地图、全HUD和正常预算完全一致，唯一变量为引擎；没有profiler/GDB或其他引擎/编译进程。四份均退出0、零错误/失败，旧map/loader真正释放、回收排空、返回需求就绪，源码及地图SHA前后不变。汇总`P/instance_release_map11_comparison.json`。每次新进程及独立用户缓存，系统/驱动缓存保留；不是严格冷盘，不由四份计算加载p95。

| 项目 | A1旧引擎 | B1候选首次整图 | B2候选再次 | A2旧引擎 |
|---|---:|---:|---:|---:|
| 入口 / 完整就绪 s | 16.175 / 73.838 | 48.097 / 119.208 | 16.420 / 67.437 | 15.760 / 66.605 |
| 入口原生准备worker墙钟 s | 4.209 | 33.517 | 3.837 | 3.872 |
| 初次实例spec最大 ms | 118.852 | 1.709 | 1.676 | 33.682 |
| 初次deferred发布回调最大 ms | 480.365 | 100.875 | 82.326 | 89.911 |
| 可玩加载段最大帧 ms | 696.077 | 3686.791 | 857.359 | 731.746 |
| 卸载最大帧 ms | 404.478 | 2113.513 | 259.770 | 268.287 |
| 返回事务后收尾 s | 54.665 | 55.002 | 52.853 | 51.195 |
| 返回加载 p95 / max ms | 59.165 / 96.026 | 53.050 / 81.401 | 52.664 / 100.779 | 51.450 / 83.449 |
| 返回加载 >50ms 帧 | 198 | 125 | 116 | 108 |
| 初次稳定 / 返回稳定 1% low FPS | 30.76 / 32.53 | 32.14 / 30.99 | 32.56 / 31.54 | 29.41 / 32.68 |

初次和返回的结构工作量四份均相同：1505实例、1074引用读取、742直接prefab、1870节点访问/释放、2176网格投影、9731922面准备顶点；没有借跳过内容获得改善。初次publication单元2196 / 2192 / 2201 / 2179为时间分片差异。初次deferred交互回调累计7.206 / 6.531 / 5.869 / 6.143s；B仍有33/39个0worker、4ready、需求未完的500ms样本（A48/41），不是所有生产阻塞已解除，也不能用不同持续时间下的样本数直接当吞吐提升百分比。

**已证明的收益**是实例释放不再承担全局材质编译：三次独立复现和两次真实地图的spec最大值都下降，依赖清理及后续材质首帧保持正确。**未证明**总加载和low改善：B2总时间仍与A2相近，返回最大帧反而更高，B1有119.208s及2–3.7s尖峰，全部保留。B1的原生准备33.517s集中在逻辑资源`7824a14b…`的同一281810329字节native产品，A1/B2/A2均约3.8–4.2s；这是下一次需要定位的差异，不能只凭“首次新引擎路径”把它归因于缓存或OS。当前不替换默认引擎。

后续顺序：先澄清candidate11首次原生准备/首帧异常，确认引擎候选是否可正式采用；继续对三次稳定出现的`pavement_28cfb38d30df3a942dcd`约69–89ms实例开始做独立复现，以及把剩余渲染编译等待与真正绘制工作区分。高调用量的植被初始化继续留在累计榜，不能因单次较短丢掉。碰撞缓存失效清理仍仅有未运行的草稿测试，不作为已交付修复。本轮没有改模型/纹理/地图内容，所有实验patch和失败/慢样本保留。

### 首次新路径慢读的对照与原生管线等待

`instance_release_path_control10_01/02`将默认candidate10运行文件逐字节复制到此前未运行的隔离路径，两次均SHA `7a8029a6…`，没有candidate11改动。沿用上述冻结工程/地图、全HUD、正常预算与空私有用户缓存，无调试器/其他引擎/编译进程。两份均退出0、零错误/失败、源码地图前后相同。

| 同一旧引擎、新路径 | 首次01 | 第二次02 |
|---|---:|---:|
| 入口 s | 48.993 | 16.451 |
| 完整就绪 s | 118.893 | 65.337 |
| 同一281810329字节native产品准备 s | 35.534 | 3.835 |
| 可玩加载最大帧 ms | 4156.999 | 849.466 |
| 卸载最大帧 ms | 1945.714 | 247.230 |

旧引擎在新路径首次同样慢，证明candidate11不是触发这类异常的必要条件；同一路径第二次恢复，支持继续调查可执行路径相关的首次准备成本。仍不能由此宣称已识别具体驱动缓存、OS因素或所有长帧原因，也不能据此把候选首次慢样本删除。

`probe_native_product_read.gd`单独调用正式`CompiledAssetPreparation.read`，使用初始公会`obj_1033`的同一原生产品及CPU handoff，不导入GLB、不创建地图。`native_read_newpath_gdb10_01`使用另一份同SHA旧引擎新路径，在读前的显式诊断门口预载符号并附加，随后抓全线程栈。30次采样中25次命中真实读取worker的`ArrayMesh::_set_surfaces → RenderingServerDefault::mesh_create_from_surfaces → RenderForwardClustered::mesh_generate_pipelines → PipelineHashMapRD::wait_for_pipeline → WorkerThreadPool::wait_for_task_completion`；另3次在同一worker的材质shader完成等待。此为调用位置采样计数，不是CPU占比。

对应引擎源码`render_forward_clustered.cpp:5157`明确在非background模式等待所提交的ubershader管线；`rendering_server_default.h`给worker传入false。因此“compiled native read”不仅是读取/解码，还包括同步渲染管线准备。现场也有AMD Vulkan驱动执行栈，但符号不完整，未据此认定驱动bug。该诊断成功、零错误，112.308s跨度包含84.604s的栈收集暂停，绝不当普通加载成绩，也不简单相减冒充正常成绩。默认引擎仍candidate10，尚未改变管线等待策略。

### 同一道路的独立三进程复现：先保留未复现边界

`probe_ranked_road_lifecycle.gd`只读冻结地图的`pavement_28cfb38d30df3a942dcd`，真实worker准备原道路数组、边界、涂装和原贴图，主线程走正式纹理分片、scope、`WorldDocument._mesh`及spec投影/私有节点释放。为查计时空白，单列包含函数返回清理的整个`_mesh`调用，不能只相加其内层字段。每个进程重复使用同一份准备结果三次；这是组件隔离测试，没有整城并发上下文，也不是GPU绘制等价验收。

初稿`ranked_road_isolated10_01`因测试使用`is preload(...)`语法解析失败，修为命名脚本常量，两份新测试脚本parse-check通过，失败日志保留。随后`ranked_road_isolated10r2_01/02/03`三进程均成功、零错误/失败，原地图SHA不变。

| 每进程最大调用 ms | 01 | 02 | 03 |
|---|---:|---:|---:|
| 纹理准备/提交分片 | 76.753 | 54.069 | 53.844 |
| `_mesh`含返回 | 8.784 | 5.412 | 7.850 |
| scope begin | 0.124 | 0.178 | 0.137 |
| spec投影/释放 | 0.246 | 0.143 | 0.156 |

每份均9次纹理步骤、3次网格构建、3次spec推进，组件没有减少内容。**仍未复现整图的69–89ms instance_begin**：孤立纹理首提虽慢，其阶段不同，不能直接等同原热点或报已解决。继续在正式队列诊断中拆出texture ready check、scope begin/end和mesh完整返回跨度；新增计时只在LoadTrace开启时执行，正式发布语义与预算不变。

### 补齐真实resident上下文：结束纹理作用域首次加载编辑器脚本

细分整图`road_queue_detail10_01/02`的目标道路instance_begin分别97.851 / 89.548ms，其中`record_scope_end`占91.797 / 81.647ms，而整个`_mesh`含返回仅3.031 / 3.975ms。结束调用是`HousePrefab.end_texture_publication → load(terrain_texture_preparation.gd).restore(previous)`；本调用不传failed纹理，restore有效工作只有恢复`Paint.prepared_images`。原先与后台模型的时间重合不能证明上传锁，新的内层时钟把范围缩到这个调用。

补充`--resident-only`独立fixture：仍使用原道路和原贴图，先通过正式纹理路径得到实际GPU owner，转为共享池同样的resident ticket交接，保持其真实source身份；不提前调用编辑器图片install helper。`ranked_road_resident10_01/02/03`全部成功、零错误/失败。三份helper在发布前均未缓存，第一次scope end后均变为已缓存；该调用分别 **62.583 / 56.959 / 56.572ms**，后两次恢复很短。这补齐了此前孤立Image交接未复现的上下文：Image安装路径会较早加载helper，resident路径第一次真正需要它反而在scope结束。

修复只把无failed参数的scope结束改为直接恢复原Dictionary引用，保留uploaded texture恢复、进入作用域时的身份/失效处理，以及失败、取消时的原清理逻辑。没有把耗时移到预热或扩大缓存，不再为一次赋值动态加载编辑器辅助脚本。

`ranked_road_scope_fixed10_01/02/03`同样三进程、同记录/owner/work，scope end最大 **0.016 / 0.023 / 0.016ms**；辅助脚本始终未进入缓存，三份零错误/失败。既有真实GPU回归`test_prepared_material_publication_scope_restore10_01` **102/102**、`test_streamed_texture_publication_scope_restore10_01` **103/103**，包括精确外层owner恢复、共享/不同角色纹理、实际GPU纹理像素与mip、源版本切换、取消及失败、零热缓存。尚需与整图后续三份细分样本对照；组件结果不能替代总加载或low验收。

### 整图前后三次：道路热点消失，剩余长帧完整保留

修复前road_queue_detail10_01/02/03均目录命中，第三份目标scope end为79.982ms。修复后的road_queue_scope_fixed10_01源码变化触发stale_index：目录重建读取1448项、后续入口reference_read读取1056项，并交接1098个已还原记录；deferred记录读取从1074降为435，是提前读取/交接造成的工作位置变化，不能冒充本次scope修复节省了639次读取。该冷目录样本完整就绪66.075s、卸载239.599ms、返回最大85.079ms，全部保留。

因此另补road_queue_scope_fixed10_04，最终同条件三份取修复后 **02/03/04**，初次及返回均目录命中。新增排序合同检查初次/返回的directory hit/rebuild标记；真实混合01/02/03会拒绝生成同条件榜，失败证据mixed_directory_rejection.log保留，Python回归 **5/5**。此前混合三份分析road_scope_map_comparison.json保留为探索记录，不用于最终三次排名。

最终排名是P/road_scope_before_matched_three/及P/road_scope_after_matched_three/，都有完整资源累计、资源阶段累计、单次倒序CSV，以及未删减的>50ms事件；对照为P/road_scope_map_matched_comparison.json。六份固定源码各组三次、同地图/引擎/预算/全HUD，没有GDB/官方profiler/其他引擎或编译进程；均退出0、零错误/失败、两层journal零丢失、旧owner释放及回收排空通过。开着队列/内层时钟，仍是诊断样本，且顺序为AAA后BBB，**不是正常性能ABBA或加载p95**。

| 项目 | 修复前01 / 02 / 03 | 修复后02 / 03 / 04 |
|---|---:|---:|
| 目标道路初次instance_begin ms | 97.851 / 89.548 / 86.165 | **6.190 / 5.532 / 4.972** |
| 同道路返回instance_begin ms | 5.162 / 5.420 / 5.188 | 9.156 / 5.738 / 5.541 |
| 完整就绪 s | 81.211 / 75.382 / 64.946 | 67.993 / 66.690 / 64.743 |
| 卸载最大帧 ms | 327.520 / 286.159 / 246.714 | 222.355 / 259.419 / 320.276 |
| 返回加载p95 ms | 57.100 / 48.553 / 46.377 | 55.511 / 55.470 / 53.855 |
| 返回加载最大帧 ms | 96.521 / 84.404 / 68.672 | 134.509 / 90.945 / 86.915 |
| 初次稳定1% low FPS | 31.22 / 30.64 / 34.90 | 29.01 / 34.62 / 29.08 |
| 返回稳定1% low FPS | 26.47 / 30.19 / 30.78 | 28.51 / 29.89 / 24.38 |

目标道路修复后没有超过2ms阈值的scope end事件，不将被阈值省略的小调用写成0。六份初次/返回结构工作量均为1505实例、1074引用读取、742直接prefab、1870节点访问/释放、2176网格投影、9731922面准备顶点；时间分片次数略变，不是删内容。能够确认该局部首次加载工作被去掉；不能把总时间差或low波动归因于这一个修复。

最终修复后三份仍分别有 **536.036 / 520.970 / 491.872ms** 的spec单元，内层均为私有节点释放；另有pack等尖峰。累计资源榜首重新为2abd3fe0…（中位831.703ms），植被5dde353b…为472.063ms，完整保留。没有把这些既有问题算成已解决，也没有扩大队列或放宽依赖条件。

下一轮应回到上述原生管线等待及既有释放/pack等待：candidate11仍隔离保留、默认仍10；需评估原生准备是否必须逐网格等待全部管线，以及异步准备的首帧正确性、取消/资源寿命和真实总耗时，不能只移动等待位置。Image安装仍会调用编辑器helper，是否能把共享运行时安装逻辑从编辑器依赖中拆出留作同链候选。此轮仅完成scope结束的不必要加载修复，纹理画质和地图/模型资源均未修改。

### 原生管线等待：同条件各三次，区分重复运行与新路径首次运行

本轮沿用P、冻结地图和同一281810329字节公会原生产品，未修改地图、模型、纹理或正式运行参数。默认引擎仍candidate10，下面两个新构建均仅放在外部证据目录。已有整图倒序榜仍以此前同条件三份为准；本节是从原生读取热点拆出的独立测试，不把它替换成整图加载、卸载或low成绩。

candidate12继承11，仅增加默认关闭的`RMMO_ASYNC_MESH_PIPELINES=1`：Forward+的`mesh_generate_pipelines`仍提交同样的管线任务，但开启时不收集逐网格等待数组、不在每个网格后等待，绘制及资源销毁保留原有完成等待。引擎SHA `0c714661071765e68a0fddfdb54eae1b874f5ae4e74cfac471c623de54f00b44`。比较使用同一候选的开关两种状态，不能把10与12的差值全归因于该开关，因为12还包含11的实例释放改动。

`probe_native_product_read.gd`补充首次实际显示、节点释放、最后PackedScene owner释放、帧间隔和官方RenderingServer管线计数。显式`--inventory`检查得到2319个节点、2007个独立网格、2099个surface、139个surface材质owner、9个shader RID；该操作前后管线计数均为42，没有产生额外编译。库存扫描不放在正式计时样本的读取与首次显示之间，防止它替后台准备争取额外时间。

初稿解析失败日志`pipeline12_product_parse.log`保留，修为显式Transform3D类型。初稿跨await传递PackedScene，清空Dictionary只有4us，不能据此证明最后owner已释放；正式版本改用可清空的packet交接并检查WeakRef失效，最后owner释放在约20–40ms。`native_pipeline12_draw_off_01/02`保留为探索样本，前者还出现下文的退出卡住，不纳入正式三次性能表。

正式重复运行样本为`native_pipeline12_triple_{draw,cancel}_{off,on}_01..03`，每种操作按off/on/on/off/off/on交错运行，固定测试脚本SHA `6b06826c89c0b8d972d08fb2e6ff0bc1911df129fb62297153975e1f24e3ac28`，每次新进程及私有用户目录。串行GPU，不带GDB，运行前检查无其他引擎/编译进程；保留OS和驱动缓存，不称为冷磁盘。12份均退出0、零错误、PackedScene owner释放成立；6份显示样本首次像素与随后12帧稳定像素完全一致。

| 同一引擎路径重复运行 | 逐网格等待 off：01 / 02 / 03 | 异步 on：01 / 02 / 03 |
|---|---:|---:|
| 显示用例的原生读取 ms | 3078.586 / 3286.556 / 3139.255 | 3122.889 / 3103.906 / 3136.969 |
| 读取完成后至首次显示 ms | 164.269 / 170.665 / 176.664 | 189.554 / 197.429 / 189.331 |
| 首次draw等待 ms（包含于上一行） | 31.463 / 34.137 / 31.487 | 47.388 / 51.981 / 49.616 |
| 最后PackedScene owner释放 ms | 28.515 / 28.230 / 29.063 | 32.427 / 28.014 / 28.606 |
| 读完立即取消用例的原生读取 ms | 3353.888 / 3124.773 / 3132.867 | 3060.075 / 3178.043 / 3234.314 |
| 取消用例owner释放 ms | 30.147 / 19.606 / 22.368 | 24.434 / 19.810 / 24.968 |

显示用例每次均42 mesh、2 surface、28 specialization管线；取消用例均42 mesh、0 surface、0 specialization。没有少做模型内容，也没有多编译管线。这组没有确认总收益，首次draw等待反而增大；不能只报读取最快一次。报告为`pipeline12_triples_index.json`和`pipeline_shutdown_comparison.json`。计时是壁钟跨度；读取完成至首次显示还包含实例化、相机/环境设置及背景读回，不能全部归为引擎管线等待。

### 真实退出卡住：线程池低优先级队列排空后漏唤醒

`native_pipeline12_draw_off_01`写完报告后仍不退出，180秒被其测试宿主终止。GDB的`native_pipeline12_exit_stacks.jsonl`显示主线程停在`WorkerThreadPool::exit_languages_threads`，所有12个池线程停在空队列条件变量等待。

修正owner测量后的新路径样本`native_pipeline12_first_path_off_01`再次出现相同问题，虽然报告已确认owner释放。`shutdown_state.json`抓到明确状态：`RUNLEVEL_PRE_EXIT_LANGUAGES`、`num_idle_threads=3`、线程数12、普通及低优先级任务队列均为空。两次都在异步开关关闭时发生。该次完整保留为超时失败并停止其批次，不能把报告中的ok写成进程成功。

源码机制是：切换到退出登记时，部分空闲线程看见低优先级队列尚未清空，未登记便再次休眠；能接低优先级任务的少数线程继续排空队列、登记自己，剩余休眠线程没有再被唤醒，主线程无限等待其登记。不是任务尚未完成，也不是地图依赖检查。

新增`test_worker_pool_pending_shutdown.gd`：仅提交40个原生`OS.delay_msec(100)`任务后退出，没有地图、GPU或工作线程GDScript回调。`check_worker_pool_pending_shutdown.py`使用独立空工程、12个worker、0.25低优先级比例及每次私有用户目录；低/高优先级各3次，真正进程退出才算通过，任务已入队标记不算成功。

最初使用完整冻结工程和8秒超时的`shutdown_default10_before_01`受工程启动开销干扰，只作夹具探索。正式空工程在默认10与candidate12上均连续3次低优先级超时，高优先级对照均正常退出。最终用入库runner重跑默认10，记录为`shutdown_isolated_default10_final_before_01`。

candidate13只在`exit_languages_threads`等待空闲登记的循环内补唤醒：其他线程报告空闲后，主线程在同一已有锁下唤醒尚未登记的线程，使其重新检查已排空的队列。正常运行的任务选择、并发数、优先级、队列大小、完成条件均不变。继承12，异步开关仍默认关闭；SHA `be2ccb71c4cfaba194d331c094ffe48a88d7b559320056c0157efafeb2b64715`。

| 独立关闭测试，实际进程耗时 s | 默认10：01 / 02 / 03 | 修复13：01 / 02 / 03 |
|---|---:|---:|
| 低优先级40任务 | 8秒超时 / 8秒超时 / 8秒超时 | **2.078 / 1.734 / 1.734** |
| 高优先级40任务对照 | 0.734 / 0.734 / 0.688 | 0.703 / 0.734 / 0.688 |

这是关闭流程修复，不能据此宣称游戏中区块卸载长帧消失。修复后的GPU `pipeline_first_draw13_off_01/on_01`各 **28/28**：初次显示、3次即时取消、2个真实并行reader中取消一个再显示另一个、重新读取，均验证首帧像素及PackedScene owner真正释放。

复现命令：`python tools/check_worker_pool_pending_shutdown.py --engine <引擎绝对路径> --output <外部新证据目录>`；旧引擎加`--expect-low-timeout`代表预期复现缺陷，而非旧引擎通过正常关闭验收。补丁、来源/产物SHA与测试边界分别入库`godot-4.8-beta1-mesh-pipeline-candidate12.{patch,json}`及`godot-4.8-beta1-worker-shutdown-candidate13.{patch,json}`。

### 关闭修复后完成新路径三次：吞吐有收益，但首次draw仍不合格

修复后使用同SHA candidate13的6份全新可执行路径，每份仅首次运行；仍按off/on/on/off/off/on交错、各3次，真实产品及测试脚本不变。命名`native_pipeline13_first_path_{off,on}_01..03`，索引`pipeline13_first_paths_index.json`，无GDB/并行编译。全部正常退出、零错误、owner释放、首次和稳定像素一致。没有删除或清空系统/驱动缓存，这叫“新路径首次执行”，不能写成严格cold磁盘或已证明的cold驱动缓存。

| 新路径首次执行 | 逐网格等待 off：01 / 02 / 03 | 异步 on：01 / 02 / 03 |
|---|---:|---:|
| 原生读取 s | 17.199 / 17.231 / 17.061 | **4.621 / 4.536 / 4.519** |
| 读取完成后至首次显示 ms | 329.449 / 325.951 / 334.794 | **1680.665 / 1595.604 / 1577.077** |
| 首次draw等待 ms（包含于上一行） | 66.047 / 64.187 / 54.111 | **1250.517 / 1278.155 / 1256.592** |
| 进程/夹具完整运行 s | 32.406 / 32.095 / 31.846 | 19.811 / 19.711 / 19.551 |
| 最后PackedScene owner释放 ms | 32.213 / 32.362 / 40.358 | 38.880 / 34.110 / 32.879 |

每份工作量仍为42 mesh、2 surface、28 specialization管线，像素一致。这证明原生worker逐网格等待会拉长新路径首次准备的关键路径；异步并非增加队列或少编译才变快。按本组件边界，读取开始至首次显示中位数约17.529s降至6.132s，但首次draw本身出现1.25–1.28秒等待，不能作为正常游戏优化直接启用。

**当前状态：默认引擎10未替换，异步开关未启用，整图加载/卸载/返回与low本轮尚无新验收结论。** candidate13关闭修复通过独立复现及真实产品关闭回归，candidate12机制保留为隔离试验。下一步优先研究整份native产品先提交管线、再在后台统一完成等待后交接；必须保证取消、失败、共享shader及资源存活，不能只把wait删掉，不能把1秒等待移到游戏首次绘制，也不为批量等待重复扫描全部网格。完成后再回到同条件三份队列榜及整图生命周期比较，既有500ms私有节点释放和卸载长帧仍未关闭。

### 原生读取后台批量完成：组件收益成立，普通读取与游戏入口须区分

candidate14r2 继承13，新增默认关闭的 `RMMO_BATCH_MESH_PIPELINES`。仅在独立原生读取线程启用，主线程和 WorkerThreadPool 任务保留原来的协作等待，避免编译池自等。沿原有 surface 读取循环保留唯一材质 owner、收集独立的完成凭据，不再遍历第二次网格，也不借用可能已被别的线程取走的 task ID。整份产品返回前等待唯一编译完成项并释放临时引用；失败根类型和取消同样遵守这个边界。已编译 task ID 在队列中移出后于局部锁外回收，避免遗留和重复等待。

构建 SHA `f5504198b6c33d2b1e00acef1c02f39b2020bd44b3780c5d0e7dcd535e51f0de`，旧异步开关始终为0。第一次准备脚本中断、第一次编译条件变量使用递归 Mutex 的失败均保留，最终使用 BinaryMutex；不能把失败目录当成功构建。GPU初稿非场景根 fixture 保存方式错误也保留，改为有效 .res 原字节改扩展名后验证加载后根类型失败。

最终 `pipeline_first_draw14_off_02` **53/53**、`pipeline_first_draw14_on_01` **78/78**，覆盖两种真实材质、两个共享shader reader、取消、失败和主线程/池线程回退。`native_cpu_handoff_batch14_01` **35/35**、`prepared_material_batch14_01` **102/102**。公会独立 inventory 得到 **6297 次管线请求 → 42 个唯一完成项**、139 个材质 owner；收尾时5项仍未完成，后台等待1.469s，返回时临时owner和凭据均为0。CPU原生输入11,641,784字节，没有重复记录。

六个全新可执行路径按 off/on/on/off/off/on 交错，各3次，结果在 `pipeline14_first_paths_index.json` 和 `pipeline14_component_comparison.json`。同一真实原生产品、独立用户目录，GPU串行、无GDB/编译；不是严格冷磁盘或已证明的冷驱动缓存。全部退出0、无错误、首帧与稳定像素一致、PackedScene owner释放。

| 新路径首次执行 | off：01 / 02 / 03 | batch on：01 / 02 / 03 |
|---|---:|---:|
| 原生读取 s | 20.352 / 19.145 / 18.890 | **6.968 / 7.029 / 6.931** |
| 读取完成至首次显示 ms | 371.805 / 372.954 / 346.567 | 368.888 / 363.945 / 382.317 |
| 最后owner释放 ms | 36.219 / 30.498 / 36.867 | 42.467 / 37.745 / 34.888 |

实际首次draw等待中位数67.375→75.060ms，仍有成本，但没有上一版异步试验1.25s的转移。六份工作量均42 mesh、2 surface、28 specialization，未少做内容。组件读取中位数19.145→6.968s不等于整图缩短12秒。

整图探索 `pipeline_batch14_map_first_on_00` 完整保留：入口33.575s、当前需求全就绪106.449s，初次 `compiled_read` 18.357s。源码发现 `load_job`、编辑器普通读取没有请求CPU捕获，仍直接调用 `ResourceLoader.load`，绕过仅绑在CPU接口上的batch范围。**该编辑器/普通读取缺口确实存在，但起初把它直接归因为真实游戏入口是错误推断；后续核对发现游戏走 `ModelParsePreparation._candidate_stage`，本就请求CPU捕获。** 随后已启动的 off01 / on01 正常完成，分别全就绪72.858 / 70.449s，卸载max247.121 / 214.686ms，返回加载max120.483 / 107.522ms；只有各一次，不能作为三次验收。停止后续series只终止外部协调器，没有中断正在运行的引擎。结束凭据为 `pipeline14_series_stop_receipt.json`。

candidate15补齐不分配CPU捕获上下文的原生批量读取接口，并接入 `CompiledAssetPreparation` 普通分支。普通读取三次组件中位数18.901→6.905s成立，CPU附加网格为0；但真实游戏首轮 `compiled_read` 仍18.585s，证明它没有解释游戏中的等待。剩余整图对照因此停在进程边界，先补实际游戏入口的批量完成统计并用GDB核对调用线程；不能继续把组件收益当游戏收益。默认引擎仍10，本节没有宣布整图或剩余卸载长帧解决。

### candidate15：补齐普通原生读取，保留首次显示变慢的样本

引擎 SHA `16ea82d443dcb76f34b516ed3e8e7c063eabfa556021e439b4b600ae6a21d5e6`。共享原生加载实现新增不创建 CPU capture context 的普通接口；有 CPU 几何消费者时仍调用原接口。两者都在私有读取线程完成同一批量收尾，错误资源保留到主线程回收。成功统计附加在成功返回处，不污染具有严格字段约定的重试/错误 packet。旧引擎没有新方法时保持原 ResourceLoader 路径。

`pipeline15_first_paths_index.json` / `pipeline15_component_comparison.json`：同一真实公会产品，普通 Reader、零 CPU 附加网格，六个新可执行路径按 off/on/on/off/off/on。均正常退出、首帧像素等于稳定像素、最后 owner 释放；每份均42 mesh、2 surface、28 specialization 管线。不是严格冷磁盘或已证实的冷驱动缓存。

| 新路径首次运行 | off：01 / 02 / 03 | batch on：01 / 02 / 03 |
|---|---:|---:|
| 原生读取 s | 18.849 / 18.901 / **23.034** | 6.905 / 6.538 / 7.216 |
| 完成至首次显示 ms | 334.610 / 336.505 / 356.596 | 345.551 / 339.002 / **539.467** |
| 首次 draw 等待 ms，包含于上一行 | 51.916 / 58.816 / 64.079 | 66.903 / 63.256 / **147.329** |
| 最后 owner 释放 ms | 25.565 / 26.667 / 28.518 | 26.674 / 27.882 / 35.190 |

读取中位数明显下降，但不能掩盖 on03 的首次显示回退。功能覆盖：batch off **77/77**、on **111/111**，包括共享 shader 的普通/CPU 两种 reader 并行、失败根类型、取消、主线程/池线程回退及实际首帧；CPU handoff **35/35**、材质发布 **102/102**，默认引擎10的兼容回退 CPU handoff **35/35**。普通 inventory 没有 CPU context，6297请求合并为42唯一完成项。

真实游戏 `pipeline15_batch_receipt_on_01` 无GDB、退出0：入口15.150s，完整就绪66.495s；实际 native read 3.769s，批量统计 **enabled=true、6297请求、42完成项、139材质owner、收尾待完成0、等待2µs、遗留owner/凭据0**。这证明游戏已走到批量范围，不能再把此前18.585s归因于接口未接入。该次是重复路径的统计核对，有少量同时文件阅读，不作为正式性能对照。卸载219.845ms、返回传送360.093ms、返回加载92.139ms仍保留，初次/返回稳定1% low约26.87/25.99。

### GDB发现属性查询全局等待，独立复现后隔离修复

`pipeline15_native_game_gdb_01` 使用显式诊断门、预载符号、两处软件断点及全线程采样。命中 `NativeMeshCpuCapture::_load_native_scene` 的真实私有线程且 capture_cpu=true，再次确认入口。七份栈中主线程出现：

- `SceneState::pack → GeometryInstance3D::_get_property_list → instance_geometry_get_shader_parameter_list → update_dirty_instances → MaterialStorage::_update_queued_materials → ShaderRD::_compile_version_end → WorkerThreadPool` 等待。
- `GLTFDocument::append_from_file → PNG解码`，上游是节点 `_ready`。优化构建未恢复具体 GDScript 调用和资产；只能记录仍有非地图角色/装备导入链候选，不能把具体资源或耗时定案。

该诊断最终 **0x80000003 / 2147483651** 非正常退出，未拿到 finish 断点；软件断点及打断交互可能相关，不能算成功回归、普通计时或已证实引擎崩溃原因。原始报告、debugger日志及 `focus_stacks.json` 完整保留。

独立 `probe_geometry_property_flush.gd` 不加载地图：创建三个尚未完成的真实河流 shader 变体后，查询空 MeshInstance3D 属性或 pack 空网格节点。默认实现查询单个节点会处理全部 dirty instances，并调用全局资源更新，因而同步等待不相关 shader。

最初 `geometry_property_flush15_before_01` 有1项测试假设失败：旧引擎 mesh=null 后仍保留先前实例参数。改用“替换成无材质 BoxMesh”验证声明更新，不把旧 null 行为说成已修复。随后 before02/03/04 均 **31/31**，空网格属性查询216.383/208.297/209.333ms，pack225.786/210.412/205.008ms，三进程复现成立。

candidate16r2 继承15，SHA `abfdc3c81dff5b88a2a50cd10e6954e82b93211c455f6e1a697e58945ddecd12`，新增默认关闭 `RMMO_TARGETED_INSTANCE_PROPERTY_QUERY=1`。仅处理目标 instance 的 dirty dependencies，再取实例参数声明；正常 renderer update/draw 仍更新全部资源。未删除 GPU 编译、未提前声称可绘制，也未扩大预算。初次16编译因 OS 头文件原来仅在 DEBUG_CULL_TIME 下引入而失败，r2改为普通include后成功，两个构建记录均保留。

最终独立测试增加 MultiMesh、粒子 draw pass、覆盖/叠加/next_pass/替换shader、pack实例值以及真实像素更新，固定脚本 SHA `e4e532bf39aa42679f966932e31a4e4bd6f57465020b4dc79e98390f74ee5a5b`。同一引擎 batch始终1、旧async始终0，targeted开关 off/on/on/off/off/on，六份 **39/39**：

| 独立复现 ms | targeted off：01 / 02 / 03 | targeted on：01 / 02 / 03 |
|---|---:|---:|
| 空网格属性查询 | 220.108 / 202.572 / 219.556 | **2.987 / 16.687 / 2.364** |
| 空网格 pack | 240.142 / 188.375 / 213.374 | **6.545 / 10.905 / 21.198** |
| shader创建+属性查询+下次draw合计 | 295.267 / 267.402 / 297.830 | 294.989 / 280.445 / 326.486 |
| shader创建+pack+下次draw合计 | 303.715 / 262.493 / 282.520 | 304.272 / 271.822 / 360.090 |

只证明不必要的同步查询等待被去掉，合计没有改善，剩余编译成本仍在正常draw支付。不能用局部查询下降冒充整图加载或low改善。candidate16 原生GPU **111/111**、材质 **102/102**，deferred native测试通过。trusted native 首次漏传必需 `--test-root` 的失败保留，正确传入外部独立目录后 **92/92**，不是修改业务代码掩盖测试错误。

### 原生专项遗漏的旧回归与死接口：范围和修复约定

`editor_native_property16_01` **60通过/14失败**，默认引擎10对照同样14项失败。逐项及提交历史核对后，原因是测试迁移漏项：`test_editor_native_admission_gpu.gd` 从10月13日 `6da4cec7` 后未更新，而 `load_job` 于10月28日 `6b17a555` 已改为消费 published native。新增 native-only 专项没有同步该文件及继承它的 lanes/residency GPU 旧夹具。这是上轮交付缺口，不是“旧引擎也失败所以可以忽略”。

8项来自 source_retry：仍期望改GLB后重新导入新几何、新纹理并二次申请raw预算；6项来自 corrupt_product：在默认信任产品模式下，仍期望自动做全文件checksum并回退GLB。现有生产 `_prepare_model_template` 只接受 ready，已没有raw调度，但 `_native_result_action` 仍残留retry分类、队列仍有仅测试调用的 `retry_as_raw`。本轮移除编辑器该死接口，转换/审计共享Reader继续保留明确的源文件事务能力。

旧测试改为验证原生产品权威性：改变或临时移走GLB仍用同一原生几何/纹理；原生产品缺失且GLB尚在时失败、不得回退；checksum破坏仅在显式诊断审计模式下测试拒绝，生产不新增校验。真实GPU取消及失败保持主线程回收、释放前预算仍收费、引用清空和租约归还；HTTP打开/放置/撤销/保存/重开在GLB被移走期间执行。CPU、lanes和residency夹具同步去掉旧raw重试假设，保留队列压力、取消和寿命覆盖。报告改写入每次独立输出目录，不再覆盖固定20261011历史路径。

编辑器清理在主工作区进行，candidate16整图对照继续使用修改前冻结脚本。两者分开记录，不能把源码变更混入同条件性能样本。另一个零调用的旧 `retry_cached_model` 也移除；转换/导入业务不依赖这两个接口。

### candidate16整图三次：查询改动不能默认启用

`property16_map_series_index.json`、`property16_map_comparison.json` 为完整结果。先保留新路径首次探索 first_on_00，再 off/on/on/off/off/on 各三次。固定地图SHA与各次源文件SHA完全一致，batch始终1、旧async始终0，仅改变targeted属性查询；全贴图、正常HUD/角色、真实跨地图卸载及返回。七次均正常退出、无错误/失败、旧地图与Deferred owner释放、回收队列排空。没有GDB或并行编译/GPU测试；期间有轻量代码阅读/编辑，不是专用静默机器，也不称严格cold或跨进程p95。

首次探索入口36.231s、完整就绪124.893s、卸载最大2361.320ms，完整保留。这是同一新引擎路径的首次游戏运行，与后续重复路径分开，未以“异常值”为由删除。正式六份初次/返回均目录命中，结构工作量一致：**1505实例、1074引用读取、742直接prefab、1870节点访问及释放、2176网格投影、9731922面准备顶点**。

| 同路径重复运行 | targeted off：01 / 02 / 03 | targeted on：01 / 02 / 03 |
|---|---:|---:|
| 入口 s | 15.552 / 16.494 / 15.883 | 15.228 / 16.705 / 16.597 |
| 当前需求完整就绪 s | 67.912 / 71.512 / 71.536 | **69.617 / 76.702 / 77.286** |
| 卸载最大帧 ms | 248.208 / 266.406 / 360.493 | 346.980 / 321.242 / 255.546 |
| 返回传送最大帧 ms | 373.519 / 266.808 / 375.391 | 361.715 / 384.908 / 296.301 |
| 返回加载帧p95 ms | 54.309 / 51.829 / 61.090 | **66.141 / 56.126 / 71.887** |
| 返回加载最大帧 ms | 80.395 / 94.217 / 111.391 | **105.680 / 115.072 / 126.268** |
| 返回加载 >50ms 帧数 | 128 / 107 / 261 | **289 / 191 / 404** |
| 初次稳定1% low FPS | 33.69 / 28.56 / 25.15 | 25.37 / 27.74 / 25.75 |
| 返回稳定1% low FPS | 27.20 / 26.56 / 15.85 | 25.33 / 30.13 / 26.41 |

完整就绪中位数71.512→76.702s，返回加载三份最大帧均更慢。初次稳定阶段六份均无>50ms帧；返回稳定阶段off03有8帧>50ms，其余五份为0，同样保留。该对照没有证明总时间、low或工作量收益，**不批准默认启用targeted查询开关**。仅保留独立复现与默认关闭的研究补丁，不能宣称这项已经优化正式游戏。组件测试也已显示创建+查询+draw总量不降，整图结果进一步说明将同步等待推到renderer/draw不足以解决关键路径。

默认引擎10仍未替换。后续性能工作要重新定位首次游戏路径中的实际编译/导入与绘制提交等待，尤其入口后收尾、卸载及返回；不能再以查询函数耗时下降替代整图结果，也不能由最后一份返回阶段的Deferred累计快照断言初次500ms类别全部消失。GDB只采样时的线程停顿与软件断点异常需继续分开。

### 沿旧回归继续补齐上下游：新统计交接与可选驻留登记

整图七次结束后才将编辑器改动同步到冻结测试工程，差异记录在 `editor_native_cleanup_source/receipt.json`。CPU加载队列97、混合lane91、resident103、模型处理35、native-only24项均通过。候选16下普通GPU/HTTP **91/91**、混合GPU/HTTP **73/73**，但驻留GPU首先出现 **73通过/12失败**：`unexpected_packet_field:native_pipeline_batch`。这是本轮新增统计与所有权交接不匹配的真实回归，不能归为前述旧GLB断言。

修复只允许可选的平坦整数/布尔计数字典，在原字段遍历时投影掉它，不把诊断带入发布身份或owner ticket，不增加资源图扫描。CPU用例验证同样的graph visits与weak owners，并拒绝夹带Resource、嵌套字典/数组等额外所有权。普通/拆分原生产品共用该入口；没有加回文件checksum、源文件读取或第二次网格遍历。

继续运行驻留GPU后得到95通过/10失败。默认10控制 `editor_residency_legacy_contract_default10_control_01` 同样95/10，逐项拆为：

- **真实潜在登记缺口**：原生Reader已写入 `_rmmo_source_digest`，原 `adopt` 仅检查该标记，未进入缓存的有效preflight也可被登记。这只在可选驻留发布链涉及；生产默认仍关闭该驻留开关。首次登记补一个当前缓存的同一owner查询，已有同一allocation的重复登记仍幂等，未做文件I/O或全表扫描。CPU补“Reader已盖身份但未发布”复现。
- **旧回收断言**：GPU夹具仍要求缓存替换/移除即刻销毁，生产早已由ResourceRetirement分帧释放。更新为等待真实回收服务排空，再检查PackedScene弱引用与独立持有纹理的存活；手动计费检查期间关闭夹具tracker的自动collect，避免测试自身抢先扣账。实际释放前保持原预算收费，不强制同步清空生产队列。
- **测试污染原生图**：direct-case的Audit为观察销毁加入了脚本化Lifetime元数据，严格所有权图正确拒绝该额外owner。发布用例改成只记录WeakRef，实际取消/回收测试仍保留原带析构观测的独立fixture；没有放宽生产图的准入规则。

补充拆分测试的第一次调用因未指定隔离content_root退出2，记录保留；改用仅在外部测试工程中的wrapper设置独立review_artifacts根，原测试安全条件不变。`editor_native_counter_fix_source/`、`editor_native_publication_fix_source/` 分别保留两轮源码差异。全部旧失败、新统计失败、95/10控制和参数失败独立保留，最终验收以下方最终索引为准，不能把中间通过项冒充整套通过。

最终索引 `editor_native_cleanup_final_validation.json`：

| 验证 | 候选16 | 默认10 |
|---|---:|---:|
| 普通原生GPU + HTTP，无GLB打开/编辑/保存重开 | 91/91 | 91/91 |
| 模型/纹理混合队列GPU + HTTP | 73/73 | 73/73 |
| 驻留资源发布、回收、取消GPU + HTTP | **112/112** | **112/112** |
| 所有权CPU，含Reader已盖章但未入缓存 | **132/132** | 本轮未重复 |
| 拆分纹理所有权CPU | **70/70** | 本轮未重复 |
| 拆分纹理真实GPU、像素与回收 | **165/165** | 本轮未重复 |

候选普通/混合GPU来自此前成功索引，最后的改动针对可选所有权发布，驻留与拆分用例已在最终源码重跑；默认三份均在最终源码运行。所有最终进程正常退出，无引擎/脚本错误；165项用例的源图/候选实际渲染检查通过，最后native streaming计费与已发布几何计费均归零。未恢复GLB回退、生产checksum或即时强制清空资源队列；地图、模型、纹理资源未修改，默认引擎仍10。

本轮可交付结论是编辑器旧合同及死接口清理、新统计交接修复、实际缓存发布证明补齐，以及有明确收益边界的原生批量候选。整图属性查询试验有回退，保持默认关闭；完整贴图加载与卸载/返回长帧仍未解决，不能将编辑器回归通过等同于性能目标完成。

### 再次核对主线程：传送点全量重扫与卸载析构

重新查询街区会话，最新一轮已完成且空闲；继续使用原冻结地图，不修改正式内容。上一轮 `706ea12f` 已推送。`unload_commit_three_sample_review.json` 核对 candidate16 targeted-off 三份正常样本的地图、源码、引擎和控制项相同，旧地图销毁分别111.160 / 116.802 / 187.549ms，不能仅凭该调用的墙钟判断是CPU析构还是渲染等待。

默认引擎10的新官方记录 `unload_current_official10_01_receiver/` 共6923帧、6185个签名、零引擎错误，正常完成完整往返；使用调用者归因模式。这是插桩诊断，不作为正常加载或low成绩。它确认：

- 初次/返回加载期间 `_poll_warp` 分别341 / 344次重建候选，产生563157 / 563001次 `Object.get_meta`。主线程脚本累计包含时间1047.928 / 1069.543ms。原因是任意碰撞体增删都触发世界的 `child_order_changed`，使传送点缓存失效并重新枚举全部子节点；稳定阶段没有这些重复扫描。
- 卸载提交中仍有天气PCM首次生成154.502ms、合批clear 51.886ms及旧地图销毁145.453ms。它们是同一插桩运行中的调用墙钟，不与其嵌套值相加，也不替代正常样本。天气和资源退役尚未修复。

`unload_current_gdb10_01` 使用固定的已提交exporter副本、默认引擎匹配符号、GDB18.1及纯采样，没有软件断点。91份栈中，按诊断Unix/tick锚点与提交顺序对齐：sample15位于prepare_disposal，释放缓存中的 `GroundCpuMesh → ShaderMaterial`（可见 `ground_cpu_cache`、`rock_albedo`）；sample17位于outgoing_map的节点退出信号；sample21位于outgoing_map的 `DeferredAssets → WorldDocument` 成员容器析构。`commit_attribution.json`保存阶段边界及对齐。不能把三个采样推成整段耗时占比，也不能断言所有释放尖峰都是同一原因。

这次GDB诊断最终exit1：旧地图owner已释放，但既有夹具在12秒墙钟等待后仍有92个回收ticket，触发“返回前回收排空”失败。All-stop暂停期间墙钟继续流逝而可用游戏帧减少，因此该次只提供栈证据；保留失败与92个ticket事实，不算功能/性能通过，不把等待时间改大后冒称回收已修好。

### 传送点增量候选：独立复现后保留同代码整图对照

修改 `World3D` 的候选维护：初次绑定只扫描一次；随后只记录新增子节点，在实际查询前读取它们的kind，允许生产者在add_child后补齐元数据。退出/重挂立即移除候选；实际有多个传送点时保留场景顺序；中心、目标和出生点仍每次读取当前值。内部子节点保持原来的排除规则，普通碰撞体增删不再触发全世界元数据扫描。查询与接近预加载共用刷新入口。没有降低采样频率、延后释放/发布、改变传送判定或扩大预算。

`probe_warp_candidate_churn.gd` 调用真实 `_poll_warp`：2049常驻子节点，256次额外增删、512次查询。前后各三个独立进程，每进程三次重复，默认4.8、串行、无其他引擎/GDB/编译器。进程内中位数从 **223.772 / 200.434 / 231.784ms** 降为 **1.820 / 2.002 / 1.811ms**；所有单次值留在 `warp_candidate_component_comparison.json`。新路径每份总检查2305个节点（2049初始+256新增），不重新检查未变化的常驻节点。此处不声称整图加载缩短相同时间或low已改善。

`test_world_warp_candidates` 旧实现16项中2项失败（移除/重挂后候选未立即注销），修复后 **16/16**。覆盖初始内容、重叠顺序、移除、重返、内部子节点、晚补元数据、实时目标/位置、失败重试和锁定玩家。接近预加载旧fixture原先直接覆盖私有数组，改为真实节点进出，`warp_prefetch_retry_after_01` **35/35**：取消、预算拒绝、再次接近保持去重与完整资源归还。

`warp_candidate_source/receipt.json` 保存冻结工程修改前后字节身份。整图对照使用默认引擎10、同源码同地图、完整HUD/角色/贴图、旧全量候选与新增量候选按off/on/on/off/off/on各三次；索引为 `warp_catalog_map_series_index.json`，汇总为 `warp_catalog_map_comparison.json`，重建命令为外部证据目录中的 `python summarize_warp_catalog.py`。候选引擎11–16仍未安装，属性查询试验开关继续关闭。

六份均exit0，无引擎错误、脚本错误或功能失败，旧地图及Deferred owner释放，返回前pending/known均0。冻结脚本、地图及引擎身份相同，初次/返回目录均命中。结构工作量均为1505实例、1074引用读取、742直接prefab、1870节点访问及释放、2176网格投影、9731922面准备顶点。每份使用新进程和独立用户缓存，OS/driver缓存保留；没有并行引擎、GDB或编译。期间有轻量阅读/编辑，不称严格cold、静默独占机器或加载p95。

| 同路径重复运行 | 全量候选 off：01 / 02 / 03 | 增量候选 on：01 / 02 / 03 |
|---|---:|---:|
| 候选节点检查次数（初次及返回累计） | 1010831 / 1017480 / 1014917 | **4302 / 4302 / 4302** |
| 入口 s | 14.547 / 14.414 / 14.506 | 14.341 / 14.627 / 14.371 |
| 当前需求完整就绪 s | 71.195 / 73.618 / 73.901 | 73.492 / 70.286 / 73.138 |
| 卸载最大帧 ms | 231.049 / 265.811 / 476.514 | 273.374 / 348.181 / 369.878 |
| 返回传送最大帧 ms | 369.553 / 294.904 / 404.441 | 307.396 / 318.664 / 390.438 |
| 返回加载帧p95 ms | 57.202 / 53.877 / 58.388 | 56.183 / 54.322 / 57.702 |
| 返回加载最大帧 ms | 85.395 / 89.800 / 89.647 | 99.593 / 96.197 / 94.696 |
| 返回加载 >50ms 帧数 | 210 / 137 / 201 | 177 / 153 / 207 |
| 初次稳定1% low FPS | 27.51 / 23.20 / 29.68 | 24.60 / 30.44 / 25.95 |
| 返回稳定1% low FPS | 26.49 / 27.72 / 25.50 | 28.82 / 24.39 / 25.75 |

候选检查下降约99.6%，这是可重复的工作量收益，保留。完整就绪中位数73.618→73.138s，low与大帧有交错，不能据此宣称总加载或low已稳定改善；返回加载最大帧三份on反而高于三份off。两组初次/返回稳定阶段均0帧>50ms，但加载与卸载尖峰仍存在。此处完整就绪使用本篇固定全贴图当前需求口径，不能与早期白模10秒目标或不同地图版本直接比较。下一项仍针对官方profiler/GDB已定位的卸载资源析构，先记录实际缓存结构，再独立复现。

### 卸载缓存持有链：实际结构、独立复现与分片修复

传送点改动已提交推送 `99def882`。六轮结束后才运行 `disposal_owner_inventory10_01`：默认10、同地图、完整往返、exit0、无功能失败。它是额外插桩诊断，不能作为正常时间成绩。同步快照仅保留类型/数量/少量描述文本，临时Resource引用在transfer前的函数返回时全部退出，未跨await持有旧缓存；首次快照自身24.608ms也单独记录。原始结构在 `disposal_owner_inventory.json`。

卸载时Deferred jobs为0，但其WorldDocument仍持有：`load_box_meshes` **303项**、材质池36项、paint判定缓存333项。网格缓存的键是含完整道路记录的Array，前两个样本转成文本分别52166/77613字符；这是结构提示，不是内存计量。terrain_neighbors、表面准备缓存、undo/redo等均已空，不对空字段再增加回收流程。GroundRenderBatches有218个group、2610个弱描述、115个建筑数据缓存；本轮只接管GDB链中group.data.mesh的强持有。其clear遍历的临时groups.values()过去在函数返回时集中释放这些网格。通用批次成员、地图实例与碰撞体仍按原顺序立即注销和销毁。

`test_map_cache_retirement` 复现303个道路记录键（每个128组三角形嵌套数组）、642个文档owner及218个group owner。旧实现三个独立进程均有相同3项失败：文档销毁同步释放缓存，合批prepare同步释放缓存，销毁前未留下分片owner。文档同步销毁 **25.479 / 32.687 / 27.286ms**。新实现只在明确的永久换图prepare入口，把缓存的键和值、每个group的引用转给现有主线程私有数组队列；既不复制递归内容，也不清空外部借用的子容器，不将Resource送到CPU释放线程。

最终实现避免在普通_exit_tree启动该快照：临时移出/交接可能比回收ticket活得更久，会使提早排空的ticket失去保护意义。`map_cache_retirement_source/` 保留第一版及其15项通过证据，`map_cache_retirement_explicit_source/` 为改到明确永久处置入口的最终源码。最终三份 `cache_retirement_explicit_after_01..03` 各 **18/18**，包括临时交接、重复prepare、退出回调仍能读完整缓存、外部借用不变、每个owner主线程释放恰一次及队列排空。

| 文档组件，三个独立进程 | 01 | 02 | 03 |
|---|---:|---:|---:|
| 最终准备+销毁同步段 ms | 0.466 | 1.113 | 0.511 |
| 后续回收最大单片 ms | 3.093 | 3.531 | 2.337 |
| 后续回收累计执行 ms | 37.998 | 48.855 | 36.400 |

这里只证明集中析构拆帧，累计CPU没有下降；不能把后续执行成本漏算，也不声称解决所有地图Node退出成本。六份组件原始结果在 `map_cache_retirement_component_comparison.json`。相关回归：记录回收9/9、索引回收32/32、合批永久卸载/普通成员移除/临时重挂6/6均通过。原合批实现还有另一会话修改，本轮没有编辑它，通过已有永久卸载入口保留group引用。

正常整图三份均已完成，索引 `cache_retirement_map_series_index.json`，汇总 `cache_retirement_map_comparison.json`。使用增量传送点实现，与前面的三份warp_catalog_map_on对比；逐项核对仅本轮两个生产文件和报告字段变动，地图/引擎/设置及结构工作量相同。三份exit0，无引擎/脚本错误或功能失败，旧地图及Deferred owner释放，返回前pending/known均0。这是按时间先后做的累计对比，不是随机ABBA。

| 正常整图，三份样本 | 修改前 01 / 02 / 03 | 修改后 01 / 02 / 03 |
|---|---:|---:|
| 当前需求完整就绪 s | 73.492 / 70.286 / 73.138 | **93.508 / 88.381 / 93.325** |
| 卸载提交 ms | 259.272 / 321.358 / 349.060 | 213.306 / 301.585 / 262.134 |
| prepare_disposal ms | 36.468 / 44.532 / 66.182 | 37.288 / 32.627 / 34.265 |
| outgoing_map ms | 136.020 / 165.127 / 170.988 | 95.922 / 152.934 / 124.452 |
| 卸载最大帧 ms | 273.374 / 348.181 / 369.878 | 232.982 / 323.150 / 285.549 |
| 回收服务最大单片 ms，返回前累计 | 32.378 / 24.042 / 31.390 | 36.909 / 4.167 / 3.992 |
| 卸载后稳定阶段最大帧 ms | 42.553 / 29.861 / 40.134 | 44.500 / 24.482 / 20.152 |
| 返回传送最大帧 ms | 307.396 / 318.664 / 390.438 | 317.967 / **689.204** / 374.160 |
| 返回加载 >50ms 帧数 | 177 / 153 / 207 | **370 / 560 / 351** |
| 初次稳定1% low FPS | 24.60 / 30.44 / 25.95 | 26.27 / **19.35** / 23.70 |
| 返回稳定1% low FPS | 28.82 / 24.39 / 25.75 | **17.88 / 17.33** / 22.74 |

卸载提交中位数321.358→262.134ms，旧地图销毁165.127→124.452ms；后续卸载稳定阶段两组均0帧>50ms。只增加2个回收ticket（198→200），多出约1560个原本同步释放的引用，模型/几何工作量没有增加。组件证明集中析构被拆开，整图卸载数据方向相符，保留该生命周期修复；总加载和low没有改善，第二份689.204ms返回帧、稳定阶段超过50ms的帧、首份36.909ms回收单片全部保留，不能用后两份约4ms遮掉首份。

为检查加载变慢，三份结束后又用**相同最终源码**关闭sliced_cache_disposal，得到 `cache_retirement_map_off_control_01`：exit0、工作量相同、old owners释放、回收排空；完整就绪 **106.246s**、卸载提交365.276ms（prepare74.706 / outgoing_map159.492ms）、卸载最大390.115ms、返回最大648.162ms。`cache_retirement_disabled_control.json`保存核对。它是一次针对时间漂移的关闭对照，不冒充三份控制成绩；只证明慢现象也出现在关闭路径，尚未定位根因。新增回收分支在第一次完整就绪以后才运行，但仍不能仅靠这一点给整轮性能验收通过。

前后资源bundle key及入口原生payload SHA一致；其余主要结构计数也一致。原宿主记录只排除了其他Godot/GDB/编译进程，没有记录完整历史频率、GPU占用或所有外部应用负载，不能据此断言宿主安静。全部游戏退出后的只读快照（`post_cache_series_host_snapshot.json`、`post_cache_series_gpu_snapshot.json`）显示可用RAM约19.3GB、独占显存约2.39GB、3D引擎当时约1%占用；这是事后状态，不能回填到先前慢帧，更不能以“OS/GPU空闲”关闭问题。

下一步先在慢现象发生期间补齐进程CPU、CPU频率/性能比例、GPU引擎及显存采样，并与游戏阶段时间对齐，解释加载/low漂移；同时对修复后的旧地图销毁重新抓栈，区分节点退出与尚未接管的资源owner。永久销毁时合批clear逐成员检查/断连后紧接着Node析构也值得独立验证是否重复，但尚未改为直接删除批服务，不能当作已修复。碰撞体39–52ms与天气首次PCM生成30–57ms仍待处理。本轮没有修改默认引擎、资源包或正式地图，没有把整体性能目标标为完成。

### 测量宿主发现的重复工作：筛选前读取所有进程命令行

`027bb9a8`已推送，下一轮重新确认街区会话仍已完成、没有在跑的Godot/GDB/编译器。检查宿主观察器发现：外部run.py每轮先调用`psutil.process_iter(['pid','name','cmdline','create_time'])`，读取所有应用的远程进程信息后才筛Godot/Blender/GDB/编译器；循环等待只有0.5秒。它记录竞争进程的目的合理，但读取所有无关应用命令行是额外工作，会与正在测量的游戏争用CPU。库内`profile_godot_thread.py`启动发现阶段也有同类问题。

无游戏运行时先做ABBA探针，再独立启动三个Python进程复现。每次约250个系统进程，选中测试工作进程为0。`host_observer_component_three.json`记录全部数据：三个进程的第一次旧扫描分别4.903 / 5.166 / 4.861秒，第二次旧扫描2.294 / 2.170 / 2.124秒；旧扫描消耗1.656–3.813 CPU秒。六次先筛名称的扫描7.146–48.291ms，不能抹掉其中48.291ms的慢值，也不能把这个微测直接换算为整图加载收益。

新增`godot_process_monitor.py`先用pid/name筛选，再对真正相关的进程读取cmdline/create_time。权限不足时仍报告匹配引擎，参数字段保留None；进程退出不使整次观察失败。`profile_godot_thread.py`复用筛选入口。四项测试通过，覆盖不查询无关应用、参数不可读仍保留竞争进程、发现中进程退出及仅找Godot的调用者。

外部run.py保留旧eager路径作为显式对照，默认filtered；每轮同时记录扫描墙钟和观察线程自身CPU时间。旧runner原文保存为`run_before_host_filter.py`。整图按eager/filtered/filtered/eager/eager/filtered各三份完成，索引`host_observer_map_series_index.json`，核对汇总`host_observer_map_comparison.json`。游戏源码、地图、默认引擎10、HUD/贴图、增量传送点和缓存回收均相同，只切换观测方式。六份均exit0、无错误/失败/其他引擎或编译进程，源文件及runner/helper SHA前后相同；旧owner释放、回收排空，结构工作量一致，warp访问均4302。

| 六份正常游戏 | eager 01 / 02 / 03 | filtered 01 / 02 / 03 |
|---|---:|---:|
| 观察线程累计CPU秒 | 72.422 / 69.156 / 69.781 | 5.688 / 2.953 / 3.219 |
| 当前需求完整就绪秒 | 92.725 / 93.652 / 96.059 | **106.628** / 84.460 / 80.144 |
| 卸载最大帧ms | 329.482 / 328.871 / 404.820 | 387.840 / 280.082 / 277.548 |
| 返回加载最大帧ms | 107.270 / 100.898 / 118.482 | 90.929 / **121.090** / 98.049 |
| 返回加载>50ms帧 | 496 / 521 / 495 | 369 / 357 / 306 |
| 初次稳定1% low FPS | 24.82 / 17.22 / 25.33 | 17.11 / 24.47 / 25.76 |
| 返回稳定1% low FPS | 20.20 / 20.40 / 20.55 | 18.72 / 18.55 / 22.85 |

观察线程CPU中位数69.781→3.219秒，减少约95.4%；完整就绪中位数93.652→84.460秒，但filtered首份106.628秒、返回121.090ms峰值及low波动全部保留。这证明宿主确有可去除工作，不能说明100秒的主因已经定位，更不能称稳定加载或low验收通过。保持原系统/驱动缓存，不是严格cold，也不是加载p95。

用户随后要求以全局时序分析100秒，并明确采用**引擎补丁暴露GD控制接口**：采集阶段内存记录、结束后统一落盘、写路径无日志锁。下一步实现每线程独立事件缓冲及任务标识，联合记录游戏发布、worker执行、渲染同步和管线等待；新补丁先作为独立诊断候选。现有脚本`LoadTrace`有共享Mutex，因此不能将它冒称无锁实现。当前尚未交付此引擎接口。

### 先完成观测基础：原生内存时间线 candidate17r3

按用户最新要求，暂缓100秒加载策略改动，先完成通用调试能力。`Performance.debug_trace_*`与`scripts/util/debug_timeline.gd`支持启动/停止、标签、任务命名、begin/end/mark及停止后导出。事件分片在线程间不共享写位置，普通记录无日志Mutex/自旋锁，不持有Resource/Node/RID；启动时预分配并预触碰，容量满后报告丢失、不覆盖已有事件。首次线程登记及首次名称表项仍会分配，不能把它们冒称完全不涉及分配器内部同步。

原生记录贯通主循环、WorkerThreadPool入队/执行/等待、ResourceLoader、材质设置、渲染同步、管线等待和Vulkan CPU调用。线程池身份、普通任务/任务组、任务ID和已有description关联上下游；组任务多worker执行保留为多个片段，不误算成重复。统一单调时钟下输出每次开始/结束、排队延迟和等待对象，并保留停止边界未闭合事件。`summarize_debug_timeline.py`输出完整CSV、耗时/调用量排行、任务名称排行、Chrome/Perfetto入队→执行连线及离线可缩放HTML。

最终构建和证据位于`engine_debug_trace_candidate17r3/`。三次独立CPU合同均**88/88**：每次12线程共147456条标量记录零丢失，暂停一个任务不影响其他写线程，停止不等该任务结束；并发停止/重启、旧token、名称复用、容量溢出均通过。每次名称测试1536任务共4608记录，3线程只保留6个名称条目；满后元数据不继续增长。离线解码器10/10；真实Vulkan保留**229条、13线程、0丢失**，采集前后渲染像素一致；实际浏览器查看器通过筛选、缩放、聚焦与线程切换。

GPU组件已能直接看到主线程`render.draw → pipeline.wait → worker.wait(PipelineCompilation)`与对应worker同时发生：该次worker编译2.440秒，主线程最长对应等待2.353秒。这里证明工具能区分“执行”和“等其他线程”，不是用小立方体测试解释整城100秒，更不是GPU硬件执行时间。另有2个跨停止边界的span保持未闭合。

用户指出图上仍主要是wait、需要查原始数据。已逐条联结：主线程18144等待249号`PipelineCompilation`；该任务入队6522150us，worker24652于6522186us开始，排队仅36us；8961884us执行结束，主线程8961887us结束对应等待。worker范围2439698us，记录到线程CPU2093750us；该组件样本的大头是后台编译执行，不能由此确定编译内部哪一步昂贵。新增`dependencies.json`和查看器“查看等待方和执行方”，点击pipeline.wait会沿子范围显示任务名称/ID、排队时长、执行线程和CPU，再将两条线程放到一起。`viewer_browser03`以原始capture验证确实关联18144与24652；解码器新增任务组依赖回归，总计**11/11**。这是观测呈现补齐，尚未改变加载流程。

三个进程各做21轮等工作量压力测试：每轮96000单元，启用时288000事件，校验和一致、零丢失。1/2/12线程下，开启标量采集比关闭接口调用增加约44–85ms；**关闭状态的GD接口调用本身也有约88–156ms成本**，不能遗漏。应只在任务/批次边界插桩，不逐顶点记录；可选线程CPU计数更重且分辨率粗，普通采集默认关闭。本轮没有宣称线性扩展或整图加载/low收益，完整原始数值和异常边界见专项文档。

已安装独立入口`D:/tools/godot/debug-trace-4.8/godot.windows.editor.x86_64.exe`及匹配符号，SHA`9f88c2f6a09fa1e164e9f25b1b8fabea89419d45f47a56e77b6b557a9b83ece6`。补丁清单`tools/engine_patches/godot-4.8-beta1-debug-trace-candidate17.json`记录依赖candidate16r2和完整source SHA。普通默认candidate10及其清单、符号未改。诊断构建继承前面候选源代码，既有可选优化继续关闭，因此诊断成绩与普通引擎验收必须分开。

完整用法、成本与复跑命令见[原生内存时序采集](debug_timeline.md)，历史查看器/编码失败保留在上述外部证据目录。本轮完成的是debug基础能力；100秒根因仍未关闭。下一步在冻结地图副本接入业务阶段和稳定任务ID，连续三次采集需求→准备→完成→发布→回收的完整链路，按排队/执行/等待及重复次数倒序选取独立复现对象，再改生产流程。未观测空白不能归为OS/GPU空闲，GPU调用范围也不能冒称GPU硬件计时。

用户随后明确**不需要查看器，只需agent能从CSV判断问题**，已据此删除未提交的HTML实现，移除浏览器/Chrome导出及交付依赖，不再投入界面工作。最终仅交付原生capture、GD控制、CSV/JSON离线分析；上面的浏览器步骤仅是已发生的组件历史，其外部证据保留。新增`dependencies.csv`将等待任务名、排队延迟、执行线程及CPU直接放在同一行，任务组保留多行并明确禁止重复累计等待时间。最终CSV对任务249的36us排队、2352944us等待、线程24652的2439698us执行/2093750us CPU逐项核对通过；11项解码测试改为CSV合同，结果仍11/11。用户已同意在此基础上继续真实地图定位和优化。

### 全局三次捕获与保留着色器缓存的三次重启

用户要求直接分析工作耗时，不另开采集开关扰动对照。使用冻结地图 SHA `ee80500d6156c79d68a04315931c024319d92fb351567e5ced38d0ddb7c22697`，candidate17r3 诊断引擎，在外部项目的 30 个业务方法补充任务边界；原生事件贯通 worker、渲染和等待。完整贴图、HUD、角色、真实 Vulkan，沿用加载→稳定→卸载→12秒空场回收→返回路径。只改外部副本，完成后按 SHA 恢复，未改正式地图、资源包或默认引擎。

证据根目录仍为 `D:/code/rmmo_runtime/review_artifacts/axel_post_roads_perf_20261030_01/`。`native_global_trace17_01..03` 每次新建空用户目录；`native_cached_trace17_01..03` 从对应前次样本**只复制 shader_cache 和 vulkan 缓存**到新的用户目录，没有复制地图、几何和纹理派生缓存。OS/驱动缓存没有清空，因此第一组不是严格冷机样本。`cache_seed.json` 记录逐文件 SHA，`shader_cache_restart_comparison.json` 汇总六次结果；各样本的 `csv/` 和 `phase_analysis/` 保留原始任务与阶段归因。以上均为诊断成绩，不替代普通引擎验收或 p95。

| 同样的当前需求完整就绪边界 | 空用户目录 01 / 02 / 03 | 保留 GPU 缓存重启 01 / 02 / 03 |
|---|---:|---:|
| 入口 s | 61.841 / 16.944 / 17.698 | 10.784 / 10.636 / 9.594 |
| 完整就绪 s | **145.757** / 84.733 / 96.963 | **90.896** / 65.170 / 60.260 |
| ShaderCompilation 累计线程 CPU s | 152.578 / 112.141 / 112.109 | **0 / 0 / 0** |
| LoadVariantFromCache 累计线程 CPU s | 0 / 0 / 0 | 6.125 / 4.453 / 4.984 |
| PipelineCompilation 累计线程 CPU s | **299.531** / 0.563 / 0.906 | 0.391 / 0.234 / 0.219 |

采集从地图加载前开始，表中的编译计数只覆盖采集窗口。空用户目录三份各有112个 ShaderCompilation 任务组、1344个 worker 执行片段；保留缓存三份全部改为 LoadVariantFromCache。1344是线程池执行片段数，不能称作1344个不同着色器。六份 PipelineCompilation 都是529个任务，但实际CPU成本相差数百倍；创建新进程的管线对象不等于再次执行昂贵代码生成。并行 CPU/墙钟累加不能当成加载经过时间，也不能把缓存表里的下降直接扣到总加载中。

三份重启的181个 shader_cache 文件合计33,964,612字节，Vulkan管线缓存1个18,272,460字节；退出后均无新增、缺失或内容变化。源码确认 `ShaderRD::_compile_version_start` 先 `_load_from_cache`，命中则跳过 `_compile_variant`，已加载缓存不会重新保存；原生缓存加载仍需创建当前进程的 shader/RID。缓存键包括引擎版本/hash、基础源码、宏、阶段代码及 API；源码段名称排序后散列。Vulkan缓存验证设备、驱动版本、UUID和ABI后复用，不能在环境改变后承诺永不编译。项目代码未发现主动删除这两个引擎缓存的路径。官方机制说明见 [Godot 管线编译文档](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html)。目前没有证据要求新增另一套持久缓存或移除这些兼容性检查。

六份采集零丢失、零孤立结束、零交叉范围、零任务名称冲突。保留缓存首份仍有功能失败：12秒回收窗口结束剩37个ticket，`old resource retirement drains before return`失败；保留退出码1及完整数据，后两份退出码0且回收排空。首份旧地图/Deferred owner已释放，但这不等于所有延迟回收已完成。没有延长12秒或改断言来隐藏失败。此前空用户目录三份均正常完成。

重启后收尾的大头依然是渲染：入口→完整就绪期间，`render.draw`扣除已有子范围后的累计墙钟分别 **43.292 / 28.667 / 26.439秒**，调用 **2152 / 1866 / 1822次**；不是单帧43秒，也不是GPU硬件计时。主循环未细分成本17.761 / 11.230 / 10.183秒；`_publish_ready`自身3.589 / 2.875 / 2.767秒，不能继续只盯几秒发布而忽略渲染大头。可见网格节点4442不等于实际draw call数，不能据此推断资源过重。

用户已明确下一步**重点查渲染**。回收每帧只推进一个队首的疑点和独立用例草稿暂存外部，不修改生产回收策略。下一轮细分场景脏更新、资源/材质更新、视口、剔除、阴影、绘制列表、实例数据、提交等原生调用，按三次CSV的耗时与工作量排序定位；不把剩余空白归为OS/GPU空闲，不降低画质或改地图来掩盖问题。

### 渲染细分三份：绘制列表与帧末处理反复居前

独立candidate18在17r3上增加40个固定阶段标签，没有修改渲染行为、质量或预算。原有时间线CPU合同88/88，固定工作量与真实Vulkan像素一致性通过；GPU854事件、13线程、零丢失，3个停止边界范围未闭合。补丁可应用于17r3的9份源码，规范化内容与实际构建逐项相同，源码/默认入口SHA未变；构建385.921秒，普通默认10与已安装诊断17都未替换。

`native_render_trace18_01..03`完成同样往返流程，均exit0、无功能/引擎错误、回收排空，分别3,047,073 / 3,097,100 / 3,134,074事件，零丢失/孤立结束/交叉范围/任务名称冲突。使用相应17重启样本的shader/pipeline缓存，冻结源码、地图和资源bundle key相同。最终网格节点快照4442 / 4445 / 4442、合批节点216 / 219 / 216，保留这个差异；合批源3580和其中缩放源132一致，不能把最终节点快照当作总渲染工作量恒定。初次分析误把含mount_us的bundle对象及最终网格节点要求完全相同，断言失败；改为核对身份并保留节点差异，没有丢弃或重跑样本。汇总`render_trace18_three_samples.json`。

| 诊断范围，扣除已记录直接子范围后的累计墙钟秒 | 01 | 02 | 03 |
|---|---:|---:|---:|
| 地图当前需求完整就绪 | 90.527 | 93.000 | 102.498 |
| 入口后收尾：render.draw_list | **17.071** | **17.881** | **20.398** |
| 入口后收尾：render.end_frame | **12.464** | **13.427** | **14.885** |
| 返回加载：render.draw_list | 18.262 | 24.547 | 24.606 |
| 返回加载：render.end_frame | 12.587 | 16.484 | 16.594 |
| 返回稳定15秒：render.draw_list | 4.306 | 4.329 | 4.315 |
| 返回稳定15秒：render.end_frame | 3.185 | 3.153 | 3.181 |

这些不是单帧耗时，也不是GPU硬件计时；`end_frame`包含RD的结束记录、提交以及下一帧准备。`vulkan.submit_present`等已有子范围已扣除，因此不能将它全部解释成等GPU。第一份收尾的候选列表元素分布：阴影5,719,473、颜色2,611,801、深度/法线/粗糙度2,278,676；对应列表调用11602 / 4226 / 2113。元素可能被过滤或通过repeat合并，尚不能称作实际draw数量。可见节点中的合批源已经替换成无RS base的CPU描述，不能把其节点可见性误判成重复画原网格。

`render18_return_gdb_01`使用匹配符号和冻结exporter，GDB18.1取得41份主线程样本，正常退出并恢复外部源码；仅用于栈归因，不与正常low/加载成绩混用。5份在绘制列表，见顶点上传依赖检查、uniform更新、PipelineKey哈希、Thread::get_caller_id与draw_list_draw的MinGW模拟TLS；7份在swap_buffers链，见draw graph命令回放、Vulkan命令调用及present的驱动路径。present样本中也有外部graphics hook；它属于已单独记录的submit/present子范围，不能凭单栈把前述帧末独占时间归给它。栈数量不足以分摊内部函数占比，更不证明互锁。完整分类见`stack_render_analysis.json`。

先独立验证一个明确重复操作：`RenderingDevice::draw_list_draw`每次都访问thread_local描述符向量、clear和resize，而绑定数量已受MAX_UNIFORM_SETS=16限制，记录器同步复制ID。`test_draw_descriptor_scratch.gd`在真实local RD完成复用、材质切换、稀疏set 0/2/3、管线切换及每像素验证。修改前三个进程各49/49，每个模式每轮4096次draw，剔除首轮预热后中位数：reuse编码818 / 844 / 986us，material1587 / 1582 / 1646us，sparse2356 / 2409 / 2360us，pipeline1366 / 1355 / 1381us。计时包含GD分发，submit/sync另列，不冒称纯C++耗时或整图收益。

### 描述符临时数组：六进程交错组件对照

candidate19r2只将上述scratch替换为16项栈数组，两个命令记录入口使用只读VectorView，记录器仍同步复制ID；没有改变绑定顺序、验证、资源生命周期和绘制工作量。首次candidate19误向只读VectorView赋值，编译失败，保留失败日志；r2修正后359.125秒构建完成，源码/默认入口SHA核对一致。候选SHA `b3e939a9932560c1f0fcc848e305cca476f3c3863c2d7cf168abb3818e5c8c76`，未安装。

测试补充四条同时可见的像素带，分别使用不同稀疏绑定和管线，确保命令队列保留每次绑定历史，不能仅凭最后一次覆盖全屏通过。最终同一53项测试按 **A B B A A B** 各跑三个新进程；A为18，B为19r2，六次均53/53、无引擎错误、24行绘制/绑定工作量和像素SHA逐项一致。历史49项结果不混入这组对照。原始数据 `descriptor_abba19_01_A..06_B/`，汇总 `descriptor_abba19_summary.json`。

| 每4096次draw的编码中位数，us；各进程先剔除预热轮 | A三次 | B三次 | 三次中位数变化 |
|---|---:|---:|---:|
| 复用绑定 | 828 / 902 / 827 | 749 / 708 / **1044** | 828→749，−9.5% |
| 材质切换 | 1594 / 1673 / 1662 | 1455 / 1428 / 1518 | 1662→1455，−12.5% |
| 稀疏绑定 | 2359 / 2401 / 2443 | 2218 / 2168 / 2194 | 2401→2194，−8.6% |
| 管线切换 | 1432 / 1396 / **2408** | **1729** / 1160 / 1192 | 1432→1192，−16.8% |

保留所有波动；submit和sync另列在原始数据中，没有声称它们每次均改善。这是明确移除每draw的TLS访问及向量重置所带来的局部收益，不等于整图draw_list下降同样百分比，更没有证明解决17–20秒绘制列表或12–15秒帧末开销。补丁已在保存的18父源码上应用，并与实际19r2构建源码逐项核对；整图累计验证待完成。

### 帧结束三份细分：主要是驱动命令回放，不是依赖排序

candidate20继承19r2，追加22个原生标签，细分RD帧结束/开始、命令图依赖整理、排序、屏障、回放、提交和释放。每个绘制列表结束仅汇总draw、uniform绑定、顶点绑定、pipeline绑定的指令数量，不逐draw写日志。独立真实GPU用例53/53，捕获的 **98,308条draw指令** 与用例工作量严格一致，四种排队绑定历史像素通过，零丢失/孤立结束/交叉范围。补丁在保存的19r2源码上应用并核对与构建相同；编译保留了局部诊断Scope变量遮蔽警告，无构建错误。候选SHA `45d58ac6f7265498f6e258df459a53fc7349d63a2b8783284e81c2d057941de0`，默认10和已安装诊断17仍未替换。

`native_frame_trace20_01..03`各自完成完整纹理/HUD的冻结地图往返，均exit0、无脚本/引擎/功能错误、无其他引擎或编译器竞争、旧owner释放且回收排空。捕获5,050,586 / 4,762,950 / 4,544,361事件，零丢失、孤立结束、交叉范围、任务名称冲突；外部项目源码SHA未变且已恢复。最终合批节点219 / 216 / 216，差异保留。汇总 `frame_trace20_three_samples.json`，每份 `phase_analysis/` 含逐阶段独占时间；这里是诊断样本，不是普通引擎ABBA或p95。

| 累计独占墙钟秒，非单帧、非GPU硬件计时 | 01 | 02 | 03 |
|---|---:|---:|---:|
| 当前需求完整就绪 | 79.769 | 74.374 | 67.066 |
| 入口后：3D绘制列表构建 | 13.415 | 13.173 | 11.472 |
| 入口后：驱动绘制命令回放 | **9.446** | **9.529** | **8.126** |
| 入口后：命令依赖整理 | 0.053 | 0.050 | 0.045 |
| 入口后：命令排序 | 0.011 | 0.010 | 0.010 |
| 入口后：待释放资源处理 | 0.129 | 0.123 | 0.113 |
| 返回加载：驱动绘制命令回放 | 11.040 | 12.046 | 10.837 |
| 返回稳定15秒：3D绘制列表构建 | 4.110 | 4.099 | 4.016 |
| 返回稳定15秒：驱动绘制命令回放 | 2.831 | 2.872 | 2.811 |

三个阶段一致把工作指向 `_run_draw_list_command` 内的驱动调用，而不是继续优化约十毫秒累计的排序或把帧结束空白统称GPU等待。全程第一份 `rd.graph_end` inclusive30.420秒中，绘制回放25.381秒；同阶段直接子范围已分开，不能再与父项相加。资源释放和卸载仍有独立问题，但不是这段渲染大头的解释。

工作量也已落地：入口后各记录9,083,169 / 8,964,747 / 8,456,323条draw指令，平均每次主循环约4470 / 4500 / 4549条；返回稳定期每循环约 **4077 / 4077 / 4076条**。后者顶点绑定约3974次/循环、uniform绑定约2170次/循环。计数包含2D、3D和后处理，一条indirect指令可能代表多次硬件draw；不能宣称这是4077件物件或4077条3D主颜色pass，也不能把所有工作判成重复。后续仍需分清pass与材质/顶点绑定的必要性。

加载值低于18的三份，但这组同时包含19r2和新增诊断范围，运行次序也不同，**不把79.769/74.374/67.066秒宣称为栈数组带来的整图收益**。卸载最大帧266.707 / 379.145 / 262.375ms；返回传送最大364.641 / 372.473 / 310.670ms；返回加载最大102.569 / 106.677 / 99.923ms。返回稳定期第二份仍有5帧>50ms、最大57.928ms，第三份空场回收有52.254ms；慢值全部保留，low与长帧未验收通过。

源码进一步确认当前回放没有后台派发：`SECONDARY_COMMAND_BUFFERS_PER_FRAME=0`，`_run_secondary_command_buffer_task`只有声明和定义，没有调用，`secondary_command_buffers_used`没有递增路径。增加地图准备worker不会加速这一段。上游[RenderingDevice源码](https://github.com/godotengine/godot/blob/master/servers/rendering/rendering_device.cpp)保留默认禁用的驱动兼容性说明；[Khronos多线程指南](https://docs.vulkan.org/guide/latest/threading.html)要求独立命令池及明确同步，不能只改常量就宣称并行完成。

下一切片优先做大绘制列表的独立并行记录实验：每个在途任务独占命令池/缓冲，保留完整列表状态及GPU依赖顺序；待当前frame GPU fence完成后才能复用。先用多列表、稀疏绑定、材质/管线变化、纹理与buffer依赖、反复submit/reset/free的像素及工作量测试，确认无任务或指令重复、无漏画，比较主线程时间和总CPU；小列表不机械拆线程，含subpass切换的列表先保留原路径。然后才对冻结地图做对照。当前尚未实现该并行实验，不修改默认引擎，也没有把渲染或100秒问题标为解决。
