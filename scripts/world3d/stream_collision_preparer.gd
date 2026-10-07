extends Node
## Extract immutable collision triangles away from the gameplay thread. The stream
## cursor waits outside the player's near region until the exact shape is ready;
## never replace arches, doorways or stairs with a solid bounding box.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var _thread:Thread
var _mesh:Mesh
var _terrain=preload("res://scripts/world3d/terrain_collision_preparer.gd").new()
static var terrain_slicing_enabled:=true # Diagnostic A/B override for large static collision slices.
var profile_enabled:=false
var profile_serial:=0
var last_profile:Dictionary={}
var _profile_stages:Dictionary={}
var _profile_path:=""

func _measure(stage:String,started:int)->void:
	if profile_enabled:_profile_stages[stage]=(Time.get_ticks_usec()-started)/1000.

func _ready()->void:
	name="StreamCollisionPreparer"
	set_meta("stream_instance",true)

func prepare(spec:Dictionary,host:Node=null)->bool:
	_terrain.profile_enabled=profile_enabled
	if not profile_enabled:return _prepare(spec,host)
	_terrain.profile_collect_rows=false
	_profile_stages={};_profile_path=""
	var started:=Time.get_ticks_usec();var ready:=_prepare(spec,host)
	profile_serial+=1
	last_profile={"uuid":str(spec.get("uuid","")),"ms":(Time.get_ticks_usec()-started)/1000.,"frame":Engine.get_process_frames(),"ready":ready,"path":_profile_path,"stages":_profile_stages}
	if _profile_path=="terrain":last_profile["terrain"]=_terrain.last_profile
	return ready

func _prepare(spec:Dictionary,host:Node=null)->bool:
	var measured:=Time.get_ticks_usec() if profile_enabled else 0
	var source:Mesh=spec.get("collision_mesh",spec.get("mesh"))
	var sliced:=terrain_slicing_enabled and host!=null and _needs_slices(spec,source)
	_measure("needs_slices_ms",measured)
	if sliced:
		if profile_enabled:_profile_path="terrain"
		return _terrain.prepare(spec,host)
	if spec.has("shape"):
		if profile_enabled:_profile_path="existing_shape"
		return true
	var mesh:Mesh=spec.get("collision_mesh",spec.get("mesh"))
	if mesh==null or mesh is BoxMesh or (mesh is Cpu and mesh.box_size!=Vector3.ZERO):
		if profile_enabled:_profile_path="primitive"
		return true
	if mesh.has_meta("runtime_concave_shape"):
		if profile_enabled:_profile_path="cached_concave"
		spec.shape=mesh.get_meta("runtime_concave_shape");return true
	if _thread!=null:
		if _thread.is_alive():
			if profile_enabled:_profile_path="worker_pending"
			return false
		if profile_enabled:_profile_path="worker_complete"
		measured=Time.get_ticks_usec() if profile_enabled else 0
		var faces:PackedVector3Array=_thread.wait_to_finish()
		_measure("worker_handoff_ms",measured)
		# Physics runs on the main thread in this project. Workers must not call
		# PhysicsServer (even indirectly through a Shape resource constructor).
		measured=Time.get_ticks_usec() if profile_enabled else 0
		var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces)
		_measure("shape_set_faces_ms",measured)
		measured=Time.get_ticks_usec() if profile_enabled else 0
		_mesh.set_meta("runtime_concave_shape",shape)
		_thread=null;_mesh=null
		_measure("cache_release_ms",measured)
		if mesh.has_meta("runtime_concave_shape"):
			spec.shape=mesh.get_meta("runtime_concave_shape");return true
	# CPU geometry is retained when the stream spec is created. Never read GPU
	# buffers or scene nodes on a worker. Legacy uncaptured meshes use the old path.
	var cpu:Mesh=mesh if mesh is Cpu else (mesh.get_meta("ground_cpu_cache") if mesh.has_meta("ground_cpu_cache") else null)
	if cpu==null:
		if profile_enabled:_profile_path="uncaptured"
		return true
	var surfaces:Array=cpu.surfaces
	if profile_enabled:_profile_path="worker_start"
	measured=Time.get_ticks_usec() if profile_enabled else 0
	_thread=Thread.new();_mesh=mesh
	var error:=_thread.start(func():return build_faces(surfaces))
	_measure("worker_start_ms",measured)
	if error!=OK:
		_thread=null;_mesh=null;return true
	return false

static func _needs_slices(spec:Dictionary,source:Mesh)->bool:
	var cpu:Mesh=source if source is Cpu else (source.get_meta("ground_cpu_cache") if source!=null and source.has_meta("ground_cpu_cache") else null)
	if cpu==null or cpu.box_size!=Vector3.ZERO:return false
	if spec.get("ground_batch_record",{}).has("terrain_mesh"):return true
	# Imported/baked fortifications have no terrain authoring record. Their
	# exact concave bodies can be even larger; count indices without extracting
	# triangles or calling PhysicsServer on this thread's preparation path.
	var count:=0
	for arrays:Array in cpu.surfaces:
		var indices:Variant=arrays[Mesh.ARRAY_INDEX]
		count+=indices.size() if indices!=null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
		if count>preload("res://scripts/world3d/terrain_collision_preparer.gd").SLICE_VERTICES:return true
	return false

static func build_faces(surfaces:Array)->PackedVector3Array:
	var snapshot:=Cpu.new();snapshot.surfaces=surfaces
	return snapshot.collision_faces()

func _exit_tree()->void:
	_terrain.finish()
	if _thread!=null:_thread.wait_to_finish()
	_thread=null;_mesh=null

func cancel_pending()->void:
	_terrain.cancel()
