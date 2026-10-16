# 市场药瓶与矿物近景细化（2026-10-16）

## 当前状态：v6 正式素材库交付通过，微观细化保留

两款已纳入四摊统一 `v6` 交付，完成最新管线真实 native、全视角复验、正式目录发布和真实 HTTP 编辑器保存重开。当前准确 SHA、逐件状态与成本见[统一复验报告](axel_market_realism_review_20261016.md)。药瓶明暗背景透视、液面以及矿物内部薄片属于本轮通过范围；布微纤维、木端纹与密集部署性能分别保留，不宣称最终美术或整城性能完成。本任务未替换正式地图实例。

## 历史 v5 专项结果（包边结论已由 v6 复核替代）

下面保留原专项判断。主任务后续检查发现 v5 实际 GLB 包边仍有 153 对相交三角形，因此该版本的包边通过结论不能沿用。v6 按导出三角形修正后，密集间隙、三角相交和实际背面/侧光复拍均通过；货品、光学参数和对应材质纹理字节保持原版，不重复构建已正确的药瓶/矿物。

已实际查看 `gpu_realism_v5_01` 本轮药瓶全部 12 个候选视角、矿物全部 9 个候选视角及 4 张同机位旧版基线；全部为核对收据与实际 SHA 的 1400×1000 WebP Q90。本次通过范围为药瓶玻璃/液体/标签、矿物断面/晶面/稀疏内部薄片，以及两款摊棚的正背面包边修复。没有用旧 v3 图片代替 v5 验收。药瓶明暗背景中的瓶颈、口沿、底壁、液面和空余空间均可读；矿物内部不再呈逐颗居中的白色圆块，偏心薄片随光照变化；背面包边未见异常斑纹。

独立逐图报告：`D:/code/rmmo_runtime/review_artifacts/axel_market_realism_20261016/gpu_realism_v5_01/independent_potion_ore_review.json`，SHA `ef718bc2580ed3caeab5c11de761911fbf8990b097a336a6be07304540256c5e`。绑定最终候选：

- 药瓶 `v5/potion.glb`：SHA `2ab8e7b73927407b1c7e0f05033cf0f8a6b39fce7bcd6c89cfa2f5452b2b96ec`，本轮隔离候选运行检查 254 项、0 失败。
- 矿物 `v5/ore.glb`：SHA `4ea6b34f2d17355ddca876f150bfe848248cb6ffccdf9fee203e38c338b2344a`，本轮隔离候选运行检查 164 项、0 失败，GoodsOpaque 实际 native 有 46,796 个 tangent floats 且法线启用。

布料微纤维/织纹和木材端纹仍是独立待细化项，本次不为其签署最终写实质量。当前透明合同不等于物理体积折射或焦散；静态图也不代替运动镜头排序测试。上述候选图审及隔离运行检查不等于正式资源发布、地图接入或全城性能验收。本审阅方未启动 GPU、修改模型或改动地图。下文保留各旧版本的制作和修复历史，旧“待验”状态以本节的明确范围为准。

## 制作范围与版本历史

范围：只替换原母版 `03_potion_vendor_CONTENTS` 的瓶/塞/签，以及 `05_ore_vendor_CONTENTS` 的矿物货品；保留棚架、布棚、四个药瓶货架支撑件、十五个矿物木箱件。所有新增形制属于**项目补充设计**，不是动画设定中未展示细节的官方复原。原 `.blend` 和正式旧资源未修改；不执行地图编辑、发布或 GPU 渲染。

## 可复用接口

模块：`tools/axel_market_realism_potion_ore.py`。在原母版的工作副本中执行一次：

```python
import axel_market_realism_potion_ore as goods
potion = goods.apply('potion', bpy.data.collections['03_potion_vendor'])
ore = goods.apply('ore', bpy.data.collections['05_ore_vendor'])
```

也可传对应 `_CONTENTS` 子集合。函数返回可序列化的数量、各货品坐标、尺寸、分组和验收状态；不保存或导出文件。输入必须是尚未替换的母版，以明确的 16/30 数量断言阻止重复覆盖。原母版坐标是 Blender Z 向上、前方 −Y；药瓶 offset X=0，矿物 offset X=7.2，模块原样保留，统一导出方负责归零/轴转换。

原母版：`D:/code/rmmo_runtime/art_sources/town_market_stalls/town_market_stalls.blend`，SHA-256 `07624a3241d64ac86f308955331d2e372312a994a92c3a7bc0f120f109f4fa73`。

## 参考与具体变化

