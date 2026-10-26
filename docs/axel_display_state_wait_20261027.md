# 2026-10-27：重复显示设置触发交换链重建

承接 `axel_road_cleanup_and_native_capture_20261027.md` 的静止首两帧归因。
本轮未改引擎、地图、材质、worker 数或发布预算。主分支为
`codex/latest-map-runtime-review`，测量使用隔离 worktree。

## 证据和实际原因

证据根目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/first_draw_wait_20261027/`。
引擎仍为 collision_debug_20261026/engine09，SHA256
`40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`。
匹配符号 SHA256
`3039c3ba7fbb71f965ec42cb9100a483a439e95b6cfda3ed194cfae54989db76`。
`source01_verification.json` 确认此前六个引擎修改源文件与 build09 清单一致。

`attach02` 普通优先级启动后附加 GDB，以 PID、创建 FILETIME 和 exe 校验所有权。
监视已有 post-ready steady 日志后请求一次 DebugBreakProcess，实际相隔 26.735ms。
主线程栈落在：

```
NtGdiDdDDIWaitForSynchronizationObjectFromCpu
AMD Vulkan driver / vulkan-1 / we-graphics-hook64
RenderingDeviceDriverVulkan::swap_chain_resize (3845: CreateSwapchainKHR)
RenderingDevice::screen_prepare_for_drawing
RendererCompositorRD::blit_render_targets_to_screen
RendererViewport::draw_viewports
RenderingServerDefault::_draw
Main::iteration
```

`RenderingServerDefault::create_thread=false`，这一运行由主线程执行 draw。
引擎 `RenderingContextDriverVulkan::surface_set_vsync_mode` 即使收到相同值也设置
`needs_resize=true`。probe 在加载开始、可操作入口、post-ready 观察开始三处重复
提交 VSYNC_DISABLED；第三次紧邻已有 steady 长帧。正式游戏的
`GameSettings.apply_display()` 也无条件重设模式、尺寸和 VSync。

这次栈说明交换链重建的驱动等待，不是后台几何占满队列。不能仅因栈含 hook DLL
就归因于它，也不能把主动 SIGTRAP 当成原有 0xC0000005。GDB 暂停样本仅作诊断，
继续后 engine/GDB 均退出 0、功能通过；不计入普通帧统计。

官方 visual profiler 的 `visual01` 另揭示不同问题：首个 3D frame3398 的 CPU
render 跨度 62.344ms、GPU 跨度 1.227ms，其中 Setup 3D Scene CPU 47.556ms。
后续 frame 的 render CPU 约 4.5–6.1ms。该首次场景准备成本与 steady 处重复 VSync
重建分开追踪。profiler 的 frame payload 已保留；新记录 render_frame 以对应 GPU
提交帧，不能只拿 process frame 硬对齐。240 条 profiler warnings 原样保留，未出现
非 warning 错误；完整就绪 11.402s 为诊断数字。

## 修复

新增共享 `scripts/util/display_state.gd`：只在 DisplayServer 实际状态不同的情况下
提交 VSync、窗口模式或尺寸；headless 跳过。读取实际状态，而非记住上次偏好，因此
OS 或其他入口改变窗口后，偏好仍能重新应用。显示操作继续由主线程执行，避免把
窗口线程要求变成后台线程竞态；本次直接去掉无效调用。

正式 `GameSettings.apply_display()` 接入该工具，保留分辨率白名单、FPS cap 和实际
模式变更。地图 probe 的三处 VSync 统一接入同一工具；显式
`--legacy-vsync-submission` 只存在于测试入口，可复现旧调用，生产无旧路径开关。
report 记录 requests/submitted/legacy，runner 的命令和清单同步保存该开关。

## 独立复现与功能测试

所有 GPU 用例经 run_godot_background.py 在独立且不激活的桌面运行，未修改用户
显示偏好文件，测量区间为请求至包含该请求的下一次绘制完成。

| 用例 | 修复前 | 修复后 |
| --- | --- | --- |
| 同值 VSync，12 次 | 12 次 native 提交；25.358–27.793ms | 0 次提交；0.600–1.439ms |
| 正式 apply_display，8 次 | 29.993–45.295ms | 0.756–3.936ms |

证据 `fixture03_raw`、`fixture06_guarded`，分别 15/0、20/0；后者还验证真实
enabled/disabled 切换与尺寸正确的已绘制帧。`settings05_before`、`settings07_after`
均 15/0，真实支持的分辨率切换、VSync 改变、外部模式改变后的恢复、FPS cap、
无边框和返回窗口均通过。这里的 ms 包含正常绘制，不是纯函数 CPU 时间。

保留失败 `settings04_before`：13 项中 1 失败，夹具错误请求不在项目白名单的
960×540 并期待生效。修正夹具为已有 1600×900 后，旧生产实现和新实现均通过，
未为通过测试放宽分辨率合同。首次 PowerShell GUI headless 启动未得到有效日志，
不作测试证据；`settings09_headless.log` 使用 Python 等待真实退出 0，原有
test_game_settings 的持久化、音频、HUD 和设置窗口检查全部通过。

## 普通整图 ABBA

`map10_A1 / B1 / B2 / A2`，均正常优先级、无 GDB/profiler/故障扩展、无 QoS 或
OS 缓存修改。A 为 probe 原始重复 VSync 提交，B 为去重；生产 GameSettings 的
修复在两组都存在。因此整图对照证明的是 probe 重复设置造成的额外等待被移除，
生产设置重应用的改善由上面的独立 GPU 用例证明，不能宣称全游戏持续 FPS 同幅增加。

| 样本 | 完整就绪 | 静止最大帧 | >50ms | 1% low | VSync native 提交 |
| --- | ---: | ---: | ---: | ---: | ---: |
| A1 | 9.433494s | 58.427ms | 1 | 40.176 | 3 |
| B1 | 9.266213s | 22.556ms | 0 | 50.590 | 1 |
| B2 | 9.263703s | 22.580ms | 0 | 51.780 | 1 |
| A2 | 9.298107s | 50.975ms | 1 | 43.179 | 3 |

全部源/地图未变、功能通过；1Hz 宿主观察未发现其他 Godot/Blender/编译/GDB 进程。
完整就绪均值 9.365801→9.264958s，仅少约 0.101s；两条/组不足以报告 p95 或长期
稳定性，更不能称作模型加载吞吐大幅增长。1% low 是最慢 ceil(N×1%) 帧平均耗时
的倒数；四条所有原始帧保留，未删首帧或把旧尖峰换阶段标签。

四条初始工作量完全一致：231 rebuilds、2724 packed source visits、3923 prepared
source visits、229 groups、2564 source objects、2352429 source vertices、2299528
render vertices、361 render surfaces、live worker joins 0。测试中的 311 路面 paint
异步候选仍显式开启；普通游戏该候选仍默认 false，不能据此关闭既存无栈 AV。

口径仍是地图加载计时开始到需求/作业/流式/合批连续三次完整并排空像素消费者。
首个呈现和 audit 另有原始阶段。几何、边界和元数据派生缓存禁用，native、派生索引、
纹理磁盘缓存保留，OS 缓存不动。当前为地图/预制件纹理阶段，导入模型材质仍白模。

## 后续

`map11_B` 正常卸载/返回复测完整就绪 **9.358698s**，功能、源和地图检查通过，
全部阶段未观察到其他相关进程，初始工作量与 ABBA 一致。`summary13.json`
包含五条普通样本的阶段统计、上传/paint/Deferred 计数与宿主观察。

| 阶段 | 最大帧 | >50ms | 1% low |
| --- | ---: | ---: | ---: |
| 静止 | 23.346ms | 0 | 46.802 FPS |
| 卸载 | 44.540ms | 0 | 105.161 FPS |
| 返回 | 38.642ms | 0 | 45.815 FPS |
| 重载 | 46.835ms | 0 | 28.512 FPS |

这是一次正常往返，不冒充 p95 或证明所有长帧消失；重载 low 仍有明确改进空间。
旧 N/map14 的重载 50.808ms 与新 46.835ms 不作为该显示修复的因果收益：旧样本
相应阶段有 Blender 重叠，而且显示设置调用发生在初始阶段。此次完整往返证明
这一修复未破坏正常卸载、重建、提交和最终资源释放合同。

首个 3D frame 的另一组 GDB 已完成，全部与普通性能结果分离：

- `first12`：settled 日志后 8.339ms 请求中断，主线程在 RtlAllocateHeap →
  PagedAllocator<GeometryInstanceSurfaceDataCache>::alloc →
  _geometry_instance_add_surface_with_material → _geometry_instance_update →
  _update_dirty_geometry_instances → _fill_render_list。32,768 字节是分页分配器的
  可用指针数组，不是每个材质各分配 32KB；单次采样不能证明分配占据整个 48ms。
  engine/GDB 退出 0、功能和源码检查通过。
- `first14`：28.719ms 请求中断时已进入 transparent render list，栈保留；额外 GDB
  Python 检查器的 Windows 路径被转义，退出 1 并 detach，未得到实例计数。引擎
  正常退出、功能通过。这是诊断脚本失败，不是游戏崩溃，失败文件全部保留。
- `first15` 修正检查器路径后，在 7.105ms 采到 Vulkan texture_create →
  VmaAllocator::AllocateMemory → AMD driver；上游是 RenderSceneBuffersRD::ensure_velocity
  → get_color_pass_fb → _render_scene，R16G16_SFLOAT 图像请求 6,324,240 字节。
  这是首次绘制所需速度缓冲的显存分配栈，不能把它冒充地图纹理解码，或未经对照
  就禁用 TAA。renderer this 被优化掉，本次也未取得实例数量；engine/GDB 退出 0。

普通五条从恢复 3D 到首次绘制完成仍为 **65.030–75.300ms**，原始观察帧
68.845–78.686ms。去重 VSync 并未消除它。下一轮应先取得渲染实例/缓存数量与
首次缓冲分配分段耗时，再独立复现必要建立、重复建立及等待；不能仅凭上述瞬时
栈认定源实例多余，或把工作挪到 cover 里就声称总工作减少。重载 low 的主要帧
还要结合已保留的 map11 frame-split 逐段归因。

原始 native AV 与道路冻结测试的既存 13 处字节差异
仍按上一份记录单列，未在本轮修复；道路 paint 异步候选不擅自解除门控。
目标保持 active，尚有首次材质提交和 covered publication 的可定位成本。
