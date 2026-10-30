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

## 旧 operation → 新 Initial 入站复用

本切片以 `9eb7a9fa` 为旧源复现，补齐此前只覆盖 Initial → Deferred 的另一方向。旧 Initial 已完成绑定并发布缓存，随后释放其 scope；新 Initial 准备另一模型时，现在可以复用仍由旧缓存场景持有的同一原生纹理。完整交付清单为 B 的 `initial_native_inbound_reuse_handoff.json`；它包含逐文件 SHA、冻结工程、红绿结果及失败样本，不覆盖上一轮证据。

`MapLoader` 在启动 parser 前安装主线程票据桥，并在 `_process` 的线程存活提前返回之前按预算推进。后台唯一纹理表准备完成后只提交本表所需 keys；主线程直接查已有 hot/weak 条目，确认原生格式、源身份、有效 RID/load path 与实际 streaming 登记，再交付同一 owner。没有遍历全材质目录、读回像素、额外读取或哈希文件，也没有新增全局池或线程。early hint 换 controller 时保留桥，但每次 run 的请求、回复和 scope 独立。

已命中 keys 使用既有 `SharedPool.offer` 缓存路径，不创建新输出或重复预留完整纹理链；worker 把回复中的 owner 合并进该模型自己的绑定结果。只有本消费者实际新建的 native 输出进行预算移交，全命中仍完成真实材质绑定和 READY 登记。等待主线程回复不占 worker 槽，scheduler 将待回复/待退役视为可继续推进的外部工作。

票据与索引 metadata 单独按保守额度扣除 working budget。压测发现，若一直保留到整批完成，前一张大表的回复会阻止后一张表准入；现在最后一个模型消费该表后，主线程分片退役回复，协调器收到退役确认再退还额度。1024-byte 工作额度下两张超大表可以依次完成，退出后精确恢复原额度。取消只关闭标量请求；回复 owner 留到线程与结果别名退休后由主线程释放。即使回复到达与 close 竞态，也不重新交给 worker、不提前销毁最后一个 GPU owner。

|验证|旧源/失败样本|最终结果|
|---|---|---|
|入站 CPU 基础|`initial_inbound_cpu_red_02`：7 项中 2 FAIL，重复 producer 与 owner 身份不同，零诊断|`initial_inbound_cpu_final_05`：29/29，零诊断|
|实际 GPU 全命中|`initial_inbound_gpu_red_01`：15 项中 4 FAIL，新池创建/加载各 2 次|`initial_inbound_gpu_green_02`：15/15，创建/加载均 0；对象与 RID 完全复用|
|混合命中/缺失 CPU|同一模型一项命中、一项缺失|只产生 1 个输出、1 次 STEX load、1 次 handoff；受控夹具额度 128 bytes，两材质槽正确，最终 admission/pool 归零|
|取消、换代与低预算 CPU|包括暂停主线程回复、关闭时迟到回复、两张超大表|等待期间 0 个 worker 槽；真实 `exit_tree` 无需另一次 main pump 即可完成 join；旧 scope 不影响新 generation；最终 owner、metadata 与账本释放|

GPU 夹具执行了真实 native 文件/纹理表读取、共享池、绑定，以及 `MapLoader.start/_process/_exit_tree`；仅 parser 输入和最后文档构建由外部夹具替换。新 Initial 只查所需 2 个 keys、命中 2 项，保守完整链重复额度从 699,046 bytes 降为 0，不再次 handoff。回复 metadata 在结果返回时仍计 4,724 bytes，直至主线程 scope 清退。删除第一份缓存后，新场景仍有 **21,623 个非背景像素、RGBA 零字节差**；全部释放后引擎实际账本 **152,915 → 0**，观察 owner 全部死亡。

本轮混合 case 的上述结论来自显式假 native 验证通道的 CPU 测试，没有将它冒充新的 GPU 混合实测；上一轮共享池混合 GPU 合同仍是独立证据。测试同时存在引擎 CPU 编译竞争，计时不作对照结论。本切片只证明调用量、身份、画面和生命周期，不据此宣称 axel_town 加载耗时、low、物理硬盘读取量或实际 RSS/VRAM 改善。最终同 SHA 的无桥路径回归另在 `initial_inbound_final_regressions_02` 完成：Initial 78/78、metadata 21/21、Initial → Deferred 16/16、prefetch 41/41，全部 exit 0、零诊断。初次 `_01` 漏带既有 `-- --without-mock-server` 隔离参数，每组产生 3 条缺默认地图包诊断；恢复原参数后重跑，没有修改生产、测试断言或诊断检测，也没有复制地图包。原始 12 条诊断保留，完整源码与配置 SHA 见该目录的 `results.json`、`source_sha.json`。

以下生产文件 SHA 与最终 CPU/GPU 冻结副本全部一致；两个测试文件分别对应最终 CPU/GPU 样本。完整路径与比对布尔值在交付 JSON 中。

|文件|SHA-256|
|---|---|
|`scripts/world3d/map_loader.gd`|`4f0f2329ead642d770bf2d9abdf9b74effb17a2b40d92cb4f95ee9e3430f1108`|
|`scripts/world3d/model_parse_preparation.gd`|`a4f8acd1066cd42135d869bf9cd6886ad78ab6b22de51b5243a625afe4ebe31b`|
|`scripts/world3d/initial_native_texture_jobs.gd`|`42c15899d532b17acea4cf7f71a52f0e3cad437ac3dfef87324e53075a90d45e`|
|`scripts/world3d/initial_native_texture_scope.gd`|`9e2eea07498169f77aa2741b005ee1ca9e9f66ee84cb046eb8c691395baadac5`|
|`scripts/world3d/native_texture_sharing.gd`|`ecadb4b8ed0706974538ec294c476de13bc9474d36389e0d6716570ee4943ef0`|
|`scripts/world3d/initial_native_resident_bridge.gd`|`38f96251ee6bf9451ada529e80cca209bd8b6410445352682cdcf59fa3fc302a`|
|`tools/test_initial_native_resident_bridge.gd`|`542920f95dd68646cae966e3ffecd27a981a7c0cbe437e4f4c4395ac826f7a7c`|
|`tools/test_initial_native_resident_bridge_gpu.gd`|`3f2b8b554c40afc315727c493d03b625c8730d025dcb7764208904e0c3b2c486`|

失败样本均保留在 B，并区分生产问题与夹具问题：

- `initial_inbound_tight_red_01` 复现了生产票据 metadata 堵住第二张超大表；该样本还含下面已确认的测试 Node 释放错误，两者分别记录。
- `initial_inbound_cpu_green_02` 的新增取消夹具直接 free 正在执行 `_parse` 的锁定 Node；修正为先 `remove_child` 触发真实 `exit_tree` join，再 free。没有把修改测试说成修复生产释放。
- `initial_inbound_cpu_red_01`、`initial_inbound_cpu_final_02` 是夹具类型注解/推断导致的解析失败。`initial_inbound_gpu_green_01` 是桥排版时误将注释拆成代码，修正后重跑；这次失败没有可用 GPU 功能结论。
- `initial_inbound_cpu_final_03` 深复制未加载的 CPU native stub 导致空路径读取，另含错误材质槽；`initial_inbound_cpu_final_04` 的混合 normal 槽未启用/字典 key 设置不完整。修正夹具后 `_05` 通过，生产源码没有为这些夹具错误作改动。

## 队列所有权证据与未解决边界

`tools/test_simple_command_queue_ownership.py` 从真实引擎源码提取 SimpleCommandQueue，在单线程中用始终存活的控制块统计 copy/move/destruct。它不访问已释放 payload，不需要外部暂停线程。旧实现四类所有权检查均失败，合法 move_to 对照均通过：浅 memcpy 后按值 move 会重复 decrement；const-ref 的最终释放发生在队列锁内。

这不是完整引擎生命周期验证，也未将该原型合入 candidate05。LocalVector<byte> 增长仍会原始搬移非平凡命令，现有对齐也不足以给出一般保证。完整实现需要稳定命令存储、锁外执行及销毁，并验证 push 重入、停止与排空。

