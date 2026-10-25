# 纹理阶段：卸载选择准备（2026-10-26）

本轮延续目标：压缩完整加载耗时与 low 帧，按加载时间、帧耗时、工作量分别判断。
**结论：异步选择候选未默认接入；运行代码恢复本轮开始的 b337b900。**
它证明了同步等待可以移走，但没有证明足够稳定的净收益，且增加复制/释放工作。
保留独立压测工具、修正后的旧测试、完整候选补丁和失败证据；没有撤回以前的有效优化。
地图/材质范围、计时合同与引擎版本沿用 `axel_async_texture_headers_20261026.md`。
证据根目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/retirement_selection_20261026/`。

## 依据与候选机制

前轮官方 profiler 的卸载帧 9920：NativeResidency 41.244ms，retire_specs
39.864ms，preflight 20.832ms，ResidentSelection.prepare 17.673ms，其中七次
Thread.wait_to_finish 合计 10.670ms。这些是嵌套时间，不能相加。

原实现由主线程处理一部分选择，同时开最多七个子线程，随后同步等待全部完成。
新候选仅对不少于 2048 项的完整 resident 单元生效：

- 分帧复制所选源的字段所有者，每帧目标 750µs；不扫描全地图，不读取资源包。
- 使用 Deferred 共用的 ResourceAdmission；复制阶段只占字节预算，后台计算时占一个 worker。
- 一个 CPU worker 生成选择集合、组计数及清理元数据，主线程只 join 已结束的 worker。
- 结果完成立即归还执行槽位，快照实际释放完成后再归还字节预算。
- 提交仍原子更新 index/navigation，并保留当前玩家需求、活动对象及门状态保护。
  复用已有 stream_collision_revision 确认受控索引的成员关系；任意可变字典调用者仍走逐项身份检查。
- 玩家返回、切换地图、队列停止或预算抢占时取消；后台未退出前不释放其输入。
  永久超预算/准备失败走既有同步路径，临时容量不足等待现有预算。

未修改模型、纹理、碰撞或地图文件；未恢复 GLB 运行加载。

## 独立复现与失败尝试

`bench_resident_retirement_selection.gd` 覆盖 2200/8800 行、空/密集元数据、
1/2/4/8 worker。`baseline01` 中 8800 密集行串行约 51–52ms，八线程约 21–27ms。
尝试缓存成员集合但仍串行扫描 live 字段的 `candidate02` 约 49ms，未接入生产。
失败候选源码保留为外部 `candidate_cached02.gd`，基准可用 `--candidate=<path>` 复现。

`handoff_abba07` 是实际 NativeResidency → WorldStream → Index → Navigation
事务的 2200 行微测，不是整图 FPS：同步主线程 max 35.217/18.692ms；候选
20.055/22.626ms。候选累计主线程工作 45.871/51.672ms，墙钟 234/250ms，
同步墙钟 35/19ms。**峰值并非每个样本都改善，快照与分帧增加了总工作和回收等待。**
不能凭异步化宣称总体收益，真实地图对照决定保留范围。

`test_resident_selection_preparation` 包含 8800 行逐字段结果对照、版本失效、
门状态/活动对象变更、暂停 worker、第二槽继续接活、重复取消、最终计费归零与
永久超额拒绝。`test_native_selection_handoff` 检查真实导航/索引原子卸载，
以及玩家返回和停用队列取消准备。

旧 `test_native_retirement_scheduling` 仍假定缓存清理在 index 事务中同步完成。
当前 HEAD 与候选都已将其推迟到下一帧，初次测试因访问未创建的回收服务中断。
外部 candidate/baseline 首次 poll 都成功卸载相同八项、生成相同清理任务。
测试已显式推进下一帧清理再检查资源归属，未放宽正在准备的资源保护。

`test_resource_retirement` 的 headless 失败来自其明确要求真实 GPU；随后通过私有
桌面运行，7 项通过。两类失败样本均保留，不能写成所有原始运行一次通过。

## 整图与 profiler

使用同代码 ABBA，仅切换
`--sync-retirement-selection`；异步纹理头部读取在两组均开启。
几何/包围盒/模型元数据缓存禁用；native、依赖索引、磁盘纹理缓存保留，OS 缓存未控制。
不属于物理冷盘测试，不用四个样本作 p95 稳定性结论。

| map09 | 完整就绪 s | 卸载 max ms / >50ms 数 | 返回 max ms | 重载 max ms / >50ms 数 | 重载 1% low FPS |
|---|---:|---:|---:|---:|---:|
| A1 同步 | 11.189884 | 31.029 / 0 | 32.126 | 43.306 / 0 | 26.871 |
| B1 候选 | 11.466478 | 30.775 / 0 | 33.995 | 53.753 / 1 | 27.227 |
| B2 候选 | 11.262020 | 49.332 / 0 | 40.412 | 46.739 / 0 | 26.896 |
| A2 同步 | 11.164171 | 364.936 / 6 | 36.188 | 61.208 / 1 | 25.076 |

1% low 为最慢 ceil(n×1%) 帧的平均耗时取倒数。完整就绪仍超过 10 秒；候选不在
首次加载链上，不能将约 0.2 秒波动归因给卸载改动。重载 low 数值有改善/重叠，
不足以证明因果。四组 steady 还各有一次 53.0–69.1ms 长帧。

A2 最慢卸载帧在 73338.933ms，process 15.883ms、physics 0.089ms，Deferred
各项合计不足 0.1ms。未抓到该帧主线程/渲染线程栈，不能写成 OS/GPU 已定责，
也不能把 A2→B 的 300 多毫秒差值当作候选收益。失败/慢样本均纳入表格。

真正的 Native retire_commit max：A 为 28.364/27.727ms，B 为 27.338/27.224ms，
只差约 0.5–1ms。B 两次各准备 2151 行，额外 capture 34.614/34.446ms，
worker 31.948/31.473ms，最终核对 12.014/12.518ms。private_values 从 A 的
5342/5356 增至 B 的 7510/7499，包含新增快照释放；这不是工作量减少。
私有释放 max 仍达 22.855ms，未解决。

四组功能、最大建筑/初始地形实际卸载与完整返回重建均通过；无需延长卸载观测窗口。
最终 worker、admission、像素消费者、资源回收队列全部归零。每组 85 个唯一纹理
来源，GPU 上传 170 次 / 721,332,072 B，其中 DDS 148 次 / 508,911,392 B。
动态路径模型任务数分别 69/63/65/71，不能宣称所有工作量完全相同。

官方 `reload_official10`：游戏、接收器、解码器均返回 0，errors/failures 为空，
地图与运行源码未变化，记录 24032 个 visual frame。它是诊断样本，不并入上表。

- 卸载帧 9720 共 37.225ms：selection join 0.012ms，valid_for 12.513ms，
  navigation._retire_selected 5.643ms，index._commit_owned_delta 6.942ms，
  asset_residency.forget_specs 3.201ms。preflight 15.301ms / retire_specs
  33.165ms 是包含上述子调用的总时间，不能重复相加。
- 候选共创建 6 次准备、5607 份行快照，含取消/重新准备；主线程没有等待仍在执行
  的选择 worker，但整批 equality 已成为替代热点。worker rows 不计为主线程时间。
- 返回帧 21095 共 50.493ms，其中 `_refresh_demanded` 44.502ms：self 25.061ms，
  `_in_clip_catalogue` 8.183ms，1483 次距离计算合计 1.352ms。单纯优化距离公式不是重点。
- 重载帧 22082 共 44.409ms，`SurfaceMaterials.trim_cached_resources` **16 次 /
  23.745ms**，排序 lambda **8068 次 / 2.348ms**，材质纹理属性读取 1512 次，
  `_texture_cost` 984 次 / 2.002ms。这是新确认的重复缓存维护工作，优先独立复现。

## 归档、验证与下一步

`candidate_snapshot11/` 保存 11 个候选文件的原始字节和 SHA，`candidate11.patch`
可恢复完整运行接入及专用测试。恢复基线后 `git apply --check` 通过；后续可在隔离
worktree 应用，避免再次从零实现。基准工具留在仓库；本轮不保留无调用者的运行 API。

候选相关 14 组 CPU 测试与真实 GPU 释放测试通过；其中新增 preparation 62 项、
真实导航/索引 handoff 9 项，另含动态门/活动 pin、索引版本变化、预算拒绝、阻塞
worker 的取消与最终归零。初次测试宿主错误和纯 headless 下 GPU 条件失败保留在
`regression08*`。归档恢复后重新运行修正的 scheduling 测试，11 项通过。
基准最终补显式 Dictionary 类型，首次 parse 失败记录保留；修正后用
`baseline_final12.json` 验证 32 个参数组合、每组 7 次，全部投影等价。

下一步先针对材质缓存的重复全表扫描/排序建立独立压测，区分必要淘汰和未超预算的
无效排序，保持纹理去重、热缓存字节上限、弱引用及外部刷新语义。再处理需求刷新中的
候选集合维护。卸载的后续方案应减少静态元数据与动态 pin 的重复遍历，避免重做完整
spec 快照再逐字段比较。365ms 低 process 样本及 steady 等待仍需要 profiler/GDB
抓对应帧的线程栈，不与上述高 CPU 工作混为一类。
