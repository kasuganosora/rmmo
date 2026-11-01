extends RefCounted
## Shared UI / current 3D MCP operations. Catalog history never edits the map.
const Catalog = preload("res://scripts/world_editor/world_map_catalog.gd")
const Address = preload("res://scripts/world3d/world_address.gd")
var editor: Node3D
var catalog: RefCounted

func _init(owner: Node3D = null, content_root: String = "") -> void:
	editor = owner
	catalog = Catalog.new(content_root)

static func _text(maximum: int = 2048) -> Dictionary:
	return {"type":"string", "maxLength":maximum}

static func _spec(name_: String, description: String, properties: Dictionary, required: Array = [], read_only: bool = false) -> Dictionary:
	return {"name":name_, "description":description, "inputSchema":{"type":"object", "properties":properties, "required":required, "additionalProperties":false}, "annotations":{"readOnlyHint":read_only}}

static func tool_specs() -> Array:
	var revision := {"type":"integer", "minimum":0, "maximum":9007199254740991}
	var document := {"document_id":_text(), "expected_edit_revision":revision}
	var document_required := ["document_id", "expected_edit_revision"]
	return [
		_spec("list_world_maps", "列出资源包的稳定数字地图编号、未登记入口及独立目录文档修订。只读，不自动编号或改地图；pack_root 只能选择已发现的资源包版本。", {"pack_id":_text(128), "pack_root":_text(), "offset":{"type":"integer","minimum":0,"maximum":9007199254740991}, "limit":{"type":"integer","minimum":1,"maximum":500}}, [], true),
		_spec("register_world_map", "为已发现的地图入口显式登记稳定数字编号，保留原文件名和 map_ref。一笔目录撤销，需另行 save_world_catalog；不修改地图内容。", {"entry_id":_text(), "map_number":_text(19), "expected_edit_revision":revision}, ["entry_id","map_number","expected_edit_revision"]),
		_spec("save_world_catalog", "原子保存指定编号目录。同时验证编辑修订和磁盘 SHA；首次保存 expected_disk_sha 为空。只保存目录，不代存地图。", document.merged({"expected_disk_sha":_text(64)}), document_required + ["expected_disk_sha"]),
		_spec("undo_world_edit", "按文档句柄撤销编号目录或世界布局的一笔修改；目录保留编号占用，不影响当前地图 undo/redo。", document, document_required),
		_spec("redo_world_edit", "按文档句柄重做编号目录或世界布局的一笔修改，不影响当前地图历史。", document, document_required),
		_spec("discard_world_catalog", "显式放弃指定目录的未保存修改并重新校验读取磁盘目录；不会删除目录或修改地图。", document, document_required),
		_spec("resolve_world_address", "只读解析 资源包:数字地图ID:x,y,z；可通过 document_id 指定世界布局，再用 space_id/placement_id 消除歧义，返回连续空间坐标和归属。未提供布局时只解析地图内地址。每轴±1e12米；不贴地、不移动、不授予通行。", {"address":_text(Address.MAX_ADDRESS_LENGTH), "pack_root":_text(),"document_id":_text(),"space_id":_text(128),"placement_id":_text(128), "anchor_kind":{"type":"string","enum":["point","feet","object_origin"]}}, ["address"], true),
		_spec("get_current_world_address", "读取单个物件作者原点或实际胶囊脚点地址。只读；可指定世界布局 document_id 及 space_id/placement_id 获得连续空间位置。共享地图的包版本须唯一或显式指定。", {"anchor_kind":{"type":"string","enum":["object_origin","feet"]}, "object_id":_text(), "pack_root":_text(),"document_id":_text(),"space_id":_text(128),"placement_id":_text(128)}, [], true),
	]

static func _failure(code: String, message: String) -> Dictionary:
	return {"ok":false, "reason_code":code, "message":message, "error":message}

