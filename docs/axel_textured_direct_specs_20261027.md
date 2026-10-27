# 纹理原生预制件的直接实例描述（2026-10-27）

接续 §176 / `82198015`。证据目录（T）为
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/textured_direct_specs_20261027/`。
性能口径为地图加载开始至当前需求完整就绪；不改变画面、地图、容量或任务预算。

## 定位及合同

§176 的 origin 官方 profiler 对 `WorldDocument._mesh` 记录 1135 次；原有
`PrefabSpecPreparation` 仅支持白模。纹理模式的无单独表面涂装 box prefab 在几何
已发布后仍创建 MeshInstance3D、读取其 transform/material/collision 等字段、再销毁。
实际后续生产 spec 仍绑定此前发布的 CPU mesh 和材料，不需要临时节点作为 owner。

`PrefabSpecPreparation.supports` 新增显式 textured 参数，默认仍按旧白模门槛；
调度器仅在加载不可变、可信包且当前 job 未持有 `streamed_texture_owners` 时传入。
存在 record 纹理 handoff 时沿用 `_begin_record_texture_scope → _mesh`，保留该 scope
的 ticket 验证、owner 恢复、可能的代际失效及重新读取；严格校验和可编辑文档也
沿用旧路径。原先白模 direct 的合同不变。显式表面涂装、asset、局部碰撞收集、
未准备 CPU mesh 及需创建 BoxMesh 的碰撞 source 仍回退。

这次仅避免主线程上的临时节点；`project_fields` 此轮仍在主线程运行，并未声称已将
它转移到 worker。候选的纯 record/bounds 投影若下轮转到后台，必须计入现有任务的
准入和内存预算，保留取消/重试；在绑定时重新核对 record、draw order、最终 canonical
mesh bounds 和 material owner，以免缓存合并后绑定过期的 fields。不能简单将资源
对象创建、GPU提交或 scene tree 工作丢给任意线程。

## 先复现及独立回归

`unit01_before` 在原 production gate 下其他 45 项通过，仅“纹理支持直接投影”失败；
固定2048件老路径访问并释放2048个节点，新投影为0，墙时老180.130/198.458ms、
新60.312/53.985ms。该微测独立于真实地图，不能换算整图或单帧收益。

`unit02_after` 有一项测试断言错误：非 immutable 的编辑路径本来会 restore 和重新
capture 独立 CPU 包装对象，不能要求它与不可变 canonical wrapper 具有同一身份。
`unit03` 保留测试脚本推断类型失败；不把它们当生产问题。修正后 `suite04`：
纹理54、白模80、材质46、prepared材质86、共享图片39、scheduler16项均通过，
每项退出0、源码及测试SHA不变。纹理 fixture 覆盖真实双slot、有alpha/法线/粗糙度、
共享AO与albedo、旋转楼层、门扇不同开合及碰撞模式；真实 `_spawn` 使用同一
mesh、material及texture owner。另直接调用调度器，验证 trusted/immutable 正向选择
与严格、可编辑、带record纹理owner的三条回退；保留 collision source。
最终独立 ABBA 为旧162.272/147.402ms、新41.778/46.561ms，均2048次。

独立审查发现 scheduler fixture 原本使用已驻留 prefab 和空 packet，未验证纹理
分片时实际代际交接。补充 `unit08_generation` 后，prepared material GPU 测试
**97 项通过**：真实调度器完成第一个纹理分片后，另一个消费者发布替代源代际、
清掉热/弱目录并恢复源文件；续跑通过 direct 路径绑定正确的 canonical mesh、
原代际 Texture 和精确 GPU 像素。另令 job 持有旧 streamed owner、新 packet，
确认走原节点/record scope、丢弃旧 owner 并绑定新代际；无效 resident ticket
被 record scope 拒绝且作用域未泄漏。该测试使用临时目录，退出0，无脚本/引擎
错误，生产源码和测试文件 SHA 不变。


## 真实地图对照

map05 ABBA：A 禁用 native prefab direct，B 保持默认；都沿用 §176 的 combined
material scope 和 §175 的面复用。私有桌面、新进程、普通优先级、不清 OS 缓存；
不是严格无缓存冷 IO。所有功能断言通过、无错误，源码及地图 SHA 不变，收尾时
地图、共享图片及配额释放；没有截图替换或改动用户地图。单位为秒、FPS、毫秒。

| 样本 | 入口 | 完整就绪 | 返回 1% low | 重载 1% low | 卸载 / 返回 / 重载最大帧 |
| --- | ---: | ---: | ---: | ---: | --- |
| A1 旧 | 4.329 | 11.240 | 36.637 | 34.826 | 31.516 / **51.334** / 37.765 |
| B1 新 | 4.210 | 9.995 | 36.052 | **24.742** | 49.687 / 43.807 / **53.988** |
| B2 新 | 4.015 | 9.994 | 33.067 | 35.841 | 44.155 / 43.941 / 41.216 |
| A2 旧 | 4.054 | 12.585 | 34.166 | 37.287 | 45.179 / 40.463 / 45.693 |

A1 返回 1 帧超过50ms；B1 重载 2 帧超过50ms（53.988、52.128ms），其他列出的
阶段均无 >50ms 帧。B1两个峰值无 queue observer 采样，最近的 previous process
wall 为34.343/44.363ms、previous draw wall为19.804/7.811ms；这些是阶段墙时、
可能跨边界，缺原生栈，不足以证明原因或归为系统空闲。B1的重载 draw calls≥2000
的观察时间约3.812s，其他三条约1.621–2.003s；工作/画面轨迹不同，不能将 low 差异
简单归因于 direct。其余样本仍保留，不能计算可靠p95或声称帧时间稳定改善。

两条 B 完整就绪较两条 A 快，但单组四次、且当前场景和同机负载会波动，不足以
证明稳定低于10秒或将秒级差值全部归给这个微优化。B1/B2 的就绪在 origin 观察期，
分别为9.995/9.994s；A2 超出8秒 origin观察窗口，进入需求 settle 后12.585s就绪。
就绪定义是实际需求/任务/合批及共享图片连续三帧清空，观察窗口不是就绪计时器。
所有初始样本均为231 builds / 3923 prepares / 2724 packs、229 groups / 2564 sources /
361 surfaces；GPU audit 均为3943 surfaces、3202 nonwhite、1502 textured、145 unique
textures，仅证明审计范围内绑定正常，不能覆盖全部外部模型材质。实际测试环境观察到
其他应用，不能凭进程存在确定干扰来源。

正常引擎就绪附近的采样 A1/A2 未启用 direct，B1/B2分别观察到154/141个直接实例，
`instance_nodes_avoided` 比各自 A 的417增加至571/558（采样点在就绪附近，不保证
相同帧）。官方 profiler 为独立插桩诊断：§176 `origin_official07` 对比本轮
`origin_official09`，入口 `_mesh` **1135→1013**、`House.visual` **748→626**、
`WorldStream._spec` **1866→1744**，均少122次；`_publish_prepared` 仍748次，
新增 direct `project_fields` 122次。统计可确认这些重复节点工作被移除，插桩累计
耗时不能直接当普通游戏时间。两次诊断的引擎、接收、解码均成功，地图/源码未变。
`verification07.json` 和 `map05_sources/` 保存796个测量源码；完整指标、最慢帧和
官方调用量分别见 `analysis06_summary.json`、`analysis06_peaks.json`、
`official10_compare.json`。

## 后续范围

用户于 2026-10-27 补充：完成游戏材质加载优化并验证后，需要适配、优化内容编辑器
的对应资源导入与材质流程，验证 3D MCP、编辑/撤销/保存语义和性能；游戏侧的当前
结果不能代替该编辑器交付。首次呈现、需求刷新、回收和旧无栈 AV 仍分别追踪。
