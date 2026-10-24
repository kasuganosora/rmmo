extends "res://tools/test_collision_basis_preparation.gd"
## Root-owned private-desktop GPU execution only. Temporary generated geometry;
## no formal map, model, native product, or on-disk cache is touched.
const Prefetch = preload("res://scripts/world3d/collision_face_prefetch.gd")
const StreamIndex = preload("res://scripts/world3d/stream_index.gd")

class LifetimeObserver extends RefCounted:
	var releases: Array[int] = []

class LifetimeMarker extends RefCounted:
	var observer: RefCounted
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE: observer.releases.append(OS.get_thread_caller_id())

class CoveredLookaheadGate extends "res://scripts/world3d/stream_collision_preparer.gd":
	# Test-only publication gate. Actual WorldStream planning/lookahead and the
	# real batch worker still run; no ready result or shape is fabricated here.
	var hold_application := false
	func prepare(record: Dictionary, host: Node = null, work_budget_usec: int = 1500) -> bool:
		if hold_application: return false
		return super.prepare(record, host, work_budget_usec)

class DelayedBatch extends RefCounted:
	var mutex:=Mutex.new()
	var released:=false
	func release()->void:
		mutex.lock();released=true;mutex.unlock()
	func start(worker:Thread,task:Callable)->int:
		return worker.start(func():
			while true:
				mutex.lock();var ready:bool=released;mutex.unlock()
				if ready:break
				OS.delay_usec(500)
			return task.call())

func indexed_source(small: bool = false, offset: Vector3 = Vector3.ZERO) -> Mesh:
	var original := source()
	var faces: PackedVector3Array = original.surfaces[0][Mesh.ARRAY_VERTEX]
	if small: faces = faces.slice(0, 900)
	var vertices := PackedVector3Array(); vertices.resize(faces.size())
	var indices := PackedInt32Array(); indices.resize(faces.size())
	# Reverse storage order and use explicit indices so copying vertices without
	# expanding indices cannot accidentally pass the exact geometry assertions.
	for index in faces.size():
		vertices[faces.size() - index - 1] = faces[index] + offset
		indices[index] = faces.size() - index - 1
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_INDEX] = indices
	var cpu := Cpu.new(); cpu.surfaces = [arrays]; cpu.materials = [null]
	cpu.bounds = AABB(vertices[0], Vector3.ZERO)
	for vertex: Vector3 in vertices: cpu.bounds = cpu.bounds.expand(vertex)
	return cpu

func face_equal(actual: PackedVector3Array, expected: PackedVector3Array, label: String) -> void:
	var error := INF
	if actual.size() == expected.size():
		error = 0.
		for index in actual.size(): error = maxf(error, actual[index].distance_to(expected[index]))
	check(error < .0001, label + ": all triangle vertices/order/winding agree within 0.1 mm")

func request(source_mesh: Mesh, cpu: Mesh, basis: Basis = Basis.IDENTITY) -> Dictionary:
	return {"source":source_mesh, "cpu":cpu, "basis":basis}

func settle(queue: RefCounted) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while queue._thread != null and Time.get_ticks_msec() < deadline:
		queue.poll()
		await process_frame
	queue.poll()
	check(queue._thread == null, "prefetch finishes and joins its single worker")

func cancel_queue(queue: RefCounted, worker: Thread = null) -> void:
	if worker == null: worker = queue._thread
	queue.cancel()
	var deadline := Time.get_ticks_msec() + 15000
	while worker != null and worker.is_started() and Time.get_ticks_msec() < deadline:
		queue.poll()
		await process_frame
	queue.poll()
	check(worker == null or not worker.is_started(), "cancellation drains the previous worker without leaving a started Thread")
	check(queue._thread == null and queue._ready.is_empty() and queue.profile.reserved_bytes == 0, "cancelled prefetch releases ready output and its complete reservation")

