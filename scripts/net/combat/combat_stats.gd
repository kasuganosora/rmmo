extends RefCounted
## Authoritative HP/MP/ATK etc. for player and NPCs (MockServer / future GameServer).

const StatusEffects = preload("res://scripts/net/combat/status_effects.gd")
const SkillBook = preload("res://scripts/net/combat/skill_book.gd")

const DEFAULT_PLAYER := {
	"hp": 100,
	"hp_max": 100,
	"mp": 50,
	"mp_max": 50,
	"atk": 12,
	"def": 4,
	"atk_speed": 0.8,
}

## npc_id -> { hp, hp_max, atk, def, hostile }
var npcs: Dictionary = {}
## Player combat blob (copy of DEFAULT_PLAYER keys).
var player: Dictionary = {}
## skill_id -> ready_at (seconds, Time.get_ticks_msec()/1000.0 basis via engine clock)
var skill_ready_at: Dictionary = {}
## item_id -> ready_at
var item_ready_at: Dictionary = {}
## Global basic-attack ready time (seconds).
var attack_ready_at: float = 0.0
## Optional NPC cell tracking for range checks: npc_id -> Vector2i
var npc_cells: Dictionary = {}
## npc_id -> AI runtime { facing, aggressive, enraged, chase_target, lose_sight_sec,
##   home_cell, wander_radius, leash_radius, respawn_sec, ai_state, idle_wander_acc,
##   hate_list, victim_id }
## aggressive = base 主动; enraged = passive became chase-active after taking damage.
## ai_state: idle | chase | return_home. wander_radius 0 = stand still when idle.
## group_id: 0 = solo; same non-zero id = pack (assist within hit mob wander_radius).
## leash_radius: Chebyshev cells from home; chase beyond → clear_chase (default 12).
## respawn_sec: seconds after death before respawn at home (default 30; <0 = no respawn).
## hate_list: Array of { id, threat, threat_mod } — multi-player hate (source of truth).
## victim_id: sticky current target from hate_list (synced to chase_target).
var npc_ai: Dictionary = {}

## Sticky threat switch threshold (WoW-style melee hysteresis; ranged 1.30 later).
const THREAT_SWITCH_RATIO := 1.10
## Default single-player / fallback actor key.
const DEFAULT_PLAYER_ID := "player"
## Heal hate multiplier stub (future party heals).
const HEAL_HATE_RATIO := 0.5

## Session local actor id string (character id when available; else DEFAULT_PLAYER_ID).
var player_actor_id: String = DEFAULT_PLAYER_ID
## actor_id -> threat_mod (tank weapons/skills e.g. 1.5–3.0; default 1.0).
var actor_threat_mods: Dictionary = {}
## Buff / debuff / DoT / HoT runtime (see status_effects.gd).
var statuses = StatusEffects.new()
## Known skills + SP (session). Reset with starters via MockServer.
var skill_book = SkillBook.new()

## Primary attribute keys (Chinese UI: 力量/敏捷/体质/智力).
const ATTR_KEYS := ["str", "agi", "vit", "intel"]
## Unspent attribute points granted per level-up.
const ATTR_POINTS_PER_LEVEL := 5
## Derived combat bonuses from allocated attrs.
const ATTR_ATK_PER_STR := 1
const ATTR_DEF_PER_AGI := 1
const ATTR_HP_PER_VIT := 5
const ATTR_MP_PER_INTEL := 3

## Rested EXP: hard ceiling; effective max is min(HARD_CAP, exp_to_next).
## Documented choice: min(500, exp_to_next) — one bar-worth of bonus, never above 500.
const RESTED_EXP_HARD_CAP := 500
## Sit tick gain while sitting in a safe zone (MockServer 1.0s sit tick).
const RESTED_EXP_PER_TICK := 5


func reset_player(level: int = 1) -> void:
	var lv: int = maxi(level, 1)
	player = {
		"level": lv,
		"exp": 0,
		"exp_to_next": exp_to_next_for(lv),
		"rested_exp": 0,
		"hp": 80 + lv * 20,
		"hp_max": 80 + lv * 20,
		"mp": 40 + lv * 15,
		"mp_max": 40 + lv * 15,
		"atk": 10 + lv * 3,
		"def": 3 + lv,
		"atk_speed": 0.8,
		"threat_mod": float(actor_threat_mods.get(player_actor_id, 1.0)),
		"attr_points": 0,
		"attrs": {"str": 0, "agi": 0, "vit": 0, "intel": 0},
	}
	skill_ready_at.clear()
	item_ready_at.clear()
	attack_ready_at = 0.0
	if statuses != null:
		statuses.clear_all("player")


## EXP required to advance from this level to the next.
static func exp_to_next_for(level: int) -> int:
	var lv: int = maxi(level, 1)
	return 50 + lv * 40


## Kill EXP grant formula from NPC combat level.
static func kill_exp_for_npc_level(npc_level: int) -> int:
	return maxi(5, maxi(npc_level, 1) * 8 + 10)


## Ensure attrs / attr_points exist on player (migration-safe).
func ensure_attrs() -> void:
	if player.is_empty():
		reset_player(1)
		return
	if typeof(player.get("attrs", null)) != TYPE_DICTIONARY:
		player["attrs"] = {"str": 0, "agi": 0, "vit": 0, "intel": 0}
	else:
		var a: Dictionary = player["attrs"]
		for k in ATTR_KEYS:
			a[k] = maxi(int(a.get(k, 0)), 0)
		player["attrs"] = a
	player["attr_points"] = maxi(int(player.get("attr_points", 0)), 0)


