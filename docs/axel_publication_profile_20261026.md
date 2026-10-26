# 纹理发布链下一轮定位（2026-10-26）

从 `26087789` 继续，目标仍为 active。此记录是新的诊断证据与复现入口，
不是已完成修复；不要重新把之前的合批工作量收益当作总加载达标。

## 普通样本指出的实际成本

证据为 `covered_arrivals_20261026/selective09_normal.json`。在完整就绪后的
首个 Deferred 采样中，covered 服务累计 **4.441432s**，发布单元累计
**3.569284s / 1698 units**，接纳结果 **41.534ms / 185 units**。
这些累计跨度有包含关系，不是可相加的独立 CPU 时间，也不是全部在入口后。
当前完整就绪 11.011397s、entry 约 4 秒，工作量详细记录见上一轮文档。

纹理计划生成 185 次仅 13.647ms、header ready 206 次 31.241ms，67 个唯一
header 累计后台跨度 80.407ms。暂不为此扩大缓存或新增复杂状态机；它们不是
本条暖样本数秒尾部的解释。首次 header 6.178s 的历史样本仍需单独归因。

## 官方 profiler 记录

证据根 `P`：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/publication_profile_20261026/`。

`P/run_official02.py` 使用既有 engine09（SHA `40554844…`），
`record_axel_official_profiler.gd` 接收官方 servers / visual 协议，
`profile_axel_worker_official.gd` 记录 engine frame 对齐，原生调用者归因开启。
GPU 客户端仍在不激活的独立桌面；接收器使用外部空项目，headless。
没有逐容器原生日志、引擎修改、优先级 / QoS 修改或 OS 缓存清除。

- `official02.result.json`：client / receiver exit 0，failures / errors 全空，
  源码和地图 SHA 不变；3691 个官方 profiler 帧，离线解码 exit 0。
- `.host.json` 仅观察到本次客户端和接收器，没有其他相关 Godot / Blender /
  GDB 进程；这不是无外部负载的系统级证明。
- **失败夹具保留**：`official01` 从完整遍历命令删掉 native-departure，却
  漏加 origin-only，导致“跨多个格 / 卸载 / 返回”三项断言失败。没有脚本或
  引擎错误；不是生产加载回归。`official02` 明确 origin-only 后通过。不能
  把 official01 当作已通过的卸载 / 返回验证。
- 两条均为诊断运行，profiler 改变了时序、到达顺序及工作交错；不使用它们
  的加载秒数、帧率或调用数量作为普通固定工作量 AB 结论。

`official02.summary.json` 的 white_stream_origin 阶段：

| 调用 | 次数 | self 累计 | inclusive 累计 | 含义 |
| --- | ---: | ---: | ---: | --- |
| `SurfaceMaterials.painted_mesh` | 311 | 311.441ms | 1512.458ms | 主线程给程序道路等应用 paint |
| `SurfaceMaterials.geometry` | 311 | 283.510ms | 497.126ms | 面分组 / 几何标识，包含在上项中 |
| `CpuMesh.restore → surface_set_material` | 709 | 535.923ms | 同左 | 主线程原生材质提交跨度 |
| `procedural_surface_bounds.bounds` | 311 | 319.970ms | 同左 | 后台准备边界；不是另一个主线程成本 |
| `prefab_face_arrays.build` | 1442 | 2325.841ms | 2327.556ms | 后台 face 准备，不能计入主线程合计 |
| `geometry_signature → HashingContext.update` | 758 | 879.944ms | 同左 | 多消费者的全局 profiler 汇总，需再按调用路径区分 |

最长三个 streaming 诊断帧：

| engine frame | 帧跨度 | surface_set_material 次数 / 累计 |
| --- | ---: | ---: |
| 1540 | 395.741ms | 8 / 322.442ms |
| 1627 | 171.585ms | 12 / 103.587ms |
| 1541 | 167.928ms | 3 / 104.060ms |

这些是加 profiler 后的跨度，不能拿来替换普通样本中的长帧或认定全部是 CPU
计算。现有 GDB 调用链已指向 shader 载入 / 创建，但本次没有新抓 GDB 栈，
也没有证明 919.560ms 历史慢样本根因已解决。

加载阶段另有 `terrain_regions.mask` 17 次，self 6.281s / inclusive 8.213s，
以及 863604 次 `Geometry2D.is_point_in_polygon`；主要是后台、受 profiler
放大，不能直接声称可减少 8 秒。它是后续独立算法压测候选，不抢当前发布链。

## 下一项实施边界

代码证据：`ChunkReferencePreparation` 已在现有几何 worker 中生成道路原始
arrays 和 bounds，`DeferredAssets._accept_prepared_records` 交给 document。
随后 `WorldDocument._mesh → SurfaceMaterials.apply → painted_mesh` 仍在
主线程重新做 paint 面分组、UV / 切线、重排与最终 `CpuMesh.from_surfaces`
的边界扫描。材质绑定 / 全局纹理和共享材质缓存仍属于主线程。

接下来先在独立测试中复现同一道路的这两阶段，再拆出**只读源 arrays +
paint 声明 → 私有几何结果与材质绑定描述**的纯 CPU 函数，评估能否跟随
现有 worker / byte lease 准备。先证明输出与旧路径一致，再接正式流程。

必须覆盖：

- 部分 face paint、完整 UV、平面 / 米制投影、不同材质、normal 切线；不能
  因当前城镇常见整面铺装就假设所有声明覆盖整个 surface。
- 精确三角形 / 顶点通道 / 材质顺序、边界、未修改源 arrays；不能直接复用
  源 AABB 而漏掉重排剔除未引用顶点后的差异。
- 私有中间结构与结果纳入现有内存估计、取消和资源回收；不额外扩线程数，
  不建立无上限跨区块缓存。已有 editor 任意材质与几何编辑继续走通用路径。
- `surface_set_material` 另行处理：先复现实际 material / shader 组合，核对
  GDB 主线程 / 渲染线程和后台锁；不恢复已经证明无效的隐藏三角预热。
- 接入后沿用正式计时边界，对照加载 / 卸载 / 返回 / 重载、1% low 和工作量。
  若只是把工作移到后台而关键路径更慢，保留证据并调整，不宣称总加载完成。

目前未修改上述发布链实现，未运行新的美术生产或编辑器功能操作。
