# 白模初始加载 cover、32ms covered budget 与 slow-source yield（2026-10-24）

范围：axel 白模 full-ready；不恢复纹理、角色、HUD、Recast。验收口径为
`origin_first_ready`：当前 demand、job、stream 和 render-batch 连续三帧为空，
不是入口 `AXEL_MESH_READY`，也不是完整游戏 FPS。

## 最终结果

最终源码（32ms covered budget + 10ms slow-source yield + 按帧 demand removal
+ 分组 index preparation）：

| 口径 | N | full-ready median | p95（=max） |
|---|---:|---:|---:|
| warm | 10 | **6.764 s** | **6.918 s** |
| cold-index 普通优先级 | 10 | **7.550 s** | **7.918 s** |

N=10 的 nearest-rank p95 就是最大值；warm/cold 两种口径现在都低于 10s。
2026-10-25 已从 `prepgroup_load_10_20261025` 的20份原始报告复核这些值；它们是
当前需求队列完整就绪时间，不是固定观察窗口结束后的撤罩时间。后续剩余问题修复
与验证见 `docs/axel_white_remaining_20261025.md`，不把旧样本回写成新版本成绩。
`_remove_published_demand` 改为在 `_publish_ready` 末尾按批处理：1514 个需求
一次移除，per-unit remove 从约 0.097s 降到约 0.002s，批量 remove 约 0.062s。
warm 9.937s 是单次 9.936s 样本，p95 仍是最大值；不把 median 当 p95。

历史口径（24ms/旧样本保留，不与最终 32ms 混算）：

| 口径 | N | full-ready median | p95（nearest-rank） | max |
|---|---:|---:|---:|---:|
| warm 索引，24ms，无 yield | 10 | 7.30 s | **10.728 s** | 10.728 s |
| cold-index，24ms，无 yield | 10 | 8.15 s | **8.980 s** | 8.980 s |
| warm/cold 混合，24ms + 10ms yield | 10 | 7.47 s | **8.138 s** | 8.138 s |
| warm 索引，32ms + 10ms yield | 10 | **6.694 s** | **7.564 s** | 7.564 s |
| cold-index，32ms + 10ms yield，普通优先级 | 10 | **7.526 s** | **10.499 s** | 10.499 s |
| cold-index，32ms + 10ms yield，高优先级/关闭节流 | 10 | **7.704 s** | **8.052 s** | 8.052 s |
| warm，32ms + yield + 批量 removal | 10 | **7.085 s** | **9.937 s** | 9.937 s |
| cold-index，32ms + yield + 批量 removal | 10 | **8.512 s** | **8.871 s** | 8.871 s |

N=10 的 nearest-rank p95 就是最大值；旧文中的 `7.49/8.53/7.94` 是错误地取第 9 个
样本，不能再引用。32ms 后 warm 10 次全部 <7.6s；cold 普通优先级有 1 次 10.499s
（loader 2.66s、publication 2.09s、tail 6.36s 的 CPU 慢样本），其余 9 次 <8.4s；
高优先级/关闭节流 10 次 p95 8.052s。严格按普通优先级 p95，cold 仍未通过；不能
把高优先级结果当成普通环境的稳定结论。

修复前同一白模口径约 9.5–10.2 s，tail 中位约 5.5 s；当前 tail 中位约 4.0 s。

## 机制

1. **不透明 2D cover**：`InitialLoadingCover`，白模宿主在 loader 启动前创建；生产
   `World3D` 由 GameSession loading screen 覆盖 map load。
2. **关闭 3D**：cover 期间 `viewport.disable_3d=true`；cover 不透明且 3D 关闭时
   `DeferredAssetLoader` 使用 32 ms covered publication 预算（普通交互 2 ms、
   普通白模 6 ms、同地图 transfer 固定 16 ms 不变）。
3. **full-ready settle**：cover 保持到 demand/job/stream/batch 连续稳定，再恢复
   3D、输入并 retire cover。
4. **slow-source yield**：`WorldStream` 中单个 source 的 `_apply` 超过 10 ms 时，
   当前帧立即让出，不再把 batch/collision 收尾叠在同一帧；下一帧从同一 cursor
   继续。工作不丢，只拆帧。
5. **World3D 白模入口**走同一 cover/settle；`is_world_ready` 在 cover 结束前为
   false，防止 GameSession 提前放行。

## 长帧证据

旧 `cover_traverse_01` 的 36.9/46.2/22.5 ms 是 **3D 关闭**下测的，不能代表正常
绘制。恢复 3D 后（cover 在 origin full-ready 后释放，先等一帧真实 3D 再撤罩）：

