extends RefCounted
## Rain/snow gather & fish yield helpers (pure; MockServer applies).


const GATHER_BONUS_CHANCE := 0.30
const FISH_SHINY_WEIGHT_BONUS := 0.1
const BONUS_MESSAGE := "雨天收获更好！"


## Rain or snow (not storm/fog/clear).
static func is_bonus_weather(kind: String) -> bool:
	var k := str(kind).strip_edges().to_lower()
	match k:
		"rain", "raining", "雨", "snow", "snowing", "雪":
			return true
		_:
			return false


## Herb gather nodes (id herb_* or kind herb); ores/tools excluded.
static func is_herb_node(node_id: String, def: Dictionary = {}) -> bool:
	var nid := str(node_id).strip_edges().to_lower()
	if nid.begins_with("herb"):
		return true
	var kind := str(def.get("kind", "")).strip_edges().to_lower()
	if kind == "herb":
		return true
	return false


## True when roll in [0, 1) should grant +1 gather qty.
static func roll_gather_qty_bonus(roll: float) -> bool:
	return float(roll) < GATHER_BONUS_CHANCE


static func apply_gather_qty_bonus(qty: int, proc: bool) -> int:
	var q := maxi(int(qty), 1)
	if proc:
		return q + 1
	return q


static func fish_shiny_bonus_for_weather(kind: String) -> float:
	if is_bonus_weather(kind):
		return FISH_SHINY_WEIGHT_BONUS
	return 0.0


## Effective fish_shiny weight after bait + weather.
static func shiny_weight(base_w: float, weather_kind: String, bait_bonus: float = 0.0) -> float:
	return maxf(float(base_w), 0.0) + maxf(float(bait_bonus), 0.0) + fish_shiny_bonus_for_weather(weather_kind)
