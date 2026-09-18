extends SceneTree
## Headless: charge「冲锋」— leap adjacent, 1.2× physical, brief root; MP12 CD12 range2–6.

const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")


## Minimal collision stub: GridPath uses find_astar_path when present.
class BlockPathCol extends RefCounted:
	func find_astar_path(_start: Vector2i, _goal: Vector2i) -> Array[Vector2i]:
		var empty: Array[Vector2i] = []
		return empty

	func find_astar_path_any(_start: Vector2i, _cands: Array, _goal: Vector2i) -> Array[Vector2i]:
		var empty: Array[Vector2i] = []
		return empty

	func is_valid(_x: int, _y: int) -> bool:
		return true

	func is_landable(_x: int, _y: int) -> bool:
		return true

	func is_extra_blocked(_x: int, _y: int) -> bool:
		return false

	func set_extra_blocked(_x: int, _y: int, _on: bool) -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _expect(true, "boot")

	var stats = CombatStats.new()
	stats.reset_player(3)
	if stats.has_method("set_player_actor_id"):
		stats.set_player_actor_id("player")
	var skills = SkillCatalog.new()
	skills.load_catalog()
	var items = ItemCatalog.new()
	items.load_catalog()
	var bag = Inventory.new()
	bag.grant_starter()
	var engine = CombatEngine.new()
	engine.setup(stats, skills, items, bag)
	engine.combat_randf = func() -> float: return 0.5

	stats.ensure_skill_book()
	if stats.skill_book.list_known().is_empty():
		stats.skill_book.grant_starters(skills)
	stats.skill_book.grant_skill_points(99)

	# --- Catalog ---
	failed += _expect(skills.has_skill("charge"), "catalog has charge")
	var def: Dictionary = skills.get_skill("charge")
	failed += _expect(str(def.get("name", "")) == "冲锋", "name 冲锋")
	failed += _expect(str(def.get("category", "")) == "physical", "category physical")
	failed += _expect(str(def.get("effect", "")) == "charge", "effect charge")
	failed += _expect(int(def.get("mp_cost", 0)) == 12, "mp_cost 12")
	failed += _expect(abs(float(def.get("cooldown", 0.0)) - 12.0) < 0.01, "cooldown 12s")
	failed += _expect(int(def.get("range", 0)) == 6, "range 6")
	failed += _expect(int(def.get("min_range", 0)) == 2, "min_range 2")
	failed += _expect(abs(float(def.get("power", 0.0)) - 1.2) < 0.01, "power 1.2")
	failed += _expect(float(def.get("cast_time", 0.0)) <= 0.0, "instant no cast_time")
	failed += _expect(bool(def.get("requires_target", false)), "requires_target")
	failed += _expect(not bool(def.get("starter", true)), "learnable not starter")
	failed += _expect(int(def.get("sp_cost", 0)) >= 1, "sp_cost learnable")
	var st_def: Dictionary = def.get("status", {}) if typeof(def.get("status", {})) == TYPE_DICTIONARY else {}
	failed += _expect(str(st_def.get("id", "")) == "root", "status id root")
	failed += _expect(str(st_def.get("name", "")) == "定身", "status name 定身")
	failed += _expect(str(st_def.get("kind", "")) == "debuff", "status kind debuff")
	failed += _expect(float(st_def.get("duration", 0.0)) >= 0.5 and float(st_def.get("duration", 9.0)) <= 1.0, "root duration 0.5–1s")

	# --- Builtin fallback ---
	var fb = SkillCatalog.new()
	fb._load_builtin_fallback()
	failed += _expect(fb.has_skill("charge"), "fallback has charge")
	failed += _expect(str(fb.get_skill("charge").get("name", "")) == "冲锋", "fallback name")
	failed += _expect(abs(float(fb.get_skill("charge").get("power", 0.0)) - 1.2) < 0.01, "fallback power")

	# --- Learn via SP ---
	failed += _expect(not stats.skill_book.is_known("charge"), "not known before learn")
	var learn: Dictionary = stats.skill_book.try_learn("charge", skills, 99)
	failed += _expect(bool(learn.get("ok", false)), "learn ok")
	failed += _expect(stats.skill_book.is_known("charge"), "known after learn")

	# --- Setup hostile at (4,0); caster at (0,0) → dist 4 (in 2–6) ---
	stats.ensure_npc("slime_a", true, true)
	stats.ensure_npc_ai("slime_a", 2, true, Vector2i(4, 0), 0)
	stats.set_npc_cell("slime_a", 4, 0)
	stats.npcs["slime_a"]["name"] = "史莱姆"
	stats.npcs["slime_a"]["hp"] = 500
	stats.npcs["slime_a"]["hp_max"] = 500
	stats.npcs["slime_a"]["def"] = 0
	stats.player["atk"] = 40
	stats.player["mp"] = 50
	stats.player["mp_max"] = 50
	stats.skill_ready_at.clear()

	var mp_before: int = int(stats.player.get("mp", 0))
	var hp_before: int = int(stats.npcs["slime_a"].get("hp", 0))
	var cast: Dictionary = engine.try_use_skill("charge", "slime_a", 0, 0)
	failed += _expect(bool(cast.get("ok", false)), "cast charge ok")
	failed += _expect(int(stats.player.get("mp", 0)) == mp_before - 12, "spent mp 12")
	var expected_dmg: int = int(round(40.0 * 1.2))  # 48 with def 0
	var dmg: int = hp_before - int(stats.npcs["slime_a"].get("hp", 0))
	failed += _expect(dmg == expected_dmg, "dmg ~1.2×atk (%d got %d)" % [expected_dmg, dmg])
	failed += _expect(stats.statuses.has_status("slime_a", "root"), "root applied")
	var root: Dictionary = stats.statuses.get_status("slime_a", "root")
	failed += _expect(float(root.get("remaining_sec", 0.0)) >= 0.5 and float(root.get("remaining_sec", 9.0)) <= 1.0, "root remaining 0.5–1s")
	failed += _expect(_has_msg(cast.get("actions", []), "冲锋了史莱姆！"), "log 冲锋了史莱姆！")
	failed += _expect(_has_type(cast.get("actions", []), "player_move"), "player_move action")
	var pm: Dictionary = _first_type(cast.get("actions", []), "player_move")
	# Adjacent to (4,0) toward (0,0) → (3,0)
	failed += _expect(int(pm.get("x", -1)) == 3 and int(pm.get("y", -1)) == 0, "landed adjacent (3,0)")
	failed += _expect(engine.player_cell_hint == Vector2i(3, 0), "hint updated to (3,0)")
	failed += _expect(not stats.is_skill_ready("charge"), "on cooldown")

	# --- Reject: no target ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var no_tgt: Dictionary = engine.try_use_skill("charge", "", 0, 0)
	failed += _expect(not bool(no_tgt.get("ok", true)), "no target rejected")
	failed += _expect(_has_msg(no_tgt.get("actions", []), "需要目标"), "need target msg")

	# --- Reject: out of range ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.set_npc_cell("slime_a", 20, 20)
	var far: Dictionary = engine.try_use_skill("charge", "slime_a", 0, 0)
	failed += _expect(not bool(far.get("ok", true)), "oor rejected")
	failed += _expect(_has_msg(far.get("actions", []), "目标太远"), "oor msg")
	stats.set_npc_cell("slime_a", 4, 0)

	# --- Reject: too close (min_range 2) ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.set_npc_cell("slime_a", 1, 0)  # dist 1 < 2
	var near: Dictionary = engine.try_use_skill("charge", "slime_a", 0, 0)
	failed += _expect(not bool(near.get("ok", true)), "too close rejected")
	failed += _expect(_has_msg(near.get("actions", []), "目标太近"), "too close msg")
	stats.set_npc_cell("slime_a", 4, 0)

	# --- Reject: blocked path ---
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	engine.map_collision = BlockPathCol.new()
	var blocked: Dictionary = engine.try_use_skill("charge", "slime_a", 0, 0)
	failed += _expect(not bool(blocked.get("ok", true)), "blocked path rejected")
	failed += _expect(_has_msg(blocked.get("actions", []), "冲锋路径被阻挡"), "blocked path msg")
	engine.map_collision = null

	# --- Reject: non-hostile ---
	stats.ensure_npc("vendor_x", false, false)
	stats.set_npc_cell("vendor_x", 3, 0)
	stats.npcs["vendor_x"]["hostile"] = false
	stats.npcs["vendor_x"]["hp"] = 50
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var soft: Dictionary = engine.try_use_skill("charge", "vendor_x", 0, 0)
	failed += _expect(not bool(soft.get("ok", true)), "non-hostile rejected")
	failed += _expect(_has_msg(soft.get("actions", []), "只能冲锋敌对目标"), "hostile-only msg")

	# --- Reject: unlearned ---
	var stats2 = CombatStats.new()
	stats2.reset_player(3)
	stats2.ensure_skill_book()
	stats2.skill_book.grant_starters(skills)
	var eng2 = CombatEngine.new()
	eng2.setup(stats2, skills, items, bag)
	stats2.ensure_npc("m2", true, true)
	stats2.set_npc_cell("m2", 3, 0)
	var unl: Dictionary = eng2.try_use_skill("charge", "m2", 0, 0)
	failed += _expect(not bool(unl.get("ok", true)), "unlearned rejected")
	failed += _expect(_has_msg(unl.get("actions", []), "尚未学会"), "unlearned msg")

	# --- MockServer wiring (optional if available) ---
	failed += _mock_server_charge(failed)

	if failed == 0:
		print("test_charge: PASS")
		quit(0)
	else:
		print("test_charge: FAIL count=", failed)
		quit(1)


