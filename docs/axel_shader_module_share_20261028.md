# Vulkan shader module sharing candidate — 2026-10-28

This is an isolated, default-off engine prototype, not installed into `D:/tools/godot` and not yet an ordinary-map performance result. Prior buffered same-thread diagnostics showed repeated shader-module creation as a large portion of several material spans; a separate snapshot of shader-cache bytes showed repeated SPIR-V payloads. The snapshot was taken after an earlier trace, which recorded file lengths but not payload SHA; it does not prove those byte hashes existed at the original trace time.

The driver-local active-owner registry uses the final SPIR-V bytes passed to `vkCreateShaderModule`, hash+length as a lookup hint followed by full byte equality. Only flags=0 and pNext=null are admitted. It retains each ShaderInfo's own reflection, RID, layout, sampler and specialization state; temporary specialized pipeline modules are not shared. One registry mutex protects lookup, creation and reference bookkeeping without acquiring the RenderingDevice lock in its callbacks. This may serialize unrelated keys and must be evaluated under real workloads. Explicit `shader_destroy_modules`, ordinary free and partial-create rollback release the same per-stage owner; last owner removes the entry and destroys the module. The original same-ShaderInfo concurrent-destroy contract is not expanded.

The prototype has a 64 MiB cap on retained byte-vector capacity and an 8,192 entry cap. Above either cap, it falls back to private module creation. Vector capacity is not RSS or VRAM and excludes allocator overhead, hash bucket storage and most metadata. The reported peak `sizeof(Entry) × peak_live` is a metadata lower bound, not total memory. Each driver writes its own uniquely numbered diagnostics file; because an independent created-device total is unavailable, real-map evidence can establish zero retained for observed devices only. Test-only APIs, collision override, error injection and small budget are explicitly gated; ordinary sharing remains off unless `RMMO_SHADER_MODULE_SHARE=1`.

Evidence root: `D:/code/rmmo_runtime/review_artifacts/shader_module_share_20261028_01/`. `module_share.patch`, the four `candidate/` source files, original `before/`, build09 identity, and `contract_identity.json` are preserved. The 100-round C++ stress test uses the exact candidate registry header SHA `2630c990136f69f0d1dad385b5c961e4f687e8dedf4cd46dbc4451e7b2971cd4`; it covers concurrent same-key first creation and release, forced hash collisions with unequal bytes, independently exercised byte and entry limits, failure with live owner and final zero. It does not by itself prove Vulkan integration.

The first build was intentionally stopped during SCons scanning after a multi-device diagnostics issue was found; its failure and source restoration are preserved in `build.log` / `build.result.json`. The revised `build02` succeeded, restored build09 source bytes, and left the original engine09 EXE/symbol SHA unchanged. Its isolated EXE SHA is `01328b8c85c8209333867c82c73275a6a77b4c55e482b048dab13fcb850e8873` and symbols SHA `7863be9f9193ada0d3b9ce4eefff4537a3ee383a1a968dc41ede41257d91f618`.

A real private-desktop Vulkan fixture ran under off/on/1-byte-cap, each 43/0 with exactly the two expected error lines from a test-only injected second-stage failure. It creates one global and two local devices, keeps two owners alive during forced identical-hash/different-byte compute programs and reads their distinct GPU values, repeats explicit module destroy on the first owner then exercises the second, and draws/reads the same graphics owner's red pixels before and after partial-failure rollback. All three observed devices ended with zero live entries and retained bytes. Under the fixed fixture the global device's Vulkan module calls were 16 off vs 4 on (12 hits), and each local device 2 vs 1 (1 hit each); the 1-byte-cap run fell back and matched the off call counts. On-run global peak retained vector capacity was 2,004 bytes and peak entry metadata lower bound 192 bytes; this is not a full-map peak or actual RSS. Error injection occurs only for the named fixture shader and must not be confused with an actual driver failure. The first off fixture run failed its two pixel checks because the fixture omitted a vertex array; it is preserved as `contract_off_01`, then `contract_off_02` passed after the fixture fix.

Existing `test_prepared_material_publication.gd` was run on a copied project in a private desktop with isolated content root and unrelated MockServer autoload disabled: off/on both 97/0 with no unexpected engine or script errors. The prior isolated-root attempt left MockServer enabled and produced three missing-pack startup errors despite 97 test passes; `material_off_01` is preserved as failed. These are functional/counter tests, not map time or frame improvements.

