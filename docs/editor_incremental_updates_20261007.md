# 编辑器增删与增量保存

> 后续方案已由用户改为引用地图 v2，正常保存不再走本文旧内嵌增量流程。11 张旧地图已正式迁移；最终性能和验收见 [引用地图实施记录](reference_maps_20261007.md)。本文保留之前阶段的测量与排查证据。

用户在 Grok 初审及主代理复核后明确“那开始处理些问题”。本轮先处理普通模型增删、地形摆放的编辑器卡顿及保存资源增量；不修改正式 `medieval_river_town` 地图。原始反馈、静态分析与未完成总项见 `world_editor_todo.md`、`editor_issue_static_review_20261007.md`、`editor_save_slow_static_20261007.md`。

## 编辑操作

UI 与当前 3D HTTP MCP 共用按 UUID 的增量提交。普通物体、导入模型、新地形、自动瓦片、删除与相应撤销重做更新受影响节点；无关物体、列表行及城防渲染/碰撞批次保持身份。地形源变化才更新邻接；普通地面同格连续涂刷没有新记录时不提交。地面合批仅失效相关描述并继续分帧准备。元数据结构变化仍使用原有完整重建，不能宣称所有生成器均已改为局部更新。

地形属性面板绑定改变时复用原有控件，以无信号方式更新值；schema/材质选择范围变化时才重新建表单。此前每次绑定销毁重建河岸与坡度控件，是小图地形提交约 0.24 秒的主要成本。

私有桌面临时测试图（240 普通物体、6 地面及真实未烘焙城防）结果：

| 操作 | 修正表单之前 | 修正之后 |
| --- | ---: | ---: |
| 新增地形 | 238.240 ms | 14.050 ms |
| 撤销地形新增 | 242.756 ms | 7.215 ms |
| 重做地形新增 | 232.625 ms | 11.848 ms |

数字为该夹具的提交阶段，不是整城端到端时延或用户硬件帧率保证。普通单 UUID 提交约 2.84–7.84 ms。`test_editor_incremental_records.gd` 79 PASS；原有 `test_world3d_ground_batching.gd` / `test_editor_incremental_motion.gd` 回归退出 0。真实 HTTP 覆盖发现、合法增删、非法/锁定/隐藏拒绝、撤销重做、保存重开；实测射线拾取、无关节点/碰撞/批次/列表行身份及地形控件身份保留。

日志位于 `D:/code/rmmo_runtime/review_artifacts/`：`editor_incremental_records_final_20261007.log`、`editor_incremental_ground_regression_20261007.log`、`editor_incremental_motion_regression_20261007.log`。

## 保存实现与边界

`incremental_save.gd` 对可信基线按实例 UUID 对齐。新增已有相同资源实例复制节点树并共享网格/材质/图片；新增不同素材单独构建/导出片段并重映射 glTF 核心索引；删除脱离作者根、裁剪动画 channel，保留资源索引和已发布文件以免破坏共享引用及恢复版本。模型骨架、动画、路灯实例分组均保留独立身份。新源使用新加载场景，并只失效新增子集涉及的材质/门模型缓存，避免把旧预览像素绑定到新文件摘要。

所有成员变化先回主线程执行完整业务校验，再获取保存锁，复查基线、源文件和已发布资源并原子发布；失败不替换地图。UI 与同步文档保存共用实现，当前 3D MCP 参数/schema 不变。诊断通过 `timings.export.mode=incremental_reuse`、`added_instances`、`removed_instances`、`cloned_instances`、`exported_instances`、`images_written`、`texture_export_passes` 和 `partial_export` 验证，不能只看“保存成功”。

明确限制：特殊地形/道路/河道/岩岸/城防艺术件/自动瓦片等受世界坐标或邻接影响的增删，几何或材质修改、未知 glTF 扩展、跨实例骨架等仍拒绝复用并报告回退原因；首次/旧版本基线、生成器指纹或已有源内容变化仍完整重建。保留现有完整代码指纹及 SHA 校验，未给旧地图手工重签。JSON 仍完整序列化，删除后不自动压缩历史资源；总保存性能项保持开放。

## 本轮验证

