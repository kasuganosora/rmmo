extends RefCounted
## Full map record. The scene tree is only a view of these records.

const WorldLocation = preload("res://scripts/world3d/world_location.gd")
const GltfMapIo = preload("res://scripts/world3d/gltf_map_io.gd")
const SurfaceMaterials = preload("res://scripts/world3d/surface_materials.gd")
const CpuMesh = preload("res://scripts/world3d/ground_cpu_mesh.gd")
static var legacy_mesh_placeholder_enabled:=false # Same-code measurement of superseded GPU bindings.
static var white_entry_material_reuse_enabled:=true # Diagnostic old white-entry fallback material control.

var records: Array = []
var map_meta: Dictionary = {}
var _next := 1
var _disk_path := ""
var _disk_signature := ""
var editor_dirty := false
var terrain_neighbors=preload("res://scripts/world3d/terrain_neighbors.gd").new()
var _save_meshes = preload("res://scripts/world3d/save_mesh_cache.gd").new()
# Immutable load/build operations supply these caches and restore their scope.
# Editable documents leave them null so later edits recheck paths and textures.
var load_paint_validation: Variant=null
var load_material_pool: Variant=null
var load_texture_checks: Variant=null
var load_box_meshes: Variant=null
var load_box_hits:=0
var load_model_signatures:Dictionary={}
var load_immutable_records:=false
var load_require_native_products:=false # Game-owned documents prohibit raw imports; editor documents can import.
var load_surface_arrays:Dictionary={}
var load_surface_bounds:Dictionary={}
var load_surface_paints:Dictionary={}
var load_surface_uploads:Dictionary={}
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
## Session-only candidate revision. Never persisted or restored by undo.
var authoring_revision:=0


func checkpoint() -> void:
	commit_change(records)


func commit_change(before: Array) -> void:
	commit_owned_snapshot(before.duplicate(true))


func commit_owned_snapshot(before: Array) -> void:
	# Takes an already independent deep snapshot. The caller must discard its
	# reference without clearing/mutating the array after transferring ownership.
	assert(not is_same(before, records), "Cannot transfer live document records into history")
	authoring_revision+=1
	_undo.append(before)
	_redo.clear()
	if _undo.size() > 32:
		_undo.pop_front()


func undo() -> bool:
	if _undo.is_empty():
		return false
	var state: Variant = _undo.pop_back()
	authoring_revision+=1
	_redo.append(recovery_snapshot() if state is Dictionary else records.duplicate(true))
	if state is Dictionary: apply_recovery(state)
	else: records = state
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var state: Variant = _redo.pop_back()
	authoring_revision+=1
	_undo.append(recovery_snapshot() if state is Dictionary else records.duplicate(true))
	if state is Dictionary: apply_recovery(state)
	else: records = state
	return true


func recovery_snapshot() -> Dictionary:
	return {"records": records.duplicate(true), "map_meta": map_meta.duplicate(true), "next": _next, "disk_path": _disk_path, "disk_signature": _disk_signature}


func commit_recovery_change(before:Dictionary)->void:
	authoring_revision+=1
	_undo.append(before.duplicate(true));_redo.clear()
	if _undo.size()>32:_undo.pop_front()


func checkpoint_recovery() -> void:
	authoring_revision+=1
	_undo.append(recovery_snapshot())
	_redo.clear()
	if _undo.size() > 32: _undo.pop_front()


func apply_recovery(state: Dictionary) -> void:
	authoring_revision+=1
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
	var previous_context:Array=[load_paint_validation,load_texture_checks,load_box_meshes,load_model_signatures,load_material_pool]
	load_paint_validation={};load_texture_checks={};load_box_meshes={};load_model_signatures={};load_material_pool={}
	var world := export_root()
	terrain_neighbors.update(records)
	if not effects: _save_meshes.begin(records)
	for record in records:
		world.add_child(_asset(record) if record.get("kind") == "asset" else _mesh(record,effects))
	load_paint_validation=previous_context[0];load_texture_checks=previous_context[1];load_box_meshes=previous_context[2]
	load_model_signatures=previous_context[3]
	load_material_pool=previous_context[4]
	return world