- [Science Museum：透明玻璃、软木塞标本瓶](https://collection.sciencemuseumgroup.org.uk/objects/co180034/clear-glass-specimen-bottle-from-the-old-english-pharmacy)。该件标为 1831–1900，仅参考玻璃/软木的物质层次与组合方式，不借其年代宣称中世纪复原。
- [GIA：海蓝宝石说明与自然晶体照片](https://www.gia.edu/aquamarine-description)、[GIA：巴基斯坦海蓝宝石晶体](https://hongkong.gia.edu/gems-gemology/spring-2018-gemnews-aquamarine-from-pakistan)。浅绿蓝色绿柱石和六方柱晶形作为第三箱矿物依据；不是做蓝色多面球或任意尖锥。
- [Mindat/Hudson Institute：黄铜矿实物资料](https://www.mindat.org/a/best_chalcopyrite)。参考搜索索引的黄铜色矿物、母岩与非规则矿脉信息；本次页面直接访问返回 403，未把未读取内容或照片当作已审看证据。模型只命名“含铜矿物母岩”，不宣称精确矿相鉴定。

已实际查看旧 `gpu_ab02/potion/candidate/goods_detail.webp` 与 `ore/candidate/goods_detail.webp`，原尺寸 1400×1000，Q90 压缩收据与图像 SHA 一致才复用。旧药瓶主要表现为不透明三色瓶身；旧矿物直接使用一级 ico 的大型三角面，铜色小球与蓝色粗块缺乏合理矿物形态。

药瓶保留 16 瓶及 6 绿、6 紫、4 琥珀三种液体。瓶壁为 2.2 mm、底为 4.2 mm 的闭合薄壳，口沿加厚而内腔连续；另建液体闭体、不同装液高度以及高 1.2 mm 的弯月边缘。软木塞独立插入瓶颈；纸签厚 0.35 mm，贴合圆瓶，带少量独立深色墨迹。未添加恒定发光、金属玻璃或伪焦散。

矿物保留三箱各 10 份及逐件原始 AABB。前两箱使用噪声扰动并经切平面断裂的岩块，微颗粒和细脉由米制程序材质供烘焙；第二箱的铜色成分位于母岩脉纹中，删除原先分离的十颗金色 ico 球。第三箱为十件六方柱蓝绿色晶体，基部带同一标本内的少量母岩；没有增加货品标本数量。

v2 实际 GPU 图审没有放行药瓶和矿物：薄玻璃读形过弱，母岩的闭合 Voronoi 网像裂纹陶瓷，晶体主体近乎消失。v3 作者修订删除 Voronoi，改为窄噪声等值带叠加高频随机门控，形成断续、变宽的少量脉纹；母岩底色收暗、铜脉覆盖与金属强度收敛。每个蓝晶增加一小块位于内部的实体石英类包裹体，保持透明壳，不假称模拟了体积散射。玻璃与晶体透色/粗糙度如下调节；主任务将补实际游戏天空反射后再拍，作者 CPU 检查不能代替该轮 GPU 复验。

## 统一烘焙/导出合同

所有新增 mesh 的 `rmmo_export_group`：

| 分组 | 材质 | 处理 |
|---|---|---|
| `GoodsOpaque` | 软木、纸、墨迹、两类母岩 | evaluated 副本 join 后统一 PBR atlas bake |
| `Glass_Clear` | `MarketRealism_Bottle_ClearGlass` | 不烘焙，保留光学合同 |
| `Liquid_Emerald` | `MarketRealism_Liquid_Emerald` | 不烘焙，保留光学合同 |
| `Liquid_Amethyst` | `MarketRealism_Liquid_Amethyst` | 不烘焙，保留光学合同 |
| `Liquid_Amber` | `MarketRealism_Liquid_Amber` | 不烘焙，保留光学合同 |
| `Glass_Aquamarine` | `MarketRealism_AquamarineCrystal` | 不烘焙，保留光学合同 |

普通程序材质的纹理坐标使用 `Geometry.Position` 的实际米制位置，不用 join 后会改变的 Generated 包围盒坐标。当前 UV 是作者投影 UV，适合保留参数/查看；最终 opaque 应使用统一不重叠 atlas UV。母岩节点包括 base color、roughness、铜脉 metallic、颗粒 normal，不能只 bake base color 后丢弃凹凸和粗糙度。

光学对象已设置现行消费者实际识别的 **mesh extras** `rmmo_tinted_glass={version:1,materials:{EXACT_MATERIAL_NAME:{transmittance:[r,g,b],roughness:n}}}`。统一 join 同组后必须合并/保留这个字典，并保持材质名称精确匹配；只保留材质上的 authoring 属性不能生效。

| 光学组 | 透过色 | roughness |
|---|---|---|
| 透明瓶壁 | `[0.94,0.975,0.96]` | 0.11 |
| 绿色液体 | `[0.48,0.83,0.61]` | 0.10 |
| 紫色液体 | `[0.76,0.52,0.85]` | 0.10 |
| 琥珀液体 | `[0.96,0.76,0.38]` | 0.10 |
| 蓝绿色晶体 | `[0.56,0.80,0.90]` | 0.19 |

材质作者属性 `authoring_bake_required` 和 `authoring_optics_spec` 仅供统一构建脚本使用，不发明新的运行时消费者。Principled fallback 设置 transmission=1、IOR=1.46、metallic=0、低 alpha；当前 Godot `tinted_glass.gd` 的正式语义是背景乘色 + 独立介电反射，**不是体积吸收、物理折射或焦散**。多层瓶壁/液体排序及玻璃反射必须在 native GPU 图中确认；GPU 发现累积过暗时应调整光学合同/材质值并复验，不改成不透明涂色。

## CPU 结果与剩余验收

执行 `tools/audit_axel_market_realism_potion_ore.py`（Blender `-b --python-exit-code 1`）：v3 共 474 项通过，0 失败（初版为 454 项）。检查包含闭合流形、有限坐标、非零面积、有效 UV、光学合同、货品数量、原有货架/箱件身份、原模型 surviving 对象精确身份、整体 AABB、矿物各件 AABB 和主母版文件 SHA。

v3 新货品三角：药瓶 55,040，矿物 14,272（增加内部包裹体前为 10,850），均是实际几何计数，**不是减面收益**。药瓶的真实内外壁/液体会高于旧占位；根任务应结合统一模型的近中远画面、draw calls、透明 overdraw 和重复实例场景评估成本。不能仅凭三角总数宣称 FPS/VRAM 已通过，也不能把移除内壁以降低数量自动视为无损优化。

证据目录：`D:/code/rmmo_runtime/review_artifacts/axel_market_realism_20261016/potion_ore/`，`cpu_audit.json`；独立可编辑测试母版在 `D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016/potion_ore/potion_ore_authoring.blend`。

未完成/交给统一管线：PBR 烘焙、最终 GLB 实际 SHA/native、同光照曝光近中远和货品细节图（上传前原尺寸 WebP Q90）、玻璃瓶内液面可读性/排序、矿物凹凸与铜脉金属分布、实际导入保存重开/碰撞检查。现阶段为 **CPU 作者模块通过，最终画质和正式接入待验**。

## v3 实际图审与 v4 局部修正

`gpu_realism_v3_01/independent_potion_ore_review.json` 保存独立图审（SHA `2ceaca4416d12aa16e7cea3bd6512743c0cc0e8ae7be49dbc4d90ed70f050963`）。实际查看药瓶 6 图、矿物 4 图，均为核对收据与 SHA 的原尺寸 WebP Q90。中性天空反射接入后，药瓶的颈/口沿/底壁、液面和空余空间在明暗背景下均可读，纸签和瓶塞独立，所看静态图未见明显多层排序错误；药瓶专项视觉接受。矿物的闭合白裂纹已消除，母岩断面和少量断续脉纹接受；晶体内逐颗白色圆实体过于醒目，仍不通过。当前 native 已为 `ore/GoodsOpaque` 生成 61,452 个 tangent floats，法线启用，源 GLB 未显式带 TANGENT 的疑点解除。

v4 只改晶体内部包裹体：十件中四件保留偏心、不规则、厚度不足 2 mm 的暗矿物薄片，其余保持洁净透明。晶体外表面、母岩、摆位、所有其他原物件的几何/UV/材质和光学参数精确保留。专项 CPU 审计 `potion_ore/cpu_inclusions_v4.json` 为 54/54 通过（SHA `e864c12baa0daf810493ddca832f4048109f18aef9885d8de02306508fb08451`），检查薄片全部在原晶体内部及闭合流形。新作者矿物货品 10,852 三角；此变化为删除不合格内部实体后的几何差异，不称整体无损减面。

模块 v4 SHA `fe700ffc2f343270b14b3b2cca82b908a12b1f81bb649b1469158eab21576179`。旧 v3 模块在作者目录 `potion_ore/module_v3.py` 保留。v4 使用 CPU 六线程仅重烘 GoodsOpaque，最终合并须直接保留 v3 的 Structure、布、透明晶体节点及所有对应资源身份。v4 画质、native 与正式接入仍须由统一管线复验，不以 CPU 合格代替。

v4 ore 候选已完成：`D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016/v4/ore.glb`，SHA `5b5ccb49889e15c46bd97c9108adf656b2a402c4028bd7f963a09b15fcf6afc8`。全模型 27,976 三角（v3 为 31,354），无退化面，实际 AABB 与既有结构允许的导出精度一致。`ore_incremental_identity.json`（SHA `0df0b124b45eee79779b7f667b7738d2e4df7879a99ac8a0462bec95dd95cd56`）确认仅替换 GoodsOpaque；CanopyCloth、CanopyTrim、Glass_Aquamarine、Structure 的几何/材质/纹理及其他已解析渲染输入逐字节保持。`ore_source_audit.json` SHA `ef867e09db30129d62dc0b175d2d55a6190ecb489594ba00259bdde370e033d0`。药瓶、陶罐未重新构建，共享 v4 清单内既有 scroll 行与 SHA 保留。GLB 导出仍报告 n-gon 切线生成限制，与 v3 同类；后续 native 检查应确认运行时实际切线和 UV0 法线绑定，不能只凭 Blender 参数声明存在。
