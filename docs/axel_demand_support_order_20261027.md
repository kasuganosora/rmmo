# 需求刷新中的支持关系查询顺序（2026-10-27）

## 原因与修改

返回加载诊断的 B2 样本中，两次分别 **54.189 ms** 和 **53.738 ms** 的观测帧内，主线程 `demand.rank_candidates` 分别为 **35.115 ms** 和 **38.938 ms**，其中嵌套的 `demand.collect_candidates` 为 **33.773 ms** 和 **37.798 ms**。同帧 `Stream.sync` 分别为 2.587 ms 和 1.995 ms。这些是包含调用和探针开销的 wall time，嵌套数据不能相加；高速度几何焦点遍历也不是实际玩家行走。

本次只交换 `deferred_asset_loader.gd` 中逐候选的两次支持关系检查：先判断 `_runtime_building_supports.has(uuid)`，再查 `support_priorities`。仅在支持关系存在时，本轮同步刷新才会向 `support_priorities` 写入该 UUID；不改变候选处理顺序、评分、support 推广、发布或优先级。该修改不依赖上次已撤回的跨刷新分数缓存。

工作量不能只计算省掉的一侧：令 **U** 为到达检查且没有支持关系的候选数，**P** 为旧顺序中已由足够高优先级处理、因而提前跳过的候选数。换序少做 U 次 `support_priorities.has`，但多做 P 次 `_runtime_building_supports.has`，总字典查询净减少 **U − P**。支持建筑占比很高且 P 超过 U 时，净工作量可能反增；不同字典查询实际成本也不一定相同。

## 独立语义和 ABBA

两个完全隔离的 Godot 项目，仅 loader 的两行顺序不同。相同的 24 组状态覆盖空支持集合、多个父建筑共享支持、多优先级顺序、已发布项、scope、实例错误和同 UUID 不同 owner；比较完整候选顺序、路径组与首项、rank、priority、dispatch 与 owner 身份特征，A/B 结果一致。每个试验内部 3 组，每组 48 次刷新；每组的候选行数、距离计算、支持访问、推广和调度写入等已有计数相同。

| 次序 | 48 次刷新耗时（ms，全部三组） | 组均值（ms） |
| --- | --- | --- |
| A1 原顺序 | 1705.714 / 1837.015 / 1770.853 | 1771.194 |
| B1 换序 | 1665.275 / 1663.099 / 1688.618 | 1672.331 |
| B2 换序 | 1738.178 / 1697.724 / 1659.231 | 1698.378 |
| A2 原顺序 | 1727.212 / 1616.895 / 1610.771 | 1651.626 |

这组结果有波动，最后原顺序快于两组换序，**没有证明稳定耗时或帧率收益**。数值为合成 CPU 基准，不是整图加载时间、玩家行走 FPS 或冷启动 p95。

另建带计数的隔离审计副本，不将其耗时用于比较。每组 48 次刷新，实际到达支持检查 **244,800** 次，其中 U = **220,800**，P = **0**；因此此合成工作负载下总字典查询由 **489,600** 降至 **268,800**，净减少 **220,800 次**。三组一致，审计结果与原版的 24 组状态和原有工作计数一致；此结果不代表真实地图的 U、P 或净收益。

引擎 SHA-256：`40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`。两份独立项目的 2,797 个快照文件仅 loader 不同，试验前后各自不变；独立类缓存 SHA 一致 `993c13fc6350351025b2b6e332bbb4ba6348882f1c67bfe944e00d24b84f3896`。隔离工程使用独立用户环境，没有触碰实际地图与资源包。

## 正式代码回归

- `test_support_promotion_dedup.gd`：24 项通过，新增空支持、优先级增强及减弱、确定的距离排序、published 和现有 alias 回归。
- `test_demand_score_pruning.gd`：26 项通过。
- `test_deferred_typed_demand_scan.gd`：60 项通过。
- `test_demand_candidate_catalogue.gd`：211 项通过。

以上四个 headless 日志均无脚本或引擎错误，共 **321 项通过**。首次新增测试错误地预期两个相同优先级候选的顺序，忽略了从 demand clip 中心计算距离；该项失败后更正为现有实际排序，重新运行上述全部测试通过。失败日志保留。

### 返回刷新测试的旧阈值与 oracle

额外运行既有 `test_demand_return_refresh.gd` 时，正式源码和隔离副本均出现 **111 项通过、2 项失败**。该测试编写时使用 4 米排名更新阈值，而现在 `prioritize()` 采用 32 米阈值：原测试在同一分块内只移动到 x=4–28 米，故实际刷新 **0 次**，原断言的 24 次刷新已过时。

另一个失败来自原 full-scan oracle：移动后 `_priority` 已更新，但未达到重排阈值，原快照仍反映此前排序；强制 full scan 又按当前 `_priority` 重新排序，比较的输入位置并不一致。修改测试：先在当前坐标强制刷新优化路径，记录完整输出和 owner，再用同一坐标强制 full scan；恢复优化开关后再次检查坐标、UUID、排序、路径、首项、rank、priority 与准确 owner。

同区块的 rank 测试改为先预热，再在 `(4,4)` 和 `(28,28)` 之间交替；二者在同一区块，距离约 33.94 米，实际 **24 次刷新、membership miss 0 次**。另断言 31.999 米时 anchor 和 revision 不变，32 米时 anchor 更新且 revision 增大；32 米同时跨区块，因此不假设 revision 只增加一次。修复后以 `--expect-current-invalidation` 运行 **120 项通过、0 失败**，stderr 无脚本或引擎错误。修正仅改变测试，既有无关 requeue 触发全量刷新问题仍在，不能据此认为需求刷新性能问题已解决。

## 证据与限制

独立实验、完整 4 轮原始输出、源文件哈希、审计脚本及其结果位于 `D:/code/rmmo_runtime/review_artifacts/support_order_review_20261027/`：

- `run_clean01/summary.json`、`1_A.json`、`2_B.json`、`3_B.json`、`4_A.json` 与同目录 `.log`：完整顺序、耗时、状态和代码哈希。
- `net_work_audit.json`、`net_work_audit.log`、`run_net_count.py`：U、P 实测及语义一致性；该副本的时间无效。
- `test_*.log`：正式代码四项测试；`test_support_promotion_dedup_initial_failure.log` 保留首次预期错误。
- `test_demand_return_refresh_fixed_confirm.log`：返回刷新测试修正后的复验；旧 111/2 日志保存在 `D:/code/rmmo_runtime/review_artifacts/demand_ticket_overlay_user_20261027_05/test_demand_return_refresh_original.log`。
- 根目录 `1_A.invalid.txt`、`1_A.log`：早期重叠尝试缺少类缓存而报编译错误，已作废，不是上表的 `run_clean01/1_A`。当时误结束了另一个 agent 的 Godot PID 50496，该进程是其隔离类缓存初始化，返回 4294967295，初始化样本无效；重叠尝试也不用于性能结论。后续测试由主 agent 排程，清理并隔离后才运行 `run_clean01`。

后续 `requeue_abba` 与 `requeue_private_abba` 真实隔离地图已包含此换序，但 A/B 两组均启用，**没有对它单独做地图时间收益归因**。本项只证明合成工作负载减少查询及语义回归通过；不能据此称 axel_town 的加载或 1% low 已改善，也没有完成材质、编辑器或 3D MCP 的后续工作。
