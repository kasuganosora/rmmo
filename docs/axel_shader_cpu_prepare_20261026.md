# Vulkan shader CPU 准备移出设备锁（2026-10-26）

本轮接续 `axel_shader_transfer_20261026.md` 的实际 GDB 等待链：后台在
shader 解码 / re-spirv 解析时持有 RenderingDevice mutex，主线程绘制中的
`uniform_set_is_valid` 等待同一把锁。上一轮 compact + move 减少了复制，
没有解除解析期间的设备锁。本轮先独立复现，再拆开每次调用私有的 CPU 数据
准备与需要设备锁的 GPU 创建 / RID 发布。没有增加 shader 变体或隐藏预热。

## 实现及所有权

补丁 `tools/engine_patches/godot-4.7.2-shader-cpu-prepare.patch` 应用在已含
上一轮 `godot-4.7.2-shader-data-transfer.patch` 的引擎源码上。

- Vulkan container 新增仅本次调用拥有的 PreparedData：每阶段解码结果和
  re-spirv 解析结果。不写磁盘，不放共享缓存，也不改变 shader 输入。
- container 反序列化、reflection、ZSTD / SMOL-V 解码、re-spirv 解析与
  无 specialization 时的原有优化移到设备锁外。reflection 只生成一次，
  提交后 move 给 Shader，消除原有 RD / driver 重复生成。
- sampler RID 查询、Vulkan module / layout 创建、RID owner 分配和占位
  RID 替换保留锁保护。解锁后才销毁私有准备缓冲。
- 非 Vulkan 后端不启用锁外准备，仍走原有 driver 创建入口；本轮没有对
  非 Vulkan 后端做运行验证。
- `RMMO_SHADER_PREPARE_UNLOCKED=0/1` 在同一二进制切换锁范围。本节原始
  engine03 默认 1；完成 map12 后，交付候选改为默认 0、显式 1 才开启，
  保留实验实现而不默认启用未证明整图收益的路径。
  这是锁范围对照，不是原始引擎与候选的完整对照，两组都含 reflection 复用。
- 既有 `RMMO_SHADER_TRANSFER_MOVE` 保留，正常样本固定 1。

stage 缓冲由原先逐阶段复用改为同一容器内同时保留到提交结束，可能增加临时
内存。新增诊断 `buffered_bytes` / `largest_stage_bytes` 用于记录该成本；
这是逻辑 buffer 字节，不是 RSS / VRAM。并行容器的生命周期也可能重叠。

## 引擎身份

隔离候选 `shader_prepare_20261026/engine03/godot.windows.editor.x86_64.exe`：

- EXE SHA256 `a0665661e75d8a038cf83f36177feb9c8cdfb17348c32cfaf01e7ae0fba76a0f`
- symbols SHA256 `9dbc1e14e18882fb99ab31217fa48d7e083f8ac52888ca50a2841ef839ff7450`
- `build03.json` / `build03.log`：MinGW 15.2，optimize=speed、无 LTO，
  引擎实际 `-fno-exceptions -fno-rtti`，exit 0，385.625 秒。
- 源码前副本在 `before02/`，生成过程 `prepare_split02.py`，前后 SHA
  在 `split02_sources.json`，补丁反向 apply 检查通过。

本轮尚未替换 `D:/tools/godot` 默认安装（仍为 `0f0bf446…`）。后续包含碰撞
修复、shader 拆锁默认关闭的 engine09 身份见
`axel_collision_debug_refresh_20261026.md`。原始默认开启的源码 / 补丁快照
在该证据目录 `before08/`；这里的 micro05 / map09 / map12 数据身份不变。

## 独立复现和固定工作量压测

`tools/stress_shader_creation_lock.gd` 使用上一轮真实 GDB 捕获的 SPIR-V，
取最大的 16 个阶段，先转换一次容器，再固定分配给两个 worker。
每个 shader RID 保留到两者完成后统一释放；主线程每帧执行同一 RD 查询并
绘制 ColorRect。正常模式不写逐帧进度文件。此处没有执行被捕获的 shader，
实际 GPU 输出另由材质回归验证。

