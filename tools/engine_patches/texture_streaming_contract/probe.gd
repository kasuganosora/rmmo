extends SceneTree
## Run from a copied external project with --rendering-method forward_plus.
## Write the upstream GSTF v1 format without lossy compression; never change
## production source textures. Readbacks are contract checks, not frame timings.
var failed:=0
var report:={"checks":[],"samples":[]}
var output:=""
var source:=""
var streaming:Object
var flush_done:=false

func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.substr(9)
		elif arg.begins_with("--output="):output=arg.substr(9)
	call_deferred("run")

func check(value:bool,label:String)->void:
	report.checks.append({"label":label,"pass":value})
	if not value:failed+=1
	print("PASS " if value else "FAIL ",label)

func write_stex(image:Image,path:String)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	var error:=preload("streamed_texture_product.gd").write(file,image)
	if file!=null:file.close()
	check(error==OK,"write staged streaming product")

func sample(texture:Texture2D,label:String)->Image:
	var image:=RenderingServer.texture_2d_get(texture.get_rid())
	report.samples.append({"label":label,"width":image.get_width(),"height":image.get_height(),"mip_bytes":image.get_data().size(),"streaming_accounted_bytes":streaming.call("get_memory_budget_bytes_used")})
	return image

func flush()->void:
	flush_done=false;streaming.call("flush_texture_streaming")
	var deadline:=Time.get_ticks_msec()+15000
	while not flush_done and Time.get_ticks_msec()<deadline:await process_frame
	check(flush_done,"flush completes")
	for i:int in 8:await process_frame

func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	if source.is_empty() or output.is_empty():push_error("--source and --output required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	report.engine=Engine.get_version_info();report.source=source;report.source_sha256=FileAccess.get_sha256(source)
	check(ClassDB.class_exists("StreamedTexture2D") and Engine.has_singleton("TextureStreaming"),"streaming API exists")
	if failed:finish();return
	streaming=Engine.get_singleton("TextureStreaming")
	streaming.connect("flush_completed",func():flush_done=true)
	report.memory_before=streaming.call("get_memory_budget_bytes_used")
	var image:=Image.load_from_file(source);image.convert(Image.FORMAT_RGBA8);image.generate_mipmaps()
	var path:=output.path_join("source_pixels.stex");write_stex(image,path)
	var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D")
	check(texture.call("load",path)==OK,"load uncompressed GSTF v1")
	var initial:=sample(texture,"initial")
	check(initial.get_width()==maxi(1,image.get_width()>>3),"initial upload starts at mip 3")
	var scene:=Node3D.new();root.add_child(scene)
	var mesh:=MeshInstance3D.new();mesh.mesh=PlaneMesh.new();scene.add_child(mesh)
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_texture=texture;mesh.material_override=material
	var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(0,2,2);camera.look_at(Vector3.ZERO);camera.current=true
	for i:int in 30:await process_frame
	texture.set("min_lod_override",1);texture.set("max_lod_override",1)
	await flush()
	var full:=sample(texture,"forced_full")
	check(full.get_width()==image.get_width() and full.get_data()==image.get_data(),"full resident mip chain preserves source RGBA bytes")
	texture.set("min_lod_override",4);texture.set("max_lod_override",4)
	await flush()
	var small:=sample(texture,"forced_mip_3")
	check(small.get_width()==maxi(1,image.get_width()>>3),"streaming returns to mip 3")
	check(small.get_data().size()<full.get_data().size(),"resident image payload decreases")
	mesh.material_override=null;material.albedo_texture=null;material=null;texture=null;scene.queue_free()
	for i:int in 30:await process_frame
	report.memory_after=streaming.call("get_memory_budget_bytes_used")
	check(report.memory_after==report.memory_before,"streamed texture removal returns accounting to baseline")
	check(FileAccess.get_sha256(source)==report.source_sha256,"source input unchanged")
	finish()

func finish()->void:
	report.failed=failed
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("STREAMING_CONTRACT_FAILED=",failed);quit(1 if failed else 0)
