extends Node3D
## Spatial render cache. The source nodes, UUIDs, physics and records remain independent.
const Geometry = preload("res://scripts/world3d/ground_batch_geometry.gd")
const Cpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")
var groups: Dictionary = {}
var pending: Array[String] = []
var enabled := true
var rebuild_count := 0
var last_build_ms := 0.0
var max_build_ms := 0.0
var _material_keys: Dictionary = {}
var _instance_meshes: Dictionary = {}
var _workers: Array = []
const MAX_WORKERS=3
var _generation := 0
var last_commit_ms := 0.0
var max_commit_ms := 0.0
var last_sync_ms := 0.0
var sync_profile: Dictionary={}
var sync_count:=0
var release_groups_visited:=0
var _member_groups: Dictionary={}
var _audit_cursor:=0
var _audit_keys:Array=[]
var _building_meshes:Dictionary={}
var building_mesh_hits:=0
var work_budget_usec:=2000

static func _fingerprint(value:Variant)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value));return hash.finish().hex_encode()

func _ready() -> void:
	name = "GroundRenderBatches"
	set_meta("stream_instance", true)

static func freeze(node: MeshInstance3D, captured: Mesh = null) -> void:
	if node.mesh is Cpu: return
	var cpu: Mesh = captured if captured != null else Cpu.capture(node.mesh)
	var materials: Array[Material]=[]
	for slot in node.mesh.get_surface_count(): materials.append(node.get_active_material(slot))
	# Geometry can be shared, but per-instance paint must not overwrite another
	# source's materials when the original GPU mesh is shared by both objects.
	if cpu.materials!=materials:
		var local:=Cpu.new(); local.surfaces=cpu.surfaces; local.bounds=cpu.bounds; local.box_size=cpu.box_size; local.source_reference=cpu.source_reference; local.materials=materials
		if cpu.has_meta("static_batch_geometry_signature"): local.set_meta("static_batch_geometry_signature",cpu.geometry_key())
		local._collision_faces=cpu._collision_faces; cpu=local
	for slot in node.get_surface_override_material_count(): node.set_surface_override_material(slot,null)
	# Empty the instance's override list before assigning a CPU mesh (no RS base).
	node.mesh = null; node.material_override = null; node.mesh = cpu
	if node.has_meta("paint_source"): node.set_meta("paint_source", Cpu.capture(node.get_meta("paint_source")))

static func restore(node: MeshInstance3D) -> void:
	if node.mesh is Cpu: node.mesh = node.mesh.restore()

func clear(restore_sources: bool = true) -> void:
	for group: Dictionary in groups.values(): _drop(group,restore_sources)
	groups.clear(); pending.clear(); _material_keys.clear(); _instance_meshes.clear(); _member_groups.clear();_building_meshes.clear()
	_audit_keys.clear();_audit_cursor=0

func release(ids: Array) -> void:
	# Editing is synchronous: remove the old combined draw before changing a source.
	var affected: Dictionary={}
	for id in ids:
		if _member_groups.has(str(id)): affected[_member_groups[str(id)]]=true
	for key: String in affected:
		if not groups.has(key): continue
		release_groups_visited+=1
		_drop(groups[key]); groups.erase(key); pending.erase(key)

func _drop(group: Dictionary, restore_sources: bool = true) -> void:
	var watcher=group.get("pose_watcher")
	if is_instance_valid(watcher):
		watcher.changed=Callable();watcher.set_notify_transform(false);watcher.queue_free()
	for id in group.get("member_ids",[]):_member_groups.erase(id)
	for node in group.members:
		if not is_instance_valid(node):continue
		_member_groups.erase(str(node.name))
		var callback:Callable=group.get("exit_callback",Callable())
		if callback.is_valid() and node.tree_exiting.is_connected(callback):node.tree_exiting.disconnect(callback)
		var visible_callback:Callable=group.get("visible_callback",Callable())
		if visible_callback.is_valid() and node.visibility_changed.is_connected(visible_callback):node.visibility_changed.disconnect(visible_callback)
	if is_instance_valid(group.get("visual")): group.visual.free()
	if not restore_sources: return
	for node in group.members:
		if is_instance_valid(node) and not node.is_queued_for_deletion(): restore(node)

func _invalidate_group(key:String,generation:int)->void:
	if not groups.has(key) or groups[key].generation!=generation:return
	var group:Dictionary=groups[key]
	groups.erase(key);pending.erase(key)
	_drop(group)