func export_root(export_records: Variant = null) -> Node3D:
	var world := Node3D.new()
	world.name = "rmmo_world"
	var extras := {
		"rmmo_format": WorldLocation.FORMAT,
		"rmmo_version": WorldLocation.FORMAT_VERSION,
		"rmmo_unit": "m",
	}
	for key in map_meta.keys():
		extras[key] = map_meta[key]
	extras["rmmo_records"] = (records if export_records==null else export_records).duplicate(true)
	world.set_meta("extras", extras)
	return world


func save(gltf_path: String) -> Error:
	var started := Time.get_ticks_usec()
	last_save_metrics = {}
	var err := validate_save()
	last_save_metrics.validate_ms = (Time.get_ticks_usec()-started)/1000.0
	if err != OK:
		last_save_metrics.total_ms = (Time.get_ticks_usec()-started)/1000.0
		return err
	# Author records stay editable in memory. Only the persisted representation
	# contains immutable references and ordinary glTF placement proxies.
	var phase := Time.get_ticks_usec()
	var published:Dictionary = preload("res://scripts/world3d/reference_map_save.gd").save(
		gltf_path, save_signature(gltf_path), records, map_meta,
		preload("res://scripts/world3d/map_paths.gd").external_root(), GltfMapIo)
	last_save_metrics.publish_ms = (Time.get_ticks_usec()-phase)/1000.0
	last_save_metrics.export = published
	last_save_metrics.total_ms = (Time.get_ticks_usec()-started)/1000.0
	if published.error == OK: accept_save(gltf_path,published.signature)
	return published.error


func validate_save(progress: Callable = Callable()) -> Error:
	var err := validate_save_meta()
	if err != OK: return err
	var checked := 0
	var material_validation:Dictionary={}
	var asset_validation:Dictionary={}
	for record in records:
		if progress.is_valid(): progress.call("validate", checked, records.size())
		err = validate_save_record(record,material_validation,asset_validation)
		if err != OK: return err
		checked += 1
	return validate_save_asset_paths(asset_validation)


func validate_save_meta() -> Error:
	if not preload("res://scripts/world3d/city_layout.gd").valid(map_meta): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_meta(map_meta): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_ownership(map_meta,records): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/editor_view_settings.gd").valid(map_meta): return ERR_INVALID_DATA
	if not missing_assets().is_empty(): return ERR_FILE_NOT_FOUND
	if not preload("res://scripts/world3d/environment_settings.gd").valid(map_meta): return ERR_INVALID_DATA
	return OK


