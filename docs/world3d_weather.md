# 3D 天气与美术

2026-10-02 体积云已接入：共享环境新增 `cloud_altitude`、`cloud_thickness`、`cloud_scale`、`cirrus_amount`；客户端画质分档不进入服务器配置。资源安装、协议与真实 HTTP / GPU 验收见 [3D 体积云](world3d_clouds.md)。

连续昼夜、本地湿润/积水、室内外声音渐变和世界空间雷电已接入，配置与边界见 [环境效果扩展](world3d_environment_effects.md)。实时湿润度按用户要求不保存到服务器、不强制同步。

星空分布已升级为等面积、银河密度与尘埃共同驱动的程序算法，并加入星等亮度和像素足迹滤波。研究依据、同步兼容性和 GPU 测量见 [星空分布与渲染 v2](world3d_starfield.md)。

2026-10-02 后续更新：运行时已接入 MockServer 权威环境快照，替代下文早期“未接入联网天气 / 自动时间”的限制。天空支持服务器 seed 星空、普通流星 / 火流星 / 集中流星雨及事件亮度，世界时间支持倍率与服务器昼夜切换，风、云位移、闪电时间表统一同步。真实 Go 传输仍待接入。最新字段、边界和验收以 [3D 环境同步协议](world3d_environment_sync.md) 为准。

2026-10-02：正式三维场景和地图编辑器共用 `scripts/world3d/weather_controller.gd`。旧 `scripts/map/weather_fx.gd` 留作二维历史实现，不挂到 3D 场景，也不重新注册二维 MCP。

## 使用

编辑器「环境」面板选择晴朗、下雨、雷暴、飘雪、浓雾，点「应用环境设置」。实时预览、单次撤销、保存重开和 F5 临时试玩共用地图 `extras.environment`。旧地图未写天气字段时为晴朗。切换日夜保留天气；进入另一张地图立即采用目标地图设置并清理旧粒子。

### 昼夜切换验收道具（2026-10-05）

背包「全部」中新增 **昼夜切换仪（验收）**，物品 ID `day_night_review_dial`。双击在白天 12:00 与夜晚 00:00 间切换，将时间倍率设为 0，固定当前时段便于检查。单击只选中；物品可重复使用、不消耗，聊天栏与场景提示显示结果。新角色默认持有一个，恢复旧角色背包后缺少时补发一个，已有时不重复发放；背包满时不覆盖其他道具或擅自增加容量。

通过现有 `InvSlot.activated → InventoryPanel → world.request_use_item → world_combat → _request_environment` 路径执行，读取服务器当前小时判断下一时段，经权威环境请求刷新天气控制器；保留风、天气和过渡参数。只影响本次运行当前地图的服务器环境，不写地图默认配置，也不改其他地图的时钟。转图中、物品缺失、地图环境未就绪或请求失败时不切换、不消耗。旧二维入口明确提示进入三维地图后使用。

这不是新增编辑器能力；编辑器与 3D MCP 仍使用现有 `get_environment` / `set_environment` 编辑初始环境。道具不绕过或改写这些保存事务。当前实现沿用本地 MockServer，未新增远程服务器授权接口。

`tools/test_day_night_review_item.gd` 在后台独立桌面的实际游戏场景中验证背包单击/双击、往返切换、现有运行时夜灯联动、不消耗、重复发放保护、旧角色恢复、失败无副作用、天气保留、其他地图隔离与原文件不变。报告及日夜截图：`D:/code/rmmo_runtime/review_artifacts/day_night_review_item/`，失败数 0。此测试使用临时地图与已有运行时灯光，不将其等同于旗幡路灯 GLB 的夜间光源接入验收。

HTTP MCP 沿用当前 `get_environment` / `set_environment`，工具数量不变。发现 schema、参数校验及文档事务全部复用环境业务；返回的是保存的目标设置，过渡动画不会持续改写地图或产生撤销记录。

| 字段 | 范围 / 默认 | 说明 |
| --- | --- | --- |
| `weather` | `clear/rain/storm/snow/fog`；`clear` | 天气类型 |
| `weather_intensity` | 0～1；0.7 | 粒子密度、云量、太阳衰减和远景雾 |
| `wind_speed` | 0～18；2.5 | 米 / 秒；雨和雪使用不同的风力响应系数 |
| `wind_direction` | -180～180；25 | 世界 XZ 平面，0° 向 +X，90° 向 +Z |
| `weather_transition` | 0～20；3 | 秒；0 立即切换，连续切换从当前混合状态开始 |
| `sky_enabled` | 布尔；true | 程序天空与流动云层；关闭后使用原背景色 |
| `lightning_enabled` | 布尔；true | 雷暴时照亮场景的短促闪电，可单独关闭 |

```json
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"set_environment","arguments":{"weather":"rain","weather_intensity":0.75,"wind_speed":4,"wind_direction":30,"weather_transition":3}}}
```

