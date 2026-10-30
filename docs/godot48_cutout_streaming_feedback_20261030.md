# Godot 4.8 流式透明裁切反馈修复（2026-10-30，candidate08）

本轮编辑器适配发现真实引擎问题：原像素模式生成普通 mip 链后，细小叶片在初始低精度 mip 中可能全部低于透明裁切阈值。画面没有叶片，GPU 也不再反馈需要更清晰的纹理，导致近距离仍无法恢复。不能用默认改变原图或强制所有纹理 mip0 替代这个修复。

## 两处阻断与最小修复

1. `scene_forward_clustered.glsl` 原本先执行内置 alpha-scissor `discard`，再写流式反馈。candidate08 将既有反馈块移到内置 alpha-scissor/hash 之前，没有新增渲染遍次。
2. 仅移动代码仍不足：深度预通道已经裁掉低精度透明片元，颜色通道的 `EQUAL` 深度比较会令这些片元无法执行。`scene_shader_forward_clustered.cpp` 仅在 **有流式反馈且使用 alpha clip** 的颜色管线中保留正常的反向 Z `GREATER_OR_EQUAL` 比较；颜色通道仍然 `enable_depth_write=false`。其他管线继续原来的 `EQUAL` 行为。

默认预深度开启时，更近的不透明物体仍会阻止隐藏面的反馈。透明洞仍被原 alpha 逻辑丢弃，背景像素保留；并非取消深度测试或让透明区域写入深度。

## 先复现再修复

独立测试 `tools/test_streamed_cutout_feedback.gd` 使用同一份已发布原图 STEX，为可见与被遮挡对象分别创建全新的 `StreamedTexture2D`。三个视口依次为可见流式裁切面、不透明前景遮挡的裁切面、完整驻留参考面。相机、光照、过滤和阈值完全相同；没有纹理强制请求、预算调整、LOD 覆盖或主线程等待 worker。自动画面回归使用 `TRANSPARENCY_ALPHA_SCISSOR`、阈值 0.5；alpha-hash 属于受改动影响的代码范围，但没有据此宣称 hash、全部透明模式或 MSAA 都经过画面验收。

| 引擎 | 深度预通道 | 结果 | 可见源状态 | 可见绿色像素 | 对完整驻留参考的 RGB 不同像素 |
|---|---|---|---|---:|---:|
| 原 candidate07 | 开 | 8 通过、2 失败 | mip3、无可见需求 | 0 | 31,036 |
| 原 candidate07 | 关 | 8 通过、2 失败 | mip3、无可见需求 | 0 | 31,036 |
| candidate08 | 开 | 10 通过、0 失败 | mip0、可见需求 | 31,036 | 0 |
| candidate08 | 关 | 10 通过、0 失败 | mip0、可见需求 | 31,036 | 0 |

四个最终样本均无引擎诊断。candidate08 在默认预深度模式下，被前景完全遮挡的另一份源保持 mip3、无需求；其视口全部 147,456 像素为蓝色。可见面及参考面均为 31,036 个绿色像素和 116,420 个蓝色像素，保留透明洞。原始 PNG 的逐像素 RGB 比对为 0 差异；实际查看了原尺寸 1152×384、有损 WebP quality=90 副本。

关闭预深度时，alpha-discard 需要后置深度测试，片元原子反馈可能先于遮挡判定执行。此模式下，被遮挡源也请求到了 mip0，但画面仍正确全蓝。这项额外需求如实保留，不能把默认预深度下的工作量结论推广到关闭预深度的情况。

首版候选测试的失败样本没有删除：它将票据建立在 shader 尚未准备好的第一轮反馈上，却要求票据反映后续帧。源码确认 observation 只记录指定反馈缓冲周期；后续加载到 mip0 不会改写早期票据的 `visible_demand`。最终测试保留启动票据，再为稳定绘制后的周期建立另一票据；原版和候选均使用同一修正脚本复跑。原版仍失败，候选通过。

## 可重放交付

证据根目录：
`D:/code/rmmo_runtime/review_artifacts/godot_4_8_adoption_20261029_01/streaming_alpha_feedback_08/`。

