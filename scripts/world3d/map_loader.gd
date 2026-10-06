extends Node
## Parse external glTF off the scene thread. Generate nodes only on the main thread.
signal finished(scene: Node, path: String, error: String)
signal progress(stage: String, done: int, total: int)
var _record_meta := {}
var _asset_states := {}
var _building := false
var _prepared: Node
var _thread: Thread
var _cache_thread: Thread
var _mesh_cache_thread:Thread
var _mesh_read_thread:Thread
var _mesh_cache_data:Dictionary={}
var _source_digest:=""
var _generator_key:=""
var _model_signatures:Dictionary={}
var _needed_textures:Dictionary={}
var _decoded_images:Dictionary={}
var _texture_thread:Thread
var _terrain_thread:Thread
var _terrain_context:RefCounted
var _surface_arrays:Dictionary={}
var _index_thread:Thread
var _document: GLTFDocument
var _state: GLTFState
var _error := OK
var _path := ""
var _content_root := ""
var _cancelled := false
var _profile: Dictionary = {}
var _prefab_worker_count:int=4


static func resolve_path(requested: String) -> String:
	if not requested.is_empty():
		return requested
	var Paths = preload("res://scripts/world3d/map_paths.gd")
	var yard := Paths.cache_directory("p4_yard")
	var inn := Paths.cache_directory("p4_inn")
	if yard.is_empty() or inn.is_empty():
		return ""
	var path := yard.path_join("map.gltf")
	var inn_path := inn.path_join("map.gltf")
	var Document = preload("res://scripts/world3d/world_document.gd")
	if not FileAccess.file_exists(path) and Document.sample_yard(inn_path).save(path) != OK:
		return ""
	if not FileAccess.file_exists(inn_path) and Document.make_inn(path).save(inn_path) != OK:
		return ""
	return path


func start(path: String) -> void:
	_path = path
	# Snapshot the configured root on the main thread; parsing must not read autoload nodes.
	_content_root = preload("res://scripts/world3d/map_paths.gd").external_root()
	_thread = Thread.new()
	_error = _thread.start(_parse)
	if _error != OK:
		_thread = null
		call_deferred("_finish_error", "无法启动地图读取")


func cancel() -> void:
	_cancelled = true


