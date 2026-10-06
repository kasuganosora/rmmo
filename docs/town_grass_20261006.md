# 桥头与街区写实立体草丛

2026-10-06。用户要求两类都保留，交替使用避免单调，并完成调整和优化。参考：[城镇视觉设定](medieval_town_visual_references.md)。11 款预制件已发布，未修改用户城镇地图。

## 来源与调整

- [Quixel Grass Clumps / rbojr](https://www.fab.com/listings/70b6ac17-a842-48d9-81e4-41f80fe160d9)：用户库 Raw FBX，A–C 三款，约 20–23 cm 高，路缘、墙脚矮草。
- [Quixel Wild Grass / vlkhcbxia](https://www.fab.com/listings/50d9a417-73ed-4132-9421-6be3d4f7432e)：用户库 High FBX，A–H 八款，约 11–41 cm 高。包含草穗与矮小散生变体。Raw 下载未确认完成，不把 High 写成 Raw。

实际立体叶片/叶簇使用原扫描颜色、透明度、法线及粗糙度，适度增加青绿比例，保留自然色差和少量草穗。修正 FBX 坐标，统一底部落地。不用地面纹理代替草模型，也不把整丛公告板当近景。两类保留独立身份，混植采用不规则分组、尺度和朝向变化。性能测试排布不是最终街景布局。

## 优化

| 类型 | 近景三角面/丛 | 中景 | 远景 |
|---|---:|---:|---:|
| 矮草 A–C | 2,886–13,142 | 1,298–5,913 | 577–2,627 |
| 野草 A–H | 1,377–11,874 | 568–2,780 | 380–1,482 |

矮草原始 12,291–55,995 面，近景约减少 76.5%。野草近景保守清理，中远景复用来源网格 LOD；未使用来源最低级公告板。11 款近景合计 131,437 → 56,465 三角面。

- 每档一个材质面组。0–12 / 12–25 / 25–55 m 三档，共同范围中心，1 m 迟滞硬切换；55 m 后剔除，没有宣称渐隐无跳变。
- 运行贴图 2K，4K 母版保留。同类跨 GLB 按解码像素内容、尺寸、格式和 mipmap 状态共享纹理；限额弱引用缓存，不仅凭材质名共享，不改变资源身份。
- 双面 Alpha Mask 保留透空、深度和阴影；薄叶背光为实时近似，没有自发光。近中景原生风动，根部固定、顶部摆动及遮蔽响应，远景静态。
- 预制件 `collision: none`，不挡人物。没有新增 MultiMesh 草海或自动生成器，仍独立选择、变换、保存；纹理共享不是全部草丛只有一个绘制调用。

## 验收与偏差

`tools/test_town_grass.gd` 失败数 0：11 款材质通道、朝向、三档网格和纹理共享；真实 HTTP MCP 工具发现、合法放置、非法 ID 无副作用拒绝、撤销重做、保存重开、保存/放置预制件、资源依赖；游戏加载器确认三实例九个 LOD 保留。UI/MCP 沿用相同原生业务，无新增二维接口。

同机位、灯光、曝光对比 4K/原网格与 2K/减面网格的全变体组图，以及矮草 A、野草 A 侧面近景。主要轮廓和空隙保留；局部亚像素叶尖、内部阴影并非完全相同。前景像素平均 RGB 绝对差约 4.90 / 5.61（0–255），只是辅助诊断，不是数学无损证明。扫描原件、母版及对照保留。

400 丛混植测试：RX 7900 XTX，Godot Forward+，1400×850，MSAA4+TAA；可见 345 绘制调用、1,108,096 图元，GPU 中位数约 2.19 ms，风 uniform 更新中位数约 2.21 ms。两个风动时刻有 94,897 像素变化；关主光后的低环境光检查确认草叶正常变暗。不是完整城镇帧率保证；大面积铺设仍需按真实地图验收密度。GPU 测试在不激活的独立桌面执行。

设定偏差：部分野草比动画中的宽弧形叶片更细，保留少量草穗；未强行增宽所有叶片以免破坏扫描形状。两类提供真实材质、自然疏密及高低变化，不声称逐叶复刻参考。验收图不是已完成的桥头景观。

## 文件

运行根 `D:/code/rmmo_runtime/`：

- 原件和 CRC/哈希清单：`art_sources/bridge_street_kit/sources/grass/`。
- Blender：`art_sources/bridge_street_kit/town_grass/town_grass_masters.blend`，保留源网格、优化网格与贴图，默认展示 11 款近景。
- 运行源：`assets/town_grass/`，11 GLB 和 `manifest.json`。
- 验收：`review_artifacts/town_grass/` 下 `validation.json`、`visual_review.json`、`image_metrics.json`、`density.json`、对照 PNG 和日志。
- 资源库搜索“写实矮草”/“写实野草”；`published.json` 记录 11 个正式预制件。未重复列出底层模型入口。

生成：`tools/build_town_grass.py`；复核：`tools/review_town_grass.gd`；发布：`tools/publish_town_grass.gd`（匹配验收文件哈希）；纹理共享：`scripts/world3d/grass_texture_cache.gd`，接原生 glTF 加载流程。

## 2026-10-06 补充：粗糙度 R 通道修复并重新发布

整图真实天空暴露草叶偏蓝灰的镜面反射，追查发现 Quixel 粗糙度源图为 R 通道标量，旧 Blender 直连 Color→Roughness 导出的 ORM.G 几乎为零（矮草均值约 0.063/255，野草约 0.282/255）。原先独立预览缺少实际天空反射，未暴露该缺陷；前述“材质通道通过”只能说明贴图存在，不能证明当时粗糙度值正确。

已在真实 Blender 母版里改为 Separate Color Red→Roughness，并同步修复 `tools/build_town_grass.py`。11 款重新导出与发布，几何、叶色、风动及 LOD 均保留。逐款 albedo 解码像素与旧发布版完全相同；重新打开 `town_grass_masters_before_roughness_fix.blend` 和当前母版做顶点/拓扑哈希比较一致，13 条材质粗糙度链路均已正确取 Red。修复后 ORM.G 平均矮草约 0.883、野草约 0.754。重开母版的运行贴图打包也明确保存 2K PNG，避免材质重导出时意外恢复成 4K；原 4K 仍保留。

`town_grass_roughness_test.log`：11 款、三档材质全部通过新增粗糙度值与 2K 断言，真实 HTTP 放置/拒绝非法 ID/撤销重做/保存重开/预制件捕获及运行加载复验失败数 0。同规格 400 丛测试约 345 绘制调用、1,108,096 图元，GPU 中位 2.062 ms，风更新中位 2.432 ms；该结果取代旧版本性能数值用于当前素材。

最新版 `D:/code/rmmo_runtime/review_artifacts/town_grass/published.json` 已更新 11 个预制件入口及源/资源库 GLB SHA-256；旧不可变库文件仍保留，目录仅替换对应旧版入口，不修改正式地图。粗糙度通道与原件几何证据共存于 `review_artifacts/reference_grass_clumps/roughness_channels.json`、`roughness_fix.json`，实际游戏天空 before/after 和相同问题的新三款修复记录见 [Blender 宽弧草堆](reference_grass_clumps_20261006.md)。旧 `image_metrics.json` 数字来自首次版本，只作历史记录；当前版本按更新后的 PNG 和哈希验收。
