extends Node
## A map owns this queue. Only independent static GLB scenes are prepared on
## the worker; shared library publication and instance effects stay on main.
signal published(specs:Array)
signal completed
signal failed(reason:String)
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var pending:Array=[]
var profile:Dictionary={"models":0,"instances":0,"specs":0,"worker_us":0,"max_publish_us":0}
var error:=""
var source_signatures:Dictionary={}
var _map:Node
var _host:Node
var _worker:Thread
var _worker_token:RefCounted
var _drainer:Node
var _worker_path:=""
var _scene:Node
var _ready_path:=""
var _prepared_paths:Dictionary={}
var _cancelled:=false
var _active:=false
var _priority:=Vector3.ZERO
var _requested:Variant=null
var _pending_index:Dictionary={}
var _large_pending:Array=[]
var _indexed:=false
var _doc=preload("res://scripts/world3d/world_document.gd").new()

func _init()->void:
	name="DeferredAssets";set_meta("stream_instance",true);set_process(false)
	_doc.load_immutable_records=true;_doc.load_paint_validation={};_doc.load_texture_checks={}

func activate(host:Node)->void:
	_map=get_parent();_host=host;_active=true;set_process(true)

func is_complete()->bool:return pending.is_empty() and _worker==null and _scene==null and _ready_path.is_empty()

func ensure_geometry(clip:AABB)->bool:
	if not _indexed:
		for item:Dictionary in pending:
			var box:AABB=item.bounds
			var low:=Stream.chunk_key(box.position);var high:=Stream.chunk_key(box.end)
			if (high.x-low.x+1)*(high.y-low.y+1)>64:_large_pending.append(item);continue
			for z in range(low.y,high.y+1):
				for x in range(low.x,high.x+1):
					var key:=Vector2i(x,z)
					if not _pending_index.has(key):_pending_index[key]=[]
					_pending_index[key].append(item)
		_indexed=true
	var candidates:Dictionary={}
	for item:Dictionary in _large_pending:candidates[item.record.uuid]=item
	var low:=Stream.chunk_key(clip.position);var high:=Stream.chunk_key(clip.end)
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for item:Dictionary in _pending_index.get(Vector2i(x,z),[]):
				if not item.get("published",false):candidates[item.record.uuid]=item
	var ready:=true
	for item:Dictionary in candidates.values():
		if item.get("published",false):continue
		var box:AABB=item.bounds
		if Rect2(clip.position.x,clip.position.z,clip.size.x,clip.size.z).intersects(Rect2(box.position.x,box.position.z,box.size.x,box.size.z)):ready=false;break
	if not ready:_requested=clip;_priority=clip.get_center()
	return ready

func prioritize(position:Vector3)->void:
	if _requested==null:_priority=position

static func prepare_scene(path:String,digest:String,token:RefCounted=null,expected_manifest:Dictionary={},collision_faces_required:bool=false)->Dictionary:
	var began:=preload("res://scripts/world3d/load_trace.gd").begin("deferred.prepare")
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	var Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
	if digest.is_empty():
		if expected_manifest.is_empty():return {"error":"缺少后台素材边界快照："+path}
		var current:Dictionary=Manifest.read(path)
		if not current.known or current.get("json_sha256")!=expected_manifest.get("json_sha256") or current.get("file_length")!=expected_manifest.get("file_length"):
			return {"error":"素材边界在后台准备前发生变化："+path}
	var source_digest:=FileAccess.get_sha256(path)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.source_sha",began,{"path":path})
	if source_digest.is_empty() or (not digest.is_empty() and source_digest!=digest):return {"error":"素材在后台准备前发生变化："+path}
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var parse_started:=Time.get_ticks_usec()
	var result:=document.append_from_file(path,state,0,path.get_base_dir())
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.model_parse",parse_started,{"path":path})
	if result!=OK:return {"error":"素材读取失败："+path+" "+error_string(result)}
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	if Manifest.has_native_identity(state.json):return {"error":"原生地图不能作为独立后台素材："+path}
	# Bind deferred classification to the same header after the potentially slow
	# full-file hash and parser read as well as before them.
	if not expected_manifest.is_empty():
		var current:Dictionary=Manifest.read(path)
		if not current.known or current.get("json_sha256")!=expected_manifest.get("json_sha256") or current.get("file_length")!=expected_manifest.get("file_length"):
			return {"error":"素材边界在后台准备期间发生变化："+path}
	# The queue admits static self-contained files only. Every node/resource here
	# belongs to this worker and has never entered a SceneTree or shared scene cache.
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true}
	var generate_started:=Time.get_ticks_usec()
	var scene:Node=Io.generate_scene(document,state)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.scene_generate",generate_started,{"path":path})
	if scene==null:return {"error":"素材构建失败："+path}
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true,"scene":scene}
	var capture_started:=Time.get_ticks_usec()
	var captured:=_capture_static_meshes(scene,collision_faces_required,token)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.cpu_capture",capture_started,{"path":path,"collision_faces":collision_faces_required})
	if not captured.error.is_empty():
		captured.scene=scene
		return captured
	var final_sha_started:=Time.get_ticks_usec()
	var final_digest:=FileAccess.get_sha256(path)
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.final_source_sha",final_sha_started,{"path":path})
	if final_digest!=source_digest:return {"error":"素材在后台准备期间发生变化："+path,"scene":scene}
	if token!=null and token.is_cancelled():return {"error":"素材准备已取消","cancelled":true,"scene":scene}
	captured.merge({"scene":scene,"elapsed_us":Time.get_ticks_usec()-began,"source_digest":source_digest})
	preload("res://scripts/world3d/load_trace.gd").elapsed("deferred.prepare",began,{"path":path})
	return captured

