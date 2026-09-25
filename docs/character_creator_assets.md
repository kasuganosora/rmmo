# 原创角色与独立装备素材

> 状态：2026-09-24 用户否决当前面部效果，已停止这套原创素材的批量生成与精修。本文记录的是保留的实验版本，不是已确认的美术方向。新方向改为基于 RPG Maker MV 素材调整风格，样张存放在 `assets/character_creator_mv_style/`。装备独立分层要求继续有效。

素材包位于 `assets/character_creator`。该目录沿用仓库的素材忽略规则，需要与代码一起在本地保留或单独分发。

四种体型：成年男性、成年女性、青年男性、青年女性。每种均有独立 Body，头发、眼睛、眉毛、鼻子、嘴各两款。参考用户给出的 BRP 图片的肤色与比例，图像由 ImageGen 重新生成；未复制参考图的像素到运行时图集。

## 分层契约

- Body 永远不包含可穿脱的初始装备，只保留基础遮蔽内衣。
- 上衣 Clothing1、长裤 Clothing2、短靴 Boots、腰带 Belt 分别为透明 PNG，映射到 chest、legs、feet、belt 装备槽。
- `Customization.part_ids` 保存身体和五官；预览装备单独放在 `equipment`。游戏内外观从服务器装备快照重新合成，空槽不会回退到角色创建时穿着的装备。
- 初始四件装备在 `scripts/char/starter_equipment.gd` 定义，通过实际背包/装备接口发放和穿戴。
- `user://rmmo/mv_chars` 中的整张图是可重建的显示缓存，不是 Body 源素材。换装重新合成，禁止用缓存反向替换 Body。

## 图集

`TV/<体型>`：144×576，单格 48×72，三列静态预览。

`Motion/<体型>`：384×6144，单格 96×96，四列动作帧。每个动作占八行，方向依次为正面、左、右、背面、左前、右前、左后、右后。动作依次为 idle、walk、attack、dash、cast、death、sit_ground、sit_chair。右向由对应左向镜像；动画采用有限关键帧，部分保持帧重复。坐椅图不含椅子，椅子由地图提供。

源图和只读分析的裁切/头部锚点在 `source/`。图像生成负责美术；以下工具负责图集布局、附件定位和验证：

1. `tools/pack_original_characters.gd`：静态身体、头发五官与肤色渐变。
2. `tools/index_character_sources.py`：只读取源图，输出动作与坐姿的裁切/锚点 JSON。
3. `tools/pack_character_motion.gd`：身体和头部动作层。
4. `tools/pack_character_equipment.gd`：四件独立装备层，不写 Body。
5. `tools/test_character_equipment.gd`：四体型、全部动画、单件穿脱后恢复原素体、背包装备流转。
6. `tools/review_character_layers.gd`：逐方向/动作合成审阅图。
7. `tools/capture_character_creator.gd`：真实创建角色场景中切换体型、穿脱和截图，需图形渲染器。

运行 GDScript 工具：`godot --headless --path . --script tools/<工具>.gd`。截图工具去掉 `--headless`。素材重打包后先运行编辑器导入，再验证合成器；旧导入缓存和截图不能代表新图。

## 验收记录

背包→装备→背包、四种体型的 64 个动作方向组合、四件装备独立穿脱后恢复完全相同的素体已通过自动验证。视觉审阅与生成图集分别保存，技术通过不代表逐帧视觉质量通过。

真实 Godot 创建角色界面已通过四体型切换、上衣脱穿和动画加载验证。当前美术仍有待精修项：部分侧向腿部边缘、斜后方装备轮廓与素体不能逐像素贴合；有限关键帧的动作过渡较短。`equipment_review.png` 保留这些问题的审阅证据，不能视为最终美术验收通过。
