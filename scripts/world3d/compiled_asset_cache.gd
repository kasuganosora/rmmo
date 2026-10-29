extends RefCounted
## Persistent native import products. Author maps retain logical model keys;
## the corresponding GLB is only an import source, never a runtime dependency.
## Builds belong to import/preparation, never to a live streaming cache miss.
## Each read owns its PackedScene; only the caller publishes to AssetLibrary.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const TextureProducts=preload("res://scripts/world3d/model_texture_products.gd")
const VERSION=1
# JSON metadata stores numbers as doubles. This is an exact-integer encoding
# boundary, not a native file quota or a memory-admission allowance.
const MAX_JSON_INTEGER=9007199254740991
static var enabled:=true # Probe-only A/B switch; ordinary entry points leave enabled.

static func directory(content_root:String="")->String:
	return content_root.path_join("cache/world3d/compiled_assets_v1") if not content_root.is_empty() else Paths.cache_directory("compiled_assets_v1")

static func index_path(path:String,content_root:String="")->String:
	return directory(content_root).path_join(path.replace("\\","/").simplify_path().sha256_text()+".json")

static func generator()->String:
	var values:Array=[VERSION,Engine.get_version_info(),ProjectSettings.get_setting("rendering/renderer/rendering_method","")]
	for path in ["compiled_asset_cache.gd","gltf_map_io.gd","grass_texture_cache.gd","model_texture_cache.gd","model_texture_products.gd","streamed_texture_product.gd","model_lod_preparation.gd","leaf_backlight.gd","tinted_glass.gd","asset_visibility_range.gd","asset_bounds_manifest.gd"]:
		values.append(FileAccess.get_sha256("res://scripts/world3d/"+path))
	return JSON.stringify(values).sha256_text()

static func _sha(value:Variant)->bool:
	if not value is String or value.length()!=64:return false
	for ch in value:
		if ch not in "0123456789abcdef":return false
	return true

static func valid_payload_size(value:Variant)->bool:
	if value is int:return value>0 and value<=MAX_JSON_INTEGER
	return value is float and is_finite(value) and value>0 and value<=MAX_JSON_INTEGER and value==floor(value)

static func _miss(reason:String,started:int)->Dictionary:
	return {"hit":false,"reason":reason,"elapsed_us":Time.get_ticks_usec()-started}

static func _allocated_miss(reason:String,started:int,loaded:Resource)->Dictionary:
	# The reader may run on a worker. Even invalid native types can already own
	# renderer resources; keep them in the failed result until main retires it.
	var result:=_miss(reason,started)
	if loaded!=null:result.retained_resources=[loaded]
	return result

static func dispose_miss(packet:Dictionary)->bool:
	if packet.get("hit",false):return false
	if packet.get("retained_resources",[]).is_empty():return true
	if OS.get_thread_caller_id()!=OS.get_main_thread_id():return false
	var diagnostics:=packet.duplicate()
	diagnostics.erase("retained_resources")
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(packet)
	packet.merge(diagnostics)
	return true

