# VaM 皮肤候选对照

后续进展：原灯光场景已升级为女性关节验收，默认显示新身体站姿，保留静态材质对照脚本。身体改为分轴求解后再展示细分，详见 [female_body_axis_runtime.md](female_body_axis_runtime.md)。以下保留此前静态材质接入阶段的记录。

用户要求适合其东亚角色、明亮且有细节的皮肤表现。本次按肤色、细节强度和完整贴图套装筛选，不把某一种肤色定义为所有东亚人的肤色。

输出：`D:/code/rmmo_runtime/assets/characters/source_models/vam_base_reference/skin_candidates/`。

| 候选 | 实际来源 | 观察 |
| --- | --- | --- |
| aimi_default | RenVR.AimiSkin.1.var / Default | 暖色、细节柔和，适合作为自然肤色基准 |
| aimi_pale | 同包 / Pale | 更明亮，脸与身体过渡柔和；优先作为用户期望的 ACG 材质候选 |
| riddler_2b | Riddler.Skin_2b_4k.3.var | 泛红、斑点更明显，更偏写实 |

三组均提取脸、躯干、四肢的 D/G/N/S 配套图：Diffuse、Gloss、Normal、Specular。共 36 个文件，主要为 4K；Riddler 的四肢法线实际是 8K，未因包名含 4K 而误记尺寸。逐文件来源、尺寸和包内许可字段见 manifest.json。选取包元数据均标记 CC BY；保留作者归属，不把提取结果标为自制。

原始 female bundle 的 DAZCharacterTextureControl 明确标记 `Base Female` UV，面/躯干/四肢的材质编号分别为 `[2,5,11]`、`[15,18,19,20,21,27,29]`、`[0,12,14,16,17,22,23]`。干净基础身体不含槽 29，预览只映射实际存在的槽位。使用这套分区而不是按猜测把耳朵或脖子错误分到 Face。

## 已完成的对照

三组均应用在刚提取的同一个女性原始底模上，使用同一灯光、相机、色彩管理和细分。原图没有改色或重绘。每组有可编辑 `material_preview.blend` 和 `portrait.png`，复现脚本为同目录的 `build_previews.py`。

这是 Blender 材质候选预览，眼睛是统一占位材质。未加入发型、捏脸或化妆差异，避免它们干扰皮肤比较；不能把基础脸型误认为皮肤贴图带来的变化。

## 到客户端的处理

- D 使用 sRGB；N、G、S 作为线性数据。Gloss 不直接当 Roughness，需要转换。当前统一预览映射为 `roughness = mix(0.65, 0.28, gloss)`，仅用于比较，不宣称完全复现 VaM 着色器。
- 脸、身体和四肢使用同一皮肤材质模型、肤色调节和灯光响应，各自绑定匹配的 UV 贴图；保留低频色差，避免重新退化成一块纯色。
- ACG 方向优先弱化过强微法线和油亮高光，保留粗糙度变化、柔和次表面效果和局部血色，而不是整体加大发光来漂白。
- 客户端迁移需继续核对法线方向、镜像 UV、颈/腕/踝接缝，做正光、侧光、背光和暗环境对照。

## 已选定并接入原灯光测试场景

用户确认 Aimi Pale。项目运行资源改名为 `skin_porcelain_01`（瓷白肤色 01），底模改名为 `female_base_v2`。原始来源文件保持不变，运行目录中的 manifest 保留 RenVR、包名、CC BY、原始成员路径及每张贴图 SHA-256。

- 外部材质：`assets/characters/materials/skin_porcelain_01/`，按 `face/torso/limbs` + `albedo/normal/gloss/specular` 命名。
- 外部模型：`assets/characters/base/female_base_v2/female_base_v2.glb`，保留原始网格和 UV，没有烘焙细分或更改脸型。
- 可复现打包：`python tools/package_porcelain_skin.py`。
- 运行：Godot 打开 `scenes/character_skin_studio.tscn`，默认显示新素体近景。沿用原来的棚拍和游戏光照参数；可转身、转灯、切换全身。女性/男性按钮保留旧角色对照。
- 新底模尚无可用运行骨架，因此该模式明确显示“静态；眼睛占位”，装备按钮禁用；切回旧角色恢复装备操作。没有替换正式玩家 GLB。
- 材质按原材质名分配到 16 个皮肤面组，共享三个区域 ShaderMaterial。颜色图使用 sRGB，数据图保持线性，所有贴图生成 mipmap。统一粗糙度转换、0.35 法线深度、0.4 倍 specular、0.1 SSS，无发光漂白。

验证：`tools/capture_porcelain_skin.gd` 在 Godot Forward+ / Vulkan 下检查 16 个区域、12 张 4K 图，并输出两种光照的正面、侧面、背面、全身共 8 张实拍。`tools/test_character_skin_studio.gd` 验证默认新底模、旧角色/装备回切、转身和光照操作。两者通过且无脚本/着色器错误。实拍位于外部 `review_artifacts/character_3d/porcelain_*.png`。基础网格近景轮廓仍能看到多边形，眼球未制作，尚不能代表最终角色品质或动作验收。

### 边缘质量修正

主视口原先没有启用 MSAA，现默认 4×；原灯光验收场景单独使用 8×，离开时恢复之前的设置，不使用 TAA 或后处理模糊。近景还需解决几何轮廓折线：运行 `blender --background --python-exit-code 1 --python tools/build_female_display_mesh.py`，从原始四边形 Blender 底模派生一级 Catmull-Clark 细分的 `female_base_v2_display.glb` 和可编辑 `.blend`。先执行打包脚本，再执行此构建脚本。

验收场景现加载展示 GLB；原 `female_base_v2.glb`、21,556 顶点以及原衣物绑定索引保持不变。展示网格为 168,716 三角形，只供当前近景静态验收，未来动作/衣物仍应在基础拓扑上求解，不能把细分顶点索引直接当作绑定索引。运行实拍脚本增加了三角形数量、UV 和 8× MSAA 的检查；两种光照下正、侧、背、全身重新通过。修复前截图保存在 `porcelain_before_aa.png`；近景仍有基础脸型与占位眼球的限制。
