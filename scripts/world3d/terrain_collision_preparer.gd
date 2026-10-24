extends RefCounted
## Exact triangle slices are cooked and attached with collision disabled. Publish
## the whole static body only after all slices exist, preserving holes and seams.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const WorkerRetirement=preload("res://scripts/world3d/cpu_worker_retirement.gd")
const SLICE_VERTICES:=3072 # A multiple of three: never split a triangle.
const BASIS_VARIANT_LIMIT:=8
const BASIS_CACHE_META:="runtime_terrain_basis_shapes"
static var prepared_faces_enabled:=true # Diagnostic A/B; no main-thread basis conversion.
var prepared_face_hits:=0
var prepared_face_transform_hits:=0
var face_expansions:=0
var face_prefetch:RefCounted
var _face_lease:Dictionary={}
var _thread:Thread
var _retirement:Dictionary={}
var _retiring_workers:=false
var _retired_leases:Array=[]
var _mesh:Mesh
var _spec:Dictionary={}
var _request_pose:=Transform3D.IDENTITY
var _variant_key:=""
var _bake_basis:=Basis.IDENTITY
var _body:StaticBody3D
var _faces:=PackedVector3Array()
var _shapes:Array=[]
var _prepared_shapes:Array=[]
var bvh_worker_slices:=0
var bvh_main_slices:=0
# Existing worker_slices counts accepted prepared products. These count actual
# uncached installs, so cancelled preparation and cached shape reuse differ.
var bvh_worker_installed_slices:=0
var bvh_main_installed_slices:=0
var bvh_worker_face_vertices:=0
var bvh_main_face_vertices:=0
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
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer._measure") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if profile_enabled:_profile[stage]=float(_profile.get(stage,0.))+(Time.get_ticks_usec()-started)/1000.

func _release_face_lease()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer._release_face_lease") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if _face_lease.is_empty():return
	_face_lease.owner.release(_face_lease.source,_face_lease.cpu,_face_lease.basis)
	_face_lease.clear()

func cancel(defer_free:bool=false)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer.cancel") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var pending=_ready_spec.get("prepared_body")
	if is_instance_valid(pending):
		if defer_free:pending.queue_free()
		else:pending.free()
	_ready_spec.erase("prepared_body");_ready_spec={}
	if is_instance_valid(_body):
		if defer_free:_body.queue_free()
		else:_body.free()
	_body=null;_spec={};_faces=PackedVector3Array();_shapes=[];_prepared_shapes=[];_cursor=0
	_release_face_lease()
	_request_pose=Transform3D.IDENTITY;_variant_key="";_bake_basis=Basis.IDENTITY
	# A CPU-only worker can finish without blocking this frame. Its result is
	# discarded or joined on the next request/scene exit.
	if _thread==null:_mesh=null

func retire_workers(_tree:SceneTree=null)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer.retire_workers") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# On tree exit the host may be removing its children, including these sibling
	# bodies. Do not synchronously remove another child while that parent is busy.
	# Bodies remain disabled; the host or the deletion queue releases them once.
	cancel(true)
	_retiring_workers=true
	WorkerRetirement.abandon(_retirement,_retired_leases)
	_thread=null;_mesh=null

func finish()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer.finish") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	retire_workers()

func resume_workers()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer.resume_workers") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_retiring_workers=false

func prepare(spec:Dictionary,host:Node,work_budget_usec:int=1500)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer.prepare") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if _retiring_workers or WorkerRetirement.pending(_retired_leases)>0:return false
	if not profile_enabled:return _prepare(spec,host,work_budget_usec)
	_profile={};_profile_details={}
	var cursor_before:=_cursor
	var started:=Time.get_ticks_usec();var result:=_prepare(spec,host,work_budget_usec)
	last_profile={"ms":(Time.get_ticks_usec()-started)/1000.,"ready":result,"cursor":_cursor,"cursor_before":cursor_before,"stages":_profile,"details":_profile_details}
	if profile_collect_rows:profile_rows.append(last_profile)
	return result

