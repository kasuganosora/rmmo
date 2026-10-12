extends SceneTree
## Isolated source/candidate profile. Does not publish caches or modify a map.
const OUT="D:/code/rmmo_runtime/art_sources/stone_bridge_optimization_20261009"
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var report:Dictionary={"failures":[]}
var case_name:="original"
var phase:="profile"
var run_id:="1"
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:report.failures.append(label)
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):case_name=arg.trim_prefix("--case=")
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--run="):run_id=arg.trim_prefix("--run=")
	assert(case_name in ["original","candidate"])
	assert(DisplayServer.get_name()!="headless")
	var record:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/"+case_name+"_record.json"))
	var mark:=Time.get_ticks_usec();var prepared:=Frozen.prepare_cpu(record)
	report.prepare_cpu_ms=(Time.get_ticks_usec()-mark)/1000.
	check(not prepared.is_empty(),"CPU packet")
	# Mirror the loader's already-prepared pixel inputs; do not touch runtime texture caches.
	mark=Time.get_ticks_usec();var images:Dictionary={}
	for material:Dictionary in prepared.data.materials:
		for field in Paint.MAP_FIELDS:
			var path:String=material.get("paint",{}).get(field,"")
			if path.is_empty() or images.has(path):continue
			var im:=Image.load_from_file(path)
			check(im!=null,"image "+path)
			if im==null:continue
			if not im.has_mipmaps():im.generate_mipmaps()
			im.set_meta("runtime_source_sha256",FileAccess.get_sha256(path));images[path]=im
	report.isolated_pixel_preparation_ms=(Time.get_ticks_usec()-mark)/1000.
	report.prepared_image_count=images.size()
	Paint.prepare_images(images.duplicate())
	if phase=="texture_profile":
		var details:Array=[]
		for material:Dictionary in prepared.data.materials:
			var definition:Dictionary=material.paint;var row:Dictionary={"name":definition.name,"textures":[]}
			mark=Time.get_ticks_usec();check(Paint.material_valid(definition,false,"",{}),"paint valid")
			row.validation_ms=(Time.get_ticks_usec()-mark)/1000.
			for field in Paint.MAP_FIELDS:
				if str(definition.get(field,"")).is_empty():continue
				var started:=Time.get_ticks_usec();var tex:=Paint.texture(definition,field)
				row.textures.append({"field":field,"ms":(Time.get_ticks_usec()-started)/1000.,"loaded":tex!=null})
			mark=Time.get_ticks_usec();var mat:=Paint.make_material(definition,material.cull)
			row.make_with_warm_textures_ms=(Time.get_ticks_usec()-mark)/1000.
			check(mat!=null,"material")
			details.append(row)
		report.texture_profile=details
		var detail_file:=FileAccess.open(OUT+"/texture_profile_"+case_name+"_"+run_id+".json",FileAccess.WRITE);detail_file.store_string(JSON.stringify(report,"  "));detail_file.close()
		print("BRIDGE_TEXTURE_PROFILE ",JSON.stringify(report));quit();return
	mark=Time.get_ticks_usec();check(Frozen.publish_prepared(record,prepared,{},{}),"cold prepared publish")
	report.publish_prepared_cold_materials_ms=(Time.get_ticks_usec()-mark)/1000.
	for frame in 3:await process_frame
	# Keep the material/texture cache but discard only the prefab geometry identities.
	Frozen._meshes.clear();Frozen._render_meshes.clear()
	mark=Time.get_ticks_usec();check(Frozen.publish_prepared(record,prepared,{},{}),"warm material publish")
	report.publish_prepared_warm_materials_ms=(Time.get_ticks_usec()-mark)/1000.
	# Break down an independent cold-material restore without editing shared implementation.
	Frozen._meshes.clear();Frozen._render_meshes.clear();Paint._materials.clear();Paint._textures.clear()
	for frame in 3:await process_frame
	Paint.prepare_images(images.duplicate())
	var timings:Dictionary={};mark=Time.get_ticks_usec()
	var restored:=Cook.restore(prepared.data.duplicate(),{}, {},timings)
	report.segmented_restore_ms=(Time.get_ticks_usec()-mark)/1000.
	report.restore=timings
	check(not restored.is_empty(),"segmented restore")
	var entry:Dictionary=restored.values()[0]
	mark=Time.get_ticks_usec()
	entry.mesh._collision_faces=prepared.collision_faces[prepared.data.entries[0][1][0]]
	entry.source._collision_faces=prepared.collision_faces[prepared.data.entries[0][1][1]]
	Frozen._cache_geometry(record.house_prefab.sha256,entry,prepared.geometry_keys,prepared.data)
	report.geometry_identity_ms=(Time.get_ticks_usec()-mark)/1000.
	mark=Time.get_ticks_usec();var shape:=ConcavePolygonShape3D.new();shape.set_faces(entry.source.collision_faces())
	report.physics_shape_ms=(Time.get_ticks_usec()-mark)/1000.
	report.collision_faces_sha256=Cook.Envelope.checksum(entry.source.collision_faces().to_byte_array()).hex_encode()
	if phase=="visual":await render_views(record,entry.mesh)
	report.case_name=case_name;report.phase=phase;report.run=run_id
	var f:=FileAccess.open(OUT+"/"+phase+"_"+case_name+"_"+run_id+".json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("BRIDGE_REVIEW ",JSON.stringify(report));quit(0 if report.failures.is_empty() else 1)
func render_views(record:Dictionary,cpu:Mesh)->void:
	root.size=Vector2i(1500,900)
	var view:=SubViewport.new();view.size=root.size;view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var mesh:=MeshInstance3D.new();mesh.mesh=cpu.restore();mesh.position=Frozen.vec(record.position);mesh.rotation_degrees=Frozen.vec(record.rotation);view.add_child(mesh)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.24,.30,.34);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.6;view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-25,0);sun.light_energy=1.5;sun.shadow_enabled=true;view.add_child(sun)
	var camera:=Camera3D.new();camera.far=250;camera.fov=55;view.add_child(camera);camera.current=true
	var poses:=[{"name":"wide","eye":Vector3(38,18,45),"target":Vector3(0,0,0)},{"name":"deck_rim","eye":Vector3(18,5,11),"target":Vector3(14,1.4,3.5)},{"name":"arch","eye":Vector3(0,-1,17),"target":Vector3(0,-1.5,0)}]
	for pose:Dictionary in poses:
		camera.global_position=mesh.global_transform*pose.eye;camera.look_at(mesh.global_transform*pose.target)
		for frame in 8:await process_frame;await RenderingServer.frame_post_draw
		check(view.get_texture().get_image().save_png(OUT+"/"+case_name+"_"+pose.name+".png")==OK,"image "+pose.name)
	view.queue_free();await process_frame
