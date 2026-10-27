# 完整原生发布快照隔离原型（2026-10-27）

`tools/native_published_snapshot_prototype.gd` 与 `tools/test_native_published_snapshot_prototype.gd` 是研究原型，**没有接入游戏或编辑器**，没有修改现有原生生成器或正式资源包。它尝试从私有旧 native 索引和 footprint 转换两个合成模型：将产品复制到新私有根，对复制品一次性验证身份和资源结构，最后原子发布 `snapshot.json`。显式 reader 打开该快照后读取产品时不打开原 GLB、不重复计算产品 SHA，按相同 payload 共享 PackedScene，超出原型预算返回错误。

## 保留的测试记录

两次都使用独立 `APPDATA`、`LOCALAPPDATA`、`TEMP`、`TMP`、`TMPDIR`，只有一个 headless 测试进程，外部 fixture 和旧原生产物均为测试生成；每轮的 stdout、stderr、Godot 日志及报告均保留。

| 样本 | 结果 | 明确边界 |
| --- | --- | --- |
| `native_published_snapshot_probe_01` | 断言 23/23、进程 exit 0；**不是干净通过** | Godot 启动时有 3 条 `Unexpected NUL character` Unicode 解析错误。日志在 `native_snapshot_user_20261027_01/`，不得隐藏或覆盖。 |
| `native_published_snapshot_probe_02` | 23/23、exit 0，stdout/Godot 日志无脚本或引擎错误，stderr 空，进程已退出 | 删除首轮 `_key` 的 `"\u0000"` 字面量并改用 `unicode_at(...) == 0` 后运行；错误不再出现。日志在 `native_snapshot_user_20261027_02/`。 |

上述路径均位于 `D:/code/rmmo_runtime/review_artifacts/`；各 fixture 目录的 `report.json` 记录每项断言。02 的两个源逻辑 `.glb` 均不存在，旧模型是测试创建的 ArrayMesh、StandardMaterial3D 和两个节点，没有 ImageTexture、真实 GLB 或地图。验证内容包括：两个不同产品和一个别名、单次复制/加载与别名共享、原型预算拒绝、同模板节点/基础材质共享、单实例覆盖不改基础材质、缺产物错误、不受支持 revision、路径逃逸及失败发布不产生完成标志。它不是纹理视觉、GPU 性能、真实地图或产品接入验收。

## 复现

使用新的 fixture 和 userdata 路径，避免并发其它计时工作。以下为 headless 逻辑测试，GUI 版引擎通过隐藏窗口启动：

```powershell
$env:APPDATA = 'D:/code/rmmo_runtime/review_artifacts/native_snapshot_user_example/roaming'
$env:LOCALAPPDATA = 'D:/code/rmmo_runtime/review_artifacts/native_snapshot_user_example/local'
$env:TEMP = 'D:/code/rmmo_runtime/review_artifacts/native_snapshot_user_example/temp'
$env:TMP = $env:TEMP
$env:TMPDIR = $env:TEMP
New-Item -ItemType Directory -Force $env:APPDATA, $env:LOCALAPPDATA, $env:TEMP | Out-Null
$engine = 'D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/collision_debug_20261026/engine09/godot.windows.editor.x86_64.exe'
$p = Start-Process -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput 'D:/code/rmmo_runtime/review_artifacts/native_snapshot_user_example/stdout.log' -RedirectStandardError 'D:/code/rmmo_runtime/review_artifacts/native_snapshot_user_example/stderr.log' -FilePath $engine -ArgumentList @('--headless','--log-file','D:/code/rmmo_runtime/review_artifacts/native_snapshot_user_example/godot.log','--path','C:/Users/luna/.codex/worktrees/map-load-render-review/rmmo','--script','res://tools/test_native_published_snapshot_prototype.gd','--','--fixture-root=D:/code/rmmo_runtime/review_artifacts/native_published_snapshot_probe_example')
$p.ExitCode
Get-Content 'D:/code/rmmo_runtime/review_artifacts/native_snapshot_user_example/stderr.log'
Get-Content 'D:/code/rmmo_runtime/review_artifacts/native_published_snapshot_probe_example/report.json'
```

