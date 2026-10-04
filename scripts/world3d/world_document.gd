extends RefCounted
## Full map record. The scene tree is only a view of these records.

const WorldLocation = preload("res://scripts/world3d/world_location.gd")
const GltfMapIo = preload("res://scripts/world3d/gltf_map_io.gd")
const SurfaceMaterials = preload("res://scripts/world3d/surface_materials.gd")

var records: Array = []
var map_meta: Dictionary = {}
var _next := 1
var _disk_path := ""
var _disk_signature := ""
var editor_dirty := false
var terrain_neighbors=preload("res://scripts/world3d/terrain_neighbors.gd").new()
var _save_meshes = preload("res://scripts/world3d/save_mesh_cache.gd").new()
# Only the immutable runtime loader supplies these operation-scoped caches.
# Editable documents leave them null so later edits recheck paths and textures.
var load_paint_validation: Variant=null
var load_texture_checks: Variant=null
var load_box_meshes: Variant=null
var load_box_hits:=0
var load_immutable_records:=false
var last_save_metrics: Dictionary = {}


func add_warp(position: Vector3, target_path: String, spawn: Vector3) -> String:
	var uuid := _push("warp", "warp", position, Vector3(1.2, 0.2, 1.2))
	records[records.size() - 1]["target_path"] = target_path
	records[records.size() - 1]["spawn"] = [spawn.x, spawn.y, spawn.z]
	return uuid


func add_gather(position: Vector3, node_id: String) -> String:
	var uuid := _push("gather", "gather", position, Vector3(0.6, 0.4, 0.6))
	records[records.size() - 1]["node_id"] = node_id
	return uuid


func add_npc(position: Vector3, npc_id: String, line: String) -> String:
	var uuid := _push("npc", "npc", position, Vector3(0.6, 1.6, 0.6))
	records[records.size() - 1]["npc_id"] = npc_id
	records[records.size() - 1]["line"] = line
	return uuid


var _undo: Array = []
var _redo: Array = []


func checkpoint() -> void:
	commit_change(records)


func commit_change(before: Array) -> void:
	_undo.append(before.duplicate(true))
	_redo.clear()
	if _undo.size() > 32:
		_undo.pop_front()


func undo() -> bool:
	if _undo.is_empty():
		return false
	var state: Variant = _undo.pop_back()
	_redo.append(recovery_snapshot() if state is Dictionary else records.duplicate(true))
	if state is Dictionary: apply_recovery(state)
	else: records = state
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var state: Variant = _redo.pop_back()
	_undo.append(recovery_snapshot() if state is Dictionary else records.duplicate(true))
	if state is Dictionary: apply_recovery(state)
	else: records = state
	return true


func recovery_snapshot() -> Dictionary:
	return {"records": records.duplicate(true), "map_meta": map_meta.duplicate(true), "next": _next, "disk_path": _disk_path, "disk_signature": _disk_signature}


func checkpoint_recovery() -> void:
	_undo.append(recovery_snapshot())
	_redo.clear()
	if _undo.size() > 32: _undo.pop_front()


func apply_recovery(state: Dictionary) -> void:
	records = state.records.duplicate(true)
	map_meta = state.map_meta.duplicate(true)
	_next = maxi(_next, int(state.next))
	_disk_path = str(state.disk_path)
	_disk_signature = str(state.disk_signature)


func begin_change() -> void:
	checkpoint()


func add_box_silent(surface_id: String, position: Vector3, size: Vector3, rotation_degrees: Vector3 = Vector3.ZERO) -> String:
	return _push("box", surface_id, position, size, rotation_degrees)


func add_box(surface_id: String, position: Vector3, size: Vector3, rotation_degrees: Vector3 = Vector3.ZERO) -> String:
	checkpoint()
	return _push("box", surface_id, position, size, rotation_degrees)


