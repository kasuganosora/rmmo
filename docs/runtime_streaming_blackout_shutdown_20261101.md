# 游玩中黑屏、原生窗口退出与可视范围补全（2026-11-01）

用户实测报告两个阻塞使用的问题：走到区块边缘突然黑屏并显示风动准备文字；点窗口 X 后长时间卡住。随后补充第三项：最小近邻只用于尽早进入游戏，进入后必须继续异步加载整个可视范围内的全部物件，包括建筑、植被、道路、桥梁、道具及远景，不能停在出生点附近一圈。按顺序先修前两项，再检查第三项。

本轮不恢复已清除的目标，不跑 FPS 对照。模型和正式地图不修改。测试使用 Godot 4.8、独立桌面及临时地图；其他会话 WIP 保留。`E` 为 `D:/code/rmmo_runtime/review_artifacts/runtime_blackout_exit_20261101`，风场组件证据在 `D:/code/rmmo_runtime/review_artifacts/runtime_wind_no_cover_20261101`。

## 1. 区块边缘黑屏是主动加载遮罩，不是 GPU 丢画面

`World._update_preparation_hint` 发现晚到的风动材质后调用 `_recover_streamed_wind`。旧方法创建标题为“正在准备附近风动材质”的 TransferLoading，锁输入、暂停玩家/战斗物理并关闭 viewport 的 3D。旧 HTTP 用例甚至把进入游戏后再次出现 cover 作为预期行为。此次用户明确否定这一合同。

有效独立红例使用真实 World 提示/恢复路径，3项通过、3项预期失败：创建 cover、锁输入/transfer、停物理。第一份红例因夹具提前 free、旧协程随后恢复造成脚本已释放错误，保留但不作为有效复现。

修复方向：初始加载及显式传送仍沿用自身呈现协议；游玩中晚到风动对象保留当前可见材质，共享去重的后台任务准备 shader，完成后由主线程分片接入。风场缺项不再创建加载遮罩，不锁玩家，不关闭3D。任务只操作私有资源，节点退出不等待仍在运行的任务。

审查曾发现候选中的 `Shader.get_shader_uniform_list()` 会通过 `push_and_sync` 同步等渲染主线程，可能与引擎退出互锁；已在有效运行前移除。后台仅使用默认引擎已有 candidate09 的 shader/material 准备接口，覆盖层 Shader RID 复用不改变最终风动算法。

headless 初步绿例：无 cover 6/6；真实阻塞 worker、多世界共享、排队取消及 active owner 退树17/17；covered 合同26/26，合计49项、0错误。完整 GPU 与退出资格另记后续结果，不能用普通节点退出代替整个进程退出。

## 2. 默认引擎确有已排空任务后的退出死等

默认引擎原为 candidate10，EXE SHA `7a8029a67b0e0bbc442c12f5ebf0aa67baf2e53f65c8750dd5fbb6b4adabdb53`。已有 worker shutdown candidate13 补丁未装入默认入口；旧13二进制还包含11/12，不能当作纯退出补丁直接安装。

本次重新运行 `tools/check_worker_pool_pending_shutdown.py`：低优先级任务3/3到8秒截止仍不退出，高优先级3/3正常退出，0脚本/引擎错误。单纯超时不足以定性，因此进一步用 GDB18.1 加载默认10的匹配符号确认线程状态：

- 主线程在 `WorkerThreadPool::exit_languages_threads:870 → Main::cleanup:5302`。
- 状态为 `PRE_EXIT_LANGUAGES`，仅3/12 worker登记空闲。
- 普通及低优先级队列全部为空，正在执行的低优先级任务为0。
- 12/12 worker都在 `_thread_function:213` 的条件变量休眠。

因此这是退出阶段缺少唤醒，不能解释成剩余任务仍在慢慢计算。证据 `E/default10_shutdown_red01`、`E/default10_shutdown_gdb01/{summary.json,result.json,gdb.mi.log}`。GDB样本只用于状态证明，不作为性能对照；其他会话进程均未触碰。

为避免混入未交付引擎改动，隔离重建官方4.8 beta1 + candidate08累计补丁 +09 +10 +13。10阶段55个源SHA匹配原默认构建；相对默认10的生产源只有 `worker_thread_pool.cpp` 变化。当前58源码及默认安装均不在构建时改写，对象缓存仅独立复制，不硬链接。构建与后续安装凭据在 `E/engine10_shutdown_only_setup`。

## 真实游戏 X 关闭夹具

`tools/test_game_window_close.gd` 通过正式 `GameSession.go_world_3d()` 进入游戏；宿主 `tools/check_game_window_close.py` 在私有桌面向属于本次进程的 HWND 发送真正 `WM_CLOSE`。成功路径不使用 `quit()` 替代关闭。验证可玩/可见、native close、World 退树、root退树、SceneTree finalize及正常进程退出；超过截止只终止持有句柄的本次进程。

宿主关闭至 runner 返回时间包含最多200ms轮询和管道收尾，只记观察上界；应用阶段耗时使用引擎 `ticks_us`。地图快照SHA为 `a2808a3fc088c601c4a5913ec8f97ea7603b4de49858c29ff7bd742861696f44`，位于外部 `cache/world3d/runtime_blackout_exit_20261101`。