func queue_identity_and_budget() -> void:
	var cpu := indexed_source(); var painted := indexed_source(false, Vector3.UP * .37)
	var before := var_to_bytes(cpu.surfaces)
	var a := Basis(Vector3.UP, .61).scaled_local(Vector3(1.3, 1.1, .85))
	var b := a; b.x.x += .000001
	var queue := Prefetch.new()
	queue.item_limit = 16
	var wanted := [request(cpu, cpu), request(cpu, cpu), request(cpu, cpu, a), request(cpu, cpu, a), request(cpu, cpu, b), request(painted, painted, a)]
	check(queue.request(wanted, self), "one batch accepts duplicate instances, exact basis variants and a separate collision source")
	await settle(queue)
	check(queue._ready.size() == 4 and queue.profile.batches == 1, "six instance requests produce exactly four distinct outputs in one worker batch")
	check(queue.profile.peak_bytes > 0 and queue.profile.peak_bytes <= queue.byte_limit and queue.profile.reserved_bytes <= queue.byte_limit, "in-flight plus retained outputs remain inside the configured byte budget")
	check(cpu._collision_faces.is_empty() and painted._collision_faces.is_empty() and var_to_bytes(cpu.surfaces) == before, "worker expansion never writes shared lazy face caches or source arrays")
	check(queue.take(cpu, cpu, Basis(Vector3.UP, 1.23)).is_empty() and queue.take(cpu, painted, a).is_empty(), "unrequested basis or mismatched source/CPU pair cannot consume an old result")
	var held: PackedVector3Array = queue.take(cpu, cpu, Basis.IDENTITY)
	face_equal(held, cpu.collision_faces(), "local indexed result")
	check(queue.profile.reserved_bytes >= held.size() * 12, "consumer-owned faces stay charged until explicit release")
	held = PackedVector3Array(); queue.release(cpu, cpu, Basis.IDENTITY)
	face_equal(queue.take(cpu, cpu, a), Transform3D(a, Vector3.ZERO) * cpu.collision_faces(), "positive scale and yaw result")
	queue.release(cpu, cpu, a)
	face_equal(queue.take(cpu, cpu, b), Transform3D(b, Vector3.ZERO) * cpu.collision_faces(), "subtle exact-basis variant")
	queue.release(cpu, cpu, b)
	face_equal(queue.take(painted, painted, a), Transform3D(a, Vector3.ZERO) * painted.collision_faces(), "different painted collision source")
	queue.release(painted, painted, a)
	check(queue.take(cpu, cpu, a).is_empty() and queue.profile.reserved_bytes == 0, "taking each unique output transfers ownership once and releases all output reservations")
	await cancel_queue(queue)
	queue = Prefetch.new(); queue.byte_limit = cpu._collision_faces.size() * 12
	check(queue.request([request(cpu, cpu, a)], self), "one-output budget admits one exact face buffer")
	await settle(queue)
	held = queue.take(cpu, cpu, a)
	check(not held.is_empty() and not queue.request([request(cpu, cpu, b)], self), "consumer-owned output prevents another output from overcommitting the byte budget")
	held = PackedVector3Array(); queue.release(cpu, cpu, a)
	check(queue.request([request(cpu, cpu, b)], self), "released consumer budget admits the next exact basis")
	await settle(queue); await cancel_queue(queue)
	# Same source object with a replaced CPU capture must not use the old capture.
	var first := indexed_source(true); var owner: Mesh = first.restore()
	var first_capture: Mesh = owner.get_meta("ground_cpu_cache")
	queue = Prefetch.new(); check(queue.request([request(owner, first_capture)], self), "source/capture identity fixture starts")
	await settle(queue)
	var replacement := indexed_source(true, Vector3.UP * .63)
	owner.set_meta("ground_cpu_cache", replacement)
	check(queue.take(owner, replacement, Basis.IDENTITY).is_empty(), "same source resource with a different CPU identity cannot consume stale faces")
	check(queue.request([request(owner, replacement)], self), "new CPU identity can prepare its own replacement")
	await settle(queue)
	face_equal(queue.take(owner, replacement, Basis.IDENTITY), replacement.collision_faces(), "replacement CPU geometry")
	queue.release(owner, replacement, Basis.IDENTITY)
	await cancel_queue(queue)
	# A bounded batch may select only part of a request; it must never overrun.
	queue = Prefetch.new(); queue.item_limit = 2
	check(queue.request([request(cpu, cpu), request(cpu, cpu, a), request(cpu, cpu, b)], self), "bounded batch accepts a subset of distinct outputs")
	await settle(queue)
	check(queue._ready.size() > 0 and queue._ready.size() <= 2 and queue.profile.peak_bytes <= queue.byte_limit, "item and byte limits apply to actual retained outputs")
	await cancel_queue(queue)
	queue = Prefetch.new(); queue.byte_limit = 1
	check(not queue.request([request(cpu, cpu)], self), "one output larger than budget is rejected before thread creation")
	check(queue._thread == null and queue._ready.is_empty() and queue.profile.reserved_bytes == 0, "over-budget request leaves no work or reservation")
	await cancel_queue(queue)
	queue = Prefetch.new(); queue.thread_starter = fail_thread
	check(not queue.request([request(cpu, cpu)], self), "injected thread start failure reports no successful prefetch")
	check(queue._thread == null and queue._ready.is_empty() and queue.profile.reserved_bytes == 0 and queue.profile.start_failures == 1, "thread start failure releases every reservation and keeps no worker")
	await cancel_queue(queue)

