# 编辑器完整碰撞重复准备与关闭重上传

本轮继续完成编辑器适配，未开始 4.8。编辑器整张文档打开与游戏当前需求区域就绪是不同口径；下面不改写此前游戏加载成绩。正式地图和生产素材不变。

## 定位证据

外部根：`D:/code/rmmo_runtime/review_artifacts/editor_full_map_20261028_01/`，候选引擎沿用 SHA `3d65b357ac8a14b8bf04b3a162d7dfea74eb0550ffb10a5a26764cea21958066`，未安装默认位置。

`profiler_01` 使用官方脚本/native/visual 协议和已验证的 caller attribution 模式，2431 帧、3447 个签名。调用行包含后台线程，嵌套时间不能相加为主线程关键路径。接收器报告一次 warnings overflow 与 **78 条消息丢失**，解码 exit 1，完整输入保留；不能称完整无损 profiler 样本。

观察到关闭帧约 1324ms，包含 `GroundBatcher.restore` 2508 次、`ArrayMesh.add_surface_from_arrays` 1086 次。它们是已收到的调用观察值，不代表关闭时间全部归因于上传。测试用 weak picking probe 另观察到 12137 次形状查询、3500 次 miss、118 次已有存活 shape 被容量淘汰后重建；该 probe 在 miss 时提前计时一次展开，不用于正常性能成绩。

GDB 18.1 只附加经 PID/路径确认的本轮进程：

- `gdb_01` 的 all-stop 导致测试 HTTP 10 秒期限超时，实际地图未加载；保留为夹具失败，不当作生产失败或有效整图栈。
- `gdb_02` 把诊断 RPC 期限扩为 500 秒后完整加载/关闭成功，161 个样本主要覆盖启动 UI/系统字体；未捕获拾取/关闭关键栈，不能声称这些栈已定位。
- `gdb_close_01` 在关闭前输出 marker 并等待 2 秒供附加，34 个主线程样本。seq 14–17 实际包含 `Node::_propagate_exit_tree → Object::emit_signalp → GDScriptFunction::call → ArrayMesh::add_surface_from_arrays`。脚本名称未由 pretty-printer 解码，具体脚本对应由官方 profiler 和源码交叉确认。另观察到容器释放与 dirty instance 更新；没有把其余关闭成本视为已解决。

这些调试时间均不进入正常收益比较；带门控等待的关闭样本也不作延迟成绩。

## 两项修复

`LoadJob._add_record_bodies` 原来先生成完整三角面/完整 Concave shape，随后 `_add_bodies` 对同一地形使用 `TerrainLocalPublish.initialize` 的分块 shape，前者被闲置。现在与实际 initialize 复用相同 `can_initialize` 判定，仅确定会走分块路径时跳过完整准备。带涂面、grade、furrows、不支持的 surfaces 或关闭 local 功能时保留原回退。新增前置 CPU-owner 查询有成本，不宣称零代价；它与后续 initialize 之间此分支没有 await。

直接销毁编辑器时，子树退出先于 editor `_exit_tree`，批次成员的退出回调会恢复整组其他成员；只判断成员自身 `is_queued_for_deletion()` 无法识别其即将销毁的父节点。现在 editor 在 script PREDELETE、Node 移除子树之前收集实际后代成员 ID，传给既有 `_drop` 的 retiring 机制。先断开回调，销毁批次，但不重建这些源的 GPU 网格。外部存活成员仍恢复；没有全局关闭标志，不改变普通 remove_child/reparent 语义，也没有同步 join worker。

## 独立复现和回归

`test_editor_local_terrain_picking_http.gd` 经真实 HTTP 保存/打开 64×64、含大量洞口的地形。

- `local_picking_red_02` 28 项中 **4 失败**：local 模式多出完整三角面、完整形状缓存、一次整形准备和一个闲置 worker。
- `editor_work_green_02` **37/0**、无错误：local 模式上述四项归零；关闭 local 时仍恰好一次 worker/整形准备。分块三角形多重集与独立完整几何一致，拾取和 WALK 层表面/洞口一致，HTTP 保存成功；涂面、grade、非标准 surfaces 继续走回退。
- 更早 `local_picking_red_01` 夹具误用了超过现行 schema 的 96 格，保存失败后继续访问不存在的 build 字段并超时。修正为合法 64 格及保存失败即退出；不把夹具问题称生产缺陷，也未因此更改地形尺寸协议。

