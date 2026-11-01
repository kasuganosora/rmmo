# 世界地址 D1 编号目录与地址解析

2026-11-01。本批按[多地图设计修订 2](world_space_address_research_20261018.md)实施 D1，并提前接通旧地图使用数字编号所需的目录登记、独立撤销和原子保存。世界布局、接缝与连续跨图仍属于 D2–D7。

开发分支为 `codex/world-address-d1`，隔离工作区为 `C:/Users/luna/.codex/worktrees/world-address-d1/rmmo`。开始实施时拉取核对 `origin/main`，其与本地 main、分支基线均为 `6a1bf861973ea08af04a5ba2042587423862676c`。没有从 10 月 18 日的旧研究代码分支继续开发；仅带入设计文档，保留 main 已提交的性能优化和修复。

## 使用方式

打开“文件 → 世界地址与地图编号…”。选择资源包和地图，输入数字编号并登记，然后“保存所选目录”。该操作写入资源包根下的 `maps.catalog.json`，不改地图文件名、作者 `map_ref`、地形、物件或地图撤销栈。

新规范 `Map000123.gltf` 会提示编号 `123`，仍需显式登记；不能登记为其他编号。旧 `map.gltf` 通过登记关联数字编号，目录中的日期或 `v8` 不会被猜成 ID。地图必须有可验证的唯一作者根 `map_ref`；未满足的历史文件明确显示原因，本批不自动替换路径哈希或修复地图身份。

选择一个物件后可以复制其作者原点地址；开启胶囊行走后可以复制实际脚点地址。输入地址可只读解析，例如 `default:123:-32.01,5.125,100`。解析不会移动镜头、贴地、传送或授予通行许可。结果明确标记坐标锚点、目录是否已保存，以及世界布局尚不可用。

目录撤销、重做与地图历史分开；撤销编号登记会保留该编号占用，保存后形成墓碑。显式放弃未保存编辑重新读取有效磁盘目录，会话内仍保留曾使用编号的占用；未经保存的占用不会被描述为跨进程永久记录。关闭地址窗口可明确选择保留会话编辑；退出编辑器前必须保存或放弃脏目录，不自动丢弃。

资源包版本由已发现的 `pack_root` 明确选择。同 ID 多个安装版本不能由地址解析器按发现顺序决定。所属包必须有真实字符串 `metadata.id`，不将显示名、目录名回退或数字转字符串作为稳定身份。包被移走或身份改变后，旧脏目录仍可见，显式放弃只清理会话草案，不重新创建资源包或写回地图。

## 输入与保存合同

地图编号通过十进制字符串表示，规范值范围为 `0..9223372036854775807`，最多 19 位输入，前导零归一化。XYZ 保留 float64 数组，不提前转为 `Vector3`；每轴支持 `±1e12` 米的地址值，超限拒绝而不钳位。坐标往返以 0.001 米为上限，科学计数法、负数和小数可用；空字段、额外分量、NaN、Infinity、溢出及非零数下溢均拒绝。该地址范围不表示现有单精度渲染或物理已支持同样大的世界。

脚点适配读取角色当前有效直立胶囊的尺寸、形状偏移和变换，另提供脚点到角色原点的逆变换；不会改变角色节点。未沿用固定 0.9 米为通用常量，多个碰撞体、倾斜或不支持的缩放明确拒绝。现有运行时传送和移动逻辑未切换到新协议。

目录字段为 `schema_version / pack_id / maps / tombstones`；每条地图记录包含 `map_number / map_ref / path / path_scope`。包内路径为 `pack`，既有外部根 `maps/` 下的共享地图为 `shared`。所有读取与写入均检查允许的资源根和符号链接；目录和元数据输入有字节上限，地图/墓碑数量在读取、编辑、撤销和保存两侧一致限制。

修改使用期望编辑修订，保存同时要求期望磁盘 SHA；首次保存为空基线，使用不可覆盖已有目标的创建原语。已有目录使用项目现有的锁、暂存校验与原子替换。磁盘并发变化、包元数据变化、重复身份、损坏目录和文件名冲突均明确失败，保留原磁盘文件和未保存编辑。旧目录字节已被其他会话替换时，不再把旧映射报告为当前已保存映射。

## 当前 3D MCP

UI 与 MCP 复用 [world_address_tools.gd](../scripts/world_editor/world_address_tools.gd)，没有新增二维入口。以下工具已接入当前 3D schema 和分发：