static func fail_thread(_thread: Thread, _task: Callable) -> int:
	return ERR_CANT_CREATE

func source_lifetime() -> void:
	var queue := Prefetch.new(); var observer := LifetimeObserver.new()
	var mesh: Mesh = indexed_source()
	var material: Material = StandardMaterial3D.new(); mesh.materials.clear(); mesh.materials.append(material)
	var mesh_marker := LifetimeMarker.new(); mesh_marker.observer = observer
	var material_marker := LifetimeMarker.new(); material_marker.observer = observer
	mesh.set_meta("prefetch_lifetime_marker", mesh_marker); material.set_meta("prefetch_lifetime_marker", material_marker)
	mesh_marker = null; material_marker = null
	var mesh_ref:WeakRef = weakref(mesh); var material_ref:WeakRef = weakref(material)
	var rows := [request(mesh, mesh)]
	check(queue.request(rows, self), "lifetime batch admits source and its material")
	var worker: Thread = queue._thread
	rows.clear(); mesh = null; material = null
	check(mesh_ref.get_ref() != null and material_ref.get_ref() != null and observer.releases.is_empty(), "admitted lease strongly retains source resources after caller drops ownership")
	queue.cancel()
	check(mesh_ref.get_ref() != null and material_ref.get_ref() != null and observer.releases.is_empty(), "cancellation keeps source resources alive until the main-thread drainer joins")
	var replacement := indexed_source(true)
	check(not queue.request([request(replacement, replacement)], self), "cancelled undrained lease forbids another batch")
	await cancel_queue(queue, worker)
	check(mesh_ref.get_ref() == null and material_ref.get_ref() == null and observer.releases.size() == 2 and observer.releases.all(func(id: int): return id == OS.get_main_thread_id()), "source and material release only on main after worker drain")
	check(queue.request([request(replacement, replacement)], self), "drained cancellation permits a fresh batch")
	await settle(queue); await cancel_queue(queue)

func detached_snapshot_channels() -> void:
	var cpu := indexed_source(true)
	var original_vertices: PackedVector3Array = cpu.surfaces[0][Mesh.ARRAY_VERTEX]
	var original_indices: PackedInt32Array = cpu.surfaces[0][Mesh.ARRAY_INDEX]
	var snapshot: Dictionary = Prefetch._snapshot(request(cpu, cpu))
	if not check(not snapshot.is_empty(), "valid indexed CPU source creates an immutable worker snapshot"): return
	check(not is_same(snapshot.surfaces, cpu.surfaces) and not is_same(snapshot.surfaces[0], cpu.surfaces[0]), "snapshot detaches both the surface list and every channel-slot array")
	cpu.surfaces[0][Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(99, 99, 99)])
	cpu.surfaces[0][Mesh.ARRAY_INDEX] = PackedInt32Array([0, 0, 0])
	check(snapshot.surfaces[0][Mesh.ARRAY_VERTEX] == original_vertices and snapshot.surfaces[0][Mesh.ARRAY_INDEX] == original_indices, "replacing source channel slots cannot change the queued vertex/index snapshot")

func cancelled_consumer_budget() -> void:
	for with_worker in [false, true]:
		var cpu := indexed_source(); var next_cpu := indexed_source(false, Vector3.UP * .3)
		var queue := Prefetch.new()
		check(queue.request([request(cpu, cpu)], self), "consumer cancellation fixture starts")
		await settle(queue)
		var held: PackedVector3Array = queue.take(cpu, cpu, Basis.IDENTITY)
		var bytes := held.size() * 12
		var worker: Thread
		if with_worker:
			check(queue.request([request(next_cpu, next_cpu)], self), "another batch can run while an earlier output is consumed")
			worker = queue._thread
		queue.cancel()
		check(queue.profile.reserved_bytes >= bytes and not held.is_empty(), "cancel retains the live consumer's complete charge (worker=%s)" % with_worker)
		if with_worker:
			check(queue.profile.reserved_bytes > bytes and not queue.request([request(next_cpu, next_cpu)], self), "cancelled worker and live consumer remain charged and cannot admit overlapping work")
		var deadline := Time.get_ticks_msec() + 15000
		while worker != null and worker.is_started() and Time.get_ticks_msec() < deadline:
			queue.poll(); await process_frame
		queue.poll()
		check(worker == null or not worker.is_started(), "consumer cancellation drains its unrelated worker")
		check(queue.profile.reserved_bytes == bytes, "worker drain releases only worker bytes and preserves exactly the consumer bytes")
		queue.byte_limit = bytes
		check(not queue.request([request(next_cpu, next_cpu)], self), "a still-consumed cancelled output cannot be hidden to admit a new buffer")
		face_equal(held, cpu.collision_faces(), "consumer geometry survives queue cancellation")
		held = PackedVector3Array(); queue.release(cpu, cpu, Basis.IDENTITY)
		check(queue.profile.reserved_bytes == 0, "consumer release reaches zero after either cancellation path")
		await cancel_queue(queue)

