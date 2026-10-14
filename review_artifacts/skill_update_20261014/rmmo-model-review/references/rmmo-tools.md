# RMMO 工具与案例入口

## 先找当前接口

项目当前位于 `D:/code/rmmo`，运行资源常在 `D:/code/rmmo_runtime`；这是定位线索，不是跨环境固定路径。以cwd、AGENTS和实际content_root配置为准，先查文件是否存在。母版/候选不放skill里。

- 静态资源：`scripts/world3d/gltf_map_io.gd`、`compiled_asset_cache.gd`、`compiled_asset_footprint.gd`、`compiled_asset_preparation.gd`。
- 纹理/风场：`scripts/world3d/runtime_texture_cache.gd`、`wind_material.gd`，以及当前叶片背光处理代码。
- 元数据与模型描述：查当前 `rmmo_visibility_range`、`rmmo_collision`、`rmmo_editor_picking` 消费实现，不按名字推测行为。
- 角色：沿实际骨骼/动画管线；需要时读同级技能 `../rmmo-character-art/SKILL.md`（相对技能目录的路径），避免套静态资源验证器。

Windows GPU测试使用项目 `tools/run_godot_background.py` 非激活独立桌面；headless仅用于支持的逻辑/结构检查，不作为真实GPU画质证据。先检查是否有其他GPU任务占用，串行拍摄。截图隐藏角色渲染模型；计时后隐藏、拍完恢复，不改变碰撞、加载就绪条件或计时范围。

## 图片上传流量

在调用图像查看工具前运行技能内 `scripts/prepare_review_image.py <图片>`；默认原尺寸 **quality=90、lossless=false、method=6**，实际重编码已有 WebP，不能只看后缀。返回记录包含目标路径、SHA、字节、尺寸、编码参数，并保存小型 `.review-image.json` 记录；相同输出 SHA/参数再次输入时直接复用。原 PNG 校验后可删除；仍有本地对比/归档引用时加 `--keep-source`，迁移证据后再清理。已有 WebP 加此选项会输出独立 `.upload.webp`，保留输入。

`--lossless` 只用于本地精确像素参考，不作为默认上传图。要从该本地参考生成上传副本，再以默认质量90运行并按需 `--keep-source`；使用返回的路径查看/发送。既有有损图不能凭无损编码恢复信息。这只压缩验收图片，不修改模型贴图。

重复调用复用输出时，不顺带删除先前已保留的源图；待本地对比或引用迁移完成后按清理规则处理。中断留下的 `.tmp`/`.review-backup` 先检查恢复，不盲目覆盖重试。

`view_image` 使用 `detail: "original"` 避免再缩放；当前 Windows 工具对 WebP 保留字节但可能返回 `data:application/octet-stream;base64,...`，确认载荷是 WebP 后在 `functions.image` 转发前仅将 MIME 改为 `data:image/webp;base64,...`，不要把完整 base64 打印为文本。工具行为改变时重新检查实际格式；不得把重新编码成 PNG 的载荷当作已完成质量90上传。

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

## 公会、家具与住宅材质复验入口

下列为 2026-10-12 至 14 的经验定位线索。先检查当前文件和接口；历史报告的图片可能已清理，阅读前核对实际存在与 SHA，不能把历史通过直接当本轮画面证据。专项判断见 [反复问题与处理经验](recurring-failures.md)。

|任务|资料/代码与使用边界|
|---|---|
|屋顶收口、平台、薄装饰板、布幡及活动家具|`docs/axel_guild_finish_review_20261012.md`、`docs/axel_guild_entry_alignment_review_20261012.md`、`docs/axel_guild_repairs_20261012.md`；参考定义该公会，不是全项目统一造型。|
|玻璃、魔法石、星尘、石墙与真实开孔|`docs/axel_guild_reference_recheck_20261013.md`、`scripts/world3d/tinted_glass.gd`、`streetlamp_lights.gd`；特定彩窗近似需显式语义识别，不能批量作用于所有透明材质。|
|屋瓦/灰泥表面与实际 GPU 绑定诊断|`docs/house_surface_relief_20261014.md`、`tools/diagnose_house_surface_relief.gd`、`tools/review_house_surface_relief.gd`；查看 `MeshInstance3D.get_active_material(surface)`，按实际 `Texture2D.get_image()` 数据核对同格式解码像素，记录受检面的光照入射与切线。读取需等待导入/上传/场景稳定。|
|正式素材库及材质发布复验|`tools/test_guild_street_published_catalog.gd`、`tools/verify_published_house_surface_relief.gd`；使用正式目录源，测试场景仍隔离，不覆盖用户地图。|
|运行特效误入拾取/碰撞|`tools/test_editor_light_effect_picking.gd` 与实际 `_picking_node_enabled`/`_mark_light_effect`；当前 `runtime_light_effect` 标记和 `rmmo_collision` 需查看消费方，不靠节点名识别。|
|材质版本发布与回退|`tools/publish_house_surface_relief.gd`；参考有效默认参数、SHA 冲突保护及收据失败回退逻辑，不直接运行日期/资产硬编码的历史发布命令。|

历史 `tools/cleanup_validation_thumbnails.py` 按目录和图片扩展名选择文件，不能据其名字认为已做依赖或证据引用审计；未完成本轮用途分类和精确清单核对前，不运行其批量删除模式。