游戏代码可调用 `world.set_weather("snow", 0.7)`，通过服务器环境请求复用类型、强度校验及过渡，返回 `ok/error`；`world.set_night` 同样请求服务器。运行时状态保留在服务器的地图实例中，不覆盖地图文件，不变更旧二维采集奖励规则。3D 支持服务器天气指令与世界时钟推进，尚未增加自动天气日程；真实 Go 网络传输待按同步协议接入。

## 美术与空间规则

- 天空由球面方向、五层噪声云形、天顶/地平线渐变和太阳光晕绘制；云随世界风向漂移。雨天与雷暴逐渐压低日光和天空亮度，雪天更柔和。使用小尺寸增量天空反射贴图，保留 PBR 天空反射。
- 雨线、六瓣柔边雪片和扩散水纹均为程序材质，无外部 PNG、字体或贴图依赖。三批 MultiMesh 合批绘制，粒子在世界空间中运动，受真实深度遮挡；相机转向不会让雨雪跟着旋转。
- 雨速为 15～23 米 / 秒，雪速约 1.5 米 / 秒并有缓慢风摆。模拟覆盖相机附近约 38×38 米，30 Hz 更新，显示帧在已验碰撞的前后位置间插值；最多 760 雨滴、300 雪片、96 水纹，补发每步最多尝试 64 次。粒子使用有类型的状态、复用射线查询对象，稳定天气不反复写全部环境属性。远景交给环境雾表达，避免按整张地图面积增加粒子。
- 新粒子出生前检查上方遮挡，运动用连续线段检查碰撞，快速雨滴不会跨过薄屋顶。朝上的碰撞面产生水纹，雪接触表面后消失。使用物理碰撞，因此游戏相机隐藏屋顶画面时仍能挡雨；不因为角色进入室内而关闭窗外的天气。
- 保留手工光照作为基线；天气临时乘以光照系数，不覆盖保存的太阳数值。手工雾与天气雾取较大浓度。雾对天空的影响受限，保留云层可读性。雷暴闪电使用投影方向光，非屏幕白色遮罩。
- 雨声复用现有缓存声音与 Ambient 总线；室内衰减 12 dB，编辑器预览静音。游戏「天气特效」关闭后立即停止粒子、闪电和雨声；基础天空、光照和远景雾仍保留。编辑器总是预览所编辑的天气。

## 柔性物件与天空（2026-10-02）

属性检查器新增「柔性物件受风」：选择植被 / 布料、作用网格和固定边，点「应用受风设置」。环境页统一控制世界风速 / 风向。默认不受风；旗帜模型应只选择旗布网格，保留旗杆刚性。网格必须有足够细分，四顶点平面不能产生连续波浪。

| `wind` 字段 | 范围 / 默认 | 含义 |
| --- | --- | --- |
| `profile` | `off/foliage/cloth`；`off` | 植被缓摆 / 布料波浪；off 清除受风记录 |
| `mesh` | `*` | 本物件内相对网格路径；`*` 对每个网格分别固定边 |
| `amplitude` | 0～1.5；0.35 | 米，12 米 / 秒时的摆幅基准，受刚度和风强度影响 |
| `stiffness` | 0～1；0.5 | 越大越硬、根部附近变形越少 |
| `anchor` | `bottom/top/left/right`；`bottom` | 网格局部 -Y / +Y / -X / +X 边 |
| `shelter` | true | 上方碰撞近似室内遮风，可关闭用于露天树冠等场景 |

MCP 用 `get_object.wind_meshes` 获取合法路径、支持状态与原因，再调用既有 `set_object_properties` 的嵌套 `wind`。UI / MCP 共用校验、单次撤销、保存重开、预制件和流式加载。批量最多 256 个物件；任一目标隐藏、锁定、不在当前楼层或不支持时整批无副作用失败。`wind` 不能与改名 / 隐藏 / 锁定混在同一次调用；生成建筑、自动地形、角色不开放此属性。

```json
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"set_object_properties","arguments":{"ids":["物件 ID"],"wind":{"profile":"cloth","mesh":"从 wind_meshes 取得的路径","amplitude":0.35,"stiffness":0.3,"anchor":"left","shelter":true}}}}
```

物件保存为 `wind_response`，所选网格导出 `extras.rmmo_wind`。同一阵风驱动雨雪、云和柔性物件；GPU 顶点变形同步更新法线与阴影，原网格、共享模型副本、物件变换和碰撞不改写，刷材质仍读取原材质。可见且距相机 90 米内启用，0.35 秒重查距离与遮挡，离开范围恢复原材质。遮挡检测使用第 1 物理层向上 180 米射线，不模拟建筑绕流。游戏「天气特效」关闭时柔性物件回到静止形状。

