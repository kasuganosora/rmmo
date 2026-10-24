extends "res://tools/test_interactive_collision_lookahead.gd"
const Preparer=preload("res://scripts/world3d/stream_collision_preparer.gd")
func covered(map:Node3D,point:Vector3)->Dictionary:
	var began:=Time.get_ticks_usec();var work:=0;var steps:=0
	while steps<300:
		var start:=Time.get_ticks_usec();Stream.sync(map,map,point,Stream.LOAD_BUDGET)
		work+=Time.get_ticks_usec()-start;steps+=1
		if map.get_meta("stream_chunk",Vector2i(-999,-999))==Stream.chunk_key(point) and map.get_meta("stream_jobs",[]).is_empty():break
		await process_frame
	return {"steps":steps,"main_us":work,"wall_us":Time.get_ticks_usec()-began}
func run()->void:
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	var trials:Array=[]
	for batch:bool in [false,true,true,false]:
		Preparer.small_worker_bvh_enabled=batch
		var map:=fixture()
		for spec_:Dictionary in map.get_meta("stream_library"):spec_.mesh.collision_faces()
		var row:=await covered(map,Vector3(4,0,4))
		check(exact_bodies(map),"covered entry preserves all 96 transformed collision meshes")
		var preparer:Node=map.get_node("StreamCollisionPreparer")
		row.batch=batch;row.worker_bvh=preparer.bvh_worker_shapes;row.main_bvh=preparer.bvh_main_shapes;row.serial_workers=preparer.face_worker_starts
		row.lookahead_batches=preparer._face_prefetch.profile.batches
		trials.append(row);map.free();await process_frame
	Preparer.small_worker_bvh_enabled=true
	var report:={"failures":failures,"trials":trials}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COLLISION_ENTRY_BARRIERS ",JSON.stringify(report));quit(1 if failures else 0)
