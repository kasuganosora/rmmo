# 白模剩余问题处理（2026-10-25）

主指标保持用户确认的“地图加载计时开始→当前需求区域完整就绪”。本轮不改纹理、
正式地图或原生模型，不扩worker/预算，不恢复全量数据校验。时间、帧耗时、工作量
仍分别记录；测试修复和测量纠错不冒充加载加速。

## 接手基线

`prepgroup_load_10_20261025` 的20份原始报告经复核：warm N10 median 6.764112s、
p95/max 6.918434s；cold-index N10 median 7.550522s、p95/max 7.917838s。每份源码
前后相同、同一源码组，failures为空。OS缓存未清空，cold-index不等于物理冷盘。
这些是本轮修改前的历史基线，不回写成修改后N10成绩。

`cold_00`的队列ready为7.918s，探针在固定origin观察窗口结束后才于16.356s撤罩。
两者是不同锚点，后者包含固定观察时间，不能把它解释成实际生产多等了8秒。
原报告有Godot版本/git hash，但没有exe字节SHA；本轮回归补保存exe、地图、启动
命令、源码、runner SHA及读取到的进程priority，未改变priority/QoS。

## 已修复：索引准备测试合同

`test_deferred_index_preparation`在c593 baseline headless上先复现14项通过、2项
失败，另有3次旧测试未计入的SCRIPT ERROR。根因是测试与现有私有包合同不一致：

- 默认私有runtime数组由单一fixture writer修改；旧测试任意篡改私有pose却要求
  snapshot验证发现变化。现在用真实`runtime_fixture_states`使准备失效，同时保留
  非私有snapshot路径的任意pose变更反例。
- 碰撞替身缺少`publication_status()`选择接口；提交前的promotion等待是另一道
  状态。旧测试还用`valid_for()`检查runtime-owned cursor，实际应使用对应validator。

只改测试，生产索引准备逻辑、分组阈值和快速路径均未改。修复后39项通过、0失败、
0脚本错误。覆盖600条原始identity、没有partial namespace、实际fixture新pose、
连续3次碰撞等待保留同cursor/租约且不重建、单次commit/emit，以及取消清理。
证据：外部`deferred_index_preparation_20261025/{baseline,updated}.{json,log}`和
`review.json`。新增覆盖量不同，测试总耗时不能用来比较性能。

## 已修复：初始cover输入与失败状态

旧代码的局部碰撞guard仍可能在cover下放行输入，abort后也可能保留ready。旧快照
最小反例4项中2项失败。新增`test_initial_loading_lifecycle.gd`，首轮39项通过：

- cover内允许流送工作，移动输入保持锁定；局部碰撞就绪不能解除初始加载门。
- 独立复核修正了中间版本cover早退的问题：计数反例7项中2项失败，最终覆盖期间
  继续执行prioritize与局部碰撞请求，仅阻止解锁和WASD提示覆盖，不以少做工作过关。
- full-ready超时返回false，调用方立即停止，不用WASD提示覆盖失败状态。
- 恢复3D时撤销较大publication预算，完成presentation后才完成直接入口的输入门。
- building首次画面登记不发生在3D仍关闭时；GameSession保留自己的交接门。
- settle/presentation期间退出、取消时，恢复的协程不把abort写成成功撤罩。

headless通过受控presentation信号验证时序，不冒充实际GPU画面验证。
证据：`test_initial_loading_lifecycle_before_20261025_run.log`、
`test_initial_loading_lifecycle_final_20261025.log`；相对本轮初始快照的独立diff为
`initial_loading_lifecycle_world3d_20261025_final.diff`，完整验证清单见
`initial_loading_lifecycle_validation_20261025.json`。

GameSession仍先持有entry_safety/局部导航scope，最后由自己的交接门放开邻区需求。
该既有生产入口范围并非几何探针的完整当前区域；本轮不把两者混为同一验收口径。

