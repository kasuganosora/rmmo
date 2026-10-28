# 编辑器表面贴图后台导入：实现与验证边界

本记录对应独立 worktree `editor-texture-import`，基于 `6b17a55596de80132c3424182a283ba8b481dde9`。本分支未合并到正式 worktree，也未改写正式素材。

UI 与 3D MCP 共用后台导入协调器。源图片在工作线程读取与解码，先对小文件头测量尺寸并获得与地图加载共享的准入额度，再读取一次完整快照；若长度或尺寸与准入观察不符，重新探测。当前候选移除固定的 16 MiB / 4096×4096 素材拒绝；额度是按阶段推算的工作量，不是实测或保证的 RSS 上界。大图、设备纹理上限与同步回退的完整验证仍待完成。

相同路径的并发请求共用准备工作；不同路径的输入在各自准备为规范 PNG 后，按内容地址共享 DDS producer。同内容同名称合并材质描述发布，取消按订阅者生效；最后一个订阅者取消后再提交同一路径会创建独立代际。内容和名称计算、文件发布均在后台。名称身份单独按实际长度预留工作额度，未新增名称长度限制。

各准备队列共用 editor-owned admission ledger，内部 lease key 按队列命名空间隔离；已取消但尚未退出的任务继续占用原额度。已完成的导入任务移出队列历史，空闲时停止队列处理。DDS 就绪时按路径更新 Paint、River terrain 和 Prefab 派生缓存；已在场景中使用的旧资源持有者不被修改。缓存和 GUI 实际行为仍须 GPU 回归。

图像编码使用引擎显式的 `Image.compress_from_channels_cpu` 接口。旧引擎没有该接口时直接保留 PNG，非 4 倍尺寸或编码/发布失败也使用 PNG；不会为单次调用临时修改全局 GPU 编码设置。新候选引擎 `3d65b357…` 已提供实际 CPU DDS 生产并通过真实 HTTP/UI 合同，尚未替换默认安装。32×32 最小独立程序证明了旧 GPU 压缩初始化的局部 RenderingDevice singleton/context 竞态；GDB 现场及范围见 `D:/code/rmmo_runtime/review_artifacts/editor_dds_import_proto_20261028/device_race_repro_01/README.md`。第一次真实 HTTP GPU 样本 `private_01` 堆栈相符，但缺当时完整业务源码，不单独作为完整因果证明。引擎修补与运行证据在主分支 `docs/editor_dds_engine_contract_20261028.md`。

新 sidecar 只在目标 DDS 尚不存在时先发布身份再发布 DDS。中断在两者之间时没有可被选择的 DDS，仍可使用 PNG；已存在的不匹配副产物明确报错，不能声称回退成功。正常 DDS 编码验证注入只在 headless 测试启用，不是产品路径。

## 记录的测试

证据目录：`D:/code/rmmo_runtime/review_artifacts/editor_dds_import_proto_20261028/`。其中 `headless_redgreen_06/` 包含命令、PID、日志、引擎及源码前后 SHA 和 `injected_defect_manifest.json`。注入版是人为恢复本轮初稿中的单项缺陷，并非发布过的旧提交：

- `red_grown` 先读取增长到 16 MiB 的源，再检查先前准入；该断言失败。对应绿样本在读取前拒绝，worker **33/0**。
- `red_broker_history` 人为移除 follower 空状态重探测和任务记录回收，**9 项失败**，包括剩余 follower 未完成和重复导入后历史条目残留；绿样本 coordinator **37/0**，含三源同内容、producer 取消、首 follower 源删除后的幸存 follower，以及大小名称和同名称共享发布。
- 共享预算及同逻辑 key 跨操作回收 **11/0**；既有 editor load preparation **130/0**。上述绿样本脚本日志无引擎错误，源码及引擎前后身份一致。
- 旧离线 Python DDS 生产器 **20/0**，仅证明既有工具合同，不证明本次引擎编码入口。
- 后续最终 headless `headless_07`：共享预算 **11/0**、worker **34/0**、coordinator **38/0**；`private_02` 使用旧 GREEN 引擎和私有桌面，真实 HTTP/UI/地图加载共享账本 **20/0**。一条被栅栏暂缓的 HTTP 导入期间，另一客户端 `editor_state` 得到响应；实际 UI 导入与地图打开交叠时共用同一 ledger，最终 lease 为零。fixture 中只有 PNG 和材质 JSON，符合旧引擎缺少 CPU API 时的实际 PNG 路径。日志无脚本或引擎错误，源码及引擎前后身份一致。

之前 `headless_02` 的协调器断言虽然全部通过，日志却暴露后台访问 SceneTree 取内容根的线程错误；已改为主线程解析根后传值，失败样本保留。`private_01` 在崩溃前确认一个被挂起的 HTTP 导入不会阻止另一客户端 `editor_state` 响应。随后 `private_02` 已覆盖旧 GREEN 的 HTTP/UI PNG 回退与真实编辑器打开交叠，但 DDS 分支未执行，旧材质 owner、River/Prefab 定向失效及 DDS 实际图形结果仍待新引擎验证；不能把 PNG 测试当作 DDS 交付完成。

最新实际 DDS HTTP/UI 32/0、首次涂材质四路径、缩略图共享预算、8K GPU 读回，以及重复验证网格/超缓存预算 owner 修复，见 [首次涂材质记录](editor_first_paint_preparation_20261028.md)。实际美术画质、完整编辑器地图和分支集成仍待完成；不得用合成贴图合同代替这些验收。
