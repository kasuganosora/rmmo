# 第七十六批（2026-09-29）：按用户改序，先mocker表情同步，再补形态和验收

用户明确顺序为3→1→2。本批先完成mocker事件/快照链，再新增形态，最后检查组合视觉；旧模型和裙装继续暂停，Go服务及正式地图仍暂缓。

mocker新增facial_expression_module：本地请求绑定服务端当前角色ID，拒绝未知/非有限权重及死亡请求；记录独立状态、单调revision，待投递更新按角色合并。World3D通过服务端结果更新本地人物，在正常帧读取队列更新远端；不再由UI绕过mocker直接设置。3D远端接收器复用共享Model工厂，使用明确position_m/map_path，不把旧2D cell随意当米；支持提前收到表情、进入视野快照恢复、乱序拒绝、清空和离场。已有远端调试生成入口接3D快照。此处是单机mocker的模拟对端，**不是已接入真实多人传输或Go服务**。

79955及94894真实HUD回归退出0：本地请求、远端排队投递、表情先于生成、旧包拒绝、离场后快照恢复、清空/销毁、非法值/死亡拒绝和玩家/NPC隔离通过。服务端会话重置清表情但revision不倒退。

原生形态提取从22扩至32（保持原拓扑/源hash）。新增眼睑上提/下放、眼周收缩及眉内/外侧形态，组成eye_smile（笑い）、eye_surprise（びっくり）、eye_squeeze（ぎゅっ，扩展标签）、brow_smile（にこり）、brow_serious（真面目）。共24通道；原smile仍为明确的眼嘴组合，不与眉标签混用。新通道使用有界源权重，未重塑身体或更换骨架。

84391原生回归退出0，native_expressions_03增加三组height/nose_width、三表情的正侧面组合。已查看基线闭眼笑/惊讶正面及挤眼侧面，无明显眼球穿出或脸裂；闭眼笑仍受写实底模形态限制，不能当成参考图夸张二次元外观已完全达到。原灯光场景test_expression_studio 96885退出0，棚拍/游戏灯光×idle/walk/attack×正侧面共12张，目录expression_studio_01。已查看棚拍闭眼笑正面、游戏惊讶正面、攻击挤眼侧面及游戏微笑侧面；未见明显口腔撕裂或眼球穿出。**视觉残余：侧面闭眼/挤眼的睫毛轮廓偏厚，挤眼与闭眼笑的区分仍偏弱，二次元夸张表现尚未最终验收。** 本轮记录后不反复重塑新身体；仍需完整连续动作视觉与睫毛/表情辨识度专项。定向git diff --check通过。

# 第七十五批（2026-09-29）：原生口型联动、风格眼与分类组合

新女性身体增加源 VSMAA/IY/UW/EH/OW 五口型，外部 native_face_01.json 共22个源形态。通过原 Assembly-CSharp.dll 反射核实公式枚举13/14/15为RotationX/Y/Z，证据 native_expressions_01/formula_enum.json；使用源下颌/舌头角度而非仅动嘴唇顶点。动画复位后叠加表情骨骼，立即修改时扣除上一表情角度；元音总权重超过1时归一，避免下颌重复放大。

爱心、星星、圆圈眼及脸红接同一实例API，眼睛/面部Shader参数独立；保留源身体和眼球几何。已查看 native_expressions_02 的星眼、圆圈眼、脸红、张嘴正面及组合侧面；是现有真实脸型上的风格化效果，不代表已把脸改为参考图的二次元造型。

正常HUD面板按眼睛、眉毛、口型、瞳孔效果、肤色效果分组：跨类组合，同类替换，再点取消，恢复自然清空；快速点击以待完成目标组合，避免过渡中丢失前一次选择。共享Model另有按日文标签设置的 set_mmd_expressions，未知标签整笔拒绝。19通道属于当前明确支持集，不是完整MMD。尤其原smile是眼嘴组合，不应错误标成眉毛的「にこり」，现已标为扩展组合。

验证：test_native_expressions 58378及24418退出0，五元音下颌连续帧不累积/不被动画覆盖、归零恢复、材质效果不改顶点、身体身份保留、复用实例、结构替换取消过渡通过。test_world_facial_expressions 64661退出0：真实HUD快速组合、口型替换、再次点击取消、恢复、玩家/NPC材质和几何状态隔离通过。追加回归41434退出0，日文标签组合、未知标签拒绝且状态不变、清空均通过；中间一次新增方法缩进解析失败已修复。全仓git diff --check仍报告此前布料补丁的空白问题，本轮表情文件定向检查另行执行，未擅改暂停项。

仍待：闭眼笑/惊讶/挤眼等专门形态和全部目标标签、更多身份形态与动作组合的眼睑/口腔视觉、原灯光场景对照、远端mocker同步；未实现VMD/PMX文件导入。裙装继续暂停，旧模型不修，性能后置。

# 第七十四批（2026-09-29）：正常表情菜单、可中断过渡和实例隔离

复用已有表情面板，在聊天表情之前增加共享面部表情按钮和恢复自然；使用滚动区域，不删除原聊天表情。World3D提供基础目录和请求，调用Model.transition_expressions；默认0.18秒smoothstep，从当前权重开始，中途切换无跳变。set_expressions仍支持立即设置，供工具/NPC统一调用。当前面部表情为本地人物表现，尚未做mocker远端广播，不宣称多人同步完成。

原形态测试69648退出0，新增半程0.5权重、打断不跳变、归零恢复检查。test_world_facial_expressions 68307退出0：真实HUD菜单打开、闭眼按钮驱动玩家半程、恢复自然清空、女性NPC无显式body_model经工厂迁移新模、NPC微笑与玩家权重隔离、未知ID拒绝。截图native_expressions_01/world_panel.png已查看，复用游戏面板可滚动展示。身体和衣服实例不重建。

下一步口型与完整MMD语义/风格效果，不把现有10个候选标签称为完整。已读暂存PHMMouthOpen：公式targetType13、lowerJaw、multiplier6；原vam_DAZMorphBank.cs有RotationX/Y/Z处理，需核实枚举与旋转叠加再启用，不能只加顶点不动下颌。眼睑侧面/组合、腮红/爱心星星圆圈眼仍待。裙装继续暂停，性能后置，只做新底模。
# 第七十三批（2026-09-29）：默认新身体进图通过，基础表情进入共享Model

正常创建请求不指定body_model的world流程33861退出0，未再出现空mesh脚本错误；仍有既有布料初始化警告及1个ObjectDB退出警告。女性创建默认新模已通过61849，mocker列表/进图配方迁移与女性NPC工厂共用character_body_migration；男性没有新源身体，不冒充女性或继续修旧模型。旧角色迁移完整装备/备份幂等专项仍待。

使用已记录f_mb SHA256和现有UnityPy环境，tools/extract_native_expressions.py提取17个原面部形态到外部characters/expressions/female_base_v2/native_face_01.json；保留公式，含公式的张嘴条目暂不启用，不能忽略下颌联动。新增character_expressions统一10个基础语义/MMD候选标签（眨眼、左右单眼、笑、眉及嘴角）；不是完整MMD清单。Model.set_expressions→Body在身份形态之后、原分轴蒙皮之前叠加源delta，GPU/CPU使用同一rest输入；实例权重独立，清零从基线+身份重算，不重建身体/衣服。

test_native_expressions session77358退出0，检查实际几何变化、归零、形态保留、实例ID不变、未知语义拒绝；native_expressions_01生成neutral/blink/wink_left/smile。已查看neutral和blink正面，闭眼有可见效果。**尚未完成侧面/过渡/双实例、口型公式、完整MMD标签、腮红/爱心星星圆圈眼以及正常UI控制入口。** 不能把基础API与4张图称为MMD完成。下一步优先共享过渡与游戏表情入口、源口型/眉眼组合验收；裙装项按用户暂停，性能继续后置。
# 第七十二批（2026-09-29）：按用户改序，停止裙装项，默认接入新底模

用户明确停止当前裙装项，要求快速将新模接入游戏然后实施MMD表情；覆盖先性能后表情的旧顺序。9089已Ctrl-C中止exit1，02部分图不作为验收；碰撞候选代码保留但不继续调参。

创建页女性默认female_base_v2；移除test_source_hair_creation的手工指定，实际默认主/头像、发型选择/卸下/随机/配方回读测试61849退出0。新增character_body_migration：女性旧配方切至新模及有效原生发型，保留legacy_customization原配方备份、其余配色/形态等字段；已是新模则幂等。mocker创建/角色列表/进图共用迁移，避免列表和进图版本分裂；女性NPC工厂也复用（最后该编辑尚待运行验证）。不把女性身体冒充尚无新资源的男性，也不修旧模型。

world流程2564退出0但检出SCRIPT ERROR，不能视为干净通过：暂停项的新场景碰撞接入读到空mesh。已移除World3D自动调用，候选仅留工具API并补空mesh过滤，符合停止本项；正常流程需复跑。此次创建请求不再显式传body_model，已有正常登录进图/新身体断言通过；继续原句柄至结束。下一步校验迁移/正常装备边界后立即MMD表情，复用已盘点f_mb manifest及原形态提取工具，按character_expression_requirements.md统一标签与可见效果；不从头全盘反编译。
# 第七十一批（2026-09-29）：布料场景输入坐标回归与02对照启动

原session41396最终退出0，ground_dressed_01完整捕获。该通过仅覆盖身体最低点/动作状态，不覆盖衣服。已查看起身末帧：裙子仍挤在腰腿附近，未恢复原轮廓；结合中段/坐稳画面，01明确视觉失败，并在其report写garment_visual_accepted=false。原图保持不覆盖。

新增 test_cloth_scene_input，实际共享选择器和adapter._scene_points 验证：过滤远物件、人物视觉根下沉/转向时地面世界坐标不变、家具升高对应碰撞更新、已释放物件移除。headless运行退出0。此测试验证输入坐标/生命周期，不代表GPU接触效果通过。

session9089已启动 test_ground_action_preparation --outfit --scene-contact，输出独立 ground_dressed_02。工具增加明确的衣服验收字段，身体数值通过不自动标衣服通过。继续轮询9089，不重启已完成的41396。待02完成看正/侧/背及起身；若仍有翻折，保留残余并按用户限定轮数继续下一项，不无限围绕同裙调参。正式世界的场景集合重建效果仍需实测，性能/MMD后置，只修新底模。
# 第七十批（2026-09-29）：裙装坐地视觉失败，补场景碰撞输入

继续同一session41396，未因长时间无日志重启。ground_dressed_01 已生成进入中段及坐稳正/侧/背，已查看进入中段和hold_front：裙子卷到腿后/大腿上，围裙明显折起，超过轻微穿插，视觉不通过。完整起身捕获进程尚在运行，继续轮询原句柄。保留失败目录。

代码确认 character_runtime_cloth 原 reconcile 调用 adapter.initialize(garment) 未传任何场景物件，仅身体碰撞；故地面/椅子从未进入运行时布料，不能用调站姿或删身体掩盖。新增 set_scene_colliders：筛选身体周围实际网格，集合变化时按插件固定外部三角容量重建；同集合不重复重建，现有 adapter 每帧变换场景顶点至求解局部坐标。World3D 将stream中具有实际StaticBody的网格提供给新底模玩家及战斗NPC。没有新增布料求解器，也没有改变源衣服几何。

工具新增 --outfit --scene-contact，输出独立 ground_dressed_02 并断言平面6顶点进入碰撞包；原01保留。两个脚本check-only通过。**运行接入/新对照仍待验证，不宣称修复视觉。** 等41396完成后运行02并比较；需后续验证分块卸载、集合重建及家具接触，性能后置但记录重建成本。只针对female_base_v2，不回修旧模型。
# 第六十九批（2026-09-29）：新底模切图/退出与裙装坐姿检查

新增 test_ground_world_lifecycle，只使用 female_base_v2。session17383退出0：初次动作准备期间请求缺失地图，原地图保留且迟到准备不会坐下；随后缓存正常坐下；有效切图保留人物实例、清mocker坐下状态并完成起身；再次坐下后释放世界，服务坐下状态清除，根节点无隐藏准备对象。缺失地图负例产生预期JSON/文件打开错误，不是测试通过时掩盖正常地图错误。

扩展 test_ground_action_preparation --outfit：同一新底模穿原版分体女仆上衣/裙子，使用现有运行布料适配器；完整进入/退出关键帧及坐稳后正/侧/背截图输出 ground_dressed_01，保留原几何，不为通过而修改动作或裁剪身体。session41396已启动，最终结果与画面尚待检查，不能说服装坐姿通过。

其余体型中途更换/准备期间受击、完整接触、家具入口与旧视觉残余仍待。用户要求停止旧模型工作继续有效；性能和MMD仍后置。
# 第六十八批（2026-09-29）：只验收新底模，迁移战斗夹具

用户明确要求不再修旧模型。已在计划入口记录硬约束：本期只围绕 female_base_v2 的人物实现和验收，旧模型通过不作为新人物完成依据。test_world3d_combat 移除默认男性旧夹具，显式设置新女性底模、原生发型202、身高形态；两个地图的敌方NPC也使用同一新底模配方，并断言双方均为axis_rig。

致命伤测试改为 await world.request_sit(true)，确认新底模实际进入sit_down_ground及mocker sitting，再施加真实致命伤。session57403已检出玩家/NPC新骨架、坐姿死亡保留death并清坐下状态、复活/掉落等断言通过；最终跨层导航检查通过，进程退出0。另补 World3D 离树时清服务坐下状态，避免退出后残留休息收益；该行在进程启动后加入，尚待专门退出回归。

本批没有修改旧模型或其资源。死亡仅状态/动作身份通过，尚不宣称新身体完整死亡视觉、裙装坐姿或其他未完计划已经验收。继续新身体的切图/离树/准备取消及服装动作检查。
# 第六十七批（2026-09-29）：快捷键、重复请求和受击中断

正常world回归新增调用HUD实际 _unhandled_input，按 GameSettings 配置的sit键进入正式请求；不再仅验证方法存在。重复显式 request_sit(true) 在准备中合并，不使先前结果过期；再次切换/false仍取消。检出三维反击及状态伤害直调combat_engine会绕过旧combat_module的坐下中断，在 WorldCombat._apply 统一识别玩家damage，取消异步准备并复用 server._stand_if_sitting。

session18740：test_world3d_flow --axis-body退出0，真实混合体型玩家准备/取消、重复合并、HUD键、坐稳/移动、实际非致命扣血起身及换装/事件回归通过。session1864：test_world3d_combat退出0，新增坐下服务状态下致命扣血检查：状态清除、动作保持death而非被起身覆盖；原复活/掉落/楼层/导航测试通过。后者使用原战斗夹具身体，不能替代新身体死亡视觉。world原有GPUCloth初始化提示和1个ObjectDB退出警告未解决。

下一步：切图/退出时坐下状态、准备期间体型更换/受击取消与实际服装坐姿检查。已有离树/切图防迟到保护，但切图分支尚未针对性运行。动作首载成本、普通家具绑定、躺姿完整接触、其余视觉残余/迁移/性能/MMD继续保留。
# 第六十六批（2026-09-29）：正常三维坐下请求与 mocker 状态

核对实际HUD绑定对象是 World3D（不是内部 WorldCombat），因此在 World3D 增加 request_sit；沿既有HUD快捷键路由，隐藏准备当前体型动作后安装，并通过 mocker.try_sit 返回的 sit action 进入动作。未实现第二套客户端 sitting 标志。准备期间服务状态仍false，取消请求通过revision拒绝迟到结果；攻击/技能请求也使准备结果失效。首次准备仍有等待成本，缓存和性能后续处理。

WorldPlayer 发出移动意图，World3D 先调用 mocker.try_sit(false)，sit action 从当前进入相位反向起身；避免旧实现仅动画起身却保留服务端坐下状态。真实 test_world3d_flow --axis-body 已改为调用正式世界接口，不再测试自行准备/安装动作。session6707退出0：准备不提前改变服务状态、准备中取消、缓存后正常坐下、半途移动清状态并匹配反向时间、坐稳不被idle覆盖、再次起身及原装备/事件回归通过。既有布料初始化警告与1个ObjectDB退出泄漏仍在。

补了离树、死亡和切图取消准备/清坐下状态保护；该小补丁晚于上述进程启动，**尚需下一轮运行覆盖，不能算已回归**。HUD快捷键本身、受击/死亡/切图、重复请求与体型中途变化仍需针对性验收。裙装坐姿视觉、全掌接触、家具入口、默认人物迁移、性能和MMD仍未完成。下一步优先这些状态链验证，不重复调毫米级静态接触。
# 第六十五批（2026-09-29）：坐地动作最终姿态录制与真实世界中断回归

新增共享 character_axis_pose_capture，从原生 IK 完成后的骨骼快照录制旋转、分轴角参考及视觉根位移；关闭 IK 重放两动作全部采样表面，最大差约1.09微米，证据 ground_transition_04。源动作和接触辅助移入 scripts/char，旧工具入口复用同一实现。

character_ground_action_preparer 在隐藏身体按完整体型准备进入/退出动作，缓存普通 AnimationLibrary；AxisRig.prepare_ground_actions 返回结果。可见身体不接收试算更新，同体型复用缓存。初次接入检出与自然 idle 端点不一致，进入混合最大防穿地抬高19.6毫米；保留 before_standing_alignment.json，末段对齐共享 idle 后基线降至2.88毫米。三身高60Hz Model完整播放通过，最大地面补偿分别2.80/2.88/5.29毫米，其中矮体型最大值在 idle；不是全程零接触误差。证据 ground_action_preparation_01，未验收衣服、全掌接触和所有体型组合。

WorldPlayer 将坐地三动作纳入休息仲裁，移动打断坐下时从对应反向时间起身，保留原移动目标。真实 test_world3d_flow --axis-body 退出0：混合体型玩家准备动作、进入不被idle覆盖、半途移动反向恢复、坐稳保持及再次起身通过；原登录/装备/事件回归亦通过。现有 GPUCloth 零初始锚点警告和1个退出 ObjectDB 泄漏仍在，未在本批解决。

新增动作准备主人释放回归：在原生modifier等待期间释放owner，返回null并清理busy、临时workspace，取消结果不进入缓存；基线完整播放一并复跑退出0（session59510）。这只证明准备器生命周期，不代表正式快捷键取消链已经接通。

**尚未完成普通入口：测试主动安装动作库，HUD→WorldCombat→mocker try_sit 尚未接通，不能宣称坐地正式交付。** 下一步完成异步准备取消、原子安装与服务坐下状态联动，再验证移动/死亡/攻击/重复请求。座椅家具绑定、其他视觉残余、统一入口迁移、性能及 MMD 仍按原计划继续。
# 第六十四批（2026-09-29）：坐地进出分段候选与连续接触修正

新增 ground_transition_candidate.gd：保留适配坐姿，以1秒分段收腿/转移上身衔接 UAL2 LayToIdle 的0.5秒之后片段，避开躺姿起点；总约2.033秒。坐下候选反向保留完整关键帧。通过现有 Model 变体和分轴动画播放，尚未添加普通玩法动作。

第一版只插值关节旋转失败：收腿路径穿地，原地面保护把全身最大抬高约0.290米。ground_transition_01 保留失败画面/轨迹。新增 ground_transition_support.gd 工具候选：早段臀部支撑，足端沿离地弧线从源坐姿过渡到落脚目标，再接原起身路径；复用原生双腿/双臂IK，早段保持双手支撑并逐步释放，不拉长骨骼。02连续正反向画面已复查收腿/起身中段，整人被脚轨迹顶起的明显问题消除。

03新增真正最终帧的modifier完成/错误检查与末端目标误差测量；完整基线正反向各62帧，进程退出0。最大局部穿地约6.44毫米，最大末端位置误差约4.26毫米，均为残余而不是零误差；最大骨盆帧位移约43.29毫米出现在原起身段。报告 raw_animation_floor_lift_m 是接触修正之前的原保护量，不能误当最终又被抬高29厘米。各阶段关键图与完整采样在 ground_transition_03，01失败证据保留。

本轮不再追逐毫米级归零；按用户允许轻微穿插的方向保留残余，继续实际接入。**目前仍是工具候选，尚未验证三身高/衣服/普通状态链，不能说坐地功能完成。** 下一步将最终受约束姿态准备为可重放动作（避免玩法每帧重复试算），补体型与入口/取消回归，再接 HUD→WorldCombat→mocker try_sit。连续脚掌全接触、自碰撞、裙装接触未完成，缓存性能、其他历史残余和MMD计划维持。
# 第六十三批（2026-09-29）：坐地姿态隐藏准备、体型缓存与共享播放

将静态支撑试算移至共享 character_ground_support_fit.gd，旧工具入口仅继承它。新增 character_ground_pose_preparer：在隐藏的原生 Body 工作对象上准备体型、执行有限接触求解，等待原生IK最终快照，再生成普通 Animation（含全部旋转、分轴角参考、视觉根位移）。不把中间试算写给可见身体/发型/布料，不在每帧扫描角度。每个 AxisRig 持有自己的准备器，通过 prepare_ground_pose() 返回按当前形态准备的静态 clip；形态在异步期间改变或原主人释放时拒绝结果。临时工作对象始终清理，按完整规范化形态字典缓存最近一次结果。

build_axis_ground_pose --publish-source 生成外部 female_base_v2_ground_source.res，作为准备输入，不是直接播放的最终动作；来源和署名仍在 vam_sitting_reference/ATTRIBUTION.txt、PROVENANCE.json、meta.json。常规角色动作库尚不自动安装该静态片段，坐下快捷键仍未开放。

test_ground_pose_preparation.gd 经实际 AxisRig.prepare_ground_pose API 验证三身高：可见身体实例和点集不变、试算 surface_updated 次数0；同形态重复请求不增加 build_count，不同形态恰各准备一次。生成 clip 被测试临时装入现有 AxisRig 动画库并用 Model.play/pose_at 播放，三体型最低点均0且无姿态同步错误；最后删除测试片段。角色提前queue_free的独立负例返回null/owner released，busy清除且根下无临时准备对象。完整进程退出0。证据 ground_pose_preparation_01/，基线侧图已看；此前三身高接触证据继续来自 axis_ground_pose_04。

