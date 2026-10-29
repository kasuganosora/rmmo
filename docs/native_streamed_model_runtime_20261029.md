# 原生几何与独立流式纹理：运行时接入记录

本轮延续 `c20419a9` 的离线产品，工作区为 `D:/code/rmmo`。正式资源尚未批量转换，`Compiled.build(..., split_textures=false)` 的默认值仍保留；编辑器异步加载和流式资源生命周期尚有未完成项。以下是候选管线和独立夹具的结果，不能当成 axel_town 的加载、1% low 或实际 RSS/VRAM 收益。

外部证据根目录：`D:/code/rmmo_runtime/review_artifacts/godot_4_8_adoption_20261029_01`，下文简称 B。资源、GPU 输出和冻结工程都在该目录，不写回项目触发导入。用户原有 12 个 WIP 文件单独保留。

## 加载与所有权

初始加载不再先读完全部模型纹理表再启动几何。`initial_native_texture_jobs.gd` 将几何、唯一纹理表、像素产品准备和实际材质绑定组织为可独立就绪的任务，共用既有准入账本。root + table SHA 相同只读取一张表；慢表暂停时，其余模型仍能完成准备和绑定。已完成几何等待纹理时不占用生产 worker 槽。

`initial_native_texture_scope.gd` 持有结果、共享池及其消费者，直到主线程完成接收或取消清退。`MapLoader` 保留该 owner。Deferred 路径以 `deferred_native_texture_scope.gd` 保留 metadata pin，以 `deferred_native_texture_binding.gd` 绑定实际私有场景材质，包括 local-to-scene 材质，而不是只改原始 PackedScene 中另一份材质。

`TexturePlanCatalog` 的 metadata 缓存按字节管理，活跃消费者保留其 pin。表完成后从普通任务条目移为单独的容量扣除，避免持久 metadata 条目堵住其模型自己的 exclusive 几何/像素任务。取消、reset、detach 时，借出的计划继续有效至最后消费者释放。生产 JSON reader 不再为确认标量而重走整张表；注入式测试 reader 仍检查所有权合同。

拆分 native 的 continuation 不回读 GLB，不额外深拷贝整张纹理表后又覆盖，也不再为完全不存在的内嵌 ImageTexture 扫描预留 12 MiB。普通内嵌产品保留原路线。GLB 仅用于显式离线内容导入；角色旧导入等遗留路径仍须独立改造，不能因本候选通过便称整个工程已经不读 GLB。

## 就绪、预算与材质消费者

- `model_texture_readiness.gd` 只读取根节点的表身份。读取新的 native 文件时清除资源级完成标记，完成实际绑定后才建立运行时完成证明；实例化和重打包传递该证明。缓存拒绝未绑定或表身份不同的场景。修复了 AssetLibrary 首次实例与后续直接实例化的完成状态不一致。
- `SharedPrefabImages.handoff_streamed` 在消费者仍活跃、输出 owner 匹配、纹理确实登记到引擎后，将 native 的保守完整链预算移交给引擎驻留账本。操作先完整检查再更新，可重入且幂等。混合 native 与普通 Image 的任务只移交 native 子集，普通图片预算继续保留。
- `AssetWorkerDrainer` 合并结果包、continuation、token 中同一 scope 的释放，先释放别名，最后清退 scope 一次。
- 草材质保留原生 StreamedTexture2D owner；不调用其 `get_image()` 做旧像素缓存键，不替换成 ImageTexture。同 owner 的重复材质 setter 从 10 次降到 0 次。这里的 `get_image()` 在 04d 会重新读取完整文件，并不是只读取当前驻留低 mip。
- 非零纹理拆分产品在入口要求 `StreamedTexture2D.is_streaming_active`。04d 缺少该能力时，在创建 worker、metadata pin 之前明确失败；零纹理表及显式 CPU 测试注入不受影响。

## 引擎 candidate05

默认安装仍为 4.8 candidate04d。本轮 candidate05 只在外部隔离目录运行，没有覆盖 `D:/tools/godot`。版本字符串相同，不能用它区分构建：

|构建|EXE SHA-256|
|---|---|
|默认 04d|`b15441fd50cfcec8072150d8025770952339d86faa91e95b09d0a7d6a193621e`|
|候选 05|`435e90ff0742476f881c7d14385b242314f1662879fd18ec8c5a3807b980650a`|

实际 RD 布局复现了旧引擎账本错误：256² RGBA、只有基级的纹理占 262,144 bytes 却记为 4 bytes；两级文件在最后一级占 65,536 bytes 也记为 4 bytes。candidate05 使用文件真实 mip 数和初始驻留层，缓存实际各层尾部成本，限制目标层到文件现存范围。该夹具由 12 项中 2 项失败变为 12/12；不宣称所有任意截断 mip 链都已受支持。

I/O 回调改为返回实际完成层。只有成功替换纹理才更新当前层和预算；读取失败保留原驻留层，删除同一次失败后重复全量重读。缺文件再恢复夹具 13/13，包含 3 条预期缺文件诊断；旧 04d 同一夹具有 2 项失败、6 条诊断，并错误把尚未更新的纹理记为较大驻留量。

