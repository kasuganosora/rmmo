# MockServer 启动等待与 shader include（2026-10-25）

纹理适配的实际地形 shader 画质夹具连续两次在首个样本前超时。测试没有传 `--without-mock-server`，触发了项目的同步兼容启动路径。不能据此声称 Vulkan shader 编译卡死，也不能把关闭 MockServer 后通过当作生产路径已经修复。

## GDB 证据

第三次专用诊断进程 PID 107768，eaec 带符号引擎，180 秒夹具窗口。GDB all-stop 抓栈后 detach，随后由夹具拥有者结束进程；不是普通计时样本。

- 主线程：`Node::_propagate_ready → emit_signal → GDScriptFunction::call → SleepEx`。
- `GDScript::_prepare` 线程：`ResourceLoader::load → _load_complete_inner:1144 → Semaphore::wait`。
- 引擎此处把 `Resource::connect_changed` 和 semaphore post 放入主 MessageQueue，等主线程执行。项目 `mock_server_host._install` 原来只循环 `RenderingServer.force_sync + OS.delay_usec` 等 worker；renderer 同步不会消费这条队列，因此双方互等。

原栈：`editor_dds_20261025/custom_normals01/real_planar/startup_gdb03.log`。两次正常超时和主动结束的诊断日志均保留。画质夹具随后只加 `--without-mock-server`，完成实际贴图对照；以下独立回归另行验证主程序修改。

## 项目修复

非后台兼容模式本来就要求在 autoload ready 后、下一个 autoload 前同步完成，改为直接在此同步准备，不启动一个马上被主线程等待的 worker。服务器节点身份、ready 次序、启动 pack、待发送通知均保持原合同。

游戏正常后台模式保留专用 worker、逐脚本编译交错和后台 pack 准备。若调用方在首帧前提前 `Net.server()`，通过 `ResourceLoader.load_threaded_request/get` 等待同一缓存中的服务器脚本图；原生等待实现负责渲染进度与主 MessageQueue 的资源连接回调。之后才 join 原 worker 的 detached CPU pack 工作。没有加入全局锁、重复解码 pack 或手写 MessageQueue 全局泵。

## 回归与边界

根证据目录：`material_submit_review_20261025/`。

- `mock_sync_red01` 夹具错误地在 `_initialize`、autoload ready 之前检查完成状态，失败并在退出时超时；不能作产品红测。夹具改为 deferred 检查后才使用以下结果。
- `mock_sync_red02`：最小 `tools/test_mock_server_sync_startup.gd`、无预加载服务器依赖，修改前 35 秒超时，未进入检查。
- `mock_host_green01_sync`：修复同步模式后完成，服务器已安装、处理开启、profile background=false，262 个脚本及启动 pack 准备完成。
- `mock_host_green01_background`：既有后台回归全部通过，准备期间主循环运行 1121 帧；同一服务器节点、通知、pack 内容、图像字节与缓存共享均通过。
- `mock_host_green01_early`：只修同步模式时提前访问仍然 45 秒超时，故未宣布修复完成。
- `mock_early_green02` 和 `mock_early_gpu02`：加入原生资源等待后，既有 `test_mock_server_host.gd --require-early` 的所有断言在 headless / 私人桌面 Vulkan 下通过，正常退出。
- 这两个提前访问样本退出时各有 **4 ObjectDB instances leaked** 警告；`mock_early_verbose02` 相同路径加 verbose 后正常退出且没有重现警告。不能把它说成“零警告”或已修复泄漏；保留证据继续关注，尚无对象类型/持有链可证明来源。

上述耗时是功能夹具进程墙钟，含脚本启动，不参与地图加载 ABBA，也不称作冷启动性能收益。正常地图性能夹具继续按既定口径关闭 MockServer；本次修复解决的是另行复现的启动等待，不混算为材质加载提速。
