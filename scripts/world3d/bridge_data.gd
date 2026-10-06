extends RefCounted
## Dimensioned, editable bridge recipes. Geometry/material payloads live in the map.
const S=preload("res://scripts/world3d/document_schema.gd")
const STYLES=["segmental","pointed","rustic"]
static func obj(p: Dictionary,r: Array=[]) -> Dictionary: return {"type":"object","properties":p,"required":r,"additionalProperties":false}
static func text(n:=120) -> Dictionary: return {"type":"string","maxLength":n}
static func recipe_schema() -> Dictionary:
	return obj({"style":{"type":"string","enum":STYLES},"max_span":S.number(3,16),"rail_height":S.number(.9,1.5),"pier_width":S.number(.6,2.5)},["style","max_span","rail_height","pier_width"])
static func presets() -> Array:
	return [
		{"id":"stone_segmental","name":"中世纪 · 多孔浅拱石桥","description":"低拱、规整拱圈、尖形分水墩，适合城镇主路。","recipe":{"style":"segmental","max_span":10.0,"rail_height":1.05,"pier_width":1.3}},
		{"id":"stone_pointed","name":"中世纪 · 尖拱石桥","description":"微尖拱顶、厚桥墩、石压顶，适合较深河槽。","recipe":{"style":"pointed","max_span":8.0,"rail_height":1.1,"pier_width":1.1}},
		{"id":"stone_rustic","name":"中世纪 · 乡间石拱桥","description":"较窄拱孔、粗砌桥身、较低石栏，适合乡道。","recipe":{"style":"rustic","max_span":6.0,"rail_height":.95,"pier_width":.9}}]
static func preset(id: String) -> Dictionary:
	for entry in presets():
		if entry.id==id: return entry.duplicate(true)
	return {}
static func schema() -> Dictionary:
	return obj({"version":S.number(1,1,true),"prefab_id":text(256),"length":S.number(6,120),"width":S.number(3,16),"depth":S.number(1.5,15),"camber":S.number(0,5),"arches":S.number(1,20,true),"recipe":recipe_schema()},["version","prefab_id","length","width","depth","camber","arches","recipe"])
static func request_schema() -> Dictionary:
	return obj({"id":text(100),"name":text(),"prefab_id":text(256),"start":S.vector(-10000,10000),"end":S.vector(-10000,10000),"width":S.number(3,16),"depth":S.number(1.5,15),"camber":S.number(0,5),"auto_clearance":{"type":"boolean"},"arches":S.number(0,20,true),"deck_material_id":text(256),"masonry_material_id":text(256),"trim_material_id":text(256),"plan_token":text(64),"road_edge_id":text(80)},["id","start","end"])
static func valid(record: Dictionary) -> bool:
	if not record.has("bridge_mesh"): return not record.has("bridge_materials")
	var d: Variant=record.bridge_mesh
	if not S.validate(d,schema()).is_empty() or record.get("kind")!="asset": return false
	for key in ["terrain_mesh","road_mesh","channel_mesh","tile3d","building_shape","building","fixture"]:
		if record.has(key): return false
	if not S.validate(record.get("size"),S.vector(.001,100000)).is_empty(): return false
	var opening: float=(d.length-2.0-(d.arches-1)*d.recipe.pier_width)/d.arches
	return opening>=2.0 and opening<=d.recipe.max_span+.001 and d.camber*PI/d.length<=.150001
static func dimensions(d: Dictionary) -> Vector3:
	return Vector3(d.length,d.depth+d.camber+1.7,d.width*1.31+.1)
static func default_materials() -> Dictionary:
	return {"deck":"pack:default:paving/outdoor_flagstone/material","masonry":"pack:default:walls/castle_rubble/material","trim":"pack:default:walls/stone_tiles_facade/material"}
static func deck_local_y(d: Dictionary) -> float:
	return 0.0
