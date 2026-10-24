extends Node
## Extract immutable collision triangles away from the gameplay thread. The stream
## cursor waits outside the player's near region until the exact shape is ready;
## never replace arches, doorways or stairs with a solid bounding box.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const CollisionProducts=preload("res://scripts/world3d/collision_product_cache.gd")
const WorkerRetirement=preload("res://scripts/world3d/cpu_worker_retirement.gd")
const Bvh=preload("res://scripts/world3d/collision_bvh_preparation.gd")
var collision_product_hits:=0
var _thread:Thread
var _retirement:Dictionary={}
var _retiring_workers:=false
var _retired_leases:Array=[]
var _mesh:Mesh
var _terrain=preload("res://scripts/world3d/terrain_collision_preparer.gd").new()
var _face_prefetch=preload("res://scripts/world3d/collision_face_prefetch.gd").new()
static var prefetch_enabled:=true # Covered entry and measured white runtime; probe A/B override.
static var terrain_slicing_enabled:=true # Diagnostic A/B override for large static collision slices.
static var prepared_faces_enabled:=true # Diagnostic A/B; consume only completed immutable CPU faces.
static var small_worker_bvh_enabled:=true
var bvh_worker_shapes:=0
var bvh_main_shapes:=0
var bvh_worker_face_vertices:=0
var bvh_main_face_vertices:=0
var prepared_face_hits:=0
var face_worker_starts:=0
var profile_enabled:=false
var profile_serial:=0
var last_profile:Dictionary={}
var _profile_stages:Dictionary={}
var _profile_path:=""

func _measure(stage:String,started:int)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer._measure") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if profile_enabled:_profile_stages[stage]=(Time.get_ticks_usec()-started)/1000.

func _enter_tree()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer._enter_tree") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_retiring_workers=false;_terrain.resume_workers()

func _ready()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer._ready") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	name="StreamCollisionPreparer"
	set_meta("stream_instance",true)

func prepare(spec:Dictionary,host:Node=null,work_budget_usec:int=1500)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer.prepare") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
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
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer._prepare") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
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
		var shape:=_install_shape(faces,packet.get("prepared",{}))
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
	var worker_bvh:bool=small_worker_bvh_enabled and Bvh.active()
	if prefetch_enabled and _face_prefetch.pending(mesh,cpu,Basis.IDENTITY):return false
	var prefetched:PackedVector3Array=_face_prefetch.take(mesh,cpu,Basis.IDENTITY) if prefetch_enabled else PackedVector3Array()
	if not prefetched.is_empty():
		if profile_enabled:_profile_path="prefetched_faces"
		measured=Time.get_ticks_usec() if profile_enabled else 0
		var products:Array=_face_prefetch.take_prepared(mesh,cpu,Basis.IDENTITY)
		var shape:=_install_shape(prefetched,products[0] if products.size()==1 else {})
		_measure("shape_set_faces_ms",measured)
		mesh.set_meta("runtime_concave_shape",shape);spec.shape=shape
		prefetched=PackedVector3Array();_face_prefetch.release(mesh,cpu,Basis.IDENTITY)
		return true
	if prepared_faces_enabled and not cpu._collision_faces.is_empty():
		# A small cached shape without lookahead costs less than adding a serial
		# task/frame barrier. Consume batched BVHs above; otherwise keep entry's
		# immediate bounded fallback. Empty faces still use their existing worker.
		prepared_face_hits+=1
		if profile_enabled:_profile_path="prepared_faces"
		measured=Time.get_ticks_usec() if profile_enabled else 0
		var shape:=_install_shape(cpu._collision_faces)
		_measure("shape_set_faces_ms",measured)
		mesh.set_meta("runtime_concave_shape",shape);spec.shape=shape
		return true
	var surfaces:Array=WorkerRetirement.snapshot_surfaces(cpu.surfaces)
	if profile_enabled:_profile_path="worker_start"
	measured=Time.get_ticks_usec() if profile_enabled else 0
	_thread=Thread.new();_mesh=mesh
	var tree:SceneTree=get_tree() if is_inside_tree() else (host.get_tree() if host!=null and host.is_inside_tree() else null)
	_retirement=WorkerRetirement.watch(_thread,tree,[mesh,cpu,surfaces])
	var completed:PackedVector3Array=cpu._collision_faces if prepared_faces_enabled else PackedVector3Array()
	if not completed.is_empty():prepared_face_hits+=1
	var error:=_thread.start(_worker_faces.bind(surfaces,completed,worker_bvh)) if not _retirement.is_empty() else ERR_UNCONFIGURED
	if error==OK:face_worker_starts+=1
	_measure("worker_start_ms",measured)
	if error!=OK:
		WorkerRetirement.complete(_retirement)
		_thread=null;_mesh=null;return true
	return false

