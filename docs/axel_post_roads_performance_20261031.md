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