func _watch_group(key:String,group:Dictionary)->void:
	# Residency can free sources before the next sync. Invalidate the combined
	# visual immediately, including when a non-leading member leaves the tree.
	var callback:=_invalidate_group.bind(key,group.generation)
	group.exit_callback=callback;group.member_ids=[]
	group.moving=group.category=="building" and group.members[0].get_meta("ground_batch_record",{}).has("fixture")
	if group.category=="building":
		group.visible_callback=_sync_visibility.bind(key,group.generation)
		group.members[0].visibility_changed.connect(group.visible_callback)
	for node in group.members:
		group.member_ids.append(str(node.name))
		node.tree_exiting.connect(callback)

func _sync_visibility(key:String,generation:int)->void:
	if not groups.has(key) or groups[key].generation!=generation:return
	var group:Dictionary=groups[key]
	if is_instance_valid(group.get("visual")) and is_instance_valid(group.members[0]):
		group.visual.visible=group.members[0].is_visible_in_tree()

func _sync_pose(key:String,generation:int)->void:
	if not groups.has(key) or groups[key].generation!=generation:return
	var group:Dictionary=groups[key]
	if not is_instance_valid(group.get("visual")) or group.members.is_empty() or not is_instance_valid(group.members[0]):return
	var pose:Transform3D=group.members[0].global_transform
	if pose!=group.last_source_pose:
		group.visual.global_transform=pose*group.relative_pose;group.last_source_pose=pose

