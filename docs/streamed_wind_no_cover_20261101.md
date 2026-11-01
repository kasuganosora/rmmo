# 区块边缘风场黑屏修复（2026-11-01）

用户报告普通走到区块边缘会黑屏并出现风场提示。根因是项目主动进入加载事务：`World._update_preparation_hint` 发现新风动材质后调用 `_recover_streamed_wind`，创建标题为“正在准备附近风动材质”的 `TransferLoading`，锁定玩家输入、停止玩家/战斗物理，并在遮罩绘制后关闭3D视口。旧 HTTP/GPU 用例把这一行为当成正确合同，因此此前组件通过并不代表游玩体验正确。

本次删除普通区块流送的这条覆盖事务。显式地图传送及初次进入的加载流程不在本次删除范围。晚到的风动模型继续显示原有材质，冷 shader 在共享后台队列中准备；就绪后由原有2ms预算扫描接入风动。普通走动不因此黑屏、锁输入、暂停物理或关闭3D视口。

## 实现边界

- 同一个 shader key 跨世界/多接收者去重，全局最多一个冷准备任务。后台只持有私有标量配置、Shader 和预备 ShaderMaterial；不访问 Node、共享材质或源模型。准备后的同一 Shader RID 发布到现有缓存，各接收者仍有独立材质参数。
- 首次私有 material RID 准备走现有引擎 candidate09 的后台 shader 路径。特别不能调用 `Shader.get_shader_uniform_list`：4.8 该 getter 通过 `push_and_sync` 等主渲染线程，关闭时主线程又可能在等 worker，形成互锁。最终代码没有该调用。
- 主线程只在任务完成后回收任务句柄并发布；节点退出不等待任务。排队任务只保存弱消费者，所有消费者消失时在真正派发前取消。已派发任务可独立完成共享资源准备，不再回调旧世界对象。
- 初始/显式加载的 covered 队列如遇到已有后台任务会逐帧等待，不重复编译，也不在主线程 join 活跃任务。原来的材质恢复、表面成组接入和可编辑属性保留。
- `preparation_test_gate` 生产默认 null，仅用于用例明确阻塞 worker，证明主线程、取消和退出不依赖该任务完成；不引入运行期等待开关。

## 证据

证据根目录 `P = D:/code/rmmo_runtime/review_artifacts/runtime_wind_no_cover_20261101`。`validation_receipt.json` 保存各源文件/引擎/日志 SHA，`qualified/` 保存测试时字节。测试使用实际 Godot 4.8；没有重跑全城 FPS 对照或将组件时间换算成整体收益。

| 检查 | 引擎 | 结果 |
|---|---|---|
| 实际 World 提示入口 + 真实晚到 wind receiver 红例 | 默认 candidate10 | 3通过/3预期失败：创建cover、锁输入、停止物理；0脚本/引擎错误 |
| 同一 World 入口绿例 | 默认 candidate10 | 6/6，保持原材质可见、没有cover/输入锁/物理暂停/disable3D |
| 阻塞真实worker、跨世界去重、排队取消、active owner退树 | 默认 candidate10 | 17/17；worker阻塞期间主循环推进8帧，main_thread_builds=0 |
| 原有 covered 准备及新后台协作合同 | 默认 candidate10 | 26/26；多surface整体接入、恢复原材质、失效来源清理不变 |
| 隐藏桌面 Forward+ 实际渲染 | 外部 candidate58 | 15项通过，8组细节/近中远/固定风时画面逐字节相同，最大通道差0；晚到新key正常完成 |
| 整个进程 GPU 退出时仍有风场任务 | 外部 candidate58 | exit0、0错误；quit与SceneTree._finalize均记录active=1、pending=2、completed=0 |
| 完整真实 HTTP 编辑器/试玩回归 | 外部 candidate58 | HTTP02 65/65、exit0、0错误；worker被阻塞时仍可操作，随后真实接入，停止试玩不等待该worker |

整进程退出用例为 `tools/test_wind_pending_shutdown.gd`：一个风场任务已派发、另一个key排队；有限1.5秒延迟由另一个worker释放 gate，不依赖主线程回调。退出码来自 `run_godot_background.py` 等待的真实进程；打印“finalized”本身不算通过。此用例与 `stop_playtest` 的节点生命周期验证分开。

图像在外部 `wind_cutout_20261018/wind_7839891/`，原图用于精确比较；实际查看的是 `P/near_background_q90.webp`，有损WebP quality90，尺寸640×480，压缩与SHA记录在同名json。可见真实受风形变及投影，不是空画面比较。

保留无效夹具：red01先删除旧cover再等待一帧，暴露旧协程“script is gone”错误；有效red02将旧图交给SceneTree关闭，单独复现错误呈现行为。green_parse01为两个测试weakref变量缺少显式类型，没有运行生产逻辑；补类型后绿例通过。

## 总集成确认

默认引擎候选10退出死锁由另一路调查修复，本专项不把外部candidate58当作最终安装版本。纯candidate10+退出修复构建已通过 `test_wind_pending_shutdown.gd`：quit/finalize时均active1/pending2/completed0，进程exit0、0错误；也通过实际游戏原生窗口X/WM_CLOSE。证据在相邻 `runtime_blackout_exit_20261101/{wind_pending_fixed01,game_close_fixed01}`，准确引擎SHA及安装记录见 `runtime_streaming_blackout_shutdown_20261101.md` 与交付manifest。窗口退出资格不等于沿路所有场景显示已验收；可视范围缺项另行处理。

`test_wind_recovery_http.gd` 已把“晚到材质自动黑屏”的旧断言改为后台准备时仍可操作，并加入停止试玩不等待活跃wind worker。输出使用 `RMMO_WIND_HTTP_ROOT` 或每次唯一外部目录，已存在目录拒绝运行，不覆盖旧证据。

完整 HTTP02 已通过65项，真实MCP接口覆盖未就绪状态、保持操作、材质接入、停止/重开，以及原有显式传送、撤销/重做和保存不变。夹具先等待第一次 `RenderingServer.frame_post_draw` 后发起首个RPC，记录绘制前后ticks；共享RPC的严格5秒期限没有修改。空RPC会直接记录 `http_failed.json` 并退出，防止父夹具访问空结果后空等240秒。

HTTP01失败保留：当时尚未开始试玩，首个tools/list在5秒期限内没有返回；父夹具随后访问空result，最终240秒退出。只读外部观察确认该测试进程的MCP仍正常响应idle状态。HTTP02第一次绘制等待实测仅16.848ms，不能据此将HTTP01失败精确归因于首次绘制，也不能据此宣称修复了通用MCP性能问题。两次都使用新隔离cache，并有并行引擎编译负载；本轮不做耗时对照。HTTP02仅构成在明确首次绘制就绪条件下的功能资格。

证据 `P/http01/{run.json,failure_scope.json,live_state.json}`、`P/http02/{run.json,http/http.json}`；最终HTTP夹具SHA `d3ceb7be1b3c056207ca4de9ba9430f66ff785d71bc5a476cc65a1aa455383ea`。源码、组件、HTTP以及最终安装引擎上的真实游戏验收各自记录。