static func _capture_static_meshes(scene:Node,faces_required:bool,token:RefCounted=null)->Dictionary:
	# Only worker-owned imported arrays: PrimitiveMesh capture has a shared lazy
	# box cache. Do not replace the visual mesh or publish any shared library state.
	var Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
	var profile:Dictionary={"error":"","capture_us":0,"face_us":0,"capture_bytes":0,"face_bytes":0,"captured_meshes":0}
	var seen:Dictionary={};var nodes:Array[Node]=[scene]
	while not nodes.is_empty():
		if token!=null and token.is_cancelled():
			profile.error="素材准备已取消";profile.cancelled=true;return profile
		var node:Node=nodes.pop_back()
		nodes.append_array(node.get_children())
		if not node is MeshInstance3D or not node.mesh is ArrayMesh or node.skin!=null:continue
		var mesh:ArrayMesh=node.mesh
		if seen.has(mesh.get_instance_id()):continue
		seen[mesh.get_instance_id()]=true
		if mesh.get_blend_shape_count()!=0:continue
		var triangles:=true
		for slot in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(slot)!=Mesh.PRIMITIVE_TRIANGLES:triangles=false;break
		if not triangles:continue
		var began:=Time.get_ticks_usec()
		var cpu:Mesh=Cpu.capture(mesh)
		profile.capture_us+=Time.get_ticks_usec()-began;profile.captured_meshes+=1
		for arrays:Array in cpu.surfaces:
			for channel:Variant in arrays:profile.capture_bytes+=_packed_payload_bytes(channel)
		if not faces_required:continue
		# Validate before the unchecked packed-index expansion. No generated Node
		# is released here; even a malformed result returns to the main drainer.
		for arrays:Array in cpu.surfaces:
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:Variant=arrays[Mesh.ARRAY_INDEX]
			var count:int=indices.size() if indices!=null and not indices.is_empty() else vertices.size()
			if count%3!=0:profile.error="后台素材三角面记录不完整";return profile
			if indices!=null:
				for index:int in indices:
					if index<0 or index>=vertices.size():profile.error="后台素材三角面索引越界";return profile
		if token!=null and token.is_cancelled():
			profile.error="素材准备已取消";profile.cancelled=true;return profile
		began=Time.get_ticks_usec()
		var faces:PackedVector3Array=cpu.collision_faces()
		profile.face_us+=Time.get_ticks_usec()-began;profile.face_bytes+=faces.size()*12
	return profile

static func _packed_payload_bytes(value:Variant)->int:
	# Packed buffer payload only, excluding Resource/container overhead. No extra
	# to_byte_array copies just to collect diagnostics (standard single precision).
	match typeof(value):
		TYPE_PACKED_BYTE_ARRAY:return value.size()
		TYPE_PACKED_INT32_ARRAY,TYPE_PACKED_FLOAT32_ARRAY:return value.size()*4
		TYPE_PACKED_INT64_ARRAY,TYPE_PACKED_FLOAT64_ARRAY,TYPE_PACKED_VECTOR2_ARRAY:return value.size()*8
		TYPE_PACKED_VECTOR3_ARRAY:return value.size()*12
		TYPE_PACKED_VECTOR4_ARRAY,TYPE_PACKED_COLOR_ARRAY:return value.size()*16
	return 0