func _prepare(spec:Dictionary,host:Node,work_budget_usec:int=1500)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer._prepare") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var measured:=Time.get_ticks_usec() if profile_enabled else 0
	var mesh:Mesh=spec.get("collision_mesh",spec.get("mesh"))
	var pose:Transform3D=_source_pose(spec)
	var variant:=_basis_variant(spec)
	var ready=spec.get("prepared_body")
	if is_instance_valid(ready):
		if not ready.has_meta("collision_source_transform") or (ready.get_meta("collision_source_transform")==pose and ready.get_meta("collision_source_mesh_id",0)==mesh.get_instance_id() and ready.get_meta("collision_basis_key","")==variant.key):return true
		# An unpublished result is owned by this spec; changing its pose/source
		# must not publish stale geometry or relabel a completed cache variant.
		ready.free();spec.erase("prepared_body")
	if not _spec.is_empty() and (not is_same(_spec,spec) or _mesh!=mesh or _request_pose!=pose or _variant_key!=variant.key):cancel()
	_measure("cancel",measured)
	if _thread!=null:
		if _thread.is_alive():return false
		measured=Time.get_ticks_usec() if profile_enabled else 0
		var packet:Dictionary=_thread.wait_to_finish();_thread=null
		var result:PackedVector3Array=packet.get("faces",PackedVector3Array())
		if not _spec.is_empty() and _mesh==mesh and _request_pose==pose and _variant_key==variant.key:
			_faces=result;_prepared_shapes=packet.get("prepared_shapes",[]);bvh_worker_slices+=_prepared_shapes.size()
		else:_mesh=null
		WorkerRetirement.complete(_retirement)
		_measure("worker_handoff",measured)
	if _spec.is_empty():
		var pending_cpu:Mesh=mesh if mesh is Cpu else (mesh.get_meta("ground_cpu_cache") if mesh.has_meta("ground_cpu_cache") else null)
		if face_prefetch!=null and pending_cpu!=null and face_prefetch.pending(mesh,pending_cpu,variant.basis):return false
		measured=Time.get_ticks_usec() if profile_enabled else 0
		_spec=spec;_mesh=mesh;_cursor=0;_request_pose=pose
		_variant_key=variant.key;_bake_basis=variant.basis
		if _variant_key.is_empty():
			_cached=mesh.has_meta("runtime_terrain_shapes")
			_shapes=mesh.get_meta("runtime_terrain_shapes",[]).duplicate()
		else:
			var cached:Dictionary=_cached_variant(mesh,_variant_key)
			_cached=not cached.is_empty();_shapes=cached.get("shapes",[]).duplicate()
		_measure("cached_shapes",measured)
		if not _cached:
			var cpu:Mesh=mesh if mesh is Cpu else (mesh.get_meta("ground_cpu_cache") if mesh.has_meta("ground_cpu_cache") else null)
			if cpu==null:_spec={};_mesh=null;return true
			var prefetched:PackedVector3Array=face_prefetch.take(mesh,cpu,_bake_basis) if face_prefetch!=null else PackedVector3Array()
			if not prefetched.is_empty():
				_faces=prefetched
				_prepared_shapes=face_prefetch.take_prepared(mesh,cpu,_bake_basis);bvh_worker_slices+=_prepared_shapes.size()
				_face_lease={"owner":face_prefetch,"source":mesh,"cpu":cpu,"basis":_bake_basis}
			elif prepared_faces_enabled and _bake_basis==Basis.IDENTITY and not cpu._collision_faces.is_empty():
				prepared_face_hits+=1
				# Borrow completed local-space faces without modifying the shared
				# buffer. Slices below copy only their own triangles.
				_faces=cpu._collision_faces
			else:
				# A completed local-space soup belongs to this exact CPU capture.
				# Borrow its immutable snapshot; the existing single worker makes
				# an explicit private duplicate before changing any packed element.
				# Keep the same output/workspace lifetime and shape slice budget.
				var completed:PackedVector3Array=cpu._collision_faces if prepared_faces_enabled else PackedVector3Array()
				var surfaces:Array=[] if not completed.is_empty() else WorkerRetirement.snapshot_surfaces(cpu.surfaces)
				if not completed.is_empty():prepared_face_hits+=1;prepared_face_transform_hits+=1
				else:face_expansions+=1
				var bake_basis:=_bake_basis # Value snapshot; never read changing task state on a worker.
				_thread=Thread.new()
				_retirement=WorkerRetirement.watch(_thread,host.get_tree() if host.is_inside_tree() else null,[mesh,cpu,surfaces,completed])
				if not _retirement.is_empty() and _thread.start(_worker_extract.bind(surfaces,bake_basis,completed))==OK:return false
				WorkerRetirement.complete(_retirement)
				_thread=null;_faces=_extract(surfaces,bake_basis,completed)
	if not _cached and _prepared_shapes.is_empty() and not _faces.is_empty() and preload("res://scripts/world3d/collision_bvh_preparation.gd").active():
		_thread=Thread.new()
		_retirement=WorkerRetirement.watch(_thread,host.get_tree() if host.is_inside_tree() else null,[mesh,_faces])
		if not _retirement.is_empty() and _thread.start(preload("res://scripts/world3d/collision_bvh_preparation.gd").packet.bind(_faces))==OK:return false
		WorkerRetirement.complete(_retirement);_thread=null
	if _body==null:
		measured=Time.get_ticks_usec() if profile_enabled else 0
		_body=load("res://scripts/world3d/world_stream.gd")._body_shell(spec)
		_body.collision_layer=0;_body.collision_mask=0
		host.add_child(_body)
		_body.global_transform=Transform3D(Basis.IDENTITY,_request_pose.origin) if not _variant_key.is_empty() else _request_pose
		_body.set_meta("collision_basis_baked",not _variant_key.is_empty())
		_body.set_meta("collision_source_transform",_request_pose)
		_body.set_meta("collision_source_mesh_id",mesh.get_instance_id())
		_body.set_meta("collision_basis_key",_variant_key)
		_measure("body_shell",measured)
	var started:=Time.get_ticks_usec()
	var count:=_shapes.size() if _cached else ceili(float(_faces.size())/SLICE_VERTICES)
	if profile_enabled:_profile_details={"cached":_cached,"basis_baked":not _variant_key.is_empty(),"slice_count":count,"first_slice":_cursor,"faces_vertices":_faces.size(),"set_faces_intervals":[]}
	while _cursor<count:
		var shape:ConcavePolygonShape3D
		if _cached:shape=_shapes[_cursor]
		else:
			measured=Time.get_ticks_usec() if profile_enabled else 0
			shape=ConcavePolygonShape3D.new()
			var offset:=_cursor*SLICE_VERTICES
			var faces:PackedVector3Array=_prepared_shapes[_cursor].faces if not _prepared_shapes.is_empty() else _faces.slice(offset,mini(offset+SLICE_VERTICES,_faces.size()))
			_measure("slice_copy",measured)
			measured=Time.get_ticks_usec() if profile_enabled else 0
			if not _prepared_shapes.is_empty():
				shape.call(&"set_prepared_faces",_prepared_shapes[_cursor]);bvh_worker_installed_slices+=1;bvh_worker_face_vertices+=faces.size()
			else:
				shape.set_faces(faces);bvh_main_slices+=1;bvh_main_installed_slices+=1;bvh_main_face_vertices+=faces.size()
			_measure("shape_set_faces",measured)
			if profile_enabled:_profile_details.set_faces_intervals.append({"slice":_cursor,"vertices":faces.size(),"begin_usec":measured,"end_usec":Time.get_ticks_usec()})
			_shapes.append(shape)
		measured=Time.get_ticks_usec() if profile_enabled else 0
		var child:=CollisionShape3D.new();child.shape=shape;_body.add_child(child)
		_measure("shape_attach",measured)
		_cursor+=1
		if Time.get_ticks_usec()-started>=clampi(work_budget_usec,1,24000):break
	if profile_enabled:_profile_details["end_slice"]=_cursor
	if _cursor<count:return false
	measured=Time.get_ticks_usec() if profile_enabled else 0
	if not _cached:
		if _variant_key.is_empty():_store_shapes(mesh,_shapes)
		else:_store_variant(mesh,_variant_key,_shapes)
	# A returning tile may still retain its old initial-load monolithic shape.
	# No active body uses this spec here; keep only the replacement shape set.
	spec.erase("shape")
	spec.prepared_body=_body
	_ready_spec=spec
	# Ownership transfers to the stream spec; _make_body activates and consumes it.
	_body=null;_spec={};_mesh=null;_faces=PackedVector3Array();_shapes=[];_prepared_shapes=[];_cursor=0
	_release_face_lease()
	_request_pose=Transform3D.IDENTITY;_variant_key="";_bake_basis=Basis.IDENTITY
	_measure("finalize_release",measured)
	return true