源码审查另发现流式 I/O 使用裸回调 owner、纹理析构与排队 I/O 完成不同步的风险；尚无真实崩溃栈或完整生命周期复现，因此不写成已修。若未来在 I/O 命令中保持强 owner，必须先解决上述队列搬移和锁内析构，同时调整 shutdown 的反馈/I/O 排空顺序，避免用一个生命周期修复引入互锁。

上述为 candidate05 交付时的边界。随后 `simple_command_queue_stable_06` 已实现稳定命令存储、锁外调用与销毁；独立夹具旧实现 5 项失败、新实现 16 项通过，覆盖增长、对齐、重入、并发生产与停止排空。微测包含新实现更慢的样本，每条命令增加一次分配/释放，不宣称吞吐提升。实际 Godot 原生测试也验证了 PackedByteArray 的 COW、Callable/Ref 所有权及析构重入。

`native_queue_lifetime_06/baseline2/run_02` 使用官方 doctest 入口、真实反馈/I/O 线程、public configure/flush/remove 与 dummy RenderingServer。受控 RefCounted 回调只使用外部控制块，析构期间保持分配存活：34 项断言中仅“回调未结束就开始析构”失败，证明生命周期协议缺口，无需制造悬空读。修复在反馈线程取得 owner 引用并随 I/O 任务传递，实际 state free 返回反馈线程，停机先关闭新任务、排空 I/O，再关闭反馈。`fixed/run_01` 的 33 项断言全部通过、零诊断；红测多一项失败路径的 I/O fence 断言，因此断言数不同。测试二进制 SHA 为 `16c0229135cd0f54676d4c44257297dd2a72e4a43f0e1ba4f322d14da66338dc`。

此时还不是 candidate06 的完整交付；随后补齐的证据与安装见下一节。`baseline2/run_01` 与 `gdb_01` 是运行目录错误导致官方测试初始化失败后 ThemeDB 空指针的宿主样本，保留但不算流式问题的复现，也不与此前游戏路径崩溃混为一谈。

## Candidate06 原生生命周期、回归与默认安装

最终原生 fixture 增加反馈线程上的最终 owner 析构、正在执行 reload 时发起关闭，以及多次启动/停止。关闭期间先阻止新生产，保持反馈线程服务 I/O 的最终 remove，待 I/O 完成后再停止反馈。反馈线程自身的同步调用直接执行，停止交接由独立调度锁串行化，避免最后一条同步请求留在已退出的队列中。它没有增加外部线程暂停操作，也没有通过读取已释放内存来证明失败。

`native_queue_lifetime_06/fixed2/run_01` **4 个 case、60/60 断言、零诊断**；测试引擎 SHA `633256fb7684459937eaf6b1a3457e2071111a5d75c8dfc1a6305b2167d8c34b`。实际编译选项是 `tests=yes`，不是无效的 `tests_enabled`；Godot 的 `TESTS_ENABLED` 只在 main 的编译环境定义，测试 friend 仅是编译可见性，不增加运行时 API。较早 `baseline` 构建失败来自 friend 门禁和 fixture API 名称，保留但不是产品红测。

普通运行版本另外以 `tests=no` 构建，仍保留匹配 GDB 调试符号。其 SHA 为 `d5fd6c2c82eae35a60c90b78318b71f7a8130987f1fd402ea22e1de0ba842f62`，主符号文件 SHA `6d365125e668e13bc7b7a4d151f222094cd35b00a5e895a13e2ee67df0e6890e`。以下 GPU 验证使用该普通二进制、`a5a543fb` 冻结工程和独立桌面，未混入正在开发的编辑器 LoadJob 改动或主工作区其他会话的未提交改动。

|验证|结果|证据（相对于 B）|
|---|---|---|
|native 准备、Initial、Deferred、入站复用|65、18、19、15 项分别全通过，零诊断|`native_queue_lifetime_06/gpu_regression_02/native_results.json`|
|mip 边界、混合预算移交、仅 2D cover|12、52、5 项分别全通过，零诊断|`native_queue_lifetime_06/gpu_regression_02/streaming_results.json`|
|读取失败与恢复|13/13；3 条刻意缺私有文件的预期错误，未预期诊断为 0|同上|
|普通游戏分阶段进场、失败恢复和连续取消|35/35；零错误/泄漏；74 条既有 male GLTF stride 警告与旧基线逐项相同；71 项依赖和冻结源码 SHA 未改|`native_queue_lifetime_06/normal_game_01/result.json`|
|旧独立所有权 fixture 的兼容性|原始 4 项失败、合法 move 对照全部通过，与此前结果一致|`native_queue_lifetime_06/legacy_ownership_compat_01`|

`gpu_regression_01` 少了冻结工程的 global class registry，出现 20 条 Customization/GPUClothCollider 解析诊断，虽有 PASS 也不作为验收。恢复既有 registry 后 `_02` 重跑；未修改生产代码、测试断言或过滤规则。正式女性完整 flow 的旧超时、所有可能的 reimport/退出交错及历史无栈崩溃，不在这些结果的已解决范围内。没有新的 axel_town 加载、帧耗时、low 或实际 RSS/VRAM 收益结论。

`tools/engine_patches/godot-4.8-beta1-runtime-candidate06.patch/json` 是从官方 pristine 4.8 beta1 到 candidate06 的**完整累计补丁**，不能叠加在 candidate05 上应用。对官方归档的独立稀疏副本执行 `git -c core.autocrlf=false apply --check` 与 apply，**48/48 文件逐字节 SHA 相等**；补丁 SHA `4a08ec4dc40e2762a3c2d49ea5fee050958e512ab58ff98322fe561ea0a45e51`。独立队列 fixture 的 16 项通过和保留的较慢微测见 `simple_command_queue_stable_06/delivery.json`；不将每条命令一次分配的实现描述为无成本吞吐优化。

默认 `D:/tools/godot` 已更新到上述 `tests=no` candidate06：主程序、console、两个版本别名、CLI 别名和匹配符号共 7 个文件逐项校验，三个主程序入口的 version probe 均通过。旧 04d 原字节及原安装清单保留在 `D:/tools/godot/_backup/before_06_20261029_144450`；安装记录在 B 的 `native_queue_lifetime_06/installation.json`。没有删除旧版本，没有转换或覆盖正式模型。

## 编辑器冷打开、共享纹理与几何消费者

编辑器 `LoadJob` 现使用 `NativeModelTexturePreparation` 和既有 preparation queue / editor ledger 准备拆分模型。metadata、几何和唯一纹理输出共同准入，等待共享 producer 的任务让出 worker 槽；同一模型的几何、像素和绑定仍在同一 worker 分阶段执行，并未声称它们在模型内部并行。成功发布才登记纹理复用，operation 结束才清退其共享池引用。连续打开不重设共享额度，避免抹去上一代尚未释放的 metadata 扣款。

已复现并修复六类边界：大 READY 结果阻挡另一个表的 demand；新代重设 byte limit；最后 allowance 重复退还；等待期间重复构造 offer；空纹理表要求不存在的 handoff；已释放结果仍通过 offer.rows 持有 metadata。超低预算双模型样本因必要的 speculative retirement 发生 3 次几何准备，保留该额外工作，不描述为严格一次几何读取；唯一纹理 producer 仍为 1。

`PreparedModelOwnership` 现在区分模型几何 envelope 与已经交给引擎的 native texture。共享纹理独立存活不再钉住已释放几何的额度；纹理 metadata 的私有 Resource 子项仍按实际所有者追踪。完整 queue packet 在交接前继续计账，成功后分别记 transient、published geometry 和 engine texture；published envelope 是保守基线，不是 RSS/VRAM 或整个进程的硬上限。没有在发布时再次哈希源文件。末尾重复扫描绑定/像素包已移除：普通 CPU 夹具 53 次递归访问变为 1 次材质归属查询，空表 38 变为 0；原几何图 159 次访问及槽位核对保持不变，sources/profile 各遍历一次，不递归扫描整个 scope。

