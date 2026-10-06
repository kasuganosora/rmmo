# 女性身体：分轴蒙皮与动作验收

2026-09-28 第二十批：`lie_relaxed` 已校正两侧前臂同号旋后、指节屈曲及头颈支撑；地面/白模床、双手和头部近景见 `lying_support_03/`。原 `lie` 不变。后脑间隙约 2.14 mm、双手约 19.07 mm；这是躺稳姿势检查，未完成躺下/起身过渡、软组织接触或穿裙躺下。见实施记录第二十批。

2026-09-28：补上 Godot 最终骨骼姿态同步、连续轴角与手部接触快照，通过 modifier/附着物一致性和原身体回归；局部平移/缩放尚不支持。见 [实施记录](character_progress_2026_09_28.md)。

后续换装进度见 [新素体换装验收](female_surface_wardrobe.md)：表面绑定、源布料数据解析与实验模拟已进入原灯光场景；正式角色替换和全部裙装验收仍未完成。下文保留身体阶段的验证范围。

2026-09-28 本轮增加 `lie_relaxed` 放松躺姿实验，调节头颈、肩肘和手部；原 `lie` 完整保留作碰撞回归，灯光场景中两项独立选择。`capture_relaxed_lying.gd` 保存侧面、俯视及 CPU/GPU 对照，身体基础回归现为八个姿态。当前幅度插值只是关节检查，不能当作自然的“站立→躺下”动作；支撑过渡、床面、穿衣躺下及手指自然程度仍未完成验收，不勾掉整项躺姿待办。

当前范围是新女性素体的身体变形基础与原灯光场景验收，不是已经完成正式玩家替换或新换装。沿用用户确认的 GenesisFemale-1 体型、Base Female UV 和 `skin_porcelain_01`，没有重新雕刻体型。

## 已接入

- 从本地 `a_per` 人物预制资源筛选唯一包含全部 80 个权重节点的骨骼组；排除同名旧骨骼/其它组。保留父子层级、女性原始关节位置和朝向，逐项校验其未叠加形态变化。
- 原始 21,556 个顶点全部有权重，最多 8 条求解记录。X/Y/Z 权重、完整权重归属、旋转顺序和 bulge 参数分别保留，没有平均成普通 LBS 权重。
- `female_axis_body.gd` 创建 Skeleton3D 并提供 CPU 参考实现；`female_axis_compute.glsl` / `female_axis_gpu.gd` 提供实例独立的 GPU 求解。局部旋转按源顺序作用，部分权重在原始关节坐标系中计算，完整权重使用骨骼全局变化矩阵；之后重算身体法线。
- 先变形控制网格，再用 Catmull-Clark 权重求展示细分。85,253 个展示点、168,716 三角形；UV 接缝共享同一空间点结果。服装绑定仍应引用原始身体，不使用展示索引。
- 原皮肤贴图按文件路径和修改时间共享，实例的姿态、骨骼、计算缓冲及动态位置/法线纹理独立。法线贴图切线空间依据变形后的表面导数重建。
- 原 `character_skin_studio.tscn` 默认新女性身体，提供站立、屈肘、抬臂、抬腿、坐下、躺下及 T 姿，动作幅度滑块与循环检查。旧男女按钮明确标注对照，装备仍只在旧角色对照中可用。
- 坐姿增加简单白模椅，座高依据身体位置估计；所有验收姿态按最低身体点对齐地面。椅子只是接触检查工具，不是已实现坐椅交互或软组织受压模拟。
- 场景使用 8× MSAA；近距离单级阴影范围 8 米，避免腿部、椅脚出现无关的阴影噪点。

## 验证与限制

`tools/capture_female_axis_body.gd`：原始静止逐点一致、动作后复原、完整根旋转保持刚体、骨长不变、七种姿态不穿测试地面、混合轴旋转、CPU/GPU 逐点对照及动作幅度调节。Godot Forward+ / Vulkan、RX 7900 XTX 上，七种基本姿态最大位置差约 7.4e-7 米。不同运行中 GPU 单次求解、同步读回和两张纹理提交约 1.8–4.7 ms；CPU 参考约 44–75 ms。**这些不是整帧渲染性能或多人场景预算。**

`tools/test_character_skin_studio.gd`：新旧对照、坐姿椅子、动作幅度、躺姿、循环和场景切换。实拍输出 `review_artifacts/character_3d/female_axis_*.png`，包含坐姿侧面。

当前 GPU 使用本地 RenderingDevice，同步读回后上传主渲染纹理。该实现先保证与参考计算一致；大规模角色需要改为共享渲染设备/批量计算，避免每实例读回同步。没有 RenderingDevice 时保留 CPU 校验路径。API 使用方式参照 [Godot compute shader 文档](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html)。

尚未完成：正式玩家/NPC 的统一资源切换、已有战斗/行走动画重定向、新底模头发与眼球、形态参数、身体弹性物理，以及服装表面绑定转换/碰撞。当前关节测试姿态不是已经验收的游戏动画库。没有复现 VaM 的全部平滑、软组织和物理控制器，不能宣称与其所有动作完全一致。

## 外部资源与复现

目录 `assets/characters/base/female_base_v2/`：

- `female_axis_rig.json`：源关节、权重、旋转顺序、来源哈希。
- `axis_gpu_*.bin`：可重新生成的 GPU 权重、静止位置与法线邻接输入。
- `female_display_topology.json`、`subdivision_stencils.rgba32f`：可重新生成的展示细分权重。
- 原 `female_base_v2.glb`、原始源文件、来源说明均保留。

顺序：`extract_female_rig.py`（UnityPy 环境）→ `build_female_subdivision.py` → Godot `capture_female_axis_body.gd`。前置皮肤打包与静态展示构建沿用 `docs/vam_skin_candidates.md`。运行时只读外部资源，不需要安装 VaM 或 UnityPy；它们仅用于本地离线提取。
