# 裙装验证素材集

用户要求弃用旧女仆装作为验收样本，改从其本地 VaM 素材库选取多种裙装。后续按 Lolita/复杂裙装继续筛选，当前提取 8 组、19 个服装及配件网格；源压缩包未修改。

| 项目编号 | 作者 / 原包 | 用途 |
|---|---|---|
| maid_classic | GaryHo / maid_cloth_v1.2 | 黑白女仆连衣裙，领口、泡袖、腰线及裙摆 |
| maid_separate | AmineKunai / Maid_Costume_Set.1 | 分体女仆上衣、裙子、头饰、袜子 |
| skirt_pleated | AmineKunai / Pleated_Skirt.1 | 百褶保持与腿部碰撞 |
| skirt_pencil | AmineKunai / Short_Pencil_Skirt.1 | 贴身髋部、步幅与坐姿 |
| dress_long | maru01 / dress_l01_V2.4 | 两版连衣裙与帽子、蝴蝶结；源名 L 不表示及地长度 |
| dress_elf | JD / Elf_Dress_Set.1 | 及地裙、分离布片、地面碰撞 |
| dress_layered | maru01 / dressM08.4 | 长袖连衣裙、领口、自由裙摆 |
| dress_ruffle_layers | maru01 / HW_dress02.2 | 泡袖束腰裙、独立外裙与帽饰，层间碰撞 |

外部路径：`D:/code/rmmo_runtime/assets/characters/source_models/garment_validation_set/`。每组 `item_*` 中保留原 VAB/VAJ/VAM、贴图、模拟遮罩及来源缩略图；增加解析 JSON、原始 OBJ、可编辑 Blender 文件及 `garment_review.glb`。catalog 和逐件 manifest 记录作者、包内 CC BY 字段、源路径、SHA-256、几何和绑定统计。

## 已验证的范围

- 所有 19 件网格/UV/绑定段完成解析，索引和数值校验通过；VAJ 引用的贴图与 simTexture 文件全部存在。
- Blender 转换保留原顶点、面和 UV 数量，无减面、改版型或删背带操作。
- Godot Forward+ 实拍 8 种组合，共 9 个主服装网格，检查三角形数量与 UV，见 `review_artifacts/character_3d/garment_validation_catalog.png`。
- GLB 材质仅供轮廓检查：转换基础颜色、基础贴图、法线和透明度；原始 spec/gloss/decal/模拟参数仍保留在 VAJ，尚未完整复现 VaM 着色器。标量 Bump 在 Blender 中保留为高度凹凸，不能把 GLB 导出视为其效果完全等价。

## 尚未完成的范围

这是完整保存来源数据的静态样本库，不是已验收的运行时换装。衣服未挂到新人物骨架，也未运行碰撞/布料。二进制模拟尾部原样保存并统计，尚未解码移植。

主裙装全部存在超出干净身体 21,556 顶点的绑定：经典女仆 100 条、分体裙 18 条、百褶 114 条、包臀 33 条、L 两版各 18 条、精灵裙 77 条、M08 18 条。需要转换拼接身体索引或重新建立绑定；不得截断索引或仅凭静态叠放判定合身。

后续先用经典女仆与百褶/包臀裙检查基础跟随，再用多层、及地裙覆盖坐、躺、抬腿、转身和地面接触。头饰、袜子及每种活动区域单独验证。旧女仆资源仍保留以免破坏现有角色，但不再作为新换装验收样本。

## 复现

1. `python tools/extract_garment_validation_set.py`
2. `blender --background --python-exit-code 1 --python tools/build_garment_validation_meshes.py`
3. `Godot --path . --script tools/capture_garment_validation_set.gd --quit-after 300`

脚本只写外部资源目录，截图与日志也保存在外部 review_artifacts。

## 复杂款追加筛选

扫描本地可读 VAR 中的包内服装条目，未发现明确名为 Lolita/Lilita 的服装。按原始缩略图检查多个候选后，现有 dress_l01 的双版本、帽子与多组蝴蝶结最接近装饰裙结构；追加 HW_dress02 的基础裙、独立外裙和帽子，未选其掀裙变体。它是泡袖束腰/荷叶边款，不能称为已找到标准甜系 Lolita 大裙撑款。

新三个网格分别 11,436 / 4,920 / 6,323 顶点，Godot 中 22,259 / 9,560 / 12,552 三角形全部与原始面数匹配；外裙有 32 条绑定引用干净身体外的点。保留完整原始贴图及模拟记录。`capture_garment_validation_set.gd -- --complex` 输出三组静态组合到 `garment_complex_catalog.png`；没有宣称布料模拟通过。

追加检查还发现旧 `dress_long/item_02` 帽子的 GLB 比源面三角化少 4 个三角形（1572/1576），源 JSON/OBJ/Blend 仍完整。该帽饰转换未验收通过，不纳入复杂款组合，需修复导出后再使用；这不影响已通过数量检查的两款裙身和新 HW 帽饰。