## Snapshot of primary attrs + unspent points.
func snapshot_attrs() -> Dictionary:
	ensure_attrs()
	return {
		"attr_points": int(player.get("attr_points", 0)),
		"attrs": (player["attrs"] as Dictionary).duplicate(true),
	}


## Add attr-derived bonuses onto current level baseline scalars (in-place).
## Call only after setting level baseline (apply_level_stats / recompute).
func _apply_attr_bonuses() -> void:
	ensure_attrs()
	var a: Dictionary = player["attrs"]
	var str_v: int = int(a.get("str", 0))
	var agi_v: int = int(a.get("agi", 0))
	var vit_v: int = int(a.get("vit", 0))
	var intel_v: int = int(a.get("intel", 0))
	player["atk"] = int(player.get("atk", 0)) + str_v * ATTR_ATK_PER_STR
	player["def"] = int(player.get("def", 0)) + agi_v * ATTR_DEF_PER_AGI
	player["hp_max"] = int(player.get("hp_max", 0)) + vit_v * ATTR_HP_PER_VIT
	player["mp_max"] = int(player.get("mp_max", 0)) + intel_v * ATTR_MP_PER_INTEL


## Recalc combat scalars from current player.level; heal to full when heal=true.
## Preserves allocated attrs; re-applies attr bonuses after level baseline.
## Alias note: "apply_level_curve" in design docs == this function.
func apply_level_stats(heal: bool = true) -> void:
	if player.is_empty():
		reset_player(1)
		return
	ensure_attrs()
	var lv: int = maxi(int(player.get("level", 1)), 1)
	player["level"] = lv
	player["exp_to_next"] = exp_to_next_for(lv)
	# Level baseline (attrs re-applied below — do not wipe attrs).
	player["hp_max"] = 80 + lv * 20
	player["mp_max"] = 40 + lv * 15
	player["atk"] = 10 + lv * 3
	player["def"] = 3 + lv
	_apply_attr_bonuses()
	if heal:
		player["hp"] = int(player["hp_max"])
		player["mp"] = int(player["mp_max"])
	else:
		player["hp"] = mini(int(player.get("hp", 0)), int(player["hp_max"]))
		player["mp"] = mini(int(player.get("mp", 0)), int(player["mp_max"]))
	player["threat_mod"] = float(actor_threat_mods.get(player_actor_id, 1.0))


## Alias for design / callers expecting apply_level_curve.
func apply_level_curve(heal: bool = true) -> void:
	apply_level_stats(heal)


## Add EXP; level up while exp >= exp_to_next. Returns summary for MockServer actions.
## {amount, exp, exp_to_next, level, leveled, levels_gained, combat}
func grant_exp(amount: int) -> Dictionary:
	amount = maxi(amount, 0)
	if player.is_empty():
		reset_player(1)
	var lv: int = maxi(int(player.get("level", 1)), 1)
	var exp_v: int = maxi(int(player.get("exp", 0)), 0)
	var need: int = int(player.get("exp_to_next", exp_to_next_for(lv)))
	if need <= 0:
		need = exp_to_next_for(lv)
	exp_v += amount
	var levels_gained: Array = []
	# Safety cap against infinite loops if formula ever breaks.
	var guard: int = 0
	while exp_v >= need and guard < 100:
		guard += 1
		exp_v -= need
		lv += 1
		levels_gained.append(lv)
		need = exp_to_next_for(lv)
	player["level"] = lv
	player["exp"] = exp_v
	player["exp_to_next"] = need
	if not levels_gained.is_empty():
		ensure_attrs()
		# Grant unspent attr points per level (attrs themselves preserved).
		player["attr_points"] = int(player.get("attr_points", 0)) + int(levels_gained.size()) * ATTR_POINTS_PER_LEVEL
		apply_level_stats(true)
	else:
		# Keep combat scalars in sync without healing.
		player["exp_to_next"] = need
	return {
		"amount": amount,
		"exp": exp_v,
		"exp_to_next": need,
		"level": lv,
		"leveled": not levels_gained.is_empty(),
		"levels_gained": levels_gained,
		"combat": snapshot_player_stats(),
	}


func clear_npcs() -> void:
	npcs.clear()
	npc_cells.clear()
	npc_ai.clear()
	if statuses != null and statuses.has_method("clear_non_player"):
		statuses.clear_non_player()


static func npc_mp_max_for(level: int, hp_max: int = 30) -> int:
	return maxi(20, 16 + maxi(level, 1) * 8 + maxi(hp_max, 0) / 6)


func _fill_npc_mp(st: Dictionary) -> void:
	if not st.has("level"):
		st["level"] = 1
	var hp_max: int = int(st.get("hp_max", 30))
	if not st.has("mp_max") or int(st.get("mp_max", 0)) <= 0:
		st["mp_max"] = npc_mp_max_for(int(st.get("level", 1)), hp_max)
	if not st.has("mp"):
		st["mp"] = int(st["mp_max"])
	else:
		st["mp"] = clampi(int(st.get("mp", 0)), 0, int(st.get("mp_max", 0)))


