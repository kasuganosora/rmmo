extends SceneTree
## Run in an isolated project whose external content root is a review directory.
## The GLB path is only an asset key: this fixture never creates an import source.
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Binding=preload("res://scripts/world3d/model_texture_bindings.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Ready=preload("res://scripts/world3d/model_texture_readiness.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var failures:=0
var checks:=0
var content_root:String
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func write(path:String,body:String)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(body);file.close()
func fixture(name_:String,split:bool)->Dictionary:
	var path:=content_root.path_join("assets/native_preview_%d_"%OS.get_process_id()+name_+".glb")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var table:={"version":1,"image_bytes":64,"textures":{SHA:{"file":"cache/world3d/model_textures_v1/"+SHA+".stex","pixel_sha":SHA,"width":4,"height":4,"format":Image.FORMAT_RGBA8,"bytes":64,"file_bytes":116,"mip_sizes":[64],"alpha":false,"normal_xy":false}}}
	var table_body:=JSON.stringify(table);var table_sha:=table_body.sha256_text()
	if split:write(Binding.Products.table_directory(content_root).path_join(table_sha+".json"),table_body)
	var scene:=Node3D.new()
	if split:
		scene.set_meta(Binding.TABLE_META,table_sha)
		scene.set_meta(Ready.READY_META,table_sha) # An authored flag is not completion.
	var material:=StandardMaterial3D.new()
	if split:material.set_meta(Binding.BINDINGS_META,{"albedo_texture":{"id":SHA,"normal":false}})
	var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,material)
	var part:=MeshInstance3D.new();part.mesh=mesh;scene.add_child(part);part.owner=scene
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack "+name_+" fixture");scene.free()
	if split:packed.set_meta(Ready.READY_META,table_sha)
	var folder:=Compiled.directory(content_root);DirAccess.make_dir_recursive_absolute(folder)
	var staging:=folder.path_join("preview_fixture_%d_%s.scn"%[OS.get_process_id(),name_])
	check(ResourceSaver.save(packed,staging,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save "+name_+" fixture")
	packed=null
	var payload_sha:=FileAccess.get_sha256(staging);var product:=folder.path_join(payload_sha+".scn")
	if FileAccess.file_exists(product):DirAccess.remove_absolute(staging)
	else:check(DirAccess.rename_absolute(staging,product)==OK,"publish "+name_+" fixture")
	var file:=FileAccess.open(product,FileAccess.READ);var size:=file.get_length();file.close()
	var descriptor:={"version":1,"sha256":table_sha,"bytes":table_body.to_utf8_buffer().size(),"textures":1,"image_bytes":64}
	var manifest:={"version":1,"source_path":path,"source_sha":SHA,"payload_sha":payload_sha,"generator":"native_preview_fixture","bytes":size}
	if split:manifest.texture_table=descriptor
	write(Compiled.index_path(path,content_root),JSON.stringify(manifest))
	var footprint:=manifest.duplicate(true);footprint.erase("texture_table")
	footprint.merge({"source_bytes":28,"estimated_bytes":67108864,"resident_bytes":67108864,"model_metadata":{"version":1,"local_bounds":[0,0,0,1,1,1],"file_length":28,"json_bytes":4,"json_sha256":SHA}})
	var body:=JSON.stringify(footprint)
	write(Footprint.descriptor_path(path,content_root),JSON.stringify({"version":1,"body":body,"sha256":body.sha256_text()}))
	return {"path":path,"table_sha":table_sha}
func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):
		printerr("This fixture requires an isolated review_artifacts content root");quit(2);return
	var model:=fixture("split",true)
	var candidate:=Assets.native_candidate(model.path)
	check(not candidate.is_empty() and not FileAccess.file_exists(model.path),"published split candidate needs no GLB source")
	var packet:=Assets._read_published_native(model.path,candidate)
	check(packet.get("hit",false) and not Ready.packed_ready(packet.packed),"native reader clears serialized completion on the packed resource")
	var ordinary:=Assets.instantiate(model.path,true)
	check(ordinary==null,"ordinary cold entry refuses an unbound split product")
	if ordinary!=null:ordinary.free()
	Trace.start()
	var preview:=Assets.instantiate_preview(model.path,true)
	var traced:=Trace.stop();var native_reads:=0
	for stat:Dictionary in traced.stats:
		if stat.label=="compiled.native_read":native_reads+=int(stat.count)
	check(preview==null,"preview cold entry refuses unbound textures and forged node completion")
	if preview!=null:preview.free()
	check(native_reads==0,"unbound preview miss does not allocate and discard a native geometry graph")
	check(not Assets._scenes.has(model.path),"failed preview does not publish a cache entry")
	var state:=Binding.begin(packet.packed,{SHA:"fixture_texture"},model.table_sha)
	var texture:=GradientTexture2D.new()
	check(Binding.adopt(state,{"fixture_texture":texture}) and Binding.step(state)==Binding.READY,"explicit preparation completes the material graph")
	Binding.release(state)
	check(Assets.cache_packed(model.path,packet.packed,SHA,candidate),"complete native product can enter the shared cache")
	for index:int in 2:
		preview=Assets.instantiate_preview(model.path,true)
		check(preview!=null and Ready.scene_ready(preview) and preview.get_child(0).mesh.surface_get_material(0).albedo_texture==texture,"cached preview %d retains the exact completed texture owner"%index)
		if preview!=null:preview.free()
	Assets._scenes.erase(model.path);Drainer.dispose_result(packet)
	var embedded:=fixture("ordinary",false)
	preview=Assets.instantiate_preview(embedded.path,true)
	check(preview!=null and Ready.scene_ready(preview),"ordinary native preview without split textures remains available")
	if preview!=null:preview.free()
	check(not Assets._scenes.has(embedded.path),"ordinary one-shot preview leaves the shared scene cache unchanged")
	print("NATIVE_TEXTURE_PREVIEW checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