func _parse() -> void:
	var started:=Time.get_ticks_usec()
	# Our editor records are the authoritative document; avoid importing their
	# duplicate glTF mesh export and constructing thousands of temporary nodes.
	if _path.get_extension().to_lower() == "gltf":
		var Cache=preload("res://scripts/world3d/map_metadata_cache.gd")
		# Reading the derived envelope does not depend on hashing the source.
		# Join and verify its source identity before validation or scene creation.
		var metadata_thread:=Thread.new()
		var metadata_started:bool=metadata_thread.start(Cache.read_candidate.bind(_path))==OK
		var digest:=FileAccess.get_sha256(_path)
		_source_digest=digest
		_generator_key=preload("res://scripts/world3d/runtime_mesh_cache.gd").generator_key()
		_mesh_read_thread=Thread.new()
		var read_cache:=preload("res://scripts/world3d/runtime_mesh_cache.gd").read.bind(_path,digest,_generator_key)
		if _mesh_read_thread.start(read_cache)!=OK:
			_mesh_read_thread=null;_mesh_cache_data=read_cache.call()
		var candidate:Dictionary=metadata_thread.wait_to_finish() if metadata_started else Cache.read_candidate(_path)
		var cache_context:Dictionary=candidate.get("context",{})
		var cached:Dictionary=candidate.get("extras",{}) if candidate.get("source_digest")==digest else {}
		_profile.metadata_cache_hit=false
		if not cached.is_empty():
			_start_texture_prefetch(cache_context.get("textures",[]))
			_profile.parse_us=Time.get_ticks_usec()-started
			var checked:=Time.get_ticks_usec()
			if _valid_records(cached,cache_context.get("paint_ids",[])):
				_profile.validate_us=Time.get_ticks_usec()-checked
				_profile.metadata_cache_hit=true
				_record_meta=cached
				if cache_context.get("upgrade",false) or (_texture_thread==null and not _needed_textures.is_empty()):
					_cache_thread=Thread.new()
					if _cache_thread.start(Cache.write.bind(_path,digest,cached,_needed_textures.values()))!=OK:_cache_thread=null
				_prepare_record_assets()
				return
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
		_profile.parse_us=Time.get_ticks_usec()-started
		if data is Dictionary:
			var nodes: Array = data.get("nodes", [])
			var scenes: Array = data.get("scenes", [])
			var scene_index := int(data.get("scene", 0))
			if scene_index >= 0 and scene_index < scenes.size():
				var roots: Array = scenes[scene_index].get("nodes", [])
				if roots.size() == 1 and int(roots[0]) >= 0 and int(roots[0]) < nodes.size():
					var root: Dictionary = nodes[int(roots[0])]
					var extra: Dictionary = root.get("extras", {})
					# Validate this immutable parsed document once. Repeating every
					# material/root check is expensive for thousands of wall records.
					var validate_started:=Time.get_ticks_usec()
					var native_valid:=_valid_records(extra)
					_profile.validate_us=Time.get_ticks_usec()-validate_started
					if extra.get("rmmo_format") == "rmmo_gltf_map" and not native_valid:
						_error = ERR_INVALID_DATA
						return
					if not root.has("matrix") and not root.has("translation") and not root.has("rotation") and not root.has("scale") and native_valid:
						_record_meta = extra
						if not digest.is_empty() and FileAccess.get_sha256(_path)==digest:
							# Encoding a disposable cache must not delay first entry. Both
							# consumers only read this already validated record snapshot.
							_cache_thread=Thread.new()
							if _cache_thread.start(Cache.write.bind(_path,digest,extra,_needed_textures.values()))!=OK:_cache_thread=null
						_prepare_record_assets()
						return

	_document = GLTFDocument.new()
	_state = GLTFState.new()
	_error = _document.append_from_file(_path, _state, 0, _path.get_base_dir())


