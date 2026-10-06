# 2D 地图与 3D 角色原型

> 本文保留早期方案历史，不代表当前地图与身体方案。继续角色工作先读 [2026-09-27 素体与换装复盘](character_lessons_2026_09_27.md)、[新女性身体](female_body_axis_runtime.md) 和 [换装验收](female_surface_wardrobe.md)，避免把旧基线重新当成现行决定。

2026-09-24：用户确认保留 2D 地图，改用 3D 人物。停止批量生成 2D 动作装备图集。

项目开关 `rmmo/characters_3d=true`。角色移动、格子坐标、碰撞、服务器装备数据及地图前后景仍使用原来的 2D 系统。
`character_view_3d.gd` 用独立、透明的 SubViewport 和正交相机渲染角色，再在原人物脚底位置显示 ViewportTexture。
玩家与远端玩家、创建角色、选角头像、装备窗口使用此显示组件。

当前成年女性及成年男性都基于用户提供的 `artoria.zip/default.fbx`；男性按用户指示从女性网格派生。青年男女仍是旧几何原型，尚未精修替换。

## 用户模型接入（2026-09-24）

检查了用户提供的 Theresa、Rose、Artoria 三份模型：均有骨骼和面部形变。Artoria 的完整版本保留衣服下的皮肤，先选它适配。
原件复制到 `assets/characters/source_models/`；该目录有 `.gdignore`，避免 Godot 直接导入 FBX 或调用 Blender。
包内 readme 的来源与条款原样保存到派生素材 `SOURCE.txt`，不将其称为原创模型。其他两份尚未接入游戏。

`tools/prepare_artoria_character.py` 在 Blender 中从原件重建派生文件：保留 UV、完整皮肤、65 根骨骼、56 个面部形变；拆出上衣、裙装、靴子、头发配饰；重置初始表情并转换过曝的 FBX 材质。
输出 `assets/characters/imported/artoria/character.glb` 和 `editable/character.blend`。素材均保持在 git 忽略目录。
`tools/refine_character_models.py` 再生成最终的 `assets/characters/imported/female/character.glb` 和 `male/character.glb`，各自附有 `editable/character.blend`。
男性修改肩宽、腰胯、胸部、下颌和眼部比例，并同步变形骨骼静止位置及全部表情形变；原盘发剪短并补上后脑网格，改为棕色。男性上衣去掉胸前蝴蝶结，改为蓝灰色。
两者从完整身体网格派生独立长裤，保留权重；原裙装另存为隐藏的 `SkirtVariant`，初始装备的“旅行者长裤”现在实际显示长裤。增加可自动隐藏的独立基础内搭，卸装才显示，身体网格不烘焙衣物。
`character_imported_rig.gd` 按体型缓存和加载男女 GLB；青年体型目前仍使用 15 骨原型。
导入时缓存 PackedScene，实例保留原始权重蒙皮和表情数据；将原来 T 姿势及局部骨轴转换到动作控制器。
上衣、下装、鞋、测试腰带与测试剑为独立对象，装备更新不重建模型，也不重置动作时间。原贴图上的黑色长袜提取为带权重的独立覆盖网格，归入鞋子开关；男女身体改用偏白的独立皮肤材质，派生模型内不再把黑袜贴图当皮肤。
运行时在身体网格上附加装备遮挡区域标记；着装时仅隐藏衣服覆盖的皮肤片元，卸装还原完整身体，避免屈膝时皮肤穿出裤子。没有删除身体顶点，也不把装备合并进身体。
发型下拉列出当前体型的盘发/短发和无发；肤色、发色、服装配色通过独立实例材质调色，支持 glTF 的 albedo 或 emission 纹理。头像相机适配新头部比例。

验证：`tools/test_character_3d.gd` 覆盖四体型、八方向和八动作的骨骼数值有效性，导入模型权重存在，独立卸装、玩家装备同步、创建界面衣服开关。
测试还覆盖面部形变保留、移除头发、材质调色以及内搭与外装的可见性切换。
`tools/capture_refined_adults.gd` 输出成年男女的头像、素体正背面、穿衣对照 `artifacts/character_3d/refined_adults.png`。
`tools/capture_imported_character.gd` 实际渲染面部、穿衣/卸装正背面、行走、施法、坐地及坐椅；加 `-- --male` 检查男性。输出 `imported_review_female.png` / `imported_review_male.png`。
世界截图脚本加 `-- --imported` 使用女性派生模型，已验证在现有 Axel256 2D 地图显示及坐下。
成年角色的待机、行走、冲刺、施法和死亡已接入下述动作库；攻击和坐姿仍为程序姿势。测试通过不代表美术完成；衣物细节、第二套发型、青年体型及长裙变形尚待精修。世界编辑器试玩退出时仍有原先的 1 个 ObjectDB 实例泄漏提示，不属于模型测试成功声明。

## 2026-09-25 捏人参数

成年男女支持瞳孔（虹膜）自选颜色；成年女性增加胸部大小 0–100 滑条，50 为源模型默认值。
`Customization` 保存 `eye_color`（空串保留原色，否则规范化 #RRGGBB）和 `bust_size`（0–1，默认 0.5），读取旧数据使用默认值，拒绝非法颜色并限制尺寸范围。
颜色仅替换源脸部贴图中的绿色虹膜，保留眼白、深色瞳孔、高光以及面部表情形变。
胸部在静止网格坐标中对身体、上衣和基础内搭施加相同平滑变形；保留骨权重、UV 和装备遮挡标记，并根据局部变形重新计算法线。每个实例使用独立变形网格，避免影响其他角色。
创建、选角头像、装备面板和游戏角色均读取同一外观字典；卸装及动作切换不丢失参数。青年几何原型暂未提供这两个新控件。
`tools/test_character_customization.gd` 检查 JSON 往返、默认值、无效输入、实际几何变化、蒙皮/表情保留、换装保持参数和创建面板联动。
`tools/capture_character_customization.gd` 输出 `artifacts/character_3d/customization_options.png`，显示三种瞳色与尺寸 0/50/100 的实际渲染。

## 旧几何原型

以下为尚未替换的模型实现记录：四种体型共用 15 骨骨架，使用 BoneAttachment3D 驱动刚性分段网格。

