# Axel 纹理阶段：StandardMaterial3D 变体释放后重复创建

## 范围与基线

本轮从 `4c2ba020` 接手，复核最近三次提交：

- `4c2ba020`：DDS sidecar 上传；保留其压缩上传方向。编辑器刷新、法线转换与 mip 链另有实际缺口，交由编辑器子任务修复。
- `96c8dfa4`：纹理阶段准备/发布与 mounted source identity；本轮不恢复逐纹理内容认证、不引入 GLB 游戏回退。
- `7657696b`：白模返回等待和无栈 AV 的证据记录，不代表 AV 已修复。

隐藏三角 mesh 预热已在接手前完整撤回。其 `map_traverse_27` 慢样本仍保留，不能重用为本轮候选收益。实际基线为压缩 DDS 已启用、隐藏 mesh 预热关闭。

测量边界继续沿用：地图加载计时开始 → 当前需求区域连续三帧完整就绪。当前是地图/预制件纹理阶段，导入模型材质仍为白模，HUD 等外围系统尚未恢复；不是完整游戏验收。

## 直接证据

所有外部证据位于：

`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/material_submit_review_20261025/`

### 真实地图 GDB

`material_return_gdb01` 使用 c593 基线引擎及校验匹配的 debug symbols、GDB 18.1，在私人桌面的自有 PID 上，返回阶段触发 all-stop 采样。正常退出，40 次采样、40 次包含其他线程，无脚本错误、功能失败或源文件变化。

其中 4 次主线程采样直接命中：

```text
ground_cpu_mesh.gd::restore
ArrayMesh::surface_set_material
BaseMaterial3D::get_rid
BaseMaterial3D::_update_shader
RenderingServerDefault::shader_create_from_code
RendererRD::MaterialStorage::shader_set_code
SceneShaderForwardClustered::ShaderData::set_code
ShaderRD::_load_from_cache
RenderingDeviceDriverVulkan::shader_create_from_container
respv::Shader::parse / inlineData / ~Shader
```

另一命中栈位于该链的 Vulkan shader module 驱动调用。它证明这里仍在从缓存字节同步创建 shader，包括 re-spirv 的解析、内联、临时结构释放；不能把这段统称为纹理上传，也不能断言是主线程等待后台上传锁。

调试器采集自身累计暂停约 114 秒，只获约 2.626 秒运行间隔后到达 wall cap。全部调试时长仅作定位，不从暂停时间中扣减来虚构正常加载耗时。归纳栈见 `material_submit_native_chains.json`，完整原始栈、MI 日志、源快照、引擎 SHA 均保留。

### 独立复现

`material_reuse_before.log`：同一 shader 变体仍有材质实例存活时，另外 15 个等价实例绑定约 13–19µs；重复取同一材质 RID 约 0–1µs。全部释放后，四次重建同一个变体分别 44.773 / 22.324 / 22.183 / 21.563ms。

这排除了“必须每个几何组合都创建一遍该 shader”的解释：此处成本由 BaseMaterial3D 的材质特征键和 shader 生命周期决定。首次绘制的 graphics pipeline 成本仍是另一条边界。

### 地图变体核对

`material_variants01` 临时记录全部 CpuMesh 绑定的整数/布尔属性和时点。7034 次绑定分为 8 类 StandardMaterial3D 特征组合，另有一类 ShaderMaterial；13 次 StandardMaterial3D 绑定超过 10ms。

返回时，7 类变体再次出现 143.900–182.044ms 提交。分别包括 normal+AO、normal、普通各向异性、双面、顶点色、透明和 normal+AO+顶点色。入口已使用过这些类别。对应源码在最后一个使用者消失时立即 `free_rid` 并从 `shader_map` 删除，返回即重建。

该全量属性诊断增加了观测工作，不计入普通性能样本；代码已撤回，补丁保存在 `variant_diagnostic.patch`，原始报告和分组在 `variant_summary.json`。

## 修复机制

补丁：`tools/engine_patches/godot-4.7.2-standard-shader-residency.patch`。

- 用引擎既有的精确 `MaterialKey` 复用 shader，不另造不完整的 GDScript 特征键。
- 最后一个使用者释放后，仅将 shader RID 放入闲置队列；默认最多 32 个，可设置 0 恢复立即释放。
- 重新引用从闲置队列移除，之后释放时放到队尾。超限淘汰最早闲置的项；活跃项不被淘汰。
- 队列登记和既有 map 均使用现有 `shader_map_mutex`。shader 创建仍在该锁外，保留原有并发重复创建的仲裁。
- 材质、纹理、网格、场景节点不被此队列持有。退出阶段释放全部闲置 RID，并关闭继续保留。
- 不添加隐藏 mesh、不提前创建未使用变体、不增加加载生产队列容量。

