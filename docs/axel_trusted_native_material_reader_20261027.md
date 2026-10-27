# 完整材质原生读取：取消重复认证（2026-10-27）

接续 `axel_pending_snapshot_ownership_20261027.md`。目标仍是降低真实地图完整就绪耗时和 low；用户补充的后续任务为：**游戏侧材质优化完成后，适配和优化内容编辑器与当前 3D MCP**，保留导入、撤销、保存重开和派生资源更新语义。本轮提前处理共享 reader 对编辑器造成的回归，不等于编辑器专项已经完成。

## 本轮生产改动

已发布资源包由运行时直接信任。`CompiledAssetFootprint.candidate` 的 trusted 路径从原生索引和预算描述符取得固定产品身份、版本和保守驻留预算；不再打开原 GLB 取长度，不计算当前生成器源码指纹、描述符 body SHA 或重新遍历统计。`CompiledAssetPreparation.read` 的 trusted 路径不再重复计算整个 SCN 的 SHA、枚举依赖、递归检查全部资源存储属性或打开可选 GLB；直接读取已经准入的固定产品。

仍保留真正影响执行的条件：命名空间/固定产品路径、格式版本、正数且有界的预算、索引与预算描述符属于同一产品、实际产品存在/长度及 PackedScene 加载结果。取消、资源所有权、主线程回收和独立预算下的重试不变；小 native 预算不得进入 GLTF 导入。strict 调用可继续用于显式离线审计。

游戏包与编辑器可变源分开：编辑器传入 `mutable_source=true`，同路径源重新导出后不得发布旧几何，仍返回持有原生资源的重试包，由主线程先回收再重新准入。编辑器转换规则版本也必须在一次加载操作中保持一致；预算描述符的源码变化本身不再使同格式预算失效。生成规则相关回归另见下节后续记录。

本改动接入 ModelParse、Deferred 的 candidate 路径及编辑器 lookahead/retry。**普通 `Compiled.read`、完整材质 MapLoader 元数据入口和部分复用路径尚未完成改造，不能宣称游戏全链路已经无 GLB。**

## 复现与回归

新增 `tools/test_trusted_native_preparation.gd`。旧 reader 在可信产品路径仍计算 payload SHA，且无 GLB 时返回 source_missing；原始红测 **23 通过、2 失败**，改动后同用例 **25/0**。扩展版本 **78/0** 覆盖无源读取、历史生成器、预算身份/版本、缺产物、strict 审计及 coordinator 去重；coordinator 注入内存估算器，不能替代完整 MapLoader 无源集成测试。

随后用真实 `EditorLoadJob._parse_native_asset` 复现同长度、普通文件名的源变化：首次候选 **81/1**，旧资源被错误接受。增加 mutable source 重试后 **82/0**；扩展真实 editor 初始 lookahead、重复项去重和 cached retry 后 **95/0**。这些轮次为按顺序扩展的测试，不能相加当独立总数。

既有 `test_editor_load_preparation` 最初失败。隔离 HEAD 与候选使用同一个私有 content root 对照，确认旧断言分别使用了过期的 publication 预算、normal texture key 和 trusted 模式的身份含义。只修测试后两版均 **131/0**，stderr 空；保留原始失败。可信纹理标记是路径身份，不是文件内容认证，也不能因此声称编辑器同路径纹理修改的缓存失效已通过。

相关回归：editor residency **106/0**、lanes **92/0**、native source retry **153/0**、native budget **32/0**、model processing contracts **37/0**、model parse preparation **25/0**；native without source 的 headless 元数据项 **43/0**。没有用 exit=0 掩盖脚本错误。

独立 review 发现转换规则变化而源文件不变时，editor 还会接受旧 generator 产品。真实初始 plan 与直接 mutable worker 红测为 **95/2**。修复后，editor 惰性取得一次 product generator 快照并传给 candidate/worker，cached retry 复用此快照，无模型候选时不计算；游戏 published 路径不增加此检查。最终 **102/0**，再跑 source retry **153/0** 和 editor **131/0** 均通过。转换规则在进行中的加载操作里热替换不属于新增合同。legacy 回退只生成内存场景，不自动持久化新的原生产物。

该组 `green01` 曾因测试把 source.glb 写成普通字符串，在正确转入 legacy 后触发 GLTF 解析错误，**96/1**，已保留失败；将夹具改成有效最小 GLB 后才计通过，不把解析错误隐藏掉。最终记录在 `editor_generator_fix_20261027_green03/` 与 `editor_generator_fix_20261027_regression01/`，最初版本缺口在 `editor_generator_fix_20261027_red01/`。

证据位于外部目录 `D:/code/rmmo_runtime/review_artifacts/`：

- `trusted_native_preparation_red_20261027_04/`：原始红测。
- `trusted_native_preparation_suite_20261027_07/`：组件回归与批处理原始日志。
- `editor_mutable_native_red_20261027_01/`：真实编辑器可变源红测。
- `editor_native_regressions_20261027_04/`：既有编辑器测试最初失败。
- `editor_load_baseline_20261027_01/fixed2_result.json`：旧/新两臂 131/0、输入身份及原始日志。

## 真实含材质产品 GPU 对照

使用历史 axel 隔离夹具中的旗帜模型，复制既有 SCN 字节到外部独立目录，没有重新导出或改变材质、几何。SCN 为 **34,654,419 字节**，SHA `347f7c6722514d50a8597ebf7f019a3c7e496082aae3572eceab8d1a49426d35`；索引和 footprint 仅离线改为夹具逻辑路径，保留历史生成器、产品身份与预算。逻辑 GLB 文件不存在。

