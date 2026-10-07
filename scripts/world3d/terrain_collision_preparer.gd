extends RefCounted
## Exact triangle slices are cooked and attached with collision disabled. Publish
## the whole static body only after all slices exist, preserving holes and seams.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const SLICE_VERTICES:=3072 # A multiple of three: never split a triangle.
var _thread:Thread
var _mesh:Mesh
var _spec:Dictionary={}
var _body:StaticBody3D
var _faces:=PackedVector3Array()
var _shapes:Array=[]
var _cursor:=0
var _cached:=false
var _ready_spec:Dictionary={}
var profile_enabled:=false
var profile_rows:Array=[]
var profile_collect_rows:=true
var last_profile:Dictionary={}
var _profile:Dictionary={}
var _profile_details:Dictionary={}

func _measure(stage:String,started:int)->void:
	if profile_enabled:_profile[stage]=float(_profile.get(stage,0.))+(Time.get_ticks_usec()-started)/1000.

func cancel(defer_free:bool=false)->void:
	var pending=_ready_spec.get("prepared_body")
	if is_instance_valid(pending):
		if defer_free:pending.queue_free()
		else:pending.free()
	_ready_spec.erase("prepared_body");_ready_spec={}
	if is_instance_valid(_body):
		if defer_free:_body.queue_free()
		else:_body.free()
	_body=null;_spec={};_faces=PackedVector3Array();_shapes=[];_cursor=0
	# A CPU-only worker can finish without blocking this frame. Its result is
	# discarded or joined on the next request/scene exit.
	if _thread==null:_mesh=null

func finish()->void:
	# On tree exit the host may be removing its children, including these sibling
	# bodies. Do not synchronously remove another child while that parent is busy.
	# Bodies remain disabled; the host or the deletion queue releases them once.
	cancel(true)
	if _thread!=null:_thread.wait_to_finish()
	_thread=null;_mesh=null

func prepare(spec:Dictionary,host:Node)->bool:
	if not profile_enabled:return _prepare(spec,host)
	_profile={};_profile_details={}
	var cursor_before:=_cursor
	var started:=Time.get_ticks_usec();var result:=_prepare(spec,host)
	last_profile={"ms":(Time.get_ticks_usec()-started)/1000.,"ready":result,"cursor":_cursor,"cursor_before":cursor_before,"stages":_profile,"details":_profile_details}
	if profile_collect_rows:profile_rows.append(last_profile)
	return result

func _prepare(spec:Dictionary,host:Node)->bool:
	var measured:=Time.get_ticks_usec() if profile_enabled else 0
	var ready=spec.get("prepared_body")
	if is_instance_valid(ready):return true
	var mesh:Mesh=spec.get("collision_mesh",spec.get("mesh"))
	if not _spec.is_empty() and not is_same(_spec,spec):cancel()
	_measure("cancel",measured)
	if _thread!=null:
		if _thread.is_alive():return false
		measured=Time.get_ticks_usec() if profile_enabled else 0
		var result:PackedVector3Array=_thread.wait_to_finish();_thread=null
		if not _spec.is_empty() and _mesh==mesh:_faces=result
		else:_mesh=null
		_measure("worker_handoff",measured)
	if _spec.is_empty():
		measured=Time.get_ticks_usec() if profile_enabled else 0
		_spec=spec;_mesh=mesh;_cursor=0
		_cached=mesh.has_meta("runtime_terrain_shapes")
		_shapes=mesh.get_meta("runtime_terrain_shapes",[]).duplicate()
		_measure("cached_shapes",measured)
		if not _cached:
			var cpu:Mesh=mesh if mesh is Cpu else (mesh.get_meta("ground_cpu_cache") if mesh.has_meta("ground_cpu_cache") else null)
			if cpu==null:_spec={};_mesh=null;return true
			var surfaces:Array=cpu.surfaces
			_thread=Thread.new()
			if _thread.start(func():return _extract(surfaces))==OK:return false
			_thread=null;_faces=_extract(surfaces)
	if _body==null:
		measured=Time.get_ticks_usec() if profile_enabled else 0
		_body=load("res://scripts/world3d/world_stream.gd")._body_shell(spec)
		_body.collision_layer=0;_body.collision_mask=0
		host.add_child(_body);_body.global_transform=spec.get("transform",_body.transform)
		_measure("body_shell",measured)
	var started:=Time.get_ticks_usec()
	var count:=_shapes.size() if _cached else ceili(float(_faces.size())/SLICE_VERTICES)
	if profile_enabled:_profile_details={"cached":_cached,"slice_count":count,"first_slice":_cursor,"faces_vertices":_faces.size(),"set_faces_intervals":[]}
	while _cursor<count:
		var shape:ConcavePolygonShape3D
		if _cached:shape=_shapes[_cursor]
		else:
			measured=Time.get_ticks_usec() if profile_enabled else 0
			shape=ConcavePolygonShape3D.new()
			var offset:=_cursor*SLICE_VERTICES
			var faces:=_faces.slice(offset,mini(offset+SLICE_VERTICES,_faces.size()))
			_measure("slice_copy",measured)
			measured=Time.get_ticks_usec() if profile_enabled else 0
			shape.set_faces(faces)
			_measure("shape_set_faces",measured)
			if profile_enabled:_profile_details.set_faces_intervals.append({"slice":_cursor,"vertices":faces.size(),"begin_usec":measured,"end_usec":Time.get_ticks_usec()})
			_shapes.append(shape)
		measured=Time.get_ticks_usec() if profile_enabled else 0
		var child:=CollisionShape3D.new();child.shape=shape;_body.add_child(child)
		_measure("shape_attach",measured)
		_cursor+=1
		if Time.get_ticks_usec()-started>=1500:break
	if profile_enabled:_profile_details["end_slice"]=_cursor
	if _cursor<count:return false
	measured=Time.get_ticks_usec() if profile_enabled else 0
	if not _cached:mesh.set_meta("runtime_terrain_shapes",_shapes)
	# A returning tile may still retain its old initial-load monolithic shape.
	# No active body uses this spec here; keep only the replacement shape set.
	spec.erase("shape")
	spec.prepared_body=_body
	_ready_spec=spec
	# Ownership transfers to the stream spec; _make_body activates and consumes it.
	_body=null;_spec={};_mesh=null;_faces=PackedVector3Array();_shapes=[];_cursor=0
	_measure("finalize_release",measured)
	return true

static func _extract(surfaces:Array)->PackedVector3Array:
	var snapshot:=Cpu.new();snapshot.surfaces=surfaces
	return snapshot.collision_faces()