func ensure_npc(npc_id: String, hostile: bool = true, aggressive: bool = false) -> Dictionary:
	if npcs.has(npc_id):
		var existing: Variant = npcs[npc_id]
		if typeof(existing) == TYPE_DICTIONARY:
			# Keep previously set aggressive if already present; backfill level for nameplates.
			var ex: Dictionary = existing
			if not ex.has("level"):
				ex["level"] = 1 + absi(hash(npc_id + ":lv")) % 8
			_fill_npc_mp(ex)
			npcs[npc_id] = ex
			return ex
	var hp_max: int = 30 + absi(hash(npc_id)) % 21
	var level: int = 1 + absi(hash(npc_id + ":lv")) % 8
	var mp_max: int = npc_mp_max_for(level, hp_max)
	var st := {
		"hp": hp_max,
		"hp_max": hp_max,
		"mp": mp_max,
		"mp_max": mp_max,
		"atk": 6 + absi(hash(npc_id)) % 5,
		"def": 1 + absi(hash(npc_id)) % 3,
		"level": level,
		"hostile": hostile,
		"aggressive": aggressive,
	}
	npcs[npc_id] = st
	return st


## Ensure AI blob for hostile. Defaults: aggressive from arg, enraged false, idle at home.
## home_cell: spawn/home (Vector2i). wander_radius: 0 = stand still when idle.
## leash_radius: Chebyshev home leash (default 12). respawn_sec: death → respawn delay (default 30; <0 off).
func ensure_npc_ai(
	npc_id: String,
	facing: int = 2,
	aggressive: bool = false,
	home_cell: Vector2i = Vector2i(-9999, -9999),
	wander_radius: int = 0,
	group_id: int = 0,
	leash_radius: int = 12,
	respawn_sec: float = 30.0
) -> Dictionary:
	if npc_ai.has(npc_id):
		var existing: Variant = npc_ai[npc_id]
		if typeof(existing) == TYPE_DICTIONARY:
			# Fill missing home / wander / state / group if an older blob lacked them.
			var ai_ex: Dictionary = existing
			if not ai_ex.has("home_cell") and home_cell.x > -9990:
				ai_ex["home_cell"] = home_cell
			if not ai_ex.has("wander_radius"):
				ai_ex["wander_radius"] = maxi(wander_radius, 0)
			if not ai_ex.has("group_id"):
				ai_ex["group_id"] = group_id
			if not ai_ex.has("leash_radius"):
				ai_ex["leash_radius"] = leash_radius
			if not ai_ex.has("respawn_sec"):
				ai_ex["respawn_sec"] = respawn_sec
			if not ai_ex.has("ai_state"):
				ai_ex["ai_state"] = "idle"
			if not ai_ex.has("idle_wander_acc"):
				ai_ex["idle_wander_acc"] = 0.0
			if not ai_ex.has("seen_target"):
				ai_ex["seen_target"] = false
			_migrate_hate_fields(ai_ex)
			npc_ai[npc_id] = ai_ex
			return ai_ex
	var home := home_cell
	if home.x <= -9990:
		home = Vector2i(-9999, -9999)
	var ai := {
		"facing": facing if facing in [1, 2, 3, 4, 6, 7, 8, 9] else 2,
		"aggressive": aggressive,
		"enraged": false,
		"chase_target": "",
		"lose_sight_sec": 0.0,
		"no_target_sec": 0.0,
		"return_stuck_ticks": 0,
		"return_best_dist": 99999,
		"seen_target": false,
		"home_cell": home,
		"wander_radius": maxi(wander_radius, 0),
		"group_id": group_id,
		"leash_radius": leash_radius,
		"respawn_sec": respawn_sec,
		"ai_state": "idle",
		"idle_wander_acc": 0.0,
		"hate_list": [],
		"victim_id": "",
	}
	npc_ai[npc_id] = ai
	return ai


func get_npc_ai(npc_id: String) -> Dictionary:
	if npc_ai.has(npc_id):
		var v: Variant = npc_ai[npc_id]
		if typeof(v) == TYPE_DICTIONARY:
			return v
	return {}


func set_npc_facing(npc_id: String, facing: int) -> void:
	if facing not in [1, 2, 3, 4, 6, 7, 8, 9]:
		return
	var ai: Dictionary = ensure_npc_ai(npc_id, facing, false)
	ai["facing"] = facing
	npc_ai[npc_id] = ai


## Mark passive hostile as enraged (chase like aggressive) after taking player damage.
func enrage_npc(npc_id: String) -> void:
	if not npc_ai.has(npc_id) and not npcs.has(npc_id):
		return
	var aggressive := false
	if npcs.has(npc_id):
		aggressive = bool(npcs[npc_id].get("aggressive", false))
	var ai: Dictionary = ensure_npc_ai(npc_id, 2, aggressive)
	if bool(ai.get("aggressive", false)):
		return
	ai["enraged"] = true
	npc_ai[npc_id] = ai


