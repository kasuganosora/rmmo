# Godot 4.8 本机画质控制（2026-10-30）

编辑器顶栏新增“本机画质”：可保存接触阴影与多次反弹 AO、恢复默认或恢复上一次设置。设置影响本机编辑器和游戏，不属于地图，也不插入地图撤销历史。默认保持两项关闭，没有批量改变现有场景光照。

## 生效方式

本机 candidate07/08 的实际接口是项目级启动设置：

- `rendering/lights_and_shadows/contact_shadow/enabled`
- `rendering/lights_and_shadows/multi_bounce_occlusion/enabled`

后者直接控制 Forward+ 启动时的 shader 宏，不能在修改地图环境后假称实时生效。编辑器分别显示 `applied`（当前启动设置）、`saved`（已保存设置）和 `restart_required`；保存后需要退出并重新启动编辑器/游戏，单纯地图重开或 F5 不等同于进程重启。不支持的渲染器会明确提示需使用 Forward+。

`project.godot` 通过 Godot 原生 `application/config/project_settings_override` 指向 `user://rmmo_rendering_override.cfg`。这个独立文件只更新两项渲染设置和上一版本，保留已有未知字段，不写工程或资源根路径；普通 `override.cfg` 中的 `content_root` 等设置保持有效。偏好文件缺失时正常启动。若工程禁用启动覆盖或指定其他覆盖文件，面板与 API 拒绝写入，不接管他人的配置。

写入复用编辑器共享准备预算与后台任务队列，完成后原子替换文件、归还租约。在准备临时文件前和发布前均比对原文件 SHA；准备过程中有外部修改时拒绝覆盖，保留外部更改。Windows 原子发布会启动文件替换辅助进程，因此不在主线程等待它。返回成功后才展示已保存状态。一个保存尚未完成时，不允许另一项保存覆盖它。

## 3D MCP

| 工具 | 行为 |
|---|---|
| `get_rendering_preferences` | 读取当前/已保存/待重启状态、是否仍在保存及 `last_result` |
| `set_rendering_preferences` | 可选布尔参数 `contact_shadows`、`multi_bounce_ao`，至少提供一项；返回 `pending=true` 时轮询上一个工具，检查 `last_result.ok` |
| `reset_rendering_preferences` | 恢复默认关闭；同样后台保存、下次启动生效 |
| `restore_rendering_preferences` | 恢复上次保存的偏好；没有前一版本时明确失败，不影响文件和地图 |

UI 和 HTTP 使用同一服务。未知字段、非布尔值、空修改以及没有前一版本的恢复都在写入前拒绝。

## 验证

证据：`D:/code/rmmo_runtime/review_artifacts/godot_4_8_adoption_20261029_01/editor_usable_20261030/` 下的 `rendering48_http_03/`（最新 UI/HTTP）及 `rendering48_http_02/`（新进程与画面对照）。

- `test_rendering_preferences_http.gd`：真实独立桌面 UI/HTTP **38 项通过，0 失败，0 引擎诊断**。包括工具发现、非法调用无文件副作用、UI/MCP 互相读取、后台完成、恢复默认/上一次、地图记录/元数据/脏标记/撤销不变、共享队列释放，以及未知字段保留和临时文件完成后发生外部修改时拒绝覆盖。
- 实际保存结果：当前 `false/false`，已保存 `true/true`，`restart_required=true`。运行中的 ProjectSettings 仍为 `false/false`，没有冒充即时切换。
- `test_rendering_preferences_startup.gd`：同一隔离 APPDATA 中再次启动两次。无偏好文件时两项为 `false`，有偏好文件时两项为 `true`，渲染器均为 Forward+；每次打印的 `content_root` 仍是原隔离工程路径。两次均退出 0、无诊断。
- `rendering_off.webp` / `rendering_on.webp`：相同相机、灯光和合成几何的联动开关对照，已实际查看；开启后的红色 AO 材质不再过度压暗，几何和光照方向保持一致。截图采用原尺寸、有损 WebP quality=90；SHA 与参数见 `image_review.json`。这是两项联动的功能画面对照，不是每种几何的接触阴影独立质量验收，也不是整城性能测试。
- `rendering48_http_01` 保留了首次测试脚本变量类型推断失败记录；显式类型修正后重跑通过，没有忽略失败。

实现文件：`scripts/world_editor/rendering_preferences.gd`、`rendering_preferences_panel.gd`，以及 `world_editor.gd` 的初始化/HUD 挂接、`mcp_schema.gd`/`mcp_ops.gd` 的四个工具。没有修改现有 environment_settings、environment_panel、weather_controller 或 workspace 的用户工作。
