extends SceneTree
## CPU ownership tests: no source import, file writes, mesh surfaces or texture
## uploads. Empty native resources use the headless renderer; real Native.read
## and independently retained GPU textures belong to the separate GPU fixture.
const Ownership = preload("res://scripts/world_editor/prepared_model_ownership.gd")
const Assets = preload("res://scripts/world_editor/asset_library.gd")
const BYTES := 67108864
var passed := 0
var failures := 0

class RetirementProbe extends "res://scripts/world_editor/prepared_model_ownership.gd":
	var sync_observations: Array = []
	func _synchronize_retirement() -> void:
		sync_observations.append({"bytes":report().published_envelope_bytes, "main":OS.get_thread_caller_id() == OS.get_main_thread_id()})
		super._synchronize_retirement()

class ScriptedResource extends Resource:
	pass

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1; print("PASS ", label)
	else: failures += 1; push_error("FAIL " + label)

func make_tracker() -> Node:
	var tracker := RetirementProbe.new()
	root.add_child(tracker)
	tracker.set_process(false)
	return tracker

func candidate() -> Dictionary:
	# Deliberately nonexistent paths: ownership transfer must never rehash/read a
	# source or rewrite the reader-completion contract during publication.
	return {"source_path":"res://__ownership_cpu_only__/model.glb", "source_sha":"a".repeat(64), "payload_sha":"b".repeat(64), "generator":"c".repeat(64), "product":"res://__ownership_cpu_only__/" + "b".repeat(64) + ".scn", "bytes":123, "estimated_bytes":BYTES, "resident_bytes":BYTES, "exclusive":false}

func packet(resource: Resource = null) -> Dictionary:
	var scene := Node3D.new()
	scene.name = "OwnershipFixture"
	if resource != null: scene.set_meta("fixture_resource", resource)
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "CPU scene packs without importing a source")
	scene.free()
	packed.set_meta("compiled_asset_validated", true)
	return {"error":OK, "packed":packed, "compiled":true, "source_digest":"a".repeat(64), "compiled_payload_bytes":123, "cache_us":1, "elapsed_us":1}

func publish(tracker: Node, identity: Dictionary, result: Dictionary) -> Dictionary:
	var before: Dictionary = tracker.preflight(identity, result, BYTES)
	check(before.get("ok", false), "closed native graph passes preflight")
	if not before.get("ok", false): return before
	check(Assets.cache_packed(identity.source_path, result.packed, identity.source_sha), "real AssetLibrary cache accepts the exact source identity")
	var adopted: Dictionary = tracker.adopt(before.ticket)
	check(adopted.get("ok", false), "publication transfers ownership into the baseline")
	tracker.set_process(false)
	return before

func preflight_is_weak_and_side_effect_free() -> void:
	var tracker := make_tracker()
	var identity := candidate()
	var result := packet()
	var packed_ref: WeakRef = weakref(result.packed)
	var metadata: Array = result.packed.get_meta_list()
	var before: Dictionary = tracker.preflight(identity, result, BYTES)
	check(before.get("ok", false) and before.get("weak_owner_count", 0) == 2, "minimal graph covers PackedScene plus its SceneState")
	check(result.packed.get_meta_list() == metadata and not result.packed.has_meta("_rmmo_source_digest"), "preflight adds no serialization metadata")
	check(not Assets.has_cached_scene(identity.source_path) and tracker.report().published_envelope_bytes == 0, "preflight neither publishes nor transfers byte ownership")
	check(not tracker.adopt(before.ticket).ok, "adoption before cache publication is rejected")
	result.clear()
	check(packed_ref.get_ref() == null, "an abandoned preflight ticket does not retain PackedScene")
	check(not tracker.adopt(before.ticket).ok, "a ticket with an expired resource cannot transfer ownership")
	check(tracker.collect_retired().retired == 0 and tracker.sync_observations.is_empty(), "unpublished resources never cause published retirement accounting")
	before.clear(); tracker.free()