func _prepare_record_assets()->void:
	# Joining the cache reader here blocks only this parser worker, never UI.
	if _mesh_read_thread!=null:
		_mesh_cache_data=_mesh_read_thread.wait_to_finish();_mesh_read_thread=null
	var build_geometry:bool=_mesh_cache_data.is_empty()
	var terrain_snapshot:Variant=_mesh_cache_data.get("terrain_context")
	_terrain_thread=Thread.new()
	var prepare_terrain:=func():
		var began:=Time.get_ticks_usec()
		var cached=preload("res://scripts/world3d/terrain_context_cache.gd").restore(terrain_snapshot,_record_meta.rmmo_records)
		if cached!=null:return {"context":cached,"surfaces":{},"elapsed":Time.get_ticks_usec()-began,"cache_hit":true}
		var mask_buckets:Array=[[],[],[],[]];var mask_workers:Array[Thread]=[];var masks:Dictionary={};var mask_at:=0
		for record:Dictionary in _record_meta.rmmo_records:
			if record.has("terrain_regions"):mask_buckets[mask_at%4].append(record);mask_at+=1
		for bucket:Array in mask_buckets:
			var worker:=Thread.new()
			var task:=func():
				var result:Dictionary={}
				for record:Dictionary in bucket:result[record.uuid]=preload("res://scripts/world3d/terrain_regions.gd").mask(record)
				return result
			if not bucket.is_empty() and worker.start(task)==OK:mask_workers.append(worker)
			else:masks.merge(task.call())
		var context=preload("res://scripts/world3d/terrain_neighbors.gd").new()
		context.update(_record_meta.rmmo_records,true)
		# Coverage masks are CPU images; build them off the scene thread too.
		var buckets:Array=[[],[],[],[]];var at:=0;var workers:Array[Thread]=[]
		for record:Dictionary in _record_meta.rmmo_records:
			if build_geometry and (record.has("terrain_mesh") or record.has("road_mesh") or record.has("rock_bank")):
				buckets[at%4].append({"record":record,"image":null,"surfaces":[]});at+=1
		for bucket:Array in buckets:
			if bucket.is_empty():continue
			var worker:=Thread.new()
			var task:=func():
				for entry:Dictionary in bucket:
					var record:Dictionary=entry.record
					if build_geometry:
						if record.has("terrain_mesh"):entry.surfaces=preload("res://scripts/world3d/terrain_surface.gd").arrays(record,context.data.get(record.uuid,{}))
						elif record.has("road_mesh"):entry.surfaces=preload("res://scripts/world3d/road_surface.gd").arrays(record)
						elif record.has("rock_bank"):entry.surfaces=preload("res://scripts/world3d/rock_bank_mesh.gd").arrays(record)
			if worker.start(task)==OK:workers.append(worker)
			else:task.call()
		for worker:Thread in workers:worker.wait_to_finish()
		for worker:Thread in mask_workers:masks.merge(worker.wait_to_finish())
		var surfaces:Dictionary={}
		for bucket:Array in buckets:
			for entry:Dictionary in bucket:
				if not entry.surfaces.is_empty():surfaces[entry.record.uuid]=entry.surfaces
		for id:String in masks:
			if not context.data.has(id):context.data[id]={}
			context.data[id].region_mask=masks[id]
		return {"context":context,"surfaces":surfaces,"elapsed":Time.get_ticks_usec()-began,"cache_hit":false}
	if _terrain_thread.start(prepare_terrain)!=OK:
		_terrain_thread=null
		var terrain:Dictionary=prepare_terrain.call()
		_terrain_context=terrain.context;_surface_arrays=terrain.surfaces;_profile.terrain_context_worker_us=terrain.elapsed
		_profile.terrain_context_cache_hit=terrain.cache_hit
	for record in _record_meta.rmmo_records:
		if record.has("fortification_art"):
			var path:String=record.fortification_art.asset_path
			if not _model_signatures.has(path):_model_signatures[path]=FileAccess.get_sha256(path)
		if record.get("kind") != "asset" or record.has("house_prefab"): continue
		var asset_path := str(record.get("asset_path", ""))
		if _asset_states.has(asset_path): continue
		if not FileAccess.file_exists(asset_path):
			_error = ERR_FILE_NOT_FOUND
			return
		var asset_document := GLTFDocument.new()
		var asset_state := GLTFState.new()
		_error = asset_document.append_from_file(asset_path, asset_state, 0, asset_path.get_base_dir())
		if _error != OK: return
		_asset_states[asset_path] = [asset_document, asset_state]
	var decoded:Dictionary=_texture_thread.wait_to_finish() if _texture_thread!=null else _decode_textures(_needed_textures)
	_texture_thread=null
	_decoded_images=decoded.images
	_profile.texture_decode_us=decoded.elapsed
	# The dependency hint is optional. Full validated records remain authoritative.
	for key:String in _needed_textures:
		if not _decoded_images.has(key):
			var source:Array=_needed_textures[key]
			var image:Image=preload("res://scripts/world3d/runtime_texture_cache.gd").image(source[0],source[1])
			if image==null:_error=ERR_FILE_CORRUPT;return
			_decoded_images[key]=image


func _finish_terrain()->void:
	if _terrain_thread==null:return
	while _terrain_thread.is_alive():await get_tree().process_frame
	var terrain:Dictionary=_terrain_thread.wait_to_finish();_terrain_thread=null
	_terrain_context=terrain.context;_surface_arrays=terrain.surfaces;_profile.terrain_context_worker_us=terrain.elapsed
	_profile.terrain_context_cache_hit=terrain.cache_hit



func _start_texture_prefetch(dependencies:Variant)->void:
	if not dependencies is Array or dependencies.is_empty():return
	var requested:Dictionary={}
	for item in dependencies:
		if not item is Array or item.size()!=2 or not item[0] is String or not item[1] is bool:return
		if item[0].get_extension().to_lower() not in ["png","jpg","jpeg","webp"] or not preload("res://scripts/world3d/map_paths.gd").allowed(item[0],_content_root) or not FileAccess.file_exists(item[0]):return
		requested[item[0]+("|flip_y" if item[1] else "")]=item
	_texture_thread=Thread.new()
	if _texture_thread.start(_decode_textures.bind(requested))!=OK:_texture_thread=null