继续复核发现两项既有接线缺口，不能仅凭探针速度放行：World3D的环境/导航准备
会调用GameSession提前恢复3D，使cover仍在时失去covered预算；超时保留的layer1000
内罩会挡住layer100外罩的错误和返回按钮，并在`_input`吞掉按钮事件。修复遵守
初始cover对viewport的所有权，两处调用经过同一边界；失败撤销较大预算、停止
ready tick并锁住玩家，有外罩时交回既有错误UI，直接入口则在内罩显示原因和
返回操作。退掉内罩立即停止输入处理，不等queue_free；不改GameSession需求范围。
这部分独立红测48项/9失败，修后生命周期覆盖扩至49项/0失败；GPU按钮输入结果
另见下方，不能用信号直接emit的接线断言代替鼠标路由验收。

## 已修复：首帧测量跨阶段

`walkg_00`的53.123ms区间为11077.560–11130.683ms，cover于11126.790ms撤除；
`walkg_01`的55.412ms区间为10937.115–10992.527ms，cover于10990.005ms撤除。
附近draw墙钟49.507/53.136ms、draw calls由2变945。它们实际跨越恢复3D首帧，
不能因结束时的phase叫outbound就当作普通步行中的OS空闲。

探针现在为恢复3D→首帧完成→撤罩保留独立`white_initial_first_draw`阶段与精确
时间锚，等下一个观察回调记录该区间后再恢复路线phase。原始帧全部保留，主
full-ready锚不变。报告另说明`process_ms`是Godot约每秒发布的process墙钟最大值，
不是单帧OS线程CPU；stage最近值为0也不能证明OS/GPU空闲。

## 独立跟踪：卸载未归因长帧（低优先，不作已解决）

`pg_03` 62.817ms帧附近，process侧墙钟61.300ms、draw墙钟1.428ms、geometry tick
3.222ms、Deferred service 64µs。现有样本没有匹配的OS线程CPU、native wait或栈，
只能定位为process侧未解释区间，不能写成“OS/GPU空闲、非生产路径”。
保留原始报告；不据此改引擎。后续如优先处理，先用既有CPU/native采样在同一帧
关联，再按实际等待对象取栈。证据：`cover_phase_wait_attribution_review_20261025.json`。

## 独立跟踪：访问冲突（低优先，缺栈）

| 历史样本 | 已知证据 | 状态 |
| --- | --- | --- |
| `coldnoeco_00/01` | 早期优先级/节流夹具组不完整报告，历史记录称AV | 无本地退出summary/栈，不能证明夹具因果 |
| `coldph_04` | 已撤回parallel-hints实验，退出3221225477 | 明确AV，entry已完成5.555s |
| `coldpm_04` | 已撤回metadata-mutex实验，退出3221225477 | 明确AV，entry已完成5.543s |
| `coldpm_06` | 有不完整报告与live.log，未收入6条summary | 未完成attempt，退出原因未知 |

三个对应时间窗的Application 1000/1001与WER目录查询未找到可用历史dump。正常参数
白模探针23次未复现不能证明根因消失，也不是完整游戏23次验证。当前不再运行已
撤回的并行实验，不改变全局WER或进程优先级。若复现，采用特定自有测试PID的
未处理异常dump监视，保存退出码、dump、exe/符号SHA；捕获运行独立于性能基准。

本轮已准备微软签名有效的ProcDump 12.02，封装核验自有子PID、exe和精确创建时间，
只用`-e -mm -n 1`，不注册WER或改变优先级。`cold_exception_capture_03`实际监视
PID85940至exit0，监视器也exit0、无强制清理、无dump；这证明捕获接线可运行，不
证明历史AV根因已修复。此诊断样本full-ready 8.371939s，不并入普通性能基准。
工具、签名、mock验证和真实监视记录在`remaining_white_20261025/diagnostics/`。
原始ProcDump日志含ASCII banner与UTF-16LE主体；原件保留，解码复核另存，不把
普通Exception通知行当作未处理AV或dump。
外部解码封装修正后21项测试通过，实际日志独立复核确认PID85940的Unhandled监视
及正常退出；C0000005通知0。`postprocess-review.json`与UTF-8阅读副本位于该次
capture目录，原始log/capture.json的SHA未变。没有为解析修复重复启动游戏或监视器。

## 本轮GPU与整图回归

结果在外部`remaining_white_20261025/`保存。所有GPU运行通过项目
`tools/run_godot_background.py`的未激活独立桌面执行；每次保存exe/地图/源码SHA、
完整命令和owned PID，未修改priority/QoS。`accepted`仅表示功能回归通过，不代表
性能低于10秒；后续结果另列`full_ready_below_10s`。