- `stable_prepass_on_02/`、`stable_prepass_off_02/`、`candidate_prepass_on_02/`、`candidate_prepass_off_02/`：最终进程日志、反馈状态、退出码、截图及源/脚本/引擎 SHA。
- `image_review.json`：无损 RGB 比对、WebP 参数与 SHA。候选画面 WebP SHA 为 `ff7753c7c33bf3f9526c459880ffc25c8b67ba4df8caa57d39d070df42da2e3a`。
- `before/`、`after/`、`change.json`、`alpha_feedback.patch`：本轮两个引擎文件的最小改动。
- `runtime_01/source/`、`source_manifest.json`：全部 51 个累积影响文件的冻结源码；此前 49 个文件保持 candidate07 原字节。
- `official_to_08_replay/`、`cumulative_verification.json`：对官方 beta1 归档执行累积补丁，51/51 文件 SHA 与实际构建源码一致。
- 仓库 `tools/engine_patches/godot-4.8-beta1-runtime-candidate08.patch` 及同名 `.json`：可交付累积补丁和构建清单。只应用于官方原版 beta1，不能叠加到 candidate07 上。

候选二进制在 `runtime_01/engine/`，与调试符号匹配：

| 文件 | SHA-256 |
|---|---|
| `godot.windows.editor.x86_64.exe` | `69fccbed237845e578fdb279d9951ac92c71a29d2a1c7c660903064296cb3303` |
| `godot.windows.editor.x86_64.exe.debugsymbols` | `7bcda28b4b686ebe409f8c49356d4e0a86a9ff419a4b7ccc675c73d4b2849f08` |
| 累积补丁 | `9c358f0723b1ceab6865138b7d3449d855feab07d77aad33f469f9a451773a9e` |

沿用 candidate07 的 MinGW 运行时构建选项，增量构建退出 0、用时 496.25 秒；构建前后稳定入口、其符号和安装清单 SHA 均不变。

## 完整编辑器回归与默认安装

主任务使用同一 candidate08 完成 alpha 编辑器/UI/HTTP/打包 **71 项**、旗帜 **47 项**，以及接入实际 `WindRuntime` 后的最终旗帜 **48 项**回归，均无失败或引擎诊断。证据分别位于同级 `editor_usable_20261030/alpha_coverage_gpu_08_engine08/`、`banner_gpu_04_engine08/`、`banner_gpu_05_runtime08/`。安装器核对各自冻结工程、运行日志、断言数和实际引擎 SHA，没有把旧 candidate07 原生 CPU 包的结果冒充 candidate08 新结果。

2026-10-30 08:37 +08:00，主任务审阅授权后，默认入口更新为 candidate08。安装前及完成准备后再次检查默认目录中没有在用进程，没有结束任何用户进程。原候选07的全部七个入口/别名/符号和两个元数据文件，原字节备份于：

`D:/tools/godot/_backup/before_08_20261030_083604_735508/`。

七个新文件通过 SHA 核对后，以逐文件原子替换发布，安装清单最后发布；五个入口的 `--headless --version` 均退出 0。安装记录：

`streaming_alpha_feedback_08/installation_attempts/20261030_083604_735508/installation.json`。

默认 `D:/tools/godot/godot.windows.editor.x86_64.exe` 及匹配符号 SHA 与上表候选一致。安装记录中的构建清单 SHA 指向保留的安装前候选快照；仓库清单随后追加安装事实，二者通过快照及记录链相连，不假称安装前后清单字节相同。

安装后从默认入口再次启动独立 GPU scissor 回归：**10 项通过、0 失败、0 诊断**，记录在 `stable_prepass_on_installed08/`。该 smoke 仅验证默认预深度开启的 alpha-scissor 路径，没有扩大为所有 alpha 模式验收。

## 边界

- 修复内置 alpha-scissor/hash 流程。用户自定义 shader 在 `FRAGMENT` 中直接 `discard` 的代码仍早于该反馈块，本轮不声称已修复它。
- 裁切表面的需求按几何投影产生，包含透明洞；真正全透明的表面可能因此请求清晰纹理。这是让初始 mip 无覆盖的细节能自行恢复所必需的行为。
- 本轮未重新编译或运行 candidate07 的原生 CPU 测试包；本次只改两个 Forward+ 渲染文件，旧 49 文件的原字节和测试历史保留。
- 合成回归证明近距离清晰纹理能恢复、透明洞及遮挡保持正确，不是整城加载、FPS、low 帧或实际 VRAM/RSS 的性能结论。
