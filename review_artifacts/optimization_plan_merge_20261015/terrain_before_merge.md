# 城市：天际线的地形编辑与性能处理：RMMO 对照研究

**建议把下一轮地形工作集中在“笔刷局部计算 → 局部几何与拾取更新 → 按实际瓶颈选择远近细节”上。** 天际线值得借鉴的是连续雕刻、材质绘制和远近尺度切换的工作方式；本项目已有不少对应能力，主要需要缩小每一笔的计算与更新范围，并补齐坡地创作工具。

范围按用户 2026-10-15 的澄清修正为**地形编辑和性能处理**。道路分区、城市经济及建筑自动生长不属于本次研究。下面主要采用《城市：天际线 II》的官方材料，明确区分公开事实、独立技术参考和 RMMO 建议。

代码基线：`520d142197bd71920b476f10d7e5261d4f4d3db5`，包含未提交修改，具体核对文件 SHA 见[研究证据清单](D:/code/rmmo/review_artifacts/skylines_terrain_research_20261015/evidence.json)。本次只做资料研究、代码审计和候选计划；没有修改运行代码、用户地图或性能开关，没有运行 GPU/性能测试。[历史性能跳过状态](D:/code/rmmo/docs/world_editor_todo.md)保持不变。

## 1. 查到的资料实际说明了什么