func _process(_delta:float)->void:
	if not _active or _cancelled or not error.is_empty():return
	if _worker!=null:
		if _worker.is_alive():return
		var result:Dictionary=_worker.wait_to_finish()
		if is_instance_valid(_drainer):_drainer.forget(_worker)
		_worker=null;_worker_token=null
		if not result.error.is_empty():
			if is_instance_valid(result.get("scene")):Drainer.dispose_scene(result.scene)
			_fail(result.error);return
		Drainer.synchronize_transfer()
		_scene=result.scene;_ready_path=_worker_path;profile.worker_us+=result.elapsed_us;profile.models+=1
		for key in ["capture_us","face_us","capture_bytes","face_bytes","captured_meshes"]:profile[key]=int(profile.get(key,0))+int(result.get(key,0))
		if result.has("source_digest"):source_signatures[_worker_path]=result.source_digest
	# Finish the current covered entry before publishing unrelated distant work.
	if is_instance_valid(_host) and "_ready_for_play" in _host and not _host._ready_for_play:return
	if _scene!=null:
		if not Assets.cache_scene(_ready_path,_scene):_scene=null;_fail("无法缓存后台素材："+_ready_path);return
		_prepared_paths[_ready_path]=true;_scene=null;_ready_path=""
	var began:=Time.get_ticks_usec()
	while not pending.is_empty() and Time.get_ticks_usec()-began<2000:
		var at:=_nearest_index()
		var item:Dictionary=pending[at]
		# Choose globally: a nearby new model precedes distant instances of a
		# model already prepared. Re-evaluate after each publication/player move.
		if not _prepared_paths.has(item.path):break
		var holder:Node3D=_doc._asset(item.record)
		if holder.has_meta("missing_asset") or holder.has_meta("paint_error"):
			holder.free();_fail("后台物件构建失败："+str(item.record.uuid));return
		var specs:Array=[];_collect(holder,Transform3D.IDENTITY,specs)
		for i in specs.size():specs[i].map_draw_order=int(item.get("draw_order",0))+i
		holder.free()
		var registered:Dictionary=Stream.append_specs(_map,specs)
		if not registered.ok:_fail("后台物件登记失败："+str(registered.error));return
		item.published=true;pending.remove_at(at);profile.instances+=1;profile.specs+=specs.size()
		published.emit(specs)
	profile.max_publish_us=maxi(profile.max_publish_us,Time.get_ticks_usec()-began)
	if _requested!=null and ensure_geometry(_requested):_requested=null
	if pending.is_empty():set_process(false);completed.emit();return
	var next:Dictionary=pending[_nearest_index()]
	if _prepared_paths.has(next.path):return
	_worker_path=next.path;_worker=Thread.new()
	_worker_token=Drainer.CancelToken.new();_drainer=Drainer.for_tree(get_tree())
	_drainer.watch(_worker,_worker_token)
	var needs_faces:=false
	for item:Dictionary in pending:
		if item.path==next.path and str(item.record.get("collision",""))!="none":needs_faces=true;break
	# A failed worker start must never move a multi-second import onto live frames.
	if _worker.start(prepare_scene.bind(next.path,next.digest,_worker_token,next.get("manifest",{}),needs_faces))!=OK:
		_drainer.forget(_worker);_worker=null;_worker_token=null;_fail("无法启动附近素材后台准备："+next.path)

func _nearest_index()->int:
	var at:=-1;var nearest:=INF
	for i in pending.size():
		var distance:float=_distance(pending[i])
		if distance<nearest:nearest=distance;at=i
	return at

func _distance(item:Dictionary)->float:
	var bounds:AABB=item.bounds
	var point:=Vector3(clampf(_priority.x,bounds.position.x,bounds.end.x),_priority.y,clampf(_priority.z,bounds.position.z,bounds.end.z))
	return _priority.distance_squared_to(point)

static func _collect(node:Node,pose:Transform3D,result:Array)->void:
	if node is Node3D:pose=pose*node.transform
	if node is MeshInstance3D:
		var spec:Dictionary=Stream._spec(node)
		spec.transform=pose;spec.position=pose.origin;spec.rotation=pose.basis.get_euler()
		var box:AABB=pose*node.get_aabb()
		spec.chunk=Stream.chunk_key(pose.origin);spec.chunk_min=Stream.chunk_key(box.position);spec.chunk_max=Stream.chunk_key(box.end)
		preload("res://scripts/world3d/building_fixtures.gd").prepare_spec(spec)
		spec.uuid=str(spec.extras.get("uuid",node.name));result.append(spec)
	for child:Node in node.get_children():_collect(child,pose,result)

func _fail(reason:String)->void:
	error=reason;set_process(false);failed.emit(reason)

func _exit_tree()->void:
	_cancelled=true
	if _worker_token!=null:_worker_token.cancel()
	if _worker!=null:
		if is_instance_valid(_drainer) and _drainer.is_inside_tree():_drainer.abandon(_worker)
		else:Drainer.drain_shutdown(_worker,_worker_token)
		_worker=null;_worker_token=null
	if is_instance_valid(_scene):Drainer.dispose_scene(_scene);_scene=null
