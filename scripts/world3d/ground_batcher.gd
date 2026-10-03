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
var _thread: Thread
var _job: Dictionary = {}
var _generation := 0
var last_commit_ms := 0.0

func _ready() -> void:
	name = "GroundRenderBatches"
	set_meta("stream_instance", true)

static func freeze(node: MeshInstance3D, captured: Mesh = null) -> void:
	if node.mesh is Cpu: return
	var cpu: Mesh = captured if captured != null else Cpu.capture(node.mesh)
	for slot in node.mesh.get_surface_count(): cpu.materials[slot] = node.get_active_material(slot)
	for slot in node.get_surface_override_material_count(): node.set_surface_override_material(slot,null)
	# Empty the instance's override list before assigning a CPU mesh (no RS base).
	node.mesh = null; node.material_override = null; node.mesh = cpu
	if node.has_meta("paint_source"): node.set_meta("paint_source", Cpu.capture(node.get_meta("paint_source")))

static func restore(node: MeshInstance3D) -> void:
	if node.mesh is Cpu: node.mesh = node.mesh.restore()

func clear(restore_sources: bool = true) -> void:
	for group: Dictionary in groups.values(): _drop(group,restore_sources)
	groups.clear(); pending.clear(); _material_keys.clear()

func release(ids: Array) -> void:
	# Editing is synchronous: remove the old combined draw before changing a source.
	for key: String in groups.keys():
		var affected := false
		for node in groups[key].members:
			if is_instance_valid(node) and str(node.name) in ids: affected = true; break
		if affected: _drop(groups[key]); groups.erase(key); pending.erase(key)

func _drop(group: Dictionary, restore_sources: bool = true) -> void:
	if is_instance_valid(group.get("visual")): group.visual.free()
	if not restore_sources: return
	for node in group.members:
		if is_instance_valid(node): restore(node)

func sync(nodes: Array, excluded: Array = []) -> void:
	var desired := {}
	_material_keys.clear()
	if enabled:
		var ordered := nodes.duplicate()
		ordered.sort_custom(func(a,b):return str(a.name)<str(b.name))
		for node in ordered:
			if not node is MeshInstance3D or not node.has_meta("ground_batch_record") or str(node.name) in excluded: continue
			if not node.is_visible_in_tree() or node.transparency > 0 or node.material_overlay != null or node.skin != null: continue
			var record: Dictionary = node.get_meta("ground_batch_record")
			if not Geometry.candidate(record) or not node.global_basis.is_conformal() or not node.global_basis.get_scale().is_equal_approx(Vector3.ONE) or node.global_basis.determinant() < 0: continue
			var keys: Array = []; var eligible := true
			for slot in node.mesh.get_surface_count():
				var material: Material = node.get_active_material(slot)
				if not _material_keys.has(material): _material_keys[material] = Geometry.material_key(material)
				var key: String = _material_keys[material]
				if key.is_empty(): eligible = false; break
				keys.append(key)
				if material is ShaderMaterial and (absf(node.global_basis.y.x) > .00001 or absf(node.global_basis.y.z) > .00001): eligible = false
			if not eligible: continue
			# Small surfaces use 128 m bins; a 200 m terrain uses 512 m bins. Never
			# merge a whole city, so culling and local edits stay spatially bounded.
			var extent: Vector3 = node.get_aabb().size
			var cell := maxf(128., pow(2., ceil(log(maxf(1., maxf(extent.x,extent.z))) / log(2.))) * 2.)
			var center: Vector3 = node.global_position
			var shape: Array = [record.terrain_mesh.columns,record.terrain_mesh.rows] if record.has("terrain_mesh") else []
			var base := var_to_str([floor(center.x/cell),floor(center.z/cell),cell,keys,shape,node.cast_shadow,node.layers])
			var vertices := Geometry.vertex_count(node.mesh)
			if vertices > Geometry.MAX_VERTICES: continue
			var bin := 0; var key := base + ":0"
			while desired.has(key) and (desired[key].members.size() >= Geometry.MAX_MEMBERS or desired[key].vertices + vertices > Geometry.MAX_VERTICES):
				bin += 1; key = base + ":" + str(bin)
			if not desired.has(key): desired[key] = {"members":[], "vertices":0, "keys":keys, "signature":[], "origin":Vector3((floor(center.x/cell)+.5)*cell,0,(floor(center.z/cell)+.5)*cell)}
			desired[key].members.append(node); desired[key].vertices += vertices
			desired[key].signature.append([node.get_instance_id(),node.global_transform])
	for key: String in desired.keys():
		if desired[key].members.size() < 2: desired.erase(key)
	for key: String in groups.keys():
		if not desired.has(key) or desired[key].signature != groups[key].signature:
			_drop(groups[key]); groups.erase(key); pending.erase(key)
	for key: String in desired:
		if groups.has(key): continue
		_generation += 1; desired[key].generation = _generation
		groups[key] = desired[key]; pending.append(key)
	_material_keys.clear() # Don't pin materials from deleted maps.

