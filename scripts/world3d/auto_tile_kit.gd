extends RefCounted
## Immutable, self-contained GLB pieces. The saved tile embeds its kit manifest.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const Families = ["road", "wall", "grass", "dirt", "water", "cliff", "stairs", "roof", "bridge"]
static var _meshes := {}
static var _mesh_ids:Dictionary={}
static var _mesh_slots:Dictionary={}
static var _mesh_order:Array[String]=[]
static var _mesh_free:Array[int]=[]
static var _mesh_cursor:=0
var directory := ""

func _init(folder: String = "") -> void:
	directory = folder if not folder.is_empty() else Paths.cache_directory("auto_tile_kits")

static func rotate_mask(mask: int) -> int:
	return ((mask << 1) & 14) | ((mask >> 3) & 1) | ((mask << 1) & 224) | ((mask >> 3) & 16)

static func variant(pieces: Dictionary, mask: int) -> Dictionary:
	var rotated := mask
	for turns in 4:
		if pieces.has(str(rotated)): return {"path": pieces[str(rotated)], "turns": (4 - turns) % 4}
		rotated = rotate_mask(rotated)
	return {}

static func masks(family: String) -> Array[int]:
	var result: Array[int] = []
	for mask in (256 if family in ["grass", "dirt", "water", "roof"] else 16):
		var valid_mask := true
		for i in 4:
			if mask & (1 << (i + 4)) and not (mask & (1 << i) and mask & (1 << ((i + 1) % 4))): valid_mask = false
		if valid_mask: result.append(mask)
	return result

static func valid(kit: Variant, relative: bool = false, content_root: String = "") -> bool:
	if not kit is Dictionary or kit.get("version") != 1 or kit.get("family") not in Families or not kit.get("name") is String or not kit.get("pieces") is Dictionary: return false
	if kit.name.is_empty() or kit.name.length() > 120 or kit.pieces.is_empty() or kit.pieces.size() > 47: return false
	for key in kit.pieces:
		if not key is String or not kit.pieces[key] is String: return false
		var path: String = kit.pieces[key]
		if path.get_extension().to_lower() != "glb": return false
		if relative and not path.is_absolute_path():
			if path.contains("..") or path.contains(":") or path.begins_with("/") or path.contains("\\"): return false
		elif not Paths.asset_key_allowed(path, content_root): return false
	match kit.family:
		"cliff": return kit.pieces.size() == 2 and kit.pieces.has("top") and kit.pieces.has("edge")
		"stairs": return kit.pieces.size() == 1 and kit.pieces.has("default")
	for key in kit.pieces:
		if not str(key).is_valid_int() or not masks(kit.family).has(int(key)) or str(int(key)) != key: return false
	for mask in masks(kit.family):
		if variant(kit.pieces, mask).is_empty(): return false
	return true

func entries() -> Array:
	var result: Array = []
	if not DirAccess.dir_exists_absolute(directory) or not Paths.allowed(directory): return result
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() != "json": continue
		var path := directory.path_join(file)
		var loaded := read(path)
		if loaded.ok: result.append({"kit_id": path, "name": loaded.kit.name, "family": loaded.kit.family, "piece_count": loaded.kit.pieces.size()})
	return result

