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