func exact_publication_and_identity() -> void:
	var tracker := make_tracker()
	var other := make_tracker()
	var identity := candidate()
	var result := packet()
	var before: Dictionary = tracker.preflight(identity, result, BYTES)
	check(not other.adopt(before.ticket).ok and not tracker.adopt(Ownership.Ticket.new()).ok, "foreign and unissued tickets fail closed")
	check(not Assets.cache_packed(identity.source_path, result.packed, "invalid"), "invalid source identity is rejected by the real cache")
	check(not tracker.adopt(before.ticket).ok and tracker.report().entries == 0, "failed cache publication leaves baseline ownership unchanged")
	check(Assets.cache_packed(identity.source_path, result.packed, identity.source_sha), "cache stamps the verified digest before handoff")
	var first: Dictionary = tracker.adopt(before.ticket)
	var again: Dictionary = tracker.adopt(before.ticket)
	check(first.ok and not first.reused and again.ok and again.reused and first.entry_id == again.entry_id, "reusing an issued ticket is idempotent for one allocation")
	var second_ticket: Dictionary = tracker.preflight(identity, result, BYTES)
	check(tracker.adopt(second_ticket.ticket).reused and tracker.report().published_envelope_bytes == BYTES, "a second ticket for the same allocation never double-charges")
	var changed := identity.duplicate(); changed.source_path += ".different"
	var conflict: Dictionary = tracker.preflight(changed, result, BYTES)
	check(conflict.ok and not tracker.adopt(conflict.ticket).ok and tracker.report().entries == 1, "one allocation cannot acquire a conflicting frozen identity")
	# The input dictionaries may go away; the ticket retains scalar identity and
	# weak owners only. Cached resources must remain fully charged until eviction.
	identity.clear(); result.clear()
	check(tracker.collect_retired().retired == 0 and tracker.report().published_envelope_bytes == BYTES, "a cache-owned allocation remains charged after caller dictionaries disappear")
	Assets.evict_cached_scene(candidate().source_path)
	check(tracker.collect_retired().retired == 1 and tracker.report().published_envelope_bytes == 0, "cache eviction permits retirement only after the last resource dies")
	check(tracker.sync_observations.size() == 1 and tracker.sync_observations[0] == {"bytes":BYTES, "main":true}, "main-thread renderer sync observes the full charge before decrement")
	before.clear(); second_ticket.clear(); conflict.clear(); tracker.free(); other.free()

func scene_state_outlives_packed() -> void:
	var tracker := make_tracker()
	var identity := candidate()
	var result := packet()
	var state: SceneState = result.packed.get_state()
	var packed_ref: WeakRef = weakref(result.packed)
	var state_ref: WeakRef = weakref(state)
	var ticket: Dictionary = publish(tracker, identity, result)
	result.clear(); Assets.evict_cached_scene(identity.source_path)
	check(packed_ref.get_ref() == null and state_ref.get_ref() != null, "SceneState can outlive its original PackedScene")
	check(tracker.collect_retired().retired == 0 and tracker.report().published_envelope_bytes == BYTES, "a separately held SceneState prevents premature byte release")
	state = null
	check(state_ref.get_ref() == null and tracker.collect_retired().retired == 1, "SceneState release finishes the original allocation lifetime")
	ticket.clear(); tracker.free()

func resource_fixture() -> Dictionary:
	var mesh := ArrayMesh.new()
	var shadow := ArrayMesh.new()
	mesh.shadow_mesh = shadow
	var material := StandardMaterial3D.new()
	var next_material := StandardMaterial3D.new()
	var texture := ImageTexture.new() # No create_from_image/upload/get_image.
	var image := Image.new()
	material.next_pass = next_material
	material.albedo_texture = texture
	material.set_meta("image_owner", image)
	mesh.set_meta("shared_materials", [material, material])
	return {"packet":packet(mesh), "escaped":next_material, "mesh_ref":weakref(mesh), "texture_ref":weakref(texture), "image_ref":weakref(image)}

