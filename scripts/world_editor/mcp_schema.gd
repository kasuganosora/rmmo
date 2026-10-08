extends RefCounted
## The advertised contract is also validated before dispatch.
const MAX_SELECTION := 256
const MAX_PAINT_CELLS := 1024
const SNAP_VALUES := {"position_snap": [0.0, 0.01, 0.1, 0.25, 0.5, 1.0], "rotation_snap": [0.0, 1.0, 15.0, 45.0, 90.0], "scale_snap": [0.0, 0.1, 0.25, 0.5]}

static func number(low: float = -1000000.0, high: float = 1000000.0) -> Dictionary:
	return {"type": "number", "minimum": low, "maximum": high}

static func vector(dimensions: int = 3, low: float = -1000000.0, high: float = 1000000.0) -> Dictionary:
	return {"type": "array", "items": number(low, high), "minItems": dimensions, "maxItems": dimensions}

static func text_field() -> Dictionary:
	return {"type": "string", "maxLength": 2048}

static func choice(values: Array) -> Dictionary:
	return {"type": "string", "enum": values}

static func spec(name: String, description: String, properties: Dictionary = {}, required: Array = [], read_only: bool = false) -> Dictionary:
	return {"name": name, "description": description, "inputSchema": {"type": "object", "properties": properties, "required": required, "additionalProperties": false}, "annotations": {"readOnlyHint": read_only}}

