# 木门样式修订（2026-10-05，用户已认可并完成接入）

最新资产：846 三角面。用户明确允许矛头弱化为细长立体菱形；这一新指示覆盖此前复杂十字凸脊造型要求。下方 1680/1322 面版本均为过程记录。

用户已确认最终 846 三角面版本，并授权实装。新生成的编辑器房屋已使用此版本；正式城镇 24 栋房屋的 74 扇门已通过原生原子保存替换，入口改内开。以下第一稿、1680 面与 1322 面说明仅是修订过程。

## 样式依据和用户纠正

- 主参考：`docs/references/medieval_town_20261004/03_door_and_steps.png`。普通门用单扇适配现有开口，大门参考本身为双扇；暂未扩大城镇门洞。
- 木板由三种深浅颜色交替组成，木纹必须沿斜板方向，上下同色板在中腰衔接为连续人字纹。不是同色平板刻黑线；不加横档截断纹样。
- 铁件包括到门边的细横铁带、上下两条向中间收拢的弧形铁带、带厚度的菱形凸饰。第一稿漏弧带、铁饰过于平直；补充参考位于本目录 `references/timber_door_20261005/`。
- 用户进一步纠正：中心铁饰应像长矛，不能做成四片硬三角拼出的宽菱形。两端细长尖锐、侧缘凹弧收束，中间微鼓，平滑的低矛脊与细铁带衔接。后续用户要求靠近门边、中心具有十字隆起：凸饰中心从 x=-0.34 m 移到 -0.53 m，外端止于 -0.675 m，保留 25 mm 门边余量；内侧长矛尖连入横铁带。中心横纵凸脊直接构建在同一连续曲面上，非贴片。铆钉从矛尖处移开。整门现为 1680 三角面。
- 把手采用竖向铁拉手。门边有合页卷筒，全部五金贴合木料。
- 第一稿 760 三角面；补齐弧带、改三色板后 1680 三角面，仍为 2 个网格、2 个材质。三色通过逐板顶点色实现，复用同一整木纹纹理。

