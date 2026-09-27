# 共享皮肤材质与棚拍验收

2026-09-27，接续用户对「纯色、没质感」和女性胸臀形体的反馈。此前把固定补光提高到 0.65 的方案已被替换。

## 参考方向

- 用户指定 [NSFW Body](https://www.fab.com/listings/e6f59378-6307-405c-8f6c-d3323d338aa4)：观察柔和皮肤反光及胸廓、胸部、腰臀过渡。页面说明展示由 Marmoset Toolbag 4 渲染，包含基础色、法线、粗糙度和遮蔽等贴图。
- 用户指定 [Kitsune Inari](https://www.fab.com/listings/898e03d9-beb5-4ae4-bee5-c2c71a171aaa)：观察风格化角色在完整装备下的材质区分与受光。
- 补充 [Stylized Skin Materials](https://www.fab.com/listings/ad672c08-fbef-4803-ad5c-e6a6a55acc2b)：观察柔和高光、细节尺度和不同肤色的反射。参考的是材质表现，没有购买、提取或复制这些商品的贴图/模型。

## 生成与运行时

tools/bake_character_skin_detail.py 从现有共享 Body 和骨骼烘焙局部遮蔽、关节暖色过渡，按原 UV 生成 2048×2048 的 skin_basecolor.png、skin_normal.png 和 skin_orm.png。ORM 为遮蔽/粗糙度/金属度，皮肤金属度为零。基础色采用 sRGB，法线和 ORM 为线性数据，读取后生成 mipmaps。额外的 skin_detail.json 按静止顶点坐标保存遮蔽和色差，保留无贴图时的兼容显示。顶点匹配验收要求大于 98%。

资产保存在 content_root/assets/characters/imported/{female,male}/。editable/skin_material.blend 是带完整 PBR 节点的可编辑副本；原始 character.blend 的骨架、UV 和脸部表情没有被材质生成器修改。几何源更新后应重新运行烘焙工具。支持 --female-only / --male-only。

character_skin_material.gd 集中实现柔和直射、略暖的阴影、宽而弱的镜面高光和低强度半球补光。脸部保留原表情和五官贴图，使用同一受光函数；身体使用新贴图，以原默认肤色归一化乘入用户选择的肤色。贴图按体型缓存共享，材质参数按人物独立。没有更换捏人色板或另建玩家/NPC 人物体系。

法线细节是轻微微表面起伏，局部遮蔽来自当前身体的静止几何。它不能替代高模雕刻，也不等于完整的皮下散射或动态自遮蔽；不会据此宣称已达到参考商品的几何精度。

## 女性形体

refine_character_models.py 的 refine_female_surface 做离线小幅形体修整：上胸过渡、胸部下方曲面和后侧腰臀过渡，并重算跨 UV 接缝的平滑法线。以前胸下缘和臀腿交界处的旧自定义法线会造成明显分块。身体与贴身上衣使用同一修整，基础衣物/裤装由该身体生成，女仆服随后重建适配。没有改变角色整体尺度，也没有新增胸臀的固定运行时偏移。

修改前备份：content_root/review_backups/female_surface_20260927/。与备份比对，骨架静止矩阵、身体顶点数、57 个源脸部形态键完全一致，蒙皮权重归一化检查通过。

## 固定测试场景

直接运行 scenes/character_skin_studio.tscn。可切换男女、转身、转灯、基础层/初始装/裙装、全身/近景、棚拍/游戏灯光。没有增加首页试玩入口。

棚拍采用深灰背景、正交近景、固定曝光、主光/弱补光/侧后轮廓光：主光 (-32,-32,0)、能量 1；补光 (-12,48,0)、0.30；轮廓光 (-25,145,0)、0.8；环境光 0.25。源页面没有给出布光参数，这些是根据参考图推定的本地可重复布光，不能当作原作者的 Marmoset 设置。游戏对照使用项目日间方向光及环境光参数。

## 验证与图片

- test_character_skin：真实渲染男女深浅肤色、恢复默认、脸/身体统一参数、56 个导出表情、材质隔离、新贴图实际载入、顶点匹配率与明暗范围。
- test_character_skin_lighting：同相机、同人物和同灯光对比旧平色方案和新材质，按真实身体像素检查明暗变化、转灯响应和纯白过曝比例。结果在 skin_lighting_metrics.json；对比图 skin_material_before_after.png 左旧右新。
- test_character_skin_studio：验收独立场景控件与共享角色配方。
- capture_character_skin_studio：男女正面、斜侧、背面。
- capture_female_shape_review：女性尺寸 0 / 0.5 / 1，正侧背、跑动与椅坐，基础层和裙装。female_shape_base.png、female_shape_maid.png 每列分别为三个尺寸。
- test_character_customization、test_character_body_integrity、test_character_equipment_fit 继续检查增量捏人、穿裙身体完整性与装备/姿势兼容。

所有图片位于 content_root/review_artifacts/character_3d/。评估包含几何和皮肤材质，不把头发、眼睛、布料的全部美术质量算作同时完成。
