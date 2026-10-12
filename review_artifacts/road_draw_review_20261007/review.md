# 道路叠加绘制静态复核（2026-10-07）

结论：未发现可凭当前源码证据安全消除透视道路 9–10 ms 回调成本的重大改动。只保留一个有限的投影候选供后续考虑；不实施生产代码、不启动测试，不把它列为已完成优化。

## 已确认的边界

- `scripts/world_editor/city_overlay.gd:281` 的道路回调依次执行边过滤、中心线投影、两侧线投影与绘制、中心线绘制，最后绘制节点圆点。每条道路的先侧线后中心线以及逐边顺序影响半透明覆盖，不能任意按颜色分组重排。
- `city_overlay.gd:156` 已使用一次 PackedVector3Array 原生 camera transform。正交平移命令复用也已存在（173 行）；不能再次把它们作为新的优化。
- `docs/editor_camera_performance_20261007.md` 的 headless 分项仅表明约 4.018 ms 中 cull 0.569 ms、project 1.104 ms；dummy renderer、细分计时开销和实际 GPU 回调不同，不能将该比例外推至全部 9–10 ms。
- 明确 controls 的 Bezier 路径仍需保留 `scripts/world3d/city_layout.gd:90` 的所有样本；无 controls 已是两个端点。
- cull 循环外提 fringe 是现有实验，约 0.18 ms，非重大新发现。

## 唯一保留的有限候选（未实施、未实测）

`city_overlay.gd:165` 每点执行 Projection × Vector4。可以在相机投影更新时将 Projection 的 clip.x / clip.y / clip.w 三个结果编码成 Transform3D 的三行，对已经得到的 local PackedVector3Array 再作一次原生批乘，之后 GDScript 仍按原顺序用 clip.w 除法与像素变换。

矩阵列应为 `(P.x.x, P.x.y, P.x.w)`、`(P.y.x, P.y.y, P.y.w)`、`(P.z.x, P.z.y, P.z.w)`，origin 为 `(P.w.x, P.w.y, P.w.w)`。这保留通用 Projection 的 w，不能仅假定透视 w=-z 或正交 w=1。原 local.z 与 near 比较仍须保留，并维持“任一点越过 near 就整条返回空数组”的现有行为。

该方式增加一个 Packed 数组分配和一次原生遍历，短边或已近裁剪拒绝的边可能更慢；不能只依据少了 GDScript Vector4 运算宣称收益。不得直接把 camera_inverse 和 clip 矩阵合并后声称逐位等价，重排运算及引擎浮点实现需验证。即便有收益，也只触及投影子项，无法据此宣称编辑器镜头卡顿已解决。按根代理决定，本轮不实施或测试此候选。

## 不采纳的方向

- 将多条道路合为一次 draw_polyline 会增加跨边连接，破坏路径及 AA 接缝；draw_multiline 又改变折线接缝，不是等价替代。
- 按颜色/线宽分组会改变透明交叠顺序。保留每条道路的 Node2D 命令后用透视变换复用，不能自动保留每个像素的固定线宽与 AA；复杂 shader/自定义网格不是已证实安全的大项。
- 屏幕外节点圆点裁剪仅可能减少小量提交。对正交模式在命令构建时裁剪会导致后续平移进入屏幕的节点丢失；没有收益证据，本轮不作为候选。
- 小地图纹理、降低曲线采样、禁用 overlay、宽度/颜色/AA 改变均不在本次候选范围。

## 范围

只读已列源文件与相关路径定义；仅在本报告目录写分析资料。未运行 GPU、headless、HTTP 或性能测试，未修改生产代码、地图或资源。Grok 的初审结论及退出情况另见同目录输出，在其完成后补充下面的复核记录。
## Grok 初审完成与独立筛选

使用 `C:/Users/luna/.grok/bin/agent.exe`，版本 `grok 1.0.46 (2765805b9442)`，参数为 `--tools '' --permission-mode plan --disable-web-search --no-subagents --max-turns 2 --output-format plain`，完整待审材料由 prompt.txt 提供。进程正常退出 **0**，exit.txt 已保存；grok_report.txt 为有效完整答复。stderr 仅有 Mixpanel 遥测 HTTP 失败警告，不能把这些警告理解为模型分析失败或据此改变登录配置。

采纳：Grok 的矩阵列布局与独立推导一致；它指出额外 Packed 分配、额外遍历和 near 提前返回可能抵消收益，确认没有可保证等价的简单透视 draw_polyline 缓存。其第二节是被否决的方向，不将其算成第二个实施候选。

纠正或收窄：

1. 开头“9–10 ms 的主体不在投影乘法”不能仅由 headless 1.10 ms 推出真实 GPU 场景的严谨比例。我们只确认乘法是投影中的一部分，尚无真实该操作分项/替换 A/B；不把 Grok 的推断当作测量结论。
2. “1 ULP 偏差就应放弃”是 Grok 自加的严格标准，用户约束是无可见质量损失。已有逐点相同测试可作为强验收，但浮点微差本身不自动等于视觉失败；需要像素及相同镜头目视验证。当前决定不实施，是收益尚无依据且只属小子项，不是以零 ULP 为额外门槛。
3. `project_local` 必须与折线投影一致是对结果的要求，并不要求为了代码形式强制改它；它继续用原 Projection 运算可作为参考。若候选与原运算结果相同，节点和正交 offset 不会因内部实现不同而必然错位。

最终处理：没有可靠的大项进入待实施列表，保留上述一个有数学依据但收益未证实的小候选；不改生产、不运行测试、不宣称解决编辑器 P0。