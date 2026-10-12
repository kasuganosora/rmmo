# 编辑器扩展交付（2026-10-12）

用户要求一次完成上一轮列出的扩展。本批不恢复已标记“未解决-跳过”的性能专项；功能所需的共享批次、后台准备及缓存失效仍属于交付范围。正式城镇手工布置和五处保留区不得被测试覆盖。

同日后续，用户要求完成“本轮功能仍有的边界”。六项补完已实现并验收，见 [边界补完记录](editor_extension_boundaries_20261012.md)。下方 271 条检查保留首批交付时点，后续证据单列，避免重复累计。

## 执行与验收清单

- [x] 相邻地形跨块笔刷、共享边界同步，包含不同格距；真实 HTTP、锁定失败无副作用、单次撤销及保存重开。
- [x] 三维体积地形：加减体积、洞穴、横向隧道及悬挑；UI/MCP、真实洞顶/地面碰撞、原生保存重开、后台 CPU 准备、共享渲染批次与游戏流式加载。
- [x] 自动贴地：道路按实际高度场三角形切分投影，后续雕刻同事务更新；河床随中心线雕刻；墙段生成时顺坡；独立桥梁接受不同桥头高度。
- [x] 通用中心线河道 UI/MCP，复用原生地形/水面、32 米水面分块和自然 PBR 材质。
- [x] 控制点样条城墙、坡地墙顶与墙基、真实多孔砌石水关、独立铰链的开合铁闸栅。
- [x] 原创木桥模块、桥头翼墙、磨损/苔藓变体；青麦/成熟小麦、沿垄沟成行散布与庭院地表复核。
- [x] 城防和住宅街景的受影响外观自审、资源 SHA 与保存重开证据。用户最终美术确认单列保留，不代为勾选。

## 结构资料与项目补充设计

