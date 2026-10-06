# 室内木门（2026-10-05，样式已确认）

用户已确认 Blender 预览样式并授权实装。下面保留模型制作资料；末尾记录编辑器接入、地图迁移和验证范围。

## 用户参考与造型

主参考为本轮动画截图，已保存到 `D:/code/rmmo_runtime/art_sources/interior_timber_door/user_reference.png`。门扇为深棕木色，两侧厚竖挺，顶底横档与中下部腰横档；上下两块板芯采用方向相反的斜拼板，木纹沿各自板材方向。左侧竖挺安装黄铜长方底板和圆门钮，右侧为铰链。取消室外门的弧形铁饰和长条拉手。背面保留完整板芯、木框和另一只门钮，开门后不会露出空壳。

木纹复用 `packs/default/assets/materials/wood/solid_timber/texture.png`；授权见该素材旁的 `material.json`。板间采用小幅深浅变化，使用同一木纹材质与顶点色。固定门框是独立 U 形网格，无横跨门口的门槛；门扇的木材和黄铜件是两个同动网格。

既有现实构造资料再次核对：[Historic England Conisbrough 门板、合页、把手详图档案](https://historicengland.org.uk/images-books/photos/item/MP/CON0005)记载 1954 年修复设计的门板、合页及把手详图；[National Trust Ightham Mote 建筑记录](https://heritagerecords.nationaltrust.org.uk/HBSMR/MonRecord.aspx?skin=printerfriendly&uid=MNA181826)记载历史木板门及长合页。它们仅用于独立门扇、门框与五金安装关系，不能证明动画中的斜拼板和黄铜圆钮属于同一历史实物。具体外观仍以用户截图为准。

## 尺寸、坐标与开启示意

门扇基础宽 1.20 m、高 2.20 m、厚 75 mm，面板比竖挺凹入约 13.5 mm。门钮中心距门底 0.93 m。以上是角色通行与现有门洞适配的建模尺度，截图不提供实测尺寸；尚未按每个实际房间门洞替换。

Godot +Y 向上，正面朝 -Z。站在过道 -Z 看门，图像左侧门钮对应模型 x=+0.53 m；图像右侧铰链对应 x=-0.60 m。开门预览绕 `(-0.60, 0, 0)` 作 -45° Y 旋转，门扇自由端进入房间 +Z；固定框完全不转动。`open_into_room.png` 的地面标注 `ROOM +Z` 仅解释预览方向，不属于资产。

后续实装应依据真实房间/过道拓扑确定每扇门的开向，并分别检查开门后通道、家具及墙面的避让；不可把当前预览的统一坐标直接当作所有房屋世界坐标。铰链位于图像右侧与既有外门约定不同，接入时必须正确转换。

## 面数与优化

| 部分 | 三角面 |
| --- | ---: |
| 活动木门扇 | 280 |
| 活动黄铜五金（双面门钮、两枚合页） | 296 |
| 独立固定门框 | 36 |
| 合计 | 612 |

活动门扇合计 576 三角面，整体 3 个网格、2 个材质。门钮使用 12 周向分段的旋转轮廓，合页圆筒 8 分段；面板周边只保留一圈倒角。板宽 20 cm，实际暗缝 4 mm，浅、中、深三个木色帮助读出每块板。斜板没有埋在芯板内部的背盖，仅保留正反可见板面和拼缝返边。没有细分曲面、未应用的修改器或逐板运行时节点。网格检查通过：无退化三角面；UV、逐角法线和顶点色已导出。尚未与另一套高面数相同模型做图像差分，因此不声称达到某个无损减面百分比。

## 文件与复现

- 作者脚本：`tools/build_blender_interior_door.py`，Blender 4.5 后台运行。
- Blender 源：`D:/code/rmmo_runtime/art_sources/interior_timber_door/interior_timber_door.blend`。
- 模型：`D:/code/rmmo_runtime/assets/interior_timber_door/interior_timber_door.glb`。
- 分组网格数据：同目录 `interior_timber_door_mesh.json`，包含铰链、动静分组、材质编号、UV、颜色、法线。
- 独立预览场景：同目录 `interior_timber_door_preview.tscn`；明确开启顶点色参与底色，避免 Godot GLTF 默认材质开关遗漏。
- 校验报告：`D:/code/rmmo_runtime/art_sources/interior_timber_door/validation.json`。
- 预览脚本：`tools/preview_interior_door.gd`，必须经 `tools/run_godot_background.py` 的不激活独立桌面运行。
- 预览目录：`D:/code/rmmo_runtime/review_artifacts/interior_timber_door/`，含 `front_straight.png`、`front_angle.png`、`back.png`、`knob_joinery_detail.png`、`open_into_room.png` 及后台测试日志。

## 实装与验证

`interior_door_mesh.gd` 读取批准的 Blender 数据，保留原 UV、法线及顶点色。门扇与框的模型缓存分别按尺寸共享；烘焙后嵌入原生固定房屋，不在玩家进图时读取 JSON 或展开零件。门扇保留 12 三角面盒碰撞，门框采用真实 U 形碰撞，不用跨门洞的实心盒。固定框深度按现有 20 cm 隔墙增至 27 cm；宽高随既有门洞缩放，门口没有新增门槛。

`interior_door_layout.gd` 在完整房间/门洞关系建立后替换室内门。依据关联房间中心所在侧确定向内方向；主屋连接翼楼的门向附属房开启，入户门、院门及阳台门不套用这项替换。固定框并入对应楼层静态壳体；门扇及黄铜件属于原 fixture，整栋旋转后仍保持同一铰链。编辑器生成与 MCP `generate_buildings` 走相同路径，`set_building_component_state` 参数与事务不变，未注册任何二维工具。

`upgrade_interior_doors.gd` 对正式城镇制作隔离候选：24 栋房屋中 48 扇室内门及 46 条相关楼层静态网格，共 94 条记录。逐三角形匹配并移除旧框和铁铰链，再加入新框；匹配允许 0.15 mm 旧量化误差，并核对全部目标三角形移除数量。其余静态面片及纹理保留，包含此前墙角闪烁修复。外门、窗户、灯具、建筑身份、物件数量及未涉及的记录保持不变。候选保存与正式发布均使用原生原子保存；发布前校验原图基线、候选和批准模型摘要。

- `test_interior_door_layout.gd`：22 组配方、82 扇门，含中世纪、标准房、城中村和多房间布局；5 个整体朝向、4 个开启比例，转轴固定且朝关联房间内开，全部通过。
- `test_house_prefab_mcp.gd`：真实 loopback HTTP 发现、生成、室内门合法/非法状态、无副作用失败、锁定、撤销重做、素材库复制和保存重开通过；同时验证室内门 576 / 外门 846 三角面及颜色保留。
- `test_interior_doors.gd`：后台 GPU 场景逐栋建立候选房屋，48 扇门均验证关闭阻挡、打开后双向胶囊通行、转轴及开向，`failures=0`。实景截图为 `town_closed.png`、`town_open.png`。

报告与日志均位于上述预览目录，`upgrade.json`、`physical.json` 将验收绑定到候选地图摘要。固定旧预制件不会因普通重开自动重建；此迁移只针对已授权的正式城镇，其余历史样房文件保持原状。

正式 `medieval_river_town/map.gltf` 已原生保存并重开验证，`publish.log` 记录 `INTERIOR_PUBLISHED failures=0`。重新进入城镇可加载这 48 扇新室内门。
