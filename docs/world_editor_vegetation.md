# 区域植被散布

2026-10-02：该批 3D MCP 新增 4 项植被操作，总数 **92 项**；后续河道批次为 **96 项**。入口为「城镇布局 → 区域植被散布」。这是编辑器即时放置模型的工具，默认资源包不存生成结果，也不会自动新增或购买树木素材。

## 使用

1. 新建区域，搜索资源库中的树木、灌木 GLB，Ctrl 多选最多 8 种。所有 GLB 都可以由用户选择；工具不根据名称猜测植物种类或美术风格。预制件和自动瓦片不在本批范围内。
2. 点选区域边界，Enter 完成、Backspace 退一点、Esc 取消；也可以使用街区面板选中的单个街区边界。
3. 设置地面标高、目标株数、中心间距、缩放范围、边界留空和种子；预览会显示完整模型占地，以及边界、承托、障碍、道路、间距和楼层导致的候选跳过统计。
4. 应用方案后，模型和区域配方一起进入一次撤销。可以选择已有区域，换种子重新生成；同方案重试不产生额外撤销。缺额 `shortfall` 表示在本轮候选预算内未放足，不是区域理论容量。
5. 生成成员经手动移动、改名、刷材质、受风设置、事件或分组修改后，更新会拒绝。可以先解除关联，保留所有现场，再以新区域 ID 生成补充植被。隐藏、锁定和楼层隔离成员须先恢复可编辑状态。

## 规则与边界

- 在简单多边形三角剖分中按面积采样，用局部固定种子随机选择模型、Y 轴朝向和等比缩放；通过最小中心间距及完整旋转包围盒拒绝重叠。并非聚簇分布、生态模拟或精确网格布尔碰撞。
- 完整模型包围盒均需落在退让后的区域内，并由指定标高的实际水平地面覆盖。支持多个相邻地面块共同承托；地面种类为 `ground/grass/dirt/stone/sand` 的水平 box，含相应自动块。模型坡地、地形投射、非水平地面、桥面种植尚不支持。
- 物件（含隐藏/锁定）、水面、已生成道路及其净空均为障碍；生成建筑按整栋体积和活动门窗范围避让，防止在室内空角长树。道路骨架尚未生成铺面时仍保留通行范围；骨架曲线按已有采样近似，变宽道路保守使用较大半宽。
- `no_vegetation` 和 `reserved_passage` 区域约束散布，隐藏/锁定不关闭约束；`no_build` 仅阻止建筑。新画区域不会自动清除旧树，需显式预览、更新其植被配方。门前接路、未建道路之外的游玩通道需要显式设置保留通道；本批不保证完整寻路可达性。
- 运行时碰撞开关显式应用到生成 GLB 的每个网格，保存后仍有效；编辑器始终保留用于选取的碰撞。树木保持原模型材质。本批没有自动受风模板；手动添加受风也是受保护修改。
- 区域/成员身份保存在 `editor_layout.vegetation`。成员仍为普通 `asset` 记录，物件复制不获得原区域所有权。删除成员后不擅自补回；只读清单报告 `modified_or_missing`。
- 重新生成只替换所选区域的未修改成员，其他区域和所有独立物件继续作为障碍。没有部分覆盖合并；修改后的成员不能被强制覆盖。解除关联允许保留已修改或删除后的现场，删除整个区域则要求成员保持原状。
- 本批不附送写实植物素材。现有默认库里的旧低多边形树不代表目标美术；可用现有导入入口接入许可允许的写实、嵌入依赖的 GLB。

上限：128 区域，每区 3～64 顶点、最多 8 种 GLB、目标 1～256 株；包围宽深最多 1000 米、包围面积最多 25 万平方米；每株目标最多 64 次候选，总候选上限 8192、道路/物件检查预算 200 万。超预算无副作用失败。仍使用文档全量撤销和场景重建，不声称已经完成整城密林性能优化、MultiMesh、LOD 或植被刷除。

## MCP 与共享事务

| 工具 | 参数和结果 |
| --- | --- |
| `list_vegetation_scatter` | 只读。返回区域设置、成员数、被修改/删除的 ID、GLB 素材；`query/offset/limit` 只过滤素材 |
| `preview_vegetation_scatter` | 只读。必填 `id/polygon/asset_ids`；其他参数省略时沿用已有区域或默认设置；返回 `placements/count/requested/shortfall/attempts/skipped/plan_token` |
| `generate_vegetation_scatter` | 同预览参数，可带 `plan_token`；创建或替换选定区域，一次恢复事务，返回 `ids/count/shortfall`；相同结果 `changed:false` |
| `remove_vegetation_scatter` | 必填 `id`；`keep_objects:true` 默认解除关联并保留物件，`false` 删除未修改的关联成员及配方；一次撤销 |

公共参数：`height` -10000～10000 米、`seed` 0～2147483647 整数、`count` 1～256、`spacing` .5～100 米、`scale_min/scale_max` .1～5 且最小值不大于最大值、`boundary_margin` 0～20 米、`collision` 布尔、`name` 至多 120 字符。`asset_ids` 与 `list_assets` 或本清单返回的 ID 一致；只接受当前或共享资源库内、处于授权内容根的 GLB。

`plan_token` 覆盖设置、布局、现有物件、楼层设置和 GLB 内容哈希；任一改变均拒绝旧预览。绘图草案期间禁止文档修改；UI 圈选本身不写历史，预览后应用才提交。旧地图没有 `vegetation` 字段时仍正常读取。二维 MCP 未注册。

```json
{"name":"preview_vegetation_scatter","arguments":{"id":"north_grove","polygon":[[-60,-40],[-15,-40],[-15,30],[-60,30]],"asset_ids":["使用 list_vegetation_scatter 返回的 asset_id"],"height":0,"count":40,"seed":7,"spacing":5}}
```

## 验收

- `tools/test_vegetation_scatter.gd`：凹多边形、种子复现、范围/身份校验、相邻地面联合承托与悬空拒绝。
- `tools/test_world3d_scatter.gd`：临时多网格 GLB、真实 HTTP 发现与原子失败、混合散布、隐藏障碍与保留区、未建道路、整栋建筑、单事务撤销/重做、手改/删除保护、楼层、草稿、保存重开、真实画布边界输入、保存后运行时射线检验碰撞开关。
- GPU 测试使用 `tools/run_godot_background.py` 的独立未激活桌面。临时地图位于外部 `__scatter_test_*`，不覆盖用户地图。球冠测试树只是几何验收夹具，不是写实素材交付。

主验收 `D:/code/rmmo_runtime/review_artifacts/scatter_final_live.log` 返回 `WORLD3D_SCATTER_FINISHED failures=0`。临时验收图位于 `D:/code/rmmo_runtime/__scatter_test_11870740/`：`scatter_preview.png`、`scatter_acceptance.png` 和 `maps/map.gltf`。

纯数学验收返回 `VEGETATION_MATH_FINISHED failures=0`；相关街区、MCP 和事件/环境回归日志为 `scatter_blocks_regression_live.log`、`scatter_mcp_regression_live.log`、`scatter_gameplay_regression_live.log`，全部通过，无脚本错误。回归日志位于相同 `review_artifacts` 目录。
