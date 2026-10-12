extends Node
## Exact, map-owned collision before render publication. This store proves only
## its accepted instances, NOT map dependency closure, support or entry readiness.
## No stream placeholders, source IO, mesh readback, workers or implicit eviction.
const Preparation=preload("res://scripts/world3d/collision_instance_preparation.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const SLICE_VERTICES:=3072
const MAX_RETAINED_BYTES:=128*1024*1024
const MAX_QUEUED_BATCHES:=4
const MAX_ROWS:=16384

class Promotion extends RefCounted:
	var owner:WeakRef
	var generation:=-1
	var instance_ids:Array=[]
	var consumed:=false

var _map:WeakRef
var _path:=""
var _sha:=""
var _epoch:=-1
var _generation:=0
var _terminal:="unconfigured"
var _instances:Dictionary={}
var _members:Dictionary={}
var _owned_bodies:Dictionary={}
var _batches:Array=[]
var _queue:Array=[]
var _retained_bytes:=0
var _shape_count:=0
var _promoted:=0
var _promoted_ids:Dictionary={}
var _step_usec:=0
var _max_step_usec:=0

func _init()->void:
	name="CollisionInstanceResidency"
	set_meta("stream_instance",true)

func _enter_tree()->void:
	if _map==null or not _terminal.is_empty():return
	if get_parent()!=_map.get_ref():cancel("map_owner_changed");return
	# A synchronous preparation-viewport -> live-map reparent preserves owned
	# geometry, but registration in the new World still needs a physics tick.
	var stamp:=Engine.get_physics_frames()
	for instance:Dictionary in _instances.values():
		if not instance.installed:continue
		instance.stamp=stamp
		for row:Dictionary in instance.rows:
			if is_instance_valid(row.body):row.stamp=stamp;row.body.set_meta("stream_physics_published_frame",stamp)
	_generation+=1

func configure(map:Node,path:String,sha:String,epoch:int)->Dictionary:
	if _map!=null:return _failure("already_configured")
	if not map is Node3D or not is_instance_valid(map) or get_parent()!=map or path.is_empty() or not _valid_sha(sha) or epoch<0:return _failure("invalid_context")
	_map=weakref(map);_path=path;_sha=sha;_epoch=epoch;_terminal=""
	var error:=_context_error(epoch)
	if not error.is_empty():_terminal=error;return _failure(error)
	return {"ok":true,"error":""}

func enqueue(batch:Variant,epoch:int)->Dictionary:
	var error:=_context_error(epoch)
	if not error.is_empty():return _failure(error)
	if not batch is Preparation.Batch or batch.map_path()!=_path or batch.map_sha()!=_sha:return _failure("batch_identity")
	var pending_batches:=0
	for existing:Dictionary in _batches:
		if existing.pending>0:pending_batches+=1
	if pending_batches>=MAX_QUEUED_BATCHES:return _failure("queue_capacity")
	var values:Array=batch.instances()
	if values.is_empty() or batch.retained_bytes()<0:return _failure("empty_batch")
	var fresh:Dictionary={};var member_ids:Dictionary={};var shape_bytes:=0;var row_count:=_members.size()
	var map:Node=_map.get_ref();var known:Dictionary=map.get_meta("stream_by_id",{});var live:Dictionary=map.get_meta("stream_bodies",{})
	var append_state:Dictionary=map.get_meta("stream_append_state",{})
	for instance:Variant in values:
		if not instance is Dictionary or not instance.get("uuid") is String or instance.uuid.is_empty() or instance.uuid.contains("__") or not instance.get("rows") is Array or instance.rows.is_empty():return _failure("invalid_instance")
		if _instances.has(instance.uuid) or fresh.has(instance.uuid):return _failure("duplicate_instance")
		if append_state.get("namespaces",{}).has(instance.uuid) or append_state.get("prefixes",{}).has(instance.uuid):return _failure("existing_namespace")
		var rows:Array=[];var bytes:=0
		for row:Variant in instance.rows:
			if not _valid_row(row,instance.uuid):return _failure("invalid_row")
			if member_ids.has(row.uuid) or _members.has(row.uuid) or known.has(row.uuid) or live.has(row.uuid):return _failure("duplicate_member")
			member_ids[row.uuid]=instance.uuid;row_count+=1
			if row_count>MAX_ROWS:return _failure("row_capacity")
			# Includes source payload separately and conservatively reserves native
			# triangle/BVH copies. This is admission accounting, not measured RSS.
			var reserved:int=(row.faces.size()*(24 if OS.has_feature("double") else 12)*4+1024) if row.collision!="none" else 0
			bytes+=reserved
			rows.append({"source":row,"body":null,"shapes":[],"cursor":0,"complete":row.collision=="none","bounds":row.transform*row.bounds})
		shape_bytes+=bytes
		fresh[instance.uuid]={"source":instance,"rows":rows,"row_cursor":0,"installed":false,"stamp":-1,"shape_bytes":bytes,"batch":null,"error":""}
	var charge:int=batch.retained_bytes()+shape_bytes
	if charge>MAX_RETAINED_BYTES-_retained_bytes:return _failure("memory_capacity")
	var owner:Dictionary={"batch":batch,"bytes":batch.retained_bytes(),"remaining":fresh.size(),"pending":fresh.size()}
	_batches.append(owner)
	for id:String in fresh:
		fresh[id].batch=owner;_instances[id]=fresh[id];_queue.append(id)
	for id:String in member_ids:_members[id]=member_ids[id]
	_retained_bytes+=charge;_generation+=1
	return {"ok":true,"error":"","instances":fresh.size(),"reserved_bytes":charge}

func step(budget_usec:int=1500)->Dictionary:
	var error:=_context_error(_epoch)
	if not error.is_empty():return _failure(error)
	if budget_usec<=0:return {"ok":true,"error":"","units":0,"pending":_queue.size()}
	var began:=Time.get_ticks_usec();var units:=0
	while not _queue.is_empty():
		var id:String=_queue[0];var instance:Dictionary=_instances[id]
		if not instance.error.is_empty():return _failure(instance.error)
		# One bounded shape or one whole-instance activation always progresses
		# when granted positive time, even for a slice below clock resolution.
		_advance(instance);units+=1
		if not instance.error.is_empty():return _failure(instance.error)
		if instance.installed:_queue.pop_front()
		if Time.get_ticks_usec()-began>=budget_usec:break
	_step_usec=Time.get_ticks_usec()-began;_max_step_usec=maxi(_max_step_usec,_step_usec)
	return {"ok":true,"error":"","units":units,"pending":_queue.size(),"elapsed_usec":_step_usec}

func _advance(instance:Dictionary)->void:
	while instance.row_cursor<instance.rows.size() and instance.rows[instance.row_cursor].complete:instance.row_cursor+=1
	if instance.row_cursor==instance.rows.size():
		for row:Dictionary in instance.rows:
			if row.source.collision!="none" and (not is_instance_valid(row.body) or row.body.is_queued_for_deletion() or row.body.get_child_count()!=row.shapes.size()):
				instance.error="collision_invalidated";return
			for value:Dictionary in row.shapes:
				var child:Variant=value.node
				if not is_instance_valid(child) or child.is_queued_for_deletion() or child.disabled or child.shape!=value.shape or child.has_meta("collision_source_mutated"):
					instance.error="collision_invalidated";return
		var stamp:=Engine.get_physics_frames()
		# All members become solid in the same non-yielding publication section.
		for row:Dictionary in instance.rows:
			var body:StaticBody3D=row.body
			if body==null:continue
			body.collision_layer=1;body.collision_mask=1;body.set_meta("stream_physics_published_frame",stamp);row.stamp=stamp
		instance.installed=true;instance.stamp=stamp;instance.batch.pending-=1;_generation+=1
		return
	var row:Dictionary=instance.rows[instance.row_cursor];var source:Dictionary=row.source
	if row.body==null:
		var body:=StaticBody3D.new();body.name=str(source.uuid)+"_body"
		body.collision_layer=0;body.collision_mask=0;body.set_meta("stream_instance",true)
		body.set_meta("uuid",source.uuid);body.set_meta("surface_id","ground");body.set_meta("kind","box")
		body.set_meta("center",source.transform.origin);body.set_meta("target_path","");body.set_meta("spawn",[0,0.9,4])
		for key:String in ["npc_id","node_id","line"]:body.set_meta(key,"")
		_map.get_ref().add_child(body)
		# Bake the exact source basis into bounded triangle slices. Physics body
		# scaling must not approximate nonuniform GLB transforms or reflected faces.
		body.global_transform=Transform3D(Basis.IDENTITY,source.transform.origin) if source.kind=="faces" else _box_pose(source.transform)
		row.body=body;row.expected_pose=body.global_transform;_owned_bodies[source.uuid]=body
	var child:=CollisionShape3D.new()
	if source.kind=="faces":
		var end:=mini(row.cursor+SLICE_VERTICES,source.faces.size())
		var faces:PackedVector3Array=source.faces.slice(row.cursor,end)
		if source.transform.basis!=Basis.IDENTITY:
			for i in faces.size():faces[i]=source.transform.basis*faces[i]
		var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces);child.shape=shape
		row.cursor=end;row.complete=end==source.faces.size()
	else:
		var shape:=BoxShape3D.new();shape.size=source.box*_basis_lengths(source.transform.basis);child.shape=shape;row.complete=true
	row.body.add_child(child);row.shapes.append({"node":child,"shape":child.shape});_shape_count+=1
	child.shape.changed.connect(_shape_changed.bind(weakref(child)),CONNECT_ONE_SHOT)

