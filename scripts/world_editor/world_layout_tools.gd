extends RefCounted
## UI and 3D MCP share authoring transactions; no runtime map adoption here.
const Geometry = preload("res://scripts/world3d/world_layout_geometry.gd")
const Address = preload("res://scripts/world3d/world_address.gd")
const Store = preload("res://scripts/world_editor/world_layout_store.gd")
const Seams = preload("res://scripts/world_editor/world_layout_seams.gd")
const Common = preload("res://scripts/world_editor/world_address_tools.gd")
var editor: Node3D
var store: RefCounted
var addresses: RefCounted

func _init(owner: Node3D, address_tools: RefCounted) -> void:
	editor = owner
	addresses = address_tools
	store = Store.new(address_tools.catalog)

static func _object(properties: Dictionary, required: Array) -> Dictionary:
	return {"type":"object","properties":properties,"required":required,"additionalProperties":false}

static func _array(items: Dictionary, minimum: int, maximum: int) -> Dictionary:
	return {"type":"array","items":items,"minItems":minimum,"maxItems":maximum}

static func layout_schema() -> Dictionary:
	var text := {"type":"string","maxLength":128}
	var scalar := {"type":"number","minimum":-1e12,"maximum":1e12}
	var placement := _object({"id":text,"pack_id":text,"map_number":{"type":"string","maxLength":19},"pack_version":text,"origin_m":_array(scalar,3,3),"ownership_xz_m":_array(scalar,4,4)},["id","pack_id","map_number","origin_m","ownership_xz_m"])
	var side := _object({"placement_id":text,"edge":{"type":"string","enum":["x_min","x_max","z_min","z_max"]},"interval_m":_array(scalar,2,2)},["placement_id","edge","interval_m"])
	var seam := _object({"id":text,"a":side,"b":side,"mode":{"type":"string","enum":["continuous"]}},["id","a","b","mode"])
	var space := _object({"id":text,"placements":_array(placement,0,128),"seams":_array(seam,0,256)},["id","placements","seams"])
	return _object({"schema_version":{"type":"integer","enum":[1]},"world_key":text,"units":{"type":"string","enum":["meters"]},"up_axis":{"type":"string","enum":["Y"]},"spaces":_array(space,1,32)},["schema_version","world_key","units","up_axis","spaces"])

static func tool_specs() -> Array:
	var text := Common._text()
	var id := Common._text(128)
	var revision := {"type":"integer","minimum":0,"maximum":9007199254740991}
	var document := {"document_id":text,"expected_edit_revision":revision}
	return [
		Common._spec("list_worlds","只读列出已发现资源包的世界布局与未保存文档；不创建文件。",{"pack_id":id,"pack_root":text},[],true),
		Common._spec("get_world_layout","读取世界布局、独立文档修订、来源绑定及诊断。归属范围来自作者配置，不从可见物件包围盒猜测。",{"document_id":text},["document_id"],true),
		Common._spec("preview_world_layout","预览完整世界布局。只允许平移，地图尺寸可不同；同空间归属矩形不可重叠。引用须已保存的编号目录。候选绑定布局/目录/包/地图修订，不写作者文件。",{"mode":{"type":"string","enum":["create","update"]},"pack_id":id,"pack_root":text,"world_key":id,"document_id":text,"layout":layout_schema(),"expected_edit_revision":revision},["mode","layout","expected_edit_revision"],true),
		Common._spec("apply_world_layout","应用已预览且全部来源仍有效的候选，一笔独立世界布局历史；需要另行 save_world_layout。",{"candidate_id":text,"expected_edit_revision":revision},["candidate_id","expected_edit_revision"]),
		Common._spec("save_world_layout","只原子保存指定世界布局，检查期望编辑修订、磁盘SHA及引用来源；不代存目录或地图。",document.merged({"expected_disk_sha":Common._text(64)}),["document_id","expected_edit_revision","expected_disk_sha"]),
		Common._spec("discard_world_layout","显式放弃布局编辑并重新读取磁盘；资源包不可用时可释放会话草稿，不重建包。",document,["document_id","expected_edit_revision"]),
		Common._spec("validate_world_seams","只读检查世界边段结构及已保存原生高度场的采样、边界高度和洞口；输出两侧局部/连续空间坐标。检查不授予物理、导航、桥面或连续跨图通行许可。",{"document_id":text,"space_id":id,"seam_id":id},["document_id"],true),
		Common._spec("locate_world_position","在指定连续空间按左闭右开的XZ归属范围定位地图地址；保留Y，不贴地、不移动场景。",{"document_id":text,"space_id":id,"space_position_m":_array({"type":"number","minimum":-1e12,"maximum":1e12},3,3)},["document_id","space_id","space_position_m"],true)
	]

func _validate(name_: String, args: Dictionary, write: bool = false) -> Dictionary:
	for spec: Dictionary in tool_specs():
		if spec.name != name_: continue
		var error: String = load("res://scripts/world_editor/mcp_schema.gd").validate(args,spec.inputSchema)
		if not error.is_empty(): return Common._failure("invalid_arguments",error)
		return addresses.guard_write() if write else {"ok":true}
	return Common._failure("invalid_arguments","未知世界布局操作。")

func list_worlds(args: Dictionary = {}) -> Dictionary:
	var checked := _validate("list_worlds",args)
	return checked if not checked.ok else store.list_worlds(args.get("pack_id",""),args.get("pack_root",""))

func get_layout(args: Dictionary) -> Dictionary:
	var checked := _validate("get_world_layout",args)
	return checked if not checked.ok else store.get_layout(args.document_id)

