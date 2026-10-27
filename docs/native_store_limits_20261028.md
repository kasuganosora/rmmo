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