|验证|结果与边界|证据（相对于 B）|
|---|---|---|
|默认 LoadJob 真实 GPU|140/140，2 模型、1 表、2 次 STEX load；36 槽在 READY 前完成，下一 LoadJob 复用同一对象/RID、零再次创建/读取；源/候选 RGBA 零差，最终各账本归零|`editor_native_texture_join_01/delivery_gpu.json`|
|可选 residency 发布与真实 GPU 生命周期|165/165，几何 envelope 128MiB → 192MiB → 64MiB → 0；仅保留纹理时几何已为 0、引擎仍为 152,915 bytes，最后纹理释放后引擎也为 0|`editor_native_texture_join_01/delivery_ownership_gpu.json`|
|最终去重源码 CPU|70 + 125 + 106 + 126 + 79 = 506 项通过，零诊断；包括外来材质、隐藏 Resource、额外 owner 的拒绝与无提前退账|`editor_split_native_ownership_01/no_duplicate_tail_01/delivery.json`|

上述两组完整 LoadJob GPU 使用去重前的 ownership SHA `a76c9e…`；最终 SHA `ebf60ae…` 已在后续真实冷 UI 样本中通过发布、共享和最终归零，显示失败见下节。不把两个源码版本的 GPU 证据混为同一快照。`gpu_resident_01` 的 QuadMesh fixture API 错误已保留，改为实际 ArrayMesh 后重跑；不是产品失败。

仅需几何的桥梁/城防 kit、道路与桥接触边界、散布边界和树形参数，现在用显式 `AssetLibrary.instantiate_geometry`。它可直接读 native 几何而不准备纹理表或 STEX；暖缓存复用原 mesh/material owner。实例带 geometry-only 标记，不能作为完整渲染模板进入 cache 或继承 READY。普通渲染消费者（例如复制 kit 材质的 auto tile）不走该入口。它仍是几何查询入口，并非把文件读取全部改为后台。

独立 CPU 以缺失纹理表、无 GLB/STEX 复现旧入口失败，最终 **47/47**，补测 native preview **18/18**、readiness **19/19**、native-only **24/24**，均零诊断。树 fixture 带真实序列化 recipe、UV2 和两个 LOD；非默认树形参数下，新几何路径与已绑定渲染路径的顶点、法线、拓扑、UV2、调整后 AABB/可见范围逐项相等，冷树形缓存不会替换渲染材质。证据 `native_geometry_consumers_01/green_tree_01`、`green_02`。早期零深度 AABB 断言错误已保留，最终按 Godot 序列化后的真实 AABB 比较。

这些是编辑器管线与资源合同结果，没有新的 axel_town 加载、low 或物理 I/O 提升结论，未转换正式模型，默认 split 导入仍未开启。

## 冷预览候选的显示缺口（复现记录）

后续切片让普通模型、缩略图和普通组合 prefab 复用有限批次的 `EditorAssetPreparation`；私有模板不加入全局 `_scenes`，完成但仍等待慢兄弟的模板纳入 published geometry 追踪。CPU 158/158；split CPU 使用协议替身的部分已在报告中明确，不能替代 GPU 证明。交付 `editor_asset_preparation_01/delivery_cpu.json`。

真实 GPU `gpu_ui_01` / `delivery_ui_gpu_red.json` 得到 **57 PASS、3 FAIL、零引擎诊断**。共享生产、真实 tracker、换选关闭、prefab、全局缓存不增长及最终归零通过。但首次预览 mip 3，随后纹理自然升至 mip 0，`UPDATE_ONCE` 画面仍停留 90 帧，相比同相机源图差 30,185 个 RGBA 字节；真实缩略图在 mip 2 保存，差 1,046 字节。之后仅允许普通连续重绘一帧，预览即为零差，未 flush 或强制 LOD。

三条失败断言中，首帧与完整细节不相等属于渐进流式显示的观察，不单独规定首帧必须全清；持续冻结与永久保存低清 PNG 才是必须修复的缺口。引擎 `texture_reload` 更新 current mip 时只把替换排入渲染队列，没有发出 changed；current getter 也不代表新画面已经完成。现有 pending 在 I/O 入口就被清空，不能用它判断是否正在读取。单纯持续轮询 mip 后重绘会与未使用纹理的降级互相影响，因此最终采用下面的有限观察与复核流程，没有用固定等待、mip 0 或全局 flush 冒充完成。

正式放置/rebuild、custom tile kit、UI 与当前 3D HTTP MCP 的事务验收仍在后续范围。`workspace.gd` 和 `docs/world_editor_mcp.md` 有其他会话修改，本切片未覆盖它们。

## Candidate07：有限纹理就绪观察与实际编辑器回归

引擎新增 `begin_texture_observation`、`query_texture_observation`、`cancel_texture_observation`。在正常 process、目标 `frame_pre_draw` 之前创建票据，然后请求一次真实绘制；票据对应原始反馈 buffer 的 generation，沿用原有异步 GPU 回读、30ms 节流及预算 fitting。完成水位只接受连续完成的 generation，乱序段合并，不把“最大已完成编号”当作全部完成。

I/O epoch 在清空 pending 前进入执行态，全部返回路径用 RAII 退出，读取端检查一致性及内存顺序。查询复用反馈线程，主线程不 join/flush；票据仅持有 RID/ObjectID，不跨帧钉住纹理。无正反馈是整个被标记 buffer 周期的结果，并非单 viewport 归因；这类有效对象可完成，不被别的周期 I/O 阻挡。正需求则要求当前 mip 达到预算 fit、无 pending/执行中任务，允许预算限制下的非零 mip。

编辑器只扫描一次当前材质图，保存弱引用；预览允许渐进首帧。观察 ready 后重新绘制，等待 `FramePresentation.after_drawn`，再以同一票据复核版本，才结束预览或写 PNG。版本改变就重试；隐藏、换选、滚动和关闭取消票据并屏蔽迟到回调。超时明确报错，不伪装完成；结束后停止查询/重绘。还修复了全驻留 STEX 的分类：关闭 streaming 后仍是同一纹理类，必须检查 `is_streaming_active()`，走普通单次绘制。

|验证|结果与边界|证据（相对于 B）|
|---|---|---|
|引擎原生线程/反馈合同|10 case，148/148，含新增 88 和原生命周期 60；tests=yes 与 tests=no 的 49 项源码一致|`native_texture_observation_07/delivery_cpu.json`、`delivery_runtime.json`|
|编辑器协议、collector/控件、请求服务|269 + 24 + 158 均通过；最终 active 分类修改后的 collector 24 项另复验|`editor_asset_preparation_01/readiness_delivery_01/report.json`、`delivery_ui_gpu07_final.json`|
|最终真实 UI|72/72，预览 settled 与持久 PNG 均 RGBA 零差；该夹具每控制器 1 begin/6 query/2 draw，随后 90 帧无新增 query/draw；实际 ticket 取消、共享及各账本归零|`editor_asset_preparation_01/gpu_ui_07_04`|
|既有 LoadJob 与 mip 边界|140/140、12/12，最终 ownership `ebf60ae…`；零诊断|`editor_asset_preparation_01/delivery_ui_gpu07_final.json`|
|普通游戏|35/35，74 条既有 male GLTF stride warning 与 06 按序逐条相同；无新增错误/泄漏，71 项资源未变|同上，`gpu_normal_game_07_01`|
|streaming 关闭的真实 STEX|红 14 PASS/6 FAIL，已加载 256×256/9 mip/有效 RID、mip0；修复后 24/24，预览/PNG 零差、各 1 draw/0 begin/0 query|同上，`inactive_stex` 字段|

inactive 样本直接把已加载全驻留 STEX 交给控件，仅证明其呈现，不冒称整个 split 准备器的 Compatibility 支持已完成。原 259 项报告保持原 SHA；最终报告替换 UI 为最终 collector 的复验，其他同引擎回归引用原报告，额外 inactive 24 单列。第一次 GPU 快照混用了新 geometry consumer 与旧 AssetLibrary，虽然有 PASS 仍因解析诊断被拒绝；修正依赖后重跑。原冷 UI 红测、runner 路径错误和 inactive fixture 解析失败都保留。

原生测试首次运行缺少官方 `tests/data`，在任何 case 之前初始化失败、ThemeDB 清理崩溃；补齐隔离 cwd 后同一二进制全部通过。首次编译的 LocalVector 显式复制构造写法也已修正并保留失败记录。这些不是历史游戏 `0xC0000005` 的复现或修复证据。