func sync(nodes: Array, excluded: Array = []) -> void:
	var sync_started:=Time.get_ticks_usec()
	sync_count+=1
	sync_profile={"material_us":0,"geometry_us":0,"capture_us":0}
	var desired := {}
	_material_keys.clear()
	for cached: String in _instance_meshes.keys():
		if _instance_meshes[cached].get_ref()==null: _instance_meshes.erase(cached)
	for cached:String in _building_meshes.keys():
		if _building_meshes[cached].reference.get_ref()==null:_building_meshes.erase(cached)
	if enabled:
		# Convert names once and sort native strings; a scripted comparator used
		# to cross into GDScript tens of thousands of times for one small town.
		var ordered:Array[String]=[];var named:Dictionary={}
		for node in nodes:
			if not is_instance_valid(node):continue
			var id:=str(node.name);ordered.append(id);named[id]=node
		ordered.sort()
		for id in ordered:
			var node:Node=named[id]
			if not node is MeshInstance3D or not node.has_meta("ground_batch_record") or str(node.name) in excluded: continue
			if not node.is_visible_in_tree() or node.transparency > 0 or node.material_overlay != null or node.skin != null: continue
			var record: Dictionary = node.get_meta("ground_batch_record")
			if not Geometry.candidate(record) or not node.global_basis.is_conformal() or not node.global_basis.get_scale().is_equal_approx(Vector3.ONE) or node.global_basis.determinant() < 0: continue
			var keys: Array = []; var eligible := true
			var mark:=Time.get_ticks_usec()
			for slot in node.mesh.get_surface_count():
				var material: Material = node.get_active_material(slot)
				if not _material_keys.has(material): _material_keys[material] = Geometry.material_key(material)
				var key: String = _material_keys[material]
				if key.is_empty(): eligible = false; break
				keys.append(key)
				if material is ShaderMaterial and (absf(node.global_basis.y.x) > .00001 or absf(node.global_basis.y.z) > .00001): eligible = false
			if not eligible: continue
			sync_profile.material_us+=Time.get_ticks_usec()-mark
			# Small surfaces use 128 m bins; a 200 m terrain uses 512 m bins. Never
			# merge a whole city, so culling and local edits stay spatially bounded.
			var extent: Vector3 = node.get_aabb().size
			var kind:=Geometry.category(record)
			var cell := maxf(32. if kind=="fortification" else 128., pow(2., ceil(log(maxf(1., maxf(extent.x,extent.z))) / log(2.))) * (1. if kind=="fortification" else 2.))
			var center: Vector3 = node.global_position
			var shape: Array = [record.terrain_mesh.columns,record.terrain_mesh.rows] if record.has("terrain_mesh") else []
			if kind=="building":
				var b:Dictionary=record.building
				var presentation:String="ceiling" if str(b.part).ends_with("/ceiling") else ("roof" if b.role=="roof" else "body")
				shape=[b.id,b.floor,presentation,record.get("fixture",{}).get("id","")]
			var merge_base:=_fingerprint([kind,floor(center.x/cell),floor(center.z/cell),cell,keys,shape,node.cast_shadow,node.layers])
			# Keep repeated modules together even when a spatial cell also contains
			# other stone shapes. Mixing shapes defeats vertex-buffer sharing.
			mark=Time.get_ticks_usec()
			var cpu:=Cpu.capture(node.mesh)
			sync_profile.capture_us+=Time.get_ticks_usec()-mark; mark=Time.get_ticks_usec()
			if kind=="fortification": shape=[_geometry_signature(cpu)]
			sync_profile.geometry_us+=Time.get_ticks_usec()-mark
			var base:String = _fingerprint([kind,floor(center.x/cell),floor(center.z/cell),cell,keys,shape,node.cast_shadow,node.layers]) if kind=="fortification" else merge_base
			var vertices := Geometry.vertex_count(node.mesh)
			if vertices > Geometry.MAX_VERTICES: continue
			var bin := 0; var key := base + ":0"
			while desired.has(key) and (desired[key].members.size() >= Geometry.member_limit(record) or desired[key].vertices + vertices > Geometry.MAX_VERTICES):
				bin += 1; key = base + ":" + str(bin)
			if not desired.has(key): desired[key] = {"merge_base":merge_base,"category":kind,"members":[], "vertices":0, "keys":keys, "signature":[], "origin":Vector3((floor(center.x/cell)+.5)*cell,0,(floor(center.z/cell)+.5)*cell)}
			desired[key].members.append(node); desired[key].vertices += vertices
			desired[key].signature.append([node.get_instance_id(),node.global_transform])
	# Unique shapes still benefit from actual mesh merging. Keep them out of the
	# repeated-module groups so shared stone geometry is never flattened N times.
	for key: String in desired.keys():
		var source: Dictionary=desired[key]
		if source.category!="fortification" or source.members.size()!=1: continue
		desired.erase(key)
		var bin:=0; var target: String="unique:"+source.merge_base+":0"
		while desired.has(target) and (desired[target].members.size()>=Geometry.MAX_FORTIFICATION_MEMBERS or desired[target].vertices+source.vertices>Geometry.MAX_VERTICES):
			bin+=1; target="unique:"+source.merge_base+":"+str(bin)
		if not desired.has(target): desired[target]=source
		else:
			desired[target].members.append_array(source.members); desired[target].signature.append_array(source.signature); desired[target].vertices+=source.vertices
	for key: String in desired.keys():
		if desired[key].members.size() < 2: desired.erase(key)
	for key: String in groups.keys():
		if not desired.has(key) or desired[key].signature != groups[key].signature:
			_drop(groups[key]); groups.erase(key); pending.erase(key)
	for key: String in desired:
		if groups.has(key): continue
		_generation += 1; desired[key].generation = _generation
		groups[key] = desired[key]; pending.append(key)
		_watch_group(key,groups[key])
	_material_keys.clear() # Don't pin materials from deleted maps.
	_member_groups.clear()
	for key: String in groups:
		for node in groups[key].members: _member_groups[str(node.name)]=key
	_audit_keys=groups.keys();_audit_cursor=0
	last_sync_ms=(Time.get_ticks_usec()-sync_started)/1000.

func _process(_delta: float) -> void:
	# Lifetime signals are immediate. A bounded audit also repairs stale caches
	# without polling thousands of static/closed fixtures every frame.
	for i in mini(32,_audit_keys.size()):
		_audit_cursor%=_audit_keys.size()
		var key:String=_audit_keys[_audit_cursor];_audit_cursor+=1
		if not groups.has(key):continue
		var group:Dictionary=groups[key]
		if group.category!="building" or not is_instance_valid(group.get("visual")):continue
		# Check the Variant before typed assignment: casting a freed Object fails
		# before an is_instance_valid() check on the typed local can run.
		if group.members.is_empty() or not is_instance_valid(group.members[0]):
			_invalidate_group(key,group.generation);continue
	# The worker only owns immutable arrays/material snapshots, never scene nodes.
	# Several cheap instance groups fit in one frame; one group per frame adds
	# seconds of artificial latency to a city even when no CPU work is pending.
	var started:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-started<work_budget_usec:
		var ready: int=_workers.find_custom(func(job):return not job.thread.is_alive())
		if ready>=0: _finish_worker(ready); continue
		if _workers.size()>=MAX_WORKERS:
			# A loading screen can spend its 24 ms slice joining a tiny job.
			# Returning here otherwise limits hundreds of fixtures to 3 per frame.
			if work_budget_usec>=24000:_finish_worker(0);continue
			return
		if pending.is_empty(): return
		_build_next(true)