static func _worker_extract(surfaces:Array,bake_basis:Basis,completed:PackedVector3Array=PackedVector3Array())->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer._worker_extract") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	return preload("res://scripts/world3d/collision_bvh_preparation.gd").packet(_extract(surfaces,bake_basis,completed))

static func _extract(surfaces:Array,bake_basis:Basis=Basis.IDENTITY,completed:PackedVector3Array=PackedVector3Array())->PackedVector3Array:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer._extract") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var faces:=completed
	if faces.is_empty():
		var snapshot:=Cpu.new();snapshot.surfaces=surfaces
		faces=snapshot.collision_faces()
	elif bake_basis!=Basis.IDENTITY:
		# Transform3D's native packed operation allocates the one private output
		# which the old duplicate + scripted loop needed. Do not first duplicate.
		return Transform3D(bake_basis,Vector3.ZERO)*faces
	# Expansion or duplicate supplies a private transformed output. Never bake
	# into shared local faces or include translation twice in the physics body.
	if bake_basis!=Basis.IDENTITY:
		for i in faces.size():faces[i]=bake_basis*faces[i]
	return faces

static func _source_pose(spec:Dictionary)->Transform3D:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer._source_pose") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	return spec.get("transform",Transform3D(Basis.from_euler(spec.get("rotation",Vector3.ZERO)),spec.get("position",Vector3.ZERO)))