修改前 engine22 的 `baseline01`：128 次创建 / 释放，43 项检查通过，
壁钟 92.615ms，主线程 RD 查询最大 42.675ms，帧间隔最大 50.432ms。

候选同一二进制 `micro05`，固定 512 次创建 / 释放、16 个相同输入，ABBA：

| 样本 | 锁外准备 | 壁钟 ms | 主线程 RD 查询 max ms | 帧间隔 max ms |
| --- | --- | ---: | ---: | ---: |
| A1 | 关 | 470.713 | 22.094 | 349.144 |
| B1 | 开 | 271.205 | 0.131 | 32.798 |
| B2 | 开 | 315.151 | 0.263 | 32.182 |
| A2 | 关 | 425.085 | 15.045 | 211.551 |

壁钟均值 447.899 → 293.178ms（-34.5%）。全部输入、创建 / 释放数量和
语义检查通过。不同轮次的正常调度会影响帧数 / 检查次数。该结果证明独立
负载的锁争用收益，不当作整图加载或游戏 1% low 收益。

## GDB 实际暂停单个 worker

`pause_worker04.py` 使用 GDB 18.1，断在实际
`RenderingDeviceDriverVulkan::shader_prepare_from_container`。核对拥有的
进程 PID / 创建时间 / 可执行文件，以及目标 OS 线程确实不是主线程，然后
删除断点，以 Win32 SuspendThread 只挂起该 worker，再让 GDB 恢复进程。
观察 2 秒后抓主线程 / 被暂停线程栈，finally 中平衡 ResumeThread，最后
detach 并等测试正常结束。8 秒看门狗均未触发。

Windows GDB 本身仍为 all-stop；没有宣称获得 GDB non-stop 支持。
此试验不是普通性能样本，不修改引擎内存、优先级或 QoS。

| 样本 | 被暂停 worker 所在位置 | 另一 worker 完成 | 主线程进度 | 最终创建 / 释放 |
| --- | --- | --- | --- | --- |
| pause06_A1 | 持 RD 锁准备 | 0 | 不推进 | 256 / 256 |
| pause06_B1 | 锁外准备 | 128 次 | 推进至 109 次采样 | 256 / 256 |

A 的主线程栈为 `RtlEnterCriticalSection → RenderingDevice::uniform_set_is_valid
→ RendererCanvasRenderRD`；B 的主线程已在 Vulkan present。B 观察期间
被暂停线程仍停在准备入口，另一 worker 完整执行自己的固定分片，恢复后
所有工作完成。两组没有失败或额外引擎错误，源码不变。

## 错误路径和 GPU 语义

`tools/test_shader_preparation_failure.gd` 先生成具有 specialization 的
vertex 和 fragment 两阶段容器；只在本地副本破坏第二阶段 SMOL-V 头，
迫使第一个阶段已准备后失败，不把无效 SPIR-V 交给 Vulkan。

旧 engine22、候选锁内、候选锁外各运行 4 次失败 / 重试。每组 18 项检查：
失败返回无效 RID、RD 仍可查询、有效输入重试复用原占位 RID、全部释放、
共享输入字节未修改。三组均通过。每组恰好 4 条预期解码错误与 4 条对应
调用返回错误；`run_map09.py` 按完整错误列表精确核对，没有宽泛忽略 ERROR。
这是释放路径及恢复性验证，不是 allocator 泄漏检测器。

`gpu07` 的 prepared material publication、material publication、ground
batching 三组全部通过。`residency07` 的保留上限 0 / 2 / 32 / 0 四组共
36 项通过：相同 red / green / red GPU 回读 SHA、最后 owner 释放及并发
材质复用仍符合原合同。

## 首组真实地图对照及外部负载混杂

`run_map09.py` 固定先保留首次地图 `first09`，再运行 0 / 1 / 1 / 0 四次
完整遍历。原生逐容器诊断关闭，几何 / bounds / metadata 缓存关闭，native
和纹理磁盘缓存保留，不清 OS 缓存，不调整优先级。地图材质开，导入模型
材质仍白模，HUD / MockServer 关。不是物理冷盘，也不是完整游戏所有系统。