当前支持常用 `StandardMaterial3D` 的颜色 / 法线 / 金属度 / 粗糙度 / AO / 自发光贴图、UV1、顶点颜色、纹理过滤、双面、不透明 / Alpha / Alpha Scissor。自定义 Shader、ORM、多 Pass、骨骼 / BlendShape、公告板、视差、三平面等不兼容功能明确拒绝。单网格最多 32 个材质槽。这是带固定边的视觉变形，不是物理布料、自碰撞或可被风吹走的刚体。

天空新增黄昏冷暖渐变与迎光云色，夜间使用月盘与世界方向固定的星点。云会遮住星月；太阳 / 月盘方向与地图方向光一致。天体不会随相机转动，云仍随统一风场移动。天气切换保留云层连续漂移，`sky_enabled=false` 回到背景色。

`tools/test_world3d_wind.gd` 通过真实 HTTP 验证发现、非法调用、批量原子失败、撤销重做、UI 同步、保存重开与预制件；后台 GPU 验证固定边、反向风、旋转 / 非均匀缩放、停风复位、遮挡、原材质保留、Alpha Scissor 植被、刷面源材质与三时段天空，最后验证区块卸载重载。命令：

```powershell
python tools/run_godot_background.py --timeout 200 --log D:/code/rmmo_runtime/wind_gpu.log -- D:/tools/godot/Godot_v4.7.2-stable_win64.exe --path D:/code/rmmo --script res://tools/test_world3d_wind.gd
```

## 边界

遮雨依赖当前物理世界中第 1 层碰撞。无碰撞装饰不会挡雨；出生遮挡检测上限为上方 180 米。编辑器隐藏或楼层隔离的物体可能没有编辑器碰撞，完整建筑的室内遮雨以实际试玩为准。编辑器重建地图几何时清理旧粒子；运行时物理碰撞保持逐段检查。运行时突然在已有雨滴上方新增屋顶时，屋顶下的存活雨滴仍会自然结束，不立即回溯删除。

当前没有积雪堆积、地面湿润 PBR 替换、持续水洼、雷击伤害或独立雷声音频。云为程序天空背景，雾为深度雾，不是体积云或局部雾体。不会把屏幕雨雪或全屏调色称为这些能力。

## 验收与预览

`tools/test_world3d_weather.gd` 使用临时地图，通过真实 loopback HTTP 验证工具发现、八类非法参数无副作用、UI 同步、单次撤销重做、保存重开；并验证连续/重复切换、屋内出生遮挡、薄屋顶碰撞水纹、视觉屋顶隐藏、粒子上限和特效关闭。图形模式另验收五种天气截图、墙体深度遮挡、正式游戏场景、运行时调用和跨图清理。

```powershell
& 'D:/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path D:/code/rmmo --script res://tools/test_world3d_weather.gd
python tools/run_godot_background.py --timeout 200 --log D:/code/rmmo_runtime/weather_gpu.log -- D:/tools/godot/Godot_v4.7.2-stable_win64.exe --path D:/code/rmmo --script res://tools/test_world3d_weather.gd
```

`tools/preview_world3d_weather.gd -- --map=<内容根内的地图绝对路径>` 只读加载地图，在后台 GPU 生成五种天气及白天 / 黄昏 / 夜晚美术图，不保存源地图。脚本图片均输出到外部内容根 `review_artifacts/weather3d/`，不进入项目导入扫描。预览脚本也必须经 `tools/run_godot_background.py` 启动。

测试日志的 `weather CPU step` 是每次 30 Hz 脚本模拟（含碰撞和实例更新）的采样耗时，不含整个游戏或 GPU 渲染，不能换算为整体 FPS 提升。共享编辑器的图形回归还包括 `test_world3d_groups_ui.gd`、`test_world3d_transform.gd`、`test_world3d_editor.gd`，环境及事件回归为 `test_world3d_gameplay.gd`。

2026-10-02 实测：Godot 4.7.2、Forward+、RX 7900 XTX；天气 headless / 后台 GPU、环境事件 headless、分组 / 变换 / 编辑器后台 GPU 均通过，无脚本或着色器错误。90% 强度、684 雨滴的每步脚本中位数约 3.65 ms（雨）/ 3.96 ms（雷暴），270 雪片约 1.44 ms；P95 分别约 9.11 / 7.27 / 3.22 ms。这是带编辑器和临时房屋的短期采样，尚不是大城镇性能承诺。五种材质房屋实景见外部 `review_artifacts/weather3d/art_*.png`。


2026-10-05 路灯补验：旗幡路灯 GLB 已接入共用天气控制器，不再依赖独立 TSCN 的预览脚本。`tools/test_town_streetlamp_night.gd` 在真实城镇通过背包双击切换，逐盏检查 23 盏发光/光晕和道路朝向、原地整街同时点亮、相机距离不影响开关、白天关闭与流式卸载/重入。报告 `D:/code/rmmo_runtime/review_artifacts/town_streetlamps_20261005/night.json`；该检查补足早期仅验证昼夜道具而未覆盖此 GLB 灯具的缺口。