static func _basis_key(basis:Basis)->String:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer._basis_key") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Keep all basis components: no angle/scale quantization and no translation.
	return var_to_bytes(basis).hex_encode()

static func _basis_variant(spec:Dictionary)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer._basis_variant") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var fallback:Dictionary={"key":"","basis":Basis.IDENTITY}
	# Fixtures directly animate body transforms; actors/native visuals also
	# retain their own pose owners. Only immutable static collision specs bake.
	for data:Dictionary in [spec,spec.get("extras",{}),spec.get("ground_batch_record",{})]:
		if data.has("fixture") or data.has("closed_transform"):return fallback
		for flag:String in ["native_dynamic","native_visual","dynamic","moving","actor","hostile","ally"]:
			if data.get(flag,false):return fallback
		if data.get("kind","") in ["npc","enemy","actor","character"] or not str(data.get("npc_id","")).is_empty():return fallback
	var pose:=_source_pose(spec);var basis:=pose.basis
	if not pose.is_finite() or basis==Basis.IDENTITY:return fallback
	var determinant:=basis.determinant()
	if not is_finite(determinant) or determinant<=0.:return fallback
	var lengths:=Vector3(basis.x.length(),basis.y.length(),basis.z.length())
	if not lengths.is_finite() or minf(lengths.x,minf(lengths.y,lengths.z))<.00000001:return fallback
	var x:=basis.x/lengths.x;var y:=basis.y/lengths.y;var z:=basis.z/lengths.z
	# Positive upright Y, no pitch/roll, reflection or shear. Small import
	# roundoff is accepted; every original component is still baked exactly.
	if y.y<=0. or absf(x.y)>.000001 or absf(z.y)>.000001 or absf(y.x)>.000001 or absf(y.z)>.000001:return fallback
	if absf(x.dot(y))>.000001 or absf(x.dot(z))>.000001 or absf(y.dot(z))>.000001:return fallback
	return {"key":_basis_key(basis),"basis":basis}

static func _cached_variant(mesh:Mesh,key:String)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer._cached_variant") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# All cache mutation and PhysicsServer resources remain on the main thread.
	var cache:Dictionary=mesh.get_meta(BASIS_CACHE_META,{})
	var entries:Dictionary=cache.get("entries",{})
	if not entries.has(key):return {}
	cache.serial=int(cache.get("serial",0))+1
	var entry:Dictionary=entries[key];entry.stamp=cache.serial
	mesh.set_meta(BASIS_CACHE_META,cache)
	return entry

static func _store_shapes(mesh:Mesh,shapes:Array)->void:
	if mesh is Cpu:mesh.set_terrain_shapes(shapes)
	else:mesh.set_meta("runtime_terrain_shapes",shapes)

static func _store_variant(mesh:Mesh,key:String,shapes:Array)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.terrain_collision_preparer._store_variant") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var cache:Dictionary=mesh.get_meta(BASIS_CACHE_META,{"entries":{},"serial":0})
	var entries:Dictionary=cache.entries
	cache.serial=int(cache.serial)+1
	entries[key]={"shapes":shapes.duplicate(),"stamp":cache.serial}
	while entries.size()>BASIS_VARIANT_LIMIT:
		var oldest:="";var oldest_stamp:=9223372036854775807
		for candidate:String in entries:
			if int(entries[candidate].stamp)<oldest_stamp:oldest=candidate;oldest_stamp=int(entries[candidate].stamp)
		# Remove only cache ownership. Published bodies keep their shape refs.
		entries.erase(oldest)
	if mesh is Cpu:mesh.set_terrain_basis_cache(cache)
	else:mesh.set_meta(BASIS_CACHE_META,cache)
