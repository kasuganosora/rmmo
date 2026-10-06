# 日月与夜云修正（2026-10-06）

用户反馈天空缺少太阳和月亮、夜间没有可辨月光、云层过亮。

现有着色器已有日月圆盘，并非没有绘制路径。本次增强太阳圆盘辐射与抗锯齿边缘，月亮加入固定月面明暗；降低体积云固定月光散射和夜间环境底光约一个数量级，同时降低薄云亮度。云仍遮挡日月，不把圆盘叠在厚云前方。

连续昼夜的满强度月光从 0.04 调到 0.16，改用较中性的冷色；手工 night 预设同样更新。手工模式已有显式保存的 sun_energy 仍受保存值控制，不覆盖用户设置。夜空明暗不再随手工月光能量增加而变亮。月亮角半径 0.018 弧度，太阳 0.009 弧度，是游戏可读性的美术调整；当前仍沿用日月相对的既有轨道，不宣称真实天文历或月相。

编辑器与游戏复用 weather_controller；检查了当前 3D get_environment/set_environment、environment_settings schema 与面板入口，无新增编辑能力或参数，保存/撤销事务保持原路径，未恢复二维 MCP。此次没有运行新的 HTTP 编辑事务测试。

验证：tools/test_celestial_visibility.gd 通过 tools/run_godot_background.py 在独立桌面、Forward+ / RX 7900 XTX 上运行，使用内存临时场景，不读写用户地图。覆盖手工和连续昼夜的日/月地平线上方方向、无遮挡圆盘像素、带云截图、月光开关的地面像素差异和阴影开启状态。截图人工检查确认夜云变暗、白天云层正常、地面可见方向性阴影。未对用户截图的街道相机进行同机位复验。

日志与图片：D:/code/rmmo_runtime/review_artifacts/celestial_visibility_20261006.log 与同名目录。另执行 tools/test_world3d_weather.gd headless，退出码 0。