func readiness(clip:AABB,epoch:int)->Dictionary:
	var result:Dictionary={"ok":false,"reason":"","scope":"accepted_instances_only","map_closure":false,"instances":0,"physics_published_frame":-1}
	result.reason=_context_error(epoch)
	if not result.reason.is_empty():return result
	if not clip.position.is_finite() or not clip.size.is_finite() or clip.size.x<0 or clip.size.y<0 or clip.size.z<0:result.reason="invalid_clip";return result
	var area:=Rect2(clip.position.x,clip.position.z,clip.size.x,clip.size.z)
	for instance:Dictionary in _instances.values():
		var intersects:=false
		for row:Dictionary in instance.rows:
			var bounds:AABB=row.bounds
			if row.source.collision!="none" and area.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z),true):intersects=true;break
		if not intersects:continue
		result.instances+=1
		if not instance.error.is_empty():result.reason=instance.error;return result
		if not instance.installed:result.reason="collision_pending";return result
		# Check the whole accepted instance, including disabled/removed shapes;
		# no cached boolean may survive a body mutation or lost physics owner.
		for row:Dictionary in instance.rows:
			if not _row_live(row):result.reason="collision_invalidated";return result
		result.physics_published_frame=maxi(result.physics_published_frame,instance.stamp)
	result.ok=Engine.get_physics_frames()>int(result.physics_published_frame)
	result.reason="" if result.ok else "physics_sync_pending"
	return result

