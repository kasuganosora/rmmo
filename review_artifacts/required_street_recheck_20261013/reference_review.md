# S10 / S12 新增模型复审（2026-10-13）

本批 11 件中，11 件的资源、画质、运行管线及临时编辑器接入均通过。正式目录/城镇地图尚未发布。每项只采用当前导出 SHA 的证据；完整身份与独立状态见 [逐件验收索引](acceptance/index.json)。

## 参考与最终修复

按 `rmmo-model-review` 执行。用户原图入口为 `docs/references/town_required_shots_20261012/` 的 S10 果树院落、S12 浅溪踏石及外挑双柱拱门。原始资料、原母版、原 GLB 与各次回退版本保留；不可见背部、雕饰纹样和游戏通行尺寸是项目补充设计。

- 外挑双柱拱门保留两柱、柱础、拱券和回墙关系，补背部连接。小型切石替换原不合尺度的岩崖层理，补米制 UV；柱体端盖与侧面分离法线，修复原斜向假阴影。
- 高窄雕饰板保留尖顶、层次边框，叶片及卷草接入底板；曲线实现后建立有效 UV。内部卷草图案为项目补充设计。
- 三/四级下水短阶采用粗糙细矿物切石。0.16 m 踢面、0.40 m 踏面与 0.84 m 平台是第三人称通行适配。
- 四种踏石及组合最终采用统一角序的环形采样、宽圆肩和独立内冠。轮廓变化对 X/Y 同倍作用，保留角序；两圈浅内冠连接中心，顶冠起伏控制在毫米级；移除旧内辐射边倒角。四件宽度和轮廓变化不同，中央稳定踏带属于游戏补充设计。真实碰撞完全跟随可见三角形，没有跨缝隐形桥。
- 踏石保留已购 `natural_rock_02` 灰色碎裂岩面及正确的 DirectX 法线绿色通道转换；可见冠面连续投影，水下侧面连续环向 UV。水线验收平面固定在 0.34 m，仅用于观察露出比例，不代表正式河流材质验收。干地全露时两种 UV 的接带仍可见，本次画质结论限定于 S12 浅溪踏石用途；正式水透明度和水下观察仍随场景复验，不宣称任意露底摆放已验。
- 安装样例修正矩形墙洞：实心弧形墙肩封住旧拱角漏天处，保留真正通透的拱顶。它是拱门和雕饰的安装验证载体，不是完整住宅。
- 红果树保留已购枝叶几何、叶 atlas、alpha、三个 LOD 及风场；果皮 UV 从无效层恢复，增加粗糙度微差，主干转竖向米制 UV，枝条恢复原已购 UV。树皮改灰褐色，母版与 GLB 同步；果形/数量是参考红果语义的补充设计，不冒称确证物种。

## 逐件结果

| 模型 | 源三角形 | 资源 | 画质 | 运行管线 | 临时编辑器 |
|---|---:|---|---|---|---|
| [s12_projecting_arch](acceptance/s12_projecting_arch.json) | 21200 | 通过 | 通过 | 通过 | 通过 |
| [s12_gable_relief](acceptance/s12_gable_relief.json) | 29660 | 通过 | 通过 | 通过 | 通过 |
| [s12_water_step_a](acceptance/s12_water_step_a.json) | 958 | 通过 | 通过 | 通过 | 通过 |
| [s12_water_step_b](acceptance/s12_water_step_b.json) | 958 | 通过 | 通过 | 通过 | 通过 |
| [s12_water_step_c](acceptance/s12_water_step_c.json) | 958 | 通过 | 通过 | 通过 | 通过 |
| [s12_water_step_d](acceptance/s12_water_step_d.json) | 958 | 通过 | 通过 | 通过 | 通过 |
| [s12_landing_steps_3](acceptance/s12_landing_steps_3.json) | 2256 | 通过 | 通过 | 通过 | 通过 |
| [s12_landing_steps_4](acceptance/s12_landing_steps_4.json) | 3008 | 通过 | 通过 | 通过 | 通过 |
| [s12_water_steps_four](acceptance/s12_water_steps_four.json) | 3832 | 通过 | 通过 | 通过 | 通过 |
| [s12_facade_installation_demo](acceptance/s12_facade_installation_demo.json) | 51648 | 通过 | 通过 | 通过 | 通过 |
| [s10_redfruit_broadleaf](acceptance/s10_redfruit_broadleaf.json) | 363516 | 通过 | 通过 | 通过 | 通过 |

## 验证与成本边界

资源证据见 [resource_audit.json](resource_audit.json)；真实 AssetLibrary 导入、原生缓存身份、逐件 native 资源图、实际 3D loopback HTTP 放置/选择/碰撞/非法调用/撤销重做/保存重开见 [editor_http.json](editor_http.json)。测试通过既有进程级 content_root_override 隔离内容根；没有提高 8 GiB 缓存预算、清理共享缓存或覆盖用户地图。

生产 `world_authority.gd` 使用 1.8 m 高、0.30 m 半径角色胶囊，拱门、两种阶梯、四石组合分别双向遍历，共 8 路。最终原生模型证据见 [traversal_native.json](traversal_native.json)；GLB 直接验证另见 [traversal.json](traversal.json)，两者不混用。单石由组合四个相同局部三角网覆盖物理路线，并保留各自独立碰撞探针。

四件实际导出网格的顶冠朝下三角、退化三角均为零；每件 3,721 个竖直采样没有重叠的向上表面。组合局部三角形与四个单件逐点完全一致，检查记录写入逐件 JSON。

人工图审覆盖近、中、远、背面、材质/连接细节；树补明暗叶缘、树影、风姿态及六个距离的自动 LOD/强制 LOD0 对照。当前视图、相机和光照参数见每件 report.json；实际查看的图像 SHA 见 [visual_decisions.json](visual_decisions.json)。发送模型分析前使用原尺寸高质量 WebP，PNG 仍在本地保留以供精确比较。

小踏石各 958 三角、组合 3,832 三角；去除问题拓扑后无需额外 LOD。台阶、雕饰、拱门保留轮廓与倒角，未为比例指标强制减面。树的 363,516 三角是全部存储 LOD 的合计；实际图库计数（含 2 面地面）为 258,094 → 93,513 → 44,441，不能将合计当作单帧可见面数。

RGBA/mip、原生资源图及准入估算是资源预算，不是单件实测 RSS/VRAM；同像素纹理的去重统计也不证明不同导出文件在运行时共享纹理。正式地图部署仍需复用既有共享材质/批次和逐组件选择语义。

## 已保留的失败证据

history/ 保留旧大尺度层理、规则石墩、局部压肩后的顶扇反折、矩形拱洞、HTTP 夹具身份错误及共享 native 缓存容量耗尽记录。旧单轴压肩使相邻顶点角序反转，原倒角又放大了顶内折面；最终已改为完整有序冠肩拓扑。通行通过从未替代这些画面问题的修复。
