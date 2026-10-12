# 冻结房屋自动合批候选复核（2026-10-07）

此项已进一步做窄范围原型与整城对照，收益不足以支持生产接入，原型已移出生产脚本，地图未修改。`house_prefab` 并非格式上不能合批；现有一刀切排除属于策略限制，但直接删除该条件不足以证明安全或收益。

## 冻结图的真实分布

只读解析 `bridge_perf_20261006/map.gltf`，未加载模型、解码预制件或计算资源 SHA；两次字典统计分别耗时 1.51 / 1.57 秒。

| 类别 | 记录数 | 说明 |
|---|---:|---|
| 已烘焙 `house_prefab` | 2276 | 已在烘焙时合并内部几何，不能等同于 2276 个未处理散件 |
| 普通导入资产 | 867 | 26 个资源路径，其中 14 个草素材路径共 750 实例 |
| `channel_mesh` 水面 | 162 | 动态水材质路径，目前被排除 |
| 记录级候选 | 1067 | 地形 49、道路 784、石岸 4、灯烛 230；实际 1009 记录进入 223 个已发布批次 |

因此 `4372−1009=3363` 的差额是 `2276+867+162+58`，最后 58 条仅能归为后续节点/材质/空间分组/单件等条件未成组，本轮没有运行时材质普查，不能进一步指定原因。record 上的风响应均缺省/off，不代表 GLB 子网格没有风场或 LOD 元数据。

2000 条房屋预制件中，1338 条带 fixture，**662 条不带 fixture**：floor 340、shell 245、roof 77。全部 2276 个预制件共有 1411 个 fixture；不能把另 73 个非房屋 fixture 也从 2000 中扣除。按当前 id/floor/presentation 的简化键，662 条形成 301 键，其中 126 键含多条、覆盖 487 条；113 键混有 floor 与 shell。该结果还没有材质、空间、顶点和可见性门槛，只是宽松上界，不是可兑现的 draw-call 节省。

最后按下述最小安全 gate 再做一次只读字典统计（1.33 秒）：排除 fixture、roof、`/ceiling`、事件等后剩 **521 条**，其中 floor 276、shell 245；64 个被排除的天花板本身标记为 floor。以同 id/floor/floor_y/role 分组有 **69 个多成员组**、244 条参与，最多减少 175 个记录对应的渲染实例。再加完整 `prefab_materials` 列表为参考键，得到 **114 个双成员组：110 对楼板、4 对墙体**，228 条参与，另 293 条单件；该参考分桶最多减少 **114 个实例**。组数增加是四成员组拆成两个双成员组，收益上界实际降低。

`prefab_materials` 只包含作者材质定义列表，保留其完整列表顺序并规范化字典键；它不等于运行时每个 surface 的材质顺序、完整非涂装材质或资源身份。后者、空间桶、65536 顶点及实际显隐会进一步改变可合并结果。因此这不是“几乎没有可合并对”，也不支持把它说成解决约 9000 次绘制或 30 ms 的主因。保留 **110 对楼板/4 对墙体的窄范围自动合批** 为具体后续候选，先验证代表性配对的实际 surface 条件与收益，再决定是否承担可见性失效改动；本轮不接入生产。证据为 `prefab_narrow_groups.json`。

## 已证实的实现条件

- `world_document._mesh` 的冻结分支虽早返回，`HousePrefab.visual` 已写入 `ground_batch_record` 和独立 `collision_solid`，不存在漏标记的根因。
- `HousePrefab.bake` 已使用 `Merge.build_fortification` 合并内部网格。`Geometry.build` 对非 ShaderMaterial 的 building 也会分派到同一 `build_fortification`。方法名带城防并不构成房屋格式限制。
- box 类冻结件使用实际刚体 transform；`size` 是已烘焙边界，并不会再次缩放网格。现有共形/单位缩放、材质、65536 顶点、空间单元门槛仍可复用。UV、UV2、切线和法线随原生 SurfaceTool 追加；不需要重建房屋生成器或改写作者记录。
- 透明、多 pass、triplanar、grow、fade、自定义 shader 等不能因“已经冻结”而绕过现有材质拒绝。正常 Cook 数据只支持 StandardMaterial3D/null，但运行时仍需对实际材质执行门槛。
- 选择/修改/撤销路径已有按 UUID `release` 后再更新和重新同步的流程；新候选仍须走这些共享业务操作，保留碰撞源与单件 UUID。不能用一个跨栋 MultiMesh 替代全部房屋。

