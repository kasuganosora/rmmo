extends RefCounted
## City view loads 32 m chunks around the player. The document keeps every record.

const Location = preload("res://scripts/world3d/world_location.gd")
const CHUNK_M := 32.0
const RENDER_RADIUS := 1
const BUILDING_VIEW_M := 1000.0
const BUILDING_RENDER_RADIUS := int(ceil(BUILDING_VIEW_M / CHUNK_M))
const COLLISION_RADIUS := 2
## Gameplay spreads a chunk swap across frames. Tests pass 0 and finish in one call.
const FRAME_BUDGET := 12
## Loading has no moving player; use a 24 ms time slice without a tiny
## object-count ceiling that otherwise wastes hundreds of loading frames.
const LOAD_BUDGET := 512
const GroundBatcher = preload("res://scripts/world3d/ground_batcher.gd")
const CpuMesh = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const FortCollision = preload("res://scripts/world3d/fortification_collision_batcher.gd")


static func chunk_key(position: Vector3) -> Vector2i:
	return Vector2i(
		Location.chunk_index(position.x, 0.0, CHUNK_M),
		Location.chunk_index(position.z, 0.0, CHUNK_M)
	)


static func ring(origin: Vector3, radius: int) -> Dictionary:
	var center := chunk_key(origin)
	var keys := {}
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			keys[Vector2i(center.x + dx, center.y + dz)] = true
	return keys