- [Historic England：Warkworth Bridge](https://historicengland.org.uk/listing/the-list/list-entry/1020741)：参考拱桥、分水墩及桥头翼墙的结构关系。项目桥孔、净宽和栏高按第三人称通行调整，不照搬实桥尺寸。
- [Historic England / National Trust：Tattershall 木桥记录](https://historicengland.org.uk/listing/heritage-gateway/results/record/c30a9cd9-4500-41f0-acda-ed2a4d72a681/MNA182238)：参考橡木横梁、斜撑和栏杆连接关系；该实物是近代按中世纪构造制作，不能称为原存中世纪桥。
- [English Heritage：Eynsford Castle](https://production.english-heritage.org.uk/visit/places/eynsford-castle/history/description/)：护城河木桥与城门通路关系。

新构件缺少项目原图的背面、固定件、连接与尺寸属于“项目补充设计”。既有参考明确部分优先。功能通过不等同于用户最终美术确认。

## 当前证据

所有地图操作在独立临时地图中完成。GPU 由 `run_godot_background.py` 在不激活的桌面运行，场景无角色人像。下列路径位于 `D:/code/rmmo_runtime/`：

最终汇总 `review_artifacts/editor_extensions_20261012/verification.json`：7 组集成/回归日志、271 条通过检查、0 条失败，另存 25 个相关源文件 SHA 和正式地图 SHA。可用 `tools/summarize_editor_extensions.py` 重新核对；这不是 271 个互相独立的场景测试，也不是新一轮整城性能基准。

|验收|结果与证据|
|---|---|
|地形 / 道路 / 河道|`terrain_extensions_final_live.log`：`CROSS_TILES_FINISHED failures=0`；GPU 图 `cache/world3d/terrain_extensions_10938461/`。随后增加邻块河岸锁定保护，`terrain_extensions_guards_live.log` 同样零失败。|
|桥 / 坡墙 / 水关|`structure_extensions_final_live.log`：`STRUCTURE_EXTENSIONS_FINISHED failures=0`，GPU 图 `cache/world3d/structure_extensions_19090471/`。木桥和石桥真实胶囊双向过桥；三孔射线通行、实体拱顶、三孔关栅阻挡均通过。|
|深河床 / 墩基保护|`structure_extensions_bed_live.log`：零失败；河床降低 4 米后水关合法，2 米浅墩预览整笔拒绝。修复了旧岸面承托检查误拒水下墩；五点实际河床检查保留。|
|三款城墙外观|`fort_visual_extensions_live.log`：`FORT_VISUAL_FINISHED failures=0`；真实 HTTP 分别生成直线、圆形和椭圆，原生保存重开后拍全景/门洞近景，图 `cache/world3d/fortification_visual_extensions_13097194/`。|
|作物|`crop_extensions_wind_live.log`：`CROP_EXTENSIONS_FINISHED failures=0`，图 `cache/world3d/crop_extensions_11265226/`；真实导入、工具发现、预览、行列落位、选择、锁定失败、撤销/重做、保存重开、受风设置及退出静态批次。|
|游戏加载|`extensions_runtime_live.log`：`EXTENSIONS_RUNTIME_FINISHED failures=0`；生产 `MapLoader → WorldStream` 加载三类保存文件，体积地形实际碰撞驻留，作物真实 MultiMesh 批次，水关独立 fixture 保留。|
|既有管线回归|`extensions_batch_regression.log`：`GROUND_BATCH_LIFETIME PASS`；`extensions_structure_prefab_regression.log`：`STRUCTURE_PREFAB_MCP_FINISHED failures=0`。覆盖编辑失效、删除/卸载、过期后台任务、材质变化，以及冻结桥梁/城防活动件保存。|
|路径边界|`tools/test_extension_guards.gd`：闭合普通轮廓合法、闭合末段自交和重合点拒绝，零失败。|
|素材库|`publish_extension_crops_live.log`：`CROPS_PUBLISHED`；默认库两种作物、native 派生资源与缩略图已登记；完整成本见 `review_artifacts/editor_extensions_20261012/crops.json`。|

作物测试请求 80 株，在行距、株距、边界和避障共同约束下可放 56 株，API 明确返回 24 株缺额；不强行重叠凑数。56 株的 112 个源表面变为 18 个提交表面、9 个空间实例组。此数字是该临时场景的批次统计，不是整城 FPS 或显存收益。

## 实现边界与使用方式

- 地形面板增加“跨相邻地块”“洞穴 / 悬挑”和中心线河道入口。跨块同步支持同方向、原始边界对齐的不同格距地形，细网格边界约束到共享折线；1/2 米及非倍数 2/3 米已验收。不自动修复原先就错开的地块，不等同运行时地形 LOD。侵蚀仍固定每块边界，不实现跨块水力/泥沙模拟。
- 体积块每轴 2～64 米，分辨率 4～32，最多 128 笔并另受总工作量约束。笔画输入世界 XYZ，生成可见表面与真实碰撞；增加体积裁剪在该块范围内。它是可编辑建模能力，方盒隧道验收样件不是已经布置好的天然山洞美术。现有物件、锁定/隐藏及保留区保护仍有效。
- 道路 `follow_terrain` 选择实际地形承托，缺口、覆盖歧义和超过 15% 坡度拒绝。后续雕刻会连带重建对应道路及生成清单，一次撤销；手刷面/锁定道路不会被静默覆盖。
- 河道使用 XZ 中心线和固定水位，自动收集受河岸影响的兼容邻块；邻块锁定则整笔失败。同 ID 可加载、替换控制点、改线或删除，持久化恢复图层先还原原河床，再计算新路径，不反复挖低。无关雕刻保留；河道拥有的样本或水面被手改时拒绝覆盖。没有恢复快照的历史河道不能凭空恢复原始地形。
- 城墙 `shape=spline`、`curve_tension`；连续共线控制点可构成直段。`follow_terrain=true` 让短墙段随坡，后续雕刻也会更新已冻结城防；已有结构可在面板或 `set_fortification_terrain_follow` 切换。鼠标笔刷松开时统一重建一次，与地形共用一次撤销。墙顶通行坡度不超过 15%；城门、城楼保持刚性，底面需局部整平（高差 ≤0.12 米）。锁定、手改或承托失败时整笔回滚。
- 水关每孔跨度受限，使用真实拱券和中墩；`grille=true` 为每孔两扇独立铁栅。path/spline、圆形和椭圆均支持，环墙上方补曲线券顶接合并去除共面重叠。复用现有城门开度操作，各扇保持实际轴心。当前是平开栅，不是升降闸门或水利模拟。
- 木桥为 `timber_trestle`；翼墙长度、磨损、苔藓和变化种子可编辑。独立桥梁及 `road_edge_id` 道路绑定转桥均支持两端不同 Y，线性高差与起拱坡度共同受通行限制。道路绑定沿用路口宽度、真实坡线和铺面抬高量；裁切插值旧路面高度，重铺不复活桥下桥板，高架交叉路保留。
- 作物位于默认素材库“作物”分类，青麦与成熟小麦新增 LOD 版及缩略图；原始母版保留。散布面板选择成行、方向、株/行距和按地形落位，包含真实垄沟几何。单株保留身份、选择和变换；静态单网格作物使用 32 米空间批次和最多 64 个成员的实例组，并保留 native LOD。活动/受风/手刷材质对象退出该批次。两方向连续风与相机跨 LOD 已补测；默认无风，编辑器风预览仍默认关闭。
- 大地图地形 LOD、保存取消以及既有性能遗留不在本次功能扩展恢复范围，继续“未解决-跳过”。不以本次合批数字宣称这些旧问题解决。

## 街景复核

直线、圆形和椭圆城墙的墙基/压顶、扶壁、垛口、圆楼接墙、拱圈、门板方向与铁箍完成六图自审，所拍视角无新增明显洞缝或堵口。补测修复一个既有边界问题：离原点 200 米的窄垛口，float32 中心舍入使局部归一化坐标略超 ±0.5，被误判无效。现在围绕实际保存中心重新计算包围尺寸，不放宽校验、不裁切顶点；`diagnose_extension_ring.gd` 以及真实 HTTP 重跑通过。

`review_artifacts/editor_extensions_20261012/outdoors/` 保存院落正背面、庭院俯视、窗/灯/临街近景、屋面衔接和入口道路共六张无角色截图。检查 1,390 条区域记录，缺失资源为 0；这批观察未发现需要因此改写正式地图的庭院地面悬空、院墙断口、屋面明显洞缝或堵门道路。夜间、室内和所有动态视角不在这六张图的证明范围；沿用已经完成的组件验收。

正式地图 SHA 始终为 `a2808a3fc088c601c4a5913ec8f97ea7603b4de49858c29ff7bd742861696f44`，本轮未覆写用户城镇、未扩建五处特殊建筑保留区。历史用户最终美术确认继续待确认。

模型身份、每件成本与检查状态见 [扩展模型验收](editor_extension_models_20261012.md)。