## 具体可见性风险

当前 building 分组键只含 id、floor、presentation、fixture id；可见性只监听首成员。`building_cutaway` 却按每个 UUID 隐藏，并对 roof 使用该记录的高度、对 `roof/headhouse/ceiling` 使用单独 ceiling UUID。混组后隐藏非首成员可能残留，隐藏首成员可能让整组消失。

烘焙流程特意保留 headhouse ceiling 身份。本图该特殊 part 数为 **0**，这是通用正确性边界，不能描述成本图已发生的错误。当前 `floor` 和 `shell` 都进 body，编辑器楼层隔离还读取 `floor_y`；新增候选不应仅假设所有同层成员永远一起显隐。

## 最小可实施范围（后续验证，不在本轮生产接入）

1. 在 `ground_batch_geometry.gd` 增加窄的冻结静态房屋谓词：house_prefab + building + kind box，只允许无 fixture/fortification/事件/风响应的墙体与楼板；第一版继续排除 roof、`/ceiling`、资产和冻结城防/桥。保留现有材料/姿态/顶点限制。
2. 在 `ground_batcher.gd` 为该子集添加独立分组标签，并保持同建筑、同楼层、同 `floor_y`、同显示角色和空间单元，不跨栋，也不把冻结源与未烘焙灯烛混组。
3. 对新子集连接全部成员的 visibility 失效：成员显隐不再等价时，立即丢弃派生批次并恢复源网格，随后按正常受预算流程重建；不能只修改首成员监听。正常编辑仍先 release 再变换，不新增每帧整组扫描。
4. 第一版可在编辑器批次器显式开启窄候选，游戏保持现有行为，待运行时 cutaway 回归通过后再讨论共用启用范围。UI 与 3D MCP 自动经过同一批次同步，不新增用户必须手动执行的“合并”步骤。

天花板/屋顶未来可在完整可见性分区或全成员失效机制下另行接入；不能笼统判为永远无需合批。沿用现有 floor/role 键、只删 `house_prefab` 排除行，不是合格补丁。

### 全成员显隐失效的最小实现边界（静态设计，未改生产）

仅对新标签的冻结静态房屋组调整 `_watch_group`：将同一个带 key/generation 的 `_invalidate_frozen_visibility` 回调连接到每个成员的 `visibility_changed`；原有活动 fixture 继续使用现有首成员姿态/可见性路径。新回调先校验 generation，再立即调用现有 `_invalidate_group`。后者会删除 `groups`/`pending`、释放派生 visual 并恢复每个存活源的 GPU mesh，隐藏源仍由自身 visible 保持隐藏；`_drop` 已遍历全部成员断开同名 `visible_callback`，可直接复用。异步 `_finish_worker` 已检查 generation，失效组的旧结果不会发布到替代组。

但“只多连几个 signal”仍不是完整补丁：

- `_preparation.desired` 可能已经收集该组的旧可见性，必须将对应 snapshot 标为失效，并在 add 阶段重新确认该子集成员全部可见；commit 前也复查。不能让稍后准备/上传复活隐藏成员。若采用取消当前 preparation 的更简单方案，必须同时请求新的完整同步，不得永久丢掉无关组的待准备工作。
- 合并失效后，组级 signal 都被断开，单靠该 signal 不会在再次 show 时自动合批。最小正确行为是立即恢复直接绘制，到既有同步点再合并；若需自动重合，给拥有者发送合并后的 deferred 请求，使用**当前完整节点集与当前选中 excluded** 调用原 `request_sync`，不能拿刚失效的少数成员调用全量 API（会误删其他批次）。同一帧多成员改变应合并成一次请求，下一轮 editor/MCP 操作仍保留同步 release 语义。
- 第一版限编辑器，可由编辑器已有同步入口提供新快照；游戏不启用新候选，可避免在每次 cutaway 时同步恢复/上传一整栋的性能风险。自动重合性能收益未验证前，不通过每帧全量扫描补救。

