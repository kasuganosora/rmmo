# 现有能力与插件复用清单

下次实际开工优先读 [人物系统选型与收尾路线](character_next_session_plan.md)：包含捏人框架补查、推荐决策、接入阻塞与完成门槛。本表作为候选来源索引。

2026-09-27，用户要求：把我们将用到的内置能力、现有插件一起预研究并记录，避免重复造轮子。

本次是文档调查与少量本地源码核对，**没有安装、购买、运行候选插件或修改运行时**。重点覆盖人物系统，并补充此前地图/编辑器需求。不是整个游戏全部依赖的穷尽调查，也不是宣布候选已经兼容。来源为官方文档、作者仓库；判断与限制单列。正式采用前固定提交/版本、核对许可证和本机 Godot 4.7.2 / Blender 4.5 兼容性。`stable` 文档会随发布变化。

顺序保持：当前身体/服装视觉与动作接触 → 性能优化 → 新增 MMD 二次元表情。调查不等于立即接入；Go 持久化与正式地图仍暂缓。

## 人物与换装

| 我们需要的能力 | 已有能力/候选及来源 | 如何复用、哪里不能直接解决 |
|---|---|---|
| 裙装布料、身体与层间接触 | 内置 SoftBody3D/Jolt、GPU Cloth Simulation 等，详见 [布料预研究](godot_cloth_options_research.md) | 首先评估现成求解器。自然垂手、内外层、坐姿和源版型按同一标准验收，不能把披风演示当复杂裙通过。 |
| 头发、尾饰、衣带等二级摆动 | 内置 [SpringBoneSimulator3D](https://docs.godotengine.org/en/stable/classes/class_springbonesimulator3d.html) 与弹簧骨碰撞节点 | 优先评估内置骨链动力学，不再默认自写弹簧。它的碰撞体系独立于 PhysicsServer3D；不是完整布面碰撞，也不自动解决软组织体积保持。核对骨骼缩放与更新时序。 |
| 动画状态、混合、上下身分层 | 内置 [AnimationTree](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html)，配合 AnimationPlayer/AnimationLibrary | 可复用状态机、BlendSpace、过滤和 OneShot；不需要重做通用动画混合器。行走速度、脚滑、技能事件和网络状态仍需项目接线与验证。 |
| 不同人形骨架之间重定向 | 内置 [RetargetModifier3D](https://docs.godotengine.org/en/stable/classes/class_retargetmodifier3d.html) | 先测公共骨骼语义与静止姿态映射。重定向姿态不等于重建源分轴权重；新身体的自定义求解不能未经验证换成普通蒙皮。 |
| 持刀、握持点、脚底/坐姿目标约束 | 内置 [BoneAttachment3D](https://docs.godotengine.org/en/stable/classes/class_boneattachment3d.html)、[TwoBoneIK3D](https://docs.godotengine.org/en/stable/classes/class_twoboneik3d.html) | 附着用于武器/饰品，IK 用于明确的交互目标。手指握法、极向量、骨轴与座位姿态仍须制作；**不许用 IK 抬手绕开裙子穿模**。当前旧角色代码已使用 BoneAttachment3D，先复用已有接线。 |
| 头部/视线朝向 | 内置 [LookAtModifier3D](https://docs.godotengine.org/en/stable/classes/class_lookatmodifier3d.html) | 可做朝向与角度限制；眼球、眼皮联动与眼神风格仍需模型和逻辑。不能将头部 LookAt 当成完整眼动追踪。 |
| 受击倒地/布娃娃（若后续需要） | 内置 [PhysicalBoneSimulator3D](https://docs.godotengine.org/en/stable/classes/class_physicalbonesimulator3d.html) | 可作为骨骼刚体模拟基础。不是衣服求解器，也不是身体软组织模拟；不要因此扩展当前任务。 |
| 身体形态、面部基础形态键 | 内置 [MeshInstance3D blend shape 接口](https://docs.godotengine.org/en/stable/classes/class_meshinstance3d.html)，由动画轨道控制 | 可复用播放/混合能力，但引擎不会生成好看的脸型和表情。我们 GPU 自定义展示路径能否直接使用内置形态键需验证，不能认为改一个属性就会生效。 |
| 服装离线权重迁移、表面跟随 | Blender [Data Transfer](https://docs.blender.org/manual/en/4.3/modeling/modifiers/modify/data_transfer.html)、[Surface Deform](https://docs.blender.org/manual/pt/4.5/modeling/modifiers/deform/surface_deform.html) | 可作为离线制作工具/对照。查到的官方页面分别为 4.3 英文与 4.5 葡语；本机选项需核对。不能把 Blender 修改器当成 Godot 自动执行的运行时功能；普通权重迁移也不能等价替代我们的分轴权重。 |
| 换装槽位、完整身体遮罩、跨体型合身 | 本次未确认能直接覆盖本项目的通用现成插件 | 保留现有统一装备配方和事务换装。资产元数据、内搭、显露区域、体型适配仍需项目实现；“未找到”不等于不存在。插件不得删身体或修改衣服款式来通过验收。 |

## 表情、VRM/MMD 与材质

此组仅预研究；新增 MMD 表情的实际实施仍在性能之后。

| 需求 | 已有方案/来源 | 本项目采用边界 |
|---|---|---|
| VRM 导入、MToon、表情绑定和弹簧骨 | [V-Sekai/godot-vrm](https://github.com/V-Sekai/godot-vrm) | 作者列出 VRM 0/1、MToon、表情动画轨道和弹簧骨支持，也注明约束与重定向组合、弹簧性能及 lookAt 接线限制。优先评估导入与材质复用；不要另写完整 VRM 解析器。不能自动把 VRM 衣服适配成当前身体。正式选用前核对主插件与附带 shader 的许可证。 |
| MMD 源模型/动作的离线检查 | [MMD-Blender/blender_mmd_tools](https://github.com/MMD-Blender/blender_mmd_tools)，GPL-3.0 | 支持 PMD/PMX、VMD/VPD 制作管线；作者表中 v4.x 覆盖 Blender 4.2–5.2，可作为本机 4.5 的候选。优先用来核对形态名称和源效果，不自行从零解析。离线工具与游戏分发依赖分开记录。 |
| Godot 直接导入 MMD | [n0pen/godot-mmd-plugin](https://github.com/n0pen/godot-mmd-plugin)，GDExtension | 作者说明仅顶点 morph、基础材质，VMD 仍开发中，物理不等价原 MMD。仅列备选，构建、许可及版本兼容尚未核实，不能当完整 MMD 实现。用户要 MMD 表情标签不代表必须支持运行时 PMX/VMD 导入。 |
| MMD 标签与二次元组合表情 | 内置 blend shapes/动画混合；VRM 插件可提供已有源绑定 | 表情命名映射、互斥/叠加、爱心/星星/圆圈眼及腮红仍需素材和统一语义层。现有身体没有某形态时插件不会补出来。范围见 [表情需求](character_expression_requirements.md)。 |
| 口型 | 内置形态键/动画；已有 VRM 源可导入 viseme 绑定 | 本次只确认表达/播放基础，不引入口音识别或面捕依赖。实时音频驱动、ARKit 52、VRChat 口型兼容未自动纳入需求。 |
| 皮肤质感与二次元光照 | 内置 [StandardMaterial3D/ORM](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)，MToon 见上 | 优先复用已有 PBR 参数、法线和粗糙度等能力，MToon 用于相应风格对照。MToon 不等于高质量皮肤；脸身一致、贴图 UV、曝光、亮暗层次仍要实拍。不能将参考角色贴图直接套到不同 UV。 |
| 发丝、轮廓、阴影等锯齿 | 内置 [3D 抗锯齿](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html) | 先比较 MSAA/TAA/FXAA 等现成选项及适用渲染器，无需另造抗锯齿。检查移动拖影、透明发丝和 shader 自定义变形；不能只提高采样数就宣称全部解决。 |

## 地图与编辑器相关能力

这里只登记已有任务的复用入口，不重新开始正式地图制作。

| 需求 | 已有方案/来源 | 本项目判断 |
|---|---|---|
| 三维地形编辑与显示 | [Terrain3D](https://github.com/TokisanGames/Terrain3D)，MIT、C++ GDExtension | 提供可编辑地形、分区、LOD、植被和高度图路径。值得评估，未安装。现有地图文档格式、游戏内编辑器及导出构建能否接入需另查；不能直接把 Godot 编辑器工具当玩家可用的编辑器。 |
| 地形上的技能预警 | 内置 [Decal](https://docs.godotengine.org/en/stable/classes/class_decal.html) | 可作投影显示候选，需核对 Forward+/Mobile 支持及表面选择。它不能替代技能命中/高度规则，多层建筑、悬崖遮挡和动画边缘需验收。 |
| 寻路与局部避让 | 内置 [NavigationAgent3D](https://docs.godotengine.org/en/stable/classes/class_navigationagent3d.html) | 优先复用导航和避让接口；不自动解决地图切换、服务端判定或实际角色移动。 |
| 雷达、小地图、素材预览 | 内置 [SubViewport](https://docs.godotengine.org/en/stable/classes/class_subviewport.html) 与相机/Control | 可复用离屏渲染与显示。标记、坐标换算、地图发现和数据源仍属业务；当前项目已有 SubViewport 预览，不重建一套入口。 |
| 编辑器撤销/重做 | 内置 [UndoRedo](https://docs.godotengine.org/en/stable/classes/class_undoredo.html) | 可用于运行时编辑器操作历史。不能代替磁盘保存可靠性、故障恢复或多人冲突处理。 |
| 栅格吸附与操纵手柄 | 内置 [Vector3.snapped](https://docs.godotengine.org/en/stable/classes/class_vector3.html)；编辑器专用 [EditorNode3DGizmoPlugin](https://docs.godotengine.org/en/stable/classes/class_editornode3dgizmoplugin.html) | 栅格数值吸附可复用；表面/顶点吸附仍需拾取与容差逻辑。EditorNode3DGizmoPlugin 是编辑器 API，不能直接作为导出游戏内编辑器的完整手柄方案；运行时手柄插件尚未筛选。 |
| glTF 模型加载 | 内置 [GLTFDocument](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html) | 优先复用解析/场景生成，不自行解析整个格式。特殊扩展、资源外置、压缩与材质兼容逐项验证。 |
| 大图首载和资源加载 | 内置 [ResourceLoader 线程加载](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html) | 适用于相应资源管线；外部 GLB 经 GLTFDocument 的流程不能假定自动变异步。分块调度、取消、缓存预算和错误恢复仍需项目实现。 |

## 关键接入风险：自定义身体求解顺序

本地 `female_axis_body.gd:set_angles()` 当前先写 Skeleton3D，再立即执行 GPU 分轴求解并上传展示纹理。因此不能仅将 SpringBone/IK/Retarget 节点挂上去，就认为最终身体会使用它们修改后的姿态；必须确认 modifier 执行时机、最终骨骼数据与身体/服装目标的一致性。也不能同时让两个系统写同一骨骼。此项是本地代码推导的集成风险，不是插件有缺陷的结论。

当前 `addons/` 目录没有本表新增候选；这里只证明尚未安装这些候选，不说明原工程没有使用任何内置功能。旧角色已用 BoneAttachment3D，世界编辑器已用 SubViewport；后续先查已有接线再新增。

## 下次工作入口

1. 当前视觉阶段优先：布料插件对照 → 骨骼更新顺序 → 内置弹簧骨/握持与动作工具 → 材质/抗锯齿。具体任务需要哪个再测哪个，不一次引入全部插件。
2. 新候选先在隔离场景验证与现有身体、衣服、灯光和原失败动作一致，保存版本/许可/输入及结果。不能以改动作、删网格或换简单裙子替代回归。
3. 通过后做最小适配并复用统一角色配方。未覆盖的衣服合身、表情美术、遮罩、数据保存等继续明确保留，不能误称“插件已经做完”。
4. 性能与新增 MMD 表情按用户顺序后置。地图项仅作为后续参考；Go 持久化、正式地图内容继续暂缓。

本表新增候选都未实测。**原则：先查内置，再查已有插件；确认缺口后才写项目特有部分。** 不能由本次未找到某插件推断生态中不存在。
