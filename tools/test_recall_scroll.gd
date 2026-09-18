extends SceneTree
## Headless: scroll_town consumable → recall to town; qty decrements; fail gates.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_recall_scroll: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.item_catalog == null or srv.inventory == null or srv.combat_engine == null:
		print("test_recall_scroll: FAIL combat layers missing")
		quit(1)
		return

	# Catalog must know scroll_town
	var def: Dictionary = srv.item_catalog.get_item("scroll_town")
	failed += _expect(not def.is_empty(), "catalog has scroll_town")
	failed += _expect(str(def.get("name", "")) == "回城卷轴", "Chinese name")
	var ue := str(def.get("use_effect", def.get("effect", "")))
	failed += _expect(ue == "recall" or ue == "teleport_home", "use_effect recall")

	# Clean bag; grant 2 scrolls
	srv.inventory.clear()
	srv.inventory.add_item("scroll_town", 2)
	failed += _expect(srv.inventory.get_qty("scroll_town") == 2, "qty start 2")

	srv.map_collision = null
	srv.awaiting_respawn = false
	if srv.combat_stats != null:
		srv.combat_stats.player["hp"] = maxi(int(srv.combat_stats.player.get("hp_max", 100)), 1)
	srv.last_safe_cell = Vector2i(12, 8)
	srv.respawn_cell = Vector2i(5, 6)
	srv.set_player_cell(3, 3)
	var before: Vector2i = srv.player_cell

	var r: Dictionary = srv.try_use_item("scroll_town")
	failed += _expect(bool(r.get("ok", false)), "use scroll ok")
	failed += _expect(_has(r, "recall"), "recall action")
	failed += _expect(srv.player_cell == Vector2i(5, 6), "player_cell → respawn")
	failed += _expect(srv.player_cell != before, "cell changed")
	failed += _expect(srv.inventory.get_qty("scroll_town") == 1, "qty decremented to 1")
	failed += _expect(_msg_has(r, "回城卷轴") or _msg_has(r, "使用了"), "Chinese use msg")

	# Already at town: fail, do not consume
	srv.set_player_cell(5, 6)
	var qty1: int = srv.inventory.get_qty("scroll_town")
	var r2: Dictionary = srv.try_use_item("scroll_town")
	failed += _expect(not bool(r2.get("ok", true)), "already safe fails")
	failed += _expect(str(r2.get("reason", "")) == "already_safe", "reason already_safe")
	failed += _expect(_msg_has(r2, "安全点"), "msg 安全点")
	failed += _expect(srv.inventory.get_qty("scroll_town") == qty1, "qty unchanged when already safe")

	# Dead: fail, do not consume
	srv.set_player_cell(3, 3)
	if srv.combat_stats != null:
		srv.combat_stats.player["hp"] = 0
	var qty2: int = srv.inventory.get_qty("scroll_town")
	var r3: Dictionary = srv.try_use_item("scroll_town")
	failed += _expect(not bool(r3.get("ok", true)), "dead fails")
	failed += _expect(str(r3.get("reason", "")) == "dead", "reason dead")
	failed += _expect(_msg_has(r3, "倒下"), "msg 倒下")
	failed += _expect(srv.inventory.get_qty("scroll_town") == qty2, "qty unchanged when dead")

	# awaiting_respawn: fail
	if srv.combat_stats != null:
		srv.combat_stats.player["hp"] = maxi(int(srv.combat_stats.player.get("hp_max", 100)), 1)
	srv.awaiting_respawn = true
	var qty3: int = srv.inventory.get_qty("scroll_town")
	var r4: Dictionary = srv.try_use_item("scroll_town")
	failed += _expect(not bool(r4.get("ok", true)), "awaiting_respawn fails")
	failed += _expect(str(r4.get("reason", "")) == "dead", "reason dead (awaiting)")
	failed += _expect(srv.inventory.get_qty("scroll_town") == qty3, "qty unchanged awaiting")
	srv.awaiting_respawn = false

	# Shop lists scroll (optional)
	if srv.shop_catalog != null and srv.shop_catalog.has_method("sells_item"):
		failed += _expect(srv.shop_catalog.sells_item("starter_goods", "scroll_town"), "shop sells scroll_town")

	# Starter grant includes 1–2 (optional soft check via fresh grant)
	if srv.inventory.has_method("grant_starter"):
		srv.inventory.grant_starter()
		var sq: int = srv.inventory.get_qty("scroll_town")
		failed += _expect(sq >= 1 and sq <= 2, "starter grants 1–2 scrolls (got %d)" % sq)

	if failed == 0:
		print("test_recall_scroll: PASS")
		quit(0)
		return
	print("test_recall_scroll: FAIL count=%d" % failed)
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