结构资料：[National Trust Ightham Mote 建筑记录](https://heritagerecords.nationaltrust.org.uk/HBSMR/MonRecord.aspx?skin=printerfriendly&uid=MNA181826)记载木板门和长铁合页；[Historic England Conisbrough 门板、合页与把手详图档案](https://historicengland.org.uk/images-books/photos/item/MP/CON0005)用于结构关系参考。曲线五金及三色人字板的具体构图来自用户动画参考，不能声称完整复原历史实物。

模型基础宽 1.4 m、高 2.2 m，结构芯厚约 65 mm，为现有角色通行和门洞比例调整；五金另有小幅凸起，图像不提供实物尺寸。

## 资产与复现

- 制作脚本：`tools/build_blender_timber_door.py`，Blender 4.5 后台执行。
- Blender 源：`D:/code/rmmo_runtime/art_sources/timber_door/timber_door.blend`。
- GLB：`D:/code/rmmo_runtime/assets/timber_door/timber_door.glb`。
- 带正确顶点色开关的独立 Godot 预览：`D:/code/rmmo_runtime/assets/timber_door/timber_door_preview.tscn`。
- 三色、非退化面与面数校验：源目录的 `validation.json`。
- GPU 预览脚本：`tools/preview_timber_door.gd`，必须经 `tools/run_godot_background.py` 运行，不抢用户焦点。
- 输出：`D:/code/rmmo_runtime/review_artifacts/timber_door/front.png`、`front_straight.png`、`back.png`、`spear_detail.png`。

木纹复用资源包 `packs/default/assets/materials/wood/solid_timber/texture.png`，原有 Fab 素材授权和来源见相邻 `material.json`。Blender 文件和 GLB 内嵌纹理。颜色不能只在 Blender 中成立：当前 Godot 运行时 GLTF 导入后材质的 `vertex_color_use_as_albedo` 默认关闭，预览明确开启；正式接入必须保留该设置。

## 接入状态与后续要求

正式地图 `D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf` 未修改，基线 SHA256 为 `2e38f351083aed7edec8ede53ebc3fa051b5826f13605ab85d252721a5ea2fef`。

第一稿曾在隔离地图生成 24 栋房屋的 74 扇门；只更新独立烘焙门扇、保留其他构件和身份，12 个碰撞三角面/门。该候选已过时，禁止发布。旧形状的 HTTP MCP 预制件生成、开合、撤销重做、保存重开测试曾通过，不能等同于本修订美术版本或正式城镇已通过验收。

接入草案移至 `D:/code/rmmo_runtime/art_sources/timber_door/integration_draft/`，不在游戏生成路径启用。后续需同步三色、UV、纹理依赖和原生烘焙序列化，再验证内开方向、门轴、四向及任意朝向、闭门阻挡/开门双向通行。外门按立面内侧开，室内门继续避让公共走廊；不改窗扇或城防门。更新原有冻结门扇须保留地板/屋顶分组和实例身份，正式保存仍走原生原子保存与冲突检测。


2026-10-05 追加参考：`references/timber_door_20261005/edge_cross_relief.png`。当前 GLB 保留平滑凸脊法线，作者网格 JSON 同时导出逐角法线；后续接入不得重新生成全平面法线丢失凸脊。正式地图仍未替换。

横脊补充修订：用户标红指出横向仍太平。横纵凸脊统一为 28 mm 的最大附加隆起，扩大横脊肩宽，并采用连续交叉曲面避免竖脊吞掉横脊。额外横截面保留凸脊轮廓，整门 1680 三角面、2 材质，非退化面和三色校验通过。`spear_relief.png` 为侧向补光近照，`spear_detail.png` 保留原打光角度，两个视角均由真实 Godot 后台渲染生成。用户标注见 `references/timber_door_20261005/horizontal_ridge.png`。

## 减面验收（最新资产：1322 三角面）

用户要求检查面数，在不大幅损伤质量的前提下减面。最终采用保守版：

| 分组 | 优化前 | 优化后 |
| --- | ---: | ---: |
| 木板 | 316 | 182 |
| 金属件 | 1364 | 1140 |
| 合计 | 1680 | 1322 |

减少 358 个三角面（21.31%），仍为 2 个网格、2 个材质、3 种木板深浅。删除斜板背后与实心芯接触的面、上下板在中腰的内部接触面、藏在边框内的端面；保留正面拼缝。四条弧带每条由 16 段调整为 12 段。矛饰十字凸脊保留顶点、肩部和宽侧面关键截面，只去掉部分中间截面。不得删除开门后可见的门背、边框背面和五金外侧。

曾试过 1226 面版本，十字凸脊极近距离高光变化偏大，因此退回保留更多曲面细节的 1322 面版本。三色、非退化三角面校验均通过；独立 Godot 场景、GLB、Blender 源与 JSON 网格均已更新。

使用相同相机和光照比较五个 GPU 渲染视角：背面逐像素一致；整门正面平均通道差约 0.019/255、斜正面约 0.035/255；十字凸脊补光极近照约 0.335/255。极近照仍有细微高光差别，并非完全无损。以上像素数据仅描述这组视角，不能代表所有光照下的美术验收或帧率收益。

优化前 GLB、JSON、制作脚本和五张截图留在 `D:/code/rmmo_runtime/review_artifacts/timber_door/before_reduction/` 供对照。最终报告为 `D:/code/rmmo_runtime/art_sources/timber_door/optimization.json`，图像对比数据为预览目录的 `reduction_image_metrics.json`。正式城镇未发布本资产。

## 用户指定进一步简化：细长立体菱形（最新）

用户提出“矛头可以直接弱化为一个长的立体菱形”。已将两处采样曲面凸饰替换为六顶点、八三角面的闭合立体菱形。靠门边的位置保留，中部隆起由四块平面形成；此处有意简化原来的曲面十字凸脊。

- 每个菱形：8 三角面；长 0.36 m、高 0.084 m，靠边尖端距门边 20 mm。
- 整门：846 三角面（木材 182，金属 664）、2 网格、2 材质，三色斜板及弧形铁带保留。
- 相比保守减面版 1322 面，再减少 476 面（36.01%）；相比最初 1680 面共减少 49.64%。
- 源文件、GLB、JSON、Godot 预览场景和五个视角图片均已更新。生成器仍验证非退化面、三色和尖端边界，并新增 900 面上限。
- 此次是用户授权的外形简化，不再宣称与复杂十字凸脊版近照无损一致。之前 `reduction_image_metrics.json` 只属于 1322 面的保守版，不适用于当前菱形版。
- 正式城镇仍未替换。


## 最终接入与验收

- `scripts/world3d/timber_door_mesh.gd` 读取 Blender 导出的 UV、顶点色、法线；冻结后几何直接存在房屋预制件中，不在游戏进图时重建门板。每门 846 三角面、2 材质面，碰撞为 12 三角面的门芯盒。
- `runtime_mesh_cache.gd` 为材质记录保存可选 `vertex_color` 布尔值，恢复时复制材质后启用顶点色，避免改变其他墙体共用的木纹材质。旧缓存及旧预制件兼容。
- 保持每扇门 UUID、所属建筑、楼层、铰链与原开度；外门改内开，门芯碰撞同步转动。非门的地图记录逐条比较不变。
- `tools/test_house_prefab_mcp.gd` 真实 HTTP MCP：工具发现、生成、非法开度无副作用、门开度、撤销重做、素材库拷贝、锁定保护、保存重开均通过；重开和打包后仍为三种板色及相同面数。
- `tools/test_timber_doors.gd` 独立 Windows 桌面/Vulkan：24 栋入口全部向内，关闭阻挡胶囊、打开双向通行，失败数 0。
- `tools/upgrade_town_doors.gd` 先生成临时候选图；发布校验当前模型 SHA、候选图 SHA、正式地图基线 SHA 与物理测试报告。正式保存后重新打开成功，所有权一致。没有复制整份正式地图目录。
- 正式地图：`D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf`；发布 SHA256：`07471d74a84e91983f49164f4f830fd196c0f93695e1054a3877d16015557bd3`。
- 报告与日志在 `D:/code/rmmo_runtime/review_artifacts/timber_door/`：`upgrade.json`、`physical.json`、`mcp_runtime.log`、`publish_runtime.log`。城门和五处地标不在本次替换范围内。
