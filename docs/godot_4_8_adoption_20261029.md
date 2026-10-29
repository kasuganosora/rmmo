# Godot 4.8 beta1 接入：源码、独立验证与剩余合同

编辑器适配先于本工作完成，提交 `90a2fcc5` 已推送；默认新贴图保留原像素，DDS 显式可选，用户已确认。用户于 2026-10-29 明确要求默认使用 4.8，当前默认引擎与工程配置已切到已验证的 candidate03 补丁构建，详见文末“默认迁移”。下文按时间保留此前的候选与 4.7 对照记录；完整加载与 low 帧优化仍未完成。

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

## 原生流式产品接入共享队列与编辑器导入

用户再次确认：**新增导入默认保留原像素，DDS 有损压缩由用户显式选择**。本轮保留该选择；流式产品只改变读取与驻留方式，不另做有损编码。默认引擎仍为 4.7.2，正式项目的 streaming 开关未启用。

`streamed_texture_source.gd` 从导入 worker 已准备好的 RGBA8 或既有 BC1/BC3/BC5 mip 链发布不可变 `.stex`，最后原子发布小型描述文件。源图不重读、不重编码；活动纹理继续引用旧不可变文件。运行时只为可信资源包选取对应表示，规划阶段读取有界描述及原生头部，以防低估预算；不再次校验完整源图或产品 SHA。不支持的格式、缺失的可选产品、旧引擎和未启用 streaming 的路径沿用原准备流程。

`PrefabTexturePreparation`、`SharedPrefabImages`、`TexturePlanCatalog` 接入同一纹理计划、worker 与预算。producer 在锁内认领后于锁外加载原生纹理；follower 返回 pending，不占住 worker 等待。完成包只有 Texture2D owner，没有为了满足旧接口而产生完整 Image。取消后迟到的结果不能覆盖新 owner，最后释放仍由既有所有权和预算回收路径处理。没有新建另一套线程池。

本轮额外复现了 resident ticket 的表示漏洞：源身份相同的完整 ImageTexture 会让原生流式计划提前跳过加载。`native_ticket_red_01` 仅将 HousePrefab 恢复为 `1074fbe8`，其余候选和测试不变，35 项中唯一失败正是这个断言；保留原失败结果。修正要求 native 计划的 ticket 同时具备实际 StreamedTexture2D 类型和相同表示身份，材质 owner 回填与分片发布也遵守已有表示规则。

最终串行矩阵 `native_streamed_regressions_02/result.json` 的八组运行全部退出 0，冻结的源码、配置、引擎 SHA 前后一致，无非预期引擎/脚本错误：

| 运行 | 检查数 | 证据范围 |
| --- | ---: | --- |
| `shared_streamed_02` | 38 | 两变体/两消费者只有 2 次 native load、2 次产生和 2 次 follower 复用；实际材质分片发布无源图回读、无重复 ImageTexture 上传；取消接管、迟到结果隔离、所有 lease 和引擎驻留归零；完整颜色/翻转法线 mip 字节一致 |
| `native_reference_02` | 29 | 真实 Index/Chunk worker → DeferredAssetLoader → WorldDocument；颜色与 shader 高度共享一个 native owner；首次及零 hot-cache 返回均无回读/重复上传，像素与普通源图路线一致 |
| `native_background_legacy_01` | 31 | 4.8 原有 Image 后台上传、共享、取消和释放不回退 |
| `native_prepared_material_01` | 97 | 材质分片、失效与失败回退、嵌套作用域 |
| `editor_native_import_02` | 43 | 真实 HTTP 和 UI 导入、保真/显式 DDS 两种原生产品、完整像素一致、绘制/撤销/重做/保存重开、lease 归零 |
| `native_tickets_47_01` | 3 | 4.7 CPU ticket 合同；该运行未传 `--gpu`，不冒称覆盖 GPU owner |
| `native_background_47_01` | 31 | 默认 4.7 原有后台上传合同 |
| `editor_native_import_47_01` | 39 | 默认 4.7 编辑器 HTTP/UI 保真与显式 DDS、保存重开 |

