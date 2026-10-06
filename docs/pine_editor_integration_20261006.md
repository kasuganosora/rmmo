# 密冠松树：簇级减面与编辑器接入

最新补充：已开发原生编辑器树形参数，素材库只保留“参数化松树·小型 / 成熟 / 倾斜”三款可编辑预制件。按用户要求已移除六个旧固定预制件/模型入口，底层文件保留供旧地图引用。树高、冠幅、树干、裸干、倾斜、密度及种子的使用方式、3D MCP 和验收详见 [参数化编辑器交付](parametric_baltic_pine_20261006.md)。以下“尚无编辑器树形参数”的文字仅描述之前固定模型阶段。

## 用户验收与正式预制件（2026-10-06）

用户明确“通过验收，可以放到游戏编辑器中作为预制件”。已通过真实 HTTP `save_prefab` 将验收版 V6 登记到默认资源包的“预制件”分类，名称为“写实密冠松树·小型·预制件”“写实密冠松树·成熟·预制件”“写实密冠松树·倾斜·预制件”。原始模型资源条目保留；预制件复用相同不可变 GLB，贴图依赖已包含在模型中，保留三级 LOD、碰撞及风动。编辑器里的实例支持原有变换，Blender 程序化控制仍在母版中，不宣称已新增编辑器树形参数面板。

在临时地图验证三款预制件放置、撤销重做、非法 ID 无副作用、六个模型/预制件实例保存重开与依赖完整，失败数 0。未修改用户地图。发布凭据为 `D:/code/rmmo_runtime/review_artifacts/pine_density/prefab_publication.json`，工具入口 `tools/publish_pine_prefabs.gd`。打开更新后的编辑器并刷新素材库，搜索“写实密冠松树”即可放置。

## 密集绿植运行开销优化（2026-10-06）

用户说明地图绿植较多后，本轮保留 V6 的模型、纹理、三级面数、阴影和母版，优化共享风动运行时。被 LOD 隐藏的叶层暂停逐帧参数更新与避风射线；保留绑定，跨边界直接恢复当前风动时间。使用与渲染一致的变换后 AABB 中心，过渡带额外预留 1 m，镜头移动超过 0.25 m 重算活动集合，常规 0.35 s 扫描更新物件移动/移除。恒定风速不再重复上传相同参数。风形变依赖单一固定轴，法线改用等价秩一变换，减少形变采样及通用矩阵求逆，保留法线和切线随风弯曲。

在私有后台桌面的 256 棵合成阵列、1280×720、MSAA4+TAA、RX 7900 XTX 上：绑定 240 个近距离受风叶层，逐帧活动 116 个；风动更新中位数从 1.137 ms 降至 0.527 ms（约 54%），周期扫描从 3.475 ms 到 3.590 ms。GPU 中位数最终 2.858 ms；同场景旧法线着色器对照 2.948 ms，差距小，不宣称显著 GPU/FPS 提升。帧等待受同步影响，不能用来证明倍数帧率提升。阵列包含视锥外树，非 256 棵全部可见；实际地图的草、花池及建筑组合尚未压测。

前后同镜头阵列截图逐像素一致（RGB 平均/最大差均 0），近景受风针叶亦已检查。此证据限于测试镜头，不代表所有角度数学无损。`test_wind_lod_optimization.gd` 通过 2000 组法线等价检查、变换后边界、镜头返回恢复时间及移除缓存检查；`test_world3d_wind.gd` 覆盖风向/停止、旋转、屋顶避风、恢复材质和流式卸载；`test_pine_runtime.gd -- --game-cards --reuse-imports` 真实 HTTP MCP 与保存重开失败数 0。

证据目录：`D:/code/rmmo_runtime/review_artifacts/pine_density/`，含 `before.json/png`（修改前）、`after.json/png`、`legacy_shader.json/png`、回归日志。复测入口 `tools/benchmark_pine_density.gd`，GPU 计时采用 [RenderingServer 视口测量](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu)。本轮不重发布 GLB、不修改用户地图。新增运行时优化在重新启动更新代码的编辑器/游戏后生效；LOD 平滑切换、远景替身与森林合批仍未实施。