func validate_save_record(record: Dictionary, material_validation:Variant=null, asset_validation:Variant=null) -> Error:
	if not preload("res://scripts/world3d/model_components.gd").valid(record):return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/parametric_tree.gd").valid(record):return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/event_templates.gd").valid_record(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_record(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/auto_tile_rules.gd").valid(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/road_surface.gd").valid(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/terrain_surface.gd").valid(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/channel_surface.gd").valid(record): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/fortification_data.gd").valid_record(record): return ERR_INVALID_DATA
	if not SurfaceMaterials.valid(record,false,"",material_validation): return ERR_INVALID_DATA
	if not preload("res://scripts/world3d/wind_response.gd").valid(record): return ERR_INVALID_DATA
	if record.get("kind") == "asset":
		var path:=str(record.get("asset_path",""))
		# A caller-owned cache lasts for this immutable validation only. A forest
		# of instances should not reopen the same path's ancestors per instance.
		if asset_validation==null or not asset_validation.has(path):
			if not preload("res://scripts/world3d/map_paths.gd").allowed(path):return ERR_INVALID_DATA
		if not preload("res://scripts/world3d/runtime_package_policy.gd").trusted() and not preload("res://scripts/world3d/imported_building.gd").verify_source(record):return ERR_FILE_CORRUPT
		if asset_validation!=null:
			var required:=preload("res://scripts/world3d/house_prefab.gd").requires_source_model(record)
			asset_validation[path]=bool(asset_validation.get(path,false)) or required
	return OK


func validate_save_asset_paths(asset_validation:Dictionary) -> Error:
	# Repeat path authority and existence after any sliced validation yields;
	# neither a previous save nor a stale in-pass cache authorizes publication.
	for path:String in asset_validation:
		if not preload("res://scripts/world3d/map_paths.gd").allowed(path):return ERR_INVALID_DATA
		if asset_validation[path] and not FileAccess.file_exists(path):return ERR_FILE_NOT_FOUND
	# Room/member proofs checked before a sliced yield must still refer to the
	# same immutable bytes immediately before publication.
	var verified:Dictionary={}
	for record:Dictionary in records:
		if not record.has("model_building"):continue
		var path:String=str(record.get("asset_path",""))
		if not asset_validation.has(path):return ERR_INVALID_DATA
		if not verified.has(path):verified[path]=FileAccess.get_sha256(path)
		if verified[path]!=record.model_building.source_sha:return ERR_FILE_CORRUPT
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


static func open_file(gltf_path: String, prepared: Dictionary = {}, progress: Callable = Callable(), allow_legacy_migration: bool = false):
	var cursor=preload("res://scripts/world3d/document_open_cursor.gd").new()
	cursor.begin_document(gltf_path,prepared,false,progress,allow_legacy_migration)
	while not cursor.done:cursor.advance()
	return cursor.document


static func authoritative_extras(path: String, parsed: Variant = null, metadata_only: bool = false) -> Dictionary:
	# Like MapLoader, native editor records are authoritative. Importing thousands
	# of duplicate exported meshes just to discard them makes reopening a street
	# take minutes. Legacy/imported/transformed roots retain the GLTF import path.
	if path.get_extension().to_lower()!="gltf" or not FileAccess.file_exists(path):return {}
	if not preload("res://scripts/world3d/map_paths.gd").allowed(path):return {"error":"map outside content root"}
	var signature:=FileAccess.get_sha256(path)
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if parsed==null else parsed
	if not data is Dictionary:return {"error":"invalid JSON"}
	var validation=preload("res://scripts/world3d/document_open_cursor.gd")
	var root_index:int=validation.native_root(data)
	if root_index<0:return {"error":"native map needs explicit migration"} if validation.claims_native(data) else {}
	for section in ["buffers","images"]:
		if not data.get(section,[]) is Array:return {"error":"invalid dependencies"}
		for dependency in data.get(section,[]):
			var issue:String=validation.dependency_issue(path,dependency,true,section=="buffers")
			if not issue.is_empty():return {"error":issue}
	var extra:Dictionary=data.nodes[root_index].extras
	if metadata_only:
		# Weather needs only map metadata; never expose compact records as if
		# they were complete authoring records to callers of this shared API.
		extra=extra.duplicate();extra.erase("rmmo_records")
	else:
		var restored:Dictionary=validation.hydrate_references(extra,path,preload("res://scripts/world3d/map_paths.gd").external_root(),4,preload("res://scripts/world3d/runtime_package_policy.gd").trusted())
		if not restored.get("ok",false):return {"error":str(restored.get("reason","invalid reference map"))}
		extra=restored.extras
	if FileAccess.get_sha256(path)!=signature:return {"error":"map changed while reading"}
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


func _mesh(record: Dictionary, effects: bool=true, timings: Variant=null) -> MeshInstance3D:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_document._mesh") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var profile_mark:int=Time.get_ticks_usec() if timings!=null else 0
	var cpu_index:bool=effects and load_immutable_records and (preload("res://scripts/world3d/ground_batch_geometry.gd").candidate(record) or (record.has("water_depth_effect") and preload("res://scripts/world3d/river_materials.gd").water_cpu_index_enabled))
	# Mounted package declarations were prepared by the loader. Actual material
	# construction still resolves its textures; editing/strict calls keep preflight.
	var trusted_texture_load:bool=effects and load_immutable_records and preload("res://scripts/world3d/runtime_package_policy.gd").trusted()
	# This immutable white entry is never used for authored material restoration.
	# Its effective material was already the global white override; retain that
	# exact shared material in the CPU slots instead of constructing hidden colors.
	var white_prepared:bool=white_entry_material_reuse_enabled and cpu_index and preload("res://scripts/world3d/runtime_probe_controls.gd").white_materials and load_surface_arrays.has(str(record.get("uuid","")))
	if record.has("house_prefab"):
		var prefab=preload("res://scripts/world3d/house_prefab.gd")
		# Runtime indexing consumes immutable CPU geometry. Upload only when the
		# stream actually instantiates a component, not once for every recipe row.
		var visual:MeshInstance3D=prefab.visual(record,effects and not load_immutable_records,load_paint_validation,load_material_pool,timings)
		if timings!=null:timings.prefab_visual_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
		var texture_error:="" if trusted_texture_load else SurfaceMaterials.texture_error(record,load_texture_checks)
		if not texture_error.is_empty():visual.set_meta("paint_error",texture_error)
		if timings!=null:timings.texture_validation_ms=(Time.get_ticks_usec()-profile_mark)/1000.
		# Immutable payloads already live in the document. Duplicating the entire
		# town into the disposable geometry cache exceeds its bounded file budget.
		return visual
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = str(record.get("uuid", "box"))
	if record.has("terrain_mesh"):
		var texture_error:="" if trusted_texture_load else SurfaceMaterials.texture_error(record,load_texture_checks)
		if not texture_error.is_empty():mesh_node.set_meta("paint_error",texture_error)
		if timings!=null:timings.texture_validation_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
	var signature: String = _save_meshes.key(record, terrain_neighbors.data.get(str(record.uuid), {})) if not effects else ""
	var cached: Mesh = _save_meshes.get_mesh(str(record.uuid), signature) if not effects else null
	var box_key:Array=[]
	if effects and load_box_meshes!=null and not record.has("fortification_art"):
		for field in ["terrain_mesh","terrain_volume","road_mesh","channel_mesh","rock_bank"]:
			if not record.has(field):continue
			# Cache editable source geometry before dynamic water/slope overlays.
			# Context normals cover shared terrain edges; the full record includes
			# holes, furrows, UV scale, paint and material dependencies.
			box_key=[field,record,terrain_neighbors.data.get(str(record.uuid),{}).get("normals",{})]
			if load_box_meshes.has(box_key):cached=load_box_meshes[box_key].mesh;load_box_hits+=1
			break
	if effects and load_box_meshes!=null and not ["tile3d","road_mesh","terrain_mesh","terrain_volume","channel_mesh","rock_bank","fortification_art"].any(func(field):return record.has(field)) and record.get("building_shape","") in ["","cylinder","gable","wall_grid","draped_cloth","joined_box","roof_prism","candle_sconce","timber_door","interior_door","interior_door_frame"]:
		# Native Variant hashing/equality handles collisions without serializing
		# every repeated material and face to an indented string on every object.
		box_key=[record.get("water_gate",{}),record.get("terrain_grade",[]),record.get("building_shape",""),record.get("size",[1,1,1]),record.get("color",[]),record.get("invisible",false),record.get("surface_paint",[])]
		# Repeated houses also share immutable custom geometry. Include every
		# topology/UV input, never UUID, floor identity or fixture state/pose.
		for field in ["wall_grid","cloth","box_faces","roof_mesh"]:
			box_key.append(record.get(field))
		if record.get("building_shape")=="roof_prism" and not record.roof_mesh.has("uv_origin"):box_key.append(record.position)
		if load_box_meshes.has(box_key): cached=load_box_meshes[box_key].mesh; load_box_hits+=1
	if effects and load_box_meshes!=null and record.has("fortification_art") and str(record.fortification_art.asset_path).get_extension().to_lower()=="glb":
		var model_path:String=record.fortification_art.asset_path
		if not load_model_signatures.has(model_path):
			if load_require_native_products and preload("res://scripts/world3d/runtime_package_policy.gd").trusted():
				var metadata:=preload("res://scripts/world3d/native_model_product.gd").read(model_path,preload("res://scripts/world3d/map_paths.gd").external_root(),"",-1)
				if metadata.is_empty():
					mesh_node.set_meta("paint_error","游戏模型缺少可用原生描述，请在内容编辑器重新导出："+model_path)
					return mesh_node
				load_model_signatures[model_path]=metadata.native_source_sha
			else:load_model_signatures[model_path]=FileAccess.get_sha256(model_path)
		box_key=["fortification",record.size,record.get("channel_mesh",{}),record.get("terrain_grade",[]),record.get("water_gate",{}),record.fortification_art,record.fortification_materials,record.get("surface_paint",[]),load_model_signatures[model_path]]
		if load_box_meshes.has(box_key):cached=load_box_meshes[box_key].mesh;load_box_hits+=1
	var box:BoxMesh
	var size: Array = record.get("size", [1, 1, 1])
	if cached==null or record.get("building_shape") in ["joined_box","timber_door","interior_door"]:
		box=BoxMesh.new()
		box.size=Vector3(float(size[0]),float(size[1]),float(size[2]))
	var color: Array = record.get("color", [])
	if white_prepared and cached==null:
		box.material=preload("res://scripts/world3d/runtime_probe_controls.gd").white_material()
	elif color.size() >= 3 and cached==null:
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.92
		mat.albedo_color = Color(float(color[0]), float(color[1]), float(color[2]))
		if bool(record.get("invisible", false)):
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.0
		box.material = mat
	if not white_prepared and record.has("channel_mesh") and not record.has("fortification_art") and record.get("surface_id")=="water" and box!=null and box.material is StandardMaterial3D:
		box.material.roughness=.22;box.material.metallic=.15
	var geometry_started:int=Time.get_ticks_usec() if timings!=null else 0
	if cached != null:
		mesh_node.mesh = cached
		if not box_key.is_empty():
			var original:Mesh=load_box_meshes[box_key].source
			var originals:Array=[]
			for slot in original.get_surface_count():originals.append(original.surface_get_material(slot))
			mesh_node.set_meta("paint_source",original);mesh_node.set_meta("paint_source_materials",originals)
	elif record.has("rock_bank") and load_surface_arrays.has(str(record.uuid)):
		mesh_node.mesh=preload("res://scripts/world3d/rock_bank_mesh.gd").mesh(record,load_surface_arrays[str(record.uuid)])
	elif load_surface_arrays.has(str(record.uuid)):
		var prepared:Mesh
		if timings!=null:timings.setup_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
		var channel_geometry:bool=preload("res://scripts/world3d/channel_mesh_preparation.gd").supports(record)
		var material:Material=preload("res://scripts/world3d/runtime_probe_controls.gd").white_material() if white_prepared else (SurfaceMaterials.make_material(record.terrain_material,BaseMaterial3D.CULL_BACK) if record.has("terrain_material") and not channel_geometry else box.material)
		if timings!=null:timings.material_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
		var arrays:Array=load_surface_arrays[str(record.uuid)]
		var slot_materials:Array=[]
		for slot in arrays.size():slot_materials.append(preload("res://scripts/world3d/road_surface.gd").kerb_material(record) if not white_prepared and (record.has("road_mesh") or channel_geometry) and slot==3 else material)
		if cpu_index and load_surface_bounds.has(str(record.uuid)):
			prepared=preload("res://scripts/world3d/procedural_surface_bounds.gd").make_cpu(arrays,slot_materials,load_surface_bounds[str(record.uuid)])
		elif cpu_index:prepared=preload("res://scripts/world3d/ground_cpu_mesh.gd").from_surfaces(arrays,slot_materials)
		else:
			prepared=ArrayMesh.new()
			for slot in arrays.size():
				prepared.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays[slot])
				prepared.surface_set_material(slot,slot_materials[slot])
				prepared.surface_set_name(slot,(["volume_terrain"] if record.has("terrain_volume") else (["terrain","bedrock_and_cut_edges","cultivation"] if record.has("terrain_mesh") else ["pavement","underside","edge","automatic_kerb"]))[slot])
			if record.has("road_mesh") or record.has("terrain_mesh"):preload("res://scripts/world3d/ground_cpu_mesh.gd").remember(prepared,arrays)
		if cpu_index and load_surface_uploads.has(str(record.uuid)):
			preload("res://scripts/world3d/prepared_cpu_upload.gd").attach(prepared,load_surface_uploads[str(record.uuid)])
		mesh_node.mesh=prepared
		if timings!=null:timings.arraymesh_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
	else:
		var geometry:Mesh = preload("res://scripts/world3d/auto_tile_mesh.gd").build(record.tile3d) if record.has("tile3d") else box
		# Bind only the final geometry; assigning a disposable box uploads it and
		# can wait for the renderer before the real procedural mesh is prepared.
		if legacy_mesh_placeholder_enabled:mesh_node.mesh=geometry
		if timings!=null:timings.placeholder_ms=(Time.get_ticks_usec()-geometry_started)/1000.;timings.record_shape=record.get("building_shape","")
		if record.has("road_mesh"): geometry = preload("res://scripts/world3d/road_surface.gd").mesh(record,box.material)
		if record.has("terrain_volume"):geometry=preload("res://scripts/world3d/terrain_volume.gd").mesh(record,box.material)
		if record.has("terrain_mesh"): geometry = preload("res://scripts/world3d/terrain_surface.gd").mesh(record,box.material,terrain_neighbors.data.get(str(record.uuid),{}))
		if record.has("rock_bank"): geometry = preload("res://scripts/world3d/rock_bank_mesh.gd").mesh(record)
		if record.has("channel_mesh") and not record.has("fortification_art"):
			geometry = preload("res://scripts/world3d/channel_surface.gd").mesh(record,box.material)
		if record.has("water_gate") and not record.has("fortification_art"):geometry=preload("res://scripts/world3d/water_gate_mesh.gd").mesh(record,box.material)
		if record.has("fortification_art"): geometry=preload("res://scripts/world3d/fortification_art.gd").new().build(record,load_require_native_products)
		if record.get("building_shape")=="wall_grid": geometry = preload("res://scripts/world3d/house_wall_mesh.gd").mesh(record,box.material)
		if record.get("building_shape")=="draped_cloth":geometry=preload("res://scripts/world3d/curtain_mesh.gd").mesh(record,box.material)
		if record.get("building_shape")=="joined_box":geometry=preload("res://scripts/world3d/joined_box_mesh.gd").mesh(record,box.material)
		if record.get("building_shape")=="candle_sconce":
			var sconce=preload("res://scripts/world3d/candle_sconce_mesh.gd")
			var candle_began:=Time.get_ticks_usec() if timings!=null else 0
			var candle_mesh:Mesh=sconce.cpu_mesh(record) if effects and load_immutable_records and sconce.cpu_index_enabled else sconce.mesh(record,box.material)
			if timings!=null:timings.candle_prepare_ms=(Time.get_ticks_usec()-candle_began)/1000.;candle_began=Time.get_ticks_usec()
			geometry=candle_mesh
			if timings!=null:timings.candle_bind_ms=(Time.get_ticks_usec()-candle_began)/1000.
		if record.get("building_shape") in ["interior_door","interior_door_frame"]:geometry=preload("res://scripts/world3d/interior_door_mesh.gd").mesh(record)
		if record.get("building_shape")=="timber_door":geometry=preload("res://scripts/world3d/timber_door_mesh.gd").mesh(record,box.material)
		if record.get("building_shape")=="gable": geometry = preload("res://scripts/world3d/building_blueprint.gd").gable_mesh(box.size,box.material)
		if record.get("building_shape")=="cylinder": geometry = preload("res://scripts/world3d/building_blueprint.gd").cylinder_mesh(box.size,box.material)
		if record.get("building_shape")=="roof_prism": geometry = preload("res://scripts/world3d/roof_mesh.gd").mesh(record,box.material)
		var bind_began:=Time.get_ticks_usec() if timings!=null else 0
		mesh_node.mesh=geometry
		if timings!=null:timings.geometry_bind_ms=(Time.get_ticks_usec()-bind_began)/1000.
	if record.has("terrain_grade") and (not record.has("channel_mesh") or record.has("fortification_art")) and cached==null and mesh_node.mesh!=null:mesh_node.mesh=preload("res://scripts/world3d/fortification_terrain.gd").deform(mesh_node.mesh,record.terrain_grade)
	if mesh_node.mesh == null:
		if record.get("building_shape") in ["timber_door","interior_door","interior_door_frame"]:mesh_node.set_meta("paint_error","木门模型或木纹资源缺失，无法烘焙")
		mesh_node.mesh = box
		mesh_node.set_meta("tile_error", "自动拼接套件无法读取")
	if timings!=null:timings.geometry_total_ms=(Time.get_ticks_usec()-geometry_started)/1000.;profile_mark=Time.get_ticks_usec()
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
	# Transparent water is excluded from ground batching, but remains part of
	# the landscape's long-distance residency. Keep that semantic independently.
	if record.has("channel_mesh"):extras.rmmo_landscape_kind="channel"
	mesh_node.set_meta("extras", extras)
	if record.get("building_shape") in ["joined_box","timber_door","interior_door"]:mesh_node.set_meta("collision_solid",box)
	if cached == null:
		if timings!=null:timings.metadata_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
		SurfaceMaterials.apply(mesh_node, record, load_paint_validation, load_texture_checks,cpu_index,load_surface_paints.get(str(record.uuid),{}) if load_immutable_records else {})
		if timings!=null:timings.surface_paint_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
		if not box_key.is_empty() and load_box_meshes.size()<4096 and not mesh_node.has_meta("paint_error"):
			load_box_meshes[box_key]={"mesh":mesh_node.mesh,"source":mesh_node.get_meta("paint_source",mesh_node.mesh)}
		if not effects and not mesh_node.has_meta("paint_error") and not mesh_node.has_meta("tile_error"):
			_save_meshes.put_mesh(str(record.uuid), signature, mesh_node.mesh)
	if effects:
		if timings!=null:timings.geometry_cache_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
		var river_context:Dictionary=terrain_neighbors.data.get(str(record.uuid),{}).duplicate()
		river_context.texture_checks=load_texture_checks
		# Water keeps separate rendering/transparency, but its directory entry
		# can retain CPU geometry and slot materials until the actual stream spawn.
		preload("res://scripts/world3d/river_materials.gd").apply(mesh_node,record,river_context,load_paint_validation,load_immutable_records,cpu_index)
		if white_prepared and mesh_node.mesh is CpuMesh:
			var white:Material=preload("res://scripts/world3d/runtime_probe_controls.gd").white_material()
			var redundant:bool=mesh_node.material_override==white and not mesh_node.mesh.materials.is_empty()
			for slot in mesh_node.mesh.materials.size():
				redundant=redundant and mesh_node.mesh.materials[slot]==white and mesh_node.get_surface_override_material(slot)==null
			# A redundant override would make every cooked spec fall back to _mesh
			# on the next load. Only erase it when all effective slots are identical.
			if redundant:mesh_node.material_override=null
		if timings!=null:timings.river_ms=(Time.get_ticks_usec()-profile_mark)/1000.;profile_mark=Time.get_ticks_usec()
	preload("res://scripts/world3d/wind_response.gd").annotate(mesh_node,record)
	if effects and preload("res://scripts/world3d/ground_batch_geometry.gd").candidate(record): mesh_node.set_meta("ground_batch_record", (record if load_immutable_records else record.duplicate(true)))
	if timings!=null:timings.final_ms=(Time.get_ticks_usec()-profile_mark)/1000.
	return mesh_node