- `test_world3d_pose_save_http.gd`：退出 0；建筑整栋位姿/楼层/登记/活动门窗、撤销重做重开、后台查询与忙时拒绝、失败重试均通过，日志 `pose_http_incremental_regression_20261007.log`。
- `test_world3d_pose_save.gd`：退出 0；原有位姿复用、资源字节不变、源变更像素、故障/晚到写入/失效基线保护回归通过。日志 `pose_save_incremental_regression_20261007.log`。
- `test_gltf_delta_graph.gd`：89 项基础检查 + 实际失败夹具只读验证共 90 PASS；覆盖核心引用、骨骼、动画、路灯分组、源缓存、原生 `GODOT_single_root` 声明和 JSON 数字往返。删除子树的名称换成唯一内部名，兼容旧孤儿后撤销/重做，避免 Godot 导入时重命名活动实例。
- `test_incremental_save_plan.gd`：6 PASS；整数作者数据与 JSON 浮点数共用模板、独立复制组资源复用、混合位姿与成员变动、非法位姿拒绝、删除最后实例省略空 children。
- `test_world3d_incremental_save_http.gd`：145 PASS，退出 0；实际 HTTP 发现、非法调用无副作用、已有模型复制 0 图片/0 导出、不同 GLB 仅新增 2 网格/1 图片、删除/同数量换 UUID、撤销重做/原生重开、后续位姿复用、两个故障注入、晚到外部写入与源贴图改蓝验证。日志 `incremental_http_final_20261007.log` / `incremental_http_final_engine_20261007.log`。
- 首几轮集成失败均修复后重跑：原生 `GODOT_single_root` 声明缺少支持、JSON `[0.0]` 与整型数组比较误拒绝、删除孤儿同名影响原生导入。未移除断言规避失败。
- `profile_editor_incremental_save.gd`：已完成下面整城临时验证，退出 0。
- `test_incremental_save_fallback.gd`：48 PASS，退出 0；增量规划拒绝、基线 JSON 字节变动、已发布依赖变动三种全量回退，均先真实预热绿色新模型缓存，再修改磁盘为蓝色，确认导出蓝色并保留原模型红色。所有源集合变化的完整回退均刷新资源；成功增量只清新增子集。

列表专项 `test_object_list_incremental.gd` 另 9 PASS；完整编辑提交说明见 `editor_incremental_records_20261007.md`。

地图加载、游戏三个坐标卡顿、角度输入实时预览和花坛行走/跳越未列为本轮已完成。

## 当前城镇实测

读取 `D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf` 的 4437 条记录，向 `D:/code/rmmo_runtime/cache/world3d/town_incremental_save_10411421/map.gltf` 保存；没有复制/覆盖正式地图目录。真实 HTTP 启动后台保存并等待完成，最终全部作者记录和建筑登记重开一致。正式源 SHA256 前后均为 `8c9248b1f5fa9bbe51d09bbcce39826a50d386e7e23a82e5afbca29d4fa6631d`。

| 操作 | 总耗时 | 模式 | 图片导出 | 新导出实例 |
| --- | ---: | --- | ---: | ---: |
| 首次建立可信基线 | 564.707 s | full_export | 236 | 全部 |
| 移动一个普通模型 | 41.810 s | pose_reuse | 0 | 0 |
| 复制一个普通模型 | 48.486 s | incremental_reuse | 0 | 0（克隆 1） |
| 删除该复制件 | 39.153 s | incremental_reuse | 0 | 0 |

完整基线含 6189 网格、1127 材质；构建 117.408 s，发布 435.693 s，其中导出 write_ms=382.321 s 包含几何、图片与 JSON，不将全部归因于贴图。三次后续保存保留 236 图片及 2 个 buffer，没有执行纹理导出。相比同次完整导出，所测三个操作减少约 91–93% 总时长；这不是当前修改与旧版本等条件的全量 A/B。

约 39–49 秒仍不能视作即时保存。复制例中，源/基线/依赖探测与协调共 26.305 s，主线程业务校验 5.804 s，发布 16.275 s（序列化 4.390 s、最终校验 9.883 s）；建新导出视图仅 36 ms，实际导出实例 0。未来优先减少大 JSON 与重复扫描/强校验成本，并收窄可靠的生成依赖指纹。当前**未削弱校验、未重签旧基线**，升级后的首次保存及特殊几何修改仍可能完整重建，保存性能总项保持最高优先级未关闭。

原始报告 `D:/code/rmmo_runtime/review_artifacts/editor_incremental_save_town_20261007.json`；日志 `editor_incremental_save_town_20261007.log` / `editor_incremental_save_town_live_20261007.log`。整城测试使用私有桌面，未抢用户焦点。

只读最终复查另外发现原有全量导出路径中，生成 manifest 时的源变动仅跳过清单、没有中止发布；本轮增量路径会拒绝这种冲突。该原有完整导出一致性缺口另留待修，不能以增量路径的故障测试声称所有全量并发源变化均已覆盖。

## 用户追加：从库新增模型补测

用户明确要求还要测添加模型。此前整城的“复制一个模型”不能替代首次从素材库新增；HTTP 145 项的小图新增 GLB 也不能替代当前城镇规模验收。现补测默认素材库中、当前地图没有引用的真实“方窗石砌窗套”（约 14.6 MB、1 网格、1 材质、3 图片、1296 三角），使用临时地图，通过真实 `list_assets` / `place_asset` 测首次加载、摆放、增量保存、原生重开及撤销重做。结果待实际运行填写。
