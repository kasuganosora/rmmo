extends SceneTree
## Headless: P2c AOI rings — bind refs, cancel LOW on COLD, set_interest, upgrade enqueue.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var am: Node = root.get_node_or_null("AssetManager")
	failed += _expect(am != null, "AssetManager autoload present")
	if am == null:
		_finish(failed)
		return

	# Isolate queue
	am._queue.clear()
	am._inflight.clear()
	am._actor_rings.clear()
	am._actor_refs.clear()
	am._evictable_refs.clear()
	am._evictable_at_msec.clear()

	# --- bind_actor_refs ---
	am.bind_actor_refs("npc_far", ["content://charset/__aoi_test_a"])
	var refs: Array = am.get_actor_refs("npc_far")
	failed += _expect(refs.size() == 1 and str(refs[0]).ends_with("__aoi_test_a"), "bind_actor_refs stores charset ref")

	# --- PREFETCH enqueue LOW then COLD cancels ---
	am.enqueue(["content://charset/__aoi_test_a"], 0)  # LOW
	failed += _expect(_queue_has(am, "content://charset/__aoi_test_a"), "LOW job queued for prefetch charset")
	am.note_actor_ring("npc_far", "PREFETCH")
	failed += _expect(str(am.get_actor_ring("npc_far")) == "PREFETCH", "ring PREFETCH")
	am.note_actor_ring("npc_far", "COLD")
	failed += _expect(str(am.get_actor_ring("npc_far")) == "COLD", "ring COLD after downgrade")
	failed += _expect(not _queue_has(am, "content://charset/__aoi_test_a"), "LOW cancelled on PREFETCH→COLD")

	# --- shared ref: other PREFETCH actor keeps LOW ---
	am._queue.clear()
	am.bind_actor_refs("npc_a", ["content://charset/__shared"])
	am.bind_actor_refs("npc_b", ["content://charset/__shared"])
	am.note_actor_ring("npc_a", "PREFETCH")
	am.note_actor_ring("npc_b", "PREFETCH")
	am.enqueue(["content://charset/__shared"], 0)
	am.note_actor_ring("npc_a", "COLD")
	failed += _expect(_queue_has(am, "content://charset/__shared"), "shared LOW kept while npc_b still PREFETCH")
	am.note_actor_ring("npc_b", "COLD")
	failed += _expect(not _queue_has(am, "content://charset/__shared"), "shared LOW cancelled when all COLD")

	# --- set_interest assigns rings + unmarked → COLD ---
	am._actor_rings.clear()
	am.bind_actor_refs("v1", ["content://charset/v1"])
	am.bind_actor_refs("a1", ["content://charset/a1"])
	am.bind_actor_refs("p1", ["content://charset/p1"])
	am.bind_actor_refs("c1", ["content://charset/c1"])
	am.note_actor_ring("c1", "AOI")
	am.set_interest(["v1"], ["a1"], ["p1"])
	failed += _expect(str(am.get_actor_ring("v1")) == "VIEW", "set_interest VIEW")
	failed += _expect(str(am.get_actor_ring("a1")) == "AOI", "set_interest AOI")
	failed += _expect(str(am.get_actor_ring("p1")) == "PREFETCH", "set_interest PREFETCH")
	failed += _expect(str(am.get_actor_ring("c1")) == "COLD", "set_interest marks previous unlisted COLD")

	# VIEW wins over duplicate in aoi/prefetch lists
	am.set_interest(["dup"], ["dup"], ["dup"])
	failed += _expect(str(am.get_actor_ring("dup")) == "VIEW", "VIEW precedence in set_interest")

	# --- ring upgrade enqueue priority (inspect _queue before pump) ---
	am._queue.clear()
	am._inflight.clear()
	# Prevent deferred pump from draining mid-assert: temporarily raise concurrent to 0
	var old_conc: int = int(am._max_concurrent)
	am._max_concurrent = 0
	am.bind_actor_refs("up1", ["content://charset/__upgrade_x"])
	am.note_actor_ring("up1", "COLD")
	# Simulate driver upgrade path: enqueue by ring priority
	am.enqueue(["content://charset/__upgrade_x"], 0)  # PREFETCH LOW
	failed += _expect(_queue_priority(am, "content://charset/__upgrade_x") == 0, "upgrade start LOW")
	am.enqueue(["content://charset/__upgrade_x"], 1)  # AOI NORMAL bump
	failed += _expect(_queue_priority(am, "content://charset/__upgrade_x") == 1, "upgrade bump NORMAL")
	am.enqueue(["content://charset/__upgrade_x"], 2)  # VIEW HIGH bump
	failed += _expect(_queue_priority(am, "content://charset/__upgrade_x") == 2, "upgrade bump HIGH")
	am.note_actor_ring("up1", "VIEW")
	failed += _expect(str(am.get_actor_ring("up1")) == "VIEW", "up1 VIEW")
	am._max_concurrent = old_conc
	am._queue.clear()

	# --- AoiDriver classify distances (Chebyshev) ---
	var AoiDriver = load("res://scripts/asset/aoi_driver.gd")
	var drv = AoiDriver.new()
	drv.configure(14, 22, 30, 0.25)
	failed += _expect(drv.chebyshev(Vector2i(0, 0), Vector2i(3, 5)) == 5, "chebyshev max(dx,dy)")
	failed += _expect(str(drv.classify_distance(0)) == "VIEW", "dist0 VIEW")
	failed += _expect(str(drv.classify_distance(14)) == "VIEW", "dist14 VIEW")
	failed += _expect(str(drv.classify_distance(15)) == "AOI", "dist15 AOI")
	failed += _expect(str(drv.classify_distance(22)) == "AOI", "dist22 AOI")
	failed += _expect(str(drv.classify_distance(23)) == "PREFETCH", "dist23 PREFETCH")
	failed += _expect(str(drv.classify_distance(30)) == "PREFETCH", "dist30 PREFETCH")
	failed += _expect(str(drv.classify_distance(31)) == "COLD", "dist31 COLD")
	failed += _expect(drv.ring_priority("VIEW") == 2, "priority VIEW HIGH")
	failed += _expect(drv.ring_priority("AOI") == 1, "priority AOI NORMAL")
	failed += _expect(drv.ring_priority("PREFETCH") == 0, "priority PREFETCH LOW")
	failed += _expect(drv.ring_priority("COLD") < 0, "priority COLD none")

	# --- Driver refresh with fake NPC-like objects ---
	am._queue.clear()
	am._actor_rings.clear()
	am._actor_refs.clear()
	am._max_concurrent = 0
	var FakeNpc = load("res://scripts/game/npc_actor.gd")
	# Use plain dictionaries via a tiny helper node — NpcActor needs tree; use RefCounted stubs
	var stubs: Array = []
	stubs.append(_make_stub("near", Vector2i(2, 2), "cs_near"))
	stubs.append(_make_stub("mid", Vector2i(18, 0), "cs_mid"))
	stubs.append(_make_stub("edge", Vector2i(25, 0), "cs_edge"))
	stubs.append(_make_stub("far", Vector2i(40, 0), "cs_far"))
	var player_stub = _make_stub("player", Vector2i(0, 0), "")
	drv.reset()
	drv.refresh(player_stub, stubs, am)
	failed += _expect(str(am.get_actor_ring("near")) == "VIEW", "driver near VIEW")
	failed += _expect(str(am.get_actor_ring("mid")) == "AOI", "driver mid AOI")
	failed += _expect(str(am.get_actor_ring("edge")) == "PREFETCH", "driver edge PREFETCH")
	failed += _expect(str(am.get_actor_ring("far")) == "COLD", "driver far COLD")
	failed += _expect(_queue_priority(am, "content://charset/cs_near") == 2, "driver enqueued near HIGH")
	failed += _expect(_queue_priority(am, "content://charset/cs_mid") == 1, "driver enqueued mid NORMAL")
	failed += _expect(_queue_priority(am, "content://charset/cs_edge") == 0, "driver enqueued edge LOW")
	failed += _expect(not _queue_has(am, "content://charset/cs_far"), "driver no enqueue for COLD")

	# Move player toward far → upgrade; previous near may stay or change
	player_stub.cell = Vector2i(40, 0)
	drv.refresh(player_stub, stubs, am)
	failed += _expect(str(am.get_actor_ring("far")) == "VIEW", "after walk far→VIEW")
	failed += _expect(str(am.get_actor_ring("near")) == "COLD", "after walk near→COLD")
	# LOW for edge charset should cancel if edge now COLD and was PREFETCH
	# edge at (25,0) from player (40,0) dist=15 → AOI
	failed += _expect(str(am.get_actor_ring("edge")) == "AOI", "edge now AOI after walk")

	am._max_concurrent = old_conc
	am._queue.clear()

	# --- evictable mark on COLD ---
	am.bind_actor_refs("ev1", ["content://charset/__evict"])
	am.note_actor_ring("ev1", "AOI")
	am.note_actor_ring("ev1", "COLD")
	failed += _expect(bool(am._evictable_refs.get("content://charset/__evict", false)), "COLD marks ref evictable")
	am.note_actor_ring("ev1", "VIEW")
	failed += _expect(not bool(am._evictable_refs.get("content://charset/__evict", false)), "VIEW clears evictable")

	# cleanup stubs
	for s in stubs:
		s.free()
	player_stub.free()

	_finish(failed)


func _make_stub(nid: String, cell: Vector2i, charset: String) -> Node:
	var stub := _AoiNpcStub.new()
	stub.npc_id = nid
	stub.cell = cell
	stub.charset = charset
	return stub


func _queue_has(am: Node, ref: String) -> bool:
	for item in am._queue:
		if str(item.get("ref", "")) == ref:
			return true
	return false


func _queue_priority(am: Node, ref: String) -> int:
	for item in am._queue:
		if str(item.get("ref", "")) == ref:
			return int(item.get("priority", -99))
	return -99


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS test_aoi_rings")
		quit(0)
	else:
		print("FAILED ", failed, " assertions")
		quit(1)


## Minimal stand-in for NpcActor fields the AOI driver reads.
class _AoiNpcStub extends Node:
	var npc_id: String = ""
	var cell: Vector2i = Vector2i.ZERO
	var charset: String = ""