func add_asset(entry: Dictionary, position: Vector3) -> String:
	checkpoint()
	var id := _push("asset", "model", position, Vector3.ONE)
	records[-1].merge(entry.duplicate(true))
	return id

func missing_assets() -> Array:
	# River restoration snapshots keep the overwritten slope/depth materials.
	# They are save dependencies even when the current rendered record no longer
	# uses them; share one discovery pass so repeated texture paths are deduped.
	var river=preload("res://scripts/world3d/terrain_river_layer.gd")
	var snapshots:Array=river.snapshot_records(map_meta) if river.valid(map_meta) else []
	var missing: Array = SurfaceMaterials.missing(records if snapshots.is_empty() else records+snapshots)
	missing.append_array(preload("res://scripts/world3d/auto_tile_kit.gd").missing(records))
	var checked:Dictionary={}
	for record in records:
		if record.get("kind")!="asset":continue
		if not preload("res://scripts/world3d/house_prefab.gd").requires_source_model(record):continue
		var path:=str(record.get("asset_path",""))
		if not checked.has(path):checked[path]=FileAccess.file_exists(path)
		if not checked[path]:missing.append(path)
	return missing

func _asset(record: Dictionary, prepared: Dictionary = {}) -> Node3D:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_document._asset") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if record.has("house_prefab"):return _mesh(record)
	var context:=_begin_asset_instance(record,prepared)
	var holder:Node3D=context.holder;var model:Node3D=context.model
	if model!=null:
		_namespace_asset(model,str(record.uuid),model,str(record.get("collision","")))
		preload("res://scripts/world3d/model_components.gd").apply(model,record,preload("res://scripts/world3d/runtime_package_policy.gd").trusted())
		_asset_components_ready(holder,model)
	return _finish_asset_instance(holder,record)

