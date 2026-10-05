extends SceneTree
func _initialize() -> void:
	var doc=preload("res://scripts/world3d/world_document.gd").open_file("D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf")
	print("ROAD_FIX ",JSON.stringify(preload("res://tools/medieval_town_walls.gd").correct_approaches(doc)))
	var args:=preload("res://tools/medieval_town_walls.gd").requests(doc)
	preload("res://tools/medieval_town_walls.gd").water_zones(doc,args)
	for zone in doc.map_meta.editor_layout.zones:
		if not preload("res://scripts/world3d/planning_zones.gd").valid([zone]): print("BAD_ZONE ",JSON.stringify(zone), " ",preload("res://scripts/world3d/document_schema.gd").validate(zone,preload("res://scripts/world3d/planning_zones.gd").schema()))
	var terrain: Array=doc.records.filter(func(r):return r.has("terrain_mesh"))
	for i in args.points.size():
		var p:=Vector3(args.points[i][0],0,args.points[i][1]); var h:=preload("res://scripts/world_editor/bridge_tools.gd").ground_height(terrain,p)
		if absf(h)>.001: print("GROUND ",i," ",h)
	var file:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/wall_trace/requests.json",FileAccess.WRITE); file.store_string(JSON.stringify(args,"\t")); file.close()
	print("REQUESTS ",JSON.stringify(args))
	var plan:=preload("res://scripts/world3d/fortification_plan.gd").new().build(args.merged({"style":"medieval_stone","layout_version":1}))
	if not plan.ok: print("PLAN_ERROR ",JSON.stringify(plan)); quit(1); return
	print("PLAN_OK records=",plan.records.size()," towers=",plan.access_routes.size()," length=",plan.length)
	quit(0)
