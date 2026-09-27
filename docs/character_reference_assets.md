# 用户提供的角色参考（2026-09-27）

参考资源位于外部 content_root，当前为 `D:/code/rmmo_runtime`。原始压缩包保持不变。

## 女仆装

`C:/Users/luna/Desktop/Maid.zip` 为造型依据。外部 `assets/characters/source_models/maid/Maid.fbx` 和衣服贴图与压缩包对应文件的 SHA256 一致。

制作入口为 `tools/prepare_maid_equipment.py`：直接读取原始 FBX，保留原衣片、袖口花边、围裙、蝴蝶结及 UV，再适配共享骨架。此前重建封闭肩背、圆筒袖子和背带的方案已废弃。细分增加顶点用于贴体，不用删除原衣片修复穿模。当前男性肩部仍有局部穿模，不能视为全部外观验收通过。

## 女性体模

`Female_Body_Base_Mesh_Model.zip` 中的 Blender/GLB 已放在 `assets/characters/source_models/female_base_reference/`。这是比例和轮廓参考，没有替换游戏共享素体或骨架。正、侧、背灰模对照位于 `review_artifacts/character_3d/female_base_reference_*.png`。

## Templar Knight 皮肤

两卷 RAR 已联合读取，项目素材位于 `assets/characters/source_models/templar_skin_reference/TemplarKnight_UE4/Content/TemplarKnight/`。

实际找到的材质包括 `Materials/M_TK_Face.uasset`、`M_TK_Skin.uasset`、`MasterMaterials/M_Skin.uasset` 和 `MasterMaterials/SSSProfile/SP_Head.uasset`。材质标识表明包含 Subsurface/SubsurfaceProfile、基础法线与细节法线混合、分区粗糙度和高光控制；目前未解析数值参数，不推断其精确设置。

`tools/inspect_skin_reference.py` 从 UE4 压缩源数据提取了 21 张原尺寸参考图，并校验压缩块长度和图像解码，输出在同目录下的 `extracted_skin_maps/`：

| 类型 | 文件 | 尺寸 |
| --- | --- | --- |
| 脸部底色 | TK_Face_Albedo | 4096² |
| 脸部法线、AO、厚度、透光 | TK_Face_Normal / AO / Thickness / Translusency | 8192² |
| 粗糙度分区 | TK_Face_Roughness_ID | 4096² |
| 微凹陷 | TK_Face_Cavity | 2048² |
| 身体法线、平铺法线/粗糙度 | TK_Body_Skin_* | 1024² |
| 四组细节法线和粗糙度 | SkinDetail1–4_* | 1024² |

完整清单、源路径、尺寸和源格式见 `extracted_skin_maps/manifest.json`。BGRA8 与 RGBA16 源分别处理通道次序；这些 PNG 是 8 位观察副本，高位深原资产仍完整保留。不把缩略图误报为原始贴图。

这套参考说明皮肤层次需要共同考虑底色变化、粗糙度、法线和透光。贴图使用其他模型的 UV，不能直接覆盖现有脸/身体。当前只完成查找、提取和观察，尚未把此参考迁移至运行时共享皮肤材质。

### Templar Knight 几何提取结果

已使用 UE Viewer 官方 GitHub 仓库内的 umodel.exe 成功导出六个角色版本（Default、Concept、Dynamic，各含有/无披风）至 `exported_meshes/TemplarKnight/Meshes/`。这些是 StaticMesh，导出 GLTF 无 Skin/骨架；源文件中的 FBX 导入记录不代表压缩包包含原 FBX。

Default 的材质槽 6 为 M_TK_Face（15,230 三角形），槽 12 为 TK_Skin（1,566 三角形）。去披风款皮肤移至槽 11，几何数量与包围范围相同。分离并渲染确认：皮肤保留头颈及髋部至大腿上段，不含完整胸腹、手臂、小腿和脚。服装、盔甲和手套不能误算为裸身体。因此可提取原始头部及局部身体参考，不能直接作为完整共享换装素体。

`inspection/TemplarKnight_original_parts.blend` 为按材质分离的灰模检查文件；原始 GLTF 保留 UV 和网格数据。`inspection/TemplarKnight_skin_parts.glb` 为局部皮肤网格，名称刻意不称完整 Body。正侧背检查图、网格报告、六版本清单和复现脚本亦保留在 inspection。游戏角色未被替换。
