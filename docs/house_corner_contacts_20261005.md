# 房屋墙角闪烁修复（2026-10-05）

用户在城镇坐标 `(-169.8, -25.5)` 报告门旁石饰不停闪烁。对应固定房屋 `building_e5279e4cef254a55ba86`。

## 原因和处理

转角石饰后缘嵌入墙体约 2 cm；石饰端面与垂直方向的侧墙表面共面，产生深度竞争。侧墙外露端面还误用了室内细灰泥，形成白色竖条。

- `house_wall_contacts.gd` 从 `wall_grid` 的实心单元提取墙体范围，保留真实门窗洞口。
- `joined_box_mesh.gd` 在生成时裁去饰件埋入墙体的面片，保留外轮廓和原碰撞。楼板不参与这项裁切。
- `build_medieval_material_demo.gd` 将外墙可见端面归为外墙材质。
- `repair_house_contacts.gd` 对已有固定房屋作定向修复，不重新生成整栋建筑。只更新静态渲染网格；门窗、碰撞、坐标、楼层身份及非房屋物件均不变。

## 验证与发布

临时候选地图位于 `D:/code/rmmo_runtime/cache/world3d/house_flicker/map.gltf`。24 栋房屋、74 条静态组件记录完成处理；裁切 46952 个原始三角面，1136 个端面三角形改为外墙材质。这是处理数量，不是净减面数量。

校验包括：烘焙数据合法、精确碰撞数组不变、第二次修复没有剩余修改、活动门窗和非建筑记录逐条相同、建筑身份有效，以及原生保存重开。全部通过。

`review_house_flicker.gd` 通过 `run_godot_background.py` 在后台 GPU 场景复现问题，并用三个轻微移动的近景相机检查候选地图。`before0..2.png` 与 `fixed0..2.png` 显示原有锯齿闪烁边缘消除，外露端面材质连贯。没有使用深度偏移或加厚模型掩盖问题。

`test_house_prefab_mcp.gd` 真实 HTTP 回归通过（`failures=0`），覆盖工具调用、非法调用无副作用、门窗状态、锁定、撤销重做、素材库与保存重开。本次没有新增编辑器操作或 MCP 参数，UI/MCP 继续复用建筑生成与烘焙路径。

发布使用原生 `WorldDocument.save`；先检查正式地图基线摘要和候选摘要，避免覆盖检查期间的外部修改。正式城镇已保存并重开验证通过（`CONTACTS_PUBLISHED failures=0`）。日志、修复报告、前后截图位于 `D:/code/rmmo_runtime/review_artifacts/house_flicker/`。

室内门的新造型及开启方向是另一项待用户预览确认的工作，不包含在此次墙角修复中。
