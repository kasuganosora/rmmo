# 编辑器渲染热点静态复核（2026-10-07）

初始只读分析生产代码；后经主代理授权修复已证实的道路预览冗余重画并新增测试探针，未启动 GPU 场景，没有修改地图。Grok 初审使用本机 `C:/Users/luna/.grok/bin/agent.exe` 1.0.46，显式禁用工具、网络和子代理，输入为源码快照 `prompt.txt`；报告和退出状态将在结束后附记。以下数字来自独立解析，不依赖 Grok 推断。

## 1. 优先实验：冻结房屋的阴影材质面，而非再次扩大普通合批

`building_shadow_proxy.gd` 当前只由 `world_stream.gd` 的运行时两处接入；编辑器 `HousePrefab.visual` 没有调用。已有 gate 限定冻结 building、普通不透明材质、无变形和覆盖层等，将同一物件相同 cull 的材质面合并为派生 shadow-only 网格。作者几何、单件、门窗、碰撞不变。编辑器能否从此受益需实测，不把游戏收益推定为编辑器收益。

冻结 glTF 的原始导出节点 census（**未执行运行时合批/可见性/阴影剔除，不是 draw call**）显示，2000 个冻结 building 有 6415 材质面：fixture 1338 节点 / 3833 面，shell 245 / 1284，floor 340 / 1020，roof 77 / 278。里面 fixture 有 867 个 BLEND 面、shell 有 43 个 BLEND 面，不能全部走不透明代理。普通 box building 另有 230 节点 / 920 面。完整分布在 `export_geometry_census.json`，解析脚本 `geometry_census.py`，记录 UUID 和导入子 UUID 归属已核对。

新 `tools/profile_editor_town.gd --building-shadow-compare` 只在测试脚本给现有合格节点 attach 一次，记录 setup 耗时、合格数、实际 attach、按 fixture/floor/shell/roof 的源/代理面数，然后同视角同轨迹跑两轮 ABBA（原 / 代理 / 代理 / 原）；每段预热 90 帧，恢复原 cast_shadow 和代理可见性。强制收集 root/scene 渲染 CPU/GPU 和分别的 visible/shadow draw calls，原 overlay 保持。该模式排斥 frozen/minimap/overlay-only/motion 混合实验。可选 `--shadow-screenshots` 抓恢复相机后的图；环境仍推进，因此只是画面审查辅助，不是确定性逐像素验收。真正画质验收应冻结同天气时钟、阳光、曝光后拍摄。

推荐排队运行：

```
python tools/run_godot_background.py --timeout 600 --log D:/code/rmmo_runtime/review_artifacts/editor_shadow_compare_20261007.log -- D:/tools/godot/Godot_v4.7.2-stable_win64.exe --path D:/code/rmmo --script res://tools/profile_editor_town.gd -- D:/code/rmmo_runtime/review_artifacts/editor_shadow_compare_20261007.json --source=D:/code/rmmo_runtime/cache/world3d/bridge_perf_20261006/map.gltf --view=overview --samples=180 --building-shadow-compare
```

先确认 shadow draw 稳定下降以及 scene CPU/全帧 ABBA 是否同向，才投入生产接入。若收益有限，停止原型；不要因为 surface 计数下降就宣布完成。

生产接入风险：必须在 `authoring_view.decorate` 后判断 dim（transparency=.85）的拒绝，不能给半透明楼层留下不透明影子。后来材质覆盖/paint/节点替换、隐藏恢复、楼层重建、选中释放和 undo 必须同步清理/重建代理。代理带 `stream_instance` 元数据，仍需核对编辑器 picking、bounds、保存遍历确实排除；本探针在编辑器已经构建完之后 attach，避免把代理误加入选取形状，但这不代替生产验收。

## 2. 道路 overlay：一个可确认的多余重画分支

`city_overlay._process` 当前 `view_key != _view_key or preview or _had_preview` 分支同时请求主层、前景和透视道路层重画。因此静止相机下，只要建筑/散布/水道/城防 overlay_plan 存在，正式道路会每帧重投影提交；正式道路数据未变。`_roads_need_redraw` 已在真实道路缓存刷新和投影键变化时置脏。可将该分支的道路 dirty 限于相机视图变化，主层和前景继续跟随 preview。需要验证真实道路数据编辑、undo、隐藏/锁定、投影切换及结束预览都仍刷新。

