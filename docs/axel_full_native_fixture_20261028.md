# Axel Town 完整材质原生产物测试地图：构造与等同性记录（2026-10-28）

## 范围与约束

本记录是**隔离测试夹具**的构造证据，不是游戏实机帧率、加载耗时、资源内存或画质验收。测试地图来自正式 `axel_town` 当前记录，保留布置、碰撞、模型及材质参数。导入模型使用完整材质 native `.scn`；游戏侧使用的 49 个模型逻辑 `.glb` 路径均不存在。

- 正式地图：`D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf`，SHA-256 `667091a1e0b299f44d0ad1e9bb5d247fd1bec74603b3ac9dd401d494f418e8e4`。
- 隔离根：`D:/code/rmmo_runtime/review_artifacts/axel_full_native_staging_20261027_01`。
- 测试地图：`packs/default/maps/axel_town/map_full_native.gltf`，SHA-256 `870e9384df4923df7668967e17faddc7bfb15444100b525f664b3f65515f12d1`。
- 测试清单：`full_fixture_manifest.json`，SHA-256 `e54ff11993616a492c6a7e4abce21ebd5b2c40e5604b92d51907933d5d25dcb7`。
- 该根下的五件模型 authoring 备份属于离线产物，不在其逻辑模型路径，也不作为运行时 GLB 输入；不能把目录中存在任意备份文件误称为逻辑路径回退。

## 构造和验证

`tools/isolated_full_native_map_builder.gd` 使用真实 `Store.read_records` 读取并解包原图，只重定位 schema 中模型与材质路径；其余字符串（包括内容恰好是路径的 provenance）不改。路径变动的 frozen prefab 通过 `Prefab.retarget_materials` 同步其内部材质路径。源码 map 的原始 JSON 文本只替换唯一个 `rmmo_records` 和唯一个 `rmmo_resource_dependencies`，新字段以 full precision 序列化；其他地图元数据保持字节内容及解析值。新引用由 `Store.write_records` 生成，再实际重新解析目标地图并重新读取全部 rmres。

对每一条重开的记录，分别对原根与目标根的 schema 路径做标准化，比较所有记录字段；对 prefab 先解码，再比较完整几何、材质值及路径。不是抽样对比。

| 项 | 结果 |
| --- | --- |
| 逐条重开比较 | 2369 条，0 条差异 |
| 全部非引用闭包地图元数据 | 源目标解析结果相等 |
| 路径重定位的 prefab packet | 721；其解码内容按上述范围逐条比较 |
| 源模型及 staged 完整材质 native 产品 | 49 个逻辑模型、49 个唯一 SCN；构造时每个 SCN 离线 SHA 与发布身份一致 |
| 源地图与测试地图引用 | 1065 个目标 rmres；独立文件审计重新计算其 SHA，均匹配地图和清单 |
| runtime 材质引用文件 | 159 个原图/sidecar；源、目标 SHA 均匹配，其中 DDS 74 个；85 个纹理角色变体 |
| 原始地图 | 构造后 SHA 保持 `667091…e8e4` |
| staging 模型逻辑 GLB | 49 个路径均不存在 |

独立文件复核：`D:/code/rmmo_runtime/review_artifacts/full_map_builder_real_20261028_02/independent_file_audit.json`，issues 为空。SCN 的全量 SHA 由构造器完成，独立审计没有再次读取这些大文件。原图/sidecar 对比仅覆盖此地图实际 runtime 材质定义及对应选中 sidecar，不代表整个资源包均已复制或完整编辑器依赖闭包已满足。引用路径之外的 editor/reference provenance 保持原样。

## 失败样本和修复

1. `full_map_builder_test_20261028_01/output.log`：`flip` 的 GDScript 类型不能推断，脚本编译失败；进程中止。修复为显式 `bool`。
2. `full_map_builder_test_20261028_02/output.log`：私有测试 **12/1**。比较使用了尚未经过 Store 规范化的内存对象；源地图本身已持久化后加载。将测试基准改为从源地图实际重开的记录，没有放宽内容比较。第 03 轮 **13/0**。
3. `full_map_builder_real_20261028_01/output.log`：真实构造检查失败，Godot 默认 JSON 重写导致非引用元数据浮点精度变化。失败地图及生成物保留；没有覆盖或删除。构造器改为仅文本替换两处唯一引用字段并以 full precision 写引用；使用新地图名重试。
4. `full_map_builder_test_20261028_04/output.log`：私有测试 **14/0**，包含高精度非引用元数据、重复 JSON key 拒绝、共享 prefab/model、逻辑 GLB 缺失、DDS 字节一致、provenance 保持、材质负向篡改、目标覆盖拒绝。退出 0，无引擎/脚本错误。
5. `full_map_builder_real_20261028_02/output.log`：真实构造退出 0，2369 条记录、49 个模型。与独立文件审计一起构成上述夹具证据。