造型第二版：用截面网格替换圆球式脸型、躯干和四肢，增加下颌/面颊、杏形眼白、虹膜、高光、眉毛和收尖发束。
衣服改为有肩腰轮廓的短外套，裤腿随骨骼分段，继续保持独立换装。女性默认使用较长的齐耳发。
实际渲染对照输出为 `artifacts/character_3d/refined_review.png`（头像、穿衣、卸装三行）。
这次改善的是现有模型造型，仍未替代后续的权重蒙皮和动作精修。
衣服、腰带、裤子、靴子分别是可开关的网格组。裤子只有一个腰臀网格、两条大腿与两条小腿网格；从不写入素体。
主手装备暂用一把通用测试剑验证手骨挂点，尚未按物品分别制作武器。首饰、头盔、副手及 NPC 专用模型尚未迁移。

动作包含站立、走动、冲刺、攻击、施法、死亡、坐地、坐椅子；目前是程序控制的骨骼姿势，不是精修动作。
换装备保留方向、动作及播放时间。体型暂以比例区别，面部只有一个基础样式、头发两种几何变体。
后续正式美术应替换为具有权重蒙皮的统一骨架模型和同骨架服装，精修关节、面部、发型、坐姿与穿模。
单个角色当前使用 256×256 渲染目标；隐藏角色停止更新渲染。大量同屏角色仍需性能测试及共享渲染优化。

验证命令：

```powershell
godot --headless --path . --script tools/test_character_3d.gd
godot --path . --rendering-method gl_compatibility --script tools/capture_character_3d.gd
godot --path . --rendering-method gl_compatibility --script tools/capture_character_3d_world.gd
```

截图输出 `artifacts/character_3d/`。世界截图走现有 Axel256 编辑器试玩入口，不修改地图。