func add_seat(surface_center:Vector3,dimensions:Vector2,yaw_degrees:float=0.0)->String:
	# A white-box stool; imported furniture may provide the same local seat metadata.
	if not surface_center.is_finite() or not dimensions.is_finite() or dimensions.x<=0 or dimensions.y<=0 or not is_finite(yaw_degrees):return ""
	checkpoint()
	var id:=_push("seat","block",surface_center-Vector3(0,.02,0),Vector3(dimensions.x,.04,dimensions.y),Vector3(0,yaw_degrees,0))
	records.back()["seat"]={"surface":[0,.02,0],"size":[dimensions.x,dimensions.y]}
	return id


func _push(kind: String, surface_id: String, position: Vector3, size: Vector3, rotation_degrees: Vector3 = Vector3.ZERO) -> String:
	var uuid := "obj_%d" % _next
	_next += 1
	records.append({
		"uuid": uuid,
		"kind": kind,
		"surface_id": surface_id,
		"position": [position.x, position.y, position.z],
		"size": [size.x, size.y, size.z],
		"rotation": [rotation_degrees.x, rotation_degrees.y, rotation_degrees.z],
	})
	return uuid


func move(uuid: String, position: Vector3) -> bool:
	var record := _find(uuid)
	if record.is_empty():
		return false
	record["position"] = [position.x, position.y, position.z]
	return true


func remove(uuid: String) -> bool:
	for i in records.size():
		if str(records[i].get("uuid", "")) == uuid:
			records.remove_at(i)
			return true
	return false


func has_uuid(uuid: String) -> bool:
	return not _find(uuid).is_empty()


func build(effects: bool=true) -> Node3D:
	# effects=false is the off-screen export view; cached meshes can be CPU-only.
	# One immutable rebuild shares validation and painted primitive geometry;
	# restore the ordinary edit context afterwards so later edits revalidate files.
	var previous_context:Array=[load_paint_validation,load_texture_checks,load_box_meshes]
	load_paint_validation={};load_texture_checks={};load_box_meshes={}
	var world := export_root()
	terrain_neighbors.update(records)
	if not effects: _save_meshes.begin(records)
	for record in records:
		world.add_child(_asset(record) if record.get("kind") == "asset" else _mesh(record,effects))
	load_paint_validation=previous_context[0];load_texture_checks=previous_context[1];load_box_meshes=previous_context[2]
	return world


func export_root() -> Node3D:
	var world := Node3D.new()
	world.name = "rmmo_world"
	var extras := {
		"rmmo_format": WorldLocation.FORMAT,
		"rmmo_version": WorldLocation.FORMAT_VERSION,
		"rmmo_unit": "m",
	}
	for key in map_meta.keys():
		extras[key] = map_meta[key]
	extras["rmmo_records"] = records.duplicate(true)
	world.set_meta("extras", extras)
	return world


