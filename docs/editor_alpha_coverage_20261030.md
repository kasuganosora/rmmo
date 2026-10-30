# 4.8 编辑器透明裁切 mip 覆盖率适配（2026-10-30）

## 范围与行为

本轮将 Godot 4.8 `Image.generate_mipmaps(false, preserve_alpha_test_coverage, alpha_test_threshold)` 接入表面颜色贴图导入。默认关闭，默认保真仍保留原像素；不是整批素材转换，也没有修改现有模型的 GLB MASK 导入产物。

- UI「导入表面贴图」增加「保持远景叶缘 / 发丝轮廓」及裁切阈值，默认关闭、阈值 0.5。说明限颜色裁切贴图，不用于 normal、玻璃等连续透明材质。
- 3D MCP `import_surface_material` 同步两个可选参数：`preserve_alpha_test_coverage: false`、`alpha_test_threshold: 0.5`，后者范围 0–1。UI 和 HTTP 共用导入服务、预算、取消和发布流程。
- 主动开启时，材质同时记录 `alpha_scissor_threshold`，实际绘制使用同一 cutoff；关闭时保留旧透明模式。不能只修改 mip 而继续用 alpha blending 来冒充裁切覆盖率验证。
- 关闭选项时，不同阈值参数复用原产品和材质身份。开启后，精确参数纳入工作去重、目录和材质身份；同源不同阈值、保真/DDS 互不覆盖。
- 保真路径 mip0 RGBA 字节不变，改变只发生在较小 mip 的 alpha。DDS 是用户显式选择的有损模式，不声称其 mip0 保真。
- 独立描述位于材质库根目录，以兼容既有目录查找。纹理位于 `alpha_coverage/<选项摘要>/<原PNG摘要>[.source].png`，保留原 PNG 摘要命名合同。

主要修改位置：

- `scripts/world_editor/surface_texture_import_worker.gd`：参数身份、颜色 mip/DDS 生成、独立产物与材质描述。
- `scripts/world_editor/surface_texture_imports.gd`：提交、共享工作组及后台调用转发。
- `scripts/world_editor/surface_paint_panel.gd`：实际导入对话框控件。
- `scripts/world_editor/mcp_schema.gd`、`mcp_ops.gd`：当前 3D 工具发现与分发。
- `scripts/world3d/surface_materials.gd`：仅材质 cutoff 校验及绘制语义；纹理准备/缓存的其余同期变更属于主任务。

HTTP 参数示例（通过现有 `tools/call` 调用）：

```json
{"name":"import_surface_material","arguments":{"path":"<外部资源根内的颜色PNG>","compression":"source","preserve_alpha_test_coverage":true,"alpha_test_threshold":0.5}}
```

## 测试证据

所有产物位于外部临时内容根，GPU 通过 `run_godot_background.py` 在独立桌面运行，未修改用户地图。引擎为默认 4.8 beta1 补丁 candidate07，SHA256 `dabba1322488f959bddbd1d20ebdf40ee788c918c1a8b193a533d0472efb7375`。每轮 `freeze.json` 固定脚本、输入及引擎 SHA。

证据根：`D:/code/rmmo_runtime/review_artifacts/godot_4_8_adoption_20261029_01/editor_usable_20261030`。

| 测试 | 结果 | 验证范围 |
| --- | --- | --- |
| `alpha_coverage_cpu_03` / `tools/test_surface_alpha_coverage.gd` | 32 项通过，0 诊断 | 原图与 mip0 字节保持、关闭选项复用、不同阈值独立、目录重开、实际阈值校验与精度 |
| `alpha_coverage_cpu_04_red` → `alpha_coverage_cpu_05_green` / 同上 | 旧行为 40 通过 / 1 失败 → 修复后 41 项通过，0 诊断 | 真实阻塞 STEX 描述目标导致原子发布失败；coverage 明确失败，默认行为保留原 fallback；不发布材质描述、不改原输入和占用目标 |
| `alpha_coverage_gpu_05` / `tools/test_editor_alpha_coverage_gpu.gd` | 38 项通过，0 诊断 | 真实 HTTP、实际 UI 选择、source/DDS 的 StreamedTexture2D、裁切绘制、撤销重做、保存重开、释放、流式近中远观察 |
| `alpha_coverage_gpu_07` / 同上 | 71 项通过，0 诊断 | 增加 HTTP 工具发现；同源 .5 source、.7 source、.5 DDS 三个变体完整预制件打包/放置/撤销重做/保存重开 |

