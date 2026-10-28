# 内容编辑器材质管线适配（2026-10-28）

用户将当前顺序调整为先完成编辑器适配与优化，支持继续内容设计，再返回游戏材质长帧专项；同时要求将旧导入模型补齐为原生格式。最新硬约束：GLB 仅用于显式导入/转换，导入后的打开、预览、保存重开、派生功能与游戏加载均消费 native；缺失产品不得回退 GLB。旧 `.glb` 字符串可以保留为逻辑模型键，不要求对应源文件存在。此记录区分已验证的代码、待迁移的资源和未测的整图性能。

## 本批代码

- 第一阶段先让 native 候选命中时跳过 GLB 内存估算；随后按用户的硬约束移除编辑器普通加载的 raw 重试、源存在检查与源哈希。实际固定 native reservation 保留，缺失产品明确要求重新导入。历史 legacy 总额不能在未估算时伪造；第一阶段的 raw fallback 测试不再代表最终合同。
- 编辑器纹理准备显式使用可变源快照身份，不再继承游戏包的路径身份。bounded PNG/JPEG 从已读字节生成内容标识，fallback PNG/JPEG/WebP 也用同一快照做标识与解码；不切换进程级 `verify_packages`。编辑器与游戏的派生像素缓存分开，保留旧材质/图片的外部 owner，刷新不会原位篡改它们。
- 通用 DDS 生成器在实际编码时写入相邻 `.source.json`，关联源快照、DDS 字节和颜色/法线/翻转角色。两文件发布不是原子组；中断后编辑器会拒用不匹配产品并回到源图片。没有给未知来源的历史 DDS 补签名，也没有改写正式包。
- 编辑器预先按完整 PNG/JPEG 路径准入，在 worker 取得本次源快照后才选择匹配的 DDS；尺寸或输出成本不符、来源过期、缺元数据或发布中断均走已预留的源图片回退。游戏默认 DDS 路径不增加这些可变源检查。罕见 fallback 格式仍使用原独占预算。

UI 与当前 3D MCP 保持共享业务入口，工具名/schema 未变。此次修复的是打开地图时的刷新，不新增文件监视器或自动同步已经刷到地图里的材质定义。

## 验证

全部 Godot GPU 测试通过 `run_godot_background.py` 私有桌面执行。使用 GREEN 引擎 SHA `20d25131e638bb6cafa0c285e2cddbf09eb6e7e528ee4f8f22dc566adfd8fde8`；这不是安装引擎已更新的声明。

| 检查 | 结果与边界 |
| --- | --- |
| native 规划独立复现 | 原版 4 通过 / 2 失败；候选扩展至 14/0，含真实 lookahead 去重、准入与取消。扩展版与原版测试不是同一字节版本 |
| 编辑器旧队列回归 | 原断言 130/1；唯一失败仍期待路径身份，按本次编辑器内容身份合同更新后 131/0 |
| trusted 可变纹理复现 | 同一个测试原版 19 项 / 4 失败，候选 19/0；补 DDS 实际 Job 消费、过期/中断/尺寸及小块预算后 27/0 |
| mutable DDS | 25/0；初次故意坏 JSON 有解析日志，改用返回错误码的可选元数据读取后再次 25/0、无该日志 |
| DDS 原合同 | 旧 editor 断言 271 项 / 4 失败；为编辑器 fixture 增加真实生成来源记录、改为内容身份后 271/0，游戏案例不变 |
| 游戏像素回归 | `test_texture_cache_trust` 0 失败，默认路径不增加源 SHA/完整 checksum/header 读取；`test_prefab_texture_preparation` 63/0 |
| Python 生成/暂存/迁移 | 20/0、20/0、5/0；含同长度源变化、元数据发布中断、normal 第二变体失败和编码中源替换 |
| 真实 3D HTTP + GPU | 39/0；paint/clear、锁定无副作用、undo/redo、save/open、同路径红→蓝、旧 shader/纹理仍红、后台 open 退出后的实际 lease/worker 回收 |

HTTP 隔离内容根缺少云噪声资源时使用原 layer clouds 回退，日志没有测试/脚本错误。该验收不代表所有视觉视角或正式地图已经复测。

外部证据根为 `D:/code/rmmo_runtime/review_artifacts/`：

