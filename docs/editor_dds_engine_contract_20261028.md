# 编辑器 DDS 编码与局部渲染设备初始化

编辑器后台导入现在有真实 DDS 路径的图形测试证据。候选引擎为自编译 **4.7.2**，尚未安装为默认引擎；这不是 Godot 4.8 的验证结果，也不是整图加载或 low 帧收益结论。

## 问题与修复范围

在 Compatibility 已持续绘制的独立场景中，从 worker 调用旧 GPU 图片压缩入口，Betsy 会构造局部 RenderingDevice。原构造函数把它立即发布为全局 singleton，此时 context 仍为空。主线程随即查询窗口 surface，访问空 context；GDB 记录了 `RenderingContextDriver::surface_get_from_window(this=0)`，另一线程还在准备 Vulkan context。固定设置的 CPU/GPU/GPU/CPU 四样本中，两次 GPU 样本自然崩溃，两次 CPU 样本完成。

补丁分为两项：

- `godot-4.7.2-main-device-publication.patch`：局部设备永不发布到全局；主设备通过明确窗口参数识别，在 initialize 全部完成后发布，已有其他主设备时明确拒绝。
- `godot-4.7.2-per-call-cpu-compression.patch`：增加 `Image.compress_from_channels_cpu`，单次调用跳过 GPU 分支，复用已有 CPU 编码器；没有对应编码器返回 ERR_UNAVAILABLE，不修改全局设置。

原来没有堆栈的历史 `0xC0000005` 不在本结论之内。早期 HTTP private_01 的堆栈相符，但未保存当时完整业务源码，不能以它单独完成因果证明。

## 实际验证

候选引擎 SHA256：`3d65b357ac8a14b8bf04b3a162d7dfea74eb0550ffb10a5a26764cea21958066`。
符号 SHA256：`a100d38c3b91939c48a2bd9117950b15c13332642fd52783a834ca1735d87271`。
基线 GREEN SHA256：`20d25131e638bb6cafa0c285e2cddbf09eb6e7e528ee4f8f22dc566adfd8fde8`。

所有图形样本通过 `tools/run_godot_background.py` 在私有桌面串行执行，每次使用独立用户目录和运行前后身份记录。

| 验证 | 结果与证明范围 |
| --- | --- |
| 原始最小 GPU 崩溃夹具，候选运行两次 | 均正常退出，原 probe 字节未改；不是旧引擎偶然未复现的替代证据 |
| 新 CPU 接口，Compatibility / Forward+ | 四种 32/64 像素 RGB/RGBA mip 链均成功；与固定全局 GPU=false 的旧 CPU 路径输出 SHA 全部相同；设置和主设备身份不变 |
| GDB 新 CPU 接口 | RenderingDevice 构造断点已解析，计数 0，inferior 正常退出 |
| GDB 旧 GPU 接口阳性对照 | 同一断点计数 1，inferior 正常退出，Compatibility 全局 RD 始终为空 |
| 旧 GPU 接口，Forward+ | 局部编码完成，主设备 instance ID 前后相同 |
| 真实编辑器 HTTP/UI 导入，强制要求 DDS | **32 PASS / 0 FAIL**，无脚本或引擎错误，生产源码与引擎身份前后一致 |

最后一项使用实际 CPU API，不注入 encoder：新材质读取新 DDS，现有 PNG owner 保持原对象；River 与 Prefab 只失效相关缓存；延迟到达的同内容 follower 不再次失效首 owner；HTTP 导入未完成时另一客户端能读取 editor_state；UI 导入与实际地图 LoadJob 共用账本，完成后额度归零。32×32 合成贴图用于功能验证，不能代替实际材质画质验收。

首次 CPU GDB 样本的应用及 debugger 都正常结束，证据已落盘，但 Python 最后向 GBK 控制台打印警告文本时出现 UnicodeEncodeError。该失败保留，后续 runner 使用 `python -X utf8`；不把该样本整个 runner 标作无错。

## 重现与证据

外部引擎证据根：`D:/code/rmmo_runtime/review_artifacts/editor_dds_cpu_rd_fix_20261028_01/`。

- `attempt_02/build.result.json`：SCons 参数、编译器及输入/产物身份。基于已修 shader decode 的 GREEN overlay，追加两项补丁；`target=editor debug_symbols=yes separate_debug_symbols=yes optimize=speed -j4`。
- `attempt_02/restore_audit.json`：共享源码、生成源码和受影响 bin 已恢复；既有对象/库编译缓存允许保留，未替换默认安装。
- `runtime_01/{gpu_01,gpu_02}`：原始崩溃夹具的候选结果。
- `runtime_01/cpu_api/{cpu_api_gpu_true_01,legacy_cpu_01,cpu_api_forward_01,cpu_api_gdb_01,legacy_gpu_gdb_01,legacy_gpu_forward_01}`：CPU 字节等价、设备身份与构造断点对照。
- 原始红样本及堆栈：`D:/code/rmmo_runtime/review_artifacts/editor_dds_import_proto_20261028/device_race_repro_01/`。
- 真正 DDS HTTP/UI 证据：同级 `gpu_required_dds_01/{candidate_parse_01,candidate_gpu_01}`，含命令、日志、引擎及业务源码前后 SHA。

仓库保留可移植的 CPU/GPU 入口 probe 与 GDB 构造计数脚本，位于 `tools/engine_patches/cpu_texture_compression/`。将其复制到外部测试目录；每个样本启动前固定 `test/cpu_only` 与 `compress_with_gpu`，运行过程中不修改设置。CPU 测试用前者 true、后者 true；旧 CPU 对照 false/false；GPU 阳性对照 false/true。通过私有桌面 runner 启动 `--script probe.gd`，渲染方式分别指定 Compatibility / Forward+。原始输入与构建过程以外部证据为准，项目模板不是早期样本原文件。

剩余：实际大纹理的尺寸/额度清理、画质与导入工作量评测、全部原生素材的真实编辑器集成、DDS 分支合并。完成编辑器后再评估和编译 4.8，不能提前视为交付。
