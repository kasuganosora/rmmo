extends SceneTree
## Headless: potion_cleanse「净化药水」→ use_effect cleanse; strips poison/silence; keeps buffs; shop + CD 3s.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_cleanse_potion: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.item_catalog == null or srv.inventory == null or srv.combat_engine == null or srv.combat_stats == null:
		print("test_cleanse_potion: FAIL combat layers missing")
		quit(1)
		return

	# Catalog
	var def: Dictionary = srv.item_catalog.get_item("potion_cleanse")
	failed += _expect(not def.is_empty(), "catalog has potion_cleanse")
	failed += _expect(str(def.get("name", "")) == "净化药水", "Chinese name")
	var ue := str(def.get("use_effect", def.get("effect", "")))
	failed += _expect(ue == "cleanse", "use_effect cleanse")
	failed += _expect(bool(def.get("consumable", false)), "consumable")
	failed += _expect(str(def.get("type", "")) == "consumable", "type consumable")
	failed += _expect(int(def.get("stack_max", 0)) == 20, "stack_max 20")
	failed += _expect(int(def.get("sell_price", 0)) == 8, "sell_price 8")
	failed += _expect(abs(float(def.get("cooldown", 0.0)) - 3.0) < 0.01, "cooldown 3s")

	# Engine recognizes cleanse
	failed += _expect(srv.combat_engine._is_item_effect("cleanse"), "_is_item_effect cleanse")

	# Shop stock
	if srv.shop_catalog != null and srv.shop_catalog.has_method("sells_item"):
		failed += _expect(srv.shop_catalog.sells_item("starter_goods", "potion_cleanse"), "shop sells potion_cleanse")

	# Apply harmful + keep a buff, then cleanse
	srv.awaiting_respawn = false
	srv.sitting = false
	if srv.combat_stats != null:
		srv.combat_stats.player["hp"] = maxi(int(srv.combat_stats.player.get("hp_max", 100)), 1)
	var statuses = srv.combat_stats.statuses
	failed += _expect(statuses != null, "statuses present")
	statuses.clear_all("player")

	statuses.apply_status("player", {
		"id": "poison",
		"name": "中毒",
		"kind": "dot",
		"duration": 8.0,
		"tick_interval": 1.0,
		"tick_hp": -4,
	}, 8.0, "npc")
	statuses.apply_status("player", {
		"id": "silence",
		"name": "沉默",
		"kind": "debuff",
		"duration": 5.0,
		"tick_interval": 0,
	}, 5.0, "npc")
	statuses.apply_status("player", {
		"id": "_test_might",
		"name": "力量",
		"kind": "buff",
		"duration": 20.0,
		"tick_interval": 0,
		"atk_add": 3,
	}, 20.0, "player")
	failed += _expect(statuses.has_status("player", "poison"), "poison applied")
	failed += _expect(statuses.has_status("player", "silence"), "silence applied")
	failed += _expect(statuses.has_status("player", "_test_might"), "buff applied")

	srv.inventory.clear()
	srv.inventory.add_item("potion_cleanse", 2)
	failed += _expect(srv.inventory.get_qty("potion_cleanse") == 2, "qty start 2")

	# Clear any prior CD
	if srv.combat_stats.has_method("set_item_cooldown"):
		srv.combat_stats.set_item_cooldown("potion_cleanse", 0.0)

	var r: Dictionary = srv.try_use_item("potion_cleanse")
	failed += _expect(bool(r.get("ok", false)), "use potion ok")
	failed += _expect(not statuses.has_status("player", "poison"), "poison cleared")
	failed += _expect(not statuses.has_status("player", "silence"), "silence cleared")
	failed += _expect(statuses.has_status("player", "_test_might"), "buff kept")
	failed += _expect(srv.inventory.get_qty("potion_cleanse") == 1, "qty decremented to 1")
	failed += _expect(_has(r, "status_update"), "status_update action")
	failed += _expect(_has(r, "inventory_update"), "inventory_update action")
	failed += _expect(_msg_has(r, "净化药水") or _msg_has(r, "使用了"), "Chinese use msg")

	# Cooldown gate (~3s)
	var r_cd: Dictionary = srv.try_use_item("potion_cleanse")
	failed += _expect(not bool(r_cd.get("ok", true)), "on cooldown rejected")
	failed += _expect(srv.inventory.get_qty("potion_cleanse") == 1, "qty unchanged on CD")

	if failed == 0:
		print("test_cleanse_potion: PASS")
		quit(0)
		return
	print("test_cleanse_potion: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _msg_has(result: Dictionary, needle: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if needle in str(a.get("text", "")):
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