## Begin chase on one NPC (hit / pack assist). Passive also enrages.
## Uses select_victim (hate sticky) when present; else fallback player_id / DEFAULT_PLAYER_ID.
func begin_chase(npc_id: String, player_id: String = "") -> void:
	if not npc_ai.has(npc_id) and not npcs.has(npc_id):
		return
	enrage_npc(npc_id)
	if not npc_ai.has(npc_id):
		return
	var ai: Dictionary = npc_ai[npc_id]
	_migrate_hate_fields(ai)
	var tid := select_victim(npc_id)
	if tid.is_empty():
		tid = player_id.strip_edges()
		if tid.is_empty():
			tid = player_actor_id.strip_edges() if player_actor_id.strip_edges() != "" else DEFAULT_PLAYER_ID
		ai["victim_id"] = tid
	ai["chase_target"] = tid
	ai["lose_sight_sec"] = 0.0
	ai["seen_target"] = false
	ai["ai_state"] = "chase"
	ai["idle_wander_acc"] = 0.0
	npc_ai[npc_id] = ai


## Pack assist: same non-zero group_id within hit mob's wander_radius of hit cell → chase.
## Distance is Chebyshev from the attacked mob's **current** cell. group_id 0 = solo (no-op).
func activate_group_allies(hit_npc_id: String) -> void:
	if not npc_ai.has(hit_npc_id):
		return
	var hit_ai: Dictionary = npc_ai[hit_npc_id]
	var gid: int = int(hit_ai.get("group_id", 0))
	if gid == 0:
		return
	var hit_cell: Vector2i = get_npc_cell(hit_npc_id)
	if hit_cell.x <= -9990:
		return
	var radius: int = maxi(int(hit_ai.get("wander_radius", 0)), 0)
	var ids: Array = npc_ai.keys()
	for oid_v in ids:
		var oid: String = str(oid_v)
		if oid == hit_npc_id:
			continue
		if not npcs.has(oid):
			continue
		var st: Dictionary = npcs[oid]
		if int(st.get("hp", 0)) <= 0 or not bool(st.get("hostile", false)):
			continue
		var oai: Dictionary = npc_ai[oid]
		if int(oai.get("group_id", 0)) != gid:
			continue
		var ocell: Vector2i = get_npc_cell(oid)
		if ocell.x <= -9990:
			continue
		var dist: int = maxi(absi(ocell.x - hit_cell.x), absi(ocell.y - hit_cell.y))
		if dist > radius:
			continue
		begin_chase(oid)


## Clear chase + threat + enrage; restore full HP (evade); enter return_home.
## Passive clears enraged (back to passive until hit again); aggressive keeps base aggressive.
## Evade: full HP reset so client HP bar matches via npc_reset / heal actions from MockServer.
func clear_chase(npc_id: String) -> void:
	if not npc_ai.has(npc_id):
		return
	var ai: Dictionary = npc_ai[npc_id]
	ai["chase_target"] = ""
	ai["lose_sight_sec"] = 0.0
	ai["no_target_sec"] = 0.0
	ai["return_stuck_ticks"] = 0
	ai["return_best_dist"] = 99999
	ai["seen_target"] = false
	ai["idle_wander_acc"] = 0.0
	ai["hate_list"] = []
	ai["victim_id"] = ""
	ai.erase("threat")
	# Aggressive stay aggressive; only clear temp enrage.
	if not bool(ai.get("aggressive", false)):
		ai["enraged"] = false
	# Evade: restore NPC to full HP.
	if npcs.has(npc_id):
		var st: Dictionary = npcs[npc_id]
		var hp_max: int = int(st.get("hp_max", 0))
		st["hp"] = hp_max
		npcs[npc_id] = st
	# Walk home after abandon (or arrive immediately → idle if already home).
	var home_v: Variant = ai.get("home_cell", Vector2i(-9999, -9999))
	var home := Vector2i(-9999, -9999)
	if typeof(home_v) == TYPE_VECTOR2I:
		home = home_v
	elif typeof(home_v) == TYPE_DICTIONARY:
		home = Vector2i(int(home_v.get("x", -9999)), int(home_v.get("y", -9999)))
	var cell: Vector2i = get_npc_cell(npc_id)
	if home.x > -9990 and cell.x > -9990 and cell == home:
		ai["ai_state"] = "idle"
	else:
		ai["ai_state"] = "return_home"
	npc_ai[npc_id] = ai


## Migrate legacy threat{} dict → hate_list + victim_id (in-place).
func _migrate_hate_fields(ai: Dictionary) -> void:
	if not ai.has("hate_list") or typeof(ai.get("hate_list")) != TYPE_ARRAY:
		var hate: Array = []
		var tv: Variant = ai.get("threat", {})
		if typeof(tv) == TYPE_DICTIONARY:
			for k in (tv as Dictionary).keys():
				hate.append({
					"id": str(k),
					"threat": float((tv as Dictionary)[k]),
					"threat_mod": 1.0,
				})
		ai["hate_list"] = hate
	if not ai.has("victim_id"):
		var vid := str(ai.get("chase_target", ""))
		if vid.is_empty() and (ai["hate_list"] as Array).size() > 0:
			vid = str((ai["hate_list"] as Array)[0].get("id", ""))
		ai["victim_id"] = vid
	# Drop legacy dict once migrated.
	if ai.has("threat"):
		ai.erase("threat")


func set_player_actor_id(actor_id: String) -> void:
	var aid := actor_id.strip_edges()
	player_actor_id = aid if aid != "" else DEFAULT_PLAYER_ID
	if not player.is_empty():
		player["threat_mod"] = get_actor_threat_mod(player_actor_id)