以上日志均位于 `D:/code/rmmo_runtime/review_artifacts/` 对应目录。失败轮的残留 `map.gltf` 不作为测试样本；后续测试只能使用清单明确指定的 `map_full_native.gltf`，不得混淆。

## 后续测试边界

当前夹具完整保留内容，但尚未证明运行中的所有导入模型和材质在画面中都正确。现有 core-streaming probe 的 full-ready 需 demand、任务、batch、纹理 header 和共享像素及回收计数稳定；其计时不是 GPU 完成栅栏，且不包括完整游戏的 HUD、角色、天气和导航。真实 GPU 检查、加载与区块往返测试、原生模型材质的可见性/覆盖范围、性能前后对照均需单独记录。诊断宿主与产品加载工作应分开归因。

## 完整材质 native 预算：静态观察与待实测

以下仅解析清单列出的 49 个小型 footprint descriptor，没有读取 SCN、启动测试或测量进程内存。当前所有 descriptor 的估算公式与其存储的数值一致。相同场景被多次摆放仍是一个模型描述；以下统计按 49 个模型分别计算，不代表本次需求区域全部加载这些模型。

| 指标 | 静态结果 |
| --- | --- |
| 49 个独立模型保守包络的加总 | **50.03 GiB**；不是实际占用、不是峰值 RSS、不是显存，也不表示 49 个模型会同时驻留 |
| 单模型估算最小 / 中位 / 最大 | 71.7 / 546.8 / 5198.4 MiB |
| 自身估算大于 4 GiB | 1 个：`7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd`，5198.4 MiB |
| 花池 `8072add85cdbbcb157b0c372961af898fa635d9c8973543713ee1d613aaf657a` | 2,733,580,075 bytes，约 2606.9 MiB；SCN 文件约 51.8 MiB，压缩文件大小不代表运行内存 |

在 49 个估算的公式项合计中，GPU RGBA 项约 **19,607.8 MiB**、image mip 项 **15,831.5 MiB**、native 解压项 **10,801.1 MiB**，每模型 64 MiB 基底共 **3136 MiB**。公式对 image mip/GPU RGBA 各乘 3，native 解压乘 2；这些项有意重叠，不能把它们直接解释成 3 份真实对象，也不能因此推断某份副本不存在。花池独立公式包含 GPU RGBA 项 960 MiB、image mip 项 944 MiB、native 解压项约 630.3 MiB、基底 64 MiB，其他模型/碰撞项另计。花池 descriptor 离线观测为 6 张 Image、6 张 ImageTexture；存储的 `image_mip_bytes` 为 329,951,907，`gpu_rgba_bytes` 为 335,544,312，均是描述统计，不是实测同时驻留字节。

初始 `ModelParse` 的默认 in-flight 预算为 4 GiB，再扣可配置的 definition 预算；花池单独未超过 4 GiB，但和另外 **9 个** descriptor 两两相加会超过 4 GiB，其中包含上述本身超过 4 GiB 的独占模型。这只是潜在配对，并不证明这些模型属于同一次初始需求或曾重叠排队。当前 ModelParse 按输入顺序看下一项：排头无法准入时，本次扫描不会跳到后面较小任务。其已完成任务 join 后释放 in-flight 账目，结果仍保留在 `resident` 统计里直到调用者接手；`resident + inflight` 当前没有作为统一额度阻断后续任务。因此不能把 4 GiB 说成全部保留结果、进程 RSS 或显存上限，也不能把任务释放额度说成实际资源已释放。

Deferred 使用独立 admission：本机系统报告物理内存 34,043,858,944 bytes，初始额度按 `physical/4`、上限 8 GiB 计算，再减 definition、prefab decode、几何定义、引用交接及纹理目录各自的实际启用预算；运行结果应以样本中的 `byte_limit` 和保留项为准。一个 model job 在 worker join 后可让出 worker，但其完整模型额度通常仍 `park`，直到消费、丢弃以及延迟 retirement 释放原 owner；独占任务需等待其他额度先排空。纹理 header/shared pixel 和发布 workspace 也可能占用同一 ledger。部分纯 native-reference 任务有经明确证明后可 `shrink_joined` 的既有路径，不能把该规则直接套到完整模型。

