# 小贩布棚：现实资料与离线样品

用户要求先查现实详细资料，造型仍须与两张动画参考相似。用户原图保存在 `references/town_market_stalls_20261005/01_close.png`、`02_overview.png`。延续本轮约定，未经用户明确同意不接入游戏。

## 画面观察

近景：蓝灰低斜布篷，正面一排窄瓣垂边，边饰为暗黄/赭色；深色木框、柜台上成堆果蔬、棚下挂篮和成束植物。墙体在后方，但截图不能证明布篷直接锚入墙面。远景：成排小型摊棚，紫与蓝色棚顶轮廓明显；图像较小，无法可靠判断背部结构。

## 现实来源及采用范围

1. [klipklap 木摊实物与尺寸](https://www.klipklap.de/Markt/profistall.html)：现代松木摊架、棉质棚布、柜台承托、可扩展单元。实物图 [K4](https://www.klipklap.de/Markt/marktsbilder/k4mwolle.jpg)。仅用来补结构逻辑，不照搬现代金属插接件。
2. [厂商逐步装配说明与构件图](https://www.klipklap.de/aufbau/aufbauhinweise_s.html)：侧架、承托杆、棚布压杆和斜撑；布顶需张紧，不能做成积水凹袋。参考 [结构示意](https://www.klipklap.de/aufbau/aufbaubilder/Standzng.jpg)、[裸架照片](https://www.klipklap.de/aufbau/aufbaubilder/aufbauen5.jpg)。
3. [London Picture Archive：Trebeck Street 市集摊位](https://www.londonpicturearchive.org.uk/view-item?i=144073)：1958 年街边布棚售卖的档案照片，支持临街布棚与商品陈列场景，不能作为中世纪棚架的证据。

用户截图决定布篷轮廓、垂边和配色；上述现代实物与历史照片补支撑/陈列细节，当前并非中世纪原物复原，也非结构安全设计。

## 样品

- 脚本 `tools/build_blender_town_market_stalls.py`。
- 输出 `D:/code/rmmo_runtime/art_sources/town_market_stalls/town_market_stalls.blend`。
- 总览 `market_stalls_review.png`，主款近景 `market_stall_detail.png`。
- 蓝灰+赭色缝边主款；淡紫同结构配色款。宽 2.8 m、棚深 1.7 m，前棚边高 2.48 m、后端 2.82 m、垂边最低约 2.20 m，柜台约 1.01 m。尺寸为画面比例及角色站位暂定，不是从图片测量，也未完成游戏/VR 通行验收。
- 木架四柱支撑、侧架斜撑、柜台承托，侧向进入柜台后方。后部不做穿过站位的低横杆。木纹复用已购 solid_timber 素材。
- 布篷为有浅褶的薄网格、粗糙布料材质；垂边独立并带缝制色边。不是硬木顶/金属顶。本版为静态，尚未制作棚布风动。
- 棚下挂篮和草束、三个可替换果蔬托盘用于画面陈列。几何与木架分离，属于样品道具，尚未成为游戏商品系统。
- 未注册资源包、未改地图或编辑器；最终美术和性能均待后续验收。

## 后续修订：四面垂边与可换货物

用户指定移除后方长斜木杆，已移除；保留四柱和侧面支撑。用户第二张图指向棚布垂边，按此将其加长 5 cm（最长下垂 33 cm），并补齐前、后、左、右四面，侧边沿斜棚顶高度变化。前沿最低净高约 2.172 m。前述初版尺寸描述以本节为准。

配置 `tools/town_market_stalls_parameters.json` 保存逐款 `canopy_color`、`trim_color`、`contents`；Blender 材质节点 `USER CLOTH COLOR` 可分别更改棚布及边饰颜色。四边垂布同用该款棚布材质。

货物预设支持 `none`、`produce`、`pottery`、`potions`、`scrolls`、`ores`。本轮展示空摊、陶器、药水、卷轴、矿石五款，原果蔬仍可通过配置恢复。每款货物独立放入 `<variant>_CONTENTS` 子集合，隐藏/替换不影响棚架；三个 `DISPLAY_SLOT` 标记台面放置原点，尚未实现游戏商品或交易功能。

- 药水：高低两层木架、三色玻璃瓶、瓶塞与纸签。
- 卷轴：有卷层端面与束绳的卷束、摊开的陈列样本。
- 矿石：分格木箱、深色矿块、铜色包裹体、蓝色晶石。
- 新渲染：`market_potions.png`、`market_scrolls.png`、`market_ores.png`；`market_stall_rear.png` 验收后沿和两侧垂边。

以上均为离线美术样品，布棚仍为静态，待用户确认后才考虑游戏接入。
