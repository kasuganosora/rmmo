extends SceneTree
## Headless: bandage「绷带」→ heal_hp 40; out of combat only; CD 8s; shop starter_goods.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_bandage: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.item_catalog == null or srv.inventory == null or srv.combat_engine == null or srv.combat_stats == null:
		print("test_bandage: FAIL combat layers missing")
		quit(1)
		return

	var engine = srv.combat_engine
	var stats = srv.combat_stats

	# Catalog
	var def: Dictionary = srv.item_catalog.get_item("bandage")
	failed += _expect(not def.is_empty(), "catalog has bandage")
	failed += _expect(str(def.get("name", "")) == "绷带", "Chinese name 绷带")
	var ue := str(def.get("use_effect", def.get("effect", "")))
	failed += _expect(ue == "heal_hp", "use_effect heal_hp")
	failed += _expect(bool(def.get("consumable", false)), "consumable")
	failed += _expect(str(def.get("type", "")) == "consumable", "type consumable")
	failed += _expect(int(def.get("amount", 0)) == 40, "heal amount 40 flat")
	failed += _expect(abs(float(def.get("cooldown", 0.0)) - 8.0) < 0.01, "cooldown 8s")
	failed += _expect(bool(def.get("out_of_combat_only", false)), "out_of_combat_only")
	failed += _expect(str(def.get("combat_fail_msg", "")) == "战斗中无法包扎。", "combat_fail_msg")
	failed += _expect(int(def.get("icon_index", -1)) == 32, "reuse heal icon_index 32")
	failed += _expect(int(def.get("sell_price", 0)) <= 5, "cheap sell_price")

	# Shop stock
	if srv.shop_catalog != null and srv.shop_catalog.has_method("sells_item"):
		failed += _expect(srv.shop_catalog.sells_item("starter_goods", "bandage"), "shop sells bandage")

	srv.awaiting_respawn = false
	srv.sitting = false
	if engine.has_method("reset_dps_fight"):
		engine.reset_dps_fight()
	stats.statuses.clear_everything() if stats.statuses.has_method("clear_everything") else stats.statuses.clear_all("player")

	stats.player["hp_max"] = 100
	stats.player["hp"] = 20
	failed += _expect(not engine.player_in_combat(), "baseline not in combat")

	srv.inventory.clear()
	srv.inventory.add_item("bandage", 3)
	failed += _expect(srv.inventory.get_qty("bandage") == 3, "qty start 3")
	if stats.has_method("set_item_cooldown"):
		stats.set_item_cooldown("bandage", 0.0)

	# Use out of combat: heal +40, consume
	var r: Dictionary = srv.try_use_item("bandage")
	failed += _expect(bool(r.get("ok", false)), "use bandage ok ooc")
	failed += _expect(int(stats.player.get("hp", 0)) == 60, "hp 20+40=60")
	failed += _expect(srv.inventory.get_qty("bandage") == 2, "qty decremented to 2")
	failed += _expect(_has(r, "inventory_update"), "inventory_update")
	failed += _expect(_msg_has(r, "绷带") or _msg_has(r, "使用了"), "Chinese use msg")

	# Cooldown ~8s blocks
	var r_cd: Dictionary = srv.try_use_item("bandage")
	failed += _expect(not bool(r_cd.get("ok", true)), "on cooldown rejected")
	failed += _expect(srv.inventory.get_qty("bandage") == 2, "qty unchanged on CD")
	failed += _expect(int(stats.player.get("hp", 0)) == 60, "hp unchanged on CD")

	# Clear CD; enter combat via DPS; use must fail without consume
	if stats.has_method("set_item_cooldown"):
		stats.set_item_cooldown("bandage", 0.0)
	stats.player["hp"] = 30
	if engine.has_method("note_dps_hit"):
		engine.note_dps_hit(5)
	failed += _expect(engine.player_in_combat(), "in combat via dps")
	var r_combat: Dictionary = srv.try_use_item("bandage")
	failed += _expect(not bool(r_combat.get("ok", true)), "blocked in combat")
	failed += _expect(_msg_has(r_combat, "战斗中无法包扎。"), "msg 战斗中无法包扎。")
	failed += _expect(srv.inventory.get_qty("bandage") == 2, "qty unchanged in combat")
	failed += _expect(int(stats.player.get("hp", 0)) == 30, "hp unchanged in combat")

	# Leave combat; use succeeds again
	if engine.has_method("reset_dps_fight"):
		engine.reset_dps_fight()
	failed += _expect(not engine.player_in_combat(), "left combat")
	if stats.has_method("set_item_cooldown"):
		stats.set_item_cooldown("bandage", 0.0)
	var r2: Dictionary = srv.try_use_item("bandage")
	failed += _expect(bool(r2.get("ok", false)), "use ok after combat")
	failed += _expect(int(stats.player.get("hp", 0)) == 70, "hp 30+40=70")
	failed += _expect(srv.inventory.get_qty("bandage") == 1, "qty to 1")

	if failed == 0:
		print("test_bandage: PASS")
		quit(0)
		return
	print("test_bandage: FAIL count=%d" % failed)
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
