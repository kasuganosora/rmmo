# 白模原生产品兼容合同

`white_native_asset_writer.gd` 的 `PRODUCT_REVISION` 是持久化产品的转换合同。`generator()` 保留既有调用接口和 manifest 字段名，返回该版本、原生 metadata schema 名和 Godot 引擎修订的稳定组合。运行时不再用五份混合职责脚本的全文 SHA 判定原生模型是否可读。

这一边界修复了第 170 轮的实测退化：仅修改 `GroundCpuMesh` 的 PREDELETE 回收，就使 49 个原生索引全部失效；当前可见范围的 24 次原生读取退回 GLB，配套 bounds/memory 描述也失效。实际模型数相同，但重新解析、节点实例化/遍历和批次准备增加，完整加载从此前约 9.7 秒升到 21.51 秒。不能把这次退化归因于游戏资源或同工作量的随机波动。

修改下列持久化语义时，应更新 `PRODUCT_REVISION` 并正常重导出：

- `META` 结构，以及 surface/LOD/faces/culls/geometry_key 的内容、编码或顺序。
- 实际保存的节点、变换、extras、可见范围、LOD 转换规则或受支持资源类型。
- 修复了导入/导出几何语义，必须让已有产品重新生成的情况。

线程调度、资源回收、运行时缓存寿命、统计、profiler 或注释变化不更新此版本。引擎修订目前仍作为保守兼容门槛；这是有意保留的版本约束，并非精确的原生 ABI 检测。

`exporter_provenance` 记录导出时的脚本 SHA、产品版本及引擎修订，仅供审计，不参与运行时兼容判定。它不声称穷举全部传递依赖。源 SHA、产品身份/大小、可信资源包规则及显式诊断 checksum 策略保持原合同。元数据 companion 仍绑定源、产品及同一 geometry generator；不能只使几何命中却让 companion 继续按旧运行时指纹失效。

迁移必须经正式 writer 重导出、原子发布索引，再核对保存重开与几何语义。不得给旧 manifest 直接换 generator 冒充重新导出。旧 content-addressed 产品与原始索引应保留作对照。本轮不改变源 GLB、模型、材质或正式地图内容。

回归包括实际 generator 函数的隔离多进程测试（无关源码注释变化保持 key、重启保持 key、产品版本变化改变 key）、真实 GPU 导出/重开及 companion 一致性、旧合同拒绝、独立 provenance 变化不影响读取、源/产品身份与诊断校验。派生格式与模型导出改变后，按 `rmmo-model-review` 复验受影响项；纯运行时修改不应再要求整城重新转换。

2026-10-23 用户明确取消游戏运行时的 GLB 自动回退。MapLoader 在启动时启用 `require_native_products`，传给初始模型准备、取消后重建的准备器及 DeferredAssets。原生产物缺失、失效或读取期间身份变化时，结束对应加载并报告需要内容编辑器重新导出；不能在原生额度下导入 GLB，也不能另行排队重试 GLB。已分配的 native 资源仍交给原有主线程回收，错误不能使 worker/准入额度泄漏。

白模入口的 bounds/memory companion 缺失时也不再解析 GLB 重建描述，原生模型的 GLB 并行导入资格扫描跳过。编辑器显式 GLB 导入、导出工具和共享导入器仍保留；共享 helper 的默认策略服务这些调用者，游戏入口明确启用强制原生策略。当前地图及包中仍使用源路径/身份作为引用键，并保留部分源文件存在性/长度观察；此改动不等于运行包已可删除所有 GLB 文件。

`tools/test_native_required_loading_gpu.gd` 验证缺失/失效拒绝、禁止 raw_only 绕过、无 raw 重试、native 正常读取、已分配资源所有权、线程/额度排空和编辑器显式导入。真实白模路线另外检查策略已开启、初始/延迟原生命中、区块卸载返回及最终清理。尚未复测纹理阶段，不把白模通过扩大为所有运行模式验收。

同日补齐同步发布入口：游戏WorldDocument携带独立的`load_require_native_products`，经普通实例化、桥梁kit及城防kit传入AssetLibrary；不能让这些共享helper在native miss时同步导入GLB。编辑器文档保留默认显式导入行为。MapLoader删除模型发布阶段的GLTF生成/重新pack分支，仅接收PackedScene，并在实例缺失或paint/tile错误时结束加载。`test_native_required_publication_gpu.gd`先在旧路径复现普通/桥梁发布的3个失败，再验证拒绝、编辑器raw缓存隔离、native成功及Deferred文档策略传递，最终20/0。
