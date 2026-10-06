# 参考低矮木围挡 · Blender 审阅样品

## 最新支撑高度调整

用户继续要求支撑至少 50 厘米。本轮按“横板下方露出的支撑净高”执行：横板最低下缘不得低于地面 0.50 米，板顶基准调至 0.88 米、柱高基准调至 1.02 米。横板保留约 0.33 米宽及不齐的钉装变化；生成时逐块校正最低边，避免随机倾斜使局部低于 50 厘米。下方第二版尺寸为历史记录，当前以本节和参数 JSON 为准。仍未接入游戏。

## 用户比例反馈后的第二版

用户指出第一版横板宽度、支撑高度与截图不符，而且缺少随手钉装的感觉。第二版横板约 0.33 米宽（原 0.255）、板顶约 0.57 米（原 0.63），下方留空降为约 0.24 米；立柱改为约 0.08～0.094 米宽、约 0.70 米高，柱高有少量差异。立柱轻微倾斜，板边和端切不齐、横板安装有小幅倾角及高低错位，钉头和钉位不再规则对称，木色压深。构件仍在立柱处固定，不以随机散开制造破损感。

第一版源文件与预览保存在源目录 `first_proportions/`。下文“首版尺寸”仅为历史记录，当前尺寸以上述第二版和参数 JSON 为准；第二版仍待用户美术确认，不接入游戏。

用户在确认花池减面版后，要求继续制作截图中的木围挡，并明确暂不接入游戏。本批仅输出离线 Blender 与审阅 GLB，不注册资源包、不改地图。

## 参考与结构

原图：`references/town_low_fence_20261005/01_user_reference.png`。观察为单层宽横板、少量窄立柱、立柱头略高于横板、下方开放、深暖褐木材。截图底部彩色线条属于画面叠加，不是模型。背景石墙、草地、水岸不属于本次围挡。

现实构造核对：[Jacksons nailed post-and-rail CAD](https://www.jacksons-fencing.co.uk/-/media/cad-pdfs/post-and-rail/post-and-rail-nailed.pdf) 与 [Knee rail installation](https://www.jacksons-fencing.co.uk/-/media/jacksons/installation-instructions/Knee%20Rail/Installation%20Instructions/Knee%20Rail%20Fencing%20Installation%20Instructions.pdf)。仅借鉴横板固定于立柱、接头由立柱承托、转向设柱的关系；不复制现代多横杆样式、不宣称中世纪考据或临水安全防护等级。

首版尺寸是游戏美术估计：柱高约 0.77 米，柱宽 0.132 米；横板顶 0.63 米、板高 0.255 米、厚 0.09 米，最大柱距 1.8 米。柱脚埋入地面 0.12 米。横板沿本地 X 延伸、柱纹沿 Z，原点地面；GLB 转为 Y 向上。没有角色或 VR 通行验收。

## 素材和参数

复用已归档且已购核对的 [Wood Material Pack3](https://www.fab.com/listings/ff8612c9-a38f-4d8c-95d8-5d97282e7fe4) 中 `solid_timber` 的颜色、OpenGL 法线、粗糙度三张 2K 图，内嵌在 Blender 文件中。来源详见 `docs/default_material_pack.md` 和默认包 `wood/solid_timber/material.json`。没有把现有默认包做任何修改。

`tools/town_low_fence_parameters.json` 控制样品长度、转角回边、柱高、横板顶高、最大柱距；`tools/build_blender_town_low_fence.py` 重新分段并排柱，纹理按米铺设。当前是离线配方，不是游戏 UI/MCP 功能。首批短直段 1.8 米、长直段 3.6 米、L 形 1.8 × 1.8 米。端部外伸另计。短直段为参考结构样品，转角是同结构延伸提案。

## 文件

源目录 `D:/code/rmmo_runtime/art_sources/town_low_fence/`：

- `town_low_fence.blend`：可编辑原件，木材和固定钉分开。
- `town_low_fence_review.png`：三款总览。
- `town_low_fence_detail.png`：长直段低视角。
- `review_exports/`：三款 GLB，仅用于审阅。
- `mesh_stats.json`：逐款三角面和柱数统计。

原图为造型目标，渲染为待用户确认候选，不算已接入或正式地图内容。

三款重开检查通过，均含木材与固定钉两组网格、内嵌三张 PBR 贴图。长段拼缝两侧分别落钉，不将固定钉放在板缝空隙中。初版三角面：短直段 292、长直段 540、转角 540；只计模型，不计审阅灯光和地面。
