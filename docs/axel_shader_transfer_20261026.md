# Shader 首次提交：原生阶段计时与所有权转移（2026-10-26）

承接 `bac4a4f2` 的需求目录复用。最近官方 profiler 在初始 cover 内记录
`Mesh.surface_set_material` 单帧累计 310.778ms；本轮继续真实材质提交链，
没有恢复已经失败的隐藏三角预热，没有改地图、材质定义、纹理或就绪边界。

本轮保留的是已复现的重复复制减少，尚未达成稳定加载/低帧目标。最终候选为
显式 compact+move 的 engine22；四组整图功能通过，加载均值 10.955 → 10.839s、
重载 1% low 27.032 → 26.950 FPS。返回仍有 52.335ms（其中需求维护 29.240ms）。
GPU 回归通过，常用引擎尚未替换；修正和失败候选均归档，供后续锁/调度优化累计。

证据目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/shader_submit_20261026/`。

## GDB 证据与失败边界

- `capture01` 在地图计时起点挂接，48 个周期样本、游戏功能通过，但只捕获
  入口中的 8 次相同 SPIR-V，未覆盖目标材质提交。不能用它解释 311ms。
- `capture03` 改为初始 stream 起点，75 个周期样本、游戏功能通过；捕获
  108 次 parse、46 份唯一输入（全部 inline），总输入 3529992 B、唯一
  输入 1495836 B。这是带调用栈筛选的样本，不能当作全场景解析总数或
  直接换算整图去重收益。未修改 inferior 内存、未调用其函数。
- 同一采样中主线程在 `RenderingDevice::uniform_set_is_valid` 的
  recursive mutex 等待，后台 `_prepare_job` 处于
  `ArrayMesh.surface_set_material → BaseMaterial3D.get_rid → ShaderRD._load_from_cache
  → RenderingDevice.shader_create_from_bytecode_with_samplers → Vulkan driver → respv::Shader`
  链。源码确认 shader 创建方法的 RD 锁覆盖解析与 Vulkan 创建。后台化并不
  自动免除主线程等待；断点会放大等待，本轮不报告它的正常占比或耗时。
- `native05` 去掉输入断点、加密周期采样，取得 151 个样本，但采集暂停累计
  至少 114.895s，最终触发测试宿主的 demand-settle 超时，exit 1、full-ready
  缺失。失败日志完整保留，不计作正常性能或功能通过样本。栈还包含纹理上传
  transfer-worker fence 等待，但不能把其他帧统一归给这一条链。

## 先解释压测与引擎的差异

独立 SPIR-V 压测远快于整图材质提交，不能以此断言整个提交应该接近零。
检查构建配置确认 `dev_build=no` 已设置 `NDEBUG`；不是漏关 assert。
另外将正在使用的引擎 re-spirv `.o` 直接链接进独立程序，46 份输入解析
中位约 13.69ms，与独立同源码构建相当。捕获输入只是整个 shader 变体集合
的一部分，实际 map 诊断创建 688 个 shader container，不能比较两个不同
工作量的数字后推断编译器出了问题。

## 去掉两次深复制

`RenderingDeviceDriverVulkan::shader_create_from_container` 原先：

1. 将局部 `respv::Shader` 复制进 `respv_stage_shaders`，复制其所有 vector。
2. 将局部完整 `ShaderInfo` 再复制到最终资源分配，其中又含上述解析数据。

两处源对象在成功交接后不再使用，改为 `std::move`。不改变解析、内联、优化、
specialization、VkShaderModule、描述符布局、RID 或缓存生存期。失败路径仍
使用原来的清理逻辑。新增 `RMMO_SHADER_TRANSFER_MOVE=0` 诊断旧路径；正常
默认转移。`RMMO_RESPV_PROFILE=1` 仅在诊断时记录解码/解析/交接/模块创建，
正常不逐调用计时或输出日志。

补丁：`tools/engine_patches/godot-4.7.2-shader-data-transfer.patch`。
独立复现：`tools/engine_patches/bench_shader_transfer.cpp`。该程序用两个
stage 的标准 vector packet 复现两次交接语义，不冒充完整 Vulkan driver；
真实 engine06 的阶段计时另行验证。

`micro04` 的 46 输入 × 40 轮 ABBA：复制交接每轮中位 1.475/1.611ms，
转移 0.00430/0.00415ms；全部优化输出逐字节 SHA 相同。两组转移分别检查
2760 次 buffer 地址交接。`object08` 链接实际引擎对象再次确认复制
1.736ms、转移 0.00390ms。独立测试收益不直接放大成整图加载收益。

## 原生阶段计时

engine06 SHA `985732cc831f53f89e0031ee587373b3d7a05ccc293c99b6aa5e3dca074d6a41`，
独立符号 SHA `bdf6c788572f11a0110817d4230848f97d07db80d88cdf749b349b387a37d220`。
构建前保存完整 driver 源码，保持此前引擎补丁和构建选项；安装引擎尚未在此步覆盖。

首轮 `diag07_move0` 完整就绪 17.279s，其中 Vulkan module 创建在入口累计
3662.664ms、入口后累计 2272.826ms。后续较热样本的该项显著缩短；没有
GPU driver cache 命中证据，不能直接宣布具体缓存根因，也不能把首次慢样本
与候选相减宣称省了五秒。该样本保留。

| 诊断 / 阶段 | container 数 | total ms | decode ms | parse ms | transfer ms | Vulkan module ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| diag11_move0 / entry | 256 | 1030.050 | 89.907 | 678.631 | 171.479 | 81.985 |
| diag07_move1 / entry | 256 | 984.896 | 100.603 | 750.438 | 0.216 | 126.900 |
| diag11_move0 / initial stream | 168 | 713.955 | 62.559 | 478.849 | 113.096 | 54.838 |
| diag07_move1 / initial stream | 168 | 581.429 | 59.373 | 445.085 | 0.153 | 72.570 |

这是函数内累计值，可能含 worker，与主线程和壁钟有重叠；total 已包含右侧各
子项，不加算。入口与 stream 分类来自日志标记，不是逐帧 CPU 线程占用。
诊断每个 container 还有一行日志，不能拿诊断加载时间替代正常样本。
stage 解析仍有大量成本，此外初始尾段的主线程 batch prepare 仍约 280ms。

## 已完成回归与正常样本边界

`gpu09` 的 prepared material publication、material publication、ground
batching 全部 exit 0、无错误，验证实际 GPU 材质交接及合批结果。
`residency12` 的 shader cache 0/2/32/0 四组共 36 项通过，包含并发创建、
驱逐后仍存活材质、最后 texture/material/mesh 引用释放；四组实际 GPU
红/绿/红回读 SHA 完全相同。没有增加强引用缓存。

正常 `map10` 使用同一 engine06，只有 `RMMO_SHADER_TRANSFER_MOVE` 为
0/1/1/0；新增原生 profile 关闭，其他生产改动相同。沿用地图加载计时到当前
需求连续三帧完全就绪。几何/边界/模型元数据缓存禁用，原生/依赖索引和纹理
磁盘缓存保留，OS 缓存不操作；地图/预制件纹理开启，导入模型材质仍白模。
这不是物理 cold，也不是全部游戏材质验收。

### engine06 正常 ABBA：未证明整体收益

四组均 exit 0、无错误/失败、源码和地图 SHA 不变；GPU 上传均为 170 次 /
721332072 B。实例/模型准备数随异步时序变化，不称所有工作完全相等。

| 样本 | 完整就绪 s | 卸载 max ms | 返回 max ms | 重载 max ms / >50ms | 重载 1% low FPS |
| --- | ---: | ---: | ---: | --- | ---: |
| A1 copy | 10.808 | 37.657 | 37.719 | 41.975 / 0 | 26.961 |
| B1 move | 10.760 | 30.183 | 31.282 | 367.407 / 6 | 14.942 |
| B2 move | 11.432 | 40.157 | 30.633 | 44.221 / 0 | 27.542 |
| A2 copy | 11.032 | 30.811 | 28.407 | 53.931 / 2 | 25.953 |

完整就绪均值 10.920 → 11.096s，不能宣称加载改善。重载 1% low 按最慢
`ceil(N×0.01)` 帧均值换算，候选均值 21.242 FPS、对照 26.457 FPS。
候选 B1 重载 367.407ms；对照 A2 离开阶段也有 289.788ms。对应周期性
process monitor 分别为 17.830/23.046ms，没有这些帧的原生线程栈，不能
把它们归成 OS 空闲、无关样本，或直接证明由本次 copy/move 导致。
普通材质首次提交仍约 89–123ms，问题没有彻底解决。

因此 engine06 没有替换默认安装，失败和慢样本全部保留。继续检查空间成本和
原生解析/锁内工作，而非以独立交接压测作为整图验收。

## 容量副作用与后续候选

`capacity13` 发现直接 move 还会保留 parser 的 spare capacity。46 份输入的
17 个 vector 请求容量合计由 5765408 增为 6267408 B（+8.7%）。这是实际
vector capacity × element size，不包含分配器开销，不是 RSS/VRAM。
不能为了省复制而不记录这个长期空间增加。

候选 `driver_candidate14.cpp` 只对 capacity != size 的 vector 做一次
`shrink_to_fit`，其余紧凑缓冲直接 move，随后完整 ShaderInfo move。检查
当前 re-spirv Shader 的所有 vector 字段均在名单中（17 个）。`compact14`
再次 ABBA，四组容量都精确为 5765408 B，输出 SHA 相同；每轮 transfer
中位 copy 2.084/5.233ms，compact+move 0.625/1.063ms。该轮绝对耗时
存在较大波动，不和 micro04 拼成稳定提升比例。

随后曾将仓库补丁和独立 benchmark 更新为 `shrink_to_fit` 候选。`build_engine15.py`
已成功生成隔离 engine15，构建退出 0。引擎 SHA
`8e5b03da0f1933d2d454b2e178738db32e6448f85bb5e14dde21cc98fb8c47f7`，符号 SHA
`bf9737a4e1b992c36851cf38d89a3396a4b0bfa65e6ef2bb7e98066d5e9730d3`。
driver 源 SHA `3e813c6d8061a203cfae3b6ff483355880a79b47707717832353dfb8f0c2e6bc`；
仓库补丁在当前引擎源码上通过 `git apply --check --reverse`。

`gpu16` 三组实际 GPU 回归全部通过；`residency16` 四组共 36 项通过，
红/绿/红 GPU 回读 SHA 与 engine06 相同，最终闲置 shader 数 0/2/32/0。
重新检查 parser 的数组元素均为索引或值；没有通过元素指针相互引用，compact
不会改变这些索引。`extSpirvWords` 指向输入，并不指向缩容的数组；此处持久
保存的解析结果均 inline，后续优化使用其自有 `inlinedSpirvWords`。

正常整图 `run_abba17.py` 四组全部完成，均功能通过；**尚不能称为最终有效优化**。
第一组 A1 完整加载 16.117s、B1 17.289s 均保留。06:08:11 的只读进程查询
发现另一项 Blender 任务（启动于 06:07:47，累计 CPU 462.641s），与 A1 末段
和 B1 入口重叠；未调整或停止该任务。这只证明存在并发负载，不能解释 A1
更早的慢入口。后加 `observe_host18.py` 记录系统 CPU 和相关进程 CPU/RSS，
其开始记录时 Blender 已退出，不虚构重叠期间的瞬时负载或 GPU 使用率。
整组保留此干扰边界，不用慢 A1 与较热候选直接相减作为优化收益。

默认 `D:/tools/godot` 仍为此前的 `0f0bf446…` 引擎，尚未安装 engine15。

| 样本 | 完整就绪 s | 卸载 max ms | 返回 max ms / >50ms | 重载 max ms / >50ms | 重载 1% low FPS |
| --- | ---: | ---: | --- | --- | ---: |
| A1 copy | 16.117 | 30.132 | 107.155 / 5 | 49.785 / 0 | 25.761 |
| B1 shrink + move | 17.289 | 41.271 | 31.775 / 0 | 41.129 / 0 | 28.261 |
| B2 shrink + move | 11.111 | 34.609 | 36.414 / 0 | 43.845 / 0 | 27.444 |
| A2 copy | 10.897 | 49.246 | 30.978 / 0 | 43.330 / 0 | 26.540 |

后两组亦不能说明加载变快。B1 仍有离开 61.861ms / 2 帧及静止 61.324ms / 1 帧，
A2 静止 54.238ms / 1 帧；不丢弃这些帧。四组上传都是 170 次 / 721332072 B；
模型 64/68/65/66、实例 3233/3249/3269/3261，异步工作次数并非全部相等。
B2 的单次材质提交仍 99–103ms，A2 约 103–108ms。旧 engine06 的 367/289ms
尖峰没有在本轮复现，不等同其原因被解决。

## 原生计时发现容量测试漏掉了引擎编译选项

`diag19` 两组均功能通过、均创建 688 个 container。入口/stream 的 copy
交接累计为 167.160/112.118ms，engine15 的所谓 compact+move 仅 0.241/0.124ms。
这个几乎没有压紧成本的结果与 micro 不符，继续检查才发现：

- Godot `SConstruct` 默认 `disable_exceptions=true`，实际使用 `-fno-exceptions`。
- 本机 MinGW 15.2.0 的 `bits/alloc_traits.h:1000` 在 `__cpp_exceptions` 未启用时，
  `__shrink_to_fit_aux` 直接返回 false；此处 `shrink_to_fit()` 实际是空操作。
- `compact14` 独立 benchmark 没带该选项。即使链接引擎的 re-spirv `.o`，
  vector 的模板代码仍由 benchmark 自己的编译选项实例化，不能验证引擎容量。

因此 **撤销 engine15 已恢复紧凑容量的推断**。其功能/帧耗时记录仍有效，但不是
有效压紧候选，不能安装。入口 total 918.036 → 963.026ms，stream total
660.885 → 555.272ms，仍有其他子阶段波动，不能把交接累计直接当壁钟节省。

`verify_compact21.py` 带 `-O3 -DNDEBUG -fno-exceptions -fno-rtti`，链接实际
引擎 re-spirv 对象，复现并修复这个漏验。对有 spare capacity 的 vector 改为
显式 `std::vector<T>(begin, end).swap(vector)`；已经紧凑的 vector 不复制。

| 独立测试 | vector 容量 B | 交接每轮中位 ms | 输出 |
| --- | ---: | ---: | --- |
| 原复制对照 | 5765408 | 1.67805 | 46 份 SHA 一致 |
| 原 shrink + move，禁用异常 | 6267408 | 0.00430 | SHA 一致但容量失败 |
| 显式 compact + move，第 1 组 | 5765408 | 0.42435 | 46 份 SHA 一致 |
| 显式 compact + move，第 2 组 | 5765408 | 0.46040 | 46 份 SHA 一致 |
| 末组复制对照 | 5765408 | 1.49260 | 46 份 SHA 一致 |

每组 40 轮、46 个输入；两组修复各 2760 次压紧后的 buffer 交接检查通过。
测试、编译命令和 SHA 在 `noexcept21.json`，旧容量失败也保留。
仓库 patch/benchmark 已更新为显式交换版；独立 engine22 构建成功，SHA
`5daa60be7ef022e71a42ed95333f4d3b008be3a02d48cbc8d7d85af4bd23403d`，符号 SHA
`14640e1ee66451a49e4a6f02028dc331fc2286d03457f0dfd38365c448955dc6`。
driver 源 SHA `2c803e1db916f6fb19a3e60c1fe7aa453422b01dbf710b84963cef70b8ea30ef`。
`gpu23` 三组通过，`residency23` 四组 36 项通过、GPU 图像 SHA 一致。
补丁在当前源码通过反向 apply 检查。默认安装仍未替换。

`run_normal24.py` 已完成：预先固定协议，先单独保留候选首次地图
`first_map25`，再做 copy/compact/compact/copy 四次完整 `map24` 遍历。
所有样本原生 profile 关闭、不清 OS 缓存、不改优先级，加载边界和纹理/缓存
条件与上轮相同。首次运行也保存计时和失败，不将其静默排除；这不是证明
driver cache 根因的实验。`observe_host24.py` 全程只读记录相关进程负载，
按进程名筛选后才读取 CPU/RSS，结束自动停止。

首次地图 `first_map25` 功能通过，entry 6.805137s、full-ready 15.263710s；
首次慢样本保留，不解释为特定 driver cache 因果。之后四次遍历全部 exit 0、
功能通过、源码/地图 SHA 不变，新增原生 profile 关闭：

| 样本 | 完整就绪 s | 卸载 max ms | 返回 max ms / >50ms | 重载 max ms / >50ms | 重载 1% low FPS |
| --- | ---: | ---: | --- | --- | ---: |
| A1 copy | 10.643 | 32.506 | 31.651 / 0 | 43.424 / 0 | 26.527 |
| B1 compact + move | 10.765 | 30.659 | 52.335 / 1 | 41.301 / 0 | 26.759 |
| B2 compact + move | 10.913 | 31.514 | 31.879 / 0 | 44.762 / 0 | 27.140 |
| A2 copy | 11.267 | 45.585 | 37.856 / 0 | 44.423 / 0 | 27.538 |

完整加载均值 10.955083 → 10.839116s（-0.116s），重载 1% low 均值
27.032446 → 26.949894 FPS，没有稳定总体帧率改善证据。返回 1% low 均值
49.560748 → 44.750644 FPS；B1 的 52.335ms 对应需求 bookkeeping 29.240ms，
同期 periodic process monitor 40.958ms。前者是该帧区间，后者不是逐帧 OS CPU。
不把该帧归为 OS 空闲，也不据此证明是 shader 交接引入的回归。
候选静止仍有 54.450/57.587ms，未完成归因。

所有组纹理上传均 170 次 / 721332072 B；模型 69/62/73/68、实例
3317/3209/3311/3277，仍不声称全部异步工作相等。正常材质提交 max 为
114.079/106.888/103.122/109.719ms，长提交仍在。`host24.jsonl` 共 642 条
只读样本，没有看到其他 Blender/编译器进程；系统 CPU 峰值 37.9%，这并非
CPU/GPU 完全空闲的保证。观察器正常停止。四次样本不作为稳定 p95。

最终 engine22 的 `diag26` 原生计时两组均功能通过，container 数保持
264/256/168。入口+stream 交接累计 **280.218 → 70.761ms（-74.7%）**；
显式压紧实际产生了成本，符合独立禁用异常测试，不再是 engine15 的空操作。

| 阶段 / 模式 | total ms | decode ms | parse ms | transfer ms | Vulkan module ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| entry / copy | 999.973 | 90.349 | 647.005 | 172.215 | 83.093 |
| entry / compact + move | 970.734 | 98.357 | 725.969 | 41.545 | 97.294 |
| initial stream / copy | 640.263 | 55.722 | 422.999 | 108.003 | 49.201 |
| initial stream / compact + move | 597.819 | 57.136 | 446.800 | 29.216 | 59.500 |

total 包含右侧子项，包含后台调用，不能相加或全部视为主线程 CPU/关键路径。
诊断完整加载仍有 11.426/13.303s 波动，native 之外的入口耗时未由此实验
归因；这两组带逐容器日志，不混入正常 map24 对照。不用阶段计时掩盖慢样本。
下一步继续解析和同步创建这一更大的区间，默认安装仍保持 `0f0bf446…`。

## 下一关键路径的源码边界

`RenderingDevice::shader_create_from_bytecode_with_samplers` 的方法级锁覆盖
container 解析、Vulkan driver 中的解压、SMOL-V 解码、re-spirv 解析与 Vk
资源创建。`ShaderRD::_load_from_cache` 即使命中磁盘缓存也会经过该路径。
因此减少交接复制并不会自动消除大部分解析或主线程等待。

`diag19` 的入口 256 次、stream 168 次（共 424 次）均为
`SceneForwardClusteredShaderRD` 容器创建；bootstrap 264 次另计，不能
塞入地图加载边界。日志只有 shader 类型和变体编号，不能据此断言 424 个
不同材质或 424 份重复输入。源码进一步确认 `_load_from_cache` 逐个同步
创建已启用变体，而 `_compile_version_start` 缓存未命中时才创建原有的
`ShaderCompilation` 任务组。后续应先验证锁外准备，再检验缓存命中路径是否
能复用同一任务组协议；必须维持相同变体工作量、失败清理和任务完成语义。

下一候选应先在测试中分离每次调用独占的 CPU 准备与需要锁保护的 GPU 创建、
sampler 查询、RID 发布；保留当前输入、错误路径、specialization 与所有权。
需要验证暂停一个准备任务时其他任务和主线程可继续、实际 GPU 输出一致、
准备失败无资源泄漏，并测额外阶段缓冲的峰值成本。此方案目前仅完成源码
边界审查，**没有实现移出锁，也没有新建共享解析缓存**。
