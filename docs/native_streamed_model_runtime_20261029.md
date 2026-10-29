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

## 后续顺序

1. 旧 operation → 新 Initial 的**已完成 owner 入站复用已完成**，结果见上节及 B 的 `initial_native_inbound_reuse_handoff.json`。并发 operation 中尚未完成的 producer 仍各有自己的池，尚无跨 operation 的全局在途 single-flight；不把本轮完成票据复用说成该问题也已解决。也不能因 `start` 时目录为空就整次跳桥，旧 operation 可能在 metadata 就绪前发布 owner。后续可考虑请求抵达主线程时，以两个目录当前均空作 O(1) 全 miss 回复，保留现有取消与 metadata 退役合同。
2. 引擎排队 I/O 的 owner、shutdown 及预览就绪 API 已按上节复现、修复、回归并安装 candidate07；后续验证使用准确 SHA，不以相同 version 字符串混淆 04d/05/06/07。更广生命周期和整图表现继续在实际集成中检验。
3. 编辑器 LoadJob、PreparedModelOwnership、预览/放置和 TargetScenePrefetch 接入同一独立纹理准备与释放协议；当前 UI/HTTP MCP 还没有据此完成导入、保存重开验证。下一生产集成顺序按 B 的 `editor_native_streaming_integration_readonly_01.json`：先用无 GLB、空场景/弱缓存复现冷打开、预览、缩略图和放置；再以编辑器既有共享账本接异步准备、世代取消和主线程所有权，区分只需几何的消费者；引擎生命周期就绪后做 GPU、UI 与真实 loopback HTTP MCP 的放置/撤销/保存冷重开。全部冷消费者通过后，才切换默认 split 导入并迁移既有内嵌 native。该报告是 `9eb7a9fa` 上的只读审查，未修改或验收编辑器，不应把游戏 Initial 的独立账本直接当作编辑器并发共用账本。
4. 从入口大模型开始转换并按 `rmmo-model-review` 做受影响项验收，保持原像素默认策略。随后覆盖实际引用与角色原生产品。
5. 正式接入后再测 axel_town 加载、卸载、返回加载及 low，继续使用地图加载开始到当前需求区域完整就绪的计时边界。
