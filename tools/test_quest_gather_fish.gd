extends SceneTree
## Headless: accept herb_gather / pond_fishing → try_gather / try_fish → ready → turn-in.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_quest_gather_fish: FAIL no MockServer")
		quit(1)
		return
	if srv.quest_journal == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.quest_journal != null, "quest_journal")
	failed += _expect(srv.has_method("try_gather"), "has try_gather")
	failed += _expect(srv.has_method("try_fish"), "has try_fish")
	failed += _expect(srv.quest_journal.has_method("note_fish"), "has note_fish")

	if srv.has_method("_load_pack"):
		srv._load_pack("res://demo_map")

	# Fresh journal: catalog-only side quests (no starter clutter).
	srv.quest_journal.clear()
	srv.quest_journal.load_catalog()
	failed += _expect(srv.quest_journal.accept_quest("herb_gather"), "accept herb_gather")
	failed += _expect(srv.quest_journal.accept_quest("pond_fishing"), "accept pond_fishing")
	failed += _expect(str(srv.quest_journal.get_status("herb_gather")) == "in_progress", "herb in_progress")
	failed += _expect(str(srv.quest_journal.get_status("pond_fishing")) == "in_progress", "fish in_progress")

	# Unit: note_fish any
	var j_unit = load("res://scripts/net/combat/quest_journal.gd").new()
	j_unit.load_catalog()
	j_unit.clear()
	j_unit.accept_quest("pond_fishing")
	failed += _expect(bool(j_unit.note_fish("fish_small", 3)), "note_fish ×3")
	failed += _expect(str(j_unit.get_status("pond_fishing")) == "ready", "note_fish ready")

	# --- gather via try_gather until herb_gather ready (max 5) ---
	if srv.inventory != null:
		srv.inventory.clear()
		srv.inventory.add_gold(10)
		srv.inventory.max_slots = 40
	srv.set_player_cell(10, 21)
	if srv.has_method("register_npc"):
		srv.register_npc("herb_a", 10, 22, false, false, 2, 0, 0, {
			"id": "herb_a", "name": "野生药草", "kind": "object"
		})
	var gather_progress := 0
	var saw_quest_update := false
	for _i in range(8):
		if srv.has_method("force_gather_respawn"):
			srv.force_gather_respawn("herb_a")
		var gr: Dictionary = srv.try_gather("herb_a")
		if not bool(gr.get("ok", false)):
			continue
		if _has_type(gr, "quest_update"):
			saw_quest_update = true
		gather_progress += 1
		if str(srv.quest_journal.get_status("herb_gather")) == "ready":
			break
	failed += _expect(gather_progress >= 5, "gathered >=5 times")
	failed += _expect(str(srv.quest_journal.get_status("herb_gather")) == "ready", "herb_gather ready via try_gather")
	failed += _expect(saw_quest_update, "gather emitted quest_update")

	# Turn-in herb
	var tin: Dictionary = srv.quest_journal.try_turn_in("herb_gather")
	failed += _expect(bool(tin.get("ok", false)), "herb turn-in ok")
	failed += _expect(str(srv.quest_journal.get_status("herb_gather")) == "completed", "herb completed")

	# --- fish via try_fish until pond_fishing ready (max 3) ---
	srv.set_player_cell(16, 10)
	if srv.has_method("register_npc"):
		srv.register_npc("fish_pond_a", 16, 11, false, false, 2, 0, 0, {
			"id": "fish_pond_a", "name": "小水塘", "kind": "object"
		})
	if " _fish_busy_until" in str(srv.get_property_list()):
		pass
	srv._fish_busy_until = 0.0
	var fish_progress := 0
	var saw_fish_qu := false
	for _j in range(6):
		if srv.has_method("force_fish_respawn"):
			srv.force_fish_respawn("fish_pond_a")
		srv._fish_busy_until = 0.0
		var fr: Dictionary = srv.try_fish("fish_pond_a")
		if not bool(fr.get("ok", false)):
			print("  try_fish fail reason=", fr.get("reason", ""))
			continue
		if _has_type(fr, "quest_update"):
			saw_fish_qu = true
		fish_progress += 1
		if str(srv.quest_journal.get_status("pond_fishing")) == "ready":
			break
	failed += _expect(fish_progress >= 3, "fished >=3 times")
	failed += _expect(str(srv.quest_journal.get_status("pond_fishing")) == "ready", "pond_fishing ready via try_fish")
	failed += _expect(saw_fish_qu, "fish emitted quest_update")

	var tin2: Dictionary = srv.quest_journal.try_turn_in("pond_fishing")
	failed += _expect(bool(tin2.get("ok", false)), "fish turn-in ok")
	failed += _expect(str(srv.quest_journal.get_status("pond_fishing")) == "completed", "fish completed")

	# Offer still listed for vendor when not accepted (smoke accept path)
	srv.quest_journal.clear()
	srv.quest_journal.load_catalog()
	var offers: Array = srv.quest_journal.list_offers_for_npc("vendor_demo")
	var offer_ids := {}
	for o in offers:
		offer_ids[str(o.get("id", ""))] = true
	failed += _expect(offer_ids.has("herb_gather"), "vendor offers herb_gather")
	failed += _expect(offer_ids.has("pond_fishing"), "vendor offers pond_fishing")

	if failed == 0:
		print("test_quest_gather_fish: PASS")
		quit(0)
	else:
		print("test_quest_gather_fish: FAIL count=%d" % failed)
		quit(1)


func _has_type(result: Dictionary, t: String) -> bool:
	var acts: Variant = result.get("actions", [])
	if typeof(acts) != TYPE_ARRAY:
		return false
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
