# 最新代码加载与渲染审查

审查基线：`d1121df18039605a19a7f4aeedc9bd05b0e7b989`，2026-10-17 拉取时及收尾复查时的 `origin/main`。主工作区已 `pull --ff-only` 到该版本，原有 `project.godot` 的 SHA 保持不变。修复分支为 `codex/latest-map-runtime-review`。

审查直接从新增生产代码及调用链开始，未以历史待办选择问题。三个疑点及其基线复现完成后，核对 MCP 入口时误读到 `world_editor_mcp.md` 开头夹带的历史性能记录，随即停止读取；该段没有用于产生本轮发现或评估收益。之后仅以源码和独立实验核实。

## 两项现行路径问题

**P2：目标 GPU 预加载完成后，私有视口仍持续绘制。**

`TargetScenePrefetch._loaded()` 创建 `UPDATE_ALWAYS` 视口，完成两帧预热和后台来源验证后，将结果标记 ready 并保留资源租约，但没有停止更新。玩家在传送点附近时，接近检查持续续期，私有目标会长期与当前地图同时渲染。

修复：两帧预热结束即设置 `UPDATE_DISABLED`。GPU 网格、材质和离树目标继续由原有 `_warm`、`_scene` 保持，确认传送仍接收同一份资源；取消、来源变化及退出的清理路径不变。

真正 MapLoader、私有 GPU 预热和后台校验完成后，连续观测 8 帧：测试进程没有其他活动 3D 视口，基线每帧 **2 次 3D draw call**，修复后每帧 **0 次**。Viewport 的 `get_render_info()` 在停止更新后保留最后一帧统计，因此证据同时保存 `last_viewport_draws` 和实际 `total_frame_draws`，不把前者误当作新增绘制。

**P2：容量不足的 GPU 预加载会抢占已完成 CPU 预加载，并反复重做。**

`ResourceAdmission.reserve_background()` 原先直接走前台 `reserve()`。后者在容量不足时请求抢占后台工作，也允许超预算的必要任务独占运行。GPU 预加载尝试因此可能取消它自己的已完成 CPU 前置结果，下一次接近检查重新启动 CPU 准备；不足以容纳预加载的预算也可能被当成允许独占的前台预算。

修复：后台申请只使用当前剩余容量，提前拒绝超出总预算或剩余字节的请求；前台 `reserve()` 的独占、抢占和实际释放后再回收额度的语义保持。

实际临时地图、1 GiB 源侧预算、连续 3 次接近检查：两版均拒绝 3 次 GPU 升级，CPU 准备启动次数 **3 → 1**，修复后保留已验证的 CPU 结果供确认传送使用。512 MiB CPU 额度继续保留到消费/取消，它是保守预留，不是实测 RSS。必要前台任务仍可请求取消，资源未真正释放前额度不归还。

## 一处兼容函数缺口

**P3：旧来源刷新工具没有清掉新增弱材质、纹理目录。**

`PoseSave.refresh_export_sources()` 原先仅清强缓存和待上传图像。仍有独立消费者保留旧材质时，同路径图片替换后调用该工具，再构建材质会通过弱目录恢复旧像素和旧来源 SHA。修复为统一调用 `SurfaceMaterials.refresh_sources()`，同时清理强缓存、弱目录和缓存访问记录；独立存活的旧消费者保持不变。

红色 albedo 改为蓝色、DirectX normal 同路径替换的真实 PNG/GPU 纹理测试，验证新材质像素及 SHA 更新、旧消费者像素不变、最后旧消费者结束后资源释放。

**调用范围已核实：该旧函数目前没有现行生产调用者，当前原生引用保存不调用它。** 本项是兼容接口修复，不作为“当前保存必现错误”或生产数据损坏结论。

## 验证与收益口径

冻结基线的新用例 33 项检查、11 项预期失败；修复版本 33/33。11 项失败属于上述两个现行问题和一个兼容缺口的重复观测，不代表 11 个独立缺陷。

最终选用 13 组回归，合计 **1674 项检查/比较，0 失败**；总数包括重复覆盖和地形差分比较：

| 用例 | 模式 | 检查/比较 |
| --- | --- | ---: |
| latest_runtime_blind_review | headless / Vulkan | 18 / 33 |
| resource_admission | headless | 20 |
| approach_prefetch | headless | 25 |
| native_retirement_contract | headless | 16 |
| terrain_incremental | headless | 1132 |
| terrain_cpu_patch | headless | 254 |
| target_scene_prefetch_gpu | Vulkan | 25 |
| material_residency_budget | Vulkan | 8 |
| native_residency_gpu | Vulkan | 26 |
| distant_building_proxy_gpu | Vulkan | 24 |
| material_publication | Vulkan | 46 |
| latest_prefetch_http | Vulkan + 真 HTTP MCP | 47 |

HTTP 复用当前 UI 的事件表单、保存/重开、撤销重做、非法请求无副作用、游戏试玩和传送流程，验证 ready 目标停止绘制时源地图仍可玩，确认传送消费目标 GPU 结果并在目标帧后释放预加载租约。没有新增工具、参数或二维适配器。

材质发布用例要求真实 renderer，一次 headless 调用被其前置条件主动拒绝；最终验收使用 Vulkan 的 46/46，不将拒绝算作生产发现。部分既有测试只重定向固定输出目录，执行副本和原始测试的 SHA 均归档，没有更改其校验条件。

额外检查地形增量发布的 CPU 缓存监听：20 次真实 prepare/publish 后连接数始终为 2，未增长；显式 invalidation 能移除 CPU 缓存。本疑点未成立，没有据此修改生产代码。

FPS、耗时、工作量分别判断：本轮已实测减少空闲目标绘制和重复 CPU 准备工作；未测整图 FPS、加载或传送总耗时，不宣称这些维度提升。既有地形回归打印的时间不属于本轮修复收益。

GPU 均通过 `tools/run_godot_background.py` 在不激活的独立桌面运行；临时地图和资源输出在外部 `rmmo_runtime`。正式地图未改动，截图未上传查看。

## 归档及分支关系

精简证据：`review_artifacts/latest_map_runtime_blind_20261017/evidence.json`。
完整对照、源码快照、测试副本及日志：`D:/code/rmmo_runtime/review_artifacts/latest_map_runtime_blind_20261017_d1121df/`。

上一轮未发布修复仍保存在 `codex/map-load-render-review`（末尾 `e26ed92`）。本轮直接审查公开最新版本，没有自动混入那些提交；本轮通过不能视为上一轮修复已进入主分支。