无相机、无 3D 场景的加载盖板仍通过全局帧回调推进 streaming 反馈。5/5 夹具中预算自然登记并最终归零，因此没有添加额外生产强制 flush。

累计补丁与清单为 `tools/engine_patches/godot-4.8-beta1-runtime-candidate05.patch/.json`。它替代 04d 补丁，应用到官方原始 4.8 beta1，不能叠加。使用 `git -c core.autocrlf=false apply` 后，47/47 文件与实际编译源码逐字节一致；默认 autocrlf 的首次重放失败仍保留在 B。构建及符号 SHA、源码来源和逐文件 SHA 均在清单中。

## 已完成的独立验证

|范围|结果与证据|
|---|---|
|初始乱序依赖|最终 CPU 基础 78 项；慢 metadata 21 项旧源 6 FAIL → 新源全通过。`initial_native_metadata_red_01`、`initial_native_metadata_green_02`|
|Deferred 与 direct 空计划|最终 64 项；旧源 2 FAIL → 新源全通过。`native_split_empty_scan_red_01`、`native_join_capability_cpu_01`|
|既有准入与乱序|493 + 32 + 26 项通过；`native_join_final_cpu_01`|
|04d 提前能力门禁|7 项通过，零 worker/零 metadata pin；`native_join_capability_cpu_01`|
|初始实际 GPU DAG|18/18，metadata 29,388 → 0，实际引擎账本 152,915 → 0，21,623 个非背景像素，源/候选 RGBA 零差；`initial_native_join_gpu_05`|
|Deferred 实际 GPU|19/19，2 模型/1 表/2 STEX/1 PNG，native 保守 699,046 bytes 移交，普通图片 624 bytes 保留，最终引擎账本归零、RGBA 零差；`deferred_native_join_gpu_02`|
|混合共享池移交 GPU|52/52，零诊断，最后释放归零；`streamed_budget_handoff_01/handoff_candidate05_02`。此前 `_01` 有测试计划缺 cache_limit 的脚本错误，保留为失败|
|共同 CPU 快照|导出 87、绑定 53、就绪 19、native catalog 48、普通 header 24、预算移交 52、05 能力 3、草 21，全部通过且零诊断；`native_integration_freeze_01/cpu_results.json`|

上述 GPU 初始/Deferred 样本早于最后的入口门禁、空扫描收束及跨阶段弱登记改动；最终源码共同 GPU 复验另记，不能用这些较早样本替代。

## 跨阶段共享与重复工作收束

实际复现：初始加载绑定的 STEX 被材质和缓存场景持有，但未登记到 Paint 的弱目录。后续新模型即便使用同表、同产品，Deferred 的新共享池也会再读并创建两张 STEX。新增 `NativeTextureSharing` 只在主线程、成功批次/场景发布后登记现有 owner，保持弱引用；取消或失败批次不登记，不读回、不哈希文件，也不加入强驻留缓存。关闭旧 Paint budget 时，native ticket 仍允许从弱目录查找，普通纹理行为保留。

真实 GPU 交叉阶段夹具为初始准备 → 缓存 → 释放 initial scope → 新 Deferred 几何 → 新场景缓存 → 移除第一份缓存 → 释放全部。旧源 17 项中 4 FAIL，新源 **17/17**：第二池 `produced/streamed_loads` 从各 2 降为 0，复用同一 Texture 实例和 RID；第一份 owner 移除后第二模型仍有 21,623 个非背景像素、RGBA 零差，最后引擎账本 152,915 → 0，全部观察 owner 死亡。证据 `native_cross_operation_gpu_red_01` / `native_cross_operation_gpu_green_01`。CPU 跨阶段 16 项、direct fallback 扫描 3 项均通过。

共享弱目录原来超过 1,024 项便逐次全扫，超过 4,096 项无条件淘汰活标识。现在每次最多检查 8 个引用，在迭代结束后移除已死亡项并轮转活项，不复制全部 keys、不增加强 owner、不保留会被外部 clear 弄失效的游标。两个类别各 4,352 个活对象的夹具中，旧源丢失 256 个身份，随后的 512 次查询连续重复创建 512 个对象；新源丢失与重复创建均为 0。登记约 3.5–3.7s → 52ms，仅为单对 CPU fixture 数据；不能作为整城收益。旧源一次清理 8,192 个死亡条目，新源一次最多 8 个，后续可全部清理。专用 26/26、既有材质缓存 5,780/5,780，零诊断，见 `surface_weak_catalog_01/delivery.json`。

`ModelTextureCache.apply` 与 direct fallback 都跳过已经拆分的 native 根，避免只会发现“没有内嵌 ImageTexture”的场景/属性扫描；计数测试证明 split 的遍历和属性读取均为 0，普通 embedded 仍执行原逻辑。`instantiate_preview` 冷入口也不再返回未绑定 native 模型或先分配再丢弃几何：18 项旧源 2 FAIL → 新源全通过，已绑定缓存预览保留同纹理 owner。该门禁不是编辑器异步预览的替代实现。