func set_actor_threat_mod(actor_id: String, mod: float) -> void:
	actor_id = actor_id.strip_edges()
	if actor_id.is_empty():
		return
	var m: float = maxf(mod, 0.0)
	actor_threat_mods[actor_id] = m
	if actor_id == player_actor_id and not player.is_empty():
		player["threat_mod"] = m


func get_actor_threat_mod(actor_id: String) -> float:
	actor_id = actor_id.strip_edges()
	if actor_id.is_empty():
		return 1.0
	if actor_threat_mods.has(actor_id):
		return float(actor_threat_mods[actor_id])
	if actor_id == player_actor_id and not player.is_empty():
		return float(player.get("threat_mod", 1.0))
	return 1.0


## Add hate: applied = raw_amount * threat_mod; upsert entry in hate_list; refresh victim.
func add_hate(npc_id: String, actor_id: String, raw_amount: float, threat_mod: float = 1.0) -> void:
	npc_id = npc_id.strip_edges()
	actor_id = actor_id.strip_edges()
	if npc_id.is_empty() or actor_id.is_empty() or raw_amount <= 0.0:
		return
	var mod: float = maxf(threat_mod, 0.0)
	var applied: float = raw_amount * mod
	if applied <= 0.0:
		return
	if not npc_ai.has(npc_id):
		if not npcs.has(npc_id):
			return
		var aggressive := bool(npcs[npc_id].get("aggressive", false))
		ensure_npc_ai(npc_id, 2, aggressive)
	var ai: Dictionary = npc_ai[npc_id]
	_migrate_hate_fields(ai)
	var hate: Array = ai["hate_list"]
	var found := false
	for i in range(hate.size()):
		var e: Variant = hate[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str((e as Dictionary).get("id", "")) == actor_id:
			var entry: Dictionary = e
			entry["threat"] = float(entry.get("threat", 0.0)) + applied
			entry["threat_mod"] = mod
			hate[i] = entry
			found = true
			break
	if not found:
		hate.append({"id": actor_id, "threat": applied, "threat_mod": mod})
	ai["hate_list"] = hate
	npc_ai[npc_id] = ai
	select_victim(npc_id)


## Compat wrapper: amount treated as already-final hate (mod 1.0).
func add_threat(npc_id: String, player_id: String, amount: float) -> void:
	add_hate(npc_id, player_id, amount, 1.0)


## Future: heal generates hate at HEAL_HATE_RATIO of heal amount.
func add_hate_heal(npc_id: String, healer_id: String, heal_amount: float, threat_mod: float = 1.0) -> void:
	if heal_amount <= 0.0:
		return
	add_hate(npc_id, healer_id, float(heal_amount) * HEAL_HATE_RATIO, threat_mod)


func clear_hate(npc_id: String) -> void:
	if not npc_ai.has(npc_id):
		return
	var ai: Dictionary = npc_ai[npc_id]
	ai["hate_list"] = []
	ai["victim_id"] = ""
	ai.erase("threat")
	# Keep chase_target unless caller also clear_chase — only wipe hate here.
	npc_ai[npc_id] = ai


## Alias for clear_hate (legacy name).
func clear_threat(npc_id: String) -> void:
	clear_hate(npc_id)


## Copy of hate entries. sorted=true → threat descending (debug).
func get_hate_list(npc_id: String, sorted: bool = true) -> Array:
	if not npc_ai.has(npc_id):
		return []
	var ai: Dictionary = npc_ai[npc_id]
	_migrate_hate_fields(ai)
	npc_ai[npc_id] = ai
	var out: Array = []
	for e in ai["hate_list"]:
		if typeof(e) == TYPE_DICTIONARY:
			out.append((e as Dictionary).duplicate(true))
	if sorted and out.size() > 1:
		out.sort_custom(func(a, b): return float(a.get("threat", 0.0)) > float(b.get("threat", 0.0)))
	return out


func get_threat(npc_id: String, player_id: String) -> float:
	player_id = player_id.strip_edges()
	if player_id.is_empty() or not npc_ai.has(npc_id):
		return 0.0
	var ai: Dictionary = npc_ai[npc_id]
	_migrate_hate_fields(ai)
	for e in ai["hate_list"]:
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("id", "")) == player_id:
			return float((e as Dictionary).get("threat", 0.0))
	return 0.0


## Highest-threat actor id (empty if none). Does not apply sticky hysteresis.
func highest_threat_target(npc_id: String) -> String:
	var best_id := ""
	var best_v := -1.0
	for e in get_hate_list(npc_id, false):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var v: float = float((e as Dictionary).get("threat", 0.0))
		if v > best_v:
			best_v = v
			best_id = str((e as Dictionary).get("id", ""))
	return best_id