最初两份真实游戏夹具未进入游戏：临时副本遗漏相邻资源引用闭包，报 `Resource reference escapes adjacent directory`。原始失败和其过早退出后的异步HUD加载错误保留，不能算作窗口关闭复现或修复。随后补齐1769个引用资源、98,299,222字节；地图原字节不改，正式地图未写入。

第三、四份样本已进入游戏并保持3D可见，但宿主仍在默认desktop查询私有desktop的HWND，或从子进程thread取到不可用desktop句柄，安全归属检查拒绝发送关闭；不是游戏响应X失败。第四份完整stdout保留，第三份回调异常的stdout未返回这一夹具边界也保留。

现为 `run_godot_background` 增加可选 `on_desktop` 回调，借用该runner自行创建的desktop句柄；仅新helper线程加入它、核对本次PID并发WM_CLOSE，仍不调用 SwitchDesktop、不激活窗口、不改变宿主主线程desktop。所有原调用默认行为不变。新增实际 Win32 子窗口关闭用例通过，原有输出/超时/进程归属回归一并7/7通过。接口依据：[SetThreadDesktop](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setthreaddesktop)、[GetWindowThreadProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowthreadprocessid)。此处仅证明宿主能正确发送窗口关闭，不能代替下面的真实游戏退出资格。

`E/game_close_default10_05` 是第一份有效真实X样本：正式进入游戏、3D可见，实际收到WM_CLOSE，所有退出阶段顺序完整，exit0、0错误。关闭事件→World退树107.041ms，→SceneTree finalize555.392ms；宿主观察上界3.063秒。该样本与本次引擎编译并行，只记录，不作干净性能对照。它说明实际游戏并非每次关闭都命中死等，不能用这个通过样本推翻上述3/3独立复现及空队列GDB证据，也不能把当前2.5秒左右的其余进程收尾全部归因worker死锁。

## 新构建资格与交付

纯默认10+13构建已完成，EXE SHA `b981f16e36c93cd3f1ad8eeb2be519339c22ade1d8888f70b3a3eca066c9bf86`，符号SHA `b74861e86ada3a4cd38328e0c95be8abb32de912e7c03812d928cd3df306c3ec`。构建117个单元、exit0；源差仍仅worker退出唤醒。资格是实际运行，不以静态检查代替：

- `E/shutdown_fixed01`：低优先级3/3、高优先级3/3正常退出，0错误。低优先级1.734–2.203秒；该原生任务夹具原默认10为3/3超过8秒截止。
- `E/wind_pending_fixed01`：真实GPU、私有桌面；quit及SceneTree finalize仍有active=1/pending=2/completed=0，进程最终exit0、0错误。
- `E/game_close_fixed01`：实际游戏、3D可见、真实WM_CLOSE及完整有序退树，exit0、0错误。close事件→SceneTree finalize500.046ms；宿主观察上界2.844秒。不能把默认有效样本3.063秒到2.844秒当性能收益，修复目标是已复现的退出死等。
- 风场完整证据另见 `streamed_wind_no_cover_20261101.md`：49项逻辑、15项GPU（8组画面字节完全相同）、65项真实HTTP检查通过。

第一次安装版本探针拒绝并完整回滚，所有13项文件SHA恢复成功。新构建源为官方4.8-beta1，但生成版本显示 `4.8.beta.custom_build.4d10419ca`，没有继承旧构建环境的 `beta1` 显示标签；不是引擎进程退出失败，也不是源码commit改变。原失败探针没有落盘stdout，独立重探证据不能冒称原输出；诊断为 `E/engine10_shutdown_only_setup/version_failure_diagnosis.json`。安装器随后在修改目标之前校验真实版本receipt和生成头，逐别名版本探针先落盘再验收，保留回滚机制。

第二次安装已成功：默认入口、console、3个别名及匹配符号共7文件独立SHA复核通过，5项版本探针exit0/stderr空，4份其他补丁元数据保持原SHA。安装凭据 `E/engine10_shutdown_only_setup/installation_attempts/20261101_195410_525953/installation.json`，回退副本 `D:/tools/godot/_backup/before_10_shutdown13_20261101_195410_525953`。仓库交付索引为 `tools/engine_patches/godot-4.8-beta1-default10-shutdown13-manifest.json`；未安装candidate11/12/58其他变化。

## 可视范围缺项调查

最小可玩放行后，正式路径确实恢复了Deferred scope并持续运行，不能预先归咎于“队列主动停止”。但代码存在明确策略断层：通用player需求只覆盖±128m；远景票仅building/road/structure/terrain；未带render_bounds的普通物件在WorldStream只绘制3×3个32m区块。首次未被分类的导入房屋也不能依赖“先加载后识别building”来获得初次远景需求。

修复必须同时统一请求、候选选择、发布和回收的视觉范围，碰撞维持近邻；不能只扩大房屋标签或扩大队列。相机当前实际far=4000，旧1km建筑距离也不等于全部相机可视范围；按实际投影及宽高比覆盖远平面角落，不通过缩短相机远裁面掩盖问题。当前正在用独立红例及固定正式地图副本记录可视范围未请求/已加载未显示的对象，再进行修复。
