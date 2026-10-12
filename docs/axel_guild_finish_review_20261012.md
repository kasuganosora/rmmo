# 公会立面修订与门口徽饰验收 · 2026-10-12

本轮交付离线修订候选，尚未发布正式素材库或覆盖用户地图。按 `rmmo-model-review` 执行受影响项复验；不能把本报告视作整座公会的运行接入完成。

## 本轮用户修正

- U28–U32：内外彩窗使用深蓝、红为主，少量琥珀、绿与紫的配色，深色铅条分隔；改为透明混合。当前确认的是色板与分格，尚不宣称真实彩色焦散或夜间透光验收完成。
- U33：徽幡为无金属度的布料，几何垂坠褶皱、顶部布环固定，图案烘入同一布面 UV0，避免浮动金色网格与布面穿插。两侧为水平臂、墙面竖件、斜撑闭合三角结构，附固定片与螺栓。静态、风时刻 1/4 秒已截图；不等同连续动画稳定性验收。
- U34：重建 10 组交叉山墙/老虎窗的 20 片闭合屋面，统一墙顶净空、出檐、山墙斜收边，补屋脊盖与顺两侧坡面的斜沟泛水；侧墙檐口闭合。中央两侧柱顶下收。主建筑层高、门洞和室内布局不变。
- U35：原资产缺少门口左右金色徽饰立杆，现已补齐。包含弯月、中心圆饰、斜向尖饰、分节杆身和底座。中心圆饰通过杆身连接，非悬浮。单件原点位于底座，可独立复用；两件位于原石栏帽上，不占主门洞。
- 保留原 v4 母版与中间候选；导出移除 40 个比例人偶及根节点，清理精确重复图片。楼层、屋顶、活动门柜层级仍保留。

图中可见外形以用户截图为准。隐藏连接、尺寸、泛水、背面与固定件为**项目补充设计**，不冒称官方设定。屋面泛水关系参考 [Copper Development Association 屋顶老虎窗节点](https://copper.org/applications/architecture/arch_dhb/arch-details/flashings_copings/dormers.php)；三角支架为参考驱动的游戏结构表达，非工程承载认证。

## 实际交付资源

|资源|源字节|Native 字节|三角面|SHA256|
|---|---:|---:|---:|---|
|主楼候选|115,206,500|170,768,375|478,026（实例展开）|`9c6d6439735fe4b4382bae3c00daa2ae56bad64d6e2c5cb16dc2d6ab9f96517f`|
|独立徽饰立杆|65,312|27,157|3,222|`66e890457aad8ad9057497da0050fb6e193cb9f261ac0fa5ec63380b2d852513`|

- 主楼：`D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/axel_guild_delivery.glb`
- 母版：`D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/axel_guild_finish.blend`
- 独立立杆：`D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/guild_entrance_crescent_standard.glb`；单网格、单材质、无贴图。仅门口两件，本轮不追加 LOD，以保留近景金属轮廓；大规模重复部署时重新评估。
- 主楼图片预算字段 `gpu_rgba_bytes` 为 608,174,028 字节，`image_mip_bytes` 为 345,767,936 字节，调度估算为 3,818,423,762 字节。这些是引擎保守预算，**不是实测 RSS 或模型 VRAM**。
- 本轮主要处理导出冗余及用户修正，没有对全楼盲目减面；床、骨架、远景细饰 LOD，以及保留语义的派生静态合批仍待接入阶段处理。

## 验收与限制

|范围|资源|画质|管线|游戏/编辑器接入|
|---|---|---|---|---|
|门口徽饰立杆|通过|参考轮廓及近中远/背面通过|真实导入、Native 保存重开通过|待正式发布/放置验证|
|主楼本轮修订|通过|已检查日间细节、近中远与布幡三个风样本；夜间光学、连续动态仍待验|真实导入、Native 保存重开、Footprint 准备通过|门柜、灯光、碰撞和隐藏等真实接入仍待验|

Blender 母版保存重开后执行 6,985 个屋顶垂直覆盖采样，无检出漏空；新建闭合屋面在制作时检查流形边。覆盖采样不等于水密布尔并集或实际游戏碰撞验证。屋面实体和装饰分组分别保留碰撞意图。阳台门既有内开方向保留，三角支架在墙外；运行时活动件碰撞仍属接入待验项。

GPU 在独立后台桌面执行，未激活前台窗口；使用临时内容根，截图无比例人偶。固定 1400×1000、4×MSAA、ACES、曝光 1、太阳能量 1.5、环境能量 0.65。未用预览专用贴图替换生产导入内容。

目前导入纹理仍存在部分无 mip 的情况，斜视屋面和细织纹可能闪烁；本轮不宣称过滤质量已最终通过。透明彩窗尚需夜间/背光专项检查，未制作彩色投影。之前清理候选的少量像素不一致未完成归因，因此不宣称严格像素无损。此次有明确用户要求的造型及材质变化，以该目标作人工比对。

最终证据：[candidate.json](../review_artifacts/axel_guild_finish_20261012/delivery/candidate.json)、[逐项摘要](../review_artifacts/axel_guild_finish_20261012/delivery_summary.json)、[独立立杆验收](../review_artifacts/axel_guild_finish_20261012/standard_final/baseline.json)。`clean_review/compare.json` 及 `finish_review_initial/compare.json` 为早期历史结果，不对应最终候选，不用于本轮通过判断。

![门口及独立金色徽饰](../review_artifacts/axel_guild_finish_20261012/delivery/candidate/entrance_detail_still.png)

![屋面交接、彩窗与布幡](../review_artifacts/axel_guild_finish_20261012/delivery/candidate/roof_detail_still.png)

![布幡及三角支架](../review_artifacts/axel_guild_finish_20261012/delivery/candidate/banner_detail_still.png)

![室内扇形彩窗](../review_artifacts/axel_guild_finish_20261012/delivery/candidate/fanlight_detail_still.png)
