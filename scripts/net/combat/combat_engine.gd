extends RefCounted
## Damage resolve, death, cooldowns, counter-attack. Called by MockServer facade.

const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")
const CastState = preload("res://scripts/net/combat/cast_state.gd")
const GridPath = preload("res://scripts/map/grid_path.gd")

var stats: RefCounted = null
var skills: RefCounted = null
var items: RefCounted = null
var _repair_kit_msg: String = ""
var bag: RefCounted = null
## Optional Equipment (paperdoll bonuses folded into effective atk/def).
var gear = null
## Cast / channel runtime (spend MP+CD at start; interrupt wastes MP).
var cast = CastState.new()
## Per-NPC cast / channel (npc_id -> CastState). Hostile skills with cast_time > 0.
var npc_casts: Dictionary = {}
## Optional: Callable(npc_id) -> bool for "is hostile" when not in stats yet.
var hostile_lookup: Callable = Callable()
## Last known player grid cell (NPC skill footprint vs player).
var player_cell_hint: Vector2i = Vector2i(-9999, -9999)
## Optional MapCollision for charge path checks (MockServer wires this).
var map_collision = null
## Optional test override: Callable() -> float in [0,1). Used for hit then crit rolls.
var combat_randf: Callable = Callable()

## Personal DPS meter session window (player → NPC damage only).
## Keys: active, total_damage, fight_start, last_hit_time. Clock via _dps_clock.
var _dps_fight: Dictionary = {
	"active": false,
	"total_damage": 0,
	"fight_start": 0.0,
	"last_hit_time": 0.0,
}
var _dps_clock: float = 0.0
## Last emitted snapshot kept after fight ends until next hit.
var _dps_last_snap: Dictionary = {
	"dps": 0.0,
	"total": 0,
	"elapsed": 0.0,
	"active": false,
}
const DPS_IDLE_TIMEOUT := 6.0

const HIT_CHANCE_BASE := 0.90
const HIT_CHANCE_MIN := 0.50
const HIT_CHANCE_MAX := 0.99
const HIT_LEVEL_STEP := 0.02
const CRIT_CHANCE_BASE := 0.08
const CRIT_DAMAGE_MULT := 1.5
const CastModule = preload("res://scripts/net/combat/engine/cast_module.gd")
const DpsModule = preload("res://scripts/net/combat/engine/dps_module.gd")
const TargetingModule = preload("res://scripts/net/combat/engine/targeting_module.gd")
const PlayerStateModule = preload("res://scripts/net/combat/engine/player_state_module.gd")
var _player_state_module_logic: PlayerStateModule = PlayerStateModule.new(self)
var _targeting_module_logic: TargetingModule = TargetingModule.new(self)
var _dps_module_logic: DpsModule = DpsModule.new(self)
var _cast_module_logic: CastModule = CastModule.new(self)
const SkillEffectsModule = preload("res://scripts/net/combat/engine/skill_effects_module.gd")
var _skill_effects_module_logic: SkillEffectsModule = SkillEffectsModule.new(self)


func setup(p_stats, p_skills, p_items, p_bag, p_gear = null) -> void:
	stats = p_stats
	skills = p_skills
	items = p_items
	bag = p_bag
	gear = p_gear
	if cast == null:
		cast = CastState.new()
	else:
		cast.clear()
	# Match MockServer boot: bare setups get starters so known-gate is usable.
	if stats != null and skills != null:
		if stats.has_method("ensure_skill_book"):
			stats.ensure_skill_book()
		if stats.skill_book != null and stats.skill_book.has_method("list_known"):
			if stats.skill_book.list_known().is_empty() and stats.skill_book.has_method("grant_starters"):
				stats.skill_book.grant_starters(skills)


func _player_stat_actions() -> Array:
	var p: Dictionary = stats.player
	return [
		{
			"type": "set_stat",
			"target": "player",
			"hp": int(p.get("hp", 0)),
			"hp_max": int(p.get("hp_max", 0)),
			"mp": int(p.get("mp", 0)),
			"mp_max": int(p.get("mp_max", 0)),
		}
	]


func _combat_randf() -> float:
	if combat_randf.is_valid():
		return clampf(float(combat_randf.call()), 0.0, 0.999999)
	return randf()


func _attacker_level(attacker_id: String) -> int:
	if attacker_id == "" or attacker_id == "player":
		if stats != null and typeof(stats.player) == TYPE_DICTIONARY:
			return maxi(1, int(stats.player.get("level", 1)))
		return 1
	if stats != null and stats.npcs.has(attacker_id):
		return maxi(1, int(stats.npcs[attacker_id].get("level", 1)))
	return 1


func _defender_level_npc(npc_id: String) -> int:
	if stats != null and stats.npcs.has(npc_id):
		return maxi(1, int(stats.npcs[npc_id].get("level", 1)))
	return 1


func _hit_chance(attacker_level: int, defender_level: int) -> float:
	var diff: int = maxi(attacker_level, 1) - maxi(defender_level, 1)
	return clampf(HIT_CHANCE_BASE + float(diff) * HIT_LEVEL_STEP, HIT_CHANCE_MIN, HIT_CHANCE_MAX)


func _crit_chance(_attacker_level: int = 1) -> float:
	return CRIT_CHANCE_BASE


## Returns true if the hit landed (damage applied). False on miss (no HP change).

func _npc_is_ally(st: Dictionary) -> bool:
	if bool(st.get("ally", false)):
		return true
	var kind := str(st.get("kind", "")).strip_edges().to_lower()
	if kind in ["ally", "friendly", "companion", "party"]:
		return true
	var faction := str(st.get("faction", "")).strip_edges().to_lower()
	if faction in ["ally", "friendly", "player", "party", "town"]:
		return true
	# Non-hostile NPCs marked friendly via hostile=false + ally_eligible.
	if bool(st.get("ally_eligible", false)):
		return true
	return false