普通 candidate07 已安装为默认 4.8：EXE SHA `dabba1322488f959bddbd1d20ebdf40ee788c918c1a8b193a533d0472efb7375`，主符号 SHA `53c4f5fbd0fad31f24e5c13f1cb2637484998b7bef23762b6a951e82dc5b98a3`。7 个入口/别名/符号全部核对，3 个主入口版本探测通过；旧 06 保留在 `D:/tools/godot/_backup/before_07_20261029_173232_031474`。安装及最终记录同步见 `native_texture_observation_07/installation_attempts/20261029_173232_031474/installation.json`、`delivery_manifest_lf_finalization.json`。累计 patch 从官方归档回放 49/49 文件逐字节相等，不叠加到旧 candidate 上。

### Godot 导出模型的 SingleRoot 导入修复

完整资产回归发现普通 Godot 导出的 GLB 带 `GODOT_single_root`，被旧 Manifest 的 extension 白名单拒绝。仅增加标记识别仍不够：4.8 实际固定生成 node 0，而非 selected scene 的 roots。现在 bounds 跟相同子树走，根 TRS/shear 保留一次、不累乘原父、不混入其他根；不添加“只能一个 scene”的限制。原有无效图、未知 payload、变形及 native-map 边界保持。

专用红测 92 项中 19 失败；修复后 108 项真实导出/解析/native 保存、21 项独立进程无 GLB 冷重开、原 bounds 42、policy 22，合计 **193/193、零诊断**，见 `godot_single_root_bounds_01/delivery.json`。没有绕过 `Compiled.build` 的 graphics_required 让 CPU 假装完成实际导入。

真实 GPU `editor_native_assets_regression_01/gpu_native_04` 的 **20/20** 验证 Library 导入、去重、真实编辑器预览、变换/碰撞、撤销、保存及删除 GLB、清理模板缓存后的重新加载；只有删除 native 产品才报缺失。隔离 content root 缺云噪声的 1 条 fallback warning 单独保留，无脚本错误。这里不是 file-dialog/HTTP MCP 的全流程验收、OS 冷缓存测量，也没有开启默认 split 导入或修改正式素材。

## 连续编辑消费者复用同一份已完成模板

`2ebe6dfd` 上的独立红测确认：预览的 Handle 已销毁、但实际场景仍通过 `_compiled_resource_owner` 持有原模板时，随后两个消费者仍会再读两次 native 文件。三个消费者形成三份不同的 PackedScene/网格；夹具的保守几何基线从 64 增至 192 MiB。这是三份分配的正确记账，问题在重复准备，不是重复扣账；该值不是实际 RSS。

`EditorAssetPreparation` 现在只对已经完成 READY、adopt 和 publication 的模板建立弱索引。按 content root 和逻辑模型路径定位，比较完整当前 candidate 和原生身份；命中后走既有异步 Handle 交付，不再读取、绑定、入队或重复 adopt。没有新增强缓存、线程池、资源 metadata 或第二套预算，也不把结果写入全局 `_scenes`。同路径仅保留当前版本；失效、未完成、仅供几何查询的模板仍会被拒绝。

死索引按固定小步清理，存活条目不因任意数量上限被淘汰；闲置服务停止处理。探活使用实例 ID，避免仅为了清索引就通过 `WeakRef.get_ref()` 临时取得大资源的强引用。candidate 不同先丢弃索引；真正借用后若发现状态无效，交给既有 `ResourceRetirement.defer_scene` 清退。额外的受控协议红测覆盖了这三个分支，不冒称已经抓到历史长帧中的同一原生线程竞态。

最终验证均以 `git archive 2ebe6dfd` 为基线，仅覆盖本切片指定文件，未混入用户 12 个 WIP 或同时开发的放置、prefetch 修改。引擎仍是默认 candidate07，EXE SHA `dabba1322488f959bddbd1d20ebdf40ee788c918c1a8b193a533d0472efb7375`。

|验证|结果与边界|B 下证据|
|---|---|---|
|独立 CPU 复用及回收|1095/1095；145 个存活模板不被数量上限淘汰，候选变更、READY、取消、死条目清理及最终归零|`editor_sequential_native_requests_01/isolated_cpu_01`|
|原请求服务回归|158/158；冷并发用例先等原模板 WeakRef 真正失效，再保留新 producer 的原断言|`editor_sequential_native_requests_01/isolated_compatibility_01`|
|真实 GPU 顺序消费者|51/51；实际预览 → 实际缩略图 → 普通实例请求，native read、纹理表读取、STEX 加载、材质绑定和几何 adopt 各一次，PackedScene/Mesh/Texture/RID 相同|`editor_sequential_native_requests_01/gpu_sequential_02`|
|既有呈现回归|72/72；沿用同版本 UI/有限观察协议和像素比较|`editor_sequential_native_requests_01/gpu_ui72_01`|

合计 **1376 项通过、零诊断**。三个消费者释放并完成清退后，临时账本、已发布几何基线和该夹具的引擎纹理计数归零；随后重新请求产生新的 producer 和分配。无全局强缓存增长，也没有用永不释放的模板换取命中率。生产 service SHA `ed9298337598af9d07f403faaf8018703542b98bd86ae3a8c18d2e9145176f55`，完整最终记录见 `editor_sequential_native_requests_01/delivery_reuse_final.json`。

旧工作区依赖的探索 CPU/GPU 样本保留，但不作为最终隔离验收。此切片证明工作量减少和共享/回收正确性，不等于正式放置/HTTP MCP 已接通，不提供整图加载时间或 1% low 收益。默认 split 导入仍关闭，正式资源未修改。

## 消费世界退出时异步清退跨图预取

独立复现确认：原 `TargetScenePrefetch` 随 world 一起销毁，进入 `MapLoader._exit_tree → drain_shutdown`，在主线程等待尚未完成的解析。真实 SCN 解码后受控延迟返回 250ms 时，普通 cancel 立即返回，但 world.free 阻塞 254.611ms、期间没有 process_frame 推进。

现在 `TargetScenePrefetch.for_world` 在正常派发时即把任务挂到既有 SceneTree drainer 下。消费世界退出只 abandon/cancel，原 loader、回调和同一份预算继续存活，沿现有异步收尾路径退出；未在 `_exit_tree` 中重挂节点，也没有把仍被线程调用的 loader 提前释放。完成后才释放 lease 和空闲服务。真正销毁 SceneTree/drainer 时仍保留同步安全等待。

预热的两次绘制仍检查相同 `FramePresentation` 的实际完成串号；等待期间逐帧响应取消，避免 renderer 不再提交绘制时 `_warming` 永久留住资源和预算。普通 process_frame 不能冒充绘制完成。abandon 后不能再 request/take，同 world 查找幂等、不同 world 独立；退出前已经捕获的路径继续供清退使用。

最终以 `2ebe6dfd` 隔离基线和本切片指定 override 验证，默认 candidate07 EXE SHA 与前节相同。CPU **50 + 49** 项及 GPU **36** 项通过，零引擎错误/警告：

- CPU 取消专用命令需要 `--cancel-only`：`target_scene_prefetch_cpu_01/cancel_frozen_02` 与 `retirement_frozen_01`。同一 250ms 门控条件下，world.free 返回为 70us，随后推进 39 次 process_frame；后台完成前原 native owner 与 1GiB lease 均仍保留，完成后归零。零绘制时取消预热、verify 进行中、两 world 隔离和幂等 abandon 也通过；最终 drainer 销毁仍等待 253.865ms。
- GPU `target_scene_prefetch_cpu_01/gpu_04` 通过真实 world 进场、一个 initial native 模型和两个 STEX、两次实际绘制、park、`transfer_map` 接管及采样 RID 复用。另一次真实 SCN 读取的返回被门控 1000ms，world.free 返回为 40.641ms，随后推进 58 次 process_frame；取消地图文件被删除、session 路径被清理后，任务仍正常退役。最终 lease、门控 native owner、采样纹理弱引用及该夹具引擎纹理计账全部归零。

