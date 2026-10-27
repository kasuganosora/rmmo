# 完整材质原生入口与重复加载修复（2026-10-27～28）

接续 `axel_trusted_native_material_reader_20261027.md`，基线为已推送的 `8c7f1023`。本轮完成原生元数据与运行时入口接线，并复现、修复了一处完整模型二次读取。当前证据主要是组件和合成带纹理模型的真实 GPU 集成；**不是 axel_town 整图加载/low 的新成绩**。正式资源尚未补齐，不能宣称完整材质阶段结束。

## 改动和工作量

- `NativeModelProduct.read` 统一白模与完整材质的元数据入口。完整材质从已发布 native index + footprint 取得身份、离线边界及保守预算，不访问可选 GLB；白模委托原 WhiteMetadata。full 的 budget 来自自身 footprint，带 `native_product_kind=full`，不借用白模估算。
- 现有 footprint 增加小型 `model_metadata`（边界、源 JSON 身份和历史长度）。新导出必须包含它；既有产品可以显式离线 `refresh_bounds`，仅补描述符，不改变 SCN。运行时缺失就报告缺少可用原生产物，禁止导入 GLB。离线入口允许读源文件，仍保留源更新时的绑定条件。
- MapLoader、依赖目录、ModelParse、Deferred、AssetLibrary、桥梁/城防及目标场景预加载改用完整原生产品身份。初始和返回加载沿用固定 candidate 的预算、取消与资源回收；editor 非 native-only 导入路径仍保留。
- ModelParse 在完整材质游戏模式下直接使用 native 预算及固定 candidate；不先打开 GLB 做原始估算，也不因 probe 关闭 footprint 优化就切回旧 generic reader。缺产物在准入前失败，失败结果仍记录去重数及零线程/零占用。
- MapLoader 只缓存本次加载的元数据。有效 warm 目录的远端模型预算直接复用；不为未访问区域无条件打开全部产品。遇到旧白模或未标识的预算才补 full metadata，实际派发仍以产品候选重新确定准入。
- 仍有既有的同步 native cache miss，尤其桥梁/城防 kit；本轮未把它伪装成已经纳入统一后台预算。后续须把这类工作提前放进上游准备，再由主线程复用结果。

## 真实复现的重复读取

完整材质 Deferred 返回私有 scene 后，正式发布调用 `AssetLibrary.cache_scene`。它将节点重新打包为 PackedScene，却丢失了原生来源标记；后续 `instantiate(path, true)` 把刚发布的模板当成非 native，重新打开、解码并替换缓存。

`candidate_02` 在两个不同逻辑源键上均复现，**86 通过、2 失败**，日志无引擎/脚本错误。修复让重打包模板继承 accepted native owner 的 `compiled_asset_validated`，并记录该场景已经执行材质重绑；没有给任意 raw scene 添加标记，也没有用路径永久缓存掩盖失效。原有 source digest、替换回收和模板所有权保持。

修复后原用例保持模板对象身份，材质/图像仍可用，清空返回结果并驱逐缓存后 owner 释放。当前只证明每个受测返回模型不再发生这次重复读取；整图调用数及主线程打包成本仍待下一轮测量。

## 测试证据

元数据红测 **2/1**；实现后 `test_native_model_product` **20/0**，覆盖缺 GLB、旧 footprint 离线补充、full 预算、固定产品身份、预加载文件身份、白模委托。`test_white_native_asset_metadata` **14/0**。

`test_full_native_without_source.gd` 使用含真实内嵌 PNG 和材质的两个临时模型：离线编译并保存 native 后，物理删除 GLB。对照基线保留同一新 producer/helper，以确保输入包有效，只替换五个旧上游文件为 `8c7f1023`：MapLoader、ModelParse、Deferred、AssetSourceMetadata、MapDependencyIndex。旧入口 **24/4**，cold hints、初始加载及剩余身份路径失败；**旧 ModelParse 在该夹具中能通过，不把它宣称为红测**。

候选第一次 **79/3**：三项为测试误用了白模直传 PackedScene 的假设，以及 fortification 缓存键里把默认 `terrain_grade=[]` 写成 `{}`；原日志保留，修正测试合同后发现上述真实二次读取，得到 **86/2**。修复生产 cache provenance 后，扩展远端登记检查，最终 **92/0**，无引擎/脚本错误。

92 项涉及真实 MapLoader 初始准备、无注入估算器的 ModelParse 去重与预算、Deferred 冷返回/复用/驱逐、AssetLibrary 冷缓存与预览、bridge/fortification/world-document 路径、目标预加载及缺产品失败。有效 full 远端预算两条登记产生 **0 次** metadata helper 调用；白模预算和不完整预算各调用一次真实 helper 取得 full 预算。它不是完整地图或实际走路路线。

