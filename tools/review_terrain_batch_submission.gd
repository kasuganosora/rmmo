extends "res://tools/test_terrain_batch_submission.gd"
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/terrain_submission86_gpu"
func sha(value:Variant)->String:
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(var_to_bytes(value));return hash_.finish().hex_encode()
func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Private desktop GPU required");quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT)
	var source_sha:=FileAccess.get_sha256(MAP)
	var parsed:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MAP));var compact_records:Array=[]
	for node:Dictionary in parsed.nodes:
		for r:Dictionary in node.get("extras",{}).get("rmmo_records",[]):
			if str(r.get("uuid","")).begins_with("axel_terrain_"):compact_records.append(r)
	var decoded:Dictionary=preload("res://scripts/world3d/map_resource_store.gd").read_records(compact_records,MAP,"D:/code/rmmo_runtime",null,4,true)
	check(decoded.ok and not decoded.records.is_empty(),"actual map terrain references read without source mutation")
	var rows:Array=[];var sample:Array=[]
	for record:Dictionary in decoded.records:
		if not record.has("terrain_mesh"):continue
		var surfaces:Array=Terrain.arrays(record);var before:=sha(surfaces)
		if record.terrain_mesh.holes.has(true) or record.has("surface_paint"):
			rows.append({"uuid":record.uuid,"status":"unaffected: holes/paint","source_sha":before});continue
		var old:=legacy(surfaces[1],record);var new:=compact(surfaces[1])
		var exact:=var_to_bytes(old)==var_to_bytes(new) and sha(surfaces)==before
		check(exact,"exact source/derived terrain "+str(record.uuid))
		rows.append({"uuid":record.uuid,"exact":exact,"source_sha":before,"old_sha":sha(old),"new_sha":sha(new),"vertices":new[Mesh.ARRAY_VERTEX].size(),"indices":new[Mesh.ARRAY_INDEX].size()})
		if sample.is_empty():sample=[surfaces[0],old,new]
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,720);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var scene:=Node3D.new();viewport.add_child(scene)
	var env:=WorldEnvironment.new();var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.12,.14,.17);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color.WHITE;environment.ambient_light_energy=.55;env.environment=environment;scene.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-35,0);light.light_energy=1.4;light.shadow_enabled=true;scene.add_child(light)
	var camera:=Camera3D.new();camera.fov=55;camera.far=3000;scene.add_child(camera);camera.current=true
	var visual:=MeshInstance3D.new();scene.add_child(visual)
	var meshes:Array=[];var material:=StandardMaterial3D.new();material.albedo_color=Color(.8,.8,.8)
	for mode:int in 2:
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,sample[0]);mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,sample[mode+1])
		for slot:int in 2:mesh.surface_set_material(slot,material)
		var path:=OUT.path_join("terrain_%d.res"%mode)
		check(ResourceSaver.save(mesh,path)==OK,"save derived mesh %d"%mode)
		meshes.append(ResourceLoader.load(path,"ArrayMesh",ResourceLoader.CACHE_MODE_IGNORE))
	var bounds:AABB=meshes[0].get_aabb();var center:=bounds.get_center();var extent:=maxf(bounds.size.x,bounds.size.z)
	var views:=[Vector3(.55,.45,.65),Vector3(1.,.8,1.),Vector3(2.,1.6,2.),Vector3(.55,-.6,.55)]
	var images:Array=[]
	for index:int in views.size():
		camera.position=center+views[index]*extent;camera.look_at(center)
		var before:PackedByteArray
		for mode:int in 2:
			visual.mesh=meshes[mode]
			for frame:int in 4:await process_frame
			await RenderingServer.frame_post_draw
			var image:=viewport.get_texture().get_image();var data:=image.get_data()
			image.save_png(OUT.path_join("view_%d_%d.png"%[index,mode]))
			if mode==0:before=data
			else:
				check(data==before,"saved/reopened old/new pixels exact view %d"%index)
				images.append({"view":index,"camera":camera.transform,"exact":data==before})
	check(FileAccess.get_sha256(MAP)==source_sha,"formal map unchanged")
	var file:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"map":MAP,"map_sha":source_sha,"pipeline_sha":FileAccess.get_sha256("res://scripts/world3d/ground_batch_geometry.gd"),"terrains":rows,"views":images,"textures":"not applicable: white geometry stage","failures":failures},"  "));file.close()
	viewport.free();print("TERRAIN_BATCH_GPU failures=",failures);quit(1 if failures else 0)