func instance_readiness(uuid:String,epoch:int)->Dictionary:
	# Unlike the spatial helper, absence is never success. The dependency
	# coordinator must prove each selected author record, including pure visuals.
	var result:Dictionary={"ok":false,"reason":_context_error(epoch),"state":"failed","physics_published_frame":-1}
	if not result.reason.is_empty():return result
	if not _instances.has(uuid):
		result.state="promoted" if _promoted_ids.has(uuid) else "not_accepted"
		result.reason=result.state
		# Promotion relinquished ownership: the ordinary Stream now supplies the
		# live body/stamp proof. A historical success cannot authorize movement.
		return result
	var instance:Dictionary=_instances[uuid]
	var publication:=publication_status(uuid)
	if not publication.error.is_empty():result.reason=publication.error;return result
	if publication.pending:result.state="installing";result.reason="collision_pending";return result
	result.physics_published_frame=instance.stamp
	result.ok=Engine.get_physics_frames()>int(instance.stamp)
	result.state="ready" if result.ok else "physics_sync_pending"
	result.reason="" if result.ok else result.state
	return result

func publication_status(uuid:String)->Dictionary:
	# Renderer coordination does not await another physics tick: promotion keeps
	# the original watermark, which movement checks through the new owner.
	var result:Dictionary={"owned":_instances.has(uuid),"pending":false,"error":""}
	if not result.owned:return result
	result.error=_context_error(_epoch)
	if not result.error.is_empty():return result
	var instance:Dictionary=_instances[uuid]
	result.error=instance.error
	if not result.error.is_empty():return result
	if not instance.installed:result.pending=true;return result
	for row:Dictionary in instance.rows:
		if not _row_live(row):result.error="collision_invalidated";return result
	return result

