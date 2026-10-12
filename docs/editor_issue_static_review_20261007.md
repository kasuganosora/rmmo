# 编辑器与游戏新反馈：Grok 静态初审及复核（2026-10-07）

## 范围与结论

用户在“仅记录、先不要修”之后，授权“先让 grok 静态分析这些问题”，重点判断是否同类。本轮只分析和更新记录，没有改动实现代码、地图或素材，没有启动 Godot、复现操作、运行测试或采集新性能数据。所有反馈继续保持未完成。

**可以合并的主要问题是：编辑器摆放物体、删除普通物体、普通地面摆放、新建/转换可雕刻地形，共用同步全场景重建。** 局部刷新之后的同步合批准备和撤销快照，是同一次编辑中另外两段共同成本。角度输入、地图加载、游戏行走及花坛通行不能全部归为同一原因。

| 分组 | 对应反馈 | 复核结论 | 后续优先级 |
| --- | --- | --- | --- |
| A：编辑提交触发全量重建 | 摆放物体很慢、删除物体很慢；部分地形摆放 | 调用链确认；本次实际耗时未测 | 最高，优先统一处理 |
| A2：局部刷新及撤销的共同成本 | 自动瓦片、雕刻，以及未来改成局部刷新的增删操作 | 存在同步全量准备/扫描和全记录快照；耗时占比未知 | 随 A 一起核对，避免只换调用入口 |
| B：加载总耗时 | 加载地图很久 | 已有后台和分帧；游戏与编辑器入口不同，最长阶段未确认 | 最高，保留独立性能项 |
| C：运行时区域切换或角色通行 | 三处坐标卡顿 | 有流式碰撞、导航与物理候选；尚不能判为同一根因 | 最高，三处分别保留 |
| D：输入提交 | 微调角度不实时 | 文本提交机制是明确候选；不能覆盖“点箭头也不实时”等未确认行为 | 独立功能项 |
| E：花坛通行 | 应能站上行走、跳越 | 碰撞承托与导航/空中移动约束；不与编辑器重建合并 | 独立功能项 |

## A：已确认的编辑器共同调用链

- 资产摆放：[world_editor.gd:485](D:/code/rmmo/scripts/world_editor/world_editor.gd:485)；普通地面/box 在同文件 493–502；预制件在 1251–1258。
- 普通删除：[object_selection.gd:222](D:/code/rmmo/scripts/world_editor/object_selection.gd:222)，撤销快照、自动瓦片刷新后调用 `_rebuild()`；整栋删除也经 [building_motion.gd:172](D:/code/rmmo/scripts/world_editor/building_motion.gd:172) 重建。固定城防有独立分支，不以普通删除链替代全部类型判断。
- 新建/转换可雕刻地形：[terrain_tools.gd:72](D:/code/rmmo/scripts/world_editor/terrain_tools.gd:72) 调用 `_rebuild()`；前置占地/几何校验还有全记录检查。
- 当前 **3D MCP** 的普通资产/box 摆放同样经过 [mcp_ops.gd:417](D:/code/rmmo/scripts/world_editor/mcp_ops.gd:417)。后续应共用业务增量提交，不能只优化 UI。

共同链为：修改记录 → `_rebuild()` → 清拾取缓存、渲染批次和城防碰撞 → 释放整棵编辑视图及编辑器根下的静态碰撞体 → 全记录 `build()` → 重建拾取/行走碰撞 → 更新选择、列表、合批和环境。见 [world_editor.gd:541](D:/code/rmmo/scripts/world_editor/world_editor.gd:541)。

`WorldDocument.build()` 还会生成带全记录深拷贝的导出根，更新全体地形邻接，再逐记录生成节点。加载期和单次构建内已有资源缓存，因此不能进一步声称“每次所有文件必定从磁盘重读”；确定的是场景与相应派生状态的全量重建。

主代理补查发现，**普通地面连续涂刷还有无变化重建**：鼠标左键移动经 `world_editor.gd:380–389` 调用 `_place(..., false)`；[world_paint.gd:26](D:/code/rmmo/scripts/world3d/world_paint.gd:26) 在同一笔划已经访问过的格子返回空字符串，但调用者 495–502 行忽略返回值，仍置脏并 `_rebuild()`。这是满足该分支条件时的确定行为，不能泛化到自动瓦片或断言用户当时使用的就是这类地形。

自动瓦片走 `_refresh_records(changed)`；已有可雕刻地形的雕刻、换材质也走局部记录刷新。**“地形”必须保留这三类区别。**

## A2：不能只把 `_rebuild` 替换成现有局部刷新