func _begin_asset_instance(record:Dictionary,prepared:Dictionary)->Dictionary:
	var holder := Node3D.new()
	holder.name = str(record.uuid)
	holder.set_meta("asset_uuid", str(record.uuid))
	holder.position = Vector3(record.position[0], record.position[1], record.position[2])
	holder.rotation_degrees = Vector3(record.rotation[0], record.rotation[1], record.rotation[2])
	holder.scale = Vector3(record.size[0], record.size[1], record.size[2])
	var model: Node3D
	if record.has("bridge_mesh"):
		var bridge:=MeshInstance3D.new(); bridge.name="StoneBridge"
		bridge.mesh=preload("res://scripts/world3d/bridge_mesh.gd").new().build(record,load_require_native_products)
		if bridge.mesh!=null: model=bridge
		else: bridge.free()
	# Async loads pass an independently instantiated scene, including null for a
	# failed import. No persistent negative cache hides a later repaired file.
	elif prepared.has("scene"): model = prepared.scene
	# A cached load pins its checked allocation across the editor's publication
	# awaits. Never replace it with a different global template at the same path.
	elif prepared.has("template"):
		var template:Variant=prepared.template
		if template is PackedScene:model=preload("res://scripts/world_editor/asset_library.gd")._instantiate(template)
	else: model = preload("res://scripts/world_editor/asset_library.gd").instantiate(str(record.get("asset_path", "")),load_require_native_products)
	if model == null:
		var fallback := MeshInstance3D.new()
		fallback.mesh = BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.MAGENTA
		fallback.material_override = material
		holder.add_child(fallback)
		holder.set_meta("missing_asset", true)
		if load_require_native_products:holder.set_meta("paint_error","游戏模型缺少可用原生产物，请在内容编辑器重新导出："+str(record.get("asset_path","")))
	else:
		holder.add_child(model)
		var tree_error:=preload("res://scripts/world3d/parametric_tree.gd").apply(model,record)
		if not tree_error.is_empty():holder.set_meta("paint_error",tree_error)
	return {"holder":holder,"model":model}

