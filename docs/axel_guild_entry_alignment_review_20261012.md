# 公会入口平台外延复验 · 2026-10-12

用户 U36 指出入口平台与石栏前端未对齐。此次只改平台及下级踏步的两个网格，尺寸属于项目补充设计；其他部件保留。原图已归档到参考 manifest。

|部件|原范围（Blender Y，米）|修改后|
|---|---|---|
|上层平台|-1.20～0|-1.83～0，前沿对齐石栏帽|
|下级踏步|-1.80～-1.20|-2.43～-1.83，保留 0.60m 踏面|

两层统一 X=12.55～19.45m，宽 6.90m，与左右石栏帽外侧齐平，去掉原下级外扩角。标高保持平台 Z=0、下级 Z=-0.16m、底面 Z=-0.32m；碰撞意图 true 保留。UV 按原每面的世界尺度映射更新，石缝不随平台尺寸拉伸。

## 本轮验收

- 资源：通过。只改变两件平台网格，实例展开面数仍为 478,026；未增加面数、材质或图片，不需要为这两个简单台阶新增 LOD。全楼原有 LOD/合批待办仍保留。
- 画质：入口同机位对照与侧面检查通过，台阶与石栏支承关系连续。近中远截图存档。额外俯视截图受既有阳台/徽幡遮挡，不能将它作为整个平台无遮挡俯视验证；准确边界由保存重开后的几何坐标检查。
- 管线：通过真实 GLB 导入、隔离 Native 保存重开与 Footprint 准备。母版实际保存重开通过。后台独立桌面运行，未修改正式地图。
- 游戏/编辑器接入：仍待验。本轮验证的是离线资产，不宣称已在正式地图完成角色行走或门交互。

## 版本与成本

- GLB：`D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/entry_extension/axel_guild_entry.glb`
- SHA256：`b5498b3278fc5f2e929bd1b8d410b6896b5c6f8bb3c58212e328b71220318567`
- 母版：`D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/entry_extension/axel_guild_entry.blend`
- GLB 115,207,676 字节，Native 170,768,439 字节。
- 引擎统计纹理字段：RGBA 预算 608,174,028 字节、image_mip_bytes 345,767,936 字节；这些不是实测 RSS/VRAM。资源成本基本不变，不宣称本次提高性能。
- 保留先前 `axel_guild_delivery.glb` 与母版作为回退。上轮彩窗光学、纹理 mip 和正式接入限制继续有效。

[实际导入验收 JSON](../review_artifacts/axel_guild_finish_20261012/entry_extension/candidate.json) · [既有参考及限制](axel_guild_finish_review_20261012.md)

![平台与石栏对齐](../review_artifacts/axel_guild_finish_20261012/entry_extension/candidate/entrance_detail_still.png)

![侧面踏步衔接](../review_artifacts/axel_guild_finish_20261012/entry_extension/candidate/entry_side_still.png)