1. [world_editor.gd:694](D:/code/rmmo/scripts/world_editor/world_editor.gd:694) 的 `_refresh_records` 更新局部节点后，仍会调用完整 `_sync_ground_batches()`。
2. [ground_batcher.gd:136](D:/code/rmmo/scripts/world3d/ground_batcher.gd:136) 的 `sync()` 清源描述缓存，并用 `_prepare_step(0)` 一次完成准备循环。后续网格合并已有后台/分帧，但准备扫描本身没有这层时间预算。不能把“已有 worker”等同于编辑调用全程异步。
3. [world_editor.gd:523](D:/code/rmmo/scripts/world_editor/world_editor.gd:523) 扫描可见城防源并提交碰撞分组。**现有 [fortification_collision_batcher.gd:79](D:/code/rmmo/scripts/world3d/fortification_collision_batcher.gd:79) 会跳过签名不变的组，83 行也有形状缓存。** 局部刷新不等于每次重生成全城防三角；全量 `_begin_rebuild` 则会清掉这些状态。
4. [world_document.gd:53](D:/code/rmmo/scripts/world3d/world_document.gd:53) 的 `checkpoint()` 对全部记录深拷贝，最多保存 32 步。普通增删、属性数值提交会承担这部分成本。存在全图拷贝已确认，但不能凭记录数宣布它就是最长耗时。

未来边界：按受影响 UUID 和邻接关系增删节点，失效相应渲染/碰撞组；无变化操作直接结束；分帧准备并复用未变化来源；撤销按完整事务保留。已有局部位姿路径应继续使用。不能通过取消碰撞、撤销、校验或整图合并为一个网格换取速度，也不能仅给每次点击套一层加载遮罩。

## D：角度输入是另一条链

