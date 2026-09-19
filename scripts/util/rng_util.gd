extends RefCounted
## RNG helpers (shared; avoid rewriting weighted picks per catalog).


## Pick one Dictionary from `rows` by `weight_key`. Empty if none have weight > 0.
## `roll` if valid must return a float in [0, 1); default is randf().
static func weighted_pick(rows: Array, weight_key: String = "weight", roll: Callable = Callable()) -> Dictionary:
	var total := 0.0
	var valid: Array = []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var w: float = maxf(float(row.get(weight_key, 1.0)), 0.0)
		if w <= 0.0:
			continue
		valid.append(row)
		total += w
	if valid.is_empty() or total <= 0.0:
		return {}
	var u: float = float(roll.call()) if roll.is_valid() else randf()
	var r := u * total
	var acc := 0.0
	for row2 in valid:
		acc += maxf(float((row2 as Dictionary).get(weight_key, 1.0)), 0.0)
		if r <= acc:
			return (row2 as Dictionary).duplicate(true)
	return (valid[valid.size() - 1] as Dictionary).duplicate(true)
