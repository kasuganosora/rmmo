# 返回资源的需求成员缓存（2026-10-27）

本轮候选只减少无关 requeue 后的部分 typed membership 重建。每次接受新条目仍增加 `_demand_revision`，重新计算候选排序和 support，并按原路径清理 typed fallback、碰撞查询及调度重试；**全局需求刷新尚未消除**。首版隔离真实地图路线没有观察到命中；内部只读路径修正后的 ABBA 已观察到命中并减少 typed full-scan 工作，但有限样本不能证明稳定帧率或初始加载时间收益。

## 实现边界

增量索引且 pending 快照为 dirty 时，authoritative UUID 目录承接返回条目，避免在 requeue 当下为 append 物化整个 pending Array；外部已借用的旧 Array 不会被改写，后续 getter 仍按目录顺序创建当前快照。非增量、活跃借用快照或大对象目录 alias 等情况走原有 Array 路径与全量缓存清理。

缓存只可能保留建立时使用 canonical typed full-scan 的票据。重用前重新检查实际查询策略与桶数阈值、配置和 registration epoch，按返回条目的 live bounds 对所有缓存票据做 inclusive XZ 相交检查；疑点、组票据或其他查询路径一律清除。typed cache 建立时若任何同类 pending 项已发布，则不对该 cache 启用 requeue 重用，避免此项后来变回可用时被漏掉。重新登记建筑的 bounds/support/order 会推进 epoch；这是一条保守防线，不代表已证明既有登记逻辑有 bug。

`pending` 的支持生命周期是现有 publication 将旧 Array 与 authoritative map 分离后的 dirty 状态；非 dirty 的可变借用回退原路径。本措施不承诺检测对私有索引字典的任意外部篡改。共享 support 从 live `_pending_by_record_id` 在每次刷新重新获取；碰撞查询、texture attempt、publication retry、调度容量和在途 job/lease 均沿原 revision 流程处理。

## 红测与回归

`test_requeue_membership_delta.gd` 在旧实现上最终基线为 **146 项通过、2 项失败**，两项分别是无关 requeue 的 membership 全部重建，以及 dirty pending 在 requeue 内发生一次全量物化；最早的较窄基线、alias 扩展基线和最终基线日志均保留。候选扩展测试为 **155 项通过、0 失败**，覆盖：scope 外票据后续放宽、组匹配、桶阈值切换与同分顺序、非 canonical alias、登记变更 epoch、当前位置排序、live support、published 回转、learned bounds、旧 snapshot、getter 顺序、碰撞观察、非增量回退、错误和 job/token/byte lease。

另有 9 项原有 headless 回归共 **667 项通过**：返回刷新 119、demand membership 56、live membership 24、support promotion 24、support set ID 100、terrain return 29、retirement scan 24、requeue compaction 80、candidate catalogue 211。以上测试 stderr 无脚本或引擎错误；这些不代替真实地图、实际并发、GPU 或编辑器验收。

## 独立 CPU ABBA

三次进程内 ABBA，按 A/B/B/A 顺序；每项计 24 次 requeue + 完整 refresh 的墙钟，包含 guard 与实际重排。A 关闭 dirty/index 和 selective membership 两开关，B 开启；均使用同一候选源码和合成夹具，逐轮验证调度状态与 queue 内 owner 身份。A、B **共同执行**新增的 typed cache `published` 跟踪和 metadata 构造，所以下表无法测量这些公共新增工作的相对原始源码成本。

| 进程 | A1（ms） | B1（ms） | B2（ms） | A2（ms） |
| --- | ---: | ---: | ---: | ---: |
| 1 | 310.210 | 388.367 | 328.094 | 353.461 |
| 2 | 357.434 | 287.570 | 285.419 | 460.638 |
| 3 | 263.108 | 252.205 | 315.919 | 316.662 |

首轮两个 B 均不快于相邻 A；结果波动较大，**不能声称稳定的总时间或 FPS 收益**。每 24 次 candidate 的 typed membership miss 为 **120→24**、保留 96 个票据；完整 `demand_input_rows` 仍是 41,856、距离计算 23,040、support 访问 1,536、全局刷新 24 次，均未改变。`pending_snapshot_materializations` 全程都是 24 次：候选将物化推迟到随后 full refresh，而非消除；物化行数从 **25,128 增至 25,152**。仅 requeue 段 A 为 7.440–10.350 ms、B 为 5.710–7.512 ms / 24 次，这不能代替包含 refresh 的总耗时对比。