func retire_partial_terrain() -> void:
	Preparer.prefetch_enabled = true
	var fixture := world(); var cpu := indexed_source()
	var pose := Transform3D(Basis(Vector3.UP, .52).scaled_local(Vector3(1.2, 1.1, .85)), Vector3.ZERO)
	var record := spec(cpu, "retire_partial", pose)
	var queue: RefCounted = fixture.preparer._face_prefetch
	check(queue.request([fixture.preparer.prefetch_request(record)], self), "retirement fixture prefetches its actual sliced collision request")
	await settle(queue)
	var ready: bool = fixture.preparer.prepare(record, fixture.host, 1)
	var terrain: RefCounted = fixture.preparer._terrain
	if not check(not ready and is_instance_valid(terrain._body) and terrain._thread == null and not terrain._face_lease.is_empty() and not terrain._faces.is_empty(), "one-microsecond slice budget creates a real partial body with a live consumer lease and no worker"):
		fixture.viewport.free(); return
	var body_ref:WeakRef = weakref(terrain._body)
	check(queue.profile.reserved_bytes == terrain._faces.size() * 12 * (12 if preload("res://scripts/world3d/collision_bvh_preparation.gd").active() else 1) and terrain._body.collision_layer == 0, "unpublished partial body remains noncolliding and its faces and BVH workspace stay charged")
	check(fixture.preparer.release_retired_sources([record]), "retiring a matching partial terrain releases its own consumer before checking source leases")
	check(body_ref.get_ref() == null and terrain._faces.is_empty() and terrain._face_lease.is_empty() and queue.profile.reserved_bytes == 0 and not record.has("prepared_body"), "retirement frees the incomplete body and faces without a permanently pinned source")
	check(fixture.preparer.release_retired_sources([record]), "repeated retirement is idempotent and cannot remain falsely busy")
	var published := await prepared(fixture, record)
	if published != null: geometry_equal(published, cpu, pose, "reprepared source after partial retirement")
	fixture.viewport.free(); await process_frame

func cancelled_and_replaced() -> void:
	var old_cpu := indexed_source(); var next_cpu := indexed_source(false, Vector3.UP * .4)
	var basis := Basis(Vector3.UP, .42).scaled_local(Vector3(1.2, 1.05, .9))
	var queue := Prefetch.new()
	check(queue.request([request(old_cpu, old_cpu, basis)], self), "cancellable prefetch starts")
	var worker: Thread = queue._thread
	queue.cancel()
	if worker != null and worker.is_started():
		check(not queue.request([request(next_cpu, next_cpu, basis)], self), "a cancelled but undrained batch cannot overlap a replacement worker")
	await cancel_queue(queue, worker)
	check(queue.take(old_cpu, old_cpu, basis).is_empty(), "cancelled destination cannot reinstall old output")
	check(queue.request([request(next_cpu, next_cpu, basis)], self), "new destination starts after old cancellation drains")
	await settle(queue)
	face_equal(queue.take(next_cpu, next_cpu, basis), Transform3D(basis, Vector3.ZERO) * next_cpu.collision_faces(), "new destination after cancellation")
	queue.release(next_cpu, next_cpu, basis)
	await cancel_queue(queue)
	queue = Prefetch.new()
	check(queue.request([request(old_cpu, old_cpu, basis)], self), "retired source fixture starts")
	var deadline := Time.get_ticks_msec() + 15000
	var released := queue.release_sources({old_cpu.get_instance_id():true})
	while not released and Time.get_ticks_msec() < deadline:
		queue.poll(); await process_frame
		released = queue.release_sources({old_cpu.get_instance_id():true})
	check(released and queue.take(old_cpu, old_cpu, basis).is_empty(), "retired collision source cannot expose a completed stale result")
	check(queue.profile.reserved_bytes == 0, "retiring a source releases its pending and ready output reservation")
	await cancel_queue(queue)

