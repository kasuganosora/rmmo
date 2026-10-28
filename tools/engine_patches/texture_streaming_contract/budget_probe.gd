extends "camera_probe.gd"
## Near-camera demand must respect the streaming budget, and regain detail when
## budget pressure is removed. Never forces a mip or flushes the streaming queue.

func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	Engine.max_fps=60
	if source.is_empty() or output.is_empty():push_error("--source and --output required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	report.engine=Engine.get_version_info();report.source=source;report.source_sha256=FileAccess.get_sha256(source)
	report.forced_lod=false;report.flush_used=false;report.scope="one-texture budget feedback contract; not a whole-map memory/FPS measurement"
	check(ClassDB.class_exists("StreamedTexture2D") and Engine.has_singleton("TextureStreaming"),"streaming API exists")
	if failed:finish();return
	streaming=Engine.get_singleton("TextureStreaming")
	report.memory_before=streaming.call("get_memory_budget_bytes_used")
	check(ProjectSettings.get_setting("rendering/textures/streaming/memory_budget_enabled"),"fixture enables the streaming budget")
	streaming.set("memory_budget_mb_override",4)
	var image:=Image.load_from_file(source);image.convert(Image.FORMAT_RGBA8);image.generate_mipmaps()
	var full_bytes:=image.get_data().size()
	check(full_bytes>4*1024*1024 and full_bytes<64*1024*1024,"source spans the two explicit test budgets")
	if failed:finish();return
	var path:=output.path_join("source_pixels.stex");write_stex(image,path)
	var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D")
	check(texture.call("load",path)==OK,"load uncompressed source mip chain")
	var scene:=Node3D.new();root.add_child(scene)
	var quad:=QuadMesh.new();quad.size=Vector2(2,2)
	var mesh:=MeshInstance3D.new();mesh.mesh=quad;scene.add_child(mesh)
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture=texture;mesh.material_override=material
	var camera:=Camera3D.new();scene.add_child(camera);camera.position.z=0.5;camera.current=true
	# Permit initial feedback and its asynchronous IO before observing the limit.
	await create_timer(2).timeout
	check(await wait_for_bytes(1,4*1024*1024,10),"near camera remains within 4 MiB budget")
	var restricted:=sample(texture,"budget_4_mib")
	check(restricted.get_width()<image.get_width(),"budget pressure reduces resident detail")
	streaming.set("memory_budget_mb_override",64)
	check(await wait_for_bytes(full_bytes,full_bytes,15),"raising budget restores full detail without explicit LOD override")
	var restored:=sample(texture,"budget_64_mib")
	check(restored.get_data()==image.get_data(),"restored full mip chain preserves source bytes")
	streaming.set("memory_budget_mb_override",4)
	check(await wait_for_bytes(1,4*1024*1024,15),"lowering budget evicts high mips while still visible")
	sample(texture,"budget_reduced_again")
	mesh.material_override=null;material.albedo_texture=null;material=null;texture=null;scene.queue_free()
	check(await wait_for_bytes(int(report.memory_before),int(report.memory_before),10),"final release returns budget accounting to baseline")
	report.memory_after=streaming.call("get_memory_budget_bytes_used")
	check(FileAccess.get_sha256(source)==report.source_sha256,"source input unchanged")
	finish()
