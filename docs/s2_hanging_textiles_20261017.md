# S2 悬挂布饰交付与验收 · 2026-10-17

当前阶段：v6 独立模型画质、资源、native 保存重开、正式共享组件库发布及真实 HTTP 接入验证均通过（4/4）。本任务未部署正式 S2 地图。

## 参考与边界

参考：[S2 节庆住宅街镜头](references/town_required_shots_20261012/03_festival_residential_lane.webp)，SHA `2ea277fd49a3e5033e56dcc7d008de595cd554da691ce1afcfded33152d898cf`。补齐黄色短矩形跨街旗、墙间白布晾绳、黄底长竖幡及复用古铜旗灯的长幡样式。原 S1 多色尖旗、S2 彩柱、S12 墙旗和原红旗灯保持独立，不做替换。

布旗准确数量、隐藏缝线/绳结/固定件、尺寸及长幡具体角形纹样为**项目补充设计**。不将纹样说成官方文字。灯杆、灯罩与晶石复用原件；本轮不扩展到建筑、整城性能或正式地图布置。

## 版本与证据

母版及导出：`D:/code/rmmo_runtime/art_sources/s2_hanging_textiles_20261017/v6/`。每件 `_authoring.json` 记录母版 SHA、挂点和制作说明。完整交付索引：[handoff.json](../../rmmo_runtime/review_artifacts/s2_hanging_textiles_20261017/handoff.json)。

| 组件 | 三角面 | 源 GLB MiB | native MiB | 网格 / 表面 | 纹理解码含 mip 预算 MiB |
|---|---:|---:|---:|---:|---:|
| S2 黄色短矩形跨街布旗串 · 8米 | 34,212 | 4.83 | 5.22 | 13 / 13 | 16.67 |
| S2 墙间白布晾绳 · 3.6米 | 17,248 | 4.31 | 4.99 | 4 / 6 | 16.67 |
| S2 黄底纹样长竖幡 · 独立布旗 | 12,692 | 6.51 | 8.81 | 2 / 2 | 48.67 |
| S2 古铜旗灯 · 黄底长竖幡样式 | 14,620 | 6.99 | 8.85 | 5 / 7 | 48.67 |

预算为每件源中唯一图片按 RGBA8/mip 保守估算，不能当作实测 RSS/VRAM，也不能按实例数直接累乘共享纹理。跨件相同图片可共享；实际驱动纹理格式/物理驻留未测。灯样式保留源描述符与二进制，源材质描述符 23 个，但 native 实际使用 7 个。

本轮不强制减面/新增 LOD：布面细分参与风动及褶皱轮廓，保留独立挂点；绳结、包边在近景可见。保留母版和退回版本，没有将文件压缩率作为画质或内存结论。未开展整城 FPS/RSS/VRAM 性能专项。

### 每件身份与放置接口

#### S2 黄色短矩形跨街布旗串 · 8米

- ID：`s2_yellow_rectangular_festoon_8m`
- 源 SHA：`9814ad653a94241f049fe2b02c83849a45d9abd89d0b42f45287503708fc296a`
- native SHA：`b8d5a0b009e6a9d4f43026569b762014a7a87bfdc94ed75e1ab13cffeaad4a15`
- AABB：`{"position": [-4.052000045776367, -1.3952796459197998, -0.06350739300251007], "size": [8.1039400100708, 1.4472795724868774, 0.12902826070785522]}`
- 挂点：`{"left_end": [-4, 0, 0], "right_end": [4, 0, 0], "span": 8.0, "cord_midpoint": [0, -0.48, 0], "front_axis": "+Z", "mount_height_recommended": 4.7, "minimum_static_cloth_height_at_recommended_mount": 3.3047203540802004, "notes": "Root is midpoint of end-to-end chord. Align both eyes to post rings. Do not stretch Y with X; use uniform scale or a correctly sized variant."}`
- [独立验收记录](../../rmmo_runtime/review_artifacts/s2_hanging_textiles_20261017/acceptance/s2_yellow_rectangular_festoon_8m.json)

#### S2 墙间白布晾绳 · 3.6米

- ID：`s2_wall_to_wall_white_laundry_36m`
- 源 SHA：`3a49702a127ca822a22f5ee6d76e067867fb5c5595efaf375b009c4c7086cdc8`
- native SHA：`0ac53260112d165d0df0d6f0913ecbe1dfdbec635fb2df8c6848d3fe99991f3a`
- AABB：`{"position": [-1.9299999475479126, -1.5714832544326782, -0.08029746264219284], "size": [3.859999895095825, 1.6414833068847656, 0.16465458273887634]}`
- 挂点：`{"left_end": [-1.8, 0, 0], "right_end": [1.8, 0, 0], "span": 3.6, "cord_midpoint": [0, -0.15, 0], "front_axis": "+Z", "mount_height_recommended": 3.8, "minimum_static_cloth_height_at_recommended_mount": 2.2285167455673216, "wall_planes_x": [-1.9, 1.9]}`
- [独立验收记录](../../rmmo_runtime/review_artifacts/s2_hanging_textiles_20261017/acceptance/s2_wall_to_wall_white_laundry_36m.json)