func save(gltf_path: String) -> Error:
	var started := Time.get_ticks_usec()
	last_save_metrics = {}
	var validation := validate_save()
	if validation != OK: return validation
	# glTF stores standard PBR fallbacks; native records restore dynamic shaders.
	last_save_metrics["validate_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	var phase := Time.get_ticks_usec()
	var view := build(false)
	last_save_metrics["build_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	last_save_metrics["geometry_cache_hits"] = _save_meshes.hits
	last_save_metrics["geometry_cache_misses"] = _save_meshes.misses
	last_save_metrics["geometry_cache_bytes"] = _save_meshes.bytes
	for child in view.get_children():
		if child.has_meta("paint_error") or child.has_meta("tile_error"):
			view.free()
			return ERR_INVALID_DATA
	phase = Time.get_ticks_usec()
	var err := GltfMapIo.save_scene_atomic(view, gltf_path, save_signature(gltf_path))
	last_save_metrics["publish_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	if err == OK: last_save_metrics["export"] = GltfMapIo.last_export_metrics.duplicate(true)
	if err == OK: accept_save(gltf_path, str(view.get_meta("published_signature", "")))
	view.free()
	last_save_metrics["total_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	return err


func validate_save(progress: Callable = Callable()) -> Error:
	var err := validate_save_meta()
	if err != OK: return err
	var checked := 0
	for record in records:
		if progress.is_valid(): progress.call("validate", checked, records.size())
		err = validate_save_record(record)
		if err != OK: return err
		checked += 1
	return OK


func validate_save_meta() -> Error:
	if not preload("res://scripts/world3d/city_layout.gd").valid(map_meta): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_meta(map_meta): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_ownership(map_meta,records): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/editor_view_settings.gd").valid(map_meta): return ERR_INVALID_DATA
	if not missing_assets().is_empty(): return ERR_FILE_NOT_FOUND
	if not preload("res://scripts/world3d/environment_settings.gd").valid(map_meta): return ERR_INVALID_DATA
	return OK


func validate_save_record(record: Dictionary) -> Error:
	if not preload("res://scripts/world3d/event_templates.gd").valid_record(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_record(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/auto_tile_rules.gd").valid(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/road_surface.gd").valid(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/terrain_surface.gd").valid(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/channel_surface.gd").valid(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/fortification_data.gd").valid_record(record): return ERR_INVALID_DATA
	if not SurfaceMaterials.valid(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/wind_response.gd").valid(record): return ERR_INVALID_DATA
	if record.get("kind") == "asset" and not preload("res://scripts/world3d/map_paths.gd").allowed(str(record.get("asset_path", ""))): return ERR_INVALID_DATA
	return OK


func save_signature(gltf_path: String) -> Variant:
	var canonical := ProjectSettings.globalize_path(gltf_path).simplify_path()
	return _disk_signature if canonical == _disk_path else null


func accept_save(gltf_path: String, signature: String) -> void:
	_disk_path = ProjectSettings.globalize_path(gltf_path).simplify_path()
	_disk_signature = signature
	# History restores content, never an obsolete conflict baseline after saving.
	for state in _undo + _redo:
		if state is Dictionary:
			state.disk_path = _disk_path
			state.disk_signature = _disk_signature


static func open_file(gltf_path: String):
	var signature := FileAccess.get_sha256(gltf_path) if FileAccess.file_exists(gltf_path) else ""
	var fast:=authoritative_extras(gltf_path)
	if fast.has("error"): return null
	var extras: Dictionary=fast.get("extras",{})
	var scene: Node
	if extras.is_empty():
		scene=GltfMapIo.load_scene(gltf_path)
		if scene==null:return null
		extras=GltfMapIo.extras_of(scene).duplicate(true)
	var raw: Variant = extras.get("rmmo_records")
	if raw == null and scene!=null and str(extras.get("rmmo_format", "")) == WorldLocation.FORMAT:
		raw = _legacy_records(scene)
	if scene!=null: scene.free()
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_meta(extras): return null
	if not preload("res://scripts/world3d/editor_view_settings.gd").valid(extras): return null
	if not preload("res://scripts/world3d/city_layout.gd").valid(extras): return null
	if not preload("res://scripts/world3d/environment_settings.gd").valid(extras): return null
	if not raw is Array:
		# Do not replace unsupported/imported documents with an empty yard.
		return null
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_ownership(extras,raw): return null
	var doc = load("res://scripts/world3d/world_document.gd").new()
	var ids := {}
	for record in raw:
		if not record is Dictionary:
			return null
		if not preload("res://scripts/world3d/event_templates.gd").valid_record(record): return null
		if not preload("res://scripts/world3d/building_blueprint.gd").valid_record(record): return null
		if not preload("res://scripts/world3d/auto_tile_rules.gd").valid(record): return null
		if not preload("res://scripts/world3d/road_surface.gd").valid(record): return null
		if not preload("res://scripts/world3d/terrain_surface.gd").valid(record): return null
		if not preload("res://scripts/world3d/channel_surface.gd").valid(record): return null
		if not preload("res://scripts/world3d/fortification_data.gd").valid_record(record): return null
		if not SurfaceMaterials.valid(record): return null
		if not preload("res://scripts/world3d/wind_response.gd").valid(record): return null
		var uuid := str(record.get("uuid", ""))
		if uuid.is_empty() or ids.has(uuid):
			return null
		ids[uuid] = true
		for field in ["position", "size", "rotation"]:
			var values: Variant = record.get(field)
			if not values is Array or values.size() != 3:
				return null
			for value in values:
				if not (value is float or value is int) or not is_finite(float(value)):
					return null
		if uuid.begins_with("obj_"):
			doc._next = maxi(doc._next, int(uuid.trim_prefix("obj_")) + 1)
	doc._disk_path = ProjectSettings.globalize_path(gltf_path).simplify_path()
	if signature != FileAccess.get_sha256(gltf_path): return null
	doc._disk_signature = signature
	doc.records = raw.duplicate(true)
	extras.erase("rmmo_records")
	doc.map_meta = extras
	return doc


static func authoritative_extras(path: String) -> Dictionary:
	# Like MapLoader, native editor records are authoritative. Importing thousands
	# of duplicate exported meshes just to discard them makes reopening a street
	# take minutes. Legacy/imported/transformed roots retain the GLTF import path.
	if path.get_extension().to_lower()!="gltf" or not FileAccess.file_exists(path):return {}
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:return {"error":"invalid JSON"}
	var scenes: Variant=data.get("scenes"); var nodes: Variant=data.get("nodes")
	var index:=int(data.get("scene",0))
	if not scenes is Array or not nodes is Array or index<0 or index>=scenes.size() or not scenes[index] is Dictionary:return {}
	var roots: Variant=scenes[index].get("nodes")
	if not roots is Array or roots.size()!=1 or not (roots[0] is float or roots[0] is int):return {}
	var root_index:=int(roots[0])
	if root_index<0 or root_index>=nodes.size() or not nodes[root_index] is Dictionary:return {}
	var node: Dictionary=nodes[root_index]; var extra: Variant=node.get("extras")
	if not extra is Dictionary or extra.get("rmmo_format")!=WorldLocation.FORMAT or extra.get("rmmo_version")!=1 or not extra.get("rmmo_records") is Array:return {}
	for field in ["translation","rotation","scale","matrix"]:
		if node.has(field):return {}
	var Paths=preload("res://scripts/world3d/map_paths.gd")
	for section in ["buffers","images"]:
		if not data.get(section,[]) is Array:return {"error":"invalid dependencies"}
		for dependency in data.get(section,[]):
			if not dependency is Dictionary:return {"error":"invalid dependency"}
			var uri:=str(dependency.get("uri",""))
			if uri.is_empty() or uri.begins_with("data:"):continue
			var relative:=GltfMapIo.decode_dependency_uri(uri)
			var target:=path.get_base_dir().path_join(relative)
			if relative.is_empty() or not Paths.allowed(target) or not FileAccess.file_exists(target):return {"error":"missing or invalid dependency"}
			if section=="buffers":
				var file:=FileAccess.open(target,FileAccess.READ)
				if file==null or file.get_length()<int(dependency.get("byteLength",0)):return {"error":"truncated buffer"}
	return {"extras":extra}


static func _legacy_records(scene: Node) -> Variant:
	# Previous prototype saves contain only box meshes and per-node extras.
	# Recover those exact documents; do not silently flatten arbitrary glTFs.
	var result: Array = []
	for child in scene.get_children():
		if not child is MeshInstance3D or child.get_child_count() != 0:
			return null
		var mesh := child as MeshInstance3D
		var metadata := GltfMapIo.extras_of(mesh)
		if mesh.mesh == null or not metadata.has("uuid") or not mesh.scale.is_equal_approx(Vector3.ONE):
			return null
		if mesh.mesh.get_surface_count() != 1 or not mesh.mesh.get_aabb().get_center().is_zero_approx():
			return null
		var half := mesh.mesh.get_aabb().size * 0.5
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if not vertex.abs().is_equal_approx(half):
				return null
		var record := metadata.duplicate(true)
		var size := mesh.mesh.get_aabb().size
		var pos := mesh.position
		var rotation := mesh.rotation_degrees
		record["position"] = [pos.x, pos.y, pos.z]
		record["size"] = [size.x, size.y, size.z]
		record["rotation"] = [rotation.x, rotation.y, rotation.z]
		record["collision"] = str(metadata.get("rmmo_collision", "walk"))
		var material := mesh.get_active_material(0) as StandardMaterial3D
		if material != null:
			record["color"] = [material.albedo_color.r, material.albedo_color.g, material.albedo_color.b]
		result.append(record)
	return result


static func sample_yard(inn_path: String = ""):
	var doc = load("res://scripts/world3d/world_document.gd").new()
	doc.map_meta["spawn"] = [-4.0, 0.9, 4.0]
	doc.map_meta["map_ref"] = "prototype/yard"
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(40, 0.2, 40))
	doc.add_box("block", Vector3(8, 1, 2), Vector3(0.4, 2, 8))
	doc.add_box("bridge_deck", Vector3(0, 2.9, -2), Vector3(3, 0.2, 8))
	doc.add_box("ramp", Vector3(0, 1.5, 4.2), Vector3(3, 0.25, 5), Vector3(31, 0, 0))
	doc.add_npc(Vector3(-3, 0.8, 2), "guide", "桥在北边，坡道可以上去。")
	doc.add_gather(Vector3(3, 0.4, 2), "herb")
	if inn_path != "":
		doc.add_warp(Vector3(0, 0.1, -8), inn_path, Vector3(0, 0.9, 3))
	return doc


static func make_inn(yard_path: String):
	var doc = load("res://scripts/world3d/world_document.gd").new()
	doc.map_meta["map_ref"] = "prototype/inn"
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(16, 0.2, 16))
	doc.add_npc(Vector3(0, 0.8, -2), "keeper", "欢迎回来。")
	doc.add_warp(Vector3(0, 0.1, 6), yard_path, Vector3(0, 0.9, -4))
	return doc


func _find(uuid: String) -> Dictionary:
	for record in records:
		if str(record.get("uuid", "")) == uuid:
			return record
	return {}


func _mesh(record: Dictionary, effects: bool=true) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = str(record.get("uuid", "box"))
	var signature: String = _save_meshes.key(record, terrain_neighbors.data.get(str(record.uuid), {})) if not effects else ""
	var cached: Mesh = _save_meshes.get_mesh(str(record.uuid), signature) if not effects else null
	var box_key:Array=[]
	if effects and load_box_meshes!=null and not ["tile3d","road_mesh","terrain_mesh","channel_mesh"].any(func(field):return record.has(field)) and record.get("building_shape","") in ["","cylinder","gable","wall_grid","draped_cloth","joined_box","roof_prism","candle_sconce"]:
		# Native Variant hashing/equality handles collisions without serializing
		# every repeated material and face to an indented string on every object.
		box_key=[record.get("building_shape",""),record.get("size",[1,1,1]),record.get("color",[]),record.get("invisible",false),record.get("surface_paint",[])]
		# Repeated houses also share immutable custom geometry. Include every
		# topology/UV input, never UUID, floor identity or fixture state/pose.
		for field in ["wall_grid","cloth","box_faces","roof_mesh"]:
			box_key.append(record.get(field))
		if record.get("building_shape")=="roof_prism" and not record.roof_mesh.has("uv_origin"):box_key.append(record.position)
		if load_box_meshes.has(box_key): cached=load_box_meshes[box_key].mesh; load_box_hits+=1
	var box:BoxMesh
	var size: Array = record.get("size", [1, 1, 1])
	if cached==null or record.get("building_shape")=="joined_box":
		box=BoxMesh.new()
		box.size=Vector3(float(size[0]),float(size[1]),float(size[2]))
	var color: Array = record.get("color", [])
	if color.size() >= 3 and cached==null:
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.92
		mat.albedo_color = Color(float(color[0]), float(color[1]), float(color[2]))
		if bool(record.get("invisible", false)):
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.0
		box.material = mat
	if cached != null:
		mesh_node.mesh = cached
		if not box_key.is_empty():
			var original:Mesh=load_box_meshes[box_key].source
			var originals:Array=[]
			for slot in original.get_surface_count():originals.append(original.surface_get_material(slot))
			mesh_node.set_meta("paint_source",original);mesh_node.set_meta("paint_source_materials",originals)
	else:
		mesh_node.mesh = preload("res://scripts/world3d/auto_tile_mesh.gd").build(record.tile3d) if record.has("tile3d") else box
		if record.has("road_mesh"): mesh_node.mesh = preload("res://scripts/world3d/road_surface.gd").mesh(record,box.material)
		if record.has("terrain_mesh"): mesh_node.mesh = preload("res://scripts/world3d/terrain_surface.gd").mesh(record,box.material,terrain_neighbors.data.get(str(record.uuid),{}))
		if record.has("channel_mesh"):
			if record.get("surface_id")=="water" and box.material is StandardMaterial3D:
				box.material.roughness=.22; box.material.metallic=.15
			mesh_node.mesh = preload("res://scripts/world3d/channel_surface.gd").mesh(record,box.material)
		if record.get("building_shape")=="wall_grid": mesh_node.mesh = preload("res://scripts/world3d/house_wall_mesh.gd").mesh(record,box.material)
		if record.get("building_shape")=="draped_cloth":mesh_node.mesh=preload("res://scripts/world3d/curtain_mesh.gd").mesh(record,box.material)
		if record.get("building_shape")=="joined_box":mesh_node.mesh=preload("res://scripts/world3d/joined_box_mesh.gd").mesh(record,box.material)
		if record.get("building_shape")=="candle_sconce":mesh_node.mesh=preload("res://scripts/world3d/candle_sconce_mesh.gd").mesh(record,box.material)
		if record.get("building_shape")=="gable": mesh_node.mesh = preload("res://scripts/world3d/building_blueprint.gd").gable_mesh(box.size,box.material)
		if record.get("building_shape")=="cylinder": mesh_node.mesh = preload("res://scripts/world3d/building_blueprint.gd").cylinder_mesh(box.size,box.material)
		if record.get("building_shape")=="roof_prism": mesh_node.mesh = preload("res://scripts/world3d/roof_mesh.gd").mesh(record,box.material)
	if mesh_node.mesh == null:
		mesh_node.mesh = box
		mesh_node.set_meta("tile_error", "自动拼接套件无法读取")
	if record.has("tile3d"): mesh_node.scale = Vector3(float(size[0]), float(size[1]), float(size[2]))
	var position: Array = record.get("position", [0, 0, 0])
	mesh_node.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	var rotation: Array = record.get("rotation", [0, 0, 0])
	mesh_node.rotation_degrees = Vector3(float(rotation[0]), float(rotation[1]), float(rotation[2]))
	if record.has("fixture"): mesh_node.transform=preload("res://scripts/world3d/building_fixtures.gd").transform(record)
	if bool(record.get("invisible", false)):
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var surface_id := str(record.get("surface_id", "ground"))
	var collision := str(record.get("collision", ""))
	if collision == "":
		collision = "block" if surface_id == "block" else "walk"
	var extras := {
		"uuid": str(record.get("uuid", "")),
		"surface_id": surface_id,
		"kind": str(record.get("kind", "box")),
		"rmmo_collision": collision,
	}
	for key in ["event", "item_id", "qty", "name", "appearance", "hostile", "ally", "skills", "respawn_seconds", "level", "hp_max", "atk", "def"]:
		if record.has(key):
			extras[key] = record[key].duplicate(true) if record[key] is Dictionary else record[key]
	if bool(record.get("invisible", false)):
		extras["invisible"] = true
	if str(record.get("target_path", "")) != "":
		extras["target_path"] = str(record.get("target_path", ""))
		extras["spawn"] = record.get("spawn", [0, 0.9, 4])
	if str(record.get("npc_id", "")) != "":
		extras["npc_id"] = str(record.get("npc_id", ""))
		extras["line"] = str(record.get("line", ""))
	if str(record.get("node_id", "")) != "":
		extras["node_id"] = str(record.get("node_id", ""))
	if record.get("seat") is Dictionary:extras["seat"]=record.seat.duplicate(true)
	if record.has("fixture"):
		extras.fixture=record.fixture.duplicate(true)
	if record.has("building"):extras.building=record.building.duplicate(true)
	if record.has("fortification"): extras.fortification=record.fortification.duplicate(true)
	mesh_node.set_meta("extras", extras)
	if record.get("building_shape")=="joined_box":mesh_node.set_meta("collision_solid",box)
	if cached == null:
		SurfaceMaterials.apply(mesh_node, record, load_paint_validation, load_texture_checks)
		if not box_key.is_empty() and load_box_meshes.size()<4096 and not mesh_node.has_meta("paint_error"):
			load_box_meshes[box_key]={"mesh":mesh_node.mesh,"source":mesh_node.get_meta("paint_source",mesh_node.mesh)}
		if not effects and not mesh_node.has_meta("paint_error") and not mesh_node.has_meta("tile_error"):
			_save_meshes.put_mesh(str(record.uuid), signature, mesh_node.mesh)
	if effects: preload("res://scripts/world3d/river_materials.gd").apply(mesh_node,record,terrain_neighbors.data.get(str(record.uuid),{}))
	preload("res://scripts/world3d/wind_response.gd").annotate(mesh_node,record)
	if effects and preload("res://scripts/world3d/ground_batch_geometry.gd").candidate(record): mesh_node.set_meta("ground_batch_record", (record if load_immutable_records else record.duplicate(true)))
	return mesh_node


func add_asset(entry: Dictionary, position: Vector3) -> String:
	checkpoint()
	var id := _push("asset", "model", position, Vector3.ONE)
	records[-1].merge(entry.duplicate(true))
	return id

func missing_assets() -> Array:
	var missing: Array = SurfaceMaterials.missing(records)
	missing.append_array(preload("res://scripts/world3d/auto_tile_kit.gd").missing(records))
	for record in records:
		if record.get("kind") == "asset" and not FileAccess.file_exists(str(record.get("asset_path", ""))): missing.append(str(record.get("asset_path", "")))
	return missing

func _asset(record: Dictionary) -> Node3D:
	var holder := Node3D.new()
	holder.name = str(record.uuid)
	holder.set_meta("asset_uuid", str(record.uuid))
	holder.position = Vector3(record.position[0], record.position[1], record.position[2])
	holder.rotation_degrees = Vector3(record.rotation[0], record.rotation[1], record.rotation[2])
	holder.scale = Vector3(record.size[0], record.size[1], record.size[2])
	var model: Node3D
	if record.has("bridge_mesh"):
		var bridge:=MeshInstance3D.new(); bridge.name="StoneBridge"
		bridge.mesh=preload("res://scripts/world3d/bridge_mesh.gd").new().build(record)
		if bridge.mesh!=null: model=bridge
		else: bridge.free()
	else: model = preload("res://scripts/world_editor/asset_library.gd").instantiate(str(record.get("asset_path", "")))
	if model == null:
		var fallback := MeshInstance3D.new()
		fallback.mesh = BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.MAGENTA
		fallback.material_override = material
		holder.add_child(fallback)
		holder.set_meta("missing_asset", true)
	else:
		holder.add_child(model)
		_namespace_asset(model, str(record.uuid), model, str(record.get("collision","")))
	SurfaceMaterials.apply(holder, record)
	preload("res://scripts/world3d/wind_response.gd").annotate(holder,record)
	return holder

func _namespace_asset(node: Node, prefix: String, asset_root: Node, collision: String="") -> void:
	if node is MeshInstance3D:
		var extras: Dictionary = node.get_meta("extras", {}).duplicate(true)
		extras["uuid"] = prefix + "__" + str(asset_root.get_path_to(node)).replace("/", "__")
		if collision in ["none","walk","block"]: extras["rmmo_collision"]=collision
		node.set_meta("extras", extras)
	for child in node.get_children(): _namespace_asset(child, prefix, asset_root, collision)