编辑器两种入口复用 `SurfaceTextureImportWorker` 的同一业务流程，没有新增 UI/MCP 参数或改变保存语义。编辑器可变源准备仍使用源快照，原生产品供后续可信包加载使用。测试中的完整 `get_image()` 仅用于发布计数完成后的字节对比，不属于运行时发布流程，测试加载微秒数不当作性能收益。

补充 GPU owner 回归：`native_tickets_47_gpu_01` 为 17 通过、1 失败。测试早先用无源身份 Image 验证观察操作无副作用，随后一直保留这个 prepared scope，却期待不相关的热纹理优先；接收端的身份保护会拒绝它。结束该观察作用域后再测试普通优先级，`native_tickets_47_gpu_02` **18/0**、零错误、SHA 稳定。只修正测试作用域，没有为通过旧断言放宽生产身份检查；失败记录保留。

**仍待处理：**当前 app admission/热缓存采用完整 mip 链保守收费，后续 mip 读取由引擎既有 streaming worker 执行，尚不能宣称与项目实现了动态 GPU 驻留及 CPU IO 的统一预算。内嵌在模型原生场景中的纹理尚未转换，本轮覆盖 authored paint/terrain/road/prefab definitions。还须在独立产品目录或新测试资源包中准备 axel_town 产品，保持旧样本与原始包不变，然后完成真实地图加载、卸载、返回、画面和 low 帧对照。独立合同通过不等于整图已加速或 4.8 可以替换生产引擎。

## 首次完整贴图地图兼容样本（尚未加入流式产品）

`full_map_compat_01` 使用 `068e9b8e` 的外部冻结项目、candidate03、原 `axel_full_native_staging_20261027_01` 只读测试包（2,369 records / 49 native models）。使用全新私有用户目录，正常优先级、无 GDB/profiler、真实 private-desktop Forward+/Vulkan；没有启动并发 GPU/引擎编译。项目设置开启 streaming/budget，但包内没有 `.stex`，因此是完整贴图引擎迁移兼容样本，**不是流式性能样本**。测试宿主仍关闭 HUD/mock server，历史 phase 名称仍含 white；`full_controls_match=true` 与绘制后材质审计确认实际为 full-material，不把它叫成完整外围系统的生产游戏验收。

全部功能断言通过、零引擎/脚本错误、正常退出。源码/配置/引擎 SHA、地图与原 fixture 均未变。模型绘制后可见 mesh 606、表面 887，其中 523 个表面有纹理、97 个独立纹理；这些不是整张地图所有模型的美术验收。

| 指标 | 首次私有缓存样本 |
| --- | ---: |
| 地图开始 → 入口 | 34.224 s |
| 地图开始 → 当前需求队列完整就绪（原口径） | 57.274 s |
| 首次显示阶段单帧 | 5,490.269 ms |
| 离开 / 卸载 / 返回最大帧 | 43.326 / 43.990 / 48.140 ms |
| 上述三阶段 >50ms 帧 | 0 / 0 / 0 |
| 返回重载最大帧 / >50ms | 53.596 ms / 2 |
| 离开 / 卸载 / 返回 / 重载 1% low | 44.35 / 116.81 / 35.66 / 25.40 FPS |
| 带在途工作的地图退出 | 178.301 ms |

总 wall 207.984 s 包含固定路线、宿主阶段与关闭，不是加载时间。首轮需求完整就绪和首次显示仍有大块耗时，保留慢样本；全新 shader/用户缓存是待对照因素，未抓栈前不把 5.49 s 直接归因为 shader 编译。后续复用同一私有缓存检查。该单样本不能与旧引擎暖缓存结果作提速/退化比较，也不能推断 p95。

流式对照需要额外记录实际显示与 mip 收敛：原来的 full-ready 仅检查项目 demand/job/render-batch 及共享像素预算排空，不包含未来绘制反馈触发的高分辨率 mip 读取。必须同时保留原时间锚与显示/质量证据，不能把低 mip 提前可用冒充同画质的全部就绪。

### 相同配置与私有缓存复测

