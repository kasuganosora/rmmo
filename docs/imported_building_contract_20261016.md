# Blender 完整建筑的导入、楼层与活动门合同

本轮用于厄里斯教团教会、警卫处、水磨坊。模型仍是一个可选择、移动和保存的导入资源；室内分层、屋顶隐藏、门状态与加载就绪成员来自源模型的显式标注。没有标注的旧模型保持原有行为，不根据包围盒推断室内，也不冒用旧公会 `delivery_stage`。

## 源文件标注

GLB 默认场景中只有一个节点携带：

```json
{
  "rmmo_model_components": {"version": 1},
  "rmmo_building": {
    "version": 1,
    "regions": [{"id":"hall","floor":0,"min":[-4,0,-8],"max":[4,4,8]}]
  }
}
```

`regions` 是 Godot 坐标（米、+Y 向上）的真实室内区域；外廊、门前平台、楼梯孔和室外水轮不能因为落在建筑总包围盒中就成为室内。重叠区域由对应楼层高度判断。

每个网格节点必须有唯一稳定的 `uuid`（字母、数字、下划线或连字符，最多180字符），以及：

```json
{"rmmo_part":{"floor":0,"floor_y":0.3,"role":"door","part":"main_left"}}
```

`role` 为 `body / floor / roof / ceiling / stairs / furniture / door / mechanism`。所有网格均需标注；部分标注不放行。节点显示名称不作为跨导入身份，避免 Godot 对名称的清理导致源/native不一致。

实际门叶在自身局部坐标携带 `rmmo_hinge: {id, pivot:[x,y,z], angle, open}`，当前是绕局部Y轴的门铰链，角度−180～180°、开度0～1。同一门的叶片、铰链、把手可共享活动件ID，必须使用一致默认开度。水轮X轴运动不冒充门铰链；独立机械件保留轴心资料，自动传动另行实现。

## 导入与保存

正常 AssetLibrary 导入同时读取实际 native 场景和有界 GLB JSON，比较房间、源UUID、分件和门ID，并绑定最终完整文件SHA。库条目的 `model_building` 包含 `version / regions / members / fixtures / source_sha`。重复导入的合同和缩略图信息合成一次原子目录保存，失败整体还原；旧不可变资源保留。

记录中的每实例门状态保存为 `model_building_states`。旧公会继续使用原来的 `model_component_states`，不迁移旧不可变定义。两个实例可以共享几何资源而有不同门状态。保存和打开均核验每条记录的合同与实际源文件，即使两个实例引用同一路径，也不能跳过后一个实例的检查；保存分片等待结束后再次检查源SHA。

源文件可访问范围仍受内容根限制。门开合扫掠范围使用原始 accessor 包围盒与连续转角极值计算；静态关闭状态的包围盒不能遗漏打开的把手/门叶。运行成员身份为 `record.uuid + "__" + source_uuid`。依赖索引将整个导入建筑作为原子加载组，加载就绪检查使用完整实际网格成员，保留独立门、逐楼层和屋顶语义。

## UI 与当前3D MCP

复用现有 `list_building_components`、`set_building_component_state`、`set_floor_view`、`place_asset`、`save_world`、`open_world`。无需增加二维适配器或另一套行为。

- 组件清单返回实际门ID、楼层、层高和 `editable`；锁定、隐藏、隔层外的组件不可操作。
- UI按钮与HTTP调用使用同一操作、撤销记录和重建流程。门开合后碰撞跟随实际网格变换。
- 导入建筑分层显示/调暗以各网格层高判断；屋顶和天花板结合实际世界包围盒剔除遮挡，不整栋合并隐藏。
- 第三人称相机初次绑定和重新绑定读取已加载的 `stream_library`；后续流式发布增量补齐。成员来自显式 `extras.building` 与实际世界包围盒，灯锚、透明片或LOD不参与合批也不会丢失遮挡隐藏语义。
- 楼层隐藏仅关闭显示与拾取层。物理部件的 `WALK_MASK` 保留，非物理玻璃不产生不可见拾取面；分片加载与同步重建规则一致。
- 地图保存保持一个原始建筑记录和每实例门状态，派生渲染批次、可见性与碰撞体不写回源GLB。
- 流式可见性分组优先读取 `extras.building.id`，合批记录仅作旧组件兼容；不合批的灯锚、玻璃或LOD与同栋主体同组。未标建筑归属的普通风场物件仍沿用原近距策略。

## 验证入口与当前状态

`tools/test_imported_building_components.gd` 覆盖合同拒绝、旧公会兼容、非均匀缩放、真实源JSON读入、连续门扫掠及分层碰撞策略；当前73项通过。新增真实物理射线检查初次加载和重绑后的上层遮挡隐藏、不合批灯的成员归属与原始可见性恢复。`test_house_stream_observers.gd` 原有流式观察者28项回归通过。带 `--candidate-audit` 可审计三栋当前候选（可用 `--church=...` 等覆写文件），输出 `review_artifacts/axel_landmarks_20261016/pipeline/source_contracts.json`。

`tools/test_imported_building_membership.gd` 覆盖室内归属、完整就绪成员、同SHA伪造房间拒绝、共享路径第二实例拒绝、资源分组与保存引用；当前53项通过，另含保存分片后源文件改变拒绝及既有库条目合同/缩略图升级失败的整体回滚。既有authority/index相关回归由该改动负责人记录。

`tools/test_imported_building_stream_index.gd` 21项通过，另有增量索引68项与退场索引70项回归，确认合批资格不再决定建筑成员的距离可见性。

`tools/test_imported_buildings_http_20261016.gd` 在独立桌面使用临时资源库和地图，从真实HTTP入口检验组件、锁定/隐藏/隔层、共享UI、撤销重做及保存重开。最终警卫处v6／教会v8／磨坊v11共430项通过、0失败；三件实际native构建成功，放置与两次保存重开均验证native所有者，未用源GLB fallback冒充native通过。标准半径0.3m、高1.8m角色由门前平台连续进出及上楼，无跳跃、途中瞬移或碰撞例外。回执为 `review_artifacts/axel_landmarks_20261016/pipeline/http_139526127.json`。早期回执曾遇共享缓存容量不足和磨坊狭口，保留失败记录但不用于最终放行。

三栋随后通过正常 AssetLibrary 发布入共享默认库。正式目录实例直接使用正式SHA路径，另有126项HTTP检查通过，覆盖实际选择、门开合碰撞、锁定拒绝、撤销重做和保存重开，三次验证native所有者；正式库与源前后SHA不变。回执 `review_artifacts/axel_landmarks_20261016/pipeline/http_57497240.json`，发布回执分别在同批 `publication/`。这完成正式素材库使用，正式地图部署仍由布局任务负责。

逐模型资源、画质、管线、接入结论分别见三个 `docs/axel_*_model_review_20261016.md`；主地图布局由布局任务负责。