`test_editor_batch_shutdown.gd` 使用真实 WorldEditor、真实批次与 `PreparedCpuUpload` 的 opt-in 调用 hook。

- `batch_shutdown_red_01` **4 失败**，queued/direct/重新挂载后销毁均恢复 3 个将销毁成员；含一个外部存活成员时也恢复全部 3 个。
- `editor_work_green_02` **27/0**、无错误：上述内部恢复 **0**，跨子树案例只恢复 **1** 个外部成员；普通移出仍恢复全部 3 个并能重挂重建。部分加载中的真实 worker 能排空；历史悬空成员先检查有效性再使用，未产生类型强转错误。
- 既有 `test_ground_batch_lifetime` 在 `editor_work_green_01` **37/0**、无错误，覆盖普通成员删除、存活源恢复、在飞任务、替换代际、预算和已有 retirement 行为。

green 02 的脚本、生产源码与引擎均纳入前后 SHA 清单。较早 runner 的通配符未覆盖不含 texture 字样的新测试文件，旧红样本的 identity 清单只冻结生产源码/引擎等原有项；已修正 runner 显式加入每条命令指定的测试脚本，未改写旧清单。

## 边界与后续

正常整图 `picking_shutdown_abba_01` 完成 A/B/B/A；A 为 `1a9dfafd` 的四份旧生产文件，B 为最终候选，收尾已按原字节恢复 B。每轮原地图/验证副本/1065 个依赖、源码和引擎身份前后不变，2369 条记录，0 脚本/引擎错误，已观察的预算/退役队列归零。

| 样本 | LoadJob 秒 | HTTP 到就绪观测秒 | 完整形状准备调用 | 关闭至排空 ms | 关闭最大帧 ms | 关闭 >50ms 帧 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A1 sample_06 | 47.125 | 51.366 | 6100 | 1788.058 | 1364.888 | 2 |
| B1 sample_07 | 43.899 | 47.642 | 6037 | 1348.934 | 1012.032 | 1 |
| B2 sample_08 | 49.684 | 53.669 | 6037 | 1303.755 | 974.581 | 1 |
| A2 sample_09 | 51.889 | 56.269 | 6100 | 1630.753 | 1276.146 | 2 |

真实地图确定减少 **63 次闲置整形准备**；本地图 43 个大面展开任务不变，不能把独立高密度洞口夹具省掉的 worker 外推到此地图。模型/纹理预备队列仍为 60 个启动、0 重排，未增加重复加载。B 的完整形状准备合计约 5.04–5.07s，A 5.60–6.21s；各阶段包含关系与并行关系仍保留，不加算为总加载收益。

关闭最大间隔两次都下降约 0.3 秒，但仍约 **1 秒**。总加载 A/B 范围重叠，B2 的 picking capture 从 B1 的 3.92s 波动到 6.75s，因此只报告这组观测，不宣传稳定总耗时倍率或 p95。整个加载观察窗口 >50ms 帧数 A 为 58/73、B 为 68/69，最大间隔 A 4.14/4.26s、B 3.61/3.83s（均包含 Job 启动前）；**没有证明编辑器加载低帧或全部长帧已解决**。保留已验证的工作量减少与关闭收益。

销毁优化针对 editor 直接 queue_free/free。整个子树先移出再销毁、SceneTree finalize 等仍可能先发生源退出；普通移出必须保留可恢复语义，未一概关闭恢复。程序整体退出与编辑器回到游戏也应按实际入口分别评估。

拾取 shape 仍有容量淘汰后的重复烹饪，单个大型 shape 的 native 构建和资源最终释放仍可能形成长帧。本轮不增大缓存/worker/帧预算，不把未观察到的路径宣布解决。正常整图 A/B/B/A 在同一验证副本协议下执行，复制和 SHA 会预热文件缓存，不称严格冷启动。
