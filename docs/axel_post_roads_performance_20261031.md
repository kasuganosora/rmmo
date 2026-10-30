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
