# 阿克塞尔警卫处模型验收（2026-10-16）

当前选中 v6 已完成 Blender 母版、游戏 GLB、导出侧 CPU 审计和隔离 native／GPU 图审；真实 HTTP 胶囊通行与编辑器保存重开已通过；正式素材库发布和直接正式路径使用已通过126项联合验证。没有改动正式 axel_town 地图；地图部署及整图性能仍由布局任务验证。

## 身份与参考

- ID：`axel_guardhouse_20261016`；名称：阿克塞尔警卫处；制作阶段：完整结构与便携 PBR 候选。
- 主要视觉依据：[U13 公会／告警塔／警卫处关系图](references/axel_guild_plan_20261007/user_13_guild_alarm_guard_relationship.png)，归档文字见 [公会镜头设定 U13](axel_guild_screenshot_review_20261007.md)。已实际查看完整图片及用户标注。图像可辨浅墙、二层尺度、红瓦坡顶与独立布置；远景不足以确认精确窗数、内部、门廊连接及屋面白点。未把 S12 河岸住宅当作警卫处，也不添加告警塔或跨街连廊。
- 结构资料：[English Heritage Dunstanburgh Castle 实物与功能说明](https://www.english-heritage.org.uk/visit/places/dunstanburgh-castle/history/description/)、[官方分期平面](https://www.english-heritage.org.uk/siteassets/home/visit/places-to-visit/dunstanburgh-castle/history/dunstanburgh-castle-phased-plans.pdf)。用于核对值守房间、上层居住及庭院出入之间的关系，不照搬巨大城门体量。
- [Historic England 剖面／平面档案 MP/DUN0012](https://historicengland.org.uk/images-books/photos/item/MP/DUN0012) 的全文图像不可用，不能声称看过该剖面。实际平面推敲来自已打开的官方分期平面和本项目的空间设计。
- 旧暂定 13×10m 主体来自公会白模记录。完整内部、背面、门廊、壁炉／烟道、门窗数量、家具位置均为**项目补充设计**，不是动画精确复原或工程承载认证。

## 结构与游戏尺寸

主体 13×10m；局部 +Z 为正面、+Y 向上，原点在地面中心。实际导出 AABB 为 `{'min': [-7.085000038146973, 0.0, -5.619999885559082], 'max': [7.085000038146973, 11.300000190734863, 6.675000190734863], 'size': [14.170000076293945, 11.300000190734863, 12.295000076293945]}`。首层地面 +0.30m，二层 +3.90m，主檐 7.25m、主脊 10.80m，烟囱最高 11.30m。近屋面处的斜墙封口以坡面下皮控制，不让外墙穿顶，也不留下水平截墙造成的透光带。

主入口净洞 2.20×2.95m，双门扇；后勤门 1.50×2.80m。门前保留 x±2.3m、z5..9m 通路；后勤门中心 (3.7,.3,-4.84)，外侧至少 2m 通路。屋檐／平台尺寸应按真实 AABB 放置，不填满布局给出的 19×14m 预留。

两跑楼梯 20 个 .18m 高差、.30m 踏面、1.65m 净宽；中间平台接两跑，顶端实板接二层走廊。CPU 已检查每个踏步支撑和不少于 2.4m 头顶，以及顶梯到楼板的连续落脚；最终 HTTP 已通过标准胶囊连续两跑登楼。尺寸是第三人称游戏调整，不能称通用建筑规范，任意相机与所有家具间隙不在本轮代表性路线的通过范围。

首层含值守桌、等候／巡逻人员共用桌凳、后侧装备库与通向后勤门的路径。二层含办公桌、3 张单人休息床与折返梯出入口。家具几何复用 `tools/axel_guild_furniture.py`，不新增同名素材库资产。后墙壁炉有真实炉口和穿顶空心烟道；未伪造发光或运行灯光系统。

## 材质与资源

|部件|当前材质与来源|画面验收关注点|
|---|---|---|
|首层石墙／石地基|已购 Quixel Stone Tiles Facade 2K，米制2×2m、法线1.0、粗糙度与AO；glTF合并AO/Roughness|斜光砂浆凹槽、石面起伏、避免瓷砖感|
|上层石灰刷面|暖浅色非金属，复用公会已制作切石细法线／粗糙度，normal .14|抹面微表面应克制，不应出现石砖接缝|
|门窗、楼梯、屋架、家具|已购 Natural Joinery 2K，normal .35，木纹沿板长方向|近景纹理尺度及端部方向|
|屋瓦|现有 terracotta_warm 与 2026-10-14 加强层次的 OpenGL 法线；1×.72m|正常近中远与斜光检查叠压层次、拼接；没有为凹凸另造高频噪点|
|门五金|已有锻铁参数 metallic .75、roughness .58|环境高光和双面把手、固定／活动铰链连接|
|玻璃|生产 `rmmo_tinted_glass`：transmittance [.97,.985,.98]、roughness .08，乘法透射＋独立介电反射；标准 GLB fallback alpha .04、暗中性色、IOR1.45、无发光|v4 GPU发现乳白感已退回；v6 亮暗背景透视、排序及投影已在限定 studio 画面复验通过；不宣称焦散／折射|

原始已购贴图及其 metadata 没有改写。母版所有使用图片已打包；实际 GLB 使用 12 张嵌入图，路径、尺寸、通道、源 SHA 和导出 SHA 分别见 manifest 与 CPU 审计。粗糙度因 glTF 通道打包而编码 SHA 可变化，不把文件 SHA 等同于解码像素一致。无上传用有损处理作用到 PBR 技术贴图。

|成本项|v6 候选|口径|
|---|---:|---|
|GLB 字节|50,095,352|嵌入纹理实际源文件|
|Blender 母版字节|38,831,559|已压缩且保留独立结构／门扇|
|三角面|106,452|所有可见作者网格，不含额外LOD|
|mesh／surface／material|50／57／8|非实际 draw calls|
|导出图片解码|99,087,300 B|源图 RGB 基础层|
|RGBA8 全 mip 预算|176,147,148 B|保守预算，非实测显存|
|native 文件|85,587,671 B|实际 .scn 字节|
|native 图片含 mip 解码|132,110,361 B|资源对象实际计数|
|准入保守峰值|1,354,102,123 B|共享准入计账，不是实际 RSS／VRAM|
|近／中／远 draw calls|60|包含验收地面与玻璃额外反射 pass|
|RSS／VRAM／稳定帧耗时|未测|不将预算或单帧监控等同实测|

先保留识别轮廓、真实孔洞和各层／门扇语义，不对一件低频地标做强制百分比减面。106k 面包含完整室内及倒角、门五金、三床和屋架；屋瓦大面由法线表现，只有屋脊瓦和檐口具真实轮廓。本次不新增简化 LOD：低频单实例地标的106,452源面未证明是瓶颈，同条件近／中／远AABB保守投影约826×687、474×387、295×240px（1440×1080，8角投影非精确轮廓），均60 draw／107,414渲染面含地面与光学pass。保留完整房间、真实孔洞和门／楼梯语义；纹理和批次成本不能只靠减面解决。若正式地图profile显示几何瓶颈或大量重复部署，再评估壳体远景LOD。本结论不等于整城FPS验收；详见同批 lod_decisions.json。

## 语义与 CPU 证据

根节点 `rmmo_model_components={version:1}`；`rmmo_building` 保存 6 个真实内部区域。每个 mesh 有稳定 uuid、`rmmo_part`（floor、floor_y、role、part）和 `rmmo_collision`。房屋仍为单资产记录，内部楼层和屋顶按通用导入建筑协议保留；未使用旧公会专用阶段标签。

五个独立门叶持有 `rmmo_hinge`，网格原点在实际门轴，木门、活动铰链桶和两侧把手一起转动；墙上固定底板、销与门框不跟着转。真实运行的开合状态隔离、碰撞、保存重开已在本报告末尾的 HTTP 证据中通过。

2026-10-16 通用导入建筑 CPU 管线补充：author 仍为单条 asset；`model_building` 描述源 SHA、真实房间、稳定源 mesh UUID 成员与默认门状态；活动状态使用新的 `model_building_states`，旧公会的 `model_component_states` 保持原存储位置。成员授权按精确的 namespace 子 mesh 清单，目录按 `building:asset_uuid` 原子分组；房间外的平台、屋顶空间不授予室内身份，未注解资产继续保守 unknown。authority 注册与目录读取同时检查完整源 SHA 和 CPU 从实际 GLB 得到的精确描述；同一路径第二实例不能跳过检查，篡改房间/删减成员以及 geometry/bin 改变但 accessor JSON 不变均会拒绝。

[共享管线 CPU 验收记录](../review_artifacts/axel_landmarks_20261016/guardhouse/imported_membership_cpu_review.json)：新合同 53 项，既有 authority 56、目录 42、城防目录 45、不可变目录证明 37、入场门禁 126 项，合计 359 项通过、0 失败。包含非等比缩放＋旋转、compact/hydrated 两种完整元数据、门状态序列、成员缺失／额外成员和源 BIN 替换。此为临时合成资产的 headless 管线检查，不能代替本警卫处原生资源实际导入、角色行走和 GPU 画质验证。

[导出侧 CPU 审计](../review_artifacts/axel_landmarks_20261016/guardhouse/v6_cpu_audit.json)：301 项通过、0 项失败。涵盖实际 GLB finite/索引/零退化、法线材质切线、UUID、通用合同、外门／上层窗真实穿孔、20 梯级、2.4m 头顶、顶平台连续连接、5 门叶与全开正门通路、固定铰链／移动五金、玻璃生产透射合同和主屋面下皮木望板。它不替代碰撞系统、角色行走、GPU 画面和人工看图。

## 本轮发现与修复

- 初版材质节点因 Blender 中文名称无法查到：改按节点类型识别，不依赖语言。
- 圆柱端面为 n-gon，导出器无法提供切线：仅对最终 n-gon 做可保留自定义法线的三角化，导出后逐材质检查切线实际存在。
- 屋顶挑檐与水平墙顶之间出现潜在空隙：增加按真实坡面下皮构造的墙顶楔形封口，山墙和封边端点对齐实际坡面。
- v3 顶梯与上层平台相差 .25m：v4 添加真实连接板并补21个连续采样。
- v3 门廊柱脚前缘超过上平台约 .1m：v4 上平台延至柱脚外、下级随之外推，并补两柱脚支撑采样。

- v4 GPU 图审发现窗玻璃乳白：v5 使用既有 `rmmo_tinted_glass` 透射／反射双通道，移除高 alpha 浅色 diffuse 的白板效果。所有玻璃同时处理。
- v4 上层／楼梯图显示屋面下皮误用了外侧瓦正面：v6 将主屋面及门廊既有闭合壳下皮改为木望板，并重新按米制铺木纹；保持外侧红瓦及原结构。两处增加材质 surface，未添加叠面。

v1 为构建调试输出、无完整 manifest，不可交付；v2–v5 保留作为回退与问题证据。选择 v6，相同机位材质复验已通过；这是修复后画质验收，非优化无损宣称。

## 身份及交付状态

- 母版：`D:\code\rmmo_runtime\art_sources\axel_landmarks_20261016\guardhouse\v6\axel_guardhouse.blend`，SHA `1cdb0c43dd1ad92d39f7530a39b24ebe7559b98cc0fb26bb85a7c817418ee4da`。
- GLB：`D:\code\rmmo_runtime\art_sources\axel_landmarks_20261016\guardhouse\v6\axel_guardhouse.glb`，SHA `6b811b8f9bdd41a32776af805e1185a24df28e781bc62b7c2994fad117c8fb70`。
- 冻结制作脚本：`D:\code\rmmo_runtime\art_sources\axel_landmarks_20261016\guardhouse\v6\build_script.py`；构建入口 `tools/build_blender_axel_guardhouse_20261016.py`。
- 资源审计：导出侧 CPU 301/0；隔离 native 导入重开及资源计账通过，预算不当作实测峰值。
- 画质：v4 已由图审代理查看15张 GPU 图，玻璃与内屋面材质不通过；v6 由同一代理实际查看全部15张 Q90 WebP，玻璃、木望板、屋架、楼梯平台、门廊支撑与近中远画面在限定 studio 条件通过。
- 运行管线：真实临时库导入、HTTP／UI共享事务、楼层视图与WALK碰撞、实例独立门状态、保存重开均通过。
- 正式素材库：已发布，直接正式路径 HTTP 126/0（三栋合计）通过；正式地图：未修改；整场景玩法／性能：由布局任务验收。
- 画面由图审代理在私有桌面串行拍摄，所有15张上传图均原尺寸1440×1080、实际有损 WebP quality=90；路径、原 PNG SHA、上传 SHA 与字节数均在报告内。


## v6 隔离原生与 GPU 证据

[实际 GPU／原生报告](../review_artifacts/axel_landmarks_20261016/guardhouse/v6/gpu/report.json) 绑定源 SHA `6b811b8f9bdd41a32776af805e1185a24df28e781bc62b7c2994fad117c8fb70`，native SHA `19455d157e4347190e0fb93a13eb6b611c3623a66d65d3442d2d7036f8d9db35`。15张图涵盖近中远、后立面、门窗、檐口、主屋面、门廊、上下层、楼梯与剖视，玻璃乳白和屋面下皮错误已闭环。光学新增通道保留真实背景与介电反射，无玻璃自发光。

40个实际碰撞 mesh 和5门活动状态在原生场景对齐；主门与后门各9条通道射线无阻挡。此项仅证明碰撞网格、活动姿态与孔洞，**不代替真实胶囊进出／上楼**。后者已经通过下节正式 `move_editor_walk` 与当前3D HTTP检查，正式地图地形贴合仍待后续接入。

## v6 真实 HTTP 与胶囊通行

[三候选联合 HTTP 回执](../review_artifacts/axel_landmarks_20261016/pipeline/http_150551760.json)，SHA `c10aa48a506d0e93bda7a8889d2430113efd05b89088c15110ab1efd9432de7d`，**警卫处行为子集130/0**。本轮 `compiled_asset.reason=cache_capacity`，实际使用源GLB fallback，不能作为HTTP native接入通过；独立GPU native证据仍有效。其运行结论已由下节独立内容根、强制compiled.ok和实际PackedScene owner 的最终回执替代。整份旧回执还包含其他模型问题，不把子集成功称作整份通过。测试使用私有桌面、独立临时库与地图，未写正式库／用户地图。

通过范围：真实生产导入、当前3D HTTP发现与调用、双实例门状态隔离、共享UI门按钮、锁定／隐藏拒绝且文档历史无副作用、撤销重做、非等比缩放＋23°旋转、楼层hide/dim/整栋排除、隐藏只关闭picking并保留所有WALK碰撞、非物理玻璃无零层碰撞体、保存重开后语义与实际活动门位置一致。

标准高1.8m、半径.3m胶囊经 `move_editor_walk` 从门前平台连续进门、出门、再次进门，走到第一梯段、半层平台横移、第二梯段、二层走廊并站稳。中途无瞬移或跳跃、不改碰撞与台阶参数，源SHA保持一致；角色状态未改作者记录／撤销栈。各目标与实际脚点、分段轨迹记录在回执 walk_evidence 中。此为代表性路线，不宣称所有家具间隙、第三人称任意机位或正式地图地形已验。

### 最终隔离 native HTTP：替代此前 source fallback 结果

[最终回执](../review_artifacts/axel_landmarks_20261016/pipeline/http_139526127.json)，SHA `8525b064f7d5b7bcc1e57975cbb6c8b6da184ad9a766e388c71ad1a8f93dc1e4`：全批430/0，**警卫处138/0**。采用既有进程级 content_root_override 隔离源副本、native、临时库与地图，不提高8GiB限制，也未驱逐共享缓存。每件强制 `compiled.ok`，每次放置／楼层排除重开／最终重开实际场景都保留已验证 native PackedScene owner。

警卫处此轮 native 为85,589,046B，payload SHA `7689ba95bcd90b4d245a5c538ce17e5e2408060845ea360188ef1d72bebcaa54`，同一源SHA；较独立GPU原生构建的字节差异分开记录，不宣称二者字节相同。标准单位尺度胶囊再次完整进出主门和两跑上楼，二层站稳；编辑变换／楼层／门状态还保留非等比23°旋转检查。旧容量失败回执仅作问题历史，最终运行接入结论采用此份原生证据。正式库原路径回读现已完成，结果见末节。


## 最终正式素材库交付（根任务核验）

最终 `v6` 已通过正常 AssetLibrary 导入发布到共享默认库，目录分类“城镇地标建筑”。实际 asset_id 为 `D:/code/rmmo_runtime/packs/default/assets/6b811b8f9bdd41a32776af805e1185a24df28e781bc62b7c2994fad117c8fb70.glb`，GLB SHA `6b811b8f9bdd41a32776af805e1185a24df28e781bc62b7c2994fad117c8fb70`。该条目为完整导入建筑，不是参数化组件模板；`component_template_id` 不适用，门与楼层由源 `model_building v1` 合同保留。

[正式发布回执](../review_artifacts/axel_landmarks_20261016/publication/guardhouse_publish01.json) 记录源、正式目标、native/footprint、缩略图与原子目录保存；[正式目录使用回执](../review_artifacts/axel_landmarks_20261016/pipeline/http_57497240.json) 三栋合计126项通过、0失败。直接使用正式目录的原路径实例，无重导或临时源拷贝；实际选择、活动门碰撞、撤销重做、锁定拒绝及临时地图保存重开均通过，正式源与目录前后SHA不变。此前完整候选430项通过的几何/胶囊证据绑定相同源SHA。

正式库 native 实际为 **85,587,935 B**，payload SHA `8a69dfdb3e6b8132f6d15e6949eb55bce2248191189521897efbad64df7d5c43`。它与上文隔离图审/HTTP 构建采用同一最终源 SHA，但构建路径及序列化元数据不同，文件字节不宣称相同；正式使用身份以发布和126项回执为准。

资源、画质、运行管线、正式素材库使用四项均通过；正式地图部署与整图玩法/性能由布局任务另行验证，本任务未修改地图。最终身份与布局锚点见 `D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016/blender_building_handoff.json`，此节取代前文历史阶段的待发布状态。
