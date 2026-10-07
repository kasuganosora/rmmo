# 自动道路路缘：素材与编辑器实现

2026-10-07 用户要求先实施素材，再实施代码。本次按此顺序完成，验证使用临时地图，未覆盖既有城镇。

## 美术来源与素材

- 设定依据：[街区视觉参考](medieval_town_visual_references.md)中的石桥通向节庆街道、石铺路与草地边界。采用写实浅石灰岩，低矮石边，不将动漫画面色块直接做成材质。
- 现实结构参考：[Historic England 1393770](https://historicengland.org.uk/listing/the-list/list-entry/1393770) 的石铺路、石缘与石板铺地，以及 [1393679](https://historicengland.org.uk/listing/the-list/list-entry/1393679) 的路口石材铺装。这些是近代保留实例，只用于结构与材料参考，不称为中世纪复原。
- 纹理来源为已购 Quixel [Beach Cliff](https://www.fab.com/listings/cda0efb9-0659-49fb-905e-812e51085c86)，原资产、许可证入口、来源哈希保存在材质 JSON 内。Blender 烘焙石灰岩颜色、石材法线与接缝凹凸；粗糙度为制作时设定的均匀值，并非扫描粗糙度。
- 生成脚本 `tools/build_automatic_kerb_material.py`；母版、优化版、同机位/灯光/曝光对照图、截面 GLB 和参数存于 `D:/code/rmmo_runtime/art_sources/automatic_kerb/`。
- 发布材质 ID：`pack:default:paving/automatic_limestone_kerb/material`。1024² 颜色/法线/粗糙度共三张贴图，1.76 米沿长度循环、四条接缝。安装目录 `D:/code/rmmo_runtime/packs/default/assets/materials/paving/automatic_limestone_kerb/`。
- 宽度默认 28 厘米；低款高出路面 5.5 厘米，样板另有 14 厘米抬高款，倒角最大 1.8 厘米。尺寸为本项目设计值，非历史实测。路缘向道路内部占用宽度，两侧均开启时净路宽相应减少。
- 截面样板曲线从 64 段减至 16 段，保留倒角、厚度和贴图。母版与优化版采用同一场景渲染；未观察到明显轮廓或光影损失。运行时细分沿实际道路边界生成，并非摆放这些独立样板。

## 实施方式

采用自动瓦片的邻接判断思想，结合连续道路网格：

1. 同层交叉先拆分连接，保留跨层道路独立。
2. 既有铺面算法生成路口与 32 米分块，取消共边及长边对多段短边的内部覆盖。
3. 仅沿外露轮廓生成六点倒角截面。跨分块连续，坡道跟随路面标高；桥头通行面留开口，两端封口。
4. 每个道路块内追加一个路缘材质表面。石缝通过贴图表达，不生成逐砖对象，也不产生额外素材栏格子。
5. 启用后新增道路、移动节点、修改宽度和删除骨架都会在同一事务重算派生铺面。仅重建记录有变化的可视块及其合批；全网边界求解目前仍是同步预检，不宣称已实现后台增量拓扑求解。

算法参考：RPG Maker [autotile 邻接](https://www.rpgmakerweb.com/blog/classic-tutorial-how-autotiles-work)、SideFX [Road Generator 的路口与侧边输出](https://www.sidefx.com/docs/houdini/nodes/sop/labs--road_generator)、[ClipperOffset 的先处理交叠再偏移原则](https://www.angusj.com/clipper2/Docs/Units/Clipper.Offset/Classes/ClipperOffset/_Body.htm)。本项目代码没有直接拷贝第三方实现。

小于 2.5 厘米的布尔裁切碎边先合并，避免内侧偏移翻折；更尖锐、过窄或分叉的不可安全截面会整次拒绝，并保留原文档。此容差是轮廓的微小近似，不称为数学无损。保留环路内孔，不跨高差消边。

## 编辑器与 MCP

入口：城镇规划 →「生成道路铺面与路口」→「自动路缘与道路同步更新」。先预览，再应用。可调路缘宽度、高度，独立选择路缘材质；5.5 厘米用于参考图低边，14 厘米用于较高路缘。

当前 3D `preview_road_surface` / `generate_road_surface` 共用参数：

| 参数 | 默认值 | 范围 / 含义 |
|---|---|---|
| `kerb_enabled` | false | 开启连续路缘及后续道路同步更新 |
| `kerb_width` | 0.28 | 0.12–0.4 米，向路面内侧 |
| `kerb_height` | 0.055 | 0.025–0.18 米，高出路面 |
| `kerb_material_id` | 上述石灰岩材质 ID | 必须为有效不透明材质 |

预览返回 `kerb_length`；生成保留 `plan_token` 防陈旧覆盖。`update_road_graph`、UI 绘制和节点移动共用事务：同步几何失败时骨架也不变。锁定/隐藏、手刷材质和事件保护沿用既有规则。关闭路缘后回到既有手动更新铺面模式；解除关联保留已有实体网格。

旧地图缺少新字段时按关闭处理，不自动迁移。旧二维工具不启用。本版处理连续道路工具的边界，未接管旧网格自动瓦片；尚无局部下沉路缘、门口排除笔刷或泥草渐变边缘功能。

## 性能、保存与验收

- 路缘嵌在 `road_mesh.kerbs`，道路仍按块独立选择、碰撞、撤销和保存；材质快照 `road_kerb_material` 接入统一资源依赖收集与路径校验。
- 接入现有共享静态批次；运行时数组由已有 worker 准备。生成器文件纳入派生网格缓存哈希，准备数组保留 CPU 副本。
- 真实 Vulkan HTTP 测试的八个参与合批道路块：24 个源材质表面 → 12 个渲染表面，3312 个顶点。只是该测试场景结果，不代表整座地图的帧率。
- `tools/test_road_plan.gd`：既有路面几何回归通过。
- `tools/test_automatic_kerb_geometry.gd`：直路、T/X/Y 路口、环路、直线坡道、跨层交叉、S 弯、桥头开口及收口通过。检查序列化、法线、边界长度及内部块缝。
- `tools/test_automatic_kerb.gd`：真实 HTTP 工具发现、预览无修改、自动拆分路口、生成、非法参数/缺材质无副作用、节点移动、新支路、锁定保护、UI 共用参数、撤销重做、实际合批、原生保存重开、重开后可再次生成、运行时后台加载通过。
- GPU 验收使用 `tools/run_godot_background.py` 的独立未激活桌面。日志和引擎截图位于 `D:/code/rmmo_runtime/review_artifacts/automatic_kerb/`。

美术自审：符合写实石材、立体低路缘、连续转角及路口无横向挡条；测试画面采用平地与道路，以便看清连接，不代表完整街区布景。路缘未添加苔藓、草丛遮挡及泥土过渡，这些仍由已有地形/植被系统布置。没有将测试地图作为已完成城镇交付。