要确认是否为本轮关键路径，应在完整材质正式采样中查看 `map_profile.asset_admission_details.blocked_us_by_reason` 和 `tasks` 的逐模型排队时间、各阶段 dispatched/joined 时刻、额度、`worker_us`，并与 `origin_first_ready`、Deferred admission 的 `byte_limit`、各 `stage`/exclusive 占用、资源退役、主线程发布及其他并行阶段的时间轴对齐。先确认花池与最大模型是否实际进入初始需求和 worker、何时与哪些任务重叠，再区分 worker_limit、byte_limit、exclusive drain 和主线程等候；不得把各并行计数相加当成墙钟时间。

安全缩小分阶段额度前，需要隔离模型和实际地图分别观察加载、解码、资源上传、worker join、发布、共享对象借用、取消/失败及 unload/reload 各阶段的 CPU 私有内存与引用生命期；用 GPU 工具独立观察显存/上传队列，并区分 Godot/GPU/OS 指标口径。需要验证极端图片格式、mip、共享/重复实例、重复并发、已完成但未发布、回收中及设备差异下的峰值，再给每个可明确释放的阶段建立绑定产品版本的上界与压力测试。现在静态数字不能证明可以直接降低倍率或缩短 retained 额度。

## 公会完整材质 native 读取：首个实际样本的初步归因

`full_native_pipeline_20261028_03/sample.json` 运行中已发布的初始 `map_profile.asset_admission_details` 快照中，初始模型只有 `7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd`；资源库 `packs/default/assets/library.json` 将其标记为“阿克塞尔冒险者公会（含室内陈设）”。该任务 `queue_us=74`、`blocked_us=0`，`compiled_cache_us=29,465,862`、worker 29,465,910 µs，文件 281,810,329 bytes。此次初始批只有一项，不能用独占或额度等待解释这一项的 29.46 秒，也不能把这份运行中快照当作完整场景测试已通过。花池并非该批模型。

在可信 fixed native 路径中，`CompiledPreparation.read` 的 `cache_us` 覆盖少量路径/长度检查和 Godot 的 `ResourceLoader.load`，没有 GLB 解析、native 产品 SHA、私有场景回调。该 worker 时间与 `cache_us` 几乎相同，强烈指向 native reader 内部；当前数据不能将它拆分为 GPU、CPU、文件读取或锁等待，也不能称作纯磁盘读取时间。

仅取该 SCN 前 32 字节，头为 `RSCC`、ZSTD mode 2、4,096-byte block、576,645,460 bytes 未压缩数据；块表对应 140,783 块。`FileAccessCompressed::get_buffer` 逐块调用底层读、解压和内存拷贝。底层 Windows `fread` 可以被 CRT/OS 缓冲，4 KiB 块数不是物理磁盘请求数。`seek` 若目标在当前块内不会重复解压；binary saver 和 loader 的内部资源通常依同一顺序写入、读取，因此现阶段没有证据声称每个资源 seek 重复解压。已有引擎补丁复用每线程的 ZSTD 解压上下文，但并不消除逐块解压调用。当前 source 快照包含可选 `RMMO_FILE_TRACE` 文件读取计数，是否在所用二进制启用仍需按该二进制构建身份验证。

该产品 descriptor 记录 2319 nodes、2007 ArrayMesh、2099 surfaces、149 materials、60 ImageTexture/60 Image；统计不是计时或物理资源占用。Godot binary loader 对内部资源逐项解析并调用 setter；ImageTexture 的 `image` setter 会创建 texture，而 ArrayMesh 的 `_surfaces` setter 会创建对应 meshes/surfaces。RD 后端可允许当前 worker 直接调用资源创建，这不等于整个过程不会等待 renderer/driver 锁，也不能预先归因为主线程同步或 PNG 解码。建议单独捕获上述 worker 栈并计数、分段：RSCC 的文件读取/seek/ZSTD、binary parse 和 setter、图像和 GPU texture 创建、网格 surface 创建及 pipeline 生成、锁/driver 等待，再与无跟踪正常样本对照。不得依据单次或诊断样本声称某一项已证实为全部原因。