实验使用引擎 SHA-256 `40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`；脚本保存了各次源文件 SHA 和全部计数。诊断截图的非真实玩家高速轨迹里观察到 typed full tickets 反复 miss，但尚不能把这些合成次数或收益直接转成真实帧时改善。

## 证据

全部原始日志在 `D:/code/rmmo_runtime/review_artifacts/support_order_review_20261027/`：

- `requeue_delta_baseline.log`、`requeue_delta_baseline_complete.log`、`requeue_delta_baseline_final.log`：分阶段旧实现红测；`requeue_delta_candidate01.log`、`requeue_delta_candidate02.log`：候选测试。
- `delta_related_test_*.log`：9 项 headless 回归原始输出。
- `membership_abba_01.log`、`membership_abba_02.log`、`membership_abba_03.log`、`membership_abba_summary.json`：全部 12 个时间样本、工作计数、源码与引擎 SHA。
- `run_membership_abba.py`：独立压测运行及快照检查脚本。

真实地图复测必须使用同一目标、纹理及采样范围、保存失败/慢样本，并同时记录加载耗时、卸载/返回帧分布和工作量。结果不能将几何相机扫描冒称真实玩家体验，也不能把有限次数当作 p95。

## 隔离 axel_town ABBA：未观察到 fast path 命中

在同一个隔离地图和 A 态侧车上，按 A/B/B/A 顺序完成四轮。A 禁用 dirty-index 和 selective membership 两开关，B 启用；两组均抑制同步慢日志，其余 runner 参数相同。**B1、B2 的所有 500 ms 队列 profile 快照均未出现累计的 `requeue_direct_pending_items` 或 `requeue_memberships_preserved` 计数**：最后可用快照的两个计数均按缺省值记为 0。最后一次队列快照分别处于 exit-inflight、reload，无法证明之后直到退出的极短未采样尾部绝无执行，但覆盖的路线中没有观察到候选路径执行。必须先弄清 guard 为什么没有命中，不能将下面任何帧时差归因于此优化。

所有样本 exit 0、功能断言通过、开关与实际状态匹配；四份 `source_before` 的 798 项一致，源码、地图、资源变体与 settings 在各轮前后不变。引擎 SHA 为 `40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`；隔离 fixture manifest SHA 为 `466827d04434fdf34f007c53ef76c99359e91370188ac112f95673a2ba8a3340`，settings SHA 为 `c1e4facc3d9f5351e4672467ed5b015bba5ce3425ae9304475c8c9708bc8b5d6`。校验会预热 OS 页缓存；不同私有用户目录、四个样本均不构成真正物理 cold disk 或 p95。

| 样本 | 入口（s） | 需求完整就绪（s） | unload：最大 ms / >50 帧数 / 1% low FPS | return：最大 ms / >50 帧数 / 1% low FPS | reload：最大 ms / >50 帧数 / 1% low FPS |
| --- | ---: | ---: | --- | --- | --- |
| A1 | 6.800 | 14.649 | 77.696 / 1 / 93.900 | 67.622 / 1 / 35.677 | 64.994 / 2 / 32.445 |
| B1 | 6.281 | 14.312 | 48.678 / 0 / 90.132 | 45.902 / 0 / 38.074 | 47.372 / 0 / 31.667 |
| B2 | 5.562 | 13.446 | 49.708 / 0 / 97.571 | 41.988 / 0 / 37.771 | 47.485 / 0 / 29.682 |
| A2 | 5.628 | 13.286 | 115.549 / 1 / 93.746 | 67.242 / 2 / 27.423 | 54.348 / 1 / 27.815 |

首次进入后 steady 阶段的最大帧 / >50 帧数 / 1% low FPS 分别为 A1 **93.541 / 1 / 42.826**、B1 **113.093 / 1 / 37.303**、B2 **46.486 / 0 / 50.392**、A2 **46.286 / 0 / 50.120**。离开阶段分别为 **361.903 / 1 / 30.744**、**96.885 / 1 / 39.320**、**32.845 / 0 / 44.850**、**38.566 / 0 / 45.344**；必须保留 A1 的 361.903 ms 样本，现有数据不足以认定其根因。FPS 计算口径为每阶段最慢 `ceil(帧数 × 1%)` 个 observer 帧间隔的算术平均值，再用 `1000 / 平均毫秒` 换算；这些并非真实玩家行走 FPS。

