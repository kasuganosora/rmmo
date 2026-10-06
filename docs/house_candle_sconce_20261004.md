# 室内烛台壁灯（2026-10-04）

这是固定在墙面的烛台壁灯，不是台灯。背板上有两枚墙面固定铆钉，上横臂与下斜撑共同承托接蜡盘，盘中为短蜡烛与灯芯。自制 Blender 模型没有下载或拷贝 Fab 的资产。

## 参考

- [Met，欧洲15–16世纪烛台，55.40.2](https://www.metmuseum.org/art/collection/search/471567)：实物烛钎、蜡盘比例，及馆方说明的室内墙托烛台使用方式。当前自制墙托结构是游戏用简化组合，不宣称复制该博物馆实物。
- [Fab，Medieval Lighting Candle Holder 2](https://www.fab.com/listings/9d467bca-5ee6-487d-8e8b-f83dab69a8bd)：确认市场中已有中世纪蜡烛灯具的模型、蜡烛与火焰分离方式；仅查看官方商品资料，没有采购、下载或转用其模型和贴图。

## 源文件与使用

- 可编辑 Blender 源：`D:/code/rmmo_runtime/art_sources/candle_sconce/candle_sconce.blend`。
- 实際 Blender 4.5.3 后台生成脚本：`tools/build_blender_candle_sconce.py`。
- 运行时源网格：`scripts/world3d/candle_sconce_data.gd`；mesh 构造：`candle_sconce_mesh.gd`。
- 模型 304 个三角形，铁、蜡、灯芯分材质；拆成4个表面，每表面不超过120面，适配现有局部涂装预算。墙上模型作为独立建筑构件，保留楼层、隐藏、旋转、移动与保存语义。
- `house_candle_layout.gd.add_to_plan(plan)` 在各房间实体墙上找可用位置；不在城市自建房模板自动放置。自动位置的灯具 AABB 与每片窗帘 AABB 至少相距1米，避开门窗洞口。它是自动布局选择规则，不是手动部署禁令。
- 安装中心高2.15米，模型向房间突出约45厘米。该高度为约1.9米角色与第三人称通行作了调整，不是历史测绘尺寸。
- `house_candle_lights.gd.bind_map(map_root, observer, weather_controller)` 跟随现有服务端同步世界时间；20:00至06:00才显示火焰及灯光，白天和黄昏关闭。单个烛台的真实光半径5.5米是游戏室内可读性调整，不是烛光物理照度标定。
- 最多同时开启最近两盏18米内的真实光，两盏均投射阴影，避免通过墙壁照到室外。45米内其余可见烛台只显示火焰。每0.25秒刷新选择，无每帧全地图查找；共享火焰网格。卸载、释放、楼层隐藏时关闭对应光。
- 同楼层且从玩家胸口至火焰无遮挡的候选优先，相邻房间隔墙更近的灯不会抢走当前房间灯光额度。绑定时立即读取现有世界时钟，不等待首个0.25秒刷新。

## 验证

`tools/test_house_candles.gd`：七款住宅预设共31个房间的壁灯生成、窗帘1米距离、墙面接触、安装高度、JSON往返、网格无退化面、昼夜边界、两个阴影灯预算、卸载/重载12次、释放后遗留引用、地图释放、构件移动与楼层隐藏。

`--preview` 通过 `tools/run_godot_background.py` 在独立非激活桌面生成日夜近景：`D:/code/rmmo_runtime/review_artifacts/candle_sconce/`。它是壁灯独立验收图，不代表整屋最终照明效果。主任务负责样房重建、MCP与保存重开验证。

`tools/benchmark_house_candles.gd` 的独立基准放置36组简化墙、144盏共享网格壁灯，不包含完整住宅、角色或导航，因此不能作为整屋帧率数据。RX7900XTX、1280×800视口、关闭垂直同步：白天GPU中位0.081毫秒，夜间0.107毫秒；可见绘制调用37→38；144灯一次刷新CPU0.478毫秒，每0.25秒调用一次。原始记录为该预览目录的 `benchmark.json`。
