extends Node
## Private, admitted GPU resources + shader draw warmup. No authority, events,
## navigation or target physics activation before confirmed-transfer adoption.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const LEASE_BYTES=1024*1024*1024
static var enabled:=true
var profile:Dictionary={"started":0,"ready":0,"hits":0,"cancelled":0,"misses":0,"warmed_meshes":0}
var _loader:Node
var _scene:Node3D
var _viewport:SubViewport
var _warm:Array=[]
var _manifest:Dictionary={}
var _ledger:RefCounted
var _token:RefCounted
var _lease:=""
var _path:=""
var _destination:=Vector3.ZERO
var _touched:=0
var _gpu_ready:=false
var _warming:=false
var _verify:Thread
var _verify_ticket:Dictionary={}
var _root:=""
static func plan(records:Array,root:String,source_path:String,source_sha:String,dependencies:Dictionary)->Dictionary:
	var files:Dictionary={source_path:source_sha};var models:Dictionary={};var pixels:Dictionary={};var bytes:=512*1024*1024
	for record:Dictionary in records:
		bytes+=int(record.get("house_prefab",{}).get("length",0))*16
		if record.has("terrain_mesh"):bytes+=int(record.terrain_mesh.columns)*int(record.terrain_mesh.rows)*1024
		if not record.has("house_prefab"):
			for path:String in [str(record.get("asset_path","")),str(record.get("fortification_art",{}).get("asset_path",""))]:
				if not path.is_empty():models[path]=true
		if not preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:
			for definition:Dictionary in Paint.definitions(record):
				for field:String in Paint.MAP_FIELDS:
					var path:String=definition.get(field,"")
					if not path.is_empty():pixels[path]=true
	for path:String in models:
		var file_identities:Dictionary={}
		var metadata:=preload("res://scripts/world3d/native_model_product.gd").read(path,root,"",-1,null,file_identities)
		var memory:=preload("res://scripts/world3d/model_parse_preparation.gd").native_memory(metadata)
		if memory.is_empty():return {}
		bytes+=int(memory.estimated_bytes)*2
		# The authoring path is a logical key. Only the actual published index,
		# descriptor and native payload participate in prefetch invalidation.
		for metadata_path:String in [metadata.native_index_path,metadata.native_descriptor_path]:
			if not file_identities.has(metadata_path):return {}
			files[metadata_path]=file_identities[metadata_path]
		files[metadata.native_product_path]={"sha256":metadata.native_payload_sha,"length":int(metadata.native_product_bytes),"native_product":true}
	for path:String in pixels:
		var header:=preload("res://scripts/world3d/prefab_texture_preparation.gd")._header(path,root)
		if header.is_empty():return {}
		bytes+=int(header.width)*int(header.height)*4*8+int(header.source_bytes)*2
		files[path]=FileAccess.get_sha256(path)
	for uri:String in dependencies:
		var path:=preload("res://scripts/world3d/map_resource_store.gd")._location(uri,dependencies[uri],source_path,root)
		if path.is_empty():return {}
		files[path]=dependencies[uri]
	if bytes>LEASE_BYTES:return {}
	for path:String in files:
		if not Paths.allowed(path,root):return {}
		if files[path] is Dictionary:
			if not _native_file_identity(path,files[path],root):return {}
		elif not preload("res://scripts/world3d/compiled_asset_cache.gd")._sha(files[path]):return {}
	return {"files":files,"estimated_bytes":bytes}

static func _native_file_identity(path:String,identity:Dictionary,root:String)->bool:
	if identity.size()!=3 or identity.get("native_product")!=true or not preload("res://scripts/world3d/compiled_asset_cache.gd")._sha(identity.get("sha256")) or not identity.get("length") is int or not preload("res://scripts/world3d/compiled_asset_cache.gd").valid_payload_size(identity.length):return false
	var directory:String=preload("res://scripts/world3d/compiled_asset_cache.gd").directory(root)
	return path==directory.path_join(identity.sha256+".scn") and Paths.allowed(path,directory)

