# 返回需求版本触发诊断（2026-10-27）

接续 `return_official27` 官方profiler，返回帧34343中 `_refresh_demanded` 包含40.225ms，但原记录没有需求变化来源；旧 `test_demand_return_refresh` 的无关requeue合成场景能引发重复刷新，本次附近多窗口的requeue及index更新计数均0，不能认定该用例解释本帧。

新增 `demand_revision_trace.gd` 默认不实例化，诊断开启时在十类真实revision变化点和实际refresh边界记录有界、已清洗的标量和值类型、ID、需求变化、scope和累计工作，不保留地图对象；容量溢出分别记录change/refresh丢弃。scope增删ID上限16且标记截断。诊断probe按返回期启停，只有 `complete_return_leg` 且无丢弃才可视为完整覆盖；trace启用前的原因未知，initial仅指队列历史初次刷新。每次刷新自计墙时包含探针，record_us不包含整个runner开销和最终快照复制。独立审查覆盖10类触发及默认关闭；`demand_revision_final06.log` 33/0，移动需求既有回归 `demand_revision_moving06.log` 20/0，runner parse通过。路径 `D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/material_cache_pressure_20261027/`。

`demand_trace27` 正常客户端退出0、无failures/errors、被测脚本及地图主文件前后SHA一致、诊断runner额外SHA一致；状态complete_return_leg，2412事件、0丢弃，记录自身44.846ms，终止复制24.087ms；诊断不作为普通性能样本。期间1675次版本变化：set_demand 1350、release_demand 236、priority_anchor 89；737次刷新。其中434次由一次 `player_collision` set单独触发，经revision关联，累积输入173615行，刷新墙时合计1488.344ms、中位约2.29ms、最大18.566ms；这是整个诊断路段的累计，不能简单推算正常帧收益。

重要场景边界：`--native-departure` 的返回阶段是24秒从距原点(2048,2048)处回原点，约120.7m/s，player_collision envelope约每轴移动4m便更新；它是高速穿行压力，不是约6m/s普通步行。不能把434次直接说成正常游戏频率；需单独验证6m/s并保持精确碰撞就绪、候选优先级和排序，不能靠扩大碰撞需求制造表面收益。轨迹不显示原来的map24_B2长帧的具体调用栈，先前长帧仍未归因。

## 6m/s焦点对照

现有 `--walk-only` 路线使用几何焦点/相机，速度6m/s，不模拟完整玩家与游戏；取消 `--native-departure`，不混入约120.7m/s路线。实际返回被leg实现分成 `white_walk_return_straight` 和 `_turn`。`demand_walk28` 原探针只匹配父阶段，状态not_started，不能当零工作；相关红测 `demand_revision_walk_red29.log` 3项预期失败，修为仅匹配明确白名单的两个子阶段并记录边界。`demand_walk31` 中途诊断runner被并发修改，独立SHA不一致且内部源码检查失败；该样本无效，即使有事件也不用作性能结论。最终 `demand_revision_walk_green32.log` 39/0，覆盖缺子阶段、溢出、提前结束；runner check-only通过。

`demand_walk33` 退出0、无errors/failures，测量脚本与诊断runner、地图主文件SHA前后相同，状态complete_return_leg，change/refresh事件丢弃0；采集start=straight、transition=turn、end=walk_reload，返回时长42.683秒。共133次revision变化及89次刷新，62次仅因player_collision变化；这62次刷新累计18.104ms、中位0.269ms、最大0.973ms；其余21次刷新累计19.302ms、最大2.345ms，6次仅anchor刷新累计1.146ms、最大0.281ms。探针自身记录6.725ms，结束快照复制4.310ms，非全部探针开销。以上是该诊断样本，不代表所有地图/普通玩家；正常速度该样本的需求刷新明显轻于先前高速焦点压力，不能把后者434次/18.566ms最大值推广为正常步行。

不能只因碰撞窗口成员不变就跳过重排：`prioritize()` 每帧更新当前位置，旧刷新会按最新位置重新比较player与rank_from_player票据、支撑距离，同优先级候选可能反超。保留实时发布、错误、路径、支撑和准确就绪是优化前提；当前没有声称该重排已解决。

## 新一轮GDB现场

`material_publication_scope_20261027/map24_return28` 在高速返回阶段geometry-end后12ms阈值触发，独立PID/启动时间和引擎身份核对，冻结marker仍有效、无新包/序号缺口，冻结PC与GDB一致，已归还本工具唯一suspend增量；触发到读取context 0.442ms。冻结前窗口墙时15.267ms、主线程CPU计数15.625ms（Windows 粒度及接收误差，不能当精准逐帧占比）；现场GDScript主线程为 Deferred._process → _refresh_demanded，顶层native位于 Array::size / indexed get，说明该瞬间在执行需求刷新，不证明该单个数组调用占据窗口，也不是map24_B2原发布帧。调试暂停约299ms及后续GDB all-stop开销污染该路线，不能作为正常FPS。引擎/GDB退出0，主地图与测量源前后未变，完整线程与原始触发记录保留。
