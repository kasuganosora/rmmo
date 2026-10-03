extends SceneTree
func _initialize() -> void:
	var doc=preload("res://scripts/world3d/world_document.gd").open_file("D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf")
	var tool=preload("res://scripts/world_editor/terrain_furrow_tools.gd")
	var library=preload("res://scripts/world_editor/surface_material_library.gd").new()
	for args in preload("res://tools/medieval_town_cultivation.gd").field_regions(doc):
		var update: Dictionary=preload("res://scripts/world_editor/terrain_region_tools.gd").prepare(doc.records,args,library,func(_r):return true)
		if not update.ok: print("TRIM_FAIL ",args.id," ",update); quit(1); return
		for r in update.records:
			for i in doc.records.size():
				if doc.records[i].uuid==r.uuid: doc.records[i]=r; break
	for args in preload("res://tools/medieval_town_cultivation.gd").requests(doc.records):
		var start:=Time.get_ticks_msec(); var result: Dictionary=tool.prepare(doc.records,args,func(_r):return true)
		print(args.id," ",result.get("ok")," ",result.get("error",str(result.get("triangles",0)))," ms=",Time.get_ticks_msec()-start)
		if result.ok:
			for next in result.records:
				for i in doc.records.size():
					if doc.records[i].uuid==next.uuid: doc.records[i]=next; break
	quit()
