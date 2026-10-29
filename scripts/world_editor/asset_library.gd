extends RefCounted
## Imports become self-contained, immutable GLBs outside the source repository.
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const Compiled = preload("res://scripts/world3d/compiled_asset_cache.gd")
var entries: Array = []
var directory := ""
var _revision := ""
static var _scenes := {}
static var _compiled_imports:Dictionary={}

func _init(folder: String = "") -> void:
	directory = folder if not folder.is_empty() else preload("res://scripts/world3d/map_paths.gd").cache_directory("asset_library")
	var path := directory.path_join("library.json")
	if FileAccess.file_exists(path):
		_revision = FileAccess.get_sha256(path)
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if raw is Array:
			for entry in raw:
				if entry is Dictionary and (entry.get("asset_path") is String or entry.get("prefab_path") is String) and entry.get("label") is String:
					for key in ["asset_path", "prefab_path", "thumbnail_path"]:
						if entry.get(key) is String and not str(entry[key]).is_absolute_path():
							entry[key] = directory.path_join(str(entry[key])).simplify_path()
					entries.append(entry)

func import_file(path: String) -> Dictionary:
	if path.get_extension().to_lower() not in ["gltf", "glb"] or not FileAccess.file_exists(path): return {"ok": false, "error": "请选择存在的 glTF / GLB 文件"}
	# Prefab capture may re-import the exact immutable model just added here.
	# Only reuse a catalogued, content-addressed file after verifying its bytes.
	var normalized:=path.simplify_path().replace("\\","/")
	if normalized.get_base_dir()==directory.simplify_path().replace("\\","/") and normalized.get_extension()=="glb":
		for entry in entries:
			if str(entry.get("asset_path","")).simplify_path().replace("\\","/")==normalized and FileAccess.get_sha256(path)==normalized.get_file().get_basename():
				var contract:Dictionary=preload("res://scripts/world3d/imported_building.gd").source_descriptor(path,normalized.get_file().get_basename())
				if not contract.is_empty() and not preload("res://scripts/world3d/imported_building.gd").same(contract,entry.get("model_building",{})):break
				if contract.is_empty() and entry.has("model_building"):return {"ok":false,"error":"素材库建筑合同与源文件不一致"}
				var compiled:=_compile_import(str(entry.asset_path))
				var gate:=_import_product_gate(path,compiled,contract)
				if not gate.ok:return {"ok":false,"error":"模型原生转换失败："+str(gate.reason),"compiled_asset":compiled}
				return {"ok":true,"entry":entry,"compiled_asset":compiled}
	DirAccess.make_dir_recursive_absolute(directory)
	var staging := directory.path_join("import_%d.glb" % Time.get_ticks_usec())
	var prepared:Compiled.PreparedSource
	var reexport_parses:=0
	var err: Error
	if preload("res://scripts/world3d/embedded_glb.gd").can_copy(path):
		# Validate the copy, not an earlier version of a concurrently replaced source.
		err = DirAccess.copy_absolute(path, staging)
		if err == OK and not preload("res://scripts/world3d/embedded_glb.gd").can_copy(staging): err = ERR_FILE_CORRUPT
		if err == OK:
			prepared=Compiled.prepare_source(staging)
			err=prepared.error
	else:
		var doc:=GLTFDocument.new();var state:=GLTFState.new()
		reexport_parses+=1
		err = doc.append_from_file(path, state, 0, path.get_base_dir())
		if err == OK:
			Io.preserve_node_morph_defaults(state)
			err = doc.write_to_filesystem(state, staging)
		# Export can rewrite geometry, textures and node morph defaults. Only a
		# parse of those final bytes can supply the bounds and native product.
		preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
		state=null;doc=null
		if err==OK:
			prepared=Compiled.prepare_source(staging)
			err=prepared.error
	if err != OK:
		if prepared!=null:prepared.dispose()
		if FileAccess.file_exists(staging): DirAccess.remove_absolute(staging)
		return {"ok": false, "error": "模型或依赖读取失败：" + error_string(err)}
	var hash := prepared.source_digest
	var authored_scene:Node3D=prepared.get_scene()
	var building:Dictionary=preload("res://scripts/world3d/imported_building.gd").describe(authored_scene) if authored_scene!=null else {}
	if authored_scene!=null and preload("res://scripts/world3d/imported_building.gd").opted(authored_scene) and building.is_empty():
		prepared.dispose();DirAccess.remove_absolute(staging)
		return {"ok":false,"error":"导入建筑的分件或室内区域合同无效"}
	if not building.is_empty():
		building.source_sha=hash
		var source_building:Dictionary=preload("res://scripts/world3d/imported_building.gd").source_descriptor(staging,hash)
		if not preload("res://scripts/world3d/imported_building.gd").same(building,source_building):
			prepared.dispose();DirAccess.remove_absolute(staging)
			return {"ok":false,"error":"导入建筑的源文件与原生分件合同不一致"}
	authored_scene=null
	var target := directory.path_join(hash + ".glb")
	if FileAccess.file_exists(target):
		# A content-addressed pathname is not proof that its bytes are intact.
		if FileAccess.get_sha256(target)!=hash:
			prepared.dispose();DirAccess.remove_absolute(staging)
			return {"ok":false,"error":"已有同名素材的内容校验失败"}
		DirAccess.remove_absolute(staging)
	else:
		err = DirAccess.rename_absolute(staging, target)
		if err != OK:
			prepared.dispose()
			if FileAccess.file_exists(staging):DirAccess.remove_absolute(staging)
			return {"ok": false, "error": error_string(err)}
	if not prepared.relocate(target):
		prepared.dispose()
		return {"ok":false,"error":"导入模型在发布前发生变化"}
	for entry in entries:
		if entry.get("asset_path") == target:
			var existing_compiled:=_compile_import(target,prepared)
			var existing_diagnostics:=prepared.report();existing_diagnostics.parse_count+=reexport_parses
			var gate:=_import_product_gate(target,existing_compiled,building)
			if not gate.ok:return {"ok":false,"error":"模型原生转换失败："+str(gate.reason),"compiled_asset":existing_compiled,"import_preparation":existing_diagnostics}
			var previous:Dictionary=entry.duplicate(true)
			if not building.is_empty():entry.model_building=building
			if not entry.has("thumbnail_path"):
				entry.thumbnail_path = directory.path_join("thumbnails").path_join(hash + ".png")
			if not preload("res://scripts/world3d/imported_building.gd").same(previous,entry) and save()!=OK:
				entry.clear();entry.merge(previous,true)
				return {"ok":false,"error":"素材信息保存失败"}
			return {"ok": true, "entry": entry,"compiled_asset":existing_compiled,"import_preparation":existing_diagnostics}
	var instance := prepared.get_scene() as Node3D
	if instance == null:
		prepared.dispose()
		return {"ok": false, "error": "导入结果无法实例化"}
	var bounds := bounds_of(instance)
	instance=null # The preparation owner retains this same scene for compilation.
	if not prepared.current():
		prepared.dispose()
		return {"ok":false,"error":"导入模型在登记前发生变化"}
	var entry := {"label": path.get_file().get_basename(), "category": "导入模型", "asset_path": target, "thumbnail_path": directory.path_join("thumbnails").path_join(hash + ".png"), "bounds_position": [bounds.position.x, bounds.position.y, bounds.position.z], "bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z]}
	if not building.is_empty():entry.model_building=building
	# Only publish a catalog entry after the full native product and its
	# consumption metadata are complete. GLB remains an import source only.
	var compiled:=_compile_import(target,prepared)
	var diagnostics:=prepared.report();diagnostics.parse_count+=reexport_parses
	var gate:=_import_product_gate(target,compiled,building)
	if not gate.ok:return {"ok":false,"error":"模型原生转换失败："+str(gate.reason),"compiled_asset":compiled,"import_preparation":diagnostics}
	entries.append(entry)
	err = save()
	if err != OK:
		entries.pop_back()
		return {"ok": false, "error": "素材库写入失败：" + error_string(err)}
	return {"ok": true, "entry": entry,"compiled_asset":compiled,"import_preparation":diagnostics}

static func _compile_import(path:String,prepared:Compiled.PreparedSource=null)->Dictionary:
	# A pathname/session success marker cannot prove a product still exists or
	# that source bytes and generator are unchanged. Reuse only a verified tuple.
	var started:=Time.get_ticks_usec()
	if prepared!=null and prepared.path.simplify_path().replace("\\","/")!=path.simplify_path().replace("\\","/"):
		prepared.dispose()
		return {"ok":false,"reason":"prepared_source_path","total_elapsed_us":Time.get_ticks_usec()-started}
	if prepared!=null and not prepared.current():
		prepared.dispose()
		_compiled_imports.erase(path)
		return {"ok":false,"reason":"source_changed","total_elapsed_us":Time.get_ticks_usec()-started}
	var compiled:Dictionary
	var previous:Variant=_compiled_imports.get(path)
	if previous is Dictionary and not previous.is_empty() and _verified_compiled_identity(path)==previous:
		compiled={"ok":true,"reused":true}
	else:
		_compiled_imports.erase(path)
		compiled=Compiled.build_from_prepared(prepared) if prepared!=null else Compiled.build(path)
	# Footprint measurement reloads the closed native graph. Do not retain the
	# original decoded GLTFState/scene across that independent measurement.
	if prepared!=null:prepared.dispose()
	if compiled.get("ok",false):
		var identity:Variant=previous if compiled.get("reused",false) and _compiled_imports.has(path) else _verified_compiled_identity(path)
		if not identity is Dictionary or identity.is_empty():
			return {"ok":false,"reason":"compiled_identity_changed","total_elapsed_us":Time.get_ticks_usec()-started}
		if _compiled_imports.size()>=4096:_compiled_imports.clear()
		_compiled_imports[path]=identity
		# Published consumers require this bounded admission descriptor. Recheck
		# even on a session hit; import rejects before catalog publication if it
		# cannot be measured, written, or completed with current metadata.
		compiled.footprint=_compile_footprint(path)
		compiled.footprint_elapsed_us=compiled.footprint.elapsed_us
	compiled.total_elapsed_us=Time.get_ticks_usec()-started
	return compiled

static func _import_product_gate(path:String,compiled:Dictionary,building:Dictionary)->Dictionary:
	if not compiled.get("ok",false):return {"ok":false,"reason":str(compiled.get("reason","native_build_failed"))}
	if not compiled.get("footprint",{}).get("ok",false):return {"ok":false,"reason":"native_footprint_failed"}
	var root:String=preload("res://scripts/world3d/map_paths.gd").external_root()
	var metadata:=preload("res://scripts/world3d/native_model_product.gd").read(path,root)
	if metadata.is_empty():
		var refreshed:=preload("res://scripts/world3d/compiled_asset_footprint.gd").refresh_bounds(path,root)
		if not refreshed.get("ok",false):return {"ok":false,"reason":"native_bounds_"+str(refreshed.get("reason","missing"))}
		metadata=preload("res://scripts/world3d/native_model_product.gd").read(path,root)
	if metadata.is_empty():return {"ok":false,"reason":"native_metadata_missing"}
	var footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
	var descriptor:=footprint.ensure_imported_building(path,root)
	if not descriptor.get("ok",false) or descriptor.get("present",false)!=(not building.is_empty()):return {"ok":false,"reason":"native_building_descriptor_missing_or_mismatched"}
	if not building.is_empty():
		var native_building:=preload("res://scripts/world3d/imported_building.gd").read_source_descriptor(path,str(metadata.native_source_sha),root)
		if not preload("res://scripts/world3d/imported_building.gd").same(building,native_building):return {"ok":false,"reason":"native_building_descriptor_mismatch"}
	return {"ok":true}

static func _verified_compiled_identity(path:String)->Dictionary:
	# Import only: full product/source checks avoid a second native allocation.
	# The existing footprint identity reader validates bounded manifest fields,
	# generator, paths and file lengths; none of those alone prove file contents.
	var footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
	var content_root:=preload("res://scripts/world3d/map_paths.gd").external_root()
	var identity:Dictionary=footprint._identity(path,content_root)
	if identity.is_empty() or FileAccess.get_sha256(identity.product)!=identity.payload_sha:return {}
	if footprint._identity(path,content_root)!=identity or FileAccess.get_sha256(path)!=identity.source_sha:return {}
	return identity

static func _compile_footprint(path:String)->Dictionary:
	# Shared by import_file (UI and MCP prefab dependency capture) and the
	# explicit compile_map_assets tool. Never called by live load/cache misses.
	var started:=Time.get_ticks_usec()
	var footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
	var content_root:=preload("res://scripts/world3d/map_paths.gd").external_root()
	var candidate:Dictionary=footprint.candidate(path,content_root)
	var reused:=not candidate.is_empty()
	var building_present:Variant=null
	if not reused:
		var built:Dictionary=footprint.build(path,content_root)
		if not built.get("ok",false):
			return {"ok":false,"reused":false,"reason":built.get("reason","unknown"),"error":built.get("error",OK),"elapsed_us":Time.get_ticks_usec()-started}
		candidate=built.get("candidate",{})
		building_present=built.get("building_present")
		if candidate.is_empty():return {"ok":false,"reused":false,"reason":"candidate_changed_after_build","elapsed_us":Time.get_ticks_usec()-started}
	var result:={"ok":true,"reused":reused,"estimated_bytes":candidate.estimated_bytes,"resident_bytes":candidate.resident_bytes,"exclusive":candidate.exclusive,"elapsed_us":Time.get_ticks_usec()-started}
	if building_present is bool:result.building_present=building_present
	return result

func save() -> Error:
	var path := directory.path_join("library.json")
	var err := Io._acquire_save_lock(path)
	if err != OK: return err
	var current := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	if current != _revision:
		Io._remove_tree(path + ".save-lock")
		return ERR_BUSY
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		err = FileAccess.get_open_error()
	else:
		var stored: Array = entries.duplicate(true)
		for entry in stored:
			for key in ["asset_path", "prefab_path", "thumbnail_path"]:
				if entry.get(key) is String and str(entry[key]).begins_with(directory.trim_suffix("/") + "/"):
					entry[key] = str(entry[key]).trim_prefix(directory.trim_suffix("/") + "/")
		file.store_string(JSON.stringify(stored, "\t"))
		file.flush()
		err = file.get_error()
		file.close()
		if err == OK: err = preload("res://scripts/world3d/atomic_file.gd").publish(path + ".tmp", path)
	if err == OK: _revision = FileAccess.get_sha256(path)
	Io._remove_tree(path + ".save-lock")
	return err

func search(query: String) -> Array:
	var needle := query.strip_edges().to_lower()
	if needle.is_empty(): return entries
	return entries.filter(func(entry: Dictionary): return (str(entry.get("label", "")) + " " + str(entry.get("category", ""))).to_lower().contains(needle))

## Existing synchronous native-only miss path; callers retain the existing
## ownership semantics. Admission/async preparation belongs to the upstream
## loading coordinator and has not yet been moved into this entry point.
static func native_candidate(path:String,root:String="",expected_generator:String="")->Dictionary:
	if root.is_empty():root=preload("res://scripts/world3d/map_paths.gd").external_root()
	return preload("res://scripts/world3d/compiled_asset_footprint.gd").candidate(path,root,"",true,expected_generator)

static func native_available(path:String,root:String="")->bool:
	return not native_validation_candidate(path,root).is_empty()

static func native_validation_candidate(path:String,root:String="")->Dictionary:
	if root.is_empty():root=preload("res://scripts/world3d/map_paths.gd").external_root()
	var candidate:=native_candidate(path,root)
	if not candidate.is_empty():candidate.native_product_kind="full"
	return candidate

static func _native_cached(path:String,candidate:Dictionary)->bool:
	var packed:Variant=_scenes.get(path)
	if not packed is PackedScene or not preload("res://scripts/world3d/model_texture_readiness.gd").matches(packed,candidate):return false
	return packed is PackedScene and packed.get_meta("compiled_asset_validated",false) and (preload("res://scripts/world3d/runtime_package_policy.gd").trusted() or packed.get_meta("_rmmo_native_audited",false)) and packed.get_meta("_rmmo_source_digest","")==candidate.get("source_sha") and packed.get_meta("_rmmo_native_payload_sha","")==candidate.get("payload_sha") and packed.get_meta("_rmmo_native_generator","")==candidate.get("generator")

static func _read_published_native(path:String,candidate:Dictionary={})->Dictionary:
	var root:String=preload("res://scripts/world3d/map_paths.gd").external_root()
	# The fixed footprint binds both the actual product and its accounting;
	# never reopen the authoring source or fall back to a raw import here.
	if candidate.is_empty():candidate=native_candidate(path,root)
	if candidate.is_empty() or OS.get_thread_caller_id()!=OS.get_main_thread_id():return {"hit":false}
	var packet:=preload("res://scripts/world3d/compiled_asset_preparation.gd").read(path,candidate,root,Callable(),preload("res://scripts/world3d/runtime_package_policy.gd").trusted(),false,"",true)
	if packet.get("error",FAILED)!=OK or not packet.get("packed") is PackedScene:
		preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(packet)
		return {"hit":false}
	packet.hit=true
	return packet

static func instantiate(path: String,native_only:bool=false) -> Node3D:
	if not preload("res://scripts/world3d/map_paths.gd").asset_key_allowed(path):return null
	var candidate:=native_candidate(path)
	if candidate.is_empty():return null
	if _native_cached(path,candidate):return _instantiate(_scenes[path])
	var compiled:=_read_published_native(path,candidate)
	if not compiled.get("hit",false):return null
	if not cache_packed(path,compiled.packed,compiled.source_digest,candidate):
		preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(compiled);return null
	return _instantiate(_scenes[path])

static func _instantiate(packed:PackedScene)->Node3D:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_library._instantiate") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if packed.get_meta("compiled_asset_validated",false) and not packed.get_meta("compiled_grass_rebound",false):
		var first:=preload("res://scripts/world3d/compiled_asset_cache.gd").instantiate(packed)
		if first!=null:packed.set_meta("compiled_grass_rebound",true)
		return first
	# Materials are shared by this template. Rebinding once avoids reading every
	# grass surface again for hundreds of subsequent instances of the same GLB.
	var scene:=packed.instantiate() as Node3D
	if scene!=null:preload("res://scripts/world3d/model_texture_readiness.gd").inherit_instance(packed,scene)
	if scene!=null and packed.get_meta("compiled_asset_validated",false):scene.set_meta("_compiled_resource_owner",packed)
	return scene

## Preview/import owns one scene and frees it; it must not grow the runtime scene cache.
static func instantiate_preview(path: String,native_only:bool=false) -> Node3D:
	if not preload("res://scripts/world3d/map_paths.gd").asset_key_allowed(path):return null
	var candidate:=native_candidate(path)
	if candidate.is_empty():return null
	if _native_cached(path,candidate):return _instantiate(_scenes[path])
	# Split products need the async texture coordinator before they are visible.
	# A synchronous preview miss cannot bind them, so avoid reading and discarding
	# their geometry too. Geometry-only consumers need an explicit separate API.
	if candidate.has("texture_table"):return null
	var compiled:=_read_published_native(path,candidate)
	if not compiled.get("hit",false):return null
	if not preload("res://scripts/world3d/model_texture_readiness.gd").packed_ready(compiled.packed):
		preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(compiled);return null
	return _instantiate(compiled.packed)

## Private geometry/recipe query, not a render template. Split products need no
## texture table or pixel preparation here; an existing complete allocation may
## be borrowed without rebinding materials or changing its completion marker.
static func instantiate_geometry(path:String,candidate:Dictionary={}) -> Node3D:
	if not preload("res://scripts/world3d/map_paths.gd").asset_key_allowed(path):return null
	if candidate.is_empty():candidate=native_candidate(path)
	if candidate.is_empty():return null
	var packed:PackedScene
	if _native_cached(path,candidate):packed=_scenes[path]
	else:
		var compiled:=_read_published_native(path,candidate)
		if not compiled.get("hit",false):return null
		packed=compiled.packed
	# Raw instantiation deliberately skips rendering caches and grass rebinding.
	# Node metadata, transforms, mesh surfaces and material role names are intact.
	var scene:=packed.instantiate() as Node3D
	if scene!=null:
		var readiness=preload("res://scripts/world3d/model_texture_readiness.gd")
		scene.set_meta(readiness.GEOMETRY_ONLY_META,true)
		if scene.has_meta(readiness.READY_META):scene.remove_meta(readiness.READY_META)
		scene.set_meta("_compiled_resource_owner",packed)
	return scene

static func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child, root)