## 完整材质地图工作量对照

`full_module_abba_20261028_01/` 的严格空闲窗口等待因其他 Blender 工作持续存在而超时退出，未启动任何地图；该记录保留。随后另建 `full_module_workload_abba_20261028_01/`，显式指定 `--workload-only`，允许观察到的外部负载，只验功能与工作量。四轮均使用上述 engine02，同一源码、完整材质 fixture、private user/cache、预算及路径；direct-native template 候选固定开启，worker prepack 关闭，仅 module sharing 按关闭/开启/开启/关闭切换。关闭逐调用日志及 GDB/profiler，双侧仅记录相同的退出聚合计数。

| 样本 | 入口 / 完整就绪 s | module 创建 / 命中 | 卸载 max ms / >50ms 帧 | 返回 max ms / >50ms 帧 | 重载 max ms / >50ms 帧 | 返回 / 重载 1% low FPS |
| --- | --- | --- | --- | --- | --- | --- |
| A1 关闭 | 19.287 / 47.297 | 2559 / 0 | 40.031 / 0 | 61.934 / 3 | 99.918 / 1 | 32.085 / 26.695 |
| B1 开启 | 9.846 / 21.273 | 1681 / 878 | 50.503 / 1 | 51.620 / 1 | 108.530 / 2 | 33.373 / 24.740 |
| B2 开启 | 10.295 / 21.452 | 1681 / 878 | 32.088 / 0 | 53.036 / 1 | 99.694 / 2 | 34.224 / 25.853 |
| A2 关闭 | 10.115 / 20.919 | 2559 / 0 | 37.193 / 0 | 49.700 / 0 | 123.722 / 6 | 30.908 / 22.290 |

四轮功能、源码/fixture 身份、实际开关、回收检查均通过；实际 direct reuse 都为 1。完整就绪处的 batch 工作一致：211 groups、2316 source objects、3349 source surfaces、2128385 source vertices，输出 359 surfaces / 2075484 vertices。Deferred 周期采样的 models 为 48/55/54/56、instances 为 3134/3195/3172/3170，不当成完整全程精确计数。相同 cache 文件的大小与 mtime 未变化；未记录内容 SHA/物理缓存状态，不能称为严格 cold 对照。

两次开启都消除了 878/2559（34.31%）次源 module 创建；计数覆盖启动至退出，排除临时 specialization module，不能当成单一长帧减少量。两次都创建 889 个共享 entry、发生 792 次预算回退，peak vector capacity 为 67108160 字节，已贴近原 64 MiB 上限。唯一观察到的 device 在退出时 retained/live/metadata 均归零；没有独立的 device 创建总数，因此不扩充为所有潜在设备退出证明。A1 慢样本完整保留；这组受到外部负载影响，**未证明加载时间或 low 帧稳定改善，也不计算 p95**。

下一步保持 64 MiB/8192 上限，研究已成功完整解码、不会重写的 stage 能否以其原有压缩字节和完整解码参数作精确身份键，减少缓存自身重复保存的数据及预算回退。仍需精确字节比较、独立 owner、并发/失败/释放和实际 GPU 合同；不能靠扩大预算或只比较哈希换取命中。

## 压缩 source-key 候选

`shader_module_source_key_20261028_01/` 保留第二版独立候选；原 raw-key engine02/候选未覆盖。仅在成功完成原有解码、`store_respv` 无 optimizer 重写且 compressed bytes 小于 final SPIR-V 时，用完整压缩字节、codec flags、声明解码长度、mode、stage 和 final size 作身份。final SPIR-V hash 仍只是 bucket 提示，命中必须精确比较自有 key 字节及全部参数。其他分支仍用 raw-key；不同编码或 raw/source 混用保守地少命中，不声称跨所有表示全局去重。没有新增编码、重复解码或文件读取，保持相同 64 MiB/8192 per-device 上限。

该推论要求解码成功确实产生完整输出；本轮同时修复共享解码函数的实际错误，红绿证据见 [解码合同](axel_shader_decode_contract_20261028.md)。不能单独采用 source-key 而遗漏该修复，也不把该缺陷归因于旧的无栈崩溃。