func _mock_server_charge(_failed_so_far: int) -> int:
	# Lightweight: ensure MockServer try_use_skill applies player_move via set_player_cell.
	var failed := 0
	var MockServer = load("res://scripts/net/mock_server.gd")
	if MockServer == null:
		print("  SKIP mock_server (load null)")
		return 0
	var srv = MockServer.new()
	if srv == null:
		return 0
	# Boot minimal combat pieces if method exists
	if srv.has_method("_ready"):
		# Node _ready may need tree; skip full boot and only check helper presence.
		pass
	failed += _expect(srv.has_method("_apply_player_move_actions"), "srv has _apply_player_move_actions")
	failed += _expect(srv.has_method("try_use_skill"), "srv has try_use_skill")
	# Simulate apply
	if srv.has_method("set_player_cell"):
		srv.set_player_cell(0, 0)
		var fake := {"ok": true, "actions": [{"type": "player_move", "x": 5, "y": 2, "cell": {"x": 5, "y": 2}}]}
		srv._apply_player_move_actions(fake)
		failed += _expect(srv.player_cell == Vector2i(5, 2), "srv player_cell after charge move")
	srv.free()
	return failed


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


func _first_type(actions: Array, t: String) -> Dictionary:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return a
	return {}


func _has_msg(actions: Array, sub: String) -> bool:
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(sub) >= 0:
			return true
	return false