static func read(path:String,verified_digest:String="",content_root:String="",caller_verifies_source:bool=false,trusted_package:bool=false)->Dictionary:
	var started:=Time.get_ticks_usec()
	if not enabled:return _miss("disabled",started)
	# Strict callers can delegate the final source check to their transaction.
	# Gameplay may explicitly trust the published package identity instead.
	if caller_verifies_source and not _sha(verified_digest):return _miss("missing_verified_digest",started)
	if content_root.is_empty():
		if OS.get_thread_caller_id()!=OS.get_main_thread_id():return _miss("missing_root_snapshot",started)
		content_root=Paths.external_root()
	var folder:=directory(content_root)
	if not Paths.allowed(path,content_root) or not FileAccess.file_exists(path):return _miss("source_missing_or_outside_root",started)
	var index:=index_path(path,content_root)
	if not Paths.allowed(index,folder) or not FileAccess.file_exists(index):return _miss("absent",started)
	var file:=FileAccess.open(index,FileAccess.READ)
	if file==null or file.get_length()>8192:return _miss("invalid_manifest",started)
	var data:Variant=JSON.parse_string(file.get_as_text());file.close()
	if not data is Dictionary or data.get("version")!=VERSION or data.get("generator")!=generator():return _miss("version",started)
	if not _sha(data.get("source_sha")) or not _sha(data.get("payload_sha")):return _miss("invalid_manifest",started)
	if not valid_payload_size(data.get("bytes")):return _miss("invalid_size",started)
	if data.has("texture_table"):
		if not data.texture_table is Dictionary or not TextureProducts.read_table(data.texture_table,content_root,trusted_package).ok:return _miss("texture_table",started)
	# Strict reads bind this candidate to a final source scan. Gameplay binds it
	# to the authored package identity. Both validate the derived native product.
	var digest:=verified_digest if _sha(verified_digest) else str(data.source_sha)
	if trusted_package:digest=preload("res://scripts/world3d/runtime_package_policy.gd").source_identity(path,verified_digest)
	if digest!=data.source_sha:return _miss("source_changed",started)
	var payload:=folder.path_join(data.payload_sha+".scn")
	if not Paths.allowed(payload,folder):return _miss("payload_path",started)
	file=FileAccess.open(payload,FileAccess.READ)
	if file==null or file.get_length()!=int(data.bytes):return _miss("payload_missing_or_size",started)
	file.close()
	var verify_started:=Time.get_ticks_usec()
	if FileAccess.get_sha256(payload)!=data.payload_sha:return _miss("payload_checksum",started)
	Trace.elapsed("compiled.payload_sha",verify_started,{"path":path,"bytes":data.bytes})
	# The native file is our own verified product, never a path supplied by a map.
	# No external dependencies may bypass the GLB's closed dependency identity.
	if not ResourceLoader.get_dependencies(payload).is_empty():return _miss("external_dependency",started)
	var load_started:=Time.get_ticks_usec()
	var loaded:Resource=ResourceLoader.load(payload,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var packed:=loaded as PackedScene
	Trace.elapsed("compiled.native_read",load_started,{"path":path,"bytes":data.bytes})
	if packed==null or not _valid_packed(packed,not data.has("texture_table")):return _allocated_miss("invalid_product",started,loaded)
	if not Paths.allowed(path,content_root):return _allocated_miss("source_changed_during_read",started,loaded)
	if not caller_verifies_source and not trusted_package:
		var source_started:=Time.get_ticks_usec()
		var final_digest:=FileAccess.get_sha256(path)
		Trace.elapsed("compiled.source_sha",source_started,{"path":path})
		if final_digest!=digest:return _allocated_miss("source_changed_during_read",started,loaded)
	packed.set_meta("compiled_asset_validated",true)
	Trace.elapsed("compiled.read",started,{"path":path,"bytes":data.bytes})
	var result:Dictionary={"hit":true,"packed":packed,"source_digest":digest,"elapsed_us":Time.get_ticks_usec()-started,"bytes":int(data.bytes)}
	if data.has("texture_table"):result.texture_table=data.texture_table
	return result

## Main-thread import transaction. The parsed state is private to this owner,
## bound to bytes verified before and after parsing. A re-export must create a
## new owner for the final GLB; its original GLTFState is never interchangeable.
class PreparedSource extends RefCounted:
	var path:String
	var source_digest:String
	var document:GLTFDocument
	var state:GLTFState
	var scene:Node
	var error:Error=OK
	var reason:String=""
	var parse_count:int=0
	var scene_count:int=0
	var disposed:bool=false
	var trusted_package:bool=false

	func current()->bool:
		if trusted_package:return not disposed and error==OK and not source_digest.is_empty() and FileAccess.file_exists(path)
		return not disposed and error==OK and not source_digest.is_empty() and FileAccess.get_sha256(path)==source_digest

	func relocate(destination:String)->bool:
		# Copy/rename may change the pathname, never the represented bytes.
		if disposed or error!=OK or FileAccess.get_sha256(destination)!=source_digest:return false
		path=destination
		return true

	func get_scene()->Node:
		if disposed or error!=OK:return null
		if scene==null:
			if not current():error=ERR_FILE_CORRUPT;reason="source_changed";return null
			scene=load("res://scripts/world3d/gltf_map_io.gd").generate_scene(document,state)
			scene_count+=1
		return scene

	func report()->Dictionary:
		return {"parse_count":parse_count,"scene_count":scene_count,"source_sha":source_digest}

	func dispose()->void:
		assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
		if disposed:return
		disposed=true
		if is_instance_valid(scene):preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(scene)
		scene=null
		preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
		state=null;document=null

static func prepare_source(path:String,trusted_package:bool=false)->PreparedSource:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	var prepared:=PreparedSource.new();prepared.path=path;prepared.trusted_package=trusted_package
	prepared.source_digest=preload("res://scripts/world3d/runtime_package_policy.gd").source_identity(path) if trusted_package else FileAccess.get_sha256(path)
	if not _sha(prepared.source_digest):prepared.error=ERR_FILE_CANT_READ;prepared.reason="source_path";return prepared
	prepared.document=GLTFDocument.new();prepared.state=GLTFState.new()
	prepared.parse_count+=1
	prepared.error=prepared.document.append_from_file(path,prepared.state,0,path.get_base_dir())
	if prepared.error!=OK:prepared.reason="parse";return prepared
	preload("res://scripts/world3d/model_lod_preparation.gd").prepare(prepared.state)
	# Godot may return OK after an embedded image failed to decode.
	if prepared.state.images.size()!=prepared.state.json.get("images",[]).size():prepared.error=ERR_FILE_CORRUPT;prepared.reason="images";return prepared
	for texture in prepared.state.images:
		if texture==null or texture.get_width()<=0 or texture.get_height()<=0:prepared.error=ERR_FILE_CORRUPT;prepared.reason="image_decode";return prepared
	if not prepared.current():prepared.error=ERR_FILE_CORRUPT;prepared.reason="source_changed"
	return prepared

static func build(path:String,split_textures:bool=false)->Dictionary:
	var started:=Time.get_ticks_usec()
	if OS.get_thread_caller_id()!=OS.get_main_thread_id():return {"ok":false,"reason":"main_thread_required"}
	if DisplayServer.get_name()=="headless":return {"ok":false,"reason":"graphics_required"}
	if not Paths.allowed(path) or not FileAccess.file_exists(path):return {"ok":false,"reason":"source_path"}
	var source_digest:=FileAccess.get_sha256(path)
	var bounds:=Manifest.read(path)
	if not bounds.get("known",false):return {"ok":false,"reason":"unsupported:"+str(bounds.get("reason",""))}
	var hit:=read(path,source_digest)
	if hit.hit and hit.has("texture_table")==split_textures:return _reuse_build_hit(hit,started)
	if hit.hit:preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(hit)
	if not dispose_miss(hit):return {"ok":false,"reason":"main_disposal_required"}
	var prepared:=prepare_source(path)
	if prepared.source_digest!=source_digest:
		prepared.dispose();return {"ok":false,"reason":"source_changed"}
	var result:=_build_prepared(prepared,started,split_textures)
	prepared.dispose()
	return result

## Borrows the transaction's scene. The caller disposes it before measuring the
## native footprint, so the original decoded graph does not overlap readback.
static func build_from_prepared(prepared:PreparedSource,split_textures:bool=false)->Dictionary:
	var started:=Time.get_ticks_usec()
	if OS.get_thread_caller_id()!=OS.get_main_thread_id():return {"ok":false,"reason":"main_thread_required"}
	if DisplayServer.get_name()=="headless":return {"ok":false,"reason":"graphics_required"}
	if prepared==null or prepared.disposed or not Paths.allowed(prepared.path):return {"ok":false,"reason":"source_path"}
	if prepared.error!=OK:return {"ok":false,"reason":prepared.reason,"error":prepared.error}
	var bounds:=Manifest.read(prepared.path)
	if not bounds.get("known",false):return {"ok":false,"reason":"unsupported:"+str(bounds.get("reason",""))}
	var hit:=read(prepared.path,prepared.source_digest)
	if hit.hit and hit.has("texture_table")==split_textures:return _reuse_build_hit(hit,started)
	if hit.hit:preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(hit)
	if not dispose_miss(hit):return {"ok":false,"reason":"main_disposal_required"}
	return _build_prepared(prepared,started,split_textures)

static func _reuse_build_hit(hit:Dictionary,started:int)->Dictionary:
	var bytes:int=hit.bytes
	var texture_table:Dictionary=hit.get("texture_table",{})
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(hit)
	var result:Dictionary={"ok":true,"reused":true,"bytes":bytes,"elapsed_us":Time.get_ticks_usec()-started}
	if not texture_table.is_empty():result.texture_table=texture_table
	return result

static func _build_prepared(prepared:PreparedSource,started:int,split_textures:bool=false)->Dictionary:
	if prepared.error!=OK:return {"ok":false,"reason":prepared.reason,"error":prepared.error}
	if not prepared.current():return {"ok":false,"reason":"source_changed"}
	var path:=prepared.path;var source_digest:=prepared.source_digest;var state:=prepared.state
	if Manifest.has_native_identity(state.json) or not state.json.get("skins",[]).is_empty() or not state.json.get("animations",[]).is_empty():return {"ok":false,"reason":"changed_or_unsupported_scene"}
	if state.images.size()!=state.json.get("images",[]).size():return {"ok":false,"reason":"images"}
	for texture in state.images:
		if texture==null or texture.get_width()<=0 or texture.get_height()<=0:return {"ok":false,"reason":"image_decode"}
	var scene:Node=prepared.get_scene()
	if scene==null:return {"ok":false,"reason":"generate"}
	# Keep ordinary publication on the current contract until every consumer is
	# integrated. Explicit split builds replace the stamp/readback pass itself.
	var textures:Dictionary={}
	if split_textures:
		textures=TextureProducts.prepare(scene,Paths.external_root())
		if not textures.ok:return {"ok":false,"reason":"texture_split:"+str(textures.error),"error":textures.get("error_code",FAILED)}
	else:
		preload("res://scripts/world3d/model_texture_cache.gd").stamp(scene)
	_own(scene,scene)
	var packed:=PackedScene.new();var err:=packed.pack(scene)
	# No runtime CPU mesh metadata, scripts or per-instance effects are bundled.
	if err!=OK or not _valid_packed(packed,not split_textures):
		packed=null;TextureProducts.restore(textures)
		return {"ok":false,"reason":"unsupported_scene"}
	if not Paths.allowed(directory()) or DirAccess.make_dir_recursive_absolute(directory())!=OK:
		packed=null;TextureProducts.restore(textures)
		return {"ok":false,"reason":"cache_directory"}
	var temporary:=directory().path_join("build_%d_%d.scn"%[OS.get_process_id(),Time.get_ticks_usec()])
	err=ResourceSaver.save(packed,temporary,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)
	packed=null
	TextureProducts.restore(textures)
	if err!=OK:
		_remove(temporary);return {"ok":false,"reason":"save","error":err}
	var file:=FileAccess.open(temporary,FileAccess.READ)
	if file==null:_remove(temporary);return {"ok":false,"reason":"product_read"}
	var size:=file.get_length();file.close()
	if not valid_payload_size(size) or not ResourceLoader.get_dependencies(temporary).is_empty():
		_remove(temporary);return {"ok":false,"reason":"invalid_or_external_product"}
	if not Paths.allowed(path) or FileAccess.get_sha256(path)!=source_digest:
		_remove(temporary);return {"ok":false,"reason":"source_changed"}
	var payload_digest:=FileAccess.get_sha256(temporary)
	var payload:=directory().path_join(payload_digest+".scn")
	if not Paths.allowed(payload,directory()):_remove(temporary);return {"ok":false,"reason":"payload_path"}
	if FileAccess.file_exists(payload):
		if FileAccess.get_sha256(payload)!=payload_digest:_remove(temporary);return {"ok":false,"reason":"existing_product_corrupt"}
		_remove(temporary)
	else:
		# These are the only consumable model products, not an evictable cache.
		# A global historical-byte quota made unrelated imports fail after all
		# parsing/serialization work. Per-product bounds and filesystem errors
		# still apply; live memory is governed by the separate admission ledger.
		err=DirAccess.rename_absolute(temporary,payload)
		if err!=OK:
			_remove(temporary)
			if FileAccess.get_sha256(payload)!=payload_digest:return {"ok":false,"reason":"publish_payload","error":err}
	var index:=index_path(path);var staged:=index+".%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
	if not Paths.allowed(index,directory()):return {"ok":false,"reason":"index_path"}
	file=FileAccess.open(staged,FileAccess.WRITE)
	if file==null:return {"ok":false,"reason":"manifest_write"}
	var manifest:Dictionary={"version":VERSION,"source_path":path,"source_sha":source_digest,"generator":generator(),"payload_sha":payload_digest,"bytes":size}
	if split_textures:manifest.texture_table=textures.texture_table
	file.store_string(JSON.stringify(manifest))
	file.flush();err=file.get_error();file.close()
	if err==OK:err=preload("res://scripts/world3d/atomic_file.gd").publish(staged,index)
	_remove(staged)
	var result:Dictionary={"ok":err==OK,"reused":false,"bytes":size,"elapsed_us":Time.get_ticks_usec()-started,"error":err}
	if split_textures:
		result.texture_table=textures.texture_table;result.texture_stats=textures.stats
	return result

static func instantiate(packed:PackedScene)->Node3D:
	var scene:=packed.instantiate() as Node3D
	if scene!=null and packed.get_meta("compiled_asset_validated",false):
		# The verified product retains the pixel identity computed at build time.
		# Restore cross-GLB sharing without GPU image readback on the warm path.
		preload("res://scripts/world3d/grass_texture_cache.gd").apply(scene,true)
		preload("res://scripts/world3d/model_texture_cache.gd").apply(scene)
		# A preview has no shared-library owner. Retain resources on the root
		# until every child instance has queued its renderer destruction first.
		scene.set_meta("_compiled_resource_owner",packed)
	return scene

static func _own(node:Node,root:Node)->void:
	for child in node.get_children():child.owner=root;_own(child,root)

static func _remove(path:String)->void:
	if Paths.allowed(path,directory()) and FileAccess.file_exists(path):DirAccess.remove_absolute(path)

static func strict_image_free(packed:PackedScene)->bool:
	return packed!=null and _valid_packed(packed,false)

static func _valid_packed(packed:PackedScene,allow_images:bool=true)->bool:
	var state:=packed.get_state();var seen:Dictionary={}
	if state.get_node_count()==0:return false
	for i in state.get_node_count():
		if state.get_node_type(i) not in [&"Node3D",&"MeshInstance3D"]:return false
		if state.get_node_instance(i)!=null:return false
		for j in state.get_node_property_count(i):
			if not _valid_value(state.get_node_property_value(i,j),seen,0,allow_images):return false
	return true

static func _valid_value(value:Variant,seen:Dictionary,depth:int=0,allow_images:bool=true)->bool:
	if depth>32:return false
	if value is Resource:
		if value.get_script()!=null:return false
		var id:int=value.get_instance_id()
		if seen.has(id):return true
		seen[id]=true
		if value is ImageTexture or value is Image:return allow_images
		if not value is ArrayMesh and not value is StandardMaterial3D:return false
		for info in value.get_property_list():
			if int(info.usage)&PROPERTY_USAGE_STORAGE and not _valid_value(value.get(info.name),seen,depth+1,allow_images):return false
		return true
	if value is Object or value is Callable or value is Signal or value is RID:return false
	if value is Dictionary:
		for key in value:
			if not _valid_value(key,seen,depth+1,allow_images) or not _valid_value(value[key],seen,depth+1,allow_images):return false
	elif value is Array:
		for item in value:
			if not _valid_value(item,seen,depth+1,allow_images):return false
	return true
