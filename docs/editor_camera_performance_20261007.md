# 编辑器镜头移动与俯视计时（2026-10-07）

本项仍未完成。新的分项计时确认：透视移动时道路叠加层每帧重新投影并提交绘图；正交平移已正确复用道路绘图命令，但保留命令的渲染开销仍存在。不能把旧 `overlay_draw_ms` 的 2–3 ms 当作全部道路开销；该旧字段只计主 `_draw`，而道路、前景及小地图是独立回调，未重画时还保留旧值。

后续 subagent 调用 Grok 初审（exit 0）并独立复核，未发现可直接删除的大项。再次 Packed 批乘齐次投影仅保留为未测小候选；按颜色合并折线会改变透明交叠顺序与 AA 接缝，未采用。完整分析及对 Grok 推断的纠正在 `review_artifacts/road_draw_review_20261007/review.md`，不将 headless 子项比例外推为 GPU 场景归因。

`city_overlay` 新增默认关闭的累计 CPU/调用次数统计；`profile_editor_town.gd` 按帧取差值，分别记录 process、main、roads、foreground、minimap、marker。projection 是包含于 process/main 的子项，不重复计入合计。GPU测试采样至 frame_post_draw，使用实际 `move_camera`，对同一路径做正常、仅测试隐藏道路、仅测试隐藏全部叠加层的对照。粗粒度 Performance process/physics monitor 不用作逐帧归因。

两轮 GPU 矩阵均使用冻结 `bridge_perf_20261006/map.gltf`，源 SHA `95999c6c22d14a14d3187ea0df865db5fb3dcb52276b6c6ec3426559c74bc62d`，4372 记录、223 批次，测试前后源文件未变。每段 180 帧；相机移动时所有段批次 sync/rebuild 增量均为 0，没有发现镜头移动触发碰撞或合批重建的证据。

| 场景 | 原移动帧中位数 | 批量投影后 | 原道路回调 CPU | 批量投影后 |
|---|---:|---:|---:|---:|
| 出生点透视 | 27.505 ms | 25.468 ms | 9.944 ms | 9.061 ms |
| 桥头透视 | 28.607 ms | 31.166 ms | 11.819 ms | 10.450 ms |
| 全城正交 | 32.923 ms | 27.389 ms | 0（复用） | 0（复用） |

全帧结果存在波动：桥头没有稳定下降，正交隐藏道路对照反而从 24.296 ms 到 29.721 ms。因此只确认道路回调 CPU 的小幅降低，不宣称整体现已流畅或把正交变化归功于此。原矩阵桥头隐藏全部叠加层后同路线为 6.209 ms；正交为 20.637 ms，后者还有场景渲染成本。Canvas/渲染线程与 GPU 尚未单独计时，不将所有差值都称为 GPU 时间。

已实施的严格等价小改仅替换 `project` 内部：使用 PackedVector3Array 一次原生变换、预分配输出，并执行相同齐次投影和近裁剪。所有样本点、道路宽度、颜色、抗锯齿、节点语义均保留。`test_overlay_projection.gd` 的 4644 点、多相机姿态/偏移、正交/透视/frustum 与原运算逐点完全相同。原 HTTP 叠加层缓存回归 exit 0；独立桌面旧/新图片及分数正交平移均逐像素相同。

后续测试专用 `profile_editor_road_overlay.gd` 可拆 cull/project，配合 `--overlay-only --view=bridge --samples=30 --road-details`。该模式只读权威布局，不校验或构建整城记录；不会绕过生产加载校验。headless 初探 260 边、192 节点、4320 样本、36 区域：道路约 4.018 ms，其中 cull 0.569、project 1.104，其余约 2.35 ms。这是 dummy renderer，不能把原生提交成本当作实际 GPU 渲染成本；细分包装还引入时钟开销。将每边不变的裁剪余量移出六平面循环，仅省约 0.18 ms，尚未作为主要优化提交。无 controls 的道路本来就是两个端点，不能对显式 Bezier 道路任意降低采样。

