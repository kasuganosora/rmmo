# 原生地图保存性能（2026-10-03）

UI 保存、另存为和当前 3D MCP `save_world` 仍复用 `WorldDocument.save`，保留完整 glTF 网格、PBR 贴图、原生编辑记录与现有原子发布。优化不把地图改成只有参数而没有实际网格的文件，也不降低贴图尺寸或网格精度。

## 定位与实现

原参考城镇的分段测量：场景重建约 24.13 秒，原子导出约 219.85 秒；其中 Godot `append_from_scene` 约 3.49 秒，`write_to_filesystem` 约 214.62 秒。主要开销在 glTF 写出而非磁盘原子替换。

`gltf_static_geometry.gd` 对原生 `.gltf` 地图的普通三角网格采用顺序二进制写入，以 SHA-256 索引复用相同顶点数据段。Godot 继续负责场景图、变换、材质、图像、动画和蒙皮的标准序列化；仅在暂存文件中使用保持材质槽的简化网格，写完真实几何后才允许原子发布。骨骼、变形、自定义通道和非三角图元沿用引擎路径；`.glb` 及通用外部资产导出路径不变。颜色、法线、切线、双 UV、索引绕序和 POSITION 包围范围均保留。

性能问题的源码参考：[Godot GLTFDocument](https://github.com/godotengine/godot/blob/master/modules/gltf/gltf_document.cpp)、[GLTFBufferView](https://github.com/godotengine/godot/blob/master/modules/gltf/structures/gltf_buffer_view.cpp)。源码展示逐段去重与缓冲扩展；上述耗时来自本机 Godot 4.7.2 的实际测量，不将源码阅读代替性能测量。

`save_mesh_cache.gd` 为每个文档保留最多 **96 MiB 顶点数组载荷**的 CPU 缓存，不持有第二套 GPU 网格。缓存键包含完整物件记录及共享边缘法线；修改、撤销、邻块法线变化会失效，删除记录会清理，外部模型与自动瓦片模型套件保留原构建路径。单次遍历固定已用条目，避免地图大于缓存时逐项淘汰造成每次保存全部未命中。缓存不跨文档、进程或打开操作持久化，也不跳过保存校验。

锁、磁盘签名冲突检测、不可变资源版本、`.previous` 恢复入口以及原子替换的顺序保持不变。不额外复制用户地图目录。导出失败不会把简化中间网格发布为正式文件。

## UI / MCP

工具仍为 114 个，二维适配器不注册。`save_world` 默认等待完成，成功结果包含 `timings`：`validate_ms`、`build_ms`、`publish_ms`、`total_ms`、`geometry_cache_hits/misses/bytes` 和 `export` 中的 `append_ms/write_ms/streamed_meshes/meshes/materials`。`publish_ms` 包含导出、依赖改写和原子发布，不等于纯磁盘耗时；`export.write_ms` 包含引擎写出与静态几何补全。

2026-10-03 增加可选 `background:true`，立即返回 `pending:true/saved:false/job_id/path`；用 `editor_state.save` 读取 `active/phase/completed/total/elapsed_seconds/result`。完成或失败后保留最后一次结果，任务 ID 在当前编辑器实例内递增。默认 HTTP 调用仍等发布完才返回 `saved:true`，其他客户端可以同时读取进度。连接断开不会取消写盘。

底部状态栏显示当前阶段（检查地图与素材、准备地图网格、整理场景、导出材质与贴图、写入网格数据、完成原子保存）和已用秒数。有数量的阶段显示已完成/总数；引擎内部编码和原子替换没有细分进度，使用活动条，不编造全局百分比或剩余时间。完成显示总秒数并收起进度条；失败显示原因、收起进度条，保持 dirty 和原文件。

`save_job.gd` 为 UI 保存、另存为、保存后打开、保存后关闭及 HTTP 提供同一个任务。任务期间禁止编辑输入和所有 MCP 写操作，草稿定时器暂停写入，关闭请求不能打断发布；只读查询继续工作。保留 3D 视口的最后一帧、暂停城镇辅助线重复投影，状态栏仍持续绘制，成功或失败后恢复原视口更新模式。

校验调用同一套 `WorldDocument` 校验器，网格构建沿用有界 CPU 缓存；两者在主线程每批约 8 ms 后让出一帧。资源根校验会读取活动 AssetManager，因此不在工作线程访问它。材质及纹理图像在主线程制作专用快照；缓存 CPU 网格只共享不变的顶点数组，不在缓存上修改材质。独立线程只拥有离屏导出场景及导出资源，完成后 join，再回到主线程接纳磁盘签名、释放场景、清除 dirty。线程使用互斥锁报告进度，不读取或修改活动编辑器场景。参照 [Godot 线程安全约束](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)。同步 `WorldDocument.save` 继续服务无界面的脚本，复用相同校验和原子发布实现。

## 验收与实测

所有测试仅写临时地图，正式城镇 SHA-256 保持 `a02a52f5cd4c28bc2869ff420f13fea7e67119f0da9e99e9ccdcaf5cc37d7621`。

| 范围 | 实测 |
| --- | --- |
| 原路径，场景重建 + 原子导出，不包含先前读取/记录校验 | 243.98 秒 |
| 首轮顺序导出，同范围 | 42.95 秒 |
| 加入缓存后的第一次完整 `save`，包含记录校验和缓存填充 | 54.67 秒 |
| 同文档局部地形修改后的完整 `save` | 25.19 秒 |
| 同文档再次保存（仍完整导出资源） | 24.43 秒；997 命中 / 0 重建 |
| 第二次保存的场景重建 | 0.96 秒；996 命中 / 1 重建 |
| 城镇 CPU 几何缓存载荷 | 73.69 MiB，未超过 96 MiB 上限 |

这些是一次本机受控测试，不是所有地图的速度保证；首次保存与连续保存分开报告，读取地图不计入保存时间。缓存数组直接交给导出器，避免重新上传 GPU 时再次量化法线；第二次 `append_from_scene` 约 0.05 秒。新鲜进程的原始报告在 `D:/code/rmmo_runtime/review_artifacts/save_performance/`：`baseline.json`、`streamed.json`、`cached.json`。

- `tools/benchmark_world3d_save.gd`：默认 `baseline` 使用仅供测试的引擎几何导出开关，`streamed` 使用顺序导出，`cached` 测量首次保存与真实地形修改后的再次保存。后台私有桌面执行，输出唯一临时目录。
- `tools/compare_gltf_geometry.py`：独立解码 glTF 二进制，逐个比对 997 个网格、2964 个材质面、1120955 个三角形；各顶点属性误差为 0，索引绕序一致，10 张图像内容哈希相同，节点/元数据/PBR 材质一致。
- `tools/test_world3d_save_performance.gd`：真实 HTTP 工具发现、保存耗时响应、缓存与邻块失效、非法路径无副作用、撤销重做、保存重开、外部修改冲突、中断及重试；缓存网格与独立重建逐数组比较。
- `tools/test_world3d_save_reliability.gd`：强制中断写入、故障注入、旧版恢复、存活/失效锁和冲突保护。
- `tools/test_world3d_native_gltf.gd`：混合静态网格与蒙皮/变形、动画、灯光相机，用标准 glTF 导入器检查真实网格，避免原生编辑记录重建掩盖导出错误。
- `tools/test_world3d_recovery.gd`：真实 HTTP、自动草稿、恢复、关闭保存、失败与重试。

最终四项回归共 158 个检查通过，记录在 `regressions.json` 和各项引擎日志；子进程启动日志单独保留。测试限制父进程帧率并为独立 Godot 进程预留 45 秒启动时间，避免把启动未完成当作关闭功能失败。

上述 55/25/24 秒为上一轮同步性能基线。新增进度版本另用 `tools/benchmark_world3d_save_progress.gd` 在完整编辑器和正式城镇的临时副本中测量，结果保存在 `review_artifacts/save_progress/town.json`；不将纯导出基线与活动编辑器的耗时混为同一测试。仍需后续处理取消、重复图像编码和增量资源发布；单个复杂网格或纹理回读不能被 8 ms 批次预算中断，允许有限帧时间尖峰。

- `tools/test_world3d_save_progress.gd`：真实 HTTP 发现、后台模式、保存中查询与无副作用拒绝、默认等待超过服务器 10 秒空闲期限、Ctrl+S、视口暂停/恢复、失败重试和保存重开；截图 `save_progress/status_bar.png`。
- `tools/test_world3d_native_gltf.gd` 追加独立线程导出蒙皮/变形/动画，以及标准 glTF 场景图比对。
- 保存缓存、关闭/草稿恢复回归和全城逐顶点/贴图哈希比较仍沿用上述工具。

完整编辑器内的城镇副本实测：首次保存 63.26 秒，期间绘制 2486 帧（P95 48.96 ms）；重复保存 31.89 秒，期间绘制 1632 帧（P95 26.99 ms）。最大单帧分别约 434/502 ms，主要阶段仍持续刷新，不再整段等待导出才恢复界面；这并不代表完全消除短暂停顿。首次导出场景整理 45 ms，静态数组在主线程取得后移交工作线程，避免每个新网格从工作线程触发 GPU 回读等待。997 个网格、2964 个材质面、1120955 个三角形与原导出逐属性误差为 0，10 张贴图哈希相同，正式城镇 SHA-256 未变。证据：`save_progress/town.json`、`geometry.json` 和 `town_status_0.png/town_status_1.png`。

最终五项回归共 **201 个检查通过**（进度 38、缓存 32、恢复 78、原生 glTF 30、原子可靠性 23）；对应日志未发现引擎/脚本错误，`git diff --check` 通过，汇总为 `save_progress/regressions.json`。GPU 测试均在私有后台桌面执行，未切换或抢占用户桌面。
