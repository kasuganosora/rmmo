# 同步材质发布作用域去重（2026-10-27）

接续 §175 / `8304ebb7`。当前分支 `codex/latest-map-runtime-review`，完整加载仍按
地图加载开始到当前需求完整就绪计算。没有更改预算、worker 数量、画面范围、首帧
与完整就绪条件。地图/prefab 纹理启用，导入模型仍为无材质 native。

证据目录（下文 Z）：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/material_publication_scope_20261027/`
仍为 engine09，EXE SHA
`40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`。
没有修改引擎、GPU资源格式、美术资源或系统设置。

## 重复调用及修复

上轮官方 `origin_official15` 显示入口后 tickets_valid 4413 次、scope_current
2923 次。代码确认：`MaterialPublication.step_prepared` 已在同步作用域里完成
代际检查和准备；返回 READY、没有发生让出或外部回调后，scheduler 又调用
`House.publish_prepared`，再次进入、检查并恢复同一个作用域。

新增 `MaterialPublication.step_and_publish_prepared`，在同一同步调用内完成最后
一步准备及几何发布。返回 READY 表示发布已完成；PROGRESS 仍只完成一个纹理上传
或一个完整材质，并关闭作用域。FAILED、正常返回、嵌套调用均恢复此前 CPU images
与 uploaded textures 的确切 owner。作用域不逃逸到scheduler，也没有跨帧保存
“已验证许可”或新增全局缓存。

旧 `step_prepared` 与新方法复用 `_step_prepared_in_scope`；它在安装来源代际之后
才检查现有 prefab，避免失效前的 cache hit 误跳过新材质。新的同步 READY 分支
直接调用相同 `_publish_prepared`。后续实例准备、原子建筑发布、碰撞登记和回收
协议不变；scheduler 仅跳过已经完成的第二次发布。

没有移除跨帧/交接的 resident ticket 检查，没有改资源替换与失败重试规则。
纹理为空、未启用分片或未满足准备合同的路径继续走原发布入口。
`--separate-material-publication` 可选择旧的两次作用域路径；launch与report均记录
实际开关。`combined_material_publications` 统计真正完成的合并发布次数。

## 先复现，再做独立回归

先仅将既有GPU测试的作用域次数合同改为“一次同步最终发布不重复进入”。旧生产
源码的 `unit01_before` 退出1，62条通过、2条预期失败：原来五个scheduler turn
共进入六次scope；随后单独调用最终发布又进入一次。没有引擎或脚本错误。

修复后 `unit02_after` 75条通过；进一步把零预算回归也接到合并入口后，最终
`unit03`：prepared_material_publication **76**、material_publication **46**、
shared_prefab_images GPU **39**、deferred_ready_progress CPU **16** 条全部通过。
退出均0，errors为空，测量生产源码及各测试SHA前后不变。

覆盖实际GPU像素及所有mip、法线翻转、alpha、重复slot的Texture身份、零热缓存预算、
中途取消和配额回收、跨帧来源替换、清空热/弱catalogue后仍能区分材质代际、resident
失效、最终几何发布失败、失败后的有效重试，以及两个外层handoff字典的精确恢复。
只生成外部临时PNG和测试资源，没有修改用户地图。

独立审查指出函数级失败测试没有验证调度器收尾，补充 `unit12_scheduler`（最终
**86** 条通过）：通过保留合法 SHA 和 mesh/face 数量、将测试包的 entries 置空，
让材料完整切片后在最终几何 restore 返回空。先 staging 的健康组件和最后失败组件
一起标错并清除 staging，正常服务循环回收原 packet 和租约；调用 retry_failed、
注入重新准备的有效包后，两组件重新构建并原子发布、租约释放。断言记录 5 个
材质单元、一次 scope 初始化及 4 次复用，确保到达最终分支。`unit11` 的一条断言
曾错误地要求原始错误文本保持不变；实际 `_stage_building` 对整个组重写错误文本，
故该断言失败并保留日志，不是引擎崩溃。修正为验证实际材料和作用域状态。

新增固定1000次已准备prefab发布ABBA，旧路径仍执行真实step_prepared+publish_prepared，
新路径执行合并入口。每条输出Mesh/Material owner完全一致，旧scope entries2000、
新1000。unit02的墙时为旧152.705/168.898ms、新79.359/93.684ms；最终unit03为
旧122.542/128.538ms、新65.216/66.911ms；补充调度器回归的 unit12 为旧
158.010/164.479ms、新79.539/75.292ms，原始数值保存在日志
`MATERIAL_SCOPE_TRANSACTION` 行。微测收益不可直接相加为
地图加载加速，也不代表所有材质检查都可删除。

## 真实地图与官方复查

map04 ABBA：A开启separate旧路径，B开启combined；两组都保留§175几何面复用，
后台GPU上传与完整建筑提前通知候选关闭，既有退出重整去重开启。新进程、私有桌面、
普通优先级，无GDB、官方profiler或timeline，不清OS缓存，不能称为严格冷IO。
运行期间用户机器仍可有其他工作，不以进程存在直接归因。两组计时与就绪边界相同。

普通引擎四次样本（单位秒、FPS及毫秒；1% low 数值越高越好）：

| 样本 | 入口 | 完整就绪 | 返回 1% low | 重载 1% low | 卸载 / 返回 / 重载最大帧 |
| --- | ---: | ---: | ---: | ---: | --- |
| A1 旧 | 4.085 | 10.329 | 37.772 | 35.277 | 29.192 / 38.299 / 40.454 |
| B1 新 | 4.226 | 10.601 | 40.161 | 31.474 | 34.465 / 41.533 / 42.909 |
| B2 新 | 4.108 | 10.179 | 32.949 | 35.219 | 40.006 / **67.605** / 35.497 |
| A2 旧 | 4.121 | 10.403 | 36.320 | 37.130 | 44.283 / 40.104 / 38.394 |

除 B2 返回 1 帧外，各表列阶段均无超过 50ms 的帧。所有功能检查通过，
源码和地图 SHA 不变；`verification06.json` 留存 796 个源码文件快照。四次完整就绪
均超过 10 秒、1% low 高低交错，因此**尚无稳定整图收益**；也不能由四次样本计算
可靠 p95。运行时检测到其他 Blender 进程，且测试时有外部结果分析工作，不能将
这些现象直接认作原因；这些样本不作为完全空闲机器上的纯净 ABBA。初始阶段四次
均为 231 builds / 3923 prepared / 2724 packs、229 groups / 2564 sources / 361
surfaces。路径终点的动态 build/pack 数在运行间变化，不能当成同工作量微测。

B2 的 67.605ms 返回帧中，observer 回调自身测得 13.067ms，之后的 stage 分解显示
`bookkeeping_us=35019`、`publication_us=0`，bookkeeping 包含需求刷新、资源准备
检查等；Godot `process_ms=41.294` 是约每秒更新的滚动指标，并非该帧线程 CPU。
不能把整帧归为测试开销、系统空闲，或认定是材质发布造成；该帧未获得原生栈。
保留此慢样本，后续继续用时间戳及栈确认账务阶段内部原因。该帧前后约 520ms
的低频快照中累计 13 次需求刷新、输入 33740 行，且最大刷新墙时从 29.160 增至
34.186ms；快照覆盖多帧，不能证明这次最大刷新属于该帧。

`return09` 在返回期从 observer-end 开始监听 25ms，使用受控私有进程/GDB、无
优先级改动；引擎与 GDB 退出 0、资源释放和地图/source checks 通过，但未触发、
`trigger={}`、`freeze_valid=false`，所以**没有栈**，也不能用该诊断证明长帧已消失。
这是插桩运行，不进入普通性能统计。

官方 profiler 使用不同进程和插桩，仅比较调用量，不将其累计耗时当普通运行性能：
旧 `origin_official15` → 新 `origin_official07` 中 `begin_texture_publication`
**2950 → 2219**，`_texture_scope_current` **2923 → 2192**，`tickets_valid`
**4413 → 3652**。两次 `_publish_prepared` 均为 **748**，`WorldDocument._mesh`
均为 **1135**；旧 `publish_prepared` 748 次，新为 27 次（其他入口保留）。新方法
调用 817 次，含切片续跑。两次官方采样有插桩和调度波动，差值不是严格同路径
墙时收益；`prefab_pixels.publish` 的计时起点在新旧实现不同，不能直接比较。
新官方进程、接收和解码退出均为 0，errors/failures 空，源码地图未变。
完整表见 `official08_comparison.json`、普通样本见 `analysis05_summary.json`、
`transactions08_summary.json` 与原始日志。

## 下一条关键路径

代码另确认 `PrefabSpecPreparation.supports` 仍强制 white_materials 和
discard_map_textures。于是纹理模式下，即使 prefab 几何/材质已经发布且无 surface
paint，仍经 `WorldDocument._mesh → House.visual → InstanceSpecPreparation` 创建、
遍历、读取再销毁临时MeshInstance3D。已有direct字段投影与geometry binding未被使用。

下一轮先用真实节点输出逐字段、逐owner对照纹理模式，覆盖透明/法线/多slot、fixture
姿态、碰撞、楼层元数据及失效边界。特别保留可信不可变包条件：普通编辑/严格路径
仍有texture_error语义，不能只删white开关就绕过它。若证明等价，再复用直接描述，
把只依赖record和bounds的字段准备接到既有后台任务，并计入原任务预算；主线程只绑定
最终canonical几何/材质。暂未实施或宣称该项收益。

约500ms一次的queue快照只能说明观测瞬间worker状态，不足以证明worker持续空闲
500ms。不能从一个active_workers=0样本直接认定生产队列再次阻塞或扩大队列。
目标仍active；首次真实材质提交、首次3D呈现、独立纹理释放与旧无栈AV边界仍保留。