func flush() -> void:
	while not _workers.is_empty(): _finish_worker(0)
	while not pending.is_empty(): _build_next()

func _build_next(background: bool = false) -> void:
	var key: String = pending.pop_front()
	if not groups.has(key): return
	var group: Dictionary = groups[key]
	for node in group.members:
		if not is_instance_valid(node): _drop(group); groups.erase(key); return
	var started := Time.get_ticks_usec()
	if group.category=="building":group.origin=group.members[0].global_position
	var snapshot: Array = []
	group.cpu = []
	for node: MeshInstance3D in group.members:
		var cpu: Mesh = Cpu.capture(node.mesh); var materials: Array = []
		group.cpu.append(cpu)
		for slot in node.mesh.get_surface_count(): materials.append(node.get_active_material(slot))
		snapshot.append({"record":node.get_meta("ground_batch_record"),"transform":node.global_transform,"surfaces":cpu.surfaces,"materials":materials,"keys":group.keys})
	if group.category=="building" and not snapshot[0].materials.any(func(material):return material is ShaderMaterial):
		var identity:Array=[]
		for i in snapshot.size():
			var pose:Transform3D=snapshot[i].transform;pose.origin-=group.origin
			# World float cancellation differs between translated copies. Render
			# cache comparisons tolerate at most 0.1 mm, without editing records.
			pose.origin=pose.origin.snapped(Vector3.ONE*.0001)
			identity.append([group.cpu[i].geometry_key(),pose,group.keys])
		group.mesh_cache_key=_fingerprint(identity)
		if _building_meshes.has(group.mesh_cache_key):
			var entry:Dictionary=_building_meshes[group.mesh_cache_key]
			var shared:Mesh=entry.reference.get_ref()
			if shared!=null:
				var data:Dictionary=entry.data.duplicate();data.mesh=shared;building_mesh_hits+=1
				_commit(group,data,started);return
	# Repeated stone modules should share one vertex buffer. Flattening them
	# all into a combined mesh trades fewer draws for duplicated GPU geometry.
	if group.category=="fortification" and _identical_geometry(group.cpu):
		_commit_instances(group,snapshot,started)
		return
	if background:
		var job:={"key":key,"generation":group.generation,"started":started,"thread":Thread.new()}
		var origin: Vector3=group.origin
		if job.thread.start(func():return Geometry.build(snapshot,origin,true)) == OK: _workers.append(job); return
	_commit(group,Geometry.build(snapshot,group.origin),started)

func _identical_geometry(meshes: Array) -> bool:
	var expected: String=""
	for mesh: Mesh in meshes:
		var signature:=_geometry_signature(mesh)
		if expected.is_empty(): expected=signature
		elif signature!=expected: return false
	return true

func _geometry_signature(mesh: Mesh) -> String:
	return mesh.geometry_key()

func _commit_instances(group: Dictionary,snapshot: Array,started: int) -> void:
	var key: String=(str(group.cpu[0].get_meta("static_batch_geometry_signature"))+var_to_str(group.keys)).sha256_text()
	var mesh: Mesh=_instance_meshes[key].get_ref() if _instance_meshes.has(key) else null
	if mesh==null:
		var original: Mesh=group.cpu[0].source_reference.get_ref() if group.cpu[0].source_reference!=null else null
		var compatible:=original!=null
		if compatible:
			for slot in original.get_surface_count():
				if original.surface_get_material(slot)!=snapshot[0].materials[slot]: compatible=false; break
		mesh=original if compatible else group.cpu[0].restore()
		if not compatible:
			if mesh is PrimitiveMesh: mesh.material=snapshot[0].materials[0]
			else:
				for slot in mesh.get_surface_count(): mesh.surface_set_material(slot,snapshot[0].materials[slot])
		_instance_meshes[key]=weakref(mesh)
	var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D; multi.mesh=mesh; multi.instance_count=snapshot.size()
	for i in snapshot.size():
		var pose: Transform3D=snapshot[i].transform; pose.origin-=group.origin; multi.set_instance_transform(i,pose)
	var visual:=MultiMeshInstance3D.new(); visual.multimesh=multi; visual.cast_shadow=group.members[0].cast_shadow; visual.layers=group.members[0].layers; visual.set_meta("ground_render_batch",true)
	add_child(visual); visual.global_position=group.origin
	var vertices:=Geometry.vertex_count(mesh)
	group.visual=visual; group.data={"mesh":mesh,"source_surfaces":mesh.get_surface_count()*snapshot.size(),"source_vertices":vertices*snapshot.size(),"render_vertices":vertices,"instanced":true}
	for i in group.members.size(): freeze(group.members[i],group.cpu[i])
	group.erase("cpu"); rebuild_count+=1
	last_build_ms=(Time.get_ticks_usec()-started)/1000.; max_build_ms=maxf(max_build_ms,last_build_ms); last_commit_ms=last_build_ms
	max_commit_ms=maxf(max_commit_ms,last_commit_ms)

