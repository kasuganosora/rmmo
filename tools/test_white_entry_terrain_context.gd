extends "res://tools/test_selected_terrain_context.gd"
const ContextCache=preload("res://scripts/world3d/terrain_context_cache.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
func run()->void:
	var loader:=Loader.new()
	var source:=records();var bytes:=var_to_bytes(source)
	source[4].terrain_regions={"materials":[{}],"regions":[]}
	Controls.white_materials=false
	var reference:=Neighbors.new();reference.update(source)
	var context:=Neighbors.new();Controls.enable_white_materials()
	var began:=Time.get_ticks_usec()
	if "--expect-images" in OS.get_cmdline_user_args():context.update(source,true)
	else:context.call("update",source,true,true)
	var elapsed:=Time.get_ticks_usec()-began;var images:=0;var exact:=true
	for id:String in reference.data:
		images+=int(context.data[id].has("image"))
		exact=exact and context.data[id].normals==reference.data[id].normals and context.data[id].neighbors==reference.data[id].neighbors
	check(exact,"all entry tiles retain exact seams and neighbor ordering")
	for record:Dictionary in source:check(var_to_bytes(Terrain.arrays(record,context.data[record.uuid]))==var_to_bytes(Terrain.arrays(record,reference.data[record.uuid])),"entry geometry remains byte-identical "+record.uuid)
	if "--expect-images" not in OS.get_cmdline_user_args():
		check(images==0 and loader.call("_terrain_region_records",source).is_empty(),"white entry builds no height images or region mask jobs")
		var packed:=ContextCache.pack(context)
		var restored:RefCounted=ContextCache.restore(packed,source)
		check(restored!=null and restored.data.size()==source.size(),"geometry-only context survives cache save/reopen")
		if restored!=null:
			for id:String in restored.data:check(not restored.data[id].has("image") and not restored.data[id].has("region_mask") and restored.data[id].normals==reference.data[id].normals,"white cached context retains only geometry "+id)
		Controls.white_materials=false
		check(ContextCache.restore(packed,source)==null,"ordinary material mode regenerates images rather than accepting missing data")
		check(loader.call("_terrain_region_records",source)==[source[4]],"ordinary mode schedules exactly the authored region masks")
		context.update(source,false,false)
		check(context.data.tile11.has("image"),"switching an unchanged live context restores required images")
		context.update(source,false,true)
		check(not context.data.tile11.has("image"),"switching back drops unused images with unchanged heights")
	Controls.white_materials=false;source[4].erase("terrain_regions")
	check(var_to_bytes(source)==bytes,"source heights, holes and transforms remain unchanged")
	loader.free()
	print("WHITE_ENTRY_TERRAIN_CONTEXT ",JSON.stringify({"us":elapsed,"images":images,"failures":failures}));quit(1 if failures else 0)