`full_map_compat_warm_01` 沿用上一样本冻结项目、引擎、配置、地图以及它的私有用户缓存，未加入流式产品；功能、全部身份和错误检查继续通过。入口 **9.500 s**，原完整就绪锚 **18.335 s**，首次显示 **132.637 ms**。卸载 / 返回 / 重载最大帧 **36.089 / 45.590 / 48.889 ms**，均 0 帧 >50ms，对应 1% low **117.12 / 36.57 / 25.54 FPS**。离开出现 1 帧 **52.380 ms**；steady 1 帧 **101.071 ms**；在途退出 **219.529 ms**，均保留。

首轮与此轮差异明确表明缓存状态需要单独控制；不是已证明哪个具体引擎方法承担全部差额。两次没有 ABBA，不能据此建立 p95 或对旧引擎提速结论，也不能把首次缓存慢样本删除。

### 独立流式测试包准备

`axel_streamed_fixture_01` 从原 full-native 测试包另建测试副本：49 模型 `.scn` 逐字节 SHA 保持一致（约 2,214.9 MiB），地图 2,369 records 重开后只归一化 schema 声明的根路径即完全一致；纹理与材质参数未改。新 `full_fixture_manifest.json` SHA 为 `eb9d90be02c04b901f7e6a4a91debfffb4b84591c064983d47646b9f84b9437c`。源模型 GLB 文件未复制、未打开、未重建；使用既有原生产物。原始用户包与旧证据包不写入新副产物。

离线 `streamed_product_conversion_01` 成功生成 **85 个变体 / 85 个产品**，完整 mip payload 合计 **360,666,036 bytes**：11 个保真 RGBA8，74 个既有 DDS 块表示；逐一与运行时同表示准备结果比较，全部完整 payload 一致，未重编码 DDS。产品/描述 SHA 及逐项字节对照写入 `axel_streamed_fixture_01/streamed_products.json`。这是文件数据保真证据，仍不能替代实际流式显示、mip 反馈与细节收敛验收。

## 整图流式诊断与入口绕过已发布产品的复现

`full_map_streamed_diag_01` 使用上述新包、candidate03 和兼容暖样本的私有缓存副本；启用纹理分段计时，只作为功能/归因样本。功能、源码/配置/引擎/产品身份与错误检查全部通过。入口 **11.035s**，原需求完整就绪 **20.214s**；离开/卸载最大帧 **38.016/26.565ms**，返回 **80.519ms（6 帧 >50ms）**、重载 **128.496ms（1 帧 >50ms）**，对应返回/重载 1% low **27.99/23.90 FPS**，未通过长帧目标。引擎流式账本峰值 **84,666,152 bytes**，不是驱动 VRAM，也不是所有内嵌纹理成本；原就绪点后尚有 mip 反馈，不能称画质已完全收敛。

计数揭示入口遗漏：共享池初始产生 **67** 个 native owner，完整路线 **152** 个（包含卸载后的正常重载），末尾 lease/outputs 均归零；但入口仍额外解码 **24 张源图**，主线程上传 **352,321,512 bytes**。`map_profile.texture_decode_us=2,783,641`。24 次 source SHA、decode、mipmap、normal flip、cache write 都来自入口；这些并行/嵌套 span 不能相加当关键路径。整个共享池 native load 最大 **2.602ms**，不能据此推断 GPU 后续驻留成本。

对照 `full_map_nonstreamed_diag_01` 使用同一新包、关闭 streaming，其完整路线 176 次主线程 Image 上传 **1,009,340,616 bytes**（其中 130 次 DDS，444,598,424 bytes）；同样包含 24 次入口源图解码。入口 **32.639s**、需求完整就绪 **56.225s**。**开关 streaming 改变 shader permutation，复制的暖缓存只有开启配置，因此这两个耗时不构成同缓存 A/B，也不能声称 20s 对 56s 的流式提速。** 两个样本与慢帧均保留。

根因在 `MapLoader._decode_textures`：游戏入口一直调用编辑器可变源准备，使用源内容 SHA，并要求编辑器 DDS provenance。运行资源包已有选定 DDS、但没有编辑 provenance 时，入口回到完整 PNG；之后区块使用可信包的路径身份/选定产品，无法复用入口 owner。入口发布也只交接 Image，不接收原生 Texture2D。这两处使接收端/共享队列已经支持流式后，入口仍漏接。