这些是独立夹具的路径和生命周期证明，**不是 axel_town 总加载、1% low 或全部退出长帧的验收**。GPU 逐对象弱引用只覆盖采样的 PackedScene、Mesh、Material 和一个 surface Texture；另一个 STEX 由实际准备计数和最终引擎归零覆盖。`normal_loaded` 因测试字典别名被清空，具体串号/profile 未保存；对应原断言和 PASS 日志仍在，不补造这些数值。

`gpu_01` 因平面恰落 entry clip 边界，没有进入 initial native 路径，保留为不合格夹具；移入 core 后 `gpu_02` 已走到该路径，但测试函数的 Mesh/Material 局部引用导致末尾仍有 9555B。将观测局限于返回标量/弱引用的短函数后，`gpu_03/04` 全绿，生产代码未因此修改。所有失败和较早工作区依赖样本原样保留。

完整记录为 B 的 `target_scene_prefetch_cpu_01/delivery_cancel_gpu.json`。本切片不修改 split 预算估算：CPU 测试不带 `--cancel-only` 时仍会执行尚未解决的预算红探针。该探针只验证合法元数据声明的保守预约，不分配巨量像素，也不代表实际 RSS；后续须单独处理。试玩初入的 `playtest_session.clone.build` 是另一消费入口，本次跨图预取修复没有覆盖它。

## 冷模型放置、预制件与撤销重做

原真实编辑器红测出现两项失败：冷模型放置返回成功但只有占位物；释放最后一个 owner 后的冷 redo 也缺失模型。现在 UI 与 3D MCP 共用 `PreparedAssetOperation`，先通过现有 `EditorAssetPreparation` 去重并准备完整模板，再私下分帧建立场景和拾取碰撞。准备期间不修改当前记录、UUID、撤销栈、视图、选择或 dirty 状态；发布前复核文档/源/保护上下文及连接状态，成功后提交一次事务。HTTP 保留连接到最终结果，断线只取消本请求；并发请求若基于旧版本，则明确失败。

历史操作只分类一次，姿态/属性/地形材质继续走增量路径。新碰撞形状先存私有缓存，成功才并入现有缓存；取消不会污染后续复用。普通模型操作借用已有地形上下文，零额外边界扫描；混合地形变化只准备受影响上下文。重力放置仍显示原下落过程，并在落定后产生一笔撤销。此处约 2ms 是切片调度预算，不能抢占单个模型、碰撞形状或最终同步提交。

|验证|结果与边界|B 下证据|
|---|---|---|
|冷操作 CPU|174/174；真实文档/操作，split 上传和 ownership 为显式协议替身|`cold_asset_operations_01/frozen_cpu_04`|
|拾取与建筑增量回归|42 + 30；相关最终源码 SHA 一致|同目录 `frozen_cpu_03/regression`、`frozen_cpu_04/regression_02`|
|真实 HTTP/UI/GPU|89/89；默认服务/原生 STEX/真实 ownership，冷 redo、断线、并发版本冲突、UI model/prefab、无 GLB 保存与 LoadJob 重开|`cold_asset_operations_01/gpu_http_02`|

合计 **335 项通过，零诊断**。GPU 的真实地表批次由 6 个 source surfaces 合为 1 个 render surface，模型放置/历史操作后原合批节点与 body 身份保持。源/候选渲染 RGBA 零差；真正冷 redo 前原 PackedScene/纹理 owner 已死亡，新分配身份不同。所有场景释放后 temporary、published geometry 和该夹具 engine texture 计数归零。截图已用实际有损 WebP quality=90 保存；root 查看了实际编辑器画面。

该夹具准备延迟最高 58.548ms（不是主线程 CPU 时间），visual 0.544ms、body 2.761ms、commit 33.819ms、含复核的 publish 38.056ms。操作期间整帧最高 130.632ms；含保存、截图/readback 的整段最高 609.415ms。保留这些慢样本；没有整图加载或 1% low 收益结论，也不把本切片称为消除了主线程长帧。恢复 checkpoint、既有 Doc undo/redo 深拷贝及最终发布仍有同步工作。

完整交付 `cold_asset_operations_01/delivery.json`，SHA `5e6a5976ef00eb5d74ce6543852712069fdef6f6a40271e3590697547faaa71f`，联合源码 SHA `c229560080c5f4e0026e45e3c05b6d1000f5f0817e8b947bfc9fe0960c90fcfa`，默认引擎 candidate07 与前节相同。最终 GPU 样本替代较早 87 项样本，不重复累加计数。

原 `test_world3d_prefabs` 在旧基线与候选均为 21 PASS / 2 FAIL、无引擎诊断：一项期待模型复制到目标库目录，另一项期待删除 GLB 后 native 依赖失效。它们没有被改成通过；GLB 删除和原生产品删除应分开测试，而资源包独立依赖/搬迁的要求仍须核查，不能仅凭基线也失败就删除其合同。普通 `_rebuild`、custom kit 和试玩入口不计入本切片完成范围。默认 split 仍关闭，正式资源未修改。

## 普通整视图重建与自定义套件的剩余入口缺口

`1b3f5293` 上新增独立 CPU 复现，直接调用真实 `WorldEditor._rebuild` 与 `AutoTileKit.piece_mesh`。由共享服务完成准备、原 Handle 已释放、实际编辑器视图仍持有私有 READY 模型且全局 `_scenes` 为空时，整视图重建先释放旧视图，再调用没有 prepared templates 的 `WorldDocument.build`。结果模型变为 `missing_asset` 占位物，并额外读取一次 native 几何；原文档记录未变。这个入口仍由隔离显示、部分程序化编辑、重新关联等操作调用，不能用放置/历史操作的私有发布覆盖它的验收。

同一模型的自定义套件入口也返回 null；从已准备场景提取 piece 的控制组成功，把同一模板放入既有全局缓存的控制组也成功且纹理对象相同。因此缺口在消费者取得完整模板的协议，不在模型或纹理内容。后续应让这些入口复用准备结果，并为真正的冷依赖保留异步准备、失败保护与明确完成状态；不能通过永久填充全局强缓存绕过。

证据：B 的 `editor_native_rebuild_boundary_01/delivery_red.json`、`red_01`，**15 PASS / 3 FAIL、零引擎诊断**。以 git archive 为基线，只新增专用测试；6568 个归档文件复核一致。native 几何和表读取使用真实代码，纹理上传及 split ownership 沿用明确的 CPU 协议替身；不是 GPU/整图性能结果。红测源码保存在 `B/editor_native_rebuild_boundary_01/red_01/project/tools/test_editor_native_rebuild_boundary.gd`，SHA `1ede3d4d47424e20563b673ee257f868b0371c2ea1b8086384baf7f0d0390ebe`；工作区同名测试留待后续修复，未计入本次提交。默认 split 导入继续关闭，正式模型未转换。

## 试玩复用同一份完整模型准备结果

试玩的出生点碰撞验证与实际场景分别需要新的节点和物理对象，原先两次裸 `clone.build` 在私有 native 模板存活时仍会重复读取，真正冷 split 模型则缺少完整材质。现在先通过共享 `EditorAssetPreparation` 按规范化逻辑路径去重，两次 build 消费同一批 READY PackedScene；场景取得实际资源所有权后释放请求和 Handle，不把模板存入全局强缓存。碰撞探针会改变 stream 索引，并在 host 上创建兄弟 body，因此仍保留两份新节点树，不能直接搬移探针根节点。

准备阶段保留文档身份、revision、路径与关闭状态检查；物理帧/处理帧边界和最终进入前检查资源身份。原 session 自身的 await 在 owner 销毁后可能恢复已释放脚本，独立取消红测复现后改为可单独断开的真实 physics/process frame 回调。加载阶段沿已有 `_process` 轮询直到 ready/失败/取消，空闲和运行阶段停止处理。停止或关闭编辑器时只取消本请求，恢复此前 session/server 状态并删除本次临时试玩地图；退出树时不递归释放正在退出的子节点。