**仅准备能力和静态共享播放验收，不是正式坐地流程完成。** 下一步自然过渡：UAL2 LayToIdle 后半段有撑地收腿的可复用姿态，可评估截取合适段落与已准备坐姿衔接；不能直接从躺姿起点播放，也不能用短时间全身混合掩盖收腿/重心切换。仍需普通HUD→WorldCombat→mocker try_sit→玩家和取消链、掌面/衣服/连续接触。缓存准备开销与多人性能未验收，性能阶段未提前宣告完成。总体目标及历史残余保留。
# 第六十二批（2026-09-29）：坐地导入核对与共同支撑候选

新增 inspect_axis_ground_contact.gd，以原 VAP 的 rootPosition/rootRotation 和逐骨 position/rotation 重建源 FK，对比当前体模保留骨长的 FK：27骨最大位置偏差约0.483毫米。原最低点为7871，归于 hip/pelvis 强权重区域，未抬高 y=-.0620123；因此不能归咎为导入旋转把脚翻错。整体防穿地抬高后臀部落地，但手和脚失去支撑。诊断 JSON 保留在 axis_ground_pose_01/contact_diagnostic.json，原失败图不覆盖。

新增工具候选 ground_support_candidate.gd：保持源双腿交叠关系，按臀区与较低脚部的表面高度差求有限骨盆转动；双臂复用 native TwoBoneIK3D。先在有界躯干后倾范围内寻找可达手部支撑，再把目标限制在真实臂长内，未拉骨长或改源网格。这是接地姿态适配，不是通过抬手避开衣服碰撞。02仅双手候选仍悬脚，失败图保留；03补共同支撑，04为三身高断言验收。

三身高 test_axis_ground_pose --support --height=-1/0/1 全部退出0：臀部最低点距地0.015/0.014/0.026毫米，较低脚部0，双手最低采样误差小于0.001毫米。腿部整体调整约3.04/3.39/3.83度，躯干后倾14/16/18度；未扩展超过20度的候选边界。测试断言臀/脚/手采样偏差<3毫米、完整身体最低点不低于-1毫米。已看03侧面和04矮端正面；全部三身高正侧背图及报告在 axis_ground_pose_04/。

**仍是工具候选，未提升正式资源/动作。** 最低点接地不代表完整掌面或所有接触成立；静态求解不能直接每帧套用（角度扫描/二分需离线缓存或按体型准备）。下一步把经过验证的静态姿态准备接入共享 Model，并解决自然进入/退出和 mocker 坐下指令链。不能把 get_up 的躺姿起点直接当坐地起身，也不能把0.16秒全身混合当自然坐下。衣服接触、连续/体型组合、普通家具入口与其余历史残余均待，总目标仍未完成。
# 第六十一批（2026-09-29）：坐地源姿态与导入证据

核对两个现有 UAL 源 GLB 的动画清单：UAL1 仅 Sitting_Enter/Exit/Idle/Talking，UAL2 仅 LayToIdle，没有坐地动作。禁止降低椅子动作冒充坐地。VaM AddonPackages 中发现 AshAuryn.AshAuryn''s_Anime_and_Sitting_Poses_(Legacy).3.var；源 meta 声明 CC BY。提取坐姿参考到外部 characters/source_models/vam_sitting_reference，保留 meta、ATTRIBUTION.txt 和 PROVENANCE.json（包/所选姿态 SHA256）。本地参考选 AA_sitting003，坐地伸腿交叠、双手在身后支撑。未导入其控制/物理脚本或外观形态。

已从既有反编译 vam_DAZBone.cs 核实：普通骨 rotation 是 transform.localEulerAngles，根骨 rootRotation 是世界欧拉；不能当 DAZ 分轴角。新增 build_axis_ground_pose.gd 按 Unity Y*X*Z 转四元数，再为共享分轴蒙皮生成连续角参考，保留当前体模骨长。输出27骨记录候选库到 review_artifacts/character_3d/axis_ground_pose_01/candidate.res，未提升正式资源。

test_axis_ground_pose.gd 实际加载候选并捕获正侧背三图，进程退出0；已对照源003缩略图并检查正侧图，姿态轮廓基本一致。**接触未通过**：report.json support_lift_m=0.0620123，说明源位置在当前身体上造成最低点低于地面约6.2厘米，现有只抬高的地面保护使最低点归零，不能据此宣布臀部/手掌正确支撑。visual_accepted=false。不改源骨角/网格来遮盖；下一步定位位置适配与最低点所属区域，再检查臀/手/腿共同接触和自然进入/起身。

同时核对正常入口：HUD 已调用 request_sit，但 WorldCombat 尚无该接口，world apply_actions 尚无 sit 分支；mocker try_sit/_stand_if_sitting 已存在。后续应复用该权威坐下/移动起身/受伤取消链，不另造客户端 sitting 状态。候选坐地及退出没验好之前不把接口伪装成已完成。坐椅家具入口及其他计划继续保留，总目标未完成。
# 第六十批（2026-09-29）：坐椅进入/退出连续支撑

character_axis_seat 扩展到 sit_chair 与 stand_up_chair。进入前段只阻止已有座面穿插，不把站立身体向下拉到椅子；进入后段平滑允许落座补偿。起身时仅保留防穿座面的正向补偿，身体自然离开后补偿归零；足底高度修正在退出后段释放。仍使用原生双腿 IK、源动作和固定座面，不改骨长/源身体，不移动椅子。

新增 test_axis_seat_transition.gd，真实 Model._process 以30Hz连续运行进入→保持→退出→idle，三身高分别留轨迹和关键画面在 axis_seat_transition_02/height_-1.0、height_0.0、height_1.0。动作边界骨盆帧位移最大分别约9.09/9.84/8.39毫米，小于测试2厘米阈值；脚底最低采样全程穿地小于0.001毫米。基线最大骨盆帧位移43.34毫米出现在起身中段，此时座面补偿已归零，不能把这个数误报为切换跳变。基线起身首帧约0.112毫米。所有三次进程退出0；坐稳三身高及退出/idle取消回归也重新通过。

已看基线起身首帧/中段、高端起身中段、矮端进入后段图。证据证明该固定水平白模椅、赤足、原动作的连续支撑比只修坐稳完整；不等于所有家具或碰撞通过。脚底指标是最低采样点，尚未验足掌全平面和水平防滑；鞋底、不同朝向/坡地、椅背与裙装接触仍待。正常家具绑定入口尚未接。下一项推进坐地动作与普通交互链路，旧服装/武器/躺姿残余与后续性能/MMD仍保留，总目标未完成。
# 第五十九批（2026-09-29）：固定座面与足底联合约束接入

复用 Godot TwoBoneIK3D，把既有双臂桥接推广为配置两条骨链，新增 character_axis_seat。绑定固定模型局部座面及水平地板高度；坐稳时由当前身体臀/大腿区域估计座面补偿，同时用原生双腿 IK 保留脚底最低采样点落地，不拉骨长、不改身体源网格、不让椅子追随动作。AxisRig.finish_frame 已接入，并在最终腿 IK 完成后提交布料姿态。未绑定座椅默认不启用；离开坐稳动作或找不到座面接触候选会关闭旧 IK。

实际 test_axis_seat_support.gd 通过，证据 axis_seat_support_02/report.json 与三身高画面：身高权重 -1/0/1 的座面区域残差分别 -0.122/-1.649/-1.871 毫米，原基线约 -49.336 毫米。脚底最低采样点误差小于 0.001 毫米；每体型连续五个 Model 帧及起身取消/清绑定通过。新增断言座面残差小于3毫米、足底采样小于1毫米。已看基线候选及新版高矮端点图。双臂 test_axis_ik_lifecycle 回归通过，腕位置误差约0.164微米、朝向误差0。

范围限制：只验证固定水平座面、赤足、坐稳阶段；最低点落地不是整个脚掌均贴地。座面探针为臀/大腿几何区域，不是完整碰撞器。进入/退出尚未平滑衔接高度补偿，不能视为自然起坐通过。正常家具绑定入口、坐地、不同朝向/坡地/鞋底、椅背和服装接触仍待；当前测试只在每个体型开始时定位一次白模椅，保持时固定不动。下一步优先补进入/退出的连续支撑，避免高度跳变，再继续坐地和正式交互。总目标及历史视觉残余不变。
# 第五十八批（2026-09-29）：坐椅退出、休息状态与真实椅面缺陷

复用 UAL1 Sitting_Idle_Loop / Sitting_Exit，`--axis-chair` 输出独立 `female_base_v2_chair.res`（保持1.667秒循环，起身1.033秒）；AxisRig载入，共用Model增加sit_chair_hold/stand_up_chair。完成规则坐椅→保持、坐椅起身→idle、躺下→lie、地面起身→idle已接实际_process，不需外部每帧重发状态。

发现三维WorldPlayer._step原来每帧无条件play idle/walk，会覆盖所有坐躺。新增request_rest能力接口与休息状态保护，清导航意图后进入；休息中有移动请求先播放对应起身，起身结束后才恢复移动。拒绝输入锁定、死亡和不支持的片段。**当前是玩家控制接口，未把躺下按钮/家具交互/坐地快捷键全部接好**；普通战斗动作的保持也不在本批范围，不要扩写成所有动作仲裁已完成。

`test_world3d_flow.gd -- --axis-body` 退出0：真实玩家接受躺下、locomotion不覆盖、完成进入lie、点击移动触发get_up、结束idle，原装备/事件检查通过。既有ObjectDB退出1实例和插件警告保留。

`test_axis_chair_exit.gd` 验证坐椅保持和退出自动切换，白模椅固定座面高.46米。01为初始水平位置不匹配画面，02按初始坐姿骨盆仅校准一次椅子水平位置，此后站起过程中椅子不跟随、不改变高度。已看02坐姿和起身中段图。**座面接触未通过**：臀部几何区域探针最低y=.410664，较座面低.049336米（约4.9厘米）；骨盆y=.637369。报告 `axis_chair_exit_02/seat_probe.json` 是区域探针，不是完整碰撞认证，但足以阻止宣称坐椅正确。

下一步需要真实座面锚定与脚底共同约束，不能仅整体抬高身体让脚悬空，也不能让椅子每帧追人物。坐地动作及正常交互入口仍未完成，头手/裙子/武器旧残余仍保留，整体目标未完成。

# 第五十七批（2026-09-29）：源起身/反向躺下与共享放松躺姿

复用 UAL2 LayToIdle，`retarget_universal_animations.gd --axis-recovery` 输出独立 `female_base_v2_recovery.res`：get_up约1.533秒、52映射骨带分轴参考；lie_down反转同一关键帧时间，lie取源起点静止片段。AxisRig载入独立库，Model增加三动作ID，不覆盖基础/战斗资源。反向起身是躺下候选，不宣称已经符合真实人类躺下动力学。

实际 `axis_recovery_01/lie_00.png` 显示原起点双手抬在身前，是准备起身姿态，不是自然休息。动画层复用此前 Body.POSES.lie_relaxed（含头颈、仰掌、放松手指），静卧使用该端点，起身前/躺下末.25秒与源动画过渡；同时按最终身体最低点计算躺姿支撑高度，不把身体节点的测试场景position复制到正式角色，所有消费者仍读同一骨架/身体表面。没有隐藏手、身体或衣服以过检查。

`test_axis_recovery.gd` 两次实际 GPU 运行退出0，最新 `axis_recovery_02/` 保留起身/躺下各五相位及静卧图，已看静卧和起身中段。正反向表面最大误差3.653e-7米，采样最低地面高度0。三种身高静卧头部距地约[5.84,2.14,4.54]毫米，手部约19–25.27毫米，报告按头/手原权重顶点测量。**这些是近地检查，不是手背已经接触地面；1.9–2.5厘米手部余隙仍需完善。** 没有对整段连续接触、床/椅子、裙装或持武器躺姿做验收。

当前只是共用 Model 动作能力，世界交互菜单/自动结束转静卧或站立尚未接全，旧身体也未提供对应片段；sit_ground仍缺，sit_chair有进入但退出未补。下一步补坐地/坐椅退出和正常动作流程，继续真实头手支撑与过渡验证；不能把本批当成全部坐躺需求完成。

# 第五十六批（2026-09-29）：真实世界/预览持棒及连续动作缺陷留档

扩展 `test_world3d_flow.gd -- --axis-body`：实际mocker背包装备great_club→world玩家→等待真实渲染→双掌握点→实际卸下立即取消modifier，退出0；已有衣服/事件回归保留，仍有既有1个ObjectDB退出告警。扩展 `test_equipment_preview_identity.gd`：真实HUD装备木棒、复用原身体实例、IK握点、卸下/窗口释放通过，退出0；已看 `equipment_preview_01/actual_club_preview.png`。该图上衣内衣已由之前的独立卸装测试移除，不是身体被隐藏。

新增 `test_axis_twohand_continuous.gd`，固定1/30秒运行真实Model更新及过渡，idle→walk→完整attack→idle共87帧，后续卸装4帧；双掌最大误差3.9453e-7米，但握点最大单帧移动.290926米，不能称自然动作通过。`axis_twohand_continuous_01/02` 保留源A运行图/轨迹，02补requested_origin/reach_correction诊断：最大突变处可达域修正为0，跳动已存在于胸部驱动的原始目标，不是约束突然推开。

为核对动作来源，现有重定向工具额外生成 `attack_club_body`（源Sword_Heavy_Combo，4.333秒，52骨并带角度参考）。对照176连续帧最大握点步长仍.269947米，记录 `axis_twohand_continuous_03/`；没有接受该片段替换，正式选择已恢复A，额外片段只供诊断。辅助测试 `--heavy-carrier` 可复现该对照，默认下一轮输出04。报告显式 continuous_visual_accepted=false，控制台将握点数值通过与自然度待验分开，不再笼统写连续动画PASS。

本轮剩余：木棒整体挥击起手过快/躯干目标跳动、握指与腕肘自然度、完整服装接触；旧裙子明显翻折同样未解决。依用户“一轮后还有问题先记录推进下一项”，不继续循环调此动作/裙子；下一项推进新身体坐地/躺下/起身等缺失动作（躺姿头手参考真实人类要求保留），这些残余并未从总验收中删除。

# 第五十五批（2026-09-29）：共用角色双握点与最终 IK 后布料

`character_axis_twohand.gd` 已接 AxisRig；实际 Model._process 在源动画与混合后生成双掌目标，原生 TwoBoneIK3D 解算。great_club 的 idle/walk/dash 使用随躯干的握姿，attack 有独立武器起手/挥击/收势轨迹，源剑 A 仅承载身体动作；不再为木棒轮播带跳转的剑 C。**剑 A 身体仍含抬腿等风格，整套重武器自然度还未验收**，不能写成已完成真实重击动作。其它动作取消双臂覆盖，保留其原动作。

最初 tall/attack/.5 的副手到握点差.0681159米，已复现记录。修复将整根武器和两个握点一起投影到双臂可达区域，保留.13米握距与骨长，不拉伸胳膊、不分别挪握点。副手握指复用源主手握指按静止骨轴映射；按当前身体骨长和胸部朝向适配。换走木棒取消 modifier 并恢复求解前姿态，随后执行现有主手卸装恢复。

布料从原 Model 直接调用改由 AxisRig.finish_frame 编排：无双手 IK 时仍按旧流程；有 IK 时在 pose_solved 的 revision 完成后提交且每 revision 仅一次，避免重复骨架通知推进多次。取消、形态变更和清理沿原共用生命周期。

`test_axis_twohand_runtime.gd` 三轮：修复不可达后，三身高×idle/walk/attack×五相位共45采样，最终一次退出0、双掌最大误差3.1994151e-7米、取消后渲染不恢复旧握姿。`axis_twohand_04/` 最新图片/报告已查看挥击中段。注意测试清除过渡后采样片段，并非完整连续动画视觉验收，仍需真实运行的连续转换与更多体型。`test_axis_shield.gd` 本批初始接入后回归退出0。

`test_runtime_cloth_lifecycle.gd -- --twohand` 运行退出0，65帧预热、同装备复用、改形态重建/卸装清理保留；实际Model一次walk混合+双手IK后的插件目标包与最终身体逐点误差0，revision检查通过，证据 `runtime_cloth_ik_01/`。**已看 final_ik.png，裙子有明显前方翻折和侧部掀起，视觉没有通过。** 数据顺序正确不等于布料结果正确，不重启已收口裙子的参数迭代；保留现有缺陷供后续处理，不能将图称为换装完成。

下一步补正式世界/预览的木棒连续过渡与生命周期覆盖，检查挥击整体自然度、握指/腕肘接触；对残余视觉按用户要求记录后推进坐地/躺下/起身等剩余计划。Go与正式地图继续暂缓，整目标未完成。

# 第五十四批（2026-09-29）：原生双臂 IK 最终帧桥接与持棒候选

新增 `character_axis_ik.gd`，使用引擎 TwoBoneIK3D 两组设置，独立 target/pole，调用方在动画/混合后提交两只手腕目标、肘向及分轴角度参考。modifier 完成阶段设定目标掌向并 sync_final_pose，发出带 revision 的 pose_solved；cancel 停用修改器。没有自写二骨求解器，没有等待固定帧数后再给玩家补上一帧姿态。

`test_axis_ik_lifecycle.gd` 实际 GPU 检查六次两腕移动/转向，每次在 frame_post_draw 验证 completed_revision、最终身体手腕位置和朝向：最大位置误差1.6408201e-7米、朝向误差0；cancel 后原动画身体不再被改动。报告 `axis_twohand_02/lifecycle.json`。这里只证明双臂最终帧数据同步，没有连接布料提交，更不能声称完整装备生命周期完成。

新增 `capture_axis_twohand.gd` 候选：主手继续使用源15指骨握姿，副手按源/目标静止骨轴反射转换握指，目标点由胸部和前臂长度定位；棒柄两握点相隔.13米（装备尺寸），用各手自身 wrist→palm 变换反求腕目标，避免将手腕原点错误当成掌心。原生 IK 负责双臂到达与肘向，主手掌骨挂点继续驱动棒体。候选不是固定世界坐标贴手，也没有移动源身体顶点去匹配棒子。

`axis_twohand_03/` 正侧图及报告：两掌中心误差约1.94e-7/4.77e-8米，已观察，两手位于棒柄而非一只悬空；静态站立较第五十三批单手失败图改善。**未启用到正式 AxisRig**：当前是站立候选，仍须检查握柄指面接触/腕肘自然度、不同身高/体型、行走和攻击轨迹、换装取消，以及布料在最终IK后的提交顺序。不要直接将静止固定胸前握姿用于所有攻击，或用位置误差替代视觉验收。

下一步将候选提为受控运行组件，补动作与生命周期测试后再启用；其余人物计划继续，目标未完成。

# 第五十三批（2026-09-29）：大木棒几何与内置 IK 路线验证

实际 great_club 不再复用剑身/护手：独立.9米木质渐粗圆柱白模，换回木剑恢复剑几何；仍沿现有手骨挂点，**双手握持尚未完成**。`test_axis_shield.gd` 再跑退出0，新增实际大木棒换装几何/换回木剑断言，保留 `axis_shield_01/club_singlehand_unaccepted.png`，已观察并明确单手失败状态，不将此图视为完成。

新增 `inspect_source_twohand.gd` 实际采样源 GLB。UAL2 Sword_Heavy_Combo 六帧两手距离约[.672,.591,.543,1.364,1.045,.679]米，显然不能直接当双手握柄；TreeChopping_Loop约.94–1.18米，Walk_Carry_Loop约.43–.45米。UAL1 Sword_Idle约1.03–1.05米、Sword_Attack约1.03–1.42米。两库已检查实际片段名单，不凭 Heavy/Sword/Chopping 名称承诺双手动作。双手需要真实握点适配与自然肘向，不能用片名切换替代。

本机引擎 ClassDB 验证 TwoBoneIK3D、CCDIK3D、FABRIK3D 可用（辅助 `inspect_native_ik.gd`），优先原生 TwoBoneIK3D，不新增另一套手写二骨求解器。`test_axis_native_ik.gd` 实际 GPU 原型：在新身体 Skeleton 上添加 modifier，配置 lShldr/lForeArm/lHand、target/pole；抓取 modification_processed 中求解旋转，在骨架更新后恢复到骨架并调用 sync_final_pose，三可达目标最大手腕误差2.642594e-7米，报告 `axis_twohand_01/native_ik_probe.json`。

第一轮立即调用 advance(0) 后读结果，断言失败（未收到 modifier 信号）；第二轮等待骨架更新后通过。说明 advance 不保证同步完成。**接生产运行时不能照搬测试中等待两帧**：需在引擎修改回调时序内取最终姿态，避免普通动画、布料和挂点先消费上一帧 IK。当前只有单臂位置桥接证据，尚无双臂/掌心朝向/握柄自然度/连续过渡验收，原型没有自动启用到玩家。

下一步用原生 IK 建立大木棒双握点与自然肘向、验证最终姿态处理顺序，再补其它动作；整目标不缩小，性能/MMD/默认迁移仍在计划中。

# 第五十二批（2026-09-29）：副手木盾接入及双手互斥

共用 equipment_parts 保留副手物品身份 WeaponOffItem，AxisRig 安装 `character_axis_shield.gd`。木盾白模为直径.44米、厚.035米圆板及两条前臂绑带，挂点使用最终 rForeArm/rHand 和指根横向构造正交坐标，随前臂长度适配位置/绑带代理半径；源动画、身体网格和手臂姿势未改变。当前采用绑带盾，无握柄强制握拳，不声称所有盾牌都是这个持法。渲染物件及材质每角色独立。

`test_axis_shield.gd` 两次实际 GPU 运行退出0。通过真实 mocker 背包物品→装备快照→共用 View：剑盾共存、三身高三动作108最终混合采样、正交/前臂挂点、身体实例复用；实际卸下副手不改变身体姿态；装备 great_club 后服务端移除副手、渲染清除木盾，继续装备盾被拒绝。第二次补 NPC 工厂独立盾/材质及 NPC 卸装不影响玩家。注意此处只验证 great_club 的服务端互斥，仍未解决它的模型/双手握持。

