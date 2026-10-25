# Axel 纹理阶段：合批尾段计时与原生 shader 提交

接续 `axel_chunk_texture_parallel_20261025.md`。验收仍是地图管线开始到当前需求
连续三帧完全就绪；纹理阶段仍只包含地图/预制件纹理，导入模型材质为白模。
不把遮罩揭开、进程启动和完整游戏入口混为一个数字。

证据目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/batch_tail_20261025/`。
该目录保留正常、诊断、失败测试和候选引擎，不能混算。

## 先测关键路径，修正原先假设

新增可关闭的 `ground_batch_timeline.gd`，主线程记录 request/prepare/queued/
dispatch/join/commit/slice/denied，worker 只返回起止两个时间戳。最多 100,000
行，无逐帧磁盘写入，不持有额外 Node/Material/Mesh。worker wall 与主线程区间
重叠，不能相加为加载总时长。默认关闭；运行器 `--batch-timeline` 开启。

| 诊断样本 | 入口 | 完全就绪 | header plan 累计 / max | 最长合批 commit |
| --- | ---: | ---: | ---: | ---: |
| timeline01 | 6.456s | 19.200s | 3685.098 / 2133.834ms | 432.409ms |
| timeline02 | 4.737s | 12.669s | 44.334 / 15.573ms | 322.136ms |

两个样本同源码/引擎，资源未改变，操作系统缓存未清理。不能称作严格物理 cold/
warm 配对或 p95。timeline01 虽然跨请求去重生效（67 miss / 1533 hit），首次
头部读取仍在主线程阻塞；去重没有消除首次磁盘等待。此问题尚未修复。

timeline02 最后约 1 秒含 403.463ms 合批主线程 slice，其中 prepare 291.663ms、
commit 59.138ms（这些已包含在 slice 中）。更早时段多次 batch pending=0；
资源发布直到约 10.7s，随后 streaming 继续到约 12s。不能把整个入口后等待
解释成“合批预算小”，也没有因此扩大 worker 或结果队列。

## GDB 实际归因与独立压测

`initial_gdb03`：安装引擎 SHA
`52f532a05155b18e9614b48531e5fe136bea3a76fc240466adfe7110e0fbaee6`，
GDB 18.1，139 个样本 / 35 个含其他线程，正常退出，游戏功能检查通过。
仅栈采集暂停就超过 131s；所有加载数字均为诊断值，不作为性能对照。

样本 53/54/100/101 等抓到：

`ArrayMesh.surface_set_material / ArrayMesh._set_surfaces → BaseMaterial3D.get_rid
→ _update_shader → shader_create_from_code → ShaderRD._load_from_cache
→ RenderingDeviceDriverVulkan.shader_create_from_container → respv::Shader`

其内部有 parseData、inlineData、sort，以及 MinGW 的 `__emutls_get_address /
pthread_getspecific`。这证明提交包含 CPU shader 处理，不能统一归为上传锁等待；
也不证明所有 shader 提交峰值都由 TLS 查找产生。

`shader_capture04` 通过 GDB 只读取 inferior 内存，提取 32 份实际 SPIR-V 输入
与 SHA/调用栈，未调用 inferior 函数或改资源。游戏正常退出、无错误，输入捕获
成功；通用采样器的 `diagnostic_capture_ok=false` 是因为仅四次周期采样没有脚本
帧，不能把它改写成整轮采样成功。输入和调用栈位于 `spirv_inputs04/`。

候选仅把 re-spirv 中 44 份函数内 `thread_local vector` 绑定为普通局部引用，
保留线程隔离、原有缓冲区复用和完整算法。没有关闭 shader 优化或删掉材质特性。
原版与候选用同一 MinGW 15.2、`-O3 -DNDEBUG` 独立编译。

`micro05` 顺序 A/B/B/A，每次 32 输入 × 5 轮：

| 样本 | 每轮处理整组输入的中位数 |
| --- | ---: |
| A1 | 17.333ms |
| B1 | 11.799ms |
| B2 | 11.945ms |
| A2 | 17.524ms |

所有优化结果逐字节 SHA 一致。`parallel06` 使用 6 线程，每线程轮换输入四次，
原版/候选各 768 次输出比较全部通过。微测收益约 32%，不等于整图加载缩短 32%。
可复用压测源码：`tools/engine_patches/bench_respv.cpp`；引擎补丁：
`tools/engine_patches/godot-4.7.2-respv-tls-alias.patch`。

## 遮罩下空闲预算交接

旧逻辑只允许白模借用闲置发布额度，纹理尾段仍为 2ms，即使已经没有发布任务。
`test_covered_texture_batch_budget.gd` 在真实 cover/queue 上先复现两项失败。
现在仅当 cover 已绘制且 opaque、viewport.disable_3d、queue idle 时，允许
纹理尾段使用原有的 6ms streaming + batch 共享额度。没有加两个独立 6ms。
同帧 streaming 超时仍留零，新的 demand/owner/目标或退休工作即时撤销借用。
遮罩结束、隐藏、恢复 3D、取消也撤销；正常交互纹理仍为 2ms。

启用可选全帧 ledger 时，covered batch 仍受 5ms lane 和总额度约束。没有默认
启用此前关闭的全帧 ledger。对照开关 `--without-covered-batch-borrow`。

相关测试：新 cover 13/13、旧 batch budget 54/54。额外发现
`test_frame_work_budget` 原有断言仍期待旧 7ms publication；生产 policy 已经
是总 32ms。本轮未改该 policy，只把断言纠正为扣除前两项 0.1+8ms 后的 23.9ms，
32/32。失败日志保留为 `test_frame_work_budget_green08.log`。

## GPU 回归与累计对照边界

候选引擎 SHA `0f0bf4469c70de8d051b1e6d22293ed508e077bf1c1a326c6291d50890e583e0`，
匹配独立符号 SHA `358bcf62a75534cdb4aab8bbc96736ea57ec534661764a78825bb3a8c9ad6571`。
构建前 bin 的 SHA 与安装引擎一致。此时先在独立目录验证；最终安装见文末。

`*_candidate10.log` 的 prepared material publication、material publication、
ground batching 真实 GPU 测试均正常退出、无脚本/引擎错误。合批画面平均像素差
0.0000069501，保留碰撞、独立选择、隐藏、paint face 寻址和恢复。该 fixture
含首次 shader 初始化的 2493.686ms build 长帧；这是功能/画面回归，不是加载
性能通过证据，也不能因输出正确而省略这个慢样本。

第一次 prime11 因新 timeline 接入时重复声明测试宿主的 `save()` 而解析失败，
未进入地图；失败产物保留。将记录合入原 `save()` 后重跑 prime12（12.968s）。
prime 单列，不参与 measured 数据。随后跑 A/B/B/A 完整加载、卸载、返回重载。
A 为安装引擎且关闭 cover 借用，
B 为候选引擎且启用借用；这些是累计对照，不能分别归因两项的整图贡献。

### 完整卸载 / 返回 / 重载对照 map12

| 样本 | 入口 | 完整就绪 | 卸载 max / >50ms | 返回 max / >50ms | 重载 max / >50ms |
| --- | ---: | ---: | --- | --- | --- |
| A1 | 4.524s | 12.184s | 29.830 / 0 | 49.702 / 0 | 47.772 / 0 |
| B1 | 7.401s | 16.588s | 32.083 / 0 | 36.679 / 0 | 62.158 / 2 |
| B2 | 4.263s | 11.521s | 30.587 / 0 | 35.664 / 0 | 57.916 / 2 |
| A2 | 4.420s | 12.034s | 29.897 / 0 | 36.215 / 0 | 43.117 / 0 |

四轮功能通过、index hit、源码和地图一致、退出预算/worker/模板全部归零。
GPU 上传仍为 **170 次 / 721,332,072 B**，零 pixel retry。共享 produced
163/165/161/164、DDS reads 141/143/139/142；释放后重新准备的数量受时序影响，
不能把上传量相同扩写成所有 CPU 工作量完全相同。

reload p99 为 35.983/36.272/35.383/35.362ms；1% low 分别为
25.861/23.999/24.119/27.046 FPS，计算方式为 `1000 / 最慢 1% 帧的平均毫秒`。
这里没有证明低帧改善。B1 的 62.158ms 帧附近 geometry tick 42.553ms、publication
12.532ms、render CPU 9.482ms，范围不同不能直接相加，也不能归为纯 OS 空闲。

B1 的 header plan 只有 77.042ms，慢因不等同 timeline01 的首次纹理头 IO。
其 asset_parse_wall 1.664s，对照约 0.664/0.681s；mesh_us 1.512s，对照
0.717/0.665s。多个初始化/原生提交也放大。没有 OS page-fault/驱动 cache 证据，
因此尚不能把原因写死成冷 cache 或引擎回退。该慢样本完整保留。

### 两引擎都已执行后的加载复测 load13

| 样本 | 入口 | 完整就绪 |
| --- | ---: | ---: |
| A1 | 4.416s | 12.435s |
| B1 | 4.204s | 11.318s |
| B2 | 4.262s | 11.332s |
| A2 | 4.500s | 11.908s |

四轮功能与一致性均通过。A 均值 12.172s、B 11.325s，减少 **0.847s / 7.0%**。
这是保留 map12 慢样本后的补充 warm 证据，不能替换首组结果、宣称 cold/p95，
或保证纹理阶段 <10s。map12 中相同几何特征的前几条 material_us：A1 152/152/
150ms，B2 94/104/103ms，A2 151/164/152ms；B1 仍有 479/502/497ms。原生
处理有所减少，但首次提交没有全部消除。

保留有独立收益的引擎补丁与 cover 调度修复；在 map12 阶段暂不覆盖默认安装。
继续使用候选做官方 profiler 诊断 `tail_official14`，查明 reload 的生产耗时。
待处理：首次纹理 metadata 主线程 IO，需求刷新、重载主线程工作与资源回收；
过往 60ms 卸载样本未靠本组零尖峰宣称结案。

## 官方 profiler 复测与重载 UV 重复工作

`tail_official14` 正常退出，接收器/解码/游戏检查均通过，源码与地图一致；仍是
诊断样本，不能与正常 A/B 加载时间混算。关键帧：

| 阶段 / 帧 | wall / process | 已归因生产调用 |
| --- | --- | --- |
| unload / 9074 | 55.874 / 55.872ms | selection.prepare 19.312ms，其中 7 次 Thread.wait_to_finish 10.969ms；导航 _retire_selected 12.836ms |
| reload / 27338 | 51.667 / 51.489ms | painted_mesh 21.163ms，含 geometry 7.546ms、from_surfaces 2.892ms、37 次 JSON.stringify 1.729ms |

这些范围有包含关系，不相加。selection.rows 的 8 次累计 82.896ms 包含子线程，
不能算到主线程；但调用链 `NativeResidency._process → WorldStream.retire_specs
→ _retirement_preflight → StreamIndex._resident_owned_retire_plan → Selection.prepare`
确实在主线程同步启动并 join。不能再称这段已完成后台化。下一步必须解决跨帧
准备的不可变所有权和提交时需求变化，不能直接把对 live Dictionary 的读取丢给
线程、让主线程继续修改它。导航原子移除与需求刷新仍有工作。

`_uvs` 的原始 UV 模式与面平面无关，却先遍历该面的所有三角形计算投影边界，
再为每顶点重复读取同一旋转/缩放/偏移。现在在有效原始 UV 分支直接复制 packed
数组、提前构造变换；不改 planar/meters 以及缺失/不完整 UV 的原有回退。源 UV
和作者记录不变。诊断开关 `--without-uv-projection-elision` 保留同代码 A/B。

`bench_surface_uv_projection.gd` 使用冻结旧源码
`surface_materials_before_uv15.gd`（SHA
`f9bab77c3fe598d8acbf93850033e51ff5ed930d802c854a1c4fd0b0bd296cb0`），
先在未修改代码上复现相同耗时，再进行 A/B/B/A；每格五次：

| 三角形 / 顶点 | 旧单次约 | 新单次约 |
| --- | ---: | ---: |
| 128 / 81 | 169us | 6–7us |
| 2,048 / 1,089 | 2,453us | 62–63us |
| 32,768 / 16,641 | 38,500us | 933us |

37 项检查通过：三种 mapping、三种旋转、负缩放、所有 UV 字节、源数组不变、
缺失 UV 回退，以及有效 UV 不访问未使用的几何面描述。最大 fixture 减少
98,304 次无用角点投影；这是 CPU 组件收益，不是整图 40 倍提速。
`test_surface_uv_batch` 6 项 GPU 输出/合批/作者记录检查通过。
初版 bench 有一处 Script 静态调用解析错误（uv_repro15b），修正后复现/对照
为 uv_repro15c / uv_candidate16；失败产物保留。

## 回归发现的失败纹理磁盘缓存缺口

`test_immutable_mesh_upload_uv17`：几何/材质/CPU/GPU 34 项通过，但“修复纹理
后读回新像素”失败。关闭 UV 新分支，原安装引擎和 TLS 候选均复现同一个失败
（immutable_old18 / immutable_alias18），GPU 回读新旧均为红色。

根因是明确的 failed handoff 只撤销热/弱材质纹理引用，未撤销 trusted path
identity 的磁盘像素产品。相同路径修复成蓝色后仍重新读取旧红色缓存。这不靠
恢复逐次 SHA 校验解决：现在只在 editor handoff install/restore 的明确失败
列表中删除对应像素缓存，保留其他路径/方向，以及已有消费者的旧资源。
普通成功加载无新增 IO。`test_failed_texture_disk_handoff` 13/13，覆盖正常/
翻转 variant、install/restore 两个通知、旧消费者、新磁盘命中、无 SHA 扫描；
真实 GPU immutable_fixed20 35/35，修复前失败已转绿。

旧 `test_world3d_surface_paint` 另外暴露了测试宿主的三处旧假设：工具固定总数
118、正式地图必含 glTF images、通过 GLTFDocument 直接读取原生运行产品。
前两处改为核对必需工具名、显式构造非法 URI fixture；第三处按 reference-map
合同检查 glTF 仅含 proxy、没有重复烘焙纹理。真实原生游戏加载由独立材质发布
测试和本轮 axel_town 实测覆盖，不将 GLTFDocument 当作游戏入口。
editor18 在旧 images 访问处报错并超时，日志从仍可核对的引擎轮换文件保留；
editor20 为截取到保存重开的诊断子集，不能当完整回归通过。editor21 完整运行
75 项通过、仅旧 glTF runtime 检查失败；editor23 曾因测试变量重名解析失败。
这些都不算生产性能样本。

额外测试适配尝试也保留：editor24 的 MapLoader 子测试缺 native 产物，错误处理
又直接 free 了正在发信号的 loader，形成夹具错误并超时；editor25/compile26
查到自造 GLB 带 `GODOT_single_root`，既有 static importer 拒绝该扩展。
editor27 尝试改变该 fixture 的导出 root mode，又改变了 prefab 节点寻址并报错；
已停止这个已报错的自有测试进程。这些尝试均未修改生产 importer，也没有扩大
白名单、恢复游戏 raw GLB 回退或宣称 native 导入问题已解决。最终保留原 fixture
的几何/节点结构，仅修正上述三项旧测试合同。

最终 `paint_full28` 为 76/76，无脚本/引擎错误，包含真实 HTTP 工具发现与调用、
非法输入无副作用、undo/redo、保存重开、prefab、实际鼠标笔刷和 UI 操作。
截图路径仅在外部复制的 fixture 中重定向，未覆盖旧图；本轮未将原 PNG 上传
查看。以上是编辑器功能回归，不代替全模型材质画质验收。

后续优先级（尚未实施，不能当作收益）：

1. 纹理头部首次 miss 的有界后台准备：沿用同一个 worker/byte admission，完成
   后主线程只接收结果，跨请求共享去重，取消/来源 generation 改变时不可发布。
   禁止为消除 FileAccess 等待而建立无预算线程或重复估算/解码。
2. 卸载 selection 与导航移除：先复用已有发布目录，去掉重新扫描/聚合；需要
   跨帧准备时，先证明输入不可变、提交版本与当前需求仍有效。不能把当前 live
   Dictionary 无保护地交给异步 worker，更不能把同步 join 改个名字就算解决。
3. 重载 painted_mesh 的其余部分：geometry 拓扑、重复 JSON 分组、重新扫描
   bounds 仍在主线程；本次 UV 优化仅处理了已证明无用的一段。

## 10 月 26 日凌晨：同候选引擎的 UV 单项 ABBA

`map22_A1/B1/B2/A2` 均使用 alias06 引擎、covered idle 借用开启；只有 A 关闭
UV projection elision。四组 source/map 未变、功能通过、index hit、普通优先级，
无 cache purge / QoS 操作；测试间没有并行 GPU 或压测工作。

| 样本 | 入口 / 完整就绪 | 卸载 max | 返回 max | 重载 max / >50ms | 重载 p99 | 重载 1% low |
| --- | --- | ---: | ---: | --- | ---: | ---: |
| A1 | 6.351 / 13.419s | 49.038ms | 30.449ms | 45.558ms / 0 | 35.303ms | 26.253 FPS |
| B1 | 4.245 / 11.197s | 31.462ms | 31.986ms | 42.375ms / 0 | 33.486ms | 27.184 FPS |
| B2 | 4.124 / 11.166s | 43.474ms | 29.926ms | 43.263ms / 0 | 34.512ms | 26.884 FPS |
| A2 | 4.314 / 11.385s | 36.301ms | 34.377ms | 52.263ms / 1 | 37.019ms | 24.895 FPS |

1% low 算法沿用上文。重载均值由 25.574 → 27.034 FPS（约 +5.7%），p99 均值
36.161 → 33.999ms；只有各两轮，不能作为全游戏或长期稳定性保证。B 的卸载/
返回/重载均为零帧 >50ms；A 的卸载/返回也为零。不能把 map12 的全部慢帧消失
都归给 UV 一项，时序变化与测量波动仍存在。

A1 的入口明显更慢，header plan 仍仅 82.216ms。两组完整就绪均值直接相减会
夸大 UV 收益；保留该样本，不报这种百分比。warm A2 11.385s，对比 B 两轮
11.197/11.166s 只显示约 0.19–0.22s 差值；入口之后尾段四轮分别
7.068/6.952/7.042/7.071s。仍未证明总加载稳定 <10s。

工作量：四组均 170 次 GPU 上传 / 721,332,072 B，其中 DDS 148 次 /
508,911,392 B；shared produced 162/166/164/164，DDS reads 140/144/142/142。
原始像素准备数会因资源生存期变化，不能说每项 CPU 工作完全相同。所有最终
admission/worker/template/shared consumer/output/retained bytes 归零，释放的
geometry logical bytes 均 167,884,640。B2 仍记录 geometry main max 20.954ms、
private slice max 23.169ms，不能因当轮没有 >50ms 卸载帧宣称回收彻底解决。

另四组 post_ready_steady 各一帧 >50ms，分别 52.080/59.095/54.442/55.224ms。
对应 previous draw wall 46.556/49.910/49.849/50.760ms，previous process
5.594/9.163/4.646/4.430ms；Deferred publication=0、stream/batch pending=0。
这是 draw/presentation 等待段的定位线索，尚无该帧 GDB 栈，不能直接盖章 OS
问题或非生产路径。证据 `map22_slow_splits.json`；继续独立处理。

## 最终安装与交接

10 月 26 日在微测/并发输出逐字节验证、GPU 回归、编辑器 76 项回归、map22
两轮完整候选遍历通过后，沿用用户已有引擎替换授权，安装 alias06：

- `D:/tools/godot/godot.windows.editor.x86_64.exe`
- `D:/tools/godot/Godot_v4.7.2-stable_win64.exe`
- `D:/tools/godot/godot.windows.editor.x86_64.exe.debugsymbols`

安装前及备份后均确认该目录没有运行进程，未停止用户应用。原 exe、别名、匹配
symbols 和既有 manifest 完整复制到 `D:/tools/godot/_backup/respv_tls_20261026/`，
逐文件校验备份 SHA 后才覆盖。安装后 exe/symbols SHA 与本轮已测候选一致，
`--headless --version` 退出 0。console launcher 未改变。
记录为证据目录 `installed_respvtls_20261026.json` 和安装目录
`respv_tls_build_manifest_20261026.json`。引擎源码可反向检查本仓库 patch，未
触碰既有其他补丁。没有因此把 >10s、draw 等待、退休同步 join 标记为完成。
