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