## Sticky victim: keep current unless another has threat ≥ THREAT_SWITCH_RATIO (1.10 melee).
## Updates victim_id + chase_target. Returns victim id ("" if empty list).
func select_victim(npc_id: String) -> String:
	if not npc_ai.has(npc_id):
		return ""
	var ai: Dictionary = npc_ai[npc_id]
	_migrate_hate_fields(ai)
	var hate: Array = ai["hate_list"]
	if hate.is_empty():
		ai["victim_id"] = ""
		# Do not clear chase_target here — begin_chase / clear_chase own that.
		npc_ai[npc_id] = ai
		return ""
	var best_id := ""
	var best_v := -1.0
	var by_id: Dictionary = {}
	for e in hate:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var eid := str((e as Dictionary).get("id", ""))
		var v: float = float((e as Dictionary).get("threat", 0.0))
		by_id[eid] = v
		if v > best_v:
			best_v = v
			best_id = eid
	if best_id.is_empty():
		ai["victim_id"] = ""
		npc_ai[npc_id] = ai
		return ""
	var cur := str(ai.get("victim_id", ""))
	if cur.is_empty():
		cur = str(ai.get("chase_target", ""))
	if cur.is_empty() or not by_id.has(cur):
		ai["victim_id"] = best_id
		ai["chase_target"] = best_id
		npc_ai[npc_id] = ai
		return best_id
	var cur_v: float = float(by_id.get(cur, 0.0))
	# Epsilon: 1.10 is not binary-exact (100*1.10 can exceed 110).
	if best_id != cur and best_v + 0.0001 >= cur_v * THREAT_SWITCH_RATIO:
		ai["victim_id"] = best_id
		ai["chase_target"] = best_id
	else:
		ai["victim_id"] = cur
		ai["chase_target"] = cur
	npc_ai[npc_id] = ai
	return str(ai["victim_id"])


## Player-relative threat snapshot for HUD (uses hate_list + victim_id; no second system).
## {npc_id, threat_you, threat_rank, threat_pct, victim_id}
func snapshot_threat(npc_id: String) -> Dictionary:
	npc_id = npc_id.strip_edges()
	var empty := {
		"npc_id": npc_id,
		"threat_you": false,
		"threat_rank": 0,
		"threat_pct": 0.0,
		"victim_id": "",
	}
	if npc_id.is_empty() or not npc_ai.has(npc_id):
		return empty
	var ai: Dictionary = npc_ai[npc_id]
	_migrate_hate_fields(ai)
	npc_ai[npc_id] = ai
	var vid := str(ai.get("victim_id", "")).strip_edges()
	var you := player_actor_id.strip_edges()
	if you.is_empty():
		you = DEFAULT_PLAYER_ID
	var threat_you := (not vid.is_empty()) and vid == you
	var hate: Array = get_hate_list(npc_id, true)
	var your_threat := 0.0
	var top_threat := 0.0
	var rank := 0
	var i := 0
	for e in hate:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		i += 1
		var eid := str((e as Dictionary).get("id", "")).strip_edges()
		var t: float = float((e as Dictionary).get("threat", 0.0))
		if i == 1:
			top_threat = t
		if eid == you:
			your_threat = t
			rank = i
	var pct := 0.0
	if top_threat > 0.0 and your_threat > 0.0:
		pct = (your_threat / top_threat) * 100.0
	return {
		"npc_id": npc_id,
		"threat_you": threat_you,
		"threat_rank": rank,
		"threat_pct": pct,
		"victim_id": vid,
	}


func set_npc_cell(npc_id: String, x: int, y: int) -> void:
	npc_cells[npc_id] = Vector2i(x, y)


func clear_npc_cell(npc_id: String) -> void:
	if npc_cells.has(npc_id):
		npc_cells.erase(npc_id)


func get_npc_cell(npc_id: String) -> Vector2i:
	if npc_cells.has(npc_id):
		return npc_cells[npc_id]
	return Vector2i(-9999, -9999)


func remove_npc(npc_id: String) -> void:
	if npcs.has(npc_id):
		npcs.erase(npc_id)
	clear_npc_cell(npc_id)
	if npc_ai.has(npc_id):
		npc_ai.erase(npc_id)
	if statuses != null:
		statuses.clear_all_on_death(npc_id)


func player_alive() -> bool:
	return int(player.get("hp", 0)) > 0


## Full HP/MP restore after death (keeps atk/def/level scaling already in player).
func restore_after_death(partial: bool = false) -> void:
	var hp_max: int = int(player.get("hp_max", 100))
	var mp_max: int = int(player.get("mp_max", 50))
	if partial:
		player["hp"] = maxi(1, hp_max / 2)
		player["mp"] = maxi(0, mp_max / 2)
	else:
		player["hp"] = hp_max
		player["mp"] = mp_max
	attack_ready_at = 0.0
	skill_ready_at.clear()
	item_ready_at.clear()
	if statuses != null:
		statuses.clear_all_on_death("player")


func now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func is_skill_ready(skill_id: String) -> bool:
	var t: float = float(skill_ready_at.get(skill_id, 0.0))
	return now_sec() >= t


func set_skill_cooldown(skill_id: String, cd_sec: float) -> void:
	skill_ready_at[skill_id] = now_sec() + maxf(cd_sec, 0.0)


func skill_cd_remaining(skill_id: String) -> float:
	return maxf(0.0, float(skill_ready_at.get(skill_id, 0.0)) - now_sec())


func is_item_ready(item_id: String) -> bool:
	return now_sec() >= float(item_ready_at.get(item_id, 0.0))


func set_item_cooldown(item_id: String, cd_sec: float) -> void:
	item_ready_at[item_id] = now_sec() + maxf(cd_sec, 0.0)