|验证|结果与边界|B 下证据|
|---|---|---|
|准备、取消与旧 HTTP CPU 回归|75 + 210 + 46，通过；split 上传/归属使用明确的 CPU 协议替身|`playtest_native_preparation_01/green_02`、`cancel_03`、`existing_playtest_02`|
|真实 native UI/HTTP 与退出生命周期|66/66；实际 F5、结束按钮鼠标输入、无 GLB 冷 HTTP start/stop、实际 loading 中停止和销毁编辑器|`playtest_native_preparation_01/gpu_loading_03`|
|既有图形试玩回归|81/81；非法/无支撑/阻塞出生点、私有进度、跨图再回临时地图、编辑保护|`playtest_native_preparation_01/gpu_legacy_01`|

最终 **478 项通过，零诊断**。已有私有模板的 UI 路径增加 0 次 producer/native read；原模板及纹理 owner 真正死亡后，冷 HTTP 路径增加 1 次 producer/native read，并供两次 build 共用。实际 PackedScene/Mesh/StreamedTexture2D/RID 身份一致，全局 `_scenes` 为空；结束并清退后 transient、published geometry 和该夹具引擎 texture 计数均归零。64MiB published 几何数值是夹具的保守 envelope，不是 RSS/VRAM。原文档、正式地图 SHA、历史/选择/相机及原游戏进度保持。

以 `git archive b9d7d6d9` 加本切片文件独立验证，未混入其它并行修改或用户 WIP；默认 candidate07 EXE SHA 与前节相同。旧 `tools==118` 总数断言改为必需工具唯一性和具体参数 schema，不把新增工具当作失败。较早缺 Trace、WeakRef 注解和隔离 MockServer 默认碰撞包的失败样本保留；runner 补足明确外部 fixture，未关闭生产检查。最终 66 项替代较早 55/60 项，不重复累计。

完整交付 `playtest_native_preparation_01/delivery_final.json`，SHA `46a8fceebaca71c0dbd3f53d7e79f167da8d20af25c007ea0bfd3198cf39c63e`；生产 `playtest_session.gd` SHA `eab4240140d8ea6a9e0e763bedd16fcc52ab163b10edd280a65cdbda479bdfe0`。root 复核交付列出的 26 个文件 SHA，并查看两张实际有损 quality=90 WebP：冷/复用路径的彩色模型和阴影均在真实试玩视图显示，截图时仅隐藏角色渲染并随后恢复。没有正式模型画质等价或整图性能结论。

本节仅覆盖普通 asset；custom kit 的依赖收集仍需接到共享 record/build context。初始编辑器 fixture 为构造基线曾短暂使用旧 cache，试玩测量前已驱逐；此结果不冒称普通 `_rebuild` 已完成。默认 split 导入仍关闭，正式模型尚未转换。

## 原生预制件资源包独立性复现

为区分旧 prefab 测试里的 GLB 假设和实际原生依赖合同，新增只读生产复现：使用真实序列化的 synthetic native 模型，没有 GLB；调用实际 `PrefabLibrary.capture/read`，然后只暂时移走该测试模型原来的 native index。捕获成功且作者记录不变，但捕获结果仍指原逻辑路径；原登记不可用后，预制件读取失败，恢复原登记立即恢复。这说明当前捕获没有建立目标包独立的模型登记，不能将旧“模型复制到目标包”失败简单删除。这里只隔离了登记依赖，不宣称证明了完整跨机器搬迁合同。

`native_prefab_pack_closure_01/red_01` 为 **12 PASS / 2 FAIL、零诊断**，基线 `0b255db8` 的 6575 个归档文件全部未改，仅新增测试。未启动纹理 worker 或 GPU、未改正式资产，测试原登记已恢复。完整记录 `native_prefab_pack_closure_01/delivery_red.json`，SHA `5c3866ee110e83c09d3ce0304e462019be2ec05bedd38e72f307c8f3615ffad1`。冻结测试在该目录 `red_01/project/tools/test_native_prefab_pack_closure.gd`，SHA `9de96b31d6f4fadac6a09f28402cea38da34e1c2e4a56c401d5d16586447c283`；主工作区同名测试留待修复，不计入已通过切片。

## 跨图可选预取预算与预算拒绝后的重复准备收尾

本切片在用户将优先级明确转为编辑器可用性后只完成既有测试与归档，不启动后续性能工作。原外层 1GiB 预取 lease 没有约束 split 内层的 oversized-exclusive 放行，也漏扣已完成但仍保留的几何。实际共享 pool 对合法 16K 单 mip 元数据给出的保守工作预约可达 4,295,032,832B；这是协议估算，测试没有分配巨量像素。

现在保留既有源 packet/地形等外层 allowance，native scheduler 在剩余额度内同时计算 definition-cache 预约容量、已保留几何、表/票据元数据和实际共享池工作。严格模式下额度可以为 0，不能借 oversized-exclusive 越界；普通按需加载仍保留原 exclusive 行为。表工作区在 resident ticket 建立期间继续计账，再交给保留元数据，避免交接空窗。非 split 分支仍沿旧的双倍几何 plan 上界，不冒称使用新严格账本。这些均为保守工作量预算，不是进程 RSS/显存硬上限。

随后复现了预算拒绝导致的反复调度：实际 `World3D` 每 250ms 检查接近目标，同一 manifest 和额度下，12 次检查触发 5 轮真实 CrossMap、native 几何与纹理表准备。现在仅在本次接近期间记住明确的终止预算拒绝，在 CrossMap 启动前抑制重复任务；原任务、token 和 lease 仍正常清退。离开/取消、切换目标或根目录、definition-cache 配置容量变化、观察到源文件 stamp/长度变化或新 packet 的真实 manifest/native cap 变化后可以重试。普通取消不留下预算拒绝记录，真正传送的 take/verify 和按需加载不受该 memo 阻挡。

失效探针每次最多轮转检查 4 个已有 manifest 路径的 mtime/长度，不解析/重哈希内容。最终样本的前 12 次检查只产生 **1 次 CPU packet、1 次几何读取、1 次表读取、0 次像素读取**；36 次路径探针累计 10.898ms、单路径最高 1.217ms，后续 8 次检查仍无新准备。它有同步元数据 I/O，既不是零 I/O，也不是耗时上界；同秒同长度的外部替换可能直到离开再接近才恢复可选预取，实际传送仍执行原权威校验。

最终以 `1b3f5293` 归档加指定 6 个生产文件独立验收：预算 121、retry 35、旧回归 198，共 **354 CPU 检查**，另既有真实预取 GPU 生命周期 **36 项**，全部通过、零诊断。GPU 验证实际 STEX、两次绘制、park、接管及退出后归零；受控 1000ms worker 下 world 退出调用 42.458ms，仅作为该样本保留，不能推广为整图长帧结果。原 121 项预算测试有 20 项红失败，重复准备红测为 5 次几何/表读取，均保留。GPU 初次运行在启动前因 LF/CRLF 的精确 SHA 守卫拒绝；最终显式使用原已验 CRLF 夹具字节，文本相同，生产未改。

完整交付 `target_scene_prefetch_budget_01/delivery_budget_final.json`，SHA `a2edac1f90c029de15691ea2ba15aee2525811f046e1a832f50b01959efce7ef`。默认 candidate07 未修改。GPU 原夹具 `normal_loaded` 字典别名被清空、只对其中一个 surface texture 保留逐对象弱引用等限制沿原记录保留；不补造 profile，也不将旧样本重复计数。没有 axel_town 总加载或 1% low 收益结论。

## 默认拆分导入：完整编辑流候选验证（尚未切主默认）

当前 `AssetLibrary.import_file` 默认仍调用 embedded native 编译。独立 `e1cb061b` 归档中通过真实 GLB 导出/公共导入接口复现：8 项检查中 6 通过、2 失败，失败分别是没有独立纹理表、原生几何仍内嵌图片，零引擎诊断。证据为 B 的 `editor_split_import_flow_01/red_01`。这不是资源坏包，属于导入默认值尚未切换。

