# C-IPC 完整接触参考实现评估

2026-09-28，接续第十三批真实裙装失败。当前用途是离线参考对照，不是新的 Godot 默认后端，也不等于全部视觉验收通过。

## 为什么做这一项

当前 PBD 候选能修复部分身体穿透，但结构、身体和布层投影仍相互推翻；两接触方向近似已经在真实动作上否定。用户要求优先复用完整实现。此前安装的 IPC Toolkit 只有检测/势函数等组件，不包含完整物理求解器；因此检查作者的完整 [C-IPC 实现](https://github.com/ipc-sim/Codim-IPC)，不把检测函数冒充布料系统。

## 固定输入与范围

- 源提交：`9c6cbe3a5bef09a967ca8d420056adfafdf1fc9a`，Apache-2.0；保留源码许可证。
- 工程外源码：`D:/code/rmmo_runtime/tools/codim-ipc-evaluation`。稀疏检出 Library、Externals、CMake、Python，没有下载约 638 MB 的论文演示场景目录。
- 本机已有 WSL Ubuntu 24.04、GCC 13.3、CMake 3.28、Python 3.12.3。没有可用的免密码 sudo；所需 Eigen、Boost、pybind11 的 Ubuntu 包仅下载并解包到 `/home/luna/.local/share/rmmo/codim-reference/deps`，没有修改系统安装。
- Eigen 3.4.0、Boost 1.83、pybind11 2.11.1。包哈希、依赖 Git 提交和补丁文件哈希保存在外部 `review_artifacts/character_3d/codim_build_manifest.json`。
- 使用原实现已有的 `LINEAR_SOLVER=EIGEN` 选项；不是重写线性求解器。布壳能量、碰撞、摩擦、应变限制算法暂未改动。

## 可重放的兼容修改

`tools/prepare_codim_reference.py <源码目录>` 核对固定提交后，仅允许原文件或自己的已知修改版本，拒绝覆盖其他改动：

1. 改用项目专用目录内的 pybind11，适配 Python 3.12；保留原绑定接口。
2. 关闭无头模块没有使用到的 GLUT 查找，保留可重新开启的构建选项。
3. 在旧 meta 头文件的嵌套别名处显式写 `meta::invoke`，消除 GCC 13 名字含义冲突。
4. 对 Boost 递归 ptree 的 Python 绑定使用其真实 C++ 拷贝/移动构造 traits，避免绑定器递归展开 value_type；不是删除物理功能。
5. 固定原来未指定提交的 amgcl 和 Cabana。Kokkos/Kernels 沿用原 3.1.01 标签，同时记录实际 SHA。

配置已经成功。PowerShell 中完整引用 `-D...` 参数，否则包含 `.local` 的值会被拆开；失败日志不能当作依赖不存在。

```powershell
wsl -d Ubuntu -- cmake -S /mnt/d/code/rmmo_runtime/tools/codim-ipc-evaluation -B /home/luna/.local/share/rmmo/codim-reference/build '-DCMAKE_BUILD_TYPE=Release' '-DLINEAR_SOLVER=EIGEN' '-DCMAKE_PREFIX_PATH=/home/luna/.local/share/rmmo/codim-reference/deps/usr' '-DBOOST_ROOT=/home/luna/.local/share/rmmo/codim-reference/deps/usr' '-Dpybind11_DIR=/home/luna/.local/share/rmmo/codim-reference/deps/usr/lib/cmake/pybind11'
wsl -d Ubuntu -- cmake --build /home/luna/.local/share/rmmo/codim-reference/build --target JGSL --parallel 2
```

## 已执行的控制验收

主体已经编译成功，模块成功导入，并运行 `tools/probe_codim_reference.py`。原实现有未使用函数缺少 return 等编译警告；不能据此声称整个第三方源码没有缺陷。完整日志 `codim_build_compat.log`，实际模块位于源码 checkout 的 `build/JGSL.cpython-312-x86_64-linux-gnu.so`，不是 CMake 构建目录。

各案例独立进程，避免 driver 的 Kokkos 生命周期相互影响。小例使用 0.5 mm 最小接触偏移与 1 mm 屏障范围，和旧 GPU 小例参数不同，不作性能或数值幅度的横向结论。身体以 1 m/s 完成 0.2 秒轨迹。

| 控制 | 结果 |
|---|---|
| 自由落体，dt=0.01 | 通过，y 从 1 降至 0.79399；不是静止假通过。 |
| 身体推动双层布，dt=0.01 | 接触没有穿透，但身体最大偏差 0.043 mm，未过 0.001 mm 位置门槛。 |
| 上例收紧 Newton 容差至 1e-6 | 位置偏差仍相同，不是简单收紧 Newton 停止条件就能修复。 |
| 身体推动双层布，dt=0.00005，4000 步 | 通过当前控制门槛；最小身体间隙约 1.487 mm，最小布层间隙约 1.496 mm。独立 IPC 对全部 4000 个输出线性段再审计，无失败。 |
| 关闭接触，dt=0.01 和 dt=0.00005 | 两者均检出身体穿过布层，最终有向间隙 -100 mm；负对照有效。粗步长输出另经独立 IPC 检出两个穿越段。 |

上游 `Library/FEM/Shell/IMPLICIT_EULER.h` 的移动边界采用 `progress < 0.99`，所以 Newton 容差不等于身体轨迹误差。小步控制是在原实现上避开这一误差的诊断配置，**不是已修复其约束收敛，更不是游戏运行时方案**。OBJ 写出为 `%le`（7 位有效数字），报告中的近零误差受写出精度限制，不能解释成内部求解有 1e-16 米精度。

入口和证据：

- `tools/probe_codim_reference.py`：控制生成、每步有限性/位置/间隙检查；`--dt` 保持总时长 0.2 秒不变。
- `tools/audit_codim_reference.py`：检查固定拓扑、每一输出状态及相邻状态的连续线性碰撞，包含独立已知穿越/不穿越控制及旋转版本；不代表未导出的 Newton 中间迭代或整件衣服。
- `review_artifacts/character_3d/codim_probe/summary.json` 汇总原始报告。细步负例完整数据位于 WSL `/home/luna/.local/share/rmmo/codim-reference/probes/body_layers_no_contact_substeps`，报告另复制到工程外证据目录。
- 日志与 OBJ 写到 WSL 原生目录能减少跨文件系统 I/O。不同输出位置的耗时不可用来比较接触开关的物理求解性能。

## 真实裙装输入门槛

`tools/prepare_codim_garment_input.py` 使用已固定的原 HW 外裙和完整 `female_base_v2`，核对绑定/源 SHA256，导出原 rest OBJ 与原跟随权重；没有重新建模或膨胀网格。4920 布点/9560 三角面、21556 身体点/42160 有效三角面；与现有候选一样仅跳过源身体两张零面积三角面，记录原索引，不删除渲染面。

独立 IPC 仅排除规定运动的身体与自身接触，保留全部布层间及布—身体检查。原 rest 输入无自交/布—身体交叉；但全局最小间隙约 **0.162813 mm**，不满足小例的 0.5 mm 偏移。因此完整输入门槛明确返回失败，不能把“没相交”当成“任意厚度都可求解”。报告 `codim_hw_input/input_manifest.json` 保存间隙、最近特征、源哈希及结果。

原 `cloth_rest.bin` 第四分量是跟随权重；现有候选用 `cloth_weight=1-follow_weight`，再按原 0.01/0.99 阈值分类。对应 0 硬固定、1632 混合、3288 自由。不能读反权重，更不能为了让其它求解器容易接入而把混合区全锁死。

## 接下来的门槛

先处理源间隙与接触偏移的兼容、原软跟随语义及运动约束误差，再输入原自然动作和椅子、输出回放并完整几何审计。上游 `STITCH.h` 遇到任意固定端会跳过该缝合项，且全局只有单一 k，不能直接冒充每顶点的软跟随接口。不要先跑一个自由掉落或全腰硬固定的裙子就声称换装适配完成。

没有授权替换身体、删褶边、改变动作或把有软跟随的区域全部锁死。Windows/Godot 运行时桥接及性能仍未验证；不能因 Linux 参考输出好看就称正式换装成立。正式游戏后端仍未切换，完整裙装状态仍以第十三批失败为准。

## 第十六批：软跟随输入适配层与原动作导出

`enable_codim_surface_follow.py` 在固定的参考 checkout 增加一个显式可关闭的预测输入适配层，源码为 `tools/reference/codim_surface_follow.h`。**这一批修改了输入预测，不再是完全没有算法适配的原版参考**；接触能量、CCD 和 Newton 接触求解未更改。补丁及哈希独立记录为 `RMMO_SURFACE_FOLLOW.json`，不要把第十五批兼容构建的 manifest 单独当成本批模块身份。

仅在设置 `Set_Parameter('RMMOSurfaceFollowFile', path)` 时启用。文件首行是 `count reference_dt max_travel`，后续按前 count 个布点顺序给出 `target_x target_y target_z cloth_weight`。用原候选预测公式：先限最大偏离，再按 `pow(cloth_weight, dt/reference_dt)` 混合。目标作用于 Xtilde，之后仍由联合结构/接触求解修正，不能在最终已解决位置上再次拉回目标。全部输入先检查，再修改预测；拒绝错误数量、截断、非有限值及硬固定范围，硬固定应单独使用 DBC。当前 HW 不含硬固定点。

原生编译成功。`test_codim_follow.py` 的十项独立进程测试均通过：关闭、软跟随、自由权重、细步指数、最大偏离、两种非法权重拒绝、原自由落体、接触正负对照。软跟随一大步 y=1→1.5；固定身体 y=1.25 时，开启接触后的间隙约 0.898 mm，身体不移动；关闭接触后布面穿过 250 mm，负例有效。此控制不代表整裙、多层或运动身体验收。

证据 `codim_follow_controls/suite.json` 包含当前模块 SHA256、各案例结果及原生日志；构建日志 `codim_build_surface_follow.log`。Linux 原始控制目录 `/home/luna/.local/share/rmmo/codim-reference/probes/surface_follow_01`。兼容准备器和此适配器均拒绝覆盖未知修改，现有源码无需重复重建。

`export_codim_motion.gd` 复用现有身体与表面绑定，在 CPU 求解器导出与候选相同的 rest→自然站立→坐下轨迹，共 130 帧；输出世界坐标身体 OBJ 和原权重的 follow 输入包。没有运行布料、改动关节或新增固定点。`audit_codim_motion.py` 核对全部文件哈希/点数/有限性/原权重，并将五个关键状态与 `body_release` 原 GPU 快照比较：身体最大差异约 0.5305 微米，权重写出误差小于 4.6e-10。证据为 `codim_hw_motion/motion.json`、`audit.json`。这是输入保持验收，**尚未包含椅子/地面或布料模拟输出**。

下一步：以该动作和原跟随输入接整裙；先明确与 0.162813 mm 源间隙相容的接触偏移，再保留同一身体/椅子及原门槛独立审计。不得把预览输入导出误记为整裙已验证，也不要使用原 driver 的 seqDBC 隐含 -0.75 米平移。

## 第十七批：完整网格已开始求解，起步输出通过，整段运行中

`prepare_codim_scene.py` 从原坐姿快照恢复六个椅子盒体及同一 6×6 地面，坐标转换到世界空间；52 场景顶点、74 三角面。身体及裙子初态相对原 rest 只作统一平移，误差分别小于 0.060/0.175 微米。没有改椅子间隙或删模型面。

`run_codim_garment.py` 接入 4920 布点、21556 身体点和全部场景碰撞体。身体与场景由显式 DBC 输入，关闭原 driver 隐含平移；原软跟随先作用于预测再联合求解。参考偏移选 0.08 mm，小于已验证源间隙一半；屏障激活 1 mm，四子步，材质与全部参数写进 result。这是离线参考配置，**不等于将游戏 6 mm 身体候选参数改小或降低已有几何门槛**。

第一次 `hw_smoke_01` 随外部运行环境中断：原进程已不存在、WSL 随后重新启动，只留下 shell0 和未完成日志，没有完成结果；不把它当成求解器通过或已证实的算法故障。确认进程终止后，新目录 `hw_smoke_02` 两帧/八子步已完成。帧 0 包含约 304 秒起步收敛；它是原 T 姿到自然垂手的开头，绝不是已完成自然站姿。

实测两个保存输出：子步 2、帧 1 末子步 8，当前独立几何门槛通过。两者身体/手/场景穿透、自交/共面交叉、退化面和过度拉伸均为零；最大边长比分别 1.03491、1.02399。求解器身体与原要求身体的最大偏差小于 0.504 微米。`convert_codim_capture.py` 使用原要求身体而非求解偏移后的身体，并核对输出序号，防止重标样本。`audit_garment_contacts.py` 增加显式输入/报告路径；旧失败站姿重放仍准确检出 7 对自交，与原报告除样本名外逐项一致。

`capture_codim_garment.gd` 将相同原材质、源拓扑与求解结果送回 Godot 棚拍。帧 1 正/侧视已检查，原裙分层、褶边和版型保留正常；背面另提供只隐藏遮挡椅子的伴随图，不修改物理碰撞体。仍没有测试垂手压裙或坐下结果。

完整 130 帧已启动：WSL `/home/luna/.local/share/rmmo/codim-reference/runs/hw_full_01`；日志 `codim_hw_full_01.log`。下一轮先核实当前进程、`progress.json` 与输出，**未证实终止前不要重启**。结果由 `complete_trajectory` 和独立审计共同判断；runner 自身永远不会以“写出文件”自动标 accepted。正式人物链和后续计划仍待完成。