独立测试先替换回 `068e9b8e` 的原入口，保留相同引擎/其余源码：

- `entry_streamed_red_03`：9 项中 **5 项失败**，干净复现原生产品被源图解码、重复上传及后续 ticket 不能复用。red01/red02 的材质 fixture 缺少 name，分别超时/报告脚本错误，保留失败目录，但不拿它们作生产问题证据。
- `entry_representation_red_47_01`：6 项中 **2 项失败**，直接复现已有 DDS 块未使用以及入口/区块源身份不一致；无其他脚本错误。

修复让入口复用 `PrefabTexturePreparation` 的 immutable plan/prepare，原生 Texture2D 与 Image 共同交接；只有无有界计划的旧格式继续普通读取。保留既有最多 3 个入口 bucket，跳过空 bucket；取消传到准备任务，退出仅移除当前 loader 拥有的交接资源。没有增加 worker，也没有声称入口三组与后续共享池已经拥有统一的内存准入账本。

`entry_streamed_green_02` **12/0**：真实 native worker → 入口交接 → 材质绑定 → 后续 chunk ticket 保持同一 owner，零源图解码、零完整 ImageTexture 上传；取消不产生结果，真实 loader 退出移除自己的 owner，保留无关外层 owner。`entry_representation_green_47_01` 与 `entry_representation_green_48_01` 均 **6/0**：没有编辑 provenance 的运行 DDS 逐块保留，源身份与区块一致，源文件未改。全部正常退出、无非预期错误、选定源码/引擎身份稳定。整图收益仍需修复后的真实地图证据，不能用独立计数替代。

### 修复后首个完整地图样本

`full_map_streamed_entry_green_01`：相同 candidate03、产品包和旧兼容暖缓存种子，入口覆盖为本轮修复；其余源码不变。正常退出，功能/全部身份/错误检查通过。入口纹理准备 **40.306ms**（修复前 2,783.641ms），整条路线 `texture.image` 解码 **0**、主线程完整 ImageTexture 上传 **0 bytes**（原 24 次 / 352,321,512 bytes）。入口直接交接 24 个 native owner，初始共享池产生 61 个，合计 85；修复前为入口 24 个完整 ImageTexture 加池内 67 个 native，共 91，只有其中 **6 次**可据此确认是跨入口重复产生，不能把池内 67→61 写成“总共只加载 61 个”。全路线池内 146，加入口 24 为 170，包含卸载后的合法再加载；最终共享 lease/outputs 均零。

总耗时没有同步下降：入口 **11.256s**、原完整就绪 **23.257s**；实例准备最大切片 **512.808ms**，初始需求阶段最大 **420.812ms**。离开/卸载/返回/重载最大帧 **40.358/39.444/54.359/66.845ms**，>50ms 为 **0/0/1/6**，对应 1% low **35.10/93.00/34.78/22.25 FPS**；在途退出 **188.065ms**。本轮保留确定的重复工作下降，不将总加载、low 帧或默认引擎迁移写成已达标。

实际完整贴图截图已查看：公会墙面、草地和道路纹理正常可见；1440×900、有损 WebP Q90，SHA `2e2feb37a79393011b5dd1c11d71ef4e036cca4cc10ce360704646450adfc942`，拍摄于加载开始后 33.622s。这一机位未覆盖针叶细节，也不证明所有 mip 在原就绪锚时已收敛。确认 candidate 源码 shader cache 默认位于 `user://shader_cache`，只读项目 `.godot/shader_cache` 为另一来源；本 fixture 实际缓存位于其私有用户目录，下一样本继续使用本次完成后的缓存副本。

`full_map_streamed_entry_warm_02` 功能、释放与身份检查继续通过，入口准备 **34.179ms**，源图完整解码/主线程 ImageTexture 上传仍为零，入口+池初始 85、全路线 170 个 handoff，与上一样本一致。入口 **12.655s**、完整就绪 **25.869s**，返回/重载最大 **63.234/65.262ms**、1% low **31.47/21.64 FPS**，退出 **241.518ms**。期间分析脚本曾重复解析旧 116MB 日志，已停止；该宿主干扰与分段 profiling 一同保留，本次不纳入普通性能验收，也不把“缓存暖了仍慢”当排除 shader 的因果证据。

