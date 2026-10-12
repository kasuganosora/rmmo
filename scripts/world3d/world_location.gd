extends RefCounted
## Meter-space pose for one map. y is height. This is not a 2D cell.

const FORMAT := "rmmo_gltf_map"
const FORMAT_VERSION := 2
const STORAGE := "references_v1"
const POSITION_ROUNDTRIP_M := 0.001

var map_ref: String = ""
var position_m := Vector3.ZERO
var surface_id: String = ""


static func make(p_map_ref: String, p_position_m: Vector3, p_surface_id: String):
	var loc = load("res://scripts/world3d/world_location.gd").new()
	loc.map_ref = p_map_ref.strip_edges()
	loc.position_m = p_position_m
	loc.surface_id = p_surface_id.strip_edges()
	return loc


func valid() -> bool:
	return map_ref_ok(map_ref) and finite_vector(position_m) and id_ok(surface_id)


func matches(other, tolerance_m: float) -> bool:
	if other == null or not valid() or not other.valid():
		return false
	if map_ref != other.map_ref or surface_id != other.surface_id:
		return false
	return position_m.distance_to(other.position_m) <= tolerance_m


func to_dictionary() -> Dictionary:
	return {
		"map_ref": map_ref,
		"position_m": [position_m.x, position_m.y, position_m.z],
		"surface_id": surface_id,
	}


static func from_dictionary(data: Dictionary):
	var loc = load("res://scripts/world3d/world_location.gd").new()
	loc.map_ref = str(data.get("map_ref", "")).strip_edges()
	loc.surface_id = str(data.get("surface_id", "")).strip_edges()
	var raw: Variant = data.get("position_m", [])
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
		loc.position_m = Vector3(NAN, NAN, NAN)
		return loc
	var coords: Array = raw
	loc.position_m = Vector3(float(coords[0]), float(coords[1]), float(coords[2]))
	return loc


## Identity, not a filesystem path. One slash separates pack id and map id.
static func map_ref_ok(value: String) -> bool:
	var parts := value.split("/", false)
	return parts.size() == 2 and id_ok(parts[0]) and id_ok(parts[1])


static func id_ok(value: String) -> bool:
	if value.is_empty():
		return false
	for i in value.length():
		var c := value.unicode_at(i)
		var digit := c >= 48 and c <= 57
		var upper := c >= 65 and c <= 90
		var lower := c >= 97 and c <= 122
		if not digit and not upper and not lower and c != 95:
			return false
	return true


static func finite_vector(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


## Index only. Negative positions use floor, so -0.01 with origin 0 and size 32 is chunk -1.
static func chunk_index(position_m: float, origin_m: float, chunk_size_m: float) -> int:
	if not is_finite(position_m) or not is_finite(origin_m) or not is_finite(chunk_size_m) or chunk_size_m <= 0.0:
		return 0
	return int(floor((position_m - origin_m) / chunk_size_m))
