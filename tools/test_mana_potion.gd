extends SceneTree
## Headless: mana_potion「魔力药水」→ heal_mp 50; in/out combat; CD 6s; full MP fail; shop.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_mana_potion: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.item_catalog == null or srv.inventory == null or srv.combat_engine == null or srv.combat_stats == null:
		print("test_mana_potion: FAIL combat layers missing")
		quit(1)
		return

	var engine = srv.combat_engine
	var stats = srv.combat_stats
	const IID := "mana_potion"

	# Catalog
	var def: Dictionary = srv.item_catalog.get_item(IID)
	failed += _expect(not def.is_empty(), "catalog has mana_potion")
	failed += _expect(str(def.get("name", "")) == "魔力药水", "Chinese name 魔力药水")
	var ue := str(def.get("use_effect", def.get("effect", "")))
	failed += _expect(ue == "heal_mp", "use_effect heal_mp")
	failed += _expect(bool(def.get("consumable", false)), "consumable")
	failed += _expect(str(def.get("type", "")) == "consumable", "type consumable")
	failed += _expect(int(def.get("amount", 0)) == 50, "restore amount 50 flat")
	failed += _expect(abs(float(def.get("cooldown", 0.0)) - 6.0) < 0.01, "cooldown 6s")
	failed += _expect(not bool(def.get("out_of_combat_only", false)), "usable in combat")
	failed += _expect(int(def.get("icon_index", -1)) == 33, "reuse blue potion icon_index 33")
	failed += _expect(int(def.get("sell_price", 0)) <= 5, "cheap sell_price")

	# Shop stock
	if srv.shop_catalog != null and srv.shop_catalog.has_method("sells_item"):
		failed += _expect(srv.shop_catalog.sells_item("starter_goods", IID), "shop sells mana_potion")

	srv.awaiting_respawn = false
	srv.sitting = false
	if engine.has_method("reset_dps_fight"):
		engine.reset_dps_fight()
	if stats.statuses != null:
		if stats.statuses.has_method("clear_everything"):
			stats.statuses.clear_everything()
		else:
			stats.statuses.clear_all("player")

	stats.player["mp_max"] = 100
	stats.player["mp"] = 20
	stats.player["hp_max"] = 100
	stats.player["hp"] = 100
	failed += _expect(not engine.player_in_combat(), "baseline not in combat")

	srv.inventory.clear()
	srv.inventory.add_item(IID, 4)
	failed += _expect(srv.inventory.get_qty(IID) == 4, "qty start 4")
	if stats.has_method("set_item_cooldown"):
		stats.set_item_cooldown(IID, 0.0)

	# Use out of combat: +50 MP, consume, clamp later
	var r: Dictionary = srv.try_use_item(IID)
	failed += _expect(bool(r.get("ok", false)), "use mana_potion ok ooc")
	failed += _expect(int(stats.player.get("mp", 0)) == 70, "mp 20+50=70")
	failed += _expect(srv.inventory.get_qty(IID) == 3, "qty decremented to 3")
	failed += _expect(_has(r, "inventory_update"), "inventory_update")
	failed += _expect(_has(r, "heal") or _msg_has(r, "魔力药水") or _msg_has(r, "使用了"), "heal float or Chinese use msg")

	# Cooldown ~6s blocks
	var r_cd: Dictionary = srv.try_use_item(IID)
	failed += _expect(not bool(r_cd.get("ok", true)), "on cooldown rejected")
	failed += _expect(srv.inventory.get_qty(IID) == 3, "qty unchanged on CD")
	failed += _expect(int(stats.player.get("mp", 0)) == 70, "mp unchanged on CD")

	# Clear CD; use in combat OK
	if stats.has_method("set_item_cooldown"):
		stats.set_item_cooldown(IID, 0.0)
	if engine.has_method("note_dps_hit"):
		engine.note_dps_hit(5)
	failed += _expect(engine.player_in_combat(), "in combat via dps")
	var r_combat: Dictionary = srv.try_use_item(IID)
	failed += _expect(bool(r_combat.get("ok", false)), "usable in combat")
	failed += _expect(int(stats.player.get("mp", 0)) == 100, "mp 70+50 clamp 100")
	failed += _expect(srv.inventory.get_qty(IID) == 2, "qty to 2 after combat use")

	# Full MP: fail without consume
	if stats.has_method("set_item_cooldown"):
		stats.set_item_cooldown(IID, 0.0)
	stats.player["mp"] = int(stats.player.get("mp_max", 100))
	var r_full: Dictionary = srv.try_use_item(IID)
	failed += _expect(not bool(r_full.get("ok", true)), "full MP rejected")
	failed += _expect(str(r_full.get("reason", "")) == "mp_full" or _msg_has(r_full, "魔力已满。"), "reason/msg 魔力已满。")
	failed += _expect(_msg_has(r_full, "魔力已满。"), "msg 魔力已满。")
	failed += _expect(srv.inventory.get_qty(IID) == 2, "qty unchanged when full")

	# Partial restore clamps to max
	if stats.has_method("set_item_cooldown"):
		stats.set_item_cooldown(IID, 0.0)
	stats.player["mp"] = 80
	var r_clamp: Dictionary = srv.try_use_item(IID)
	failed += _expect(bool(r_clamp.get("ok", false)), "partial use ok")
	failed += _expect(int(stats.player.get("mp", 0)) == 100, "mp 80+50 clamp 100")
	failed += _expect(srv.inventory.get_qty(IID) == 1, "qty to 1")

	if failed == 0:
		print("test_mana_potion: PASS")
		quit(0)
		return
	print("test_mana_potion: FAIL count=%d" % failed)
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