static func verify(files:Dictionary,root:String)->bool:
	for path:String in files:
		if files[path] is Dictionary:
			var identity:Dictionary=files[path]
			if not _native_file_identity(path,identity,root):return false
			var file:=FileAccess.open(path,FileAccess.READ)
			if file==null or file.get_length()!=identity.length:return false
			file.close()
			if not preload("res://scripts/world3d/runtime_package_policy.gd").trusted() and FileAccess.get_sha256(path)!=identity.sha256:return false
			continue
		if preload("res://scripts/world3d/runtime_package_policy.gd").trusted() and path.get_extension().to_lower() in ["glb","rmres"]:
			if not Paths.allowed(path,root) or not FileAccess.file_exists(path):return false
			continue
		if not Paths.allowed(path,root) or FileAccess.get_sha256(path)!=files[path] or not Paths.allowed(path,root):return false
	return true
func request(path:String,destination:Vector3,ledger:RefCounted,cpu:Node)->bool:
	if not enabled:return false
	if path==_path and destination==_destination:_touched=Time.get_ticks_msec();return true
	if not _path.is_empty():cancel();return false
	if not is_instance_valid(cpu) or cpu._packet==null or cpu._packet.scene_plan.is_empty():return false
	# Parser/coordinator + its single model/hash worker share two source slots.
	if ledger.worker_limit<2 or ledger.active_workers()>0:return false
	_token=Drainer.CancelToken.new();_lease="target_gpu:%d"%get_instance_id()
	if not ledger.reserve_background(_lease,LEASE_BYTES,_token.cancel,2):_token=null;return false
	_root=Paths.external_root();_ledger=ledger;var packet:RefCounted=cpu.take(path,destination)
	if packet==null:_release();return false
	_path=path;_destination=destination;_manifest=packet.scene_plan.files.duplicate();_touched=Time.get_ticks_msec()
	_loader=load("res://scripts/world3d/map_loader.gd").new();_loader.background_preload=true;_loader.near_first=true;_loader.source_prefetch=packet
	_loader._model_preparation.inflight_byte_limit=LEASE_BYTES/2
	_loader.finished.connect(_loaded);add_child(_loader);_loader.start(path,destination)
	profile.started+=1;return true
func matches(path:String,destination:Vector3)->bool:
	return _path==path and _destination==destination and _token!=null and not _token.is_cancelled()
func _loaded(scene:Node,_target:String,error:String)->void:
	if _token==null or _token.is_cancelled() or not error.is_empty() or scene==null:
		if is_instance_valid(scene):Drainer.dispose_scene(scene)
		profile.misses+=1
		if _token!=null:_token.cancel()
		return
	_scene=scene;_warming=true
	# Keep the real target off-tree. Draw disposable ghosts sharing the exact GPU
	# buffers/materials; no target script or Deferred service enters a live tree.
	_viewport=SubViewport.new();_viewport.name="PrivateGPUWarmup";_viewport.own_world_3d=true;_viewport.size=Vector2i(64,64);_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(_viewport)
	var stage:=Node3D.new();_viewport.add_child(stage)
	var camera:=Camera3D.new();stage.add_child(camera);camera.position=_destination+Vector3(0,4,8);camera.look_at(_destination);camera.current=true
	var light:=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-45,-30,0)
	var slice:=Time.get_ticks_usec()
	for spec:Dictionary in scene.get_meta("stream_library",[]):
		if _token==null or _token.is_cancelled():_warming=false;return
		_ghost(stage,spec.mesh,spec.transform,spec.get("cast_shadow",GeometryInstance3D.SHADOW_CASTING_SETTING_ON),spec.get("material_override"),null,spec.get("surface_overrides",[]))
		if Time.get_ticks_usec()-slice>=2000:await get_tree().process_frame;slice=Time.get_ticks_usec()
	# Non-stream visuals (e.g. imported packed-scene children) use the same
	# bounded publication loop. Only immutable visual data enters the viewport.
	var stack:Array=[{"node":scene,"pose":Transform3D.IDENTITY}]
	while not stack.is_empty():
		if _token==null or _token.is_cancelled():_warming=false;return
		var row:Dictionary=stack.pop_back();var node:Node=row.node
		var pose:Transform3D=row.pose*node.transform if node is Node3D else row.pose
		if node is MeshInstance3D:
			var surfaces:Array=[]
			for slot in node.get_surface_override_material_count():surfaces.append(node.get_surface_override_material(slot))
			_ghost(stage,node.mesh,pose,node.cast_shadow,node.material_override,node.material_overlay,surfaces)
		for child:Node in node.get_children():
			if not child.has_meta("stream_instance"):stack.append({"node":child,"pose":pose})
		if Time.get_ticks_usec()-slice>=2000:await get_tree().process_frame;slice=Time.get_ticks_usec()
	await preload("res://scripts/util/frame_presentation.gd").drawn();await preload("res://scripts/util/frame_presentation.gd").drawn()
	# The warmed buffers stay owned by _warm/_scene until take or retirement.
	# A parked result must not keep rendering beside the playable source world.
	_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	_warming=false
	if _token==null or _token.is_cancelled():return
	_verify=Thread.new();_verify_ticket=preload("res://scripts/world3d/cpu_worker_retirement.gd").watch(_verify,get_tree(),[_manifest])
	if _verify.start(verify.bind(_manifest,_root))!=OK:_verify=null;preload("res://scripts/world3d/cpu_worker_retirement.gd").complete(_verify_ticket);cancel()
