extends "res://tools/profile_white_native_asset.gd"
## Isolate native CPU/material binding from file loading and map scheduling.
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
func _bind_meshes(meshes:Array,helper:bool)->Dictionary:
	var began:=Time.get_ticks_usec()
	for mesh:ArrayMesh in meshes:
		if helper:Native._bind_geometry(mesh)
		else:
			var data:Dictionary=mesh.get_meta(Native.META)
			for slot:int in mesh.get_surface_count():mesh.surface_set_material(slot,Controls.white_material(data.culls[slot]))
			var cpu:Mesh=Cpu.remember(mesh,data.surfaces,data.lods);cpu._collision_faces=data.faces
			mesh.remove_meta(Native.META)
	return {"helper":helper,"meshes":meshes.size(),"bind_us":Time.get_ticks_usec()-began}

func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty():quit(2);return
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	var warm_us:=0
	if "--warm-materials" in OS.get_cmdline_user_args():
		var began:=Time.get_ticks_usec()
		for cull:int in 3:Controls.white_material(cull).get_rid()
		Drainer.synchronize_transfer();warm_us=Time.get_ticks_usec()-began
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Native.index_path(SOURCE,"D:/code/rmmo_runtime")))
	var path:=Native.directory("D:/code/rmmo_runtime").path_join(manifest.payload_sha+".scn")
	var rows:Array=[]
	for helper:bool in [false,true,true,false,false,true]:
		var packed:PackedScene=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var state:=packed.get_state();var seen:Dictionary={};var meshes:Array=[]
		for i:int in state.get_node_count():
			for j:int in state.get_node_property_count(i):
				if state.get_node_property_name(i,j)!=&"mesh":continue
				var mesh:Variant=state.get_node_property_value(i,j)
				if mesh is ArrayMesh and not seen.has(mesh.get_instance_id()):
					seen[mesh.get_instance_id()]=true;meshes.append(mesh)
		Drainer.synchronize_transfer()
		var worker:=Thread.new();check(worker.start(_bind_meshes.bind(meshes,helper))==OK,"isolated binding worker starts")
		while worker.is_alive():await process_frame
		var row:Dictionary=worker.wait_to_finish();rows.append(row);print("WHITE_BIND ",row)
		Drainer.synchronize_transfer();meshes.clear();state=null;packed=null
		await process_frame
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"runs":rows,"material_warm_us":warm_us,"failures":failures},"\t"))
	quit(1 if failures else 0)
