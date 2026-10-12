extends Node
## Extract immutable collision triangles away from the gameplay thread. The stream
## cursor waits outside the player's near region until the exact shape is ready;
## never replace arches, doorways or stairs with a solid bounding box.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const CollisionProducts=preload("res://scripts/world3d/collision_product_cache.gd")
const WorkerRetirement=preload("res://scripts/world3d/cpu_worker_retirement.gd")
var collision_product_hits:=0
var _thread:Thread
var _retirement:Dictionary={}
var _retiring_workers:=false
var _retired_leases:Array=[]
var _mesh:Mesh
var _terrain=preload("res://scripts/world3d/terrain_collision_preparer.gd").new()
var _face_prefetch=preload("res://scripts/world3d/collision_face_prefetch.gd").new()
static var prefetch_enabled:=true # Covered-entry lookahead only; probe A/B override.
static var terrain_slicing_enabled:=true # Diagnostic A/B override for large static collision slices.
static var prepared_faces_enabled:=true # Diagnostic A/B; consume only completed immutable CPU faces.
var prepared_face_hits:=0
var profile_enabled:=false
var profile_serial:=0
var last_profile:Dictionary={}
var _profile_stages:Dictionary={}
var _profile_path:=""

func _measure(stage:String,started:int)->void:
	if profile_enabled:_profile_stages[stage]=(Time.get_ticks_usec()-started)/1000.

func _enter_tree()->void:
	_retiring_workers=false;_terrain.resume_workers()

func _ready()->void:
	name="StreamCollisionPreparer"
	set_meta("stream_instance",true)

func prepare(spec:Dictionary,host:Node=null,work_budget_usec:int=1500)->bool:
	if _retiring_workers or WorkerRetirement.pending(_retired_leases)>0:return false
	_terrain.profile_enabled=profile_enabled
	_terrain.face_prefetch=_face_prefetch if prefetch_enabled else null
	if not profile_enabled:return _prepare(spec,host,work_budget_usec)
	_terrain.profile_collect_rows=false
	_profile_stages={};_profile_path=""
	var started:=Time.get_ticks_usec();var ready:=_prepare(spec,host,work_budget_usec)
	profile_serial+=1
	last_profile={"uuid":str(spec.get("uuid","")),"ms":(Time.get_ticks_usec()-started)/1000.,"frame":Engine.get_process_frames(),"ready":ready,"path":_profile_path,"stages":_profile_stages}
	if _profile_path=="terrain":last_profile["terrain"]=_terrain.last_profile
	return ready

func _prepare(spec:Dictionary,host:Node=null,work_budget_usec:int=1500)->bool:
	var measured:=Time.get_ticks_usec() if profile_enabled else 0
	var source:Mesh=spec.get("collision_mesh",spec.get("mesh"))
	# Private reference workers already completed the final source transaction.
	# Only the typed immutable handoff is accepted here, never a disk candidate
	# or caller's boolean. No IO, hash, geometry expansion, or GPU readback.
	if CollisionProducts.enabled and source is Cpu and source.has_meta("runtime_collision_product") and not spec.get("collision_product_consumed",false):
		var product:Variant=source.get_meta("runtime_collision_product")
		if product is CollisionProducts.Product and product.kind()=="faces":
			source._collision_faces=product.faces();spec.collision_product_consumed=true;collision_product_hits+=1
	var sliced:=terrain_slicing_enabled and host!=null and _needs_slices(spec,source)
	_measure("needs_slices_ms",measured)
	if sliced:
		if profile_enabled:_profile_path="terrain"
		return _terrain.prepare(spec,host,work_budget_usec)
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
		var packet:Dictionary=_thread.wait_to_finish()
		var faces:PackedVector3Array=packet.get("faces",PackedVector3Array())
		_measure("worker_handoff_ms",measured)
		# Physics runs on the main thread in this project. Workers must not call
		# PhysicsServer (even indirectly through a Shape resource constructor).
		measured=Time.get_ticks_usec() if profile_enabled else 0
		var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces)
		_measure("shape_set_faces_ms",measured)
		measured=Time.get_ticks_usec() if profile_enabled else 0
		_mesh.set_meta("runtime_concave_shape",shape)
		WorkerRetirement.complete(_retirement)
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
	# Imported/reference workers finish and validate this local-space buffer
	# before publication. Keep shape construction on the main thread, but avoid
	# expanding the same indices on another worker and waiting an extra frame.
	# An empty cache is unknown: never call collision_faces() here to fill it.
	if prepared_faces_enabled and not cpu._collision_faces.is_empty():
		prepared_face_hits+=1
		if profile_enabled:_profile_path="prepared_faces"
		measured=Time.get_ticks_usec() if profile_enabled else 0
		var shape:=ConcavePolygonShape3D.new();shape.set_faces(cpu._collision_faces)
		_measure("shape_set_faces_ms",measured)
		mesh.set_meta("runtime_concave_shape",shape);spec.shape=shape
		return true
	var prefetched:PackedVector3Array=_face_prefetch.take(mesh,cpu,Basis.IDENTITY) if prefetch_enabled else PackedVector3Array()
	if not prefetched.is_empty():
		if profile_enabled:_profile_path="prefetched_faces"
		measured=Time.get_ticks_usec() if profile_enabled else 0
		var shape:=ConcavePolygonShape3D.new();shape.set_faces(prefetched)
		_measure("shape_set_faces_ms",measured)
		mesh.set_meta("runtime_concave_shape",shape);spec.shape=shape
		prefetched=PackedVector3Array();_face_prefetch.release(mesh,cpu,Basis.IDENTITY)
		return true
	var surfaces:Array=WorkerRetirement.snapshot_surfaces(cpu.surfaces)
	if profile_enabled:_profile_path="worker_start"
	measured=Time.get_ticks_usec() if profile_enabled else 0
	_thread=Thread.new();_mesh=mesh
	var tree:SceneTree=get_tree() if is_inside_tree() else (host.get_tree() if host!=null and host.is_inside_tree() else null)
	_retirement=WorkerRetirement.watch(_thread,tree,[mesh,cpu,surfaces])
	var error:=_thread.start(_worker_faces.bind(surfaces)) if not _retirement.is_empty() else ERR_UNCONFIGURED
	_measure("worker_start_ms",measured)
	if error!=OK:
		WorkerRetirement.complete(_retirement)
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