证据 `axis_shield_01/`：idle正/侧/背、attack关键帧及报告。已看正/侧和攻击帧，盾板位于副手外侧，正面可见两条绑带；未把该单帧当作全攻击轨迹、举盾格挡或服装接触通过。前臂半径目前是骨长代理，完整皮肤表面贴合、袖口与盾牌碰撞仍未验收，后续需要实际组合证据。

下一步 great_club 的几何与双手握持/动作，随后按既定计划补坐地/躺下/起身等。整个人物目标仍未完成，性能/MMD顺序保持。

# 第五十一批（2026-09-29）：正式木剑装备身份链

核对实际 `data/combat/items.json`：当前主副手条目是 wooden_sword、双手 great_club、wood_shield。原 equipment_parts 将所有主手统一压成 WeaponMain=1，仅留下 sword/heavy，物品身份丢失。现增加 WeaponMainItem，经共用快照转换传到 AxisRig.weapon；木剑使用独立实例材质的木色和粗糙度.85，不再显示金属剑身。仍为白模几何，没有声称完成正式武器美术。

`test_world3d_flow.gd -- --axis-body` 增加真实背包木剑装备→世界 apply_actions→玩家模型身份/材质→持剑攻击→卸装清除身份断言，运行退出0，其余衣服/事件回归通过。已有 ObjectDB退出1个实例、插件zero anchored警告保留。`test_axis_weapon.gd` 使用木剑再跑三身高108混合采样、连段重复/转向与卸下恢复，退出0，最新 `axis_weapon_03/`；已看实际握柄特写，木质显示正确。测试直接模拟的WeaponMain配方仅验证渲染，正式入口由world测试另证。

仍未完成：great_club 当前仍落入原白模剑几何和单手动作，wood_shield 尚无新身体显示；下一步优先补这两个实际物品，不能以剑通过代替全部武器，也不能仅将重击命名为双手握持就算完成。其余坐地/躺下/起身、默认迁移、性能、MMD任务继续保留。

# 第五十批（2026-09-29）：新身体单手剑挂点与状态重复回归

复用现有 UAL2 重定向工具，`retarget_universal_animations.gd --axis-combat` 输出独立 `female_base_v2_combat.res`，保留基础动作库；剑击 A/B/C 时长约1.40/1.57/2.00秒，每段52个映射骨骼并带分轴角度参考。握拳使用源攻击片段的15个手指旋转及角度参考，不凭截图逐指硬调。UAL 的右手实际映射到新身体 lHand，按真实映射挂主手武器。

`character_axis_weapon.gd` 以最终解算的腕骨、四指根/第二关节构造正交挂点，随身高、动作和混合后的手掌更新；当前使用三块白模剑验证。卸下恢复当前动画原手指姿态，不重建身体。共用 AxisRig 加载并选择三段攻击、在最终混合后保持握柄。当前没有适配武器种类尺寸、双手/副手和重击专用姿势，不能把所有 WeaponMain 显示白模剑视为装备系统全部完成。

实际发现并复现：相同 attack 状态重复调用 play 会在早退判断之前消耗连段，转向也会推进。新增断言先失败（`Repeated attack state restarts or advances the combo`），修复为重复状态先返回、同动作转向保留当前片段，明确 restart 才推进下一段。未修改服务器伤害时机。

`test_axis_weapon.gd` 实际 GPU 回归通过：A/B/C 选择、重复/转向不推进、15指骨握持、三身高×三动作×12混合帧共108采样、身体实例复用、正交挂点、卸下恢复控制点误差0；挂点距腕骨最大0.08909米。证据 `axis_weapon_02/report.json` 及 idle/idle_grip/三攻击关键帧；01保留初始画面，B片段初始取景裁掉剑尖，02扩大攻击取景。已查看01握柄特写和全部关键姿态；这些单帧不等于完整攻击轨迹/服装接触验收。白模护手较宽、静止腕姿及其它武器样式仍需后续视觉验收，不调身体来避开衣服。

本批再跑 `test_world3d_flow.gd -- --axis-body` 退出0：实际创建/进图/装备/源裙初始化清理及事件回归通过；保留已有1个 ObjectDB 退出警告和插件 zero anchored 警告。该回归尚未新增正式主手武器装备断言，不当作武器入口全部验收。

下一步继续真实装备入口武器种类/动作适配，以及坐地/躺下/起身等缺失动作和其余计划。全目标未完成，性能、MMD以及默认迁移仍在后序；Go与正式地图暂缓。

# 第四十九批（2026-09-29）：现有 GPU 插件接入共用角色生命周期

新增 `character_runtime_cloth.gd`，只编排已有 `garment_candidate_cloth`，不改求解器/源衣服/约束参数。物品元数据 `surface_cloth_slots` 经共用 equipment_parts 生成 SurfaceClothSlots；当前只给已经做同姿态对照的 native_maid_skirt 声明 Clothing2，其它服装不自动开启。AxisRig 管理每槽适配器，Model._process 在动画与过渡混合完成后提交身体表面。增加布料槽输入类型校验，避免错误元数据在衣柜事务之后崩溃。

初始化保留现有65帧准备流程：临时身体解算同步完成，阻止临时 surface_updated 信号，在任一可见帧之前恢复当前角度/根偏移与动作配方；准备完成前显示原表面跟随，完成后才切插件输出。人物本身不展示 T 姿，发型/标签不接收临时姿态。注意：这是正确性接入，准备耗时和完成时切换观感尚未做性能/体验优化；不能宣称已达到实时预算。

重复同一装备复用适配器；卸下/换件随对应衣服释放；身份形态改变时重新准备布料，不继续使用旧体型状态。适配器以衣服节点为父级，HUD/玩家/NPC 共用 Model 释放即可清理。输入错误仍保留静态表面并记录错误；没有宣称支持多层相互碰撞或椅子。

`test_runtime_cloth_lifecycle.gd` 两轮实际 GPU 验证：65步准备后 ready，人物最大控制点误差5.889e-7米，发型变换保持；同配方复用、改身高销毁旧适配器并重置准备、卸装释放成功。真实 Model._process 的一次 walk 混合后，插件 external_targets 与最终 garment.evaluate(body.posed_points)+root_offset 逐点比较，最大误差0，证明未提交混合前目标。仅一次行走帧的输入验证，不是完整行走视觉验收。

最新 `runtime_cloth_lifecycle_02/` 保留 prepare_00/32/64 图和 report.json，已观察准备前/完成图；image_visibility_check.json 对原始 PNG 检查头部与腿部非透明像素，三帧分别保持9,154和14,820，身体未消失。裙摆仍有第四十八批记录的侧后外翻，未伪称解决。01 是第一轮数值证据，02 补了画面与最终混合目标检查。

正式 `test_world3d_flow.gd -- --axis-body` 回归通过：实际新身体玩家装备源分体裙触发插件初始化，身份/形态保持，退出清理；该世界测试没有等满65帧，不能算正式场景全部布料动作已验收。原1个 ObjectDB退出警告仍在，插件 zero anchored 警告与第四十八批同义（混合权重+external targets），没有删除日志掩盖。

按用户要求不再循环调此裙参数，剩余侧后外翻/肩部和连续坐躺记录保留。下一步推进武器挂点/自然握持及其余人物动作和服装范围，再做默认迁移、性能、MMD；全计划继续，Go和正式地图暂缓。

# 第四十八批（2026-09-29）：正式角色同姿态接触方案对照

纠正第四十七批“启用此前处理即可解决”的潜在误解：已有两套不同的实验后端，必须在正式 Model 的同一站姿比较，不能把历史某套裙子的通过外推。新增 `capture_runtime_contact_comparison.gd`，使用共用 View/Model、原 maid_separate 上衣/裙子及完整身体/内衣，idle .2 秒；开关前后均保留正侧图，输出人物控制点差报告。没有修改源衣服、shader材质、输入动作或接触参数。

1. 默认运行复用旧 `garment_cloth_gpu`，现有80步预热后再稳定12帧；证据 `runtime_contact_comparison_01/`。人物控制点最大变化5.889e-7米，位置保持。实际观察：双手附近裙子被压下，但围裙前侧明显折起、袖肩仍穿插；**视觉未通过，不提升为正式默认**。
2. `--candidate` 复用已安装的 GPU 插件及 `garment_candidate_cloth` 现有默认参数，仅驱动裙子，用65帧原始姿态到指定最终姿态的预热；证据 `runtime_contact_comparison_02/`。同样人物控制点最大变化5.889e-7米。正侧图显示手边裙摆收拢，围裙比旧原型平顺，但侧后方仍外翻；**只有这个静态站姿的视觉改善，不是动作/所有外装验收**。原日志“zero anchored vertices”对应该衣服没有完全固定顶点；适配器仍提交混合权重及 external targets，不能单看警告就判定没有跟随目标，也不能忽略后续稳定性验证。

本轮未改求解器或源参数，两个报告均保持 visual_accepted=false，失败/改善图分别保留。运行退出成功不等于衣服验收。选择下一步复用现有插件接共用角色的受控生命周期，验证加载准备、最终混合姿态提交、换装释放与形态更新；原型继续不启用。预热不得在可见帧把角色摆成 T 姿，不能把临时预热姿态混进玩家/NPC/标签/发型输出。该接入仍未实施。

遵守裙装收口：不重新迭代旧裙子求解参数，不追几何零交叉；侧后外翻等剩余问题记录，完成生命周期检查后转武器/其它动作。性能留待对应阶段；默认身体迁移、其余服装动作、动态发型高度碰撞、性能及 MMD 仍未完成。

# 第四十七批（2026-09-29）：源女仆服装正式物品与共用角色接入，视觉未通过

新增 source_garment_equipment 的四个独立 ID：native_maid_dress、native_maid_top、native_maid_skirt、native_maid_headpiece，分别引用已有 maid_classic/item_00 和 maid_separate/item_02、01、00。没有把旧粉白/黑白生成女仆服的 ID 偷换成源服装。物品目录注册、新女性身体的 mocker 初始背包发放、装备快照到 SurfaceEquipment 映射已接通；只声明适配 female_base_v2，mocker 在实际装备前检查角色身体版本，不兼容时不消耗物品。

连衣裙通过按身体声明的 surface_hidden_parts 遮盖 Clothing2，映射在所有槽合并之后执行，避免结果依赖装备遍历顺序。卸下连衣裙后仍穿着的分体裙恢复显示；不删身体、不自动穿回内衣。这是服装层的显示规则，不是碰撞修复。

`test_source_outfit_entries.gd` 通过真实创建/进图获得物品，穿分体、改连衣裙、卸连衣裙恢复裙子；共用 View 和 NPC 工厂收到同一表面配方，身体/当前姿态保持、服装实例互不共用。旧身体尝试穿源连衣裙被拒绝，背包仍保留物品。`test_underwear_equipment.gd` 原上下槽独立/卸下/替换/外装不恢复内衣回归通过。

正式 `test_world3d_flow.gd -- --axis-body` 也已加入三件源分体装实际装备及角色身份/形态保持检查，全部通过；仍有既存1个 ObjectDB退出警告。

**视觉仍未通过，不得将数据接入当裙装完成。** 真实共用 View 正侧两套共4图在 `source_outfit_entries_01/`。已观察分体正面和连衣裙侧面：分体裙仍向两侧撑开，手部接触没有把布面压下；连衣裙肩部有穿插迹象，头饰组合也待复核。当前正式 AxisRig 仅安装 surface wardrobe，并未启用/推进此前的接触或布料处理。这是运行时集成缺口，不应改原衣服网格或再把手臂摆开。

下一步核对如何将已完成的处理接进共用角色生命周期并保留原失败姿态。遵守第十九批收口要求：不重新无限迭代同一裙装求解器，无法复用或剩余接触问题要具体留档；武器、其他外装、完整动作及动态发型高度碰撞仍待，默认迁移/性能/MMD未完成。

# 第四十六批（2026-09-29）：装备预览实例、信息与可见画面

装备窗口收到快照时会重建整个内容，原实现把 CharacterView 放在可销毁的 DollCanvas 下，导致每次换装都重新创建身体并重置预览动作。现将唯一预览挂到 HUD，窗口重建只换显示纹理/控件，调用共用 Model 更新配方与装备；HUD 释放时连同预览释放。补回 _equipment_map 丢失的 bound/enhance，槽位提示可消费实际绑定和强化信息。

真实 HUD 测试 `test_equipment_preview_identity.gd`：新身体高度/臀围与短发配方，walk .35 秒冻结，在穿两件内衣、卸上装和重开窗口后，人物/身体实例、外观和已解算姿态保持；内衣上下槽独立；绑定/强化元数据正确，HUD 释放后预览不再存活。

不能只检查实例：首次实拍发现把整个 View.visible=false 会得到透明空图。修复为只隐藏显示 Sprite，保留离屏渲染；共用 View 的二维影子也仅在显示 Sprite 可见时绘制，避免隐藏预览在 HUD 原点画影子。测试补图像 alpha 覆盖量门槛，失败空图保留为 `equipment_preview_01/failed_hidden_parent_*`。修正后的完整 HUD 与离屏图见同目录 actual_*，已实际观察。

同时修复装备人物过小：方形地图视口缩入狭长装备栏时浪费大半高度，现使用竖向296×552视口，正面相机按当前身体/发顶范围取景；3D 纹理用线性过滤，并给底部装备槽保留空间。该取景没有改身体尺寸、发型网格或动作。`test_l2_hud.gd` 原16槽/窗口/其他HUD回归全通过。

本批只验收当前新身体、内衣和预览状态，不代表未适配的外装、武器或 NPC 装备组合已通过；隐藏窗口的渲染/动作调度放在后续性能阶段评估，尚未做全场帧预算。下一步推进新身体外装/武器与 NPC 统一装备适配及剩余动作；身高下动态发型接触、默认迁移、性能、MMD 仍未完成。

# 第四十五批（2026-09-29）：mocker 角色装备往返与选角快照

修复选角和实际玩家的装备状态断链：原 mocker 每次 enter_world 都清空背包并发初始装备，选角头像又传空装备。现在 SessionModule 在切角色/成功切账号/退出登录前保存当前账号角色的内存检查点；重新进入已有角色恢复背包与装备。仅保留当前 mocker 进程内状态，不写磁盘、不实现 Go 持久化，也没有扩展为任务/仓库等全角色存档。

背包检查点保存原 stack 元数据、金币和容量；装备检查点保存槽位、耐久/上限、绑定和强化。恢复到现有 inventory/equipment 实例，避免其它战斗模块持有旧实例。成功切身份前先取消并退还交易 escrow，防止旧角色物品退给新角色。角色列表取副本附上装备快照，未进入的新角色由现有 starter 定义生成初始预览；选角经过同一 equipment_parts 和物品目录映射，空内衣槽保留卸下语义。

`test_character_gear_session.gd` 通过：真实 mocker 创建 A/B、A 穿两件内衣、实际选角预览读取两槽、B 不继承；切 B 再回 A，完整背包/金币、耐久37、绑定、强化2保持；A 卸内衣上装后登出，切另一账号再登入 A，上装仍空、下装仍在。加入交易暂存药水/金币后切角色，交易结束并退回原角色，完整检查点仍相等。该测试也确认选角不只是拿到字符串 ID，而是实际 Model 的 SurfaceEquipment 已映射。

调试过程：测试入口误写 enter_world_3d、单参数 signal await 误取[0]已修；首轮选角映射漏传 item_catalog 导致无表面内衣，已修正式调用并重跑。不是原资源或衣服模型缺失。

相关回归 `test_equipment_server.gd`、`test_trade_shell.gd`、`test_world3d_flow.gd -- --axis-body` 全部通过。正式进图仍有既存1个 ObjectDB 退出泄漏警告。范围不包括 mocker 重启/Go/网络重连存档，也不证明完整外装或武器已适配新身体。下一步完整装备面板预览与 NPC 外装组合及其余形态/动作缺口；高度下动态发型接触、默认迁移、性能、MMD 仍待完成。

# 第四十四批（2026-09-29）：头像随身高取景与选角/NPC 配方检查

发现真实入口缺口：`character_view_3d.configure` 的头像相机仍固定在1.75米并看向1.69米，新身高配方不能得到稳定构图。新身体现在按不可变原身体的头部顶点集合，计算当前已解算头部范围及发顶，自适应位置和画幅。长发末梢不纳入头像范围；其它旧身体逻辑未迁移。

首次实拍发现头顶留白过多：用于防渲染裁切的 `custom_aabb.grow(.1)` 不应作为头像美术边界。因此发型适配同时保存无扩张的 rest bounds，头像使用该范围；原渲染包围盒和头顶标签的安全余量不变。原发型顶点、UV、权重和姿态未改。

`test_identity_entries.gd` 实际加载选角场景并送入高/矮两份新身体配方，验证头像保留全部身份参数、头部在视口内，以及 `Model.create_npc` 的身体控制点/发型适配与选角一致。修改 NPC 身高后选角实例不受影响。相机中心从约1.857米变为1.584米，画幅约0.462/0.461米；头部屏幕范围约92–223及90–219像素（256图）。已观察两张实际头像，身高不同但构图稳定。证据 `identity_entries_01/`；工具另保留旧固定相机的对照图。实际创建页五滑杆、主/头像、换发/卸发/随机/性别兼容回归通过。

这是同一配方在选角及 NPC 工厂的验证，**不是 NPC 地图战斗、完整装备预览/返回选角状态或所有发型头饰组合验收**。当前选角接口只拿角色列表、传空装备，返回选角时装备快照链仍需补；不应因为身份一致就宣称换装入口全通过。

另外核实发型接触缺口：当前胶囊随骨骼移动，但局部端点/半径固定为基线。原身高增量做全局仿射拟合仍有最大约17.2毫米、95分位约10.5毫米误差，不能直接套一个身高比例宣称适配正确。局部尺寸/表面关系和高度下动态接触待验收，默认动态继续关闭。后续推进角色装备状态链、更多形态/动作、默认迁移、性能及 MMD；不重启已收口的裙装迭代。

# 第四十三批（2026-09-29）：原生身高公式、骨架与头发联动

核实原 VaM 程序枚举及调用：targetType 1/2/3 是 BoneCenter XYZ，SetBoneX/Y/ZOffset 接收 multiplier×morphValue，按原世界中心加偏移；当前80个身体骨骼的 parentForMorphOffsets 均为空，disableMorph 均为 false。FBMHeight 的240项公式由此可直接作用于原全局 rest 中心。没有把其它旋转、缩放、MCM 或形态依赖公式默认为已支持。

`character_body_shapes` 同时计算原控制点增量与骨骼中心；`female_axis_body` 从不可变基线重建 global rest、inverse rest 和 Skeleton3D local rest，再保留当前角度/根偏移解算。头发重新按头部适配，但始终从原未适配 rest/Skin 烘焙，不累计缩放、不重建实例、不修改原顶点/权重。创建页新增身高滑杆：向右变高，存储仍是源权重（原 FBMHeight 正值缩短，因此 UI 方向取反）。

验收：

- 五项形态回归通过，CPU/GPU 最大差5.50e-7米；独立源增量、配方、回零、实例隔离、身体/衣服共享表面与实例复用继续通过，报告 `body_identity_02/regression.json`。
- `test_height_identity.gd` 独立读取240公式对照，中心最大误差8.55e-7米；-1/0/+1 对应静止模型高度约1.931/1.795/1.659米。六次高/矮/回零切换，身体和头发实例保留、头发 fit 回到原值。idle/walk/sit_chair 各三个时间采样没有穿过平地，报告 `body_identity_02/height_regression.json`。
- 实际创建页五个滑杆、主预览/头像与配方回归通过。mocker 创建→Loading→实际三维玩家→内衣装卸通过，身高与其余四项权重保持一致；仍有已有的1个 ObjectDB 退出泄漏警告。
- 全身画幅捕获12图于 `body_identity_03/`，已复看高身材正面、矮身材侧面，没有明显拉断、头发脱离或内衣大片穿出。`body_identity_02/` 的截图画幅会裁掉高身材头脚，不作全身验收。

边界：当前接触采样只覆盖平地，不能证明任意地形、椅面或脚部悬空均正确；头发动态仍默认关闭，变身高后的动态碰撞体尺寸尚需复核。其它衣服/动作极值、更多捏人形态、全部角色入口、默认迁移、性能及 MMD 仍待办。下一步沿现有原数据/共用模型链继续补齐，不再重复已确认的发型父链或已收口的裙装迭代。

# 第四十二批（2026-09-29）：四项原生形态进入共用捏人和游戏链路

新增 `character_body_shapes.gd` 消费已暂存的 bust_size/hip_size/waist_width/nose_width 原增量；校验索引、有限值和源范围，拒绝带未支持公式的数据。每次从不可变 `base_rest_points` 重算，身份形态先于原分轴变形和细分；不把旧模型的 bust_size=0.5 偷换成新身体权重。`Customization.body_shapes` 使用独立字典，原身体权重0，沿用现有配方传递。

`female_axis_body.set_shape_values` 保留当前解算姿态、网格、骨架和纹理实例；CPU 与 GPU 共用形态后控制点。GPU 增量更新原 rest buffer 的 XYZ，保留 W 权重记录数和原512×43填充。第一次回归发现错误地要求缓冲区长度等于21,556点，导致 compute 开启失败；已按原填充布局修复并重新验证，未切 CPU 回避。形态更新失败时共用 Model 保留旧 appearance。

创建页新身体新增四个实际生效滑杆及默认按钮，范围来自原数据；原旧身体滑杆不变。主预览/头像/玩家仍是同一 `character_model_3d` 入口。内衣继续读取同一个身体位置纹理，调整体型不重绑网格、不重建衣服或重置动作。当前只支持无骨骼公式的四项，**height 未开放**。

本批证据：

