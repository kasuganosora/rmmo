extends SceneTree
## Headless: equipment durability (death wear), broken bonuses, try_repair, blacksmith NPC.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_durability: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null or srv.equipment == null or srv.combat_stats == null:
		print("test_durability: FAIL combat layers missing")
		quit(1)
		return

	failed += _expect(srv.equipment.has_method("apply_death_wear"), "has apply_death_wear")
	failed += _expect(srv.has_method("try_repair"), "has try_repair")

	# --- equip defaults durability 100 ---
	srv.awaiting_respawn = false
	srv.sitting = false
	srv.inventory.clear()
	srv.inventory.add_gold(500)
	srv.inventory.add_item("wooden_sword", 1)
	srv.inventory.add_item("leather_vest", 1)
	srv.equipment.clear()
	var r_eq: Dictionary = srv.try_equip_item("wooden_sword", "weapon_main")
	failed += _expect(bool(r_eq.get("ok", false)), "equip sword")
	var r_vest: Dictionary = srv.try_equip_item("leather_vest", "chest")
	failed += _expect(bool(r_vest.get("ok", false)), "equip vest")
	failed += _expect(srv.equipment.get_durability("weapon_main") == 100, "sword dur 100")
	failed += _expect(srv.equipment.get_durability_max("weapon_main") == 100, "sword max 100")
	failed += _expect(srv.equipment.get_durability("chest") == 100, "vest dur 100")
	var snap0: Array = srv.equipment.snapshot()
	var found_dur := false
	for row in snap0:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("slot", "")) == "weapon_main":
			failed += _expect(int(row.get("durability", 0)) == 100, "snapshot durability")
			failed += _expect(int(row.get("durability_max", 0)) == 100, "snapshot durability_max")
			failed += _expect(not bool(row.get("broken", true)), "snapshot not broken")
			found_dur = true
	failed += _expect(found_dur, "snapshot has weapon_main")
	var bons0: Dictionary = srv.equipment.total_bonuses()
	failed += _expect(int(bons0.get("p_atk", 0)) >= 3, "bonuses include sword p_atk")

	# --- death wear 10% (min 1) ---
	srv.death_drop_randf = func() -> float: return 0.0
	srv.combat_stats.player["hp"] = 0
	srv.awaiting_respawn = false
	var r_die: Dictionary = srv._finalize_combat_result({
		"ok": true,
		"actions": [{"type": "player_died"}],
	})
	failed += _expect(srv.awaiting_respawn, "awaiting after death")
	failed += _expect(_msg_has(r_die, "装备因死亡受损。"), "death wear message")
	failed += _expect(_has(r_die, "equipment_update"), "equipment_update on death")
	# 10% of 100 = 10 → 90
	failed += _expect(srv.equipment.get_durability("weapon_main") == 90, "sword after death 90")
	failed += _expect(srv.equipment.get_durability("chest") == 90, "vest after death 90")

	# Respawn so repair/dead checks pass
	if srv.has_method("try_respawn"):
		srv.try_respawn("town")
	else:
		srv.awaiting_respawn = false
		srv.combat_stats.restore_after_death(false)

	# --- force broken: exclude from bonuses ---
	srv.equipment._durability["weapon_main"] = 0
	failed += _expect(srv.equipment.is_broken("weapon_main"), "sword broken")
	var bons_b: Dictionary = srv.equipment.total_bonuses()
	failed += _expect(int(bons_b.get("p_atk", 0)) == 0, "broken sword no p_atk")
	# vest still contributes p_def if any
	var vest_def := int(srv.item_catalog.get_item("leather_vest").get("bonuses", {}).get("p_def", 0))
	if vest_def > 0:
		failed += _expect(int(bons_b.get("p_def", 0)) == vest_def, "vest still gives p_def")

	# --- repair all ---
	var gold_before: int = srv.inventory.get_gold()
	# sword needs 100, vest needs 10 → 110 points @ 1G
	var r_rep: Dictionary = srv.try_repair("all", 1)
	failed += _expect(bool(r_rep.get("ok", false)), "repair all ok")
	failed += _expect(srv.equipment.get_durability("weapon_main") == 100, "sword repaired")
	failed += _expect(srv.equipment.get_durability("chest") == 100, "vest repaired")
	failed += _expect(not srv.equipment.is_broken("weapon_main"), "sword not broken")
	failed += _expect(int(bons0.get("p_atk", 0)) == int(srv.equipment.total_bonuses().get("p_atk", 0)), "p_atk restored")
	failed += _expect(srv.inventory.get_gold() == gold_before - 110, "gold spent 110")
	failed += _expect(_msg_has(r_rep, "装备已全部修理"), "repair msg")
	failed += _expect(_has(r_rep, "equipment_update"), "repair equipment_update")

	# --- already full ---
	var r_full: Dictionary = srv.try_repair("all", 1)
	failed += _expect(not bool(r_full.get("ok", true)), "already full fails")
	failed += _expect(str(r_full.get("reason", "")) == "nothing_to_repair", "reason nothing_to_repair")

	# --- single slot + no gold ---
	srv.equipment._durability["weapon_main"] = 50
	srv.inventory.clear()
	srv.inventory.add_gold(10)
	var r_poor: Dictionary = srv.try_repair("weapon_main", 1)
	failed += _expect(not bool(r_poor.get("ok", true)), "no_gold fails")
	failed += _expect(str(r_poor.get("reason", "")) == "no_gold", "reason no_gold")
	failed += _expect(srv.equipment.get_durability("weapon_main") == 50, "dur unchanged when poor")
	failed += _expect(srv.inventory.get_gold() == 10, "gold unchanged when poor")

	srv.inventory.add_gold(100)
	var r_one: Dictionary = srv.try_repair("weapon_main", 1)
	failed += _expect(bool(r_one.get("ok", false)), "repair one slot ok")
	failed += _expect(srv.equipment.get_durability("weapon_main") == 100, "slot repaired to 100")
	failed += _expect(srv.inventory.get_gold() == 60, "spent 50 for one slot")

	# --- dialogue repair:all:1 ---
	srv.equipment._durability["chest"] = 95
	srv.inventory.clear()
	srv.inventory.add_gold(20)
	var r_ch: Dictionary = srv.try_dialogue_choice("repair:all:1")
	failed += _expect(bool(r_ch.get("ok", false)), "dialogue repair ok")
	failed += _expect(srv.equipment.get_durability("chest") == 100, "dialogue repaired chest")
	failed += _expect(srv.inventory.get_gold() == 15, "dialogue spent 5")

	# --- blacksmith NPC interact ---
	srv.npc_meta["blacksmith"] = {
		"name": "铁匠",
		"interact_text": "需要修理吗？",
		"shop_id": "",
		"blacksmith": true,
		"repair_cost_per_point": 1,
	}
	if srv.combat_stats.has_method("set_npc_cell"):
		srv.combat_stats.set_npc_cell("blacksmith", 14, 12)
	srv.set_player_cell(14, 13)
	var r_npc: Dictionary = srv.try_interact("blacksmith", 14, 13)
	failed += _expect(bool(r_npc.get("ok", false)), "interact blacksmith ok")
	failed += _expect(_has(r_npc, "show_npc_dialogue"), "show dialogue")
	var found_opt := false
	for a in r_npc.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "show_npc_dialogue":
			continue
		for o in a.get("options", []):
			if typeof(o) == TYPE_DICTIONARY and str(o.get("id", "")).begins_with("repair"):
				found_opt = true
	failed += _expect(found_opt, "dialogue has repair option")

	# Cleanup
	srv.death_drop_randf = Callable()
	srv.equipment.clear()
	srv.awaiting_respawn = false

	if failed == 0:
		print("test_durability: PASS")
		quit(0)
		return
	print("test_durability: FAIL count=%d" % failed)
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