func is_attack_ready() -> bool:
	return now_sec() >= attack_ready_at


func set_attack_cooldown(cd_sec: float) -> void:
	attack_ready_at = now_sec() + maxf(cd_sec, 0.0)


func ensure_skill_book():
	if skill_book == null:
		skill_book = SkillBook.new()
	return skill_book


func snapshot_skill_book() -> Dictionary:
	ensure_skill_book()
	return skill_book.snapshot()


## Spend unspent attr_points into one primary attr. Recomputes derived combat.
## {ok, reason, message, attr_points, attrs, combat}
func try_allocate_attr(stat_key: String, amount: int = 1) -> Dictionary:
	stat_key = stat_key.strip_edges()
	amount = maxi(amount, 0)
	ensure_attrs()
	var out := {
		"ok": false,
		"reason": "fail",
		"message": "无法分配属性点。",
		"attr_points": int(player.get("attr_points", 0)),
		"attrs": (player["attrs"] as Dictionary).duplicate(true),
		"combat": snapshot_player_stats(),
	}
	if amount <= 0:
		out["reason"] = "bad_amount"
		out["message"] = "分配数量无效。"
		return out
	if not player_alive():
		out["reason"] = "dead"
		out["message"] = "你已经倒下了。"
		return out
	if stat_key not in ATTR_KEYS:
		out["reason"] = "bad_key"
		out["message"] = "无效的属性。"
		return out
	var pts: int = int(player.get("attr_points", 0))
	if pts < amount:
		out["reason"] = "no_points"
		out["message"] = "属性点不足（需要 %d，当前 %d）。" % [amount, pts]
		return out
	var a: Dictionary = player["attrs"]
	a[stat_key] = int(a.get(stat_key, 0)) + amount
	player["attrs"] = a
	player["attr_points"] = pts - amount
	# Re-apply level baseline + attrs (preserve current hp ratio via clamp, no full heal).
	apply_level_stats(false)
	out["ok"] = true
	out["reason"] = "ok"
	out["message"] = "已分配 %d 点到%s。" % [amount, attr_label_zh(stat_key)]
	out["attr_points"] = int(player.get("attr_points", 0))
	out["attrs"] = (player["attrs"] as Dictionary).duplicate(true)
	out["combat"] = snapshot_player_stats()
	return out


## Chinese label for attr key.
static func attr_label_zh(stat_key: String) -> String:
	match stat_key.strip_edges():
		"str":
			return "力量"
		"agi":
			return "敏捷"
		"vit":
			return "体质"
		"intel":
			return "智力"
		_:
			return stat_key


## Refund all allocated attrs into attr_points (caller pays gold). Does not touch gold.
## {ok, reason, message, refunded, attr_points, attrs, combat}
func try_attr_respec_refund() -> Dictionary:
	ensure_attrs()
	var out := {
		"ok": false,
		"reason": "fail",
		"message": "无法重置属性。",
		"refunded": 0,
		"attr_points": int(player.get("attr_points", 0)),
		"attrs": (player["attrs"] as Dictionary).duplicate(true),
		"combat": snapshot_player_stats(),
	}
	if not player_alive():
		out["reason"] = "dead"
		out["message"] = "你已经倒下了。"
		return out
	var a: Dictionary = player["attrs"]
	var refund := 0
	for k in ATTR_KEYS:
		refund += int(a.get(k, 0))
	if refund <= 0:
		out["reason"] = "nothing"
		out["message"] = "没有可重置的属性点。"
		return out
	player["attrs"] = {"str": 0, "agi": 0, "vit": 0, "intel": 0}
	player["attr_points"] = int(player.get("attr_points", 0)) + refund
	apply_level_stats(false)
	out["ok"] = true
	out["reason"] = "ok"
	out["refunded"] = refund
	out["message"] = "已重置属性，返还属性点 %d。" % refund
	out["attr_points"] = int(player.get("attr_points", 0))
	out["attrs"] = (player["attrs"] as Dictionary).duplicate(true)
	out["combat"] = snapshot_player_stats()
	return out


## Effective rested pool ceiling: min(500, exp_to_next).
func rested_exp_max() -> int:
	if player.is_empty():
		return RESTED_EXP_HARD_CAP
	var need: int = int(player.get("exp_to_next", 0))
	if need <= 0:
		need = exp_to_next_for(maxi(int(player.get("level", 1)), 1))
	return mini(RESTED_EXP_HARD_CAP, maxi(need, 1))


## Migration-safe rested_exp clamp to current max.
func ensure_rested() -> void:
	if player.is_empty():
		reset_player(1)
		return
	var cur: int = maxi(int(player.get("rested_exp", 0)), 0)
	player["rested_exp"] = mini(cur, rested_exp_max())


func get_rested_exp() -> int:
	ensure_rested()
	return int(player.get("rested_exp", 0))


## Add to rested pool (clamped). Returns {added, rested_exp, rested_exp_max, was_empty, hit_cap}.
func add_rested_exp(amount: int) -> Dictionary:
	ensure_rested()
	amount = maxi(amount, 0)
	var before: int = int(player.get("rested_exp", 0))
	var cap: int = rested_exp_max()
	var after: int = mini(before + amount, cap)
	player["rested_exp"] = after
	return {
		"added": after - before,
		"rested_exp": after,
		"rested_exp_max": cap,
		"was_empty": before <= 0,
		"hit_cap": after >= cap and before < cap,
	}