项目设置 `rendering/shader_compiler/max_unused_standard_material_shaders` 范围 0–256，默认 32。诊断环境变量 `RMMO_STANDARD_SHADER_CACHE_LIMIT` 覆盖本次进程的上限；`RMMO_STANDARD_SHADER_CACHE_PROFILE=1` 在退出打印实际创建、闲置复用、淘汰和剩余闲置数。普通运行不打印。

32 是闲置变体数量上限，不是测得的 GPU 字节上限。首次进程加载仍须创建实际首次使用的变体，不能把返回复用收益声称为消除了全部初始 shader 成本。

## 构建与验收

后续安装记录：独立 GPU 和地图 ABBA 验收后，已将候选 exe 复制到 `D:/tools/godot/godot.windows.editor.x86_64.exe` 及 `Godot_v4.7.2-stable_win64.exe`，并同步匹配的 `.debugsymbols`。安装前确认没有该目录运行进程，未中断用户应用；旧 exe、symbols、manifest 和说明保存在 `D:/tools/godot/_backup/shader_residency_20261025/`。安装后 SHA 与下列候选一致，`--headless --version` 退出 0。证据为 `installed_engine_20261025.json` 及安装目录 `shader_residency_build_manifest_20261025.json`；既有 console launcher 保持原字节。

候选从原有 b058 源码构建，保留其默认关闭的 release169 诊断。原源文件、exe 和匹配 symbols 已备份至 `engine_baseline/`。因此主要因果对照使用同一候选引擎、cache limit 0/32，不把不同引擎补丁的差异混算为本次收益。正式 `D:/tools/godot` 安装未在构建步骤替换。

独立回归入口：

```text
python tools/check_standard_shader_residency.py --engine <candidate.exe> --output <new external directory>
```

每个子进程在私人桌面运行真实 Vulkan。测试包括等价/同一/duplicate 材质、最后使用者释放后返回、36 个变体超限淘汰、活跃材质跨淘汰存活、两个 worker 并发创建/修改/释放，以及红/绿/红贴图实际渲染读回。弱引用检查纹理、材质和网格均可释放。正常帧时比较等待构建结束后独立运行，编译同时发生的功能检查不作性能证据。

地图对照由外部 `run_shader_cache_abba.py` 按 0/32/32/0 顺序执行；期间冻结源脚本及实际地图 DDS。每次分别记录 full-ready、卸载/返回/重载长帧、shader 创建工作量、上传字节和退休工作量。保持所有慢样本，四个样本不能声称 p95 已稳定。

### 独立 GPU 回归结果

候选构建完成（编译/链接 1128.953 秒），exe SHA-256：
`eaec8870dd5940aefff21510bbd559e316e4aa3abe2985738206a9ac0348d73c`。
匹配 symbols：`0b8b0e610320f06e2a0b020416cac20d4097306f6b20a4cf76a3e0dc87187ac0`。

`fixture_candidate01/result.json` 四个进程均退出 0，每次 9 项语义检查通过，无引擎或脚本错误。

| 次序 / 闲置上限 | shader 创建 | 闲置复用 | 超限淘汰 | 退出清理前闲置数 | 释放后重新绑定（四次） |
| --- | ---: | ---: | ---: | ---: | --- |
| A / 0 | 177 | 0 | 0 | 0 | 27.661 / 35.738 / 22.054 / 21.949ms |
| 压测 / 2 | 169 | 59 | 104 | 2 | 43 / 32 / 29 / 47µs |
| B / 32 | 46 | 84 | 11 | 32 | 36 / 32 / 38 / 27µs |
| A / 0 | 178 | 0 | 0 | 0 | 26.255 / 23.023 / 23.448 / 24.542ms |

同输入并发测试的实际创建次数可因原有创建仲裁产生 1 次差异，故保留两端控制样本。小上限 2 有意制造重复淘汰，不作为推荐配置。未加入新的跨线程 shader 创建串行锁。

纹理/材质/网格三个弱引用均消失；活跃材质跨 36 变体淘汰仍可提交。四进程的红/绿/红实际图像 SHA 完全相同，也与 c593 原始引擎语义用例相同。这里验证精确 shader 键与实例参数隔离，没有声称完成所有地图资产画质验收。