func _validate(name_: String, args: Dictionary, writing: bool = false) -> Dictionary:
	for definition: Dictionary in tool_specs():
		if definition.name != name_: continue
		var error: String = load("res://scripts/world_editor/mcp_schema.gd").validate(args, definition.inputSchema)
		if not error.is_empty(): return _failure("invalid_arguments", error)
		break
	return guard_write() if writing else {"ok":true}

func guard_write() -> Dictionary:
	if not is_instance_valid(editor): return _failure("editor_unavailable", "编辑器尚未就绪。")
	if editor.saving() or editor._load_failed: return _failure("editor_busy", "地图正在读取、保存或处于只读状态。")
	if editor._playtest != null and editor._playtest.active(): return _failure("editor_busy", "请先结束试玩再修改世界配置。")
	if editor._city.busy() or editor._authoring.picking or editor._building_area_busy(): return _failure("editor_busy", "请先完成或取消当前编辑操作。")
	if editor._safety != null and editor._safety.state().close_pending: return _failure("editor_busy", "请先处理当前地图关闭提示。")
	if editor._gravity.falling or editor._transform_drag.active or editor._auto_stroke.active or editor._selection_tools.marquee or editor._stroke._open or editor._placement_tools.active or editor._material_tool.active or (editor._terrain_brush != null and editor._terrain_brush.active):
		return _failure("editor_busy", "请先完成当前拖拽或笔画。")
	return {"ok":true}

func list_maps(args: Dictionary = {}) -> Dictionary:
	var checked := _validate("list_world_maps", args)
	if not checked.ok: return checked
	var result: Dictionary = catalog.list_maps(args.get("pack_id", ""), args.get("pack_root", ""))
	if result.get("ok", false):
		result.total = result.maps.size()
		if args.has("offset") or args.has("limit"):
			var offset: int = int(args.get("offset", 0))
			result.maps = result.maps.slice(offset, offset + int(args.get("limit", 100)))
	return result

func register_map(args: Dictionary) -> Dictionary:
	var checked := _validate("register_world_map", args, true)
	return checked if not checked.ok else catalog.register_map(args.entry_id, args.map_number, int(args.expected_edit_revision))

func save_catalog(args: Dictionary) -> Dictionary:
	var checked := _validate("save_world_catalog", args, true)
	return checked if not checked.ok else catalog.save_catalog(args.document_id, int(args.expected_edit_revision), args.expected_disk_sha)

func undo_catalog(args: Dictionary) -> Dictionary:
	var checked := _validate("undo_world_edit", args, true)
	if checked.ok and str(args.document_id).begins_with("layout:") and editor._world_layout_tools != null: return editor._world_layout_tools.undo_layout(args)
	return checked if not checked.ok else catalog.undo_catalog(args.document_id, int(args.expected_edit_revision))

func redo_catalog(args: Dictionary) -> Dictionary:
	var checked := _validate("redo_world_edit", args, true)
	if checked.ok and str(args.document_id).begins_with("layout:") and editor._world_layout_tools != null: return editor._world_layout_tools.redo_layout(args)
	return checked if not checked.ok else catalog.redo_catalog(args.document_id, int(args.expected_edit_revision))

func discard_catalog(args: Dictionary) -> Dictionary:
	var checked := _validate("discard_world_catalog", args, true)
	return checked if not checked.ok else catalog.discard_catalog(args.document_id, int(args.expected_edit_revision))

func resolve_address(args: Dictionary) -> Dictionary:
	var checked := _validate("resolve_world_address", args)
	if not checked.ok: return checked
	if args.has("document_id"):
		if not is_instance_valid(editor) or editor._world_layout_tools == null: return _failure("layout_unavailable","世界布局服务尚未就绪。")
		if args.has("pack_root"): return _failure("invalid_arguments","世界布局已固定包版本，不能同时指定 pack_root。")
		return editor._world_layout_tools.resolve_address(args)
	if args.has("space_id") or args.has("placement_id"): return _failure("invalid_arguments","空间与放置筛选需要世界布局 document_id。")
	var result: Dictionary = catalog.resolve_address(args.address, args.get("pack_root", ""))
	if result.get("ok", false):
		result.anchor_kind = args.get("anchor_kind", "point")
		result.validation = "address_only"
		result.surface_id = null
		result.world_position_available = false
	return result