默认 4.7.2 的 `full_map_entry_legacy_01` 完成真实完整地图入口、卸载、返回和带在途任务退出：正常退出、功能/身份检查通过、零错误。入口纹理 **51.924ms**，初始 85 次 Image 上传 **360,666,036 bytes**，全路线 170 次 **721,332,072 bytes**；其中 DDS 为初始 74 次、全路线 148 次。没有入口 PNG 回退或内容 SHA。初始池 61 + 入口 24，与原生流式的独立 owner 工作量一致，末尾 lease/outputs 零。入口 **19.706s**、完整就绪 **38.720s**，卸载/返回/重载最大 **32.477/47.175/57.478ms**，>50ms 为 **0/0/13**，对应 1% low **100.76/33.87/21.11 FPS**；退出 **230.866ms**。私有缓存来自 4.8/off 对照，对 4.7 shader 和部分索引并非暖缓存，首轮重新建索引且首次显示 **2,217.952ms**；这是兼容回归和保留的慢样本，不与 4.8 暖样本直接比较。

本轮入口重复工作修复可以保留；完整加载和 low 目标仍未完成。接下来应控制相同引擎/配置/资源表示和缓存种子，采集实例准备、初始需求发布及退出长段的栈/trace，再独立复现。尚待：入口/区块统一内存准入、动态 mip 预算、原就绪点之外的实际画质收敛、内嵌纹理接入。用户随后要求道路支持平头，本会话先补该编辑器 UI/3D MCP 功能；不会因此把性能目标标为完成或替换默认引擎。

## 默认迁移：用户明确切到 4.8

上述候选阶段之后，用户明确要求“默认使用4.8，然后把工程也转为4.8，不要再在4.7折腾”。本机默认入口已改为 `D:/tools/godot/godot.windows.editor.x86_64.exe`，版本 `4.8.beta1.custom_build.4d10419ca`，即通过上述合同的 candidate03；exe SHA `fe41da4819801754155ba43728e9541e3a76074021d5b09d34a6293fb0e33d35`，匹配的完整独立符号 SHA `9e016e823051b42d95634c50dbbbdc11fce520e359552f684161a8c92f49e424`。GUI、console、`godot.exe` 和版本别名均已核对；正常与调试使用同一个优化构建，不是无符号 release。安装清单在 `D:/tools/godot/patched_build_manifest.json`，旧默认程序已存入 `_backup/before_default_48_20261029_071907`，不作为运行回退。

当前分支和本机主工作区的工程版本声明、默认启动路径已对齐；只定点更新主工作区的这些配置和工具路径，其余已有工作不纳入本分支提交。Windows 用户级 `GODOT` / `GODOT_PATH` 指向稳定入口，用户 PATH 加入引擎目录，新开的终端可用 `godot`。工程启用 native streaming 和 512 MiB streaming-texture budget；这是沿用已测配置的 mip 驻留预算，不是全部 VRAM、总资源准入或导入大小上限，也不冒称已完成动态统一预算。新样本统一用 4.8，不再新增 4.7 兼容测试；历史证据保留原版本。

迁移同时修复 `StandardMaterialSchema` 的版本门槛：旧代码在 4.8 静默回退为每次原生属性枚举。先在同一 candidate03 上复现 5 检查中的 3 项失败，再核对 `BaseMaterial3D::_validate_property` 实际存储条件后启用 4.8.0 缓存。独立合同 **6,490/0**，覆盖 1,619 状态、默认值、合法模式、新属性、metadata、脚本动态 usage、未知版本回退、64 项上限和四线程读取；真实材质序列化/合批 digest 消费者 **5,924/0**。原测试使用非法透明模式 MAX 哨兵的问题也已修正。