已有回归入口可复用：`tools/test_ground_batch_lifetime.gd` 覆盖成员销毁、回调解绑、worker 世代、准备期间失效；添加首/中/末成员 hide、pending worker hide、prepare/add 之间 hide、show 后完整重合、clear 后无回调。`tools/test_house_batch_share.gd` 覆盖跨房屋/楼层隔离、fixture 变换和共享 mesh 不被修改，保留原行为并添加冻结静态组的非首成员隐藏。`tools/test_ground_batching.gd` 已覆盖隐藏后 sync，须扩为“不等下一次 sync 即无残影”。`tools/test_world3d_building_motion.gd` 与 `tools/test_world3d_building_fixtures.gd` 可复用真实 HTTP 的整栋移动/撤销/保存重开和门窗碰撞入口；`tools/test_world3d_fortification_batching.gd` 有 HTTP 楼层隔离案例，可按其方式扩展冻结房屋 hide/dim。全部 GPU 对照仍走后台桌面，不新增前台窗口。

至少需要：候选正反例与材质回退；同相机/光照的多材质 UV/法线/阴影对照；首/非首成员隐藏及恢复；楼层隔离 hide/dim；活动门窗继续独立；真实 HTTP 选择、整栋移动/旋转、撤销重做、保存重开；碰撞和作者记录保持；报告实际成组数量、draw calls、帧时间、加载及派生内存。662 条只是上限，烘焙已经去掉大量内部散件，材质数组和更细语义键还会明显缩小可合并子集；未计时前不给帧时间收益承诺。

## Grok 初审与人工筛选

本机 agent.exe 两份报告均 exit 0，位于 `D:/code/rmmo_runtime/review_artifacts/grok_editor_camera_20261007/` 的 `batch_report.txt`、`prefab_batch_report.txt`。保留了它指出的首成员显隐与 headhouse 风险；否定其“building 不会走 build_fortification / 房屋不能用该函数”的结论，源码 `Geometry.build` 和 `HousePrefab.bake` 均有直接反证。“跨栋才是大头”也没有动态归因证据，不能据此扩大实施范围。

字典证据为 `batch_record_census.json`、`prefab_record_groups.json`；源码未增加 asset batching。162 块动态水、750 草实例的风/LOD、1411 活动/附属 fixture 都保留为各自语义下的独立问题，不能通过放开通用静态合批一次解决。

## 窄范围原型的实测与处置

原型仅接受无 fixture 的 shell/floor，保留独立建筑、楼层、floor_y、role、材质、空间和顶点门槛；保留包括隐藏成员在内的弱引用显隐订阅。显隐变化立即恢复原网格、废弃旧准备结果，再合并请求按预算重新准备完整节点集。`test_frozen_house_batch.gd` 的任意成员隐藏/恢复、单件再显示、准备期/worker 期失效、分组边界和 clear 回归全部通过。最初未声明 Variant 来源变量类型导致的解析失败已修复，不算通过记录。

同冻结地图的私有桌面对照为 `editor_frozen_batch_compare_20261007.json`，退出 0、4372 条记录、原 SHA 不变。同进程全城俯视移动 direct → merged → direct-repeat，各预热 90 帧、采样 120 帧：

| 指标 | direct | merged | direct-repeat |
| --- | ---: | ---: | ---: |
| 帧中位数 ms | 32.873 | 31.576 | 36.624 |
| P95 ms | 48.022 | 47.344 | 55.272 |
| 总绘制调用中位数 | 9082 | 9115 | 9073 |
| 场景渲染 CPU 中位数 ms | 13.988 | 13.970 | 16.406 |
| 场景 GPU 中位数 ms | 4.122 | 4.159 | 4.169 |

实际新增 97 组、194 个源对象，570 个源 surface 合为 285 个。正式场景中其他门槛将字典上界 114 对进一步缩小。原有组数在启动后的实际同步为 219，并非早期刚构建时的 223，三个对照阶段都使用同一个完整节点集合及选择过滤。总绘制调用没有下降，渲染 CPU 与 GPU 的首轮和合并轮基本相同；重复直接绘制又有较明显波动。因此不能把一轮约 1.3 ms 中位变化归因于这项合批，也未证明可解决用户感受到的镜头卡顿。

候选已保存为 `review_artifacts/frozen_house_batch_candidate_20261007/{batcher,geometry}.gd`，生产 `ground_batcher` 和 `ground_batch_geometry` 不保留新 gate/订阅。测试显式加载归档原型；性能脚本需同时指定 `--frozen-compare --frozen-candidate=res://review_artifacts/frozen_house_batch_candidate_20261007/batcher.gd`。没有完成生产启用所需的全部材质像素与真实 HTTP 合批验收，也没有把逻辑回归当作可交付的画质或性能验收。后续应依据实际渲染热点选择方案，不继续扩大通用合批来追逐对象计数。
