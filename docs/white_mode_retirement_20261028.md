# 白模专项退役（2026-10-28）

用户在编辑器适配收尾期间明确要求“白膜的可以删除了”。本轮停止维护白模诊断缓存，退役专用加载模式和消费分支；正常无贴图美术资源、完整材质 native 产品及历史测量证据不属于此次删除对象。

## 代码范围

- 移除 `white_native_asset_cache/metadata/writer` 及白模建筑 sidecar 的专门读取和生成。编辑器和游戏的正式产品统一使用完整材质 native candidate、预算、source/payload 身份及 reader；缺失产品仍明确失败，不回退作者 GLB。
- 移除 `white_materials`、`native_geometry_only`、白材质替换与 CPU 投影、白模 generation，以及各层对应的快捷分支。保留独立的禁纹理、HUD 诊断开关。
- 移除仅为白模启用的 worker 容量、发布压力捷径、模板投影、局部地形、prefab/road 旁路缓存等。完整材质原先实际执行的公平发布、碰撞、内存准入、取消、释放、加载覆盖与帧预算保留；没有把仅在白模测过的优化自动启用到完整材质路径。
- 部分 `white` 命名的历史 profiler 同时承载完整材质的路线、返回/卸载和回收测量，保留其通用实现并删除白模入口。纹理阶段 runner 只接受 `full`，旧 `white/map` 阶段参数明确报错，不能把旧阶段结果重新标成完整材质。
- 删除纯白模专项工具和测试；仍有价值的完整材质合同从旧 fixture 提取为公共基类。公会 whitebox 等内容制作/模型验收工具保留。
- 删除 World3D 白模专属初始遮罩和只在该遮罩下进入的收尾/超时分支。普通入口原有错误清理副作用保留为 `_abort_initial_entry`；GameSession 转场、跨图几何准备、独立 profiler 遮罩及 building 首帧等待均保留。生命周期测试改为实际无私有遮罩的入口合同，不再通过注入已不存在的白模入口制造覆盖。

## 验证状态

本轮已运行的正式路径回归如下。退役前完成的白模 21/0、缓存审计 10/0 等属于历史证据，不作为退役后正式路径的验收。

| 检查 | 当前结果 |
| --- | --- |
| 改动/新增 GDScript 解析 | 最终补测 121 文件，0 失败 |
| 普通入口与 building/GameSession 生命周期 | 11/0，含错误锁定与 presentation 取消 |
| 实际完整 native、移走作者 GLB 后加载 | 117/0 |
| 完整 native 直接模板与资源 owner | 96/0、125/0 |
| native 缓存、footprint、编辑器 native-only | 37/0、30/0、24/0 |
| 文件/节点边界及 bounds | 23/0、42/0 |
| 公平发布、实例工作区 | 29/0、57/0 |
| 完整材质 prefab specs / faces、交互切片 | 均 0 失败；保留原材质、碰撞、预算和对象数量上限 |
| 实际 3D HTTP 材质编辑 | 49/0，含同源 PNG/DDS 切换、undo/redo、保存重开、退出回收 |
| 实际 3D HTTP 原生散布/缩略图 | 26/0，含 Windows 路径、越界拒绝和外部保存冲突 |
| 严格 native reader | 92/0，保留源外部输入/显式导入与普通 native 消费边界 |
| 原生碰撞准备、调度回收、absence | 80/0、86/0、56/0；晚到失败、取消、预算、交接和视觉未就绪断言均保留 |
| strict 原生索引与真实消费者 | 30/0；另有离线索引 42/0、完整 native 117/0、编辑器外围 28/0 |
| 完整登录/游戏/HUD/事件流程 | 最终独立临时地图 16/0，保留 30 秒期限并明确验证就绪、转场结束和解锁 |

证据位于外部 `D:/code/rmmo_runtime/review_artifacts/white_mode_retirement_20261028_01/`。GPU 测试均通过私有桌面运行；使用 GREEN 引擎 SHA `20d25131e638bb6cafa0c285e2cddbf09eb6e7e528ee4f8f22dc566adfd8fde8`。各项记录运行前后脚本身份，没有将逻辑回归耗时作为整图 FPS 或加载收益。

失败样本保留：初次解析遗漏两个共享 profiler 的白模字段；ownership 旧测试错误要求延迟回收同步结束，已改为等待真实 retirement drain 并检查存活资源与预算；native-cache 退出测试遗漏重新导入后的 footprint，已补齐并增加 reader 实际启动断言；HTTP 材质首轮启动器遗漏隔离内容根，补齐后通过。这些测试修正没有放宽生产预算或重新启用 GLB 回退。

