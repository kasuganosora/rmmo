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
	var ids := {"type": "array", "items": text_field(), "maxItems": MAX_SELECTION, "uniqueItems": true}
	var target := {"ids": ids, "group_id": text_field()}
	var pagination := {"query": text_field(), "offset": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}}
	var flags := target.duplicate(true)
	flags.merge({"name": text_field(), "hidden": {"type": "boolean"}, "locked": {"type": "boolean"}})
	var select := target.duplicate(true)
	select["append"] = {"type": "boolean"}
	var face := {"type": "object", "properties": {"mesh": text_field(), "surface": {"type": "integer", "minimum": 0, "maximum": 127}, "face": {"type": "integer", "minimum": 0, "maximum": 49999}, "geometry": text_field()}, "required": ["mesh", "surface", "face", "geometry"], "additionalProperties": false}
	return [
		spec("preview_region_buildings", "在矩形平地区域内按种子随机规划单栋或成片建筑，避让全部已有物体，含隐藏/锁定物体；计入屋檐、阳台、雨棚和入口。只读，返回 plan_token 供确认同一方案。", preload("res://scripts/world_editor/building_region.gd").schema().properties, ["from","to"], true),
		spec("generate_region_buildings", "应用区域随机建筑方案，最多16栋且整批一次撤销；提交前再次校验碰撞。传预览的 plan_token 时方案改变会无副作用拒绝。", preload("res://scripts/world_editor/building_region.gd").schema().properties, ["from","to"]),
		spec("list_building_templates", "查询用途默认参数、中世纪 presets、城中村家庭/底商住宅 urban_presets 和 schema。城中村支持1至6层、折返楼梯、阳台及可到达屋顶；不含分租规则。内外共用洞口与标高，旧版本地图兼容。", {}, [], true),
		spec("preview_street_buildings", "只读规划平地道路中心线两侧的建筑，按实际屋檐和挑层留出道路净空，避开转角，返回确定的逐栋参数；不创建道路。", preload("res://scripts/world_editor/building_street.gd").schema().properties, ["points"], true),
		spec("generate_street_buildings", "沿道路中心线生成至多16栋建筑；参数含路宽、退距、间隙、侧别、宽度变化，整批校验后一次撤销；道路本身仍用地图道路工具绘制。", preload("res://scripts/world_editor/building_street.gd").schema().properties, ["points"]),
		spec("list_buildings", "列出生成建筑、参数、位置、构件数量与手工改动/锁定/楼层冲突。", {}, [], true),
		spec("preview_buildings", "只读规划至多16栋建筑，检查占地与参数，返回房间/门窗/楼梯布局和数量；replace_id 可预览单栋参数更新，不修改地图。", preload("res://scripts/world_editor/building_tools.gd").batch_schema().properties.merged({"replace_id":text_field()}), ["placements"], true),
		spec("generate_buildings", "按统一蓝图生成外观和可通行内部结构；placements 为中心脚点/朝向/种子偏移，整批校验后一次撤销。", preload("res://scripts/world_editor/building_tools.gd").batch_schema().properties, ["placements"]),
		spec("update_building", "增量修改建筑参数或整体位置/朝向，保留稳定构件身份；手改、锁定、隔层、材质拓扑冲突会无副作用拒绝。", {"id":text_field(),"parameters":preload("res://scripts/world3d/building_blueprint.gd").schema(),"position":vector(3,-100000,100000),"yaw":number(-180,180)}, ["id"]),
		spec("delete_building", "删除建筑仍由蓝图持有的构件，一次撤销；拒绝锁定/隐藏/隔层成员。", {"id":text_field()}, ["id"]),
		spec("detach_building", "解除生成关联，保留所有现有构件、材质和组合，后续可自由手工编辑；一次撤销。", {"id":text_field()}, ["id"]),
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
		spec("get_environment", "读取地图日夜、主光、环境光、雾及人物遮挡轮廓配置。", {}, [], true),
		spec("set_environment", "修改地图环境并实时预览，一次撤销。preset 填入时段光照，其他显式参数覆盖推荐值。", preload("res://scripts/world3d/environment_settings.gd").schema().properties),
		spec("editor_state", "查询当前 3D 地图、选择、相机、变换工具、撤销及服务能力。单位米，Y 向上。", {}, [], true),
		spec("list_objects", "分页查询当前地图所有楼层的物件及组合，包括隐藏/锁定状态及 in_current_floor。", pagination, [], true),
		spec("get_object", "读取一个物件的完整可编辑记录。", {"id": text_field()}, ["id"], true),
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
		spec("set_object_properties", "修改名称、编辑器隐藏或锁定。按 ids/group_id 定位，否则使用当前选择；组合名称需 group_id。", flags),
		spec("focus_selection", "将相机聚焦到当前选择。", {}),
		spec("list_assets", "分页检索当前及共享资源库，含内置模块、GLB、预制件；返回稳定 asset_id。", pagination, [], true),
		spec("list_resource_packs", "列出可保存预制件的资源包。", {}, [], true),
		spec("save_prefab", "把当前选择保存为可编辑预制件，打包引用模型；pack_root 必须来自 list_resource_packs。", {"name": text_field(), "pack_root": text_field()}, ["name", "pack_root"]),
		spec("place_asset", "放置 list_assets 返回的模型/模块/预制件；position 为表面落点，预制件保持独立组与成员。自动模块请用 paint_auto_tiles。", {"asset_id": text_field(), "position": vector()}, ["asset_id", "position"]),
		spec("paint_auto_tiles", "连续画/擦道路、墙、草土水、高台、楼梯、屋顶、桥栏杆。高台 height 为顶面，base_height 为基底，同基底重刷调整高差；楼梯/屋顶 rise 为升高，direction 0北1东2南3西；桥 rail_height 为栏杆高度。kit_id 来自套件列表。固定格宽，最多1024格，一笔撤销。", {"family": choice(preload("res://scripts/world3d/auto_tile_rules.gd").FAMILIES), "points": {"type": "array", "items": vector(), "minItems": 1, "maxItems": 256}, "cell_size": {"type": "number", "enum": [1, 2, 4, 8]}, "height": number(-1000, 1000), "erase": {"type": "boolean"}, "base_height": number(-1000, 1000), "rise": number(.1, 8), "direction": {"type": "integer", "minimum": 0, "maximum": 3}, "rail_height": number(.3, 3), "kit_id": text_field()}, ["family", "points"]),
		spec("list_auto_tile_kits", "列出已导入的自动拼接模型套件，含 kit_id、类型和变体数。", {}, [], true),
		spec("import_auto_tile_kit", "导入资源根内的 JSON 套件清单。静态 GLB 必须内嵌依赖，验证全部邻接变体后复制进独立库。", {"path": text_field()}, ["path"]),
		spec("undo", "撤销最近一笔 UI 或 MCP 地图修改。", {}),
		spec("redo", "重做最近撤销的地图修改。", {}),
		spec("save_world", "保存当前地图，或另存到授权内容根内的 glTF 路径。", {"path": text_field()}),
		spec("open_world", "打开授权内容根内的 glTF 地图；有未保存修改时需显式 discard_changes。", {"path": text_field(), "discard_changes": {"type": "boolean"}}, ["path"]),
		spec("preview_map", "返回当前 3D 画布最近渲染帧 PNG；headless 无图形时明确报错。", {}, [], true),
		spec("configure_autosave", "设置本次编辑会话的自动草稿；默认开启，每 60 秒保存已结束的编辑事务。正式地图不变。", {"enabled": {"type": "boolean"}, "interval_seconds": number(15, 600)}),
		spec("list_editor_drafts", "分页查询所有地图的恢复草稿、来源路径和磁盘版本变化；校验正文发生在恢复时。", {"offset": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 100}}, [], true),
		spec("save_editor_draft", "立即保存当前编辑文档的独立恢复草稿，不覆盖正式 glTF，不清除未保存标记。", {}),
		spec("restore_editor_draft", "按草稿 ID 恢复到编辑器内存。当前有修改时需 discard_changes=true，会先备份当前内容。同图可撤销；磁盘冲突仍禁止覆盖保存。", {"draft_id": text_field(), "discard_changes": {"type": "boolean"}}, ["draft_id"]),
		spec("discard_editor_draft", "删除指定恢复草稿及其上一版，不修改当前地图。", {"draft_id": text_field()}, ["draft_id"]),
		spec("close_editor", "保存、保留草稿或放弃修改后关闭当前编辑器进程；cancel 取消待关闭提示。仅在用户明确要求关闭时使用。", {"action": choice(["save", "keep_draft", "discard", "cancel"])}, ["action"]),
		spec("list_surface_materials", "分页查询独立表面材质库，含内置白色与棋盘格；返回 material_id 供刷面使用。", pagination, [], true),
		spec("import_surface_material", "复制内容根内的 PNG/JPEG/WebP 到独立材质库；最大 4096x4096、16 MiB，源文件保持不变。", {"path": text_field(), "name": text_field()}, ["path"]),
		spec("list_object_surfaces", "查询物件的连通共平面区域及当前材质覆盖。返回稳定 target 和世界坐标 center/normal；最多 200 项。", {"id": text_field(), "offset": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}}, ["id"], true),
		spec("pick_surface", "从 3D 画布像素拾取最近的可编辑平面，返回 id/target；锁定、隐藏和蒙皮模型不可绘制。", {"screen": vector(2, 0)}, ["screen"], true),
		spec("paint_surface", "给物件一个平面刷材质，一次撤销。target 来自拾取或面列表；保留其他面及原模型。scale 为横纵重复倍率，rotation 为度；自动瓦片冻结造型。", {"id": text_field(), "target": face, "material_id": text_field(), "mapping": choice(["planar", "uv"]), "scale": vector(2, 0.01, 100), "rotation": number(-3600, 3600), "offset": vector(2, -100, 100)}, ["id", "target", "material_id"]),
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
