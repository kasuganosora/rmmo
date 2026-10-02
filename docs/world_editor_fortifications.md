# 连续城墙与活动城门

2026-10-02。入口：**城镇布局 → 连续城墙与城门**。当前 3D MCP 共 104 项，本轮新增五项城墙操作；UI 与 MCP 共用 `fortification_tools.gd`，所有实体即时生成到地图，默认资源包只提供材质。

**美术状态：用户已要求继续优化，当前外观未验收。** 墙体层次、塔楼/城门比例、垛口和弧面纹理等已列入 [编辑器待办](world_editor_todo.md)，功能截图不代表最终城墙美术。

## 使用

1. 新建城墙，选择“点选折线”或“圆形 / 椭圆围城”，设定地面标高、墙高/厚度、向下延伸的地基，以及塔楼和垛口开关。
2. 折线模式点选中心线，Enter 完成、Backspace 撤一点、Esc 取消；勾选“闭合围城”连接末点与首点，不重复输入首点。环形模式可以直接设中心、两轴半径和朝向，或点选包围范围两个对角再 Enter；相等半径是圆形，不等为椭圆，始终闭合。
3. 折线城门按段号和比例定位（从 0 起，`t=0.5` 为中点）；环形城门按角度定位（0° 东、90° 南、180° 西、270° 北，再随城墙朝向旋转）。指定门洞宽高和初始开度。道路应从门洞内穿过，墙身和门楣不能占用道路及上方净空。
4. 选择石材和木材，预览并应用。默认 UI 在资源存在时使用城堡砌石和磨损木板，包含 PBR 法线及米制纹理重复。MCP 新建省略材质为原色，更新省略则沿用。
5. 选已有城墙修改参数并重新预览；“打开/关闭已生成的所选城门”控制双扇门并保存初始状态，单次撤销。运行时程序控制另见下文。

当前生成连续墙体、折线路径上的实心方塔或环形路径上的实心圆塔、护墙/垛口、平顶门洞和双扇门。弧线采用共享边界的曲面分段网格，圈内留空，门洞与门楣沿同一条曲线切分；不会用整圆实体堵住城内。**不包含塔楼内部、登墙楼梯、拱券门洞、闸门或随坡起伏城墙**；不能将当前墙顶当作已完成可达的城防玩法。

环形塔楼数量为 4～24，默认 8，沿椭圆参数角均匀分布；相位错开半个塔间距，为四个主方向留出自然城门位置。墙顶护墙和垛口随曲线排列。圆/椭圆由每段不超过 3°、约 2 米弧长的凸补片近似，兼顾外观、物件避让、刷面和运行时碰撞。当前提供完整圆/椭圆与手绘折线，还不支持任意样条或多段局部圆弧混合边界。

## 几何、占地和保护

- 默认墙高 6 米、厚 2.5 米、地基向下 1 米；允许高 4～12 米、厚 1.5～4 米、地基 0.5～3 米。每条线段至少为墙厚三倍，单组最长 1000 米、2～32 点，闭合至少三点。拒绝自交、过尖折角和过近非相邻墙段。
- 环形两轴半径各 15～200 米，默认均为 40 米，同时受单组周长 1000 米和 4096 构件预算约束；过扁椭圆、靠塔城门、重叠门洞、越出承托地面会拒绝。两点快捷选范围会将朝向归零，可再调整。切换形状后需更新或移除使用旧定位方式的城门草案。
- 每组最多 16 个城门、4096 构件，每图最多 64 组。门洞宽 3～10 米、高 3～9 米，门顶低于墙顶至少 0.5 米；门洞需避开角塔、墙端及其他门洞。
- 墙体、角塔和城门活动范围都需要同标高的实际水平地面承托；不会在河槽、悬空地段生成。建筑、现有物件（含隐藏/锁定）、禁建区及保留通道都参与避让。活动门扇允许横过道路，静态砌体仍须留足道路净空。
- 完整门扇转动范围保守预留，后续建筑和植被生成不能占用。门扇闭合能阻挡角色，打开能通行；不会自动规划道路或把任意普通模型改造成门洞。
- `editor_layout.fortifications` 保存设置及成员 UUID/完整签名；记录附带 `fortification:{id,part,role}`。所有成员自动归为一组。配方重生成、开合、删除和解除关联使用共享事务。
- 任意成员被手改/刷面/移动/改名/挂事件/删除后拒绝重生成，不覆盖手工作品；隐藏、锁定及楼层隔离同样保护。`list_fortifications.modified_or_missing` 返回具体成员。移动既有组合不会自动改写中心线配方，重生成前需恢复或解除关联。
- 解除关联保留现场并把门扇烘焙为当前姿态的普通静态物件；删除要求成员未改。普通复制/快照预制件同样清除生成归属，避免原门控制到副本。上述操作均支持撤销。
- 预览不写文档，过期 `plan_token` 拒绝；保存/草稿/重开校验记录、配方及依赖。全量重建与快照撤销仍是当前实现，未承诺整城海量构件性能。