GPU07 使用主任务新增的 `published_texture_copy.gd`：三变体打包后仍是三个不同的原生纹理产物，描述文件和完整 STEX mip 负载与导入原件 SHA 完全一致；重开后仍为 StreamedTexture2D。只拷 PNG 会丢覆盖率 mip、不同阈值会被同名 PNG 合并的旧缺口已由该打包路径处理。该 helper 的实现归主任务，本测试是其真实 HTTP 回归。

测试耗时分别为 CPU 9.863 秒、GPU05 31.707 秒、GPU07 38.214 秒，包含测试宿主、HTTP、截图和读回；这些不是地图加载性能数据。

CPU05 green 额外验证错误发布分支，11.676 秒。显式 coverage 遇 STEX 持久发布失败现在返回错误，导入服务沿既有失败分支结束，不再将丢失选项的产品作为成功材质发布。可以留下未被材质描述引用的不可变中间产物，未为此删除共享文件；这是原子发布既有约定，不声称整个磁盘零写入。该错误分支修复发生在 GPU07 后，未为三行错误处理重跑无关 GPU 场景。

失败样本保留：CPU01/GPU01/GPU06 是测试脚本 parse 错误；GPU02/03 冻结目录漏了同期新增生产依赖，仅 parse 阶段失败。CPU02 的周期图案是有效的算法边界，不按坏样本删除：原 coverage 10.9375%，普通 mip2 为 0%，保覆盖 mip2 为 25%，因粗 mip 离散化出现过补偿。因此该选项必须可选，不能对全体模型自动开启或声称普遍改善。

最终确定性 64×64 裁切样本：原覆盖率 28.759765625%，普通 mip2 为 5.078125%，保覆盖 mip2 为 26.171875%。判定针对 alpha-test 后留下的样本和实际画面，不以 alpha 总和代替可见结果。

## 同相机实际画面

固定 768×512 正交相机、相同材质与曝光；左右是普通 mip 和保覆盖 mip，上中下为近中远投影尺寸。两列位置相差精确 384 像素以避免采样相位差。

| 条件 | 普通 mip 近/中/远可见绿色像素 | 保覆盖 mip 近/中/远可见绿色像素 |
| --- | --- | --- |
| 新建原生流式 owner，45 帧观察 | 0 / 0 / 0 | 9550 / 964 / 68 |
| 从实际 STEX mip 链建立测试专用全驻留纹理 | 9550 / 964 / 0 | 9550 / 964 / 68 |

全驻留仅用于隔离算法与驻留状态，生产代码没有增加预热或整图读取。实际检查了两张图：全驻留下近中画面一致、远处 coverage 保留轮廓；冷流式原图列全空，coverage 近中远正常。没有用全驻留对照掩盖流式问题。

图像目录：`alpha_coverage_gpu_05/content/cache/world3d/alpha_coverage_gpu_11547680/`。

| 已实际查看的图像 | WebP SHA256 |
| --- | --- |
| `coverage_near_mid_far.webp` | `9d50a167a33a74745444f2e29e2ff90daeb0b4d891cd622d4a517d70a07c8b0c` |
| `coverage_streamed.webp` | `c9d0b88658be78b4ae71e50c1fdc49836b9736398026bbb9b480736d558b67f3` |

均为实际有损 WebP quality=90，原尺寸，旁有 `review-image.json`。GPU07 生成的两张原 PNG SHA 与 GPU05 完全相同，因此复用上述压缩查看证据，未再压缩：全驻留 PNG SHA `3d541d92ccdc1782639fd4bd0875f1e26cba3d9d2c0381fad71400bb39ee5e6a`，冷流式 PNG SHA `e0a5f3f4ed451c05dbdca5a9f8af3606010a7c74616c413733c66225e1f0eb31`。

## 原生流式 alpha discard 反馈缺口

上述普通 mip 冷流式全空在 candidate07 中是单独问题，不能归为 coverage 算法收益。GPU05、GPU07 均观察到：

