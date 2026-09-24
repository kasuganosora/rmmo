# 城镇材质、夜间照明与分层住宅

Axel256 已安装 71 张图块页、108 张技术通道贴图和 160 盏街灯。地图仍为 256×256 格、48px 原生瓦片。实际地图修改通过内容编辑器 MCP 完成。

## 昼夜和材质

编辑器“光照”选择日间、黄昏、夜晚；地图设置保存 light_preset。运行时沿用既有环境光渐变，灯柱 PointLight2D 与窗户发光按环境亮度渐入、渐出，日间禁用局部灯光。没有新增独立游戏时间系统。

Tileset 可选 renderProfile 包含 normal_sheets、height_sheets、emission_sheets，顺序与 9 张 MV 页及 extraSheets 一致。无通道填空字符串。未启用 profile 的旧地图继续使用原渲染方式。

法线由现有色彩图的局部梯度生成，属于近似凹凸，非手绘几何法线。高度通道 R 为投影高度，G>0.6 为喷泉水面、0.22–0.5 为河水；喷泉的 B 为径向坐标，G<0.1 且 R=0 时 B 为草地覆盖率。A 为覆盖轮廓。分块四周额外采样 4 格，避免日照阴影在分块边界切断。灯光只随已加载分块创建；屋体提供夜间灯光遮挡。

可选 terrain_textures 指定 meadow、river 独立纹理。Ground shader 用全局世界坐标采样，避免按分块重新起算；纹理采用像素中心镜像采样，草地混合两个不同周期并轻微连续扭曲以减弱重复。草地法线从同一连续采样计算，不能继续使用原瓦片边缘的法线。河水随时间流动，岸线与桥面保持静止。路肩草地覆盖使用邻域过渡和细碎边缘。

灯柱采用连续细线日影，避免细柱高度图离散步进产生梳齿。墙体分为立面 z2 和墙顶 z3，生成时检查整个树木图块范围与最终投影墙体的重叠。桥面采用端点高度为零的缓拱，独立桥侧和上层护栏。

喷泉水面使用持续变化的波纹与微小折射，另有独立水柱/水滴 shader；石座固定。preview_time 仅用于可重复截图，正常运行设为 -1。

## 参数化住宅

工具栏“住宅…”打开实时预览。支持 1–3 开间、1–3 层、红瓦/蓝灰瓦、窗户开关。墙体 z1，门窗 z2，屋顶 z3；固定尺寸门窗保持人物比例。相同实例名用于更新已有生成住宅；拒绝覆盖其他对象，单次生成/更新可撤销重做，实例参数随 map.json 保存。

MCP: list_building_kits、generate_building（kit、x、y、bays、floors、roof、windows、instance_id、dry_run）。当前普通住宅已拆分立面与屋顶所在图层；地标继续使用专门制作的建筑图。参数化组件是可扩展的基础住宅套件。

## 自动验收

路灯 `renderProfile.lights` 支持 `visual_scale`（Axel 为 1.5）、`sprite_tiles`、`sprite_columns`、`foot_offset`。整件精灵绕实际灯脚 (30,177) 缩放，原始地图格和碰撞不变；原瓦片从分块颜色/法线烘焙中排除，灯光位置和杆影同步变换。源法线及发光图复用后台解码结果，所有灯共享精灵纹理，不在主线程重复加载整套技术贴图。`tools/test_lamp_scale.gd` 检查脚点、发光点、投影、跨块显示及纹理共享。

项目脚本：tools/test_town_curves.gd 验证保存地图的图层、碰撞、六桥及所有建筑入口；tools/test_building_generator.gd 验证 18 种组合、固定开口尺寸、三个图层、重叠拒绝、更新、撤销重做和保存重载。

工作目录 D:/code/rmmo_runtime/style_work/town_m 中：
- accept_materials.py：已安装技术贴图的尺寸、字节一致性、灯柱标志和禁放区域。
- verify_live_lighting.py：Godot MCP 实机日夜截图、日间灯光关闭、夜间启用、喷泉两帧像素变化；完成后恢复日间与正常动画时间。
- live_review.py bridges：六桥真实寻路行走。
- scene_upgrade.json：分层住宅与灯柱的期望图层差异，供地图回归验收。
- accept_terrain.py：最终道路/院地遮罩下的灯柱、连续农田避让及完整树木与墙体相交检查。
- terrain_review.py：五处 GPU 实机截图，必须等高清分块全部完成后才计为有效。
- verify_river_motion.py：固定镜头与两个时间点，检测河水区域的像素变化。
- lighting_day.png、lighting_night.png、live_axel_house_02.png：实机截图；CPU preview_map 不包含 GPU 灯光，不能代替夜景验收。

观察到预热后的夜景约 60 FPS；首次加载/跨远距离传送仍会有分块与贴图加载的短时帧率下降，不代表持续帧率保证。
