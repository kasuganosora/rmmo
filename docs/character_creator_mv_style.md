# MV 素材风格调整样张

## 当前验收状态（2026-09-24）

用户随后改选 **2D 地图 + 3D 人物**。本目录停止制作，后续实现见 `docs/character_3d.md`。

用户认可画风，未认可批量动作装备。`source/equipment_*_Clothing2.png` 及
`equipment_front_left_Clothing2_corrected.png` 均作废：含多余裤管、手臂轮廓、倒地整个人体轮廓及不正确坐姿。
其他动作装备同样未通过逐帧验收。`Motion` 中打包的装备及 `equipment_review.png` 仅是失败草稿，不得作为生产素材。
`tools/pack_mv_style_equipment.gd` 已阻止重新打包失败批次。游戏默认素材根目录尚未切到本目录。
后续须先做单独的裤子坐姿、倒地帧，检查两个裤腿和腰裆结构，再与素体叠加核对。

2026-09-24：停止上一套角色素材的批量重绘。用户要求改用 RPG Maker MV 素材调整风格。

本轮范围是先确定面部和整体风格，制作成年男女各一款样张。保留 MV 的头身比例与五官布局，降低饱和度、柔化描边，使用偏白暖肤色。头像单独绘制，不能把行走精灵的低分辨率脸部直接放大作为头像。

参考源：本机 RPG Maker MV `NewData/img/faces/Actor1.png` 与 `NewData/img/characters/Actor1.png` 中下排前两位黑发人物。

输出：`assets/character_creator_mv_style/style_sample.png`，由内置 ImageGen 生成的风格对照样张。样张中的穿衣效果仅用于展示，不是 Body 生产素材。正式图层继续要求素体、头发、五官和装备可独立替换。

本轮没有把样张切成图集，也没有将其覆盖进游戏界面。上一套实验素材与功能代码保留，避免把未审阅的新样张直接批量接入。
