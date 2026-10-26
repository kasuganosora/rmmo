# 调试外观意外重建碰撞 BVH（2026-10-26）

真实返回重载 GDB 抓到一个此前计数遗漏的主线程工作：后台准备好的碰撞
BVH 已安装，但 `CollisionShape3D.set_shape` 传播默认调试颜色时又重新
构建碰撞。独立复现后，已实现只刷新调试显示的引擎修复；整图功能通过，
性能对照受外部负载影响，仍未完成稳定性能验收。

## 实际调用链和修复边界

证据来自 `shader_prepare_20261026/reload11/stacks.jsonl`，第 0 次主线程栈：

```text
CollisionShape3D::set_shape (scene/3d/physics/collision_shape_3d.cpp:209)
  Shape3D::set_debug_color
    ConcavePolygonShape3D::_update_shape
      PhysicsServer3D::shape_set_data
        GodotConcavePolygonShape3D::set_data
          _setup → _volume_build_bvh → introsort
```

`set_prepared_faces` 的字典中包含原生准备产品，backend 可以直接接收 BVH。
后续 `_update_shape` 只传 faces / backface，没有准备产品，于是再次完整
构建。调试填充的 setter 也有相同问题。节点绑定时的这段传播在
DEBUG_ENABLED 下存在；本机正在使用的 optimized editor 包含该路径。
不能据此声称所有 release 导出都会自动绑定重建。

`godot-4.7.2-shape-debug-refresh.patch` 将两个外观 setter 的刷新明确指向
`Shape3D::_update_shape`：保留 changed 信号、debug mesh cache 失效与
debug_properties_edited 状态，不再虚调用派生类的物理重建。没有删除
真实几何 / backface 变更的重建，没有改碰撞内容、shared shape 或 RID。

同一二进制用 `RMMO_SHAPE_DEBUG_REFRESH_ONLY=0/1` 选择旧 / 新行为，默认 1。
源码前副本 `before02/shape_3d.cpp`、修改生成器 `prepare02.py`、SHA
`sources02.json` 都保留；补丁反向 apply 检查通过。

## 先复现、后修复

`tools/test_collision_debug_refresh.gd` 在外部空项目运行，生成 18432 个
三角形，worker 准备一次、主线程安装，再绑定节点、修改 24 次颜色和
12 次填充。包括共享 owner 的通知、相同属性 no-op、RID / faces 保持、
前 / 背面射线，以及真正修改 backface 和顶点后碰撞更新，共 49 项。

首次 `baseline01` 有三项射线断言失败，原因是测试平面顶点绕序反了。
原始测试 `fixture_failed01.gd` 与失败输出保留。只修正为 Godot 顺时针
正面，未修改引擎，`baseline01b` 49 项全部通过，并复现：

- 后台准备 36.011ms，prepared 安装 **0.030ms**。
- 绑定节点再次花 **14.490ms**。
- 每次仅改颜色 / 填充约 **12–15ms**。

## 同二进制独立压测

`micro04` 的四组均通过 49 项，固定三角形与操作数量，不使用这些时间
代替游戏 FPS 或整图省时：

| 样本 | 只刷新调试显示 | 绑定 ms | 24 次颜色变更 | 12 次填充变更 |
| --- | --- | ---: | --- | --- |
| A1 | 关 | 30.093 | 每次约 13ms | 每次约 13ms |
| B1 | 开 | 0.043 | 0–5μs，多数 1μs | 1–6μs，多数 1μs |
| B2 | 开 | 0.046 | 0–5μs，多数 1μs | 1–7μs，多数 1μs |
| A2 | 关 | 29.645 | 12–27ms | 12–14ms |

输入 SHA / 每次调用原始时间 / 检查结果在 `micro04_results.json`。
first baseline 与同二进制 A 绑定时间差异保留，不用一个最快值代表全部对照。

## GDB 证明没有重建，而不只看耗时

`run_gdb05.py` 启动自己拥有的 headless 子进程，在真实原生函数断点自动
计数。缩小为 128 个三角形，操作次数与功能检查相同。没有调用 inferior
函数或修改其内存，所有停顿耗时排除出正常性能结果。

| 同二进制模式 | BVH `_setup` 次数 | base `_update_shape` 次数 | 功能检查 |
| --- | ---: | ---: | --- |
| 旧外观路径 | 40 | 40 | 49 / 49 |
| 只刷新调试 | **3** | **40** | 49 / 49 |

删除的 37 次是绑定 1 次和颜色 / 填充 36 次；保留首次 worker 准备、
backface 编辑和几何编辑各 1 次。调试刷新仍完整执行，实际前后调用栈都
保存在 `gdb05_0.json` / `gdb05_1.json`。这也说明现有项目安装计数不能
自动代表引擎内部的真实 BVH 构建次数。

## 构建与场景回归

隔离 `collision_debug_20261026/engine03`，在 shader CPU 准备候选上叠加
本修复，MinGW optimized editor、相同 flags，构建 exit 0，178.875 秒。

