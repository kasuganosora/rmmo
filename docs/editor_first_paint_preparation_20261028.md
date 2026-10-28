# 编辑器导入像素交接、缩略图与首次涂材质

当前先完成编辑器适配，Godot 4.8 尚未开始。本批与旧素材 native 迁移分开验收；不修改正式地图，不恢复 GLB 普通加载回退。

## 已实现并验证的交接

UI 与真实 3D HTTP MCP 使用同一个导入协调器。后台生产者返回实际编码完成的 DDS Image，PNG 回退则返回同一次解码的 Image。主线程在 worker 已退出、原预算仍被持有时上传，并复用现有纹理缓存；清除 CPU Image 引用后归还额度，再通知订阅者。同内容 follower 不携带脱离预算的 Image，也不重复使新 owner 失效。GPU 上传本身仍在主线程。

导入时从已解码图片生成一份 104×64 以内、保持比例的缩略图。可见缩略图队列接入编辑器共享账本：先小头部/小缓存探测，缺缓存再按源尺寸准入解码；同源多个名称共享输出。取消和关闭不等待 worker，退出后由 drainer 归还预算。已导入缩略图用源 SHA 身份、长度和 mtime 关联，不对每次游戏加载重新哈希资源包。额外 JSON 副产物不再当作材质描述解析。

移除图片导入的 16 MiB/4096 任意上限、纹理准备的源数量/累计输出截断，保留引擎图像和整数范围及共享运行预算。未知 codec 使用保守独占准入；它不是“超过 8 GiB 不可导入”的磁盘限制，也不是 RSS 保证。

## 功能与工作量证据

统一证据根：`D:/code/rmmo_runtime/review_artifacts/editor_dds_import_proto_20261028/`。图形测试均通过私有桌面 runner，不抢焦点；每个样本记录源码、工具和引擎前后身份。

| 合同 | 结果 |
| --- | --- |
| 缩略图实际队列、同源去重、侧车复用、TGA、取消与关闭 | `limits_01/thumbnail_contract_01`，21/0 |
| 导入 worker、尺寸/长度变化、PNG 回退、缩略图身份修复 | `worker_handoff_02`，46/0 |
| 订阅者、取消重试、真实发布时预算、CPU Image 不进 HTTP、闲置回收 | `coordinator_handoff_01`，44/0 |
| 目标 PNG 已被修改，再导入不得覆盖 | `conflict_red_01` 13 项/2 失败；`conflict_green_01` 13/0 |
| 实际 DDS、旧 owner、River/Prefab 定向失效、延迟 follower、UI 导入与 LoadJob 共用额度 | `gpu_required_dds_01/handoff_gpu_01`，32/0 |
| 无 CPU API 的旧 GREEN 引擎实际 PNG 回退/UI/HTTP/并发 LoadJob | `legacy_after_handoff_01`，20/0；不是 DDS 样本 |
| 真实宽度 4097×2 图片 | `large_red_01` 6 项/2 失败；`large_green_01` 6/0 |
| DDS/后台纹理准备原合同 | `test_compressed_texture_source_01` 337/0；`test_prefab_texture_preparation_02` 63/0；共享预算 11/0 |

`worker_handoff_01` 保留一个测试失败：测试自己未关闭 metadata 的 Windows 文件句柄，导致模拟删除失败。仅补关闭句柄后重跑；没有把该失败写成生产缺陷。早期纹理准备合同仍期待旧数量截断，已按用户要求更改断言并保留失败日志。

四条首次涂材质固定合同（DDS/PNG × HTTP/UI）在 `first_paint_01/`：旧版每条 2 个失败，候选全部通过。DDS 主线程重复读取从 1→0；PNG 主线程读取/解码从 1→0；四条均复用 GPU owner，并通过撤销、重做、保存重开和共享缩略图预算。单次帧间隔仍为 54–142ms；这些短样本不能提供 p95，也不能据此宣称所有长帧消失。

## 8K 实际操作与原生堆栈

`large_import_01/` 使用合成 8192×8192 RGBA，走真实 HTTP 导入、实际涂面、撤销重做和保存重开。完成绘制计时后读回 GPU 图片：实际 8K、DXT5、完整 mip **89,478,512 bytes**，颜色和 alpha 检查通过。均匀颜色负载用于管线/尺寸验证，不替代真实美术的有损 DDS 画质验收。

初次无调试器样本：Compatibility 导入 6.475s、首次涂材质 1.260s、最大帧间隔 1088ms；Forward+ 导入 6.359s、首次涂材质 1.655s、最大帧间隔 1582ms。采样进程峰值 RSS 分别约 1.54GB/2.47GB，包含测试宿主和后续 GPU 读回；不是导入阶段专属峰值或 VRAM。小图功能合同不能外推大图无卡顿。

