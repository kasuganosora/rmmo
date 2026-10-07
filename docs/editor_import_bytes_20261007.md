# 自包含 GLB 导入保持原字节（2026-10-07）

桥头长旗 `ca443…glb` 的加载单元实测约 5.93 秒。只读取各阶段 GLB 的 JSON 头后确认：Blender 原件 75,385,964 字节 / 18 images；已验证并发布的版本 263,605,740 字节 / 42 images；九旗节点拼装后 263,606,816 字节 / 42 images；再次导入后的文件 632,616,456 字节 / 78 images。九旗脚本只增节点并共享原六个 mesh，增长主要发生在 `AssetLibrary.import_file` 的 Godot 读取状态再导出路径。不能由 material 数量推断准确的历史导出次数；当前发布脚本直接复制已验证文件，Prefab.capture 同目录命中也不会再次转换。

本次只防止新导入重复编码导致的膨胀，不压缩、不修改现有 GLB 或正式地图，因此不宣称解决已有 603 MiB 模型的加载卡顿。旧文件重复图像和不可达数据的整理属于后续独立工作。

`embedded_glb.gd` 仅接受 GLB v2、严格 JSON + 单 BIN、单 buffer 无 URI、内嵌 PNG/JPEG bufferView、长度及范围合法、JSON 不超过 4 MiB、没有未知扩展的窄集合。URI 和扩展检查包含 extras；不能证明自包含的输入继续原依赖打包流程。原文件先复制到临时文件，再对临时文件重复检查并交给 GLTFDocument 验证；成功后直接按实际字节 SHA 发布，不调用 write_to_filesystem。通过窄检查但原生解析失败的文件直接失败，不转成另一个导出结果。重复和跨素材库导入都保持原始字节、节点、材质及 mesh/node morph 默认值，预览仍走共享 `Io.generate_scene`。

3D MCP 当前没有通用源模型导入工具；通用文件导入仍由 UI 提供。本次 HTTP 覆盖已有 `place_asset` → `save_prefab` 跨资源包打包依赖的同一 `AssetLibrary.import_file` 业务路径，以及重复放置、撤销重做、保存重开。没有恢复二维 import_asset 或新增工具/schema 参数。

回归同时发现：刚导入但缩略图尚未生成时，保存的源依赖收集曾把 `thumbnail_path` 当作必需模型资源，导致 Invalid data。现仅从导出依赖签名中排除这项派生预览；作者记录中的字段照常保存，真实模型/材质依赖仍检查。

验收入口：`tools/test_embedded_glb_import.gd`，小型临时 GLB / glTF 和真实 HTTP；包含字节一致、重复/跨库导入、共享 mesh 的不同 node morph 权重、非法输入及损坏 PNG 无 catalog 副作用、外链 BIN/PNG 打包后移除外链仍能加载，以及缺失派生缩略图的保存重开。最终 exit 0；1236 字节源文件与导入结果逐字节一致。`test_world3d_pose_save.gd`、`test_pose_save_hash.gd` 补充回归均 exit 0。四份真实 GLB 只读取 JSON 头，以实际 helper 判定均可走快路；没有实测这些大文件的导入耗时。测试使用临时资源包，不修改用户地图；本轮没有加载大旗模型或运行 GPU 测试。

损坏 PNG 测试还确认 Godot 原生 append 可能在解码失败后仍返回 OK；新分支因此额外核对 `state.images` 的数量、非空资源和正尺寸，避免把缺失贴图的部分结果发布进素材库。原生加载错误后直接失败，不回落重新导出。

Grok `agent.exe` 首轮大包被 CLI 截断并达到 max-turns，无有效结论；第二轮使用精简完整包、禁用工具及 `--verbatim`，exit 0 返回有效审查。人工复核了暂存后再校验、原生失败不转换、morph 恢复和 catalog 提交顺序。静态报告及测试日志在 `D:/code/rmmo_runtime/review_artifacts/grok_pennant_duplicates_20261007/`。