#### S2 黄底纹样长竖幡 · 独立布旗

- ID：`s2_ochre_long_banner`
- 源 SHA：`6043574732977c3dcb756ca88c5043cb12d2db2b834ddf70ece8e216378e2851`
- native SHA：`47037a8297b5ed08e9026c74500216bf4a59e6a9653a4bcea595f09d89a2b7cb`
- AABB：`{"position": [-0.3354779779911041, -2.053967237472534, -0.047223277390003204], "size": [0.6710155606269836, 2.0899672508239746, 0.08719438314437866]}`
- 挂点：`{"mount_origin": [0, 0, 0], "width": 0.67, "cloth_drop": 2.045, "front_axis": "+Z", "lamp_local_mount": [-0.61, 2.835, 0.038], "lamp_reference_source": "f308819058f9a51e8fecb41b24ac839073153f48481979af18c73c273199a2c9", "lamp_variant_replaces_existing_cloth": true}`
- [独立验收记录](../../rmmo_runtime/review_artifacts/s2_hanging_textiles_20261017/acceptance/s2_ochre_long_banner.json)

#### S2 古铜旗灯 · 黄底长竖幡样式

- ID：`s2_bronze_lamp_long_ochre_banner`
- 源 SHA：`259970ec89bfc6d3b42ff3f058808d791165d45801b050b6ed090a127e083d12`
- native SHA：`82507d66ba918329b17c95b421793a824b9974ef3dbdfef0a54f447e2912322c`
- AABB：`{"position": [-1.0899999141693115, 0.0, -0.20859648287296295], "size": [1.2985963821411133, 4.0980000495910645, 0.4171929657459259]}`
- 挂点：`{"ground_origin": [0, 0, 0], "front_axis": "+Z", "banner_mount": [-0.61, 2.835, 0.038], "cloth_lowest_about_y": 0.78, "note": "Use this lamp style instead of the original red-flag lamp; do not overlay two lamps."}`
- [独立验收记录](../../rmmo_runtime/review_artifacts/s2_hanging_textiles_20261017/acceptance/s2_bronze_lamp_long_ochre_banner.json)

全部坐标为米、Y 向上、正面 +Z，跨绳沿 X。挂点使用模型根坐标，而 `place_asset.position` 为 AABB 底面位置：直立时 `input_y = desired_root_y + bounds.position.y * scale.y`，不要将负向下垂的布件根点误当底面。

黄色串旗两端跨度 8m、绳中点下垂 0.48m；挂点建议 4.7m，静态最低布边约 3.305m。先将挂环对准柱身固定位置（通常柱顶下约 0.2m），再按实地净空复核。不能仅拉伸 X 却不考虑布幅与绳结变形。白布绳端跨度 3.6m，墙接触平面约 X=±1.9m；建议挂点 3.8m，静态最低约 2.229m，最终通行净空由布景现场确认。

独立长幡宽 0.67m、布面下垂约 2.045m；在原灯局部挂点 `[-0.61,2.835,0.038]`。推荐直接使用已装配的长幡灯样式，不能在旧红旗上叠另一块布或叠放两根灯杆。

## 受影响项复验

- 资源：实际 GLB 与 authoring、CPU、GPU 报告 SHA 对齐；有限坐标、有效几何、UV、切线检查通过。native 保存重开语义与纹理指纹一致。
- 材质：布面 metallic=0，粗糙度及织物法线有效；实际 native 法线像素 SHA 与导出贴图一致。长幡印花为贴图染色，随布面褶皱变形；颜色、粗糙度、法线共用正确 UV。
- 结构：旗串 12 块、白布 3 块、长幡 1 块各有独立顶部风动挂点；静态绳/挂环不随风。布及悬挂件不阻挡行走，但有编辑器拾取体；灯柱延用既有碰撞。
- 画质：每件实际查看 near、medium、far、back、cloth_detail、attachment、wind_t1、wind_t4，共 32 张。原始相机、曝光 1、ACES、太阳 1、环境 0.28、1600×1000、MSAA4 条件记录在每件 report.json。
- 风场：两次样本使用风向量 `[3,0,4]`、t=1/4；自动检查顶部最大位移上界 <1mm，人工未见挂点脱离/布边异常。结论仅覆盖所列视角和时刻，不表示所有风向全周期均已检查。
- 复用灯体：`v6/lamp_reuse_byte_proof.json` 证明原灯二进制前缀、非布网格描述符及材质保持。灯的金属、玻璃、晶石和昼夜合同沿用既有实现，本轮不是全新的灯具近景/夜景材质放行。