- `test_body_identity_shapes.gd`：逐项原文件独立参考、静止 GPU 点、弯肘 CPU/GPU 最大差5.50e-7米；精确回零、五次重复组合、JSON 配方往返、双实例隔离、网格/骨架/纹理身份及衣服共用表面通过。报告 `body_identity_01/regression.json`。这验证数据链，不是所有衣服/动作画面。
- `capture_body_identity_shapes.gd`：原基线、范围下端/上端组合、中等组合，各正侧8图于 `body_identity_01/`。已观察上端正面、下端侧面和中等正面，内衣随形态变化，没有明显大片穿出或破形；不覆盖其它服装和独立形态全部极值组合。
- `test_source_hair_creation.gd`：实际创建页四个新滑杆更新主预览/头像且不重建身体，换发/随机/保存配方/性别回切原回归通过。并验证没有未实现的身高控件。
- `test_world3d_flow.gd -- --axis-body`：mocker 创建配方→Loading→实际三维玩家、内衣装卸，形态字典持续一致，原事件回归通过。exit0，仍有此前同类1个 ObjectDB退出泄漏警告，未说已修复。

下一步：height 原数据的240公式已确认结构是80骨各XYZ（targetType 1/2/3），但枚举数值对应、源 BoneCenter 应用符号/单位与父子全局/局部关系仍需结合现存反编译证据验证。须同步 rest frames/inverse frames/局部骨骼 rest，再检验动画、足底、头发和衣服；不能只改网格开放身高。后续仍有更多捏人部位、选角/NPC完整复核、装备/动作、默认迁移、性能与MMD，当前不是总体完成。

# 第四十一批（2026-09-29）：口腔法线、牙列诊断与原捏人数据盘点

`character_native_face.gd` 为 Teeth/Tongue 接入原 `_BumpMap`，在 shader 解码 A/G 的切线 XY 并重建 Z；不把打包图当普通 RGB，也不重绘原图。读取原 `_DiffuseBumpiness`：牙齿1、舌头0.2。使用变形后导数构建切线框架，避免原静止切线在下颌旋转后指错方向；当前 PBR 一个法线同时影响漫反射/高光，尚未单独复制源 SpecularBumpiness 通道，不称渲染器完全一致。

`capture_native_mouth.gd` 真实共用 Model 在静止/下颌18度、完整头部/仅口腔诊断显示、法线开关下捕获8图；最新 `native_mouth_02/`。诊断隐藏其它面只存在工具中，不改正式角色完整身体。已观察完整张嘴及分离牙列：前牙完整、上下牙列/舌头存在，完整头部里前牙被嘴唇遮住，不能误诊为模型丢牙后移动牙齿补画面。原骨骼旋转仍不等于完整自然张嘴表情，嘴唇形变需在表情阶段配合，MMD 顺序不变。

绑定检查 `binding_check.json`：lowerJaw 从0到18度，上颌全权点最大位移0，下颌全权点对锚点的距离误差2.775e-7米。法线开关在完整张嘴图改变3,101像素、最大通道差4/255；分离口腔图8,633像素、最大6/255，确认实际采样有效且影响有限。正常退出、没有 shader 错误；不据此宣称所有发音/下颌极值已验收。

转入下一项捏人形态。新增 `extract_native_body_morphs.py` 只读原 `f_mb`：盘点1,541项形态，索引范围/有限值/记录数量检查均通过。`FaceFemale4` 有重复顶点条目，源的加法列表可以合法累计，不当作源模型损坏；以后不能用字典覆盖丢增量。未启用该项。

首批五项原数据保存至外部 `characters/morphs/female_base_v2/source_native_01/`，含 manifest、源/输出 SHA、原范围、增量及公式：bust_size(PBMBreastsSize)、hip_size(PBMHipSize)、waist_width(PBMWaistWidth)、nose_width(PHMNoseWidth)、height(FBMHeight)。前四项没有公式；height 含240项公式，不能只改表面便开放滑杆。提取断言当前21,556控制点坐标/顺序与原身体完全相同，但这只是结构前提，不代表形态/动作/服装视觉已通过。

下一步直接消费上述数据，接 `female_axis_body` / GPU 的身份形态基准与共用 Customization 配方，验证回零、组合/重复应用、实例隔离和衣服跟随；身高需要原关节公式适配。**本批没有接形态运行时或添加滑杆**，不要重复从游戏全盘扫描。后续仍有完整装备/动作、默认迁移、性能及 MMD 工作。

# 第四十批（2026-09-29）：核实并接入眼部遮罩与反光分层

`f_c_mat` 的 shader 外链已实查为 `z_sha`（CAB-2ad6c35afaff70ad349bb299a2fb4f77）。新增 `inspect_native_face_shaders.py` 按原 pass 的 m_BlobIndex 解析 DXBC，输出四个 shader 的 pass0 等汇编、参数绑定和 SHA；物理 blob 中第一个 pixel shader 不一定是 FORWARD，首次 `*_first_pixel.asm` 仅作调查，**不作为反光公式依据**。实际证据在外部 `face_native_01/shaders/*_pass0.asm` 及 parsed.json。

- Eyelashes：原 shader 的 `_AlphaTex` 确实采样 A，上一批通道选择得到确认。当前源 AlphaAdjust 为0；不是改用 RGB 灰度来碰运气。
- Cornea：原 `Custom/Subsurface/AlphaMask` 输出 RGB=0，alpha=saturate(MainTex.a*Color.a+AlphaAdjust)，以 SrcAlpha/OneMinusSrcAlpha 混合；它是压暗遮罩，**不是半透明白膜，也不负责镜面高光**。已按此语义接入原遮罩和 .466 opacity。
- EyeReflection：原 Marmoset glass 使用 One/OneMinusSrcAlpha，默认 diffuse alpha=0 仍可保留高光。Godot 当前使用黑色 diffuse + 加法镜面层，按源 sharpness 近似映射 GGX 宽度并读取 SpecColor/SpecInt。这是明确的跨渲染器近似；未复刻 Marmoset cubemap、曝光和全部高光算法。
- Tear：原 Transparent shader、Color.a=0、AlphaAdjust=0，因此默认确实不可见。已恢复显式透明材质及源参数，而不是擅自提升透明度制造泪线；原游戏运行时是否另改该值仍待配方层核对。

`package_native_face_materials.py` 现在同时记录八个材质原 shader 名称/精确 ID 及 z_sha 哈希；运行时检查 Cornea 的来源语义，避免错包后静默套玻璃材质。`female_axis_body` 复制材质时补保留 render_priority，否则原层顺序丢失。八个面保留动态分轴变形与纹理。

`test_native_face_materials.gd` 当前覆盖八面、纹理、动态变形参数、反光/泪线优先级和源泪线透明度；两灯位、正侧面、叠层开关八张图及下颌诊断图位于 `native_face_03/`。已观察正面默认灯及侧面另一灯位，没有白膜遮眼。四组开关比较变化像素分别237/203/244/208，最大通道差40/30/40/32（640方图，变化较小，不等于所有条件视觉正确）。实际程序 exit0，无 shader 错误；一次测试预期数组把 Tear/Teeth 字母顺序写反导致断言失败，已修正再跑。新增超时退出，防止断言中止后进程无限挂起。

最新资源重打包后再次运行八面测试通过；`test_skin_viewport_capabilities.gd` 也真实运行通过，透明预览/不透明角色各16个皮肤面仍保持原贴图/肤色与 SSS 能力分支，无新增错误。两个 Python 工具语法检查通过。

下一步推进原口腔打包法线/下颌诊断暴露的问题，再接完整捏人/装备/动作链；不要将眼部有限对照当全部头部表情或正式入口迁移完成。原 MMD 任务仍在性能之后。

# 第三十九批（2026-09-29）：恢复原睫毛及口腔纹理

从已批准身体的 `original_data.json` 材质槽指针定位 `f_c_mat` / `p_eye_mat`，新增 `package_native_face_materials.py` 提取八个面部材质记录及原图至外部 `characters/materials/face_native_01/`。记录包与贴图 SHA256，Unity 64 位 PathID 全部保存为字符串，避免 Godot JSON 数字丢精度。没有重绘贴图、替换身体或借用其它模型 UV。

共用 `character_regional_skin` 接入 `character_native_face.gd`：恢复此前全透明的 Eyelashes，使用原遮罩 alpha、原 tint、原 cutoff .3；Gums/Tongue/Teeth/InnerMouth 使用各自源材质引用的原 albedo/specular 图。保持 ShaderMaterial，进入真实动态身体后保留纹理和原分轴变形。口腔粗糙度暂为明确的 PBR 近似，不声称完全还原原渲染器；Unity A/G 打包法线尚未使用。

`test_native_face_materials.gd` 真实 Vulkan 运行通过：五个面材质、2048 图及动态 body_positions 检查；`native_face_02/` 正面/侧面/原 lowerJaw 18 度诊断图。已观察正面和张嘴图：睫毛显示、口腔和牙齿不再是纯色占位。该张嘴不是完整表情，牙列/舌体显露仍需完整口腔动作检查，不能认定动作自然。01 为最初剪裁捕获；抗锯齿候选曾因 ALPHA_TEXTURE_COORD 错名编译失败，修正为 [Godot 4.7 官方文档](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html) 的 ALPHA_TEXTURE_COORDINATE 后，02 重新运行无该错误，使用 alpha-to-coverage 配合 4x MSAA。

下一步：Cornea/EyeReflection/Tear 仍透明占位，继续原材质语义及近景验收；睫毛 alpha 通道与原 shader 的精确采样语义仍需核对，不把贴图相似当原算法证明。随后继续捏人/装备/动作链。没有提前执行 MMD，也没有将这一批当成人物系统完成。

# 第三十八批（2026-09-29）：量化透明预览 SSS 限制并显式适配

先做同一个 View/角色/相机/灯光的三个控制：不透明+SSS、透明+SSS、不透明去除 SSS。`capture_skin_viewport_parity.gd` 完成 3 图于 `skin_viewport_parity_01/`，exit 0，透明项如预期报告引擎禁用 SSS。已观察透明/不透明画面。`audit_skin_viewport_parity.py` 可复算：alpha>.99 后内缩 5 像素，110,936 个前景像素；opaque_sss vs transparent_sss 平均通道差 .37374/255，p99=4/255，最大33/255；透明 vs opaque_no_sss 平均 .000297/255，p99=0，少数最大23/255。前景还包含眼/衣物，不是纯皮肤专用掩膜；不能将均值说成所有像素一致，也不能推广到所有光照/分辨率。证据说明当前配方差异很小，不支持把整片肤色异常都归咎于 SSS。

`character_regional_skin.create_preview(screen_space_sss)` 增加能力选项；`female_axis_body` 初始化时按实际 Viewport.transparent_bg 选择。透明视口编译不含 SSS 输出的材质，保留同样的 albedo/normal/gloss/specular 贴图、肤色及参考色；不透明视口继续使用原 .1 SSS。不添加假皮肤补色，不关闭全场景 SSS，也不强行把透明头像改成矩形背景。这是能力限制的显式处理，**没有声称在透明视口实现了 SSS**。

`test_skin_viewport_capabilities.gd` 实际创建透明 View 与不透明世界角色，验证两端各16个皮肤面、透明 shader 不含 SSS/不透明保留、四张贴图与两肤色参数一致；真实渲染等待后 exit 0，无此前透明 SSS 警告。测试与捕获不重建已批准身体几何。控制捕获专门先用不透明视口构造完整 shader，再切透明，以继续重现引擎限制。

限制：能力选择在身体初始化时进行，若未来新增跨视口重挂或透明属性热切换需同步重选 shader；正常创建/头像/世界入口当前分别初始化，不使用这种热切换。原16面处理已通过，不宣称旧身体全部材质或透明服装等均适配。

下一步补当前明确的眼部/角膜/泪线/睫毛与口腔占位，以及其后的完整捏人/装备/动作链；不要围着 .1 SSS 小差异反复调参。新身体默认迁移、发型动态、性能、MMD 仍未完成，裙装继续按用户要求收口。

# 第三十七批（2026-09-29）：原发型材质进入共用运行资源

马尾 K001/K007/K019（银白/深色/棕色）、棚拍/游戏灯光、0/45/90 度共 18 图完成于 `source_hair_lighting_matrix_02/`。已人工看深色棚拍45度、银白游戏侧面、棕色游戏正面：发色区分与源发束高光保留，没有据这些图扩展为所有色带/头型验收。第一轮 matrix_01 因工具替换材质后丢源名称且改色仍指向旧材质失败，已保留；修复后工具保留 source 参数/名称并登记新材质到原 hair.materials，第二轮日志无该错误。

将单一 shader 移到 `scripts/char/character_source_hair.gdshader`，删除工具重复 shader。`bake_source_hair_material.gd` 离线读取已确认源高光/ramp/细节及参数，三款 .scn 重烘焙通过。运行时不读 Unity 源材料 JSON 来组装高光。旧 PIGMENT 仅保留为构建颜色输入，实际成品使用共用新 shader。

`character_key_light` 组由创建/头像 View、三维世界太阳、灯光场景主光提供。发型只选择与自己同 World3D 的主光，并更新实际方向/可见性；无主光时采用常规漫反射，避免默认方向串场。地图太阳已接组，但本轮没有重跑完整地图流程，不能将 UI/灯光图冒充地图视觉验收。每帧参数写入可在性能阶段合并，目前不以性能重构阻挡视觉。

实际创建页测试扩展并通过：主预览/头像主光实例不同、World3D 匹配、转灯方向同步；原换发/卸发、身体身份不变、随机、男女兼容、配方 JSON 往返仍通过 exit 0。GPU 灰阶改用正式 shader，再次 .25/.5/.75→.25098/.49804/.74902，通过。`source_hair_runtime_material_01/` 不带 --candidate，实际运行资源 9 图完成、无 shader 错误，已查看马尾侧面与候选一致。

本轮接入三款当前材质，不宣称完整 ShaderForge 克隆：非空 MainTex/NormalMap/AnotherRamp 扩展、同方向重叠主光、动态阴影全等价仍有限制；源法线 AG 不能直接当 RGB。发型动态/接触仍默认关闭，后续动作组合继续单列。新身体默认迁移仍未全开。

下一步优先透明预览 SSS 差异与面部/人物链其他缺口，不继续无目标反复调同一发束高光。皮肤警告仍在创建测试出现，尚未修复。性能、MMD、Go/正式地图优先级不变。

# 第三十六批（2026-09-29）：修复重复底色乘法及重复主光效果

候选原式 `DIFFUSE_LIGHT += ALBEDO * ...` 在 Godot 中重复乘底色，导致第三十五批偏暗。现在删除重复乘法和源 ramp 之后额外的 Lambert 压暗，补源双采样 .008 V 差值（导入 V 翻转后取 -.008）、ambient shadow 与 ShadowColor 叠色、DetailMask G/B 门控、色相边缘光、背面 .66 系数；相关参数读取原材质和已验证默认配置。

新增实际 GPU 灰阶回归 `test_source_hair_light.gd`：单白灯、无环境光、白阴影、无高光/边缘光、linear tonemap，输入 .25/.5/.75 渲染为 .25098/.49804/.74902，exit 0。覆盖实际底色乘法/能量归一链，不把纯语法检查当渲染测试。初次测试引用不存在的环境枚举已移除；后续主光分支用 return 导致 Godot light() 编译失败，回归实际捕获该错误，改 if/else 后再跑通过。

`source_hair_gloss_on_02/off_02` 各 9 图显示颜色恢复但三盏工作室灯重复执行原 FORWARDBASE 导致泛亮。候选现接收工作室实际主光方向：原阴影/高光/边缘光只对主光执行，其他灯使用普通漫反射。`on_03` 因上述 return 编译失败，**不可当有效验收图**；失败保留。最终 `source_hair_gloss_on_04/` 9 图正常结束且日志无编译错误，已看马尾侧面、长发正面：过暗底色和高反差强带缓解，发束高光保留。工具输出改为 WROTE，避免仅有图片文件就打印 PASS；已启动的旧进程仍使用原输出文案，以日志/回归/观察共同判定。

当前仍是工具候选，正式 PIGMENT 不变。下一步限定深浅发色和不同灯光、转视角矩阵验收，再接共用材质/主光输入；不要继续无目标微调。主光方向现是捕获时快照，尚不是地图/动态灯光正式接口；同方向重叠灯未区分、非空 MainTex/NormalMap/AnotherRamp 与原全局最终颜色夹取仍未完整处理，不能声称完整 ShaderForge 等价。透明预览 SSS 及整体迁移继续待办。

Godot 4.7 官方自定义 light 示例不乘 ALBEDO，LIGHT_COLOR 包含 PI，参考：https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html 。

# 第三十五批（2026-09-29）：原 UV2 高光的实际开关对照

本轮完成可运行候选，未替换正式材质。提取器保留原 tangents，builder 按 Z 反射/V 翻转转换 tangent.xyz，两个手性翻转抵消后保留 w，并保存源材质/网格名以便追溯。重提取、三款重烘焙 exit 0；UV2 回归扩展到全部原切线方向（压缩误差 < .002）及手性，42,356 UV2 表面顶点继续通过。

`source_hair_lighting_candidate.gd/.gdshader` 仅由捕获工具 `--candidate` 使用。从已验证的 program_defaults 加载原 gloss/ramp，从各源材料加载 DetailMask、ShadowColor、SpeclarHeight。UV2 使用原高光图并消费切线视角偏移、源 .005 光向偏移；光照接入 Godot light() 的颜色/衰减。它只恢复了部分采样关系，**不是原 DXBC 完整等价移植**：当前漫反射仍包含 Lambert 因子，尚缺源全局阴影混合、双采样差值、色相边缘光和完整背面处理，不能把预览成功说成材质验收完成。

`capture_fitted_source_hair.gd -- --candidate --capture=source_hair_gloss_on_01` 与额外 `--no-gloss --capture=source_hair_gloss_off_01` 各完成三款正侧背 9 图，均 exit 0，无 shader 编译报错。已看马尾侧面开关对照、长发正面、短发背面：原 UV2 高光分布已生效，但整体偏暗、亮带反差偏强，视觉尚未批准。保持正式 PIGMENT 不变，候选不自动启用。不通过修图/删网格/调头型掩盖阴影算法差异。

下一步直接完成已知遗漏的原阴影/双采样及边缘光运算并做同灯光对照，不再重复查默认纹理或 UV2。透明预览 SSS、头型/头饰/外装组合与默认迁移仍待办。Godot shader 空间/UV2/light 接口参考官方 4.7 文档：https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html 。

# 第三十四批（2026-09-29）：原高光与全局 ramp 默认装配已核实

本轮是源参数证据补齐，未修改运行时光照、未新增视觉通过声明。新增 `inspect_source_hair_lighting.ps1`，复用本地 dnlib 只读程序集，不执行游戏代码；导出有程序集 SHA256 的 407 行相关 IL 到外部 `source_hair/koikatu/lighting/source_lighting.il.txt`。

已核实：ChaFileHair.MemberInit 设 glossId=0，ChaControl.LoadHairGlossMask 查 mt_hairgloss，并对所有头发 renderer 设置 `_HairGloss`。原 `list/characustom/00.unity3d` MessagePack 列表中 0 对应 `cf_hair_00_01_mh`。Config.EtceteraSystem 构造/Init 设 rampId=1、shadowDepth=0.26；Manager.Character.UpdateGlobalShader 查类别 432、加载所选纹理并调用 ChaShader.ChangeRampTexture→SetGlobalTexture；列表 1 对应 `gt_ramp_01`。ChangeAmbientShaodwColor RGB 为 (0.019,0.027,0.039)，A 使用 shadowDepth。

提取器增加原列表二进制与 bundle 溯源保存；两个默认 ID→纹理名用原 MessagePack 数据断言通过。`lighting/program_defaults.json` 保存已验证配置和证据路径。普通 JSON 展示中的日文标签曾因文本编码出现乱码，不用于判断；原二进制保留，ID 和 ASCII 资源名直接从原数据校验。这里是程序默认值，不是当前安装的用户配置覆盖，也不是所有角色卡的 glossId。

下一步无需再查默认来源：使用已保存 UV2、默认高光和 ramp 实现源材质计算及开启/关闭视觉对照。原法线 AG 编码、切线/UV2 视角扰动仍需正确转换；不要为快速出图用随意亮带替代。透明预览 SSS、组合/默认迁移、性能及 MMD 仍未完成。裙装保持用户要求收口。

# 第三十三批：补回源高光 UV2 与运行时指定纹理

确认源马尾头发网格 `cf_hair_b_06_00`（5823 顶点）和 `cf_hair_b_06_01`（2218 顶点）都有 UV2，发饰没有；原提取器只保存 UV0。这是我们的数据丢失，不是源模型缺少高光布局。`extract_source_hair.py` 现保留 UV2，重新提取 12 prefab；`source_hair_builder.gd` 保留原 mesh 名并将第二套 UV 按同样 V 翻转写入运行时，未改顶点/蒙皮。源无 UV2 的发饰保持无 UV2，不凭空复制第一套。

三款运行时资源重新打包 exit 0。新增 `test_source_hair_uv2.gd` 从烘焙 PackedScene 的全部表面逐点对比 source.json：42,356 个表面顶点，除 V 坐标转换外误差 < 1e-5，通过 exit 0。本轮只是数据链补全，当前 shader 尚未使用 UV2，故没有宣称高光已经修好或重复拍摄不变画面。

复用已反编译 `customization_research/kk_ChaControl.cs` 4511–4547：LoadHairGlossMask 由 hair.glossId 查询 mt_hairgloss，ChangeSettingHairGlossMask 将结果写到全部 rendHair。prefab `_HairGloss=0` 不代表原游戏无高光。新增可重复的 `extract_lighting_textures`，只读提取 `mt_hairgloss_00` 的 10 张高/低分辨率高光与 `mt_ramp_00` 的 7 张 ramp，均带 bundle SHA256，保存外部 `characters/source_hair/koikatu/lighting/manifest.json`。纹理已落地不等于选中的 glossId/全局 RampG 默认组合已还原。

下一步直接核对 glossId 默认值及全局 ramp 赋值，利用已保留 UV2 接原高光/细节采样；不要再重复查源是否有 UV2，也不要随便挑一张 ramp 声称原效果。预览 SSS、组合/默认迁移仍待办。动态默认仍关，裙装不重新展开。