| 工具 | 主要输入 | 语义 |
| --- | --- | --- |
| `list_world_maps` | 可选 `pack_id / pack_root / offset / limit` | 返回地图入口、编号、状态和独立目录文档修订；读取不自动登记 |
| `register_world_map` | `entry_id / map_number / expected_edit_revision` | 登记已发现入口，一笔目录历史，不自动保存 |
| `save_world_catalog` | `document_id / expected_edit_revision / expected_disk_sha` | 只保存指定目录 |
| `undo_world_edit`、`redo_world_edit` | `document_id / expected_edit_revision` | 当前仅支持编号目录历史；地图 `undo/redo` 保持原语义 |
| `discard_world_catalog` | `document_id / expected_edit_revision` | 显式放弃目录草案；不可用包只放弃内存状态 |
| `resolve_world_address` | `address`，可选 `pack_root / anchor_kind` | 解析并查找登记地图，返回 `can_transfer=false` 和未验证表面 |
| `get_current_world_address` | 可选 `anchor_kind / object_id / pack_root` | 单个物件作者原点或实际胶囊脚点地址 |

读取 `list_world_maps.documents` 获取所选目录的句柄、编辑修订和磁盘 SHA；写入后采用返回的新修订，不能自行递增猜测。`editor_state.world_addresses` 返回缓存的目录状态及脏标记，不触发地图扫描或文件哈希。

## 验证与证据

使用默认 Godot 4.8 补丁构建 `4.8.beta1.custom_build.4d10419ca`，入口 `D:/tools/godot/godot.windows.editor.x86_64.exe`；实际可执行文件 SHA256 为 `7a8029a67b0e0bbc442c12f5ebf0aa67baf2e53f65c8750dd5fbb6b4adabdb53`，与安装清单一致。没有开展 4.7 适配。

逻辑与集成入口分别为 [地址测试](../tools/test_world_address.gd)、[目录测试](../tools/test_world_map_catalog.gd) 和 [真实 HTTP/UI 测试](../tools/test_world_address_editor_http.gd)。测试数据均在外部临时资源包，未登记或修改正式地图。GPU/UI 使用 `tools/run_godot_background.py` 的独立非激活桌面；复制按钮通过注入捕获目标验证内容，不覆盖用户 Windows 剪贴板。

最终结果与源码身份见外部证据目录 `D:/code/rmmo_runtime/review_artifacts/world_address_d1_20261101/` 的 `evidence.json`：

| 验证 | 结果 | 原始证据 |
| --- | --- | --- |
| 地址编解码与胶囊适配 | 350 项检查，0 失败 | `codec.log` |
| 编号目录、历史、并发保存与恢复 | 86 项检查，0 失败 | `catalog_test_v4.log`、`catalog_33480_8982156/result.json` |
| 当前 3D HTTP + 实际 UI 控件 + GPU 截图 | 81 项检查，0 失败；独立桌面进程退出 0 | `http_gpu_final.log` |
| 现有外部资源只读盘点 | 145 个包、132 个地图入口 | `inventory.json`、`inventory.log` |

三组最终测试无引擎错误或警告。HTTP 覆盖工具发现、合法/非法参数、超大分页偏移拒绝、地址范围内大坐标数值返回、登记/撤销/重做/保存重开、复制内容一致、关闭保护、资源包失联后的显式草稿放弃，以及包元数据变化后的重新载入。原测试地图路径、字节 SHA、对象记录及地图历史均未变化。首轮 GPU 测试暴露了不可用目录选择及重新载入的恢复缺口，修复后重跑的最终日志通过；保留首轮失败日志，不将它作为通过证据。

最终界面原图为 `ui.png`，查看副本为同目录 `ui.webp`，1175×900、原尺寸及色彩、实际有损 quality=90；`ui_conversion.json` 记录转换参数和源/结果 SHA。已目视检查中文、状态、登记按钮、目录历史和地址结果，无重叠或裁切。

只读盘点中，3 个入口具备有效唯一作者身份但未登记（包括正式城镇 `default/axel_town`）；127 个入口因缺失/非法作者身份不可登记，其中大量是历史测试资源；另外 2 个展示地图共享 `showcase/medieval_houses`，报告身份冲突。未给正式地图分配编号或改写这些文件；不能将历史测试入口数量解释为同等数量的正式地图故障。

逻辑和 UI 验证不作为连续跨图或性能收益证据。地址扫描仅发生于显式目录/解析操作；常驻 `editor_state` 与退出脏状态检查使用缓存，不新增逐帧地图扫描。main 已有的加载、渲染和资源退役实现未改动。

## 后续边界

D2 继续世界布局、不同地图尺寸、原点放置和接缝诊断；本批提前交付的目录保存不重复实现。新增目录没有改变旧地图打开与现有传送流程，也未给正式城镇分配编号。原统一优化列表保持原排序，本批只落实新世界设计的首个功能闭环。
