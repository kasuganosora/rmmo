extends RefCounted
## The town recipe uses the same validation and records as UI/HTTP authoring.
const Tools=preload("res://scripts/world_editor/river_material_tools.gd")
const Settings=preload("res://scripts/world3d/editor_view_settings.gd")
const GROUND_MATERIAL="pack:default:terrain/mossy_grass_vcjmej0s/material"
static func parameters(doc) -> Dictionary:
	var terrain_ids: Array=[]; var water_ids: Array=[]
	for record in doc.records:
		if record.has("terrain_mesh") and float(record.terrain_mesh.heights.min())*record.size[1]+record.position[1]<-.2: terrain_ids.append(record.uuid)
		if record.has("channel_mesh") and record.get("surface_id")=="water": water_ids.append(record.uuid)
	return {"terrain_ids":terrain_ids,"water_ids":water_ids,"water_level":-1.5,"shore_start":0.,"shore_end":.35,"wet_height":.6,"wet_darkening":.65,"rock_start":.6,"rock_end":2.2,"absorption":.9,"shallow_color":[.13,.27,.31],"deep_color":[.055,.14,.205],"bank_profile":"natural","transition_width":2.5,"edge_noise":.55,"height_blend_strength":.35,"transition_material_id":"pack:default:terrain/natural_dirt/material","sand_material_id":"pack:default:terrain/natural_sand/material","rock_material_id":"pack:default:terrain/icelandic_jagged_slate/material"}
static func apply(doc, include_ground: bool=false) -> Dictionary:
	var args:=parameters(doc)
	var view:=Settings.resolve(doc.map_meta)
	var library=preload("res://scripts/world_editor/surface_material_library.gd").new()
	var ground: Dictionary=library.find(GROUND_MATERIAL)
	if include_ground and (ground.is_empty() or not preload("res://scripts/world3d/surface_materials.gd").missing([{"terrain_material":ground}]).is_empty()): return {"ok":false,"error":"Missing town grass PBR"}
	var prepared:=Tools.prepare(doc.records,args,library,func(r):return not r.get("editor_hidden",false) and not r.get("editor_locked",false) and Settings.contains(r,view))
	if not prepared.ok: return prepared
	for r in prepared.records: doc.records[doc.records.find(doc._find(r.uuid))]=r
	if include_ground:
		for r in doc.records:
			if r.has("terrain_mesh"): r.terrain_material=ground.duplicate(true); r.terrain_saturation=1.
	return {"ok":true,"terrain_count":args.terrain_ids.size(),"water_count":args.water_ids.size(),"parameters":args}