- EXE SHA256 `6be09288a2725778bb922d8c3de8d939a016d56878fafe316b56ec8e5d870870`
- symbols SHA256 `42395486adc67e91823e8473bf1967963fb1d647b013b1730b25fda64c20e8e2`
- shape_3d.cpp SHA256 `5eebc11e60aa47228b910f9e6bae4054a94268803dd759fe7193e2daf1a86ec9`

GPU `gpu06` 使用不激活的私有桌面：collision product 31 项、loading
collision preparation 54 项、prepared material publication 64 项通过，
共 149 项。包含门洞 / 地板空洞、射线、球扫掠、角色地面接触与准备产品
的真实提交。没有修改用户地图或模型资源。

## 整图对照与保留边界

`run_map07.py` 先单独保留新二进制首次地图 `first07`，再做旧 / 新 / 新 /
旧四次完整遍历；加载边界、无派生几何缓存、地图纹理与导入模型白材质范围
沿用 `axel_shader_cpu_prepare_20261026.md`。新 shader 锁外准备在这组固定
**关闭**，避免混入此前已发现没有整图收益的另一变量；compact transfer 开。

每次启动前有 10 秒只读安静期检查，运行中用 host07 记录相关进程负载，
不停止用户或其他 agent 任务。普通样本不开 GDB / 原生逐容器 profile。
默认 `D:/tools/godot` 尚未替换。

首次 `first07` 功能通过，完整就绪 **16.257063s**，独立保留。四组完整
遍历也全部 exit 0、功能通过、源码 / 地图不变：

| 样本 | 完整就绪 s | 卸载 max ms | 返回 max ms / >50ms | 重载 max ms / >50ms | 重载 1% low FPS |
| --- | ---: | ---: | --- | --- | ---: |
| A1 旧外观更新 | 12.781 | 44.510 | 96.811 / 15 | 77.552 / 8 | 22.020 |
| B1 仅调试刷新 | 14.007 | 31.819 | 44.051 / 0 | 39.905 / 0 | 29.064 |
| B2 仅调试刷新 | 10.476 | 28.435 | 78.765 / 11 | 70.890 / 9 | 21.349 |
| A2 旧外观更新 | 12.532 | 69.679 | 35.936 / 0 | 43.563 / 0 | 27.946 |

**四组全程都出现了其他 Blender / Godot 运行，不能作为严格性能收益
对照。** 安静期只能保证启动前一段时间，不能保证整次遍历。B2 首次观察到
其他 Blender 在其进程启动后约 39.5 秒；其加载 10.476s 可保留作单样本，
没有足够无干扰对照来宣称改善比例，也仍高于 10 秒。

四组系统 CPU 峰值分别 61.4 / 78.8 / 61.1 / 71.3%。模型工作量
63 / 62 / 62 / 70，实例 3230 / 3192 / 3229 / 3267，纹理上传均
170 次 / 721332072 B。未归因帧保留，不能把 Deferred 子项短解释成
OS 空闲；需求刷新单次仍出现 73.450 / 55.828ms，材质提交仍为
136.176 / 146.900 / 101.572 / 129.383ms。

负载汇总还修正了 **PID 重用** 的统计错误：初版 `host07_summary.json`
只按 PID 筛选，会把该 PID 在后续样本中对应的新进程算入前一组。正确版本
是 `host07_summary_identity.json`，使用 PID + 创建时间 + launch/result
窗口确认身份。`summarize_host_identity.py` 含合成 PID 复用检查，原始
host07.jsonl 不改。旧汇总不再作为逐组负载证据。

## 最终默认配置候选（尚未安装）

保留 shader CPU 拆锁实现，但将环境开关变为显式 `=1` 才开启；碰撞修复
仍默认开启。`prepare_stable08.py` / `sources08.json` 保留修改，`before08/`
保留原始开启默认值的源码与补丁。engine09 构建成功，226.360 秒：

- EXE SHA256 `40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`
- symbols SHA256 `3039c3ba7fbb71f965ec42cb9100a483a439e95b6cfda3ed194cfae54989db76`
- RD.cpp SHA256 `4d8a7b78ec0a3dc8cfadd549f5846be0417c1e7073e39cff0b970dabcf1e5bd3`

清除三个试验开关后，`default10` 重跑 49 项逻辑和 149 项 GPU 检查，
共 **198 项通过**，绑定 0.043ms。`first_default11` 默认配置地图烟测
功能通过、源码 / 地图不变，但 entry **8.354262s**、完整就绪
**22.333824s**。此烟测没有独立 host 观察器，不能用之前的进程记录替它
归因；既不能说是修复引入，也不能说已证明是外部负载或驱动冷缓存。

因此本轮保留候选与明确的工作量收益，**不替换常用引擎**。已准备的安装
脚本 `install12.py` 尚未执行，默认安装仍是 `0f0bf446…`，没有改动用户
正在运行的其他任务。下一步需要完整记录负载的默认配置复测，查清首次
慢样本及仍存在的需求刷新 / 材质提交 / 返回重载尖峰，再决定启用范围。

证据根：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/collision_debug_20261026/`。
