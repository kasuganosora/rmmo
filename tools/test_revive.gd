extends SceneTree
## Headless: revive「复活」— dead party/ally ~30% HP; MP25 CD30 range4.

const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _expect(true, "boot")

	var skills = SkillCatalog.new()
	skills.load_catalog()
	var items = ItemCatalog.new()
	items.load_catalog()
	var bag = Inventory.new()
	bag.grant_starter()

	# --- Catalog ---
	failed += _expect(skills.has_skill("revive"), "catalog has revive")
	var def: Dictionary = skills.get_skill("revive")
	failed += _expect(str(def.get("name", "")) == "复活", "name 复活")
	failed += _expect(str(def.get("category", "")) == "magic", "category magic")
	failed += _expect(str(def.get("effect", "")) == "revive", "effect revive")
	failed += _expect(int(def.get("mp_cost", 0)) == 25, "mp_cost 25")
	failed += _expect(abs(float(def.get("cooldown", 0.0)) - 30.0) < 0.01, "cooldown 30s")
	failed += _expect(int(def.get("range", 0)) == 4, "range 4")
	failed += _expect(abs(float(def.get("heal_pct", 0.0)) - 0.3) < 0.001, "heal_pct 0.3")
	failed += _expect(float(def.get("cast_time", 0.0)) <= 0.0, "instant no cast_time")
	failed += _expect(bool(def.get("requires_target", false)), "requires_target")
	failed += _expect(not bool(def.get("starter", true)), "learnable not starter")
	failed += _expect(int(def.get("sp_cost", 0)) >= 1, "sp_cost learnable")

	# --- Builtin fallback ---
	var fb = SkillCatalog.new()
	fb._load_builtin_fallback()
	failed += _expect(fb.has_skill("revive"), "fallback has revive")
	failed += _expect(str(fb.get_skill("revive").get("name", "")) == "复活", "fallback name")
	failed += _expect(int(fb.get_skill("revive").get("mp_cost", 0)) == 25, "fallback mp 25")

	# --- Engine: ally NPC revive ---
	var stats = CombatStats.new()
	stats.reset_player(3)
	if stats.has_method("set_player_actor_id"):
		stats.set_player_actor_id("player")
	var engine = CombatEngine.new()
	engine.setup(stats, skills, items, bag)
	engine.combat_randf = func() -> float: return 0.5
	stats.ensure_skill_book()
	if stats.skill_book.list_known().is_empty():
		stats.skill_book.grant_starters(skills)
	stats.skill_book.grant_skill_points(99)
	failed += _expect(not stats.skill_book.is_known("revive"), "not known before learn")
	var learn: Dictionary = stats.skill_book.try_learn("revive", skills, 99)
	failed += _expect(bool(learn.get("ok", false)), "learn ok")
	failed += _expect(stats.skill_book.is_known("revive"), "known after learn")

	stats.ensure_npc("ally_a", false, false)
	stats.set_npc_cell("ally_a", 2, 0)
	stats.npcs["ally_a"]["name"] = "盟友甲"
	stats.npcs["ally_a"]["ally"] = true
	stats.npcs["ally_a"]["hostile"] = false
	stats.npcs["ally_a"]["hp"] = 0
	stats.npcs["ally_a"]["hp_max"] = 100
	stats.npcs["ally_a"]["awaiting_respawn"] = true
	stats.player["mp"] = 50
	stats.player["mp_max"] = 50
	stats.skill_ready_at.clear()
	var mp_before: int = int(stats.player.get("mp", 0))
	var cast: Dictionary = engine.try_use_skill("revive", "ally_a", 0, 0)
	failed += _expect(bool(cast.get("ok", false)), "engine cast revive ok")
	failed += _expect(int(stats.player.get("mp", 0)) == mp_before - 25, "engine spent mp 25")
	failed += _expect(int(stats.npcs["ally_a"].get("hp", 0)) == 30, "engine hp ~30% (30/100)")
	failed += _expect(not bool(stats.npcs["ally_a"].get("awaiting_respawn", true)), "engine cleared awaiting")
	failed += _expect(_has_msg(cast.get("actions", []), "复活了盟友甲！"), "engine log 复活了盟友甲！")
	failed += _expect(not stats.is_skill_ready("revive"), "engine on cooldown")
	# Death cell kept
	var cell: Vector2i = stats.get_npc_cell("ally_a")
	failed += _expect(cell.x == 2 and cell.y == 0, "engine kept death cell")

	# Reject: not dead
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.npcs["ally_a"]["hp"] = 50
	stats.npcs["ally_a"]["awaiting_respawn"] = false
	var alive_r: Dictionary = engine.try_use_skill("revive", "ally_a", 0, 0)
	failed += _expect(not bool(alive_r.get("ok", true)), "engine not-dead rejected")
	failed += _expect(_has_msg(alive_r.get("actions", []), "目标未死亡"), "engine not-dead msg")

	# Reject: OOR
	stats.npcs["ally_a"]["hp"] = 0
	stats.npcs["ally_a"]["awaiting_respawn"] = true
	stats.set_npc_cell("ally_a", 20, 20)
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var far: Dictionary = engine.try_use_skill("revive", "ally_a", 0, 0)
	failed += _expect(not bool(far.get("ok", true)), "engine oor rejected")
	failed += _expect(_has_msg(far.get("actions", []), "目标太远"), "engine oor msg")
	stats.set_npc_cell("ally_a", 2, 0)

	# Reject: not ally (hostile)
	stats.ensure_npc("slime_x", true, true)
	stats.set_npc_cell("slime_x", 1, 0)
	stats.npcs["slime_x"]["hp"] = 0
	stats.npcs["slime_x"]["awaiting_respawn"] = true
	stats.npcs["slime_x"]["ally"] = false
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var foe: Dictionary = engine.try_use_skill("revive", "slime_x", 0, 0)
	failed += _expect(not bool(foe.get("ok", true)), "engine non-ally rejected")
	failed += _expect(_has_msg(foe.get("actions", []), "只能复活队友"), "engine non-ally msg")

	# Reject: self
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var self_r: Dictionary = engine.try_use_skill("revive", "player", 0, 0)
	failed += _expect(not bool(self_r.get("ok", true)), "engine self rejected")
	failed += _expect(_has_msg(self_r.get("actions", []), "无法自我复活"), "engine self msg")

	# Reject: no MP
	stats.npcs["ally_a"]["hp"] = 0
	stats.npcs["ally_a"]["awaiting_respawn"] = true
	stats.skill_ready_at.clear()
	stats.player["mp"] = 10
	var nomp: Dictionary = engine.try_use_skill("revive", "ally_a", 0, 0)
	failed += _expect(not bool(nomp.get("ok", true)), "engine no-mp rejected")
	failed += _expect(_has_msg(nomp.get("actions", []), "MP 不足"), "engine no-mp msg")

	# --- MockServer: party stub ally ---
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		failed += _expect(false, "MockServer present")
	else:
		if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
			srv._init_combat_layers()
		if srv.combat_stats != null:
			srv.combat_stats.reset_player(3)
			if srv.combat_stats.has_method("set_player_actor_id"):
				srv.combat_stats.set_player_actor_id("1")
			srv.combat_stats.ensure_skill_book()
			if srv.combat_stats.skill_book.list_known().is_empty():
				srv.combat_stats.skill_book.grant_starters(srv.skill_catalog if srv.skill_catalog else skills)
			srv.combat_stats.skill_book.grant_skill_points(99)
			if not srv.combat_stats.skill_book.is_known("revive"):
				var lr2: Dictionary = srv.combat_stats.skill_book.try_learn(
					"revive", srv.skill_catalog if srv.skill_catalog else skills, 99
				)
				failed += _expect(bool(lr2.get("ok", false)), "srv learn ok")
			srv.combat_stats.player["mp"] = 80
			srv.combat_stats.player["mp_max"] = 80
			srv.combat_stats.player["hp"] = 100
			srv.combat_stats.skill_ready_at.clear()
		srv.awaiting_respawn = false
		srv.set_player_cell(10, 10)
		if srv.has_method("_party_clear"):
			srv._party_clear()
		var cr: Dictionary = srv.try_party_create()
		failed += _expect(bool(cr.get("ok", false)), "party create ok")
		var stub: Dictionary = srv._party_make_stub("stub_ally_revive")
		stub["name"] = "队友丁"
		stub["hp_max"] = 200
		stub["hp"] = 200
		srv._party_members.append(stub)
		var kill: Dictionary = srv.debug_ally_kill("stub_ally_revive", 12, 10)
		failed += _expect(bool(kill.get("ok", false)), "debug_ally_kill ok")
		var pidx: int = srv._party_find_member_index("stub_ally_revive")
		failed += _expect(pidx >= 0, "stub in party")
		failed += _expect(int(srv._party_members[pidx].get("hp", 1)) == 0, "stub hp 0")
		failed += _expect(bool(srv._party_members[pidx].get("awaiting_respawn", false)), "stub awaiting")

		var mp0: int = int(srv.combat_stats.player.get("mp", 0))
		var rviv: Dictionary = srv.try_use_skill("revive", "stub_ally_revive", 10, 10)
		failed += _expect(bool(rviv.get("ok", false)), "srv revive ok (reason=%s)" % str(rviv.get("reason", "")))
		failed += _expect(int(srv.combat_stats.player.get("mp", 0)) == mp0 - 25, "srv spent mp 25")
		pidx = srv._party_find_member_index("stub_ally_revive")
		var hp_after: int = int(srv._party_members[pidx].get("hp", 0))
		failed += _expect(hp_after == 60, "srv hp ~30pct of 200 (=60) got %s" % str(hp_after))
		failed += _expect(not bool(srv._party_members[pidx].get("awaiting_respawn", true)), "srv cleared awaiting")
		failed += _expect(_has_msg(rviv.get("actions", []), "复活了队友丁！"), "srv log 复活了队友丁！")
		failed += _expect(_has_type(rviv.get("actions", []), "ally_revived"), "srv ally_revived action")
		var cell_v: Variant = srv._party_members[pidx].get("cell", {})
		# Keep death cell or nearest walkable (map_collision may nudge).
		var cx := int(cell_v.get("x", -9999)) if typeof(cell_v) == TYPE_DICTIONARY else -9999
		var cy := int(cell_v.get("y", -9999)) if typeof(cell_v) == TYPE_DICTIONARY else -9999
		failed += _expect(cx > -9990 and cy > -9990, "srv has revive cell")
		failed += _expect(maxi(absi(cx - 12), absi(cy - 10)) <= 3, "srv cell near death (got %s,%s)" % [str(cx), str(cy)])
		failed += _expect(not srv._party_members[pidx].has("death_cell"), "srv cleared death_cell key")

		# Reject: not dead (already revived)
		srv.combat_stats.skill_ready_at.clear()
		srv.combat_stats.player["mp"] = 80
		var again: Dictionary = srv.try_use_skill("revive", "stub_ally_revive", 10, 10)
		failed += _expect(not bool(again.get("ok", true)), "srv not-dead rejected")
		failed += _expect(_has_msg(again.get("actions", []), "目标未死亡"), "srv not-dead msg")

		# Reject: OOR
		srv.debug_ally_kill("stub_ally_revive", 30, 30)
		srv.combat_stats.skill_ready_at.clear()
		srv.combat_stats.player["mp"] = 80
		var oor: Dictionary = srv.try_use_skill("revive", "stub_ally_revive", 10, 10)
		failed += _expect(not bool(oor.get("ok", true)), "srv oor rejected")
		failed += _expect(_has_msg(oor.get("actions", []), "目标太远"), "srv oor msg")

		# Reject: not ally (random id)
		srv.combat_stats.skill_ready_at.clear()
		srv.combat_stats.player["mp"] = 80
		var na: Dictionary = srv.try_use_skill("revive", "stranger_x", 10, 10)
		failed += _expect(not bool(na.get("ok", true)), "srv not-ally rejected")
		failed += _expect(_has_msg(na.get("actions", []), "只能复活队友"), "srv not-ally msg")

		# Reject: dead caster cannot self-revive
		srv.combat_stats.player["hp"] = 0
		srv.awaiting_respawn = true
		srv.combat_stats.skill_ready_at.clear()
		srv.combat_stats.player["mp"] = 80
		var dead_c: Dictionary = srv.try_use_skill("revive", "stub_ally_revive", 10, 10)
		failed += _expect(not bool(dead_c.get("ok", true)), "srv dead-caster rejected")
		failed += _expect(_has_msg(dead_c.get("actions", []), "无法自我复活"), "srv dead-caster msg")
		srv.combat_stats.player["hp"] = 100
		srv.awaiting_respawn = false

		# Reject: no MP
		srv.debug_ally_kill("stub_ally_revive", 11, 10)
		srv.combat_stats.skill_ready_at.clear()
		srv.combat_stats.player["mp"] = 5
		var nm2: Dictionary = srv.try_use_skill("revive", "stub_ally_revive", 10, 10)
		failed += _expect(not bool(nm2.get("ok", true)), "srv no-mp rejected")
		failed += _expect(_has_msg(nm2.get("actions", []), "MP 不足"), "srv no-mp msg")


	# --- Combat death keeps ally corpse → revive ---
	var stats_c = CombatStats.new()
	stats_c.reset_player(3)
	if stats_c.has_method("set_player_actor_id"):
		stats_c.set_player_actor_id("player")
	var engine_c = CombatEngine.new()
	engine_c.setup(stats_c, skills, items, bag)
	engine_c.combat_randf = func() -> float: return 0.0  # hit, no crit
	stats_c.ensure_skill_book()
	if stats_c.skill_book.list_known().is_empty():
		stats_c.skill_book.grant_starters(skills)
	stats_c.skill_book.grant_skill_points(99)
	var learn_c: Dictionary = stats_c.skill_book.try_learn("revive", skills, 99)
	failed += _expect(bool(learn_c.get("ok", false)), "combat-path learn revive")
	stats_c.ensure_npc("ally_combat", false, false)
	stats_c.set_npc_cell("ally_combat", 1, 0)
	stats_c.npcs["ally_combat"]["name"] = "盟友战"
	stats_c.npcs["ally_combat"]["ally"] = true
	stats_c.npcs["ally_combat"]["hostile"] = false
	stats_c.npcs["ally_combat"]["hp"] = 5
	stats_c.npcs["ally_combat"]["hp_max"] = 100
	var kill_acts: Array = []
	var killed := engine_c._damage_npc("ally_combat", 999, kill_acts, false, "player", false)
	failed += _expect(killed, "combat kill ally landed")
	failed += _expect(stats_c.npcs.has("ally_combat"), "ally corpse kept after combat death")
	failed += _expect(int(stats_c.npcs["ally_combat"].get("hp", -1)) == 0, "ally hp 0 corpse")
	failed += _expect(bool(stats_c.npcs["ally_combat"].get("awaiting_respawn", false)), "ally awaiting_respawn")
	failed += _expect(not _has_type(kill_acts, "kill_npc"), "no kill_npc for ally")
	failed += _expect(_has_type(kill_acts, "ally_downed"), "ally_downed action")
	stats_c.player["mp"] = 50
	stats_c.skill_ready_at.clear()
	var rev_c: Dictionary = engine_c.try_use_skill("revive", "ally_combat", 0, 0)
	failed += _expect(bool(rev_c.get("ok", false)), "revive after combat death ok")
	failed += _expect(int(stats_c.npcs["ally_combat"].get("hp", 0)) == 30, "revive after combat ~30% hp")

	if failed == 0:
		print("test_revive: PASS")
		quit(0)
	else:
		print("test_revive: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _has_msg(actions: Array, sub: String) -> bool:
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(sub) >= 0:
			return true
	return false