func _process(_delta: float) -> void:
	# The worker only owns immutable arrays/material snapshots, never scene nodes.
	if _thread != null:
		if _thread.is_alive(): return
		_finish_worker()
	if not pending.is_empty(): _build_next(true)

func flush() -> void:
	if _thread != null: _finish_worker()
	while not pending.is_empty(): _build_next()

func _build_next(background: bool = false) -> void:
	var key: String = pending.pop_front()
	if not groups.has(key): return
	var group: Dictionary = groups[key]
	for node in group.members:
		if not is_instance_valid(node): _drop(group); groups.erase(key); return
	var started := Time.get_ticks_usec()
	var snapshot: Array = []
	group.cpu = []
	for node: MeshInstance3D in group.members:
		var cpu: Mesh = Cpu.capture(node.mesh); var materials: Array = []
		group.cpu.append(cpu)
		for slot in node.mesh.get_surface_count(): materials.append(node.get_active_material(slot))
		snapshot.append({"record":node.get_meta("ground_batch_record"),"transform":node.global_transform,"surfaces":cpu.surfaces,"materials":materials,"keys":group.keys})
	if background:
		_job={"key":key,"generation":group.generation,"started":started}
		_thread=Thread.new()
		var origin: Vector3=group.origin
		if _thread.start(func():return Geometry.build(snapshot,origin,true)) == OK: return
		_thread=null; _job.clear()
	_commit(group,Geometry.build(snapshot,group.origin),started)

func _finish_worker() -> void:
	var data: Dictionary = _thread.wait_to_finish(); _thread=null
	if groups.has(_job.key) and groups[_job.key].generation == _job.generation:
		_commit(groups[_job.key],data,_job.started)
	_job.clear()

func _exit_tree() -> void:
	if _thread != null: _thread.wait_to_finish(); _thread=null

func _commit(group: Dictionary, data: Dictionary, started: int) -> void:
	if data.is_empty(): return
	for node in group.members:
		if not is_instance_valid(node): return
	var commit_started := Time.get_ticks_usec()
	if not data.has("mesh"): data=Geometry.upload(data)
	if data.is_empty() or data.mesh.get_surface_count()==0: return
	var visual := MeshInstance3D.new(); visual.mesh = data.mesh
	visual.cast_shadow = group.members[0].cast_shadow; visual.layers = group.members[0].layers
	visual.set_meta("ground_render_batch", true)
	if data.source_surfaces == group.members.size(): visual.set_meta("extras", {"kind":"ground"})
	add_child(visual); visual.global_position = group.origin
	group.visual = visual; group.data = data
	for i in group.members.size(): freeze(group.members[i],group.cpu[i])
	group.erase("cpu")
	rebuild_count += 1
	last_build_ms = (Time.get_ticks_usec()-started)/1000.; max_build_ms = maxf(max_build_ms,last_build_ms)
	last_commit_ms = (Time.get_ticks_usec()-commit_started)/1000.

func stats() -> Dictionary:
	var result := {"enabled":enabled,"pending_groups":pending.size()+(1 if _thread != null else 0),"groups":0,"source_objects":0,"source_surfaces":0,"render_surfaces":0,"source_vertices":0,"render_vertices":0,"rebuild_count":rebuild_count,"last_build_ms":last_build_ms,"max_build_ms":max_build_ms,"last_commit_ms":last_commit_ms}
	for group: Dictionary in groups.values():
		if not group.has("data"): continue
		result.groups += 1; result.source_objects += group.members.size()
		result.source_surfaces += group.data.source_surfaces
		result.render_surfaces += group.data.mesh.get_surface_count()
		result.source_vertices += group.data.source_vertices; result.render_vertices += group.data.render_vertices
	return result