另在真实 `MapLoader._build_records → instance cursor → WorldDocument` 链复现了缓存实例化的重复候选读取，以及跨 await 混用新旧模板。修复复用本轮已经接受的 PackedScene，经既有 `_private_assets` 与 `prepared.template` 通道传递，不新建长期全局缓存、不借任意 `_scenes` 条目绕过本轮身份。32 个 foreground 实例的 JSON 读取 64 → 0、SCN 长度读取 32 → 0；过程中替换全局模板，本轮仍全部使用原快照，下一次操作使用新版本。background 与取消/退出释放同时覆盖。初版 40 项旧源 6 FAIL → 新源 40/40，零诊断，见 `initial_template_snapshot_01`；不把包含实例化的单次墙钟时长当作纯 I/O 或整图收益。

最终补上未完成 READY、没有本轮接受快照时不能借全局缓存或偷偷读盘的入口检查，共 53/53。专用脚本自身 50 项，外部冻结的文件读取计数夹具额外 3 项；计数器没有写入生产代码。

## 最终共同快照与普通进场回归

`native_integration_freeze_01` 使用同一最终生产源码与 candidate05，GPU 导出/准备 **65/65**、Initial **18/18**、Deferred **19/19**，均零错误和警告。三组均 21,623 个非背景像素、源/候选 RGBA 零字节差，最终引擎驻留归零。后续 CPU 同快照的 preview 18、Initial 78、metadata 21、Deferred 主断言 64 全部通过；日志另有 Deferred 共用夹具的 10 条 PASS，不混成其主断言数量。23 个本轮生产文件逐一与 GPU 快照 SHA 相等。

原生模型夹具的观察图实际使用 Godot `save_webp(..., true, .9)`，384×192；精确比较仍用本地 RGBA/PNG。已查看交叉阶段的 quality=90 WebP，确认调色块、透明空隙和重复区域正常；编码记录、RIFF/VP8 检查与 SHA 位于 `native_cross_operation_gpu_green_01/content/cross_operation_native_39168/cross.review.json`。这是程序夹具的材质合同验证，正式房屋/植物的画质、LOD、风场、可编辑和保存重开仍待逐件验收。

另用默认已安装 **04d**，在最终源码和独立 71 项依赖副本上运行正常自动分阶段进场、失败恢复与连续取消：**35/35**，无 ERROR/泄漏、源码与依赖 SHA 不变。74 条已有 male GLTF stride 警告与旧基线逐项计数一致，没有新增警告。证据 `native_default_game_regression_01/result.json`。没有复测此前女性完整 flow 的超时，也没有把这组功能回归当成 axel_town 性能采样。

## 队列所有权证据与未解决边界

`tools/test_simple_command_queue_ownership.py` 从真实引擎源码提取 SimpleCommandQueue，在单线程中用始终存活的控制块统计 copy/move/destruct。它不访问已释放 payload，不需要外部暂停线程。旧实现四类所有权检查均失败，合法 move_to 对照均通过：浅 memcpy 后按值 move 会重复 decrement；const-ref 的最终释放发生在队列锁内。

这不是完整引擎生命周期验证，也未将该原型合入 candidate05。LocalVector<byte> 增长仍会原始搬移非平凡命令，现有对齐也不足以给出一般保证。完整实现需要稳定命令存储、锁外执行及销毁，并验证 push 重入、停止与排空。

源码审查另发现流式 I/O 使用裸回调 owner、纹理析构与排队 I/O 完成不同步的风险；尚无真实崩溃栈或完整生命周期复现，因此不写成已修。若未来在 I/O 命令中保持强 owner，必须先解决上述队列搬移和锁内析构，同时调整 shutdown 的反馈/I/O 排空顺序，避免用一个生命周期修复引入互锁。

## 后续顺序

1. 旧 operation → 新 Initial 的入站纹理复用仍需主线程按已知依赖 keys 提供票据，不能让 worker 直接查询 Paint 全局，也不能为了快照强持有全部无关纹理；等待票据不占生产 worker。最小设计及取消/early hint 边界见 B 的 `initial_native_inbound_reuse_next_slice.json`。原 `Prefab.texture_tickets` miss 会扫全部材质缓存，不能原样当作主线程桥的查询入口。
2. 解决引擎排队 I/O 的真实 owner 生命周期及 shutdown，完成独立复现和回归后再安装候选引擎。
3. 编辑器 LoadJob、PreparedModelOwnership、预览/放置和 TargetScenePrefetch 接入同一独立纹理准备与释放协议；当前 UI/HTTP MCP 还没有据此完成导入、保存重开验证。
4. 从入口大模型开始转换并按 `rmmo-model-review` 做受影响项验收，保持原像素默认策略。随后覆盖实际引用与角色原生产品。
5. 正式接入后再测 axel_town 加载、卸载、返回加载及 low，继续使用地图加载开始到当前需求区域完整就绪的计时边界。