GDB 18.1 两次受控捕获在 `large_import_01/gdb_probe/runs/`，仅附加本轮拥有且校验过 PID/exe 的进程：

- Compatibility：主线程在 `ShaderGLES3::_compile_specialization` 的 fragment `glCompileShader` 等待 AMD 驱动，来自首次材质版本/特化绑定。
- Forward+：主线程 `VisualInstance3D` 释放 → `RendererSceneCull::free` → dirty resource/material 刷新 → `MaterialData::update_parameters` → `ShaderRD::_compile_version_end` → 等待编译组；后台线程同时在 glslang 编译。记录不是纹理解码栈。
- 全线程 all-stop 样本本身耗时很大（Forward+ 一次收集约 10 秒）；调试运行的帧时间不进入收益比较。

## 去掉丢弃的验证网格

`SurfacePaintTool.paint` 原先调用 `painted_mesh` 完整构建一个未使用的验证网格，随后 `_commit/_refresh_records` 再构建最终网格。第一次创建的新材质还使随后的旧实例释放遇到未完成 shader 编译。

现抽出共享 `validate_paint`，保留几何签名、可绘制面、UV、贴图和既有槽位检查，提交前不创建新 painted material/网格；最终网格只构建一次。没有取消非法操作保护。独立检查 `limits_01/paint_validation_01` 11/0；真实 HTTP 同测试 `single_build_01/dds_http_red_01` 唯一失败为构建次数，候选 `dds_http_green_01` 通过，材质构建调用 2→1。删除工作不等同于把所有 shader 成本消除。

首次 8K Forward+ 候选样本 `dds_8k_forward_single_build_01`：导入 6.584s，首次涂材质 195ms，最大帧间隔 128ms，材质调用一次。**后续 A/B/B/A 未证明上述秒级下降来自此次改动。** 固定同一个提取后的校验内核，仅切换调用点的丢弃构建 A/校验 B，结果如下；每次独立应用/shader 目录，但未清显卡驱动缓存：

| 样本 | 导入 ms | 首次涂材质 ms | 最大帧间隔 ms | 材质构建调用 |
| --- | ---: | ---: | ---: | ---: |
| A1 | 6566.899 | 204.196 | 143.751 | 2 |
| B1 | 6834.561 | 186.946 | 119.515 | 1 |
| B2 | 6783.521 | 260.933 | 134.356 | 1 |
| A2 | 6575.854 | 210.860 | 143.997 | 2 |

四条都通过实际 GPU 读回、保存重开与无重复主线程读图。A/B 的完整调用时间重叠，且 A 已不再出现此前秒级尖峰，不能宣传稳定时间倍率或 shader 编译已解决。保留已证明的工作量减少，继续区分冷 shader/驱动缓存。证据 `large_import_01/single_build_abba_01/result.json`；脚本保存两种源码、每次身份并确认最终恢复 B。

审查又发现超热缓存预算时的生命周期缺口：新校验临时访问纹理后，唯一强引用可能被释放，真正提交再次读取/上传。零缓存预算独立复现 `paint_owners_red_01` 为 9 项/4 失败，实际 lookup/upload 均 3 次。修复让校验包借用 GPU Texture2D 到本次提交结束，由最终网格接手，既不复制像素也不提高缓存预算；`paint_owners_green_01` 10/0，lookup/upload 均 1 次、实际材质 owner 相同。新增通过断言只在 owner 存在时执行，所以红绿检查数不同；不是省略失败。该修复覆盖事务内复用，不能据此称导入时超预算的大图在很久后首次使用也不会重读。

最终补跑 `paint_preparation_regression_01` 151/0，覆盖多面、多槽、法线、不同 UV 映射、几何数组一致、取消和生产交接；`single_build_01/png_ui_green_01` 通过实际 UI 单次构建、无重复读图、撤销重做和保存重开。这些回归不提供整城性能收益。

## 未完成边界

1. 冷 shader 编译及首次 GPU 提交仍有成本；缓存淘汰后的老材质首次使用、超出热缓存预算的单张图片，尚未由本次“导入后立即使用”合同全面覆盖。
2. 当前设备上 8K 实际成功，不代表所有 GPU 支持任意合法 Image 尺寸。ImageTexture 非空/尺寸正确本身不能证明驱动分配成功；本次以独立 GPU 读回证明该实际输入。
3. canonical PNG 首次发布的跨进程竞争仍在外部原型中。顺序冲突已修；不得宣称它解决检查后被另一个进程创建目标的竞争。DDS 与身份文件的跨进程多文件一致性另有边界。
4. 分支合并、候选引擎正式安装、真实材质画质、完整编辑器地图打开/关闭与剩余迁移图审继续收尾。新引擎评估严格后置。