static func bounds_of(node: Node3D, transform_: Transform3D = Transform3D.IDENTITY) -> AABB:
	var transform := transform_ * node.transform
	var bounds := AABB()
	if node is MeshInstance3D and node.mesh != null: bounds = transform * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var box := bounds_of(child, transform)
			if box.has_surface(): bounds = bounds.merge(box) if bounds.has_surface() else box
	return bounds


static func cache_scene(path: String, scene: Node, verified_digest:String="") -> bool:
	if scene == null: return false
	if not preload("res://scripts/world3d/model_texture_readiness.gd").scene_ready(scene):return false
	var started:=Time.get_ticks_usec()
	var keepalive:Variant=scene.get_meta("_compiled_resource_owner") if scene.has_meta("_compiled_resource_owner") else null
	if keepalive is PackedScene and keepalive.get_meta("compiled_asset_validated",false):
		preload("res://scripts/world3d/model_texture_cache.gd").apply(scene)
	preload("res://scripts/world3d/load_trace.gd").elapsed("asset_library.cache_materials",started,{"path":path})
	if scene.has_meta("_compiled_resource_owner"):scene.remove_meta("_compiled_resource_owner")
	started=Time.get_ticks_usec()
	_own(scene, scene)
	var packed := PackedScene.new()
	var err := packed.pack(scene)
	if err==OK and not preload("res://scripts/world3d/model_texture_readiness.gd").inherit_pack(scene,packed):err=ERR_INVALID_DATA
	preload("res://scripts/world3d/load_trace.gd").elapsed("asset_library.cache_pack",started,{"path":path})
	started=Time.get_ticks_usec()
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(scene)
	preload("res://scripts/world3d/load_trace.gd").elapsed("asset_library.cache_dispose",started,{"path":path})
	if err != OK: return false
	# This scene was instantiated from an accepted native product. Repacking its
	# private node graph must preserve that provenance, or native-only consumers
	# immediately reject this freshly published template and reload the product.
	if keepalive is PackedScene and keepalive.get_meta("compiled_asset_validated",false):
		packed.set_meta("compiled_asset_validated",true)
		packed.set_meta("compiled_grass_rebound",true)
		for key:String in ["_rmmo_source_digest","_rmmo_native_payload_sha","_rmmo_native_generator","_rmmo_native_audited"]:
			if keepalive.has_meta(key):packed.set_meta(key,keepalive.get_meta(key))
	var cached:=cache_packed(path,packed,verified_digest)
	keepalive=null
	return cached

