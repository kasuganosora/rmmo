extends RefCounted
## Map changes commit only after the target file is known to exist.

var switches := {}


static func commit(current_path: String, target_path: String, target_exists: bool) -> Dictionary:
	if target_path == "" or not target_exists:
		return {"ok": false, "path": current_path}
	return {"ok": true, "path": target_path}


static func near(feet: Vector3, center: Vector3, radius_m: float) -> bool:
	return absf(feet.y - center.y) <= 1.0 and Vector2(feet.x, feet.z).distance_to(Vector2(center.x, center.z)) <= radius_m


func talk(npc_id: String) -> String:
	if bool(switches.get(npc_id, false)):
		return "已经谈过了"
	switches[npc_id] = true
	return "你好"


func talked(npc_id: String) -> bool:
	return bool(switches.get(npc_id, false))


func gather(node_id: String) -> String:
	if bool(switches.get(node_id, false)):
		return "这里已经采过"
	switches[node_id] = true
	return "采到了草药"


static func interact_at(travel, feet: Vector3, bodies: Array) -> String:
	var best: Object = null
	var best_d := 2.0
	for body in bodies:
		if body == null:
			continue
		var kind := str(body.get_meta("kind", ""))
		if kind != "npc" and kind != "gather":
			continue
		var center: Vector3 = body.get_meta("center", Vector3.ZERO)
		if not near(feet, center, best_d):
			continue
		var distance := Vector2(feet.x, feet.z).distance_to(Vector2(center.x, center.z))
		if distance < best_d:
			best = body
			best_d = distance
	if best == null:
		return ""
	var picked := str(best.get_meta("kind", ""))
	if picked == "gather":
		return travel.gather(str(best.get_meta("node_id", "")))
	var npc_id := str(best.get_meta("npc_id", ""))
	if travel.talked(npc_id):
		return "已经谈过了"
	travel.talk(npc_id)
	var line := str(best.get_meta("line", ""))
	return line if line != "" else "你好"