工作量按各轮**最后一次 500 ms 队列快照**读取，A1/B1 快照处于 exit-inflight，B2/A2 处于 reload，并非严格相同终点：demand refresh 为 **1586 / 1611 / 1620 / 1588** 次，累计 wall 为 **4.188 / 4.149 / 4.069 / 5.552 秒**，输入行 **360326 / 352324 / 362204 / 389108**；typed full ticket 为 **1676 / 1732 / 1708 / 1696**，typed candidate 行 **197136 / 204985 / 208691 / 204852**，pending 快照物化 **174 / 201 / 169 / 165** 次。该观测不能作为精确同工作量控制，也不能把嵌套 wall 累加或直接归因开关。

四轮初始 render audit 均为 3,943 GPU surfaces、1,502 textured surfaces、145 个 unique textures；native 路径各退休并回访 504 units、退休 3,677 specs。asset 退休 specs 分别为 **1011 / 1033 / 1055 / 1060**，整个焦点扫描观察到的 reloaded specs 为 **4530 / 4509 / 4504 / 4482**，其余工作量因调度和观测点变化。退出检查均为 `map_freed=true`，worker jobs、resource retirements、admission bytes、lookahead bytes、loading render contexts 和 retained templates 均为 0。这里仅为 map-texture-stage 隔离几何/相机扫描：导入模型仍是无原材质的 native geometry，未覆盖完整游戏、HUD/角色或完整模型材质；输出字节量不是实测 VRAM。

原始记录 `D:/code/rmmo_runtime/review_artifacts/isolated_axel_dds_samples_01/requeue_abba_A1`、`B1`、`B2`、`A2`（完整目录名均以 `requeue_abba_` 开头）；整理脚本和机器可读报告为同目录 `requeue_abba_analyze.py` 与 `requeue_abba_summary_analysis.json`。下一步应只读定位 dirty、索引、类型目录和 scope 等 guard 的实际失败原因；调试要记录 probe 的成本，不能通过放松 owner、published 或 support 合同强行提高命中率。

## 不同源码的完整退休周期对照

`D:/code/rmmo_runtime/review_artifacts/requeue_source_abba_20261027_02/` 在独立项目、私有用户目录及私有类缓存中，比较旧源码和实际候选源码，顺序为旧/新/新/旧 ×2。旧 loader 取自 `921b8c19`，只额外应用与候选相同的 support 判断换序，以隔离此既有优化；旧版 SHA 为 `1c558748fd90f577be268cc355bf494596a9cfdaeea8a9aad7d7c49838125ea8`，候选 SHA 为 `a3ac8414bd7c4cb63fad4fe792a0794dab7a1a4f0b7b328bf2877545195465b0`。不像开关对照，这次旧版本不包含候选共有的 typed `published` 跟踪和 metadata 构造。隔离项目、原项目和引擎在测试前后身份一致；完整差异、各样本与机器可读报告均保留在证据目录。

每个样本包含 24 步。requeue 两组将退休登记、实际 requeue 和完整 refresh 纳入计时，并另计最后的 pending 快照兑现；每步计时后比较完整调度状态指纹并校验原 owner 身份。无 requeue 组交替移动位置并刷新排名。8 个样本的对应 24 个状态指纹一致，owner 检查均通过；调度状态检查在计时之外。强制 miss 是有意在每步清空 membership 的合成条件，不代表真实地图 miss 率。

| 场景 | 旧版 4 次（ms） | 候选 4 次（ms） | 旧/新中位（ms） |
| --- | --- | --- | --- |
| 无关 requeue：退休 + requeue + refresh + 尾部兑现 | 447.017 / 315.310 / 378.639 / 255.269 | 281.112 / 233.303 / 229.354 / 230.517 | 346.975 / 231.910 |
| 强制 membership miss：同上完整周期 | 452.355 / 398.887 / 316.026 / 294.235 | 321.028 / 303.733 / 319.531 / 235.742 | 357.457 / 311.632 |
| 无 requeue 的移动排名刷新 | 480.104 / 345.726 / 214.651 / 221.827 | 294.890 / 315.311 / 196.692 / 242.900 | 283.777 / 268.895 |

