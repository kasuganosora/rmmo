# 返回需求版本触发诊断（2026-10-27）

接续 `return_official27` 官方profiler，返回帧34343中 `_refresh_demanded` 包含40.225ms，但原记录没有需求变化来源；旧 `test_demand_return_refresh` 的无关requeue合成场景能引发重复刷新，本次附近多窗口的requeue及index更新计数均0，不能认定该用例解释本帧。

新增 `demand_revision_trace.gd` 默认不实例化，诊断开启时在十类真实revision变化点和实际refresh边界记录有界、已清洗的标量和值类型、ID、需求变化、scope和累计工作，不保留地图对象；容量溢出分别记录change/refresh丢弃。scope增删ID上限16且标记截断。诊断probe按返回期启停，只有 `complete_return_leg` 且无丢弃才可视为完整覆盖；trace启用前的原因未知，initial仅指队列历史初次刷新。每次刷新自计墙时包含探针，record_us不包含整个runner开销和最终快照复制。独立审查覆盖10类触发及默认关闭；`demand_revision_final06.log` 33/0，移动需求既有回归 `demand_revision_moving06.log` 20/0，runner parse通过。路径 `D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/material_cache_pressure_20261027/`。

`demand_trace27` 正常客户端退出0、无failures/errors、被测脚本及地图主文件前后SHA一致、诊断runner额外SHA一致；状态complete_return_leg，2412事件、0丢弃，记录自身44.846ms，终止复制24.087ms；诊断不作为普通性能样本。期间1675次版本变化：set_demand 1350、release_demand 236、priority_anchor 89；737次刷新。其中434次由一次 `player_collision` set单独触发，经revision关联，累积输入173615行，刷新墙时合计1488.344ms、中位约2.29ms、最大18.566ms；这是整个诊断路段的累计，不能简单推算正常帧收益。

重要场景边界：`--native-departure` 的返回阶段是24秒从距原点(2048,2048)处回原点，约120.7m/s，player_collision envelope约每轴移动4m便更新；它是高速穿行压力，不是约6m/s普通步行。不能把434次直接说成正常游戏频率；需单独验证6m/s并保持精确碰撞就绪、候选优先级和排序，不能靠扩大碰撞需求制造表面收益。轨迹不显示原来的map24_B2长帧的具体调用栈，先前长帧仍未归因。
