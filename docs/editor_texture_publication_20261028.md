# 编辑器纹理首次发布的并发修复

范围是显式 UI/3D HTTP 贴图导入，不给普通游戏资源加载增加校验。继续使用共享 producer 和内存预算。主分支为 `codex/latest-map-runtime-review`，未修改用户的 `D:/code/rmmo` 工作区。

## 已复现的问题

此前 worker 检查 canonical PNG 不存在后，调用允许替换的 `Atomic.publish`。另一个进程在这两步之间创建目标时，原 worker 会覆盖竞争者，随后生成自己的缩略图。DDS 与 `.source.json` 也使用同一替换逻辑，存在相同窗口。

测试让 A 完整写好并关闭自己的临时文件后暂停，独立 Python 子进程创建 B，确认子进程退出和 B 字节完整后才恢复 A。RED 在隔离副本里把新的发布入口接回旧 `Atomic.publish`；这是带门控的旧行为重建，不是原样历史提交。输入、脚本、引擎 SHA 和失败日志均保留。

## 改动

- canonical PNG、DDS、DDS 身份文件首次发布均采用 create-only。Windows 使用无覆盖的 `File.Move`，替代原来的那一次 PowerShell 调用，不新增进程调用。文件先在同目录随机临时路径完整写入并关闭。
- 已有目标仅在内容逐块相同时复用；不同内容返回明确冲突，保留竞争者。只清本任务的临时文件，不删除或回滚他人产物。
- DDS 身份先发布；取消后留下的同内容身份可供下一次补齐 DDS。不同身份即使尚无 DDS 也报冲突，不能假称 PNG 回退成功。
- 相同 DDS 的竞争复用必须与当前编码字节相等，之后才可交接自己的 CPU Image。发布结束检查实际选中的后缀，不能把被另一优先副产物遮住的文件报告成当前产物。
- 缩略图和可编辑材质 JSON 继续沿用原替换语义；正常单进程去重流程不变，新文件成功发布不额外重读其 payload。

## 验证

证据根：`D:/code/rmmo_runtime/review_artifacts/editor_dds_import_proto_20261028/`。引擎为已有 CPU 压缩候选，SHA `3d65b357ac8a14b8bf04b3a162d7dfea74eb0550ffb10a5a26764cea21958066`，不是新引擎版本。

| 检查 | 结果 |
| --- | --- |
| `no_replace_redgreen_02` PNG 跨进程竞争 | RED 20 项中 3 失败；GREEN 20/0 |
| `dds_no_replace_redgreen_01` DDS/身份竞争 | RED 35 项中 4 失败；GREEN 35/0 |
| `publication_extended_01` DDS 扩展合同 | 45/0；含身份孤儿恢复、不同身份无 DDS 时拒绝、实际 DDS 读回与交接 Image 字节一致 |
| `publication_regression_01` | PNG 竞争 20/0、worker 46/0、顺序源冲突 13/0、共享 coordinator 44/0 |
| `merged_01/publication_dds_http_01` | 真实 HTTP 导入/涂材质、undo/redo、保存重开、共享缩略图账本通过；主线程 DDS/source 读取 0，材质构建 1 次 |

上述有效样本无脚本/引擎错误，记录的源码与引擎身份前后一致。真实 HTTP 样本 paint 283.758ms、最大帧间隔 140.936ms、材质构建 0.717ms；这是功能回归，不能声称冷 shader 或长帧已解决，也不提供整图性能提升结论。

`no_replace_redgreen_01` 是无效夹具样本：子进程 marker 尚未写完即读取，并误启动缺地图的 MockServer。修正为等子进程退出、关闭无关 MockServer 后在新目录重跑，未删除失败记录或放宽错误检测。

## 边界

本次实际执行平台为 Windows。Linux 分支使用系统 `link`，macOS/BSD 使用 Perl 的直接 `link`；缺少能力或文件系统不支持时明确失败，没有覆盖式回退。其他平台仍待原生测试，不能宣称跨平台验收完成。后续引擎工作可考虑直接暴露原生无覆盖发布，减少外部程序依赖；本轮没有为此追加引擎编译。

这不是任意外部修改者下的多文件事务，也不防止发布后他人原位改写文件。相同 source 的合作 producer 按相同 alpha 选择后缀；异后缀对抗测试验证本次提交结束时的实际选择，不承诺未来外部新增后缀不会改变选择。测试 B 的不同 DDS 是故意构造的冲突数据，不是美术编码正确性的证据。

普通消费者仍信任资源包。以上字节比较只发生于显式导入碰到已有目标的竞争/冲突；没有恢复 GLB 消费、白模路径或每次加载纹理校验。编辑器完整地图、实际美术画质和剩余模型复验继续收尾，完成后再开始 4.8。
