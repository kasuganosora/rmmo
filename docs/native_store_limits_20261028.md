# 原生产物存储上限审查（2026-10-28）

用户要求导入后的模型只消费 native，并明确同意移除 8GB 限制、继续检查无依据的硬上限。

## 已修复：累计 8GiB 配额

`compiled_asset_cache.gd` 原先在完成 GLB 解析、场景准备、native 序列化与 SHA 后，逐个打开目录内的 SCN 累加大小；超过 8GiB 就删除刚生成的临时产品并返回 `cache_capacity`。重复尝试会重复全部生成工作。此限制作用于所有地图、旧生成版本和测试产物的磁盘总和，既不是当前地图大小，也不是内存准入预算。

当前目录 358 个 SCN 共 8,732,544,285 bytes（8.132816GiB）。当前 index、previous 与 footprint 引用的并集没有完全无引用的 SCN；只删除能够证明过期的文件不能解决问题，也不能把未知所有权当作垃圾。详细只读盘点在外部 `D:/code/rmmo_runtime/review_artifacts/native_cache_capacity_20261028_01/REPORT.md`。

已移除全局配额及全目录统计。产物是必须保留的导入结果，不能在普通加载时丢弃或回退 GLB。仍使用原内容寻址文件、原子索引发布、单产品大小约束和真实磁盘错误处理；运行内存由独立的 admission ledger 管理，没有扩大 worker/完成队列或关闭预算。新索引增加 `source_path`，用于后续确定所有权；没有替历史未知产品补写来源、删除或改指向。

## 复现与回归

`tools/test_native_store_capacity.gd` 在隔离资源根用一个逻辑大小 9,663,676,416 bytes、实际占用 65,536 bytes 的 sparse SCN 代表既有产品，实际导入一个有纹理的小模型。该占位文件从未被解析或加载进内存。

- 旧 producer（取自 `341094e0`）确切返回 `cache_capacity`，预期成功的两项失败。
- 新 producer 6/0：导入成功、native 读回、重复导入复用、来源记录、历史文件不变。
- 测试 SHA：`21375e5b304d1ee679afec0682d88af272ab0b9fe25bb66422e093652519f49f`。
- GREEN 引擎 SHA：`20d25131e638bb6cafa0c285e2cddbf09eb6e7e528ee4f8f22dc566adfd8fde8`。
- 两次运行各自前后生产脚本身份一致；通过私有桌面 OpenGL 运行，保留 TAA 不适用警告。这是功能红绿，不是整图时间或低帧收益样本。
- 证据：`D:/code/rmmo_runtime/review_artifacts/native_store_capacity_20261028_01/red_02/`、`green_02/`。
- 首轮夹具使用 Python truncate 意外分配数据，实际占用断言在引擎启动前终止；删除了该唯一测试占位文件。第二轮采用 sparse 后 seek/write 并先确认实际分配，失败样本没有算作引擎/产品问题。

## 后续限额审查边界

继续逐项区分格式/合法结构上界、内存准入、调度时间预算与任意历史大小阈值。没有依据的硬上限应移除或改成真实资源约束；不能把真实预算一并去掉。当前没有宣称单产物 1GiB、节点数量等其他边界已经全部审查完成，也没有因此完成旧素材迁移或全编辑器交付。

## 已修复：材质库目录静默截断

`surface_material_library.gd` 的旧递归遍历在深度大于 8，或结果达到 2048 后直接停止进入后续目录；没有报告不完整。批量查找还在扫描到 2048 个 JSON 名称或 256 个目录后重新做全量遍历，同样无法找回被深度/数量规则隐藏的内容。

改为保持原顺序的迭代深度优先遍历，移除上述内容截断及无收益的重复扫描回退。UI 和 MCP 沿用同一素材库业务实现。隐藏目录、链接、资源根与越界 ID 规则保留；没有放宽图片解码预算。