渲染方式参考 [Godot Viewports 官方文档](https://docs.godotengine.org/en/4.4/tutorials/rendering/viewports.html)。

## 2026-09-25 Universal Animation Library 接入

用户提供 `Universal Animation Library[Standard].zip`。包内 License.txt 标为 Quaternius / CC0 1.0，原始 README、License 和 Godot_Setup.png 保存在 `assets/characters/source_models/universal_animation_library/`。选择无根运动的 `UAL1_Standard.glb`，地图位移仍由原 2D 控制器负责。

`tools/retarget_universal_animations.gd` 离线采样 30 fps，把源骨骼的全局旋转相对于静止姿势的变化转到男女目标骨骼，再写回目标局部旋转。映射 52 根骨骼，含肩膀、脊柱、手指、脚趾；保留目标骨长、蒙皮、表情和独立服装。髋部位移按身高缩放，站立动作按原脚/趾支撑高度补偿不同身体比例。循环末尾 0.1 秒平滑闭合。

输出 `assets/characters/animations/{male,female}_universal.res`；`character_animation_library.gd` 缓存并插值播放，运行时不加载源人偶。资源缺失则回退程序动作。素材仍为 git 忽略项，需要随游戏资产分发，不能只拉取源码。

| 游戏动作 | 库内片段 | 时长 |
| --- | --- | --- |
| 待机 | Idle_Loop | 2.5 秒循环 |
| 行走 | Walk_Loop | 1.333 秒循环 |
| 冲刺/跑步 | Sprint_Loop | 0.667 秒循环 |
| 施法 | Spell_Simple_Enter + Shoot + Exit | 1.467 秒 |
| 死亡 | Death01 | 2.4 秒，末帧保持 |

动作切换对旋转、髋部位置及模型根节点进行短过渡；走/跑切换保持周期相位；动作持续时间同步到玩家控制帧。死亡时扩大渲染目标与正交视野，维持像素密度及地图脚底锚点，避免横躺后被原方形窗口裁掉。

仅上述成年男女动作已迁移。Sword_Attack、椅子相关动作暂未接入，坐地不在本库动作清单中，原有攻击与两种坐姿仍保留。青年体型仍为旧原型。

验证：`tools/test_character_motion.gd` 检查脚部高度、循环接缝、死亡保持、动作打断过渡和施法控制时长；`tools/test_character_3d.gd` 回归八方向、独立换装、玩家与捏人界面；`tools/capture_library_motion.gd` 输出成年男女四动作的真实渲染帧。

## 共用骨架、胸部次级骨骼与女仆测试装备

成年男女使用相同的 67 个骨骼名称/层级；身体比例与静止骨长允许不同。增加 `SecondaryBreastLeft` / `SecondaryBreastRight`，父级为 `mixamorig:Spine2`。女性身体、原上衣、基础内搭及女仆裙装有平滑次级权重；男性保留兼容骨骼供同一件衣服绑定。

`tools/add_female_secondary_rig.py`（男性加 `-- --male`）及完整重建脚本 `refine_character_models.py` 保存真实骨骼和蒙皮到 `.blend` / `.glb`。`character_soft_motion.gd` 在主动作与切换混合完成后驱动左右独立阻尼弹簧；行走/跑步有延迟与回弹，停步逐渐收稳，胸部大小改变幅度和回弹速度。每个通用 CharacterModel3D 实例独享状态，玩家和未来 NPC 使用同一层逻辑，无玩家控制器依赖。不是逐帧重建网格的形变替代品。

用户提供 `Maid.zip`，内附 CC0 许可。`tools/prepare_maid_equipment.py` 只提取粉白裙装/围裙和皮鞋，不替换原人物身体、脸或头发；另从共用身体生成贴合长袜。将源服装绑定到男女共用骨架，按身体比例分别生成适配网格。输出 `assets/characters/equipment/maid/{female,male}/outfit.glb` 和可编辑参考文件。玩家/NPC 使用同一个道具 ID 和外观变体 ID，男女不设装备限制，不以复制两份物品来区分体型。

- `maid_dress`：粉白女仆裙装，胸部槽，Clothing1=2。
- `maid_shoes`：女仆皮鞋（含配套长袜），脚部槽，Boots=2。

进入世界的初始背包获得各 1 件，保留已穿旅行者套装。当前服务器的背包本来在进入角色会话时重置，赠送跟随现有初始化方式。装备裙装时隐藏长裤/腰带外观（保留装备与属性），换回上衣或卸下裙装时恢复；裙装和鞋子分别换装。原长裤、鞋子、捏人参数、动作方向与时间不会因换装而重置。

`character_equipment_3d.gd` 将独立服装按骨骼名绑定现有身体，不把装备烘焙到素体，也不保留第二套运行骨架。`test_maid_equipment.gd` 验证真实进入世界赠送、背包交换、同一物品在男女身上显示、骨骼名称兼容、换回旅行者装、播放状态保留。`test_character_soft_motion.gd` 验证身体/服装的非零次级权重、左右独立回弹、停步稳定、NPC/玩家实例隔离。

尚未替换青年几何原型；新权重服装的可视适配范围目前为成年男女。裙摆使用骨骼蒙皮，尚未做布料碰撞模拟，极端动作仍需后续精修。

### 女仆鞋袜修正

源 Maid FBX 的脚骨轴向与身体底模不同；鞋子改用实际脚部空间对齐，并从目标脚的邻近顶点转移踝/脚趾蒙皮权重，避免直接套用 FBX 骨轴旋转造成鞋面和鞋口扭曲。丝袜脚尖和脚底收进鞋内。

`maid_shoes` 显示名改为“女仆皮鞋与丝袜”。运行时显式将 MaidShoes、MaidStockings 都映射到 Boots（鞋槽）；MaidDress 仅属于 Clothing1。测试补充裙装独穿、鞋袜独穿、卸鞋及换旅行者短靴，不允许残留上一套丝袜。`capture_maid_footwear.gd` 输出男女足部近景；加 `-- --moving` 检查走跑姿势。

### 输入方式与走跑速度

WASD/方向键默认行走（0.32 秒/格），鼠标寻路默认奔跑（0.16 秒/格，保留原常规移动速度）。Shift 或“键盘移动始终奔跑”可覆盖键盘默认模式。键盘接管会取消寻路，当前格走完后下一格按键盘模式执行；最后一个寻路格仍按奔跑完成。

每步先结合输入来源和地图 no_dash 得到实际走跑状态，再同时驱动动画与移动 Tween；禁跑区域不再出现慢速移动却播放跑步动作。加速/减速状态倍率继续通过同一时长计算应用。

验证：`tools/test_player_locomotion_modes.gd` 执行真实键盘分支、路径队列、Tween 到达、键盘中断与禁跑地块检查；`tools/test_move_speed.gd` 回归状态倍率。

### 黑白款、头饰槽与丝袜材质

新增 `maid_dress_black`，胸部槽映射 Clothing1=3，与粉白款（2）共用同一份蒙皮网格。独立实例材质仅将粉色裙身改为黑色，围裙/褶边保持白色。两款都沿用胸部参数、次级骨骼和裙装遮挡规则。

新增 `head_accessory`（头饰）装备槽，与已有 `head`（头部装备）分开，装备面板顶部各占一格。`maid_headpiece` 映射 HeadAccessory=1，为独立白色褶边/黑色发箍网格，绑定共用 Head 骨骼，男女可穿，卸下不隐藏发型或裙装。未来兔耳等使用同一槽位、独立变体即可；此次未制作兔耳。新头饰是程序建模的独立网格，不冒称从原 Maid 包提取。

新款裙装与女仆头饰加入既有出生赠送列表。装备服务器、比较提示、快照和背包交换沿用通用槽位逻辑；测试覆盖头饰独立卸下、头盔槽互不占用，以及物品到模型的映射。

MaidStockings 使用独立织物着色器，结合当前角色肤色做微透肤混色，正面覆盖率 90%、掠射角约 96.5%，粗糙度 0.60、镜面强度 0.26、无金属度。因为身体被装备遮挡裁掉，透明效果在材质中合成肤色，而非 Alpha 透出空洞；这保留肉色暗示和柔和反光，避免原皮革式高亮。鞋子仍保留皮革材质，鞋袜仍共占 Boots。

验证：`test_maid_equipment.gd`、`test_equipment.gd`、`test_equipment_server.gd`；视觉对照 `artifacts/character_3d/maid_black_headpiece.png`。


### 六种发型与天气联动

成人男女均支持 FrontHair1=10 女士短发、11 男士短发、12 公主切、13 长发、14 束发长发、15 轻空气刘海波波头；0 无头发，原始 1/2 保持兼容。捏人选择、随机、换男女和保存使用同一部件 ID。青年仍为原先占位模型，尚未适配这批成人发型。

`tools/build_character_hairstyles.py` 保留来源前发片并生成独立发束，产物位于 `assets/characters/hair/{female,male}`。新增三个 Head 子骨，运行时接到共用骨架（70 骨），根部固定，发梢权重渐增。每个人独立弹簧状态，走跑/转向后有延迟与回落；原始发型不受新增发骨驱动。材质使用柔和发束明暗，无硬亮金属高光。该方案是三分区蒙皮弹簧，并非逐发丝物理或完整身体碰撞求解。

天气 compose/blend 新增地图空间 wind 向量：x 东、y 南，表示吹向方向。天气定义可设置 `wind_direction: [1,0]` 和 `wind_strength: 0..1`；默认雷暴最大，晴天微风，室内为零。WeatherFx 统一生成阵风采样，雨雪与地图人物共享；角色预览不读取地图风。发骨将世界风变换到角色局部坐标，站立也受风，转身不改变世界风向。当前屋檐仅保留原雨雪遮挡逻辑，没有新增逐 NPC 建筑风场遮蔽。

验证：`test_character_hair.gd`（12 个男女发型组合、静止风响应/回落、运动、UI保存、场景天气传递）、`test_weather.gd`、`test_maid_equipment.gd`。`capture_hairstyles.gd` 与 `capture_hair_wind.gd` 输出实际 Godot 渲染；头饰保持独立装备。

波波头按参考进一步收窄颧骨以下轮廓并向内卷；新增 UV2 高度渐变，所有发层与男女模型共用一致高度映射，深发根—亮中段—偏冷发梢。渐变基于所选发色，不影响其他发型；未加入参考图头饰。

公主切（12）按最新确认移除胸前两条长发，后发缩至肩胛骨，保留脸颊短切层；顶部/侧面收窄、刘海采用波波头同款短碎内扣，UV2 渐变映射独立适配后发长度。波波头（15）保持已确认形状。

发骨现有后蒙皮采样碰撞约束：最多72个蒙皮采样点，对随头/胸/双肩骨移动的4个解析胶囊迭代推出；接触耗散速度，后发统一绑定 Back 防止独立位移撕开接缝。它是简化发束碰撞，并非逐顶点、逐发丝或任意服装网格碰撞，极端姿势及厚衣服仍需专门检查。`test_hair_collision.gd` 验证男女五类动作与风吹下采样点退出胶囊。

修复短发碰撞撑开：碰撞累计世界位移按发型限制（短发0.012、长发0.035），每帧先清除动作混合继承的旧碰撞位移；仅单步限幅不足以防止多轮迭代拉伸。碰撞代理若与拟合发型冲突，优先保形，允许剩余接触，不能将采样点全部推出作为唯一通过条件。`test_hair_collision_bounds.gd` 覆盖男女波波头/公主切六次动作切换与风吹，实际运行截图由 `capture_bob_collision.gd` 生成。

束发长发（14）沿用已调整的低顶部与脸侧短发，后发在后颈用简单皮筋汇合，发尾约肩胛骨；Gather/Tail/Tie 共用后发骨避免皮筋与发束错位，刘海作轻微偏分斜向收尾。运行态预览脚本 `capture_tied_hair.gd`，位移限幅回归测试包含14。

男士短发（11）按参考改成三层错落碎发、偏分短刘海、后颈收短，使用深根浅梢材质；共用成人男女骨架及短发碰撞位移上限。运行态四向预览为 `capture_short_male.gd`。碰撞回归对11使用仅测试中放大的头部代理强制触发接触，避免天然无接触导致漏测。

披散长发（13）按参考加入偏分刘海、胸前及后背松散 S 形波浪、错落发尾和暖桃渐变；不含参考图盘花/珠饰。后发共用 Back，前发按左右发骨蒙皮，沿用累计碰撞位移限制。运行态四向预览脚本 `capture_long_hair.gd`；回归限幅检查现覆盖六种成人男女发型。


### 全局 K 系列发色色板
- `hair_palette.gd` 按参考图 K-001～K-230 提取代表色，230 色共享于男女、六种发型与 NPC 随机配色；色块提示显示编号和 RGB。
- 新发色用稳定 ID 1001～1230，旧 MV 色带 ID 保持原义，已有存档不会被重新解释。新建角色默认 K-012。
- 启用选色时，发根至发梢采用同色相深浅渐变，覆盖各发型原有固定蓝色或暖色渐变；束发皮筋保留独立深色。
- 色值是照片取样的近似色；角色实际显示仍受材质与场景光照影响。
- 验证：`tools/test_hair_palette.gd` 检查全部颜色、稳定编号、2D 明暗方向、存档往返、3D 材质与创建界面选色；预览 `artifacts/character_3d/hair_palette_preview.png`。


### 外部头发素材与切换缓存
头发资源整体迁至 `{content_root}/assets/characters/hair`，本机为 `D:/code/rmmo_runtime/assets/characters/hair`。包括男女 GLB、贴图、Blender 源文件和独立运行时 `hair_10.scn`～`hair_15.scn`。工程不再保留此素材目录。运行时沿用项目 content_root 配置，不回退到工程资源。

修改发型后运行 Blender 构建脚本（输出根目录可用 `RMMO_CONTENT_ROOT` 指定），再执行 `godot --headless --path . --script tools/bake_hair_runtime.gd`，从 GLB 生成每款独立场景。分发时携带外部 runtime 目录。

发型/发色切换只更新头发，复用身体、服装、骨骼和动画；每个人物缓存已访问发型，共享 Shader。建角页在人物初始化阶段预备六款，避免首次点选时才读盘和创建网格。缓存随人物释放。初始化仍有一次加载成本，不等同于零加载时间。

`tools/test_hair_switch.gd` 验证外部资源、男女全部发型/原始发型/无发切换、骨骼不增长、人物对象保持一致，并输出切换耗时。


### 外观编辑统一增量更新
成年导入角色的瞳色/恢复默认、肤色开关与选色、发色、胸部大小及兼容旧存档的服装染色参数统一经 `update_appearance` 更新。只改变材质参数、变形权重或发型缓存，不重建身体、装备、骨骼及动画。结构字段或体型改变仍走完整构建。

身体肤色更新复用遮罩材质，面部染色材质复用现有实例；关闭染色、恢复默认瞳色会重置相应参数。建角预览共享控制动画资源，外观编辑不再重启动作，同帧修改继续合并。换装保留原有可见性更新路径。

验证 `tools/test_appearance_updates.gd` 覆盖男女连续 100 次组合编辑、瞳色恢复、肤色开关、装备切换、模型/网格/动画状态复用，以及建角主预览、头像和随机配色的真实事件路径。本机组合编辑逻辑约 1 ms，不包含 GPU 帧呈现耗时。


### 战斗动作与站姿/女生跑步
外部 `{content_root}/assets/characters/animations/{female,male}_combat.res` 由 `tools/retarget_combat_animations.gd` 离线生成。UAL2 原始 GLB 和 CC0 许可在外部 `source_models/universal_animation_library_2`。不把源模型载入运行时。

- 空手按刺拳、直拳、勾拳轮换；持剑按 A/B/C 轮换。另有普通连击、重击连段、突进。双手装备标记默认选重击连段。当前来源是剑类动作，并非每种武器都有专属动作。
- 施法复用 UAL1 的片段，提供标准流程、快速释放、含蓄力停留的流程。UAL2 Standard 没有新增施法片段。建角动作菜单逐款预览，空手/持剑预览同步装备可见性。
- 主要技能按 skill_id 映射动作，也接受 skill_anim 的 motion 字段。仅改变表现，未修改伤害、判定与冷却；角色动作计时使用片段实际长度，防止原有固定时长截断。
- 剑改挂到源动画实际挥击的 RightHand（当前适配器内部键为 handL）。
- 站姿在角色坐标系校正手臂自然下垂。女生跑步以 Jog_Fwd_Loop 的周期和躯干动作为基础，离线重做重心、手臂和脚部轨迹。旧版直接保留原片腾空高度造成明显跳动，已不再采用；播放速度仍为 1.25。
- `tools/test_combat_motion.gd` 验证 12 款战斗动作、装备分流、时长、有限骨骼姿态、站姿、女生跑步与预览菜单；`tools/capture_combat_motion.gd` 输出关键帧对照图。


### 全量美术资源外置（覆盖前文旧路径）

后续导入排查：原先工程内 `artifacts/` 的验收图片和动画帧仍会被 Godot 导入，`.gitignore` 无法阻止引擎扫描。这些验证文件现也迁至 `{content_root}/review_artifacts/`，原 `.grok/` 预览迁至其 `editor/` 子目录。前文所有 `artifacts/` 输出路径均以这个外部目录为准。GDScript 统一调用 `ArtPaths.review_path()`，Python 使用 `review_path()`；工程内原目录只保留 `.gdignore` 防止误写触发导入。迁移时 1,149 个文件逐一通过 SHA-256 校验。用户随后要求删除验收文件：截图、录像、帧序列、临时对照动画库、验收日志和迁移校验清单已清理；前文验收链接仅是历史记录，文件不再保留。后续验证临时输出到外部目录，查看结果后清理，不累积保留。`.godot/` 是引擎自身缓存，不是美术制作源目录，不应通过每次删除它来解决导入问题。
工程 `assets/` 已整体迁出。角色、服装、头发、所有动画库、2D 捏人素材、原始 FBX/GLB/Blender 文件及许可均保存在 `{content_root}/assets/`，本机为 `D:/code/rmmo_runtime/assets/`。应用图标也从外部加载。迁移清单 `D:/code/rmmo_runtime/art_migration_manifest.json` 记录 721 个原 assets 文件的字节数与 SHA-256，搬迁后全部校验一致。

GDScript 通过 `scripts/asset/art_paths.gd` 解析统一目录，Python/Blender 工具通过 `tools/art_paths.py`（`RMMO_CONTENT_ROOT` 环境变量，默认工程同级 rmmo_runtime）。旧 `res://assets/` 回退已移除。分发需带上外部素材包；工程内保留代码、场景配置和制作工具。`artifacts/`、`.grok/` 是开发验证截图，`.godot/` 是 Godot 自动缓存，不作为游戏美术加载源。

验证：四种体型的 2D 合成/装备、男女战斗动作、3D 外部加载实渲染均通过；工具源码检查避免重新生成到工程目录。

### 跑步摆臂与起伏修正（2026-09-25）

重新核对用户 UAL1 压缩包，Godot GLB 与外部已有源文件一致。本轮查阅日本 Sportiva 的傳谷英里香／中島靖弘[女性摆臂教学视频](https://sportiva.shueisha.co.jp/contents/movie/2020/10/14/go_for_it22/)，以及日本 [RUNNET 教练诊断](https://runnet.jp/movie/form/03.html)。另找到中国[央视张德顺女子马拉松录像](https://tv.cctv.com/2025/11/15/VIDEcsEEUA1e3JuxTQnpBadD251115.shtml)，未据此声称完成逐帧分析。未使用欧美人物跑姿参考。参数是游戏风格调校，不代表女性统一的运动学标准。

- UAL 原 Jog 髋部起伏本身较大；旧版目标模型髋部世界高度跨度约 0.374，头部约 0.359。现在髋部约 0.034，头部约 0.033，保留小幅周期运动。
- 上臂和前臂在角色空间重设方向，肘部弯曲约 83 度，前后交替摆动。原手部横向跨度约 0.32，现约 0.014–0.016；不以局部欧拉角猜测轴向。
- 腿部使用原有两段 IK 离线求解：每脚周期 38% 支撑、62% 回摆，双脚相差半周期；支撑脚匀速后移，回摆曲线匹配接触速度。降低重心时同时重新求脚部姿势，避免穿地。结果烘焙进外部动画，运行时没有新增 IK 开销。
- 走／跑切换使用实际导入片段时长保留周期比例，替换旧的程序动作常量。
- 重新生成：Godot `--headless --path <project> --script tools/retarget_combat_animations.gd -- --run-only`。资源仍在外部 `assets/characters/animations/`，运行中的静态动画缓存需重启游戏或预览进程刷新。
- `tools/test_run_motion.gd` 检查完整循环 181 帧：头部高度、手部中线、脚趾地面、腾空高度、接缝连续性、走跑切换；`tools/test_combat_motion.gd` 检查原战斗分流与站姿。
- `tools/capture_run_cycle.gd` 生成正／侧／背完整循环对比帧，修改前库读取外部 `review_backups/run/female_combat.res`。`artifacts/character_3d/run_comparison.gif` 为开发验收产物，上排修改前、下排修改后；不是游戏加载素材。

### 地图内跑动修正（接续用户反馈）

地图角色尺寸后续按用户红线整体缩小 18%（约一个头高）：共享 `WORLD_RENDER_SCALE` 从 0.546 调整为 0.44772。玩家与远端 3D 角色一起应用，等比例缩放且固定脚底锚点；独立捏人预览比例不受影响。跑动位移校准使用该渲染比例自动换算，缩小后重新检查了支撑脚滑移。`capture_character_3d_world.gd -- --imported --size-review` 可生成同场景尺寸前后对照。

前一轮原地预览没有验证地图移动，不能据其证明步速匹配。女生跑步现增加骨盆带动躯干的前倾，支撑阶段前后跨度由 0.62 增至 1.25 个角色坐标单位，腿部重新求解；继续保留较小的周期起伏。

外部 `dash_female` 片段记录 `ground_speed`，`character_view_3d.gd` 用地图实际位移、角色渲染比例、正交相机像素比例和素材原始地面速度计算动画推进率。这样连续跑动、加速、阻挡都不会继续用固定 1.25 倍时间推进；瞬移不计入跑动距离。独立预览仍使用素材默认速度。当前校准元数据针对女生跑步，其他未校准片段保持原行为。

验证实际启动 Axel256 的 World 场景，走正常 Player 键盘输入、服务器移动判定及 Tween 路径，没有用替代空地图或解除碰撞。完成向右跑、转向走、向左跑，以及实际使用疾风靴油后加速跑。实测普通段约 284 像素/秒、加速段约 372 像素/秒；两者每动画秒推进距离均约 189.474 像素。该动画秒包含素材默认播放倍率，不能直接当作完整步伐周期。

- `tools/verify_world_run.gd`：真实地图运行与连续画面、位置／动画时间记录。采集图片暂存内存，结束移动后编码，避免 PNG 写盘卡顿干扰移动过程。
- `tools/test_run_distance.gd`：侧向支撑脚在 200、400 像素/秒时屏幕滑移均小于 0.01 像素，并检查停住与瞬移不推进步伐。此数值是侧向支撑阶段的测试，不代表所有方向、地形和装备都逐一验收。
- `tools/test_run_motion.gd`：增加前倾断言，完整循环头部起伏约 0.031，检查落脚和循环连续性。
- `tools/test_player_locomotion_modes.gd`：键盘走路、鼠标跑动、路径中断、禁止跑动地块保持原行为。
- 实际地图录像：`artifacts/character_3d/world_run_verified.mp4`；记录：`world_run_metrics.json`。旧 `run_comparison.gif` 是上一轮预览，不能作为这轮地图验证结果。


### 三维入口与人物一致性核查（2026-09-27）

用户反馈登录页「3D 试玩」里的人物不像既有素体。已实际复现：该按钮绕过登录选角，空会话由 world_3d/world_player 隐式取 gender=male，且没有装备快照，因此生成棕发、无上装的男性派生模型。截图中胸部残留轮廓来自既有男性资源，不是本轮白模验收新建的人物。female、male、artoria 三份 GLB 的 SHA-256 均与外置迁移清单一致。本轮没有修改美术文件，也没有将男性轮廓问题标记为已修复。

- 按用户新要求，首页删除「3D 试玩」「3D 编辑」，仅走登录→选角/建角→Loading→三维世界。
- 三维世界拒绝无角色数据的直接进入；不再靠空会话生成默认男性。编辑器内部试玩需要正常角色选择，保留待试玩文档路径及返回标记；缺少同一角色的服务端装备快照时先走正常 enter_world3d。
- active_character 不再让上一角色的 spawn 快照覆盖新选择。玩家模型在入树前完成同一外观/装备配方的赋值，避免先构建默认男性再重建；静态 NPC、战斗 NPC、召唤人物统一使用 CharacterModel3D.create_npc。
- 成人角色只加载 imported/{female,male}/character.glb，移除缺资源时回退原 Artoria/程序占位的隐式路径。青年占位的既有范围没有据此扩展为成人完成度。
- 新增 test_world3d_character_parity，覆盖首页按钮移除、空角色拒绝、正常角色创建与装备快照、旧快照拒绝，以及同一配方下预览/玩家/NPC 的体型、参数、比例、网格几何、装备显隐一致。相关物理测试改为显式提供测试角色，不依赖生产默认人物。

验证：parity、flow、combat、npc_skills、summons、review、editor 逻辑回归通过；flow 执行 Vulkan 图形验证，正常进入显示选定女性角色与初始装备。flow 进程退出仍有一条 RefCounted（引用计数 0）ObjectDB 警告，尚未定位，不据此声称退出资源检查完全无警告。男性派生体自身的胸部轮廓仍是单独的素材修整项，本轮没有用替换默认人物或改摄像机来掩盖它。

### 男性基础美术修整（2026-09-27，接续上节）

上节记录的是修整前核查。本次已实际修改男性制作源文件和 GLB，迁移清单中的旧 male 哈希只保留历史意义；female、原 Artoria 未重建。

- 修正胸部只压平中段所留下的下缘折叠，重建连续胸廓曲面并局部松弛网格。重新计算身体和上衣法线，按同位置顶点平滑 UV 接缝法线；保留脸部原始法线和表情。
- 修正膝部及胸侧局部蒙皮权重，裤装、基础内衬从修正后的身体派生。男性女仆装长袜同步重新派生，袜口使用平面裁切，避免直接删除整面产生锯齿。
- 初始靴子携带的 Stockings 在穿长裤时隐藏，脱下长裤时恢复；不再让两个覆盖层互相穿插。
- 源文件：外部 assets/characters/imported/male/editable/character.blend；运行资源：同目录上级 character.glb。男性女仆装仍位于 assets/characters/equipment/maid/male/。修整前备份在 review_backups/male_body_20260927/。
- 重建：Blender --background --python-exit-code 1 --python tools/refine_character_models.py -- --male-only；随后以相同参数执行 tools/prepare_maid_equipment.py -- --male-only。未传 male-only 时保留原有双体型构建行为。

验证：validate_male_body.py 对比备份，骨骼名称/层级/静止矩阵完全一致，57 个脸部形态键坐标完全一致，身体顶点数不变，身体与相关服装权重归一化。test_character_3d、test_world3d_character_parity、test_maid_equipment 通过。capture_male_body_review 用实际 Godot Vulkan 渲染检查正侧背、行走、跑动、攻击、初始装备、靴袜组合，并检查女性初始装备；本轮日志无 SCRIPT ERROR / ERROR / FAIL。

范围限制：本轮解决男性基础胸廓、局部关节变形及初始装备覆盖问题，不代表所有服装完成美术验收。扩展检查确认女仆装肩领、裙边的黑色碎片来自忽略贴图 Alpha（原贴图约 40.6 万个透明像素），已在共享服装着色器接入透明裁切，男性可编辑材质同步保留 Alpha；重新检查男性跑姿，碎片消失。未据此声称所有动作阶段和服装组合都已检查。发型、脸型未重新设计。运行中的模型静态缓存需重启游戏刷新。

### 脸身肤色与裆部修正（接续反馈）

此前脸部沿用不受光照影响的材质，而身体受场景光照，默认脸部贴图底色也未归一化，导致脸亮身灰。现在 Face 始终使用独立的肤色材质，按原图主肤色 faebde 归一化后与 Body 使用相同 skin_color；两者共享柔和漫反射光照，保留原贴图眼睛、嘴唇和腮红。改肤色/恢复默认增量更新，服装 MaidStockings 的肤色参数一并同步，材质不跨人物共享。

男性身体前裆轮廓收浅并松弛局部网格，BaseBottom 和 Clothing2 从同一修正身体重新派生，避免保留鼓包或产生硬折痕。已更新外部男性 editable/character.blend 与 character.glb；骨骼静止矩阵和 57 个 Blender 脸部形态键（含 Basis）与备份完全一致。

验证：test_character_skin 使用 Vulkan 检查男女默认、深浅肤色、恢复默认、人物隔离、袜材质同步和 56 个导出 morph；采集有方向光和仅环境光两组真实渲染。test_character_customization、test_character_3d、validate_male_body 通过。另检查最新素体与初始装备的正侧视、跑姿和攻击帧；日志无 SCRIPT ERROR / ERROR / FAIL。

### 头顶文字、背光肤色及女性膝部（接续截图反馈）

- 城镇 NPC 名称原来按脚底 +1.85m 固定放置，战斗施法文本按角色原点 +1.3m 固定放置。现在统一使用 character_overhead_label，根据当前头骨 pose、Skin inverse bind、可见头发/头饰/脸部包围体及相机朝向定位，文字底部朝上留出间距。不能直接把导入网格局部 Y 当作世界高度；测试期间已实际发现并修正这个坐标空间错误。
- 面部与身体继续共用肤色和受光逻辑；为匹配现有明亮的头发/服装材质，加入固定柔和补光并降低直射分量。这样背光保留明暗但不会将皮肤压成明显灰黑。这是风格化角色着色，不是严格物理材质。没有更换人物肤色 ID 或重置用户捏人数据。
- 女性膝部沿用的旧自动权重存在突变，裤装从身体复制后继承了折块。现在男女共用局部膝部权重修整；女性不使用男性胸部修整。女性素体、初始裤装/袜层、女仆袜重新生成；女仆袜口使用平面切割。骨骼、静止姿势和 57 个 Blender 脸部形态键与修整前备份完全一致。
- 外部女性备份：review_backups/female_knees_20260927/。构建工具增加 --female-only，避免无关体型重建。

验证：test_character_overhead 覆盖四体型、0.7/1/1.5 倍缩放、站立/走/跑/坐、发型切换及战斗施法文本；test_world3d_map 验证真实世界 NPC 挂接，另通过 test_character_3d、test_maid_equipment、test_character_customization 和源模型比对。Vulkan 图片检查女性站立、行走、跑姿、坐姿、袜装以及有直射/无直射情况下的名字和肤色。未宣称所有服装动作组合都完成全面美术验收。

### 腰带悬空修正

旧成人腰带是运行时固定尺寸椭圆 + 独立扣子，整体刚性挂在 Hips，无法匹配男女真实裤腰，也不能跟随腰部混合蒙皮。现从各自 Clothing2 裤腰裁出窄带，沿外法线留 4mm 间隙，保留裤腰蒙皮；扣子是同一网格上的窄材质区域。移除旧的程序椭圆和悬浮扣子。下摆末段收进裤腰并同步底层腰部权重，修复坐姿时后摆穿出腰带。

已同步男女外部 editable/character.blend 和 character.glb，备份在 review_backups/belt_fit_20260927/。test_character_3d 增加腰带必须是单一带 Skin 的网格、不能是 BoneAttachment 刚性附件的断言；装备独立穿脱回归通过。源文件比对骨架/脸部形态键不变，包含腰带的权重归一化检查通过。实机检查女性正侧背、走、跑、坐和男性初始装备；侧面与坐姿不再有向外悬出的腰带或后摆尖片。

### 裙装身体完整性、握持与坐姿（2026-09-27）

用户再次反馈肩膀和手臂被挖空，说明此前仅检查装备状态和少量截图不足以验收。裙装现在通过 glTF extras 的 garment_kind=skirt 标识，不再套用封闭上衣/裤子的身体裁切；身体与 BaseBottom 保留，由衣服实际遮挡。test_character_body_integrity 使用真实 Vulkan 渲染，对比穿裙前后独立身体层的像素：男女、站立/攻击/椅坐/地坐/倒地、正侧背共 30 组通过。该测试证明身体没有被隐藏，不等于证明衣服不存在任何交叠。

女仆服制作脚本对身体附近网格加密、外推并转移权重，袖子按上臂重建，胸口保留贴体衣片；头饰沿实际头发包络拟合。原始源文件备份在外部 review_backups/maid_shoulders_20260927/，最终男女 editable/maid.blend 与 outfit.glb 位于 content_root/assets/characters/equipment/maid/{gender}/。

武器插槽由共享手骨及食指、中指、小指的静止位置生成，持武器时追加握拳，卸下恢复动画手势。character_equipment_fit 从衣服蒙皮包络推导手部避让，通过双骨 IK 保持肢体长度。测试三个合成衣宽、男女、动画切换及卸下武器，不依赖女仆装 ID。

裙子权重按骨盆与大腿位置分配；共享 character_garment_motion 使用身体推导的骨盆和大腿支撑体，以及有界弹簧位移。外层围裙使用更大的支撑体，避免折叠后单纯法线偏移将其推回裙面。素材约定：COLOR.r 为布料亮度，g 为外层偏移权重，a 为裙摆活动权重；紧身上身为 0 活动权重。新裙装需提供 garment_kind、正确蒙皮和这些数据，并做动作验收。这里是轻量形变与身体避让，不是完整布料物理，没有任意衣服自碰撞或椅子布料碰撞保证。

椅坐使用骨长定位双腿与脚底，空手放到大腿表面。capture_character_seating 按骨长生成白模椅子，检查男女侧面、斜前、低视角、地坐和倒地。capture_character_equipment_review 检查初始装备与女仆服正侧背、走跑、施法、攻击与坐姿。最终 test_character_equipment_fit、test_maid_equipment、test_character_body_integrity 通过；日志无 SCRIPT ERROR / ERROR / FAIL。

### 明亮 ACG 肤色（接续身体发灰反馈）

以下补光方案为中间尝试，后因用户指出缺少皮肤质感而被替换。最终重新生成的材质、女性形体修整和固定棚拍场景见 [character_skin_material.md](character_skin_material.md)。

实际关掉直射光后，原皮肤着色显著变灰，和不受光头发形成反差。脸和身体共享的直射分量从 0.22 调整到 0.12，保色补光从 0.45 调整到 0.65；保留环境色、柔和体积明暗、贴图腮红与眼睛，不修改肤色 ID。补光为风格化发光项，黑暗环境也保留可读性，不按物理皮肤完全变暗。

test_character_skin 对男女默认/深肤色/浅肤色/恢复默认、直射/纯环境光共 16 张真实渲染验收，并增加胸口像素亮度、阴影亮度比例和过曝检查。女性默认胸口均值：直射 fdebe0，纯环境 edddd3；深肤色仍为 996749/8f6144。报告和图片在 content_root/review_artifacts/character_3d/skin_measurements.json 与 skin_*.png。此次只调整共享皮肤着色，不把其他服装和材质的美术效果算作一并验收完成。

米制与 VRChat SDK 的交叉核验见 [world3d_scale_validation.md](world3d_scale_validation.md)。

### 基础内衣款式（2026-09-27）

按用户指定，女性 BaseTop 改为白色蕾丝文胸，包含贴体罩杯、背带与两条共享蒙皮肩带；BaseBottom 改为白色蕾丝三角内裤。男性 BaseBottom 改为白色纯棉三角内裤，无女性蕾丝效果。腿口采用曲线裁切，移除原短裤裤腿，保留裆部和后侧覆盖。白色蕾丝使用花纹与织线表现，具有不透明衬底；不通过透明裁掉身体制造镂空。

制作源在 refine_character_models.py，运行时材质集中于 character_underwear_material.gd，外部男女 character.blend/character.glb 同步重建。源材质保存同款蕾丝纹样（characters/materials/underwear_lace.png）。备份位于 review_backups/underwear_20260927/。沿用既有基础层显隐、共享骨架与女性胸部形变；捏人和装备适配回归通过，并检查三档女性尺寸、正侧背、跑动、坐姿。

### 前裆、女仆袖子与头饰修整（2026-09-27）

女性前裆在源素体上平滑收回，随后生成基础内裤和裤装，避免只改一个装备后切换又复现。重烘焙女性皮肤数据；共享骨架、57 个面部形变、顶点数及蒙皮权重校验通过。

女仆袖子按上臂长度与身体表面重新生成短袖，收小膨胀量，袖山混合身体蒙皮和上臂权重。头饰以头部网格的前后中心定位，沿头发曲面重新采样贴合，后移到头顶中部。男女共用生成逻辑，已同步导出外部制作源与运行资源。

真实运行时检查女仆正侧面、攻击、冲刺，以及女性裤装正面；装备装卸、不同衣宽适配、裙装身体完整性回归通过。截图位于 review_artifacts/character_3d/maid_fit_* 与 male_body_9.png（后者为既有捕获工具命名，实际是女性裤装）。以上验收针对当前资源，不代表尚未接入的所有发型和衣服均已验证。

### 女仆肩背破面复查

上轮侧面验收遗漏了旧肩背花边与新袖子的交叠破面，不能把上轮测试通过视为这项外观问题已解决。本次移除变形的肩背残片，按共享素体重建衣片并保留前胸领结、花边；裁切同步插值 UV 与蒙皮，重合顶点焊接，腋后保留贴体衬片。源袖子识别增加上臂权重条件，避免固定横向范围误删宽体型的胸廓。

捕获工具增加背面、后侧攻击及冲刺，并跟随骨骼调整近景取景。换装测试增加裙摆活动性遮罩断言，防止重建网格时丢失活动权重。源资源与运行 GLB 位于外部 assets/characters/equipment/maid/{female,male}；修改前备份位于 review_backups/maid_shoulders_20260927。

用户指出中间修复误删围裙背带，最终保留两条从前胸越过肩部、连接后腰的白色背带及波浪花边。背带沿实际衣服曲面采样贴合，使用共享身体蒙皮，不能用删除背带来掩盖破面。

生成袖子和背带时逐面校正朝外法线。运行时布料分层会沿法线偏移，镜像面绕序错误即使关闭背面剔除也会把白色外层推入衣身，不能用双面材质掩盖这个问题。

本轮女性款背带、侧后肩及抬臂/冲刺画面已复核。男性款仍能在侧面看到腋后局部皮肤穿出，正面袖山也需要继续收整；这两项不计入外观验收通过。换装、裙摆活动性遮罩和身体完整性回归只证明对应功能，不能替代这项视觉检查。


### 用户原装恢复（取代以上重建衣片方案）

收到用户 Maid.zip 与原图后，确认此前重建袖子、封闭肩背及另造背带改变了设计。以上相关修复方案已废弃。现在直接从原始 FBX 保留衣片、袖口花边、围裙与背部蝴蝶结，用语义骨段方向做重定向，避开源/目标骨滚转差异；上身按身体表面适配，裙摆不投影到最近大腿。UV 和导出三角面数量增加保留检查。白色纹理区域不再自动认定为独立外层布料，防止围裙被额外撑大。

双手避让检查完整手掌及手指跨度，支撑大腿半径从真实素体截面推导。撤回了导致袖子异常膨大的实验性上臂胶囊。男性肩部局部穿模仍未解决，不能标为完整美术验收通过。

本次重新运行 test_character_equipment_fit、test_maid_equipment、test_character_body_integrity 均通过；身体完整性比较固定相同姿势，隔离衣服引起的手部避让差异。它们验证装备、骨架、手部约束和身体保留，不代表所有衣片和动作都没有交叠。新参考资源与皮肤提取结果见 [character_reference_assets.md](character_reference_assets.md)。


### 自然待机与局部手部避让

按用户裙装站姿参考收拢待机双腿，将支撑位置放在髋部下方并校正脚底高度；保留上身呼吸，不修改行走或战斗片段的腿部姿态。空手待机手指放松，持武器一侧仍使用握持姿势。

原手部避让将所有前后位置压成高度/宽度包络，后方蝴蝶结也会迫使前方手臂外张。现使用高度/深度网格记录局部宽度；空手待机选择较小的侧向/前向位移，并优先减少侧向外张。旋转双骨 IK 不拉长手臂，空手手腕自然跟随前臂。无女仆 ID 或固定世界坐标分支。该包络仍为静止空间近似，不是完整的动态布料碰撞。

回归增加后方装饰不干扰前方手部、真实圆柱表面避让（允许从前方避让）、待机上臂外张约束及脚底高度。test_character_equipment_fit 和 30 组 test_character_body_integrity 通过，日志无 SCRIPT ERROR/ERROR/FAIL。真实渲染复核男女粉/黑款，待机正侧背输出 garment_{gender}_{2|3}_idle.png；男性原有肩部局部穿模仍单独待修，未因此修改或删除衣片。