func full_spec(collision: Mesh, id: String, pose: Transform3D, visual: Mesh = null) -> Dictionary:
	var record := spec(collision, id, pose)
	if visual != null: record.mesh = visual
	var bounds: AABB = pose * collision.get_aabb()
	if visual != null: bounds = bounds.merge(pose * visual.get_aabb())
	record.chunk = Stream.chunk_key(pose.origin)
	record.chunk_min = Stream.chunk_key(bounds.position); record.chunk_max = Stream.chunk_key(bounds.end)
	return record

func initialize_stream_map(map: Node3D) -> void:
	# append_specs is an incremental operation on an existing stream index. A
	# fresh temporary map needs the same complete empty index as a real loader.
	map.set_meta("stream_library", [])
	var index: Dictionary = StreamIndex.build([])
	for key: String in index: map.set_meta(key, index[key])

func stream_world(mode: String) -> Dictionary:
	var viewport := SubViewport.new(); viewport.own_world_3d = true; viewport.disable_3d = true; root.add_child(viewport)
	var host := Node3D.new(); viewport.add_child(host)
	var map := Node3D.new(); host.add_child(map)
	initialize_stream_map(map)
	var preparer := CoveredLookaheadGate.new(); map.add_child(preparer)
	if mode == "budget": preparer._face_prefetch.byte_limit = 1
	elif mode == "thread_failure": preparer._face_prefetch.thread_starter = fail_thread
	var small := indexed_source(true); var big := indexed_source(); var paint := indexed_source(false, Vector3.UP * .37)
	var a := Basis(Vector3.UP, .61).scaled_local(Vector3(1.3, 1.1, .85))
	var b := Basis(Vector3.UP, 1.07).scaled_local(Vector3(1.3, 1.1, .85))
	var records := [
		full_spec(small, "ordinary_a", Transform3D(Basis.IDENTITY, Vector3(0, 0, 25))),
		full_spec(small, "ordinary_b", Transform3D(b, Vector3(0, 0, 40))),
		full_spec(big, "sliced_a", Transform3D(a, Vector3.ZERO)),
		full_spec(big, "sliced_b", Transform3D(a, Vector3(24, 0, 0))),
		full_spec(big, "sliced_other_basis", Transform3D(b, Vector3(48, 0, 0))),
		full_spec(paint, "painted_collision", Transform3D(a, Vector3(72, 0, 0)), big)]
	var appended: Dictionary = Stream.append_specs(map, records)
	check(appended.ok, "real WorldStream accepts ordinary, sliced, basis-varied and painted-source instances: " + str(appended.get("error", "")))
	check(Stream.set_entry_scope(map, AABB(Vector3(-16, -10, -16), Vector3(112, 30, 76))), "temporary map uses the actual covered-entry clip")
	return {"viewport":viewport, "host":host, "map":map, "preparer":preparer, "records":records, "mode":mode}

func finish_stream(fixture: Dictionary, enabled: bool) -> void:
	Preparer.prefetch_enabled = enabled
	if enabled and fixture.mode == "on":
		# Separate lookahead from application deterministically. These tiny meshes
		# may otherwise finish/cache before enough distinct outputs are consumed;
		# functional path coverage must not depend on OS worker scheduling speed.
		fixture.preparer.hold_application = true
		Stream.sync(fixture.map, fixture.host, Vector3.ZERO, Stream.LOAD_BUDGET)
		check(fixture.preparer._face_prefetch.profile.batches > 0 and fixture.map.get_meta("stream_bodies", {}).is_empty(), "real covered Stream lookahead starts before the test releases collision publication")
		await settle(fixture.preparer._face_prefetch)
		check(fixture.preparer._face_prefetch._ready.size() >= 2, "actual covered lookahead prepares multiple distinct collision outputs")
		print("STREAM_PREFETCH_LOOKAHEAD ", JSON.stringify(fixture.preparer._face_prefetch.profile))
		fixture.preparer.hold_application = false
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		Stream.sync(fixture.map, fixture.host, Vector3.ZERO, Stream.LOAD_BUDGET)
		if stream_is_ready(fixture.map): break
		await process_frame
	check(stream_is_ready(fixture.map), "real loading WorldStream reaches visual and collision readiness")
	check(fixture.map.get_meta("stream_bodies", {}).size() == fixture.records.size(), "every requested ordinary and sliced collision body is actually published")
	print("STREAM_PREFETCH_RESULT mode=", fixture.mode, " profile=", JSON.stringify(fixture.preparer._face_prefetch.profile))
	var bodies: Dictionary = fixture.map.get_meta("stream_bodies", {})
	for record: Dictionary in fixture.records:
		var body: StaticBody3D = bodies.get(record.uuid)
		if check(body != null, "published body exists: " + record.uuid): geometry_equal(body, record.collision_mesh, record.transform, record.uuid)