后续 headless 回归：白模缺源元数据 **43/0**、native budget **32/0**、source retry **153/0**、model parse **25/0**、dependency index **42/0**、build handoff **17/0**、initial prefetch **35/0**、cold prefetch **41/0**、cold reference index **20/0**。trusted native 最初 **100/2**，因为新增准入前失败返回遗漏了旧 API 的统计字段；保留早失败并补齐结果合同后原断言 **102/0**。此失败不是已证明的 raw 导入或泄漏，不将补字段描述成性能收益。

既有 `test_native_without_source.gd --gpu` 白模真实管线回归 **86/0**，包含 bridge、fortification、Deferred 返回、缺源与预加载，日志无引擎/脚本错误。记录为 `full_native_integration_20261027_01/white_gpu_01/godot.log`。

外部证据根 `D:/code/rmmo_runtime/review_artifacts/`：

- `native_full_metadata_20261027_red01/`、`native_full_metadata_20261027_green02/`。
- `full_native_integration_20261027_01/`：baseline、candidate_01、candidate_02、candidate_03 各自原始日志和版本身份。
- `native_full_headless_regress_20261027_01/`：完整回归及 100/2 失败。
- `native_full_headless_regress_20261027_trusted_green01/`：102/0 复测。

## 下一步仍属于原目标

先准备与当前 axel_town 内容对应的完整材质测试包。现有 map-texture-stage 夹具重写过材质，不能当作正式完整材质地图。

当前 staging 在 `D:/code/rmmo_runtime/review_artifacts/axel_full_native_staging_20261027_01/`：44/44 SCN 源/副本 SHA 一致，bounds 已离线补齐；5/5 源 GLB SHA 与文件名一致，缺失产品已通过现有离线编译器构建。49 个路径与地图清单一致；`staging_manifest.json`、`bounds_migration_report.json`、`missing_build_report.json` 分别保留复制、迁移和构建身份。5 个源文件保留在 staging 的 `authoring/assets/`，运行时逻辑模型路径下 GLB 数量为零。正式资源根未因此改动。

五件新增导出按 `rmmo-model-review` 完成受影响项复验，逐件报告入口是 `model_review_manifest.json`：sign_potion、frame_2、sign_general、长木围挡、暖砖长花池的节点、变换、网格、材质、解码纹理、LOD 和 extras 记录一致；源与实际 native SCN 的固定近/中/远/细节及风时刻对照共 60/60 帧原始像素一致。花池另补明暗背景、接收投影地面及两个风时刻，24/24 帧一致。提交查看的图像为原尺寸有损 WebP Q90，SHA/参数记录在清单和逐件报告中。花池砖材在测试灯光下偏亮是源和候选共有的表现，本轮没有改材质掩盖它。

这证明受检格式转换保持内容；不是五件模型的设定美术重新验收，也不是连续动画、真实地图光照或编辑器交互完成。随后已经完成 2369 条记录的隔离地图重定位和一次 full core-streaming 测试，分别见 `axel_full_native_fixture_20261028.md` 和 `axel_full_native_pipeline_20261028.md`：入口 39.079 s、需求完整就绪 65.779 s，初始公会 native 读取 29.466 s，不能视为性能达标。实际图像记录也确认本轮 native 内嵌图像仍是未压缩 RGB/RGBA 加 mip；前轮地表 DDS 优化没有自动覆盖这些模型。图像字节数与 footprint 保守预留均不能冒充实测显存。

**正式资源迁移尚未完成，当前分支不能凭隔离测试视为正常游戏已可用。** 2026-10-28 的只读核对发现，正式根下 44 个既有 footprint 均缺少新增 `model_metadata`，另 5 个 full index 缺失；默认游戏使用 full + require_native_products，会沿原生元数据入口拒绝这些旧产品。这是源码和实际文件证据，尚未运行正式地图取得失败日志。必须将已经验证的元数据补充与五件产品离线发布到正式根，再验证正常入口；不以恢复 GLB fallback 掩盖迁移缺口。普通编辑器非 native-only 路径不同，仍有源 GLB 时可能走旧导入，但不因此宣称编辑器适配已完成。

完成后用同一边界测加载、卸载、返回、长帧、1% low 及工作量，确认本轮取消二次读取的实际命中。模型内嵌材质尚未接入地表/道路 DDS sidecar，须分别测其图像格式、解码和上传成本；不能把前轮 DDS 收益外推过来。同步 kit miss、主线程重打包、冷目录预制件重复准备、此前 51.133 ms 边界帧均仍待证据闭环。

游戏材质关键路径稳定后，继续内容编辑器与当前 3D MCP 适配及优化，覆盖缓存失效、导入、共享预算/回收、撤销、保存重开和真实 HTTP MCP 调用。目标保持进行中。