| 一手资料 | 确认内容 | 对本项目的意义与证据边界 |
| --- | --- | --- |
| [Colossal Order：Map Editor](https://colossalorder.fi/news/development-diary-map-editor/)，2024-03-20 | 高度图导入/导出；4096²、16-bit 灰度 PNG/TIFF；可玩区与外围 worldmap 分别输入，后者中央 1024² 对应可玩区 | 支持“大范围地貌与近处精修分开考虑”。输入格式不能证明其内部 chunk、LOD 或碰撞架构。不要直接采用其固定分辨率作为我们的规格。 |
| [City Corner #4 — A Peek into Performance](https://steamcommunity.com/games/949230/announcements/detail/532128384944178048)，2026-04-09 | 官方区分 GPU 渲染与 CPU 仿真问题，讨论过多三角形、过晚剔除、LOD、阴影和 GPU 水模拟成本 | 特定情形约 65% 地形提交几何随后因视野剔除；另报告提交三角中 40–60% 因屏幕占比太小被丢弃。口径不同，不能相加，也不是 RMMO 的数字。这说明天际线本身仍有优化空间。 |
| [City Corner #8 — Transforming the Terrain](https://steamcommunity.com/ogg/949230/announcements/detail/699893179027030812)，2026-06-11 | 岩壁三轴投影、独立光滑度贴图、纹理层级/混合及地形法线修正 | 画质改善不全靠增加面数；法线、投影与材质过渡值得优先检查。其性能改善声明没有给出可复现测试数字。 |
| [Patch 1.6.0f1 — Summer Solstice](https://steamcommunity.com/games/949230/announcements/detail/699893179027031260)，2026-06-22 | 游戏与编辑器加入纹理笔刷及旋转；调整笔刷尺寸与强度关系；纹理平铺细节层级由两级变三级；低纹理质量可减少地形 VRAM | **此处是纹理 LOD，不是几何 LOD。** 这是已发布补丁，区别于上一条发布前介绍。不要由此宣称其采用某种地形流式系统。 |
| [paavohtl：Why Cities: Skylines 2 performs poorly](https://blog.paavo.me/cities-skylines-2-performance/)，2023-11-05 | 原作者对 1.0.11f1 的帧捕获与代码观察，拆分渲染 pass、细节模型和阴影成本 | 可学习分析方法，不能当作 2026 年现状或标准性能基准。作者当时观察到的虚拟纹理路径还明确排除了地形，因此不能拿这篇文章证明“天际线地形用了虚拟纹理”。 |
| [Unity 6.0：SetHeightsDelayLOD](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/TerrainData.SetHeightsDelayLOD.html) | 局部写入高度时暂缓 LOD/植被更新，交互结束后同步 | 支持区分高频编辑反馈与低频派生工作；**这是独立引擎设计参考，不是天际线实现证据**，也没有授权我们延后必要碰撞校验。 |
| Losasso、Hoppe，[Geometry Clipmaps](https://hhoppe.com/proj/geomclipmap/)，SIGGRAPH 2004 | 观察点周围嵌套规则网格，随移动增量补充地形数据 | 为大范围近密远疏渲染提供论文依据，不直接解决洞穴、碰撞、撤销或实时编辑事务。论文帧率不可移作本项目目标收益。 |
| [Terrain3D 1.0.2 架构](https://terrain3d.readthedocs.io/en/stable/docs/system_architecture.html)及[作者性能说明](https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/performance.md) | 固定 clipmap 网格由 GPU 高度图位移，区域按需分配；纹理、植被、材质成本独立于网格成本 | 提供 Godot 侧可阅读的实现参考。检索时 main 文档仍把区域流送和 Runtime Virtual Texture 列为未来工作，不能将其当作现成完整流式替代品。 |

检索日期为 2026-10-15。Steam 个别单篇网页正文抽取不完整，#4、#8 与 Summer Solstice 正文进一步通过 Steam 官方 News API 的 `steam_community_announcements` 核对；标题、时间戳与查询入口保留于证据清单。没有取得足够一手资料证明天际线的笔刷 dirty rectangle、碰撞更新粒度、后台取消或原子发布协议；下文相关方案均为针对 RMMO 的设计建议。

## 2. 我们已经有什么，真正值得改在哪里

| 链路 | 当前代码事实 | 下一步判断 |
| --- | --- | --- |
| 作者数据 | [terrain_surface.gd](D:/code/rmmo/scripts/world3d/terrain_surface.gd) `MAX_CELLS=64`；一条记录保存高度、洞格、底床；雕刻支持平移、Y 轴旋转和缩放，拒绝 X/Z 倾斜；支持不同格距几何接缝。另有独立体积地形 | 保留 UUID 与现有存档语义。渲染分块可以是派生表示，不需要把作者对象拆散。高度场与体积地形需继续共存。 |
| 雕刻功能 | 已有隆起、下沉、整平、平滑、洞口/补洞、侵蚀，以及矩形宅基、河道非破坏改线、体积隧洞 | 这些不能再次列为待开发。当前公开 UI/MCP 中未发现两端定高的地形坡道笔刷、高度图导入或等高线覆盖层；坡度材质不等于坡道工具。 |
| 单笔计算 | [terrain_stroke_batch.gd:5](D:/code/rmmo/scripts/world3d/terrain_stroke_batch.gd:5) 先搜完整连通组，再逐块调用 stroke，两轮成对接缝处理，最后逐格复核差异；[terrain_surface.gd:141](D:/code/rmmo/scripts/world3d/terrain_surface.gd:141) 的升降/整平/平滑等路径对进入作用范围的样本复制高度并遍历整块网格 | 已限制单次连通组最多 256 块，但计算量不只取决于实际刷中的格子。侵蚀已有局部矩形及工作量上限，不能笼统称所有笔刷都无界。空间/邻接索引、样本局部范围和边界依赖是明确可研究的缩减点。 |
| 邻接与保护 | [terrain_neighbors.gd:16](D:/code/rmmo/scripts/world3d/terrain_neighbors.gd:16) 先扫描地形和边界，再按局部签名复用；[terrain_tools.gd:99](D:/code/rmmo/scripts/world_editor/terrain_tools.gd:99) 检查改变的体积，并遍历物件保护承托 | 已有缓存和精确保护。应减少候选遍历，保留普通物件接触细查、隐藏物件、锁定、保留区与跨缝校验。 |
| 派生网格 | [terrain_surface.gd:76](D:/code/rmmo/scripts/world3d/terrain_surface.gd:76) 重新生成整块顶面、底床/切边及可选垄沟；[world_editor.gd:790](D:/code/rmmo/scripts/world_editor/world_editor.gd:790) 已按受影响 UUID 和邻块刷新 | 当前是对象级局部刷新，不是格子级顶点更新。`SurfaceTool.index()` 后的输出不能未经证明就按格点编号直接写 GPU。 |
| 编辑器碰撞 | [picking_shape_cache.gd:10](D:/code/rmmo/scripts/world_editor/picking_shape_cache.gd:10) 缓存不可变网格的碰撞；新网格仍同步生成 faces / `set_faces`，供精确拾取及编辑器行走使用 | 每次雕刻更换网格会经过这条路径。它与运行时后台碰撞准备不同，是必须单独计时的阶段。 |
| 依赖更新 | [terrain_follow_tools.gd:19](D:/code/rmmo/scripts/world_editor/terrain_follow_tools.gd:19) 按 terrain_ids 选 follower，整条拟合并复核障碍；[terrain_brush.gd:30](D:/code/rmmo/scripts/world_editor/terrain_brush.gd:30) 已将城防重新冻结延至松手，失败整笔回滚 | 贴地铺面仍参与每次 dab；不能声称所有依赖已推迟，也不能把“城防松手更新”作为新优化。精确影响范围可减少无关重算。 |
| 渲染与材料 | 已有共享地面批次、后台 CPU 几何、派生缓存，合批使用高度纹理数组；[river_terrain.gdshader](D:/code/rmmo/scripts/world3d/river_terrain.gdshader) 已有三轴投影、坡度露岩和高度混合 | 天际线材质更新中的不少思路我们已经采用。下一步是检查近远采样成本与实际画质，不能重复开发已有功能，或只拿 draw call 降低证明整体性能提升。 |
| 历史与保存 | [world_document.gd:91](D:/code/rmmo/scripts/world3d/world_document.gd:91) 的 recovery snapshot 深拷贝记录和元数据；保存沿用现有原子提交/冲突检测 | 松手一次撤销已实现。若计时表明快照占比明显，再评估记录/地形区域差量历史；不先重写保存系统。 |

上述是静态代码事实，**还不能断言其中哪一项是当前最大耗时**。本轮没有生成新的性能数字。

另一个需要单独验收的边界：[terrain_neighbors.gd:7](D:/code/rmmo/scripts/world3d/terrain_neighbors.gd:7) 的法线及高度采样邻域兼容条件要求相同格距；跨不同格距的几何接缝虽然已经支持，却不等于这些视觉上下文也已统一。应区分几何裂缝、法线亮暗接缝和材质过渡接缝，先确认现状，再决定是否扩展兼容规则。

已有[地面批次历史测试](D:/code/rmmo/docs/world_editor_terrain_sculpt.md)曾在限定地面视口中将城镇绘制调用从 2972 降至 720，GPU 绘制中位数从 0.581 ms 降至 0.416 ms；同记录的首次后台构建仍出现 87.2 ms 峰值。它说明“稳定绘制”和“编辑/构建尖峰”必须分别测量，不能据此推定今天完整编辑器或游戏的帧率，也不能把已完成合批再次排进待办。

## 3. 推荐的地形编辑方式

### 3.1 保留连续笔刷，缩小每一笔触发的工作

可把派生更新组织为以下流程。这是 RMMO 候选流程，并非天际线内部架构图。

```mermaid
flowchart LR
    A[笔刷路径与参数] --> B[局部高度/洞格差异]
    B --> C[接缝、法线、材质采样邻域]
    C --> D[承托与道路等依赖校验]
    D --> E[版本一致的局部显示与拾取]
    E --> F[松手完成派生工作与单次撤销]
    F --> G[原生保存与重开]
```

“局部”必须包含完整依赖：平滑会读取邻点，侵蚀会跨迭代传播，混合格距边界可能牵动相邻边，当前材质上下文还有最多 8 m 查询及额外插值采样。不能统一写成“扩大一个格子即可”，也不能只凭笔刷圆心决定更新范围。

交互按路径距离采样的现有强度语义保持不变。减少鼠标事件处理次数时仍须重放同一有效采样序列，尤其不能把 smooth/erode 简化为只处理最后一个点。天际线补丁中的尺寸/强度调整可启发新预设，但不能悄悄改变已有 MCP 参数含义。

### 3.2 补“采样标高 → 两端坡道 → 坡度预览”这条创作链

这是比扩大笔刷种类更贴近当前内容制作的功能补充：从现有地面取目标标高；在两点之间定义起终高度和宽度；实时展示坡度、接缝、挖填范围及被影响物件；通过同一地形业务提交。

已有道路贴地会对超过允许坡度的结果拒绝，而不会自动替用户削坡。新工具可让用户明确塑造桥头、院门及坡地通道，再由既有道路/承托保护判断是否有效。不得全图自动整平，也不得绕过锁定、保留区或把桥下空间填实。两端坡道属于新功能，应同时提供当前 3D MCP schema、预览/提交与撤销保存验收。

等高线/坡度覆盖层可作为该工具的反馈；高度图导入则作为以后扩展大地貌的独立入口，先定义米制尺寸、垂直基准、精度、跨块边界及数据预算。仅导入 4096² 图片不能使现有编辑链自动具备高性能。

### 3.3 区分地形轮廓、表面细节和物理精度

近处需要真实可走地形、洞口和细节；远处主要需要轮廓、河岸线和稳定光影。几何 LOD、材质采样 LOD、纹理驻留和碰撞范围应分别设计、测量。更换远景材质不能降低近处碰撞精度，减少可见面数也不保证降低 VRAM。

我们的城镇包含第三人称通行、桥洞、切边与体积洞穴，不能全部压成一张高度图。较稳妥的演进是先给既有派生地形增加可验证的局部更新/远景表示；若后续尺度与测量证明需要，再对普通开放高度场试验 clipmap，复杂结构保留现有表示。

## 4. 下一轮工作包与进入条件

| 工作包 | 具体交付 | 进入/验收条件 |
| --- | --- | --- |
| **T0：建立地形编辑基线** | 同一路径分别记录拾取、连通组、stroke、接缝、承托/依赖、邻接上下文、arrays、shape、批次发布、松手历史的耗时；另记输入到预览、松手到可保存/试玩的延迟 | 这是首选启动项。区分拖动、松手、静止俯瞰、低空行走；保存场景/资源/代码身份及渲染设置。得到数据后才选后续瓶颈。 |
| **T1：局部候选与采样计算** | 缓存地形邻接和空间候选；遍历刷迹实际涉及的格点，保留所需边界/传播闭包；为物件及 follower 查询提供空间候选 | 与现有路径逐例比较作者数据及失败语义；移动、删除、撤销、重开后索引正确失效。扩大地图但保持相同局部编辑时，工作计数不再随所有远处记录线性增长；超时不能削掉校验。 |
| **T2：局部显示与编辑器碰撞** | 先试固定拓扑路径的顶点/法线/切线局部更新或有界派生小块；为拾取碰撞准备和发布设置明确粒度、版本与就绪状态 | 仅在 T0 证明 mesh/shape 是热点后开展。洞格变化、垄沟等派生拓扑变化保留整块回退；新增粒度须比较 CPU 收益与批次/GPU 增量。下一次笔刷不得打在过期碰撞上。 |
| **T3：近远渲染与材质成本** | 对高空俯瞰、低空近景分别比较地形几何、阴影、河岸材质、多层纹理采样与驻留；选择地形 LOD、材质远景简化或受控代理 | 以实际 GPU pass/几何/纹理计数为依据，不默认都做。保留岸线、洞口、接缝、法线、地形与道路衔接；合批剔除范围不能大到抵消收益。 |
| **T4：坡地创作工具** | 采样标高、两端坡道、坡度/冲突预览，复用现有保护及事务 | 可独立排期；UI 与当前 3D MCP 共用实现，增加真实 HTTP 验证。内容功能收益与性能收益分开记录。 |

**建议顺序：T0 → 选择有证据的 T1/T2；T3 由 GPU 证据决定；T4 作为内容制作补完独立安排。** 暂不把替换 Terrain3D、重写 ECS、虚拟纹理、全城水模拟列为前置条件，也不直接提高 `MAX_CELLS` 或连通组上限。

T2 的实现需特别处理三点：

1. [Godot ArrayMesh](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html)支持区域更新，但我们仍要建立稳定的格点→渲染顶点映射，处理法线/切线、AABB、缓存版本、材质高度上下文及合批失效。不能修改共享不可变缓存来影响其他来源。
2. [线程安全约束](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)继续适用。worker 处理私有 CPU 数据；活动节点与物理/GPU 发布走适当线程及边界。复用现有地面批次的 generation 检查和缓存失效，扩展交互任务所需的文档 epoch、源版本和笔画身份；撤销/取消/新笔画后迟到结果不能覆盖新状态，队列必须有上限。
3. 若延迟碰撞发布，笔刷拾取必须切换到同版本 CPU 高度/三角查询，或等待该区域就绪；试玩也要等待正确物理状态。桥、洞口、体积地形不能只用单值高度采样。现有同步 `sculpt_terrain` 成功语义不能静默改成“后台任务刚开始”。[HeightMapShape3D](https://docs.godotengine.org/en/4.7/classes/class_heightmapshape3d.html)可作为规则顶面的对照候选，但底床、切边、洞穴及非均匀缩放需单独适配，不能一键替换所有三角碰撞。

## 5. 如何证明优化有效

首次试验只用临时地图/资源包：少量规则地形、相同局部区域加大量远处记录、不同格距接缝、带洞口/垄沟与河岸材质、带道路/草根承托的局部场景。固定采样路径及初态，分别测冷缓存和重复编辑；避免用更平坦或少了保护对象的样例冒充同条件提速。

- **响应指标**：拖动及松手分别报告 P50/P95/P99/最大帧耗时、输入到可见反馈、松手到派生完成；同时记录总工作量和待发布队列，防止只是把卡顿移到松手后。
- **CPU/GPU 区分**：记录实际受改格点、访问候选、重建 mesh/shape 数、上传量、draw call、三角形、GPU pass；分别报告进程内存、renderer 计数与保守预算，不能互称实际 RSS/VRAM。计时目标由基线和目标设备确定，不预报收益倍数。
- **正确性**：同路径的作者高度/洞格等价；混合分辨率和 T 接缝无裂缝；越界、锁定、隐藏、保留区、草根承托及道路超坡失败无副作用；Esc/撤销/重做、保存重开、过期任务取消一致。浮点顺序确需改变时先约定误差，不能未经检查放宽旧保护。
- **视觉与通行**：同相机、灯光、曝光检查近中远、岸线/洞口、法线和阴影；第三人称坡面/路面接缝真实可走；渲染就绪不能替代碰撞就绪。GPU 测试继续使用 `tools/run_godot_background.py`，不抢前台，截图遵守质量 90 有损 WebP 及隐藏人像约定。
- **既有回归入口**：`tools/test_terrain_cross_tiles.gd`、`tools/test_terrain_neighbors.gd`、`tools/test_terrain_house_plots.gd`、`tools/test_terrain_prop_contact_http.gd`、`tools/test_terrain_follow_paint_http.gd`、`tools/test_ground_cpu_mesh.gd`、`tools/test_world3d_ground_batching.gd`；复用相关项，新增异步/局部更新才补对应测试。本轮没有执行这些测试。

本研究作为[无缝转场计划](D:/code/rmmo/docs/seamless_streaming_optimization_plan_20261014.md)的独立地形方向：可复用测量纪律、任务版本和有界发布原则，但编辑笔刷与传送加载具有不同热路径。地形试验不依赖传送演出、不默认打开原计划里的实验开关，也不重开全部历史性能专项。