static func _needs_slices(spec:Dictionary,source:Mesh)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer._needs_slices") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
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
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer.build_faces") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var snapshot:=Cpu.new();snapshot.surfaces=surfaces
	return snapshot.collision_faces()

func _install_shape(faces:PackedVector3Array,prepared:Dictionary={})->ConcavePolygonShape3D:
	var shape:=ConcavePolygonShape3D.new()
	if not prepared.is_empty() and shape.has_method(&"set_prepared_faces"):
		shape.call(&"set_prepared_faces",prepared);bvh_worker_shapes+=1;bvh_worker_face_vertices+=faces.size()
	else:shape.set_faces(faces);bvh_main_shapes+=1;bvh_main_face_vertices+=faces.size()
	return shape

static func _worker_faces(surfaces:Array,completed:PackedVector3Array=PackedVector3Array(),prepare_bvh:bool=false)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer._worker_faces") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var faces:PackedVector3Array=completed if not completed.is_empty() else build_faces(surfaces)
	# Whole ordinary shapes are not split. The lookahead uses the same pure CPU
	# native preparation in its existing batch worker for shapes <= one slice.
	return {"faces":faces,"prepared":PhysicsServer3D.call(&"prepare_concave_shape_data",faces,false) if prepare_bvh else {}}

func retire_workers(tree:SceneTree=null)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer.retire_workers") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_retiring_workers=true
	_terrain.retire_workers(tree)
	_face_prefetch.cancel()
	WorkerRetirement.abandon(_retirement,_retired_leases)
	_thread=null;_mesh=null

func _exit_tree()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer._exit_tree") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	retire_workers()

func cancel_pending()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer.cancel_pending") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_terrain.cancel()
	_face_prefetch.cancel()

func prefetch_request(spec:Dictionary)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer.prefetch_request") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var source:Mesh=spec.get("collision_mesh",spec.get("mesh"))
	if source==null or source is BoxMesh:return {}
	var cpu:Mesh=source if source is Cpu else (source.get_meta("ground_cpu_cache") if source.has_meta("ground_cpu_cache") else null)
	if cpu==null or cpu.box_size!=Vector3.ZERO:return {}
	if is_instance_valid(spec.get("prepared_body")):return {}
	var basis:=Basis.IDENTITY
	var prepare_bvh:=false
	if terrain_slicing_enabled and _needs_slices(spec,source):
		prepare_bvh=preload("res://scripts/world3d/collision_bvh_preparation.gd").active()
		var variant:Dictionary=preload("res://scripts/world3d/terrain_collision_preparer.gd")._basis_variant(spec)
		basis=variant.basis
		# An extraction already owned by the serial fallback must finish once;
		# lookahead must not launch a duplicate while that cursor is in flight.
		if _terrain._mesh==source and not _terrain._spec.is_empty() and _terrain._bake_basis==basis:return {}
		if variant.key.is_empty():
			if source.has_meta("runtime_terrain_shapes"):return {}
			if not prepare_bvh and _terrain.prepared_faces_enabled and not cpu._collision_faces.is_empty():return {}
		elif source.get_meta(_terrain.BASIS_CACHE_META,{}).get("entries",{}).has(variant.key):return {}
	else:
		prepare_bvh=small_worker_bvh_enabled and Bvh.active()
		if _mesh==source and _thread!=null:return {}
		if spec.has("shape") or source.has_meta("runtime_concave_shape"):return {}
		if not prepare_bvh and prepared_faces_enabled and not cpu._collision_faces.is_empty():return {}
	return {"source":source,"cpu":cpu,"basis":basis,"prepare_bvh":prepare_bvh}

func release_retired_sources(specs:Array)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_collision_preparer.release_retired_sources") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# A finished extraction may otherwise retain its source until another body
	# is requested. Never join a live worker on a walking frame.
	if _mesh==null and _terrain._mesh==null and _terrain._spec.is_empty() and _terrain._ready_spec.is_empty() and not _face_prefetch.has_source_owners():return true
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