func _damage_npc(npc_id: String, amount: int, actions: Array, roll_accuracy: bool = true, attacker_id: String = "player", weapon_wear: bool = false) -> bool:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return false
	var st: Dictionary = stats.ensure_npc(npc_id)
	var crit := false
	if roll_accuracy:
		var chance: float = _hit_chance(_attacker_level(attacker_id), _defender_level_npc(npc_id))
		if _combat_randf() >= chance:
			actions.append({"type": "miss", "target": "npc", "id": npc_id})
			actions.append({"type": "system_message", "text": "未命中。"})
			return false
		if _combat_randf() < _crit_chance(_attacker_level(attacker_id)):
			crit = true
			amount = maxi(1, int(round(float(amount) * CRIT_DAMAGE_MULT)))
	var def: int = _effective_def_npc(npc_id)
	var dealt: int = maxi(1, amount - def)
	var hp: int = maxi(0, int(st.get("hp", 0)) - dealt)
	var hp_max: int = int(st.get("hp_max", 1))
	st["hp"] = hp
	stats.npcs[npc_id] = st
	# Hate ≈ damage * attacker threat_mod (tank >1.0). Actor id from session when set.
	var actor_id := "player"
	if "player_actor_id" in stats:
		var aid := str(stats.player_actor_id).strip_edges()
		if aid != "":
			actor_id = aid
	var threat_mod := 1.0
	if stats.has_method("get_actor_threat_mod"):
		threat_mod = float(stats.get_actor_threat_mod(actor_id))
	elif typeof(stats.player) == TYPE_DICTIONARY:
		threat_mod = float(stats.player.get("threat_mod", 1.0))
	if stats.has_method("add_hate"):
		stats.add_hate(npc_id, actor_id, float(dealt), threat_mod)
	elif stats.has_method("add_threat"):
		stats.add_threat(npc_id, actor_id, float(dealt) * threat_mod)
	# Pack assist BEFORE remove_npc (killing blow must still wake allies).
	if stats.has_method("activate_group_allies"):
		stats.activate_group_allies(npc_id)
	# Surviving hit → chase/enrage self.
	if hp > 0:
		if stats.has_method("begin_chase"):
			stats.begin_chase(npc_id)
		elif stats.has_method("enrage_npc"):
			stats.enrage_npc(npc_id)
	var dmg_act := {
		"type": "damage",
		"target": "npc",
		"id": npc_id,
		"amount": dealt,
		"hp": hp,
		"hp_max": hp_max,
	}
	if crit:
		dmg_act["crit"] = true
	actions.append(dmg_act)
	# Personal DPS: player (or session actor) damage to NPC.
	if _dps_attacker_is_player(attacker_id):
		var dps_act: Dictionary = note_dps_hit(dealt)
		if not dps_act.is_empty():
			actions.append(dps_act)
	if hp <= 0:
		var death_cell := {"x": 0, "y": 0}
		var has_death_cell := false
		if stats.has_method("get_npc_cell"):
			var dc: Vector2i = stats.get_npc_cell(npc_id)
			if dc.x > -9990:
				death_cell = {"x": dc.x, "y": dc.y}
				has_death_cell = true
		# Ally / revive-eligible: keep corpse (hp=0, awaiting_respawn) so revive works post-combat.
		var is_ally := _npc_is_ally(st)
		if is_ally:
			st["hp"] = 0
			st["awaiting_respawn"] = true
			stats.npcs[npc_id] = st
			var down_act := {"type": "ally_downed", "npc_id": npc_id, "hp": 0}
			if has_death_cell:
				down_act["cell"] = death_cell
			actions.append(down_act)
		else:
			stats.remove_npc(npc_id)
			var kill_act := {"type": "kill_npc", "npc_id": npc_id}
			if has_death_cell:
				kill_act["cell"] = death_cell
			actions.append(kill_act)
			actions.append({"type": "system_message", "text": "击败了敌人。"})
	if weapon_wear:
		_apply_weapon_hit_wear(actions)
	return true


## −1 main-hand weapon durability on successful damaging hit; break+remove at 0.
func _apply_weapon_hit_wear(actions: Array) -> void:
	if gear == null or not gear.has_method("wear_weapon"):
		return
	var wr: Dictionary = gear.wear_weapon(1, "weapon_main")
	if not bool(wr.get("ok", false)):
		return
	actions.append({
		"type": "equipment_update",
		"equipment": gear.snapshot() if gear.has_method("snapshot") else [],
		"bonuses": gear.total_bonuses() if gear.has_method("total_bonuses") else {},
	})
	if bool(wr.get("broken", false)):
		actions.append({"type": "system_message", "text": "武器已损坏。"})


## Returns true if the hit landed. False on miss (no HP change).
func _damage_player(amount: int, actions: Array, source: String = "", roll_accuracy: bool = true) -> bool:
	var p: Dictionary = stats.player
	var crit := false
	if roll_accuracy:
		var atk_lv: int = _attacker_level(source if source != "" else "npc")
		var def_lv: int = maxi(1, int(p.get("level", 1)))
		var chance: float = _hit_chance(atk_lv, def_lv)
		if _combat_randf() >= chance:
			var miss_act := {"type": "miss", "target": "player", "id": "player"}
			if source != "":
				miss_act["source"] = source
			actions.append(miss_act)
			actions.append({"type": "system_message", "text": "未命中。"})
			return false
		if _combat_randf() < _crit_chance(atk_lv):
			crit = true
			amount = maxi(1, int(round(float(amount) * CRIT_DAMAGE_MULT)))
	var def: int = _effective_def_player()
	var dealt: int = maxi(1, amount - def)
	var absorbed := 0
	var mp_drain := 0
	# Mana shield: absorb portion of incoming damage as MP (1 MP per hp_per_mp HP).
	if stats.statuses != null and stats.statuses.has_status("player", "mana_shield"):
		var shield: Dictionary = stats.statuses.get_status("player", "mana_shield")
		var ratio: float = float(shield.get("absorb_ratio", 0.5))
		if ratio <= 0.0:
			ratio = 0.5
		var amax: int = int(shield.get("absorb_max", 0))
		var hp_per_mp: int = int(shield.get("hp_per_mp", 2))
		if hp_per_mp <= 0:
			hp_per_mp = 2
		var want: int = int(floor(float(dealt) * ratio + 1e-6))
		if amax > 0:
			want = mini(want, amax)
		want = clampi(want, 0, dealt)
		var mp_now: int = int(p.get("mp", 0))
		if want > 0 and mp_now > 0:
			var max_by_mp: int = mp_now * hp_per_mp
			var raw_abs: int = mini(want, max_by_mp)
			# Exact chunks: 1 MP per hp_per_mp HP absorbed.
			mp_drain = mini(mp_now, raw_abs / hp_per_mp)
			absorbed = mp_drain * hp_per_mp
			if absorbed > 0:
				dealt -= absorbed
				p["mp"] = mp_now - mp_drain
	var hp: int = maxi(0, int(p.get("hp", 0)) - dealt)
	var hp_max: int = int(p.get("hp_max", 1))
	p["hp"] = hp
	stats.player = p
	# Taking damage cancels stealth / mount (even if fully absorbed by mana shield).
	break_stealth(actions)
	break_mount(actions)
	var act := {
		"type": "damage",
		"target": "player",
		"id": "player",
		"amount": dealt,
		"hp": hp,
		"hp_max": hp_max,
		"mp": int(p.get("mp", 0)),
		"mp_max": int(p.get("mp_max", 0)),
	}
	if absorbed > 0:
		act["absorbed"] = absorbed
		act["mp_drain"] = mp_drain
	if source != "":
		act["source"] = source
	if crit:
		act["crit"] = true
	actions.append(act)
	if hp <= 0:
		if stats.statuses != null:
			stats.statuses.clear_all_on_death("player")
		actions.append({"type": "player_died"})
		actions.append({"type": "system_message", "text": "你被击败了……"})
	return true


