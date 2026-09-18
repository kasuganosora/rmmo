extends SceneTree
## Headless: cooked foods heal + apply nested status buffs; potions stay buff-free.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_food_buff: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.combat_engine == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("food_grilled_fish"), "item food_grilled_fish")
	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("food_herb_soup"), "item food_herb_soup")
	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("food_fish_feast"), "item food_fish_feast")
	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("potion_hp_small"), "item potion_hp_small")

	# Catalog nested status present for foods, absent for potion.
	var gf: Dictionary = srv.item_catalog.get_item("food_grilled_fish")
	var hs: Dictionary = srv.item_catalog.get_item("food_herb_soup")
	var ff: Dictionary = srv.item_catalog.get_item("food_fish_feast")
	var pot: Dictionary = srv.item_catalog.get_item("potion_hp_small")
	failed += _expect(str(gf.get("status", {}).get("id", "")) == "well_fed", "grilled status well_fed")
	failed += _expect(str(hs.get("status", {}).get("id", "")) == "herb_warmth", "soup status herb_warmth")
	failed += _expect(str(ff.get("status", {}).get("id", "")) == "feast", "feast status feast")
	var pot_st: Variant = pot.get("status", {})
	var pot_empty := typeof(pot_st) != TYPE_DICTIONARY or (pot_st as Dictionary).is_empty() or str((pot_st as Dictionary).get("id", "")).is_empty()
	failed += _expect(pot_empty, "potion has no status nest")

	var stats = srv.combat_stats
	failed += _expect(stats != null, "combat_stats available")
	if stats == null:
		print("test_food_buff: FAIL count=%d" % failed)
		quit(1)
		return

	# --- grilled fish: heal + well_fed ---
	stats.statuses.clear_everything()
	stats.item_ready_at.clear()
	stats.player["hp"] = 10
	stats.player["hp_max"] = 200
	srv.inventory.clear()
	srv.inventory.add_item("food_grilled_fish", 2)
	var r1: Dictionary = srv.try_use_item("food_grilled_fish")
	failed += _expect(bool(r1.get("ok", false)), "use grilled fish ok")
	failed += _expect(int(stats.player.get("hp", 0)) == 45, "grilled heal 35 (10->45)")
	failed += _expect(stats.statuses.has_status("player", "well_fed"), "well_fed applied")
	failed += _expect(_status_remaining(stats, "well_fed") > 0.0, "well_fed remaining > 0")
	failed += _expect(_count_status(stats, "well_fed") == 1, "one well_fed instance")
	failed += _expect(_has_type(r1.get("actions", []), "status_update"), "grilled status_update")
	var wf: Dictionary = _find_status(stats, "well_fed")
	failed += _expect(abs(float(wf.get("atk_add", 0.0)) - 3.0) < 0.001, "well_fed atk_add 3")

	# Re-eat refreshes (still one instance)
	stats.item_ready_at.clear()
	stats.player["hp"] = 10
	var r1b: Dictionary = srv.try_use_item("food_grilled_fish")
	failed += _expect(bool(r1b.get("ok", false)), "re-eat grilled ok")
	failed += _expect(stats.statuses.has_status("player", "well_fed"), "well_fed still present")
	failed += _expect(_count_status(stats, "well_fed") == 1, "refresh keeps one well_fed")
	failed += _expect(_status_remaining(stats, "well_fed") > 50.0, "well_fed refreshed near 60s")

	# --- herb soup: heal+mp + herb_warmth HoT ---
	stats.statuses.clear_everything()
	stats.item_ready_at.clear()
	stats.player["hp"] = 10
	stats.player["hp_max"] = 200
	stats.player["mp"] = 5
	stats.player["mp_max"] = 100
	srv.inventory.clear()
	srv.inventory.add_item("food_herb_soup", 1)
	var r2: Dictionary = srv.try_use_item("food_herb_soup")
	failed += _expect(bool(r2.get("ok", false)), "use herb soup ok")
	failed += _expect(int(stats.player.get("hp", 0)) == 35, "soup heal 25 (10->35)")
	failed += _expect(int(stats.player.get("mp", 0)) == 20, "soup mp +15 (5->20)")
	failed += _expect(stats.statuses.has_status("player", "herb_warmth"), "herb_warmth applied")
	failed += _expect(_status_remaining(stats, "herb_warmth") > 0.0, "herb_warmth remaining > 0")
	var hw: Dictionary = _find_status(stats, "herb_warmth")
	failed += _expect(str(hw.get("kind", "")) == "hot", "herb_warmth kind hot")
	failed += _expect(int(hw.get("tick_hp", 0)) == 2, "herb_warmth tick_hp 2")

	# --- fish feast: heal + feast atk/def ---
	stats.statuses.clear_everything()
	stats.item_ready_at.clear()
	stats.player["hp"] = 10
	stats.player["hp_max"] = 200
	srv.inventory.clear()
	srv.inventory.add_item("food_fish_feast", 1)
	var r3: Dictionary = srv.try_use_item("food_fish_feast")
	failed += _expect(bool(r3.get("ok", false)), "use fish feast ok")
	failed += _expect(int(stats.player.get("hp", 0)) == 90, "feast heal 80 (10->90)")
	failed += _expect(stats.statuses.has_status("player", "feast"), "feast applied")
	failed += _expect(_status_remaining(stats, "feast") > 0.0, "feast remaining > 0")
	var fe: Dictionary = _find_status(stats, "feast")
	failed += _expect(abs(float(fe.get("atk_add", 0.0)) - 5.0) < 0.001, "feast atk_add 5")
	failed += _expect(abs(float(fe.get("def_add", 0.0)) - 3.0) < 0.001, "feast def_add 3")

	# --- potion: heal, no food buff invented ---
	stats.statuses.clear_everything()
	stats.item_ready_at.clear()
	stats.player["hp"] = 10
	stats.player["hp_max"] = 200
	srv.inventory.clear()
	srv.inventory.add_item("potion_hp_small", 1)
	var rp: Dictionary = srv.try_use_item("potion_hp_small")
	failed += _expect(bool(rp.get("ok", false)), "use potion ok")
	failed += _expect(int(stats.player.get("hp", 0)) > 10, "potion healed")
	failed += _expect(not stats.statuses.has_status("player", "well_fed"), "potion no well_fed")
	failed += _expect(not stats.statuses.has_status("player", "herb_warmth"), "potion no herb_warmth")
	failed += _expect(not stats.statuses.has_status("player", "feast"), "potion no feast")
	failed += _expect(stats.statuses.snapshot_statuses("player").is_empty(), "potion leaves no statuses")

	if failed == 0:
		print("test_food_buff: PASS")
		quit(0)
		return
	print("test_food_buff: FAIL count=%d" % failed)
	quit(1)


func _status_remaining(stats, status_id: String) -> float:
	for s in stats.statuses.snapshot_statuses("player"):
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == status_id:
			return float(s.get("remaining_sec", 0.0))
	return 0.0


func _count_status(stats, status_id: String) -> int:
	var n := 0
	for s in stats.statuses.snapshot_statuses("player"):
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == status_id:
			n += 1
	return n


func _find_status(stats, status_id: String) -> Dictionary:
	for s in stats.statuses.snapshot_statuses("player"):
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == status_id:
			return s
	return {}


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