func preview_layout(args: Dictionary) -> Dictionary:
	var checked := _validate("preview_world_layout",args)
	return checked if not checked.ok else store.preview(args)

func apply_layout(args: Dictionary) -> Dictionary:
	var checked := _validate("apply_world_layout",args,true)
	return checked if not checked.ok else store.apply(args.candidate_id,int(args.expected_edit_revision))

func save_layout(args: Dictionary) -> Dictionary:
	var checked := _validate("save_world_layout",args,true)
	return checked if not checked.ok else store.save(args.document_id,int(args.expected_edit_revision),args.expected_disk_sha)

func discard_layout(args: Dictionary) -> Dictionary:
	var checked := _validate("discard_world_layout",args,true)
	return checked if not checked.ok else store.discard(args.document_id,int(args.expected_edit_revision))

func undo_layout(args: Dictionary) -> Dictionary:
	var checked: Dictionary = addresses._validate("undo_world_edit",args,true)
	return checked if not checked.ok else store.undo(args.document_id,int(args.expected_edit_revision))

func redo_layout(args: Dictionary) -> Dictionary:
	var checked: Dictionary = addresses._validate("redo_world_edit",args,true)
	return checked if not checked.ok else store.redo(args.document_id,int(args.expected_edit_revision))

func validate_seams(args: Dictionary) -> Dictionary:
	var checked := _validate("validate_world_seams",args)
	if not checked.ok: return checked
	var current: Dictionary = store.get_layout(args.document_id)
	if not current.ok: return current
	if current.document.get("read_only",false) or current.document.get("disk_conflict",false):
		return Common._failure("layout_conflict","布局来源已变化，请先重新载入配置。")
	var report: Dictionary = Seams.inspect(current.layout,current.bindings,store.root,args.get("space_id",""),args.get("seam_id",""))
	if not report.ok: return report
	# Native hydration can take longer than the initial catalogue scan. Reobserve
	# the layout and its package/catalogue proof before publishing the report.
	var observed: Dictionary = store.get_layout(args.document_id)
	if not observed.ok: return observed
	if observed.document.get("read_only",false) or observed.document.get("disk_conflict",false):
		return Common._failure(str(observed.document.get("reason_code","layout_conflict")),"接缝检查期间布局或引用来源已变化，报告已废弃；请重新载入后检查。")
	if _seam_source_stamp(current) != _seam_source_stamp(observed):
		return Common._failure("layout_inputs_changed","接缝检查期间文档修订或来源基线已变化，报告已废弃。")
	report.document = current.document.duplicate(true)
	report.layout_inputs = current.inputs.duplicate(true)
	report.layout_sha = JSON.stringify(current.layout,"",true,true).sha256_text()
	report.selection = {"space_id":args.get("space_id",""),"seam_id":args.get("seam_id","")}
	# Different selected seams can read exactly the same native files. Their
	# reports also bind the authored identity, revisions and requested scope.
	report.report_id = JSON.stringify([report.report_id,report.document,report.layout_inputs,report.layout_sha,report.selection],"",true,true).sha256_text()
	return report

static func _seam_source_stamp(current: Dictionary) -> String:
	return JSON.stringify([current.document,current.layout,current.inputs,current.bindings],"",true,true).sha256_text()

func resolve_address(args: Dictionary) -> Dictionary:
	var checked: Dictionary = addresses._validate("resolve_world_address",args)
	if not checked.ok: return checked
	if not args.has("document_id") or args.has("pack_root"): return Common._failure("invalid_arguments","布局解析需要 document_id，由布局选择包版本。")
	var current: Dictionary = store.get_layout(args.document_id)
	if not current.ok: return current
	if current.document.get("read_only",false) or current.document.get("disk_conflict",false): return Common._failure("layout_conflict","布局来源已变化，请重新载入。")
	var parsed := Address.parse(args.address)
	if not parsed.ok: return parsed
	var result := Geometry.resolve(current.layout,parsed,args.get("space_id",""),args.get("placement_id",""))
	return _resolved(result,current,args.get("anchor_kind","point"))

func locate_position(args: Dictionary) -> Dictionary:
	var checked := _validate("locate_world_position",args)
	if not checked.ok: return checked
	var current: Dictionary = store.get_layout(args.document_id)
	if not current.ok: return current
	if current.document.get("read_only",false) or current.document.get("disk_conflict",false): return Common._failure("layout_conflict","布局来源已变化，请重新载入。")
	return _resolved(Geometry.locate(current.layout,args.space_id,args.space_position_m),current,"point")

func _resolved(result: Dictionary, current: Dictionary, anchor: String) -> Dictionary:
	if not result.ok: return result
	for binding: Dictionary in current.bindings:
		if binding.space_id == result.space_id and binding.placement_id == result.placement_id:
			result.binding = binding.duplicate(true)
			result.map_ref = binding.map_ref
			result.path = binding.path
			break
	result.document = current.document
	result.world_key = current.layout.world_key
	result.position_m = result.local_position_m.duplicate()
	result.world_position_available = true
	result.anchor_kind = anchor
	result.can_transfer = false
	result.surface_id = null
	result.validation = "layout_address_only"
	return result

func state() -> Dictionary:
	var documents: Array = store.cached_documents()
	return {"phase":"D2","documents":documents,"dirty":documents.any(func(doc):return doc.get("dirty",false)),"seam_scope":"authoring_heightfields","continuous_runtime_available":false}

func has_unsaved_work() -> bool:
	if state().dirty: return true
	var dialog := editor.get_node_or_null("WorldLayoutDialog") if is_instance_valid(editor) else null
	return dialog != null and dialog.has_local_changes()