fixture 路径必须不存在且位于 `review_artifacts`。除检查退出码和报告外，还要检查 stdout、stderr 和 Godot 日志；像 01 一样出现解析错误时即使断言通过也不视为干净通过。

## 只读审查：不能直接作为生产实现

- **不可变根只是调用者承诺。** 路径在 `review_artifacts` 内且检查祖先，但没有文件锁、持久挂载快照或对并发目录替换的防护；打开清单后，外部进程可替换它或产品。reader 只查产品路径、存在性和大小，不校验同长度替换。这样的信任只适用于明确发布、不可由编辑器覆盖的真实包；不能自动套用到当前共享可变 `compiled_assets_v1` 缓存。
- **清单身份和 schema 不足。** `open_snapshot` 验证 revision、引擎 hash、模型 key、SHA 形状和基本数值，但 `old_generator` 仅检查是 SHA 字符串，未与明确的受支持转换矩阵比对；products 数量和多余未引用项也未按模型集完整约束。内容本身不是经外部绑定的发布身份，公开的 `manifest` 字典还能在进程内修改。恶意或意外改写的估算不能被当作可靠的 admission 证明；这些问题不能靠重复扫描用户已信任的包解决，需要先建立明确的离线发布/挂载合同和快照所有权。
- **模型元数据与版本迁移未闭合。** 清单只绑定源 SHA、payload、长度和 footprint 估算，不包含正式地图需求所需 bounds、碰撞、LOD、依赖目录和地图版本等完整元数据；尚未验证所有模型类型、生成器版本或引擎兼容矩阵。当前离线转换要求旧索引和 footprint 的生成器等于当前生成器；不支持的旧产物明确失败，不能称全部旧包可转换。
- **预算和资源寿命仅为模型。** 原型只按同一个 reader 的唯一 PackedScene 估算计费，各 reader 不共享账本，也没有与既有 worker、共享纹理、上传和退休预算合并。`close()` 直接清账，无法确认调用方或已实例化节点是否还持有 PackedScene；测试人工先释放实例，不能证明生产回收安全。解码前仅做算术检查，未实现现有 admission 的原子预留、取消、worker join 和失败资源移交。
- **共享范围有限。** 只复用同一 payload 的 PackedScene；不同模型文件中相同的网格、材质或纹理仍各自反序列化。两个测试模型带简单材质但无 ImageTexture，不能说明跨模型去重、实际纹理色彩/normal/alpha、GPU upload 或模型材质完整等价；也未做用户要求的实际模型近中远视觉验收。
- **编辑器和 MCP 未适配或验证。** 原代码未改，测试只确认旧文件仍在、GLB 未被生成；没有走真实编辑器的导入、修改、撤销、保存重开或 HTTP 3D MCP，也未证明可变源变更/派生产物刷新语义。不能把“不改变编辑器代码”称作编辑器兼容验收。
- **失败后的临时数据会保留。** 发布失败不写 `snapshot.json`，但先前复制的产品、目标目录、临时清单可能残留；同名目标不会自动复用或删除。标志的原子 rename 也不等于已证明断电后产品和目录的持久化。生产流程需定义清理/重试及恢复语义，并验证中断发生在各发布阶段的行为。
- **同步原型不是后台加载实现。** `publish`、`open_snapshot` 和 `load_model` 要求主线程，前者会读取产品、创建资源并校验结构；后者同步反序列化。它没有接入调度、预测预取、分帧发布、profiler 或 gdb，不能声称减少了真实地图加载时间或长帧。

后续应先设计受控发布根及受限版本迁移，复现并修复预算/所有权和中断问题，再用真实带纹理的模型进行异步/统一预算接入和独立压测；只有实际游戏与编辑器路径均适配并通过各自验收，才可进行真实地图完整加载、卸载、返回的累计对照。
