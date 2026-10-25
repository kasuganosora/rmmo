extends "res://tools/test_shared_prefab_images.gd"
## Exercise DDS with the real shared reservation, two workers, parked follower,
## producer cancellation and continuation, not just standalone pixel packets.
func run()->void:
	var source_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source_path=arg.trim_prefix("--source=")
	if source_path.is_empty():push_error("--source requires a PNG with BC1 and BC5 sidecars");quit(2);return
	var logger:=Base.Errors.new();OS.add_logger(logger)
	fixture=Base.new();fixture.files=Base.Files.new();fixture.files.content_root=Prep.Paths.external_root()
	fixture.files.folder=Prep.Paths.cache_directory("shared_compressed_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(fixture.files.folder)
	var path:String=fixture.files.folder.path_join("shared.png")
	for suffix:String in ["",".dxt1.dds",".bc5.dds"]:
		fixture.files.write_bytes(path+suffix,FileAccess.get_file_as_bytes(source_path+suffix));fixture.files.created.append(path+suffix)
	var material:Dictionary={"name":"shared DDS","color":[1,1,1,1],"roughness":.7,"texture_path":path,"normal_path":path,"normal_format":"opengl"}
	var first:Dictionary=fixture.bridge("shared_a",100,material);var second:Dictionary=fixture.bridge("shared_b",200,material)
	var requested:=Prep.sources(first);var plan:=Prep.estimate(requested,fixture.files.content_root)
	check(plan.rows.size()==2 and plan.rows[path].extension=="dds" and plan.rows[path+"|normal"].extension=="dds","both shared roles use compressed admission")
	var probe:=Pool.new();var offer:Dictionary=probe.offer(plan)
	check(offer.has("scratch_bytes") and offer.get("leaders",{}).size()==2,"DDS offer computes scratch without reading PNG-only cache fields")
	if offer.is_empty():
		# The old implementation faults while holding its mutex. Do not launch
		# dependent workers after that failed offer; keep the red run bounded.
		OS.remove_logger(logger);quit(1);return
	probe=null
	await pool_test(requested,plan,path)
	var stored:Dictionary=fixture.files.fixture("shared",[first,second],Base.Fixture.metadata([first,second]))
	var index:Dictionary=Index.build(stored.path,fixture.files.content_root,[first,second])
	check(index.ok,"shared compressed reference index builds")
	var entries:Array=Index.select(index,[]).deferred_entries
	Deferred.prefab_texture_preparation_enabled=true;Deferred.shared_prefab_texture_preparation_enabled=true;Deferred.native_entry_prefetch_enabled=true
	await queue_test(index,entries,stored.path,path,false)
	await queue_test(index,entries,stored.path,path,true)
	for created:String in fixture.files.created:
		if FileAccess.file_exists(created):DirAccess.remove_absolute(created)
	fixture.files.free();fixture.free()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	print("SHARED_COMPRESSED_IMAGES passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