func _ghost(stage:Node3D,mesh:Mesh,pose:Transform3D,shadow:int,override:Material=null,overlay:Material=null,surfaces:Array=[])->void:
	if mesh==null:return
	var gpu:Mesh=mesh.restore() if mesh is Cpu else mesh
	var visual:=MeshInstance3D.new();visual.mesh=gpu;visual.transform=pose;visual.cast_shadow=shadow;visual.material_override=override;visual.material_overlay=overlay
	for slot in surfaces.size():visual.set_surface_override_material(slot,surfaces[slot])
	stage.add_child(visual);_warm.append(gpu)
	profile.warmed_meshes+=1
func _process(_delta:float)->void:
	if _verify!=null and not _verify.is_alive():
		var valid:bool=_verify.wait_to_finish();_verify=null;preload("res://scripts/world3d/cpu_worker_retirement.gd").complete(_verify_ticket)
		if valid and _token!=null and not _token.is_cancelled():_gpu_ready=true;_ledger.park(_lease);profile.ready+=1
		else:cancel()
	if _token!=null and (_token.is_cancelled() or Time.get_ticks_msec()-_touched>10000):cancel()
	if _loader!=null and not is_instance_valid(_loader):_loader=null
	if _token!=null and _token.is_cancelled() and _loader==null and _verify==null and not _warming:_dispose()
func take(path:String,destination:Vector3)->Node3D:
	if not _gpu_ready or path!=_path or destination!=_destination or not verify(_manifest,_root):return null
	var result:Node3D=_scene;_scene=null
	result.set_meta("prefetched_gpu_owners",_warm.duplicate());result.set_meta("gpu_preload_hit",true)
	_warm.clear();profile.hits+=1;_dispose();return result
func cancel()->void:
	if _token==null:return
	_token.cancel();_gpu_ready=false
	if is_instance_valid(_loader):_loader.cancel()
	profile.cancelled+=1
	if not is_instance_valid(_loader) and _verify==null and not _warming:_dispose()
func drain()->void:
	cancel()
	while _token!=null:await get_tree().process_frame
func _dispose()->void:
	if is_instance_valid(_viewport):_viewport.free()
	_viewport=null
	if is_instance_valid(_scene):Drainer.dispose_scene(_scene)
	_scene=null;_warm.clear();_manifest.clear();_release();_path="";_gpu_ready=false
func _release()->void:
	if _ledger!=null:_ledger.release(_lease)
	_ledger=null;_token=null;_lease=""
func _exit_tree()->void:
	if is_instance_valid(_loader):_loader.cancel();_loader.free();_loader=null
	if _verify!=null:
		# CPU verification owns only manifest scalars; the GPU scene stays on main.
		preload("res://scripts/world3d/asset_worker_drainer.gd").drain_shutdown(_verify);_verify=null
		preload("res://scripts/world3d/cpu_worker_retirement.gd").complete(_verify_ticket)
	_dispose()
