# Direct native 材质纹理身份去重（2026-10-28）

此前完整材质公会加载中的 `asset_library.cache_materials` 观测约 93.9 ms。该区间包含场景遍历、属性读取、共享纹理替换和可能的渲染同步，不能把全部耗时归因于纹理身份检查。

当前 `ModelTextureCache.apply` 已对材质去重，并在同一次调用中对有效纹理只执行一次 `_remember`；但同一纹理被多个 storage 属性引用时，每次仍会重复 `_plain_texture` 和 `_valid_key`。新增 `model_texture_direct_seen.gd` 仅用于已由离线声明确认的可信、私有 direct-native 模板接收：第一次检查仍使用原语义，后续已确认有效的同一纹理对象复用结果，继续强持原纹理和共享纹理到原有同步完成；无效 key、附加 metadata 或 local-to-scene 纹理仍使用原规则。普通加载、白模和编辑器沿用原 `ModelTextureCache.apply`，direct 候选本身仍默认关闭。

原计划直接修改 `model_texture_cache.gd`；该文件却是 native `Compiled.generator()` 的输入，纯运行时调整也会让编辑器旧产品判为过期。因此实现放在新的 runtime helper，仅改 `AssetLibrary.cache_direct_native_scene` 调用。engine09 headless 实测改动前后 `Compiled.generator()` 均为 `0cd6d8fc8596bc17fdd204339652d1ee02dfe90f1005251fa76dd50ee9257f2a`，9 个生成器源输入 SHA 均一致。未来若离线纹理 stamp 或转换语义改变，仍需沿用既有生成器失效机制。

独立 GPU 功能夹具建立 2000 节点、120 材质，覆盖 base、surface/material override、overlay、next_pass、metadata 纹理、无效 key、未知纹理 metadata 和 local 纹理。原生产 `ModelTextureCache.apply` 与新生产 helper 的记录输出一致，设置目标纹理、排除对象、材质参数以及销毁后的弱引用均符合预期；日志无脚本/引擎错误。对相同图的独立插桩副本观察到：

| 本次 apply 工作量 | 旧算法 | seen-first |
| --- | ---: | ---: |
| `_plain_texture` 调用 | 720 | 361 |
| `_valid_key` 调用 | 480 | 121 |
| `_remember` 调用 | 1 | 1 |
| `material.set` 调用 | 360 | 360 |
| 渲染同步调用 | 1 | 1 |

以上次数来自插桩副本；生产函数的语义通过相同 fixture 对照，尚未直接给生产 helper 加计数器。额外观察 15,480 次 storage 属性读取中 12,600 项声明类型为非 Object、非 Variant；本轮没有改变这部分。插桩 wall time 不当作真实地图加载或帧耗时收益。

实际 Deferred source-free 双任务合同 **67/0**：direct 发布原 owner、无主线程/worker pack、ready 未接收取消、完整 lease 与回收、white/editor 隔离均继续成立。真实 staging 公会再做旧 cache_scene 与实际新 helper 的两实例对照，2319 节点、2276 资源的受检节点、材质 storage、纹理 key 和归一化 RID 共享拓扑、CPU 网格及碰撞面摘要一致；与上轮旧 direct 路径的两实例记录也相同。原 owner 和模板退出后弱引用消失，模拟完整 footprint 账目从 5,450,944,511 字节归零。该账目不是实际 RSS 或 VRAM，也不是完整地图资源驻留证明。

独立样本、生成器日志和局限见 `D:/code/rmmo_runtime/review_artifacts/model_texture_seen_20261028_01/PLAN.md`，新版生产 helper 测试位于其 `runtime_helper_01/`；真实公会样本位于 `D:/code/rmmo_runtime/review_artifacts/native_texture_seen_guild_20261028_01/sample_01/`。下一步需在相同完整材质地图、实际开关与普通引擎下累计测加载、帧耗时和工作量；不得用本夹具单次插桩时间或原 93.9 ms 宣称实际收益。

## 后续：跳过非纹理属性与重复持有

同一 direct-safe helper 进一步在 storage usage 检查之后，只读取声明类型为 `TYPE_OBJECT` 或 `TYPE_NIL` 的属性。`TYPE_NIL` 可能表示 Variant，保留其动态纹理值；metadata、next_pass、override/overlay 及未知纹理身份仍按原规则处理。该可信路径已排除脚本，原生材质属性类型受 ClassDB 合同约束。普通、白模、编辑器路径和生成器输入文件没有改变。

原 `retired` 数组每次替换都 append 同一原纹理，实际只用于判断是否需要同步。`seen[id]` 已强持 original/shared 到同步后，因此用 `changed` 布尔值代替该重复数组；同步位置与次数不变，随后释放 seen。

`model_texture_seen_20261028_01/property_filter_validation_01/` 保存 engine09 私有桌面红绿测试。相同最终夹具仅替换 helper：红臂唯一预期失败为实际旧 helper 未减少 get；绿臂 errors 为空。插桩实际 helper 副本的 storage get 从 **15480 降至 2880**（减少 12600）；原生产 Cache、新生产 helper、独立插桩的受检材质状态相同。实际新旧同步前原纹理弱引用均有效、同步恰好一次、调用后及场景销毁后原纹理均释放。实际 direct 模板合同回归 **67/0**，无脚本/引擎错误。

首次 parse 因测试中的弱引用变量类型推断失败，保留原日志，显式 `WeakRef` 后两臂 parse 通过。`identity.json` 是首次失败前的身份；最终两臂同一测试 SHA 为 `cf5bc0d8b41adb9dcd5eae16078ca6504cd739968e7ec06aa8ad5e1975f5ce31`，见 `identity.final.json`。后者是完成时核对，不能冒称运行前后完整树哈希。计数来自插桩源码副本，不把该样本 wall time 当作生产或真实地图收益；真实公会及累积整图复测单独记录。

真实 staging 公会已用相同 engine09 再验，`native_texture_seen_guild_20261028_01/property_filter_02/sample_01/` 的旧 cache_scene 与新版 helper 在两实例、材质 storage/纹理共享拓扑、CPU 网格和碰撞摘要及回收账目上相等（2319 节点、2276 资源），无脚本/引擎错误，已纳入的源码/引擎/fixture 身份前后相同。报告 SHA `60780f54ee3380f98bc4e6e9e2e89ffe0ff3c0432602d9fa3fe3e64f14da34b8`。隔离项目禁用无关 MockServer，作者 GLB 不存在，未改 staged 模型。

前一份 `property_filter_01/` 功能也通过且已与历史报告逐项相等，但 coordinator 用绝对路径排除 `review_artifacts`，误漏了外部隔离项目的源码快照；它保留为有限证据。第二份修为相对路径排除，记录 2796 项 GDScript 后重新测试。整图完成后，第二份也与历史报告逐项相等，见该 sample 内的 `compare_previous_compact.json`；回收完成帧数有波动，最终均释放，不作性能结论。产品复用既有 payload SHA 和本轮前后 size/mtime，没有声称再次全量哈希 281 MB。两者都只是所测字段合同，不是全部模型/像素或加载耗时验收。

累积整图 source-key ABBA 两侧都使用此新版 helper，见 [完整记录](axel_shader_module_share_20261028.md)。它确认该路径实际复用一次且功能/回收通过，但没有单独开关本次属性过滤，因此不把两臂的时间差归给此 helper。