保存的 2240 个真实 stage 输入通过同源 Zstd/SMOL-V 解码，再逐字节核对等 source 的最终输出。在所有 owner 始终保留的合成序列中，raw-key 命中 808、miss 1432、回退 773、peak capacity 67102980 字节；source-key 命中 960、miss 1280、回退 0、capacity 17460316 字节。两组最后均归零。该序列不是实际地图生命周期；不以其数字推算地图时长。强制碰撞、不同字节/flags/长度/mode/stage、raw/source 隔离、输入修改后的独立 key 所有权和 32 线程同键创建/释放均有单独合同；带 `-UNDEBUG` 和编译期检查的同一 header 复核 100/100 通过。

组合 GREEN 引擎 EXE SHA `20d25131e638bb6cafa0c285e2cddbf09eb6e7e528ee4f8f22dc566adfd8fde8`，符号 SHA `6aec02bb3d434fa83b12b1579d8205b64651ac7d59248e871e7d4c08d08ac833`；默认仍关闭共享/source-key，CPU 诊断 API 未开时不存在。源树已恢复，engine09 和安装目录未覆盖。

`source_key_gpu_{off,on,source,cap}_20261028_01/` 使用同一 GREEN 引擎，四组私有桌面 GPU 合同均 **43/0**，严格匹配两条注入失败日志。各组固定一个 global 加两个 local device，实际 GPU 输出、含 specialization 声明的不同计算程序、强制哈希碰撞、并发 owner、重复显式 destroy 和第二 stage 失败回滚均检查。三 device 总 module calls 为 20/6/6/20，总 hits 为 0/14/14/0；source 组 14 次命中全为 source-key，cap=1 字节时全部私有回退。global peak key capacity 在 raw/source 分别为 2264/787 字节，每个 local 为 516/190 字节；所有已知三个 device 退出时 live/retained 均为零。它们是功能和计数测试，不是整图性能收益。

真实材质发布合同在 GREEN + source-key 下 **97/0**，无非预期日志，实际 source_hits=35；故障后同 placeholder 重试合同 **18/0**，精确匹配四对 malformed-smolv/prepare 预期错误。证据为 `source_key_material_contract_20261028_01/` 与 `_02/`。首轮重试合同的 Godot 自身通过，但外部 runner 误以大写 `SMOL` 匹配实际小写 `smolv` 而判失败；原输出保留，修正为精确匹配后只重跑该失败合同，未重复已通过的 97 项。

GPU fixture 复制到外部目录后，以私有桌面运行 `--path <copy> --script res://probe.gd -- --output=<new-report.json>`。其专用环境为 `RMMO_SHADER_MODULE_TEST_API=1`、`RMMO_SHADER_MODULE_TEST_COLLISION=1`、`RMMO_SHADER_MODULE_TEST_ONLY_PREFIX=RmmoModule`、`RMMO_SHADER_MODULE_TEST_FAIL_NAME=RmmoModuleFail`，以及退出计数前缀 `RMMO_SHADER_MODULE_STATS_PATH=<new-directory>/module_stats`。四组分别设置 SHARE/SOURCE_KEY 为 0/0、1/0、1/1、1/1，最后一组再设 `RMMO_SHADER_MODULE_TEST_LIMIT_BYTES=1`；TRANSFER_MOVE 固定 1、PREPARE_UNLOCKED 固定 0。这组预期错误必须恰好为 `Error (-13) creating module for shader stage Fragment.` 和 `Condition "!shader_id" is true. Returning: RID()` 各一次，不允许泛化忽略引擎错误。正常地图必须移除所有 TEST 控制。

交付 patch 的应用顺序为原 build09 + `shader-module-share` + `shader-decode-length` + `shader-module-source-key`。外部历史 patch 使用 CRLF，直接 `git apply` 检查失败；入库版只规范为 LF。`shader_module_patch_delivery_20261028_02/` 证明三份 patch 可顺序应用，结果与候选按 LF 规范化后逐字节相同，不能称原始文件 SHA 完全一致；原失败 `_01/` 保留。CPU 诊断 bridge 不属于这三份生产 patch。

## 同预算 source-key 完整路线对照