full-ready 沿用地图计时开始至当前需求连续三帧完成，并包括共享像素队列
和合批清空；不以 cover 揭开或进程启动替代。1% low 使用各阶段最慢
ceil(N × 0.01) 帧耗时均值换算，四个样本不宣称稳定 p95。

首次地图功能通过，entry 6.867921s、完整就绪 **15.681600s**；保留慢样本，
没有证据将其归因于某一种缓存。四次完整遍历功能通过，源码 / 地图不变。

| 样本 | 完整就绪 s | 卸载 max ms | 返回 max ms | 重载 max ms / >50ms | 重载 1% low FPS |
| --- | ---: | ---: | ---: | --- | ---: |
| map09_A1 锁内 | 11.121 | 31.211 | 47.606 | 54.870 / 1 | 26.102 |
| map09_B1 锁外 | 11.163 | 36.660 | 41.041 | 49.111 / 0 | 23.406 |
| map09_B2 锁外 | 11.573 | 70.028 | 43.006 | 85.819 / 3 | 25.103 |
| map09_A2 锁内 | 11.388 | 31.882 | 35.494 | 46.573 / 0 | 26.439 |

算术均值完整加载 11.254824 → 11.368198s，重载 1% low 26.270 →
24.254 FPS，返回 1% low 40.160 → 43.290 FPS。**不能用此组作严格引擎
收益 / 回归判断**：全程只读 `host09.jsonl`（639 条）发现 B2 同期有多次
其他 Blender 任务，单进程最高约 9.45 个 CPU 核，系统 CPU 峰值 100%；
B2 后段及 A2 前段有其他 Godot 运行。A1 / B1 没观察到这些相关进程，
二者也没有显示总加载明显改善。进程重叠不是已经证明某一帧的唯一原因。

B2 卸载 70.028ms 帧的 Deferred 六项累计约 1.063ms；重载 85.819ms
帧约 0.675ms。周期 process monitor 分别为 24.504 / 39.400ms，不能当
逐帧 OS CPU。该组和全部慢帧保留，不改判成 OS 空闲，也不静默丢弃。
四次材质提交 max 为 123.085 / 104.567 / 123.370 / 105.157ms，仍较长。
四组静止段也都有 >50ms 帧，未完成归因。

纹理上传各 170 次 / 721332072 B。异步模型 68 / 62 / 64 / 64，实例
3271 / 3266 / 3290 / 3270，不声称整个遍历的工作次数完全相同。
外部活动明细见 `host09_summary.json`。补测将增加运行前只读安静期检查，
不暂停或终止用户和其他 agent 的进程；运行中仍保留负载与全部结果。

## 原生阶段计时与临时内存

`diag10` 两组功能通过，都是 688 个容器：bootstrap 264、entry 256、
initial stream 168，数目不变。两组开启逐容器诊断，不混入正常性能样本。

| 阶段 / 锁范围 | 准备累计 ms | 提交累计 ms | 准备 max ms | 提交 max ms |
| --- | ---: | ---: | ---: | ---: |
| entry / 锁内 | 867.184 | 102.877 | 22.400 | 2.008 |
| entry / 锁外 | 841.079 | 99.535 | 21.798 | 1.666 |
| stream / 锁内 | 579.338 | 67.417 | 16.324 | 1.638 |
| stream / 锁外 | 550.039 | 64.939 | 16.517 | 1.770 |

候选 entry + stream 的 **1391.118ms CPU 准备已移出设备锁**，但工作仍
要执行，且同一版本内仍逐变体同步调用。因此这不是省掉 1.391 秒加载。
锁内 driver 提交累计 164.474ms，也不能与后台准备直接相加推算关键路径。
原生 total = prepare + commit，不含两者之间的锁等待或 RD 外层反序列化。

两组最大容器解码 payload 均 316936 B；相对只保留最大单阶段，最大额外
阶段 payload **34064 B**。只说明单容器逻辑字节增量，不包括容器原始压缩
数据、re-spirv vector、TLS scratch、分配器容量或同时在途容器的总峰值。

## 无已观察外部相关负载的补测