static func tools() -> Array:
	var city = preload("res://scripts/world3d/city_layout.gd")
	var scatter: Dictionary=preload("res://scripts/world3d/vegetation_scatter.gd").request_schema()
	var waterways: Dictionary=preload("res://scripts/world3d/waterway_data.gd").request_schema()
	var bridges: Dictionary=preload("res://scripts/world3d/bridge_data.gd").request_schema()
	var fort: Dictionary=preload("res://scripts/world3d/fortification_data.gd").request_schema()
	var road_settings: Dictionary=preload("res://scripts/world3d/road_plan.gd").settings_schema().properties.merged({"plan_token":city.text(64)})
	var reference: Dictionary = city.reference_schema().properties.duplicate(true); reference.erase("pixel_size"); reference.remove = {"type":"boolean"}
	var ids := {"type": "array", "items": text_field(), "maxItems": MAX_SELECTION, "uniqueItems": true}
	var target := {"ids": ids, "group_id": text_field()}
	var pagination := {"query": text_field(), "offset": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}}
	var flags := target.duplicate(true)
	flags.wind = preload("res://scripts/world3d/wind_response.gd").schema()
	flags.merge({"name": text_field(), "hidden": {"type": "boolean"}, "locked": {"type": "boolean"}})
	var select := target.duplicate(true)
	select["append"] = {"type": "boolean"}
	var face := {"type": "object", "properties": {"mesh": text_field(), "surface": {"type": "integer", "minimum": 0, "maximum": 127}, "face": {"type": "integer", "minimum": 0, "maximum": 49999}, "geometry": text_field()}, "required": ["mesh", "surface", "face", "geometry"], "additionalProperties": false}
	return [
		spec("set_editor_walk_mode","切换编辑器内第三人称胶囊行走。position 可选，为待站立地面的脚点 XYZ；省略则从画布中心附近寻找。胶囊仅属于会话，保留编辑能力，不修改地图/撤销；退出恢复原视角。",{"enabled":{"type":"boolean"},"position":vector(3,-100000,100000)},["enabled"]),
		spec("move_editor_walk","驱动胶囊沿镜头水平轴行走。direction=[右,前]，各 -1～1；duration 秒，最多2秒，异步按物理帧执行，可由 editor_state.walk 查询。fast 加速、jump 跳跃；零方向可停止。与键盘共用碰撞和台阶移动。",{"direction":vector(2,-1,1),"duration":number(.01,2),"fast":{"type":"boolean"},"jump":{"type":"boolean"}},["direction","duration"]),
		spec("set_editor_walk_view","设置胶囊第三人称视角，角度为度、distance 为米；镜头遇墙自动收近。行走模式才可调用。",{"yaw":number(-360,360),"pitch":number(-75,55),"distance":number(1.5,12)}),
		spec("move_editor_camera","按世界坐标偏移平移镜头和观察中心，Y 为垂直方向；与中键键盘导航共用操作，不修改地图或撤销历史。",{"offset":vector()},["offset"]),
		spec("set_editor_wind_preview","开启或关闭本次编辑会话的风场预览，默认关闭。只控制编辑器内植被和布料受风，不修改地图风场配置、游戏效果、保存内容或撤销历史。",{"enabled":{"type":"boolean"}},["enabled"]),
		spec("get_tree_parameters","读取树木是否支持枝簇参数及当前值。仅显式带树形配方的资源支持；普通模型不按名称推断。",{"id":text_field()},["id"],true),
		spec("set_tree_parameters","修改1～32棵参数化松树的树高、冠幅/树干倍率、裸干长度、倾斜、枝簇密度和种子。settings可为部分字段。同步三级LOD，保留材质/风动；整批先验证，再一次撤销，保存与预制件保留配方。裸干须小于树高80%。",{"ids":{"type":"array","items":text_field(),"minItems":1,"maxItems":32,"uniqueItems":true},"settings":preload("res://scripts/world3d/parametric_tree.gd").schema()},["ids","settings"]),
		spec("list_rock_banks","查询可编辑岩岸、世界岸顶路径及材质。",{},[],true),
		spec("preview_rock_bank","只读校验岩岸。points为世界XYZ岸顶折线；side为沿路径方向的陆侧；height为向下岩壁落差，cap_width为草顶统一宽度，inner_widths/inner_heights为内侧逐点宽度/标高。direction_mode默认normal沿法向，fixed按cap_angle世界XZ角（0度+X，90度+Z）。固定seed可复现岩面；保护地形、物件与通道，校验实际桥梁石构而非填满桥孔的包围盒。",preload("res://scripts/world3d/rock_bank_mesh.gd").schema().properties,[],true),
		spec("set_rock_bank","新增或按id更新原生岩岸。参数同preview_rock_bank；rock_material_id/top_material_id使用PBR素材库。真实碰撞，保存保留参数，整笔校验、一次撤销。",preload("res://scripts/world3d/rock_bank_mesh.gd").schema().properties),
		spec("remove_rock_bank","删除可见未锁定的岩岸，一次撤销。",{"id":text_field()},["id"]),
		spec("set_terrain_furrows","为已有地表区域生成/修改真实农田垄沟，id 为区域ID，terrain_ids 包含关联地形。spacing/height/margin 为米，angle为世界方向（0度南北垄）；enabled=false移除垄沟，保留土壤区域。跨块统一相位、跟随地形、有碰撞；拒绝保护目标、超过20度陡坡、侵入道路/物件和超面数预算。一次撤销。",preload("res://scripts/world3d/terrain_furrows.gd").schemas().properties,["id","terrain_ids"]),
		spec("set_river_materials", "河床沙/岩PBR水深渐变；bank_profile=natural默认增加坡度露岩及三向投影，depth保留旧算法。steep_start/end为露岩角度；transition_width默认1.25米（0禁用自然交错），transition_material_id指定边缘土/碎石，缓岸草土沙按世界坐标不规则交错，陡岸保留坡度露岩；edge_noise及height_blend_strength默认0.3/0.5。terrain_ids/water_ids/bank_ids合计至少一个；bank_ids为普通护岸/渠底，保留铺砌材质与UV，只增加wet_height米水线湿痕。河床需sand_material_id/rock_material_id；wet_darkening为天然岸沙/土/岩湿润变暗程度（0～0.8，默认0关闭），wet_height控制水线上方湿痕高度，不染暗岸上草地。water_level世界水位；shore_start/end岸上恢复底材高度，rock_start/end水下沙转岩深度。水面启用深度透光，absorption控制浑浊；同选岸/床和水面时校验标高。enabled=false恢复底材。整批校验、一次撤销；锁定/隐藏/隔层或手刷河床拒绝。", preload("res://scripts/world3d/river_material_data.gd").request_schema().properties),
		spec("set_terrain_slope_materials", "普通地形从原草/土渐变到rock_material_id岩石PBR，不依赖水位。steep_start/end默认40/65度；三向投影与材质权重分离。transition_width默认1.25米（0禁用自然交错）；transition_material_id为边缘土/碎石，默认包褐色泥土；edge_noise默认0.3，height_blend_strength默认0.5，使用原材质height_path高度图。隆起/下沉/整平后即时更新覆盖。terrain_ids批量，一次撤销；enabled=false恢复底材。自然河岸已包含此能力，不叠加独立坡度配置；隐藏/锁定/隔层/手刷或非法资源整批拒绝。", preload("res://scripts/world3d/river_material_data.gd").slope_schema().properties,["terrain_ids"]),
		spec("list_terrains", "查询可雕刻地形、格距、标高范围、洞格和编辑保护状态。", {}, [], true),
		spec("create_terrain", "新建连续高度网格，或用source_id转换水平普通地面，保留UUID。新建center为原始地表中心，width/depth范围；每轴最多64格，cell_size目标格距，bedrock_depth底床深度。转换不可另传center/width/depth。支持整体PBR material_id。一次撤销。", preload("res://scripts/world3d/terrain_surface.gd").create_schema().properties),
		spec("preview_terrain_stroke", "只读预览地形笔画及碰撞/承托校验。points为世界XZ折线路径，radius米，strength每次采样米数(平滑最多1)，hardness软边0到硬边1；flatten必须提供世界target_height。hole挖穿地面与碰撞，fill补洞恢复原高度。erode只读预览保体积风化与坡脚堆积：iterations/talus_angle/erosion_seed控制迭代、稳定坡角、扰动。", preload("res://scripts/world3d/terrain_surface.gd").stroke_schema().properties,["id","mode","points"],true),
		spec("sculpt_terrain", "提交与UI相同的地形笔画：raise/lower/flatten/smooth/hole/fill/erode。erode为保体积风化，iterations默认8（1–32），talus_angle默认35度，erosion_seed默认0；strength限制单采样搬移米数，固定块边/洞边，超计算预算整笔拒绝，无运行时模拟或额外网格。整笔原子提交，一次撤销；锁定/隐藏/隔层、手刷材质或破坏现有物件承托时拒绝。支持平移/Y旋转后的地形；拒绝X/Z倾斜。", preload("res://scripts/world3d/terrain_surface.gd").stroke_schema().properties,["id","mode","points"]),
		spec("paint_terrain_region", "在多块地形上圈画 PBR 区域；polygon 为世界 XZ 米，id 稳定，同 ID 更新原区域。保留完整本地多边形及米制软边，雕刻后仍贴地，河床/陡坡优先。每块最多两种覆盖材质、32 区域和256顶点，底材另算。terrain_ids 明确目标；非相交目标不新增，原同 ID 区域被更新/清除。一次撤销，锁定/隐藏/隔层/无效区域整批拒绝。",preload("res://scripts/world3d/terrain_regions.gd").request_schema().properties,["id","terrain_ids","polygon","material_id"]),
		spec("remove_terrain_region", "从所列地形删除指定 ID 的地表区域；恢复下层覆盖，保留河岸和原地形，一次撤销。区域记录可从 list_terrains.ground_regions 查询。",{"id":text_field(),"terrain_ids":{"type":"array","items":text_field(),"minItems":1,"maxItems":64}},["id","terrain_ids"]),
		spec("set_terrain_material", "替换整块地形PBR底材（含法线），不受雕刻影响；material_id省略保留底材，空字符串恢复原色；至少提供材质或饱和度。saturation 为底材饱和度 0灰～1原色，省略保留当前值，不改变区域覆盖/河床的材质色彩。一次撤销。",{"id":text_field(),"material_id":text_field(),"saturation":number(0,1)},["id"]),
		spec("list_fortifications", "查询城墙配方、城门及手改/缺失成员。", {}, [], true),
		spec("bake_fortification", "将已有城防烘焙成固定网格预制件，保留精确碰撞、射击孔和活动门；结构不可重生成/拆件，城门仍可开合。一次撤销，保护锁定隐藏隔层及手改构件。", {"id":city.text()}, ["id"]),
		spec("bake_bridge", "将已有程序桥梁烘焙为固定网格和精确碰撞，保存道路/河道绑定，不再在加载时重建拱孔；结构材质不可修改。一次撤销，保护锁定隐藏隔层和手改绑定。", {"id":city.text(100)}, ["id"]),
		spec("preview_fortification", "只读预览连续城墙、塔楼、垛口和双扇活动门。新城墙默认style=medieval_stone（Blender写实石扶壁、压顶与拱圈），plain保留旧版；stone/trim/door_material_id覆盖三类材质。shape=path需id/points(XZ)，可closed；shape=ellipse需id，可选center_x/center_z/radius_x/radius_z/rotation/tower_count，两半径相同即圆形。城门gates含id/width/height/open；height是最低净高，至少5米（拱顶更高），墙顶至少再高0.5米，新城墙默认墙高7.5米。折线用segment/t、环形用angle(0东90南180西270北，随rotation旋转)。terrain_foundation=true允许地形在地基下延范围内承托（默认仍要求同高地面），不得让地面穿入室内；避让物件/道路净空/保留区。tower_indices可指定折线节点索引，仅这些点布塔；省略沿用每拐点布塔，空数组不布塔。最多128点，显式tower_indices的描图路径最长5000米，构件最多8192。gates.kind=water为不生成门扇的过水拱道（仅折线，宽至64米），land默认宽至32米；水关上方构件可跨越开口，仍检查实体与保留区，岸侧墙脚必须承托。新写实墙默认厚3.5米、arrow_slits/wall_access开启；interior_side控制开放路径城内侧，access_routes返回内侧门、可行走塔顶、楼内旋梯及射击孔位置；tower_door_open控制内门初始开度，城墙不设外置梯。tower_layout=automatic默认应用50米塔心禁放距离和城门10米保守净距；环形tower_count=0按tower_spacing目标(默认60米)自动减量布塔；manual手动模式不受这些布局间距约束。返回layout_zones禁放圈及实际tower_count。新圆楼有下延地基和高于地面3厘米的石铺地面，floor_material_id指定铺装。", fort.properties, fort.required, true),
		spec("generate_fortification", "共享预览参数生成城墙，支持plan_token，一次撤销；应用后自动烘焙成固定预制件，保留保护成员。已烘焙结构不能再次生成或拆件，城门仍可开合；旧配方可用 bake_fortification 转换。新写实城墙默认含 arrow_slits 圆楼外向射击孔、wall_access 内侧门/楼内旋梯/可行走塔顶；开放折线用 interior_side 指定城内侧。登墙要求墙厚≥3.2米、墙高≥7.5米并保留塔楼。tower_layout=automatic执行布局禁区并跨组检查；manual不受布局间距约束，但仍校验实体/物件保护。floor_material_id控制圆楼石铺地面，随配方保存撤销。", fort.properties, fort.required),
		spec("remove_fortification", "旧配方 keep_objects 默认 true 解除关联保留现场；固定预制件只允许 false 整体删除。隐藏/锁定/隔层保护，一次撤销。", {"id":city.text(),"keep_objects":{"type":"boolean"}}, ["id"]),
		spec("set_fortification_gate", "设置指定城墙的城门开度open(0关闭，1打开)，更新模型与碰撞并保存，一次撤销；手改/保护构件拒绝。", {"id":city.text(),"gate_id":city.text(),"open":number(0,1)}, ["id","gate_id","open"]),
		spec("connect_waterway_bridge", "将现有河道桥梁绑定为道路图的一条通行边，创建/吸附两端节点，不复制桥面。两端道路需朝桥外直向接入，绘路时端点宽度自动收至净宽。已手改/隐藏/锁定/隔层河道拒绝，一次撤销。", {"waterway_id":city.text(),"bridge_id":city.text()}, ["waterway_id","bridge_id"]),
		spec("disconnect_waterway_bridge", "解除桥梁道路绑定，保留实际桥梁及两端道路，删除无连接的端点。河道或路网受保护时拒绝，一次撤销。", {"edge_id":city.text()}, ["edge_id"]),
		spec("get_road_connectivity", "只读检查道路连通分量、断头节点、缺乏水平承托的节点、桥梁绑定、铺面过期和当前铺面方案可生成性。断头/承托提示不等于完整导航证明。", {}, [], true),
		spec("list_bridge_prefabs", "读取可选的 Blender 写实石桥模块配方和用户保存的桥型。只读。", {}, [], true),
		spec("preview_bridge", "预览两端 start/end 间的石桥。prefab_id 选择桥型，width/depth 为米，arches=0 自动拱孔数，camber=0 平桥或指定拱高；坡度最大 15%。可带 road_edge_id 将已有直线桥梁道路转换为石桥并预览旧桥板裁切；两端需在该道路内并保留至少2米引道。主通航孔硬性净高2.5米、净宽2米。auto_clearance缺省true时按实际水面自动抬拱，超过15%坡度拒绝；false仍检查硬下限。只读返回plan_token、trimmed_roads及navigation实测净空和最终camber。", bridges.properties, bridges.required, true),
		spec("generate_bridge", "按预制件生成一体石桥，长度自适应、可拱起，PBR 复用默认库，LOD/碰撞/保存同一几何。与 UI 共用校验和一次撤销；旧程序桥可同 id 更新；应用后立即烘焙成固定网格，已烘焙桥不能再修改参数或材质；旧桥可用 bake_bridge 转换。保护隐藏锁定隔层及手工刷面。road_edge_id 与原路网绑定，桥体、旧路板裁切和材质保留为同一事务；固定桥保留路网绑定及桥下净空；需要新结构时须新建桥梁。水面上的主孔净高至少2.5米、净宽2米，auto_clearance缺省true自动抬拱，false仅校验；坡度超过15%拒绝。", bridges.properties, bridges.required),
		spec("save_bridge_prefab", "将程序桥梁的桥型和材质保存为可重复选取的配方（不含现场位置或跨度）。不可变资源库文件不随地图撤销删除。", {"id":city.text(100),"name":city.text(120)},["id","name"]),
		spec("list_waterways", "读取河道配方、构件数量和手改/缺失成员。只读。", {}, [], true),
		spec("preview_waterway", "预览水平河道、两岸及所选桥型。新建需 id/points(XZ中心线)/ground_ids(普通同高地面)；同ID更新可省略未变字段。width/bank_width/bank_height/water_drop/depth；bridges指定直线段segment、t、width、approach及rail_height；可选prefab_id（石桥型或legacy_flat）和camber拱高。石桥必须满足主通航孔净高2.5米/净宽2米，此河道入口按指定拱高校验，不自动抬高。挖河替换指定地面几何，保留原始记录；拒绝现有物体与道路冲突。返回轮廓、桥头端点及plan_token。", waterways.properties, waterways.required, true),
		spec("generate_waterway", "提交河道及地面开槽，一次撤销。与UI共用预览校验，可带plan_token；手改/删除、锁定/隐藏/隔层成员阻止重生成。支持河岸、河床、桥面PBR材质ID；水面无行走碰撞。", waterways.properties, waterways.required),
		spec("remove_waterway", "keep_objects默认true解除关联保留河槽现场；false删除未改生成物并恢复原地面。手改/保护或恢复会覆盖河槽独立物件时拒绝。一次撤销。", {"id":city.text(),"keep_objects":{"type":"boolean"}}, ["id"]),
		spec("list_vegetation_scatter", "查询植被散布区域、修改/缺失成员及可选 GLB 素材。query/offset/limit 仅过滤素材。素材由使用者选择，不自动判定是否为植物。", pagination, [], true),
		spec("preview_vegetation_scatter", "只读预览水平区域植被散布。id 为区域身份，polygon 为 XZ 边界，asset_ids 来自资源库；seed/count/spacing/scale_min/scale_max/boundary_margin/height/collision 可调。完整包围盒避让物件、道路、禁植区和保留通道，需实际地面承托。返回分布、缺额、跳过统计和 plan_token。", scatter.properties, scatter.required, true),
		spec("generate_vegetation_scatter", "按相同参数创建或更新一个植被区域，一次撤销；可传 plan_token 固定预览。同种子可复现，数量不足返回 shortfall。已有成员手改/删除、隐藏/锁定/隔层时拒绝更新。", scatter.properties, scatter.required),
		spec("remove_vegetation_scatter", "解除植被区域关联，keep_objects 默认 true 保留全部现场；false 删除仍未手改的生成成员。锁定/隐藏/隔层均拒绝，一次撤销。", {"id":city.text(),"keep_objects":{"type":"boolean"}}, ["id"]),
		spec("get_city_blocks", "识别平面道路闭合街区，含曲线边界、稳定ID、保护状态和地块建筑关联；桥面不围合，断头路只作为避让。只读。", {}, [], true),
		spec("preview_block_buildings", "预览沿街矩形地块及空位建筑方案，含地块状态、入口接路、跳过原因和plan_token；block_ids省略表示全部。避让屋檐/活动门窗、已有物体、禁建区和保留通道。每批最多16栋，地块未覆盖的区域保持空白。", preload("res://scripts/world3d/city_blocks.gd").request_schema().properties, [], true),
		spec("generate_block_buildings", "只在街区空地块生成房屋，整体一次撤销；已有地块关联保持原房屋、材质和事件，删除/移动后不会自动补回。plan_token固定预览；道路边界或地块尺寸变化需先显式解除关联。", preload("res://scripts/world3d/city_blocks.gd").request_schema().properties),
		spec("detach_block_buildings", "解除指定街区的地块关联，保留房屋及其参数化建筑身份。含锁定/隐藏房屋时拒绝；可清理已消失街区关联。一次撤销。", {"block_ids":city.array(city.text(80),128,1)}, ["block_ids"]),
		spec("split_road_intersections", "拆分同层同类型道路交叉点并保留宽度/三次曲线。稳定路口ID，一次撤销；自交、重叠或受保护节点拒绝。桥下穿越不合并。", {}),
		spec("preview_road_surface", "预览道路/独立桥面的32米分块连续铺面和路口，三次曲线缓弯共用连续边缘，返回面积、增删改数量和plan_token；不改文档。支持带平坦接头的直线坡道，曲线坡道暂不支持；检查桥下净空和已有物件碰撞。省略参数沿用上次设置。kerb_enabled 开启自动外露路缘并连接同层交叉；kerb_width 为向路面内侧宽度，kerb_height 为高出路面高度，kerb_material_id 来自材质库；预览返回 kerb_length。", road_settings, [], true),
		spec("generate_road_surface", "生成或更新路面，plan_token可固定预览；一次撤销，稳定分块ID，保护锁定/隐藏构件、手刷材质及事件。material_id来自list_surface_materials，空字符串清除默认材质。自动路缘随道路增删改同步生成，桥头开口不封堵；默认关闭，旧地图不自动改变。", road_settings),
		spec("detach_road_surface", "解除铺面生成关联，保留全部实体路面与材质供手动编辑。保护构件拒绝；一次撤销。", {}),
		spec("update_planning_zones", "更新/删除编辑器保留区，expected_token使用get_city_layout.zone_token。zones为完整替换项；polygon是XZ简单多边形，min_y/max_y是世界高度。no_build与reserved_passage约束建筑生成和整栋移动；no_vegetation保留给植被散布。隐藏仍生效，受保护区域需先单独解锁显示。一次撤销。", {"expected_token":city.text(64),"zones":city.array(preload("res://scripts/world3d/planning_zones.gd").schema(),128),"remove":city.array(city.text(),128)}, ["expected_token"]),
		spec("get_city_layout", "读取编辑器城镇布局、参考图、道路图、书签、road_token、世界范围和当前相机。含zone_token、铺面生成记录与是否过期；骨架修改须显式更新铺面。", {}, [], true),
		spec("set_editor_camera", "设置公里级编辑视角。top 为北向正交俯视；center 米，span 为竖向视野米数，distance 为透视距离，最大 10000 米。仅会话视图，不改文档/撤销；需要持久化使用书签。", city.camera_schema().properties),
		spec("focus_editor_view", "按全部内容、布局、所选物件或给定世界区域适配视野，包含隐藏/锁定物件；非破坏性视图操作。region 必须给 from/to，其他 target 不可带这两个字段。", {"target":choice(["all","layout","selection","region"]),"from":vector(3,-100000,100000),"to":vector(3,-100000,100000),"projection":choice(["top","perspective"])}),
		spec("set_map_reference", "导入/调整仅编辑器可见的参考底图。path 必须在外部内容根内，PNG/JPEG/WebP <=16MiB/4096px；复制为不可变 PNG。图片中心、米/像素、Y旋转、透明度、显示和锁定随地图保存且一次撤销。锁定时只允许独立解锁或改显示/透明度；remove=true 单独移除。", reference),
		spec("calibrate_map_reference", "使用两对图片像素/同高世界坐标标定位置、等比尺度和旋转。图片原点左上，X向右/Y向下；世界XYZ米。图点至少隔4px，世界点至少隔0.1m；锁定时拒绝，一次撤销。", {"pixels":city.array(city.v2(),2,2),"world":city.array(city.S.vector(-100000,100000),2,2)}, ["pixels","world"]),
		spec("save_view_bookmark", "将当前相机保存为地图书签；id 可指定以更新已有书签，省略生成稳定ID。最多32个，一次撤销。", {"name":city.text(80),"id":city.text()}, ["name"]),
		spec("delete_view_bookmark", "删除指定书签，一次撤销。", {"id":city.text()}, ["id"]),
		spec("recall_view_bookmark", "恢复指定书签的中心、投影、视距/范围和朝向；不改地图或撤销栈。", {"id":city.text()}, ["id"]),
		spec("update_road_graph", "原子增改/删除道路节点和线段，全部使用稳定ID；expected_token 传读取时的 road_token 防止覆盖较新草案。nodes/edges 每项为完整替换；删除节点须同时显式删除连接线。支持宽度变化、三次曲线两控制柄、标高和 ground/bridge。锁定/隐藏需先单独解除；受保护线段也保护端点移动。一次撤销；已启用kerb_enabled时同层交叉及铺面/路缘一并更新，否则随后使用split_road_intersections和generate_road_surface生成路面。", {"expected_token":city.text(64),"nodes":city.array(city.node_schema(),256),"edges":city.array(city.edge_schema(),512),"remove_nodes":city.array(city.text(),256),"remove_edges":city.array(city.text(),512)}, ["expected_token"]),
		spec("create_road_path", "与画布点选共用：从XYZ点列创建连续道路骨架，端点在0.25米内复用已有节点；不会自动拆分穿越线段。保护节点拒绝连接。整笔一次撤销，返回新road_token及诊断。", {"points":city.array(city.S.vector(-100000,100000),64,2),"width":number(1,60),"kind":choice(["ground","bridge"])}, ["points"]),
		spec("preview_region_buildings", "在矩形平地区域内按种子随机规划单栋或成片建筑，避让全部已有物体，含隐藏/锁定物体；计入屋檐、阳台、雨棚和入口。只读，返回 plan_token 供确认同一方案。", preload("res://scripts/world_editor/building_region.gd").schema().properties, ["from","to"], true),
		spec("generate_region_buildings", "应用区域随机建筑方案，最多16栋且整批一次撤销；提交前再次校验碰撞。传预览的 plan_token 时方案改变会无副作用拒绝。", preload("res://scripts/world_editor/building_region.gd").schema().properties, ["from","to"]),
		spec("set_streetlamp_banner", "更换独立路灯旗帜。ids 可批量至256盏；shape=pointed/rectangle/swallowtail，design=original/plain/flag(整面图片)/emblem(透明图案)，color/trim_color 为RGB，texture_path须位于资源根目录。顶部固定并随游戏风场摆动；wind_enabled可关闭。仅改布面，不改灯杆灯罩；共用UI保护、一次撤销、保存和资源打包。", {"ids":{"type":"array","items":text_field(),"minItems":1,"maxItems":256},"settings":preload("res://scripts/world3d/streetlamp_banner.gd").schema()}, ["ids","settings"]),
		spec("list_building_templates", "查询用途默认参数、中世纪 presets、参考城镇 town_presets（十一款，包含两款三层商住楼与紧凑双层住宅）、window_styles 整栋窗口方案（casement/cross_lattice/diamond_lattice/round_arch/tall_shutter/random；random 按 seed_offset 每栋只选一次并保存解析结果）、交接屋顶 roof_presets、城中村 urban_presets 和 schema。V7 roof_solver=unified 提供最终裁切屋面、真实洞口、L/T/U 同高交接和低翼楼收口；annex_floors 控制连通翼楼层数，支持 gable/hip/shed，旧实例继续 legacy。默认 foundation_depth 向下 1 米，支持活动门窗、front_canopy 遮檐、dormers 老虎窗和七款中世纪预设。中世纪支持灰泥石墙/石基木构、timber_width 柱宽、chimney 烟囱，门窗驱动分格与连接梁柱的斜撑。城中村支持1至6层、折返楼梯、阳台及可到达屋顶；不含分租规则。内外共用洞口与标高，旧版本地图兼容。", {}, [], true),
		spec("preview_street_buildings", "只读规划平地道路中心线两侧的建筑，按实际屋檐和挑层留出道路净空，避开转角，返回确定的逐栋参数；不创建道路。", preload("res://scripts/world_editor/building_street.gd").schema().properties, ["points"], true),
		spec("generate_street_buildings", "沿道路中心线生成并烘焙至多16栋固定建筑预制件；参数含路宽、退距、间隙、侧别、宽度变化，整批校验后一次撤销；道路本身仍用地图道路工具绘制。", preload("res://scripts/world_editor/building_street.gd").schema().properties, ["points"]),
		spec("list_buildings", "列出生成建筑、参数、位置、构件数量与手工改动/锁定/楼层冲突。", {}, [], true),
		spec("list_building_components", "列出建筑的活动门、玻璃窗扇和外窗板，返回稳定组件编号、楼层、成员和开合值。", {"id":text_field()}, ["id"], true),
		spec("set_building_component_state", "设置门窗开合：open 为 0 关闭至 1 全开。整组铰接成员共同转动；锁定、隐藏和楼层保护共用 UI 校验；一次撤销并随地图保存。", {"id":text_field(),"component_id":text_field(),"open":number(0,1)}, ["id","component_id","open"]),
		spec("preview_buildings", "只读规划至多16栋建筑，检查占地与参数，返回房间/门窗/楼梯及 roof_plan 最终屋面、边线、开洞和诊断；不支持的交接会拒绝，不回退屋型。replace_id 可预览单栋参数更新，不修改地图。", preload("res://scripts/world_editor/building_tools.gd").batch_schema().properties.merged({"replace_id":text_field()}), ["placements"], true),
		spec("generate_buildings", "按统一蓝图生成并烘焙为固定预制件，保留楼层与活动门窗；新木门使用846三角面三色斜拼门板及铁饰，外门向室内开。内部不能再拆改；placements 为中心脚点/朝向/种子偏移，整批校验后一次撤销。", preload("res://scripts/world_editor/building_tools.gd").batch_schema().properties, ["placements"]),
		spec("update_building", "仅未烘焙旧建筑支持增量参数更新。固定预制件请用整栋 transform_selection 移动旋转；手改、锁定、隔层、材质拓扑冲突会无副作用拒绝。", {"id":text_field(),"parameters":preload("res://scripts/world3d/building_blueprint.gd").schema(),"position":vector(3,-100000,100000),"yaw":number(-180,180)}, ["id"]),
		spec("delete_building", "删除建筑仍由蓝图持有的构件，一次撤销；拒绝锁定/隐藏/隔层成员。", {"id":text_field()}, ["id"]),
		spec("bake_building", "将既有生成建筑烘焙成不可拆改的预制件；合并静态网格和精确碰撞，保留楼层、屋顶、活动门窗。一次撤销。新生成建筑自动烘焙。", {"id":text_field()}, ["id"]),
		spec("detach_building", "仅未烘焙的旧建筑可解除生成关联，保留构件、材质和组合；活动门窗固定为当前姿态，后续可自由手工编辑；一次撤销。", {"id":text_field()}, ["id"]),
		spec("get_editor_view", "读取楼层隔离与试玩出生脚点，配置随地图保存。", {}, [], true),
		spec("set_floor_view", "设置当前楼层高度范围及外层隐藏/淡化，范围外不可选择或直接编辑；只改变编辑视图，一次撤销。", {"isolation":{"type":"boolean"},"base_height":number(-10000,10000),"floor_height":number(.1,1000),"outside":choice(["hide","dim"])}),
		spec("set_playtest_spawn", "设置试玩出生脚点 XYZ（米），一次撤销。试玩启动时检查完整地图的支撑和胶囊空间。", {"position":vector(3,-100000,100000)}, ["position"]),
		spec("pick_playtest_spawn", "点击当前编辑画布像素位置拾取朝上的地面，设置出生脚点，一次撤销。", {"screen":vector(2,0)}, ["screen"]),
		spec("start_playtest", "启动未保存地图副本的独立试玩；不保存正式地图或角色进度。异步准备，查询 playtest_state；图形编辑器可用。可临时覆盖出生脚点，不改变文档设置。", {"position":vector(3,-100000,100000)}),
		spec("stop_playtest", "结束临时试玩并恢复原编辑器、选择、镜头和撤销历史。", {}),
		spec("playtest_state", "查询试玩准备/运行/失败/停止状态和错误。", {}, [], true),
		spec("list_event_templates", "列出 3D 事件模板、默认参数和参数 schema。复用现有事件页/命令运行逻辑。", {}, [], true),
		spec("list_event_resources", "分页查询事件可用物品和商店 ID。", pagination, [], true),
		spec("create_event_template", "在指定脚点新建事件标记，模板为对话/宝箱/采集/传送/商店，一次撤销。", {"template": choice(["dialogue", "chest", "gather", "transfer", "shop"]), "position": vector(3, -100000, 100000), "parameters": preload("res://scripts/world3d/event_templates.gd").parameters_schema()}, ["template", "position"]),
		spec("set_event_template", "为单个可编辑物件挂载或修改事件。省略 template 则沿用原类型；同类型 parameters 为增量修改，切换类型使用该类型默认值。", {"id": text_field(), "template": choice(["dialogue", "chest", "gather", "transfer", "shop"]), "parameters": preload("res://scripts/world3d/event_templates.gd").parameters_schema()}, ["id", "parameters"]),
		spec("clear_event_template", "移除所选物件的事件模板，保留物件和原有非模板数据，一次撤销。", {"id": text_field()}, ["id"]),
		spec("get_environment", "读取地图日夜、连续日月、本地湿润初值 / 积水、室内外声音、3D 天气 / 风 / 天空 / 空间雷电、主光、雾、轮廓及第三人称室内相机 / 遮挡楼层配置。返回保存的目标值，天气过渡中的瞬时显示值不写入地图。", {}, [], true),
		spec("set_environment", "修改地图环境，一次撤销。weather=clear/rain/storm/snow/fog；weather_intensity 0～1；wind_speed 0～18 米/秒；wind_direction -180～180 度（0 向 +X，90 向 +Z）；weather_transition 0～20 秒。sky_enabled 控制云层天空；cloud_altitude 200～3000 为世界云底高度，cloud_thickness 100～1800 为云厚，cloud_scale 400～8000 为云团尺度（米）；cirrus_amount 0～1 控制高空薄云。云种子与漂移沿用服务器种子、风和时间，cloud_quality 仅为客户端设置，不是本工具参数。lightning_enabled 控制世界坐标雷电；thunder_enabled 控制按距离延迟雷声，lightning_center / lightning_radius 指定落点范围。celestial_cycle 开启连续日月与光照，关闭后使用手工主光；environment_audio 控制环境声。surface_wetness 控制本地湿润，initial_wetness 0～1 是进入地图的初值，wetting_seconds 10～3600 / drying_seconds 30～7200 为响应时间，puddle_strength 0～1；实时湿润度不由服务器保存。star_intensity 0～2；meteors_enabled 夜间流星开关；meteor_frequency 0～12 次/分钟。time_hours 0～24 决定时段，time_speed 0～3600 游戏秒/秒（0 暂停）；运行时由服务器推进时间、天气、星空种子与流星事件。雨雪为世界空间碰撞粒子；编辑器预览静音，隐藏或楼层排除物件不参与编辑器遮雨，实际试玩使用完整碰撞。interior_cutaway 默认关闭；启用后只在第三人称角色室内、相机至角色射线首先击中所属建筑上方楼板/天花板时隐藏天花板和上层；无障碍、先碰墙/普通物件均不触发，第一人称/VR 禁用。indoor_camera_distance 为室内第三人称最远距离（米）；相机效果需试玩。sun_shadows 控制太阳投影，ambient_occlusion 控制接缝环境遮蔽（Forward+）。preset 填入光照，显式参数再覆盖。", preload("res://scripts/world3d/environment_settings.gd").schema().properties),
		spec("editor_state", "查询当前 3D 地图、选择、相机、变换工具、撤销及服务能力，以及 ground_batching 地面、fortification_batching 静态城防渲染、fortification_collision_batching 静态城防碰撞分块统计和构建耗时；包含 sync_count/release_groups_visited 与有界 shape_cache 命中/容量统计。活动门独立，选取和原始三角面碰撞保留，派生缓存不改编辑记录。单位米，Y 向上。", {}, [], true),
		spec("list_objects", "分页查询当前地图所有楼层的物件及组合，包括隐藏/锁定状态及 in_current_floor。", pagination, [], true),
		spec("get_object", "读取完整可编辑记录及 wind_meshes（受风网格路径、支持状态和原因）。", {"id": text_field()}, ["id"], true),
		spec("select_objects", "按 ids 选择物件，生成建筑默认扩展为整栋；component_edit 开启后可精确选择构件。或按 group_id 选择整组。空 ids 清空选择，append 追加。", select),
		spec("select_rectangle", "使用 3D 画布像素坐标框选完整落在矩形内的物件，行为与 B 框选一致。", {"from": vector(2, 0), "to": vector(2, 0), "append": {"type": "boolean"}}, ["from", "to"]),
		spec("configure_transform", "切换 W/R/T 工具、世界/局部轴和吸附；不会修改物件。多选使用世界轴；整栋建筑仅 XYZ 移动和 Y 轴旋转，component_edit 显式开启单构件编辑。", {"component_edit":{"type":"boolean"}, "mode": choice(["move", "rotate", "scale"]), "space": choice(["world", "local"]), "position_snap": {"type": "number", "enum": SNAP_VALUES.position_snap}, "rotation_snap": {"type": "number", "enum": SNAP_VALUES.rotation_snap}, "scale_snap": {"type": "number", "enum": SNAP_VALUES.scale_snap}}),
		spec("set_object_transform", "精确设置单物件位置/欧拉角(度)/尺寸；asset 的 size 是缩放倍率。不吸附，一次撤销。", {"id": text_field(), "position": vector(), "rotation": vector(), "size": vector(3, 0.001, 100000)}, ["id"]),
		spec("transform_selection", "绕共同中心对当前选择做世界轴平移、欧拉旋转(度)及等比缩放，一次撤销。整栋建筑仅平移/Y 旋转，检查占地冲突并同步配方，最多 16 栋。", {"translation": vector(), "rotation": vector(), "scale": number(0.001, 1000)}),
		spec("drop_selection", "当前选择向下贴地，可贴合坡面。完整组合整体移动；排除所选物件，任一物件未找到支撑则全部不修改，一次撤销。", {"align_normal": {"type": "boolean"}, "max_distance": number(0.01, 10000), "offset": number(0, 100)}),
		spec("snap_selection_to_surface", "点选画布像素坐标处的真实表面；整份选择作为整体移到表面，可贴合法线。排除自身，不使用虚拟地平面。", {"screen": vector(2, 0), "align_normal": {"type": "boolean"}, "offset": number(0, 100)}, ["screen"]),
		spec("align_selection", "沿世界 XYZ 轴按包围盒边缘/中心对齐到最后选中物件或组合。完整组视为一个单位；至少两个单位，一次撤销。", {"axis": choice(["x", "y", "z"]), "anchor": choice(["min", "center", "max"])}, ["axis"]),
		spec("distribute_selection", "沿世界 XYZ 轴保持两端固定，等中心距离或等边缘间隙分布；至少三个物件/完整组合，间隙不足则拒绝，一次撤销。", {"axis": choice(["x", "y", "z"]), "spacing": choice(["centers", "gaps"])}, ["axis"]),
		spec("group_selection", "将当前选择成组，复用 UI 分组操作。", {}),
		spec("ungroup_selection", "解开当前选择涉及的组合，拒绝含隐藏或锁定成员的组合。", {}),
		spec("duplicate_selection", "复制当前选择，生成独立成员及组 ID，一次撤销；整栋建筑保留独立配方，并自动寻找附近空地，找不到则无副作用失败。", {}),
		spec("delete_selection", "删除当前选择，自动修复瓦片邻接，一次撤销。", {}),
		spec("set_object_properties", "修改名称、编辑器隐藏或锁定；wind 独立事务设置柔性物件受风（不能混合 name/hidden/locked）。wind.profile=off/foliage/cloth；mesh 使用 get_object.wind_meshes 路径或 *；amplitude 为米，anchor 为局部固定边。按 ids/group_id 定位，否则使用当前选择；组合名称需 group_id。", flags),
		spec("focus_selection", "将相机聚焦到当前选择。", {}),
		spec("list_building_windows", "查询单栋房屋的独立窗户及可替换窗扇样式；双扇窗按同一洞口列出。", {"building_id":text_field()}, ["building_id"], true),
		spec("set_building_window_style", "手动替换一个完整窗口的窗扇格栅（casement/cross_lattice/diamond_lattice），保留现有洞口、固定外框、铰链状态及其他窗户，一次撤销。自动生成仍为整栋统一窗型。", {"building_id":text_field(),"window_id":text_field(),"style":choice(["casement","cross_lattice","diamond_lattice"])}, ["building_id","window_id","style"]),
		spec("list_assets", "分页检索当前及共享资源库，含内置模块、GLB、预制件；category 精确筛选，query 搜索名称和分类。返回全部 categories、稳定 asset_id 和缩略图状态，与素材面板分类共用筛选。", pagination.merged({"category":text_field()}), [], true),
		spec("repair_asset_thumbnails","为已有模型/预制件重新排队生成缩略图；失败后可重试，状态从 list_assets 查询。需要图形编辑器，不修改地图。",{"asset_ids":{"type":"array","items":text_field(),"minItems":1,"maxItems":64,"uniqueItems":true}},["asset_ids"]),
		spec("list_resource_packs", "列出资源包及各包 maps（名称、原始路径）；默认包包含内容根 maps 下的既有地图。", {}, [], true),
		spec("save_prefab", "把当前选择保存到素材库并打包依赖。烘焙房屋必须整栋选择，保持固定结构、活动门窗和建筑身份；普通物件仍保存可编辑快照。pack_root 必须来自 list_resource_packs。", {"name": text_field(), "pack_root": text_field()}, ["name", "pack_root"]),
		spec("place_asset", "放置 list_assets 返回的模型/模块/预制件；position 为表面落点，预制件保持独立组与成员。自动模块请用 paint_auto_tiles。", {"asset_id": text_field(), "position": vector()}, ["asset_id", "position"]),
		spec("paint_auto_tiles", "连续画/擦道路、墙、草土水、高台、楼梯、屋顶、桥栏杆。高台 height 为顶面，base_height 为基底，同基底重刷调整高差；楼梯/屋顶 rise 为升高，direction 0北1东2南3西；桥 rail_height 为栏杆高度。kit_id 来自套件列表。固定格宽，最多1024格，一笔撤销。", {"family": choice(preload("res://scripts/world3d/auto_tile_rules.gd").FAMILIES), "points": {"type": "array", "items": vector(), "minItems": 1, "maxItems": 256}, "cell_size": {"type": "number", "enum": [1, 2, 4, 8]}, "height": number(-1000, 1000), "erase": {"type": "boolean"}, "base_height": number(-1000, 1000), "rise": number(.1, 8), "direction": {"type": "integer", "minimum": 0, "maximum": 3}, "rail_height": number(.3, 3), "kit_id": text_field()}, ["family", "points"]),
		spec("list_auto_tile_kits", "列出已导入的自动拼接模型套件，含 kit_id、类型和变体数。", {}, [], true),
		spec("import_auto_tile_kit", "导入资源根内的 JSON 套件清单。静态 GLB 必须内嵌依赖，验证全部邻接变体后复制进独立库。", {"path": text_field()}, ["path"]),
		spec("undo", "撤销最近一笔 UI 或 MCP 地图修改。", {}),
		spec("redo", "重做最近撤销的地图修改。", {}),
		spec("save_world", "原子保存引用地图 v2：模型/预制件独立保存，地图写资源引用、位置、旋转、缩放及实例状态，通用 glTF 工具显示定位方块。移动、增删均不导出整图材质贴图；返回 timings.export.mode=reference_map、resources_written/resources_reused、images_written=0。默认等完成返回 saved；background=true 返回 pending/job_id，通过 editor_state.save 查询进度与结果；保存期间拒绝修改。", {"path": text_field(), "background": {"type":"boolean"}}),
		spec("open_world", "分阶段打开内容根内的引用地图 v2；旧内嵌地图先使用迁移工具转换。后台校验并恢复独立资源，记录校验分帧，模型解析、地形CPU几何与地形/冻结预制件贴图准备在后台，拾取三角数组在后台准备、逐网格分帧发布；场景与物理资源创建仍在主线程。picking 阶段显示准备拾取碰撞。editor_state.load 查询进度、timings.validation 校验耗时与timings.build构建/后台准备耗时。单个复杂记录、末尾文件校验仍不可抢占。默认 HTTP 等待完成，background=true 返回作业编号；加载期间拒绝修改，失败保留原文档。有未保存修改时需显式 discard_changes。", {"path": text_field(), "discard_changes": {"type": "boolean"},"background":{"type":"boolean"}}, ["path"]),
		spec("preview_map", "返回当前 3D 画布最近渲染帧 PNG。include_layout=true 包含参考底图、道路骨架、概览及编辑辅助；试玩仍只返回游戏视图。headless 无图形时明确报错。", {"include_layout":{"type":"boolean"}}, [], true),
		spec("configure_autosave", "设置本次编辑会话的自动草稿；默认开启，每 60 秒保存已结束的编辑事务。正式地图不变。", {"enabled": {"type": "boolean"}, "interval_seconds": number(15, 600)}),
		spec("list_editor_drafts", "分页查询所有地图的恢复草稿、来源路径和磁盘版本变化；校验正文发生在恢复时。", {"offset": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 100}}, [], true),
		spec("save_editor_draft", "立即保存当前编辑文档的独立恢复草稿，不覆盖正式 glTF，不清除未保存标记。", {}),
		spec("restore_editor_draft", "按草稿 ID 恢复到编辑器内存。当前有修改时需 discard_changes=true，会先备份当前内容。同图可撤销；磁盘冲突仍禁止覆盖保存。", {"draft_id": text_field(), "discard_changes": {"type": "boolean"}}, ["draft_id"]),
		spec("discard_editor_draft", "删除指定恢复草稿及其上一版，不修改当前地图。", {"draft_id": text_field()}, ["draft_id"]),
		spec("close_editor", "保存、保留草稿或放弃修改后关闭当前编辑器进程；cancel 取消待关闭提示。仅在用户明确要求关闭时使用。", {"action": choice(["save", "keep_draft", "discard", "cancel"])}, ["action"]),
		spec("list_surface_materials", "分页查询默认资源包的分类 PBR 材质、导入材质及内置材质；category 精确筛选，query 搜索名称/分类/ID。返回全部 categories、稳定 material_id 和各贴图路径。", pagination.merged({"category":text_field()}), [], true),
		spec("import_surface_material", "复制内容根内的 PNG/JPEG/WebP 到独立材质库；最大 4096x4096、16 MiB，源文件保持不变。", {"path": text_field(), "name": text_field()}, ["path"]),
		spec("list_object_surfaces", "查询物件的连通共平面区域及当前材质覆盖。返回稳定 target 和世界坐标 center/normal；最多 200 项。", {"id": text_field(), "offset": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}}, ["id"], true),
		spec("pick_surface", "从 3D 画布像素拾取最近的可编辑平面，返回 id/target；锁定、隐藏和蒙皮模型不可绘制。", {"screen": vector(2, 0)}, ["screen"], true),
		spec("paint_surface", "给物件一个平面刷材质，一次撤销，含 PBR 法线/粗糙度/金属度/AO。target 来自拾取或面列表；mapping=meters 按材质 tile_size 米铺设，planar 整面归一化，uv 原 UV。scale 为重复倍率，rotation 为度；自动瓦片冻结造型。", {"id": text_field(), "target": face, "material_id": text_field(), "mapping": choice(["planar", "uv", "meters"]), "scale": vector(2, 0.01, 100), "rotation": number(-3600, 3600), "offset": vector(2, -100, 100)}, ["id", "target", "material_id"]),
		spec("clear_surface_material", "恢复一个面的原材质；省略 target 则恢复该物件全部原材质，支持撤销。", {"id": text_field(), "target": face}, ["id"]),
	]

