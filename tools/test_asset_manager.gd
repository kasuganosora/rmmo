extends SceneTree
## Headless: AssetManager ContentRef, ensure, queue, budget, collect_map_pack_deps.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var ContentRef = load("res://scripts/asset/content_ref.gd")
	var PlaceholderTex = load("res://scripts/asset/placeholder_tex.gd")

	# --- ContentRef parse ---
	var cr = ContentRef.parse("content://charset/actor03_0001@1.0.0")
	failed += _expect(cr.is_valid(), "content ref valid")
	failed += _expect(str(cr.kind) == "charset", "kind charset")
	failed += _expect(str(cr.id) == "actor03_0001", "id actor03_0001")
	failed += _expect(str(cr.version) == "1.0.0", "version 1.0.0")
	var cr2 = ContentRef.parse("content://map_pack/demo_home")
	failed += _expect(str(cr2.kind) == "map_pack" and str(cr2.id) == "demo_home", "map_pack demo_home")
	var cr3 = ContentRef.parse("content://charset/!Chest1")
	failed += _expect(str(cr3.id) == "!Chest1", "bang id")
	var made: String = ContentRef.make("charset", "x", "2")
	failed += _expect(made == "content://charset/x@2", "ContentRef.make")

	# --- AssetManager autoload ---
	var am: Node = root.get_node_or_null("AssetManager")
	failed += _expect(am != null, "AssetManager autoload present")
	if am == null:
		_finish(failed)
		return

	failed += _expect(str(am.content_root()) != "", "content_root non-empty")

	# --- resolve_map_pack_path ---
	var demo_path: String = str(am.resolve_map_pack_path("res://demo_map"))
	failed += _expect(demo_path == "res://demo_map" or demo_path.ends_with("demo_map"), "resolve res://demo_map")
	var by_id: String = str(am.resolve_map_pack_path("demo_home"))
	failed += _expect(by_id.find("demo_map") >= 0 or by_id.find("demo_home") >= 0, "resolve demo_home id -> demo_map")
	var by_cref: String = str(am.resolve_map_pack_path("content://map_pack/demo_home@1.0.0"))
	failed += _expect(by_cref.find("demo_map") >= 0 or FileAccess.file_exists("%s/pack.json" % by_cref), "resolve content map_pack")
	var by_street: String = str(am.resolve_map_pack_path("street_central"))
	failed += _expect(by_street.find("street_map") >= 0, "resolve street_central id -> street_map")
	var by_bath: String = str(am.resolve_map_pack_path("bath_home"))
	failed += _expect(by_bath.find("bath_map") >= 0, "resolve bath_home id -> bath_map")
	var by_street_cref: String = str(am.resolve_map_pack_path("content://map_pack/street_central"))
	failed += _expect(by_street_cref.find("street_map") >= 0, "resolve content street_central")

	# --- ensure map pack (res) ---
	var err_pack: Error = am.ensure("res://demo_map")
	failed += _expect(err_pack == OK, "ensure res://demo_map OK")
	failed += _expect(bool(am.has("res://demo_map")), "has res://demo_map")
	failed += _expect(bool(am.has("content://map_pack/demo_home")), "has content://map_pack/demo_home")

	# --- ensure charset: legacy D:/ or skip if missing ---
	var charset_ref := "content://charset/actor03_0001"
	var charset_path: String = str(am.path(charset_ref))
	print("charset path=", charset_path, " exists=", FileAccess.file_exists(charset_path))
	if FileAccess.file_exists(charset_path):
		failed += _expect(am.ensure(charset_ref) == OK, "ensure charset when present")
		var img: Image = am.load_image(charset_ref)
		failed += _expect(img != null and img.get_width() > 0, "load_image charset")
	else:
		print("SKIP charset PNG (no D:/ runtime) — ensure soft-miss expected")
		var miss: Error = am.ensure(charset_ref)
		failed += _expect(miss != OK, "ensure missing charset returns error")
		failed += _expect(am.load_image(charset_ref) == null, "load_image missing -> null")

	# --- ensure_many empty OK ---
	failed += _expect(am.ensure_many([]) == OK, "ensure_many empty OK")
	failed += _expect(am.ensure_many(["res://demo_map"], "校验") == OK, "ensure_many demo pack")

	# --- double ensure re-entrancy ---
	failed += _expect(am.ensure("res://demo_map") == OK, "double ensure OK")

	# --- enqueue + pump + dedupe ---
	am.enqueue(["content://charset/__missing_a", "content://charset/__missing_a"], 2)
	am.enqueue(["content://charset/__missing_a"], 1)  # bump/dedupe
	# Force pump
	if am.has_method("_pump_queue"):
		am._pump_queue()
	await process_frame
	await process_frame
	failed += _expect(true, "enqueue+pump no crash")

	# --- prefetch_allowed / budget ---
	am.set_budget(64.0, 96.0)
	failed += _expect(am.budget_soft_mb == 64.0, "budget soft 64")
	failed += _expect(typeof(am.prefetch_allowed()) == TYPE_BOOL, "prefetch_allowed bool")

	# --- note_actor_ring stub ---
	am.note_actor_ring("npc_1", "VIEW")
	failed += _expect(str(am.get_actor_ring("npc_1")) == "VIEW", "actor ring VIEW")
	am.note_actor_ring("npc_1", "COLD")
	failed += _expect(str(am.get_actor_ring("npc_1")) == "COLD", "actor ring COLD")

	# --- collect_map_pack_deps on demo_map ---
	var deps: Array = am.collect_map_pack_deps("res://demo_map")
	print("deps count=", deps.size(), " sample=", deps.slice(0, mini(5, deps.size())))
	failed += _expect(deps.size() >= 1, "deps non-empty")
	var has_map := false
	var has_charset := false
	for d in deps:
		var s := str(d)
		if s.begins_with("content://map_pack/") or s.find("demo_map") >= 0:
			has_map = true
		if s.begins_with("content://charset/"):
			has_charset = true
	failed += _expect(has_map, "deps include map_pack")
	failed += _expect(has_charset, "deps include charset from npcs")

	# --- empty deps path: fake empty pack dir shouldn't crash ---
	var empty_deps: Array = am.collect_map_pack_deps("res://does_not_exist_pack_xyz")
	failed += _expect(typeof(empty_deps) == TYPE_ARRAY, "missing pack deps returns array")

	# --- placeholder ---
	var tex: ImageTexture = am.make_letter_texture("测", 48)
	failed += _expect(tex != null and tex.get_width() == 48, "letter texture 48")
	var frames: SpriteFrames = PlaceholderTex.make_letter_sprite_frames("A", 32)
	failed += _expect(frames != null and frames.has_animation("idle_front"), "letter frames")

	# --- charset_sheet prefers manager (no crash without PNG) ---
	var CharsetSheet = load("res://scripts/char/charset_sheet.gd")
	var sheet_path: String = CharsetSheet.resolve_sheet_path("actor03_0001")
	failed += _expect(sheet_path != "", "charset resolve path non-empty")
	var built = CharsetSheet.build_sprite_frames("actor03_0001", 0)
	failed += _expect(built != null, "build_sprite_frames returns frames")

	# --- LRU eviction stub ---
	am.set_budget(32.0, 48.0)
	if am.has_method("evict_lru_if_needed"):
		am.evict_lru_if_needed()
	failed += _expect(true, "evict_lru_if_needed no crash")

	# --- P2c AOI rings smoke (full coverage in test_aoi_rings.gd) ---
	am._queue.clear()
	am._max_concurrent = 0
	am.bind_actor_refs("p2c_npc", ["content://charset/__p2c_smoke"])
	am.enqueue(["content://charset/__p2c_smoke"], 0)
	am.note_actor_ring("p2c_npc", "PREFETCH")
	am.note_actor_ring("p2c_npc", "COLD")
	var still := false
	for item in am._queue:
		if str(item.get("ref", "")) == "content://charset/__p2c_smoke":
			still = true
	failed += _expect(not still, "P2c PREFETCH→COLD cancels LOW")
	am.set_interest(["p2c_v"], ["p2c_a"], ["p2c_p"])
	failed += _expect(str(am.get_actor_ring("p2c_v")) == "VIEW", "P2c set_interest VIEW")
	am._max_concurrent = 3
	am._queue.clear()

	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS test_asset_manager")
		quit(0)
	else:
		print("FAILED ", failed, " assertions")
		quit(1)