- 普通 mip：`current_mip=3`、`request_mip=15`、`visible_demand=false`、`status=no_visible_demand`、`ready=true`。
- coverage mip：`current_mip=0`、`request_mip=0`、`visible_demand=true`、`status=ready`。
- 两者 `budget_limited=false`，不是预算拒绝；普通 mip 没有请求细 mip。

本机候选引擎源码 `D:/tools/godot-4.8-build/source/godot-4.8-beta1/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl` 在 1348–1358 行先执行 ALPHA_SCISSOR discard，1362–1395 行才写纹理流式反馈。`modules/texture_streaming/texture_streaming.cpp` 约 901 行跳过零反馈；约 304–330 行观察快照把没有可见需求视为 ready。初始粗 mip 的 alpha 全低于 cutoff 时，裁切在反馈前消掉所有 fragment，无法请求能显示几何的细 mip。实际观测、画面与源码顺序相符。

默认表面导入仍使用既有 alpha blending，本次没有将所有默认材质改成 alpha scissor。既有 GLB MASK/原生裁切模型可能命中此缺口；需要单独引擎修复与原图对照，不能用 coverage 选项掩盖，也没有在本记录声称引擎已修复。主任务另行委派引擎验证，其后续结论应补独立构建 SHA 与 red/green 证据。

## 资源成本与交付边界

GPU05/GPU07 原输入 PNG：1315 字节，SHA256 `f792fb4919a218fd0c5c18bd39d0971c5a6ac711d4b909325bfd886c06c90a36`。64×64 RGBA mip0 为 16384 字节，完整 RGBA mip 链 21844 字节。无几何减面、LOD、碰撞或风场改动，这些项目不适用；测试 quad 不是新正式美术资产。

| 产物 | 实际文件字节 | 实际文件 SHA256 |
| --- | ---: | --- |
| 普通 source STEX | 21944 | `fe7ba8dc5aeb5fb03935aae65268f4266790022a1e5fcc4f36b3d0a684b9b494` |
| coverage .5 source STEX | 21944 | `051118508c3535c2798ce2c3e9a60aef5cb8e949dc77538decbb159c422d860a` |
| coverage .7 source STEX | 21944 | `e3bb98fcecf222f838e33839f0067c1ec07fb06fca7b562e1ff32bfd83cc2ef1` |
| coverage .5 DDS STEX | 5588 | `5e456f94e62683dd813808f7b115545ec460fde82101692bf008d09ff9bc79ba` |
| coverage .5 DDS | 5616 | `6ceb708e03c857bbdb28291c1748282e6eb87ec244989ecf903c1e21f77a8f97` |

上述为文件及图像布局字节，不是实测 RSS/VRAM。DDS 压缩块负载 5488 字节；其质量未作为正式叶片/树木资产验收，本轮仅验证显式有损路径的可用性与正确携带 mip。

已通过范围：surface 颜色导入默认兼容、可选 coverage、UI/HTTP 一致性、原像素、原生流式近中远、预制件变体不污染、保存重开。未修改正式素材，不声明现有全部模型已经转换或获美术通过。

另有配置边界：source 模式的 coverage mip 保存在 STEX。主动关闭流式/切到 Compatibility，原 PNG 回退加载器仍可能重建普通 mip；DDS 自带 mip 不受此点影响。当前正式目标是 4.8 Forward+ 且开启流式，其他配置不能宣称已适配。STEX 启用但持久发布失败已改为明确失败并获上述 red/green 验证，不再静默退为 PNG 成功；没有新开另一种持久图片格式。默认原像素策略不变。

## 后续 candidate08 引擎修复复测

主任务在 `alpha_coverage_gpu_08_engine08` 使用最终编辑器代码和 candidate08 重跑完整 UI/HTTP/预制件 **71 项，全部通过、零诊断**。普通冷流式列恢复为 `[9550,964,0]`，coverage 列为 `[9550,964,68]`，分别与同相机完整驻留参考相同；两个原生纹理均 `current_mip=0`、`visible_demand=true`。不再将原版的反馈死区混入 coverage 画质收益。

引擎改动、独立 red/green、遮挡及关闭预深度时的工作量边界见 [candidate08 专项报告](godot48_cutout_streaming_feedback_20261030.md)。自定义 shader 直接 discard 和主动关闭流式的配置范围仍按各自边界保留。