## The private worker packed this graph while its original native owner stayed
## alive. Intern on main before publishing, exactly as cache_scene does.
static func cache_prepared_native_scene(path:String,scene:Node,packed:PackedScene,native_owner:PackedScene,verified_digest:String)->bool:
	if scene==null or packed==null or native_owner==null or not native_owner.get_meta("compiled_asset_validated",false):return false
	if not preload("res://scripts/world3d/model_texture_readiness.gd").inherit_pack(scene,packed):return false
	var began:=Time.get_ticks_usec()
	preload("res://scripts/world3d/model_texture_cache.gd").apply(scene)
	preload("res://scripts/world3d/load_trace.gd").elapsed("asset_library.cache_materials",began,{"path":path})
	packed.set_meta("compiled_asset_validated",true);packed.set_meta("compiled_grass_rebound",true)
	for key:String in ["_rmmo_source_digest","_rmmo_native_payload_sha","_rmmo_native_generator","_rmmo_native_audited"]:
		if native_owner.has_meta(key):packed.set_meta(key,native_owner.get_meta(key))
	var cached:=cache_packed(path,packed,verified_digest)
	began=Time.get_ticks_usec();preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(scene)
	preload("res://scripts/world3d/load_trace.gd").elapsed("asset_library.cache_dispose",began,{"path":path})
	return cached

