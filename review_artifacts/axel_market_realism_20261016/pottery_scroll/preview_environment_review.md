# 资产预览共享反射环境验收（2026-10-16）

资产预览和缩略图原有 Environment 只有纯色背景及环境漫射光，没有方向性的天空反射。新增共享中性 ProceduralSky，为正确的玻璃、釉面与金属提供反射方向信息。此项属于编辑器预览能力修复，未修改地图天气、模型材质或资源目录。

## 生产接口与调用

静态接口：`preload("res://scripts/world_editor/asset_preview_environment.gd").apply_reflections(environment)`。

helper 仅赋值当前预览 Environment 的 `sky` 与 `reflected_light_source`，采用中性灰天空/地面渐变、`Sky.RADIANCE_SIZE_64`、`Sky.PROCESS_MODE_QUALITY`，固定配方版本 1。每次创建独立资源。原背景色、ambient、曝光与主光保留。实际调用点为 `asset_preview.gd` 和 `asset_thumbnails.gd` 各自的 `_ready()`。

UI 导入、MCP `repair_thumbnails` 和 `save_prefab` 均调用已有 `asset_thumbnails.queue_import`，因此使用相同管线；没有增加用户参数或 MCP schema。既有磁盘缩略图不会因本 helper 自动批量重建。

## 验证边界

Godot 4.7.2 headless 实例化真实两个 UI 类并检查其配置：**43 项通过，0 失败**。验证反射源、64 radiance、资源隔离、全部其他 Environment 存储属性保持、私有 World3D、原主光角度/能量、地图环境资源身份与属性保持、无模型加载和文件写入。退出码 0。

回执：`preview_environment_cpu.json`，SHA-256 `c5af78b6bedc755ce073e095c6a6385da055ed54ea6054f3d6cab4321754ffc8`。测试源：`test_preview_environment.gd`。本回执仅确认 CPU 配置与隔离，GPU 画质、缩略图真实渲染和新一轮内容视觉验收由串行 `gpu_realism_v3_01` 接续；本次未启动 GPU，也未宣称视觉通过。

| 生产文件 | SHA-256 |
| --- | --- |
| asset_preview_environment.gd | `2d346d167ca52f8be8aad985438d0631867795e9e02b2ce7bb65faa2613debd9` |
| asset_preview.gd | `a1cf3da3d8b0feed3f82b6e1e1b516f7deb7e5e149b16507ee0b0e4446d766e4` |
| asset_thumbnails.gd | `49d47b1ea545e5ea5c5b761b8012c87a291c136a4abc85f6d2602a5b73636150` |

## 依据

Godot 官方 [Environment 文档](https://docs.godotengine.org/en/4.5/classes/class_environment.html) 说明 `REFLECTION_SOURCE_SKY` 可在保持其他可见背景模式时使用 Sky 作为反射源；[ProceduralSkyMaterial 文档](https://docs.godotengine.org/en/4.2/classes/class_proceduralskymaterial.html) 说明其天空/地面渐变与方向光。实际属性与枚举使用本项目 Godot 4.7.2 编译并运行验证。该配方是预览用中性照明，并非对游戏地图物理天空的替代。
