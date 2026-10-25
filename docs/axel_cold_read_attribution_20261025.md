# 2026-10-25：cold 慢样本归因与白模运行时脱离原 GLB

## 范围与版本

按用户要求先提交已有累计优化：`fc1ccd83f701dc67eb9b14025f25d4f8acef144a`
（`Checkpoint cumulative native white-map loading optimizations`）。本记录中的新改动在此之上。
分支 `codex/latest-map-runtime-review`；没有推送、修改正式地图或删除正式 GLB。

主指标仍为地图 pipeline 开始到当前需求 demand/job/stream/batch 连续三帧完整就绪。
不使用入口、撤罩或进程启动替代。纹理、HUD 等仍关闭，保留原生模型、碰撞、流送及合批。
全部 GPU 测试经 `tools/run_godot_background.py` 的不激活桌面串行运行。

统一引擎为 `release169_build/baseline/godot.windows.editor.x86_64.exe`，SHA256
`c593823dfcb41422b805558024bc21f7a6944b626ac960064b46c4d09f65afa7`。
进程普通优先级 32，不修改 QoS、优先级、系统电源策略或全局文件缓存。
没有本轮引擎补丁。

证据根目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/cold_attribution_20261025/`。
每次运行有 `.launch.json`、原始 `.json/.log`、`.result.json`；诊断另有 counters/file trace。
launch 保存引擎/地图/工具/相关源 SHA，result 核对运行前后源不变。

## 先拆清两类慢样本

原 `remaining_white_20261025/cold_regression_01` 的 **12.304s** 对比旧 cold 7.918s：
loader 多 4.216s，其中 hydrate 多 1.741s、cold hints 多 2.520s；入口后只多约 0.200s。
reference_read 属于 hydrate 内部，不能再加一次。旧样本没有线程 CPU/底层文件计时，不能
从墙钟直接归因磁盘、编译锁或某个资源。

本轮在去除 GLB 依赖前，以相同源/引擎/地图/开关捕获：

| 指标 | cold_detailed_before_01 | cold_detailed_before_02 |
|---|---:|---:|
| full-ready | 12.238s | 8.719s |
| loader | 5.455s | 2.941s |
| 引用读取墙钟 | 1.985s | 0.389s |
| 4 个 reader 累计 get_buffer | 6.553s | 0.092s |
| 入口后收尾 | 5.083s | 4.300s |

1065 个唯一文件、47,773,485 压缩字节、4 个 reader 均相同。慢样本队列取任务锁累计等待
只有 659µs；解码并未随快样本同幅下降。CPU 边界显示 reader 大部分时间未执行 CPU，
因此瓶颈已经缩到读取调用跨度，不能解释为反复加载同一批模型或任务领取锁。
但尚无该慢样本的底层 fread/等待栈，**不能宣布物理磁盘根因已确定或已修复**。

49 个模型描述被 912 个实例复用。此慢样本中原 GLB 打开/取长度/关闭累计仅 **7.131ms**，
native metadata 读取累计 381.345ms；49 个源身份均来自 SHA 文件名，没有全量 GLB hash。
因此，去除不合理的 GLB 依赖是正确的合同修复，不能拿它解释全部秒级波动。

## 修复运行时仍依赖原 GLB 的合同缺口

用户指出“已经放弃 GLB，元数据不应再打开它取长度”。原实现虽禁止导入回退，仍存在原文件
长度观察、存在性门、非 SHA 名称哈希，以及冷目录缺提示时回读 GLB 的漏洞。

现在白模可信 native 路线：

- 原 `asset_path` 只是包内逻辑键，使用纯命名空间检查；真正读取的 index、descriptor、SCN
  仍检查实际路径。逻辑键保留 `.glb` 后缀不代表读取 GLB。
- 身份、精确边界及完整保守准入预算来自已发布 native 描述。缺失即失败，不重新观察 GLB。
  描述中的原文件长度是离线导出事实，不再与运行机器上的 GLB 比较。
- 初始准备、Deferred、实例化、桥梁/城防 kit、远区块城防身份、目标地图预加载均取消原文件依赖。
- 共享目录构建在 trusted white 且没有已有 hints 时，每个唯一模型读一次 native 描述；已有
  hints 直接复用。缺描述或预算失败，不把模型降级为全局对象后发布假完整目录。
  这同时覆盖冷跨地图和初始加载后的可选后台目录构建。
- 冷预览直接使用 native reader 已有的索引读取；预加载清单对已读的 index/descriptor 字节算
  摘要，去掉再次打开两个文件的重复工作。目标场景交接的快照验证仍保留，未宣称其主线程 I/O 为零。

编辑器显式导入/离线转换/严格源审计保留 GLB。未验收纹理模式，不扩称所有运行模式都已脱离源文件。

相关生产文件：`asset_source_metadata.gd`、`white_native_asset_metadata.gd`、
`white_native_asset_cache.gd`、`map_paths.gd`、`map_loader.gd`、`map_dependency_index.gd`、
`model_parse_preparation.gd`、`deferred_asset_loader.gd`、`asset_library.gd`、
`target_scene_prefetch.gd`、`world_document.gd`、`bridge_mesh.gd`、`fortification_art.gd`。

## 原生描述迁移与受影响项验收

描述版本升级为 2，generation 由描述版本、geometry generator 和 bounds/memory 生产者决定；
不再把元数据读取脚本全文 SHA 当作格式版本。运行时计时和调度改动不会再使离线描述失效。
未修改几何产品版本、SCN、native index 或源模型，旧描述没有直接改标签冒充新导出。

离线工具 `build_white_native_metadata.gd --require-existing-equivalence` 正式重建当前 49 份描述。
51 份原描述按字节备份于 `metadata_revision1_backup/`，有独立 SHA 清单；其中 2 份不属于当前
标准产品集合，未覆盖。`metadata_revision2_export.json` 为每个模型保留源、native、index、
新旧 descriptor 的 SHA，以及精确 observation 相等、保存重开相等检查，**49/49 全通过**。
边界、原准入内存各字段完全相同，未把 SCN 文件大小当作内存。该离线转换会读取源模型并影响
系统缓存，后续 cold-index 不能宣传为物理冷盘。

按 `rmmo-model-review` 复验受影响的导出描述和读取管线：资源身份通过，几何/材质/LOD/骨骼/
风场字节未变化，未扩大为新的画质验收；纹理项阶段不适用。正式模型及地图不删除、不改写。
逐件状态与证据绑定见 `metadata_revision2_affected_review.json`（49项，无失败）。

## 红绿测试

`test_native_without_source` 使用临时 GLB，GPU分支经真实native writer导出后**物理删除原
GLB**再运行；headless分支使用小型替身payload，仅验证描述/目录合同。两者都不靠关闭一个
检查开关模拟源缺失。覆盖 SHA 文件名、人类可读名称、近远重复实例、桥梁/城防模块、原生 Mesh/CPU
所有者共享、后台初载/Deferred、目标预加载，以及缺失/损坏 native 失败和资源收尾。

- 初始红测：headless 10/5、GPU 18/14（通过/失败）。
- 桥梁/城防 kit 红测：64/6，修后 70/0。
- 冷跨地图/目录红测：32/10，修后加摘要原始字节 oracle，headless **43/0**、GPU **86/0**。
- 既有 `test_map_dependency_index` **42/0**；native-required loading/publication 各 **20/0**。
- 诊断测试：`test_map_resource_read_timing` **24/0**、旧 parallel read **25/0**、
  `test_cold_model_read_diagnostics` **21/0**、native metadata **14/0**。

原 `test_dependency_build_handoff` 还暴露 HEAD 已有的测试合同过期：把 cold hints 的 Dictionary
当作 Array，导致解析失败。修正为比较 error/paths/manifest 身份、边界及预算，并验证失败不返回
半成品；不改生产合同，也不删除原断言。重跑 **17/0**，原解析失败日志保留。

## 用同一引擎的底层文件 trace 核对

引擎现成 `RMMO_FILE_TRACE` 可记录 FileAccess 打开/失败/存在性及底层 fread 累计时间。
trace 先写 C: 临时文件，进程结束才复制到证据目录，避免诊断输出与 D: 资源同盘争用。
记录中的 end-begin 是句柄生命周期，不能当读取时间；使用 read_us 列。
诊断开关默认关闭，单独分组，不与普通基准混合。

| 指标 | cold_fread_after_01 | cold_fread_after_02 |
|---|---:|---:|
| full-ready | 8.804s | 12.693s |
| loader | 2.724s | 4.102s |
| loader→入口 | 1.459s | 2.026s |
| 入口→full-ready | 4.620s | 6.565s |
| 引用读取墙钟 | 358ms | 521ms |
| 累计 get_buffer / fread | 86.722 / 81.948ms | 131.696 / 124.684ms |
| 最长单次 fread | 1.897ms | 3.753ms |
| cold hints | 72.403ms | 114.458ms |
| 原 GLB FileAccess O/F/X/W | 0 | 0 |

两次均是1065唯一文件各1次 fread、47,773,485字节。256条保留的脚本读记录按path/thread/ticks
全部与底层唯一配对，无遗漏/重复/字节错配；其余809条核对全量trace及脚本总量，不冒称逐项匹配。
49组native index/descriptor也全部配对。地图文档 `.gltf` 的读取不是模型 GLB 回退。
这两份FileTrace早于随后补齐的共享冷目录入口及两项重复小文件读取修复；各自内部源SHA稳定，
但不与最终版本N10混成同一配置。

第二个慢样本与前面的秒级读停顿**不是同一机制**：引用及 hints 只增加约0.2s，3.889s增量散在
loader、入口与收尾。主线程CPU近邻计数从6.094到10.750秒，进程从15.109到30.078秒。
23模型、1514实例、742direct prefabs、311surface uploads/35,117,040B、2185specs、
227batch groups/2,304,380render vertices、1721collision shapes/429024faces均相同。
分片次数有变化（index slices 51→61、publication 1604→1624、template checks 79→126），
不能声称每一项执行工作完全相等，也没有模型重载翻倍的证据。

raw main cycles增加1.308倍，CPU秒增加1.764倍；该比例不是有效频率测量。采样未读取effective
QoS或全系统CPU，`qos_modified=false`只表示夹具没有修改，不能断言未节流/系统争用/降频。
详细边界与原始SHA见 `.trace_review.json`、`.cpu_io_comparison.json`、`.work_cpu_review.json`。

## 普通回归与剩余边界

最终冻结源的普通 `cold_native_independent_00..09` 全部功能通过，无profiler/GDB/file trace/
CPU采样。full-ready中位 **8.433s**，nearest-rank p95/max **10.730s**：03为10.730s、
06为10.683s，其余8次低于10s。因此严格10秒门**未通过**。中位loader2.620s、hydrate0.511s、
hints0.050s、entry4.189s、entry-tail4.319s；这些中位来自不同样本，不能相加。03的tail为6.122s。

工作核对：每次1065唯一rmres各读一次，2369实例对应1304copy+1065transfer；初始模型1次、
Deferred 23模型/1514实例/2185specs，prepared surfaces1241，raw import/readmission为0，
剩余身份source_reads为0。profile计数不能替代OS零GLB访问证据。全部源/引擎/地图/公共控制项
一致，原始慢样本完整保留。旧warm p95 6.918s/cold p95 7.918s不回填为这轮成绩；没有ABBA，
不宣称本轮总体加载提速或由本轮代码引起变慢。

`native_independent_traverse_01` 沿用warm-index，完整就绪 **7.562s**，功能/白模GPU/正式地图
未改/资源清理通过。2151part最大建筑和63块地形真实卸载，返回缺失及不可见项为0。但性能未通过：

| 阶段 | 最大帧 | >50ms帧数 |
|---|---:|---:|
| 离开 | 46.443ms | 0 |
| 卸载 | 62.353ms | 2 |
| 返回 | 190.361ms | 33 |
| 重载 | 98.277ms | 8 |

首个恢复3D帧78.608ms另列，不混作步行。汇总见`native_independent_summary.json`，包括全部
尖峰frame index/ticks与临近split。返回多数尖峰附近没有publication/stream jobs；重载最大峰
附近geometry tick61.752ms。Deferred显式poll/join/sync没有对应的大值，但last-observed计数
可在预算被拒的帧沿用，不能按行相加或凭零值排除内部等待，需stage时间戳或原生栈对应。

## GDB现场证据

`cold_tail_gdb_01` 使用同一c593引擎的匹配符号及GDB18.1，先加载符号再启动owned进程；
取得21组栈（11组含worker）、93个可解码GDScript函数帧。主线程128层、worker64层。
调试暂停累计下界43.860s，origin固定8s观察窗口被暂停耗尽，测试以
`origin full-ready missing before unload/return`结束。该失败与原栈全部保留，整体
`diagnostic_capture_ok=false`；可以使用已取得的栈，不把35.681s入口或缺full-ready视作自然性能。

初始采样实际命中：主线程碰撞 `_install_shape → ConcavePolygonShape3D::set_faces →
_volume_build_bvh`，ground batcher 的 `_watch_group` 信号登记/`_build_next`，以及
`_discard_job → Dictionary::erase` 下的嵌套容器析构。worker命中引用apply_record深复制、
dependency proof快照、stream index构建和procedural bounds。只有3个采样点属于入口后至
观察窗口失败前，不能用21个采样点当作完整收尾的时间份额。一个native ResourceLoader的
ReadFile栈也不是先前1065个rmres引用读取秒级停顿的复现。详见 `cold_tail_gdb_01.stack_review.json`。

随后 `white_return_gdb_01` 等真实路线到return标记才附加，获得13组栈（5组含worker）、
43个可解码GDScript函数帧；exit0、无测试失败/脚本错误，源码前后不变。采集暂停下界仍有
**20.282s**，因此只用来指认调用链，不与普通190.361ms峰混同，也不扣暂停“还原性能”。

- #2（地图开始后约74.397s，包含此前暂停）：主线程位于
  `NtGdiDdDDIWaitForSynchronizationObjectFromCpu → AMD Vulkan/Present →
  RenderingDeviceDriverVulkan::command_queue_execute_and_present`，确有CPU侧图形同步等待。
  尚无等待对象与普通长帧的一一对应，不能推出后台上传锁或某个图形hook是根因。
- #4/#6：主线程位于Deferred `_refresh_demanded`。
- #7（约86.883s）：`pthread_spin_lock → pthread_getspecific → __emutls_get_address →
  RenderingDevice::draw_list_draw`，对应draw_list_draw中的thread_local临时描述符数组。
  只证明采到TLS取址路径，没有持锁方或争用时长证据。主日志§96已有同类独立TLS压测，
  不能把一次栈重新命名为死锁或已确认190ms原因。
- #9：ground batcher `_build_next`中新建Thread；#10/#11在发布/接收记录。
  本次未取得明确的释放阻塞栈，也没有证实主线程正等待后台上传mutex。

GDB运行保留所有原栈、MI日志、时钟映射及报告；映射使用单个Unix/tick锚，包含暂停和
时钟粒度/漂移，不能假定纳秒级对齐。普通往返报告的峰值与这两轮调试墙钟严格分开。
返回13点中9点处于return、4点处于reload。5次worker采样只在#9抓到地图worker的
`white_native_asset_cache._bind_geometry → ground_cpu_mesh.remember`；通用池的60个
条件等待只是采样时闲置，不证明生产队列被阻塞。该次trace原GLB访问仍为0，730个打开句柄
累计fread35.856ms，不代表物理磁盘耗时。完整归因见 `white_return_gdb_01.stack_review.json`。

exe和调试符号匹配，但MI日志出现当前源码比二进制新的警告，不能把6044等行号当成当前
工作目录源码与c593构建全字节相同的证明。后续若修改引擎，必须先恢复/核对该构建的源码
身份，再建立候选和基线；本轮没有据这些采样修改或替换引擎。

本轮已经解决的是运行时原 GLB 依赖及其跨地图目录降级；尚未关闭的是旧引用读取秒级停顿的底层
原因，以及新样本整条CPU链普遍变慢的原因。不得借零GLB访问、一次低于10秒或产物工作量相等，
宣布cold尾部稳定性和全部长帧已解决。

## 2026-10-25 追加：covered 预算与 3D 返回刷新

后续针对最新普通回归的两处稳定尖峰做了受控修改，没有恢复 GLB、纹理或 HUD：

- **cold**：covered 初始加载 publication 预算从 32ms 调到 48ms（只在 cover/3D-off
  期间；交互和同地图 transfer 不变）。普通 cold-index N10：median **8.381s**、
  p95/max **9.784s**（9.784 为单次最大，仍低于 10s；原始 summary 在
  `budget48_cold_10_20261025/summary.json`）。
- **3D 返回**：`_refresh_demanded` 的返回长帧根因是 runtime building 注册触发的
  全量需求重建；现在只对已 indexed 且 cover 已撤的注册做增量 membership 追加，
  initial covered 阶段保留原 invalidation。priority rank 的移动锚从 4m 放宽到
  32m（chunk 级别），避免 2km 返回每 4m 重建整城。
- 返回/重载 10 次 native 路线结果为 **全部 0 帧 >50ms**（max 返回 43.1ms、
  重载 39.6ms）；卸载 9/10 干净，唯一 `a32_06` 50.7ms 的 `process_ms` 14.4ms、
  Deferred stage 全空，是 OS/GPU 空闲样本，按用户要求单独立项、不作为白模代码尖峰。
- `test_initial_loading_cover` 13/0、`test_entry_loading_contract` 24/0 通过；
  `test_deferred_index_preparation` 的 2 个失败在阈值 >256 时同样存在，是独立遗留。
- 代码仍在工作区，未提交；证据在 `anchor32_3d_10_20261025/`、
  `incremental_cold_10_20261025/`、`budget48_cold_10_20261025/`。