static func _asset_components_ready(holder:Node3D,model:Node3D)->void:
	if model.has_meta("model_components_error"):holder.set_meta("paint_error",str(model.get_meta("model_components_error")))
	if model.has_meta("model_component_batch_sources"):
		holder.set_meta("model_component_batch_sources",model.get_meta("model_component_batch_sources"))

func _finish_asset_instance(holder:Node3D,record:Dictionary)->Node3D:
	var cursor:=begin_asset_finish(holder,record)
	cursor.advance(0)
	return cursor.take_holder()

func begin_asset_finish(holder:Node3D,record:Dictionary,model_nodes:Array[Node]=[])->RefCounted:
	var cursor:=preload("res://scripts/world3d/asset_finish_preparation.gd").new()
	cursor.begin(self,holder,record,model_nodes)
	return cursor

func _namespace_asset(node: Node, prefix: String, asset_root: Node, collision: String="") -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.world_document._namespace_asset") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_namespace_asset_node(node,prefix,asset_root,collision)
	for child in node.get_children():_namespace_asset(child,prefix,asset_root,collision)

static func _namespace_asset_node(node:Node,prefix:String,asset_root:Node,collision:String)->void:
	if node is MeshInstance3D:
		var extras: Dictionary = node.get_meta("extras", {}).duplicate(true)
		if extras.has("uuid") and (extras.get("rmmo_part") is Dictionary if preload("res://scripts/world3d/runtime_package_policy.gd").trusted() else preload("res://scripts/world3d/imported_building.gd").valid_part(extras.get("rmmo_part"))):extras.rmmo_source_uuid=extras.uuid
		extras["uuid"] = prefix + "__" + str(asset_root.get_path_to(node)).replace("/", "__")
		if collision in ["none","walk","block"]: extras["rmmo_collision"]=collision
		node.set_meta("extras", extras)