func _heal_player(amount: int, actions: Array) -> void:
	var p: Dictionary = stats.player
	var hp_max: int = int(p.get("hp_max", 1))
	var before: int = int(p.get("hp", 0))
	var hp: int = mini(hp_max, before + amount)
	var gained: int = hp - before
	p["hp"] = hp
	stats.player = p
	actions.append({
		"type": "heal",
		"target": "player",
		"id": "player",
		"amount": gained,
		"hp": hp,
		"hp_max": hp_max,
		"mp": int(p.get("mp", 0)),
		"mp_max": int(p.get("mp_max", 0)),
	})


func _restore_mp(amount: int, actions: Array) -> void:
	var p: Dictionary = stats.player
	var mp_max: int = int(p.get("mp_max", 1))
	var before: int = int(p.get("mp", 0))
	var mp: int = mini(mp_max, before + amount)
	var gained: int = mp - before
	p["mp"] = mp
	stats.player = p
	actions.append({
		"type": "heal",
		"target": "player",
		"id": "player",
		"amount": 0,
		"mp_gain": gained,
		"hp": int(p.get("hp", 0)),
		"hp_max": int(p.get("hp_max", 0)),
		"mp": mp,
		"mp_max": mp_max,
	})


func _spend_mp(cost: int) -> bool:
	var p: Dictionary = stats.player
	var mp: int = int(p.get("mp", 0))
	if mp < cost:
		return false
	p["mp"] = mp - cost
	stats.player = p
	return true


func _spend_npc_mp(npc_id: String, cost: int) -> bool:
	if cost <= 0:
		return true
	if stats == null or not stats.npcs.has(npc_id):
		return false
	var st: Dictionary = stats.npcs[npc_id]
	var mp: int = int(st.get("mp", 0))
	if mp < cost:
		return false
	st["mp"] = mp - cost
	stats.npcs[npc_id] = st
	return true


func _npc_stat_actions(npc_id: String) -> Array:
	if stats == null or not stats.npcs.has(npc_id):
		return []
	var st: Dictionary = stats.npcs[npc_id]
	var act := {
		"type": "set_stat",
		"target": "npc",
		"id": npc_id,
		"hp": int(st.get("hp", 0)),
		"hp_max": int(st.get("hp_max", 0)),
		"mp": int(st.get("mp", 0)),
		"mp_max": int(st.get("mp_max", 0)),
	}
	# Piggyback threat / aggro for selected-target HUD.
	if stats.has_method("snapshot_threat"):
		var thr: Dictionary = stats.snapshot_threat(npc_id)
		act["threat_you"] = bool(thr.get("threat_you", false))
		act["threat_rank"] = int(thr.get("threat_rank", 0))
		act["threat_pct"] = float(thr.get("threat_pct", 0.0))
		act["victim_id"] = str(thr.get("victim_id", ""))
	return [act]


## Dedicated threat_update action from hate_list / victim_id (empty if no AI).
func _threat_update_action(npc_id: String) -> Dictionary:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or stats == null or not stats.has_method("snapshot_threat"):
		return {}
	var thr: Dictionary = stats.snapshot_threat(npc_id)
	return {
		"type": "threat_update",
		"npc_id": npc_id,
		"threat_you": bool(thr.get("threat_you", false)),
		"threat_rank": int(thr.get("threat_rank", 0)),
		"threat_pct": float(thr.get("threat_pct", 0.0)),
		"victim_id": str(thr.get("victim_id", "")),
	}


func _in_range(npc_id: String, player_x: int, player_y: int, range_cells: int) -> bool:
	return _targeting_module_logic._in_range(npc_id, player_x, player_y, range_cells)
func _maybe_counter(npc_id: String, player_x: int, player_y: int, actions: Array) -> void:
	if not stats.npcs.has(npc_id):
		return
	var st: Dictionary = stats.npcs[npc_id]
	if int(st.get("hp", 0)) <= 0:
		return
	if not bool(st.get("hostile", true)):
		return
	if not _in_range(npc_id, player_x, player_y, 1):
		return
	var atk: int = _effective_atk_npc(npc_id)
	_damage_player(atk, actions, npc_id)


func _effective_atk_player() -> int:
	var base: int = int(stats.player.get("atk", 10))
	base += _gear_bonus("p_atk") + _gear_bonus("atk")
	base += _passive_bonus("atk")
	if stats.statuses != null:
		return int(stats.statuses.effective_atk(base, "player"))
	return maxi(1, base)


func _effective_def_player() -> int:
	var base: int = int(stats.player.get("def", 0))
	base += _gear_bonus("p_def") + _gear_bonus("def")
	base += _passive_bonus("def")
	if stats.statuses != null:
		return int(stats.statuses.effective_def(base, "player"))
	return maxi(0, base)


func _gear_bonus(stat_key: String) -> int:
	if gear == null or not gear.has_method("total_bonuses"):
		return 0
	var b: Dictionary = gear.total_bonuses()
	return int(b.get(stat_key, 0))