`full_source_key_workload_abba_20261028_01/` 完成 GREEN 同二进制 raw/source 0/1/1/0 四轮。两侧固定 sharing=1、TRANSFER_MOVE=1、PREPARE_UNLOCKED=0、direct-template=1、worker-prepack=0，均包含已通过公会合同的属性过滤/重复引用精简。源码、fixture、实际开关、功能和退出回收全部通过。没有每调用日志、GDB 或 profiler；仅相同的退出聚合计数。四轮均显式 workload-only，不能当作安静主机的时间验收。

| 样本 | 入口 / 完整就绪 s | 创建 / 命中 | 卸载 max ms / >50ms 帧 | 返回 max ms / >50ms 帧 | 重载 max ms / >50ms 帧 | 返回 / 重载 1% low FPS |
| --- | --- | --- | --- | --- | --- | --- |
| A1 raw | 20.460 / 48.260 | 1680 / 879 | 38.843 / 0 | 69.847 / 3 | 111.184 / 1 | 31.989 / 26.479 |
| B1 source | 11.784 / 24.570 | 1529 / 1030 | 33.196 / 0 | 53.896 / 2 | 110.969 / 1 | 28.899 / 25.382 |
| B2 source | 10.930 / 22.254 | 1529 / 1030 | 48.276 / 0 | 49.934 / 0 | 103.218 / 4 | 33.825 / 24.471 |
| A2 raw | 10.593 / 21.649 | 1681 / 878 | 36.826 / 0 | 52.419 / 1 | 115.218 / 1 | 33.898 / 24.909 |

四轮观察到的 source-module 总请求均 2559。raw-key 仍发生 791/792 次预算回退，peak vector capacity 为 67107672/67108160 字节。两次 source-key 均为 **1529 次创建、1030 次命中、0 次预算回退**，其中 source_hits=987、raw_hits=43；source-key 不适用的分支没有被省略。两次 peak capacity 都是 **19609481 字节**，包含 source_peak=17583845、raw_peak=2025636；该样本这些分项相加等于总峰值，一般不能相加峰值推断同时驻留。相对 raw-key 多避免 151–152 次创建，key capacity 约降 70.8%，未增加原 64 MiB 上限。source 组 peak entry metadata 下界 109656 字节，raw 为 63576；不把 key 容量下降称作同等 RSS/显存下降。

同一初始就绪处仍为 211 groups、2316 source objects、3349 source surfaces / 2128385 vertices，输出 359 surfaces / 2075484 vertices。周期采样 models 为 48/54/54/56，instances 为 3145/3143/3166/3170，compiled misses 为 0，direct reuse 都为 1；这些采样最大值不是完整路线的所有实例计数。每轮唯一观察到的 device 最终 shared live/retained/metadata 和 raw/source 分项均为零，release ledger 一致；仍保留未独立记录 created-device 总数的边界。

79/67/68/69 条臂内 host 采样中，79/67/66/62 条观察到其他相关进程，CPU 最大采样 47.0/62.0/68.3/46.5%。四轮 shader-cache 文件 size/mtime 没变，不是内容 SHA/物理冷盘保证。A1 的 48.260 秒慢样本完整保留，未找到唯一成因；不能用它算加速比，也不能直接归咎外部活动。**本轮确认工作量与键容量收益，没有确认稳定的加载/low 改善；四条样本不构成 p95，103–115 ms 重载帧仍未解决。**

下一切片仅独立研究仍在每个 variant 重复发生的 RESPIRV Parse/compact：先验证只读共享产品、输入生命周期、完整容量与并发，再评估是否值得接入。module 共享不等于已经避免 CPU 解码/解析。另一个属性优化候选不能直接遍历 TEXTURE_MAX：原 storage usage 与注册顺序会随材质状态变化，贸然替换会改变共享首选对象；目前停留在审查，没有并入本轮。

该下一切片位于独立 `shader_parse_share_proto_20261028_01/`，不在本轮引擎/项目改动中。v2 编译成功且输入身份固定，但第一次 16-stage CPU 合同 `runtime_attempt_01_contract` 以 `0xC0000374` 退出，仅有两条预期 invalid-magic negative-case 输出，尚未确定在哪个步骤损坏。2240-stage 回放已停止，先准备带阶段标记/符号的独立定位；不能称解析共享已通过或把它归因于旧游戏 AV。

游戏材质阶段、默认安装与安静条件时间验收都尚未完成，内容编辑器和当前 3D MCP 的适配/优化仍是完成游戏材质之后的必要任务。
