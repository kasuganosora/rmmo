extends Node
## Extract immutable collision triangles away from the gameplay thread. The stream
## cursor waits outside the player's near region until the exact shape is ready;
## never replace arches, doorways or stairs with a solid bounding box.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var _thread:Thread
var _mesh:Mesh
var _terrain=preload("res://scripts/world3d/terrain_collision_preparer.gd").new()
static var terrain_slicing_enabled:=true # Diagnostic A/B override; normal play keeps it on.

func _ready()->void:
	name="StreamCollisionPreparer"
	set_meta("stream_instance",true)

func prepare(spec:Dictionary,host:Node=null)->bool:
	var source:Mesh=spec.get("collision_mesh",spec.get("mesh"))
	if terrain_slicing_enabled and host!=null and spec.get("ground_batch_record",{}).has("terrain_mesh") and (source is Cpu or (source!=null and source.has_meta("ground_cpu_cache"))):
		return _terrain.prepare(spec,host)
	if spec.has("shape"):return true
	var mesh:Mesh=spec.get("collision_mesh",spec.get("mesh"))
	if mesh==null or mesh is BoxMesh or (mesh is Cpu and mesh.box_size!=Vector3.ZERO):return true
	if mesh.has_meta("runtime_concave_shape"):
		spec.shape=mesh.get_meta("runtime_concave_shape");return true
	if _thread!=null:
		if _thread.is_alive():return false
		var faces:PackedVector3Array=_thread.wait_to_finish()
		# Physics runs on the main thread in this project. Workers must not call
		# PhysicsServer (even indirectly through a Shape resource constructor).
		var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces)
		_mesh.set_meta("runtime_concave_shape",shape)
		_thread=null;_mesh=null
		if mesh.has_meta("runtime_concave_shape"):
			spec.shape=mesh.get_meta("runtime_concave_shape");return true
	# CPU geometry is retained when the stream spec is created. Never read GPU
	# buffers or scene nodes on a worker. Legacy uncaptured meshes use the old path.
	var cpu:Mesh=mesh if mesh is Cpu else (mesh.get_meta("ground_cpu_cache") if mesh.has_meta("ground_cpu_cache") else null)
	if cpu==null:return true
	var surfaces:Array=cpu.surfaces
	_thread=Thread.new();_mesh=mesh
	if _thread.start(func():return build_faces(surfaces))!=OK:
		_thread=null;_mesh=null;return true
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