这些是每次 24 步的合成墙时，样本波动大，既不能声称精确稳定比例，也不能外推到地图加载或帧率。无关 requeue 中，typed full-scan 从 **96 次 / 20,928 分类候选行降至 0**，而需求输入 **41,856 行**、距离计算 **23,040 次**、support 访问 **1,536 次**和刷新 **24 次**均不变。pending 快照物化两版均为 **24 次**，旧版 **25,128 行**、候选 **25,152 行**；候选没有消除这部分工作，物化时机与行数发生了变化。强制 miss 时两版均为 96 次 typed full-scan / 20,928 候选行；无 requeue 时两版均是 120 次 membership hit、零 miss。末尾兑现另计且各样本仅 4–28 微秒，不能推论所有地图生命周期的兑现成本。

先前 `requeue_source_abba_20261027_01/` 只测 requeue + refresh，未计前置退休，且测试期间另一 agent 运行过数次约 1 秒的 PowerShell/rg 只读命令，可能干扰样本；全部数据保留，但不作为无干扰或完整周期结论。`_02` 测试期间其他 agent 已停止命令，未设置系统级干扰监控，仍不能断言整机完全无干扰。

## pending 生命周期静态审查

`pending` 公开 getter 调用 `_materialize_pending_snapshot()`；dirty 时它从 UUID 目录生成 Array 并清除 dirty。publication 的有序移除会先摘除相应索引、把私有 snapshot 标为 dirty，原先借出的旧 Array 则保留；随后 requeue 的 `direct_pending` 需要 dirty、增量索引、UUID/large/typed 目录规模一致等条件同时成立。读源码可以确认任何经过公开 getter 的读取都可能令 dirty 变为 false：例如 grouped demand、部分碰撞全量回退、模型碰撞消费者扫描及 native residency 的 membership fallback。正常稳定阶段若已物化、此后未再 publication，也会保持 clean。实际地图未命中的**具体条件尚未采到**，不能把它直接归因于某一个 getter；indexed、large 和 typed 等条件同样可能不满足。

缓存保留与“跳过 Array append”可作为两个独立判断：在 clean snapshot 与 UUID/typed/large 目录确实一致、accepted 条目已按原路径 `pending.append` 并增量入索引后，仍可让 `_preserve_unrelated_typed_memberships` 检查原有 typed 策略、registration epoch、同 UUID、inclusive bounds 及配置；revision、重新排序、live published/support、碰撞与 retry 失效都继续执行。但 **clean 和目录数量相等不能单独证明 snapshot 的 owner 身份或顺序一致**：公开 getter 返回可变 Array，外部可能同长度替换、插删或重排，未必触发 size guard。若无法证明受支持的可变借用仍与目录同一有序 owner 集合，就应走保守回退；可探索专门的借用/所有权状态或精确校验，并将其成本计入收益，不能为了命中率改变公开可变 Array 合同。尤其不能将内部只读路径对“数量相等”的判断升级为新的外部 mutable 数据正确性证明。

内部只读用途可单独评估：dirty 且 canonical 目录已经证明完整时，纯 membership 查找可同步借用现有 `pending_record_catalogue()` 的 UUID 目录；需要顺序扫描的内部方法可考虑按目录的原有插入顺序只读遍历，避免触发公开 getter，不能跨 yield 保留借用或对目录作写操作。clean 或非 canonical 场景仍读取原 Array；需要 Array 的调用若临时取 `values()`，仍会分配并可能产生释放工作，不能只统计避免了 dirty 清除。关闭、重建索引和外部 setter 仍须按原生命周期先处理权威数据。现有借用方法在非 dirty 时也以数量作为 guard，不能拿它证明同长度外部修改安全。

进一步验证应先在隔离 probe 中记录每次实际 requeue 的各项 guard、snapshot 状态及最近一次物化调用位置/帧，以确定主因，再针对命中的内部消费者做单独工作量与完整周期测试。语义用例必须覆盖旧 Array 引用与当前可变借用、同长度不同 owner/UUID、同 UUID 别名、插删重排、组/typed/spatial 查询顺序、碰撞查询失效、published/support 变更、释放及回退；精确比对 UUID、owner、顺序、path head、错误和就绪。该段是静态建议，尚未实现或证明地图收益。

## 有界 guard 诊断：dirty 是本次唯一失败条件