### 退回版本与修复

v1 的实厚边缘 UV 退化已修；v3 检出 Blender MixRGB 导出丢失色因子，改为标准 glTF texture×factor 并核对实际导出。v4 的叠加图案几何与布面相交，退回；v5 多 UV 通道方案未进入验收。选中 v6：印花与织物通道采用同一 UV 图集，近景/背面连续；旧版本和失败证据保留。

### 正式库与编辑器复验

正式接入验证已通过。采用现有 AssetLibrary 导入与当前 3D HTTP 的 list_assets/place_asset/select_objects/undo/redo/save_world/open_world，临时地图验证，不覆盖用户地图。

接入前发现 streetlamp_banner.apply 会以默认参数覆盖导入风场；已修为原始布形优先保留已作者化参数，旧版无风场标签仍用旧默认值。单材质印花布的 original 模式保留原网格与全部 PBR，避免切换风动时按旧双材质旗帜访问越界或丢失印花。UI 与 3D MCP 共用相同逻辑，无新增 schema。最终 HTTP 复验将覆盖禁用风、撤销/重做、保存重开、重新启用，以及无效形状无副作用失败。

## 上传图片压缩

32 张图均已在查看前用有损 WebP quality=90、method=6 编码，保持 1600×1000；PNG 合计 6,626,364 字节，WebP 合计 647,070 字节，减少 90.2%。每张 `.review-image.json` 有源/目标 SHA 与编码参数，实际查看发送 WebP。无损图暂保留本地作证据，不再上传。

## 最终接入记录

| 验收项 | 结论 |
|---|---|
| 资源审计 | 4/4 通过，实际导出 SHA 与证据绑定 |
| 画质 | 4/4 通过所列 32 张图和两次风动样本；复用灯体近景/夜景非本轮新验收 |
| 运行管线 | 4/4 native 保存重开及实际材质、挂点、拾取/碰撞检查通过 |
| 正式共享库 | 4/4 发布；真实 3D HTTP 检索、放置、选择、撤销/重做、保存重开通过 |
| 正式 S2 地图 | 本任务未放置；仍需由布景任务按参考机位验证布局、挂点与净空 |

发布回执：[publication/receipt.json](../../rmmo_runtime/review_artifacts/s2_hanging_textiles_20261017/publication/receipt.json)。最终验证：[formal_http_v2/editor_verification.json](../../rmmo_runtime/review_artifacts/s2_hanging_textiles_20261017/formal_http_v2/editor_verification.json)。完整绝对路径、正式 asset_id、源/native SHA、挂点和每件报告集中在 [handoff.json](../../rmmo_runtime/review_artifacts/s2_hanging_textiles_20261017/handoff.json)。

首次 formal_http 检查中，风动开关重建网格使几何指纹变化；该失败记录保留。改为 original 单材质印花直接复用源 Mesh，formal_http_v2 再验通过：几何数组、底色、粗糙度、法线像素、顶部挂点参数保持一致。关闭风动后保存重开，再启用也通过；无效形状无副作用、UI 面板、撤销重做均验证。运行代码 SHA 已写入 HTTP 报告。

功能验证使用独立后台桌面，不抢焦点；允许与其他功能测试并行，未采集性能结论。GPU 视觉图在此前固定条件下采集。本轮不改接口 schema、不启用旧二维 MCP；UI 和当前 3D MCP 共用修正后的业务逻辑。

### 正式库组件名与 asset_id

- **S2 黄色短矩形跨街布旗串 · 8米**：`D:/code/rmmo_runtime/packs/default/assets/9814ad653a94241f049fe2b02c83849a45d9abd89d0b42f45287503708fc296a.glb`
- **S2 墙间白布晾绳 · 3.6米**：`D:/code/rmmo_runtime/packs/default/assets/3a49702a127ca822a22f5ee6d76e067867fb5c5595efaf375b009c4c7086cdc8.glb`
- **S2 黄底纹样长竖幡 · 独立布旗**：`D:/code/rmmo_runtime/packs/default/assets/6043574732977c3dcb756ca88c5043cb12d2db2b834ddf70ece8e216378e2851.glb`
- **S2 古铜旗灯 · 黄底长竖幡样式**：`D:/code/rmmo_runtime/packs/default/assets/259970ec89bfc6d3b42ff3f058808d791165d45801b050b6ed090a127e083d12.glb`