engine09、Windows Vulkan Forward+、RX 7900 XTX，使用 `run_godot_background.py` 独立桌面。比较直接 `ResourceLoader.load` 与 trusted candidate/reader，两者均为 **4 节点、2 ArrayMesh、6 surfaces、11 个不同资源**；节点变换、材质存储属性、纹理尺寸及资源共享拓扑一致。同相机 512×512 PNG 像素完全一致，确实有模型内容；提供给模型查看的副本为保尺寸 RGB 有损 WebP quality=90。测试退出 0、无脚本错误、前后引擎/记录的静态源码依赖/夹具身份一致，未 fallback。

夹具：`D:/code/rmmo_runtime/review_artifacts/trusted_native_real_20261027_01/`。结果：`D:/code/rmmo_runtime/review_artifacts/trusted_native_real_sample_01/`，包含 launch、comparison、前后身份、原始图与日志；WebP 转换参数及 SHA 在 `preview_q90_02/manifest.json`。

这是**单个既有产品的读取等价性**，不是当前地图完整材质覆盖、原 GLB 视觉验收或加载时间收益。身份扫描预热了文件缓存，本轮不将其 wall time 当性能样本。

## 单产品 reader A/B/B/A

另建两份外部源码 overlay，只替换旧/新 `compiled_asset_preparation.gd`，每臂新进程并串行运行。相同 engine09、同实际源文件与产品，测试 candidate 的 generator 两臂均手工设为当前值，以排除历史生成器拒绝；没有修改正式索引。每进程连续读取 3 次，打开相同 LoadTrace，不执行 private preparation，计时外同步释放资源。身份扫描会预热文件缓存，**新进程首次读取不等于冷 IO**。

| 顺序 | reader | 首次 read ms | 进程内后续 read ms |
|---|---|---:|---|
| A1 | HEAD 旧版 | 663.894 | 381.199 / 413.157 |
| B1 | 候选新版 | 500.861 | 197.632 / 234.658 |
| B2 | 候选新版 | 589.392 | 277.625 / 312.208 |
| A2 | HEAD 旧版 | 646.155 | 366.087 / 415.829 |

首次读取各 2 个样本：A 中位 **655.025 ms**，B **545.127 ms**，配对 A1−B1 / A2−B2 差值 **163.033 / 56.763 ms**。进程内后续各 4 次：A 中位 **397.178 ms**（366.087–415.829），B **256.142 ms**（197.632–312.208）。不计算小样本 p95，也不据此承诺整图节省多少秒。

旧 reader 的 `compiled.payload_sha` **6 次、928.859 ms**；新 reader **0 次**。`compiled.source_identity` 两边各 6 次，总计 A 0.095 ms、B 0.020 ms；`compiled.native_read` A 1859.367 ms、B 2107.956 ms，说明读取本身仍有波动，不能把总差额全归于单个子阶段。`compiled.read` 包含子阶段，不能相加。未单列的余量不直接归因资源图检查。

4 个进程均退出 0，日志无脚本错误，12/12 读取成功、清空 packet 后 PackedScene 弱引用均释放。各臂前后源码/引擎/输入身份一致。证据：`D:/code/rmmo_runtime/review_artifacts/trusted_native_reader_abba_20261027_01/`；这是实际产品 reader 微测，不包含候选准备、完整地图、发布/碰撞或帧耗时结论。

## 未解决与下一项

1. 完整材质游戏入口仍有 white-native 专属条件：MapLoader 的 cold hints/源身份/near-first、ModelParse candidate 之前的原始内存估算、Deferred 与 AssetLibrary 的复用和 cache miss。需要贯通完整材质 candidate 的 source identity 和预算，缺失时报告产物缺失，不能退回 GLB。
2. bounds 可从同源的既有离线数据复用，但**不得用白模 memory 预算覆盖完整材质产品**。真实 MapLoader 无源、共享模型卸载/返回、bridge/fortification 与跨场景预加载均需实际覆盖。
3. 49 个非 prefab 模型路径中有 44 份完整材质 native 产品、5 份缺失：sign_potion、frame_2、sign_general、长木围挡、暖砖长花池（名称来自同包 prefab label）。只读核对当前正式 map SHA 与历史审计相同，2,369 record UUID/次序一致，同 map SHA 的 hydrated path audit 与夹具 49 路径无差集。另有 6 个 prefab 石桥实例不计入这 49；隔离夹具重写了路径和材质，不能当正式内容的字节等同副本，也不证明所有动态依赖。所需缺失产物仍要离线补齐。
4. 前轮 B2 卸载 51.133 ms 未取得同帧调用栈。采样 monitor 错位不能据此归为 OS；仍须定位。当前生产 reader 工作量减少不能替代地图 low/FPS 收益证据。
5. 模型内嵌材质与现有 DDS 路线不能混算：`Compiled` 的 GLTF append → `Io.generate_scene` → bundle/compress PackedScene 链没有调用 `SurfaceMaterials` / `PrefabTexturePreparation` 的外部 DDS sidecar 读取；`ModelTextureCache` 当前只 stamp 像素身份和弱引用共享。SCN 序列化压缩不等于 GPU 图像压缩，旧产物实际 image format 仍须单独取证；footprint 的 gpu_rgba_bytes 也只是保守预留，不是实际 VRAM。后续按真实材质 slot、去重图像 format/mips/data size 及模型上传数据定位，不能把地表 DDS 收益外推为完整模型收益。
6. 游戏材质路径稳定后，进入内容编辑器和 3D MCP 的完整适配，特别是同路径纹理重导入后的缓存失效、共享去重、预算/回收及保存重开。目标保持进行中。

后续入口接线和 Deferred 发布后重复读取的红绿证据见 `axel_full_native_runtime_20261028.md`。后续组件通过不覆盖本节尚未完成的真实地图测量。
