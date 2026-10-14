# RMMO 工具与案例入口

## 先找当前接口

项目当前位于 `D:/code/rmmo`，运行资源常在 `D:/code/rmmo_runtime`；这是定位线索，不是跨环境固定路径。以cwd、AGENTS和实际content_root配置为准，先查文件是否存在。母版/候选不放skill里。

- 静态资源：`scripts/world3d/gltf_map_io.gd`、`compiled_asset_cache.gd`、`compiled_asset_footprint.gd`、`compiled_asset_preparation.gd`。
- 纹理/风场：`scripts/world3d/runtime_texture_cache.gd`、`wind_material.gd`，以及当前叶片背光处理代码。
- 元数据与模型描述：查当前 `rmmo_visibility_range`、`rmmo_collision`、`rmmo_editor_picking` 消费实现，不按名字推测行为。
- 角色：沿实际骨骼/动画管线；需要时读同级技能 `../rmmo-character-art/SKILL.md`（相对技能目录的路径），避免套静态资源验证器。

Windows GPU测试使用项目 `tools/run_godot_background.py` 非激活独立桌面；headless仅用于支持的逻辑/结构检查，不作为真实GPU画质证据。先检查是否有其他GPU任务占用，串行拍摄。截图隐藏角色渲染模型；计时后隐藏、拍完恢复，不改变碰撞、加载就绪条件或计时范围。

## 图片上传流量

在调用图像查看工具前运行技能内 `scripts/prepare_review_image.py <图片>`；默认原尺寸质量92，校验后替换原 PNG。精确像素验收加 `--lossless`；仍被正在运行的对比器或归档报告引用的原图可临时加 `--keep-source`，迁移证据时更新路径和 SHA。这只压缩发送给 OpenAI 的验收图片，不修改模型内贴图。`view_image` 使用 `detail: "original"` 避免再缩放；当前 Windows 工具对 WebP 保留字节但可能返回 `data:application/octet-stream;base64,...`，在 `functions.image` 转发前仅将 MIME 改为 `data:image/webp;base64,...`，不要把完整 base64 打印为文本。工具行为改变时重新检查实际格式。

## 可复用的已验脚本

2026-10-11案例代码在 `review_artifacts/town_asset_size_audit_20261011/`：

|脚本|用途与边界|
|---|---|
|`review_lossless_candidates.gd`|baseline/candidate独立进程导入、native保存重开、真实footprint、近中远/细节×静止和两个风时刻；compare阶段检查语义与图像差。`--allow-texture-change`只是允许比较有损图像，不代表画质通过|
|`review_candidate_shadows.gd`|补接收阴影地面与投影视角；复播已验payload并核SHA，不代表当前generator命中性能|
|`review_isolated_cache_invalidation.gd`|仅修改/恢复隔离源副本，验证旧native/footprint/冻结准备拒绝；generator变更返回deferred，不改旧manifest标签|
|`architecture_lossless.py`|当前已知GLB的可达图及严格重复清理；不支持的扩展、skin/animation/extras不能假设兼容|
|`inventory_editor_picking.py`|确定的同部件LOD组添加metadata并验证BIN/其他JSON不变；不是通用自动识别所有模型的工具|

这些是案例工具，**包含日期、资产路径、输出白名单和具体组名**。先读参数和保护逻辑，再复制适配为本轮隔离review任务；不要照抄运行并覆盖旧验收或把旧32项全重跑。保留输出根验证、不可变源SHA、失败退出和恢复逻辑。相机配置读JSON时注意数字类型；新脚本先做headless语法/参数检查。

直接调用Python `run_background` 时返回 `subprocess.CompletedProcess`，从returncode/stdout读取结果，不按二元tuple解包；以当前工具源码为准。基线复用仅在源SHA、相机、灯光和相关渲染代码仍兼容时允许，记录原证据目录；代码变化不能以文件名相同为理由重用。

## LOD拾取协议（可选，先确认当前代码）

节点extras中的协议：

```json
{"rmmo_editor_picking":{"version":1,"group":"asset_local_part","role":"canonical"}}
```

同部件替代LOD一组，恰好一个canonical，通常LOD0；其它role为`render_lod`，且必须原本`rmmo_collision:"none"`。独立树干、真实walk/block节点不能误混组。坏组保守回原路线，不能丢选择。单网格不伪造LOD。新增metadata是单独候选，证明几何/图片/风场/原LOD不变；消费开关与HTTP选择/刷材质/保存重开由相应集成验证覆盖。

## 本轮经验来源（仅案例，不是固定预算）

- `docs/town_asset_size_audit_20261011.md`：无损清理、彩旗quality、植物保留4Kalpha与2KPBR、预算与实占区分。
- 同案例 `candidate_handoff.json`、`selected_visual_review.json`：最终选择与精确证据，早期构建pending记录不代表最终状态。
- `pennant_balanced_visual_review.json`：压图收益很大仍因白边/布纹微对比可见变化而退回。
- `reachability_reconciliation.json`：texture.source存在不等于mesh实际使用；须区分旧材质引用和无材质引用。

当时的Godot版本、GPU、2K/4K尺寸、1/255像素差、文件大小和LOD阈值仅是案例结果，不成为新模型固定验收阈值。