func preflight_promotion(additions:Array)->Dictionary:
	var error:=_context_error(_epoch)
	if not error.is_empty():return _failure(error)
	var provided:Dictionary={};var selected:Dictionary={}
	for spec:Variant in additions:
		if not spec is Dictionary or not spec.get("uuid") is String:return _failure("invalid_spec")
		var id:String=spec.uuid
		if provided.has(id):return _failure("duplicate_spec")
		provided[id]=spec
		var prefix:=id.get_slice("__",0)
		if _instances.has(prefix):selected[prefix]=true
	var bodies:Dictionary=_map.get_ref().get_meta("stream_bodies",{})
	for id:String in selected:
		var instance:Dictionary=_instances[id]
		if not instance.installed:return _failure("promotion_collision_pending")
		for row:Dictionary in instance.rows:
			var source:Dictionary=row.source
			if not provided.has(source.uuid):return _failure("promotion_incomplete_namespace")
			var spec:Dictionary=provided[source.uuid]
			if not _row_live(row) or bodies.has(source.uuid):return _failure("promotion_body_conflict")
			if spec.get("transform")!=source.transform:return _failure("promotion_pose")
			var extras:Variant=spec.get("extras",{})
			if not extras is Dictionary or str(extras.get("rmmo_collision",""))!=source.collision:return _failure("promotion_mode")
			# Adapter only admits plain static nodes. Refuse newly introduced actor,
			# fixture or other behavior before assigning their body to ordinary Stream.
			for key:Variant in extras:
				if key not in ["uuid","rmmo_collision"]:return _failure("promotion_semantics")
			if spec.get("native_visual",false) or spec.get("native_dynamic",false):return _failure("promotion_semantics")
			# Pure visual rows own no collision and the normal render importer
			# deliberately does not expand their triangles. Index still validates
			# the real Mesh; namespace, pose, mode and semantics must match here.
			if source.collision!="none" and not _geometry_matches(spec,source):return _failure("promotion_geometry_unprepared_or_changed")
		for uuid:String in provided:
			if uuid.get_slice("__",0)==id and _members.get(uuid,"")!=id:return _failure("promotion_extra_member")
	var token:=Promotion.new();token.owner=weakref(self);token.generation=_generation;token.instance_ids=selected.keys()
	return {"ok":true,"error":"","token":token,"instances":selected.size()}

func commit_promotion(token:Promotion)->void:
	# Stream calls synchronously after successful Index.append. No awaits, new
	# geometry, source IO, detach/reparent or fallible validation belongs here.
	assert(token!=null and token.owner.get_ref()==self and token.generation==_generation and not token.consumed,"stale collision promotion transaction")
	var map:Node=_map.get_ref();var bodies:Dictionary=map.get_meta("stream_bodies",{})
	for id:String in token.instance_ids:
		var instance:Dictionary=_instances[id]
		for row:Dictionary in instance.rows:
			var uuid:String=row.source.uuid
			if row.body!=null:
				bodies[uuid]=row.body;_owned_bodies.erase(uuid)
			_members.erase(uuid)
		_retained_bytes-=instance.shape_bytes
		var owner:Dictionary=instance.batch;owner.remaining-=1
		if owner.remaining==0:
			_retained_bytes-=owner.bytes
			for at in _batches.size():
				if is_same(_batches[at],owner):_batches.remove_at(at);break
		_instances.erase(id);_promoted+=1;_promoted_ids[id]=true
	map.set_meta("stream_bodies",bodies);token.consumed=true;_generation+=1