真实 HTTP native 散布/缩略图首次测试暴露 Windows 路径分隔符问题：原生 candidate 使用正斜杠，环境及 UI 输入使用反斜杠时误报 `candidate_product/candidate_identity`；保存也将同一地图当成另存为目标。已在精确身份比较处统一路径表示，原资源根、SHA、产物身份和保存签名检查保留。`native_http_green_02` 已通过真实读取、散布预览/生成、undo/redo、save/open、缩略图修复及外部修改后的拒绝覆盖；原失败和中间保存失败样本均保留。

保留的 sync/demand 专项 runner 已接到完整材质夹具：固定 full manifest、模板/源码/引擎身份并检查实际 full 材质报告；旧白模/map 阶段明确拒绝。相关五组 Python 测试 45/45，这是工具合同回归，不是整图性能样本。

两项旧碰撞测试改用真实原生产物 A/B 发布并移走作者 GLB，原“改写 GLB 令消费失败”改为实际原生产物切换后的身份拒绝，保留所有调度生命周期断言。首次迁移漏选 native 索引模式导致 `unsupported_record`，失败样本 `none_preparation_01` 保留；改正夹具后 80/0、86/0，独立 absence 合同 56/0。reader 回归首次漏传 `--test-root`，补齐启动参数后 92/0，未修改生产以绕过隔离限制。

复核发现的生产 strict Index 与城防缓存 GLB 读取已独立修复。`native_only` 与 `trusted_package` 解耦，普通游戏/跨地图入口显式选择 native；严格模式继续检查地图/引用/预算/归属，原生产品全字节审计仍由原 reader 负责，索引身份比较不冒称全字节审计。索引版本提升为 7，旧派生目录重建；同源不同 payload/预算直接令整个旧索引失效，避免沿用旧 building group bounds。每次目录打开仅按唯一模型读取一次小型 native 身份；不是逐实例或逐帧扫描。城防在加载操作内保留同一模型身份，下一操作重新观察产品，并保持旧 `load_model_signatures` 字符串合同。

`strict_native_index_red01` 实际复现无源 strict 返回成功却失去 bounds（4 通过/2 失败）；新增原生参数后的扩展合同最终 `green13` 30/0，入口参数变化和扩展项不能冒称同字节测试。覆盖真实游戏 MapLoader、跨地图 warm/cold、无源编辑器打开、group/预算失效、城防重复实例复用、缺产物与 rmres 损坏拒绝。green07 信号回调内同步 free、green08 误启无预取数据的后台预加载、green11/12 测试解析错误均保留，未归为生产或引擎修复。

自动瓦片 kit、文档打开、试玩、草稿和城防的模型路径检查改为逻辑 key 权限，实际 native/纹理/地图文件仍验证真实路径。该结论来自静态调用链及功能回归，没有宣称用系统级 IO 跟踪证明所有路径零系统调用。

### 游戏流程证据边界

首次旧 `test_world3d_flow` 样本 `flow_01` 只有“角色控制解锁”失败；旧夹具在 30 秒截止后只确认场景存在，没有记录实际 readiness/锁定状态。随后 3 个诊断样本使用相同默认 `p4_yard/map.gltf`（SHA `6943aeb12c311a89ba3e5f4c1955eed2a8529eef3ed606a6fc3f1ed28dc730b7`）均未复现：世界先就绪，GameSession 等待首帧/渐隐期间按设计锁定，转场结束后解锁。原样本原因仍不明，没有归为 OS/GPU，也没有宣称修复了生产锁定 bug。

最终正式流程测试使用工程外独立临时 yard/inn，保留 30 秒期限，显式检查 ready、转场结束、解锁及地图 SHA 守恒。`flow_isolated_01` 16/0，生产/测试/引擎身份在运行期间不变。日志保留 Compatibility 的 TAA/SSS 不适用及退出时 10 个 ObjectDB 实例警告；不能写成无警告、无泄漏验收。本项不是 axel_town 加载性能或资源释放压力测试，已有 owner/retirement 独立验收不能消除这条夹具退出警告。

最终静态清理统计：删除 8 个生产模块、66 个工具/测试文件，未发现已删除脚本的代码引用或孤立 `.gd.uid`。新公共 fixture 与保留的完整材质回归不计为白模模式。

源代码与测试变更均在隔离 worktree；没有改动 `D:/code/rmmo` 的用户未提交工作，也没有删改外部正式模型或历史性能证据。

## 后续顺序

先完成编辑器正式路径回归、旧素材 native 补齐和真实地图验证，再评估 Godot 4.8 beta。只读调研已保存到 `D:/code/rmmo_runtime/review_artifacts/godot_48_beta_research_20261028_01/REPORT.md`；该方向尚未编译或替换引擎，也没有宣称现有 `ImageTexture`/DDS 外部资源已自动获得官方流式纹理能力。