- 新隔离测试 2050 个根条目加后续子目录条目、12 层路径：旧 1/6，新 6/6。
- 更新旧测试中“被截断才正确”的断言后，现有窄目录查找、重复 ID、共享/本地包、无效路径、根变化等回归 89/0。
- Windows junction 保护通过；普通文件 symlink 因本机权限不足跳过，没有将跳过项计为通过。
- 红绿及旧断言失败证据保留于 `D:/code/rmmo_runtime/review_artifacts/editor_material_catalog_limits_20261028_01/`。

本轮未新增文件监视或后台扫描取消接口；现有材质面板退出仍等待后台目录任务完成，该调度边界与静默丢内容问题分开记录。

## 已修复：单产品 1GiB 与 65536 节点门槛

继续检查发现，producer、固定候选 reader、footprint、编辑器 ownership 和预取身份共用了单个 SCN 的 1GiB 配额；producer 的场景检查、ownership 图遍历、几何复用和显式导入 bounds 又各自限制了 65536 节点。这些数量不代表已测得的内存成本。特别是几何复用已经持有完整模板，却仍按节点数量拒用，会使合法产品走额外准备路径。

已去掉上述门槛。文件长度继续要求是正数、与实际文件相等，并能由 JSON 数字精确表达；`MAX_JSON_INTEGER=2^53-1` 是索引编码的精确整数边界，不是新的存储配额。实际内存准入 envelope、去重、图类型约束、来源/产物身份和严格 native 审计均保留。没有取消 worker 或显存预算。

引擎源码核对：`core/io/resource_format_binary.cpp` 使用 64 位资源偏移；`scene/resources/packed_scene.h` 的名称索引为 18 位，节点引用采用另一套标志编码，并无这两处项目门槛。另有真实限制必须区分：`FileAccessCompressed::_close` 将解压长度写入 32 位字段，`open_after_magic` 同样读取 32 位；本轮没有改造该压缩格式，不能据此声称任意大场景都可压缩或装入内存。

证据目录：`D:/code/rmmo_runtime/review_artifacts/native_product_boundaries_20261028_01/`。

- 同一 `tools/test_native_product_boundaries.gd`：旧逻辑 **5 通过 / 8 失败**；新逻辑 **14/0**，各自运行期间 scripts/tools 身份不变。
- 文件夹具由引擎保存真实小型未压缩 SCN，再追加 sparse 零填充至 **1,074,790,400 bytes**，实际分配 **131,072 bytes**；内容寻址 SHA 与索引匹配。严格读取、实际实例化、ownership 和预取全部通过，逻辑 GLB 路径不存在。它证明旧文件尺寸 gate 的问题，不代表已经压测等量真实几何、GPU 上传或 RSS。
- 另一个实际 SCN 包含 **65537 节点**，保存、读回、实例化到最后一个子节点均通过；producer schema、ownership、几何复用不再拒绝。显式导入 bounds 能包含超过旧门槛位置的最后一个 mesh。
- 使用同一 GREEN 引擎；headless 无图形资源。首次 seed 夹具函数名与 GDScript 内建 `seed` 冲突，parse 失败保留；改名后的 seed 才用于红绿，不将该夹具失败归为产品问题。

白模专项退役后扩展并重跑为 **23/0**（`white_mode_retirement_20261028_01/boundaries_02`）：增加小数、负数、非有限值、字符串和 JSON 不精确整数拒绝；用实际含 65537 节点的 GLB 经过 `Manifest.read` 验证最后一个 mesh 的 bounds。该 GLB 的 JSON 在既有字节合同内，未宣称取消了 GLB JSON 的 4MiB 上限，也未将空节点场景的成功当作大型网格性能结果。

其余审查：贴图导入的 16MiB/4096 限制与 consumer 的 4096 解码、DDS 和缓存合同相连，尚未完成整链跨阈值验证；地图记录/建筑上限也属于持久化合同，不能仅放开某个 UI 入口。缩略图 LRU、运行内存准入和每帧调度预算用于控制资源占用，与静默隐藏内容的目录限额分开评估。以上未处理项不宣称已解决。