`run_map12.py` 在每次启动前等待连续 10 秒没有其他 Godot / Blender /
编译器相关进程，至多等 180 秒；只读检查，不操作其他进程。647 条 host12
样本仅看到本次 Godot，系统 CPU 最大 38.7%。这不是所有硬件完全空闲的
保证。相同 engine03，仍为锁内 / 锁外 / 锁外 / 锁内，原生诊断关闭。

| 样本 | 完整就绪 s | 卸载 max ms | 返回 max ms | 重载 max ms / >50ms | 重载 1% low FPS |
| --- | ---: | ---: | ---: | --- | ---: |
| map12_A1 | 10.923 | 45.183 | 32.394 | 53.017 / 1 | 26.766 |
| map12_B1 | 11.157 | 40.585 | 34.382 | 47.843 / 0 | 25.369 |
| map12_B2 | 11.328 | 31.138 | 36.646 | 47.876 / 0 | 23.945 |
| map12_A2 | 10.869 | 30.669 | 37.865 | 47.123 / 0 | 27.096 |

完整加载均值 **10.895960 → 11.242214s**，重载 1% low **26.931 →
24.657 FPS**，返回 1% low 46.060 → 46.403 FPS。候选卸载 / 返回 / 重载
没有 >50ms，不代表更广泛的慢帧分布改善；不能只选最大帧阈值宣称成功。
B2 静止仍有 60.552ms，四次样本不足以判断稳定 p95。拆锁候选暂不安装。

全部功能通过，地图 / 源码不变。模型 67 / 69 / 64 / 67、实例
3307 / 3350 / 3273 / 3251；上传均 170 次 / 721332072 B，异步工作次数
仍不完全一致。独立任务解耦和复制减少的证据保留，但整图关键路径与 low
帧仍未达目标。优先追查 reload11 抓到的隐藏 BVH 重建，再累计验证。

## 仍未完成

- 缓存命中时 `ShaderRD::_load_from_cache` 仍逐个同步创建变体，本轮只把
  CPU 工作移出设备锁，没有自动并行一个版本的全部变体。
- 任务组方案需单独验证：当前 WorkerThreadPool 的 group wait 使用信号量，
  不能假设从已有 pool worker 中嵌套等待会协作执行，必须避免池耗尽死锁。
- 主线程自身同步创建材质、原生 GPU 提交、需求维护、卸载以及未归因尖峰
  仍需按实际地图证据排查，不能因独立测试通过宣布整体优化完成。

## 返回重载 GDB 的新发现

`reload11` 在真实 `white_native_reload` 开始后附加到本次拥有的测试进程，
采样窗口 18 秒、间隔 750ms，第一及第九次包含 worker，其余只抓主线程。
9 次采样，收集停顿累计 12.422 秒；全程功能通过、无错误、源码不变，
最后 detach 正常结束。所有 debugger 帧排除出正常性能对照。

第一帧抓到主线程：`_volume_build_bvh → GodotConcavePolygonShape3D::_setup
→ set_data → ConcavePolygonShape3D::_update_shape → CollisionShape3D::set_shape`。
源码 209 行是绑定 shape 时传播默认 debug color；`Shape3D::set_debug_color`
和 `set_debug_fill` 都调用虚函数 `_update_shape`，落到凹多边形完整重建。
这解释了一个明确的遗漏：`set_prepared_faces` 已提交后台 BVH 后，绑定的
调试外观设置又只用 faces 调用后端，prepared 产品不再在该字典内，重新
进入主线程 BVH 构建。此传播存在于 DEBUG_ENABLED 的节点绑定路径；
不能泛称所有 release 导出都经过它。

其他样本包括驱动提交 / present、ForwardClustered draw 和 GDScript
执行 / 数组分配。9 次抽样没有复现原来那条 RD mutex 等待，不能当作该
等待永不发生的证明，也不能将单帧原生栈直接对应 map09 的 85.819ms。

下一项优先独立复现调试外观引发的重复 BVH，保留 changed 通知、共享 shape、
射线碰撞和真实几何 / backface 编辑；再修复为仅刷新调试网格。新测试
`tools/test_collision_debug_refresh.gd` 已准备，首次执行安排在固定普通地图
矩阵结束后，避免 CPU 压测干扰对照；此处尚未宣称修复完成。

证据根：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/shader_prepare_20261026/`。