| 3D 往返样本 | 卸载 max / >50 | 返回 max / >50 | 重载 max / >50 |
|---|---:|---:|---:|
| `fix_traverse_3d_01`（首次） | 62.3 / 3 | 85.2 / 34 | 98.6 / 6 |
| `fix_traverse_3d_split_01` | — / 0 | — / 0 | — / 0 |
| `coldshader_traverse_3d_01` | 37.1 / 0 | 29.8 / 0 | 37.7 / 0 |
| `final_3d_traverse_02`（当前代码） | 51.3 / 1 | 31.9 / 0 | 30.9 / 0 |
| 5-sample batch `t3d_00..04` | 40.1 / 0 | 32.4–40.4 / 0（4 次） | 29.9–37.1 / 0 |
| `t3d_04` 单次异常 | 36.8 / 0 | **111.5 / 27** | **81.2 / 9** |
| `final_3d_split_02` 复跑 | 40.1 / 0 | 29.4 / 0 | 31.9 / 0 |
| 分组 index prep `pg_00..09` | 62.8 / 1（一次） | 0 | 0 |


分组 index prep 后 `pg_00..09` 9/10 次卸载/返回/重载全部 0 帧 >50；`pg_03`
一次 unload 62.8ms仍未归因。2026-10-25复核：其附近的
`previous_process_wall_us` 为61.300ms、draw墙钟1.428ms，不能由部分stage为0
判为OS/GPU空闲。`process_ms`是引擎约每秒更新的process墙钟最大值，既不是这帧
的OS CPU，也不能与单帧墙钟相减推导等待原因。
普通步行报告的53.1/55.4ms均跨越恢复3D/撤罩时间，附近draw墙钟49.507/53.136ms，
属于首帧呈现边界，不能写成普通步行中的OS空闲。新探针为这段保留独立phase和
时间锚，所有原始帧仍计入报告。`test_deferred_index_preparation`旧2个失败另有
3次未计入的脚本错误；2026-10-25按现有私有包和碰撞接口修复测试后39项通过、
0失败/0脚本错误，没有改动生产索引准备实现或恢复全量校验。此前
`t3d_04` 一次返回 111.5ms、
重载 81.2ms；`t3dcpu_01` 返回 91.9ms（34 帧 >50）、重载 71.8ms（7 帧 >50）。
慢帧的 `deferred_service_us` 为 27–56ms，`publication_us=0`，`engine_process_us`
26–71ms；不是 publication，而是 Deferred 的 join/`Drainer.synchronize_transfer`
路径（`RenderingServer.force_sync`）在 3D 返回值上阻塞。紧接的
`final_3d_split_02` 复跑全部 0 帧 >50。之后去掉 `_poll_jobs` 里的
`RenderingServer.force_sync` 做了 5 次实验：仍有返回 90.9ms/13 帧 >50，且该
移除会破坏资源生命周期，已恢复。加 stage 计时后的 10 次 `stage_*` 中 7 次
卸载/返回/重载全部 0 帧 >50；`stage_03` 一次 unload 54.6ms、
`stage_06` unload 85.7ms + 返回 88.9ms、`stage_09` 返回 125ms。慢帧的
Deferred poll/join/sync/dispatch 多为 0，`process_ms`/`engine_process_us`
却很高，说明阻塞不在这些 stage。加 per-frame stage ring 后，另一组 39–50ms
`_process` 帧的 `publish_us` 是 **31–44ms**，bookkeeping 50–105µs、poll 0.2ms、
dispatch 1–3ms：publication 本身仍有一个不可拆的 30–44ms unit，早前看到的
“publication 0”是帧边界错位；另有一部分在 Deferred 之外。`slow_02` 的 reload
57.6ms（3 帧 >50）也对应 `publish_us` 35.9ms，确认 publication 大 unit 是稳定
尖峰源之一，不是纯 OS。逐 unit trace 进一步显示：一次 89-spec/2151-spec 的
`Stream.append_specs` 占 10–20ms、`published.emit` 占 6.5–10.6ms，单 unit
合计 **20.6–31.1ms**；`remove_us` 仅 1–12µs，`fixture_us` 0.2–2.3ms。把大 unit 的
`published.emit` 延迟到下一帧的实验（5 次）仍有返回 78.2ms/5 帧 >50，且改变
observer 时序，已撤回；仅拆 emit 不够，`append_specs` 的 10–20ms 仍留在同帧。
另外，普通 `white_stream_*` 步行路线也不是干净对照组：5 次 `walk_00..04` 中
4 次 outbound >50（53.9–59.9ms），3 次 reload >50（69.5–79.2ms），`walk_01`
还有 unload 54.8/return 60.3ms；说明尖峰不是 native 2km teleport 夹具独有，
不能按“测试宿主”排除。下一次应拆 append/emit
大 unit，而不是继续找 Deferred 之外的 OS 等待。把 `StreamIndexPreparation`
阈值从 >256 降到 ≥32 的实验更差（return 60.4ms/5 帧、reload 78.6ms/18 帧，
37 个 preparation、203 slices、0.37s），已撤回；89-spec 组 append 仍 20ms。
进一步拆 `append_specs`：collision preflight 0–1µs、library 13–68µs、pending
6–74µs，成本几乎全在 `StreamIndex.append` 的 **5.5–10.8ms**（89/66/2151 specs），
不在 collision/library。再拆 index 子阶段：89 specs 为 validate 1.7ms / fragment
5.1ms / commit 1.5ms；2151 specs 为 validate 1.6ms / plan 2.9ms / commit 3.4ms；
没有单一 20ms 黑盒，validate/fragment/plan/commit 共同构成 5–11ms。
跳过白模 prefab texture plan 的实验（unload 67.8ms/2 帧）无收益，已撤回。
首次慢样本和上述异常都保留；当前不能宣布 3D 尖峰清零。3D 关闭的旧表只可作
历史对照。