## MCP 与运行时

| 工具 | 参数 / 结果 |
| --- | --- |
| `list_fortifications` | 无参数、只读；设置、成员数及手改/缺失成员 |
| `preview_fortification` | 折线新建需 `id/points`，环形需 `id/shape:ellipse`；返回设置、轮廓 `outline`、长度、构件数、门洞及 `plan_token` |
| `generate_fortification` | 同预览，可加令牌；同 ID 只传变化字段；幂等、一次撤销 |
| `set_fortification_gate` | `id/gate_id/open`，开度 0～1；更新两扇门初始状态 |
| `remove_fortification` | `id`；`keep_objects` 默认 true 保留现场，false 删除 |

`points` 是折线路径 XZ 二元数组；环形使用 `center_x/center_z/radius_x/radius_z/rotation/tower_count`，不需要 points。`base_height` 提供统一 Y。城门数组每项必须含 `id/width/height/open`，折线再加 `segment/t`，环形加 `angle`，不能混用定位方式。旧折线配方未含环形字段时仍可读取。`editor_state.fortification_drawing` 表示 UI 点选中。

```json
{"name":"preview_fortification","arguments":{"id":"city_wall","points":[[-30,-30],[30,-30],[30,30],[-30,30]],"closed":true,"gates":[{"id":"north","segment":0,"t":0.5,"width":6,"height":4.5,"open":1}],"stone_material_id":"pack:default:walls/castle_rubble/material","door_material_id":"pack:default:wood/worn_planks/material"}}
{"name":"set_fortification_gate","arguments":{"id":"city_wall","gate_id":"north","open":0}}
{"name":"preview_fortification","arguments":{"id":"round_city","shape":"ellipse","center_x":0,"center_z":0,"radius_x":90,"radius_z":75,"rotation":0,"tower_count":8,"gates":[{"id":"north","angle":270,"width":8,"height":4.5,"open":1}],"stone_material_id":"pack:default:walls/castle_rubble/material","door_material_id":"pack:default:wood/worn_planks/material"}}
```

用同一份参数调用 `generate_fortification` 应用预览，再调用开关门。游戏加载后复用 `building_fixtures.gd`，运行时 owner ID 为 `fortification:<城墙id>`：

```gdscript
var Fixtures = preload("res://scripts/world3d/building_fixtures.gd")
Fixtures.list_runtime(map_root, "fortification:city_wall")
Fixtures.set_runtime(map_root, "fortification:city_wall", "north", 1.0, 0.8)
```

最后两个参数是目标开度和动画秒数；可中断并改向，碰撞随门扇同步。运行时动画不改编辑器初始配置；MCP 工具修改的是文档初始状态，未新增游戏网络命令。

## 验收

`tools/test_fortification_plan.gd` 覆盖闭合城墙、角塔/垛口、门洞净空、角落及自交拒绝。`tools/test_world3d_fortifications.gd` 经真实 HTTP 验证 104 项工具发现、预览只读、合法/非法调用、无副作用失败、物件/道路避让、编辑保护、幂等、撤销重做、UI 点选与应用、草稿和保存重开，并检查实际石材法线。后台运行时测试动画开合，用 2.1 米角色胶囊验证关门阻挡和开门通行。

`tools/test_world3d_round_fortifications.gd` 经真实 HTTP 验证圆形、更新为椭圆、圆塔/城门冲突及道路净空、圈内已有物件保留、实际 PBR、撤销重做、草稿、保存重开及再次保存；通过真实画布输入验证两点快捷选范围。重新加载运行时后检查弧墙实体碰撞、内部无虚假填充，以及角色通过环形城门。

最终后台验收日志位于 `D:/code/rmmo_runtime/review_artifacts/`：

- `fortifications_final.log`：`FORTIFICATIONS_FINISHED failures=0`，包含普通复制门扇的姿态烘焙及归属隔离。
- `round_walls_final.log`：`ROUND_WALLS_FINISHED failures=0`；测试地图、圆形和椭圆截图在 `D:/code/rmmo_runtime/cache/world3d/round_walls_10347141/`。
- `walls_regression_fixtures.log`：既有房屋门窗动画、导航、流式重载回归通过。
- `round_walls_paint_regression.log`：完整刷面 UI / HTTP / 保存回归通过；单网格同 UV 参数刷面合并的几何/法线/UV 保真由 `tools/test_surface_uv_batch.gd` 验证。

最初未合并同 UV 刷面时，环形测试在再次保存阶段超过总时限；修正后完整重跑通过。当前只优化同一网格内的渲染面，跨构件静态合批与房屋拆件问题按用户要求另列待办，本轮不声称已完成。
