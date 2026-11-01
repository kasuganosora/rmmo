# 夜间公会转镜头突然变暗修复

用户复现条件：游戏模式、夜间室内，转动镜头使柱子挡住灯时，房间突然变暗。本轮只处理这条灯光状态链，不开展 FPS 或加载性能测试。

## 原因与修改

公会的 16 个 authored socket 经过 `model_components._adapt_socket` 接入 `streetlamp_lights`，不是普通住宅的 candle controller。控制器按相机距离启用最近 6 盏灯，并仅给最近 2 盏开启阴影。第三人称绕转和碰撞缩臂都会改变相机位置；人物没有移动，室内灯和门外灯仍会交换阴影资格，导致同一受光面突变。

`StreetlampLights` 新增 `observer`。游戏通过 `Weather.bind(..., actor)` 以实际玩家根节点决定距离及楼层；相机绕转不再重新选择另一组灯。首次绑定和复用绑定均同步 observer；无角色的编辑器以及角色释放后的安全回退继续使用当前相机。保留 6 灯、2 阴影、18 米范围及真实角色移动时的更新，没有关闭场景阴影、增加预算、创建额外灯或增加扫描。

本机安装引擎是 4.8 beta1 源的 `10+shutdown13`，不是另一个候选源码目录里的后续构建。引擎审查未找到按灯心视线剔除整盏灯的逻辑：原生遮挡测试用整个光照 AABB，项目也未启用 viewport occlusion culling。正式 Axel 环境没有启用 SSIL。此轮没有引擎补丁。

## 先复现，再验证

证据根 `P = D:/code/rmmo_runtime/review_artifacts/guild_pillar_light_20261101`。

|验证|修复前|修复后|
|---|---|---|
|真实 Weather.bind 的相机/角色行为测试|17 通过、9 失败|26/26 通过|
|原生公会、夜间、25 个相机绕转位置|6 组灯光/阴影选择，6 次切换|1 组，0 次切换|
|同一固定观察画面的 RGB 8-bit 均值|3.7015–6.5819|恒为 4.6556|
|固定画面相对第一张的最大通道差|255|0，逐像素一致|
|既有夜间灯状态回归|—|55/55 通过|

固定观察相机只测照明变化，另一台相机驱动生产灯光排序。前后 native 产物、纹理身份、环境、曝光完全一致，`tools/check_guild_pillar_lighting.py` 独立读取全部 25 张原始图及状态并检查，结果在 `P/comparison.json`。这些数值是图像通道值，不是物理照度或帧率。

实际 native 使用正式公会 key `packs/default/assets/7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb` 对应的发布产物。`.glb` 是现有逻辑 key；加载走原生场景和分离纹理，没有 GLB 导入。脚本为 `tools/probe_guild_pillar_lighting.gd`，有效证据 `native_night_red03` / `native_night_green01`。此独立排序探针没有相机碰撞，其移动视口在部分角度进入模型，不能用那些黑图充当游戏问题复现；结论取始终固定、未进入模型的 witness 视口。

## 真实游戏模式补验

`tools/make_guild_night_camera_fixture.py` 从正式 Axel 地图抽出 `obj_1033`，复制原 414 字节 rmres，复用原 native 模型/碰撞；只创建外部临时地图。源地图、引用字节 SHA 保持不变。

`tools/test_guild_night_camera_game.gd` 通过 `GameSession.go_world_3d()` 加载，使用真实玩家、输入、流式发布、第三人称相机和碰撞缩臂。夜间 22 时，SSIL/probe 关闭，UI/HUD 开启。地图环境的 ambient 0.08/sun 0.12 单独记录，不与上面的固定画面做亮度比较。

证据 `D:/code/rmmo_runtime/review_artifacts/guild_night_camera_game_20261101_v1/`：

- 15/15 检查通过，51 个状态采样；16 个公会 socket 全部发布。
- 36 步全周绕转，玩家位移 0；灯光/阴影集合始终不变。
- 实际相机臂从 5.9995 米缩至 2.1731 米；光源遮挡命中 `Entry timber post`、`Entry timber post_001`、`Balcony access support_001` 等真实部件。
- 正常 D 键输入行走 3.1203 米，灯光选择随后更新，未冻结选灯逻辑。
- 5 张原尺寸、有损 WebP quality=90 游戏截图全部查看；收据及 SHA 在 report.json。截图时仅暂时隐藏角色渲染模型，之后恢复。
- exit 0，无引擎错误；临时地图 SHA 不变，正式地图和模型没有修改。

本次 outline 没有进入 occluded 状态，不宣称覆盖该副视口所有情况。固定观察图的差异已由灯光排序单独复现并消除，不需要改 outline 或引擎。

## 保留的诊断边界

早期 `native_probe01` 的独立编辑器请求遇到 `cache_publication_owner`，改用已有 LoadJob 原生加载入口完成取证；该编辑器所有权问题未在本轮修复。`native_probe02/03` 是白天探索，不作为夜间通过依据；`native_night_red02` 的 witness World3D 绑定为空，黑图样本明确排除，修正夹具后保留完整 red03。

普通住宅 candle 的视线射线加分确实能因细柱换灯，但它使用角色位置，且公会不走该链，不拿它冒充本次根因。对应最小诊断留在外部 `P/diagnostic_sources/`，本轮不修改住宅照明规则。

工作区原有彩窗、室内反射等其他会话改动保持原状。本次提交只包含 observer 修复、对应测试/探针与本记录；测试运行于当时工作区，未宣称已验证其他未提交功能的独立交付。