`origin_spike_01` 逐帧对照：

| 帧 | tick | stream jobs/cursor | 归因 |
|---:|---:|---:|---|
| 56.8 ms | 0.2 ms | 0/0 | cover/启动渲染，非 source |
| 48.9 ms | 7.3 ms | 25/4 | 实际 stream，<50 |
| 48.0 ms | 6.1 ms | 170/30 | 实际 stream，<50 |
| 52.5 ms | 0.1 ms | 0/0 | 已 full-ready 的空闲调度帧，非加载工作 |

- 首帧约 380–443 ms：`--late-render-context` 对照把 loading 首帧降到 52.3 ms，
  却让 `white_stream_origin` 出现 436.7 ms。它是 Forward+ 首次 3D
  shader/feature 预热，不是地图 source 工作；保留在 cover 下预热，避免搬到
  玩家可见阶段。
- `white_traversal_setup` 约 140–165 ms 是探针新建 Navigation/Asset/Native
  residency；生产 World3D 在入口流程内完成这些对象，不是生产加载帧。
- 原始帧仍保留在报告里；加载期 >50 ms 在 cover 下，但 3D 往返首次样本仍有
  85/98 ms 的返回/重载帧，不能声称“可见长帧已全部消除”。3D 关闭的旧表只可作
  历史对照。

## cold 0xC0000005 复核

- 白模探针路径累计 23 次 cold 运行没有复现，包括 signed `D:/tools/godot` 5 次。
  这不能收紧成“正常游戏路径”：正常 GameSession 只做了入口接线复验，不是 23 次
  cold 崩溃统计。
- 此前 2 次只出现在外部脚本对子进程做 `SetProcessInformation` +
  HIGH_PRIORITY_CLASS 的实验组；该外部夹具已从后续基准移除。
- 带符号 GDB 能加载 symbols，但 GDB 自身把加载拖到超时，没有拿到崩溃栈。
- 结论边界：早期异常发生在外部优先级/节流干预组，缺少栈，尚未证明干预就是
  根因；调度变化也可能暴露竞态。2次旧异常保留，不改写成正常。
- 2026-10-25补齐历史实验清单：已撤回的并行hints、metadata mutex实验各有1次
  明确`0xC0000005`，且都已打印入口就绪；另有`coldpm_06`未完成、退出原因未知。
  不再概括为“只有外部优先级夹具两次”，完整范围见剩余问题记录。

## 代码

- `scripts/world3d/initial_loading_cover.gd`
- `scripts/world3d/deferred_asset_loader.gd`：`begin_loading_cover` /
  `end_loading_cover` / `_covered_loading_ready` / `covered_loading_budget_usec`
- `scripts/world3d/world_3d.gd`：初始白模 cover、full-ready settle、`is_world_ready`
- `scripts/world3d/world_stream.gd`：10 ms slow-source yield
- `tools/profile_axel_game_pipeline.gd`：白模默认 cover、诊断开关
- `tools/test_initial_loading_cover.gd`：7 项 cover/budget 合同
- `tools/test_entry_loading_contract.gd`、`tools/test_deferred_entry_prefetch.gd`

## 证据

`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/`：

- `warm_deferremove_10_20261024/summary.json`
- `cold_deferremove_10_20261024/summary.json`
- `warm_budget32_10_20261024/summary.json`
- `cold_budget32_10_20261024/summary.json`
- `cold_budget32_highprio_10_20261024/summary.json`
- `final_10warm_10cold_20261024/summary.json`（24ms 旧口径）
- `yield10_10_20261024/summary.json`
- `fix_traverse_3d_01.json`、`fix_traverse_3d_split_01.json`、
  `coldshader_traverse_3d_01.json`、`final_3d_traverse_02.json`、
  `final_3d_traverse_10_20261024/summary.json`、`final_3d_split_02.json`
- `origin_spike_01.json`、`late_render_01.json`

## 未解决 / 边界

- 32ms + yield + 批量 removal 后，warm 10 次 p95 9.937s、cold 普通优先级 p95
  8.871s，均低于 10s；`_remove_published_demand` 的 per-unit remove 降到约
  0.002s，批量 remove 约 0.062s。历史 10.499s 样本保留，不再作为最终结论。
- 首帧/启动预热、测试 setup 的原始帧仍 >50 ms；它们不在生产加载 source 路径。
- 3D 往返首次样本仍有卸载 62.3ms/返回 85.2ms/重载 98.6ms；后两次 0 帧 >50，
  但当前代码的 `final_3d_traverse_02` 又有卸载 51.3ms。需要更多 3D 往返样本并
  继续处理卸载峰值。
- 完整游戏纹理/角色/HUD 路径未验证 10s；OS 文件缓存未清空，不是物理冷盘。
- cold 2 次外部夹具异常没有引擎栈；要彻底闭环需要稳定复现 + dump/栈。