static func sync(map_root: Node, host: Node, origin: Vector3, budget: int = 0) -> void:
	var sync_started:=Time.get_ticks_usec()
	var library: Array = _library(map_root)
	var known := _dict(map_root, &"stream_known")
	var meshes := _dict(map_root, &"stream_meshes")
	var bodies := _dict(map_root, &"stream_bodies")
	_index_buildings(map_root,library)
	var jobs := _jobs(map_root)
	var target := chunk_key(origin)
	var child_count := map_root.get_child_count()
	var previous_chunk:Variant=map_root.get_meta(&"stream_chunk") if map_root.has_meta(&"stream_chunk") else null
	var unfinished:Array=[]
	if previous_chunk==null and map_root.has_meta(&"stream_target") and not _chunk_is(map_root,&"stream_target",target):
		previous_chunk=map_root.get_meta(&"stream_target")
		unfinished.append_array(jobs.slice(int(map_root.get_meta(&"stream_cursor",0))))
		if map_root.has_meta(&"stream_candidates"):
			unfinished.append_array(map_root.get_meta(&"stream_candidates").slice(int(map_root.get_meta(&"stream_plan_cursor",0))))
		for bin:Array in map_root.get_meta(&"stream_plan_bins",[]):unfinished.append_array(bin)
	if jobs.is_empty() and _chunk_is(map_root, &"stream_chunk", target) and _child_count_is(map_root, child_count):
		return
	if not _child_count_is(map_root, child_count):
		previous_chunk=null
		_adopt(map_root, library, known)
		_index_buildings(map_root,library)
		child_count = map_root.get_child_count()
		map_root.remove_meta(&"stream_target")
	if not _chunk_is(map_root, &"stream_target", target):
		map_root.set_meta(&"stream_target", target)
		map_root.remove_meta(&"stream_chunk")
		jobs.clear()
		map_root.set_meta(&"stream_candidates", _changed_candidates(map_root,previous_chunk,target,unfinished) if previous_chunk is Vector2i else _candidates(map_root, target, meshes, bodies))
		map_root.set_meta(&"stream_plan_cursor", 0)
		map_root.set_meta(&"stream_plan_bins", [[], [], [], [], []])
		map_root.set_meta(&"stream_cursor", 0)
	map_root.set_meta(&"stream_children", map_root.get_child_count())
	map_root.set_meta(&"stream_library", library)
	var plan_started:=Time.get_ticks_usec()
	if not _plan_jobs(map_root, jobs, meshes, bodies, target, budget):
		return
	var cursor := int(map_root.get_meta(&"stream_cursor", 0))
	var left := 1000000 if budget <= 0 else budget
	var draw := _ring_at(target, RENDER_RADIUS)
	var solid := _ring_at(target, COLLISION_RADIUS)
	var apply_started := Time.get_ticks_usec()
	while left > 0 and cursor < jobs.size():
		if _apply(map_root, host, jobs[cursor], draw, solid, meshes, bodies):
			map_root.set_meta("stream_visibility_revision",int(map_root.get_meta("stream_visibility_revision",0))+1)
		cursor += 1
		left -= 1
		if budget > 0 and Time.get_ticks_usec() - apply_started >= (24000 if budget>=LOAD_BUDGET else 3000):
			break
	map_root.set_meta(&"stream_cursor", cursor)
	var batch_started:=Time.get_ticks_usec()
	var batcher: Node3D = map_root.get_node_or_null("GroundRenderBatches")
	if batcher == null:
		batcher = GroundBatcher.new(); batcher.name = "GroundRenderBatches"; batcher.set_meta("stream_instance",true); map_root.add_child(batcher)
	batcher.work_budget_usec=24000 if budget>=LOAD_BUDGET else 2000
	# Source visuals are already visible while residency jobs are applied.
	# Reconcile the render batches once per completed residency change, not
	# after every twelve objects (which repeatedly sorts the growing scene).
	var revision:int=map_root.get_meta("stream_visibility_revision",0)
	if cursor >= jobs.size() and int(map_root.get_meta("stream_batch_revision",-1))!=revision:
		batcher.sync(meshes.values());map_root.set_meta("stream_batch_revision",revision)
		# During the covered initial load, only upload the final combined draws.
		# Transparent/ineligible/singleton sources still need their own GPU mesh.
		for source in meshes.values():
			if source.has_meta("deferred_gpu"):
				if not batcher._member_groups.has(str(source.name)):GroundBatcher.restore(source)
				source.remove_meta("deferred_gpu")
	if budget <= 0: batcher.flush()
	var collision_batches=map_root.get_node_or_null("FortificationCollisionBatches")
	if collision_batches==null:
		collision_batches=FortCollision.new(); map_root.add_child(collision_batches)
	var entries: Array=[]
	for spec: Dictionary in _dict(map_root,&"fortification_collision_sources").values(): entries.append(FortCollision.entry(spec.mesh,spec.transform,spec.uuid,spec.extras))
	collision_batches.sync(entries)
	map_root.set_meta(&"stream_library", library)
	map_root.set_meta(&"stream_children", map_root.get_child_count())
	if budget<=0:map_root.set_meta("stream_profile_ms",{"index":(plan_started-sync_started)/1000.0,"plan":(apply_started-plan_started)/1000.0,"apply":(batch_started-apply_started)/1000.0,"batch":(Time.get_ticks_usec()-batch_started)/1000.0})
	if cursor < jobs.size():
		return
	jobs.clear()
	map_root.set_meta(&"stream_cursor", 0)
	map_root.set_meta(&"stream_chunk", target)


static func _library(map_root: Node) -> Array:
	var existing: Variant = map_root.get_meta(&"stream_library", [])
	if existing is Array:
		return existing
	var created: Array = []
	map_root.set_meta(&"stream_library", created)
	return created


static func _dict(node: Node, key: StringName) -> Dictionary:
	if node.has_meta(key):
		var existing: Variant = node.get_meta(key)
		if existing is Dictionary:
			return existing
	var created := {}
	node.set_meta(key, created)
	return created


static func _live(bag: Dictionary, uuid: String):
	var node: Variant = bag.get(uuid, null)
	if node == null or not is_instance_valid(node):
		bag.erase(uuid)
		return null
	return node


static func _jobs(node: Node) -> Array:
	if node.has_meta(&"stream_jobs"):
		var existing: Variant = node.get_meta(&"stream_jobs")
		if existing is Array:
			return existing
	var created: Array = []
	node.set_meta(&"stream_jobs", created)
	return created