func stream_is_ready(map:Node)->bool:
	if map.has_meta("entry_stream_clip"):return Stream.entry_scope_ready(map)
	return map.get_meta("stream_chunk",Vector2i(2147483647,2147483647))==Vector2i.ZERO

func unclipped_loading()->void:
	var before:=stream_world("off");Stream.clear_entry_scope(before.map)
	await finish_stream(before,false)
	var after:=stream_world("on");Stream.clear_entry_scope(after.map)
	await finish_stream(after,true)
	check(after.preparer._face_prefetch.profile.hits>0,"unclipped loading consumes bounded batch results instead of one worker per mesh")
	compare_streams(before,after,"unclipped loading exact collision")
	await physics_equivalence(before,after)
	before.viewport.free();after.viewport.free()

func pending_batch_owns_extraction()->void:
	for sliced:bool in [false,true]:
		var host:=Node3D.new();root.add_child(host)
		var preparer:=Preparer.new();host.add_child(preparer)
		var gate:=DelayedBatch.new();preparer._face_prefetch.thread_starter=gate.start
		var cpu:=indexed_source(not sliced)
		var record:=full_spec(cpu,"pending_sliced" if sliced else "pending_small",Transform3D.IDENTITY)
		check(preparer._face_prefetch.request([request(cpu,cpu)],self),"admit delayed exact face producer, sliced="+str(sliced))
		check(not preparer.prepare(record,host) and preparer._thread==null and preparer._terrain._thread==null and preparer._terrain._body==null and preparer._terrain._spec.is_empty(),"pending batch keeps readiness false without duplicate extraction or empty body, sliced="+str(sliced))
		gate.release();await settle(preparer._face_prefetch)
		var deadline:=Time.get_ticks_msec()+15000
		while not preparer.prepare(record,host) and Time.get_ticks_msec()<deadline:await process_frame
		check(preparer.face_worker_starts==0 and preparer._terrain.face_expansions==0 and preparer._face_prefetch.profile.hits==1,"exact pending output is consumed once without a fallback worker, sliced="+str(sliced))
		if sliced:
			check(is_instance_valid(record.get("prepared_body")),"sliced pending result produces a complete disabled body")
			if is_instance_valid(record.get("prepared_body")):geometry_equal(record.prepared_body,cpu,Transform3D.IDENTITY,"pending sliced exact faces")
		else:face_equal(record.shape.get_faces(),cpu.collision_faces(),"pending ordinary exact faces")
		await cancel_queue(preparer._face_prefetch)
		host.free()

func compare_streams(baseline: Dictionary, candidate: Dictionary, label: String) -> void:
	var before: Dictionary = baseline.map.get_meta("stream_bodies", {})
	var after: Dictionary = candidate.map.get_meta("stream_bodies", {})
	for id: String in before:
		if not check(after.has(id), label + ": matching body " + id): continue
		face_equal(world_faces(after[id]), world_faces(before[id]), label + " " + id)

func physics_equivalence(baseline: Dictionary, candidate: Dictionary) -> void:
	var pose: Transform3D = baseline.records[2].transform
	await physics_frame; await physics_frame; await process_frame
	var before := queries(baseline, pose); var after := queries(candidate, pose)
	check(before.rays.floor.hit and not before.rays.hole.hit and not before.rays.door_front.hit and not before.rays.door_back.hit and (before.rays.wall_front.hit or before.rays.wall_back.hit), "prefetch-disabled Stream has a real floor, hole, doorway and solid wall")
	var rays_equal := true; var spheres_equal := true
	for label: String in before.rays:
		rays_equal = rays_equal and before.rays[label].hit == after.rays[label].hit
		if before.rays[label].hit and after.rays[label].hit: rays_equal = rays_equal and before.rays[label].position.distance_to(after.rays[label].position) < .0001
		for index in 2: spheres_equal = spheres_equal and absf(before.spheres[label][index] - after.spheres[label][index]) < .002
	check(rays_equal, "prefetch on/off real rays preserve holes, doorways and exact hit locations")
	check(spheres_equal, "prefetch on/off real sphere motion fractions agree within 0.002")
	var start: Vector3 = pose * Vector3(-3, 0, -2) + Vector3.UP * .902
	var first := player(baseline.host, start); var second := player(candidate.host, start)
	await physics_frame; await physics_frame
	var floor_equal := true; var motion_equal := true; var grounded := 0
	for tick in 24:
		await physics_frame
		var velocity_: Vector3 = pose.basis * Vector3(.3, 0, 0) + Vector3.DOWN * .5
		first.velocity = velocity_; second.velocity = velocity_
		first.move_and_slide(); second.move_and_slide()
		floor_equal = floor_equal and first.is_on_floor() == second.is_on_floor()
		motion_equal = motion_equal and first.global_position.distance_to(second.global_position) < .002
		if first.is_on_floor() and second.is_on_floor(): grounded += 1
	check(floor_equal and grounded >= 23, "real capsule keeps the same grounded states with prefetch enabled")
	check(motion_equal, "real capsule trajectory stays within 2 mm of prefetch disabled")
	first.free(); second.free()