func read(path: String, author_import:bool=false) -> Dictionary:
	if not Paths.allowed(path) or not FileAccess.file_exists(path): return {"ok": false, "error": "套件清单不存在或超出资源根"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 65536: return {"ok": false, "error": "套件清单超过 64 KiB 或无法读取"}
	var kit: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not valid(kit, true): return {"ok": false, "error": "套件格式、模型路径或邻接变体不完整"}
	var checked_sources:Dictionary={}
	for key in kit.pieces:
		var source: String = kit.pieces[key]
		if not source.is_absolute_path(): source = path.get_base_dir().path_join(source).simplify_path()
		if not Paths.asset_key_allowed(source): return {"ok": false, "error": "套件模型路径越界"}
		if not checked_sources.has(source):
			# The explicit importer checks each unique authored model immediately
			# before copying it; ordinary reads use only the published native.
			checked_sources[source]="" if author_import and FileAccess.file_exists(source) else ("套件模型缺失" if author_import else reference_error(source))
		var checked:String=checked_sources[source]
		if not checked.is_empty(): return {"ok": false, "error": checked}
		kit.pieces[key] = source
	return {"ok": true, "kit": kit}

func import_kit(path: String) -> Dictionary:
	var loaded := read(path,true)
	if not loaded.ok: return loaded
	var kit: Dictionary = loaded.kit
	# Preflight every dependency before writing anything to the library.
	var sources := {};var source_digests:Dictionary={}
	for source: String in kit.pieces.values():
		if sources.has(source): continue
		var checked := check_model(source,true)
		if not checked.is_empty(): return {"ok": false, "error": checked}
		sources[source] = FileAccess.get_file_as_bytes(source)
		var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(sources[source]);source_digests[source]=hash_.finish().hex_encode()
	if not Paths.allowed(directory): return {"ok": false, "error": "套件保存目录越界"}
	var err := DirAccess.make_dir_recursive_absolute(directory.path_join("models"))
	if err != OK: return {"ok": false, "error": "无法创建套件目录"}
	var compiled_destinations:Dictionary={}
	for key in kit.pieces:
		var source: String = kit.pieces[key]
		var destination := directory.path_join("models").path_join(str(source_digests[source]) + ".glb")
		if not Paths.allowed(destination): return {"ok": false, "error": "套件模型保存路径越界"}
		if not compiled_destinations.has(destination):
			err = write_immutable(destination, sources[source])
			if err != OK: return {"ok": false, "error": "套件模型保存失败"}
			var built:Dictionary=preload("res://scripts/world_editor/asset_library.gd")._compile_import(destination)
			if not built.get("ok",false) or not preload("res://scripts/world_editor/asset_library.gd").native_available(destination):return {"ok":false,"error":"套件模型原生产物生成失败，请重新导入"}
			compiled_destinations[destination]=true
		kit.pieces[key] = "models/" + destination.get_file()
	var payload := JSON.stringify(kit, "\t")
	var target := directory.path_join(payload.sha256_text() + ".json")
	if not Paths.allowed(target) or write_immutable(target, payload.to_utf8_buffer()) != OK: return {"ok": false, "error": "套件清单保存失败"}
	return {"ok": true, "kit_id": target, "name": kit.name, "family": kit.family}

static func write_immutable(path: String, bytes: PackedByteArray) -> Error:
	if FileAccess.file_exists(path): return OK if FileAccess.get_file_as_bytes(path) == bytes else ERR_FILE_CORRUPT
	var temp := path + ".tmp"
	if not Paths.allowed(temp): return ERR_UNAUTHORIZED
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(bytes); file.flush()
	var err := file.get_error()
	file.close()
	if err == OK: err = preload("res://scripts/world3d/atomic_file.gd").publish(temp, path)
	return err

static func check_model(path: String, author_import:bool=false) -> String:
	var mesh:ArrayMesh
	if author_import:
		var invalid:=_header_error(path)
		if not invalid.is_empty():return invalid
		var root:=Io.load_scene(path)
		if root==null:return "套件模型无法读取"
		mesh=_piece_from_scene(root);root.free()
	else:mesh=piece_mesh(path)
	if mesh == null or mesh.get_surface_count() == 0: return "套件模型没有有效静态三角网格"
	return ""

static func reference_error(path:String)->String:
	if not Paths.asset_key_allowed(path):return "套件模型路径越界"
	return "" if preload("res://scripts/world_editor/asset_library.gd").native_available(path) else "套件模型缺少原生产物"

static func _header_error(path: String) -> String:
	if not Paths.allowed(path): return "套件模型超出资源根"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 20: return "套件模型无法读取"
	if file.get_32() != 0x46546C67 or file.get_32() != 2 or file.get_32() != file.get_length(): return "套件需要 GLB 2.0 模型"
	var length := file.get_32()
	if file.get_32() != 0x4E4F534A or length > file.get_length() - 20: return "套件 GLB JSON 块无效"
	var raw: Variant = JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	file.close()
	if not raw is Dictionary: return "套件 GLB 数据无效"
	for section in ["images", "buffers"]:
		if not raw.get(section, []) is Array: return "套件 GLB 依赖数据无效"
		for item in raw.get(section, []):
			if not item is Dictionary: return "套件 GLB 依赖数据无效"
			if not str(item.get("uri", "")).is_empty(): return "套件 GLB 必须内嵌全部贴图和缓冲数据"
	for section in ["skins", "animations"]:
		if not raw.get(section, []) is Array or not raw.get(section, []).is_empty(): return "套件只支持静态模型"
	return ""

static func piece_mesh(path: String, context:RefCounted=null) -> ArrayMesh:
	if context!=null:return context.piece(path)
	if not Paths.asset_key_allowed(path):return null
	var library=preload("res://scripts/world_editor/asset_library.gd")
	var candidate:Dictionary=library.native_validation_candidate(path)
	if candidate.is_empty():return null
	var key:String=path+":"+str(candidate.native_product_kind)+":"+str(candidate.source_sha)+":"+str(candidate.payload_sha)+":"+str(candidate.generator)
	if _meshes.has(key):
		var existing:Variant=_meshes[key].get_ref()
		if existing is ArrayMesh:return existing
		_forget_mesh(key)
	var root:=library.instantiate_preview(path,true)
	if root == null: return null
	var output:=_piece_from_scene(root)
	root.free()
	if output==null:return null
	_prune_meshes()
	_meshes[key] = weakref(output)
	_mesh_ids[key]=output.get_instance_id()
	var slot:int=_mesh_slots[key] if _mesh_slots.has(key) else (_mesh_free.pop_back() if not _mesh_free.is_empty() else _mesh_order.size())
	if slot==_mesh_order.size():_mesh_order.append(key)
	else:_mesh_order[slot]=key
	_mesh_slots[key]=slot
	return output

static func _forget_mesh(key:String)->void:
	if _mesh_slots.has(key):
		var slot:int=_mesh_slots[key];_mesh_order[slot]="";_mesh_free.append(slot);_mesh_slots.erase(key)
	_meshes.erase(key);_mesh_ids.erase(key)

static func _prune_meshes()->void:
	# Bounded scalar liveness checks never acquire a temporary final owner.
	for index:int in mini(16,_mesh_order.size()):
		if _mesh_cursor>=_mesh_order.size():_mesh_cursor=0
		var key:String=_mesh_order[_mesh_cursor];_mesh_cursor+=1
		if not key.is_empty() and not is_instance_id_valid(int(_mesh_ids.get(key,0))):_forget_mesh(key)

static func _piece_from_scene(root:Node)->ArrayMesh:
	var output := ArrayMesh.new()
	var success := append_node(output, root, Transform3D.IDENTITY)
	if not success or output.get_surface_count()==0: return null
	return output

static func append_node(output: ArrayMesh, node: Node, parent: Transform3D) -> bool:
	if node is AnimationPlayer and not node.get_animation_list().is_empty():return false
	var transform: Transform3D = parent * node.transform if node is Node3D else parent
	if node is MeshInstance3D and node.mesh != null:
		if node.skin != null or node.mesh.get_blend_shape_count() > 0: return false
		for surface in node.mesh.get_surface_count():
			# ArrayMesh and the RD renderer enforce this engine limit. There is no
			# separate kit-only vertex or material-count budget.
			if node.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES or output.get_surface_count() >= RenderingServer.MAX_MESH_SURFACES: return false
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.append_from(node.mesh, surface, transform)
			tool.set_material(node.get_active_material(surface))
			tool.commit(output)
	for child in node.get_children():
		if not append_node(output, child, transform): return false
	return true

static func append_piece(output: ArrayMesh, path: String, transform: Transform3D, context:RefCounted=null) -> bool:
	var mesh := piece_mesh(path,context)
	if mesh == null: return false
	if output.get_surface_count()+mesh.get_surface_count()>RenderingServer.MAX_MESH_SURFACES:return false
	var owners:Array=output.get_meta("_compiled_resource_owners",[])
	for owner:PackedScene in mesh.get_meta("_compiled_resource_owners",[]):
		if not owners.has(owner):owners.append(owner)
	if not owners.is_empty():output.set_meta("_compiled_resource_owners",owners)
	for surface in mesh.get_surface_count():
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.append_from(mesh, surface, transform)
		tool.set_material(mesh.surface_get_material(surface))
		tool.commit(output)
	return true

static func required_paths(tile:Dictionary,content_root:String="")->Array[String]:
	var kit:Dictionary=tile.get("options",{}).get("kit",{})
	var result:Array[String]=[]
	if not valid(kit,false,content_root):return result
	if tile.family=="cliff":
		result.append(kit.pieces.top)
		if tile.get("drops",[1,1,1,1]).any(func(drop):return float(drop)>0):result.append(kit.pieces.edge)
	elif tile.family=="stairs":result.append(kit.pieces.default)
	else:
		var selected:=variant(kit.pieces,int(tile.mask) if tile.family in ["grass","dirt","water","roof"] else int(tile.mask)&15)
		if not selected.is_empty():result.append(selected.path)
	return result

static func build(tile: Dictionary, context:RefCounted=null) -> ArrayMesh:
	var kit: Dictionary = tile.get("options", {}).get("kit", {})
	if not valid(kit): return null
	var output := ArrayMesh.new()
	if tile.family == "cliff":
		if not append_piece(output, kit.pieces.top, Transform3D.IDENTITY,context): return null
		var drops: Array = tile.get("drops", [1, 1, 1, 1])
		for side in 4:
			var drop := float(drops[side])
			if drop <= 0: continue
			var transform := Transform3D(Basis(Vector3.UP, -side * PI / 2).scaled(Vector3(1, drop, 1)), Vector3(0, (1 - drop) / 2, 0))
			if not append_piece(output, kit.pieces.edge, transform,context): return null
	elif tile.family == "stairs":
		if not append_piece(output, kit.pieces.default, Transform3D(Basis(Vector3.UP, -int(tile.options.direction) * PI / 2), Vector3.ZERO),context): return null
	else:
		var selected := variant(kit.pieces, int(tile.mask) if tile.family in ["grass", "dirt", "water", "roof"] else int(tile.mask) & 15)
		if selected.is_empty() or not append_piece(output, selected.path, Transform3D(Basis(Vector3.UP, -int(selected.turns) * PI / 2), Vector3.ZERO),context): return null
	return output

static func missing(records: Array) -> Array:
	var result: Array = []
	var checked:Dictionary={}
	for record in records:
		var kit: Dictionary = record.get("tile3d", {}).get("options", {}).get("kit", {})
		for path: String in kit.get("pieces", {}).values():
			if not checked.has(path):checked[path]=preload("res://scripts/world_editor/asset_library.gd").native_available(path)
			if not checked[path]:result.append(path)
	return result
