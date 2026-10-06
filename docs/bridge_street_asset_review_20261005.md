# 石桥与彩旗街景素材清单和自审

2026-10-06 墙挂布幡与公会红色燕尾长旗：用户已明确红旗从屋檐附近垂至离地约 30cm，实物结构资料及离线样品见 [制作记录](wall_guild_banners_20261006.md)。短红旗已被用户纠正，不作为本轮合格尺寸；本批尚未接入编辑器。

2026-10-06 边石与踏步石后续：11 款已按用户批准加入默认资源包预制件目录，真实 HTTP、保存重开及游戏碰撞体加载通过，见 [制作与发布记录](street_edge_stones_20261006.md)。用户地图未修改。

2026-10-05。视觉目标见 [城镇视觉参考](medieval_town_visual_references.md)。全部美术采用写实风格；本页区分现有资源、离线样品和缺口，不代表整套模型已通过美术验收。尚未接入游戏或修改地图。

2026-10-06 更新：用户已明确授权本批素材接入游戏，上文“尚未接入”为当时状态。接入制作、实际发布清单与验证结果以 `town_props_integration_20261006.md` 为准；离线限制已解除，不合格占位稿仍不得标为成品。

## 资源与当前状态

2026-10-06 宽冠阔叶树后续：用户认可橡树预览并要求对齐优化；已制作宽冠河岸款优化母版及三档游戏候选，见 [宽冠橡树优化记录](street_oak_game_20261006.md)。原版保留，未新增固定树库目录项，也未自动修改地图。下表“只有高细节母版”为此前阶段状态。

### 2026-10-06 立体草丛选型补充

后续调整与优化已完成，11 款立体草已发布为编辑器预制件。材质、三档 LOD、风动、共享贴图及 HTTP 保存/重开验收见 [草丛交付记录](town_grass_20261006.md)。下段保留选型时状态。

用户确认两种都要，交替、混合使用避免单调；必须是有高度和侧面轮廓的立体草丛，地面草纹理不计作交付。已从 Fab 用户库下载并通过 ZIP CRC 与 Blender FBX 导入检查：

