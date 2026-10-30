# 编辑器 Godot 4.8 适配复查（2026-10-30）

本轮按实际代码检查，再对照官方 4.8 beta1 说明和本机引擎源码；优先补齐编辑器可用性及资源管线，没有开展新一轮整城性能调参。首轮复查使用 candidate07，SHA `dabba1322488f959bddbd1d20ebdf40ee788c918c1a8b193a533d0472efb7375`；后续实施及默认入口更新见文末。

官方依据：[4.8 beta1 发布说明](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/)，其正文通过 godotengine/godot-website 官方仓库核实。引擎源码位于 `D:/tools/godot-4.8-build/source/godot-4.8-beta1`。

## 已复现并修复：导入材质仍绕开流式纹理

虽然导入已经发布 STEX，三个消费者仍有遗漏：

1. 导入完成后把完整 Image 上传成 ImageTexture，首次刷材质复用的是这份非流式对象。
2. 编辑器重开地图统一把表面贴图当作可变源图片，读取、准备完整像素，再上传一次。
3. 材质缓存失效后的直接首次使用仍只尝试 DDS 或源图片。

现在导入生产者在原有后台任务和预算内创建 StreamedTexture2D，丢弃完整 CPU 像素后向主线程交接同一对象。重复标签/导入共享该对象。重开地图按唯一纹理需求准备流式对象，与普通可变图片共用一份任务预算；发布结束恢复临时材质作用域并释放任务租约。直接首次使用也优先读取已发布的流式资源。

仅导入器发布的 `<PNG SHA>[.source].png`、且描述中的源身份与名称相符，才走编辑器免源图片读取的路线。普通可编辑文件即使有 STEX 副产物，仍沿用原有快照准备；没有把旧副产物当作可变源的最新内容。未发布对应角色/法线变体、流式不可用或产物缺失时保留原读取路径。

STEX 描述增加可选的原编码标记，用来识别同一 DDS 导入，避免重复导入把仍然有效的流式对象失效。它不改变 STEX 二进制布局，也不改变正式模型文件；旧描述仍可读。预算使用完整 mip 链的保守估计，不冒称实际显存占用。

涉及代码：

- `scripts/world_editor/surface_texture_imports.gd`：后台导入到主线程的资源交接。
- `scripts/world_editor/terrain_texture_preparation.gd`：流式与可变源共同准备、材质池身份处理。
- `scripts/world_editor/load_job.gd`：重开时接收流式对象及恢复作用域。
- `scripts/world3d/streamed_texture_source.gd`：导入产物识别与编码身份。
- `scripts/world3d/surface_materials.gd`：交接、直接首次使用、重复导入去重。

## 验证及证据边界

证据根目录：`D:/code/rmmo_runtime/review_artifacts/godot_4_8_adoption_20261029_01/editor_usable_20261030/`。每次运行保存源文件 SHA、引擎 SHA、解析日志和运行日志；GPU 测试均使用独立桌面、隔离工程和临时资源。

| 样本 | 结果 | 证明内容 |
|---|---|---|
| `streamed_paint_red_01` | 48 通过、6 失败 | 保真与 DDS 的首次刷材质、冷材质缓存重开都仍是非流式纹理；失败保留 |
| `streamed_paint_green_01` | 解析失败 | 新增作用域代码遗漏 Paint 常量；已补齐，失败保留 |
| `streamed_paint_green_02` | 52 通过、2 失败 | 重开已接通，首次使用仍被导入时的完整上传覆盖；继续修复 |
| `streamed_paint_green_05` | **69 通过，0 失败，0 引擎诊断** | 真 HTTP 导入/刷材质、UI 刷材质、同纹理共享、重复导入、撤销重做、保存重开、缓存失效后首次使用、可变源隔离、预算归还、临时作用域清空 |
| `texture_inflight_48_01` | **30 通过，0 失败，0 引擎诊断** | 地形和 prefab 加载期间有 DDS 发布时，旧像素不能覆盖新对象；一次后台准备、无替代上传、无残留租约 |
| `texture_identity_48_01` | **37 通过，0 失败，0 引擎诊断** | 普通可变源的快照、源替换、颜色/OpenGL/DirectX 法线语义保持 |

