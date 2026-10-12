# 引用地图 v2 与旧地图迁移

2026-10-07 用户明确采用引用方案：预制件独立存放，地图保存摆放信息；通用 glTF 工具显示定位方块，游戏和内容编辑器还原完整画面。随后明确要求已有地图一起转换，避免长期维护两套正常格式。此要求覆盖本轮此前“正式地图暂不迁移”的安排。

## 格式与共享业务

- 标准入口仍为 `map.gltf`，根节点 extras 为 `rmmo_format=rmmo_gltf_map`、`rmmo_version=2`、`rmmo_storage=references_v1`。
- `rmmo_records` 每条仅含 `uuid`、`position`、`rotation`、`size`、`rmmo_ref`、`rmmo_state`。定位方块共用一个嵌入式立方体网格与材质；不包含真实场景网格、贴图导出或模型副本。
- `rmmo_ref` 使用相邻 `map.gltf.resources/<SHA256>.rmres`。资源为 `RMMORES1` 封装的 ZSTD 压缩无对象 Variant 作者定义。原 GLB/材质资源仍引用资源包文件；生成的冻结预制件保留原始 CPU 几何、碰撞及刷面定义，不损失编辑语义。
- `rmmo_state` 独立保存 building、fortification、fixture、event 以及编辑器分组/名字/隐藏/锁定字段。建筑整体升降涉及的 `floor_y`、复制后的建筑 ID、开关门窗及隐藏锁定不重写几何资源。其它作者字段保留在资源定义，真实几何/材料定义修改才产生新的不可变资源。
- 同一地图的相同定义自动共享。每次加载还原独立可编辑记录；共享存储不等于共享可变编辑对象。楼层、屋顶、活动门窗、独立身份、碰撞和撤销保留原业务行为。

`WorldDocument.save`、UI 与当前 3D MCP `save_world` 统一调用 `reference_map_save.gd`。保存只做业务校验、资源写入/复用、轻量地图 JSON 与原子发布，不构造整个导出场景，不读取 GPU 纹理，也不调用整图 glTF 材质贴图导出。通用完整 glTF 导出工具的历史代码保留，但不再是正常地图保存路径。

`document_open_cursor.gd` 后台恢复并核验引用，随后沿用原分帧业务校验；`map_loader.gd` 使用相同解析入口恢复真正的游戏几何。旧 metadata 缓存暂不作为权威输入，运行时派生几何缓存仍在引用核验后使用。旧 v1 只允许显式迁移入口；普通打开旧原生地图会提示需要迁移，不静默进入旧读写路径。未声明 RMMO 的普通模型 glTF 导入不受影响。

## 发布、恢复和安全约束

资源只创建、不覆盖。先批量写临时资源，再以无覆盖移动发布，最后原子替换小地图；起点和发布前验证地图版本，发布前完整核对资源 SHA。`.previous` 保留原生恢复点，旧图第一次转换后仍能恢复；恢复旧 v1 时也重新发布为 v2，不重新引入正常旧格式。缺失/损坏/越界资源、并发地图改写、非法记录和写入故障均拒绝发布。

严格限制资源 URI 为同名相邻目录和完整 SHA 文件名，检查路径祖先和文件链接。批量操作复用本次调用内的目录检查，操作结束再核验祖先与叶子，不以 mtime 或缓存代替磁盘完整 SHA。资源定义不允许 Object、Callable、RID 或循环结构；实例状态和地图元数据仅允许可无损保存的 JSON 值。

不删除旧资源、旧 `.versions` 或恢复依赖，不额外复制整份正式地图目录。地图列表排除 `.versions`、`.resources` 和 `.save-lock`，不会把迁移前的保存代次列为可用旧地图。

## 迁移和验收

迁移入口 `tools/migrate_reference_maps.gd`：缺省仅写临时验证地图，校对完整记录/元数据、保存重开、位置变化不写资源，以及正式源 SHA 不变。`--apply --validated=<验证报告>` 只处理已通过的源版本，源在验证后改变则拒绝。正式替换保留 `.previous`；测试目录与正式目录分开。

2026-10-07 首轮临时验证：9 张正式地图及 `p4_yard/p4_inn` 两张默认游戏地图，共 11 张通过，失败数 0。城镇 4,437 条记录，地图入口由 169,932,135 字节减为 4,689,617 字节；独立资源实际写入 96,962,670 字节（这些是必要的外部资源，并非总资源体积消失）。该次是在路径批处理优化前测量，不作最终耗时结论。

测试入口与证据：