512 材质微测 ABBA 为关闭 **552.875ms**、开启 **141.942ms / 141.628ms**、关闭 **545.496ms**，序列化字节与 digest 完全相同，开启时仅枚举一次。这是独立微测收益，整图收益仍须同配置对照。完整证据位于本文公共证据根的 `standard_material_schema_48_report.md`、`default_48_installation.json`、`migration_defaults_changes.json`。

## 入口关键路径：官方 profiler 和 GDB 的新证据

对已有 `full_map_streamed_entry_green_01` 只解析一次的归因结果在 `trace_attribution_01/analysis.md`。入口 CPU capture 活跃 **2.378s**、墙钟 **2.793s**，涉及 2,007 meshes / 2,099 surfaces；后续 cover 中 deferred service **6.683s**，包含 publication **4.908s**，不能相加。末尾生产队列空后仍有 stream 应用和第二轮合批扫描，不能再统称“纹理后台收尾”。

`full_map_entry_official_01` 官方 profiler 完成全部路线，零引擎错误，源码/配置/产品身份稳定，保存 28,720 帧及 2,824 签名。入口 11.729s / 完整就绪 22.594s **只作诊断**，外层 scope 已标记 profiler，即使内层 runner 的 diagnostic 字段为 false 也不能当普通性能样本。原 probe 缺少 engine-frame ID，故本轮官方帧不能可靠逐帧对齐阶段，不用插值补造。该样本未复现此前 348ms 小网格提交事件。

`full_map_entry_gdb_01_stacks` 在预先装入符号后采集 103 次 all-stop 栈；42 次仍在启动脚本编译，7 次明确抓到主线程 `surface_get_arrays` / `mesh_get_surface → RD.buffer_get_data → _flush_and_stall_for_all_frames`，其中 3 次进入 Vulkan fence wait。另有 `PackedScene.instantiate → set_surface_override_material → get_rid → shader cache load`。未抓到 mesh_add_surface、transfer-pool wait 或 texture_replace_rid，不能把此前 348ms 事件归罪于纹理上传锁。GDB 显著干扰墙钟，其 44.466s / 52.964s 不作性能比较。下一步直接针对已证实的 GPU 回读往返；尚未宣称引擎已修复该路径。

当前 probe 另有已复现的统计缺口：旧 `frame_split` 只读 interactive 模式，会把 cover 发布记成零。修复保留原 17 列，改为所有模式的累计差量，再附各模式差量/累计值、reset/baseline 和真实 engine-frame ID。红样本 17 检查 / 11 失败，绿样本 20/20、schema 6/6；1 万次 helper 操作 232.319ms 只是局部开销，不能当完整 observer 开销。零 publication 的旧记录不能再用作“主线程空闲”证据。

两次后续普通整图完成集成验证：control 36,183 行、候选 47,041 行，全部为 33 列，原 17 列一致，engine_frame / at_us 严格递增、跨阶段不重置。control cover 的 service/publication 为 7,777,413 / 5,633,837us，465 行非零；候选为 6,701,227 / 4,031,346us，7,270 行非零。这只是 probe 统计正确性的验证，不代表候选更快；publication 包含在 service 中。证据见 `initial_native_probe_v2_integration.json`。

### 入口后台准备实验：主线程减负没有变成加载收益

候选把私有 SCN scene 的首次实例化、CPU 几何/碰撞面准备提前到 worker，首个实例消费同一 scene，后续复用 PackedScene 和 CPU cache；没有增加 worker、驻留额度或原 8ms pump 预算。独立有效 red_03 为 53 检查 / 3 个预期失败，green_01 为 62/62、零引擎错误。但该 fixture 64 meshes 的主线程 readback 仍有 71.34ms、worker 等待 113.21ms，因此不能称全部几何工作已后台化。

普通整图 `full_map_initial_native_cpu_01` 和随后严格 control 使用同一已安装 candidate03、4.8 配置、schema 缓存、v2 probe、fixture、相同缓存种子；控制组仅将入口的 3 个生产文件恢复到 `59667b87`。两次均完整正常退出、零错误和失败、输入 SHA 稳定。控制组入口 **10.297s / 完整就绪 22.864s**，新准备路径入口 **15.377s / 完整就绪 35.632s**。这一对不构成 p95，但足以否决默认启用；实验与慢样本保留，继续追查入口之后额外的工作和等待。