## 当前结果：V6 已更新编辑器资源库

2026-10-06 用户允许减少针叶微观精细度，以游戏视角不结块为重点。V6 三款已更新共享库目录项，原母版及旧不可变文件保留，未修改用户地图；已有地图中的旧树不会自动替换。

近景每棵 48,308–48,309 三角面（含树干），比 V5 减少约 97.8%；中景 7,838–7,851，远景 3,682–3,691。默认 35/85 m 切换，共同包围盒中心、1 m 滞回。三档合计存储约 56,600 面，不代表同时绘制；单款 GLB 约 22.4 MB。

五个源枝簇分别拟合 12/16/20/28/28 张带透明间隙的小枝面片，共享 3072×2048 基色/法线图集，保留 583 个枝簇变换。中远景减少面片并补偿覆盖。游戏全树、侧面、近景、40/90 m 透视及风动画面已检查，树冠保留分层与透空；针叶微观体积较 V5 简化，不宣称无损。LOD 当前为硬切换，无渐变；远景不是 impostor，未新增森林 MultiMesh 合批。

Blender 文件：`D:/code/rmmo_runtime/art_sources/bridge_street_kit/baltic_pine_procedural/baltic_pine_game_v6.blend`。重开验证 48,308 面、583 个实例、6 张打包纹理及冠幅控制有效。三级 LOD 由导出脚本生成。构建顺序：`export_pine_game.py` 烘焙 → `pad_pine_cluster_channels.py --game-cards` → 导出脚本 `--reuse-baked` → `finish_pine_game.py` → `finalize_pine_runtime.py --game-cards`；原生文件另由 `polish_pine_game_native.py` 整理。

真实 HTTP MCP/游戏测试失败数 0，覆盖发现、三款放置、非法调用无副作用、撤销重做、风动/碰撞、保存重开及运行时流式加载 LOD。范围逻辑测试也通过。16 棵帧等待中位数 16.557 ms、P95 18.27 ms，包含引擎调度与同步，不是 GPU 单项计时或森林/VR 性能保证；最大放置 1.625 s、保存 5.191 s、重开 0.290 s。进一步优化应先测实际种植密度下的透明片重叠、阴影及切换。

最终凭据目录：`D:/code/rmmo_runtime/review_artifacts/pine_dense_v3_game/`，含 `validation.json`、`visual_review.json`、`runtime_blend_integrity.json`、`published.json`。发布记录确认替换三条旧目录项并保留旧文件。

## 历史结果：V5

2026-10-06 用户要求继续优化后，最终采用 **2.5 cm 分组 + 叶簇拟合平面**，保持 583 个原始枝簇变换、V3 加密树形及三款预设。每棵 **2,195,732 三角面**，相对母版 244,265,030 减少 **99.10%**。相比上一候选多用约 38% 面数换取叶簇空间层次，不追求最大减面比例。叶子仍以邻近叶簇共用面片，透明遮罩不做膨胀。

参数化 Blender 文件：`D:/code/rmmo_runtime/art_sources/bridge_street_kit/baltic_pine_procedural/baltic_pine_dense_cards_v5.blend`。重开验证 583 个实例、冠幅参数有效、14 张使用中的文件纹理已打包；原高精度母版保留。中间文件 `baltic_pine_fine_clusters_runtime.blend` 为直接导出用 PBR 模型，V5 另恢复原始薄叶透光节点。

共享库 `D:/code/rmmo_runtime/packs/default/assets/library.json` 已原子新增三款：“写实密冠松树·小型 / 成熟 / 倾斜”，分类“树木·写实松树”。发布后重新读取验证条目与哈希，未修改任何用户地图。重新启动使用更新代码的编辑器并刷新资源库后，可搜索“写实密冠松树”。

## V5 自审和实测

