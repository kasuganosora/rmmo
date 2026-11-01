# Axel 夜晚灯光与星空检查（2026-11-01）

本轮按用户最新指令收敛为夜晚灯光、星空检查及必要修复；完成后暂停性能目标。SceneState 计数缓存、乱序装箱前缀和批次视觉拆分三个外部候选保留，未混入本轮。`P` 为 `D:/code/rmmo_runtime/review_artifacts/axel_post_roads_perf_20261030_01`。

## 固定输入与证据边界

- 地图仍是 `P/map_snapshot/map.gltf`，SHA `ee80500d6156c79d68a04315931c024319d92fb351567e5ced38d0ddb7c22697`。HUD、玩家、物理和普通游戏系统保持开启；临时摄影机只在原摄影机位置改变朝向，未移动角色、改变流送需求或修改地图。
- 显式使用外部 Godot 4.8 candidate58，SHA `f36fb4f64d48072c3ece6d416ff10dc619104bd512aecc0f4802d4b432de8d6d`，项目 secondary draw lists=4、无环境覆盖。它尚未替换默认 candidate10，也不代表此前尚未完成的卸载/编辑器/默认引擎发布验收已通过。
- 夜景相关生产文件固定于已提交代码；两灯控制器显式覆盖冻结工程中的其他会话 stained-glass 注册 WIP。其他会话的室内反射和彩窗投影新增功能不在本轮资格范围。冻结工程不是宣称整树等于某次 git commit：保存完整源 SHA，并逐文件恢复 overlay 前的原字节。
- 使用既有 shader/Vulkan cache seed，非严格冷启动。两段夜景各观察约30秒，夜街景和仰视天空分别统计；初始日间窗口30秒。截图在计时后仅隐藏玩家渲染模型，实际有损 WebP quality90，然后恢复。
- 1% low 为最慢 `ceil(N×1%)` 帧耗时的均值取倒数，不是 `1000/p99`；采集的是 process-frame 间隔。原生渲染 scope 是 CPU 墙钟；viewport GPU 时间为最新完成结果，精确结果源帧未绑定到 GDScript，不假称同帧对应。

## 已复现并修复

### 灯光最终状态只提交变化

`StreetlampLights` 原来每0.2秒先将全部模型灯关闭，再打开排名前6个；每次都写位置及入选灯阴影属性。`HouseCandleLights` 每0.25秒同样先关闭再开启前2灯，并重写静态火焰节点位置。4.8 源码确认同值阴影 setter 仍更新 light version/依赖；同值 Node3D 位置也会传播变换。

改为计算完原有距离、楼层及遮挡排名后，一次提交最终可见状态；位置、阴影仅在实际变化时提交。没有增加缓存、降低灯数、缩短范围、改变亮度、删阴影或延迟释放。失去资格、跌出排名、源隐藏和退役仍在同次刷新关闭；重新入选恢复正确阴影。保留 live 文件中其他会话的注册行，只提交本轮窄 patch。

独立真实引擎红/绿用例 `tools/test_night_light_state.gd`：plain red 35通过/4个预期工作失败，counted red 35通过/7个预期失败；无脚本/引擎错误。正式候选39/39、外部实际 setter 计数候选42/42，合计81项通过。连续3次稳态刷新：

| 实际工作 | 原逻辑 | 修复后 |
|---|---:|---:|
| 模型灯 native transform notification |24|0|
| 模型灯 visibility_changed |36|0|
| 模型灯 shadow setter |18|0|
| 烛灯 native transform notification |12|0|
| 烛灯 visibility_changed |12|0|

真实移动仍触发通知；昼夜、排名、阴影重入、源隐藏/queue_free、显式释放、真实物理遮挡和楼层选择均通过。火焰 mesh、颜色、能量和范围身份保持。证据 `P/night_lights62_setup/validation_receipt.json` 及四个 red/green 输出目录。headless 工作量证明不是整图毫秒收益。

### 月面噪声只在有贡献的像素计算

原 `weather_sky.gdshader` 在整片天空都执行月面 fbm，随后才乘几乎处处为0的月面 mask。候选仅将 maria/fbm、lunar shade 和累加放到 `moon>0 && night_amount!=0` 内；fwidth 和月面边缘继续在统一控制流计算，没有阈值裁边，微小非零夜晚权重保留。

`tools/test_lunar_maria62_gpu.gd` 使用实际星场/cloud include 和真实噪声资源，以固定时间、机位、曝光做一次原版→候选验证。104项检查通过；8组昼夜、月面、极轴、云层/回退、微弱夜晚权重画面逐字节相同，最大通道差0。1920×1080全屏天空各360帧的官方 GPU 计时：夜空无月视野均值0.39875→0.36238ms；白天无月贡献0.19113→0.13416ms。完整波动、编译/预热及原图保留，不能把短时组件数字当地图low提升。证据 `P/lunar62_component01/pixel_and_gpu_comparison.json` 和 `P/lunar_maria62_setup/qualification.md`。

## 原始夜景时间线

`night61_01` 在上述修改前的固定生产源上，仅插入7个同步天气/灯光 scope。实际切夜走生产 `_request_environment`；World、Weather和权威星空快照一致，实际星空 uniform 开启。22个模型灯注册、2灯启用并在街景画面可见；76个烛灯注册但室外机位无启用烛灯，不宣称复测了房屋室内。星空图真实覆盖天空。manual preset 下 celestial_cycle=false、moon energy=0且阴影关闭，太阳能量约0.16并保留作者阴影。