func _finish_worker(index: int) -> void:
	var job: Dictionary=_workers[index]; _workers.remove_at(index)
	var data: Dictionary = job.thread.wait_to_finish()
	if groups.has(job.key) and groups[job.key].generation == job.generation:
		_commit(groups[job.key],data,job.started)

func _exit_tree() -> void:
	for job: Dictionary in _workers: job.thread.wait_to_finish()
	_workers.clear()

func _commit(group: Dictionary, data: Dictionary, started: int) -> void:
	if data.is_empty(): return
	for node in group.members:
		if not is_instance_valid(node): return
	var commit_started := Time.get_ticks_usec()
	if not data.has("mesh"): data=Geometry.upload(data)
	if data.is_empty() or data.mesh.get_surface_count()==0: return
	if group.has("mesh_cache_key"):
		var info:Dictionary=data.duplicate();info.erase("mesh");info.erase("slots")
		_building_meshes[group.mesh_cache_key]={"reference":weakref(data.mesh),"data":info}
	var visual := MeshInstance3D.new(); visual.mesh = data.mesh
	visual.cast_shadow = group.members[0].cast_shadow; visual.layers = group.members[0].layers
	visual.set_meta("ground_render_batch", true)
	if group.category=="ground" and data.source_surfaces == group.members.size(): visual.set_meta("extras", {"kind":"ground"})
	add_child(visual); visual.global_position = group.origin
	group.visual = visual; group.data = data
	group.reference_pose=group.members[0].global_transform
	group.last_source_pose=group.reference_pose
	group.relative_pose=group.reference_pose.affine_inverse()*Transform3D(Basis.IDENTITY,group.origin)
	if group.get("moving",false):
		var watcher:=preload("res://scripts/world3d/batch_transform_watch.gd").new()
		watcher.changed=_sync_pose.bind(_member_groups[str(group.members[0].name)],group.generation)
		group.pose_watcher=watcher;group.members[0].add_child(watcher)
	visual.visible=group.members[0].is_visible_in_tree()
	for i in group.members.size(): freeze(group.members[i],group.cpu[i])
	group.erase("cpu")
	rebuild_count += 1
	last_build_ms = (Time.get_ticks_usec()-started)/1000.; max_build_ms = maxf(max_build_ms,last_build_ms)
	last_commit_ms = (Time.get_ticks_usec()-commit_started)/1000.
	max_commit_ms=maxf(max_commit_ms,last_commit_ms)

func stats(category: String="") -> Dictionary:
	var result := {"enabled":enabled,"pending_groups":pending.size()+_workers.size(),"groups":0,"instanced_groups":0,"source_objects":0,"source_surfaces":0,"render_surfaces":0,"source_vertices":0,"render_vertices":0,"rebuild_count":rebuild_count,"last_build_ms":last_build_ms,"max_build_ms":max_build_ms,"last_commit_ms":last_commit_ms,"max_commit_ms":max_commit_ms,"last_sync_ms":last_sync_ms,"sync_profile_us":sync_profile.duplicate()}
	result.sync_count=sync_count; result.release_groups_visited=release_groups_visited
	result.building_mesh_hits=building_mesh_hits
	for group: Dictionary in groups.values():
		if not category.is_empty() and group.category!=category: continue
		if not group.has("data"): continue
		result.groups += 1; result.source_objects += group.members.size()
		if group.data.get("instanced",false): result.instanced_groups+=1
		result.source_surfaces += group.data.source_surfaces
		result.render_surfaces += group.data.mesh.get_surface_count()
		result.source_vertices += group.data.source_vertices; result.render_vertices += group.data.render_vertices
	return result
