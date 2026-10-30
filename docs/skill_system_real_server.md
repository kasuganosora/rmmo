# 真实服技能、属性与状态接入

本轮针对 `feat/real-server-transport`，与 Go 服务端共同技能／属性核心配套。没有改变正式美术、地图或数值资源；联调数据由 `tools/real_skill_fixture.py` 写入临时目录。

## 玩家可用行为

- 玩家与 NPC／怪物目标都使用服务器地图和 generation。队友单体治疗、复活可选择其他真实玩家；复活邀请通过现有 UI 接受，成功后重新完成当前代次 Ready。
- 角色面板只展示服务器提供的有效属性、SP 和资源。不存在的魔攻／魔防等字段显示“未提供”，不再用 Mock 默认值补齐。NPC 投影也不保留随机或默认攻防。
- 技能列表显示服务器效果数组、等级、学习条件、下一级 SP／金币和重置价格。已学被动不产生主动施法权限。等级返回的有效定义用于显示与施法目标类型，规则版本或世界变化清理定义缓存。
- 学习、升级、技能重置和属性重置走低频 `skill-training` HTTP 操作；序号和资格由服务器决定。网络不确定时保留原序号，不把同一次写操作重放为新操作。
- 施法、攻击、状态取消和运行时推送保持 WebSocket。Buff 取消仅对服务器明确公布的 cancelable ID 开放，并携带捕获的状态序号。旧服务器缺少权限字段时不显示取消能力。
- 定向区域技能使用实际瞄准方向。真实点击移动读取服务器 `statuses.control` 的移动许可与速度倍率，按网络步长选择末段行走，避免加速后在终点往复；客户端仍只渲染权威位置，不新增本地物理预测。

基础 `remote_boundary.gd` 继续为未接入操作兜底；本轮学习／重置等入口在 `real_gameplay_api.gd` 显式覆盖。运行时资源保持既有 13 类，新训练视图位于 `skills.training`，移动控制位于 `statuses.control`。未启用学习策略的服务器返回禁用视图；旧服未提供控制字段时保持原普通速度展示。

## 验收

```sh
godot --headless --path . --script res://tools/test_remote_skill_contract.gd
godot --headless --path . --script res://tools/test_remote_quest_social.gd
godot --headless --path . --script res://tools/test_status_icon_bar.gd
python3 tools/generate_remote_boundary.py --check
python3 tools/generate_server_protocol.py --check
python3 tools/test_real_server_integration.py --server-bin /path/to/gameserver --server-repo /path/to/rmmo_server --skill-system
```

集中契约验证包括玩家目标代次失效、实际方位、无 Mock 属性、学习请求序号、状态权限、旧服能力回退、protobuf false 默认字段、4 倍移速点击终点及禁止移动。双客户端验收使用真实 Go 服务、SQLite 和 WebSocket，覆盖学习／升级／前置、被动授权、属性重置、复合 Buff 与取消、治疗、死亡／复活、代次恢复、重置和重连；所有失败断言累积为非零退出，脚本异常和缺少成功标记也由 Python 运行器判失败。

本轮实际执行：技能契约 34 条、旧任务／社交契约 18 条、状态栏脚本全部通过；双真实客户端技能链路 58 条全部通过，零脚本错误。生成边界／协议检查与 Python 编译通过。服务器二进制由本轮最终冻结代码构建，提交标识及全量 Go 验收见服务端总记录。

该合成 headless 验收不代表生产负载容量；未运行整个客户端测试库，未开展 GPU 美术验收。