static func _chunk_is(node: Node, key: StringName, chunk: Vector2i) -> bool:
	if not node.has_meta(key):
		return false
	var value: Variant = node.get_meta(key)
	return value is Vector2i and (value as Vector2i) == chunk


static func _child_count_is(node: Node, count: int) -> bool:
	return node.has_meta(&"stream_children") and int(node.get_meta(&"stream_children")) == count


static func _adopt(map_root: Node, library: Array, known: Dictionary) -> void:
	var started:=Time.get_ticks_usec();var spec_us:=0;var free_us:=0;var freed_count:=0
	preload("res://scripts/world3d/scene_integrity.gd").prepare(map_root)
	var incoming: Array = []
	var reused_count:=0
	_collect_meshes(map_root, incoming)
	for mesh in incoming:
		var spec_started:=Time.get_ticks_usec()
		var spec := _spec(mesh as MeshInstance3D)
		spec_us+=Time.get_ticks_usec()-spec_started
		var world_transform: Transform3D = mesh.global_transform
		spec["transform"] = world_transform
		spec["position"] = world_transform.origin
		var bounds: AABB = world_transform * mesh.get_aabb()
		spec["chunk"] = chunk_key(world_transform.origin)
		spec["chunk_min"] = chunk_key(bounds.position)
		spec["chunk_max"] = chunk_key(bounds.end)
		preload("res://scripts/world3d/building_fixtures.gd").prepare_spec(spec)
		var metadata: Dictionary = spec["extras"]
		spec["uuid"] = str(metadata.get("uuid", str(map_root.get_path_to(mesh)).replace("/", "__")))
		var adopted := str(spec.get("uuid", ""))
		library.append(spec)
		known[adopted] = true
		# A freshly built flat static source is already the required runtime
		# instance. Reuse it; deleting tens of thousands of siblings and then
		# recreating them dominated first adoption. Native graphs/NPCs keep their
		# established paths, and distant sources are still removed by residency.
		if mesh.get_parent()==map_root and spec.has("ground_batch_record") and not spec.ground_batch_record.has("fortification") and not spec.native_visual:
			mesh.set_meta("stream_instance",true);_dict(map_root,&"stream_meshes")[adopted]=mesh
			preload("res://scripts/world3d/wind_response.gd").register(mesh)
			reused_count+=1
		_dict(map_root, &"stream_by_id")[adopted] = spec
		var index := _dict(map_root, &"stream_index")
		var low: Vector2i = spec["chunk_min"]
		var high: Vector2i = spec["chunk_max"]
		for z in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var key := Vector2i(x, z)
				if not index.has(key):
					index[key] = []
				index[key].append(adopted)
	# Children must be removed before their mesh parents.
	incoming.reverse()
	var free_started:=Time.get_ticks_usec()
	for mesh in incoming:
		if mesh.has_meta("stream_instance"):continue
		if mesh.has_meta("native_visual"):
			mesh.set_meta("stream_instance", true)
			preload("res://scripts/world3d/wind_response.gd").register(mesh)
			continue
		mesh.get_parent().remove_child(mesh)
		(mesh as Node).free()
		freed_count+=1
	free_us=Time.get_ticks_usec()-free_started
	map_root.set_meta("stream_adopt_ms",{"total":(Time.get_ticks_usec()-started)/1000.0,"spec":spec_us/1000.0,"free":free_us/1000.0,"freed_count":freed_count,"reused_count":reused_count})