候选只在导入端启用 `Compiled.build_from_prepared(..., true)` / `Compiled.build(..., true)`，并要求本次会话的复用记录含纹理表。`candidate_01` 使用相同归档和明确的单文件覆盖，实际公共导入两个带纹理模型，再删除原 GLB 和素材库中的 GLB 副本，运行既有真实 UI/HTTP 冷放置、撤销重做、预制件、原子保存、切图及冷重开流程：**95/95 检查通过，零诊断**。实际放置纹理为 `StreamedTexture2D`，同相机对比 30,912 个可见像素、RGBA 差异字节 0；退出后临时账本、私有几何和引擎纹理驻留全部归零。未改变正式地图或资源。

实际编辑器图及源/候选对比图均保存为原尺寸有损质量 90 WebP，记录见 `candidate_01/webp_proof.json`。两张对比图 SHA 都是 `941d47458aa1a7ce63ed3ebe3e1fde929162111a6c85bfc16a3cbf33da1c20fe`。这里只是合成管线夹具的功能与无损画面证据；不是新美术模型交付，也不是 axel_town 性能数据。导入场景包含 GLB 重导出路径，实际记录 parse_count=2，未冒称一次解析。

**该候选轮结束时主默认尚未切换**。2026-10-30 已在工作区将默认导入切到拆分产物，并进行整合验证，见文末；正式旧模型迁移和其受影响项验收尚未完成。

## 整视图重建、套件消费者与预制件独立登记（已完成并回归）

上节列出的三项入口缺口已经落地，编辑器交互、LoadJob、MapLoader、试玩与跨图预取现在共用同一份记录依赖与构建上下文：

- `record_asset_dependencies.gd` 统一“记录→原生依赖”（普通模型 + 自定义套件件），替换各入口各自的 `kind=="asset"` 判断；`prepared_record_context.gd` 让一次构建借用 READY 模板并缓存派生套件网格，不再把派生件写回全局强缓存；`private_view_preparation.gd` 提供与事务共享的私有视觉/碰撞分帧构建。
- `WorldEditor._rebuild()` 改为 `PreparedAssetOperation.rebuild()`：重建期间保留旧视图，准备完成才整体替换；只读依赖时走同步完成，模型冷依赖时分帧并在编辑器静默后发布。
- 套件消费者 `AutoTileKit.piece_mesh/build` 接受构建上下文；缓存改为弱引用 + 有界标量存活检查，套件派生网格通过 `_compiled_resource_owners` 保留原模板租约，CPU 规格捕获沿用该租约。
- 预制件独立登记：`native_prefab_dependencies.gd` 在目标包内写 `native_models_v1/<identity>/{index,footprint,(building)}.json`，记录只指向固定命名空间的 `model.glb` 逻辑路径；`Compiled.index_path` / `CompiledAssetFootprint.descriptor_path` 识别该命名空间，校验仍要求源/产物/合同字段一致。检查改用原生可用性而非 GLB 是否存在，原“把 GLB 复制进包”的测试假设替换为“移走原登记后预制件仍可读”。

同时补两处事务安全，避免新交互丢失已编辑内容：

- 作者修改类事务（放置、整视图变更、撤销/重做）不再被保存、撤销、重做、试玩和关闭前的清理取消；处于准备中时给出“正在准备编辑结果，请稍候”的明确提示，只有预览与整视图重建这类纯呈现事务可以被丢弃。
- 整视图重建被并发编辑打断后会自行重试（`_retain_stale_rebuild` + 静默后一次重建），不会停留在旧视图。

导入与重新关联也收敛为一份实现：`model_import_tools.gd` 的 `import_model` / `relink_model` 同时服务 UI 文件选择框与当前 3D MCP（schema 与文档同步），重关联保留实例 ID、变换并只形成一笔撤销。

自动拼接画笔的“私有预演”尝试已回退为逐格同步刷新（UI 与 MCP 一致）：该实验在真实 UI 测试里会把整视图替换成只含本次格子的部分视图。`auto_tile_stroke` 的暂存能力保留但不在交互路径使用，后续若恢复必须重做整视图替换条件。

|验证|结果|环境|
|---|---|---|
|整视图重建、套件消费者、中断后重试|25/25；真实编辑器、私有 READY 模型、原生读取计数 0、历史/脏标记不变|CPU headless，隔离内容根|
|冷放置/历史/试玩事务回归|174 + 89|CPU headless；GPU 私有桌面|
|载入与准备|130 + 1095 + 106 + 55 + 21|CPU headless|
|自动拼接画笔真实 UI|17/17；路径形状、撤销、保存重开、墙内角拾取、1024 布局|GPU 私有桌面|
|素材准备与启动视图|53/53；含“启动即准备好的视图”检查|GPU 私有桌面|
|预制件独立登记|23/23；移走原 GLB 与素材库副本后仍可读、可放置、可保存重开|GPU 私有桌面|
|导入/重关联真实 HTTP|38/38；非法参数无副作用、撤销重做、锁定保护、保存冷重开|GPU 私有桌面|
|整图增量记录|81/81|GPU 私有桌面|

全部夹具使用 `editor_rebuild_transaction_20261029/run_01|run_02` 的隔离内容根，未改正式地图或正式素材库；CPU 与 GPU 样本分开记录，不把两者相加当整图成绩。

**保留的基线红项**：`test_world3d_autotile` 的“导出 glTF 保留顶点色”断言在未修改的 `e1cb061b` 上同样失败（headless 与 GPU 均复现，错误为导出网格缺少 `COLOR_0`），不是本切片引入，也未在本切片修复。`test_native_kit_consumers_gpu` 的 split 元数据断言按设计需要候选默认导入，默认仍为 embedded，因此该断言在主默认切换前保持失败；其余 9 项照常通过。

## 后续顺序

1. 旧 operation → 新 Initial 的**已完成 owner 入站复用已完成**，结果见上节及 B 的 `initial_native_inbound_reuse_handoff.json`。并发 operation 中尚未完成的 producer 仍各有自己的池，尚无跨 operation 的全局在途 single-flight；不把本轮完成票据复用说成该问题也已解决。也不能因 `start` 时目录为空就整次跳桥，旧 operation 可能在 metadata 就绪前发布 owner。后续可考虑请求抵达主线程时，以两个目录当前均空作 O(1) 全 miss 回复，保留现有取消与 metadata 退役合同。
2. 引擎排队 I/O 的 owner、shutdown 及预览就绪 API 已按上节复现、修复、回归并安装 candidate07；后续验证使用准确 SHA，不以相同 version 字符串混淆 04d/05/06/07。更广生命周期和整图表现继续在实际集成中检验。
3. **当前优先交付编辑器可用性，性能后置。** 普通模型 LoadJob、预览/缩略图、冷放置/历史操作、试玩、普通整视图重建、custom kit 消费者与 prefab 独立登记均已完成各自协议与 CPU/GPU/HTTP 验证（见上节）。下一段的入口是**切换默认 split 导入并迁移既有内嵌 native**：先把 `AssetLibrary.import_file` 的默认可选值切到拆分产物，用 `test_editor_split_import_flow_gpu` 的 `--import-only --reuse-contract` 复验重复导入复用与旧 embedded 会话升级，再按 `rmmo-model-review` 迁移入口大模型与受影响引用。历史只读报告 `editor_native_streaming_integration_readonly_01.json` 不是这些后续切片的验收证据，游戏 Initial 的独立账本也不能代替编辑器共用账本。着色/彩窗工作流仍在工作区未提交，不属于本切片。
4. 从入口大模型开始转换并按 `rmmo-model-review` 做受影响项验收，保持原像素默认策略。随后覆盖实际引用与角色原生产品。
5. 正式接入后再测 axel_town 加载、卸载、返回加载及 low，继续使用地图加载开始到当前需求区域完整就绪的计时边界。

## 2026-10-30 编辑器整合与实际 GLB 改名验证

本节更新上述默认导入的待办状态。当前工作区已启用原生几何与独立纹理的默认导入；复用导入结果时也要求有 texture_table，避免继续复用旧 embedded 会话标记。默认纹理保持原像素，不改变用户选择。UI 文件选择器允许导入外部源文件；HTTP MCP 的 `import_model(path, pack_root)` 继续遵守资源根约束，检查外部引用路径后才进行离线导入。`relink_model(id, asset_id)` 选择已经登记的原生模型，使用私有准备事务，保持保护、撤销和保存语义。两项工具同步 3D schema、发现和实现。