[inspector.gd:34](D:/code/rmmo/scripts/world_editor/inspector.gd:34) 的变换 `SpinBox` 只连接 `value_changed`，没有开启 `update_on_text_changed`。Godot 官方说明此属性默认 `false`，开启才会在文本变化时更新数值，而非等提交；同时会影响表达式输入。[Godot SpinBox 文档](https://docs.godotengine.org/en/4.7/classes/class_spinbox.html)

因此，截图中数值框仍有输入焦点、打字后场景未立即更新，与当前提交行为相符。数值一旦提交，普通资产经 [object_selection.gd:309](D:/code/rmmo/scripts/world_editor/object_selection.gd:309) 调用局部变换，通常不走全图重建；楼层隔离等路径仍有例外。未复现点击箭头、回车或失焦，不能断言它们也失效，更不能归因于 15° 吸附或胶囊模式。

未来应考虑实时预览与结束编辑时的一次撤销提交；不能只打开逐字更新，仍让每个字符复制整张文档。需处理尚未输入完整的负数/小数、表达式、取消和焦点保持。

## B：加载长等待需独立分阶段

编辑器普通打开已有 `load_job`：后台文件读取，分帧校验、资源准备、场景构建和合批等待。普通增删没有经过这条加载作业。同步 `open_document()` 仍存在，主代理确认“恢复上次保存”在 [world_editor.gd:1453](D:/code/rmmo/scripts/world_editor/world_editor.gd:1453) 会调用它；不能将其当成所有普通打开的入口。

Grok 游戏初审缺少登录加载界面源码。补查 [loading_screen.gd:216](D:/code/rmmo/scripts/ui/loading_screen.gd:216) 确认，正常三维加载界面启动 `map_loader`，成功后在 243 行设置 `prepared_world3d` 再进入游戏。`world_3d._load_or_fail` 的同步导入是未提供预加载场景时的备用路径，**没有证据证明用户的慢加载走了这个备用路径**。

游戏还会等待附近碰撞、导航可查询、渲染批次、风/灯材质和小地图准备，见 [world_3d.gd:194](D:/code/rmmo/scripts/world3d/world_3d.gd:194)。若干工作在此前已启动或在让帧期间推进，不能把所有等待写成完全不重叠的串行计算，也不能只从静态代码认定最长阶段。

未来按同一地图的入口及冷热状态拆解已有 `load_job.state().timings`、`loading_profile`：总等待和最长主线程停顿分别报告。本轮不启动测量，不沿用旧文档耗时作为本次数据。

## C：三处游戏卡顿可共用诊断，但暂不合并根因

[world_stream.gd:5](D:/code/rmmo/scripts/world3d/world_stream.gd:5) 与 [world_location.gd:78](D:/code/rmmo/scripts/world3d/world_location.gd:78) 使用 32 m 分区，当前原点为零。静态换算如下：

| 截图位置（m） | 分区 | 到最近 X/Z 分界的距离（m） | 能得出的结论 |
| --- | --- | --- | --- |
| `(262.7, 125.8)` | `(8, 3)` | `6.7 / 2.2` | 靠近 Z 分界，是区域切换候选 |
| `(292.9, 151.4)` | `(9, 4)` | `4.9 / 8.6` | 与前一处不同分区，不能借用前一处根因 |
| `(321.2, 160.3)` | `(10, 5)` | `1.2 / 0.3` | 靠近两条分界交点，不代表同一帧跨过两轴 |

流式候选包括新碰撞准备/主线程安装、驻留应用和渲染合批提交。已有增量候选计划、工作线程、缓存与时间预算；单次不可拆操作仍可能超过切片预算。截图没有卡顿发生帧及完整轨迹，不能据此断言“就是跨块”，更不能宣布第三处进出条带最多。

另一个不同机制在 [world_authority.gd:57](D:/code/rmmo/scripts/world3d/world_authority.gd:57)：无支撑面，或预计位置与落地点都不满足 `near_surface` 时，会把水平移动意图 `wish` 清零；这项检查在空中也执行。它可能造成角色停步而帧率正常。**这是移动前的水平运动拒绝，不是移动后的位置回滚。** 窄处还有物理接触候选，尚未获得现场净宽/接触数据。

未来最小区分：三个点各自首次与往返；同帧对照帧时间、stream/collision/batch 耗时、`motion_timing` 的导航和物理耗时，以及移动被拒绝的状态。若帧率正常但水平意图被清零，按通行问题处理；若主线程长帧，按对应耗时阶段处理。不要把所有症状都当作 GPU 性能。

## E：花坛保留承托，另审通行规则

当前资产可按视觉网格生成碰撞；`walk` 和 `block` 都会参与相应物理/导航流程，只将标签改成 `walk` 不足以证明可站立和跳越。当前游戏水平移动前的支撑/导航校验也作用于跳跃途中，可能与矮台面未纳入导航共同影响体验；是否发生在该花坛仍未确认。

主代理只读当前保存地图和截图中的 `obj_200935` 关联 GLB 元数据：4437 条地图记录；该资产只有一个名为 `Structure` 的 mesh 节点，单 primitive 26224 个 POSITION 顶点，JSON 未见独立碰撞节点或 `rmmo_collision` 标记。整体包围盒高约 0.709 m，实例 Y 缩放约 0.85，**整体包围盒高度不等于可站立顶面高度**。没有检查三角拓扑、烘焙结果或运行时碰撞。

该 UUID 来自角度输入截图，尚未证明就是游戏通行截图中的花坛；保存地图在本轮只读检查之间发生了外部更新，不能以其当前姿态替代截图姿态。资源路径、记录快照与地图 SHA 保存在分析目录。不得据此修改当前用户地图。

未来按“可站立顶面、可沿花坛行走、可跳越”验收，必要时分离装饰和支撑碰撞，同时核对角色导航规则。不能简单删除全部碰撞作为完成。

## 对 Grok 建议的取舍与后续顺序

- **接受**：将普通增删、普通地面及新建地形的同步全量重建作为首个共同修复目标；顺带审查合批准备和撤销成本。
- **修正**：自动瓦片并非同样全图重建；局部城防同步已有不变组跳过和形状缓存；游戏使用移动意图清零而非位置回滚；正常登录已有预加载入口。
- **不采纳无证据推断**：第三个坐标必定双轴同帧跨块、建筑一定已经驻留、窄处一定是导航挤压、所有加载阶段完全串行。保留为需要证据区分的候选。
- **不机械保留全量重建**：Grok 建议对记录顺序、地图元数据或大预制件一概保留重建，证据不足；应按影响范围和一致性要求决定，不能把它们写成必然的技术限制。
- **暂不实施**：先完成本次归类。未来获得修复授权后，编辑器 A/A2 优先形成统一增量提交；加载和游戏仍保持最高优先级并分别找最长阶段；角度和花坛单独验收。UI/3D MCP、锁定/隐藏、撤销重做、保存重开、碰撞及房屋分层语义必须保留。

## 分析证据

本机程序 `C:/Users/luna/.grok/bin/agent.exe`，版本 `grok 1.0.46 (2765805b9442)`。两份任务分别覆盖编辑器和游戏，均已完成、退出码 0。使用带行号源码快照、明确只读分析范围、`--permission-mode plan`、`--no-subagents`，没有开启自动全局批准。长提示词被 CLI 截断后，Grok 调用 Read 补读了自身会话中的提示词快照；导出记录没有代码写入或测试命令。不能把空 `--tools` 参数描述成已验证的硬隔离。

- [编辑器原始初审](D:/code/rmmo_runtime/review_artifacts/grok_issue_groups_20261007/editor_report.txt)
- [游戏原始初审](D:/code/rmmo_runtime/review_artifacts/grok_issue_groups_20261007/game_report.txt)
- [源码哈希清单](D:/code/rmmo_runtime/review_artifacts/grok_issue_groups_20261007/manifest.json)
- [保存地图静态摘要](D:/code/rmmo_runtime/review_artifacts/grok_issue_groups_20261007/map_static_context.json)
- [花坛资产 JSON 元数据](D:/code/rmmo_runtime/review_artifacts/grok_issue_groups_20261007/flower_asset_metadata.json)

同目录保留 prompt、状态、stderr 和完整会话导出。主代理对照当前源码复核并补读遗漏入口；记录更新前，快照清单中的文件哈希均未变化。后续仅更新本报告和待办，不以共享工作区已有未提交代码改动作为本轮修改或本轮验证成果。
