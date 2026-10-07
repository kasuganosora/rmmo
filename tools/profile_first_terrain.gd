extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Regions=preload("res://scripts/world3d/terrain_regions.gd")
const SOURCE="D:/code/rmmo_runtime/cache/world3d/bridge_perf_20261006/map.gltf"
func _initialize()->void:call_deferred("run")
func run()->void:
	var parsed:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SOURCE));var records:Array=[]
	for node in parsed.nodes:
		if node.get("extras",{}).has("rmmo_records"):records=node.extras.rmmo_records;break
	var record:Dictionary=records[0]
	var doc:=Doc.new();doc.records=records
	doc.terrain_neighbors.update(records,true)
	var context:Dictionary=doc.terrain_neighbors.data.get(record.uuid,{})
	doc.load_surface_arrays={record.uuid:Terrain.arrays(record,context)}
	if record.has("terrain_regions"):context.region_mask=Regions.mask(record)
	doc.load_paint_validation={};doc.load_texture_checks={};doc.load_box_meshes={};doc.load_model_signatures={};doc.load_material_pool={}
	await process_frame
	var texture_probe:Array=[]
	var prepared_metrics:Dictionary={};var prepared_scope:Dictionary={}
	if OS.get_cmdline_user_args().has("--prepared-textures"):
		var helper=preload("res://scripts/world_editor/terrain_texture_preparation.gd")
		var requested:Dictionary=helper.requests(record,{})
		var worker:=Thread.new();var started:=Time.get_ticks_usec();var frames:=0
		worker.start(helper.decode.bind(requested,preload("res://scripts/world3d/map_paths.gd").external_root()))
		while worker.is_alive():await process_frame;frames+=1
		var payload:Dictionary=worker.wait_to_finish()
		prepared_metrics={"worker_ms":payload.elapsed_us/1000.,"wait_ms":(Time.get_ticks_usec()-started)/1000.,"frames":frames,"textures":payload.images.size()}
		prepared_scope=helper.install(payload)
	if OS.get_cmdline_user_args().has("--textures"):
		var paint=preload("res://scripts/world3d/surface_materials.gd");var seen:Dictionary={}
		for definition in paint.definitions(record):
			for field in paint.MAP_FIELDS:
				var path:=str(definition.get(field,""))
				if path.is_empty():continue
				var flip:bool=field=="normal_path" and definition.get("normal_format","opengl")=="directx"
				var key:=path+("|flip_y" if flip else "")
				if seen.has(key):continue
				seen[key]=true
				var began:=Time.get_ticks_usec();var image:Image=preload("res://scripts/world3d/runtime_texture_cache.gd").image(path,flip)
				var row:={"path":path,"flip":flip,"decode_ms":(Time.get_ticks_usec()-began)/1000.}
				if image!=null:
					paint.prepare_images({key:image});began=Time.get_ticks_usec()
					paint.texture(definition,field)
					row.upload_ms=(Time.get_ticks_usec()-began)/1000.
				texture_probe.append(row)
	var timings:Dictionary={};var mark:=Time.get_ticks_usec()
	var visual:MeshInstance3D=doc._mesh(record,true,timings)
	timings.total_ms=(Time.get_ticks_usec()-mark)/1000.
	if OS.get_cmdline_user_args().has("--prepared-textures"):preload("res://scripts/world_editor/terrain_texture_preparation.gd").restore(prepared_scope)
	var result:={"uuid":record.uuid,"timings":timings,"preparation":prepared_metrics,"textures":texture_probe,"surfaces":visual.mesh.get_surface_count(),"terrain_material":record.get("terrain_material",{}),"source":SOURCE}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("FIRST_TERRAIN_PROFILE ",JSON.stringify(result))
	visual.free();quit(0)