- `cover_gpu_01`：7项覆盖加载预算授权检查通过。
- `cover_gpu_final_02`：最终代码13项通过，包括真实`Viewport.push_input`鼠标点击
  直接入口返回按钮、游戏按键阻断，以及内罩retire但尚未free时外罩按钮立即可用。
- `presentation_gpu_01`：7项实际Vulkan呈现检查通过，24次变色逐帧正确、无陈旧帧，
  37个连续帧序号；回调回主线程并跳过已释放对象。
- `traverse_regression_01`：完整就绪6.543709s，failures为空、源码前后相同。
- `game_entry_final_01`：最终代码实际GameSession白模入口通过，内罩started/released
  均true、未abort；玩家落地且输入解锁，Deferred与实例错误为空。入口13.394961s，
  包含完整loading场景、角色、导航和交接，**不是几何探针full-ready**；本次用于
  接线回归，不替代6.918/7.918s基线，也不是默认主循环渲染线程的性能验收。

往返回归在最后两项World3D/失败UI修复前完成；其geometry/probe代码没有再改。
最终版本另通过GPU cover输入、实际GameSession和带异常监视的cold回归。所有普通
与诊断样本单独保留，不拼接成新N10或声称修复后p95。
8次运行的退出码、错误、计时边界与最终源码SHA汇总在`final_validation.json`。

| 3D路线阶段 | 最大帧墙钟 | >50ms帧数 |
| --- | ---: | ---: |
| native departure | 30.795ms | 0 |
| native unload | 32.199ms | 0 |
| native return | 33.562ms | 0 |
| native reload | 38.796ms | 0 |
| 恢复3D首帧（独立遮罩交接阶段） | 60.281ms | 1 |

63/63块地形和最大建筑2151个spec实际卸载，返回后无地形/建筑缺失、无不可见地形。
3814个GPU surface审计无非白模材质；退出时worker、资源回收、admission、lookahead、
模板保留和loading render contexts均为0。加载遮罩内及探针setup的长帧仍保留在
原始帧数组，不把“交互路线0帧>50ms”扩写为整个进程零长帧。

### 保留的cold慢样本

| 样本 | loader | entry | full-ready | hydrate | cold hints |
| --- | ---: | ---: | ---: | ---: | ---: |
| 历史`cold_00` | 2.651s | 4.141s | 7.918s | 0.468s | 0.249s |
| 本轮`cold_regression_01` | 6.867s | 8.328s | **12.304s** | 2.209s | 2.770s |
| 本轮`cold_diagnostic_02` | 2.505s | 3.960s | 8.025s | 0.486s | 0.058s |

12.304s样本没有删掉。相对历史样本，hydrate与cold hints分别增加1.741/2.520s，
解释了loader的4.216s增量；entry→full只增加0.200s。两次均1065次引用读取、4个
worker、1304份定义复制、1065份转移，无fallback，后续1457项索引分类工作不变。
地图、controls和这两条链源码相同，但历史组未存exe字节SHA/实际priority/独立
CPU或I/O记录，不能把环境称为严格相同。后一次带只读CPU/IO计数，未复现慢链；
全部采样调用墙钟合计25.794ms、最大0.602ms，无API失败，I/O计数不等于物理磁盘。

目前只能定位慢段，不能证明根因是OS空闲、磁盘、重复工作或本轮代码。冷hint仍
按唯一模型打开原source取长度，并读取native index和metadata小文件；不解析GLB、
不回退GLB。不能据一次8.025s复测宣布12.304s波动已解决，也不能把历史N10的
7.918s直接作为修改后稳定p95。摘要见`regression_summary_01.json`。

下一条自然首次加载应在启动前启用窄范围分段观测，分别量化资源worker的open/read、
ZSTD和Variant解码，以及cold hints的路径检查、原文件取长度、native索引/metadata
读取；每worker独立累计，结束后写出。不要清系统缓存影响用户，也不要先预读资源
再测首次读取。当前缺慢样本的对应CPU/等待证据，不添加猜测性的生产改动。