## Spend rested against a kill grant: bonus = min(pool, base_amount). Returns bonus.
func spend_rested_for_kill(base_amount: int) -> int:
	ensure_rested()
	base_amount = maxi(base_amount, 0)
	if base_amount <= 0:
		return 0
	var pool: int = int(player.get("rested_exp", 0))
	if pool <= 0:
		return 0
	var bonus: int = mini(pool, base_amount)
	player["rested_exp"] = pool - bonus
	return bonus


func snapshot_player_stats() -> Dictionary:
	ensure_attrs()
	ensure_rested()
	var snap: Dictionary = player.duplicate(true)
	snap["rested_exp"] = int(player.get("rested_exp", 0))
	snap["rested_exp_max"] = rested_exp_max()
	return snap


## --- Title / achievement thin shell (session counters + unlocks) ---

## kills / crafts / deaths (and future keys).
var title_counters: Dictionary = {"kills": 0, "crafts": 0, "deaths": 0}
## Unlocked title ids (strings).
var unlocked_titles: Array = []
## Currently equipped title id (empty = none).
var active_title: String = ""


func reset_titles() -> void:
	title_counters = {"kills": 0, "crafts": 0, "deaths": 0}
	unlocked_titles.clear()
	active_title = ""


func snapshot_titles() -> Dictionary:
	return {
		"counters": title_counters.duplicate(true),
		"unlocked_titles": unlocked_titles.duplicate(),
		"active_title": active_title,
		"kills": int(title_counters.get("kills", 0)),
		"crafts": int(title_counters.get("crafts", 0)),
		"deaths": int(title_counters.get("deaths", 0)),
	}


## Increment a counter. Returns new value.
func bump_title_counter(key: String, amount: int = 1) -> int:
	key = key.strip_edges()
	if key.is_empty() or amount == 0:
		return int(title_counters.get(key, 0)) if not key.is_empty() else 0
	var cur: int = int(title_counters.get(key, 0))
	cur = maxi(cur + amount, 0)
	title_counters[key] = cur
	return cur


func is_title_unlocked(title_id: String) -> bool:
	title_id = title_id.strip_edges()
	if title_id.is_empty():
		return false
	for u in unlocked_titles:
		if str(u) == title_id:
			return true
	return false


## Grant unlock if not already present. Returns true if newly unlocked.
func unlock_title(title_id: String) -> bool:
	title_id = title_id.strip_edges()
	if title_id.is_empty() or is_title_unlocked(title_id):
		return false
	unlocked_titles.append(title_id)
	return true


## Equip unlocked title, or unequip when title_id empty. Returns {ok, reason}.
func try_title_equip(title_id: String) -> Dictionary:
	title_id = title_id.strip_edges()
	if title_id.is_empty():
		active_title = ""
		return {"ok": true, "reason": "unequipped"}
	if not is_title_unlocked(title_id):
		return {"ok": false, "reason": "locked"}
	active_title = title_id
	return {"ok": true, "reason": "equipped"}


## --- Achievement thin shell (session counters + unlocks; separate from titles) ---

## kills / gathers / level / party (and future keys).
var achievement_counters: Dictionary = {"kills": 0, "gathers": 0, "level": 1, "party": 0}
## Unlocked achievement ids (strings).
var unlocked_achievements: Array = []


func reset_achievements() -> void:
	achievement_counters = {"kills": 0, "gathers": 0, "level": 1, "party": 0}
	unlocked_achievements.clear()


func snapshot_achievements() -> Dictionary:
	return {
		"counters": achievement_counters.duplicate(true),
		"unlocked_achievements": unlocked_achievements.duplicate(),
		"kills": int(achievement_counters.get("kills", 0)),
		"gathers": int(achievement_counters.get("gathers", 0)),
		"level": int(achievement_counters.get("level", 1)),
		"party": int(achievement_counters.get("party", 0)),
	}


## Increment a counter. Returns new value.
func bump_achievement_counter(key: String, amount: int = 1) -> int:
	key = key.strip_edges()
	if key.is_empty() or amount == 0:
		return int(achievement_counters.get(key, 0)) if not key.is_empty() else 0
	var cur: int = int(achievement_counters.get(key, 0))
	cur = maxi(cur + amount, 0)
	achievement_counters[key] = cur
	return cur


## Set counter to at least value (for level sync). Returns new value.
func set_achievement_counter_at_least(key: String, value: int) -> int:
	key = key.strip_edges()
	if key.is_empty():
		return 0
	var cur: int = int(achievement_counters.get(key, 0))
	var nxt: int = maxi(cur, maxi(value, 0))
	achievement_counters[key] = nxt
	return nxt


func is_achievement_unlocked(ach_id: String) -> bool:
	ach_id = ach_id.strip_edges()
	if ach_id.is_empty():
		return false
	for u in unlocked_achievements:
		if str(u) == ach_id:
			return true
	return false


## Grant unlock if not already present. Returns true if newly unlocked.
func unlock_achievement(ach_id: String) -> bool:
	ach_id = ach_id.strip_edges()
	if ach_id.is_empty() or is_achievement_unlocked(ach_id):
		return false
	unlocked_achievements.append(ach_id)
	return true
