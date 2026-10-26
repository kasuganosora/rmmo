# 共享纹理后台上传：复现、候选与实际地图边界

接续主日志 §171 的真实返回调用栈。本轮目标是降低主线程纹理提交压力，同时保持
共享去重、预算、编辑源替换和回收语义；没有更换纹理、压缩格式或修改引擎。
完整就绪仍为地图加载开始至当前需求完整就绪，不是首屏或进程启动时间。

证据目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/texture_transfer_20261027/`。
下称 V；前轮 `source_arrivals_20261027/` 下称 S。
所有 GPU 用例通过 `run_godot_background.py` 在私有桌面运行，普通优先级，无 QoS 修改。
engine09 SHA256 为 `40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`。

## 已取得的调用和资源证据

S/map15_service 的冻结主线程栈已在前文存档：MaterialPublication → SurfaceMaterials
→ ImageTexture.create_from_image → RenderingDevice._acquire_transfer_worker → VMA
AllocateVulkanMemory → AMD/Vulkan → CPU 同步等待。现场传输22369728字节，扩容32MiB
CPU staging buffer；这是实际调用位置，不是把35.663ms心跳间隔全部归入分配。

本轮用既有 LoadTrace 获取实际上传路径。V/map02_trace 完整执行到 failures=[]、
AXEL_PIPELINE_FINISHED failures=0，trace dropped=0；但外部脚本随后用系统GBK读取UTF8
JSON失败，wrapper exit1，未保存引擎原始退出码。保留原始日志、约112MB报告和
map02_trace.recovered.json，**不列为正常性能样本，也不补造engine_exit0**。
后续runner显式UTF8并先保存exit.json，避免解析失败丢失退出证据。

该trace中最大像素上传为默认包material_textures下
`48b49d98ebaba41dcfdf73feeb3f9efd8e423b56d8cba012850ca545418acbb6.png`：
DirectX normal翻转、2048×2048、RGBA8、完整mip链22369620字节。
与前轮GDB传输大小属于同一数据规模，但不能据此证明是同一次/同一纹理调用。
该次实际upload5.304ms，未重现35ms等待。对应未翻转DXT1 sidecar不能冒充翻转后的
法线变体；未改写资源或用错误方向/格式代替它。

本地引擎源码 rendering_server_default.h:147/214 的 FUNCRIDTEX1 在支持异步创建的
RD渲染器上直接创建资源；没有修改公共材质或节点。rendering_device.cpp:7373 的
draw提交仍可能等待transfer worker。因此验证包含真实绘制与回收，不能只报告
create_from_image从主线程消失。

## 独立固定工作压测

`tools/stress_texture_transfer.gd` 使用上述真实解码像素，64次上传，每次22369620字节，
总1431655680字节。后台最多两个in-flight/ready纹理，再加实际显示和首个readback
owner；不是无界排队。只预热2×2相同材质/几何，首个全尺寸staging扩容仍计时。
每次提交到实际QuadMesh，末个完成draw后结束计时；首尾GPU readback比较全部mip
像素，检查输入Image及原PNG未变。readback在上传计时之外，回收阶段重新设时间起点。
这是固定GPU工作压测，**不是地图加载、实际VRAM测量或原长帧完全复现**。

| fixture06 | 主线程工作累计ms | 主线程单次max ms | 上传及绘制墙时ms | 上传阶段帧max ms | 回收阶段帧max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| A1 主线程 | 273.685 | 10.364 | 452.318 | 13.191 | 76.630 |
| B1 一个worker | 6.330 | 0.353 | 393.511 | 9.249 | 18.909 |
| B2 一个worker | 11.707 | 0.425 | 453.572 | 10.731 | 59.245 |
| A2 主线程 | 310.093 | 10.068 | 494.011 | 14.944 | 58.316 |

四次均exit0/failures0/errors=[]、源码/地图未变、相同64次上传；上传阶段0帧>50ms。
后台组主线程工作下降明确；总墙时有重叠，且B2回收仍有59.245ms，**未声称回收解决**。
首个fixture04有逐次打印和readback跨阶段计时问题，不与fixture06混比；fixture05
因WeakRef类型推断warning-as-error未解析，修正后重跑，保留失败文件。

## 候选实现与去重修复

- `SharedPrefabImages.background_upload_enabled` 默认false；仅支持RenderingDevice时
  在既有像素producer中创建纹理，不增worker、队列或预算。行状态pending→uploading
  →ready；Image与Texture是显式字段。驱动调用在pool mutex外，取回时重查owner及取消。
- 现有唯一输出预约覆盖Image+Texture像素负载，生产者workspace继续覆盖解码和staging，
  join前不归还；这是保守负载记账，非显存/驱动内部分配上限。取消旧worker仍保留workspace，
  新owner只在重新准入后接管；旧结果不能覆盖新结果。销毁Image/Texture在pool锁外。
- 主线程接受结果后取得明确的uploaded_textures字典。Prefab作用域借用它，Paint仍走
  原来源失效、材质缓存和LRU协议，但直接绑定同一个已上传对象；结束恢复旧作用域。
  后台实际upload数/bytes在shared_pixels里，主线程handoff单独计数，不能把两者相加
  当重复上传，也不能仅看主线程upload_bytes下降宣称整体少传了数据。
- 同时发现 `Prefab.texture_tickets` 只查强缓存和若干材质容器，漏掉live场景拥有的
  weak textures。contract10_weak_repro以零热缓存复现该遗漏；改查retained_texture
  后contract12_fixed通过。这个修复避免再次安排已有纹理的解码/后台上传，默认生效。

## 合同测试与失败样本

`test_background_texture_upload.gd` 最终31条断言覆盖：两消费者共享两种真实变体，
仅上传两次；CPU/GPU字节一致；零热缓存直接绑定原对象；后台不写主线程缓存；未完成
producer不阻塞follower；取消并持有旧worker时新worker独立完成；旧结果不能覆盖；
重复publish不新增上传；同路径编辑不篡改旧可见纹理；最终GPU owner与预约全部释放。
contract12_fixed exit0/errors=[]。未用该测试冒称GDB单线程non-stop支持。

失败保留：contract07测试材质缺roughness，脚本错误后未退出；按PID+birth+exe验证
后只终止该owned进程，完整日志/停止原因保留。contract08的第三个consumer未将等待
follower从worker槽park，另有协程中WeakRef.get_ref临时强引用污染释放断言；修正测试
记账与隔离helper后重测，不宣称生产泄漏修复。contract09诊断说明临时引用问题，正式
断言以contract10/12为准。contract10仅“下次准入发现weak纹理”失败，修复后31/0。

既有CPU回归：shared_prefab_images32、prefab_texture_preparation63、parallel_chunk
preparation32通过。material_publication误用headless被拒绝，保留regress13失败后用
真实GPU重跑46条通过；prepared_material_publication64条通过。

shared_prefab_images旧GPU用例会原地改PNG，却没有打开可变源诊断策略，39条中2条
失败；测试入口显式verify_packages=true后39条全过，不改变生产信任资源包策略。
不能把原失败算成已证明由本轮生产改动引入。

编辑器预制件HTTP用例29条、地形HTTP用例26条通过，包含打开、保存、纹理替换、损坏
与修复、作者数据保持。损坏PNG阶段各有预期codec ERROR；预制件generic runner因
只识别PASS空格、拒绝所有ERROR而报失败，原result保留，补充review.json记录9条
明确PNG解码错误、0条其他错误、0条SCRIPT ERROR及最终FAILED=0。不是“日志无错误”。
地形用例regress17使用识别PASS冒号及明确PNG错误类型的runner通过。

## 实际地图对照

map18采用A/B/B/A，A关闭、B打开后台上传。两组均含weak复用修复，建筑提前到齐候选
维持false；shader/材质、地图、引擎、预算及原生门控相同。详细源码保存在map18_sources。
OS缓存不清空，不能叫严格冷盘。host原始记录按1Hz保存，不终止其他应用以制造空闲。
四条均exit0、failures=[]、errors=[]、源码/地图未变。汇总见abba20_summary.json和
abba20_peaks.json；1% low为最慢ceil(N×1%)帧的平均时长倒数，不是帧p95或加载p95。

| 样本 | entry s | 完整就绪 s | 返回1% low FPS | 重载1% low FPS | 卸载/返回/重载max ms |
| --- | ---: | ---: | ---: | ---: | --- |
| A1 | 5.626573 | 11.344000 | 43.079 | 37.491 | 32.290 / 39.246 / 37.776 |
| B1 | 4.052684 | 9.663463 | 43.431 | 30.488 | 38.888 / 40.479 / 40.647 |
| B2 | 4.069602 | 9.617548 | 43.570 | 30.953 | 36.822 / 35.850 / 43.877 |
| A2 | 3.944421 | 9.648629 | 42.154 | 32.540 | 35.526 / 36.467 / 41.002 |

三种移动阶段四条样本均0帧>50ms，但不覆盖首次3D/加载cover区间。
初始工作全相同：231 builds、3923 prepares、2724 packs、228 worker surfaces；
最终内容均229 groups、2564 sources、361 surfaces、live joins0。
首个真实绘制审计记录3943 GPU surfaces、3202 nonwhite、1502 textured、145 unique
textures；它不代表所有作者纹理或完整导入模型材料均已启用。

**上传工作量完全相同：每条全程170次、721332072字节。** A全部在主线程；B为主线程
24次/78294088字节，后台146次/643037984字节。无discarded uploads，最后shared
outputs/consumers/retained bytes均0。初始均85次/360666036字节（B后台61次）。
主线程upload累计A296.295/313.135ms，B53.826/53.002ms；B的146次handoff总计
0.994/1.006ms，单次max23/22us。后台upload累计280.663/276.029ms，这些是线程
墙时，不能与主线程耗时简单相加当CPU总工作或把重叠部分算进关键路径。

shared pool保守预约峰值A1/B1/A2为508819576字节、B2为531189304字节；未扩大预算，
到达时序仍可改变峰值。全路线builds/packs分别618/7361、590/6915、614/7263、
614/7153，prepare均7851；不能把完整移动中的构建差值直接称为稳定去重收益。

结论：**主线程上传压力下降有真实证据；总加载和重载low未通过默认启用门槛，候选仍
false。** 三条约9.6s并不证明稳定加载p95，首条11.344s仍保留。两条B的reload low都
低于两条A；draw_calls>=2000的观察时长A为2.158/2.633s，B为2.940/3.315s。
这提示工作时序/绘制压力仍需调查，不足以认定后台上传锁就是原因。

主机记录：A1/A2的reload都有其他Blender进程，B1/B2的reload未观测到；B1的加载有
Blender，A1/A2及整个B2未观测到相关进程。不能据此解释A1较慢入口，更不能以“无
外部竞争”作为完整OS/GPU空闲证明。B2同样low下降，不能只用其他任务把问题排除。
未新增引擎修改、优先级调整或缓存扩容。

最后仅补了background开关关闭时textures()直接返回空字典，避免默认CPU路径无谓
扫描所有绑定。该快路不在map18源码快照内，未将其算作实测收益。最终
contract21_final仍31/0/errors=[]；普通共享/并行回归见regress22_final。

## 尚未解决的边界

独立压测回收58–77ms仍需定位，不能因主线程上传变小而归类为OS空闲。前轮真实地图
55.678ms/bookkeeping45.679ms也未由本轮新纹理现场完成归因。首次实际材质绑定、
首个3D帧、旧native AV与road-paint门控继续单列；未恢复所有导入模型纹理，未宣称
完整游戏验收或总目标完成。

下一切片先给后台候选的reload下降补实际调用栈：对齐来源ready、批次开始/提交和
draw压力，使用已验证的owned冻结协议/GDB与既有LoadTrace定位30–44ms帧；不能仅因
main upload少了就默认开启，也不能仅凭CPU监控值把剩余帧定成驱动等待。优先查
RenderingDevice draw提交是否等后台transfer，以及像素worker占用是否延后几何就绪。
独立回收长帧另需在readback结束后的真正release区间复现并抓栈。

加载工作量的另一个已观察区间是A1全程prefab_pixels.final_sha_us累计1.031s，4112次
source identity命中、0次final SHA文件读取。这一阶段名字容易误导：代码实际仍逐路径
两次allowed()祖先检查和共享身份查询；尚未证明其关键路径占比或哪些检查可安全合并，
不能把累计worker墙时当可直接省下的1秒。后续应保留可变源/资源根语义，先独立复现
重复调用再优化，而非恢复GLB或额外校验资源包。