## Catalog passives only apply when the skill is in the player's known set.
func _passive_bonus(stat: String) -> int:
	if skills == null or not skills.has_method("list_all"):
		return 0
	var book = null
	if stats != null and "skill_book" in stats and stats.skill_book != null:
		book = stats.skill_book
	var n := 0
	for d_v in skills.list_all():
		if typeof(d_v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = d_v
		var sid := str(d.get("id", "")).strip_edges()
		if sid.is_empty():
			continue
		if book != null and book.has_method("is_known") and not book.is_known(sid):
			continue
		var cat := str(d.get("category", "")).strip_edges()
		var eff := str(d.get("effect", "")).strip_edges()
		if cat != "passive" and not eff.begins_with("passive"):
			continue
		if stat == "atk":
			n += int(d.get("atk_bonus", 0))
		elif stat == "def":
			n += int(d.get("def_bonus", 0))
	return n


func _effective_atk_npc(npc_id: String) -> int:
	if not stats.npcs.has(npc_id):
		return 5
	var base: int = int(stats.npcs[npc_id].get("atk", 5))
	if stats.statuses != null:
		return int(stats.statuses.effective_atk(base, npc_id))
	return maxi(1, base)


func _effective_def_npc(npc_id: String) -> int:
	if not stats.npcs.has(npc_id):
		return 0
	var base: int = int(stats.npcs[npc_id].get("def", 0))
	if stats.statuses != null:
		return int(stats.statuses.effective_def(base, npc_id))
	return maxi(0, base)


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return _targeting_module_logic._chebyshev(a, b)
func skill_target_mode(def: Dictionary) -> String:
	return _targeting_module_logic.skill_target_mode(def)
func _dir_delta(d: int) -> Vector2i:
	return _targeting_module_logic._dir_delta(d)
func facing_toward(from: Vector2i, to: Vector2i) -> int:
	return _targeting_module_logic.facing_toward(from, to)
func cell_in_aoe(center: Vector2i, cell: Vector2i, radius: int, shape: String, facing: int = 2) -> bool:
	return _targeting_module_logic.cell_in_aoe(center, cell, radius, shape, facing)
func aoe_cells(center: Vector2i, radius: int, shape: String, facing: int = 2) -> Array:
	return _targeting_module_logic.aoe_cells(center, radius, shape, facing)
func _cell_in_range(from: Vector2i, to: Vector2i, range_cells: int) -> bool:
	return _targeting_module_logic._cell_in_range(from, to, range_cells)
func _resolve_ground_cell( def: Dictionary, target_npc_id: String, player_x: int, player_y: int, ground_x: int, ground_y: int ) -> Vector2i:
	return _targeting_module_logic._resolve_ground_cell(def, target_npc_id, player_x, player_y, ground_x, ground_y)
func _append_skill_fx(
	actions: Array,
	def: Dictionary,
	skill_id: String,
	caster: String,
	center: Vector2i,
	hits: Array
) -> void:
	var shape := str(def.get("aoe_shape", "circle"))
	var radius: int = int(def.get("aoe_radius", 0))
	var effect := str(def.get("effect", ""))
	actions.append({
		"type": "skill_fx",
		"skill_id": skill_id,
		"effect": effect,
		"shape": shape,
		"radius": radius,
		"cell": {"x": center.x, "y": center.y},
		"actor": caster,
		"hits": hits.duplicate(),
		"anim": skill_anim_kind(def, skill_id),
	})
	actions.append({
		"type": "skill_anim",
		"actor": caster,
		"kind": skill_anim_kind(def, skill_id),
		"skill_id": skill_id,
	})


func skill_anim_kind(def: Dictionary, skill_id: String = "") -> String:
	var a := str(def.get("anim", "")).strip_edges().to_lower()
	if a == "strike" or a == "cast" or a == "dash" or a == "spin":
		return a
	var sid := skill_id.strip_edges()
	if sid.is_empty():
		sid = str(def.get("id", "")).strip_edges()
	match sid:
		"basic_attack", "power_strike", "execute":
			return "strike"
		"poison_dart":
			return "dash"
		"charge":
			return "dash"
		"battle_cry", "battle_shout":
			return "spin"
		_:
			var effect := str(def.get("effect", ""))
			if effect == "damage" or effect == "damage_and_status":
				return "strike"
			return "cast"


## Living hostile NPCs within AoE of center, nearest first, capped.
func _collect_aoe_hostiles( center: Vector2i, radius: int, max_targets: int, shape: String = "circle", facing: int = 2 ) -> Array:
	return _targeting_module_logic._collect_aoe_hostiles(center, radius, max_targets, shape, facing)
func _apply_status_to(target_key: String, status_def: Dictionary, source_id: String, actions: Array) -> void:
	## Re-apply same id → refresh duration (stack_max default 1); optional stack_max>1 stacks.
	if status_def.is_empty() or stats.statuses == null:
		return
	var dur: float = float(status_def.get("duration", 5.0))
	stats.statuses.apply_status(target_key, status_def, dur, source_id)
	actions.append(stats.statuses.status_update_action(target_key))
	# Stealth applied on player: drop current aggro / return home.
	if target_key == "player" and str(status_def.get("id", "")).strip_edges() == "stealth":
		_break_all_player_chases()


func player_has_stealth() -> bool:
	return _player_state_module_logic.player_has_stealth()
## Clear stealth buff if present; append status_update. Used when attacking / taking damage.
func break_stealth(actions: Array) -> bool:
	return _player_state_module_logic.break_stealth(actions)
func player_is_mounted() -> bool:
	return _player_state_module_logic.player_is_mounted()
## Thin combat gate: active DPS fight or any NPC chasing / hating the player.
func player_in_combat() -> bool:
	return _player_state_module_logic.player_in_combat()
## Clear mounted buff; append status_update + 「已下马。」. Used on combat / damage / attack.
func break_mount(actions: Array) -> bool:
	return _player_state_module_logic.break_mount(actions)
func _apply_mount_toggle(def: Dictionary, actions: Array) -> void:
	_player_state_module_logic._apply_mount_toggle(def, actions)
func _break_all_player_chases() -> void:
	_player_state_module_logic._break_all_player_chases()
func _status_def_from_skill(def: Dictionary) -> Dictionary:
	var sv: Variant = def.get("status", {})
	if typeof(sv) != TYPE_DICTIONARY:
		return {}
	return (sv as Dictionary).duplicate(true)


## Basic / auto attack (extends former MockServer.try_attack).
func try_attack(npc_id: String, player_x: int, player_y: int) -> Dictionary:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or not stats.player_alive():
		return {"ok": false, "actions": []}
	if is_casting():
		return {"ok": false, "actions": [{"type": "system_message", "text": "施法中，无法普攻。"}]}
	if not stats.is_attack_ready():
		return {
			"ok": false,
			"actions": [{"type": "system_message", "text": "攻击冷却中。"}],
		}
	if not _in_range(npc_id, player_x, player_y, 1):
		return {"ok": false, "actions": [{"type": "system_message", "text": "目标太远。"}]}
	var st: Dictionary = stats.ensure_npc(npc_id, true)
	if int(st.get("hp", 0)) <= 0:
		return {"ok": false, "actions": []}
	var cd: float = float(stats.player.get("atk_speed", 0.8))
	stats.set_attack_cooldown(cd)
	# Mirror basic_attack skill CD so hotbar shares timing.
	stats.set_skill_cooldown("basic_attack", cd)
	var actions: Array = []
	break_stealth(actions)
	break_mount(actions)
	var atk: int = _effective_atk_player()
	_damage_npc(npc_id, atk, actions, true, "player", true)
	_maybe_counter(npc_id, player_x, player_y, actions)
	var thr_act: Dictionary = _threat_update_action(npc_id)
	if not thr_act.is_empty():
		actions.append(thr_act)
	actions.append_array(_player_stat_actions())
	actions.append({
		"type": "skill_cd",
		"skill_id": "basic_attack",
		"remaining": cd,
		"cooldown": cd,
	})
	return {"ok": true, "actions": actions}


func is_casting() -> bool:
	return _cast_module_logic.is_casting()
func clear_cast() -> void:
	_cast_module_logic.clear_cast()
## Interrupt active cast/channel. Returns actions (may be empty if idle).
func interrupt_cast(reason: String = "move") -> Array:
	return _cast_module_logic.interrupt_cast(reason)
## Advance cast/channel; on finish resolves skill effect. Returns action list.
func tick_cast(delta: float) -> Array:
	return _cast_module_logic.tick_cast(delta)
func try_use_skill(
	skill_id: String,
	target_npc_id: String,
	player_x: int,
	player_y: int,
	ground_x: int = -9999,
	ground_y: int = -9999
) -> Dictionary:
	skill_id = skill_id.strip_edges()
	target_npc_id = target_npc_id.strip_edges()
	if skill_id.is_empty():
		return {"ok": false, "actions": []}
	if not stats.player_alive():
		return {"ok": false, "actions": [{"type": "system_message", "text": "你已经倒下了。"}]}
	# Must know the skill (starters included). basic_attack is always known via SkillBook.
	if stats != null and stats.skill_book != null and stats.skill_book.has_method("is_known"):
		if not stats.skill_book.is_known(skill_id):
			var sname := skill_id
			if skills != null:
				var ud: Dictionary = skills.get_skill(skill_id)
				if not ud.is_empty():
					sname = str(ud.get("name", skill_id))
			return {
				"ok": false,
				"actions": [{"type": "system_message", "text": "尚未学会【%s】。" % sname}],
			}
	# basic_attack delegates to try_attack.
	if skill_id == "basic_attack":
		return try_attack(target_npc_id, player_x, player_y)
	if is_casting():
		return {"ok": false, "actions": [{"type": "system_message", "text": "正在施法中。"}]}
	var def: Dictionary = skills.get_skill(skill_id)
	if def.is_empty():
		return {"ok": false, "actions": [{"type": "system_message", "text": "未知技能。"}]}
	var cat := str(def.get("category", "")).strip_edges()
	if cat.is_empty():
		# Infer: passive_* effects are never castable.
		var eff0 := str(def.get("effect", ""))
		if eff0.begins_with("passive"):
			cat = "passive"
	if cat == "passive":
		return {"ok": false, "actions": [{"type": "system_message", "text": "被动，无需施放"}]}
	# Mount toggle: block mounting while in combat (dismount always allowed).
	var eff_gate := str(def.get("effect", "")).strip_edges()
	if skill_id == "mount" or eff_gate == "mount":
		if not player_is_mounted() and player_in_combat():
			return {"ok": false, "actions": [{"type": "system_message", "text": "战斗中无法骑乘。"}]}
	if not stats.is_skill_ready(skill_id):
		var rem: float = stats.skill_cd_remaining(skill_id)
		return {
			"ok": false,
			"actions": [
				{"type": "system_message", "text": "技能冷却中（%.1f 秒）。" % rem},
				{"type": "skill_cd", "skill_id": skill_id, "remaining": rem, "cooldown": float(def.get("cooldown", 0))},
			],
		}
	var mp_cost: int = int(def.get("mp_cost", 0))
	if int(stats.player.get("mp", 0)) < mp_cost:
		return {"ok": false, "actions": [{"type": "system_message", "text": "MP 不足。"}]}
	var needs_target: bool = bool(def.get("requires_target", false))
	var tmode := skill_target_mode(def)
	var range_cells: int = int(def.get("range", 1))
	var gcell: Vector2i = _resolve_ground_cell(def, target_npc_id, player_x, player_y, ground_x, ground_y)
	if tmode == "ground":
		if gcell.x <= -9990:
			return {"ok": false, "reason": "need_ground", "actions": [{"type": "system_message", "text": "需要选择地点。"}]}
		if not _cell_in_range(Vector2i(player_x, player_y), gcell, range_cells):
			return {"ok": false, "actions": [{"type": "system_message", "text": "地点太远。"}]}
		ground_x = gcell.x
		ground_y = gcell.y
	elif needs_target:
		if target_npc_id.is_empty():
			return {"ok": false, "actions": [{"type": "system_message", "text": "需要目标。"}]}
		var eff_chk := str(def.get("effect", "")).strip_edges()
		if eff_chk == "revive":
			# Dead ally only — do not auto-spawn a living NPC via ensure_npc.
			if target_npc_id == "player" or (
				"player_actor_id" in stats and target_npc_id == str(stats.player_actor_id).strip_edges()
			):
				return {"ok": false, "actions": [{"type": "system_message", "text": "无法自我复活。"}]}
			if not stats.npcs.has(target_npc_id):
				return {"ok": false, "actions": [{"type": "system_message", "text": "只能复活队友。"}]}
			if not _in_range(target_npc_id, player_x, player_y, range_cells):
				return {"ok": false, "actions": [{"type": "system_message", "text": "目标太远。"}]}
			var rst: Dictionary = stats.npcs[target_npc_id]
			if not bool(rst.get("ally", false)):
				return {"ok": false, "actions": [{"type": "system_message", "text": "只能复活队友。"}]}
			var deadish := int(rst.get("hp", 0)) <= 0 or bool(rst.get("awaiting_respawn", false))
			if not deadish:
				return {"ok": false, "actions": [{"type": "system_message", "text": "目标未死亡。"}]}
		else:
			if not _in_range(target_npc_id, player_x, player_y, range_cells):
				return {"ok": false, "actions": [{"type": "system_message", "text": "目标太远。"}]}
			stats.ensure_npc(target_npc_id, true)
			if not stats.npcs.has(target_npc_id) or int(stats.npcs[target_npc_id].get("hp", 0)) <= 0:
				return {"ok": false, "actions": [{"type": "system_message", "text": "目标已死亡或不存在。"}]}
			# Taunt / interrupt / mark require a living hostile target.
			if eff_chk == "taunt":
				if not bool(stats.npcs[target_npc_id].get("hostile", false)):
					return {"ok": false, "actions": [{"type": "system_message", "text": "只能嘲讽敌对目标。"}]}
			elif eff_chk == "interrupt":
				if not bool(stats.npcs[target_npc_id].get("hostile", false)):
					return {"ok": false, "actions": [{"type": "system_message", "text": "只能打断敌对目标。"}]}
			elif eff_chk == "mark":
				if not bool(stats.npcs[target_npc_id].get("hostile", false)):
					return {"ok": false, "actions": [{"type": "system_message", "text": "只能标记敌对目标。"}]}
			elif eff_chk == "charge":
				if not bool(stats.npcs[target_npc_id].get("hostile", false)):
					return {"ok": false, "actions": [{"type": "system_message", "text": "只能冲锋敌对目标。"}]}
				var min_r: int = int(def.get("min_range", 0))
				if min_r > 0:
					var tcell: Vector2i = stats.get_npc_cell(target_npc_id)
					var cdist: int = maxi(absi(tcell.x - player_x), absi(tcell.y - player_y))
					if cdist < min_r:
						return {"ok": false, "actions": [{"type": "system_message", "text": "目标太近，无法冲锋。"}]}
				var path_err := _charge_path_error(target_npc_id, player_x, player_y)
				if path_err != "":
					return {"ok": false, "actions": [{"type": "system_message", "text": path_err}]}
			elif eff_chk == "execute":
				if not bool(stats.npcs[target_npc_id].get("hostile", false)):
					return {"ok": false, "actions": [{"type": "system_message", "text": "只能斩杀敌对目标。"}]}
				var ehp: int = int(stats.npcs[target_npc_id].get("hp", 0))
				var emax: int = maxi(1, int(stats.npcs[target_npc_id].get("hp_max", 1)))
				var thr: float = float(def.get("hp_threshold", 0.3))
				if thr <= 0.0:
					thr = 0.3
				if float(ehp) / float(emax) > thr:
					return {"ok": false, "actions": [{"type": "system_message", "text": "目标生命过高。"}]}
	# Cast / channel: validate at start, lock CD + spend MP at start (interrupt wastes MP).
	var cast_time: float = float(def.get("cast_time", 0.0))
	var channel_time: float = float(def.get("channel_time", 0.0))
	var use_cast := cast_time > 0.0
	var use_channel := (not use_cast) and channel_time > 0.0
	if use_cast or use_channel:
		if not _spend_mp(mp_cost):
			return {"ok": false, "actions": [{"type": "system_message", "text": "MP 不足。"}]}
		var cd: float = float(def.get("cooldown", 1.0))
		stats.set_skill_cooldown(skill_id, cd)
		var mode := "cast" if use_cast else "channel"
		var duration: float = cast_time if use_cast else channel_time
		var interrupt_on_move: bool = bool(def.get("interrupt_on_move", true))
		var sname := str(def.get("name", skill_id))
		var start_act: Dictionary = cast.begin(
			skill_id, sname, mode, duration, target_npc_id, player_x, player_y, def, interrupt_on_move, ground_x, ground_y
		)
		var actions: Array = [start_act]
		actions.append_array(_player_stat_actions())
		actions.append({
			"type": "skill_cd",
			"skill_id": skill_id,
			"remaining": cd,
			"cooldown": cd,
		})
		actions.append({"type": "system_message", "text": "开始施放【%s】…" % sname})
		return {"ok": true, "actions": actions}
	# Instant path.
	if not _spend_mp(mp_cost):
		return {"ok": false, "actions": [{"type": "system_message", "text": "MP 不足。"}]}
	var cd_i: float = float(def.get("cooldown", 1.0))
	stats.set_skill_cooldown(skill_id, cd_i)
	var actions_i: Array = []
	_resolve_skill_effect(def, skill_id, target_npc_id, player_x, player_y, actions_i, ground_x, ground_y, "player")
	actions_i.append({
		"type": "skill_cd",
		"skill_id": skill_id,
		"remaining": cd_i,
		"cooldown": cd_i,
	})
	return {"ok": true, "actions": actions_i}


## NPC skill. cast_time > 0 starts casting (resolve on tick / cancel via interrupt).
func try_npc_skill(
	npc_id: String,
	skill_id: String,
	npc_x: int,
	npc_y: int,
	ground_x: int = -9999,
	ground_y: int = -9999
) -> Dictionary:
	npc_id = npc_id.strip_edges()
	skill_id = skill_id.strip_edges()
	if npc_id.is_empty() or skill_id.is_empty() or stats == null or skills == null:
		return {"ok": false, "actions": []}
	if not stats.npcs.has(npc_id) or int(stats.npcs[npc_id].get("hp", 0)) <= 0:
		return {"ok": false, "actions": []}
	if not stats.player_alive():
		return {"ok": false, "actions": []}
	# Silence debuff blocks NPC skill use (interrupt fantasy).
	if stats.statuses != null and stats.statuses.has_status(npc_id, "silence"):
		return {"ok": false, "reason": "silence", "actions": []}
	if is_npc_casting(npc_id):
		return {"ok": false, "reason": "busy", "actions": []}
	var def: Dictionary = skills.get_skill(skill_id)
	if def.is_empty():
		return {"ok": false, "actions": []}
	var cat := str(def.get("category", "")).strip_edges()
	if cat == "passive" or str(def.get("effect", "")).begins_with("passive"):
		return {"ok": false, "actions": []}
	var range_cells: int = int(def.get("range", 1))
	var gcell: Vector2i = Vector2i(ground_x, ground_y)
	if gcell.x <= -9990:
		gcell = Vector2i(npc_x, npc_y)
	if not _cell_in_range(Vector2i(npc_x, npc_y), gcell, range_cells):
		return {"ok": false, "reason": "range", "actions": []}
	var mp_cost: int = int(def.get("mp_cost", 0))
	if not _spend_npc_mp(npc_id, mp_cost):
		return {"ok": false, "reason": "mp", "actions": []}
	var actions: Array = []
	actions.append_array(_npc_stat_actions(npc_id))
	var cast_time: float = float(def.get("cast_time", 0.0))
	if cast_time > 0.0:
		var cs = CastState.new()
		var sname := str(def.get("name", skill_id)).strip_edges()
		if sname.is_empty():
			sname = skill_id
		var start_act: Dictionary = cs.begin(
			skill_id, sname, "cast", cast_time, "", npc_x, npc_y, def, false, gcell.x, gcell.y
		)
		start_act["npc_id"] = npc_id
		start_act["caster"] = npc_id
		npc_casts[npc_id] = cs
		actions.append(start_act)
		return {"ok": true, "casting": true, "actions": actions}
	_resolve_skill_effect(def, skill_id, "", npc_x, npc_y, actions, gcell.x, gcell.y, npc_id)
	return {"ok": true, "actions": actions}


func is_npc_casting(npc_id: String) -> bool:
	return _cast_module_logic.is_npc_casting(npc_id)
## Cancel NPC cast. Returns cast_end actions (no player 「施法被打断」 msg).
func cancel_npc_cast(npc_id: String, reason: String = "interrupt") -> Array:
	return _cast_module_logic.cancel_npc_cast(npc_id, reason)
func clear_npc_cast(npc_id: String) -> void:
	_cast_module_logic.clear_npc_cast(npc_id)
## Advance all NPC casts; on finish resolves skill. Returns action list.
func tick_npc_casts(delta: float) -> Array:
	return _cast_module_logic.tick_npc_casts(delta)
## Force victim / top hate onto the player via a large add_hate spike.
func _apply_taunt(npc_id: String, def: Dictionary, actions: Array) -> void:
	_skill_effects_module_logic._apply_taunt(npc_id, def, actions)


## Tiny damage + silence debuff on hostile (interrupt skill fantasy).
## If the NPC is casting, cancel the cast first (msg 「打断了{名}的施法！」).
func _apply_interrupt(npc_id: String, def: Dictionary, actions: Array) -> void:
	_skill_effects_module_logic._apply_interrupt(npc_id, def, actions)


## Apply mark debuff (def_mul) on hostile — increases damage taken.
func _apply_mark(npc_id: String, def: Dictionary, actions: Array) -> void:
	_skill_effects_module_logic._apply_mark(npc_id, def, actions)


## Revive a dead ally NPC (~30% max HP); keeps death cell.
func _apply_revive(npc_id: String, def: Dictionary, actions: Array) -> void:
	_skill_effects_module_logic._apply_revive(npc_id, def, actions)



## Adjacent landing cell for charge (Chebyshev), preferring the side toward the caster.
func _charge_dest_cell(npc_id: String, player_x: int, player_y: int) -> Vector2i:
	return _skill_effects_module_logic._charge_dest_cell(npc_id, player_x, player_y)


## Empty string if charge path OK; Chinese reason if blocked / no landing.
func _charge_path_error(npc_id: String, player_x: int, player_y: int) -> String:
	return _skill_effects_module_logic._charge_path_error(npc_id, player_x, player_y)


## Dash adjacent to hostile, light physical hit, brief root.
func _apply_charge(npc_id: String, def: Dictionary, player_x: int, player_y: int, actions: Array) -> Vector2i:
	return _skill_effects_module_logic._apply_charge(npc_id, def, player_x, player_y, actions)



## Finisher: high physical damage on low-HP hostile (HP ≤ threshold).
func _apply_execute(npc_id: String, def: Dictionary, player_x: int, player_y: int, actions: Array) -> void:
	_skill_effects_module_logic._apply_execute(npc_id, def, player_x, player_y, actions)


## Apply skill damage/heal/status/aoe after validation + MP/CD already handled.
func _resolve_skill_effect(
	def: Dictionary,
	skill_id: String,
	target_npc_id: String,
	player_x: int,
	player_y: int,
	actions: Array,
	ground_x: int = -9999,
	ground_y: int = -9999,
	caster: String = "player"
) -> void:
	_skill_effects_module_logic._resolve_skill_effect(def, skill_id, target_npc_id, player_x, player_y, actions, ground_x, ground_y, caster)


func try_use_item(item_id: String) -> Dictionary:
	item_id = item_id.strip_edges()
	if item_id.is_empty() or not stats.player_alive():
		return {"ok": false, "actions": []}
	var def: Dictionary = items.get_item(item_id)
	if def.is_empty():
		return {"ok": false, "actions": [{"type": "system_message", "text": "未知物品。"}]}
	# Equipment is equipped via MockServer.try_equip_item, not consumed here.
	var type_s := str(def.get("type", "")).strip_edges()
	var ue0 := str(def.get("use_effect", def.get("effect", ""))).strip_edges()
	if type_s == "equipment":
		return {"ok": false, "actions": [{"type": "system_message", "text": "无法直接使用该物品。"}]}
	if not bool(def.get("consumable", false)) and not _is_item_effect(ue0):
		return {"ok": false, "actions": [{"type": "system_message", "text": "无法直接使用该物品。"}]}
	if not bag.has_item(item_id, 1):
		return {"ok": false, "actions": [{"type": "system_message", "text": "背包中没有该物品。"}]}
	if not stats.is_item_ready(item_id):
		return {"ok": false, "actions": [{"type": "system_message", "text": "物品冷却中。"}]}
	# Prefer use_effect (item_template); fall back to legacy effect.
	var effect := str(def.get("use_effect", "")).strip_edges()
	if effect.is_empty():
		effect = str(def.get("effect", "")).strip_edges()
	# Out-of-combat-only consumables (e.g. bandage) fail before consume.
	if bool(def.get("out_of_combat_only", false)) and player_in_combat():
		var fail_msg := str(def.get("combat_fail_msg", "战斗中无法使用。")).strip_edges()
		if fail_msg.is_empty():
			fail_msg = "战斗中无法使用。"
		return {
			"ok": false,
			"reason": "in_combat",
			"actions": [{"type": "system_message", "text": fail_msg}],
		}
	# Fail before consume: MP potions when already full.
	if effect == "heal_mp":
		var mp_now: int = int(stats.player.get("mp", 0))
		var mp_cap: int = int(stats.player.get("mp_max", 1))
		if mp_now >= mp_cap:
			return {
				"ok": false,
				"reason": "mp_full",
				"actions": [{"type": "system_message", "text": "魔力已满。"}],
			}
	# Fail before consume: repair kit needs damaged equip and/or bag tools.
	if effect == "repair_equip":
		var need_eq: bool = gear != null and gear.has_method("needs_repair") and bool(gear.needs_repair())
		var need_tool: bool = bag != null and bag.has_method("tools_need_repair") and bool(bag.tools_need_repair())
		if not need_eq and not need_tool:
			return {
				"ok": false,
				"reason": "nothing_to_repair",
				"actions": [{"type": "system_message", "text": "没有需要修理的装备。"}],
			}
	if not bag.consume(item_id, 1):
		return {"ok": false, "actions": [{"type": "system_message", "text": "背包中没有该物品。"}]}
	var cd: float = float(def.get("cooldown", 1.0))
	stats.set_item_cooldown(item_id, cd)
	var actions: Array = []
	var resolved := _resolve_item_effect(def, effect, actions)
	if not resolved:
		actions.append({"type": "system_message", "text": "物品效果未实现：%s" % effect})
	actions.append({
		"type": "inventory_update",
		"items": bag.snapshot(),
		"gold": bag.get_gold() if bag != null and bag.has_method("get_gold") else 0,
	})
	actions.append_array(_player_stat_actions())
	var iname := str(def.get("name", item_id))
	if effect == "repair_equip" and resolved:
		var rmsg := _repair_kit_msg if not _repair_kit_msg.is_empty() else "使用修理工具包，修复了装备。"
		actions.append({"type": "system_message", "text": rmsg})
		_repair_kit_msg = ""
	elif effect != "repair_equip":
		actions.append({"type": "system_message", "text": "使用了【%s】。" % iname})
	return {"ok": true, "actions": actions}


func _is_item_effect(effect: String) -> bool:
	match effect:
		"heal_hp", "heal_mp", "apply_status", "clear_status", "cleanse", "recall", "teleport_home", "repair_equip", "party_summon":
			return true
		_:
			return false


## Returns false when the effect name is unknown (caller may emit unimplemented).
func _resolve_item_effect(def: Dictionary, effect: String, actions: Array) -> bool:
	var amount: int = int(def.get("amount", 0))
	match effect:
		"heal_hp":
			_heal_player(amount, actions)
			var amount_mp: int = int(def.get("amount_mp", 0))
			if amount_mp > 0:
				_restore_mp(amount_mp, actions)
			var st_hp: Dictionary = _status_def_from_skill(def)
			if not st_hp.is_empty():
				_apply_status_to("player", st_hp, "player", actions)
			return true
		"heal_mp":
			_restore_mp(amount, actions)
			var st_mp: Dictionary = _status_def_from_skill(def)
			if not st_mp.is_empty():
				_apply_status_to("player", st_mp, "player", actions)
			return true
		"apply_status":
			var st: Dictionary = _status_def_from_skill(def)
			if not st.is_empty():
				_apply_status_to("player", st, "player", actions)
			return true
		"clear_status":
			var sid := str(def.get("status_id", "")).strip_edges()
			if sid.is_empty():
				var nested: Dictionary = _status_def_from_skill(def)
				sid = str(nested.get("id", "")).strip_edges()
			if stats.statuses != null and sid != "":
				stats.statuses.clear_status("player", sid)
				actions.append(stats.statuses.status_update_action("player"))
			return true
		"cleanse":
			if stats.statuses != null:
				stats.statuses.clear_harmful("player")
				actions.append(stats.statuses.status_update_action("player"))
			return true
		"recall", "teleport_home":
			actions.append({"type": "recall"})
			return true
		"repair_equip":
			var frac := float(def.get("repair_fraction", 0.3))
			var did_eq := false
			var did_tool := false
			if gear != null and gear.has_method("apply_kit_repair") and gear.has_method("needs_repair") and bool(gear.needs_repair()):
				var rr: Dictionary = gear.apply_kit_repair(frac)
				if bool(rr.get("ok", false)):
					did_eq = true
					actions.append({
						"type": "equipment_update",
						"equipment": gear.snapshot() if gear.has_method("snapshot") else [],
						"bonuses": gear.total_bonuses() if gear.has_method("total_bonuses") else {},
					})
			if bag != null and bag.has_method("apply_kit_repair_tools") and bag.has_method("tools_need_repair") and bool(bag.tools_need_repair()):
				var tr: Dictionary = bag.apply_kit_repair_tools(frac)
				if bool(tr.get("ok", false)):
					did_tool = true
			if not did_eq and not did_tool:
				return false
			# Stash message kind for use_item Chinese line.
			if did_eq and did_tool:
				_repair_kit_msg = "使用修理工具包，修复了装备与工具。"
			elif did_tool:
				_repair_kit_msg = "使用修理工具包，修复了工具。"
			else:
				_repair_kit_msg = "使用修理工具包，修复了装备。"
			return true
		_:
			return false


## Periodic tick: status DoT/HoT then adjacent hostile counter.

## --- Personal DPS meter (session fight window) ---

func _dps_attacker_is_player(attacker_id: String) -> bool:
	return _dps_module_logic._dps_attacker_is_player(attacker_id)
func reset_dps_fight() -> void:
	_dps_module_logic.reset_dps_fight()
func snapshot_dps() -> Dictionary:
	return _dps_module_logic.snapshot_dps()
func _dps_update_action(active: bool) -> Dictionary:
	return _dps_module_logic._dps_update_action(active)
## Record player → NPC damage. Returns dps_update action (always when dealt > 0).
func note_dps_hit(dealt: int) -> Dictionary:
	return _dps_module_logic.note_dps_hit(dealt)
## Advance DPS clock; finalize fight after IDLE_TIMEOUT with no hits.
## Returns array of actions (0–1 dps_update with active=false).
func tick_dps(delta: float) -> Array:
	return _dps_module_logic.tick_dps(delta)
func tick(player_x: int, player_y: int, delta: float) -> Dictionary:
	player_cell_hint = Vector2i(player_x, player_y)
	# Lightweight: every ~1.5s of accumulated time handled by MockServer.
	var actions: Array = []
	if stats.statuses != null:
		actions.append_array(stats.statuses.tick_statuses(delta, stats))
	if not stats.player_alive():
		if not actions.is_empty():
			actions.append_array(_player_stat_actions())
		return {"ok": true, "actions": actions}
	for npc_id in stats.npc_cells.keys():
		if not stats.npcs.has(npc_id):
			continue
		var st: Dictionary = stats.npcs[npc_id]
		if int(st.get("hp", 0)) <= 0 or not bool(st.get("hostile", false)):
			continue
		# Leash reset: returning mobs must not counter-attack.
		if stats.npc_ai.has(str(npc_id)):
			var ai_ret: Dictionary = stats.npc_ai[str(npc_id)]
			if str(ai_ret.get("ai_state", "")) == "return_home":
				continue
		if not _in_range(str(npc_id), player_x, player_y, 1):
			continue
		_damage_player(_effective_atk_npc(str(npc_id)), actions, str(npc_id))
		actions.append_array(_player_stat_actions())
		return {"ok": true, "actions": actions}
	if not actions.is_empty():
		actions.append_array(_player_stat_actions())
	return {"ok": true, "actions": actions}
