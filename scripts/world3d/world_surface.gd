extends RefCounted
## Which deck the feet are on. Overlapping XZ does not make the upper deck the lower one.

const STEP_UP_M := 0.4

const LINKS := {
	"ground": ["ramp"],
	"ramp": ["ground", "bridge_deck"],
	"bridge_deck": ["ramp"],
}


static func pick_surface(feet_y: float, candidates: Array) -> String:
	var best := ""
	var best_gap := 1000.0
	for item in candidates:
		var walk_y := float(item.get("y", 0.0))
		if walk_y > feet_y + STEP_UP_M:
			continue
		var gap := absf(feet_y - walk_y)
		if gap < best_gap:
			best = str(item.get("id", ""))
			best_gap = gap
	return best


static func allows(current_id: String, target_id: String) -> bool:
	if current_id == target_id:
		return true
	var linked: Variant = LINKS.get(current_id, [])
	return linked is Array and (linked as Array).has(target_id)