候选原主 capture 降到 38.98ms、实例化最大切片 8.105ms，却新增私有准备 **5.547s**，其中 worker 等 readback **4.390s**，主线程 readback **2.112s**；这些 span 包含/并行，不能相加。其对象数仍为 2,007 meshes，碰撞面 16,228,944 bytes，准入估计仍为 5,450,944,511 bytes。跨线程搬运并没有消除 GPU 往返。GDB 已证实的往返将由独立 candidate04 原型处理，当前默认引擎仍是已验过的 candidate03。

另一个已量化但尚未解决的边界是模型包内嵌纹理。该入口模型的已发布 footprint 显示：281,810,329 bytes 的 SCN，60 textures/images、149 materials；`image_mip_bytes=563431377`，`mesh_storage_bytes=11641784`，`native_uncompressed_bytes=576645460`。这是离线资源统计，不是实际 RSS/VRAM。`CompiledAssetCache._build_prepared` 仍用 BUNDLE_RESOURCES 打包原始图像，`ModelTextureCache.apply` 在加载后才共享。因此“入口源图解码/项目层 ImageTexture 上传计数为零”不代表 SCN 内嵌图像无需读取或上传。该路径尚未接入流式，不能把 4.8 开关启用等同于全部模型纹理已完成改造；先完成当前几何回读实验，再独立处理内嵌图像产品和编辑器合同。

实验代码保留但 `initial_native_cpu_preparation_enabled=false`，普通入口不安装新增 readback service，pump 也不服务该实验分支。真实桥 record 复现其忽略 prepared.scene 后的泄漏：17 检查 / 1 失败；补上未消费 detached scene 的释放后 17/17、零错误。真实 prefetch 的 mismatch/cancel/abandon/cancel_ack 则为 71/71，259 个观察对象（含 193 个 RID owner）正确释放；原有 retained_resources 已覆盖 entries，所以没有为了静态猜测修改 drainer。实验仍会给某些程序化桥提前做不用的准备，计入 unused_scenes，不能称重复工作已清除。

额外尾段并非已证明由合批重扫导致：候选的早期 prefetch 从控制组 4.217s 推迟到 12.549s；30.3–33.3s 时仍有 4→3 个 native worker，合批 pending_groups=0，visits 固定。最终晚到结果之后 sync 2→5、visits 6396→17741，最终 sources/surfaces/groups 相同。新增重扫主要是晚到的后果；plain 聚合尚不能拆开迟到 worker 内部的 SCN 读取、解压和 GPU 等待。详见 `initial_native_cpu_review.md` 和 `initial_native_tail_analysis.json`。

默认迁移补验：`road_caps_48_01` 使用安装后的 4.8 完成 29+46+55 项道路 CPU、真实编辑器 UI/HTTP MCP、撤销、保存重开、游戏碰撞和实际合批检查，全部通过、零错误/警告、SHA 稳定。`primary_headless_import_01` 对主工作区当前磁盘源（含未提交文件）的隔离副本完成 editor import，退出 0、零错误/警告；6,488 文件 / 32,208,111 bytes 的来源与排除范围已保存。它证明 4.8 语法/导入兼容，不证明主工作区当时的旧导入链已具备本分支的新能力。


## 2026-10-29：合入主工作区及兼容性收束

本轮按用户要求将 `codex/latest-map-runtime-review` 合入 `D:/code/rmmo` 的 `main`。代码集成提交为 `bec11ac4`，同时包含远端 `c333a646` / `b9f5a1e0` 的分阶段进场、地形 LOD、风场与受保护植被合批更新。后续开发使用主工作区；默认仍为已安装的 4.8 candidate03，未安装实验 candidate04b。

四处代码冲突保留两侧有效行为：

- World3D 的自动分阶段协议使用共享完成/解锁链，保留帧呈现证明、失败回收和预测逻辑。
- 地形先生成 LOD 再打包 CPU 上传数据，避免上传快照丢失 LOD；保留准备数据、材质 schema 与现有合批粒度。
- 风场排除在描述复用前生效，保留受保护的 cutout 策略。
- 河岸 shader 同时保留流式纹理、BC5/XY 法线解码及远距离细节衰减。

