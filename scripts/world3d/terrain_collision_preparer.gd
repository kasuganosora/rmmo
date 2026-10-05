extends RefCounted
## Exact triangle slices are cooked and attached with collision disabled. Publish
## the whole terrain body only after all slices exist, preserving holes and seams.
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

func cancel()->void:
	var pending=_ready_spec.get("prepared_body")
	if is_instance_valid(pending):pending.free()
	_ready_spec.erase("prepared_body");_ready_spec={}
	if is_instance_valid(_body):_body.free()
	_body=null;_spec={};_faces=PackedVector3Array();_shapes=[];_cursor=0
	# A CPU-only worker can finish without blocking this frame. Its result is
	# discarded or joined on the next request/scene exit.
	if _thread==null:_mesh=null

func finish()->void:
	cancel()
	if _thread!=null:_thread.wait_to_finish()
	_thread=null;_mesh=null

func prepare(spec:Dictionary,host:Node)->bool:
	var ready=spec.get("prepared_body")
	if is_instance_valid(ready):return true
	var mesh:Mesh=spec.get("collision_mesh",spec.get("mesh"))
	if not _spec.is_empty() and not is_same(_spec,spec):cancel()
	if _thread!=null:
		if _thread.is_alive():return false
		var result:PackedVector3Array=_thread.wait_to_finish();_thread=null
		if not _spec.is_empty() and _mesh==mesh:_faces=result
		else:_mesh=null
	if _spec.is_empty():
		_spec=spec;_mesh=mesh;_cursor=0
		_cached=mesh.has_meta("runtime_terrain_shapes")
		_shapes=mesh.get_meta("runtime_terrain_shapes",[]).duplicate()
		if not _cached:
			var cpu:Mesh=mesh if mesh is Cpu else mesh.get_meta("ground_cpu_cache",null)
			if cpu==null:_spec={};_mesh=null;return true
			var surfaces:Array=cpu.surfaces
			_thread=Thread.new()
			if _thread.start(func():return _extract(surfaces))==OK:return false
			_thread=null;_faces=_extract(surfaces)
	if _body==null:
		_body=load("res://scripts/world3d/world_stream.gd")._body_shell(spec)
		_body.collision_layer=0;_body.collision_mask=0
		host.add_child(_body);_body.global_transform=spec.get("transform",_body.transform)
	var started:=Time.get_ticks_usec()
	var count:=_shapes.size() if _cached else ceili(float(_faces.size())/SLICE_VERTICES)
	while _cursor<count:
		var shape:ConcavePolygonShape3D
		if _cached:shape=_shapes[_cursor]
		else:
			shape=ConcavePolygonShape3D.new()
			var offset:=_cursor*SLICE_VERTICES
			shape.set_faces(_faces.slice(offset,mini(offset+SLICE_VERTICES,_faces.size())))
			_shapes.append(shape)
		var child:=CollisionShape3D.new();child.shape=shape;_body.add_child(child)
		_cursor+=1
		if Time.get_ticks_usec()-started>=1500:break
	if _cursor<count:return false
	if not _cached:mesh.set_meta("runtime_terrain_shapes",_shapes)
	# A returning tile may still retain its old initial-load monolithic shape.
	# No active body uses this spec here; keep only the replacement shape set.
	spec.erase("shape")
	spec.prepared_body=_body
	_ready_spec=spec
	# Ownership transfers to the stream spec; _make_body activates and consumes it.
	_body=null;_spec={};_mesh=null;_faces=PackedVector3Array();_shapes=[];_cursor=0
	return true

static func _extract(surfaces:Array)->PackedVector3Array:
	var snapshot:=Cpu.new();snapshot.surfaces=surfaces
	return snapshot.collision_faces()
