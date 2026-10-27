# 内部快照读取与需求缓存复用（2026-10-27）

接续 `axel_requeue_membership_delta_20261027.md`。旧候选在独立压测能避免重复扫描，但实际隔离地图的 157 次 accepted requeue 全部因 `dirty=false` 退出快路径。其余 guard 均通过；12 个早期物化栈不能代表每次 requeue 前的直接调用者。完整诊断及地图数据保留在前述文档，不把这项工作扩写成初始加载或全部材质优化完成。

## 修复

- `DeferredAssetLoader` 区分内部生成的 pending Array 与经公开 getter/setter 借出的可变 Array。只有从 authoritative 目录物化或 publication 分离出的新数组可带 private 标记；公开借用撤销该标记。
- 内部读取调用原有物化函数，不再经公开 getter。物化仍是同一数组与顺序，索引重建/关闭仍先物化再释放目录；碰撞快照身份及失效步骤保留。
- 把「是否跳过 Array append」与「是否保留未受影响的 typed membership」分开。dirty 路径继续延迟物化；clean-private 路径正常 append、增量登记，再按既有策略、登记代际、边界和 owner 条件保留无关 membership。公开可变借用仍回退清理。
- 仍推进 demand revision，并重新计算排序、实时 published/support、碰撞状态和重试。没有复用旧排序或扩大任务容量。正常边界变更须走登记/重新入队；任意篡改私有索引或旧 item 字典不是新增支持合同。
- 采样器使用计数接口，不再为 `size`/`filter` 借出整个 Array；非 canonical 或公开可变数组仍按原逐数组谓词计数，重复 UUID 不被偷偷去重。可见性 probe 的 `any` 保留早停，只改为内部读取。

## 先复现，再回归

`tools/test_clean_private_membership.gd` 原实现红测 **61 通过、1 失败**，唯一失败是内部物化后无关 typed membership 被全部清除；前置条件通过、没有脚本/引擎错误。保存于 `D:/code/rmmo_runtime/review_artifacts/clean_private_snapshot_red_20261027_01/`，红测 loader SHA 为 `a3ac8414bd7c4cb63fad4fe792a0794dab7a1a4f0b7b328bf2877545195465b0`。

增加 observer 语义断言后，候选 **68/0**。原 requeue 测试 **155/0**，其余 9 项调度回归 **667/0**，共 **890 项**：返回刷新、membership/live membership、support promotion/ID、terrain return、retirement scan、requeue compaction、candidate catalogue。所有进程退出，stderr 空，源码/引擎身份前后不变。记录位于 `D:/code/rmmo_runtime/review_artifacts/clean_private_snapshot_green_20261027_01/`；初版批处理因某测试没有 `passed=` 汇总而停止，日志保留，改用其实际 PASS/failures 输出统计后继续，未把缺失字段当通过。

game_pipeline、white_streaming、region_loading 的 check-only 通过；region 父级 probe 修正后再次通过，记录在 `D:/code/rmmo_runtime/review_artifacts/clean_private_region_parse_20261027_01/`。Python 隔离 runner/诊断/开关回归 **23 项通过**。这些不替代真实 GPU 路线；后续同源码 A/B/B/A 结果与失败慢帧统一追加在 `axel_requeue_membership_delta_20261027.md`。

## 任务边界

本项解决实际缓存复用未触发，不能从初始 full-ready 的四个数推断初始加载因果收益，尤其缓存命中发生在初始完整就绪之后时。当前地图/预制件纹理路线仍不等于导入模型完整材质或真实玩家体验。目标保持进行中：完整材质关键路径优化后，继续适配和优化内容编辑器与当前 3D MCP，保留导入、撤销、保存重开和派生资源更新语义。

后续完整材质 reader 的生产精简、编辑器回归、真实产品 GPU 对照与 A/B/B/A 微测见 `axel_trusted_native_material_reader_20261027.md`；其中仍明确保留完整材质游戏入口尚有 GLB 依赖的边界。