func current_address(args: Dictionary = {}) -> Dictionary:
	var checked := _validate("get_current_world_address", args)
	if not checked.ok: return checked
	if not is_instance_valid(editor) or editor._doc == null or editor.saving(): return _failure("editor_unavailable", "当前地图尚未就绪。")
	var kind: String = args.get("anchor_kind", "feet" if editor._walk_mode != null and editor._walk_mode.active else "object_origin")
	var position: Array = []
	var object_id: String = ""
	if kind == "feet":
		if args.has("object_id"): return _failure("invalid_arguments", "脚点地址不能指定物件。")
		if editor._walk_mode == null or not editor._walk_mode.active: return _failure("walk_inactive", "请先开启胶囊行走以读取实际脚点。")
		var feet: Dictionary = Address.feet_from_body(editor._walk_mode.body)
		if not feet.ok: return feet
		position = feet.position_m
	else:
		object_id = args.get("object_id", "")
		if object_id.is_empty():
			if editor._selection_tools.ids.size() != 1: return _failure("selection_ambiguous", "请选择一个物件以读取作者原点地址。")
			object_id = editor._selection_tools.ids[0]
		var record: Dictionary = editor._doc._find(object_id)
		if record.is_empty(): return _failure("object_not_found", "所选物件不存在。")
		position = record.get("position", []).duplicate()
	var result: Dictionary
	if args.has("document_id"):
		if args.has("pack_root"): return _failure("invalid_arguments","世界布局已固定包版本，不能同时指定 pack_root。")
		var layout: Dictionary = editor._world_layout_tools.get_layout({"document_id":args.document_id})
		if not layout.ok: return layout
		if layout.document.get("read_only",false) or layout.document.get("disk_conflict",false): return _failure(layout.document.get("reason_code","layout_conflict"),layout.document.get("message","布局来源已变化，请重新载入。"))
		var bindings: Array = layout.bindings.filter(func(binding): return Catalog._path_key(binding.path) == Catalog._path_key(editor._path) and (not args.has("space_id") or binding.space_id == args.space_id) and (not args.has("placement_id") or binding.placement_id == args.placement_id))
		if bindings.size() != 1: return _failure("ambiguous_context" if bindings.size()>1 else "map_not_in_layout","当前地图在指定布局中的放置必须唯一；请检查空间和放置筛选。")
		var formatted := Address.format_address(bindings[0].pack_id,bindings[0].map_number,position)
		if not formatted.ok: return formatted
		result = editor._world_layout_tools.resolve_address({"document_id":args.document_id,"address":formatted.address,"space_id":bindings[0].space_id,"placement_id":bindings[0].placement_id,"anchor_kind":kind})
	else:
		if args.has("space_id") or args.has("placement_id"): return _failure("invalid_arguments","空间与放置筛选需要世界布局 document_id。")
		result = catalog.format_map_address(editor._path, position, args.get("pack_root", ""))
	if not result.get("ok", false): return result
	var authored_ref: String = str(editor._doc.map_meta.get("map_ref", ""))
	if not authored_ref.is_empty() and authored_ref != result.get("map_ref", ""):
		return _failure("map_identity_changed", "当前地图身份与编号目录不一致，请先重新核对登记。")
	result.anchor_kind = kind
	result.object_id = object_id
	if not args.has("document_id"):
		result.validation = "address_only"
		result.world_position_available = false
	return result

func state() -> Dictionary:
	var documents: Array = catalog.cached_documents()
	return {"phase":"D1", "documents":documents, "dirty":documents.any(func(doc): return doc.get("dirty", false)), "world_layout_available":is_instance_valid(editor) and editor._world_layout_tools != null}

func has_dirty_catalogs() -> bool:
	return state().dirty