# 第三十二批：按原编译着色器修正发色混合

新增只读 `tools/inspect_source_hair_shaders.py`，使用现有 UnityPy 环境及 Windows D3DDisassemble，提取源 `main_hair/main_item` 各 14 段 DXBC 汇编、属性表、完整 parsed 参数绑定和源 SHA256。证据在外部 `characters/source_hair/koikatu/shaders/`。UnityPy 的普通 export 不支持 DXBC，只有属性表，不能据此声称已经读到着色计算。

`main_hair_13.asm` 的 FORWARD 像素程序，经 parsed 中名字/寄存器表核对：t3=ColorMask，cb0[12/14/15]=Color/Color2/Color3。从白色依次按遮罩 R/G/B 混色，再乘 MainTex。此前 importer 忽略 R，且人为将 G/B 压暗到 0.67/0.82；本轮改成原三色和原混合顺序。关闭染发恢复每个源颜色，当前一个发色控件开启时统一染三通道；尚未新增独立根梢调色控件。没有改源网格或骨骼。

其余已定位但未完全移植的通道：t0=NormalMap，汇编从 A/G 解码法线 XY 并重建 Z；不能把原 PNG 当常规 RGB 法线。t4=HairGloss，按原 UV2 及光照/视角扰动进行双采样；t5=RampG、t6=AnotherRamp、t7=DetailMask，G/B 参与照明/边缘光衰减。RampG 和 ambientshadowG 是编译绑定中的运行时全局，普通材质属性表不完整。下一步据此补源全局纹理/UV2与细节照明，不把 DetailMask 简单当 albedo 相乘。

三款资源重烘焙 exit 0；发型回归新增三颜色恢复原值检查，既有换发/染发隔离/身体身份/6 动作挂点及发饰纹理检查通过。`source_hair_material_02/` 9 张捕获完成，已观察马尾侧面、长发正面，无本轮明显新错位；灰发为测试色带 18，并非源默认色。头发光泽尚是现有 Godot 近似，不宣称原游戏材质完全还原。

下一步继续原全局材质数据和 UV2/光泽，再处理透明预览 SSS 差异及组合/默认迁移；动态仍默认关。裙装继续保持本轮收口。

# 第三十一批：恢复源马尾发饰的明暗纹理

确认 `p_cf_hair_b_06` 原蝴蝶结材料具有 `_MainTex`，原图保留织物明暗/折痕，而当前 importer 的非头发分支只返回基础色。本轮恢复原图到 StandardMaterial3D albedo，保留原 tint；同时将原纹理 scale/offset 转换到已翻转 V 的导入 UV。未改任何源顶点、法线、权重或发骨，未凭名称猜测法线压缩与 DetailMask 通道语义。

`bake_source_hair.gd` 重新生成三款运行时场景，exit 0。`test_source_hair.gd` 新增实际烘焙资源中发饰纹理存在、明暗非纯色、染发保持发饰颜色/纹理身份检查；与原实例隔离、身体不重建、动作挂点检查共同通过，exit 0。`capture_fitted_source_hair.gd` 支持独立捕获目录，避免覆盖第二十七批证据；9 张新图位于 `source_hair_material_01/`，已人工查看马尾背面及侧面，无本轮新增的明显贴图错位。该距离纹理细节较弱，不据此宣称还原原游戏全部材质效果。

尚缺：头发 DetailMask/光泽、发饰法线/其他遮罩的原语义确认，透明预览禁用 SSS 导致的质感差异，头型/头饰/外装组合与默认迁移。动态及接触仍默认关闭。下一步继续这些资源/渲染缺口，不重开裙装求解器。

# 第三十批：源短发/马尾动作检查与真实创建页配方入口

继续按用户确认的原则：优先恢复原游戏的装配和参数，不修改源发型网格来掩盖导入问题。

`capture_source_hair_actions.gd` 新增 `--hair=202|203`。短发、马尾各完成实际共用 Model 的行走/坐下 12 张捕获（原生弹簧及接触显式开启），进程均 exit 0。人工复查各款 `walk_030_side.png` 与 `sit_chair_099_back.png`：未见明显大片穿肩、拉伸尖角或脱离头部；不能将这四张图推断为全部动作/全部表面无穿透。目录 `source_hair_actions_01_202/`、`source_hair_actions_01_203/`；没有摆放椅子，不属于座椅接触验收。马尾发饰仍为简单基础颜色，完整贴图/光泽没有完成。

`character_hairstyles.gd` 集中版本化发型选项：新女性身体 201/202/203 与 0 卸发，旧身体保留旧 ID。实际 `character_create` 读取同一列表和随机规则；显式新身体配方时不显示尚未支持的胸围滑杆。没有全局切换默认女性身体；需要先补外装、形态及完整动作缺口。

`test_source_hair_creation.gd` 实例化真实创建场景，显式注入 `female_base_v2`，验证主预览与头像同时切换/卸发且保持身体实例、配方 JSON 往返、随机只选新发型、男女版本兼容，exit 0。透明预览仍报告 Godot 不支持透明背景下 SSS 的警告：逻辑验收通过不代表头像与灯光场景的皮肤质感完全一致，后续材质/预览验收保留此检查点。

下一步：发饰及头发材质通道还原、预览光照一致性、头型/头饰及外装组合；动态与碰撞运行时默认仍关闭，不能把测试显式开启写成默认已上线。裙装本轮收口，不重新调求解器。

# 第二十九批：源身体接触适配、碰撞列表刷新与长发动作检查

新增 `fit_source_hair_colliders.py`，从上轮保留的 24 个女性源碰撞体中选取当前头发相关的头、颈、左右肩和上背共 6 个球/胶囊。保留源中心、方向、父链缩放和里外约束，按骨架身高比例做初始尺寸转换，映射到当前身体 head/neck/chest/左右 Collar；左右通过源世界位置转换后确定。源和目标的骨骼休息轴不同，端点方向先在统一坐标系中保留，再转进目标关节局部，不能直接把源 local XYZ 套在当前 Collar 上。输出 `hair/female_base_v2/body_contacts.json`，明确为待区域表面覆盖验收的候选，不声称所有 24 个碰撞体都接入。

`character_source_hair_spring` 为每个原生模拟器创建同一组碰撞体，随最终身体骨骼快照同步，球用退化胶囊表达；世界变换不带节点缩放。发型/身体实例回归通过。

第一轮开关完全无差异：15120 次端点—碰撞体样本，开启和关闭均最深 71.89 mm、74 次超过 1 mm，失败保存在 `source_hair_contacts_01/particle_audit_no_cache_refresh.json`。发现只调用 `set_enable_all_child_collisions` 切换没有刷新当前缓存列表；改为清空/重建显式 collision path 列表后，第二轮固定 60 fps 对照生效：关闭最深 **60.635 mm**、40 次超过 1 mm，开启最深 **4.916 mm**、6 次超过 1 mm，各 15120 样本。第二轮也含上述休息轴修正，不能拿第一轮和第二轮的关闭数据变化单独归因缓存；因果对照是第二轮同一次运行开/关。结果在 `particle_audit.json`，`test_source_hair_contacts.gd` 通过。