func _decode_textures(requested:Dictionary)->Dictionary:
	var began:=Time.get_ticks_usec()
	var buckets:Array=[[],[],[]];var at:=0
	for key:String in requested:
		buckets[at%3].append({"key":key,"source":requested[key],"image":null});at+=1
	var workers:Array=[]
	for bucket:Array in buckets:
		var worker:=Thread.new()
		var task:=func():
			for entry:Dictionary in bucket:entry.image=preload("res://scripts/world3d/runtime_texture_cache.gd").image(entry.source[0],entry.source[1])
		if worker.start(task)==OK:workers.append(worker)
		else:task.call()
	for worker:Thread in workers:worker.wait_to_finish()
	var images:Dictionary={}
	for bucket:Array in buckets:
		for entry:Dictionary in bucket:
			if entry.image!=null:images[entry.key]=entry.image
	return {"images":images,"elapsed":Time.get_ticks_usec()-began}


func _process(_delta: float) -> void:
	if _building or (_thread==null and _mesh_read_thread==null) or (_thread!=null and _thread.is_alive()):
		return
	if _thread!=null:_thread.wait_to_finish();_thread=null
	if _mesh_read_thread!=null:
		if _mesh_read_thread.is_alive():return
		_mesh_cache_data=_mesh_read_thread.wait_to_finish();_mesh_read_thread=null
	if _mesh_cache_data.get("models",{})!=_model_signatures:_mesh_cache_data.clear()
	if _cancelled:
		_building=true
		_retire()
		return
	if _error != OK:
		_finish_error("地图读取失败：%s" % error_string(_error))
		return
	if not _record_meta.is_empty():
		_building = true
		_build_records()
		return
	if _can_stream_static():
		_building = true
		_build_static()
		return
	var scene := preload("res://scripts/world3d/gltf_map_io.gd").generate_scene(_document, _state)
	finished.emit(scene, _path, "" if scene != null else "地图场景生成失败")
	queue_free()


func _retire()->void:
	while (_cache_thread!=null and _cache_thread.is_alive()) or (_mesh_cache_thread!=null and _mesh_cache_thread.is_alive()) or (_terrain_thread!=null and _terrain_thread.is_alive()):
		await get_tree().process_frame
	queue_free()


func _finish_error(message: String) -> void:
	_building=true
	if not _cancelled:
		finished.emit(null, _path, message)
	_retire()


func _exit_tree() -> void:
	if is_instance_valid(_prepared): _prepared.free()
	if _thread != null:
		_thread.wait_to_finish()
	if _cache_thread != null:
		_cache_thread.wait_to_finish()
	if _mesh_cache_thread!=null:_mesh_cache_thread.wait_to_finish()
	if _mesh_read_thread!=null:_mesh_read_thread.wait_to_finish()
	if _texture_thread!=null:_texture_thread.wait_to_finish()
	if _terrain_thread!=null:_terrain_thread.wait_to_finish()
	if _index_thread!=null:_index_thread.wait_to_finish()
	# Drop only this loader's unconsumed handoff images (e.g. height maps or
	# materials already resident); never pin them for the rest of the session.
	var images:Dictionary=preload("res://scripts/world3d/surface_materials.gd").prepared_images
	for key in _decoded_images:
		if images.get(key)==_decoded_images[key]:images.erase(key)
	_decoded_images.clear()


