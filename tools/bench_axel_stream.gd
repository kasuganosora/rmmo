extends SceneTree
func _init():call_deferred("run")
func run():
	var field=load("res://scripts/map/map_field.gd").new()
	field.skip_ready_rebuild=true
	root.add_child(field)
	field.set_process(false)
	field._ensure_sprites()
	var t=Time.get_ticks_usec()
	field.pack=load("res://scripts/map/tilemap_pack.gd").load_pack("user://content/packs/default","Axel256")
	var pack_ms=(Time.get_ticks_usec()-t)/1000.0
	field.collision=field.pack.collision
	field.tile_size=field.pack.tile_size
	field.grid_width=field.pack.width
	field.grid_height=field.pack.height
	t=Time.get_ticks_usec()
	field._bake_lofi_overview()
	var overview_ms=(Time.get_ticks_usec()-t)/1000.0
	field._stream_ready=true
	field._obs_cell=Vector2i(112,119)
	field._rebuild_chunks_around(field._obs_cell,false)
	var profiles=[]
	for i in range(8):
		var target=field._chunk_stream_module_logic.stream_stats.baked+1
		while field._chunk_stream_module_logic.stream_stats.baked<target:
			field._chunk_stream_module_logic.pump()
			await process_frame
		profiles.append(field._chunk_stream_module_logic.last_bake_profile.duplicate())
	var result={"pack_ms":pack_ms,"overview_ms":overview_ms,"chunks":profiles,"queued":field._chunk_queue.size()}
	print(JSON.stringify(result))
	var path="D:/code/rmmo_runtime/style_work/town_m/stream_benchmark.json"
	for arg in OS.get_cmdline_user_args():path=arg
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	field.queue_free()
	quit()
