# 完整材质原生产品重复工作：隔离复现（2026-10-27）

`tools/probe_compiled_native_work.gd` 使用全新外部临时根，自行写入原生索引、footprint 与 PackedScene，不读写正式地图或正式产品。运行时沿用实际 `Compiled.read`、`compiled_asset_preparation.read`、编辑器 `load_job._parse_asset` 和 `ModelParsePreparation.run`，没有修改它们或任何完整原生生成器的输入源码。

## 测试边界和结果

最终脚本的第 03 样本 `D:/code/rmmo_runtime/review_artifacts/native_work_probe_20261027_03/report.json` 退出码 0，全部 32 项通过；测试进程已退出。每条 reader 各读同一 8,393,089 字节文件 8 次，现有 `compiled.payload_sha` trace 观察到 16 次哈希，共 134,289,424 字节；这些事件的墙钟时间合计 601.056 毫秒。测试开了 trace，文件已被前面的构建、哈希、测量预热；这不是磁盘冷读、地图加载耗时或性能优化收益。两条路径在当前实现中每次成功读取各调用一次生成器（当前逐次读取 9 个脚本做哈希）、产物哈希、依赖检查及 `_valid_packed`；除 payload trace 外这些调用次数是源码结构推导，非本测试实测计数。一次独立代理测量 generator 1.515 ms、payload SHA 38.916 ms、依赖 0.361 ms、schema 0.068 ms，不能加到 reader 耗时上。

样本是 **97 个 Node3D、无 Mesh/Material/Texture 的合成 PackedScene**，包含 8 MiB 零字节元数据并以未压缩原生格式保存。占位 `.glb` 是用于路径和源身份的普通字节，不是可解析 GLB。它复现完整原生读取的检查工作，却不能证明真实材质解码、上传、画质或帧表现。第 01 和 02 样本亦通过，16 次 SHA 的 trace 墙钟合计分别为 575.717 和 675.196 毫秒；这些样本不是统计分布。01/02 未显式隔离 TMP/TMPDIR；03 的 APPDATA、LOCALAPPDATA、TEMP、TMP、TMPDIR 均指向私有路径。

真实编辑器加载入口对存在来源的合成原生产物命中；暂时移走隔离源文件后该入口失败。对 `Compiled.read(..., trusted_package=false)` 的显式严格读取，同长度替换源文件会被拒绝；不能据此称编辑器所有正常入口都执行该严格路径。`require_native_products=true` 的真实协调器成功时不调用 raw fallback，移走隔离原生产物后返回缺产物错误且 raw 调用数仍为零；测试没有从无效占位 GLB 导入。两个被移走的文件均在同一测试内恢复。

## 复现

在 Windows PowerShell 中使用项目的现有自编译引擎，并为每次运行选择**尚不存在**的独立 fixture 目录和 userdata 目录。该命令是 headless 逻辑测试；不要在其他计时样本运行时并发执行。

```powershell
$env:APPDATA = 'D:/code/rmmo_runtime/review_artifacts/native_work_user_example/roaming'
$env:LOCALAPPDATA = 'D:/code/rmmo_runtime/review_artifacts/native_work_user_example/local'
$env:TEMP = 'D:/code/rmmo_runtime/review_artifacts/native_work_user_example/temp'
$env:TMP = $env:TEMP
$env:TMPDIR = $env:TEMP
New-Item -ItemType Directory -Force $env:APPDATA, $env:LOCALAPPDATA, $env:TEMP | Out-Null
$engine = 'D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/collision_debug_20261026/engine09/godot.windows.editor.x86_64.exe'
$p = Start-Process -PassThru -Wait -WindowStyle Hidden -FilePath $engine -ArgumentList @('--headless','--path','C:/Users/luna/.codex/worktrees/map-load-render-review/rmmo','--script','res://tools/probe_compiled_native_work.gd','--','--fixture-root=D:/code/rmmo_runtime/review_artifacts/native_work_probe_example')
$p.ExitCode
Get-Content 'D:/code/rmmo_runtime/review_artifacts/native_work_probe_example/report.json'
```

报告缺失或退出码非零均不是通过。脚本拒绝已存在的 fixture 路径，并限定在 `review_artifacts` 下；路径检查不构成对抗其他进程并发替换目录的安全保证。03 报告包含 fixture、引擎与脚本身份，并按 source path 过滤 trace 事件。

## 下一切片：离线发布快照，尚未实现

完整产品当前位于可编辑、可丢弃的 `compiled_assets_v1` 本地缓存；地图文件的 snapshot 不证明该目录不可变。完整 reader 每次按 9 个脚本重新生成身份，其中包含 `compiled_asset_cache.gd` 自身；直接修改它会使旧索引失效，而游戏入口要求 native。不能直接把全局 `Policy.trusted()` 当作发布包凭据，因为编辑器也使用它。

建议先做只针对一个模型、只写私有根的离线转换：从已有完整 `.scn`、原生索引、footprint、明确来源的模型 bounds/内存元数据创建新的版本化发布清单和内容寻址产品；保留源逻辑键与源 SHA、产物 SHA/字节数、引擎和原产品生成器身份、格式 revision、完整模型语义和保守预算。模型元数据缺失时明确报错或由离线流程补齐，不能在游戏启动时再读 GLB。转换使用受限、可审计的旧格式/引擎兼容规则；一次性构建与发布可验证绑定，不在每次游戏加载时重新扫描。先完整写入新目录并完成所需语义验证，再原子发布清单；转换不覆盖来源目录，失败不留下可被当成完整发布的快照。

新增专门由游戏加载事务持有的发布快照读取器，根、清单和预算身份在该事务内固定；按同一份快照解析逻辑模型键、依赖、metadata 和原生产物，不从共享可变缓存偷偷重读新索引。发布包读取可免逐次产物 SHA、依赖/资源图复查，但仍需处理产品缺失、加载/类型错误、路径越界、错误资源所有权及取消；编辑器可变缓存继续使用其现有入口。产品版本或引擎不兼容要报明确错误，不能将任意旧 generator 标为兼容。旧 `.scn` 包含完整材质纹理，首次切片只解决读取和身份，不等同于实现纹理分离或跨模型去重。

先在临时根中构造两模型及共享引用的发布快照，独立测试：无原 GLB 读取成功；模型身份/属性、共享/独立修改和 conservative admission 保持；产品缺失或版本不匹配失败且 raw 次数为零；编辑器路径与已持有的旧实例不受影响；取消、并发、卸载/重载和资源析构无泄漏；相同模型多实例只有必要的读取与哈希工作。之后才用实际地图的**完整纹理原生路径**和私有资源副本做有/无优化的加载、逐帧、卸载、返回对照。当前白模或 `--map-texture-stage` 样本不能代替该验收。