func body_for(uuid:String)->StaticBody3D:
	var body:Variant=_owned_bodies.get(uuid)
	return body if is_instance_valid(body) and not body.is_queued_for_deletion() else null

func has_instances()->bool:return not _instances.is_empty()

func discard_instances(ids:Array)->Dictionary:
	# Explicit last-ticket withdrawal only, never automatic memory eviction.
	# The caller owns entry/player/camera/building leases and must retain every
	# still-required instance. Transferred bodies belong exclusively to Stream.
	var unique:Dictionary={}
	for value:Variant in ids:
		if not value is String or value.is_empty():return _failure("invalid_instance_id")
		unique[value]=true
	var removed:=0
	for id:String in unique:
		if not _instances.has(id):continue
		var instance:Dictionary=_instances[id]
		for row:Dictionary in instance.rows:
			var uuid:String=row.source.uuid;var body:Variant=_owned_bodies.get(uuid)
			_owned_bodies.erase(uuid);_members.erase(uuid)
			if is_instance_valid(body):body.collision_layer=0;body.collision_mask=0;body.queue_free()
		_queue.erase(id);_retained_bytes-=instance.shape_bytes
		var owner:Dictionary=instance.batch
		if not instance.installed:owner.pending-=1
		owner.remaining-=1
		if owner.remaining==0:
			_retained_bytes-=owner.bytes
			for at in _batches.size():
				if is_same(_batches[at],owner):_batches.remove_at(at);break
		_instances.erase(id);removed+=1
	if removed>0:_generation+=1
	return {"ok":true,"error":"","removed":removed}

func debug_snapshot()->Dictionary:
	var installed:=0
	for instance:Dictionary in _instances.values():
		if instance.installed:installed+=1
	return {"epoch":_epoch,"terminal":_terminal,"instances":_instances.size(),"installed":installed,"pending":_queue.size(),"owned_bodies":_owned_bodies.size(),"reserved_bytes":_retained_bytes,"shape_count":_shape_count,"promoted":_promoted,"last_step_usec":_step_usec,"max_step_usec":_max_step_usec}

func cancel(reason:String="cancelled")->void:
	_terminal=reason if not reason.is_empty() else "cancelled";_generation+=1
	# Explicit ownership, not parentage: promoted bodies are never in this bag.
	# Deferred deletion is safe during map tree teardown and never joins workers.
	for body:Variant in _owned_bodies.values():
		if is_instance_valid(body):body.collision_layer=0;body.collision_mask=0;body.queue_free()
	_owned_bodies.clear();_instances.clear();_members.clear();_queue.clear();_batches.clear();_promoted_ids.clear();_retained_bytes=0

func dispose()->void:cancel("disposed")
func _exit_tree()->void:call_deferred("_dispose_if_detached")
func _dispose_if_detached()->void:
	if not is_inside_tree():dispose()
func _notification(what:int)->void:
	if what==NOTIFICATION_PREDELETE:dispose()

func _context_error(epoch:int)->String:
	if not _terminal.is_empty():return _terminal
	if epoch!=_epoch:return "epoch_mismatch"
	var map:Variant=_map.get_ref() if _map!=null else null
	if not is_instance_valid(map) or not map.is_inside_tree() or map.is_queued_for_deletion():return "map_unavailable"
	if get_parent()!=map:return "map_owner_changed"
	if map.has_meta("source_map_sha256") and map.get_meta("source_map_sha256")!=_sha:return "map_source_changed"
	return ""