初审使用本机 Grok agent.exe；人工复核否定了它将旧主绘制计时误称为道路计时、从而排除道路瓶颈的推断。原报告、筛选记录、逐项对照与日志在 `D:/code/rmmo_runtime/review_artifacts/grok_editor_camera_20261007/`；两轮全城报告为 `editor_camera_profile_20261007.json` 和 `editor_camera_packed_20261007.json`。既有地图、游戏风场和画质设置没有修改。

原生分辨率小地图 SubViewport 缓存仅保留为外部实验原型，生产代码已移除。全城正交对照中，小地图等残留叠加命令约增加 940 次 draw call，因此尝试把静态图缓存为原生像素纹理，marker 保持独立，并为缩放/非整数定位保留直接绘制。真实 GPU 像素验收确认缓存实际启用；默认混合出现 30,827 个像素变化，改为 premultiplied alpha 后仅剩 48 个边缘像素各相差 1/255 RGB（alpha 不变）。初次因自定零误差标准撤回，但用户要求是无可见质量损失；根代理目视对照未见变化，因此继续验证缩放/背景/marker与实际收益，不将 1 LSB 量化误差直接等同于可见损失。两轮日志为 `minicache_pixels.log`、`minicache_pixels_premult.log`，图片在测试 cache `overlay_cache_9147946`、`overlay_cache_9075421`。

补充视觉矩阵 `test_editor_minimap_texture.gd` / `minicache_visual_final.log` 已 exit 0，覆盖重叠矩形、透明背景、实色背景、半透明背景及尺寸改变。native 合成的 RGB 最大差为 2/255，alpha 最大差 1/255；目视无可见变化。1.25 倍变换、分数位置、窗口 content_scale 和手动关闭均确认直接回退，图片字节相同。marker 移动不重画缓存，真实 HTTP 改路/undo 更新缓存，隐藏恢复及点击定位均通过。最终图及 `minimap_visual.json` 在 `D:/code/rmmo_runtime/cache/world3d/overlay_cache_9232936/`。首次矩阵因测试数组类型赋值错误中止，未计为通过；已修复并加未完成即失败的保护。

同冻结整城的单点对照 `editor_minimap_overview_20261007.json` 保留实际 875 个示意矩形：同进程 direct → cached → direct-repeat、各 120 帧，中位数 34.604 → 32.085 → 31.240 ms，p95 为 42.148 → 40.552 → 40.307 ms。绘制调用 9043 → 8261 → 9043，明确减少 782 次，但重复原绘制更快，尚不能证明稳定全帧收益；该轮只预热 10 帧，后续 ABBA 探针改为 60 帧并可选择 render timestamp。源文件未变，223 批次无重复重建。因未证实值得承担生产复杂度，缓存已移出生产代码，外部候选保存于 review_artifacts/grok_editor_camera_20261007/minimap_texture_candidate.gd；测试脚本可显式传入重现。镜头 P0 仍未完成，不能将 draw call 减少等同于用户已感到流畅。


## 静止预览重复重画道路（2026-10-07 续）

已修复一个独立、可稳定复现的触发条件：透视相机静止时，只要道路待定点或建筑/城防/河道/散布预览存在，原 `_process` 就把正式道路层每帧设为 dirty。现在主层/前景继续更新预览，正式道路只在相机投影或道路数据变化时重画。道路显示、曲线采样、AA、绘制顺序没有改变。

真实独立桌面 `test_editor_overlay_cache.gd` 通过（`editor_overlay_cache_20261007_final.log`，exit 0）：新增静止预览保留正式道路命令、预览继续重画、HTTP 镜头移动/道路修改/撤销正确失效六项，同时原工具发现、非法调用无副作用、风预览、正交平移、移动、undo/redo、保存重开检查全部通过。