- `tools/test_map_resource_store.gd`：66 PASS，覆盖独立定义、实例状态、损坏/越界、并发无覆盖与 junction。文件 symlink 夹具因本机 Windows 权限跳过，代码保留该检查。
- `tools/test_reference_map_save.gd`：30 PASS，包含标准 glTF 代理解析、增删/位姿复用、冲突、故障、完整性及 JSON 元数据拒绝。
- `tools/test_reference_map_loading.gd`：32 PASS，包含旧版正常拒绝/显式迁移、后台/同步等价、楼层/屋顶/铰链/碰撞、缓存绕过防护及最终完整性。
- `tools/test_reference_map_recovery.gd`：14 PASS，包含 v2 恢复、旧迁移检查点恢复为 v2、损坏拒绝、缺失主文件恢复、地图目录过滤。
- `tools/test_reference_map_http.gd`：后台桌面实际 HTTP、GPU、编辑器及游戏加载回归，失败数 0。真实石砌窗套 GLB 添加/删除、整栋 XYZ 移动、全体隐藏锁定、撤销重做、刷面/门窗/楼层、外部并发保存冲突和保存重开通过；外部 glTF 为方块，游戏恢复真实模型/材质/纹理/碰撞。
- `tools/profile_reference_map_town.gd`：整城真实 HTTP 计时及游戏加载验收，结果见 `D:/code/rmmo_runtime/review_artifacts/reference_map_town_20261007.json`；正式发布结果见 `reference_map_migration_applied_20261007.json`。最终结果见下节。

所有 GPU 测试用 `tools/run_godot_background.py` 的独立桌面执行，没有前台窗口或抢焦点。本轮格式转换不等于关闭游戏三处卡顿、角度实时预览、花坛通行或所有地图加载性能问题。


## 最终整城结果与正式发布

2026-10-07 独立桌面真实 HTTP 验收，4,437 个原始物件；实际新增共享库中的「方窗石砌窗套」GLB，原有模型及素材库 SHA 不变。各阶段无整图材质/贴图导出。

| 临时城镇操作 | 保存耗时 | 新写定义资源 | 图片导出 |
|---|---:|---:|---:|
| 首次转为引用地图 | 31.553 s | 1,762 | 0 |
| 移动已有模型 | 9.645 s | 0 | 0 |
| 添加此前未使用的真实模型 | 9.675 s | 1 | 0 |
| 撤销添加 | 9.873 s | 0 | 0 |
| 重做添加 | 9.437 s | 0 | 0 |
| 删除模型 | 11.655 s | 0 | 0 |
| 撤销删除 | 9.171 s | 0 | 0 |

临时引用城镇的完整作者文档重开 5.486 s；游戏 MapLoader 加载 58.213 s，恢复 6,190 个真实流式几何条目，新增模型材质/贴图/碰撞/独立身份核对通过。此游戏计时是本次引用图运行时加载，不与此前通用 glTF 导入的 108.768 s 混作严格同入口对比；编辑器首次视图构建仍约 76.905 s，不能宣称整个加载流程已经秒开。单次普通保存仍包含约 4 s 业务校验和 2.7–4.6 s 资源定义编码，后续可继续优化，最高优先级性能总项保持开放。

正式迁移全部完成，11/11 通过保存重开后的完整记录与元数据比较。包含以下 9 张正式地图，以及默认游戏地图 `p4_yard`、`p4_inn`：

| 正式地图 | 记录数 | v2 地图入口字节数 |
|---|---:|---:|
| medieval_river_town | 4,437 | 4,689,617 |
| medieval_house_showcase | 6,626 | 7,328,327 |
| medieval_house_showcase_v8 | 577 | 703,141 |
| river_bank_lab | 13 | 12,267 |
| town_props_showcase_20261006 | 31 | 24,307 |
| default/editor_yard | 2 | 3,287 |
| default/medieval_building_gallery | 5,452 | 6,419,514 |
| default/medieval_material_house | 634 | 714,371 |
| default/medieval_timber_house | 606 | 670,647 |

正式城镇首次迁移保存 27.351 s。发布后独立 Python 完整复核 11 个地图 SHA、11 个 `.previous` 原文件 SHA、v2 标识、完整记录数量及 5,389 个资源引用 SHA，全部通过。恢复点沿用原生 `.previous`，没有新建整目录备份；不处理历史测试夹具和 `.versions` 内的旧代次。

额外修复共用 `WorldDocument.authoritative_extras` 的返回合同：默认恢复完整引用记录，避免已有布景工具拿到 compact 后操作；天气读取显式选择 metadata-only，省去不需要的几何恢复。恢复流程对声明 RMMO 却头部非法的检查点直接拒绝，不能通过通用 glTF 分支绕过校验。以上通过专用 CPU 回归。

历史测试适用范围：`test_world3d_pose_save*`、`test_world3d_incremental_save_http`、`test_incremental_save_fallback` 等只验证旧内嵌导出算法，不能再作为正常保存合同的验收。部分早期材质测试仍用 `Doc.save → Io.load_scene` 期待真实画面，后续维护应切换到 MapLoader/作者视图；不为这些历史断言恢复旧正常格式。上述新格式专项测试均实际执行通过，不声称所有历史工具测试已更新或全量通过。

正在运行的旧编辑器/游戏进程需重新启动以加载新代码；原地图文件名和目录入口保持不变。
