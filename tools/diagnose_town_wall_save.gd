extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Walls=preload("res://tools/medieval_town_walls.gd")
func _initialize() -> void:
	var doc=Doc.open_file("D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf")
	print("ROADS ",Walls.correct_approaches(doc).ok)
	var args:=Walls.requests(doc); Walls.water_zones(doc,args); var grade:=Walls.grade_foundations(doc,args)
	print("META ",doc.validate_save_meta())
	for r in doc.records:
		var code: Error=doc.validate_save_record(r)
		if code!=OK: print("BAD_RECORD ",r.uuid," ",code," ",JSON.stringify(r)); quit(1); return
	print("RECORDS_VALID")
	var settings:=preload("res://scripts/world3d/fortification_data.gd").defaults().merged(args,true).merged({"style":"medieval_stone","layout_version":1},true)
	var plan:=preload("res://scripts/world3d/fortification_plan.gd").new().build(settings)
	print("PLAN ",plan.ok)
	for r in plan.get("records",[]):
		if doc.validate_save_record(r)!=OK:
			print("BAD_WALL_RECORD ",JSON.stringify(r)); quit(1); return
	print("WALL_RECORDS_VALID")
	for r in doc.records:
		if r.uuid not in grade.terrain_ids and not r.has("road_mesh"): continue
		var node: Node3D=doc._mesh(r,false)
		if node.has_meta("paint_error") or node.has_meta("tile_error"):
			print("BAD_MESH ",r.uuid," ",node.get_meta_list()," ",node.get_meta("paint_error","")); node.free(); quit(1); return
		node.free()
	print("STAGED_VALID"); quit()