func _valid_records(extra: Dictionary, immutable_paint_ids:Array=[]) -> bool:
	_needed_textures.clear()
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_meta(extra): return false
	if extra.get("rmmo_format", "") != "rmmo_gltf_map" or int(extra.get("rmmo_version", 0)) != 1: return false
	if not preload("res://scripts/world3d/environment_settings.gd").valid(extra): return false
	if not preload("res://scripts/world3d/editor_view_settings.gd").valid(extra): return false
	var records: Variant = extra.get("rmmo_records")
	if not records is Array: return false
	if not immutable_paint_ids.is_empty() and immutable_paint_ids.size()!=records.size():return false
	var ids:Dictionary={};var buckets:Array=[[],[],[],[]];var workers:Array[Thread]=[];var results:Array=[]
	for i in records.size():
		var record:Variant=records[i]
		if not record is Dictionary or str(record.get("uuid", "")).is_empty() or ids.has(record.uuid):return false
		ids[record.uuid]=true
		buckets[i%4].append({"record":record,"paint_id":null if immutable_paint_ids.is_empty() else immutable_paint_ids[i]})
	# Each validator owns its caches and dependency map. It reads the same
	# immutable snapshot as prefab decoding, without waiting for decompression.
	for bucket:Array in buckets:
		var worker:=Thread.new()
		if worker.start(_validate_record_batch.bind(bucket))==OK:workers.append(worker)
		else:results.append(_validate_record_batch(bucket))
	var prefab_started:=Time.get_ticks_usec()
	_decode_prefabs(records,_prefab_worker_count)
	_profile.prefab_decode_us=Time.get_ticks_usec()-prefab_started
	var ownership_started:=Time.get_ticks_usec()
	var ownership_ok:bool=preload("res://scripts/world3d/building_blueprint.gd").valid_ownership(extra,records)
	_profile.ownership_us=Time.get_ticks_usec()-ownership_started
	for worker:Thread in workers:results.append(worker.wait_to_finish())
	var totals:Dictionary={"terrain":0,"paint":0,"dependencies":0,"other":0};var valid_:bool=ownership_ok
	for result:Dictionary in results:
		valid_=valid_ and result.ok
		if not result.ok:continue
		_needed_textures.merge(result.textures,true)
		for key:String in totals:totals[key]+=result.timings[key]
	_profile.validation_parts=totals
	return valid_


func _validate_record_batch(entries:Array)->Dictionary:
	var validation_parts:Dictionary={"terrain":0,"paint":0,"dependencies":0,"other":0}
	var textures:Dictionary={}
	var material_validation: Dictionary={}; var checked_paths: Dictionary={};var checked_definitions:Dictionary={}
	var checked_paints:Dictionary={}
	for entry:Dictionary in entries:
		var part_started:=Time.get_ticks_usec()
		var record:Dictionary=entry.record
		if not preload("res://scripts/world3d/wind_response.gd").valid(record): return {"ok":false}
		if not preload("res://scripts/world3d/terrain_surface.gd").valid(record): return {"ok":false}
		if not preload("res://scripts/world3d/river_material_data.gd").valid(record): return {"ok":false}
		validation_parts.terrain+=Time.get_ticks_usec()-part_started;part_started=Time.get_ticks_usec()
		var paint_id:Variant=entry.paint_id
		if not preload("res://scripts/world3d/surface_materials.gd").valid(record,false,_content_root,material_validation,paint_id): return {"ok":false}
		validation_parts.paint+=Time.get_ticks_usec()-part_started;part_started=Time.get_ticks_usec()
		var include_paint:bool=paint_id==null or not checked_paints.has(paint_id)
		if paint_id!=null:checked_paints[paint_id]=true
		for definition in preload("res://scripts/world3d/surface_materials.gd").definitions(record,include_paint):
			if checked_definitions.has(definition):continue
			checked_definitions[definition]=true
			if not preload("res://scripts/world3d/surface_materials.gd").material_valid(definition,false,_content_root,material_validation): return {"ok":false}
			for field in preload("res://scripts/world3d/surface_materials.gd").MAP_FIELDS:
				var path: String=definition.get(field, "")
				if not path.is_empty():
					var flip:bool=field=="normal_path" and definition.get("normal_format", "opengl")=="directx"
					textures[path+("|flip_y" if flip else "")]=[path,flip]
				if not path.is_empty() and not checked_paths.has(path):
					if not preload("res://scripts/world3d/map_paths.gd").allowed(path,_content_root) or not FileAccess.file_exists(path): return {"ok":false}
					checked_paths[path]=true
		validation_parts.dependencies+=Time.get_ticks_usec()-part_started;part_started=Time.get_ticks_usec()
		if not preload("res://scripts/world3d/auto_tile_rules.gd").valid(record, false, _content_root): return {"ok":false}
		if not preload("res://scripts/world3d/event_templates.gd").valid_record(record, _content_root): return {"ok":false}
		for field in ["position", "rotation", "size"]:
			var values: Variant = record.get(field)
			if not values is Array or values.size() != 3: return {"ok":false}
			for value in values:
				if not (value is int or value is float) or not is_finite(float(value)): return {"ok":false}
		validation_parts.other+=Time.get_ticks_usec()-part_started
	return {"ok":true,"textures":textures,"timings":validation_parts}