- `editor_native_estimate_plan_20261028_01/`：保留红测、无有效日志的首轮启动及更新前旧断言失败。
- `editor_texture_identity_20261028_01/`：19 项同测试红绿。
- `editor_texture_regression_20261028_01/`、`_02/`：27 项扩展、DDS 和游戏像素回归及输入身份。
- `editor_mutable_dds_20261028_01/`：Python producer 回归与前后文件身份。
- `editor_material_http_trusted_20261028_01/sample_01/`：39 项真实 HTTP、GPU/parse 原始日志及代码/引擎身份。

## 仍须完成

1. 当前 axel_town 和旧导入素材的 native 状态清点与增量转换。旧记录中所谓“编辑器可变源闭包”已被 native-only 消费合同取代：保留作者 GLB 供显式重新导入，但普通消费不得检查、哈希或回退这些源。正式资源迁移与受影响模型复验仍待完成。
2. 固定完整材质编辑器地图的打开、预览、关闭复测，记录真实 skipped raw estimates、native 命中/回退、就绪时间与主线程峰值。目前没有整图时间收益结论。
3. 历史无来源记录的 DDS 在可变编辑器路径回到源图；UI/MCP 新贴图导入仍只发布内容寻址 PNG 和材质 JSON，自动 DDS 生成尚未接入。本批没有宣称这一项已完成。
4. 当前变更位于 `codex/latest-map-runtime-review` 隔离 worktree；未覆盖 `D:/code/rmmo` 中用户正在进行的未提交内容/代码修改。

游戏材质解析共享候选、同实例后台 shader 准备调查和尾部预算红测都保存原证据，按用户要求暂缓，编辑器任务完成后再接续。

## native-only 与存储限制收尾（进行中）

- 新核心功能样本：同一测试在隔离旧代码上 4 通过 / 10 失败，在候选代码上 14/0；扩展损坏 native 产品和显式生成版本检查后 16/0。包含没有 GLB 时的实际 LoadJob、预览、实例化、保存重开、预算归还，以及同 source 的新 native payload 替换旧缓存。严格审计仅验证 native，不回读 GLB。它是功能对照，不能换算为加载时间收益。
- 预制件捕获复用已导入模型的 native 引用，不再复制/重新导入 GLB，也不为同一模型做两次预览和表面重映射；模型身份与表面路径均未变。
- 移除 native 目录累计 8GiB 上限及每次发布逐文件统计。native 是必须保存的导入产物，已经不能作为超额可丢弃缓存；本轮没有删除或改指向任何正式产品。磁盘写入错误、单文件边界和独立运行内存准入仍保留。
- 原存储盘点 358 个 SCN 共 8,732,544,285 bytes；当前索引、previous 与 footprint 引用的并集没有完全无引用产品。仅依赖清理旧文件不能安全解决该上限。详见外部 `native_cache_capacity_20261028_01/REPORT.md`。
- 容量功能红绿已完成：隔离目录 9,663,676,416 bytes 的稀疏历史 SCN（实际占用 65,536 bytes），旧 producer 确切失败 `cache_capacity`，新 producer 6/0：新导入、native 读回、重复导入复用、新索引来源记录、历史文件保持均通过。相同测试 SHA、GREEN 引擎，分别执行期间生产脚本未变化；OpenGL 私有桌面，TAA 不适用警告保留。这是配额功能回归，不是整图性能比较。证据 `native_store_capacity_20261028_01/red_02/`、`green_02/`。首轮 Python truncate 实际分配了数据，夹具在引擎启动前被断言拦截，已删除该唯一测试占位文件；第二轮改为已标记 sparse 后 seek/write，确认实际分配后才运行。
- 其余限额按依据审查：格式整数/合法结构上界、运行内存预算、调度预算与任意历史数量阈值分开处理；不把取消限流冒充去除重复工作。

外围 native-only 改造、完整迁移与实际编辑器地图测试仍在进行；不能把核心与容量测试通过写成全链路交付。

## 本轮最新测试与交接边界