## Offline classification guarantees that the private scene made no node-local
## changes that must be repacked. Keep the original owner until after disposal.
static func cache_direct_native_scene(path:String,scene:Node,native_owner:PackedScene,verified_digest:String,material_plan:Dictionary={})->bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id():return false
	if scene==null or native_owner==null or not native_owner.get_meta("compiled_asset_validated",false):return false
	if not preload("res://scripts/world3d/model_texture_readiness.gd").inherit_pack(scene,native_owner):return false
	var began:=Time.get_ticks_usec()
	if not preload("res://scripts/world3d/model_texture_direct_plan.gd").apply_prepared(material_plan):
		# The scene and native owner still retain all partial-plan resources.
		# Clear the private aliases on main, then use the established fallback.
		material_plan.clear();preload("res://scripts/world3d/model_texture_direct_seen.gd").apply(scene)
	preload("res://scripts/world3d/load_trace.gd").elapsed("asset_library.cache_materials",began,{"path":path})
	began=Time.get_ticks_usec();var owner_fast:bool=preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_direct_native_scene(scene,native_owner)
	preload("res://scripts/world3d/load_trace.gd").elapsed("asset_library.cache_dispose",began,{"path":path,"owner_fast":owner_fast})
	native_owner.set_meta("compiled_grass_rebound",true)
	return cache_packed(path,native_owner,verified_digest)

