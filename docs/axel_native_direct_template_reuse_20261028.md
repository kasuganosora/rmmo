# Full native 原模板直接复用候选（2026-10-28）

本切片默认关闭，处理游戏可信 full fixed-native 结果的主线程重复 pack；不改变白模、编辑器或普通 fallback 的加载策略。此前完整材质追踪的公会返回阶段，`asset_library.cache_pack` 曾为 91.609 ms，但该 wall time 嵌套于其他任务，不能把它直接当作帧时间收益。后台 worker-prepack 曾出现一次完整地图 `0xC0000374`，独立 cold pack 压测有一次 `0xC0000005`，目前两者均无栈、未证实共同原因；该旧候选仍默认关闭。

## 完整地图对照结果

`D:/code/rmmo_runtime/review_artifacts/full_direct_abba_20261028_01/` 在 engine09、同一公会声明变体、同一私有 user 目录下完成关闭/开启/开启/关闭四次完整路线。全程真实模型材质及地图纹理开启，worker-prepack 关闭；没有 GDB、原生诊断、monitor 或详细 texture profile。四条功能、输入身份、跨臂 fixture 身份及结束回收检查均通过。文件审计会预热 OS 缓存，私有 shader/index 缓存复用，不能称作物理冷盘。

| 样本 | 入口 / 完整就绪 s | 卸载 max ms / >50 | 返回 max ms / >50 | 重载 max ms / >50 | 返回 / 重载 1% low FPS | 复用计数 |
| --- | --- | --- | --- | --- | --- | ---: |
| A1 关闭 | 11.065 / 37.177 | 26.713 / 0 | 54.392 / 3 | 192.936 / 2 | 34.498 / 22.577 | 0 |
| B1 开启 | 10.082 / 20.809 | 38.681 / 0 | 83.976 / 6 | 102.959 / 1 | 30.506 / 24.345 | 1 |
| B2 开启 | 10.629 / 21.157 | 50.962 / 1 | 49.576 / 0 | 136.942 / 6 | 34.861 / 22.569 | 1 |
| A2 关闭 | 10.382 / 21.075 | 36.172 / 0 | 48.517 / 0 | 188.189 / 5 | 36.805 / 22.893 | 0 |

四条均保留，没有丢弃 A1 的慢加载。`host.jsonl` 的 78/73/72/72 条臂内采样中，38/28/39/26 条观察到其他 Blender 或 Godot 进程；系统 CPU 采样最大值为 45.5/47.8/44.1/39.5%。采样不覆盖所有硬件和逐帧情况，不能把具体尖峰直接归因于外部程序，也不能据此把 37.177 秒解释掉。这组没有证明稳定的总加载或 low 改善，四样本不是 p95；重载 max 的方向也不足以单独确定因果收益。

定期 `queues[].deferred.profile` 的累计最大值：模型/compiled hits 为 51/56/54/57，实例为 3173/3186/3186/3202，compiled misses 与 worker-prepacked 均为 0；两条 B 的原模板复用各为 1。它们是单队列计数的采样最大值，不是全程所有工作量之和。正常样本不直接记录 pack 调用；公会走到省略 `_own/pack` 的分支由复用计数、代码路径及独立红绿合同共同证明。不能把路线模型数量差异包装成完全固定工作量。

本轮保留的是合同与实际整图路径证据。候选继续默认关闭，正式产品 metadata 尚未转换；仍需处理材质首次提交，并在安静条件补测再决定默认策略。游戏材质优化完成后，内容编辑器和当前 3D MCP 的适配/优化是用户要求的后续任务，尚未完成；不能因游戏样本通过就视作编辑器验收完成。

## 差异证据与边界

私有合成矩阵比较旧 `cache_scene` 与直接复用 native owner：24 种 local mesh/material/texture 与草地组合中 17 种有观察差异，包括草地动态 override、local mesh 的 CPU cache、部分 local material 的纹理共享；详见 `D:/code/rmmo_runtime/review_artifacts/native_direct_reuse_study_20261028_01/PLAN.md`。首轮因为测试脚本 `get_meta` 缺 key 报错失败，保留日志；修正后才得到可用的 24 组结果。

对真实 staging 公会模型的独立功能对照，先使用真实 fixed-native 准备再比较两个发布方法：2319 节点、2276 资源；观察到 local-to-scene 资源、grass 节点、脚本资源、实例化子场景均为 0，资源扫描未截断。两实例的受检节点、材质属性和 texture key、归一化对象/RID 共享拓扑、CPU 网格与碰撞面摘要相同；每实例各 2151 mesh、2245 surfaces。引入一张已驻留相同纹理，观察到两臂传播结果一致；旧、新模板及原 owner 均回收。原 SCN 只核对前后 stat，复用 fixture 构建时的 SHA，未声称在此样本再次全量哈希。完整证据和范围见 `D:/code/rmmo_runtime/review_artifacts/native_direct_guild_20261028_01/PLAN.md`。