- 纹理工作量：同一来源颜色、OpenGL 法线、DirectX 法线共享一次捕获的字节快照；三变体 source SHA reads=1，发布/收尾重复 SHA reads=0。补交错文件名后 37/0。当前操作期间源变化由下一次打开捕获，不原位篡改已交付 owner。
- DDS/PNG representation 进入真实热缓存与 weak alias 的身份，不能仅比较 source SHA 后误复用旧 GPU 纹理。真实 HTTP/GPU 最新 `editor_material_http_trusted_20261028_01/sample_06` 49/0，包含同源 PNG→DDS→PNG、弱引用复用、旧 owner、撤销保存与退出预算；material publication 独立回归 46/0。
- 编辑器 native 核心扩展 19/0；native 估算 9/0；队列 130/0；包含显式导入审计的 trusted preparation 92/0；真实 GPU 导入 40/0；实际编辑器 HTTP 缺源打开/编辑/undo/redo/保存重开/缺产品恢复 52/0。导入不再在 native/footprint/bounds/building 未完整时发布库条目。HTTP 前两次不受当前 converter 支持的 BoxMesh 测试夹具失败已保留，第三次使用已有支持的封闭静态 glTF。
- native 外围首次 GPU 合同 26/0：套件、道路精确几何、城墙依赖、建筑组件 sidecar 与成员身份、篡改拒绝、仅从 SCN 重建 sidecar。该首轮没有源码前后清单；最终冻结版仍须重跑，并执行新增的 HTTP scatter/缩略图脚本。
- 迁移计划与失败归一 33/0；历史产物保留 GPU 合同 15/0，旧 producer 身份的真实 SCN 只补 footprint/bounds/building，SCN 与索引 SHA 不变、不生成额外 SCN；源改变明确要求 reimport。附带严格模式、移走 GLB 后的普通/固定候选后台准备，两条实际 worker 路径均成功。证据 `native_migration_contract_20261028_01/{planning_02,published_02}`。首轮坏 JSON 测试日志噪声及测试误用 PackedStringArray.filter 导致的 parse 失败已保留；第二轮安静返回预期错误，源码前后稳定。
- 8GiB 磁盘配额修复 `df203763`、材质库静默目录截断修复 `afc0c978` 已独立提交并推送。材质库红 1/6→绿 6/6，既有查找 89/0。其余 editor/native/纹理改动仍在工作树，未冒充完整交付。

### 此前交接项（由下方最新状态更新）

1. 冻结代码后补完 native 外围 HTTP scatter/缩略图与组合回归，按语义保留既有 GLB 导入测试，不用旧 raw fallback 断言约束新消费者。
2. 白模诊断的 full-only metadata 使用仍有两处待收尾：自动套件 `piece_mesh`、严格 imported building descriptor。桥梁 terrain contact 已改用白/全 validation identity，但该白模分支未运行。普通 full-native 路径已有上述测试；不得把它扩大成所有白模探针已通过。
3. 默认关闭的 collision-first 实验中，`collision:none` 缺产品捷径仍调用旧 GLB header/absence proof；需要转成离线发布的 native absence 合同，或停用该捷径并回完整 native。已修 collision asset descriptor 的 candidate/read，不能据此宣称整个实验链路不再读源。
4. strict audit 模式切换后，已缓存 owner 与磁盘被原地破坏之间的审计边界仍需明确；现有严格损坏测试仅证明重新读 native 时拒绝损坏，没有宣称每次缓存命中扫描磁盘。
5. 正式旧素材转换尚未执行。默认库及 prefab 闭包 218 个逻辑模型：159 个已有产品约 6.20GiB，59 个缺索引。显式迁移默认保留旧产品/原 generator，只补缺项；`--reimport` 才更新源版本。bounded GLB header/JSON 盘点这 59 件共 4,575,090,284 source bytes，无 skins/animations/morph，53 件无扩展、6 件 KHR_materials_specular；这是导入计划，不是产品/画质通过。正式转换须继续 `rmmo-model-review` 受影响项，保留母版与原已发布产品。
6. 材质 UI/MCP 图片导入的自动 DDS 生产仍未接入；已有 producer 来源记录及消费者一致性不代表该入口已完成。

没有修改 `D:/code/rmmo` 的用户未提交工作，没有转换或删改正式素材、没有新增游戏整图性能结论。目标保持 active；编辑器交付先于恢复游戏材质长帧优化。

## 最新状态：白模专项退役

用户明确要求删除白模后，停止上述第 2 项白模修补，删除专用 native writer/cache/metadata、白材质替换及白模旁路。完整材质所需的共享 profiler、原生模板和材质/碰撞/释放回归保留，详细范围和最新回归见 [白模退役记录](white_mode_retirement_20261028.md)。这不删除正常无贴图美术资产或历史证据。

