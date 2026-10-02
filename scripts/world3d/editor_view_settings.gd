extends RefCounted
const Schema = preload("res://scripts/world3d/document_schema.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
static func defaults() -> Dictionary:
	return {"isolation":false, "base_height":0.0, "floor_height":3.0, "outside":"hide", "spawn":[0,0,4]}
static func schema() -> Dictionary:
	return {"type":"object", "properties":{"isolation":{"type":"boolean"}, "base_height":Schema.number(-10000,10000), "floor_height":Schema.number(.1,1000), "outside":{"type":"string", "enum":["hide","dim"]}, "spawn":Schema.vector(-100000,100000)}, "additionalProperties":false}
static func valid(meta: Dictionary) -> bool:
	return not meta.has("editor_view") or Schema.validate(meta.editor_view,schema()).is_empty()
static func resolve(meta: Dictionary) -> Dictionary:
	var value := defaults()
	if valid(meta): value.merge(meta.get("editor_view",{}),true)
	return value
static func elevation(record: Dictionary) -> float:
	if record.has("terrain_mesh"): return float(record.position[1])
	if record.has("building"): return float(record.building.floor_y)
	if record.has("tile3d"): return float(record.tile3d.elevation)
	var bounds := Geometry.bounds([record])
	# Thin walkable slabs belong to the floor they support, not the storey below.
	if (record.get("surface_id") == "ground" or record.has("road_mesh")) and bounds.size.y <= .5: return bounds.end.y
	return bounds.position.y
static func contains(record: Dictionary, settings: Dictionary) -> bool:
	if not settings.isolation: return true
	var y := elevation(record)
	return y >= float(settings.base_height) - .001 and y < float(settings.base_height) + float(settings.floor_height) - .001