func stream_integration() -> void:
	var baseline := stream_world("off"); await finish_stream(baseline, false)
	check(baseline.preparer._face_prefetch.profile.batches == 0, "disabled control uses no prefetch batch")
	var candidate := stream_world("on"); await finish_stream(candidate, true)
	var profile: Dictionary = candidate.preparer._face_prefetch.profile
	check(profile.batches > 0 and profile.hits >= 2, "actual WorldStream consumes multiple prepared outputs from the batch path")
	check(profile.peak_bytes <= candidate.preparer._face_prefetch.byte_limit, "actual Stream prefetch respects its retained output budget")
	compare_streams(baseline, candidate, "prefetch enabled")
	await physics_equivalence(baseline, candidate)
	for mode in ["budget", "thread_failure"]:
		var fallback := stream_world(mode); await finish_stream(fallback, true)
		check(fallback.preparer._face_prefetch.profile.hits == 0, mode + ": rejected prefetch falls back without claiming a hit")
		if mode == "thread_failure": check(fallback.preparer._face_prefetch.profile.start_failures > 0, "real Stream exercised injected prefetch thread-start failure")
		compare_streams(baseline, fallback, mode + " fallback")
		fallback.viewport.free()
	baseline.viewport.free(); candidate.viewport.free()
	await process_frame

func stream_exit_joins() -> void:
	var fixture := stream_world("on")
	Preparer.prefetch_enabled = true
	var queue: RefCounted = fixture.preparer._face_prefetch
	var source_mesh: Mesh = fixture.records[2].collision_mesh
	check(queue.request([request(source_mesh, source_mesh, fixture.records[2].transform.basis)], self), "scene-exit fixture owns an admitted batch")
	var worker: Thread = queue._thread
	fixture.viewport.free()
	var deadline := Time.get_ticks_msec() + 15000
	while worker != null and worker.is_started() and Time.get_ticks_msec() < deadline:
		queue.poll(); await process_frame
	queue.poll()
	check(worker == null or not worker.is_started(), "map exit joins or drains all admitted prefetch workers")
	check(queue._ready.is_empty() and queue.profile.reserved_bytes == 0, "map exit cannot retain unused face output or reservations")

func stream_destination_switch() -> void:
	var fixture := stream_world("on")
	var destination_mesh := indexed_source(false, Vector3.UP * .2)
	var destination_pose := Transform3D(Basis(Vector3.UP, .93).scaled_local(Vector3(1.2, 1.1, .9)), Vector3(512, 0, 0))
	var destination := full_spec(destination_mesh, "new_destination", destination_pose)
	check(Stream.append_specs(fixture.map, [destination]).ok, "destination-switch fixture appends a separate distant collision source")
	Preparer.prefetch_enabled = true
	Stream.sync(fixture.map, fixture.host, Vector3.ZERO, Stream.LOAD_BUDGET)
	check(Stream.set_entry_scope(fixture.map, AABB(Vector3(496, -10, -16), Vector3(48, 30, 48))), "covered target switches while the previous stream plan may be unfinished")
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		Stream.sync(fixture.map, fixture.host, destination_pose.origin, Stream.LOAD_BUDGET)
		if Stream.entry_scope_ready(fixture.map): break
		await process_frame
	check(Stream.entry_scope_ready(fixture.map), "changed entry target reaches readiness without waiting for unrelated old geometry")
	var body: StaticBody3D = fixture.map.get_meta("stream_bodies", {}).get(destination.uuid)
	if check(body != null, "new destination publishes its own collision body"):
		geometry_equal(body, destination_mesh, destination_pose, "changed Stream destination")
	var queue: RefCounted = fixture.preparer._face_prefetch
	queue.poll()
	var current_only := true
	for row: Dictionary in queue._leases.values(): current_only = current_only and row.source == destination_mesh
	check(current_only, "changed target retains no ready or consumer lease from the old request window")
	fixture.viewport.free(); await process_frame

