extends "camera_probe.gd"
## Actual StreamedTexture2D.load on a worker, including discard before publish.
## Does not claim project queue integration or that GPU submission never waits.
var product_path:=""

func load_on_worker()->Dictionary:
	var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D")
	var error:int=texture.call("load",product_path)
	return {"texture":texture,"error":error,"thread":OS.get_thread_caller_id(),"rid":texture.get_rid()}

func worker_result()->Dictionary:
	var worker:=Thread.new()
	check(worker.start(load_on_worker)==OK,"worker starts")
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish()
	check(result.error==OK and result.texture is Texture2D and result.rid.is_valid(),"worker loads a usable streamed texture")
	check(result.thread!=OS.get_main_thread_id(),"load actually runs outside the main thread")
	return result

func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	Engine.max_fps=60
	if source.is_empty() or output.is_empty():push_error("--source and --output required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	report.engine=Engine.get_version_info();report.source=source;report.source_sha256=FileAccess.get_sha256(source)
	report.forced_lod=false;report.flush_used=false;report.scope="worker load/discard/publication contract; not project scheduling or frame benchmark"
	check(ClassDB.class_exists("StreamedTexture2D") and Engine.has_singleton("TextureStreaming"),"streaming API exists")
	if failed:finish();return
	streaming=Engine.get_singleton("TextureStreaming")
	report.memory_before=streaming.call("get_memory_budget_bytes_used")
	var rd:=RenderingServer.get_rendering_device();var rd_id:=rd.get_instance_id()
	var image:=Image.load_from_file(source);image.convert(Image.FORMAT_RGBA8);image.generate_mipmaps()
	product_path=output.path_join("source_pixels.stex");write_stex(image,product_path)
	var scene:=Node3D.new();root.add_child(scene)
	var quad:=QuadMesh.new();quad.size=Vector2(2,2)
	var mesh:=MeshInstance3D.new();mesh.mesh=quad;scene.add_child(mesh)
	var camera:=Camera3D.new();scene.add_child(camera);camera.position.z=0.5;camera.current=true
	for attempt:int in 3:
		var cancelled:=await worker_result()
		# The only resource owner is the result. Drop it before any material bind.
		cancelled.clear()
		check(await wait_for_bytes(int(report.memory_before),int(report.memory_before),10),"unpublished worker result drains: %d"%attempt)
	var prepared:=await worker_result()
	var texture:Texture2D=prepared.texture
	var before_rid:RID=prepared.rid;prepared.clear()
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture=texture;mesh.material_override=material
	check(await wait_for_bytes(image.get_data().size(),image.get_data().size(),15),"worker-produced texture receives automatic near-camera feedback")
	var full:=sample(texture,"worker_then_main_publication")
	check(full.get_data()==image.get_data(),"worker handoff preserves source mip bytes")
	check(texture.get_rid()==before_rid,"automatic promotion preserves the published texture RID")
	check(RenderingServer.get_rendering_device().get_instance_id()==rd_id,"worker loading preserves main RenderingDevice identity")
	mesh.material_override=null;material.albedo_texture=null;material=null;texture=null;scene.queue_free()
	check(await wait_for_bytes(int(report.memory_before),int(report.memory_before),10),"published worker result drains after final owner release")
	report.memory_after=streaming.call("get_memory_budget_bytes_used")
	check(FileAccess.get_sha256(source)==report.source_sha256,"source input unchanged")
	finish()