func _row_live(row:Dictionary)->bool:
	if row.source.collision=="none":return row.complete
	var body:Variant=row.body
	if not is_instance_valid(body) or body.is_queued_for_deletion() or not body.is_inside_tree() or body.collision_layer&1==0 or body.collision_mask&1==0:return false
	if body.get_world_3d()!=_map.get_ref().get_world_3d() or not body.global_transform.is_equal_approx(row.expected_pose) or body.get_meta("stream_physics_published_frame",-1)!=row.get("stamp",-2):return false
	if body.get_child_count()!=row.shapes.size():return false
	for value:Dictionary in row.shapes:
		var child:Variant=value.node
		if not is_instance_valid(child) or child.is_queued_for_deletion() or child.get_parent()!=body or child.disabled or child.shape!=value.shape or child.transform!=Transform3D.IDENTITY or child.has_meta("collision_source_mutated"):return false
	return true

func _shape_changed(reference:WeakRef)->void:
	var child:Variant=reference.get_ref()
	if is_instance_valid(child):child.set_meta("collision_source_mutated",true)

static func _geometry_matches(spec:Dictionary,row:Dictionary)->bool:
	var mesh:Variant=spec.get("collision_mesh",spec.get("mesh"))
	if not mesh is Mesh:return false
	var cpu:Variant=mesh if mesh is Cpu else mesh.get_meta("ground_cpu_cache",null)
	if row.kind=="box":return (mesh is BoxMesh and not mesh.flip_faces and mesh.size==row.box) or (cpu is Cpu and cpu.box_size==row.box)
	# An empty cache is unknown; NEVER fill it by collision_faces()/get_faces().
	return cpu is Cpu and not cpu._collision_faces.is_empty() and cpu._collision_faces==row.faces

static func _valid_row(value:Variant,prefix:String)->bool:
	if not value is Dictionary or not value.get("uuid") is String or not value.uuid.begins_with(prefix+"__") or not value.get("transform") is Transform3D or not value.transform.is_finite() or value.transform.basis.determinant()==0:return false
	if value.get("collision") not in ["","none","walk","block"] or value.get("kind") not in ["faces","box"]:return false
	if not value.get("bounds") is AABB or not value.bounds.position.is_finite() or not value.bounds.size.is_finite() or value.bounds.size.x<0 or value.bounds.size.y<0 or value.bounds.size.z<0:return false
	if not value.get("faces") is PackedVector3Array or not value.get("box") is Vector3:return false
	if value.kind=="faces":return not value.faces.is_empty() and value.faces.size()%3==0 and value.box==Vector3.ZERO
	return value.faces.is_empty() and value.box.is_finite() and value.box.x>0 and value.box.y>0 and value.box.z>0 and _box_basis_supported(value.transform.basis)

static func _basis_lengths(basis:Basis)->Vector3:return Vector3(basis.x.length(),basis.y.length(),basis.z.length())
static func _box_pose(pose:Transform3D)->Transform3D:
	var lengths:=_basis_lengths(pose.basis)
	return Transform3D(Basis(pose.basis.x/lengths.x,pose.basis.y/lengths.y,pose.basis.z/lengths.z),pose.origin)
static func _box_basis_supported(basis:Basis)->bool:
	if basis.determinant()<=0:return false
	var lengths:=_basis_lengths(basis)
	if minf(lengths.x,minf(lengths.y,lengths.z))<0.000001:return false
	var normalized:=_box_pose(Transform3D(basis,Vector3.ZERO)).basis
	return absf(normalized.x.dot(normalized.y))<0.000001 and absf(normalized.x.dot(normalized.z))<0.000001 and absf(normalized.y.dot(normalized.z))<0.000001
static func _valid_sha(value:String)->bool:
	if value.length()!=64:return false
	for ch in value:
		if ch not in "0123456789abcdef":return false
	return true
static func _failure(reason:String)->Dictionary:return {"ok":false,"error":reason}