func _decode_prefabs(records:Array,worker_count:int=4)->void:
	# Only immutable plain data is decompressed here. GPU/material creation still
	# runs on the scene thread; authoritative validation below is never skipped.
	var unique:Dictionary={};var buckets:Array=[];var workers:Array[Thread]=[]
	for i in clampi(worker_count,1,16):buckets.append({"values":[],"bytes":0})
	for r in records:
		if not r is Dictionary or not r.get("house_prefab") is Dictionary:continue
		var value:Dictionary=r.house_prefab
		if not value.get("sha256") is String or unique.has(value.sha256):continue
		unique[value.sha256]=true
		var smallest:int=0
		for i in buckets.size():
			if buckets[i].bytes<buckets[smallest].bytes:smallest=i
		buckets[smallest].values.append(value);buckets[smallest].bytes+=int(value.get("length",0))
	for bucket in buckets:
		if bucket.values.is_empty():continue
		var worker:=Thread.new()
		var job:=func():
			for value:Dictionary in bucket.values:preload("res://scripts/world3d/house_prefab.gd").decode(value)
		if worker.start(job)==OK:workers.append(worker)
		else:job.call()
	for worker in workers:worker.wait_to_finish()


func _build_records() -> void:
	var root := Node3D.new()
	_prepared = root
	root.name = "rmmo_world"
	root.set_meta("extras", _record_meta)
	var library: Array = []
	# Restore buildings while the independent ground workers are still busy.
	# Keep a deterministic partition so per-record cache identities stay exact.
	var records:Array=[];var landscape:Array=[]
	for record:Dictionary in _record_meta.rmmo_records:
		if record.has("terrain_mesh") or record.has("road_mesh") or record.has("rock_bank"):landscape.append(record)
		else:records.append(record)
	records.append_array(landscape)
	var doc = preload("res://scripts/world3d/world_document.gd").new()
	doc.records=records
	doc.load_immutable_records=true
	doc.load_paint_validation={}
	doc.load_material_pool={}
	doc.load_texture_checks={}
	doc.load_model_signatures=_model_signatures
	doc.load_surface_arrays=_surface_arrays
	if _terrain_context!=null:doc.terrain_neighbors=_terrain_context
	var Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
	preload("res://scripts/world3d/surface_materials.gd").prepare_images(_decoded_images)
	var restore_started:=Time.get_ticks_usec()
	doc.load_box_meshes=Cook.restore(_mesh_cache_data,doc.load_paint_validation,doc.load_material_pool)
	var cooked_specs:Array=Cook.restore_specs(_mesh_cache_data,records)
	_profile.cooked_specs=cooked_specs.filter(func(spec):return not spec.is_empty()).size()
	_profile.cooked_meshes=doc.load_box_meshes.size()
	_profile.cooked_restore_us=Time.get_ticks_usec()-restore_started

	var Stream = preload("res://scripts/world3d/world_stream.gd")
	var cursor := 0
	_profile.mesh_us=0;_profile.spec_us=0;_profile.frames=0;_profile.hit_us=0;_profile.miss_us=0;_profile.mesh_categories={}
	while cursor < records.size():
		var start := Time.get_ticks_usec()
		while cursor < records.size() and Time.get_ticks_usec() - start < 24000:
			if _terrain_thread!=null and (records[cursor].has("terrain_mesh") or records[cursor].has("road_mesh") or records[cursor].has("rock_bank")):
				progress.emit("准备地形数据（后台）",cursor,records.size())
				await _finish_terrain()
				if _cancelled:root.free();_prepared=null;await _retire();return
				if _terrain_context!=null:doc.terrain_neighbors=_terrain_context
				else:doc.terrain_neighbors.update(records)
				doc.load_surface_arrays=_surface_arrays
				start=Time.get_ticks_usec()
			if records[cursor].get("kind") == "asset" and not records[cursor].has("house_prefab"):
				if not FileAccess.file_exists(str(records[cursor].get("asset_path", ""))):
					root.free()
					_prepared = null
					_finish_error("地图素材缺失：" + str(records[cursor].get("asset_path", "")))
					return
				var asset_path: String = records[cursor].asset_path
				if _asset_states.has(asset_path):
					var imported: Node = preload("res://scripts/world3d/gltf_map_io.gd").generate_scene(_asset_states[asset_path][0], _asset_states[asset_path][1])
					if imported == null or not preload("res://scripts/world_editor/asset_library.gd").cache_scene(asset_path, imported):
						root.free()
						_prepared = null
						_finish_error("地图素材无法实例化：" + asset_path)
						return
					_asset_states.erase(asset_path)
				root.add_child(doc._asset(records[cursor]))
				cursor += 1
				continue
			var spec:Dictionary
			if not cooked_specs.is_empty() and not cooked_specs[cursor].is_empty():spec=cooked_specs[cursor]
			else:
				var hits_before:int=doc.load_box_hits
				var mesh_started:=Time.get_ticks_usec()
				var visual: MeshInstance3D = doc._mesh(records[cursor])
				var mesh_elapsed:=Time.get_ticks_usec()-mesh_started
				var category:String="prefab" if records[cursor].has("house_prefab") else ("terrain" if records[cursor].has("terrain_mesh") else ("road" if records[cursor].has("road_mesh") else "other"))
				_profile.mesh_categories[category]=int(_profile.mesh_categories.get(category,0))+mesh_elapsed
				_profile.mesh_us+=mesh_elapsed
				_profile["hit_us" if doc.load_box_hits>hits_before else "miss_us"]+=mesh_elapsed
				if visual.has_meta("tile_error") or visual.has_meta("paint_error"):
					visual.free(); root.free(); _prepared = null
					_finish_error("自动拼接套件模型缺失或无效")
					return
				var spec_started:=Time.get_ticks_usec()
				spec = Stream._spec(visual)
				_profile.spec_us+=Time.get_ticks_usec()-spec_started
				visual.free()
			var id: String = spec.uuid
			library.append(spec)
			cursor += 1
		progress.emit("准备地图几何与材质", cursor, records.size())
		_profile.frames+=1
		await get_tree().process_frame
		if _cancelled:
			root.free()
			_prepared = null
			await _retire()
			return
	await _finish_terrain()
	if (_mesh_cache_data.is_empty() or not _profile.get("terrain_context_cache_hit",false)) and not _source_digest.is_empty():
		var snapshot:Dictionary=Cook.pack(doc.load_box_meshes,_source_digest,_generator_key,library)
		if _terrain_context!=null:snapshot.terrain_context=preload("res://scripts/world3d/terrain_context_cache.gd").pack(_terrain_context)
		snapshot.models=_model_signatures
		_mesh_cache_thread=Thread.new()
		if _mesh_cache_thread.start(Cook.write.bind(_path,snapshot))!=OK:_mesh_cache_thread=null
	var index_started:=Time.get_ticks_usec()
	var index_job:=preload("res://scripts/world3d/stream_index.gd").build.bind(library)
	_index_thread=Thread.new()
	var index_data:Dictionary
	if _index_thread.start(index_job)==OK:
		progress.emit("构建空间索引（后台）",0,library.size())
		while _index_thread.is_alive():await get_tree().process_frame
		index_data=_index_thread.wait_to_finish();_index_thread=null
	else:
		_index_thread=null;index_data=index_job.call()
	_profile.index_worker_us=Time.get_ticks_usec()-index_started
	if _cancelled:
		root.free();_prepared=null;await _retire();return
	root.set_meta("stream_library",library)
	for key:String in index_data:root.set_meta(key,index_data[key])
	root.set_meta("stream_children", -1 if root.get_child_count() > 0 else 0)
	root.set_meta("record_stream_load", true)
	root.set_meta("load_box_cache_hits",doc.load_box_hits)
	root.set_meta("load_profile",_profile)
	root.set_meta("runtime_geometry_key",_source_digest+_generator_key+str(_model_signatures))
	var server=get_node_or_null("/root/MockServer")
	if server!=null and server.has_method("register_loaded_world3d_environment"):
		server.register_loaded_world3d_environment(_path,_record_meta)
	_prepared = null
	finished.emit(root, _path, "")
	await _retire()


