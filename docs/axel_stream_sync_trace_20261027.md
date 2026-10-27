# 隔离地图 Stream.sync 长帧追踪（2026-10-27）

`isolated_axel_dds_samples_01/sync_trace45` 使用 A 状态的私有地图、私有用户目录和后台桌面，对 `white_native_return` 单段开启方法追踪。结果为 `complete_leg`、丢失事件 0、失败项为空；地图、候选、代码、引擎与设置前后检查一致。逐文件哈希会预热系统文件缓存，本次是诊断采样，不是冷启动或无探针的帧率基线。

主线程两个最大 `Stream.sync` 分别为 82.010 和 92.657 ms，处在 117.356 和 123.416 ms 帧中，包含 `_sync_work → _apply → _spawn`。这几个范围互相嵌套，不可相加，也不能将总时间归给单个对象。对应对象 `obj_320` 和 `obj_347` 实测 shadow build 分别为 3.118 / 2.854 ms，restore 为 2.117 / 3.997 ms。

两条链存在数段 22–32 ms 的未细分间隔，与 `STREAM_VISUAL_SLOW`、`STREAM_SPAWN_SLOW`、`STREAM_SLOW` 等同步打印位置对应；另一次 `WHITE_TICK_SLOW` 前后的时标相差约 25 ms。同步日志可能层层放大计时和帧时，但事件结束与追踪锁获取不在同一时刻，也不能排除调度及其他未细分工作。需要在同引擎、同路径、同探针下只切换这些打印再复现，不能凭相关性当作根因。

测试夹具 `profile_axel_game_pipeline.gd` 会主动给地图节点设置 `profile_frame`；目前未发现正式游戏代码给地图节点设置该元数据的调用。测试宿主还包含最高 14.859 ms 的队列观察；对照若改善，只能先证明诊断开销，不能冒称正式游戏帧率收益。

独立于此，追踪到一次 `demand.rank_candidates` 22.077 ms，包含 `collect_candidates` 21.183 ms（1949 输入、798 候选、52 support visits），另一次 20.030 / 18.852 ms（2300 输入、861 候选）。这些也是带探针的墙钟时间，不与嵌套时段相加。B1 卸载 128.276 ms 样本没有邻近的长 `Stream.sync`，仍需独立归因。

## 同步日志隔离 ABBA

`slowlog_abba_A1/B1/B2/A2` 使用同一个私有 A 状态资源、同一引擎、路线和追踪标签，保留 `profile_frame`，只切换所列同步慢日志；各自为新建私有用户目录。四轮 804 个源码 SHA 完全一致，每轮前后 fixture、源码、引擎与设置检查一致，完整返回阶段且追踪丢失 0。文件检查预热 OS 缓存；带追踪、使用探针宿主，不是正常游戏或冷启动 p95。

| 样本 | 慢日志 | 返回最大帧 ms | 返回 >50ms 帧数 | 同阶段 sync 最大 ms | sync >50ms 数 | full-ready s |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| A1 | 开（67 条） | 113.780 | 3 | 82.796 | 1 | 13.160 |
| B1 | 关（0 条） | 35.895 | 0 | 12.333 | 0 | 12.737 |
| B2 | 关（0 条） | 54.189 | 2 | 11.074 | 0 | 12.911 |
| A2 | 开（63 条） | 228.780 | 3 | 103.004 | 3 | 14.463 |

此对照支持同步慢日志制造或放大本测试中的 `sync` 长尾，但 B2 仍有两帧 >50ms，不能归结为唯一原因。`sync` p95 依次为 4.006、4.135、4.840、4.181 ms；最大值与少数极端帧不代表整段普遍耗时。四轮 GPU surface 3943、textured 1502、unique 145，native 均回收 3677 specs / 504 units；asset retired specs 为 1080 / 1081 / 1048 / 1000，工作量并非完全一致。日志主要由夹具开启，不能声称这些数据直接证明正式游戏帧率收益。原始数据位于 `D:/code/rmmo_runtime/review_artifacts/isolated_axel_dds_samples_01/slowlog_abba_*`；分析脚本 `slowlog_analyze.py` 与所有慢样本保留在同一外部目录。

按引擎 tick 时标和主线程关联，B2 返回两帧 54.189 / 53.738 ms 分别包含 `demand.rank_candidates` 35.115 / 38.938 ms，其中 `demand.collect_candidates` 33.773 / 37.798 ms（输入 2835→1169、2202→1146）；对应 `sync` 只有 2.587 / 1.995 ms。同帧还有 `demand.rebuild_dispatch_catalog` 8.562 / 6.528 ms；rank 包含 collect，墙钟范围不可盲目相加。`deferred_bookkeeping_us` 是最近状态而非同帧独立时标，不能将其当成单独时间块。A2 228.780 ms 帧内 sync 为 103.004 ms，内含 `_sync_work` 102.939、`_apply` 74.980、`_spawn` 53.802 ms，后者包含 obj_347 restore 2.703 / shadow 3.260 ms，附近有四条连续同步慢日志。该帧 geometry tick 221.221 ms，sync 后仍有约 118 ms 尚未解释，不能全部归因于日志或 GPU。`slowlog_frame_association.py` 保存同帧关联方法；前一帧 draw/process 不能当当前帧数据。