static func _worker_faces(surfaces:Array)->Dictionary:
	return {"faces":build_faces(surfaces)}

func retire_workers(tree:SceneTree=null)->void:
	_retiring_workers=true
	_terrain.retire_workers(tree)
	_face_prefetch.cancel()
	WorkerRetirement.abandon(_retirement,_retired_leases)
	_thread=null;_mesh=null

func _exit_tree()->void:
	retire_workers()

func cancel_pending()->void:
	_terrain.cancel()
	_face_prefetch.cancel()

func prefetch_request(spec:Dictionary)->Dictionary:
	var source:Mesh=spec.get("collision_mesh",spec.get("mesh"))
	if source==null or source is BoxMesh:return {}
	var cpu:Mesh=source if source is Cpu else (source.get_meta("ground_cpu_cache") if source.has_meta("ground_cpu_cache") else null)
	if cpu==null or cpu.box_size!=Vector3.ZERO:return {}
	if is_instance_valid(spec.get("prepared_body")):return {}
	var basis:=Basis.IDENTITY
	if terrain_slicing_enabled and _needs_slices(spec,source):
		var variant:Dictionary=preload("res://scripts/world3d/terrain_collision_preparer.gd")._basis_variant(spec)
		basis=variant.basis
		if variant.key.is_empty():
			if source.has_meta("runtime_terrain_shapes"):return {}
			if _terrain.prepared_faces_enabled and not cpu._collision_faces.is_empty():return {}
		elif source.get_meta(_terrain.BASIS_CACHE_META,{}).get("entries",{}).has(variant.key):return {}
	else:
		if spec.has("shape") or source.has_meta("runtime_concave_shape"):return {}
		if prepared_faces_enabled and not cpu._collision_faces.is_empty():return {}
	return {"source":source,"cpu":cpu,"basis":basis}

func release_retired_sources(specs:Array)->bool:
	# A finished extraction may otherwise retain its source until another body
	# is requested. Never join a live worker on a walking frame.
	var meshes:Dictionary={};var ids:Dictionary={}
	for spec:Dictionary in specs:
		ids[spec.uuid]=true
		var source:Mesh=spec.get("collision_mesh",spec.get("mesh"))
		if source!=null:meshes[source.get_instance_id()]=true
	var ordinary:bool=_mesh!=null and meshes.has(_mesh.get_instance_id())
	var sliced:bool=ids.has(_terrain._spec.get("uuid","")) or ids.has(_terrain._ready_spec.get("uuid","")) or (_terrain._mesh!=null and meshes.has(_terrain._mesh.get_instance_id()))
	if ordinary and _thread!=null and _thread.is_alive():return false
	if sliced and _terrain._thread!=null and _terrain._thread.is_alive():return false
	if ordinary:
		if _thread!=null:_thread.wait_to_finish()
		WorkerRetirement.complete(_retirement)
		_thread=null;_mesh=null
	if sliced:
		_terrain.cancel()
		if _terrain._thread!=null:_terrain._thread.wait_to_finish()
		WorkerRetirement.complete(_terrain._retirement)
		_terrain._thread=null;_terrain._mesh=null
	# A partial terrain can own a taken face buffer. Release that consumer first;
	# otherwise the prefetch lease would veto retirement forever after its cursor
	# stops being visited. A live extraction above is still never joined here.
	return _face_prefetch.release_sources(meshes)