static func validate(value: Variant, schema: Dictionary, path: String = "arguments") -> String:
	match schema.get("type", ""):
		"object":
			if not value is Dictionary: return path + " must be an object"
			for key in schema.get("required", []):
				if not value.has(key): return path + "." + str(key) + " is required"
			for key in value:
				if not schema.properties.has(key): return path + "." + str(key) + " is not supported"
				var error := validate(value[key], schema.properties[key], path + "." + str(key))
				if not error.is_empty(): return error
		"array":
			if not value is Array: return path + " must be an array"
			if value.size() < int(schema.get("minItems", 0)) or value.size() > int(schema.get("maxItems", 256)): return path + " has invalid length"
			var seen: Array = []
			for index in value.size():
				if schema.get("uniqueItems", false) and seen.has(value[index]): return path + " contains duplicate entries"
				seen.append(value[index])
				var error := validate(value[index], schema.items, path + "[%d]" % index)
				if not error.is_empty(): return error
		"string":
			if not value is String or value.length() > int(schema.get("maxLength", 2048)): return path + " must be a bounded string"
		"boolean":
			if not value is bool: return path + " must be a boolean"
		"number", "integer":
			if not (value is int or value is float) or not is_finite(float(value)): return path + " must be a finite number"
			if schema.type == "integer" and value != floor(value): return path + " must be an integer"
			if value < schema.get("minimum", -INF) or value > schema.get("maximum", INF): return path + " is out of range"
	# JSON numbers arrive as floats; numeric enum equality must accept 4 and 4.0.
	if schema.has("enum") and not schema.enum.any(func(option): return option == value): return path + " has an unsupported value"
	return ""