- 正面、2.5 m 取景近景、侧面与游戏静止/受风画面已检查：消除整段枝条糊成宽叶块的问题，保留细针、枝间透空及原树形；没有恢复逐片高细节针叶几何。此结论限于检查视角，不宣称像素一致或数学无损，显微近景不等同原始针叶体积。
- Blender 保留原始薄叶透光混合。游戏用显式节点参数 `rmmo_leaf_backlight` 恢复逐材质槽的实时薄叶背光，只有五个叶材质槽启用，树皮不启用；风动材质保留相同值。它是 [Godot 背光模型](https://docs.godotengine.org/en/4.5/classes/class_basematerial3d.html#class-basematerial3d-property-backlight) 的实时近似，不等于 Blender 路径追踪的体积散射。材质不自发光，响应场景光源。
- `test_leaf_backlight.gd` 通过非法参数无副作用、共享树皮不污染、强度、风场转换与重复加载检查；`test_world3d_wind.gd` 完整回归通过。真实 HTTP MCP 测试通过发现、三款放置、非法放置无副作用、撤销重做、风关闭/恢复、保存重开后的五槽透光恢复、运行时碰撞和风动检查，最终失败数 **0**。
- 首次冷加载测试在 5 秒客户端期限触发一次撤销超时，原始失败日志保留。重跑使用已验证哈希的不可变导入资源，客户端期限 30 秒并记录真实耗时；不是删除失败断言。最大耗时：首次放置 **20.4 s**、撤销 **7.49 s**、重做 **7.3 s**、保存 **27.4 s**、重开 **6.9 s**。资源仍很重，不能称为即时编辑或轻量森林资源。
- 16 棵共 35,131,712 三角面；独立桌面测试帧等待中位数 **24.517 ms**、P95 **25.607 ms**。此数据包含引擎调度，不是 GPU 单项计时，也不是复杂城镇或 VR 性能保证。项目 MSAA 4x + TAA 下检查针叶；无抗锯齿截图不作为最终图像依据。

最终凭据在 `D:/code/rmmo_runtime/review_artifacts/pine_dense_v3_fine/`：`validation.json`、`visual_review.json`、`runtime_blend_integrity.json`、`published.json`。`test_backlight.log` 保留冷加载超时，`test_backlight_retry.log` 是最终通过记录。所有图片是实际 Blender/Godot 渲染。

用户已确认 `baltic_pine_dense_v3.blend` 的加密树形和裸干缩短 50 cm，授权接入编辑器；随后指定同层相邻针叶共用面片，并指出第一版减面“变成一坨”。原母版和此前已确认的渲染保留。

## 减面方式与淘汰记录

- 原母版等效 244,265,030 三角面。将整段枝条投影到少数分层大面片的 23,001 面候选出现块状树冠，已淘汰，未发布到共享资源库。
- 改为源模块内约 4.5 cm 的空间小格。先识别完整连通针叶，再按针叶主轴平面朝向分组，不在三角面层面切断针叶。五个模块分别使用 187、383、489、1014、963 个小面片，按原母版的 583 个枝簇变换还原三款树形。主干骨架保留实体，细枝另保留简化的实体网格和树皮，叶簇共享透明面片，不再每片针叶对应独立几何。
- 从原几何分别烘焙无光照基色、透明遮罩及切线法线。额外烘焙叶簇 ID，剔除射线误捕获的其他簇，避免多张面片重复显示后方叶子而堵住空隙。修复材质槽清空导致针叶误用树皮的问题。
- 烘焙阶段将完整叶簇临时移入彼此相隔 2 m 的独立格，再把面片还原，避免其他叶簇遮挡导致针叶碎点。每簇纹理单元提高到 128 像素。近景比较又发现 3 像素烘焙扩边会把细针拓宽成宽叶，故覆盖率烘焙禁用扩边；上一轮有扩边候选同样不通过视觉验收。所有版本仍以实际同镜头比较为准。
- 后续检查发现禁用全部扩边后，透明区域的 RGB 为黑色，法线也未延展，双线性过滤会让细针边缘偏暗。`tools/pad_pine_cluster_channels.py` 按 128 像素叶簇单元补齐透明区域下的基色和法线，**不修改 alpha**；原始未补边纹理保留于 `zero_margin_unpadded/`。这与扩大遮罩是不同操作，逐像素检查 alpha 相等后再以 `--reuse-baked` 导出。是否通过仍由同条件渲染决定，不把此技术修正自动算作美术通过。
- 用户要求继续优化后，另行测试了原母版 14% 薄叶透光和连续覆盖率，保存 `baltic_pine_dense_cards_v4.blend`；其结果仅是 Blender 材质实验，不代表普通 glTF 已支持此透光混合。降低硬裁切到 0.25 会使树冠更黑、更实，予以排除。开始制作 `--fine-clusters` 候选：分组单元 2.5 cm、各组用 PCA 拟合实际叶簇平面，保留原树形与独立版本，检查是否改善压平造成的侧向厚度损失。
- 中间版 732,115 面仍因三角面分组而出现针叶碎点，并缺少簇间实体细枝，也没有发布。当前完整针叶分组加实体细枝的版本每棵 **1,587,030** 三角面，约减少 **99.35%**；这是实际展开后的面数，不是独立模块面数。贴图保留细针轮廓，仍须在远近视角下做图像审查，不能只以减面比例验收。

## 文件与流程

母版位于 `D:/code/rmmo_runtime/art_sources/bridge_street_kit/baltic_pine_procedural/baltic_pine_dense_v3.blend`，从不覆盖。导出候选位于 `D:/code/rmmo_runtime/assets/baltic_pine_dense_v3/`。

另存可参数化的小簇版 `D:/code/rmmo_runtime/art_sources/bridge_street_kit/baltic_pine_procedural/baltic_pine_small_clusters_runtime.blend`，保留原生 Geometry Nodes 输入和原版切换；文件重开核验 583 个枝簇实例及全部依赖纹理打包。这里的 Optimized=True 现指小簇运行几何，False 仍是非常重的原始模型。

`tools/export_pine_small_clusters.py` 负责小簇分组、所有权遮罩和烘焙；复用 `tools/export_pine_runtime.py` 的预设导出部分。后者早期的大面片烘焙路径不作为本批最终生产入口。`tools/finalize_pine_runtime.py` 显式指定 glTF Alpha Mask 和双面材质；材质名称避免 Windows 文件名禁用字符，确保地图外置纹理保存正常。

`tools/test_pine_runtime.gd` 在临时库和临时地图，经过真实 HTTP MCP 检查工具发现、放置、失败原子性、撤销重做、风关闭/恢复及保存重开；并检查运行时碰撞、风场着色器、游戏渲染和 16 棵树的场景。通过 `tools/run_godot_background.py` 在不激活桌面运行，不改用户地图。

`tools/publish_pine_runtime.gd` 仅在功能与视觉检查通过且哈希一致时将已验资产写入共享资源库，使用原生冲突检测和原子保存。目标名称为“写实密冠松树·小型 / 成熟 / 倾斜”，分类“树木·写实松树”。不会自动铺进现有城镇地图。

## 上一版阶段记录（由 V5 结果替代）

2026-10-06 本轮实测：禁用烘焙扩边后，宽叶块、粘连问题消除，近景细针和缝隙恢复。三款资源通过真实 HTTP MCP、风动、碰撞、撤销和保存重开检查，失败数 0；Blender 文件重开确认 583 个实例、14 张有使用者的文件图像全部打包。Godot 独立预览已对齐项目 MSAA 4x + TAA，避免无抗锯齿的针叶噪点误导自审。

**上一版 4.5 cm 候选没有通过视觉检查，也没有发布共享库。** 当时的同相机对照中，部分近景叶簇比母版偏暗、偏薄；原母版的透光混合与表面深度没有被普通 glTF 遮罩材质完整保留。旧结果目录的 `visual_review.json` 保持 `accepted=false`，不将其与本页顶部 V5 的实际发布凭据混淆。

结果目录为 `D:/code/rmmo_runtime/review_artifacts/pine_dense_v3/`。`validation.json` 记录功能检查；`visual_review.json` 记录最终图像审查与实际已验哈希；只有 `published.json` 表示共享库已发布。尚无发布凭据时，不将导出候选视作完成接入。

Blender 参数生成器保留；编辑器沿用现有资产变换和风场功能，不宣称已有 Blender Geometry Nodes 的原生编辑器参数面板。此项是资源接入，不新增编辑器工具或恢复旧二维 MCP。