额外两轮 ABBA 使用冻结城镇原始道路网络（260 边、192 节点、4320 采样、36 区域），只构建叠加层、不构建 3D 城镇，以隔离此触发条件。每段预热 90 帧、采样 120 帧，桥头静止透视加两个实际待定点；测试专用 wrapper 重现旧道路重复失效，生产中不包含开关。旧模式道路回调中位 9.73–10.08 ms，新模式为 0 次重画；夹具帧中位 20.17–21.17 ms 降至 6.24–7.93 ms。两种模式绘制调用相同（2071），收益来自复用绘图命令；不能把此夹具帧时当作完整城镇 FPS。源文件 SHA 未变，报告 `D:/code/rmmo_runtime/review_artifacts/editor_static_preview_20261007.json`。

全城建筑阴影代理另作候选：同源图 overview 两轮 ABBA，1026 构件、阴影调用 2566→1866，场景 CPU 多数原路径约 17.95–18.32 ms，候选约 16.46–16.77 ms；但一个原路径段仅 11.47 ms、帧时 28.44 ms，不能宣称全帧收益稳定。尚在审查编辑器拾取/材质/隐藏/保存契约，当前测量只在探针手动附加，不等于生产交付。报告 `editor_shadow_compare_20261007.json`。


## 冻结建筑派生阴影：受限合同验收后默认启用

第二轮完整城镇测试采用实际编辑器接入，不再由探针无条件附加：仅 prefab_locked 的冻结建筑、无 wind/透明/材质覆盖的构件可用；透明玻璃、风动物件、可自由修改的网格保留原路径。只合并同一构件内相同剔除模式的阴影表面，每个源仍独立，三角形、孔洞及活动件父变换完整保留。无常驻轮询，mesh/material 的 changed 信号立即移除派生代理并恢复原投影，退出时断开弱引用监听。代理排除拾取、材质枚举、湿润扫描，保存从作者文档另建导出树。

`editor_shadow_restricted_20261007.json` 使用相同冻结图、overview 移动路径、每段 90 帧预热/240 帧采样、两轮 ABBA，源 SHA 未变，4372 记录、223 批次，批次重建增量均为 0。1026 构件符合受限合同、共享 135 个阴影网格。阴影调用约 2569→1869（视角有数次调用差异），保留原可见网格。各段中位数再取中位：场景渲染 CPU 17.869→16.569 ms，约减少 1.30 ms；全帧 35.473→35.0495 ms，仅小幅改善。原路径仍有一段 27.460 ms 的低值，因此不承诺固定 FPS 增幅；此项是削减已验证冗余，不是全城镜头 P0 全部完成。

实际 GPU/loopback HTTP 测试 `test_editor_building_shadow.gd` 最终 exit 0，无 ERROR/FAIL；覆盖工具发现、选择、整栋移动、undo/redo、楼层 dim/hide、独立隐藏、风预览、保存重开、材质/几何 changed、删除和撤销。实际 JSON 无 OpaqueShadow，拾取无代理 body。6 条共享资源监听回归也通过。初次解析错误、typed Array 错误和重复信号连接错误均修复后完整重跑，不计失败轮为通过。

固定方向光且确认阴影绘制非零的同相机 GPU 图片位于 `D:/code/rmmo_runtime/cache/world3d/editor_shadow_19796_9349284/`。2,730,756 字节中 293 通道相差 1/255；主代理和 subagent 独立查看檐口、地面阴影轮廓，未见可见变化。Forward+ 精确引擎 commit 的方向光 normal bias 在可见表面的 fragment 接收侧使用原 geo_normal，代理不改变接收网格；不将该结论外推到所有渲染器。经功能、视觉及受限性能验证，编辑器现在默认启用，无需 UI/MCP 新开关；不适用构件自动保留原阴影。

默认启用后已再次执行完整后台 GPU/HTTP 回归，`editor_building_shadow_20261007_default.log` exit 0、failures=0，包含默认开关断言。天空诊断改动也经原 `test_world3d_sky_sync.gd` 的 HTTP/GPU 功能回归通过，日志 `sky_sync_diagnostics_20261007.log`。
