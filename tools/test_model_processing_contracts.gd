extends SceneTree
const Job = preload("res://scripts/world_editor/load_job.gd")
## CPU-only contracts. Actual texture binding/renderer retirement and full town
## integration remain in the deferred graphics/HTTP acceptance batch.
const Compiled = preload("res://scripts/world3d/compiled_asset_cache.gd")
const Preparation = preload("res://scripts/world3d/model_parse_preparation.gd")
const Queue = preload("res://scripts/world_editor/load_preparation_queue.gd")
const Textures = preload("res://scripts/world3d/model_texture_cache.gd")
const Drainer = preload("res://scripts/world3d/asset_worker_drainer.gd")
var failures := 0
var checks := 0
var deaths: Array = []

class DeathProbe extends Resource:
	var events: Array
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and events != null: events.append(OS.get_thread_caller_id())

func _initialize() -> void: run.call_deferred()
func check(condition: bool, label_: String) -> void:
	checks += 1
	if not condition: failures += 1
	print("PASS " if condition else "FAIL ", label_)

func failed_native(reason: String) -> Dictionary:
	var packed := PackedScene.new()
	var probe := DeathProbe.new()
	probe.events = deaths
	packed.set_meta("probe", probe)
	return Compiled._allocated_miss(reason, Time.get_ticks_usec(), packed)

func worker_miss() -> Dictionary:
	var packet := failed_native("source_changed_during_read")
	packet.worker_disposal_refused = not Compiled.dispose_miss(packet)
	return packet

func owned_legacy() -> Dictionary:
	return Preparation._owned_cache_miss(failed_native("source_changed_during_read"))