源 API 说明碰撞体必须是模拟器子节点，模拟器按设置列表处理：[SpringBoneCollision3D](https://docs.godotengine.org/en/stable/classes/class_springbonecollision3d.html)。本次保留内置求解器，仅修接入，不改引擎或自行扩写接触算法。

### 画面范围与下一步

`capture_source_hair_spring.gd -- --contacts` 固定 60 fps 捕获 10 张开关对照，检查了转头/仰头与停止后画面。另新增 `capture_source_hair_actions.gd`，**实际共用 Model 的 walk/sit_chair** 轨道驱动原长发，生成 12 张侧/背图于 `source_hair_actions_01/`；已观察 walk_030_side、walk_099_back、sit_chair_099_side/back，未发现明显大片穿肩或碰撞推起的尖角。坐姿捕获用于头发，未提供真实座椅，不是椅子接触验收。其余图片生成不等于全部人工审查。

4.9 mm 是发骨端点相对候选胶囊的重叠，**不是头发网格相对身体的穿透深度**，不能混用。按用户轻微穿模可接受的要求，记录残余而不追求计数归零。当前确认原长发在本轮姿态下的候选效果；短发/马尾、头型形态与帽饰、身体外层衣服仍须另验。动态与碰撞默认仍关闭，先补另外两款和入口配置再决定启用，不把此次长发检查表述成所有人物验收完成。

# 第二十八批：复用 Godot 原生发骨弹簧，仍保持实验开关

本机 Godot 4.7.2 的 ClassDB 确认具有 `SpringBoneSimulator3D` 和 `SpringBoneCollisionCapsule3D`。官方文档说明它支持回归原姿态的骨链惯性，但不支持 Y 分支链，且缩放骨架会影响结果：[SpringBoneSimulator3D](https://docs.godotengine.org/en/stable/classes/class_springbonesimulator3d.html)。因此没有扩写旧三根辅助骨骼的自制弹簧求解器。

`source_hair_builder` 现在保留源 DynamicBone 的根/末骨链和完整配置元数据。所选原前后发的动态链没有 Y 分支，短后发 b_03 原本没有动态链，不强行添加。`character_source_hair_spring.gd` 在每个人物实例中把头型适配变换烘焙进原骨骼休息位置及 Skin 绑定，让运行中的发骨无缩放；保留原顶点、权重和骨链数量。逐绑定重构误差须小于 1e-5，原身体仍为 80 骨，不随发型增减。蒙皮 AABB 也根据绑定后位置重算。颜色/卸发/双实例隔离回归通过。

弹簧采用 Godot 原生节点，源阻尼保留；刚度采用显式实验基线 1.0，**两个引擎方程不同，未把源 stiffness=0.1 数字原样贴上后声称等价**。源重力为零。当前 `dynamics_enabled=false`，只在验收脚本显式开启；未通过真实接触前不改变正常角色默认效果。

验证：`test_source_hair_spring.gd --fixed-fps 60`，原长发的 60 根前后发骨，35° 往返转头，关闭负例位移 0；开启最大骨位置偏移 0.3454755 m，停止后 0.00014448 m，骨链长度误差最大 6.71e-8 m，通过有限值/无拉伸/惯性存在/收敛检查。最初测试误用统一 25 cm 位移阈值触发失败，不能把长链旋转位移直接判为“爆炸”；未为通过测试限制发梢位移，改为检查实际骨链长度与收敛。这个测试不证明发片表面无穿模。

`capture_source_hair_spring.gd` 产出开关对照 10 图于 `source_hair_spring_01/`，已观察同一反向转头帧及停止后画面：发梢确有惯性，停止后回到原造型。捕获采用实时帧，不是定时测试；未把它当跨帧率一致性证据。当前画面无肩背接触求解，六动作数值随动仍不等于行走/坐下动态验收。

还查清一处重要装配条件：源 `ChaControl.LoadCharaFbxData` 会收集 `objBodyBone` 上所有 `DynamicBoneCollider`，清空发型占位碰撞列表再填入身体碰撞体。因此只读发型 prefab 中的空碰撞引用，不能认定源游戏没有接触。提取工具新增 `body_collider_reference.json`，完整保留女性 `p_cf_body_bone` 的 24 个原胶囊/球体配置和父链（包括原 radius=0 的记录）。**下一步按当前身体骨骼和尺寸适配这些源身体碰撞体，连接原生碰撞节点，再检查发片与肩背、转头/行走/坐下；不能直接套旧 Mixamo 的固定胶囊坐标。** 原生胶囊已确认存在但当前未接入。

# 第二十七批：原始发型进入共用人物，并修复遗漏的源挂点链

`character_source_hair.gd` 作为分轴身体的独立发型挂件，由 `character_axis_rig` 管理，读取现有 `part_ids.FrontHair1` 和原发色色带。201=源长发、202=源短发、203=源马尾，0=无发；未重新解释旧 10–15 ID。换发只替换发型，改色复用发型，身体仍为原 80 骨骼，发型保留原始独立骨链，随 `surface_updated` 的最终头部快照更新。**不是另一套人物系统，也未启用全局默认替换或完成 UI 选项。**

原 `capture_source_hair` 的网格/骨骼读取提炼到离线 `source_hair_builder.gd`，`bake_source_hair.gd` 烘焙 3 个外部 `.scn`。运行时不读 Unity 或源游戏。原材质色罩用于根/中/梢变色，材质参数逐人物独立；Godot 光照响应是当前近似，未声称复现 Unity 原 Shader Forge 全效果。发饰目前原基础颜色，完整贴图/细节通道仍待补。

### 本轮实际发现并修复

第一版实际佩戴的刘海压到眼/鼻，失败证据保留于 `source_hair_fitted_01/`。**没有剪短刘海或改源网格。** 从本地程序集只读核对 `ChaReference.RefObjKey.HairParent=1`，`CreateReferenceInfo` 把该键指向 `cf_J_FaceUp_ty`；`ChaControl.LoadCharaFbxData` 以其为父级。源骨架完整链 `p_cf_head_bone → cf_J_N_FaceRoot → cf_J_FaceRoot → cf_J_FaceBase → cf_J_FaceUp_ty` 累计约 `(0, .05, .006)`，之前用头模直接适配漏掉此变换。

现在 `extract_head_reference` 从原 `bo_head_00` 读取源头模，从 `oo_base` 读取完整父链及源哈希；运行时先恢复源挂点链，再做基于目标头部尺寸的适配与最终头部随动。坐标不是按每款发型手工上移。重拍 `source_hair_fitted_02/`，3 款正侧背 9 图；已观察长发正侧背、短发正背、马尾正侧，眼部遮挡明显恢复到原刘海形状，未出现整片压过双眼的旧问题。剩余两视角不据文件存在认定已人工复查。

### 验证和范围

- `test_source_hair.gd` 通过：换发/卸发、改色保留发型、双人物材质隔离、身体/皮肤实例不变、80 身体骨不变、6 类动作最终头部随动、显式头部转动。
- `test_axis_character_model.gd` 通过：已有 Model/NPC/View、装备/颜色身份、布料回暖姿态保存、混合后表面及支撑不回退。
- 此轮尚未加发梢惯性/肩背接触、完整发饰贴图、头型形态组合、真实入口 UI 和配方选项；因此不是动态换发最终验收。长发当前随整个头部，动作六类是数值挂点验证，不是全部动作视觉通过。下一步继续原生骨链动态与接触，并补可选入口；先复用已调研弹簧/碰撞实现，不再改原网格补偿导入错误。

# 第二十六批：按用户要求改用 VaM / Koikatu 原始发型

用户明确旧发型有问题，改从之前提供的两个游戏获取。停止旧生成网格的 `bake_axis_hair.gd` 失败试做进程，移除该未完成工具；没有把试做网格接进新人物。共用颜色 ID、配方、人物入口仍应复用，但不能据此继续沿用旧发型几何。

- `tools/extract_source_hair.py` 使用已有外部 UnityPy 环境，只读 `Koikatu/abdata/chara/bo_hair_f_00.unity3d` 与 `bo_hair_b_00.unity3d`，提取各 01–06 高模 prefab。保留对象层级、原 TRS、全部原蒙皮网格、UV、权重、绑定矩阵、材料属性和纹理、源 SHA256。Unity 64 位引用保存为字符串，避免 Godot JSON 浮点精度丢失造成串骨骼/材料。
- 外部目录 `assets/characters/source_hair/koikatu/`，12 个部件，不代表 12 套完整已选定发型。`tools/capture_source_hair.gd` 按原骨骼恢复并以同编号前后发临时组合，18 图在 `review_artifacts/character_3d/source_hair_01/`。观察了长发、短发和马尾；此捕获使用统一检查材质，不是原游戏最终质感，也没有人体，不能作为适配通过证据。0=后、1=侧、2=前；长发有部分超出当前取景，下轮应按实际包围盒构图。
- `tools/audit_source_hair.py` 检查引用、有限坐标、骨权重与原生 rest-bind 一致性。11 个 prefab 最大矩阵误差约 4.18e-7；`b_02` 约 0.416，完整审计**未通过**。这可能是原 prefab 预制姿态，尚未定位，不能直接归因导出损坏或强改绑定让数值通过。原始数据完整保留、该款隔离待查。
- VaM `A1X.CASANDRA_HAIR.1`、`A1X.HEROIN_HAIR.1`、`AKKEVE.hair_002.2` 原始 `.vam/.vaj/.vab` 与缩略图、meta 已解出到 `assets/characters/source_hair/vam/`。前两者元数据 CC BY-ND，后者 CC BY-NC-SA，保留来源与元数据，不标成可自由商用资源。已确认是发丝模拟数据；没有把 `.vab` 冒充可直接加载的三角网格。

**下一步：** 优先 Koikatu 的长发/短发/马尾，按新身体头部标志与源头部挂点适配，保留源版型与完整骨链；补原材质解释、实际头部随动、独立动态状态、肩背接触和配方重载。先在共用 Model 灯光场景检查正侧背与动作，再接正式换发；不要回头修旧生成发型，也不要把当前提取阶段写为换发完成。裙装保持上一轮收口，Go/正式地图/性能/MMD 顺序不变。

# 第二十五批：新身体进入共用 Model / View / 玩家 / NPC 链路

新身体不再只能由灯光工具直接创建。`character_axis_rig.gd` 已适配已有 `character_model_3d` 的配置、动作、混合、改色、换装和时长接口，`character_view_3d` / `create_npc` / 玩家外观更新继续走同一个 Model。`Customization.body_model` 保存版本 `female_base_v2`，旧配方空值保留现有角色；字段参与现有 JSON 往返，不增加独立人物存档。**这是显式版本迁移入口，尚未切换全部女性默认值，也没有宣称全部人物资源完成。**

动作混合后再次把最终旋转/角度参考同步给皮肤，再按混合后的真实表面修正支撑。颜色和装备更新复用身体、骨架及衣柜，保持 action / elapsed；正式装备快照的 `SurfaceEquipment` 驱动新衣柜，可独立装卸内衣。头顶文字以新身体当前头部控制表面计算顶点，避开旧空 gear 表导致的头部中心定位。三维世界资源入口检查也按身体版本选择，不再一律要求旧女性 GLB。

另外修正布料预热的姿态保存：原 `warm_start_cloth` 读取测试请求 `angles_by_name`，动画驱动并不更新这个字段；现保存最终节点角度并恢复同一表面，同时保留原请求元数据。回归用隔离的 cloth step 替身检查 80 步预热前后皮肤、人物位置和请求不变，**只证明姿态恢复，不把它当成复杂裙物理验收**。

复用 UAL1 增补 `attack=Punch_Jab`和 `sit_chair=Sitting_Enter + Sitting_Idle_Loop`，外部 `female_base_v2_universal.res` 现共 7 类动作。源身体/服装网格不变。未知动作在适配器明确拒绝、每类只报告一次，保留上一动作；没有用静止站立或旧身体假装支持。`sit_ground`、剑击变体等仍缺。

验证证据：

- `test_axis_character_model.gd` 通过：配方保存/恢复、同身体增量改色和装卸、NPC 实例隔离、头像 View、实际 `player_appearance.apply_gear_look` 装备快照、动作混合后骨骼/皮肤位置误差 0、支撑和头顶文字。衣柜预热姿态恢复通过。
- `test_world3d_flow.gd --axis-body` **实际 mocker 流程通过**：创建带版本的角色 → Loading → 三维世界 → 解锁操作；新身体进入真实玩家 Model；从背包装上两件内衣、通过 equipment_update 卸上装、下装保留，人物实例不变；HUD、事件和分地图状态原回归也通过。不是只测 `Model.create` 推断整个流程。
- `test_axis_animation_history.gd` 以新 7 动作完成 **49 组**切换/跳转，皮肤差异 0，负例差异约 80.98 mm，循环前 1 ms 接缝约 0.493 mm。
- 旧 `test_character_motion`、`test_character_customization`、`test_character_overhead`、默认 `test_world3d_flow` 均通过。
- `capture_axis_character_model.gd` 通过正式 Model 拍摄 13 图，证据 `axis_model_01/`；观察自然站立、行走、刺拳、坐姿侧面和过渡。没有以灯光场景直接身体路径替代正式适配器验收。坐姿图未放实际椅子，仅证明源片段接入，手部仍偏悬空，不算坐椅接触完成。

**明确缺口和下一项：**

1. 正式默认和创建 UI 尚未迁移；新身体头发、角膜/睫毛/口腔、形态参数和男性资源仍缺。当前 `bust_size`/发型字段被保存在同一配方，但新适配器尚未消费，不能把它们称为生效；上线前必须补真实功能及控件能力约束。
2. SurfaceEquipment 已接快照，但当前只有内衣物品定义有新身体资源映射。已有初始衣裤/靴子/武器等旧数值装备尚未适配；不能因 Model 可用就打开默认新人物并让装备消失。需接新服装与武器资源及动作变体，保持源版型，不返回旧底模。
3. `sit_ground`、完整战斗、自然躺下/起身及椅子/衣服连续接触未完成。2D View 的新身体步速匹配还未接，3D 角色已有外层实际位移速率，但新源动作与速度仍需验收。
4. 完整 world flow 退出时有 1 个 ObjectDB RefCounted 警告；新身体模式和旧身体默认模式均能复现。旧模式 verbose 指向引用计数为 0 的 RefCounted，尚未定位生命周期源头；按用户要求记录，不能将两条流程报告为无任何警告。

下一轮优先补新身体发型和服装/动作能力映射，让共用入口承接完整人物能力；再做默认迁移与创建/选角界面实机验收。不要重写新的玩家系统，也不重开 HW 裙最后一轮调参。Go 持久化、正式地图继续暂缓。

---

# 第二十四批：新身体的平面支撑与视觉根高度

针对第二十二/二十三批的足底下沉和倒地约 9.7 cm 穿地，`character_axis_animation` 现在在当前皮肤变形完成后，按完整控制表面最低点修正独立视觉根高度。只抬升低于支撑面的部分，保留动画本来的腾空，不每帧把脚吸回地面。骨骼、关节长度、原身体/内衣、动作旋转与角色逻辑坐标都不变。`support_enabled` 可关闭以保留失败对照，`support_height` 为视觉根局部坐标中的平面高度，默认 0；非法高度拒绝采样。

这是真实身体表面的视觉支撑，不是只看脚骨高度；也是平面约束，**不是地形 IK、鞋底/裙摆碰撞、全身压力分布或躺姿重设计**。世界地形高度应由正式人物父节点提供，不能把此偏移写进服务器移动。身体表面贴地并不保证衣服也与地面完全无交叉；轻微内衣边缘误差按用户容忍度记录。

`test_axis_animation_support.gd` 对 5 动作各 61 点，共 305 点同时检查关闭/开启支撑：

| 动作 | 关闭时最低点 | 开启后最低点 |
|---|---:|---:|
| idle | −1.334 mm | 0 |
| cast | −2.039 mm | 0 |
| walk | −12.869 mm | 0 |
| dash | −16.666 mm | 0 |
| death | −97.293 mm | 0 |

表面数组与骨骼旋转前后完全不变，横向位移不变，任意非零角色锚点保持原值；46 个腾空采样点未修正，另用 0.35 m 支撑高度验证不是写死世界零点。测试通过。`capture_axis_support.gd` 同一灯光/内衣生成 16 张原始/修正对比图，已观察倒地整体与髋部近景、行走足部和跑步腾空。证据 `axis_support_01/report.json` 及同目录图片，原 `axis_animation_02/03` 不覆盖。

**仍未完成：** 源死亡片段有躯干拱起/双臂外展，视觉抬升只解决穿地，不能将其当作用户要求的自然睡躺；后者已有 `lie_relaxed` 单独姿态，完整过渡还缺。鞋底与裙层支撑、斜坡/台阶、后续 IK 修改后的接触、完整战斗仍待办。正式人物默认入口仍旧。

**接下来直接推进统一人物入口适配**，不要下一轮重新做平面最低点工具或 HW 裙调参。已确认正式模型入口 `character_model_3d` 的 `configure / set_equipment / play / pose_at / _apply_blend / action_duration` 需接分轴适配器；动画混合后必须再次同步皮肤与支撑，避免只插值骨骼。沿用同一 `Customization`、装备快照、Model/View/玩家/NPC 入口；版本化选择用于迁移验收，最终不能长期把新身体留在灯光场景。已有 5 基础片段可复用；攻击/坐姿、发型/形态等缺口需要明确补齐，不以旧底模回退或静止站立冒充支持。

额外接入风险已记录：`character_surface_wardrobe.warm_start_cloth` 目前读取 `body.angles_by_name`（测试姿态请求），正式动画驱动后应保存当前最终节点角度/快照，否则启用实验布料可能把已播放动作恢复成旧测试姿态。修复属于人物接入，不重新扩大裙装求解器范围。

---

# 第二十三批：修正动作历史导致的手臂扭折，复用自然待机

第二十二批左侧画面的肘部凸起不是只需换一个待机姿态。完整播放倒地再回待机后，rForeArm 的分解由约 `(0.84, -26.44, 0.33)` 度变成 `(180.84, -206.44, 179.67)` 度；骨骼矩阵等价，但原分轴部分权重的皮肤变形不等价。只检查骨骼矩阵、有限顶点、关节长度，甚至 CPU/GPU 一致，都检不出这种播放历史污染。

已在现有离线重定向工具中，为每个片段烘焙 `AxisAngles:<bone>` 连续角度参考。运行时按当前片段/时刻读取参考，再从最终骨骼姿态选择对应分解；随机跳转、回放和动作切换不再继承上一动作的绕圈状态。旧的无角度参考资源安装时明确拒绝，不能静默退回不确定行为。未映射的辅助骨骼归静止参考。`female_axis_body.sync_final_pose` 同时检测分解变化，即使骨骼矩阵未变，也必须重新计算皮肤。SkeletonModifier 的已有最终姿态路径继续使用原连续规则，不把离线角度强行写回骨骼。

自然待机复用已有 `character_animation_library` 的方向对齐方法，双臂下垂、手指保留 25% 原弯曲，腿回到自然支撑位置，脚骨高度差通过视觉根位移承接，不改关节长度。不以衣服包围盒抬手避碰；旧失败站/坐/躺输入和裙装求解器不动。抽出的 `align_bone_toward` 同时服务旧人物与新身体，避免两份方向算法漂移。

验证：

- `test_axis_animation_history.gd`：5 动作完整采样后交叉跳转，共 25 组，身体表面一致误差 0；相同骨骼矩阵但刻意额外绕一圈的负例产生约 80.98 mm 差异，恢复参考后还原，证明检查覆盖皮肤而非只查骨骼。旧无参考库被拒绝；循环接缝前 1 ms 到起点的最大表面位移 0.493 mm，没有矩阵闭环但皮肤跳变的问题。
- `test_female_final_pose.gd`：最终 Modifier / 直接骨骼 / CPU-GPU / 挂点 / 复位 / 非法缩放拒绝通过。
- `capture_axis_animations.gd`：155 个采样点、循环与关节位置检查通过，60 张正侧背图保存于 `axis_animation_03`。已复看待机前后、行走肘部，第二十二批明显扭折消失，待机自然垂手。原 `axis_animation_02` 不覆盖。
- `test_character_motion.gd`：最初女性跑步循环失败是测试沿用旧 `Motion.DURATION`，未消费已选 `dash_female` 的 1.25 倍速片长。改用已有 `model.action_duration()` 后，男女行走/跑步循环、动作过渡、倒地保持及八方向构图通过；没有放宽循环误差阈值。

**仍待办：** 行走等源片段握拳仍偏紧；新身体足底约 1–2 cm 的支撑误差及倒地约 9.7 cm 下沉仍存在，当前只修了动作历史和自然待机，不能宣称所有动作完成。完整战斗、武器、躺下起身、正式入口、发型/面部/形态等保持原计划；新身体尚未默认切换正式玩家。下一项继续动作支撑与统一适配，裙装最后一轮不重开。

---

# 第二十二批：新身体的基础动画重定向与未通过项

裙装最后一轮已在第十九批收口，本批没有继续调整 HW 布料。复用 `retarget_universal_animations.gd --axis-body`，把 UAL1 的 idle / walk / Jog_Fwd_Loop / death / cast 重定向到已认可的 `female_base_v2`，输出外部 `assets/characters/animations/female_base_v2_universal.res`。旧男女资源与默认生成路径不变；没有增加一套动画来源或修改服务器移动。

映射 52 根骨骼，保留目标骨长、原轴权重及关节增量变形。髋部平移烘焙为独立 `VisualRoot:position`，采样器返回 `visual_offset`，由上层视觉根节点消费，禁止写成局部关节平移或服务器位移。`character_axis_animation.gd` 在安装时验证骨名/轨道类型，拒绝旧 Mixamo 库，应用后通过已有 `sync_final_pose` 同步身体与衣服。它目前仅由验收工具消费，**尚未替换正式角色渲染器，也未接完整战斗动作、武器、动作过渡**。

首次实拍 `axis_animation_01` 检出左右骨名约定相反，手臂被翻到头顶：当前身体 rShldr 在 +X，UAL upperarm_l 在 +X。修正为同侧空间位置对应，并增加肩/大腿静止位置断言，不能只按 l/r 字母直译；后续武器挂点也须遵循这套实际位置。修正证据在 `axis_animation_02/`，原失败画面保留。

验收工具 `capture_axis_animations.gd`：5 类动作各 31 个时间点，实际 GPU 身体与内衣、关节位置不变、输出有限值、人物实例不变、循环端点一致、未知动作和旧库拒绝。捕获四个关键时刻的正/侧/背面；倒地按身体边界调整镜头，避免将出画区域当作已观察。结构检查和视觉验收分开，不能把 PASS 解释为整套动作已合格。

**记录待修，不伪称视觉完成：**

- 待机沿用 UAL 源姿态，握拳偏紧、站距较宽，仍需自然垂手与手指放松适配；不能为了裙子避碰再抬手。
- 实拍左肘有明显锐折/局部凸起；需核对前臂旋转、分轴变形与原关节增量，不通过删身体或遮挡修复。
- 全采样最低表面高度：idle −1.97 mm、cast −2.04 mm、walk −12.87 mm、dash −16.67 mm、death −97.29 mm。旧工具按脚骨支撑高度修正，尚不能保证新身体皮肤表面落地；倒地约 9.7 cm 下沉必须修。轻微误差按用户容忍度记录，不再追求全部零穿透。
- 当前只有 5 类基础片段，不含攻击/武器挂点、完整躺下起身、转场、与裙装组合及远端角色验收；正式统一入口迁移仍待继续。

下一项按已有计划继续统一角色适配及缺失资源；裙装剩余问题保留，不重新开启同一坐姿求解器循环。性能与 MMD 优先级保持不变。

---

# 第二十一批：新身体消费统一的肤色和瞳色配方

新身体此前只使用固定贴图，没有读取已有 `Customization` 的 `skin_row`、`skin_on` 和 `eye_color`。现已通过 `character_regional_skin.apply_colors` / `female_axis_body.set_colors` 接入原保存格式，不新增第二套颜色编号或预览专用存档。原灯光场景提供肤色色带、瞳色及恢复原色控件；旧角色对照也消费同一份颜色配方。

皮肤以已选瓷白贴图为默认，统一使用相对于默认色带的线性颜色比例调整面/躯干/四肢，保留原色差、法线、粗糙度及高光图。瞳色只更新 Irises 独立实例材质，保留原虹膜明暗纹理，Pupils/Sclera 不染色；清空眼色恢复原图。ShaderMaterial 的区域标签随分轴展示材质迁移，防止静态与动态路径失配。

验证 `test_female_body_colors.gd`：既有配方 JSON 往返、100 次连续改色、16 皮肤面/独立虹膜、眼白瞳孔排除、静态/动态参数一致、两个人物互不串色、关闭及非法值恢复、真实 UI 信号均通过。身体/骨骼/网格/材质/衣柜实例及身体位置纹理在改色前后保持一致，缓存没有持续增长；不是借每次重建人物实现改色。原 `test_character_skin_studio.gd` 回归通过。

`capture_female_body_colors.gd` 在棚拍/游戏两灯光下捕获原色、深肤/绿瞳、原肤/蓝瞳及恢复原色，各有脸和全身，共 16 图于 `body_colors_01/`。已观察脸、颈、手臂和全身一致改色，眼白未被染色，默认瓷白未变。四个恢复原色截图与同条件原图逐字节相同。源纹理没有重绘或替换，深肤图是主动选择色带 5 的测试。

这完成新身体的两类颜色参数，不是完整捏人或正式玩家已迁移。`character_model_3d` 仍用旧 ImportedRig；接入分轴身体还需处理旧动画的 Mixamo 骨名/局部平移与新骨架的差异，新身体目前拒绝关节平移/缩放，不能直接套旧动画轨道。头发、角膜/睫毛/口腔最终材质、形态与正式统一入口仍按盘点继续。裙装不重开本轮调参；Go 持久化和正式地图仍暂缓。

# 第二十批：推进躺稳姿势，修正双手朝向与指节

按用户“裙装再一轮后推进下一项”要求，已转入躺姿支撑，不再修改本轮 HW 站坐条件。保留 `lie` 的原碰撞姿势，调整独立的 `lie_relaxed`：前臂旋后使双掌朝上，手指三节分别轻屈，颈部与头部反向小幅调整使后脑更接近支撑面。没有改变身体拓扑、关节长度或衣服求解来隐藏穿模。

实拍发现必须单独记录的骨架细节：这套源骨架两前臂的旋后 X 角采用同号；简单左右取反，会一只手露手背、另一只露手心。手指屈曲的 Z 方向与最初放松姿势的猜测相反。第二版近景确实检出这两处错误，第三版修正后双掌一致朝上、指节自然轻屈，不以幅度值对称当作美术正确。

`capture_relaxed_lying.gd` 在原灯光、默认白色内衣下捕获原/新姿势四个幅度的侧面/俯视，另加白模床侧面、头部及左右手近景，共 24 图。最新证据 `lying_support_03/`；保留 `lying_support_02/` 失败朝向对照。CPU/GPU 对照误差小于 0.6 微米，输入姿态没有被衣服回写。新躺稳后脑表面离支撑约 2.14 mm，左右手最小间隙均约 19.07 mm，取代原躺姿手部约 145 mm 的悬高；双手掌心与上方向点积约 0.993。手背附近的小间隙不宣称为软组织已压实接触。

已观察第三版床侧、头部、左右手及地面视角；互动场景控件回归通过。**此项只完成躺稳姿势本身的本轮调整**：四个“幅度”只是关节检查，不是自然站立→躺下/起身动画；连续支撑转换、穿裙躺下、床上交互及正式动作重定向仍待接入。后续转回资源和统一人物配方缺口，不重开本轮裙装求解器调整。

# 第十九批：裙装最后一轮与剩余问题归档

用户要求再调整一轮，仍有问题留档并直接推进下一项。本批完成后停止对 HW 同一坐姿继续试参，转到躺姿头手和支撑检查。**停止本轮优化不是整裙通过验收。**

先对照原衣服 47,036 条弯曲连接与插件的三角邻接推导，保持原网格、动作、材料柔度和接触配置；`source_bending` 站姿最大边长比 1.1740、无过度拉伸，坐稳却为 2.1121、6 条过度拉伸边。坐姿尖折未改善，开关继续关闭。证据 `candidate_source_bending_hw_*`，与已补内衣/源透明度的同版基线 `candidate_visual_current_hw_*` 对照。

最后一轮 `target_time` 修正外部跟随目标提前到整帧末的问题：此前身体碰撞按子步插值，但附件目标始终读取末帧，导致两者不在同一时刻。新增可关闭的外部目标插值，原生蒙皮不受影响；warm start 重置历史。直接执行生产预测 shader 的六项固定/混合粒子、开关及不同子步时刻对照通过；集成补丁在固定上游重放通过。

完整原站立→坐下 130 帧捕获完成，身体姿态断言保持不变。站姿最大边长比 1.2011、过度拉伸 0；坐稳 1.89985、过度拉伸 7，抽样身体/手/场景穿透仍为 0，自交 670 对、共面 2 对、退化面 0。**实际正侧面仍有明显尖折，未优于基线**，所以不作为默认升级，`interpolate_external_targets` / `interpolate_targets` 保持关闭。几何严格报告返回 false 保留作诊断，没有通过删身体、改站姿或加硬衣料来改数字。

后续待办及明确复现：

| 未完成项 | 现象与证据 | 本轮处理 |
|---|---|---|
| 坐姿多层荷叶边 | `candidate_target_time_hw_sit_front.png` / `_side.png`：膝盖上方及两侧堆叠、尖折；`candidate_visual_current_hw_*` 为保留基线 | 留档；不再阻塞下一项 |
| 源版型的展示平滑 | 源 WrapControl 有 smoothIterations=1，当前控制网格直接展示；尚未核对显示平滑与动态层间问题各占多少 | 留待明确来源算法后处理，不能将表面平滑冒充碰撞修复 |
| 其它裙与动作 | 女仆、百褶、长裙等及抬腿、躺下、多件接触没有本轮候选后端的完整验收 | 不将 HW 站坐结论外推 |
| 实际衣柜后端接入 | 原交互衣柜仍走 `garment_cloth_gpu.gd`；候选适配器目前由验收捕获工具驱动 | 统一入口仍是待办，不能称生产已应用 |
| 正式换装/捏人 | 新身体仍在灯光场景，创建、选角、玩家、NPC 尚未统一迁移 | 后续继续，Go 持久化仍暂缓 |

`test_target_time.log`、`candidate_target_time_hw_shader_manifest.json` 和最终 `candidate_target_time_hw_sit_audit.json` 对应本轮；源码/证据归档在 `checkpoints/skirt-final-round/`。离线 C-IPC 原进程仍单独运行，不是新的实时方案，也不是继续人物工作的前置条件。

# 第十八批：可卸换的内衣装备槽与裙装验收标准收敛

用户明确内衣必须是正式装备槽、可更换和不穿；本批新增 `underwear_top` / `underwear_bottom`，沿用原背包、mocker 装备事务、equipment_update 和快照。物品定义同时提供旧模型层和按身体版本索引的 surface_parts，新表面衣柜直接消费相同快照。测试场景上/下装可分别卸下，切换外装、旧/新身体对照不会强制补回。新身体整体正式入口仍未迁移，不能将本批称为人物链完成。

女性默认验收资源：maru01 的文胸及 Poli5 的完整三角内裤（本地包声明 CC BY），保留原源文件、网格、UV、贴图和来源哈希；使用白色材质与不透内衬。原先选中的 maru01 下装背面是丁字款，已从默认配方排除，保留于第一轮诊断证据。贴身内搭遵循源 simEnabled=false，衣柜布料预热不会误把它变成自由裙料。男性新资源未因此完成。

`test_underwear_equipment.gd` 已通过：错误槽位拒绝、背包装备、替换回包、单独卸下、全卸、不随外装恢复、旧渲染和新表面配方共用快照。`test_equipment_server.gd` 原流程回归通过。`test_surface_wardrobe.gd` 实机通过内搭状态保持和实例复用。`capture_underwear_equipment.gd` 实际打开正式装备栏并经槽位信号卸下文胸，确认服务器、背包和模型可见性一致；修复新增槽被窗口裁切，以及原装备格 setup 时尚未入树就读取图标的错误。最终捕获日志无该错误，截图 `underwear_equipment_panel.png`。

原灯光场景捕获站、抬臂、抬腿、坐、原躺和放松躺共 18 张正侧背图于 `underlayer_lace_02/`；已观察站正背、抬腿/坐正背侧、躺俯视/侧面，遮盖完整，无黑色替代面。旧严格几何诊断仍非全过：文胸站姿 0 个 >3 mm 体内样本/0 手交叉，但小褶边有自交和拉伸；内裤坐姿 11 个 >3 mm 样本，最深约 5.13 mm，小边比值很高。没有删报告或伪称零穿透；来源隐藏材质、贴身裁片与绑定局部偏移仍需区别于明显外观破坏。按最新用户标准，轻微局部穿模可记录接受，后续主要精力转回裙装。

**最新验收约定：** 用户允许不夸张的穿模。保留几何指标作诊断，不再以全自交归零延后交付；重点处理真实画面的明显手穿裙、大片布层互穿、尖折、围裙变形和动作问题。当前 HW 站姿接近可用，坐姿荷叶边聚集仍明显，需要继续修。C-IPC 仅离线参考，后台进程仍须核实后观察，不是实时方案或交付前置依赖。

# 第十七批：完整裙装参考起步输出通过，完整轨迹运行中

原身体、4920 点 HW 外裙、原软跟随及六个椅子盒体/地面已接入完整参考求解。`hw_smoke_01` 的旧进程随环境中断且没有完成结果；确认终止后另建 `hw_smoke_02`，两帧八子步已完成。子步 2 与第 1 帧末通过原独立几何门槛：自交、身体/手/场景穿透、过度拉伸均为零，最大边长比 1.03491/1.02399；身体轨迹误差小于 0.504 微米。Godot 原材质回放正/侧面保留版型和分层。这是 T 姿到垂手的起步，**不是自然站立或坐下已通过**。

完整 130 帧正在 `hw_full_01` 运行，先查 `codim_hw_full_01.log` 和进程/输出，不因观察超时重启。恢复与验收入口见 [参考评估第十七批](codim_reference_evaluation.md)。新增显式快照审计接口对旧失败站姿重放仍检出相同 7 对自交，没有降低门槛。整裙、统一人物链、性能和 MMD 仍未整体完成。

# 第十六批：参考软跟随接口与原动作输入保持

新增可关闭的 C-IPC 预测输入适配层，保留原 cloth_weight 与最大偏离公式，在联合接触求解之前作用于预测点，不在求解结束后强拉回目标，也不将混合区设为固定点。模块已编译，十项原生测试通过：软/自由/关闭、子步、偏离上限、非法输入、自由落体及接触正负例。目标穿过固定身体时，开启接触仍留下约 0.898 mm 间隙；关闭接触则明确穿透 250 mm。见 `codim_follow_controls/suite.json`，这是小控制，不是整裙通过。

原身体/服装绑定导出的自然站立→坐下轨迹共 130 帧，保存原权重和世界坐标身体输入；全部哈希/数量/有限性检查通过。五个关键身体状态与旧 `body_release` 捕获相差最多约 0.5305 微米，权重误差小于 4.6e-10。未调整手臂姿势，未删除身体或服装面。运动导出尚不包含椅子、地面与求解输出，下一步仍需接整裙及完整审计。具体适配范围、源补丁身份及运行入口见 [参考评估](codim_reference_evaluation.md)。

# 第十五批：完整 C-IPC 控制验证及原裙装输入审计

完整参考实现已在 WSL 编译、导入并实测；只做构建/绑定兼容修改，固定源码和依赖，没有切换 Godot 后端或修改源接触算法。自由落体通过。身体推动双层布在 dt=0.01 时无穿透，但身体误差 0.043 mm 未达门槛；收紧 Newton 容差不消除此误差，已定位上游移动约束只要求完成 99%。dt=0.00005 的 4000 步控制通过，并用 IPC 独立核验每个保存的线性状态段；相同步长关闭接触会穿过布面，保留负例。细步控制不是运行时修复，也不证明真实衣服已通过。

真实输入审计新增 `prepare_codim_garment_input.py`：保留原 HW 4920 点/9560 面及完整身体，源绑定哈希一致；没有自交或布—身体交叉。但原间隙最小约 0.162813 mm，不能套用控制例的 0.5 mm 全局偏移，输入厚度门槛返回失败。输出最近接触特征与原跟随权重，下一步不再盲目套参数。原跟随权重不是 cloth_weight；候选分类仍为 0 硬固定、1632 混合、3288 自由，禁止全腰硬固定来绕过适配。

源码准备、控制生成、独立全段审计和真实输入导出均已脚本化，证据在工程外 `codim_probe`、`codim_hw_input`。具体固定版本、命令、测试范围、OBJ 写出精度与下一步接口限制见 [完整参考评估](codim_reference_evaluation.md)。复杂裙装完整验收仍以第十三批失败为准；统一人物链、其它动作/服装、性能、MMD 的剩余顺序不变。

# 第十四批：新身体眼部占位材质补齐

复用本地 `AWWalker.AWWEyesPak01.2.var` 中棕色眼图（包元数据 CC BY），原图字节不变，命名为 `eyes_brown_01`。打包脚本 `package_character_eyes.py` 保留作者、来源成员、许可证及 SHA256；资源只存于工程外 `assets/characters/materials/eyes_brown_01/`。核对当前底模虹膜/瞳孔在眼图下半区、眼白在上半区的 UV，对应当前 glTF/动态网格的 V 翻转。

`character_regional_skin.gd` 为虹膜、瞳孔、眼白提供独立材质，与皮肤区域分开。`female_axis_body.gd` 原来会把所有 ShaderMaterial 替换成皮肤程序；现改为保留源表面 shader 与全部显式参数，加入相同分轴顶点变形。皮肤仍保留既有动态法线切线重建。纹理共享缓存，材质和身体参数仍按实例独立；记录材质名称及 skin/eye ID，供统一人物链后续接入。

验收：`capture_character_eyes.gd` 核查三个实际渲染表面的 2048 眼图、动态变形程序，捕获静态/动态 × 棚拍/游戏灯光 × 正面/斜侧八图。已检查静态和动态正面、动态游戏侧面：双眼虹膜/瞳孔位置正常，眼白未误贴肤色，无明显 UV 倒置。完整顺序重放、缓存版本重放及 `test_character_skin_studio.gd` 通过。首次与其它工作并发捕获曾异常结束且无报错尾迹；保留 `eyes_capture.log`，独立动态及两次完整顺序重放均正常，尚未归因，不把它宣称为已修复的引擎问题。

本项只补眼图和同一身体材质链。角膜反射层、睫毛、泪线、口腔最终材质仍有缺口；眼色捏人、注视和 MMD 表情没有因此完成，也没有将新身体提前切到正式玩家。新的眼图未改变身体或服装几何。当前复杂裙完整验收仍以第十三批失败结论为准。

# 第十三批：独立连续碰撞核验与身体旧接触释放

在工程外安装固定版本 `ipctk 1.6.0` Windows / Python 3.12 wheel，仅供离线诊断，不是新运行时依赖。新增 `audit_cloth_continuous.py`，使用已有 GPU 记录和焊接后的求解拓扑；先运行已知穿越/不穿越及旋转正负控制，再检查指定的线性状态段。输入若已经相交则明确拒绝给出无碰撞步长；指定两面只证明这两面，不能冒充全裙通过。IPC 库不是完整物理求解器，复用边界见布料研究文档。

独立结果：旧失败第 43 帧、面 8584/9107，从 `s3/contact3/self_edges` 到 `s3/contact3/body_reverse`，初态无相交、终态相交，IPC 给出的安全步长约 0.490234375。这印证了身体投影重新推穿布层的定位，**不是修复**，也没有把截短身体动作当成方案。报告保存在 `candidate_first_stage_hw_trace/ipc_segment_788f904b9270.json`。

另补身体前向接触的确定性错误：有些移动三角面一个子步内会两次穿过粒子位置，最终已分离；旧代码仍把粒子吸回最终接触面，而且最早的已解决事件会屏蔽后面的未解决事件。`test_gpu_cloth_body_unilateral.gd` 在生产 shader 上复现：本应不移动的粒子被拉动约 126.58 mm；加上另一个需要分离的面时仍执行错误旧接触。修复与此前自接触中的单侧约束一致，只接受仍有正分离残差的事件，并保留切向运动。小场景原向及旋转四项通过。它仅验证最终投影的非吸附性，不声称消除了所有中间轨迹穿越。

完整捕获 `--self-edges --mass-balance --review-id=body_release --trace-frames` 已完成，不打开已失败的 `--body-tangents`。17 项 GPU 正负回归符合预期，原默认网格烟测通过（81 点，固定点误差 0）。完整裙装仍失败：

| 姿态 | 自交 / 共面接触对 | 过度拉伸边 | 最大边长比 | 身体 / 手 / 场景穿透 |
|---|---:|---:|---:|---|
| 站立 | 7 / 0 | 0 | 1.1851 | 0 / 0 / 0 |
| 坐下 15 | 7 / 0 | 0 | 1.2119 | 0 / 0 / 0 |
| 坐下 30 | 37 / 0 | 0 | 1.3231 | 0 / 0 / 0 |
| 坐下 45 | 362 / 12 | 6 | 1.7783 | 0 / 0 / 0 |
| 坐稳 | 659 / 6 | 5 | 1.7568 | 0 / 0 / 0 |

相对旧质量反作用对照，坐下第 45 帧场景穿透被消除，拉伸幅度降低；层间仍明显不成立，侧视仍有褶边聚集。归档 `checkpoints/body-release/` 保存输入、编译哈希、完整捕获、17 项回归与代码。该捕获进程启动在眼部材质补齐之前，因此其中面部仍为旧占位材质；服装/身体几何没有变动，不用这些图验收新眼睛。

下一步要解决的仍是身体/布层/结构约束的联合有效性。IPC 当前只作为独立诊断，不是已经移植的完整求解器；不得重新打开失败的两方向实验或只加迭代宣称完成。

修复验收工具的另一个风险：`audit_garment_contacts.py` 原来会忽略未知参数，连 `--help` 都会执行默认旧资源审计。现在严格解析并拒绝拼错参数、缺少候选模式及非法 review ID；四项命令检查确认不会改写报告。`--stand-only` 使用单独输出名，避免覆盖完整动作报告；非有限值明确拒绝。几何阈值没有放宽。

# 第十二批：联合接触方向与过大修正回归（完整裙装仍未通过）

新增身体推进双层布的 GPU 回归，同时检查身体间隙和布层顺序，含对齐、错位及旋转对照。原质量反作用方案在对齐例中层间仅约 0.606 mm，未达 0.9 mm 门槛；记录身体接触方向、让自接触沿可行方向调整后，小场景达到约 1.01 mm。开关 `self_contact_body_tangents` 保持默认关闭。

两接触面的固定次数交替投影存在窄夹角漏约束，已经改成两半空间的直接投影。`test_body_contact_directions.gd` 对实际 GLSL 函数运行 14 项已知结果与旋转对照，旧方法有负平面距离，新方法通过。但这只证明局部方向函数，不证明曲面、三角形多点接触或完整裙装。

**必须保留的失败：** 最初交替方向版本真实站姿自交 4 对、拉伸合格，但坐下第 45 帧最大边长 14.12 倍、身体穿透 6 项；坐稳 1985 对自交、19 项身体穿透和 47 项场景穿透。直接方向版本仍失败，详见下表。不可把“站姿从 7 对降至 4 对”当成整体改进。

| 直接方向版本姿态 | 自交对数 | 超过 50% 拉伸的边 | 最大边长比 | 身体 / 手 / 场景穿透 |
|---|---:|---:|---:|---|
| 站立 | 4 | 0 | 1.1884 | 0 / 0 / 0 |
| 坐下 15 | 6 | 0 | 1.2675 | 0 / 0 / 0 |
| 坐下 30 | 18 | 1 | 1.5043 | 0 / 0 / 0 |
| 坐下 45 | 516 | 51 | 9.0309 | 0 / 0 / 3 |
| 坐稳 | 963 | 61 | 5.8552 | 0 / 0 / 3 |

发现一个可独立复现的数值错误：几乎对顶的接触方向使有效逆质量趋近零，5.5 mm 的接触修正被放大为约 5.767 m 的单步位移。新增 `test_gpu_cloth_oblique_contact.gd`，直接执行生产自接触 shader 的检测与汇总；负例和修复后的输出均保留。简单使用未投影分母虽然阻止跳变，却使双层对齐例降至 0.827 mm、仍失败，故没有采用。

当前实验保留投影后的质量分配，同时把单次最大顶点反作用限制在当前接触残差范围内，再由后续步骤重算局部接触。斜接触例单步约 5.5 mm、未重新进入身体平面；16 项 GPU 正负回归均符合预期。**有限步长不等于已经分离**，仍必须检查完整动作和残余交叉；没有增加迭代数或修改姿势/源网格/身体。

直接方向失败归档 `checkpoints/body-tangents-exact/`，先前交替方向归档 `checkpoints/body-tangents-iterative/`，均在工程外 `review_artifacts/character_3d/`。`candidate_body_bounded_hw_trace` 只是一段被停止的保守分母诊断，不是完整验收。`body_trust` 完整复测已失败：站姿 7 对自交、26 条手边相交；坐稳 1057 对自交、65 条手边相交、59 条过度拉伸边，最大边长 5.5874 倍，场景穿透 1 项。不能采用为正式后端；归档 `checkpoints/body-contact-trust-rejected/`。两方向只是局部近似，不足以代表曲面/布面多顶点的联合约束，下一轮关闭该实验。

# 第十一批：定位首次交叉和最后身体投影的冲突

本批新增默认关闭、只读的逐帧/阶段 GPU 快照。真实 HW 站立过渡保持完全相同输入和求解参数。`--trace-until` 是明确的局部诊断，不生成已完成整姿态的假报告；`audit_cloth_trace.py` 区分全网格审计与指定面配对跟踪。

全网格逐帧结果：第 0–42 帧无非邻接交叉，第 43 帧首次新增一对（源三角 8584/9107，交叉段约 0.16444 mm），位于一侧手掌附近的褶边。重放该帧记录 4 子步共 372 个预测/结构/点面/边/身体投影状态。开启记录与关闭记录的第 0–43 帧最终 GPU 缓冲逐字节完全一致，记录没有改动几何或动作。

阶段结果不能简化成“预测步骤坏了”：第一个预测阶段有另一对 2403/2492 的暂时交叉，随后被解开；最终残留的 8584/9107 从第一子步的结构第 4 轮开始反复出现/分离。关键是最后子步 contact3：`self_edges` 后这对面已经不交叉，紧接的 `body_reverse` 又产生最终约 0.16444 mm 交叉，`body_forward` 没有消除它。这是已实测的身体接触与布层接触约束冲突，不是仅凭截图猜测。

下一步：先构造“身体顶点推进相邻布层”的联合接触回归，再让布层修正尊重仍活动的身体接触约束（或反向联合求解）；保持身体和自交两道门槛。不能把最后一步简单改成只分开布层而重新穿手，也不能通过源版型/姿态修改回避。坐姿与其它裙装仍未通过。

复现捕获：`capture_candidate_wardrobe.gd -- --self-edges --mass-balance --review-id=first_stage --trace-until=43 --trace-stage-frame=43`。跟踪命令：`audit_cloth_trace.py <trace目录> --stages stand_043 --face-pair 8584 9107 --changes-only`。`--face-pair` 仅证明被选两面，不能冒充全网格通过。证据归档 `checkpoints/2026-09-28-first-crossing/`，含全帧、阶段缓冲、面配对报告、编译哈希与代码。

同时修正补丁重放校验：先前临时生成器错误剥掉上游仓库的 `addons/godot_gpu_cloth/` 前缀，导致把修改文件当成新文件，在不完整临时树中出现假通过。新增 `rebuild_gpu_cloth_patch.py`，检查实际 Git 路径和固定 SHA，并在真实原始文件上重放；现在明确是 4 个上游原文件修改、4 个新增文件，结果一致。旧归档保留，不再把旧重放日志当成可复现证明。统一 diff 的空白上下文行按补丁语法保留；普通源文件 `git diff --check` 通过。

# 第十批：内置 SoftBody/Jolt 的多层接触对照

新增 `tools/probe_builtin_cloth.gd` 与 Python 运行器，生成工程外的独立最小项目，显式分别选择 `Jolt Physics` 和 `GodotPhysics3D`。没有修改主项目物理后端、角色或衣服。实际引擎 4.7.2 `ed1daf0bf001b61586d9930840f2f1394092c079`；只做无头物理能力检查，不宣称美术或完整服装验收。

同一 5×5 布片、16 次模拟精度、90 个采样步，比较自由落体、刚体盒子、同一个 SoftBody 的两块不相连布层，以及两个不同 SoftBody。固定下层、上层自由下落，层/遮罩为默认相互可见，检查所有自由点和固定点误差。

| 后端 | 自由落体控制 | 刚体碰撞控制 | 同网格层间自接触 | 两软体互碰 |
|---|---|---|---|---|
| Jolt Physics | 通过 | 通过 | 失败 | 失败 |
| GodotPhysics3D | 通过 | 通过 | 失败 | 失败 |

两个后端自由落体均实际推进、刚体控制均挡住，故不是“物理没有运行”；固定点最大误差小于 1.2e-7 m。两种布层测试均穿过下层：Jolt 最终上层最低约 -10.07 m，GodotPhysics 约 -7.47 m。数值随首次采样时序可能小幅变化；结论只针对该明确配置，不推断所有版本/拓扑/扩展均不支持。但这足以排除“只切换内置后端就可交付本项目多层裙”的方案，暂不把完整 HW 裙绑定移植过去重复碰壁。

复现：`python tools/probe_builtin_cloth.py --godot <Godot 控制台程序>`。退出 0 仅表示两个控制组有效，报告明确保留 self/peer 为 false。外部记录 `review_artifacts/character_3d/builtin_cloth_probe/`；归档 `checkpoints/2026-09-28-builtin-softbody/`。官方能力边界及链接见布料选型文档。

下一步回到未通过的实际裙装，记录首次层交叉出现的帧和各求解阶段，区分结构投影、布层接触及最后身体/椅子投影的相互冲突，再确定需要补的持久接触约束。不能把“内置不满足这个对照”当作无限堆迭代或全面重写人物的理由。第九批未通过的门槛、自然动作、源网格和默认关闭状态保持。

# 第九批：边接触、双向布面反应及完整坐下回归（未通过）

用户已授权按整份计划持续修复和验收，不需要逐轮说“继续”。本批保持源裙、材质、自然垂手和身体完整；默认角色后端与全部实验开关不变。

新增默认关闭的 `self_edge_contacts`：使用源唯一边列表，边接触与点面接触分开快照/求解，避免同时累加旧快照修正。直接叠加版本最大边长 13.82 倍，明确失败；分相四轮历史站姿为 6 对自交，八轮反而出现 57 次手交叉，说明不能仅加迭代。随后每轮同时重投影身体点→布面和布点→身体。相关失败证据在 `checkpoints/self-edge-additive-failed`、`self-edge-phased`、`self-edge-body-reprojection`。

新增默认关闭的 `self_contact_mass_balance`：点面接触按四个参与点的逆质量/重心权重分配位移，单独 gather 阶段避免共享写入竞争。补上固定点对自由布面的反作用，原来固定点会被跳过；固定小布片挡住运动大布面的正例间隙约 6.003 mm、固定点误差 0，关闭反作用的负例穿过 100 mm。还修正旧 sweep 已经分离后仍吸回接触面的单边约束错误。多接触平均不保证整体动量守恒或必然收敛，不能宣传为完整布料求解器。

验证链新增 `gpu_shader_review_manifest.gd`：GLSL 源 MD5 必须与 Godot 导入缓存一致，捕获写入源/编译 SHA256。直接启动脚本曾读到旧 SPIR-V，新质量结论必须绑定实际编译版本。旧记录未包含编译哈希的数值仅保留作历史观察，不作为严格算法因果比较。

`test_gpu_cloth_contact_suite.py` 的 11 项 GPU 检查符合预期：近源间隙、点面穿越、移动固定点及绕序、固定点反作用正负例、仅边接触正负例、两面同时接触及反向面序、身体反向接触上下两向。几何自交测试 3 项和身体体积审计亦通过。修复重放补丁已在固定上游 SHA 上验证 8 文件一致。

真实 HW 同一站立→坐下输入，最后版本 `candidate_mass_unilateral_hw_`：

| 姿态 | 自交对 | 共面对 | 超过 1.5 倍的边 | 最大边长倍率 | 超过 3 mm 场景穿透样本 |
|---|---:|---:|---:|---:|---:|
| stand | 7 | 0 | 0 | 1.1874 | 0 |
| sit_15 | 7 | 0 | 0 | 1.1702 | 0 |
| sit_30 | 33 | 0 | 0 | 1.2186 | 0 |
| sit_45 | 386 | 7 | 6 | 2.6515 | 1 |
| sit | 695 | 2 | 7 | 1.8526 | 0 |

五项 `accepted=false`。身体体内、手边交叉、身体/椅子与地板门槛均为 0，但坐下第 45 帧有一项布面/场景穿透，坐稳仍有密集层交叉和过度拉伸。此前反作用第一版坐稳自交 617、过度拉伸 3 边、最大 1.6204 倍（`self-mass-first`）；最终修正不是实景全面改善，不能只引用更好看的某个数字。正/侧/背及手部仍需整体视觉成立；新增隐藏椅背的附加截图只改变可见性，不改变碰撞或推进模拟。

完整最终证据：`checkpoints/2026-09-28-self-contact-reactions/`（图、几何、审计、编译哈希、代码、补丁、测试日志及 SHA256）。下一步执行原计划的内置 SoftBody3D/Jolt 能力对照，先测自碰撞/互碰，再决定现成后端边界；不要无限只给当前候选加迭代。真实裙装没有通过，性能及 MMD 尚不提前开始。

躺姿另补 `lie_relaxed` 与原 `lie` 并存。调整头颈、肩肘和手部后通过身体 CPU/GPU 对照及灯光场景操作回归；原输入未删。幅度插值只是检查工具，站→躺的支撑动作、床面、穿衣与自然手指仍未完成，整项躺姿待办未勾选。资源/配方盘点见 `character_resource_inventory.md`，明确眼部占位、头发、内搭、形态与正式角色链等缺口。

# 第八批：同时接触丢失与结构约束交替

继续保留原姿势、源网格和材质，在第七批连续自接触上增加显式实验选项 `self_contact_iterations`（默认 1、限制 1–8）和 `self_contact_structural_projection`（默认关闭）。多轮之间重新快照预测位置；交替结构投影复用原 XPBD lambda，不重置柔度、不重复动画跟随。没有调整身体动作或增加全局布料刚度。

新增 `test_gpu_cloth_self_corner.gd`：自由布片同一步撞到两个垂直固定布面。单轮投影遗漏一个面，最小间隙 -68.200 mm，负对照失败；四轮保留两个面的约 6 mm 间隙，固定点误差 0；反向面顺序/绕序及交替结构选项均通过。移动固定布面、源 1 mm 近间距、原身体 reverse face 回归也通过，正例日志无错误。此测试只证明该明确两面接触场景，不证明任意多接触或完整连续碰撞。

同一真实 HW 裙装、65 帧自然垂手站姿：

| 实验 | 自交面配对 | 超过 1.5 倍的边 | 最大边长倍率 | 手交叉/超过 3 mm 身体穿透 |
|---|---:|---:|---:|---:|
| 第七批单轮接触 | 157 | 0 | 1.2348 | 0 / 0 |
| 四轮仅接触 | 125 | 1 | 1.6436 | 0 / 0 |
| 四轮接触 + 结构交替 | 99 | 0 | 1.2562 | 0 / 0 |

两次新实验均无椅子/地板穿透、无共面重叠和退化面，但 `accepted=false`。四轮仅接触虽减少交叉却拉长一条边，不能当作修复完成；结构交替解决了本次新增的过度拉伸，并进一步减少自交。侧面及手部近景仍有下摆拥挤、局部折痕；背面部分被椅背遮挡，不能据此宣称背面无问题。

本轮没有坐姿新回归，尚不能启用正式后端。候选默认仍为自接触关闭、单轮、结构交替关闭；通过捕获脚本显式 `--self-contact --contact-structure --stand-only` 才复现当前改进。输出 `candidate_self4s_hw_` 与旧实验分开，四轮仅接触输出 `candidate_self4_hw_`。下一步仍是剩余 99 对布面交叉（含边—边、多接触与相交后恢复缺口），之后回归坐姿目标折叠；不能放宽自交验收阈值。

代码、两个实景分支、GPU 正负例、参数及 SHA256 归档：`checkpoints/2026-09-28-self-contact-rounds/`。固定上游补丁 8 文件重放一致。先前提交 `bd64b491` 保持不变，本轮改动尚未提交。

# 第七批：连续自接触与源间隙约束，站姿自交减少但未通过

新增默认关闭的 `continuous_self_contacts` 实验路径，接在固定版本 GPU cloth 插件中，不更换身体或服装：

- 复用已有身体接触的移动三角面/点连续检测，避免布点一帧穿过另一布面后仅凭末端距离漏检。
- 每个子步在 PREDICT 前保存旧位置，在自接触前保存当前预测位置；两个只读快照避免邻点并发改写，并保留固定点移动前的位置。
- 使用完整源三角拓扑，不让简化代理跨接荷叶边。
- 各点/面的接触间隙不超过其源距离的一半，避免统一厚度硬撑密集褶边；连续穿越检测仍执行，没有把相近层从检测里删掉。
- 自接触之后再投影身体三角接触。仍不保证同时满足所有接触/结构约束，不能宣称完整自碰撞已完成。

GPU 对照测试：自由布片一帧移动 20 cm，旧路径最终穿入 100 mm，新路径间隙 6.00004 mm；移动固定层及反向面序间隙 6.00009 mm、固定点误差 0；源间距 1 mm 的布层保留约 1.00005 mm，不再强行撑成 6 mm。身体 reverse face 回归间隙 6.00389 mm。正例日志无 ERROR，负例正确检出失败。新增管线释放顺序也已修正为先管线后 shader，避免 GPU 资源二次释放错误。

真实 HW 原动作、原材质、自然垂手，65 帧站姿：

| 配置 | 自交面配对 | 超过 1.5 倍的边 | 最大边长倍率 | 手交叉/超过 3 mm 身体穿透 |
|---|---:|---:|---:|---:|
| 第四批默认候选 | 831 | 0 | 1.1278 | 0 / 0 |
| 连续自接触，统一厚度（失败对照） | 72 | 359 | 3.9026 | 0 / 0 |
| 连续自接触，限制为源间隙（当前实验） | 157 | 0 | 1.2348 | 0 / 0 |

当前实验无地板/椅子穿透、无共面重叠、无退化面，但整体 `accepted=false`。检查了正面、侧面及手部近景，裙摆仍有局部拥挤折痕，**不是视觉完成**。统一厚度虽然自交数字更低却造成严重拉伸，已保留为失败对照，不能采用。

本轮只跑实验路径站姿，不把第四批坐姿数据当成本轮回归。默认 `garment_candidate_cloth.gd` 保持自接触关闭；显式 `--self-contact` 才启用，捕获文件使用 `candidate_self_hw_`，独立于常规 `candidate_hw_`。`--stand-only` 只写本次一项报告。下步仍需处理剩余面交叉、边—边/多接触冲突及坐姿绑定折叠，不能靠抬手或删褶边通过。当前算法只是点—面连续检测，不含完整边—边连续检测或初始缠结解开能力。

新增 shader 与求解器改动已纳入固定上游补丁，8 文件重放一致。最终证据存于 `checkpoints/2026-09-28-self-source-gap/`，包括捕获、测试日志、代码快照及 SHA256；第一版错误统一间隙捕获在 `checkpoints/self-uniform-gap/`。

# 第六批：补齐布面自相交漏检，定位绑定与求解两个来源

复用本机 libigl 2.6.3 的三角面相交谓词，新增 `tools/audit_cloth_self_intersections.py`。以包围球和 AABB 保守筛选面配对，分别记录非共面交叉线段、共面重叠、退化面和具体三角面 ID；按源三角索引对照，源内已有交叉也不会被静默豁免。共享顶点的面暂排除，因此仍不是所有自交或连续碰撞的证明。

独立测试覆盖已知交叉线段、分离、0.01/1/100 比例、源与新增交叉区分、拓扑邻接、共面重叠、退化面与非有限值。三个测试通过。未新增客户端依赖；libigl 现在是候选自相交离线验收的必需依赖。

复审固定证据 `checkpoints/2026-09-28-reverse24-071242`（未重拍或混入其它版本）：

| 输入 | 非相邻三角面交叉对 | 共面重叠对 |
|---|---:|---:|
| 源控制网格 | 0 | 0 |
| 站姿求解后 | 831 | 0 |
| 坐下第 15 帧 | 1034 | 0 |
| 坐下第 30 帧 | 1319 | 0 |
| 坐下第 45 帧 | 4851 | 3 |
| 坐稳 | 6853 | 6 |

这些是相交面配对数，不是独立洞口数量。之前第四批“通过”仅限身体/手/椅子/拉伸门槛，不能解释为裙装完成。`audit_garment_contacts.py --candidate` 已默认纳入自相交、共面重叠和退化检查；实跑 `--stand-only` 正确报告身体穿透 0、手交叉 0、自相交 831、`accepted=false`。它只覆盖站姿，未拿其它残留文件冒充本轮完整回归。

新增 `capture_garment_binding_baseline.gd`，同一 HW 衣服、同一身体与姿势，直接导出表面绑定目标，不运行候选求解，写入单独 `binding_hw_*.json`。审计结果：静止和站姿绑定均 0；坐姿绑定已有 1235 对交叉，最长交线约 263 mm。这说明站姿交叉在动力学阶段产生，坐姿还存在跟随目标本身折叠的问题；不能把所有症状都归于显示细分，也不能指望更强的跟随修好坐姿。

本轮修复的是**验收遗漏**，尚未修好真实裙子的自相交。未改变用户指定的自然手臂姿势、源衣服拓扑、材质或默认求解开关。下一步需要在保留失败动作的前提下处理可动裙层的跟随目标与层间接触，再重跑这个新门槛；不能通过忽略计数、删褶边或扩大裙子来通过。

# 人物收尾：2026-09-28 实施记录

## 第四批：布面内部接触与审计纠错（当前状态）

新增 `cloth_reverse_contacts.glsl` 与 `cloth_gather_contacts.glsl`：从同一份预测网格计算身体顶点穿过布面的接触，按接触重心和逆质量产生顶点修正，再单独按邻接关系汇总，避免 GPU 邻点并发写入。仍保留原人物动作、源固定权重、款式、多材质与 UV。

最小场景让小碰撞面跨过大布面的中央，布料顶点均远离小碰撞面，只有身体顶点穿过布面内部：关闭反向检测会漏穿 0.1 m；开启后间隙约 0.006004 m。向下运动、反面序同样通过。原外部包/大步长/混合跟随回归通过。单三角形测试还发现了小 buffer 的分配大小与初始数据长度不一致，已统一补齐。

边—边连续检测也有实验实现与独立正/负对照，但它在真实裙装中使坐稳手部相交由 0 回退到 43；**默认不启用**。`capture_candidate_wardrobe.gd -- --edge-contacts` 专门复现，不把孤立测试通过当成实景通过，也不能宣称完整 CCD 已验收。

座面夹层间隙改为两侧接触厚度之和（身体侧 6 mm＋座面侧 6 mm），由求解器参数传入测试夹具，不改身体和裙子。增加正、侧、背、手部近景，以及逐帧“布料不得修改输入关节姿态”的断言。

审计纠错：旧算法把最近三角面法线的负侧直接当作体内，会把手指外侧点误报为 1–3 cm 深的穿透。对原候选点计算整体绕数约 0.00013，实际在体外。现在对近表面候选样本使用整个身体的立体角绕数确定内外，深度用几何距离；不再依赖最近面的朝向。`legacy_normal_candidates` 保留旧候选数以供对比，3 mm 阈值、真实手部边面相交、地面/椅子及 1.5 倍拉伸检查保持。`test_garment_contact_audit.py` 用解析盒体验证内外、尖角外侧、翻面、缩放和 NumPy/libigl 两条路径。libigl 2.6.3 是可选离线验证依赖，不进入客户端；身体存在小开口，绕数判定及离散采样仍不能代替完整运动验收。

12 次求解的对照：五个记录帧手部相交、体内 >3 mm、身体/布料与椅子穿透均为 0；站立、坐下 15/30 帧和坐稳通过，第 45 帧还有一条 7.03 mm 的边拉伸到 1.5709 倍，仍未全过。证据保存在外部 `checkpoints/2026-09-28-reverse12-070800/`。继续做相同材质顺应度下的收敛检查，不通过硬化弯曲或改变动作掩盖该边。

### 第四批末轮：五个记录状态通过几何门槛

24 次求解对照已通过，实验适配器现在默认 24 次，仍为 4 子步；结构/弯曲材质顺应度与源固定权重未改。12 次可用 `-- --baseline-iterations` 重放，边—边分支仍须显式 `--edge-contacts`，不启用为默认。

| 记录状态 | >3 mm 体内 / 手部相交 / 椅子穿透 | 最大边长比 | >1.5 倍边数 |
|---|---|---:|---:|
| 站立 | 0 / 0 / 0 | 1.1278 | 0 |
| 坐下 15 帧 | 0 / 0 / 0 | 1.2876 | 0 |
| 坐下 30 帧 | 0 / 0 / 0 | 1.1665 | 0 |
| 坐下 45 帧 | 0 / 0 / 0 | 1.4787 | 0 |
| 坐稳 | 0 / 0 / 0 | 1.3048 | 0 |

身体与椅子重叠、穿地也均为 0，每项 14,480 个样本；逐帧关节输入不变断言通过。正、侧、背与手部近景已输出；椅背遮挡的后腰不能用背面截图认定无缺陷。坐姿荷叶边仍较拥挤，层间/自碰撞、其它衣服、完整逐帧几何采样、抬腿/躺姿及体型极值尚未验收。**本表只表示同版 HW 外裙的五个记录状态通过，不表示整个人物系统或所有视觉质量完成。** 未将候选后端切换到正式角色。

同版源码、完整补丁、正/负对照日志、五份几何、各角度截图和配置归档于外部 `review_artifacts/character_3d/checkpoints/2026-09-28-reverse24-071242/`，附 SHA256 清单。上游固定版本应用完整补丁后，与六个本地求解文件逐字核对一致。当前默认实验适配器采用该 24 次、4 子步、反向顶点接触开/边—边关的配置；Go、正式地图、性能与 MMD 排序未改。

## 第三批：真实裙装接入与基础物理纠错（历史记录）

候选插件已固定放入 `addons/godot_gpu_cloth/`，保留 MIT 许可和提交号；未启用编辑器插件，也没有替换正式游戏默认后端。此前下文“仅在工程外”的说明属于当时状态。`garment_candidate_cloth.gd` 通过隐藏控制网格和粒子查找纹理接入 HW 外裙，保留源三角形、UV、多材质及固定权重。实际参与碰撞的是分轴身体 42,160 个非退化三角面和椅子/地面 74 个三角面。上衣与帽子仍是表面绑定，**尚不是多件完整布料系统**。

本批实测修复：

- 前后帧三角面输入与子步插值，求解粒子和线性移动三角面的共面时间，选择最早接触；碰撞保留切向滑动，不把布点焊死在命中位置。仍不包含完整边—边、反向顶点—面与层间连续碰撞。
- 动画跟随/最大偏离约束移到预测阶段，避免在碰撞解算之后重新把布点拉进碰撞体。更新阶段只恢复速度和保存最终位置。
- 父节点位移原先既用于坐标补偿，又累积进恢复速度，持续移动时导致布料错误加速；现在在一致的参考坐标内恢复速度，并修正旋转与平移的子步复合。预热重置参考变换历史。
- 释放底层 RD 纹理前清空 Texture2DRD 包装引用，本轮真实裙装卸载日志不再出现无效纹理绑定错误。
- 椅子参照原先漏掉臀部前侧最低点，实测座面穿入身体 8.6 mm。座高改用整个座面覆盖范围的最终 CPU 身体表面计算；站立位于椅前，连续坐入。没有改手臂、手指或其它关节输入。

基础回归 `test_gpu_cloth_candidate.gd`：

| 条件 | 结果 |
|---|---|
| 普通重力、9 固定点/81 粒子 | 通过，固定点误差 0 |
| 外部目标、非法包拒绝、单子步 0.5 秒、碰撞面一帧跨过布面 | 通过 |
| 半跟随目标位于碰撞面后方 | 通过；旧隔离副本负对照在粒子 9 的 y=0.995445 失败（面 y=1.05） |
| 无外力、持续根平移＋旋转 | 修复后世界漂移约 0.00000416 m；旧隔离副本约 1.65288 m，失败 |

`capture_candidate_wardrobe.gd` 捕获站立、坐下第 15/30/45 帧及坐稳，`audit_garment_contacts.py --candidate` 检查原身体、手部边相交、地面、椅子、身体与椅子预先重叠及源边拉伸。真实裙装仍未通过：基础小网格通过不能覆盖布面内部、细手指、复杂层次和椅子夹层。没有放宽原 3 mm 穿透/1.5 倍拉伸标准，也不能以“最终停稳了”掩盖过渡失败。

继续工作的入口：先解决双向边面接触和场景夹层约束，再扩展真实多层衣服；源网格 360 条非流形边未被删除，插件跳过了它们的弯曲约束，需单独检查。最终动作、形态极值、完整正式换装仍待验。躺姿头手待办已保留，视觉 → 性能 → MMD 顺序不变。

完整补丁 `tools/patches/gpu_cloth_candidate_integration.patch` 已更新，覆盖 solver、碰撞、预测及更新 shader，并通过对固定上游文件的 `git apply --check`。它替代旧 cleanup 补丁，不要叠加。复现现在使用 `--path D:/code/rmmo`；隔离项目保留旧版本作为负对照。

### 第三批末轮实测（覆盖中途结果）

| 姿态 | >3 mm 身体穿透样本 | 手部边相交 | 最大边长比 | >1.5 倍边数 |
|---|---:|---:|---:|---:|
| 站立 | 3 | 138 | 1.3013 | 0 |
| 坐下 15 帧 | 2 | 293 | 1.3011 | 0 |
| 坐下 30 帧 | 11 | 409 | 1.4081 | 0 |
| 坐下 45 帧 | 23 | 770 | 1.5833 | 3 |
| 坐稳 | 21 | 672 | 1.7307 | 3 |

每项均为 14,480 个点/面中心样本；以上五项**全部不通过**。身体与椅子、衣服与椅子的 >3 mm 样本及穿地样本均为 0，但只是当前抽样检查。座面修正前坐稳最大边长比 5.8534、29 条过伸边；修正后改善不能抹掉剩余穿透。手部计数是边—面相交次数，不是独立孔洞数量。

`test_character_skin_studio.gd` 已增加 45° 转向后坐姿身体/椅子检查，连同现有共享角色配方与交互控件回归通过。源码、报告、正侧截图及正/负对照日志归档于外部 `review_artifacts/character_3d/checkpoints/2026-09-28-candidate-054011/`，附 SHA256 清单。不要把旧后端的站姿通过与本候选后端的基础测试合并成验收结论。

## 第二批：外部表面输入与薄面穿透（历史记录）

用户新增待办：躺下时头颈、肩肘、手腕与手指参考真实人体姿势调整，检查过渡、放松和支撑关系；已加入 [开工入口](character_next_session_plan.md)。这属于动作设计，保留原躺姿作碰撞回归，不通过换姿势掩盖穿模。

隔离插件新增 `external_surface_input`、固定的 `external_triangle_count` 和 `set_external_frame(targets, triangles)`：

- 在 solver 局部坐标输入焊接粒子的衣服目标，以及展开的碰撞三角面。跳过内部普通蒙皮路径，为分轴身体与场景碰撞提供接入口。
- 目标和碰撞数据整包校验后提交；数量不符、非有限数值、退化三角面均拒绝，保留上一有效包。初始化后不允许改变三角面数量。
- 主线程将帧数据复制给渲染线程，预热也使用同一包，不把可变外部数组直接交给异步计算。

实测发现并修复了三角碰撞只检查终点导致的薄面穿透：在现有最近点接触之前检查粒子从子步起点到终点是否穿过三角面，并在入射侧保留厚度。没有放宽检查阈值、改变衣服或人物动作。

`test_gpu_cloth_candidate.gd --external --large-step` 验证：81 粒子/9 固定点、移动的衣服目标、缓慢升高的碰撞平面、非法输入整体拒绝，最后强制单子步 0.5 秒。关闭扫掠检查作负对照时，粒子 10 落到 y=0.817848（平面 y=0.85），测试失败；恢复检查后通过，最大下垂约 0.14 米、固定点误差 0。日志：外部 `review_artifacts/character_3d/gpu_cloth_external_sweep_test.log`。

**边界：** 这是粒子对当前三角面的扫掠，不含前后帧变形三角面的完整连续碰撞，也没修改 peer/self 接触。缓慢移动平面通过不代表高速移动手指或椅子交互通过。真实裙装的粒子映射、源固定权重、原材质、多层输入及坐姿仍未完成；上一批坐姿失败记录继续有效。

完整可重放补丁 `tools/patches/gpu_cloth_candidate_integration.patch` 包含上一批资源释放修复、本批输入接口和三角面扫掠，基于同一固定上游提交。**它替代 cleanup 补丁，不要两份叠加应用。** 已通过逆向 `git apply --check` 核对。插件仍在工程外隔离目录，没有悄悄替换正式游戏布料。

承接 [开工入口](character_next_session_plan.md)，开始实际修复与选型试验。保留认可身体与源衣服；Go 持久化、正式地图暂缓，不提前做性能重构或 MMD 表情。

## 最终骨骼姿态同步

此前 `set_angles()` 写完关节立即求解，后续 SkeletonModifier3D 改变的姿态无法可靠进入身体。只更新全局矩阵也不够：部分权重仍使用旧局部轴角，会造成关节与表面不一致。

现在 `female_axis_body.gd` 在 `Skeleton3D.skeleton_updated` 时采集最终局部旋转及全局关节快照。CPU/GPU、身体纹理、`posed_points`、手掌/手指接触代理共用同一次结果。Godot 恢复修改前的动画输入后，接触仍读保存的最终快照；不改写用户输入姿态。新增 `surface_updated` 表示表面与快照同步，不表示衣服物理已完成。

角度反解保留接近上一次的欧拉角分支，处理 ±180° 环绕和 90° 奇异点。等价的全局旋转不一定产生相同的分轴部分权重变形，不能随意切换角度分支。

**当前支持固定关节位置/比例的旋转。** 局部平移或缩放会整体拒绝同步并设置 `pose_sync_error`，保持上一次完整表面。身份形态的骨长变化仍需配套绑定数据，不可宣称已经支持；根运动可放在角色节点。

验证工具：

- `test_female_final_pose.gd`：真实 modifier、直接骨骼写入、BoneAttachment3D 一致、恢复、输入不变、不支持的缩放整体拒绝；六种旋转顺序 0–200° 连续扫描。
- `capture_female_axis_body.gd`：七姿态、混合轴、根刚体旋转、复位、CPU/GPU 对照通过，基本姿态最大差约 7.4e-7 米。
- `test_surface_wardrobe.gd`：槽位复用、预热保持姿态、实例资源隔离与卸装通过。

报告：外部 `review_artifacts/character_3d/final_pose_sync_report.json`。这是后续正式动画的基础，不能推广为完整动画库已验收。时序依据：[Skeleton3D 官方信号说明](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html#signals)。

## 布料插件已经实测，但尚未替换

[alien-life/gpu-cloth-sim](https://github.com/alien-life/gpu-cloth-sim) 固定提交 `bd917afd15a8389370c7e12ec9c074555834cf68`，MIT。隔离目录 `D:/code/rmmo_runtime/tools/gpu-cloth-sim-evaluation/`，没有装入 RMMO addons。

`test_gpu_cloth_candidate.gd` 在该项目运行：81 粒子、9 固定点，验证重力、固定边、有限值。Godot 4.7.2 / Forward+ / RX 7900 XTX 实际运行成功。这不是裙装或身体碰撞验收。

实测发现卸载时先释放 buffer，导致依赖 uniform set 失效后被重复释放。隔离副本已修为先释放仍有效的 uniform set，再释放底层资源；复测无该错误。补丁 `tools/patches/gpu_cloth_candidate_cleanup.patch`，许可 `tools/patches/gpu_cloth_candidate_LICENSE.txt`。没有向上游发送消息或提交。

| 输入/能力 | 源码确认 | 仍需完成 |
|---|---|---|
| 衣服目标 | `cloth_skin.glsl` 普通蒙皮；无骨架时为初始位置 | 输入现有表面绑定的动态目标，不能换成另一套权重 |
| 身体碰撞 | `_pack_collider_tris()` 将代理点绑定到单根主导骨骼 | 接入真实分轴身体表面或由它重建的代理面 |
| 层间/自碰撞 | 三角代理上的离散点距离与推离 | 不能当作连续边面碰撞；薄层与快速动作待验 |
| 显示材质 | 位置/法线纹理及显示 shader | 保留原裙多材质、透明裁切和 UV |
| 生命周期 | 本轮修复单实例释放错误 | 多件互碰、初始化中取消、反复换装待验 |

下一步是补真实身体与衣服目标输入后做对照，不能未经比较继续堆旧迭代器，也不能因插件存在就宣布问题解决。

复现：用 Godot `--path D:/code/rmmo_runtime/tools/gpu-cloth-sim-evaluation --script D:/code/rmmo/tools/test_gpu_cloth_candidate.gd`。首次需导入资源、注册类。稀疏检出不含 Demo 主场景，始终使用脚本入口。首次编辑器导入出现过 SVG 尚未导入的预加载错误；后续实际 Vulkan 运行才是本轮通过依据。

## 视觉复测仍有失败项

HW 外层站立与抬腿通过现有抽样穿透、手部边相交、地面和拉伸检查；坐下仍有 3 条边超过 1.5 倍拉伸，最大约 1.96 倍，**坐姿不通过**。椅子仍是白模参照，尚未参与布料碰撞。

没有修改输入姿势、源衣服或验收阈值。原报告在外部 `cloth_hw_report.json` / `cloth_hw_contact_audit.json`；完整连续碰撞、层间接触、椅子碰撞、捏人与正式角色接入仍未完成。

本轮报告与 HW 站/抬腿/坐姿截图及几何已复制到外部 `review_artifacts/character_3d/checkpoints/2026-09-28-final-pose-045216/`，附 SHA256 清单，后续默认捕获文件被覆盖时仍可复核。坐姿审计返回失败是预期记录，不属于通过项。
# 第五批：修复完整网格自碰撞被意外禁用

本轮发现 `peer_collider_voxel_resolution=0` 的语义是关闭代理简化，但原插件自碰撞只绑定代理索引，因此完整网格模式反而没有自碰撞。现与 peer 路径一致：有代理用代理，没有代理则绑定原始三角索引；不复制网格、不改变身体姿势或源衣服。

新增 `tools/test_gpu_cloth_self_contact.gd`，实际 Forward+ GPU 两个独立布片，底层固定、上层自由，初始间距 1 mm、接触厚度 6 mm：

- 完整拓扑：最终间距 6.00004 mm，固定点误差 0，所有位置有限，通过。
- 代理模式加反向面序：同样 6.00004 mm、固定点误差 0，通过。
- `--disabled` 负对照：仍为 1.00005 mm，正确检出未分离并失败。
- 原有 reverse face 测试回归：接触间隙 6.00389 mm，通过。

**范围限定：仅修复自碰撞不可用的入口错误。真实 HW 适配器仍维持第四批配置，自碰撞默认关闭；本轮没有重新拍摄裙装，也没有新的实景视觉通过结论。** 自碰撞当前读取子步起点几何，只排除含当前顶点的面，且在身体接触之后执行，仍存在贴近的源褶边被推开、快速运动漏检、重新推入身体的风险。下一步须先建立非相邻面相交及源静态基线的独立审计，再验证约束顺序和真实裙装；不要直接增厚或开启粗代理冒充层间修复。

固定上游补丁 `tools/patches/gpu_cloth_candidate_integration.patch` 已同步此修复；性能、MMD、Go 持久化及正式地图优先级不变。
