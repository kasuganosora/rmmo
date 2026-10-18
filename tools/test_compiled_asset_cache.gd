extends "res://tools/test_deferred_asset_scene.gd"
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
class ReplaceDuringCapture extends RefCounted:
	var path:String
	var replacement:PackedByteArray
	var calls:=0
	func is_cancelled()->bool:
		calls+=1
		if calls==5:
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(replacement);file.close()
		return false
func run()->void:
	Engine.max_fps=60
	var folder:=Paths.cache_directory("compiled_asset_test_%d"%OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("source.glb")
	static_fixture(path,Color(.2,.6,.3,1))
	var original:Node=Io.load_scene(path);var expected:=capture(original);Drainer.dispose_scene(original)
	check(not Compiled.read(path).hit,"absent cache preserves fallback")
	var built:=Compiled.build(path)
	check(built.ok and not built.get("reused",true),"static GLB compiles into native resource")
	var hit:=Compiled.read(path)
	check(hit.hit,"verified source and product hit native cache")
	if not hit.hit:quit(1);return
	var a:Node=hit.packed.instantiate();var b:Node=hit.packed.instantiate()
	check(capture(a)==expected,"native scene preserves exact geometry metadata pixels material and LOD")
	check(a!=b and a.find_child("Plain",true,false).mesh==b.find_child("Plain",true,false).mesh,"independent nodes share immutable resource")
	check(not a.find_child("Plain",true,false).mesh.has_meta("ground_cpu_cache"),"runtime CPU mesh cache is excluded from disk")
	# This fixture owns the PackedScene and its unpublished instances. Finish
	# instance destruction before releasing their last template references.
	Drainer.dispose_scene(a);Drainer.dispose_scene(b);hit.clear()
	check(Compiled.build(path).get("reused",false),"unchanged import reuses compiled product")
	var import_library:=Library.new(folder.path_join("imported_assets"))
	# Drain earlier fixture work so any renderer error within these markers
	# belongs to the real cold import path. Do not prewarm its target/cache.
	Drainer.synchronize_transfer()
	print("COMPILED_LIBRARY_IMPORT_BEGIN")
	var imported:Dictionary=import_library.import_file(path)
	Drainer.synchronize_transfer()
	print("COMPILED_LIBRARY_IMPORT_END")
	check(imported.ok and imported.compiled_asset.ok and Compiled.read(imported.entry.asset_path).hit,"explicit library import automatically prepares its immutable static model")
	check(FileAccess.get_file_as_bytes(path)==FileAccess.get_file_as_bytes(imported.entry.asset_path),"derived import preserves original GLB bytes")
	var Trace=preload("res://scripts/world3d/load_trace.gd")
	Trace.minimum_event_us=0;Trace.start()
	var trusted:=Compiled.read(imported.entry.asset_path,"",Paths.external_root(),false,true)
	var trusted_trace:=Trace.stop()
	check(trusted.hit and trusted_trace.events.filter(func(e):return e.label=="compiled.source_sha").is_empty(),"trusted package cache uses authored source identity without rescanning GLB")
	if trusted.hit:
		var trusted_scene:Node=Compiled.instantiate(trusted.packed)
		var strict_imported:=Compiled.read(imported.entry.asset_path)
		var strict_scene:Node=Compiled.instantiate(strict_imported.packed)
		check(capture(trusted_scene)==capture(strict_scene),"trusted native cache preserves exact geometry and metadata of the published package")
		Drainer.dispose_scene(trusted_scene)
		Drainer.dispose_scene(strict_scene);Drainer.dispose_result(strict_imported)
	Drainer.dispose_result(trusted)
	check(not Compiled.read(path,"",Paths.external_root(),true).hit,"deferred verification requires an already verified digest")
	var parsed:=preload("res://scripts/world3d/model_parse_preparation.gd").parse_gltf(path)
	check(parsed.get("compiled",false) and parsed.has("packed"),"game parser consumes private packed result")
	var editor_parsed:=preload("res://scripts/world_editor/load_job.gd")._parse_asset(path)
	check(editor_parsed.get("compiled",false),"editor parser consumes same compiled product")
	Library._scenes.erase(path)
	var preview:Node=Library.instantiate_preview(path)
	check(preview!=null and not Library._scenes.has(path),"compiled preview does not populate runtime cache")
	Drainer.dispose_scene(preview)
	var second_path:=folder.path_join("same_pixels.glb")
	static_fixture(second_path,Color(.2,.6,.3,1),false,2)
	check(Compiled.build(second_path).ok,"second source with identical grass pixels compiles")
	var shared_a:Node=Library.instantiate(path);var shared_b:Node=Library.instantiate(second_path)
	var repeated:Node=Library.instantiate(path)
	check(Library._scenes[path].get_meta("compiled_grass_rebound",false),"library marks a compiled template prepared once")
	check(shared_a.find_child("Grass",true,false).get_active_material(0).albedo_texture==shared_b.find_child("Grass",true,false).get_active_material(0).albedo_texture,"separate compiled models share identical grass textures")
	check(shared_a.find_child("Grass",true,false).get_active_material(0)==repeated.find_child("Grass",true,false).get_active_material(0) and capture(repeated)==expected,"repeated instance preserves prepared material and exact appearance")
	Drainer.dispose_scene(shared_a);Drainer.dispose_scene(shared_b);Drainer.dispose_scene(repeated)
	Library._scenes.erase(path);Library._scenes.erase(second_path)
	var deferred:Dictionary=await worker_result(path,FileAccess.get_sha256(path),null,{},true)
	check(deferred.error.is_empty() and deferred.get("compiled",false),"live worker uses native cache")
	if deferred.get("scene") is Node:
		Drainer.synchronize_transfer()
		check(capture(deferred.scene)==expected,"worker cache matches direct model")
		var mesh:Mesh=deferred.scene.find_child("Plain",true,false).mesh
		check(mesh.has_meta("ground_cpu_cache") and mesh.get_meta("ground_cpu_cache")._collision_faces==mesh.get_faces(),"cache hit prepares exact CPU collision input")
		Drainer.dispose_scene(deferred.scene)
	var source_bytes:=FileAccess.get_file_as_bytes(path)
	var mutator:=ReplaceDuringCapture.new();mutator.path=path;mutator.replacement=source_bytes.duplicate();mutator.replacement[mutator.replacement.size()-1]^=1
	var changed:Dictionary=await worker_result(path,FileAccess.get_sha256(path),mutator,{},true)
	check(not changed.error.is_empty() and changed.get("scene") is Node,"final complete SHA rejects replacement during compiled scene preparation")
	if changed.get("scene") is Node:Drainer.dispose_scene(changed.scene)
	write_bytes(path,source_bytes)
	var index:=Compiled.index_path(path)
	var manifest_text:=FileAccess.get_file_as_string(index)
	var manifest:Dictionary=JSON.parse_string(manifest_text)
	var payload:=Compiled.directory().path_join(manifest.payload_sha+".scn")
	var bytes:=FileAccess.get_file_as_bytes(payload)
	var corrupt:=bytes.duplicate();corrupt[corrupt.size()/2]^=1
	write_bytes(payload,corrupt)
	check(not Compiled.read(path).hit,"corrupt product is rejected before native load")
	var fallback:=preload("res://scripts/world3d/model_parse_preparation.gd").parse_gltf(path)
	check(fallback.error==OK and not fallback.get("compiled",false),"corrupt product falls back to original GLB")
	write_bytes(payload,bytes)
	manifest.generator="stale";write_bytes(index,JSON.stringify(manifest).to_utf8_buffer())
	check(not Compiled.read(path).hit,"generator version invalidates native product")
	write_bytes(index,manifest_text.to_utf8_buffer())
	static_fixture(path,Color(.8,.1,.5,1))
	var stale:=Compiled.read(path)
	check(not stale.hit and stale.reason=="source_changed_during_read" and not stale.has("packed"),"replacement rejects fully read native candidate without publishing its resources")
	check(Compiled.build(path).ok and Compiled.read(path).hit,"changed source rebuilds independently")
	DirAccess.rename_absolute(path,path+".held")
	check(not Compiled.read(path).hit,"missing original is not hidden by compiled product")
	DirAccess.rename_absolute(path+".held",path)
	static_fixture(folder.path_join("native.glb"),Color.RED,true)
	check(not Compiled.build(folder.path_join("native.glb")).ok,"native map cannot become an independent compiled model")
	var dangerous:=Node3D.new();dangerous.set_script(load("res://scripts/world3d/asset_worker_drainer.gd"))
	var packed:=PackedScene.new();packed.pack(dangerous)
	check(not Compiled._valid_packed(packed),"scripted nodes cannot enter compiled product")
	dangerous.free()
	var job:=preload("res://scripts/world_editor/load_job.gd").new();root.add_child(job)
	job._begin_asset_lookahead([{"kind":"asset","asset_path":path}])
	var drainer:=Drainer.for_tree(self);var drained_before:int=drainer.drained
	job.free()
	var deadline:=Time.get_ticks_msec()+10000
	while drainer.drained==drained_before and Time.get_ticks_msec()<deadline:await process_frame
	check(drainer.drained>drained_before,"editor exit abandons native-read worker without a blocking join")
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader)
	loader._thread=Thread.new()
	loader._thread.start(_coordinator.bind(path,Paths.external_root()))
	loader.free()
	check(true,"game exit services renderer while joining native-read coordinator")
	print("COMPILED_ASSET_CACHE failures=",failures)
	quit(0 if failures==0 else 1)

func write_bytes(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()

func _coordinator(path:String,content_root:String)->Dictionary:
	return preload("res://scripts/world3d/model_parse_preparation.gd").new().run([path],Callable(),2,Callable(),content_root)