新增回归 `tools/test_editor_streamed_paint_gpu.gd`。最后样本的保真模式逐字节验证了源图全部像素和 alpha；DDS 仍是用户主动选择的压缩路线。它也验证了编辑器实际场景里的对象类型，不能仅凭“生成了 STEX 文件”判为流式已接通。

工作量方面，重开中的每个唯一导入纹理由“完整像素交接并上传”变为“一次后台流式对象交接”，同纹理第二物件复用。最后样本 `paint.texture.texture_only_handoffs=1`，完整图片交接、源图片主线程读取及替代上传计数均未出现，准备任务和预算归零。

这是编辑器管线及工作量验证，没有用小贴图测试宣称 axel_town 加载时间、low 帧或实际 VRAM 已改善。正式资源、布局和光照没有在本轮批量转换。

## 前轮识别的适配缺口（后续实施见文末）

| 项目 | 代码证据与影响 | 后续处理边界 |
|---|---|---|
| 旗帜换图的 CPU 合成 | `streetlamp_banner.gd` 在 flag/emblem 分支调用纹理 `get_image()`，重组为固定 512×1024，再创建 ImageTexture；`banner_panel.gd` 还有同步解码及 8192 尺寸拒绝。本机 `StreamedTexture2D::get_image()` 会读取 mip0，不能视作免费访问已驻留 mip | 下一优先项。应将合成产物放进共享后台准备与流式发布，保留风场、图案布局、平头/尖头、撤销及 UI/MCP 一致性；不能直接换不支持风场的自定义 shader。本轮仅代码确认，未把旗帜问题写成已修复 |
| 透明裁切纹理的 mipmap 覆盖保持 | 4.8 新增 `Image.generate_mipmaps` 的 alpha test coverage 参数；自定义模型/表面导入仍使用原调用，没有暴露覆盖保持选项 | 需按材质真实 alpha-scissor 阈值接入并做叶缘近中远对比；不是给所有透明图片统一打开。普通 PNG 原像素保留要求仍有效 |
| 接触阴影等新渲染设置 | 本机构建实际使用项目级 `rendering/lights_and_shadows/contact_shadow/enabled`、`multi_bounce_occlusion/enabled`，均默认关闭；接触阴影还有 Light3D 的 allow/blur 控制。工程未启用这些项目开关，编辑器未暴露对应控制 | 可选画面能力，不是编辑器启动兼容故障。若增加，须区分项目级设置与地图/灯光设置，明确生效时机，再同步 UI、3D MCP、保存及画面对照；不能只往地图环境 JSON 加一个无效字段。本轮不改正在编辑的环境/灯光文件 |

## 已有接入或不需要专门适配的内容

- 工程特性、默认引擎和测试入口均为 4.8；已有原生模型拆分、STEX、引擎流式预算及相关共享着色器适配继续保留。
- 官方列出的子节点移除、属性访问等引擎内部优化由新引擎自动提供，不需要在内容编辑器重复实现。
- FuzzySearch、ASTC 6×6、高质量压缩、动态贴花等属于按需求选用的能力。未使用不等于兼容错误；尤其不把有损格式改成默认策略。
- 对照 `_enter_world`、ClassDB 脚本类回退等本次破坏性变更，已检查的编辑器与 world3d 主路径未发现对应旧调用。此项是本轮检查范围内的结论，不等于全工程所有功能验收完成。

仍以编辑器可用性优先；旧 embedded 模型的全量转换、跨 content_root 的 prefab 可移植性以及此前其他待验项，继续沿用 `native_streamed_model_runtime_20261029.md` 中的独立边界。

## 后续实施：本轮三项适配

用户授权后，按旗帜、透明裁切覆盖、本机画质顺序补齐。没有开展新的整城性能调参或批量改写正式素材。