这只解决静止镜头的放置预览无效工作；相机真正移动时透视屏幕路径必须变化，所以不能将其当作约 28ms 桥头移动已经修好。既有道路隐藏对照约 6.209ms 支持继续针对道路绘图提交归因。不能直接关掉道路提示、降低显式曲线采样或改透明顺序来达标。主代理已收到具体行号，未改此生产文件。

## 排除草作为全城俯视首要方案

完整 26 个导入 GLB 的 JSON chunk 已只读检查，867 实例；750 草位于 14 个路径。它们全是三层 LOD，近 0–12m、中 12–25m 带子节点 foliage 风，远 25–55m 无风；材质全 MASK。记录 wind_response 缺省不代表模型静态。全城 overview 的正交相机在 y>=10000 (`city_tools.gd:79`)，这些草应已被距离范围剔除，因此不能以草数量解释俯视约 9000 draw。

16m 空间桶中前三种 arch 草 630 实例聚成 49 桶，但这仅是实例化字典上界。普通 MultiMesh 会将 authored 每实例 AABB 距离切换改成组级；开启风后存在独立材质与 shelter/exposure，旋转缩放参与局部弯曲；需精确保留每实例 LOD、材质、风、选择和碰撞。既没有当前视角的 visible census，也没有全帧收益证据，因此本轮不投入实现。`asset_census.json` 保存逐资产节点、材质、风、LOD、碰撞和空间分组事实。

## Grok 输出复核与本轮后续修改

Grok 本次退出码 0，完整答复在 `report.txt`，stderr 为空。它正确指出 PackedScene 的潜在共享、GLB 自带风不被缺省 record 清除、逐实例 exposure、透明混合、整格 AABB/LOD 与选择保存边界。但它没有 GLB census 和 overview 相机资料，仍把草作为俯视第一候选；现已用真实 55m 范围和 10000m 相机反证这一优先级。报告把所有草是否 MASK/是否有风留作假设，实际已确定：均 MASK，近/中层有风。它猜测旧合批 draw 上升因 AABB 或失去复用，没有实测证据，不采用。它所提“格边长落在 1m margin 可接受误差内”仍是未经授权的视觉误差折衷，不能自动采纳。源隐藏是否影响碰撞需具体看 CollisionObject，不能笼统声称 visible=false 会关闭碰撞。

主代理随后授权修复第2项确定冗余。本代理仅修改 `city_overlay._process` 分支，以 `view_changed` 控制透视道路重画，保留原道路 cache 置脏。`tools/test_editor_overlay_cache.gd` 新增静止透视预览保留道路命令、主/前景继续绘制、HTTP镜头/道路/undo继续失效、结束预览仍复用共6条断言。预览 fixture 使用实际画布的 transient pending 数据；HTTP用例保留真实 loopback 服务、保存重开、wind toggle。没有新增编辑能力或 schema，UI/MCP 共用原业务行为。

`profile_editor_town.gd` 和扩展回归脚本均 headless `--check-only` 退出0，`git diff --check` 无错误（仅已有换行规范提示）。当前完整GPU/HTTP运行由主代理排队，尚不将新断言写为通过。本轮不修改其他投影算法和生产阴影代理接入。


## 受限编辑器阴影候选（默认关闭，等待复测）

主代理完整复核 overview ABBA 后确认不能声称稳定全帧收益：一段 original 快至 28.436ms / scene CPU11.468ms，其余 original 35.56–37.18ms / 17.946–18.317ms，proxy34.76–36.266ms /16.464–16.766ms。阴影调用2566→1866稳定下降只支持继续受限候选，不能直接默认启用。

新 `scripts/world_editor/building_shadow_preview.gd` 的 `enabled=false`。通过 `authoring_view.decorate` 在楼层hide/dim处理后尝试挂接；除原运行时 gate 外，只接 `prefab_locked` 冻结building，拒绝任何wind配置/receiver、自定义instance override、overlay及透明度。没有逐帧process。源resource.changed信号使用静态回调+WeakRef，不让资源回调强引用scene node；退出/删除/失效时断开，失效立即恢复原shadow模式并移出代理，延迟释放正在执行回调的monitor。