| 阶段 | 1% low FPS | 最大帧ms | >50ms帧 |
|---|---:|---:|---:|
| 初始日间steady |37.031|39.852|0|
| 夜晚街景 |29.355|41.277|0|
| 仰视星空 |49.330|28.474|0|

夜街景 viewport GPU 中位2.719ms、p95 3.264ms、max4.013ms；Weather process最大2.007ms、灯refresh最大1.231ms。单次读取CSV归因显示街景主要仍是 `render.draw_list` 和 `main.scene_process`，不能把全部耗时归为星空/GPU。最大41.277ms观察区间包括 scene_process独占15.710ms、draw_list8.817ms等；不是一个41ms星空或灯光函数。嵌套 inclusive 不相加。

首个 `night_transition` 330.267ms区间中，302.136ms发生在native header.start之前，之后28.131ms；实际生产切夜call1.543ms/native scope1.546ms。采集启动确实在header.start前分配并预触碰448MiB事件存储，但未记录 start 的调用入口，前段还含前帧尾部/状态审计，不能将302.136ms精确全归因分配，也不能冒称生产切夜卡330ms。原帧完整保留，证据 `P/night61_transition_audit/`。

引擎exit0、功能failures=[]、日志错误0；原生事件5,355,811，丢失/注册丢失、orphan、crossing、task冲突均0，导出完成。外层runner最后的严格30秒断言失败：SceneTreeTimer协议实际night29.999347秒、sky29.996926秒，分别短0.653/3.074ms。原始失败不改写、不重跑挑样本。最终正常宿主改为绝对ticks deadline，保持严格>=30秒，可能多一帧。

## 外部负载与后续边界

此前仅记录其他Godot/Blender/编译器，无法排除普通程序负载。本轮补单观察线程、约1秒采样的每核CPU、系统内存、每盘IO、Process V2按PID CPU、WDDM每PID/engine占用；内存记录在进程结束后落盘，不逐帧写文件，不读取所有进程cmdline。每次采样自耗时也保存。PDH ABI和已知CPU负载实测通过；相同EXE实例以PID区分，GPU不同engine不乱相加为总占用。接口依据见 `P/night_host_load61_validation.json` 的微软官方链接。

首样本确有浏览器/系统服务/桌面程序CPU及视频引擎活动；夜街景最大外部3D单实例约1.24%，视频引擎约18.88%。这些约1秒平均值可保留负载背景，不能据此证明某个20–40ms帧的原因，更不能追溯证明59样本的退步来自外部负载。所有慢样本保留。

## 累计正常路径结果与暂停点

`night61_plain01` 仅纳入以上三个生产文件，移除7个方法探针，不启动native capture、viewport GPU测时或sky_details；保持原被动帧/runtime记录和外部HostLoad。两段实际时长30.002504秒/30.003938秒。GPU运行在不激活的独立桌面；正式源、地图、摄影机和头像恢复检查通过，游戏assertions=[]、引擎exit0、错误0。两张计时后q90图已实际查看，灯光照亮门口/路面、星空确实入镜。

| 累计正常路径阶段 | 1% low FPS | p95 ms | 最大帧ms | >50ms帧 |
|---|---:|---:|---:|---:|
| 初始日间steady |24.317|29.663|48.706|0|
| 切夜过渡 |30.864|26.787|33.362|0|
| 夜晚街景 |30.111|24.431|44.002|0|
| 仰视星空 |56.690|10.551|33.769|0|

生产切夜同步调用2.158ms。entry12.840360秒、完整需求区域就绪62.794372秒；这些加载数据保留，不据此声称本轮解决了加载。诊断前后采集开关不同、外部负载也不同，不计算两样本的整图优化百分比。

原runner的隔离条件**失败并保留**：启动前无其他负载，但运行中另一内容任务启动 `blender.exe` PID27380；76条快照记录host约57.454–100.985秒重叠，主要在加载和初始日间窗口。该进程不在后续夜晚稳态记录中。夜稳态仍有桌面/浏览器CPU活动，因此既不能把整轮称为干净对照，也不能用Blender解释全部夜间低帧。原receipt仍是 `failed_or_incomplete / AssertionError([27380])`；额外只读 `post_run_functional_audit.json` 补核runner未执行到的功能检查，没有改写原状态。

**夜街景35 FPS目标仍未通过，不能宣称全部low问题已解决。** 当前确认的灯光重复提交和全屏无效月面计算已修复；本轮未出现夜景>50ms尖峰。后续如恢复性能专项，应依据已保存的 `render.draw_list` / `main.scene_process` 时间线继续定位普通场景与提交成本，并保留外部负载记录，不将剩余成本直接归咎于星空、GPU或外部程序。本轮按用户要求暂停，不继续扩展到普通场景处理、加载、回收，也不因此重跑对照挑更快样本。

完整证据：`P/night61_01/`（原始CSV及`native_analysis`）、`P/night61_plain01/`（正常路径、负载及失败边界），以及两个setup目录的源字节、SHA、runner、覆盖与恢复清单。原有候选分别保留在 `P/scene_count61_setup`、`P/batch_arrival61_candidate01_setup`、`P/batch_close61_setup`，资格状态各自独立，未作为本轮交付。