func stream_budget_mode_switch() -> void:
	var viewport := SubViewport.new(); viewport.own_world_3d = true; viewport.disable_3d = true; root.add_child(viewport)
	var host := Node3D.new(); viewport.add_child(host)
	var map := Node3D.new(); host.add_child(map)
	initialize_stream_map(map)
	var preparer := Preparer.new(); map.add_child(preparer)
	var cpu := indexed_source()
	var pose := Transform3D(Basis(Vector3.UP, .44).scaled_local(Vector3(1.2, 1.1, .9)), Vector3.ZERO)
	var record := full_spec(cpu, "mode_switch", pose)
	check(Stream.append_specs(map, [record]).ok and Stream.set_entry_scope(map, AABB(Vector3(-16, -10, -16), Vector3(32, 30, 32))), "budget-mode fixture enters the real Stream plan")
	# Let the real Stream own target/cursor/index setup, then seed a deterministic
	# one-slice partial state using its own preparer. This does not depend on the
	# machine taking more than 24 ms to cook a tiny synthetic collision mesh.
	Preparer.prefetch_enabled = false
	Stream.sync(map, host, Vector3.ZERO, Stream.LOAD_BUDGET)
	var terrain: RefCounted = preparer._terrain
	var deadline := Time.get_ticks_msec() + 15000
	while terrain._thread != null and terrain._thread.is_alive() and Time.get_ticks_msec() < deadline: await process_frame
	preparer.cancel_pending()
	Preparer.prefetch_enabled = true
	var queue: RefCounted = preparer._face_prefetch
	check(queue.request([preparer.prefetch_request(record)], self), "same-target loading prepares an owned face buffer")
	await settle(queue)
	var ready: bool = preparer.prepare(record, host, 1)
	if not check(not ready and is_instance_valid(terrain._body) and not terrain._face_lease.is_empty(), "same-target mode switch begins with a legitimate partial terrain body"):
		viewport.free(); return
	var body_id: int = terrain._body.get_instance_id()
	var bytes: int = terrain._faces.size() * 12 * (12 if preload("res://scripts/world3d/collision_bvh_preparation.gd").active() else 1)
	Stream.sync(map, host, Vector3.ZERO, Stream.FRAME_BUDGET)
	var body: StaticBody3D = map.get_meta("stream_bodies", {}).get(record.uuid)
	var surviving: Node = body if body != null else record.get("prepared_body", terrain._body)
	check(is_instance_valid(surviving) and surviving.get_instance_id() == body_id, "LOAD to interactive at the same target preserves the original partial body instead of restarting it")
	if not terrain._faces.is_empty(): check(queue.profile.reserved_bytes == bytes, "interactive mode keeps a still-partial consumer fully charged")
	else: check(queue.profile.reserved_bytes == 0, "finished slices release their face charge even if publication awaits another frame")
	deadline = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		Stream.sync(map, host, Vector3.ZERO, Stream.LOAD_BUDGET)
		if Stream.entry_scope_ready(map): break
		await process_frame
	body = map.get_meta("stream_bodies", {}).get(record.uuid)
	if check(Stream.entry_scope_ready(map) and is_instance_valid(body) and body.get_instance_id() == body_id, "interactive back to LOAD completes and publishes that same body"):
		geometry_equal(body, cpu, pose, "LOAD/interactive/LOAD same-target geometry")
	queue.poll()
	check(queue.profile.reserved_bytes == 0, "completed mode-switch body releases its consumer reservation")
	viewport.free(); await process_frame

func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("collision face prefetch timeout"); quit(2))
	if DisplayServer.get_name() == "headless": push_error("Private-desktop GPU required"); quit(2); return
	var previous := Preparer.prefetch_enabled
	var slicing := Preparer.terrain_slicing_enabled; Preparer.terrain_slicing_enabled = true
	await queue_identity_and_budget()
	detached_snapshot_channels()
	await cancelled_consumer_budget()
	await retire_partial_terrain()
	await source_lifetime()
	await cancelled_and_replaced()
	await stream_integration()
	await unclipped_loading()
	await pending_batch_owns_extraction()
	await stream_destination_switch()
	await stream_budget_mode_switch()
	await stream_exit_joins()
	Preparer.prefetch_enabled = previous; Preparer.terrain_slicing_enabled = slicing
	await process_frame
	print("COLLISION_FACE_PREFETCH checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