- [Quixel Grass Clumps / rbojr](https://www.fab.com/listings/70b6ac17-a842-48d9-81e4-41f80fe160d9)：原始 FBX 包，A–C 三款，配套 4K 颜色、透明度、法线、粗糙度、透光等贴图。作为路缘矮草来源。
- [Quixel Wild Grass / vlkhcbxia](https://www.fab.com/listings/50d9a417-73ed-4132-9421-6be3d4f7432e)：高质量 FBX 包，A–H 八款，每款 LOD0–3，配套 4K 植物贴图。作为桥头、河岸长草来源。原始包下载超时，尚未确认完整落盘；高质量包完整，不冒称原始母版已齐。

原件解压目录：`art_sources/bridge_street_kit/sources/grass/`；`inventory.json` 记录档案哈希及贴图清单，`mesh_audit.json` 记录 35 份 FBX 的三角面与尺寸。当前完成的是素材取得和网格检查，不是最终美术/运行验收。长草预览偏细、含枯叶与草穗，后续须按盛夏参考调整青绿比例与叶片体量，保留自然疏密和间隙；LOD 最低级需检查是否为公告板，不能把它当近景立体草使用。两种都保留独立资源身份；混植采用不规则分组、尺度和朝向变化，避免等距交替。尚未修改地图或发布草预制件。

以下运行资源路径均以 `D:/code/rmmo_runtime/` 为根。

| 镜头元素 | 资源位置 | 自审与交付状态 |
| --- | --- | --- |
| 石拱桥、桥墩、桥面、压顶石栏 | `packs/default/sources/authored/bridges/`；`packs/default/assets/bridges/medieval_stone/` | 已有三套桥梁模块；仍须按镜头组合核对，不能把模块视为完整复刻桥 |
| 石墙红瓦房、烟囱、老虎窗 | 既有建筑预设；`docs/town_house_styles_20261005.md` 与 `town_frontage_rhythm_20261005.md` | 复用已存在房型；同栋统一窗型、楼层和屋顶保持可分离 |
| 浅石铺装及草地 | `packs/default/assets/materials/paving/outdoor_flagstone/`；`terrain/mossy_grass_vcjmej0s/` | 有写实贴图；沿路自然收边和门前踏步组合尚未验收 |
| 水面及天空 | 既有 `river_materials.gd` 与 `assets/weather/clouds/` | 已有运行资源；本轮没有搭完整场景验证水色、反射与岸线 |
| 长花池、暖砖/浅砖、直形/L形 | `art_sources/town_planters/boxwood_review/optimized/` | 用户已认可低植物优化版本，仅离线批准 |
| 高植物花池 | `art_sources/town_planters/boxwood_review/tall_plant_review/` | 已有离线样品；仍需纳入此次整体写实复审 |
| 粗彩柱、金黄丝带、跨街布旗 | `art_sources/town_festival_posts/` | 已有模型、图案替换槽与风动预览；布料近景及丝带连接须按参考复审 |
| 单横板木围挡 | `art_sources/town_low_fence/` | 已有用户认可比例版本，保留至少 50cm 的下部支撑露出 |
| 四面垂边小贩棚、可换货物 | `art_sources/town_market_stalls/` | 模型已存在；矿石等近景货物需复审是否仍有刻意低多边形感 |
| 带旗路灯 | `art_sources/banner_streetlamp/` | 复用独立模型；以既有文档确认正式接入状态，不能混为本轮新增授权 |
| 门旁小壁灯 | `art_sources/small_wall_lantern/` | 已做昼夜样品；自审修正圆滑支架、铁件细纹、玻璃透射、灯底与蜡烛支座，待最终比例与近景验收 |
| 大冠绿叶树 | `art_sources/bridge_street_kit/english_oak_procedural/` | 已用 Quixel C 型制作宽冠、绿叶的 Blender 参数化母版，保留原件与优化切换；见 `parametric_street_oak_20261006.md`。旧程序树和 Trees60 秋色疏冠稿仍淘汰；当前母版不是游戏 LOD 成品 |
| 河岸岩石、草丛、矮石墙、晾衣、远塔、搬运包裹 | `art_sources/bridge_street_kit/bridge_street_missing_assets.blend` | 已有 13 件离线补缺草稿，不能视为全部写实定稿；自然物优先替换写实来源，逐件再审 |
| 外墙布幡、圆形山墙窗、门前踏步石 | 当前参考描述及现有旗帜/建筑组件 | 尚未核实全部具备适合此镜头的独立成品，保留为缺口 |
| 日常人物与交谈、搬运姿态 | `assets/characters/imported/` 既有角色基础 | 基础角色不等于已完成该镜头服装、姿态或 NPC 行为；按后续氛围层处理 |

## 已发现的问题与处理

- 程序化树曾复用黄杨叶材质，不能据此称为符合参考的成年阔叶树。转为 Fab 真实树种模型选型，旧稿保留用于构图占位。
- Tree Master 的 [Desktop Trees Pack 60](https://www.fab.com/listings/43b47da3-b552-4b6f-9deb-d638c26d3021) 已从库下载。树 1 做过 8m 高度与树冠调整、树干保守减面；6410 → 5168 三角面。实际渲染仍是秋色疏冠，不符合设定的盛夏茂密绿冠，**不通过本镜头自审**。不能用减面数值掩盖造型不符；该资产为 CC BY 4.0，保留作者、链接与修改说明。
- 继续选型的 [Quixel Megaplants: English Oak](https://www.fab.com/listings/83642c38-7661-4df1-8629-0422e1898d26) 在用户库中提供 USD（114.04 MB）。本次下载超时且本地只有未完成文件，重试尚未获得完整压缩包，未导入 Blender；不能写为已完成或已验收。
- 2026-10-06 下载复查：`C:/Users/luna/Downloads/tree_english_oak_forest_01_usd.zip` 已完整下载（119,578,436 字节），ZIP 全文件 CRC 检查通过。已解压至 `art_sources/bridge_street_kit/sources/english_oak/`，Blender 附带 USD 库可读取四款 A–D 树模型、独立 Foliage 文件；另有四份 DynamicWind JSON。该包没有贴图文件，检查 A 款的两种材质仅有棕/绿纯色 UsdPreviewSurface，没有纹理节点；不能据此称为完整写实材质成品。当前状态改为“模型包完整，贴图/材质与树冠造型待验收”，此前下载超时描述仅为历史记录。
- 同日参数化制作更新：选用 C 型恢复原始 UV、复用已购树皮材质并重建程序化绿叶表面，扩大带叶细枝以补足林地原型偏疏的问题。505 个带叶模块保留共享实例；整树展开等效三角面减少约 19.8%，不靠默认删叶减面。全树、近景与逆光固定条件对比及参数验证记录在 `parametric_street_oak_20261006.md`，该状态替代上一条“尚未制作”的阶段说明。叶表面不是原版扫描贴图，仍不能把 Blender 优化完成称为游戏性能验收通过。
- 小壁灯初版支架有明显折线、材质过于均匀，玻璃偏浑浊；已改曲线支架和细微铁表面起伏，补灯底、烛座、灯芯、门铰与门扣。六面折顶是结构选择，不应把所有硬质平面一律平滑化。总高约 84.5cm 是制作选择，非截图测量，仍需门边尺度对照。
- 壁灯夜间渲染发现补光球在玻璃后可见，已缩小灯源至 4mm、移回烛芯，并让火焰不遮蔽补光。薄玻璃对直射阴影采用透光近似，镜头射线保留玻璃；属于 Blender 预览方案，游戏端灯光与玻璃需另行实现和验收。
- 补缺草稿中的部分材质使用 Blender 程序节点/BOX 投影。导出的 GLB 不自动保证相同效果，正式使用前需烘焙或重建对应材质；当前只以 `.blend` 渲染为样品。

## 优化验收方式

保留母版；分部件减面，保留 UV、硬边/平滑法线、叶片透明轮廓、布料褶皱、开口和安装连接。用同一相机、光源、曝光、渲染采样输出原版/候选版，检查常用距离、近景、侧光和逆光。记录实际求值后的三角面数，不能仅统计未应用修改器的基础网格。

可见的轮廓削平、投影变形、叶簇稀疏、亮暗条纹或高光接缝都判为失败并回退。减面比例由通过的图像决定，不设统一硬指标。当前尚未完成所有资产的成套对比，不能宣称“全部无损优化”。

逐项自审按“参考轮廓与比例 → 真实结构连接 → 材质与光照 → 用户可调参数 → 优化对比”进行，偏差须先修正或明确列出，再交用户确认。用户确认以前不部署游戏。

## 现实结构资料

- [Historic England：Warkworth Bridge](https://historicengland.org.uk/listing/the-list/list-entry/1020741)：已有桥梁制作的真实结构参考。
- [Met：Wrought-iron wall bracket](https://www.metmuseum.org/art/collection/search/206323)：仅参考铁支架弯曲与连接方式，年代及体量不能直接用于本灯。
- [National Trust：Carriage lamp](https://www.nationaltrustcollections.org.uk/object/1700589.1)：仅参考灯框、玻璃和灯源维护关系，不声称本款为已考证中世纪灯具。


## 2026-10-06 补充：松树形针叶树

用户已明确验收通过并要求作为编辑器预制件。小型、成熟、倾斜三款正式预制件已通过真实 HTTP 保存至默认资源包，放置/撤销重做/保存重开测试失败数 0；记录见 [松树预制件交付](pine_editor_integration_20261006.md)。

最新交付为 V6：用户允许减少针叶微观精细度，以游戏视角不结块为重点。近/中/远景约 48,308/7850/3690 三角面，三款已更新库目录项，旧文件及母版保留。分层透空通过所列视角检查，微观体积有所简化，LOD 尚为硬切换；功能及真实 HTTP MCP 测试失败数 0，用户地图未修改。详见 [V6 自审记录](pine_editor_integration_20261006.md)。以下 V5 为历史结果。

后续 V5 已通过所列视角及功能检查并加入共享编辑器资源库（不是自动布置到城镇地图）：每棵 2,195,732 三角面，保留母版，恢复游戏薄叶背光及风动。实际检查范围、实时光照近似和较慢的编辑操作明确记在 [V5 自审记录](pine_editor_integration_20261006.md)，不宣称数学无损或适合密集森林。下段为前期高细节母版阶段记录。

已购 Quixel Baltic Pine 的 USD 已下载并保留原件；D 型制作原生 Blender Geometry Nodes 母版和保守减面候选。详细参数、素材限制与验收见 [Baltic Pine 参数化记录](parametric_baltic_pine_20261006.md)。这是高细节母版，不把 UE 程序化支持或 Blender 实例化等同于游戏 LOD 已完成；没有向当前地图写入这株树。最终图像审查及参数结果见母版目录的 JSON 记录。