上述“具体条件尚未采到”的边界现已由一次 **诊断样本**推进：使用外部隔离项目，在进入 native departure 的第一个 geometry tick 挂载 recorder，覆盖随后卸载和返回；之前加载、原点阶段不在捕获范围内。探针在 requeue 的 `direct_pending` 实际判定之后、任何 fallback 可能调用 pending getter **之前**记录入口 frame 和每项独立布尔条件，再在批次去重结束后记录 accepted 数；headless 契约测试专门复现 fallback 把 dirty 从 true 变 false，确认保留的仍是入口值。仅采样 scalar，没有保存 queue、item 或 Resource 引用；事件最多 512 条，物化调用栈示例最多 12 条、每条最多 8 层，source/function 分别最多 192/96 字符。超限单独计数；同步栈和记录本身会影响运行时间。

完整路线中 **157 次 accepted requeue，共 1,714 个条目**；direct 命中 **0 次**。157 次的 false 位组合全部是 **dirty=false，其他条件全 true**：feature、incremental、indexed、owner-count、large-count、kind-present、kind-count 和 selective 各自失败次数均为 0。事件丢失 **0**，逐事件计算的组合与累计计数一致；因此结论只针对这个已捕获的 157 次，而非此前启动阶段或所有游戏路径。dirty 状态下 owner-count 相等只是当前 `pending_count` 实现的恒等关系，不构成额外 owner 身份证明。

窗口内观察到 **152 次** dirty 快照物化，只保存了前 **12 次**调用栈，均非空且没有栈层或字符串截断。其中 **11 次**来自生产 `DeferredAssetLoader._dispatch_jobs` 的 `not native and not faces_known` 分支扫描 pending，**1 次**来自测试宿主 `sample_residency()`。这些示例发生在 frame **3560–3631**，首个 accepted requeue 在 frame **6984**；所以它们证明上述路径能够触发物化，**不能证明它们是那 157 次 requeue 前的直接调用者**。其余 140 次只计数、未采调用栈，不能据此归类。

独立项目初始化及 probe/runner check-only、探针契约通过；包含事件上限、截断、标量复制、默认关闭与入口位点测试。一次实际隔离地图路线 exit 0、功能失败列表空、事件丢失 0；原项目和隔离项目源文件、隔离 class/UID cache、注入 diff、fixture 变体、地图、settings 与 engine 的前后检查通过。该样本原项目 loader SHA-256 是 `a3ac8414bd7c4cb63fad4fe792a0794dab7a1a4f0b7b328bf2877545195465b0`，隔离版 loader 是 `75fe5123b100e398c954267d64a2163f8c223aa5abd7a855f719c4c9aee95f87`，engine 是 `40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`；这些值取自该样本的 before/launch 文件，不代表后续源码。原项目核对 5,069 项，隔离项目含导入生成 UID 后为 6,158 项；fixture 校验预热 OS 缓存。

原始数据和校验位于 `D:/code/rmmo_runtime/review_artifacts/isolated_axel_dds_samples_01/requeue_guard_diag01/` 的 `sample.json`、`result.json`、`before.json`、`after.json`、`launch.json`、`command.json` 和 `engine.log`。隔离项目为 `D:/code/rmmo_runtime/review_artifacts/requeue_guard_overlay_20261027_01/`，探针源码、准备脚本与 headless 日志位于 `D:/code/rmmo_runtime/review_artifacts/support_order_review_20261027/requeue_guard_overlay/`。这是 map-texture-stage 的高速焦点/相机扫描，不是完整游戏或玩家行走；不能将其时间或帧率当作优化收益。

## 内部只读修正后的隔离地图 ABBA

实现和 61/1 红测 → 68/0 green、890 项 Godot 回归及 23 项 Python 检查见 `axel_pending_snapshot_ownership_20261027.md`。本段记录该实现的实际路线，不以先前 draft 的微测替代验收。

保留同一隔离地图、A 态 fixture、engine09、settings、路线、预算及纹理控制，A 关闭 requeue 优化、B 启用，两组都抑制同步慢日志；独立用户目录，顺序 A1/B1/B2/A2。四轮均 exit 0，功能断言、实际开关及源码、engine、地图、fixture、settings 前后和跨轮身份检查通过。四轮只是样本，不是 p95；fixture 校验读盘会预热系统缓存，不能称物理冷盘。这里仍是 map-texture-stage 高速几何焦点/相机路线，不是包含全部原生模型材质、角色、HUD 的完整游戏体验。