编辑器选中路径已核对：`world_editor._refresh_selection` 新建独立 `_selection_box`，不修改源的material_overlay/透明度。building_panel的透明预览在独立ghost子树，不经decorate；楼层dim先设透明度再拒绝代理。冻结预制件的paint/wind修改由现有共享业务提前拒绝。湿润扫描只接受单面mesh，原多面building不在范围；新增专用marker排除派生单面影子，避免把它误当湿润表面。SurfaceMaterials.meshes和editor._picking_node_enabled也剪掉专用代理子树。

作者保存由save_job另建export_root并按record生成，helper只在编辑器decorate使用，保存不复制编辑器源节点及其cast_shadow/child。没有改shared runtime proxy、地图格式或MCP schema。

新 `tools/test_editor_building_shadow.gd` 覆盖真实HTTP生成、selection、move/undo/redo、floor hide/dim、风开关、save/reopen、delete/undo、代理拾取与目录排除，以及resource.changed立即回退和listener清理。GPU时固定天气process并保存同相机original/proxy图片及差分计数供主代理目视审查；不以无依据的像素阈值替代画质验收。当前此新测试尚未执行，交由主代理串行调度。`git diff --check`无错误，只有既有CRLF提示。

### Directional normal bias 复核

已查本机精确 Godot commit `ed1daf0bf001b61586d9930840f2f1394092c079` 的[官方 Forward+ shader](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl#L2145)：方向光 normal bias 在接收表面的 fragment 光照阶段使用 geo_normal；shadow depth 的 vertex 路径不据投影物体的顶点法线作该偏移。由此本 renderer 中代理缺少normal不改变方向光此项bias，原可见mesh与接收法线保留；不能扩大为所有renderer/灯类型的无条件画质证明。

旧游戏 `shadow_partitions_visual_metrics_20261006.json` 六对图片通道最大差0–3，pixels_over_3均0。独立查看0_day original/proxy：近处檐口贴合、门口台阶、路面投影边界未见变化。新编辑器图片仍需本轮实际结果审查。

候选首次完整GPU回归中，MCP生成/选择/移动/撤销/楼层/保存重开执行到位，但不能计为通过：发现静态bound Callable连接被去重（多个共享资源节点出现 already connected），随后测试的普通Array传入Array[String]失败。修为独立只捕获WeakRef的闭包，两处refresh_ids显式Array[String]。增加 `test_editor_shadow_listeners.gd` 专测同材质双实例独立监听、全体失效和删除解绑，复跑待主代理执行。

首次本轮两张截图实际0字节差，但目视相机侧几乎没有清晰的地面投影边界，因此没有当作充分的阴影画质验收。新视觉fixture明确固定方向光使影子朝相机，并验证shadow draws>0，后续检查檐口贴合及地面投影边缘。

### 最新复跑与独立终审

主代理串行执行 `test_editor_shadow_listeners.gd`：6 PASS；完整后台GPU+真实HTTP `editor_building_shadow_20261007_retry.log` 退出0，`EDITOR_BUILDING_SHADOW_FINISHED failures=0`，没有ERROR/FAIL。复跑覆盖material/mesh资源变化、删除解绑等之前未完成的末段。新的original/proxy图位于 `D:/code/rmmo_runtime/cache/world3d/editor_shadow_19796_9349284/`；2,730,756通道中293通道相差1/255，最大差1。本代理也独立查看两张全图：朝向相机的地面投影边缘、屋檐沿墙贴合、屋脊遮挡未见变化。

最终代码审查未发现现有已暴露编辑操作会绕过该合同：选中使用独立线框；楼层dim/hide和properties改动会重建/装饰；移动只改父变换；固定预制件paint/wind拒绝；保存新建作者树；proxy没有owner、没有作者UUID，且picking/材质枚举/湿润扫描显式排除。信号闭包只持有WeakRef，资源不能通过闭包强引用监视节点。没有新增常驻扫描。任意第三方代码直接替换MeshInstance3D.material_overlay/transparency/mesh属性并不是受支持的编辑业务；这些Node属性不发resource.changed，未来若新增此类业务必须同步restore/redecorate，不能把当前稳定合同擅自扩大。

收益结论仍待主代理的受限合同240帧ABBA：默认关闭保留，正确性通过不等于性能任务已完成。