上述第 3 项已改为离线 full native `collision_absence` 合同：普通 consumer 不再读取 GLB header/JSON/hash，旧产品缺少 absence 则回完整 native 准备。独立合同 56/0；旧测试中的取消、晚到失败和交接覆盖正在按新产品身份迁移，不能把 56 项称作所有旧调度测试已通过。

上述第 4 项审计边界已明确并验证：trusted 缓存切换 strict 后需对 native 审计一次；已经审计的内存 owner 可继续复用，不因随后磁盘被改写而改动它。新读盘仍拒绝损坏 native；默认 trusted 不新增逐次完整 SHA。最新 native-only 回归 24/0。

单产品 1GiB 与 65536 节点门槛也已去除，保留格式精度边界和真实运行内存预算，详见 [存储限制记录](native_store_limits_20261028.md)。正式旧素材转换、编辑器整图复测、UI/MCP 自动 DDS 生产仍未完成；完成编辑器后再进入 Godot 4.8 beta 编译评估。

补完真实 HTTP 外围回归时发现 Windows 正反斜杠表示导致两项消费者拒读相同 native，及同地图保存被误判另存为。共享 reader、编辑器保存目标比较和 document 保存签名比较已统一路径表示；越界和不同产物依旧拒绝，外部修改后的冲突检查仍保护已有字节。`white_mode_retirement_20261028_01/native_http_green_02` 已通过无 GLB 散布预览/生成、undo/redo、保存重开和缩略图修复；全部失败诊断与中间保存失败样本保留。

最终补齐 strict 地图索引与城防缓存的 GLB 遗留读取。游戏/跨地图将 native-only 与包校验策略分开，派生索引版本 7 保存 native 来源、payload 与预算；产物改变时整个旧索引失效重建，不沿用旧分组边界。城防加载操作内按唯一模型复用身份，下一次操作读取当前产品。自动瓦片、文档、试玩、草稿与城防仅校验逻辑模型 key，不再探测可选 GLB 本身，实际文件权限仍保留。`strict_native_index_green13` 30/0，真实完整 native 117/0、编辑器外围 28/0、离线索引 42/0。前者包含游戏 MapLoader、跨地图 warm/cold、无源编辑器打开及实际建筑分组；未生成新的 axel_town 整图性能数字。全部原失败/夹具错误见 [白模退役记录](white_mode_retirement_20261028.md)。

收尾解析 121 个脚本通过；完整登录/游戏/HUD/事件流程在独立临时地图上 16/0，保留 30 秒期限。旧默认图 `flow_01` 一次解锁失败在 3 个带状态记录的诊断样本中未复现，仍未归因；最终流程还有退出 ObjectDB 警告，详见上述记录，不能据此宣称全部生命周期问题已经结束。正式旧素材转换、编辑器整图复测和 UI/MCP 自动 DDS 生产继续作为后续交付，不被这次代码回归替代。

## 正式旧素材转换完成，集成验收继续

最新地图+库+99个prefab闭包共220件：59件缺失原生已全部转换，161件旧原生已补齐元数据。最终实读SHA核对确认220件源、161件旧SCN/index以及正式地图/库/prefab输入均未改变。59件新原生的实际编辑器操作现已全数通过：9批2768项检查，覆盖真实4个直接模型及55个预制件入口，放置、变换、撤销重做、保存重开、拾取、预览/缩略图和卸载；正式内容未修改。固定视角图审目前5件，54件仍待验，LOD与运行时专项单独保留。详见 [迁移记录](editor_native_migration_20261028.md)及外部 `editor_integration_summary_01.json`。

异步UI/MCP图片导入独立分支已完成旧引擎PNG回退的20项真实HTTP/UI/共享LoadJob预算测试。新CPU独立编码API与局部RenderingDevice初始化修补候选已编译，原始崩溃夹具和GDB构造计数对照通过；实际DDS HTTP/UI测试32/0，详见[引擎合同](editor_dds_engine_contract_20261028.md)。任意尺寸限制、首次涂材质同步读取、缩略图共享预算与实际材质画质仍在处理，分支未合并。Godot4.8评估继续后置。