static func cache_packed(path:String,packed:PackedScene,verified_digest:String="",native_identity:Dictionary={})->bool:
	if packed==null:return false
	if not preload("res://scripts/world3d/model_texture_readiness.gd").packed_ready(packed):return false
	if not native_identity.is_empty():
		if native_identity.get("source_sha")!=verified_digest or not _valid_source_digest(str(native_identity.get("payload_sha",""))) or not native_identity.get("generator") is String:return false
	if not verified_digest.is_empty():
		if not _valid_source_digest(verified_digest):return false
		var previous:String=packed.get_meta("_rmmo_source_digest","")
		if not previous.is_empty() and previous!=verified_digest:return false
	if not native_identity.is_empty():
		packed.set_meta("_rmmo_native_payload_sha",native_identity.payload_sha)
		packed.set_meta("_rmmo_native_generator",native_identity.generator)
	if not verified_digest.is_empty():
		packed.set_meta("_rmmo_source_digest",verified_digest)
	var began:=Time.get_ticks_usec();var replacement:bool=_scenes.has(path) and _scenes[path]!=packed
	# Replacement can drop the final owner of thousands of meshes just like
	# eviction. Transfer that disposal to the bounded retirement service first.
	if replacement:preload("res://scripts/world3d/resource_retirement.gd").defer_scene(_scenes[path])
	_scenes[path]=packed
	preload("res://scripts/world3d/load_trace.gd").elapsed("asset_library.accept_packed",began,{"path":path,"replacement":replacement})
	return true

static func _valid_source_digest(value:String)->bool:
	return value.length()==64 and value.is_valid_hex_number(false)

static func has_cached_scene(path:String,verified_digest:String="")->bool:
	if not _scenes.has(path):return false
	if not preload("res://scripts/world3d/model_texture_readiness.gd").packed_ready(_scenes[path]):return false
	return verified_digest.is_empty() or (_valid_source_digest(verified_digest) and str(_scenes[path].get_meta("_rmmo_source_digest",""))==verified_digest)

static func evict_cached_scene(path:String)->bool:
	# Remove only the template's ownership. Live nodes/specs in other consumers
	# continue owning their resources; never clear or mutate a shared Mesh.
	var scene:PackedScene=_scenes.get(path)
	if scene==null:return false
	preload("res://scripts/world3d/resource_retirement.gd").defer_scene(scene)
	return _scenes.erase(path)
