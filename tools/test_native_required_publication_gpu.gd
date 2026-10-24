extends "res://tools/test_asset_bounds_manifest.gd"
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Document=preload("res://scripts/world3d/world_document.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
func record(path:String)->Dictionary:
	return {"uuid":"native_publication_fixture","kind":"asset","asset_path":path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
func clear_cached(path:String)->void:
	Assets.evict_cached_scene(path)
	Drainer.synchronize_transfer()
func trial(path:String,bridge:bool,required:bool)->void:
	clear_cached(path)
	var doc:=Document.new()
	# The old implementation has no policy, so the same fixture exposes its raw fallback.
	if "load_require_native_products" in doc:doc.load_require_native_products=required
	var row:=record(path)
	if bridge:row.bridge_mesh={};row.bridge_materials={}
	Trace.minimum_event_us=0;Trace.start()
	var instance:Dictionary=doc._begin_asset_instance(row,{})
	var events:Array=Trace.stop().events
	var raw_calls:=events.filter(func(e):return e.label=="asset_library.raw_load").size()
	if required:
		check(instance.model==null,"runtime native miss has no model: bridge="+str(bridge))
		check(raw_calls==0,"WORK runtime publication never imports raw GLB: bridge="+str(bridge))
		check(instance.holder.has_meta("paint_error"),"runtime miss carries an actionable publication error")
	else:
		check(instance.model!=null,"editor explicit model instantiation still imports")
		check(raw_calls==1,"editor miss performs exactly one explicit raw import")
	instance.holder.free();instance.clear();clear_cached(path)
func run()->void:
	check(DisplayServer.get_name()!="headless","isolated GPU context")
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd");controls.enable_white_materials();controls.discard_map_textures=true
	var directory:=Paths.cache_directory("native_publication_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("fixture.glb");write(path,data())
	var digest:=FileAccess.get_sha256(path)
	trial(path,false,true)
	trial(path,true,true)
	trial(path,false,false)
	Trace.minimum_event_us=0;Trace.start()
	var fort:=preload("res://scripts/world3d/fortification_art.gd").new()
	check(fort.kit(path,true).is_empty(),"fortification module miss rejects missing native product")
	var events:Array=Trace.stop().events
	check(not events.any(func(e):return e.label=="asset_library.raw_load"),"fortification module lookup does not import GLB")
	var queue:=preload("res://scripts/world3d/deferred_asset_loader.gd").new()
	queue.require_native_products=true
	check(queue._doc.load_require_native_products,"deferred publication document receives runtime policy")
	queue.require_native_products=false
	check(not queue._doc.load_require_native_products,"explicit editor helper policy remains configurable")
	queue.free()
	# An editor's raw cache entry cannot silently satisfy a required native load.
	var editor:Node3D=Assets.instantiate(path);check(editor!=null,"editor can populate raw template cache")
	if editor!=null:editor.free()
	var old_template:PackedScene=Assets._scenes.get(path)
	Trace.start()
	var refused:Node3D=Assets.instantiate(path,true)
	events=Trace.stop().events
	check(refused==null and Assets._scenes.get(path)==old_template,"required lookup neither consumes nor replaces editor raw cache on native miss")
	check(not events.any(func(e):return e.label=="asset_library.raw_load"),"required cache miss never parses raw source")
	if refused!=null:refused.free()
	old_template=null;clear_cached(path)
	var built:=Native.build(path,Paths.external_root())
	check(built.ok,"explicit content export produces native template")
	var game:Node3D=Assets.instantiate(path,true)
	check(game!=null and Assets._scenes[path].get_meta("compiled_asset_validated",false),"game synchronous lookup accepts exported native product")
	if game!=null:game.free()
	clear_cached(path)
	var preview:Node3D=Assets.instantiate_preview(path,true)
	check(preview!=null and not Assets._scenes.has(path),"native module preview stays outside shared scene cache")
	if preview!=null:preview.free()
	check(FileAccess.get_sha256(path)==digest,"authored fixture bytes unchanged")
	Drainer.synchronize_transfer()
	print("NATIVE_REQUIRED_PUBLICATION_GPU passed=",passed," failures=",failures)
	quit(1 if failures else 0)