func independent_child_keeps_full_envelope() -> void:
	var tracker := make_tracker()
	var identity := candidate()
	var fixture := resource_fixture()
	var result: Dictionary = fixture.packet
	var packed_ref: WeakRef = weakref(result.packed)
	var ticket: Dictionary = publish(tracker, identity, result)
	check(ticket.get("weak_owner_count", 0) == 8, "closed graph covers shadow mesh, material next_pass, texture, image and deduplicated shared owners")
	var escaped: StandardMaterial3D = fixture.escaped
	fixture.erase("escaped"); result.clear(); fixture.erase("packet")
	Assets.evict_cached_scene(identity.source_path)
	check(packed_ref.get_ref() == null and fixture.mesh_ref.get_ref() == null, "original PackedScene and mesh die while a child material is independently retained")
	check(fixture.texture_ref.get_ref() == null and fixture.image_ref.get_ref() == null, "tracker does not pin otherwise dead textures or image metadata")
	check(tracker.collect_retired().retired == 0 and tracker.report().published_envelope_bytes == BYTES, "one escaped material retains the complete conservative allocation envelope")
	escaped = null
	check(tracker.collect_retired().retired == 1 and tracker.report().weak_owner_count == 0, "last child owner release retires the complete graph")
	check(tracker.sync_observations.size() == 1 and tracker.sync_observations[0].bytes == BYTES, "child-owner retirement synchronizes before releasing its envelope")
	ticket.clear(); fixture.clear(); tracker.free()

func independent_allocations_and_bounded_retirement() -> void:
	var tracker := make_tracker()
	var identity := candidate()
	var first := packet()
	var second := packet()
	var first_ticket: Dictionary = publish(tracker, identity, first)
	var second_ticket: Dictionary = publish(tracker, identity, second)
	check(first.packed != second.packed and tracker.report().entries == 2 and tracker.report().published_envelope_bytes == BYTES * 2, "same source/product identity never merges distinct native allocations")
	first.clear(); second.clear(); Assets.evict_cached_scene(identity.source_path)
	check(tracker.collect_retired(0).retired == 0 and tracker.report().entries == 2, "zero retirement allowance performs no lifetime-accounting work")
	check(tracker.collect_retired(1).retired == 1 and tracker.report().entries == 1, "retirement respects its per-call entry bound")
	check(tracker.collect_retired(1).retired == 1 and tracker.report().published_envelope_bytes == 0, "a subsequent bounded scan retires the remaining allocation")
	check(tracker.sync_observations.size() == 2 and tracker.sync_observations[0].bytes == BYTES * 2 and tracker.sync_observations[1].bytes == BYTES, "each retirement batch synchronizes against the pre-decrement baseline")
	var report: Dictionary = tracker.report()
	check(report.peak_published_envelope_bytes == BYTES * 2 and report.retired_envelope_bytes == BYTES * 2 and report.retired_entries == 2, "lifetime diagnostics distinguish current, peak and retired envelopes")
	first_ticket.clear(); second_ticket.clear(); tracker.free()

