# 街区彩旗装饰柱：Blender 待验收样品

用户要求：参考两张木柱图片制作，可自定义柱身颜色，缠带必须为金黄色丝带；两根柱靠近时之间有彩旗；彩旗必须是能随风运动的布料。沿用前序约定，只制作离线样品，未经用户明确同意不接入游戏。

原图位于 `references/town_festival_posts_20261005/01_pair.png`、`02_single.png`。画面提供造型参考，不是历史结构证明。

## 文件与参数

- 生成脚本：`tools/build_blender_town_festival_posts.py`。
- 参数：`tools/town_festival_posts_parameters.json`，柱高、半径、逐柱位置及 RGB、连接距离和绳索下垂量。
- Blender：`D:/code/rmmo_runtime/art_sources/town_festival_posts/festival_posts.blend`。
- 静帧：同目录 `festival_posts_review.png`；动画：`festival_posts_wind.mp4`。
- 柱高 3.05 m、半径 0.24 m（基部名义直径 48 cm）是样品设计尺度，非实测参考尺寸。示例双柱间距 3.4 m。用户反馈旧样品显细后加粗，侧面略微收分。
- 用户反馈缠带过于规整后，改为逐柱不同的非均匀绕距，局部反绕叠压、倾斜上圈、小结和不等长短垂尾。
- 彩旗按用户要求加长加宽：`flag_length_m` 为 1.05 m，再叠加逐旗长短差异和 0.15 m 尖端；总长约 1.1–1.3 m；`flag_fill_ratio` 为 0.93，减小旗间空隙。

柱身材质的 `USER POST COLOR` 节点可调整颜色，保留木纹。木纹复用既有 `solid_timber` 材质，原素材来源见其 material.json；贴图打包进 blend。丝带使用独立金黄色材质，不随柱色改变；金属度为 0，使用丝绸 sheen 和切向高光。彩旗金属度为 0，粗糙布面和细微纤维凹凸，薄布厚度 1.4 mm。

## 风动和连接范围

布料以连续正弦形态键驱动，在 24 fps 下每 48 帧循环。上沿位移严格为 0，下摆起伏并有竖向轻微卷动，每面旗相位不同；缝边共享相同位移。打开 blend 播放时间轴可检查。属于可控的离线风动形变，并非布料物理模拟，也未连接游戏风场。

生成脚本在 1.2 m 到 `connect_distance_m` 范围内按最近距离优先配对，每根柱最多连接一次。当前只验证离线双柱样品；移动 Blender 物体后需重新生成，尚未实现实时邻近检测。此规则不是未来手动放置禁令。游戏、编辑器和 3D MCP 均未接入。

## 实物参考范围

- [Royal Museums Greenwich 旗帜藏品](https://www.rmg.co.uk/collections/objects/rmgc-object-1016)：布料旗体、吊挂边和绳索连接做法参考。
- [V&A May Day](https://www.vam.ac.uk/blog/news/may-day-mayday)：节庆柱与丝带装饰参考。
- [EFDSS Maypole](https://www.efdss.org/learning/resources/beginners-guides/37-english-folk-dance/2191-maypole)：绕柱丝带参考。

这些资料仅支持装饰和布料构造，不据此声称当前方案是中世纪实物复原。美术仍待用户验收。

## 图案及未来替换约定（离线预留）

用户补充要求彩旗有参考图中的图案，并预留将来在游戏中替换的设计。参考中红旗底部金色分叉纹、绿旗白色外框与下部横条较清楚，已手工用线条重建为布面贴图；其他旗的细节无法从小图可靠辨认，黄/白旗为简洁边饰样式，蓝旗保留素色，不声称所有图案逐像素还原。

- 样式目录 `tools/town_festival_flag_styles.json`：稳定 style ID、底色、图案色和图案类型。支持 `texture_path` 使用自备 PNG（相对样式目录文件），不需要改柱身、绳索或风动代码。
- `tools/town_festival_posts_parameters.json` 中 `flag_style_sequence` 决定逐旗样式；离线重新运行脚本应用。
- 输出目录 `flag_styles/*.png` 为可编辑布面颜色贴图；同时打包进 blend。每面旗只有一个布料材质槽，节点 `REPLACE FLAG ARTWORK` 可直接替换图片，边饰也是贴图的一部分，没有独立金属片或悬浮纹章。
- 每面旗独立挂在 `FLAG_SLOT_<双柱ID>_<序号>` Empty 下，原点位于上沿中心，保留样式 ID；旗体网格及所有形态键改为相对该挂点的局部坐标。
- UV 统一：u=0 左、u=1 右；v=0 上沿、v=1 下摆尖端。外部通常以上为首行的图片需按此 UV 约定翻转排版。布面图案双面同一贴图，背面自然镜像。
- `PIN_TOP` 顶点组标记固定上沿；现有风动形态键在换贴图时不变。换几何时须保留上沿中心原点、相同 UV 和固定上沿语义，并重新提供兼容风动，不能任意换网格却沿用不同拓扑的形态键。
- `flag_asset_manifest.json` 保存样式、挂点、尺寸、材质槽和固定组等离线描述，给后续资源导入使用。

仅预留资产结构与数据约定；尚无游戏替换菜单、资源加载器、游戏风场或 MCP 操作。正式接入需另获用户同意并同步 3D 编辑器/MCP。形态键驱动表达式为 Blender 专用，后续导出须转为游戏风动实现或烘焙动画。

## 布面质感和底部丝带收尾修订

按用户截图反馈，将原本终止在柱面上的底部丝带延长为完整绕圈，起端压在出圈段下，避免可见悬空断头。保留原有不规则绕距。

彩旗增加 UV 固定的经纬纱交织凹凸、染色细微变化、0.84–0.98 粗糙度变化和细碎起皱；降低镜面强度，避免塑料般平滑表面。网格由 8×12 增至 16×24 四边形以承载细褶，上沿保持固定。仍为 Blender 离线材质；游戏阶段需要烘焙织纹/粗糙度贴图或实现等价 shader，不能声称 Blender 节点自动被游戏支持。

输出补充：`festival_cloth_detail.png`（布面近景）、`festival_ribbon_detail.png`（下圈收尾近景）。