func run() -> void:
	var main_id := OS.get_main_thread_id()
	var worker := Thread.new()
	check(worker.start(worker_miss) == OK, "worker starts")
	while worker.is_alive(): await process_frame
	var packet: Dictionary = worker.wait_to_finish()
	check(packet.worker_disposal_refused and deaths.is_empty(), "worker hands off live failed allocation without disposal")
	check(Compiled.dispose_miss(packet), "main disposes failed native")
	check(deaths == [main_id], "failed native retires on main only")
	check(packet.reason == "source_changed_during_read" and not packet.hit and not packet.has("retained_resources"), "miss diagnostics survive retirement")
	check(Compiled.dispose_miss(packet), "resource-free miss disposal is idempotent")

	deaths.clear()
	var operation := Preparation.new()
	operation.native_footprints_enabled = false
	operation.inflight_byte_limit = 64
	operation.memory_estimator = func(_path): return {"estimated_bytes":64,"exclusive":false,"known":true}
	operation.eligibility_checker = func(_path): return true
	operation.cache_reader = func(_path): return failed_native("source_changed_during_read")
	var result := operation.run(["virtual-source"], func(_path): return {"error":OK,"raw_result":true}, 1)
	check(result.error == OK and result.entries.size() == 1 and result.entries[0].raw_result, "legacy source miss safely retries raw")
	check(result.retired_native_estimate_bytes == 64 and result.result_resident_estimate_bytes == 128, "initial coordinator charges quarantined native plus raw separately")
	check(deaths.is_empty(), "initial coordinator keeps quarantine until caller retirement")
	Drainer.dispose_result(result.entries[0])
	check(deaths == [main_id], "quarantined allocation retired by main")

	deaths.clear()
	operation = Preparation.new()
	operation.native_footprints_enabled = false
	operation.memory_estimator = func(_path): return {"estimated_bytes":64,"exclusive":false,"known":true}
	operation.eligibility_checker = func(_path): return true
	operation.cache_reader = func(_path): return failed_native("invalid_product")
	var raw_count := [0]
	result = operation.run(["invalid-native"], func(_path): raw_count[0] += 1; return {"error":OK}, 1)
	check(result.error == ERR_INVALID_DATA and raw_count[0] == 0, "resource-bearing schema failure cannot launch raw under old lease")
	check(deaths.is_empty(), "fatal allocation is retained too")
	Drainer.dispose_result(result.entries[0])
	check(deaths == [main_id], "fatal allocation retired by main")

	deaths.clear()
	var queue := Queue.new()
	root.add_child(queue)
	queue.worker_limit = 1
	queue.byte_limit = 64
	queue.enqueue("model", owned_legacy, {"estimated_bytes":64,"exclusive":false,"stage":"legacy_model"}, "model")
	queue.demand("model")
	while not queue.is_ready("model"): await process_frame
	var owned: Dictionary = queue.acquire("model")
	check(Job._native_result_action({"source_sha":"a".repeat(64)},owned)!="ready", "editor rejects conversion-only retained source retry")
	check(queue.ledger.reserved_bytes == 64 and deaths.is_empty(), "failed ready allocation retains lease")
	check(not queue.has_method("retry_as_raw"), "editor has no native-to-source retry route")
	queue.release("model")
	check(owned.is_empty() and deaths == [main_id] and queue.ledger.reserved_bytes == 0, "all failed native aliases clear on main before byte credit returns")
	queue.cancel(); queue.free()
	var malformed := {"error":ERR_BUSY,"legacy_native_retry":true,"cache_reason":"source_changed_during_read","retained_resources":[]}
	check(not Preparation.is_legacy_source_retry(malformed), "resource-free forged retry rejected")
	malformed = owned_legacy(); malformed.fallback_required = true
	check(not Preparation.is_legacy_source_retry(malformed), "mixed fallback/retained control rejected")
	Drainer.dispose_result(malformed)
	malformed = owned_legacy(); malformed.legacy_native_retry = 1
	check(not Preparation.is_legacy_source_retry(malformed), "integer legacy retry marker rejected")
	Drainer.dispose_result(malformed)
	malformed = owned_legacy(); malformed.retained_resources[0].hit = 0
	check(not Preparation.is_legacy_source_retry(malformed), "integer native hit marker rejected")
	Drainer.dispose_result(malformed)
	deaths.clear()
	operation.cache_reader = func(_path): return {"hit":true,"retained_resources":[failed_native("invalid_product")]}
	var invalid_hit: Dictionary = operation._cache_stage("invalid-hit", "", {})
	check(invalid_hit.error == ERR_INVALID_DATA and deaths.is_empty(), "malformed hit keeps nested allocations owned")
	Drainer.dispose_result(invalid_hit)
	check(deaths == [main_id], "malformed hit resources retire on main")

	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.6, 1.0))
	var copy := image.duplicate() as Image
	check(Textures.pixel_key(image) == Textures.pixel_key(copy), "identical image layouts and pixels share identity")
	copy.set_pixel(0, 0, Color.WHITE)
	check(Textures.pixel_key(image) != Textures.pixel_key(copy), "one changed pixel invalidates identity")
	copy = image.duplicate() as Image; copy.convert(Image.FORMAT_RGB8)
	check(Textures.pixel_key(image) != Textures.pixel_key(copy), "channel layout is part of identity")
	copy = image.duplicate() as Image; copy.generate_mipmaps()
	check(Textures.pixel_key(image) != Textures.pixel_key(copy), "mip layout is part of identity")
	check(Textures.pixel_key(null).is_empty(), "empty image has no trusted identity")
	var visual := MeshInstance3D.new()
	var geometry := BoxMesh.new()
	var base_material := StandardMaterial3D.new()
	var slot_material := StandardMaterial3D.new()
	var override_material := StandardMaterial3D.new()
	var overlay_material := StandardMaterial3D.new()
	var pass_material := StandardMaterial3D.new()
	geometry.material = base_material; visual.mesh = geometry
	visual.set_surface_override_material(0, slot_material)
	visual.material_override = override_material; visual.material_overlay = overlay_material
	base_material.next_pass = pass_material; overlay_material.next_pass = pass_material
	var reachable := Textures._materials(visual)
	check(reachable.has(base_material) and reachable.has(slot_material), "material traversal retains mesh original behind a surface override")
	check(reachable.has(override_material) and reachable.has(overlay_material) and reachable.has(pass_material) and reachable.size() == 5, "material traversal includes overlay and shared next pass exactly once")
	check(geometry.material == base_material and visual.material_override == override_material and visual.get_surface_override_material(0) == slot_material, "material traversal leaves independent material bindings unchanged")
	visual.free(); reachable.clear()
	Textures._textures.clear()
	var first := ImageTexture.new()
	var second := ImageTexture.new()
	check(Textures._remember("same", first) == first and Textures._remember("same", second) == first, "weak pool returns shared texture owner")
	var weak: WeakRef = weakref(first)
	first = null
	check(weak.get_ref() == null, "pool does not extend texture lifetime")
	check(Textures._remember("same", second) == second, "expired pool owner replaced")
	for index in Textures.MAX_KEYS + 30: Textures._remember(str(index), second)
	check(Textures._textures.size() <= Textures.MAX_KEYS, "texture identity pool bounded")
	Textures._textures.clear(); second = null
	print("MODEL PROCESSING CONTRACTS: ", checks - failures, " PASS, ", failures, " FAIL")
	quit(0 if failures == 0 else 1)