func _can_stream_static() -> bool:
	if not _state.animations.is_empty() or not _state.skins.is_empty() or not _state.cameras.is_empty() or not _state.lights.is_empty(): return false
	for extension in _state.json.get("extensionsUsed", []):
		if str(extension) != "GODOT_single_root": return false
	for node in _state.nodes:
		if node.skin >= 0 or node.skeleton >= 0 or not node.visible: return false
	for imported in _state.meshes:
		if not imported.blend_weights.is_empty(): return false
	return true


func _build_static() -> void:
	var root := Node3D.new()
	_prepared = root
	root.name = "rmmo_world"
	var raw_nodes: Array = _state.json.get("nodes", [])
	if _state.root_nodes.size() == 1:
		root.set_meta("extras", raw_nodes[_state.root_nodes[0]].get("extras", {}))
	var stack: Array = []
	for id in _state.root_nodes: stack.append({"id": id, "parent": Transform3D.IDENTITY})
	var library: Array = []
	var by_id := {}
	var index := {}
	var known := {}
	var meshes := {}
	var visited := {}
	var Stream = preload("res://scripts/world3d/world_stream.gd")
	while not stack.is_empty():
		var start := Time.get_ticks_usec()
		while not stack.is_empty() and Time.get_ticks_usec() - start < 3000:
			var entry: Dictionary = stack.pop_back()
			var id: int = entry.id
			if visited.has(id): continue
			visited[id] = true
			var node: GLTFNode = _state.nodes[id]
			var transform: Transform3D = entry.parent * node.xform
			for child in node.children: stack.append({"id": child, "parent": transform})
			if node.mesh < 0: continue
			if not meshes.has(node.mesh):
				var imported: GLTFMesh = _state.meshes[node.mesh]
				var resource: ArrayMesh = imported.mesh.get_mesh()
				if not imported.instance_materials.is_empty():
					resource = resource.duplicate()
					for surface in mini(resource.get_surface_count(), imported.instance_materials.size()):
						if imported.instance_materials[surface] != null: resource.surface_set_material(surface, imported.instance_materials[surface])
				meshes[node.mesh] = resource
			var visual := MeshInstance3D.new()
			visual.name = "gltf_node_%d" % id
			visual.mesh = meshes[node.mesh]
			visual.transform = transform
			visual.set_meta("extras", raw_nodes[id].get("extras", {}))
			var spec: Dictionary = Stream._spec(visual)
			visual.free()
			var uuid := str(spec.extras.get("uuid", spec.uuid))
			if known.has(uuid):
				_finish_error("地图物件 ID 重复：" + uuid)
				return
			spec.uuid = uuid
			known[uuid] = true
			by_id[uuid] = spec
			library.append(spec)
			for z in range(spec.chunk_min.y, spec.chunk_max.y + 1):
				for x in range(spec.chunk_min.x, spec.chunk_max.x + 1):
					var key := Vector2i(x, z)
					if not index.has(key): index[key] = []
					index[key].append(uuid)
		progress.emit("准备静态地图", visited.size(), _state.nodes.size())
		await get_tree().process_frame
		if _cancelled:
			queue_free()
			return
	root.set_meta("stream_library", library)
	root.set_meta("stream_by_id", by_id)
	root.set_meta("stream_known", known)
	root.set_meta("stream_index", index)
	root.set_meta("stream_children", -1 if root.get_child_count() > 0 else 0)
	root.set_meta("static_stream_load", true)
	_prepared = null
	finished.emit(root, _path, "")
	queue_free()