func fail_closed_graph_and_packet() -> void:
	var tracker := make_tracker()
	var identity := candidate()
	var result := packet()
	for change: Dictionary in [{"error":ERR_BUSY}, {"error":0.0}, {"compiled":1}, {"compiled":false}, {"source_digest":"d".repeat(64)}, {"compiled_payload_bytes":124}, {"compiled_payload_bytes":123.0}, {"packed":null}, {"scene":null}, {"retained_resources":[]}, {"private_preparation":{}}, {"fallback_required":false}, {"native_source_retry":false}, {"unknown_owner":null}, {"elapsed_us":-1}]:
		var bad := result.duplicate(); bad.merge(change, true)
		check(not tracker.preflight(identity, bad, BYTES).ok, "invalid or additional packet ownership rejects: " + str(change.keys()[0]))
	for change: Dictionary in [{"source_sha":"bad"}, {"payload_sha":"bad"}, {"generator":"bad"}, {"product":"wrong.scn"}, {"bytes":124}, {"estimated_bytes":BYTES - 1}, {"resident_bytes":BYTES - 1}]:
		var bad := identity.duplicate(); bad.merge(change, true)
		check(not tracker.preflight(bad, result, BYTES).ok, "candidate identity or envelope mismatch rejects: " + str(change.keys()[0]))
	check(not tracker.preflight(identity, result, BYTES - 1).ok, "handoff cannot discount the charged native peak envelope")
	result.packed.set_meta("compiled_asset_validated", 1)
	check(not tracker.preflight(identity, result, BYTES).ok, "truthy non-bool validation metadata cannot authorize publication")
	result.packed.set_meta("compiled_asset_validated", true)
	result.packed.set_meta("_rmmo_source_digest", "d".repeat(64))
	check(not tracker.preflight(identity, result, BYTES).ok, "preexisting cache metadata cannot conflict with the reader snapshot")
	result.clear()
	for resource: Resource in [Resource.new(), ScriptedResource.new()]:
		var unsupported := packet(resource)
		check(not tracker.preflight(identity, unsupported, BYTES).ok, "unsupported or scripted resource graph cannot escape into baseline ownership")
		unsupported.clear()
	var invalid_scene := Node.new()
	var invalid_packed := PackedScene.new()
	check(invalid_packed.pack(invalid_scene) == OK, "unsupported native node fixture packs")
	invalid_scene.free(); invalid_packed.set_meta("compiled_asset_validated", true)
	var invalid_packet := packet(); invalid_packet.packed = invalid_packed
	check(not tracker.preflight(identity, invalid_packet, BYTES).ok, "a non-native node schema is rejected despite the validation marker")
	invalid_packet.clear(); invalid_packed = null
	check(tracker.report().entries == 0 and tracker.report().published_envelope_bytes == 0 and not Assets.has_cached_scene(identity.source_path), "all failed preflights preserve empty cache and accounting")
	tracker.free()

static func wrong_thread(tracker: Node) -> Dictionary:
	return {"preflight":tracker.preflight({}, {}, 1), "adopt":tracker.adopt(null), "report":tracker.report(), "retire":tracker.collect_retired()}

func global_lifetime_and_main_thread() -> void:
	var operation := Node.new()
	root.add_child(operation)
	var tracker := Ownership.for_tree(self)
	check(tracker != null and tracker.get_parent() == root and Ownership.for_tree(self) == tracker, "global ownership tracker is stable and outside the load operation")
	var identity := candidate()
	var result := packet()
	var ticket: Dictionary = publish(tracker, identity, result)
	operation.free(); result.clear()
	check(tracker.report().published_envelope_bytes == BYTES and tracker.collect_retired().retired == 0, "operation exit cannot erase still-published resource accounting")
	var worker := Thread.new()
	var started := worker.start(wrong_thread.bind(tracker))
	check(started == OK, "CPU-only main-thread guard worker starts")
	if started == OK:
		var denied: Dictionary = worker.wait_to_finish()
		for key: String in denied:
			check(not denied[key].ok and denied[key].reason == "main_thread_required", "off-main access fails before resource/accounting work: " + key)
	Assets.evict_cached_scene(identity.source_path)
	check(tracker.collect_retired().retired == 1, "global tracker eventually retires after cache eviction")
	var report: Dictionary = tracker.report()
	check(report.untracked_legacy_cache_bytes == null and report.source_proof_scope.contains("reader-completion") and report.accounting.contains("not RSS"), "report explicitly preserves unknown legacy bytes and reader-completion proof scope")
	ticket.clear(); tracker.free()

func run() -> void:
	preflight_is_weak_and_side_effect_free()
	exact_publication_and_identity()
	scene_state_outlives_packed()
	independent_child_keeps_full_envelope()
	independent_allocations_and_bounded_retirement()
	fail_closed_graph_and_packet()
	global_lifetime_and_main_thread()
	print("PREPARED_MODEL_OWNERSHIP_RESULT ", JSON.stringify({"passed":passed, "failed":failures}))
	quit(0 if failures == 0 else 1)