### 真实地图 ABBA

全部使用同一候选 exe，普通优先级、不改 QoS、不清 OS cache；脚本和地图 DDS 在四轮间冻结。派生几何、模型元数据和 prefab bounds cache 关闭，实际输入相同。四轮正常退出，全部功能断言通过，map/source SHA 未变。

| 次序 / 上限 | full-ready | shader 创建 / 闲置复用 | 卸载 max / >50ms 帧 | 返回 max / >50ms 帧 | 重载 max / >50ms 帧 |
| --- | ---: | ---: | --- | --- | --- |
| A1 / 0 | 31.416s | 17 / 0 | 114.352ms / 1 | 427.972ms / 10 | 48.858ms / 0 |
| B1 / 32 | 17.813s | 10 / 7 | 32.410ms / 0 | 211.411ms / 29 | 87.978ms / 17 |
| B2 / 32 | 18.292s | 10 / 7 | 34.091ms / 0 | 55.523ms / 1 | 46.181ms / 0 |
| A2 / 0 | 17.814s | 17 / 0 | 79.453ms / 2 | 385.625ms / 7 | 71.601ms / 9 |

证据：`shader_cache_abba_summary.json`、四组 `shader_cache_{A1,B1,B2,A2}.{json,log,launch.json,result.json}`。

A1 初始绑定有 574–932ms 慢样本，完整保留；不能拿它与 B1 相减宣称初始加载改善。A2 和 B1 full-ready 基本相同，本补丁尚无稳定的初始加载时间收益。两轮 B 的返回阶段不再重复已出现变体的 150–196ms 创建，精确工作量从 17 降至 10；但 B1 的更多长帧和重载波动不能隐藏，纹理阶段未完成。

每轮实际纹理上传总量均为 **862,537,776 B**，其中 DDS **297,795,584 B**、124 次；其余 564,742,192 B、46 次。先前 564,742,192 B 的统计漏计 DDS，不是实际总量，不能继续据此宣称上传减少 75%。每轮退休 504 单元 / 3677 specs，cleanup 504，未通过省略卸载工作降低 shader 创建数。

A1/B1 同相机地图画面已按有损 WebP quality=90 保存并查看，未发现 shader 复用造成的可见材质串用；导入模型仍处于白材质阶段，不能据此声称全资源纹理画质验收。

### 剩余长帧与诊断边界

B1 的 211.411ms 返回帧中，Deferred bookkeeping 占 160.480ms；该轮需求刷新最大 157.324ms。join/sync 均为零。时间落在需求刷新调用内，不能套用“Deferred 全空”的 OS 空闲分类；这些仍是墙钟 span，不能排除调用期间的 OS 抢占。B2 最大需求刷新 31.543ms，返回唯一 >50ms 帧有 52.886ms publication，后续仍需分别追踪。

第二次 `demand_return_gdb02` 采集 153 栈，all-stop 暂停累计 68.089s，未修改输入源，但地图需求收敛、最大建筑 UUID 和 terrain/GPU 恢复断言失败。该样本 `diagnostic_capture_ok=false`，不能作为正常功能或性能通过证据，也不能通过减去暂停时间冒充正常测量。栈用于局部定位，暂停是否导致断言失败未单独证明。

随后 `demand_official01` 使用官方 profiler，游戏与 recorder 均退出 0，7578 帧、1605 signatures、零错误，地图与源脚本未变。返回最慢记录帧 89.362ms 中 `_refresh_demanded` total 79.581ms、self 48.820ms；另有 10.173ms `_in_clip_catalogue`。后台 `terrain_regions.mask` 五次调用累计 28.685s，并执行 15,848,516 次 `Geometry2D.get_closest_point_to_segment`。后台函数累计时间和主线程帧时不是同一口径，不能相加，亦不能仅凭重叠就声称后台遮罩导致主线程 160ms。下一步先以逐像素 oracle 复现遮罩的重复边距计算，再测独立算法和真实地图。

后续已完成遮罩独立回归与 ABBA，见 `axel_terrain_mask_band_20261025.md`；编辑器 DDS/法线修复后的最终累计样本见 `axel_texture_phase_20261025.md`。最新安装为叠加 DDS 部分块修复的 52f532，shader residency 逻辑未改，eaec 对照及其 symbols 保留；安装身份见 `axel_dds_partial_blocks_20261025.md`。