| 项目 | 交付行为 | 最终证据 |
| --- | --- | --- |
| 旗帜 | 原图直接作为共享流式 detail 层，去掉 mip0 读回及固定 RGBA 画布；外部图片后台导入，保留平头/尖头/燕尾、图案位置、撤销与保存。实际 WindRuntime 准入和材质转换同步适配 | CPU 35 项、candidate08 真实 UI/HTTP/运行风场 48 项，零诊断；[报告](editor_banner_streaming_20261030.md) |
| 透明裁切覆盖 | UI 与 `import_surface_material` 暴露可选 coverage 与匹配 cutoff，默认关闭；mip0 保真、不同阈值独立，保真/DDS 均携带生成的 mip。显式 coverage 持久发布失败返回失败 | CPU 41 项、candidate08 UI/HTTP/预制件 71 项，零诊断；[报告](editor_alpha_coverage_20261030.md) |
| 本机画质 | 顶栏“本机画质”及四个 3D MCP 工具；接触阴影与多次反弹 AO 作为本机启动设置保存、恢复，不假称地图热切换，也不写入地图历史 | UI/HTTP 38 项、两次独立启动与画面对照通过，零诊断；[报告](editor_rendering_preferences_20261030.md) |

顺带修复两个真实接入缺口：预制件原先只复制 PNG，现在按唯一纹理复制完整 STEX/DDS 与描述并区分变体；风场原有准入规则整体拒绝 detail，已用 6 个失败用例复现并仅放行已实现的组合。资源、主线程工作和共享验证均以对应小样本为限，不冒称整城 FPS/low 帧改善。

### 本次发现并修复的引擎问题

默认普通 mip 的细小透明裁切片元可能在低清层全部被裁掉，反馈永远为零，近距离也无法请求清晰 mip。candidate08 把反馈移到内置 alpha discard 前，并仅对带反馈的 alpha clip 颜色管线保留正常反向 Z 深度比较，避免深度预通道将这些片元完全拦住。

相同脚本下，原 candidate07 在预深度开/关两模式均有 2 个失败；candidate08 两模式均 10 项通过。修复后可见流式画面对同机位全驻留参考为 **0 个 RGB 差异像素**；默认预深度下被不透明前景遮挡的另一个纹理仍保持低 mip、无需求。详细构建 SHA、可重放累计补丁、失败样本及边界见 [引擎专项](godot48_cutout_streaming_feedback_20261030.md)。

### 保留边界

- 本轮正式验证目标为 4.8 Forward+、启用流式。主动关闭流式/Compatibility 的 source PNG 回退不能保持 coverage mip，不在此次通过范围。
- 引擎修复覆盖内置 alpha-scissor/hash；自定义 shader 在 fragment 中直接 discard 的反馈仍需单独处理。关闭预深度时，遮挡画面正确，但被遮挡的裁切纹理可能额外产生需求。
- 旗帜使用引擎线性颜色混合，半透明测试条比旧 CPU 合成稍亮；已保留旧/新近中远对照，不宣称逐像素等价。没有下采样或有损改变原图。
- 原生预制件跨 content_root 导出、旧 embedded 模型全库迁移仍未因本次适配自动完成。
- 项目原有其他用户改动保留。本轮对 `world_editor_mcp.md` 只追加本轮工具说明，追加前的完整字节前缀保持，回执为证据目录下 `mcp_doc_append_receipt.json`。

### 默认入口已更新

candidate08 已安装至 `D:/tools/godot/godot.windows.editor.x86_64.exe`，匹配调试符号、console 及既有别名同步核验；主 exe SHA 为 `69fccbed237845e578fdb279d9951ac92c71a29d2a1c7c660903064296cb3303`。五个入口版本检查通过，默认入口安装后 scissor GPU smoke 10 项通过、零诊断。

candidate07 完整备份位于 `D:/tools/godot/_backup/before_08_20261030_083604_735508`。构建、安装前清单快照、安装记录及后续清单之间保留 SHA 链；没有冒称本次重新运行了旧版原生 CPU 测试包。未提交本轮工作区代码。

最后 `banner_gpu_07_workspace08` 使用已安装的默认入口，将当前其他用户未提交的脚本及新脚本一并冻结到隔离工程，真实 UI/HTTP/风场/预制件闭环 **48 项全通过、零诊断**。此前 `banner_gpu_06_workspace08` 的隔离夹具只复制 tracked 修改，遗漏其他工作的新脚本 stained_glass_light/interior_reflection，导致 parse 失败；补齐夹具依赖后通过，未改动这些用户脚本。受保护的 12 项最终核验中，11 项 SHA 与既有基线完全一致；MCP 文档仅为前述保留原前缀的追加。
