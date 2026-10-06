# 道路、桥梁联动与高差过渡

2026-10-02。入口：**城镇布局 → 生成道路铺面与路口**。在已有河道中选桥，点“接入路网”，再从返回的桥头节点向外绘路。直线道路可以连接不同标高；两端保留水平接头，中段生成斜坡。UI 与当前 3D MCP 共用 `road_connection_tools.gd`、`road_tools.gd`，生成到当前地图，不往资源包写固定模型。

## 桥头与斜坡规则

- 接入生成两个桥头节点和一条带 `bridge_ref:{waterway_id,bridge_id}` 的道路边。桥梁实体由河道配方管理，道路生成器跳过这条边，不在桥上再叠一层路面。
- 桥头世界位置与河道桥头一致；通行净宽为桥总宽减 0.6 米栏杆占地。0.25 米内的可编辑节点可复用。重复接入幂等；隐藏、锁定或关联其他桥的节点不能被悄悄移动。
- 桥头接路必须朝桥外直向延伸，桥头端路宽不超过净宽。UI 点选道路自动收窄桥头端，另一端保留设定宽度。需要转弯时在桥外另加节点；不能在桥上拆出十字路口。
- 接桥铺面偏移须为 0.025 米，与桥头顶面齐平。变宽道路末端在桥头平面裁齐，不覆盖桥面。
- 高差目前支持**直线段**，两端水平接头各预留该节点最大相邻半路宽。余下坡段至少 1 米，实际坡度不超过 15%；按扣除接头后的长度计算，不能仅凭整段平均坡度通过校验。
- 水平曲线仍可使用；弯曲斜坡暂不生成。坡段使用真实倾斜网格、法线、米制 UV 和碰撞；相交平面按真实重叠处高度检查净空。高平台穿入坡道、坡道彼此穿插会拒绝。
- 本轮不自动削山、回填、生成坡下支撑或导航网格。高差道路可以跨空；节点承托诊断会提示端点问题，但不证明整条路径具有地基或完整寻路能力。

## 保护与诊断

绑定后不能通过普通道路编辑改变桥梁边的几何、宽度或端点，也不能直接修改/移除河道配方。先“解除桥梁路网绑定”，再改河道，重新接入并生成道路。解除只删虚拟桥边，保留桥体及仍供引道使用的节点。

联动前校验河道全部成员；手改、缺失、隐藏、锁定和楼层隔离会阻止覆盖。已生成道路沿用手刷材质/事件保护、稳定成员身份、单事务撤销及保存校验。任何失败均不改变文档或撤销栈。第一轮水平道路旧地图仍可读。

“检查路网连通”返回连通分量、死端、疑似缺少承托的节点、桥梁绑定、铺面是否过期，以及共享铺面生成校验结果。死端是提示，巷子尽头可以是有意设计；几何相交不等于拓扑相连。

## MCP

| 工具 | 参数 / 结果 |
| --- | --- |
| `connect_waterway_bridge` | `waterway_id/bridge_id`；返回边 ID、节点 ID、端点、净宽；一次撤销 |
| `disconnect_waterway_bridge` | `edge_id`；解除绑定，保留桥体和使用中的引道节点 |
| `get_road_connectivity` | 无参数、只读；返回 `components/dead_end_nodes/unsupported_nodes/bridge_bindings/pavement_stale/buildability/diagnostics` |

实际铺面仍用 `preview_road_surface` / `generate_road_surface`，无新增平行实现。`create_road_path` 的点使用 `[x,y,z]`，不同 Y 值表示高差。

```json
{"name":"connect_waterway_bridge","arguments":{"waterway_id":"town_river","bridge_id":"market_bridge"}}
{"name":"get_road_connectivity","arguments":{}}
{"name":"preview_road_surface","arguments":{"material_id":"pack:default:paving/historic_cobble/material"}}
{"name":"generate_road_surface","arguments":{"plan_token":"预览返回的令牌"}}
```

## 验收

`tools/test_road_plan.gd` 覆盖扣除水平接头后的实际坡度、既有平路/曲线路口。`tools/test_world3d_road_connections.gd` 在独立后台桌面经真实 HTTP 验证接入/解绑、非法修改无副作用、保护、撤销重做、UI、草稿、保存重开与再次保存。保存地图加载到运行时后，2.1 米胶囊从高台走下坡道、跨桥到对岸，再反向返回，全程检查地面接触；PBR 和桥头无重复铺面同时检查。

桥梁外观仍按 [待办](world_editor_todo.md) 重做，通行验收不代表模型美术通过。

后台真实 HTTP / GPU 验收：`D:/code/rmmo_runtime/review_artifacts/road_connections_final.log`，`ROAD_CONNECTIONS_FINISHED failures=0`；测试地图为 `D:/code/rmmo_runtime/cache/world3d/road_links_10944992/map.gltf`。原有道路、河道回归分别为 `links_regression_roads.log`、`links_regression_waterways.log`，均零失败。所有文件都在临时运行目录，未覆盖用户地图。
