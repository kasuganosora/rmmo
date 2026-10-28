extends "probe.gd"
## Automatic camera feedback, shared ownership, inactivity and re-entry.
## No mip overrides or flush: read GPU images only after each phase settles.
## This is a contract test, not a loading/frame-time measurement.

func wait_for_bytes(minimum:int,maximum:int,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	var stable:=0
	while Time.get_ticks_msec()<deadline:
		var used:int=streaming.call("get_memory_budget_bytes_used")
		stable=stable+1 if used>=minimum and used<=maximum else 0
		if stable>=5:return true
		await create_timer(0.1).timeout
	return false

func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	Engine.max_fps=60
	if source.is_empty() or output.is_empty():push_error("--source and --output required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	report.engine=Engine.get_version_info();report.source=source;report.source_sha256=FileAccess.get_sha256(source)
	report.automatic_feedback=true;report.forced_lod=false;report.flush_used=false
	report.inactivity_decay_rate_ms=ProjectSettings.get_setting("rendering/textures/streaming/inactivity_decay_rate_ms")
	check(ClassDB.class_exists("StreamedTexture2D") and Engine.has_singleton("TextureStreaming"),"streaming API exists")
	if failed:finish();return
	streaming=Engine.get_singleton("TextureStreaming")
	report.memory_before=streaming.call("get_memory_budget_bytes_used")
	var image:=Image.load_from_file(source);image.convert(Image.FORMAT_RGBA8);image.generate_mipmaps()
	var path:=output.path_join("source_pixels.stex");write_stex(image,path)
	var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D")
	check(texture.call("load",path)==OK,"load uncompressed source mip chain")
	var initial:=sample(texture,"initial")
	var small_bytes:=initial.get_data().size();var full_bytes:=image.get_data().size()
	check(initial.get_width()==maxi(1,image.get_width()>>3),"initial upload is mip 3")
	var scene:=Node3D.new();root.add_child(scene)
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_texture=texture
	var meshes:Array[MeshInstance3D]=[]
	for i:int in 2:
		var quad:=QuadMesh.new();quad.size=Vector2(2,2)
		var mesh:=MeshInstance3D.new();mesh.mesh=quad;mesh.material_override=material
		scene.add_child(mesh);mesh.position.x=i*3;meshes.append(mesh)
	var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(0,0,20);camera.current=true
	check(await wait_for_bytes(small_bytes,small_bytes,15),"far camera keeps the shared texture at low resolution")
	sample(texture,"far_initial")
	camera.position.z=0.5
	check(await wait_for_bytes(full_bytes,full_bytes,15),"near camera automatically requests full source resolution")
	var near:=sample(texture,"near")
	check(near.get_width()==image.get_width() and near.get_data()==image.get_data(),"automatic full upload preserves all source mip bytes")
	meshes[1].material_override=null;meshes[1].queue_free();meshes.resize(1)
	check(await wait_for_bytes(full_bytes,full_bytes,5),"removing one shared owner does not evict the other")
	camera.position.z=20
	await create_timer(3).timeout
	sample(texture,"far_after_near_observation")
	# Upstream currently retains visible high mips without budget pressure;
	# reduced projected size alone is not asserted to force an eviction.
	meshes[0].visible=false
	check(await wait_for_bytes(small_bytes,small_bytes,15),"invisible texture decays to mip 3")
	sample(texture,"hidden")
	camera.position.z=0.5;meshes[0].visible=true
	check(await wait_for_bytes(full_bytes,full_bytes,15),"return to near view automatically reloads full resolution")
	var returned:=sample(texture,"returned")
	check(returned.get_data()==image.get_data(),"return reload preserves source mip bytes")
	meshes[0].material_override=null;meshes.clear();material.albedo_texture=null
	material=null;texture=null;scene.queue_free()
	check(await wait_for_bytes(int(report.memory_before),int(report.memory_before),10),"final owner release returns accounting to baseline")
	report.memory_after=streaming.call("get_memory_budget_bytes_used")
	check(FileAccess.get_sha256(source)==report.source_sha256,"source input unchanged")
	finish()
