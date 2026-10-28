# Godot 4.8 beta1 接入：源码、独立验证与剩余合同

编辑器适配先于本工作完成，提交 `90a2fcc5` 已推送；默认新贴图保留原像素，DDS 显式可选，用户已确认。当前默认引擎仍为已验过的 4.7.2 补丁版；本记录不代表 4.8 已用于正式内容设计或游戏。

## 固定版本与隔离范围

来源为 [官方 beta1 发布说明](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/) 和 [官方发行资产](https://github.com/godotengine/godot-builds/releases/tag/4.8-beta1)，源码 commit `4d10419cacd6d3009976e8f9fd3abd970fd58018`。源码及现成二进制按发行 API 的字节数、SHA256 核对后解包：

- `godot-4.8-beta1.tar.xz`：47,242,444 bytes，`6d49c02e438935e49a12231d857b2b56131948b004d5b668bf295c9bc3b2281c`。
- `Godot_v4.8-beta1_win64.exe.zip`：64,756,504 bytes，`d1315408b6778b39201daa74c029deb8d06a63af7513067ac3051268212cf9a2`。

源码位于 `D:/tools/godot-4.8-build/source/godot-4.8-beta1`，官方二进制位于同级 `official`。外部证据根 `D:/code/rmmo_runtime/review_artifacts/godot_4_8_adoption_20261029_01/`；`release.json`、`acquisition.json` 保存出处及实际 exe 身份。项目兼容性使用 `90a2fcc5` 的独立代码快照，地图和用户主工作目录未改。

## 流式纹理的第一项实测

源码中的 `StreamedTexture2D` 消费 `.stex`（GSTF v1），由 `TextureStreaming` 根据反馈安排 mip 加载。默认开关关闭，Compatibility 强制完整分辨率。现有 `ImageTexture` 不会因为换引擎自动得到这种行为；需要独立的派生产品与加载接入。官方流式导入器的普通 SDR 路径使用 GPU 块压缩，但原生容器和加载器也支持未压缩像素，不能把“使用流式纹理”与“必须牺牲像素”混为一谈。

`tools/engine_patches/texture_streaming_contract` 复制到外部空项目，通过私有桌面启动官方 4.8、Forward+。测试使用正式包石铺 PNG 的只读输入，SHA `c883e1c574a9682a4949b8d1e64764172f2966019f29fbd18a039cbbc51e1cc4`，在测试目录按上游格式写入 RGBA8 mip 链；没有触碰原文件或制作 DDS。

`streaming_01` **10 项通过、0 失败**，无脚本/引擎错误，输入/fixture/引擎前后 SHA 一致：

| 状态 | 实际 GPU 读回尺寸 | 读回 mip 数据长度 | 流式系统账本 |
| --- | --- | --- | --- |
| 刚加载，mip 3 | 256² | 349,524 bytes | 0，异步登记尚未计入 |
| 强制完整分辨率并完成 flush | 2048² | 22,369,620 bytes | 22,369,620 bytes |
| 再强制 mip 3 并完成 flush | 256² | 349,524 bytes | 349,524 bytes |
| 释放 owner 并处理回收 | — | — | 回到 0 |

完整驻留时，GPU 回读的全部 mip RGBA 字节与原图生成的 mip 链一致。结果证明了该容器的保真像素、mip 切换和释放合同；这是显式覆盖 mip 的检查，不是自动相机优先级、整图视觉、加载时间或 1% low 结论。GPU 同步读回和强制 flush 仅用于测试，不加入生产逐帧路径。账本不是驱动真实显存分配量。后续仍需相机移动/传送、资源共享、取消与卸载竞态及真实地图对照。

## 旧补丁核对，不能整体照搬

`patch_checks_pristine.json` 保存全部旧 patch 对原始 4.8 的只读适用性检查。“可直接应用”只表示文本上下文匹配，不表示语义或运行验证通过；部分失败是前置 patch 未应用。

| 机制 | 4.8 源码观察 | 下一步 |
| --- | --- | --- |
| Zstd 线程解压 | 上游已使用 `thread_local ZstdDecompressorContext` | 退役旧全局锁修补，复用独立并发压测 |
| CPU surface pack / decode、碰撞 BVH 准备 | 项目专用接口尚不存在 | 移植并跑原生几何/射线/输入变化回退合同，防止全退回主线程 |
| 单次 CPU 图片编码 | 没有 `compress_from_channels_cpu`；上游第三参数已改为 `CompressProfile` | 保留单次 CPU 选择，适配新签名；不能复制旧 ASTC 参数声明 |
| 局部 RenderingDevice | 构造时仍可能写 singleton，initialize 仍依赖该身份 | 移植明确主设备发布逻辑，再跑原竞态和 GDB 构造计数 |
| DDS 非整块 mip | 基础宽高仍先执行 `w += w % divisor` | 对照已有 partial-block 测试，不能仅因旧 patch 上下文冲突就当作上游已修 |
| shader CPU 准备与 RD 锁 | 上游已把容器解析、driver shader 创建放在 RD 全局锁之前，锁只包后续 RID 发布 | 不移植旧拆锁结构，避免反向加锁；仍需带符号单 worker 暂停验证 |
| shader 完整解码 | 旧完整长度修补能匹配当前源码 | 检查依赖并重跑坏数据/重试合同 |
| 碰撞调试外观 | debug color/fill 仍虚调用 `_update_shape()` | 保留仅刷新外观的修复与 BVH 次数对照 |
| profiler、线程退出、glyph、shader cache 等 | 部分代码已变，部分旧 patch 仍匹配 | 逐项核对；4.8 VM 已在动态调用后重新取 validated object，不冒称旧 UAF 原样存在 |

未移植时不能把官方 4.8 与已优化 4.7.2 的整图时间差全部归因版本，也不能提前移除项目的共享预算/去重。

## 带符号基线构建

先构建未加项目补丁的官方源码，作为可诊断基线。配置 `target=editor use_mingw=yes debug_symbols=yes separate_debug_symbols=yes dev_build=no optimize=speed lto=none d3d12=no accesskit=no angle=no -j4`，低于正常进程优先级，独立工具目录。首轮 `baseline_build_01` 因 4.8 新增 Python Zstandard 生成依赖失败，完整日志保留；不是 C++ 或项目错误。

随后创建 4.8 专用 Python 环境，安装 SCons 4.11.1、zstandard 0.25.0，安装报告保存全部 wheel 出处/摘要，不改 4.7.2 的构建环境。`baseline_build_02` 已正常编译完成、选定源码前后不变，产物已冻结到 `baseline_engine_01`。版本为 `4.8.beta1.custom_build.4d10419ca`；exe SHA `3e8bb909b8386eb0cd68d90fc7018efc25180a09c62d0b383c049a2f67ee55a5`，独立符号 SHA `891b46e4611ddc4f02eaa9937f9496c8ee4a19c7a0d6ca002baffecb7c72182e`。GDB 18.1 已解析 RD 构造函数和 StreamedTexture2D::texture_reload 地址。仅版本/符号通过，不等于全部运行合同通过。

新源码目录的全量 Git 快照索引因大量小文件写入停止了本任务拥有的索引进程；没有改引擎源码。官方 archive 本来携带只用于版本标识的 `.git/HEAD`。编译和原始源码身份引用已验证 archive，不以未完成的本地 Git 快照当作来源证明。

项目首轮 `official_cpu_01` 虽执行了 native-only 的 24 个断言，仍有新副本未初始化全局脚本类缓存造成的 `Customization/GPUClothCollider` 解析错误，因此不记为通过。先在隔离副本正常执行官方 headless editor import，再重跑；保留失败日志，不通过复制旧 4.7 `.godot` 来掩盖问题。

后续 `official_project_import_01` 正常退出、无脚本/引擎错误，项目及 addon 脚本前后身份一致。`official_cpu_02` native-only **24/0**，共享表面纹理计划 **18/0**，均无脚本/引擎错误、输入身份稳定。前者使用临时 native 产品并明确让原 GLB 不存在；后者覆盖缺失/cached native 的跨记录纹理共享和取消。在并行编译期间取得这些结果，只作为兼容性合同，不比较运行秒数。

`official_gpu_01` 在 Forward+ 私有桌面完成真实双客户端 HTTP 源贴图共享、断线与停止服务清理，0 失败、无脚本/引擎错误，运行前后身份一致。它使用保真模式，不冒称缺少自定义 CPU API 的官方版本已通过 DDS 编码合同。

## 第二批独立复现与自动相机反馈

以下均为官方 beta1，不是尚未编译完成的自制候选。并行存在本任务编译器，因此不把运行秒数、帧时间当性能对照。

- `profiler_official_01`：沿用 self-base fixture，native profiling 开/关两组都复现脚本 `super` 重复计入调用者 self time。调用次数、返回值、退出状态正常，`baseline_red_reproduced=true`。这是诊断正确性问题，不计作游戏加载收益。
- `dds_official_01`：24 个 BC1/BC3/BC5 和尺寸组合中 **9 个失败**，为 7×7、7×11、1254×1254 三种尺寸的三个格式。前两种返回读取失败，后一种报告的 mip 数据字节数与 Image 所需不符。保留全部错误，不能把 DDS 上下文变动误当上游已修。
- `shader_official_01`：固定 16 个先前 GDB 捕获的 SPIR-V，2 worker，**256 次创建 / 256 次释放**，0 失败、无引擎/脚本错误、输入身份稳定。没有暂停 worker，尚不能替代解锁验证。

`streaming_camera_01` 在 1280×960、预算关闭的独立场景运行，不设置 LOD override、不调用 flush。为了缩短功能测试等待，明确将 inactivity decay 从上游默认 5000ms 改为 fixture 的 1000ms；不是项目默认配置。**12 项通过、0 失败**，无错误，所有输入前后身份一致：

| 相机 / 所有权状态 | GPU 回读尺寸 | mip 数据 / 系统账本 bytes |
| --- | --- | ---: |
| 初始远处，两个 mesh 共用一个材质/纹理 | 256² | 349,524 |
| 靠近 | 2048² | 22,369,620 |
| 删除一个共享 mesh | 2048² | 22,369,620 |
| 再远离且仍可见，观察 3 秒 | 2048² | 22,369,620 |
| 隐藏，完成不可见衰减 | 256² | 349,524 |
| 返回近处 | 2048² | 22,369,620 |
| 释放最后 owner | — | 0 |

近处与返回的完整 GPU mip 链逐字节等于源图 mip 链。账本不是物理显存分配量。远离后不降级符合上游 `_feedback_buffer_process` 的当前策略：自由改善，降级由预算或 inactivity decay 驱动；可见对象仍持续反馈，不能宣传为“仅因相机远离自动回收高清 mip”。后续必须验证预算、传送和实际材质组合。

### 世界坐标采样必须提供实际反馈

4.8 Forward+ 的反馈分支仅在 `UV_USED` 或 `STREAMING_LOD_USED` 时生成，默认 footprint 来自 `uv_interp`。项目 `river_terrain.gdshader` 的表面采样使用 `world_position / tile`，没有网格 `UV` 使用；`river_bank.gdshader` 则会修改 UV 的缩放/偏移。不能直接把这些材质的 ImageTexture 换成 StreamedTexture2D 就宣告适配完成。

`streaming_world_uv_01` 使用最小世界坐标 shader 复现：近相机等待 5 秒仍只有 256²；在同一 shader 中加入按实际采样坐标导数计算的 `STREAMING_LOD` 后自动升到 2048²，完整 mip 字节一致、最终回收为 0。**7 项通过**包含“缺失反馈已复现”和修复路径，不表示原项目地形已修复。公式直接遵循上游 StandardMaterial3D 三平面分支及 `scene_forward_streaming_inc.glsl`，包含 16× anisotropy footprint 和 `+12.0` 的 4096 参考尺寸偏移；不能直接把纹理尺寸的 mip 序号赋给该内建变量。

正式项目仍使用 4.7.2，尚未注入 4.8 才存在的 shader 内建变量。后续接入要同时处理多层表面、不同 tile 尺寸和法线采样，并在实际地形固定镜头验证。此最小复现没有替代那些验收。

三个探针均可通过入库的 `tools/check_texture_streaming.py` 复制到外部空项目运行。`streaming_runner_01` 用正式 runner 重跑 world-uv，7/0、无错误、前后身份稳定。例：

```powershell
python -X utf8 tools/check_texture_streaming.py --engine D:/tools/godot-4.8-build/official/Godot_v4.8-beta1_win64.exe --source D:/code/rmmo_runtime/packs/default/assets/materials/paving/natural_fieldstone/texture.png --output D:/code/rmmo_runtime/review_artifacts/NEW_UNIQUE_DIRECTORY --probe camera
```

`--probe forced|camera|world-uv|worker|budget` 分别检查强制切换、自动相机/共享回收、世界坐标反馈、后台加载交接和驻留预算。每次必须使用新目录，输出包含源图、引擎、fixture、runner 前后 SHA。GPU 回读、测试轮询和 forced 的 flush 不加入生产加载链。

### 后台加载与可见纹理预算

`streaming_worker_01` **22 项通过、0 失败**，实际在独立 `Thread` 执行 `StreamedTexture2D.load`，核对线程身份。连续三次在绑定材质前丢弃结果，流式账本均归零；第四次交给主线程材质后自动升至完整 2048²，GPU mip 字节等于源图生成的链。升清晰度保持同一纹理 RID，主 RenderingDevice 身份未变，最后 owner 释放后归零。没有设置 LOD override 或调用 flush。此结果没有证明项目共享队列已经接入，也没有证明后台 GPU 上传从不等待锁。

`streaming_budget_01` **11 项通过、0 失败**。保持近处可见、启用流式预算，4 MiB 限制下为 512² / 1,398,100 bytes；放宽至 64 MiB 后自动恢复 2048² / 22,369,620 bytes，完整 mip 链逐字节一致；再收紧至 4 MiB 后降回 512²，最终释放归零。没有显式指定 mip 或 flush。证明预算可以驱动仍可见纹理降级，不能将上游流式账本称为物理显存分配量。

两项均使用官方 4.8、私有桌面及前述只读石铺源图，日志无脚本/引擎错误，输入、fixture、runner 和引擎前后 SHA 一致。编译仍在同时进行，仅作为功能合同；没有整图耗时或 low 帧收益结论。共享 CPU 准备预算与引擎动态 mip 驻留预算的协调仍待正式链路实现。

### 共用 CPU 产品写入器

`scripts/world3d/streamed_texture_product.gd` 从调用方已有的 Image 写入 GSTF v1 暂存文件。直接保留像素、格式和完整 mip 链；已有 BC 块也直接封装，不重新读源图、生成 mip、编码或创建 GPU 资源。只检查容器 uint32 和上游读取器的固有限制，取消、路径、原子发布及共享 lease 继续归调用方负责。当前由独立 fixture 使用，正式导入/加载接入仍待完成，不会使现有地图自动开启流式。

`streaming_product_03` **194 项通过、0 失败**：32 组程序化数据，尺寸为 1×1、7×11、64×32、256×128，格式为 R8、RG8、RGB8、RGBA8、BC1、BC3、BC4、BC5。覆盖输入不变、完整文件逐字节重开、初始 GPU 仅上传对应 mip 尾部及每次释放归零。这里的 `get_image()` 完整读取是离线合同检查，禁止加入生产逐帧路径。另以真实石铺源图运行 `streaming_product_camera_01`，**13/0**，共用写入器仍能支持相机升清晰度、共享 owner、不可见回收与返回加载。

保留两份失败样本：`streaming_product_01` 的 fixture 将 Image.get_size() 的 Vector2i 与 Vector2 比较，解析失败；`02` 的 4 个 RGB8 GPU 断言错误地预期 RGBA8，源码确认 texture_2d_get 会转换回原格式，修正预期后使用新目录重跑，不属于引擎修复。所有通过样本无脚本/引擎错误、身份稳定。写入器亦通过当前 4.7.2 的 check-only；没有加入 4.8 专属静态类型。正式 runner 增加 `--probe product` 并复制共用写入器到隔离项目。

## 4.7 已发布 native 的兼容性抽样

`native_compatibility_02` 从已完成迁移的 14 类中各选 native 文件最小的一件，以控制本轮兼容性抽样的 I/O；不是最重资源压测，也不是 220 件全量验收。沿用 `review_native_migration.gd --mode=metadata`，在官方 4.8、隔离项目和私有桌面实际重开 4.7 生成的发布 SCN，而非现场重新转换。依次覆盖路灯、旧树、静态花池、街道道具、彩旗柱、围栏、招牌、建筑装饰、摊位、路面、院墙、风场布幡、风场花池和带 LOD 松树。

**14/14、616 项检查、0 失败**，无引擎/脚本错误，各次输入和实际产品 SHA 不变。包括发布身份、原生读取/实例化、保守边界、建筑描述和可用 absence 数据。逻辑 GLB 路径只作为发布键，未读 GLB、未生成替代 SCN、未写正式地图。此模式没有渲染对照，不升级旧画质报告或宣称 4.8 外观已经通过；也不把有编译器并行的进程时间当加载成绩。

首个 `native_compatibility_01` 在启动引擎前因 Python 字典键的 Windows 路径分隔符差异失败，保留 runner 和失败说明。修正路径归一化后另开 `02`，没有覆盖失败证据。

接入共享队列时还需保持两个边界：当前 `PrefabTexturePreparation` 产出完整 Image、`SurfaceMaterials` 发布 ImageTexture，不能在这条链后再加一次 `.stex` 读取而保留原完整解码；流式产品应替代对应准备任务，并继续复用共享身份、取消和预算。`StreamedTexture2D.get_image()` 会重新读完整文件，现有草地/模型纹理去重、旗槽转换等像素消费者需逐项处理，不能拿它作逐帧驻留查询。静态 `runtime_upload_bytes` 也不能冒充后续动态 mip 上传总量。

## 候选移植与构建交接

外部 `ports_01/critical_runtime.patch` 为 **27 文件的首版移植草稿**。原始目标与 overlay 的逐文件 SHA、对 pristine source 的 `git apply --check` 均通过；并非运行验收。涵盖 CPU surface pack/decode、Godot Physics BVH、单次 CPU 图片编码、主 RD 发布、DDS、shader transfer/TLS、profiler、退出/字形及已有查找优化。手动适配了 4.8 的 `CompressProfile`、物理管理器头文件、Vulkan PowerVR mutex 宏和 profiler 函数链表。

旧 Zstd 全局锁修补由上游 TLS 实现替代；旧 shader CPU 拆锁结构不移植；旧默认关闭的 module-share/source-key 实验及 release 诊断补丁不直接带入。shader transfer 的实际重复拷贝仍存在，移植它时保留上游锁范围和 PowerVR workaround。

profiler 草稿第一次因为两处 `frame_*.set(0)` 的替换断言失败，失败草稿保留在 `ports_01/profiler_draft_failed_01`。修正后仅在 frame snapshot 减去捕获值，profiling_start 仍正常清零；没有修改正在编译的 baseline。

`build_candidate_01.py` 已完成原版结果核对、exe/符号冻结、版本与 GDB 符号验证以及全部目标原始 SHA 核对，冻结的草稿已应用到独立源码，候选正在编译。任一步异常停止，保留日志；不会安装到 `D:/tools/godot`。观察构建状态须以两份 `result.json` 为准，不能因为观察超时就另启编译或宣称成功。单 worker 暂停验证单独记录，不把 GDB 时间作为性能数据。

`pause_baseline_01` 使用冻结的未修改基线和 GDB 18.1。在 Vulkan driver shader CPU 准备入口断住，核对自有 PID、创建时间、exe、线程名称及调用栈，删除断点后用 Win32 SuspendThread 仅保持其中一个 fixture worker；恢复其余线程观察两秒。另一个 worker 完成 **128 次创建、0 无效结果**，主线程记录 **116 次采样**；恢复被暂停 worker 后总共 **256 次创建、256 次释放、180 项检查、0 失败**，正常退出、无引擎/脚本错误。主线程与暂停 worker 的栈、平衡的 ResumeThread 记录保存在同目录。watchdog 没有触发。Windows GDB 本身仍使用 all-stop，这不是声称其支持 non-stop；含调试器暂停的长帧和 wall time 不参与性能比较。此实测支持沿用上游已经拆开的 shader CPU 准备路径，不移植旧拆锁结构。

`candidate_build_01` 在 gdscript.cpp 的 profiler 调用者分组处编译失败：OS 没有声明。4.8 的该文件仅在 TESTS_ENABLED 块内 include OS，旧版补丁依赖的传递头文件已变化。完整日志和首版源码 SHA 保留；确认进程退出后，将 core/os/os.h 移到无条件 include，生成 `ports_02` 的完整 patch/逐文件身份，启动 `candidate_build_02` 同配置续编。没有修改冻结基线，不能把这处编译修正当 profiler 运行通过。

`zstd_baseline_cleanup_01` 用冻结基线、外部空项目及 GDB 在上游 `ZstdDecompressorContext` 析构入口捕获线程身份与非空 context。12 个短生命周期 worker 各完成 32 次 256 KiB 解码、逐字节相等，随后捕获 **12 个不同线程的有效 context 析构**，进程正常退出，无错误、输入身份不变。这支持退役旧版全局锁修补并使用上游 TLS；并发速度仍须等编译结束后跑固定工作量对照，不能从这项清理合同推导加速比。

`validate_candidate_02.py` 已排队等待同一候选构建。成功后才会复制产物至 `candidate_engine_02`、核对 SHA/版本，并在 `candidate_contracts_02` 串行跑六组原生合同：CPU surface、CPU concave、debug appearance、GPU surface 数据对照、renderer arrays、LOD hint。进度在 `candidate_validation_02/result.json`；它拥有构建后下一组 GPU 测试时段，接手时不能另开并行 GPU 任务。当前仍待运行；通过这六组也不替代后续 DDS/profiler、CPU 编码、退出与整图验收。写入器旧引擎兼容性另有 `streaming_product_47_parse_01` 的同步 subprocess 结果，0 退出、无错误、源码和引擎身份稳定。

下一步按顺序：完成候选编译并跑 CPU 准备/碰撞/DDS/profiler/退出等合同；补正式表面 shader 反馈及保真/已有 DDS 的流式产品与统一预算对照；最后比较真实地图加载、卸载、返回重载和 low 帧。当前没有更改生产纹理加载路径、正式地图或默认引擎，尚无 4.8 整图性能收益结论。

## 正式地形/河岸 shader 反馈与材质合批复验

新增 `streaming_surface_shader.gd`，只在支持 TextureStreaming、项目显式启用且使用 Forward+/Mobile 时构造两个共用 shader 变体。4.7.2 或未开启流式时继续使用原 shader。`RiverMaterials.terrain/bank` 共用这个选择，`GroundBatchGeometry` 识别两个地形身份；未开启生产纹理流式，也没有改地图记录或源图片。

反馈来自真实采样坐标：地形按世界坐标、tile 尺寸、三平面有效投影及实际层权重计算；河岸使用缩放后的 UV。高度图可能先参与混合、最后被覆盖权重消去，所以另外保留混合前实际采样的高度层需求。未参与采样的层不以其大 tile 值强迫升 mip。上游一个材质仍只有一个反馈 LOD，本轮没有宣称实现逐 sampler 独立反馈。

`surface_contracts_02` 使用真正的项目 shader 和只读石铺源图，官方 4.8 **49/0**、当前 4.7.2 **21/0**。七种场景包含基础色、法线、三平面岩石、区域覆盖、高度混合后消失的层、无用层大 tile 和河岸 UV 缩放。适用的流式样本自动升到 2048²，完整 mip 链逐字节一致；无用层测试维持 256²。七种同镜头 ImageTexture 原 shader / 完整驻留流式变体画面逐字节一致。没有强制 LOD 或 flush，最终 owner 释放后账本归零；无引擎/脚本错误、输入身份稳定。

`surface_contracts_01` 的像素/驻留断言仍保留，但其预览写入误用了 `save_webp(path,false,.9)`，实际为 VP8L 无损，不能将当时写入的 lossy 元数据当作编码证明。已在该目录保存纠正记录；`02` 使用 `save_webp(path,true,.9)`，runner 检查 RIFF 的 VP8/VP8L 块、质量参数和实际 SHA，七张图均为真正有损 Q90。发送查看的是校正后的 Q90 副本，原本用于本地对照的证据未覆盖。

### 发现并修复原有的重复分组

真实 `RiverMaterials → GroundBatchGeometry.build/upload` 集成测试发现，第一次计算材质键后，`ShaderMaterial.duplicate()` 会补齐尚未设置的 shader 默认值。相同外观由 null 变为 `.3`、`-1.5` 等明确值，导致同一个材质前后甚至与自己的副本分到不同批次。`surface_batch_02` 在原 shader 和流式 shader 中均复现；Godot `ShaderMaterial::_get_property_list` 的惰性 `param_cache` 填充与逐参数证据吻合。

现在按实际生效的 shader 默认值归一化。参数名称和默认值按两个固定地形 shader 缓存、只读共享，`Shader.changed` 时失效；不缓存材质当前值，不额外修改材质，也不在每个实例上反复枚举默认值。禁用的区域层仍忽略，启用或真实外观修改仍拆分批次。

首轮合批截图的像素不等也没有直接当成 shader 回归：完整测试项目原本开启 TAA，两个 shader 的差异图完全相同，均只涉及边缘 3,844 像素。后续精确像素 fixture 明确关闭 TAA，并先验证未改变场景的连续截图完全相等；没有放宽 MAE 阈值。`surface_batch_03` 原/流式两组各 **12/0**，合批前后逐字节相等。最终 `surface_batch_04` 官方 4.8 **17/0**，独立初始化旧版类缓存的 `surface_batch_47_01` 当前 4.7.2 **17/0**，同时验证：

- 等效复制、Inspector 默认填充不改变键，真正外观/启用区域变化仍改变键；
- shader 默认值编辑会使缓存失效，恢复后重现原键；
- 两份源表面实际合成一份渲染表面，保留选定 shader 和 layered 参数；
- 同镜头确定性画面逐字节一致，源记录和源几何数组不变。

均正常退出、无引擎/脚本错误、文件前后身份一致。这是材质管线及派生合批的受影响项复验：资源像素/运行管线通过，七种固定镜头及简化合批画面通过；没有新模型交付或正式地图部署，不替代整城、所有视角和连续动态画面验收，也不把断言数量或有编译器/GDB 并行的秒数当性能收益。

### 候选编译后的首个阻断项

`candidate_build_02` 已完成：退出 0、耗时 2078.359s、全部候选源码身份不变。冻结到 `candidate_engine_02`，exe SHA `fbfe5ecc3bb2e3b63ab70e46b4896dcf3df518c5481f1b3edc5606c3c9829c4b`，符号 SHA `4ce3ba47f9fad367589a08f1f714cd43ac875bd2f0df0fc7ee49b0101dfd3bac`。仍未安装默认引擎。

自动 `candidate_contracts_02` 第一项 CPU surface 的 48 jobs × 9 组（1/3/12 worker 正反顺序）数据全部一致、12 个断言通过，但日志出现 `GDType::bind_method: init_state != MUTABLE`，因此严格记为失败，剩余五项没有运行。不能用脚本返回 0 掩盖原生注册错误。

`gdtype_diagnosis_03` 使用冻结候选和 GDB 18.1 捕获到：`initialize_godot_physics_3d_module → ClassDB::bind_static_method<GodotConcavePreparedData3D::prepare> → GDType::bind_method`，此时类型状态明确为 `FINALIZED`。恢复后复现同一原生错误、进程正常退出、引擎和命令文件身份不变。这是旧补丁在新类型系统下的注册时机不兼容，不是证明上游碰撞算法有 bug。首个诊断因在每次类型绑定处检查条件而 180 秒超时；第二个空项目没有 main scene，未进入目标模块，终止了已核对身份的自有进程。失败边界和日志均保留，第三次改用精确模块断点及最小 SceneTree 脚本才取得上述栈。

修正将 `prepare_concave_shape_data` 绑定移到 `PhysicsServer3D::_bind_methods` 的正常初始化期；模块仅设置 CPU 实现函数指针，卸载时清空。保留原项目 API 和数据格式，不让类型重新变为可修改，也没有引入逐任务互斥。无 Godot 物理模块时返回空准备结果；现有正常构建保留该模块。新加入的两个 physics_server 文件均与已验证官方 archive 的原始字节核对。

`ports_03/critical_runtime.patch` 共 29 文件，SHA `f709dd84d021491ce10f618bdb51fcabd66a6edf85b3746b73b547bc7c7e9ebe`。`candidate_build_03` 正在以同配置、低优先级续编；`validate_candidate_03.py` 等待同一构建，成功后冻结至 `candidate_engine_03` 并串行重跑六组原生合同，拥有构建完成后的下一组 GPU 测试时段。当前只完成复现和源码修正，**未宣称候选 03 已通过编译或运行**。接手先读取这两组 result.json，不重复开启编译，不修改正在编译的源码。

## 候选 03 构建完成与移植合同验收

本节更新上节的进行中状态。`candidate_build_03` 已正常完成，退出 0、343.094 秒，源码前后身份不变。冻结到 `candidate_engine_03`：exe SHA `fe41da4819801754155ba43728e9541e3a76074021d5b09d34a6293fb0e33d35`，符号 SHA `9e016e823051b42d95634c50dbbbdc11fce520e359552f684161a8c92f49e424`。没有安装为默认引擎。

`patch_validation_03` 从已验证的官方 archive 提取 29 个目标，核对原始 SHA、执行 `git apply --check` 和实际应用，全部结果 SHA 与本次编译源码一致。完整补丁与逐文件清单归档为 `tools/engine_patches/godot-4.8-beta1-runtime-candidate.patch/.json`。补丁身份仍为上节的 `f709dd…e9ebe`，不是从一份未经核对的本地 Git 基线生成。

### 原生几何、碰撞和导入数据

`candidate_contracts_04` 六组共 **263 项通过**，无引擎/脚本错误，正常退出，fixture/配置/引擎前后身份一致：

| 测试 | 检查数 | 实际覆盖 |
| --- | ---: | --- |
| CPU surface | 12 | 48 jobs × 9 组、1/3/12 worker 正反顺序，60k 顶点数据一致 |
| CPU concave | 96 | 48 shapes × 6 组，射线、face index、背面及变化输入回退 |
| 碰撞调试外观 | 49 | 颜色/fill 不改 RID 和几何；真正几何/背面变化仍更新 |
| GPU surface | 29 | CPU 结果与提交后数据一致，custom channels、LOD、blend flags |
| renderer arrays | 20 | 显式编辑器 GLB 导入所得 CPU arrays 与 renderer 回读一致 |
| importer LOD | 57 | 既有导入 LOD 合同 |

GLB 仅用于上述显式导入测试，未恢复游戏 GLB 回退。构建 02 的 frozen-type 错误在候选 03 的这些启动与运行中不再出现。

### 纹理、shader 与 profiler

- `candidate_texture_contracts_04`：DDS **24/24**，覆盖 BC1/3/5 的 8 种尺寸，含 7×7、7×11、1254²；边缘解码及完整 GPU mip bytes 一致。原版 4.8 的 9 项失败保留，候选为 0。profiler self-base 原生开/关合同通过，原版重复 self time 的 red baseline 不覆盖。
- 同目录 shader residency 的 0/2/32/0 四种容量各 9 项通过。创建数依次 **179/166/46/179**，复用 **0/68/136/0**，最终 unused **0/2/32/0**；红/绿/红画面一致，缓存不持有 Texture/Material/Mesh。容量 32 对本次禁用样本减少约 74.3% 创建数；这是固定工作量缓存收益，不是 4.8 相对 4.7 或整图 FPS 收益。
- `cpu_compression_candidate_03`：GDB 捕获 **1 次 RD 构造，只有主设备**；真实 worker 完成 RGB/RGBA、32/64 的四次 DXT CPU 编码，mip 完整，主 RD 身份不变，`compress_with_gpu=true` 未改，绘制 123 帧后正常退出。调试器耗时不计性能。
- `shader_failure_candidate_03`：**18 项通过**。4 次故意损坏 SMOL-V 的失败后，均能用同一个 placeholder RID 重试成功。精确记录 4 条 malformed-stage 与 4 条 `!shader_id` 预期错误，无额外错误；不能将此测试写作“日志无任何错误”。
- `profiler_lifetime_candidate_04`：释放 **61,440** 个带子节点父节点后正常退出；原生 new/add_child/set_meta 分别为 **122,880/61,440/61,440**。4 worker 的 set_normal/set_uv/add_vertex 各 **200,000** 次，两个调用者 has_meta 分别 **4,000/8,000** 次，均准确归属。4.8 的 Object.free 是虚注册方法，没有真实 ClassDB MethodBind，因此无 native free 行；不能把这一点当漏计。该运行不替代先前释放后访问的 GDB 地址证据，也不宣称发现了新的 4.8 UAF。

### 上游 Zstd 的固定工作量并发

`zstd_scaling_03` 在编译完全结束、无 GDB/profiler 下运行。原始 4.8 与候选各 12 样本，每个样本严格 **384 MiB**，worker 顺序 1/3/12/12/3/1；4 KiB 共 98,304 次、256 KiB 共 1,536 次解码，输出逐字节一致。

| 候选块大小 | 1 worker 两次 wall ms | 3 workers | 12 workers |
| --- | --- | --- | --- |
| 4 KiB | 499.592 / 476.952 | 212.396 / 171.494 | 93.353 / 76.032 |
| 256 KiB | 323.029 / 303.635 | 124.919 / 103.120 | 56.532 / 47.204 |

原版也正常随并发缩短，结合前述 12 个 TLS context 析构证据，继续采用上游 TLS、退役旧全局锁补丁。两个引擎未做 ABBA，不据此声明候选比原版快；各线程 wall 相加也不是进程 CPU 工作量。

### 候选流式与真实合批

`candidate_streaming_04/result.json` 汇总候选的 worker **23/0**、budget **12/0**、surface **49/0**。前两项比旧摘要多一项源文件未变检查，不能当作又增加了新的功能覆盖。worker 复用 `candidate_streaming_03/worker/run.json` 已成功完成的实际证据；预算与表面在 04 运行。覆盖并发共享 owner、释放、自动反馈与预算，以及真正地形/河岸 shader 的七组完整驻留像素和 mip 字节。最终账本归零，预览为真实有损 WebP Q90；全部正常退出、无错误、身份稳定。仍是独立 fixture，正式共享准备队列没有因此自动接通。

`surface_batch_candidate_03` 在冻结候选运行先前相同的真实 `RiverMaterials → GroundBatchGeometry` fixture，**17/0**；原生 CPU surface 接口可用时使用既有准备/发布路径，仍将两份表面合为一份，画面逐字节一致，默认参数惰性填充不拆批，真实参数修改仍拆批。无引擎/脚本错误，源码和引擎身份稳定。

### 字形图集跨线程上传

新增可复用 `tools/check_glyph_upload.py` 和 `glyph_upload_contract/probe.gd`。在连续创建新字形、触发图集更新的循环中不做同步 GPU 回读，避免先把待测重叠串行化；每批结束才比对 CPU/GPU 的完整图集和 mip 链。四个更新入口为 RID、size、draw、outline，各覆盖 mip 开/关。

`glyph_candidate_04` 使用系统 Arial 的只读输入，safe/separate 两进程各 **20/0**、8 个场景，每场景 **188 字形**、2–3 张图集，工作量一致，所有 GPU 字节等于 CPU 快照，正常退出且没有引擎/脚本错误。渲染回调实际线程分别为主线程 1 和独立线程 5，确认并非只传了参数。fixture/字体/引擎 SHA 前后一致。该候选只编译 Advanced 文本服务器，Fallback 源码虽在补丁中但未编译，不能称已验证它；Dummy 无动态字体能力，明确跳过。此压力合同不宣称能够证明任意调度下不存在竞争。

### 保留的测试宿主失败与证据边界

- `candidate_contracts_03` 的碰撞外观实际 49 项通过、退出 0，宿主误要求逐条 `PASS` 文本而判失败。04 修正为检查它真实的 JSON 断言；日志型 fixture 继续检查文本，未放宽错误检查。
- `candidate_validation_04` 六个子测试都完成后，发布状态 JSON 的 `os.replace` 遭遇一次 Windows WinError 5。核对终态、pending payload 与子进程结束后，仅重试发布，不重复 GPU 测试；原异常与 `publication_retry.json` 保留。
- `profiler_lifetime_candidate_03` 错误要求虚方法 free 出现在 native MethodBind 表；真实释放流程正常。检查源代码与绑定模型后，04 用实际原生操作计数及释放完成记录验证，未改引擎统计掩盖失败。
- `candidate_streaming_03` 的 worker 实际完成通过，宿主误读 `result.json` 而非规范的 `run.json`。04 验证并复用原结果，未重跑以挑选更好样本。
- `glyph_candidate_03` 首轮把没有动态字体能力的 Dummy 也当实际光栅化器测试，16 项失败均来自 Dummy；Advanced 的 16 项图集检查已通过。04 按 TextServer 的动态字体能力筛选并记录跳过者，保留首轮失败日志，未把不存在的 fallback 编译项记为通过。

**接续边界：**默认仍为已验 4.7.2；4.8 尚待正式共享队列的流式产品接收、动态驻留预算，以及真实游戏/编辑器加载、卸载、返回重载和 low 帧对照。候选的独立合同通过不等于可替换整图性能结论。正式接入首先要去除 `SurfaceMaterials` 先要完整 Image 才接受 prepared Texture2D 的限制，并保持身份失效与共享去重；不能先全解码，再额外读一遍流式产品。默认保留原像素、DDS 显式可选的编辑器策略不变。

## 接收端复现：完整 Image 依赖与表示切换失效

`texture_only_red_01` 用真实 `StreamedTexture2D`、外部 128² RGBA 源图和完整 mip 原生产品进入现有 `HousePrefab.begin_texture_publication → SurfaceMaterials.make_material`。原代码 **16 项中 6 项失败**：尽管传入已完成纹理，仍进行 1 次源图解码；全测试额外上传 **174,760 bytes**。同一源 SHA 切换 `runtime_texture_representation`，并清空 hot/weak 纹理条目只保留材质 owner 时，旧分片快路径还会复用旧材质。嵌套外层 Image 也可能遮住新的内层纹理。没有借白模、关闭纹理或强制完整 mip 掩盖问题。

修正沿用同一个发布协议：

- Texture2D-only 结果在源图/DDS 回读和 Image 上传之前直接交接。使用生产者已有的源身份、表示身份、alpha、法线编码与字节元数据；不调用 `get_image()`，不制造占位 Image。
- Image 与 Texture2D 复用旧 owner 失效逻辑；成对 image/upload 包仍以 Image 身份为准，保留原有后台上传路径。
- 发布 scope、调用者材质池和分片复用同时比较表示身份。分片状态只保存字符串，不额外持有 GPU/CPU 资源；新表示只重新初始化一次，后续切片继续复用。
- 嵌套作用域结束时恢复原来的两个 Dictionary owner；缓存淘汰不改变已经显示的旧材质。缓存插入复用同一实现，不新增独立热缓存或重复去重表。

`texture_only_green_01` 同一候选、相同 fixture **16/0**，保留 red 结果；额外源图解码 **0**、重复上传 **0 bytes**，两个不同表示各直接交接一次，100 次未改变切片维持 **100 次复用、总共 2 次初始化**。alpha、零 hot-cache 和嵌套 owner 恢复均通过。这里的工作量下降属于发布接收端，不等同于整图加载已经加快。

串行回归 `texture_handoff_regressions_01` 全部正常退出、无引擎/脚本错误、选定源码及引擎前后 SHA 一致：

| 运行 | 检查数 | 覆盖 |
| --- | ---: | --- |
| `background_upload_handoff_01` | 31 | 两共享变体各上传一次、取消后的新 producer 接管、迟到结果隔离、最后 owner 与全部预算释放 |
| `prepared_material_handoff_01` | 97 | 正常/分片发布、共享材质、失效和失败路径、外层 scope 精确恢复 |
| `editor_pool_handoff_01` | 8 | 编辑器同源不同表示、材质别名、失败修复；1000 次不变记录无重复整池扫描 |
| `texture_only_47_01` | 16 | 当前默认 4.7.2 使用已有 ImageTexture 同样直接交接，无新增引擎 API 依赖 |

本轮调整的是游戏与编辑器共用的内部接收协议，没有新增 UI/MCP 操作、改变保存格式或默认压缩选项。原生流式产品由测试显式提供，正式调度器尚未生成这种 packet。GPU 热缓存当前使用完整 mip 链的保守字节上界，不把它写成动态 VRAM 实测。下一步是接上已发布流式产品的共享生产/取消/预算，处理需要 CPU 像素的消费者，再做真实地图与编辑器整体验证；默认引擎和生产流式开关尚未切换。
