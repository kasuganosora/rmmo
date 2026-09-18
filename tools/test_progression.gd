extends SceneTree
## Headless: XP grant + level-up, shop buy/sell, quest kill progress + turn-in.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var CombatStats = load("res://scripts/net/combat/combat_stats.gd")
	var ShopCatalog = load("res://scripts/net/combat/shop_catalog.gd")
	var QuestJournal = load("res://scripts/net/combat/quest_journal.gd")
	var ItemCatalog = load("res://scripts/net/combat/item_catalog.gd")
	var Inventory = load("res://scripts/net/combat/inventory.gd")

	# --- XP / level ---
	var stats = CombatStats.new()
	stats.reset_player(1)
	failed += _expect(int(stats.player.get("level", 0)) == 1, "start lv1")
	failed += _expect(int(stats.player.get("exp_to_next", 0)) == CombatStats.exp_to_next_for(1), "exp_to_next formula")
	var need: int = int(stats.player.get("exp_to_next", 90))
	var sum: Dictionary = stats.grant_exp(need)
	failed += _expect(bool(sum.get("leveled", false)), "leveled on threshold")
	failed += _expect(int(stats.player.get("level", 0)) == 2, "now lv2")
	failed += _expect(int(stats.player.get("hp", 0)) == int(stats.player.get("hp_max", -1)), "heal on level-up")
	var hp_at_2: int = int(stats.player.get("hp_max", 0))
	failed += _expect(hp_at_2 == 80 + 2 * 20, "hp_max scales")
	# Death restore keeps level/exp
	stats.player["hp"] = 0
	stats.restore_after_death(false)
	failed += _expect(int(stats.player.get("level", 0)) == 2, "level persists death")
	failed += _expect(int(stats.player.get("exp", -1)) == int(sum.get("exp", -2)), "exp persists death")

	# --- Shop catalog ---
	var items = ItemCatalog.new()
	items.load_catalog()
	var shop = ShopCatalog.new()
	shop.set_catalog(items)
	shop.load_catalog()
	failed += _expect(shop.has_shop("starter_goods"), "starter_goods shop")
	failed += _expect(shop.buy_price_for("starter_goods", "potion_hp_small") == 10, "potion buy price")
	failed += _expect(shop.buy_price_for("starter_goods", "leather_cap") == 16, "leather_cap default 8*2")

	# --- MockServer shop + exp + quest ---
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_progression: FAIL no MockServer")
		quit(1)
		return
	if srv.quest_journal == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.shop_catalog != null, "server shop_catalog")
	failed += _expect(srv.combat_stats != null, "server combat_stats")
	failed += _expect(srv.inventory != null, "server inventory")

	srv.combat_stats.reset_player(1)
	srv.inventory.clear()
	srv.inventory.grant_starter()
	var gold0: int = srv.inventory.get_gold()
	failed += _expect(gold0 >= 10, "starter gold")

	# Register a slime + vendor adjacency cells
	srv.register_npc("slime", 1, 0, true, false, 2, 0, 0, {"id": "slime", "name": "史莱姆", "hostile": true})
	srv.register_npc("vendor_demo", 0, 1, false, false, 2, 0, 0, {
		"id": "vendor_demo",
		"name": "杂货商人",
		"shop_id": "starter_goods",
		"interact_text": "看看货吧",
	})
	srv.set_player_cell(0, 0)

	# Open shop via interact (direct, or dialogue option when quest offers exist)
	var inter: Dictionary = srv.try_interact("vendor_demo", 0, 0)
	failed += _expect(bool(inter.get("ok", false)), "interact vendor ok")
	var shop_ok := _has_type(inter.get("actions", []), "open_shop")
	if not shop_ok and srv.has_method("try_dialogue_choice"):
		var shop_opt := ""
		for a in inter.get("actions", []):
			if typeof(a) != TYPE_DICTIONARY or str(a.get("type", "")) != "show_npc_dialogue":
				continue
			for opt in a.get("options", []):
				if typeof(opt) == TYPE_DICTIONARY and str(opt.get("id", "")).begins_with("shop_open:"):
					shop_opt = str(opt.get("id", ""))
		if shop_opt != "":
			var opened: Dictionary = srv.try_dialogue_choice(shop_opt)
			shop_ok = _has_type(opened.get("actions", []), "open_shop")
	failed += _expect(shop_ok, "open_shop action")

	var buy: Dictionary = srv.try_shop_buy("starter_goods", "potion_hp_small", 1)
	failed += _expect(bool(buy.get("ok", false)), "buy potion ok")
	failed += _expect(srv.inventory.get_gold() == gold0 - 10, "gold spent")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") >= 6, "potion added")

	# Ensure sellable material
	srv.inventory.add_item("slime_jelly", 2)
	var sell: Dictionary = srv.try_shop_sell("slime_jelly", 1)
	failed += _expect(bool(sell.get("ok", false)), "sell jelly ok")
	failed += _expect(srv.inventory.get_qty("slime_jelly") == 1, "jelly qty-1")

	# Quest kill progress
	srv.quest_journal.clear()
	srv.quest_journal.load_catalog()
	srv.quest_journal.accept_quest("slime_hunt")
	srv.quest_journal.accept_quest("starter_step")
	var q0: Dictionary = srv.quest_journal.get_quest("slime_hunt")
	var objs0: Array = q0.get("objectives", [])
	failed += _expect(int(objs0[0].get("cur", -1)) == 0, "slime_hunt starts 0")
	failed += _expect(srv.quest_journal.note_kill("street_slime"), "note_kill street_slime")
	var q1: Dictionary = srv.quest_journal.get_quest("slime_hunt")
	failed += _expect(int(q1.get("objectives", [])[0].get("cur", 0)) == 1, "kill progress 1")
	srv.quest_journal.note_kill("slime")
	srv.quest_journal.note_kill("street_slime")
	# item collect
	srv.quest_journal.note_item_gain("slime_jelly", 2)
	var q2: Dictionary = srv.quest_journal.get_quest("slime_hunt")
	failed += _expect(str(q2.get("status", "")) == "ready", "slime_hunt ready")

	var turn: Dictionary = srv.try_turn_in_quest("slime_hunt")
	failed += _expect(bool(turn.get("ok", false)), "turn-in ok")
	failed += _expect(_has_type(turn.get("actions", []), "quest_update"), "quest_update on turn-in")
	failed += _expect(_has_type(turn.get("actions", []), "exp_gain"), "exp_gain on turn-in")
	var q3: Dictionary = srv.quest_journal.get_quest("slime_hunt")
	failed += _expect(str(q3.get("status", "")) == "completed", "slime_hunt completed")

	# grant_kill_exp via finalize path
	srv.combat_stats.reset_player(1)
	srv.combat_stats.ensure_npc("slime", true)
	srv.combat_stats.npcs["slime"]["level"] = 2
	srv.combat_stats.npcs["slime"]["hp"] = 1
	srv.combat_stats.set_npc_cell("slime", 1, 0)
	srv.set_player_cell(0, 0)
	srv.combat_stats.attack_ready_at = 0.0
	srv.combat_randf = func() -> float: return 0.5  # force hit, no crit
	var atk: Dictionary = srv.try_attack("slime", 0, 0)
	# May or may not kill depending on damage; force finalize with kill if needed
	if not _has_type(atk.get("actions", []), "kill_npc"):
		var fake := {"ok": true, "actions": [{"type": "kill_npc", "npc_id": "slime"}]}
		atk = srv._finalize_combat_result(fake)
	failed += _expect(_has_type(atk.get("actions", []), "exp_gain"), "exp_gain on kill")
	failed += _expect(_has_msg_contains(atk.get("actions", []), "获得经验"), "chinese exp chat")

	if failed == 0:
		print("test_progression: PASS")
		quit(0)
	else:
		print("test_progression: FAIL count=%d" % failed)
		quit(1)


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _has_msg_contains(actions: Array, frag: String) -> bool:
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(frag) >= 0:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
