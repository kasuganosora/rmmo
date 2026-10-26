# 纹理阶段恢复调查：冷暖差异与材质属性表复用

## 状态与测量范围

2026-10-26 恢复目标后，从 `e4475a7f` 干净工作区继续。沿用地图加载计时
开始到当前需求完整就绪的口径；地图 / 预制件纹理开启，导入模型材质仍白模。
派生几何 / bounds / metadata 缓存强制 miss，但重建和写入仍计时；不是禁掉
缓存生产成本。native / dependency index、纹理磁盘缓存保留，OS 缓存不清。

候选引擎沿用 collision_debug_20261026/engine09，SHA256：
`40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`。
碰撞 debug 刷新修复和 compact shader transfer 开启，shader CPU 拆锁保持
默认关闭。没有修改或重编译引擎，没有替换 `D:/tools/godot`。

证据根 `R`：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/resume_20261026/`。

## 先复测慢样本

`run_observed01.py` 通过正式 private-desktop runner 启动测试，使用回调每秒
只读记录进程 CPU / RSS / I/O 及系统磁盘计数。拥有的进程以 PID + 创建时间
和 EXE 确认；不修改 QoS / 优先级，不清缓存，不操作其他进程。
首次观察器初始化 437ms 发生在引擎创建前；运行中观察回调为 0–31ms 的粗粒度
宿主计时，不应算作 Godot 主线程耗时。不是无开销的 ETW 测量。

| 同一引擎、改动前 | 恢复后首条 first01 | 后续 warm02 |
| --- | ---: | ---: |
| entry | 6.217852s | 3.951026s |
| 完整就绪 | 17.117709s | 10.623536s |
| 初始模型 / 实例 / specs | 23 / 1514 / 2185 | 23 / 1514 / 2185 |
| 初始模型解析壁钟 | 1.428408s | 0.610731s |
| hydrate | 1.459568s | 0.060585s |
| 入口纹理 decode | 0.868770s | 0.030447s |
| 67 个异步纹理 header 的累计跨度 | 6.177898s | 0.067756s |
| header 最大跨度 | 319.212ms | 2.450ms |
| 初始 worker 累计跨度 | 46.112636s | 8.816307s |
| 初始合批 sync / rebuild | 30 / 286 | 2 / 217 |
| 初始 packed source visits / worker surfaces | 3506 / 393 | 2724 / 193 |
| 最大记录 material_us | 172.177ms | 122.720ms |

初始队列计数取完整就绪前最近一次采样，分别为 17068.980 / 10584.724ms，
不是声称所有计数都在就绪边界精确同步读取。两条均功能通过、地图及源码不变，
未观察到其他 Godot / Blender / 编译 / GDB 进程。

以 1Hz 样本包住加载窗口，first01 的物理盘 0 读取约 484739072 B，warm02
约 7655424 B；相同窗口本次进程逻辑读取分别 608551009 / 619181543 B，
CPU 时间 22.922 / 21.031 秒。窗口边界误差、系统盘其他进程读取和 OS 缓存
必须保留，不能把系统磁盘计数全部归给地图或当作精准阶段 I/O。
物理盘 0 型号是 TOSHIBA HDWE160；记录来源为本机 Win32_DiskDrive。

这些证据表明本次首次慢样本伴随实际磁盘读取、header 等待和更多合批重建，
不是多加载了初始模型 / 实例。后台累计跨度与壁钟重叠，不能直接相加。
**之前 first_default11 的 22.334s / 919.560ms 没有再次复现，仍不能宣称已
查明那一条的根因。** 本轮首条也没有按物理冷盘实验重新控制环境。

warm02 的卸载 / 返回 / 重载均无 >50ms 帧，最大分别 34.554 / 35.961 /
45.544ms，重载 1% low 27.558 FPS。first01 静止观察还有 63.565ms 一帧，
保持未归因，不能自动称作 OS idle。

## profiler / GDB 的有效证据与干扰

- diagnostic03：7 个主线程样本，打开 verbose + 原生逐容器 profile。
  捕获 `ArrayMesh::surface_set_material → BaseMaterial3D::get_rid →
  _update_shader → ShaderRD::_load_from_cache`，但栈顶停在
  `WindowsTerminalLogger::logv → FlushFileBuffers`。这证明调用关系，
  不能把该采样比例当作正常运行的 shader CPU 热点。
- diagnostic04：关闭上述日志，11 个主线程样本；主要为 GDScript、
  Dictionary/Array 操作及一次 Vulkan present，未抽中那条 919ms 调用。
  正常 detach，功能通过；两轮 all-stop 记录均不参与普通性能比较。
- official05：官方 servers / visual profiler，真实调用者归因开启，
  无脚本 / 引擎错误。最慢 streaming 帧为 435.987ms，其中多次
  `surface_set_material` 合计 353.708ms；这是 profiler 样本，不与普通
  122.720ms 单次跨度混为一谈。后台方法也进入全局统计，不能称作主线程
  累计 CPU 时间。

official05 同时发现重复构造材质属性表：入口 `RuntimeMeshCache.material_data`
调用 `get_property_list` 259 次 / 81.196ms；收尾 `GroundBatchGeometry.material_key`
330 次 / 121.002ms。每次先构建完整属性字典列表，再筛选 STORAGE 字段。
对相同状态的原生 StandardMaterial3D，这些字段名相同，但字段值必须实时读取。

## 修改和语义

新增 `scripts/world3d/standard_material_schema.gd`，两个消费者共享属性名表：

- 仅支持已阅读源码的 Godot 4.7.2 原生 StandardMaterial3D，无附加脚本。
  其他版本、原生子类 / 扩展、自定义脚本仍枚举真实属性表。
- key 包含 transparency、alpha AA、billboard、deep parallax、skin mode、
  shading mode、physical light units。依据引擎
  `scene/resources/material.cpp::BaseMaterial3D::_validate_property` 的 STORAGE
  分支；仅改变 Inspector 显示且保留 STORAGE 的分支无需另分表。
- 最多保留 64 份只读属性名数组；不缓存材质值、纹理、RID 或资源对象。
  并发首次构造由短互斥保护。超过上限直接枚举，不扩大预算。
- 元数据后缀每次从 `get_meta_list` 读取，保留原顺序、String 类型以及实时
  增删。原生 Object 的 metadata 属性位于普通属性之后。材质值仍逐次获取，
  合批排除条件、摘要算法和保存格式不变。
- `--legacy-material-property-enumeration` 只用于同代码对照，消费者恢复原来
  完整循环。没有删掉真实缓存重建 / 写入工作来缩短测试口径。

没有修改模型、纹理、用户地图或编辑器业务操作。

## 独立复现和回归

`tools/test_standard_material_schema.gd` 对比原生属性顺序 / 类型 / STORAGE、
打包字节及合批摘要，覆盖状态组合、同一对象状态改变、元数据增删、自定义
脚本动态属性、64 表边界和 4 线程读。schema08 **7024 项通过**。

512 个不同颜色 / 粗糙度材质各执行一次打包和一次合批比较，同进程 ABBA：

| 模式 | elapsed | 输出字节 | 摘要字符 | 属性表构造 |
| --- | ---: | ---: | ---: | --- |
| A1 原完整循环 | 646.422ms | 2205696 | 32768 | 每个消费者完整枚举 |
| B1 共享字段名 | 222.346ms | 2205696 | 32768 | 1 次 / 1023 hits |
| B2 共享字段名 | 158.852ms | 2205696 | 32768 | 累计 1 次 / 2047 hits |
| A2 原完整循环 | 677.138ms | 2205696 | 32768 | 每个消费者完整枚举 |

均值 661.780 → 190.599ms；这是独立工作量收益，不是整图省时。
失败和被替代记录都保留：schema06_before 的 4 个失败来自 metadata 后缀误用
StringName，修成与原生列表相同的 String 后全部通过。schema07 的旧路径还
经过中间数组适配，不能作为公平旧循环基线；schema08 已恢复原循环。

同轮另外 5 组回归全部通过：runtime material pool（GPU）、runtime load
caches（GPU）、white material restore、selected mesh cache、prepared
material publication（GPU，64 项）。GPU 使用不激活的私有桌面。

`test_runtime_load_caches` 原有 `_spawn` 旧参数签名导致 parse error，改为
传 host；测试主动损坏文件 / 原地改变纹理而不触发 mount refresh，现在显式
设置审计策略 `verify_packages=true`。生产默认仍信任资源包，不恢复校验。

## 整图对照记录

`run_matrix09.py` 先保留新路径首条，再顺序执行原路径 / 新路径 / 新路径 /
原路径；使用相同 engine09、原生 profile 关闭。每次启动前观察 5 秒没有
其他相关任务，运行中继续记录。`run_observed09.py` 的 `--legacy-material`
在传入正式 runner 后追加实际游戏参数；它的文件 SHA、argv 和游戏 report
中的 `controls.material_schema_reuse` 共同记录实际模式。

首条 `schema09_first` 功能通过：完整就绪 **10.990502s**，cache pack
**34.615ms**，2 份 schema / 609 hits；没有观察到其他相关进程。单样本仍
未低于 10 秒，不能据此声称整图改善。

四次完整遍历均功能通过，运行前后源码和正式地图 SHA 不变：

| 样本 | 完整就绪 | cache pack | schema 构造 / hits | material_us 最大跨度 |
| --- | ---: | ---: | ---: | ---: |
| A1 原循环 | 11.192386s | 138.195ms | 原完整枚举 | 136.195ms |
| B1 复用 | 10.685036s | 46.530ms | 2 / 1161 | 103.280ms |
| B2 复用 | 11.036551s | 32.953ms | 2 / 1154 | 109.786ms |
| A2 原循环 | 11.806864s | 179.209ms | 原完整枚举 | 142.775ms |

本组加载均值 11.499625 → 10.860794s，约 -5.56%；cache pack 均值
158.702 → 39.742ms，约 -75.0%。加载窗口内未观察到其他相关任务；这是
本组结果，样本不足以证明稳定 p95 或稳定低于 10 秒。材质首次原生提交的
100ms 级跨度仍在；字段名复用不等于解决 shader / RID 提交。

初始工作仍为 23 模型 / 1514 实例 / 2185 specs，四条 packed source visits
均为 2724。初始 rebuild 分别 168 / 144 / 147 / 164，worker packed surfaces
139 / 110 / 117 / 135；这些阶段计数取就绪前最近采样，不是严格相等的
固定工作量。不能将整图变化全部归给属性枚举或将嵌套累计时长相加。

**后续时间线校正：** 上述就绪前采样漏掉了最后一轮提交，不能用其差异
判断最终工作量。这四条就绪后首个采样全部为 **231 rebuild / 228 worker
surfaces / 229 groups / 2564 sources**，packed source visits 全部为 2724。
first01 / warm02 对应的就绪后 rebuild 是 **297 / 231**，worker surfaces
为 **426 / 228**。原始采样保留，最终工作量以此修正；后续新增就绪边界
快照避免继续使用“就绪前最近一次”计数。见
`axel_covered_batch_arrivals_20261026.md` 和该轮 `ready_work06.json`。

帧数据每格为 **最大 ms / >50ms 帧数 / 1% low FPS**：

| 样本 | 静止 | 卸载 | 返回 | 重载 |
| --- | --- | --- | --- | --- |
| A1 | 46.101 / 0 / 49.42 | 44.178 / 0 / 86.40 | 42.817 / 0 / 35.70 | 44.675 / 0 / 30.11 |
| B1 | 60.150 / 1 / 44.26 | 28.501 / 0 / 102.19 | 32.026 / 0 / 41.81 | 42.127 / 0 / 27.81 |
| B2 | 63.006 / 1 / 41.69 | 47.298 / 0 / 100.27 | 40.290 / 0 / 38.97 | 46.351 / 0 / 28.77 |
| A2 | 51.791 / 1 / 53.71 | 39.349 / 0 / 91.70 | 39.721 / 0 / 40.18 | 50.089 / 1 / 27.70 |

1% low 按各阶段最慢 ceil(N×1%) 帧的平均毫秒换算。A1 在卸载、返回、
重载时观察到其他 Blender 任务，分别有 19 / 2 / 34 个重叠宿主采样；初始
加载和静止阶段没有。其他三条未观察到相关外部任务。保留 A1 全部数据，
不将四组遍历帧率包装成无竞争的严格 ABBA；本轮不能宣称 low 帧稳定改善。

B1 / B2 静止尖峰分别出现在地图计时 12498.431 / 12491.403ms，Deferred
join / sync 都为 0，已记录维护项合计仅 78 / 106µs。对应 process_ms 为
7.877 / 84.920ms，它是 Godot 的周期监控值，不能作为当前帧的精确 CPU
时间。两帧仍未归因，不能标成 OS idle，也不能归因到本次 schema 修改。
A2 的 50.089ms 重载帧同样保留，不能因为只略超阈值就删除。

矩阵结束后只补跑已修改测试的最终回归：`schema10_final.log` **7028 项、
0 失败**，包括跨状态热表命中和未知引擎版本回退。最终同进程独立压测
A1 / B1 / B2 / A2 为 628.981 / 159.637 / 154.322 / 550.712ms，输出字节和
摘要字符仍相等。此数据是补充回归，不替换此前 schema08 的固定证据。
最终测试和 helper / EXE SHA 见 `schema10_final.result.json`。

原始完整报告为 `schema09_{first,A1,B1,B2,A2}.json`，功能 / 身份检查为同名
`.result.json`，宿主记录为 `.host.jsonl` 和 `.host-meta.json`。
`summary09.json` / `phase_host09.json` 为派生汇总，重算入口为
`summarize09.py`；所有失败、诊断、首次和慢样本继续保留。

## 关机交接：本轮结束，等待用户恢复

用户要求做完本轮停止。本轮没有安装候选引擎，没有启动下一项优化；正式
地图和资产未改。本轮代码保留已证明的字段名复用与独立工作量收益；完整
加载和 low 帧目标仍未完成，不能把暂停记为目标完成。

下一轮按优先级推进，先独立复现再修改：

1. **首次读取与增量合批互相放大的关键路径。** 冷暖 67 次 header 累计
   6.178s / 0.068s，并伴随 rebuild 286 / 217。先用可控延迟的纹理 / 模型
   到达顺序复现，统计无效重建与重复 source visits，验证加载 cover 下能否
   合并冗余构建；不能扩大队列或改变完整就绪边界来缩短数字。审核是否可在
   资源发布时保存权威 DDS 元数据，减少打开小文件；保留共享去重、容量
   预算、失效与编辑器保存语义，不能盲删预算所需信息。
2. **材质首次提交。** 新路径仍有 103–110ms 的 material_us，历史 919.560ms
   尚未再现。关闭 verbose / 逐容器日志，用官方 profiler 与有边界的 GDB
   采样区分 ShaderRD 缓存解码、RD 锁、GPU 提交及等待。此前 CPU 拆锁整图
   无收益，保持默认关闭，不能仅凭独立压测改默认。
3. **静止及遍历 low 帧。** B1 / B2 两帧均接近地图计时 12.49s，先核对该
   时点游戏和测试宿主在做什么，再捕获主线程 / 渲染线程；这是调查线索，
   不是已确认测试宿主问题。卸载 / 返回继续记录最大值、>50ms 和 1% low，
   保留慢样本以及 PID + 创建时间的外部负载证据。

恢复入口：当前工作区 `C:/Users/luna/.codex/worktrees/map-load-render-review/rmmo`，
分支 `codex/latest-map-runtime-review`；先读本记录，再按需要查原始报告。
候选引擎继续使用上文 SHA 的 engine09；常用引擎仍未替换，禁止直接执行
先前准备但未验收的 `collision_debug_20261026/install12.py`。

收尾时所有本轮地图 wrapper 和最终逻辑测试均已退出，宿主身份核对未发现
仍存活的本轮测试进程，也未发现 Godot / GDB / 编译进程。只读检查保存在
`shutdown11_processes.json`，未终止或修改其他会话进程。