static func _collect_meshes(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child.has_meta("stream_instance"):
			continue
		if child is MeshInstance3D:
			result.append(child)
		_collect_meshes(child, result)


static func _candidates(map_root: Node, target: Vector2i, meshes: Dictionary, bodies: Dictionary) -> Array:
	var index := _dict(map_root, &"stream_index")
	var by_id := _dict(map_root, &"stream_by_id")
	var selected := {}
	for key in meshes:
		selected[key] = by_id[key]
	for key in bodies:
		selected[key] = by_id[key]
	for key in _dict(map_root,&"fortification_collision_sources"):
		selected[key]=by_id[key]
	var radius:=maxi(COLLISION_RADIUS,BUILDING_RENDER_RADIUS)
	for z in range(target.y - radius, target.y + radius + 1):
		for x in range(target.x - radius, target.x + radius + 1):
			for key in index.get(Vector2i(x, z), []):
				selected[key] = by_id[key]
	var groups:=_dict(map_root,&"stream_building_groups")
	var seen:Dictionary={}
	for spec:Dictionary in selected.values():
		var id:String=spec.get("render_building","")
		if id.is_empty() or seen.has(id):continue
		seen[id]=true
		for member:Dictionary in groups[id]:selected[member.uuid]=member
	return selected.values()

static func _changed_candidates(map_root:Node,previous:Vector2i,target:Vector2i,unfinished:Array=[])->Array:
	# After a settled swap, only the entering/leaving spatial strips can change
	# residency. Whole-building visibility is compared once per building.
	var selected:Dictionary={}
	for spec:Dictionary in unfinished:selected[spec.uuid]=spec
	for radius in [RENDER_RADIUS,COLLISION_RADIUS]:
		var index:Dictionary=_dict(map_root,&"stream_prop_index" if radius==RENDER_RADIUS else &"stream_collision_index")
		var old:=_ring_at(previous,radius);var next:=_ring_at(target,radius)
		for center in [previous,target]:
			for z in range(center.y-radius,center.y+radius+1):
				for x in range(center.x-radius,center.x+radius+1):
					var key:=Vector2i(x,z)
					var inside_old:bool=x>=old.low.x and x<=old.high.x and z>=old.low.y and z<=old.high.y
					var inside_next:bool=x>=next.low.x and x<=next.high.x and z>=next.low.y and z<=next.high.y
					if inside_old==inside_next:continue
					for spec:Dictionary in index.get(key,[]):selected[spec.uuid]=spec
	var old_draw:=_ring_at(previous,RENDER_RADIUS);var next_draw:=_ring_at(target,RENDER_RADIUS)
	for members:Array in _dict(map_root,&"stream_building_groups").values():
		if _draws(members[0],old_draw)==_draws(members[0],next_draw):continue
		for spec:Dictionary in members:selected[spec.uuid]=spec
	return selected.values()


static func _index_buildings(map_root:Node,library:Array)->void:
	if int(map_root.get_meta("stream_building_count",-1))==library.size():return
	var groups:Dictionary={}
	var props:Dictionary={};var collisions:Dictionary={}
	for spec:Dictionary in library:
		var id:String=spec.get("ground_batch_record",{}).get("building",{}).get("id","")
		var solid:bool=spec.get("extras",{}).get("rmmo_collision","")!="none"
		if id.is_empty() or solid:
			for z in range(spec.chunk_min.y,spec.chunk_max.y+1):
				for x in range(spec.chunk_min.x,spec.chunk_max.x+1):
					var key:=Vector2i(x,z)
					if id.is_empty():
						if not props.has(key):props[key]=[]
						props[key].append(spec)
					if solid:
						if not collisions.has(key):collisions[key]=[]
						collisions[key].append(spec)
		if id.is_empty():continue
		if not groups.has(id):groups[id]=[]
		groups[id].append(spec)
	for id:String in groups:
		var low:=Vector2i(2147483647,2147483647);var high:=-low
		for spec:Dictionary in groups[id]:low=low.min(spec.chunk_min);high=high.max(spec.chunk_max)
		for spec:Dictionary in groups[id]:
			spec.render_building=id;spec.render_bounds={"chunk":low,"chunk_min":low,"chunk_max":high}
	map_root.set_meta("stream_building_groups",groups)
	map_root.set_meta("stream_prop_index",props);map_root.set_meta("stream_collision_index",collisions)
	map_root.set_meta("stream_building_count",library.size())


static func _draws(spec:Dictionary,draw:Dictionary)->bool:
	if not spec.has("render_bounds"):return _overlaps(spec,draw)
	var extra:=BUILDING_RENDER_RADIUS-RENDER_RADIUS
	return _overlaps(spec.render_bounds,{"low":draw.low-Vector2i(extra,extra),"high":draw.high+Vector2i(extra,extra)})


static func _plan_jobs(map_root: Node, jobs: Array, meshes: Dictionary, bodies: Dictionary, target: Vector2i, budget: int) -> bool:
	if not map_root.has_meta(&"stream_candidates"):
		return true
	var candidates: Array = map_root.get_meta(&"stream_candidates")
	var cursor := int(map_root.get_meta(&"stream_plan_cursor", 0))
	var bins: Array = map_root.get_meta(&"stream_plan_bins")
	var draw := _ring_at(target, RENDER_RADIUS)
	var solid := _ring_at(target, COLLISION_RADIUS)
	var started := Time.get_ticks_usec()
	while cursor < candidates.size():
		var item: Dictionary = candidates[cursor]
		cursor += 1
		if _needs_work(item, draw, solid, meshes, bodies, _dict(map_root,&"fortification_collision_sources")):
			var bin := 4
			if _overlaps(item, solid):
				var key: Vector2i = item["chunk"]
				bin = mini(maxi(absi(key.x - target.x), absi(key.y - target.y)), 3)
			bins[bin].append(item)
		if budget > 0 and Time.get_ticks_usec() - started >= (12000 if budget>=LOAD_BUDGET else 2000):
			map_root.set_meta(&"stream_plan_cursor", cursor)
			return false
	for bin in bins:
		jobs.append_array(bin)
	map_root.remove_meta(&"stream_candidates")
	map_root.remove_meta(&"stream_plan_bins")
	return true


static func _needs_work(spec: Dictionary, draw: Dictionary, solid: Dictionary, meshes: Dictionary, bodies: Dictionary, batched: Dictionary={}) -> bool:
	var key: Vector2i = spec["chunk"]
	var uuid := str(spec["uuid"])
	var has_mesh := _live(meshes, uuid) != null
	var has_body := batched.has(uuid) or _live(bodies, uuid) != null
	var collides := str(spec.get("extras", {}).get("rmmo_collision", "")) != "none" and not (bool(spec.get("extras", {}).get("hostile", false)) or bool(spec.get("extras", {}).get("ally", false)))
	collides=collides and _overlaps(spec,solid)
	if not bool(spec.get("native_visual", false)) and _draws(spec, draw) != has_mesh:
		return true
	if collides != has_body:
		return true
	return false


static func _apply(map_root: Node, host: Node, spec: Dictionary, draw: Dictionary, solid: Dictionary, meshes: Dictionary, bodies: Dictionary) -> bool:
	var key: Vector2i = spec["chunk"]
	var uuid := str(spec["uuid"])
	var inst = _live(meshes, uuid) as MeshInstance3D
	var body = _live(bodies, uuid) as StaticBody3D
	var changed:=false
	var collides := str(spec.get("extras", {}).get("rmmo_collision", "")) != "none" and not (bool(spec.get("extras", {}).get("hostile", false)) or bool(spec.get("extras", {}).get("ally", false)))
	collides=collides and _overlaps(spec,solid)
	if not collides or not FortCollision.candidate(spec.get("ground_batch_record",{})): _dict(map_root,&"fortification_collision_sources").erase(uuid)
	if bool(spec.get("native_visual", false)):
		pass
	elif _draws(spec, draw):
		if inst == null:
			inst = _spawn(spec, bool(map_root.get_meta("defer_source_upload",false)))
			map_root.add_child(inst)
			inst.global_transform = spec["transform"]
			meshes[uuid] = inst
			changed=true
	elif inst != null:
		_drop(meshes, uuid, inst)
		changed=true
	if collides:
		if FortCollision.candidate(spec.get("ground_batch_record",{})):
			_dict(map_root,&"fortification_collision_sources")[uuid]=spec
		elif body == null:
			body = _make_body(host, spec)
			if body != null:
				bodies[uuid] = body
	elif body != null:
		_drop(bodies, uuid, body)
	return changed


static func _ring_at(chunk: Vector2i, radius: int) -> Dictionary:
	return {"low": chunk - Vector2i(radius, radius), "high": chunk + Vector2i(radius, radius)}


static func _drop(bag: Dictionary, uuid: String, node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
	bag.erase(uuid)


static func _spec(visual: MeshInstance3D) -> Dictionary:
	var Io = load("res://scripts/world3d/gltf_map_io.gd")
	var bounds: AABB = visual.transform * visual.get_aabb()
	var extras: Dictionary = Io.extras_of(visual).duplicate(true)
	if visual.has_meta("native_dynamic"): extras["rmmo_collision"] = "none"
	var spec := {
		"native_visual": visual.has_meta("native_visual"),
		"uuid": str(visual.name),
		"position": visual.position,
		"rotation": visual.rotation,
		"transform": visual.transform,
		"chunk_min": chunk_key(bounds.position),
		"chunk_max": chunk_key(bounds.end),
		"mesh": visual.mesh,
		"material_override": visual.material_override,
		"surface_overrides": [],
		"cast_shadow": visual.cast_shadow,
		"extras": extras,
		"chunk": chunk_key(visual.position),
	}
	for slot in visual.mesh.get_surface_count(): spec.surface_overrides.append(visual.get_surface_override_material(slot))
	# Painting changes UVs/materials, never the authored solid. Preserve the
	# exact box primitive instead of downloading the painted mesh for physics.
	var collision_source: Mesh = visual.get_meta("collision_solid",visual.get_meta("paint_source", visual.mesh))
	if collision_source is CpuMesh and collision_source.box_size!=Vector3.ZERO:
		if not collision_source.has_meta("runtime_solid"):
			var solid:=BoxMesh.new();solid.size=collision_source.box_size;collision_source.set_meta("runtime_solid",solid)
		collision_source=collision_source.get_meta("runtime_solid")
	if collision_source is BoxMesh and not collision_source.flip_faces:
		spec["collision_mesh"] = collision_source
	elif visual.mesh.has_meta("ground_cpu_cache"):
		spec["collision_mesh"] = CpuMesh.capture(visual.mesh)
	if visual.has_meta("ground_batch_record"):
		spec.ground_batch_record = visual.get_meta("ground_batch_record")
		# Off-screen terrain keeps CPU collision/authoring data, not GPU buffers.
		spec.mesh = CpuMesh.capture(visual.mesh)
	preload("res://scripts/world3d/building_fixtures.gd").prepare_spec(spec)
	return spec


static func _spawn(spec: Dictionary, defer_upload:bool=false) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = str(spec.get("uuid", "chunk"))
	visual.mesh = spec.get("mesh")
	if visual.mesh is CpuMesh:
		if defer_upload and spec.has("ground_batch_record") and spec.get("material_override")==null and not spec.get("surface_overrides",[]).any(func(value):return value!=null):visual.set_meta("deferred_gpu",true)
		else:visual.mesh = visual.mesh.restore()
	if spec.has("ground_batch_record"): visual.set_meta("ground_batch_record",spec.ground_batch_record)
	visual.material_override = spec.get("material_override")
	visual.cast_shadow=spec.get("cast_shadow",GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for slot in spec.get("surface_overrides",[]).size():
		if spec.surface_overrides[slot]!=null:visual.set_surface_override_material(slot,spec.surface_overrides[slot])
	visual.set_meta("stream_instance", true)
	visual.position = spec.get("position", Vector3.ZERO)
	visual.rotation = spec.get("rotation", Vector3.ZERO)
	visual.transform = spec.get("transform", visual.transform)
	var extras: Dictionary = spec.get("extras", {})
	if not extras.is_empty():
		visual.set_meta("extras", extras)
	preload("res://scripts/world3d/wind_response.gd").register(visual)
	if bool(extras.get("invisible", false)):
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if (bool(extras.get("hostile", false)) or bool(extras.get("ally", false))):
		visual.visible = false
		return visual
	if str(extras.get("kind", "")) == "npc":
		var bounds: AABB = visual.mesh.get_aabb()
		visual.mesh = null
		var actor := preload("res://scripts/char/character_model_3d.gd").create_npc(extras.get("appearance", {}))
		actor.position.y = bounds.position.y
		visual.add_child(actor)
		var label := preload("res://scripts/char/character_overhead_label.gd").new()
		label.model=actor
		label.text = str(extras.get("name", extras.get("npc_id", "NPC")))
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.003
		visual.add_child(label)
	return visual


static func _make_body(host: Node, spec: Dictionary) -> StaticBody3D:
	var extras: Dictionary = spec.get("extras", {})
	if str(extras.get("rmmo_collision", "")) == "none" or (bool(extras.get("hostile", false)) or bool(extras.get("ally", false))):
		return null
	var body := StaticBody3D.new()
	body.name = "%s_body" % str(spec.get("uuid", "chunk"))
	body.set_meta("uuid", str(spec["uuid"]))
	body.set_meta("surface_id", str(extras.get("surface_id", "ground")))
	body.set_meta("kind", str(extras.get("kind", "box")))
	body.set_meta("target_path", str(extras.get("target_path", "")))
	body.set_meta("spawn", extras.get("spawn", [0, 0.9, 4]))
	body.set_meta("npc_id", str(extras.get("npc_id", "")))
	body.set_meta("node_id", str(extras.get("node_id", "")))
	body.set_meta("line", str(extras.get("line", "")))
	if extras.get("seat") is Dictionary:body.set_meta("seat",extras.seat.duplicate(true))
	var position: Vector3 = spec.get("position", Vector3.ZERO)
	body.set_meta("center", position)
	body.position = position
	body.rotation = spec.get("rotation", Vector3.ZERO)
	body.transform = spec.get("transform", body.transform)
	var shape := CollisionShape3D.new()
	var mesh: Mesh = spec.get("collision_mesh", spec.get("mesh", null)) as Mesh
	if mesh == null:
		body.free()
		return null
	# A bounding box is not a collision mesh: it would fill arches and stairs.
	# Cache the static shape in the document view spec across residency changes.
	if not spec.has("shape"):
		if mesh is BoxMesh or (mesh is CpuMesh and mesh.box_size != Vector3.ZERO):
			# Reading PrimitiveMesh.get_aabb() can allocate its render buffers.
			# Physics only needs the authored size, shared by immutable instances.
			var size_:Vector3=mesh.size if mesh is BoxMesh else mesh.box_size
			var box:BoxShape3D=mesh.get_meta("runtime_box_shape") if mesh.has_meta("runtime_box_shape") else null
			if box==null or box.size!=size_:
				box=BoxShape3D.new();box.size=size_;mesh.set_meta("runtime_box_shape",box)
			spec["shape"] = box
		else:
			spec["shape"] = mesh.create_trimesh_shape()
	shape.shape = spec["shape"]
	body.add_child(shape)
	host.add_child(body)
	body.global_transform = spec.get("transform", body.transform)
	return body


static func _overlaps(spec: Dictionary, chunks: Dictionary) -> bool:
	var low: Vector2i = spec.get("chunk_min", spec["chunk"])
	var high: Vector2i = spec.get("chunk_max", spec["chunk"])
	var ring_low: Vector2i = chunks["low"]
	var ring_high: Vector2i = chunks["high"]
	return low.x <= ring_high.x and high.x >= ring_low.x and low.y <= ring_high.y and high.y >= ring_low.y
