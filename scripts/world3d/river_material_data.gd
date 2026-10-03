extends RefCounted
## Persisted river appearance. Heights/depths are world-space metres.
const S=preload("res://scripts/world3d/document_schema.gd")
const TRANSITION_DEFAULTS={"transition_width":1.25,"edge_noise":.3,"height_blend_strength":.5}
const TRANSITION_MATERIAL="pack:default:terrain/natural_dirt/material"
static func transition_parameters() -> Dictionary:
	return {"transition_width":S.number(0,8),"edge_noise":S.number(0,1),"height_blend_strength":S.number(0,1)}
const DEFAULTS={"water_level":-1.5,"shore_start":.25,"shore_end":1.3,"rock_start":.6,"rock_end":2.2,"bank_profile":"natural","steep_start":40.0,"steep_end":65.0,"wet_height":.3,"absorption":.45,"shallow_color":[.24,.42,.34],"deep_color":[.055,.16,.14]}

static func parameters() -> Dictionary:
	return {"water_level":S.number(-1000,1000),"shore_start":S.number(0,20),"shore_end":S.number(.01,40),"rock_start":S.number(0,50),"rock_end":S.number(.01,100),"bank_profile":{"type":"string","enum":["depth","natural"]},"steep_start":S.number(1,89),"steep_end":S.number(1,89.9),"wet_height":S.number(.01,3),"absorption":S.number(.01,5),"shallow_color":S.vector(0,1),"deep_color":S.vector(0,1)}
static func request_schema() -> Dictionary:
	var ids:={"type":"array","items":{"type":"string","maxLength":128},"minItems":0,"maxItems":256,"uniqueItems":true}
	var props:=parameters()
	props.merge(transition_parameters())
	props.merge({"terrain_ids":ids,"water_ids":ids,"bank_ids":ids,"enabled":{"type":"boolean"},"sand_material_id":{"type":"string","maxLength":512},"rock_material_id":{"type":"string","maxLength":512}})
	props.transition_material_id={"type":"string","maxLength":512}
	return {"type":"object","properties":props,"additionalProperties":false}
static func ordered(value: Dictionary) -> bool:
	return value.shore_end>value.shore_start+.001 and value.rock_end>value.rock_start+.001 and value.get("steep_end",65.0)>value.get("steep_start",40.0)+.001
static func slope_schema() -> Dictionary:
	var props:={"terrain_ids":request_schema().properties.terrain_ids,"enabled":{"type":"boolean"},"rock_material_id":{"type":"string","maxLength":512},"steep_start":parameters().steep_start,"steep_end":parameters().steep_end,"transition_material_id":{"type":"string","maxLength":512}}
	props.terrain_ids.minItems=1; props.merge(transition_parameters())
	return {"type":"object","properties":props,"required":["terrain_ids"],"additionalProperties":false}
static func bank_target(record: Dictionary) -> bool:
	if record.get("kind")!="box" or record.get("surface_id")=="water" or record.get("invisible",false): return false
	for key in ["terrain_mesh","tile3d","building","building_shape","fixture","road_mesh","fortification"]:
		if record.has(key): return false
	return true
static func valid(record: Dictionary) -> bool:
	if record.has("terrain_slope_blend"):
		if not record.has("terrain_mesh") or record.has("surface_paint") or record.has("terrain_depth_blend"): return false
		var props:={"steep_start":parameters().steep_start,"steep_end":parameters().steep_end,"rock_material":{}}
		var required: Array=props.keys(); props.merge(transition_parameters()); props.transition_material={}
		var config: Variant=record.terrain_slope_blend
		if not S.validate(config,{"type":"object","properties":props,"required":required,"additionalProperties":false}).is_empty(): return false
		if config.steep_end<=config.steep_start+.001: return false
	if record.has("terrain_depth_blend"):
		if not record.has("terrain_mesh") or record.has("surface_paint"): return false
		var props:=parameters()
		for key in ["absorption","shallow_color","deep_color","wet_height"]: props.erase(key)
		props.merge({"sand_material":{},"rock_material":{}})
		var required: Array=props.keys()
		for key in ["bank_profile","steep_start","steep_end"]: required.erase(key) # Existing maps retain depth-only rendering.
		props.merge(transition_parameters()); props.transition_material={}
		var schema:={"type":"object","properties":props,"required":required}
		if not S.validate(record.terrain_depth_blend,schema).is_empty() or not ordered(record.terrain_depth_blend): return false
	for field in ["terrain_depth_blend","terrain_slope_blend"]:
		if record.get(field,{}).get("transition_width",0)>0 and not record[field].has("transition_material"): return false
	if record.has("bank_wetness"):
		if not bank_target(record): return false
		var props:={"water_level":parameters().water_level,"wet_height":parameters().wet_height}
		if not S.validate(record.bank_wetness,{"type":"object","properties":props,"required":props.keys()}).is_empty(): return false
	if record.has("water_depth_effect"):
		if not record.has("channel_mesh") or record.get("surface_id")!="water": return false
		var props:={"absorption":parameters().absorption,"shallow_color":S.vector(0,1),"deep_color":S.vector(0,1)}
		if not S.validate(record.water_depth_effect,{"type":"object","properties":props,"required":props.keys()}).is_empty(): return false
	return true