这些对照只覆盖合成矩阵及公会一个 staged 产品的所测字段，没有对全部 native 产品、完整地图画面或真实地图工作量做结论；不能把同字段结果推广成所有模型语义一致。

## 实现

- 离线 `CompiledAssetFootprint.measure` 在既有资源 walk 中记录保守的 `direct_template_reuse` 声明，版本 1。任何 local-to-scene 资源、脚本或 grass 节点均不标记可直接复用；既有 native 产品类型约束仍生效。声明放在绑定 source/payload/index 身份的 footprint 中；缺失、未知版本或类型不符均回退旧方法。没有在运行时做全树扫描或打开 GLB。
- `refresh_direct_template_reuse` 是显式离线操作：仅需要逻辑 asset key、已有 index/footprint 与 SCN，校验并保留其绑定和 model metadata 后更新声明，不需要作者源 GLB，也不改 SCN。它只在明确调用时执行完整资源 walk 和离线 payload SHA，游戏运行时不执行。
- `Deferred.full_native_template_reuse_enabled` 默认 false；派发时在 trusted + full + require-native + fixed-native 且声明 safe、`white_materials` 关闭的条件下冻结直接复用决定。即使两个实验开关同时打开，direct 开关也阻止旧 worker-prepack；unsafe 或缺声明走原主线程 `cache_scene`。主线程按既有顺序做模型纹理 intern 和私有 scene 安全销毁，再发布原 native owner，保留 job 的完整原有 lease 至结果回收；不自行缩小预算。
- profile 使用 `full_native_reused_templates` 计数。`--full-native-template-reuse` 为单独 full 测试参数，与 worker-prepack 参数互斥；正常产品默认仍关闭。

## 合同测试

`D:/code/rmmo_runtime/review_artifacts/direct_native_template_tests_20261028_01/` 保留 engine09 测试。首次新测试 parse 在 `parse_direct_02.log` 因 weakref 类型推断警告失败；改为显式类型后 `parse_direct_03.log` 通过，probe parse 也通过。私有 GPU 初版 `direct_gpu_01.log` **66/0**；静态复查发现单独启用 `white_materials` 而没有 `native_geometry_only` 时仍可能命中 direct，新增真实派发用例后 `white_material_red_01.log` **66/1**（唯一失败为该组合），修复 gate 后 `white_material_green_01.log` **67/0**。这些功能样本无非预期脚本/引擎错误；`probe_gpu_01.log` **36 PASS、0 failures**。测试包括：

- 两个真实临时 full native 产品先删 GLB，再实际派发两条 Deferred job；开关关闭时主线程 pack 两次，开启时主线程和 worker pack 均为 0，发布的对象就是原 fixed-native owner。两个开关同时开启也不执行 worker-prepack，派发后的标志变化不改变已入队决定。
- safe、local mesh/material/texture、grass、脚本负例；缺标记、未知版本和不合法值回退；离线 refresh 在作者 GLB 已删除后工作并保留 model metadata、source/payload 绑定及 SCN 字节。
- ready、尚未 accept 时通过真实 `_poll_jobs` 取消，scene 和 native owner 的弱引用消失、完整 ledger 归零；双 job 最终 ledger 归零。单独 white materials、native geometry 白模以及编辑器标志为 true 时的派发检查不启用这两个 full-native 候选；真实资源缺源的纹理种子 intern 在两个实例共享同一 RID。

测试的额度是项目的保守工作量估计，不是实际 RSS/VRAM 测量。候选未默认开启；正式产品没有为此修改。测试 staging 的公会 descriptor 已在 fixture lock 下发布新声明，同步发布新的固定名 manifest，旧 manifest 和 descriptor 的完整字节及 SHA 均保存在 `D:/code/rmmo_runtime/review_artifacts/native_direct_guild_migration_20261028_01/proposal_01/`。新 manifest SHA `b350e4ded3c3666d4768f7695337fdbb0fc5147423d278a02c94d936a4ff6fbb`；前后 full fixture audit 均通过。proposal 首两次因直接比较 JSON float 与运行时 int 的字典而错误拒绝，逐字段比较无数值差异后修正判定，均保留日志；第 3 次新版离线 walk 成功且全部 stats 逐键数值不变。新旧 manifest 除公会 descriptor SHA 和新增变体来源外相同。此变体仅为独立整图对照；尚需验证实际完整材质地图的加载、卸载、返回帧和工作量，才能评估收益与默认策略。编辑器性能适配仍是后续工作。
