extends "res://tools/test_native_texture_cross_operation_gpu.gd"
## The parser consumes actual native files; production MapLoader.start, _process
## and _exit_tree run normally. Only the final document-construction step is a fixture.
class Map extends Loader:
	var input_root:String
	var paths:Array=[]
	var completed:=false
	var observed_error:=OK
	func _parse()->void:
		_content_root=input_root
		var result:Dictionary=_model_preparation.run(paths,Callable(),2,Callable(),input_root)
		_native_texture_scope=result.get("native_texture_scope")
		_profile.native_texture_preparation=result.get("native_texture_profile",{})
		for entry:Dictionary in result.entries:_asset_states[entry.path]=entry
		_error=result.error;observed_error=_error;_record_meta={"fixture":true}
	func _start_entry_prefetch()->void:pass
	func _build_records()->void:completed=true;set_process(false)
	func _finish_error(_message:String)->void:completed=true;set_process(false)

func load_map(path:String)->Map:
	var map:=Map.new();map.input_root=folder;map.paths=[path]
	map._model_preparation.candidate_provider=candidate_for
	map._model_preparation.memory_estimator=func(_path:String)->Dictionary:return {"estimated_bytes":4*1024*1024,"exclusive":false}
	root.add_child(map);map.start("private-native-fixture")
	var deadline:=Time.get_ticks_msec()+20000
	while not map.completed and Time.get_ticks_msec()<deadline:await process_frame
	check(map.completed and map.observed_error==OK,"real MapLoader completes "+path.get_file())
	return map

func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root().path_join("initial_inbound_native_%d"%OS.get_process_id());DirAccess.make_dir_recursive_absolute(folder)
	create_timer(100).timeout.connect(func():quit(2));Paint.refresh_sources();Prep.Pixels.Policy.verify_packages=false;Prep.Pixels.profile_enabled=true
	var original:=fixture();original.get_child(1).material_override.resource_local_to_scene=true
	var prepared:=Products.prepare(original,folder);check(prepared.ok and prepared.stats.textures==2,"fixture exports two real native texture products")
	var packed:=PackedScene.new();check(packed.pack(original)==OK,"pack native image-free geometry")
	var directory:=Compiled.directory(folder);DirAccess.make_dir_recursive_absolute(directory);var staging:=directory.path_join("inbound.scn")
	check(ResourceSaver.save(packed,staging,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save actual native geometry")
	Products.restore(prepared);packed=null
	var sha:=FileAccess.get_sha256(staging);var product:=directory.path_join(sha+".scn");DirAccess.rename_absolute(staging,product)
	var file:=FileAccess.open(product,FileAccess.READ);var bytes:=file.get_length();file.close()
	var a:=folder.path_join("old.glb");var b:=folder.path_join("fresh.glb")
	for path:String in [a,b]:candidates[path]={"source_path":path,"source_sha":"a".repeat(64),"payload_sha":sha,"product":product,"bytes":bytes,"generator":Compiled.generator(),"estimated_bytes":4*1024*1024,"exclusive":false,"texture_table":prepared.texture_table,"direct_template_reuse_safe":false}
	var old:Map=await load_map(a)
	if old.observed_error!=OK:root.remove_child(old);old.free();original.free();finish();return
	check(Assets.cache_packed(a,old._asset_states[a].packed,candidates[a].source_sha),"old cache accepts bound native geometry")
	var plan:=Binding.candidate_plan(candidates[a],folder,{});var owners:=native_owners(Assets._scenes[a],plan)
	report.old_initial=old._profile.native_texture_preparation;old.free()
	var fresh:Map=await load_map(b)
	if fresh.observed_error!=OK:root.remove_child(fresh);fresh.free();Assets.evict_cached_scene(a);original.free();finish();return
	report.fresh_initial=fresh._profile.native_texture_preparation
	check(report.fresh_initial.pool.get("streamed_loads",0)==0 and report.fresh_initial.pool.produced==0,"new Initial performs zero duplicate STEX loads or allocations")
	var second:=native_owners(fresh._asset_states[b].packed,plan);var same:=0
	for key:String in owners:
		if owners[key].id==second[key].id and owners[key].rid==second[key].rid:same+=1
	check(same==2,"new Initial binds exact previous Texture instances and RIDs")
	check(report.fresh_initial.get("resident_bridge",{}).get("lookups",-1)==2,"main bridge looks up exactly its two requested keys")
	check(report.fresh_initial.pool.handoff_outputs==0 and report.fresh_initial.pool.peak_retained_bytes==0,"resident hits neither reserve nor re-handoff a full texture chain")
	check(Assets.cache_packed(b,fresh._asset_states[b].packed,candidates[b].source_sha),"fresh cache accepts completed native bindings")
	var source:=viewport(original);var target:=viewport(Assets._instantiate(Assets._scenes[b]))
	Assets.evict_cached_scene(a);fresh.free();candidates.clear();prepared.clear()
	var different:=-1;var visible:=0
	for frame:int in 180:
		await process_frame;await RenderingServer.frame_post_draw
		if frame<12 or frame%6!=0:continue
		var one:=source.get_texture().get_image().get_data();var two:=target.get_texture().get_image().get_data();different=0;visible=0
		for at:int in one.size():different+=int(one[at]!=two[at])
		for at:int in range(0,one.size(),4):
			if one[at]!=one[0] or one[at+1]!=one[1] or one[at+2]!=one[2]:visible+=1
		if different==0 and visible>1000:break
	check(different==0 and visible>1000,"fresh Initial renders exact source pixels after old cache eviction")
	report.render_mismatched_bytes=different;report.render_visible_pixels=visible
	var streaming:=Engine.get_singleton("TextureStreaming");report.engine_before_release=int(streaming.call("get_memory_budget_bytes_used"))
	check(report.engine_before_release>0,"reused native owners stay engine-accounted while the new scene lives")
	var pixels:=target.get_texture().get_image();pixels.save_webp(folder.path_join("initial-inbound.webp"),true,.9)
	report.screenshot_encoding={"lossy":true,"quality":.9,"dimensions":[384,192]}
	source.free();target.free();original=null;Assets.evict_cached_scene(b)
	var deadline:=Time.get_ticks_msec()+8000
	while int(streaming.call("get_memory_budget_bytes_used"))!=0 and Time.get_ticks_msec()<deadline:await process_frame
	report.engine_after_release=int(streaming.call("get_memory_budget_bytes_used"));check(report.engine_after_release==0,"last cache and scene release remove all native engine charges")
	var alive:=0
	for item:Dictionary in owners.values():
		if item.weak.get_ref()!=null:alive+=1
	check(alive==0 and Paint._textures.is_empty(),"all actual owners die with no bridge or hot-cache resource leak")
	finish()
