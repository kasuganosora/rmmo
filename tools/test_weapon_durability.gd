extends SceneTree
## Headless: equipped weapon durability — wear on damaging hit, break+remove at 0, tip, repair.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_weapon_durability: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null or srv.equipment == null or srv.combat_engine == null or srv.item_catalog == null:
		print("test_weapon_durability: FAIL combat layers missing")
		quit(1)
		return

	# Catalog sample
	var def: Dictionary = srv.item_catalog.get_item("wooden_sword")
	failed += _expect(not def.is_empty(), "catalog has wooden_sword")
	failed += _expect(str(def.get("name", "")) == "木剑", "Chinese name 木剑")
	failed += _expect(int(def.get("durability_max", 0)) == 100, "durability_max 100")
	failed += _expect(srv.equipment.has_method("wear_weapon"), "equipment.wear_weapon")

	# Tip format (inventory/HUD reuse)
	var tip_line := "耐久：%d/%d" % [100, 100]
	failed += _expect(tip_line == "耐久：100/100", "tip format 耐久：x/y")

	srv.awaiting_respawn = false
	srv.sitting = false
	if srv.combat_stats != null:
		srv.combat_stats.player["hp"] = maxi(int(srv.combat_stats.player.get("hp_max", 100)), 1)
		srv.combat_stats.player["mp"] = maxi(int(srv.combat_stats.player.get("mp_max", 50)), 1)

	# Force hit, no crit
	srv.combat_randf = func() -> float: return 0.5
	if srv.combat_engine != null:
		srv.combat_engine.combat_randf = func() -> float: return 0.5

	# --- Equip: durability init 100/100 ---
	srv.inventory.clear()
	srv.inventory.add_gold(300)
	srv.inventory.add_item("wooden_sword", 1)
	srv.inventory.add_item("repair_kit", 2)
	srv.equipment.clear()
	var r_eq: Dictionary = srv.try_equip_item("wooden_sword", "weapon_main")
	failed += _expect(bool(r_eq.get("ok", false)), "equip wooden_sword")
	failed += _expect(srv.equipment.get_item_in("weapon_main") == "wooden_sword", "main has sword")
	failed += _expect(srv.equipment.get_durability("weapon_main") == 100, "dur 100")
	failed += _expect(srv.equipment.get_durability_max("weapon_main") == 100, "max 100")
	var snap0: Array = srv.equipment.snapshot()
	var found := false
	for row in snap0:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("slot", "")) != "weapon_main":
			continue
		failed += _expect(int(row.get("durability", 0)) == 100, "snapshot durability 100")
		failed += _expect(int(row.get("durability_max", 0)) == 100, "snapshot durability_max 100")
		found = true
	failed += _expect(found, "snapshot has weapon_main")

	# Spawn a durable hostile near player
	srv.set_player_cell(10, 10)
	if srv.combat_stats != null:
		srv.combat_stats.ensure_npc("dur_mob", true)
		srv.combat_stats.npcs["dur_mob"]["hp"] = 5000
		srv.combat_stats.npcs["dur_mob"]["hp_max"] = 5000
		srv.combat_stats.npcs["dur_mob"]["hostile"] = true
		srv.combat_stats.npcs["dur_mob"]["name"] = "耐久靶"
		if srv.combat_stats.has_method("set_npc_cell"):
			srv.combat_stats.set_npc_cell("dur_mob", 10, 11)
	if srv.has_method("register_npc"):
		srv.register_npc("dur_mob", 10, 11, true, false, 2, 0, 0, {
			"id": "dur_mob", "name": "耐久靶", "kind": "npc", "hostile": true,
		})

	# Clear attack CD
	if srv.combat_stats != null and srv.combat_stats.has_method("set_attack_cooldown"):
		srv.combat_stats.set_attack_cooldown(0.0)
	if srv.combat_stats != null and srv.combat_stats.has_method("set_skill_cooldown"):
		srv.combat_stats.set_skill_cooldown("basic_attack", 0.0)

	# --- Successful auto-attack wears 1 ---
	var r1: Dictionary = srv.try_attack("dur_mob", 10, 10)
	failed += _expect(bool(r1.get("ok", false)), "attack ok")
	failed += _expect(_has(r1, "damage"), "damage action")
	failed += _expect(srv.equipment.get_durability("weapon_main") == 99, "dur 99 after hit")
	failed += _expect(srv.equipment.get_item_in("weapon_main") == "wooden_sword", "still equipped")
	failed += _expect(not bool(r1.get("weapon_broke", false)), "not broke yet")
	failed += _expect(_has(r1, "equipment_update"), "equipment_update on wear")

	# Miss does not wear
	srv.combat_randf = func() -> float: return 0.99
	if srv.combat_engine != null:
		srv.combat_engine.combat_randf = func() -> float: return 0.99
	if srv.combat_stats != null and srv.combat_stats.has_method("set_attack_cooldown"):
		srv.combat_stats.set_attack_cooldown(0.0)
	var r_miss: Dictionary = srv.try_attack("dur_mob", 10, 10)
	failed += _expect(_has(r_miss, "miss") or _msg_has(r_miss, "未命中"), "miss")
	failed += _expect(srv.equipment.get_durability("weapon_main") == 99, "miss no wear")

	# Restore force-hit
	srv.combat_randf = func() -> float: return 0.5
	if srv.combat_engine != null:
		srv.combat_engine.combat_randf = func() -> float: return 0.5

	# --- Break at 0 ---
	srv.equipment._durability["weapon_main"] = 1
	srv.equipment._durability_max["weapon_main"] = 100
	if srv.combat_stats != null and srv.combat_stats.has_method("set_attack_cooldown"):
		srv.combat_stats.set_attack_cooldown(0.0)
	var r_break: Dictionary = srv.try_attack("dur_mob", 10, 10)
	failed += _expect(bool(r_break.get("ok", false)), "attack on last dur ok")
	failed += _expect(srv.equipment.get_item_in("weapon_main") == "", "weapon removed on break")
	failed += _expect(srv.inventory.get_qty("wooden_sword") == 0, "not returned to bag")
	failed += _expect(_msg_has(r_break, "武器已损坏。"), "msg 武器已损坏。")
	failed += _expect(_has(r_break, "equipment_update"), "equipment_update on break")

	# Direct API smoke
	srv.inventory.add_item("wooden_sword", 1)
	var r_eq2: Dictionary = srv.try_equip_item("wooden_sword", "weapon_main")
	failed += _expect(bool(r_eq2.get("ok", false)), "re-equip")
	srv.equipment._durability["weapon_main"] = 5
	var wr: Dictionary = srv.equipment.wear_weapon(1)
	failed += _expect(bool(wr.get("ok", false)), "wear_weapon ok")
	failed += _expect(int(wr.get("durability", 0)) == 4, "API dur 4")
	failed += _expect(not bool(wr.get("broken", true)), "API not broken")

	# --- repair_kit repairs equipped weapon ---
	srv.equipment._durability["weapon_main"] = 40
	if srv.combat_stats != null and srv.combat_stats.has_method("set_item_cooldown"):
		srv.combat_stats.set_item_cooldown("repair_kit", 0.0)
	var r_kit: Dictionary = srv.try_use_item("repair_kit")
	failed += _expect(bool(r_kit.get("ok", false)), "repair_kit ok")
	# +30% of 100 = 30 → 40+30=70
	failed += _expect(srv.equipment.get_durability("weapon_main") == 70, "kit 40+30=70")
	failed += _expect(_msg_has(r_kit, "修理工具包") or _msg_has(r_kit, "修复了装备"), "kit Chinese msg")

	# --- Blacksmith try_repair ---
	srv.equipment._durability["weapon_main"] = 80
	var gold_before: int = srv.inventory.get_gold()
	var r_bs: Dictionary = srv.try_repair("weapon_main", 1)
	failed += _expect(bool(r_bs.get("ok", false)), "blacksmith repair weapon ok")
	failed += _expect(srv.equipment.get_durability("weapon_main") == 100, "weapon full 100")
	failed += _expect(srv.inventory.get_gold() == gold_before - 20, "spent 20G for 20 points")

	# --- AoE skill: weapon wear once per cast, not per hit ---
	srv.equipment.clear()
	srv.inventory.add_item("wooden_sword", 1)
	var r_eq3: Dictionary = srv.try_equip_item("wooden_sword", "weapon_main")
	failed += _expect(bool(r_eq3.get("ok", false)), "aoe re-equip")
	failed += _expect(srv.equipment.get_item_in("weapon_main") == "wooden_sword", "aoe main has sword")
	srv.equipment._durability["weapon_main"] = 50
	srv.equipment._durability_max["weapon_main"] = 100
	if srv.combat_engine != null:
		srv.combat_engine.combat_randf = func() -> float: return 0.0  # always hit
	var st = srv.combat_stats
	st.ensure_npc("aoe_a", true, true)
	st.ensure_npc("aoe_b", true, true)
	st.set_npc_cell("aoe_a", 1, 0)
	st.set_npc_cell("aoe_b", 2, 0)
	st.npcs["aoe_a"]["hp"] = 200
	st.npcs["aoe_a"]["hp_max"] = 200
	st.npcs["aoe_a"]["hostile"] = true
	st.npcs["aoe_b"]["hp"] = 200
	st.npcs["aoe_b"]["hp_max"] = 200
	st.npcs["aoe_b"]["hostile"] = true
	var eng = srv.combat_engine
	var aoe_def: Dictionary = {}
	if srv.skill_catalog != null:
		aoe_def = srv.skill_catalog.get_skill("flame_burst")
	if aoe_def.is_empty():
		aoe_def = {"id": "flame_burst", "effect": "aoe_damage", "power": 1.0, "aoe_radius": 2, "max_targets": 8, "requires_target": true}
	if eng != null:
		eng.gear = srv.equipment
		if eng.stats == null:
			eng.stats = st
	var acts: Array = []
	if eng != null and eng.has_method("_resolve_skill_effect"):
		eng._resolve_skill_effect(aoe_def, "flame_burst", "aoe_a", 0, 0, acts, 1, 0, "player")
		var dur_after: int = int(srv.equipment.get_durability("weapon_main"))
		var hits := 0
		for a in acts:
			if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "damage" and str(a.get("target", "")) == "npc":
				hits += 1
		failed += _expect(hits >= 2, "aoe hit >=2 targets got %d" % hits)
		failed += _expect(dur_after == 49, "aoe wear once (50→49) got %d" % dur_after)
	else:
		failed += _expect(false, "engine missing _resolve_skill_effect")

	# Cleanup
	srv.combat_randf = Callable()
	if srv.combat_engine != null:
		srv.combat_engine.combat_randf = Callable()
	srv.equipment.clear()
	srv.awaiting_respawn = false

	if failed == 0:
		print("test_weapon_durability: PASS")
		quit(0)
		return
	print("test_weapon_durability: FAIL count=%d" % failed)
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