另复现并修复原生模型复制入口：旧代码直接提交新记录，没有传递准备好的原生模板，删除 GLB 后复制产生缺失占位。现在复制含模型依赖的记录先准备私有目标，完成后一起发布记录、节点和历史；MCP 等待该事务，UI 显示准备状态。普通无模型依赖的复制保留现有路径。

所有新测试使用默认 4.8 beta1 candidate07，exe SHA `dabba1322488f959bddbd1d20ebdf40ee788c918c1a8b193a533d0472efb7375`。冻结项目为 e1cb061b 加本专项工作区脚本；不覆盖或混入受保护的其他会话改动。证据根：`D:/code/rmmo_runtime/review_artifacts/godot_4_8_adoption_20261029_01/editor_usable_20261030/`。每次包含 freeze.json、parse.log、engine.log、runner.json，保留具体脚本 SHA。

| 测试 | 已通过 | 证据目录 |
| --- | ---: | --- |
| 真实套件导入、删除两份 GLB、冷开、预制件预览/缩略图、F5/HTTP 试玩、MapLoader、释放归零 | 60 | kit_01 |
| HTTP 导入/重新关联、删除 GLB、复制、保护失败无副作用、撤销重做、保存重开 | 49 | import_http_03 |
| 实际自动瓦片 UI、取消、邻接、手动脱离、保存重开 | 17 | autotile_ui_01 |
| 共享记录准备上下文 | 51 | context_cpu_01 |
| 私有整视图重建 | 25 | rebuild_cpu_01 |
| 同一内容根内预制件登记随包移动，移走原登记仍可用 | 30 | prefab_cpu_01 |
| 别名并发共享生产、各自身份检查及释放 | 67 | alias_cpu_01 |
| 选择移动与历史回归（套件编辑补丁后重跑） | 20 | selection_cpu_02 |
| 实际增量编辑、原生模型放置/删除/撤销、未变节点与碰撞/合批身份保持、保存重开（套件编辑补丁后重跑） | 81 | incremental_gpu_02 |

这些成功样本均零脚本/引擎诊断。历史 kit 保存失败来自测试用无效高度构造；修正为正式 AutoTileRules.configure 后通过。历史 import_http_02 保留复制缺失的修复前证据，不以修复后的样本覆盖它。

`incremental_cpu_01` 被误以 headless 运行：真实模型导入失败后测试继续读取 entry，报错并在 180 秒超时。保留原日志；测试已补失败原因与提前退出，在独立图形桌面重跑 `incremental_gpu_01` 81/81。未将该 headless 失败计入通过数，也未声称 headless 原生导入已经解决。

### 用户提出的实际素材 GLB 改名检查

直接选用默认素材库里已经导入的三件模型及其现有原生产物，未重新导入或转换模型：

| 模型 | GLB 文件 SHA / 文件名（省略 .glb） |
| --- | --- |
| banner_streetlamp | 095d9b9daa40576e8457d359861ffa002aea186c639b05a097664bc0169ab3de |
| 圆拱石砌门套 | fe4c4307d64e2f96ace70887725d5f789196b1b0f79ecd2516a5dc26edcf6c9e |
| 写实阔叶橡树·宽冠粗干 | 52968b76c466f7ab198e8c47d2c724980b0067783567eb264f90fe1fa467f057 |

外部驱动 `probe_existing_03.py` 先启动源文件正常的独立进程，然后把三件真实 GLB 改名为 `.withheld_editor_20261030_<pid>`，再启动新进程。正式地图和模型产物不改写，新增地图/缩略图在外部测试目录。finally 恢复文件，并核对 SHA。`existing_glb_rename_receipt_03.json` 证明三件均已恢复且内容完全一致，没有遗留改名文件。

- 正常源文件：`existing_baseline_03`，56/56，零诊断。
- GLB 改名：`existing_withheld_03`，56/56，零诊断。
- 两次冻结脚本 SHA 完全一致。检查包括原生登记、真实预览、新缩略图、HTTP 放置/复制/撤销、保存/重开、试玩/返回和源文件仍未被重建。
- 试玩实际网格数量分别为路灯 5、门套 1、橡树 4；改名前后相同。运行时会将组件展开为 `uuid__part` 同级节点，测试同时检查这些节点的真实 Mesh surface，不能用空父节点或空数组 all() 冒充实际渲染验证。
- 01/02 的失败样本保留：初版测试错误地从 list_assets 读取未暴露的 asset_path，随后又把运行时的组件展开误判为网格缺失。这些是测试断言缺陷，不记作修复了生产 GLB 回退。最终 03 使用相同修正后的测试完成前后对照。

本组验证证明这三件实际素材和列出的编辑/试玩入口已不依赖 GLB，不代表全库、全部模型类型或旧 embedded 纹理已迁移完成。原生登记里的 `.glb` 可以是逻辑资源键，不能仅凭扩展名判定运行时仍打开 GLB。

### 自定义套件邻居变体的补充修复

实际改名测试后，又把套件构造成相邻格，并删除全部原始/导入 GLB、清除全局强缓存，复现删除与手动脱离时邻居丢失原生模板的缺口：`kit_edit_red_01`。原因是这些旧编辑入口直接 `_commit_records` / `_refresh_records`，没有经过共享模型准备；split 模型同步 miss 明确拒绝加载，因此派生网格缺件。

现在含自定义套件的邻接变化使用私有文档：先计算变体和准备原生依赖，再发布记录、网格、碰撞与单次历史。覆盖删除、单物件变换、选择变换、UI 旋转和实际 Gizmo 拖拽；拖拽结束先恢复临时姿态，再提交私有目标，避免失败留下半次编辑。3D MCP 的删除、单物件变换和选择变换等待同一事务的最终结果，保留原保护检查。

`kit_edit_full_03` **100/100、零诊断**：包含相邻格删除与移动、两类 MCP 变换、UI 旋转、真实 Gizmo begin/update/finish 与取消、撤销、临时移走原生登记后的无副作用失败，以及原有预览/缩略图、F5/HTTP 试玩、MapLoader 和所有资源账本归零。`selection_cpu_02` 20/20，最终普通编辑回归 `incremental_gpu_02` 81/81。`kit_edit_full_02` 的 UI undo 被正确拒绝是测试只等待 saving、未等模型事务；补为同时等待操作队列后通过，没有修改保护规则。`kit_edit_full_01` 的测试辅助函数不存在导致 parse 失败，保留记录。

### 尚未关闭的编辑器边界

- 自定义套件上述编辑入口已按前节关闭；自动笔刷真实鼠标交互的 17 项仍是内建件，后续新增套件类型仍应检查其实际变体及碰撞，不能把当前两件 cliff 模型当作所有类型的外观验收。
- 既有 embedded 原生模型尚未按模型验收流程全部转换成独立流式纹理；本次改名检查没有改动三件正式模型的几何、材质或导出字节。
- 原生 prefab 的本轮可移植范围是同一 content_root 内的资源库位置变化，完整跨根导出不是本轮验收结果。
- 当前继续优先补齐编辑器可用性，上述边界关闭前不恢复独立性能专项。


## 2026-10-30：继续复查 4.8 编辑器适配

新增复查记录见 [editor_godot48_adaptation_review_20261030.md](editor_godot48_adaptation_review_20261030.md)。已复现并接通导入材质首次使用、地图重开及缓存失效后的流式纹理路径；真实 UI/HTTP 回归 69 项、并发发布回归 30 项、可变源身份回归 37 项通过。旗帜 CPU 合成、alpha coverage 导入选项、可选接触阴影等分别记录为后续缺口，没有宣称本轮已完成全部 4.8 特性适配或整城性能改善。

### 2026-10-30 后续实施

前节列出的旗帜 CPU 合成、可选 alpha coverage 和本机画质开关已完成本轮适配。同步补齐预制件的纹理产物闭包，以及真实风场准入；并用 candidate08 修复内置透明裁切材质的冷流式反馈死区。机制、测试与保留边界统一见 [4.8 适配复查](editor_godot48_adaptation_review_20261030.md) 的后续实施节。未批量改写正式素材，旧 embedded 资产迁移和跨根导出边界没有因此自动关闭。