主目录原有 36 项 tracked 修改先保存独立字节快照及 Git stash。34 项自动三方恢复结果逐字（仅归一换行）核对一致；2 项手工冲突保留 MCP 两侧文档，以及新 `part_data` 架构内的用户接光分区和彩窗排除合批语义。已被本分支涵盖的改动无需重复形成工作区 diff；其余用户改动继续保持未提交、未暂存。3,383 个不重叠的 untracked 文件逐个 SHA 不变；唯一重叠文件是此前复制的本交接文档，原件保存在外部恢复目录。

证据根目录为 `D:/code/rmmo_runtime/review_artifacts/godot_4_8_adoption_20261029_01/`：

| 验证 | 结果 | 证据目录 |
| --- | --- | --- |
| 入口生命周期 / cover / 元数据策略 | 11 / 13 / 22 项通过，无错误警告 | `merge_runtime_cpu_02` |
| 地形、边界、LOD、协议合同 | 85 项通过，无错误警告 | `merge_runtime_cpu_04` |
| 实际 HTTP cutout 与风场保护 | 36 项通过，无错误警告 | `merge_runtime_gpu_03` |
| GPU 地形与 LOD | 26 项通过，无错误警告 | `merge_runtime_gpu_03` |
| 自动分阶段进场、失败恢复与连续取消 | 两次各 35 项通过；首轮有 1 个 ObjectDB 警告，verbose 复测未出现，不能称已修复 | `merge_automatic_deps_gpu_01` / `merge_automatic_deps_gpu_verbose_01` |
| 主工作区（含用户 WIP）隔离导入 | exit 0，零错误；1 条独立 profiler 测试工程被忽略的结构警告 | `primary_headless_import_merge_wip_01` |
| 主工作区 2,007 节点包路径合同 | 29 项通过，无错误警告 | 同上 |
| 接光分区、彩窗、增量处理等价 | 32 项通过，1us 预算跨 389 次推进，与一次性处理等价 | 同上 |
| 完整女性角色游戏进场 | **未通过**：30s 内未从 Loading 交接，最终 runner 330s 终止；2 PASS / 1 FAIL，无资源缺失错误 | `merge_flow_deps_gpu_02` |

这些是功能兼容验证，期间存在独立编译/逻辑工作，不作加载性能、p95 或 1% low 结论。缺少基线脚本、角色/门/gradients 的早期私有夹具失败全部保留；headless 的 `rendered_frame_unavailable` 也不被改写为渲染通过。旧地形测试仍断言 cutout 默认关闭，与远端已验收的 guarded rollout 冲突，本轮改为验证实际默认与显式关闭两条行为。

未解决项不因合并而消失：

- 完整角色进场 GPU 样本超时，需要继续定位；不能仅凭材质 cache miss 或 GLTF 警告归因。完整日志另有不带 `ERROR:` 前缀的 image-format 诊断：uniform 期望 `R16G16B16A16_Sfloat`，实际为 `R16G16_Sfloat`。该诊断在 automatic 成功样本中也存在，因此仍需独立复现，不能直接认作 flow 超时原因，也不能将功能断言通过写成渲染零诊断。
- `character_imported_rig.gd` 的既有角色路径仍直接读取 GLB；后续“导入后只用原生资源”改造必须覆盖角色，不能只统计地图模型。
- 入口 native SCN 内约 563MB 图像 mip 数据的几何/纹理拆分尚未实施；独立模型纹理表需要接入现有共享去重与统一预算。
- candidate04b 的 CPU 移交实验仍未接生产。179 条断言通过不等于零泄漏；既有 ResourceLoader token/资源图寿命问题另有最小红测，恢复入口为 `native_cpu_capture_04/lifetime_resume.md`。

恢复资料位于 `primary_merge_20261029_01/`，包含 stash ID、原 tracked 字节和 patch、untracked SHA、两处冲突的精确恢复 diff。主分支合入范围没有新增 GLB、Blend、SCN、DDS、STEX 等模型/纹理产品，资源和测试产物继续留在外部运行目录。
