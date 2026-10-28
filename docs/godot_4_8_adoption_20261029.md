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

下一步按顺序：完成候选编译并跑 CPU 准备/碰撞/DDS/profiler/退出等合同；补正式表面 shader 反馈及保真/已有 DDS 的流式产品与统一预算对照；最后比较真实地图加载、卸载、返回重载和 low 帧。当前没有更改生产纹理加载路径、正式地图或默认引擎，尚无 4.8 整图性能收益结论。