| 样本 | 入口 s | 需求完整就绪 s | 卸载：最大 ms / >50 帧 / 1% low FPS | 返回：最大 ms / >50 帧 / 1% low FPS | 重载：最大 ms / >50 帧 / 1% low FPS |
| --- | ---: | ---: | --- | --- | --- |
| A1 | 6.409 | 14.076 | 33.022 / 0 / 113.598 | 38.388 / 0 / 41.179 | 41.973 / 0 / 31.847 |
| B1 | 5.491 | 12.367 | 34.701 / 0 / 110.754 | 34.131 / 0 / 44.272 | 47.588 / 0 / 31.705 |
| B2 | 5.395 | 12.732 | 51.133 / 1 / 111.435 | 39.302 / 0 / 39.209 | 36.637 / 0 / 33.576 |
| A2 | 6.548 | 15.327 | 30.385 / 0 / 89.989 | 35.719 / 0 / 45.388 | 37.585 / 0 / 33.839 |

steady 阶段 max / >50 / 1% low 为 A1 **58.954 / 1 / 54.339**、B1 **56.534 / 1 / 49.617**、B2 **49.875 / 0 / 55.479**、A2 **71.673 / 1 / 43.442**；departure 分别为 **43.378 / 0 / 41.532**、**30.606 / 0 / 44.393**、**30.472 / 0 / 45.664**、**42.739 / 0 / 47.069**。1% low 定义为最慢 `ceil(1% × 观察帧数)` 个帧间隔的算术均值，再用 `1000 / 平均毫秒` 换算。B2 的卸载 **51.133 ms** 明确保留；帧数据没有显示一致的 low 或最大帧改善。

时间边界尤其重要：B1 首个 observed direct / preserved 非零出现在卸载阶段 **49.651 s**（上一快照 49.150 s 均为 0），B2 出现在 **49.156 s**（上一快照 48.655 s 均为 0）；两轮 full-ready 分别为 **12.367 s、12.732 s**。计数器为累计值，真实命中在相邻 500 ms 快照之间；两次均明显发生在当前需求完整就绪之后。故上表 B 组初始 full-ready 较短**不能归因于 requeue 优化**。

B2 的 51.133 ms 是标记从 departure 切到 unload 的第一个观察间隔（at=48069.636 ms）。这一行 `process_ms=10.181`，下一行间隔只有 6.596 ms、`process_ms` 却为 51.015；monitor 与 observer 不能直接按同一行相减归因。Deferred 该行只记录 accept 2、bookkeeping 39、dispatch 108、poll 26 微秒，join/sync 为 0；这些字段没有覆盖全部主线程工作。既不能凭同一行低 process 把它归为 OS/GPU 空闲，也不能只凭阶段名认定是卸载生产方法。保留原始相邻帧，后续须对齐采样时序或获取调用栈再定位。

各轮最后 queue 快照位置不同，依次是 reload、ownership checks、exit-inflight、exit-inflight，不能冒充统一终点；截至各自最后快照，A1/B1/B2/A2 的 preserved 为 **0 / 644 / 684 / 0**，direct items 为 **0 / 9 / 9 / 0**。尝试以每轮首次 reload 的 500 ms 快照作为近似共同边界：typed full-scan tickets 为 **1668 / 1028 / 1028 / 1680**，对应分类候选行为 **199047 / 122469 / 125196 / 198567**；membership miss 为 **3617 / 2986 / 3008 / 3661**，demand input 行 **365178 / 322833 / 363630 / 338208**。这是不同时间采样及调度工作量的近似边界，不是逐条严格配对；可以确认 B 路线发生了缓存保留，也观察到 typed full-scan 工作下降，不能直接把差值转成确定帧时收益。

整段路线观察到的移除 specs 为 **4645 / 4664 / 4723 / 4739**，返回重载 specs 为 **4513 / 4537 / 4504 / 4569**，调度工作量并不完全相同。四轮退出后 `map_freed=true`，worker jobs、resource retirements、admission bytes、lookahead bytes、loading render contexts、retained templates 均为 0。原始样本在 `D:/code/rmmo_runtime/review_artifacts/isolated_axel_dds_samples_01/requeue_private_abba_A1`、`B1`、`B2`、`A2`（均以相同前缀命名）；协调器完整报告及源码/fixture 身份为同目录 `requeue_private_abba_coordinator.json`，首次命中和首次 reload 快照的整理文件为 `requeue_private_abba_boundaries.json`，相应脚本为 `run_requeue_private_abba.py` 和 `analyze_requeue_private_abba.py`。
