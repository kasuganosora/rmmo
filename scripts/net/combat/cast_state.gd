extends RefCounted
## Authoritative player cast / channel state (MockServer via combat_engine).
## MP/CD are spent at cast start; interrupt wastes MP (no refund v1).

## Empty = idle. Keys: skill_id, target_id, mode, elapsed, duration,
## player_x, player_y, name, interrupted, interrupt_on_move, def (skill snapshot).
var state: Dictionary = {}


func is_busy() -> bool:
	return not state.is_empty() and not bool(state.get("interrupted", false))


func clear() -> void:
	state = {}


func snapshot() -> Dictionary:
	if state.is_empty():
		return {}
	return state.duplicate(true)


## Start cast/channel. Caller already validated CD/MP/range and spent MP + locked CD.
## Returns cast_start action dict.
func begin(
	skill_id: String,
	skill_name: String,
	mode: String,
	duration: float,
	target_id: String,
	player_x: int,
	player_y: int,
	skill_def: Dictionary,
	interrupt_on_move: bool = true
) -> Dictionary:
	mode = mode.strip_edges()
	if mode != "channel":
		mode = "cast"
	duration = maxf(duration, 0.05)
	state = {
		"skill_id": skill_id.strip_edges(),
		"target_id": target_id.strip_edges(),
		"mode": mode,
		"elapsed": 0.0,
		"duration": duration,
		"player_x": player_x,
		"player_y": player_y,
		"name": skill_name,
		"interrupted": false,
		"interrupt_on_move": interrupt_on_move,
		"def": skill_def.duplicate(true),
	}
	return {
		"type": "cast_start",
		"skill_id": state["skill_id"],
		"name": skill_name,
		"duration": duration,
		"mode": mode,
		"elapsed": 0.0,
		"fraction": 0.0,
	}


## Advance cast. Returns {actions: Array, finished: bool}.
## On complete: clears state and sets finished=true (caller resolves skill).
func tick(delta: float) -> Dictionary:
	var actions: Array = []
	if not is_busy():
		return {"actions": actions, "finished": false}
	var dur: float = maxf(float(state.get("duration", 0.0)), 0.05)
	var elapsed: float = float(state.get("elapsed", 0.0)) + maxf(delta, 0.0)
	state["elapsed"] = elapsed
	var frac: float = clampf(elapsed / dur, 0.0, 1.0)
	actions.append({
		"type": "cast_update",
		"skill_id": str(state.get("skill_id", "")),
		"name": str(state.get("name", "")),
		"mode": str(state.get("mode", "cast")),
		"elapsed": elapsed,
		"duration": dur,
		"fraction": frac,
	})
	if elapsed + 0.0001 >= dur:
		# Leave snapshot for resolver; clear busy flag by emptying after caller copies.
		return {"actions": actions, "finished": true}
	return {"actions": actions, "finished": false}


## Cancel cast. Returns actions (cast_end cancelled + optional system_message).
func interrupt(reason: String = "move") -> Array:
	var actions: Array = []
	if state.is_empty():
		return actions
	var sid := str(state.get("skill_id", ""))
	var sname := str(state.get("name", sid))
	var mode := str(state.get("mode", "cast"))
	state = {}
	actions.append({
		"type": "cast_end",
		"skill_id": sid,
		"name": sname,
		"mode": mode,
		"ok": false,
		"cancelled": true,
		"reason": reason,
	})
	actions.append({"type": "system_message", "text": "施法被打断"})
	return actions


func should_interrupt_on_move() -> bool:
	if not is_busy():
		return false
	return bool(state.get("interrupt_on_move", true))
