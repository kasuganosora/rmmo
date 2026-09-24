extends SceneTree
var failed:=0
func check(ok: bool,label: String):
	if not ok:failed+=1;push_error(label)
	else:print("PASS ",label)
func _init():call_deferred("run")
func run():
	var pool=load("res://scripts/map/field/chunk_texture_pool.gd").new()
	var pixels=Image.create(768,768,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.RED)
	var texture=pool.upload(pixels)
	pool.offer({"color":texture})
	for i in range(4):await process_frame
	pixels.fill(Color.BLUE)
	var reused=pool.upload(pixels)
	check(reused==texture,"evicted GPU texture reused without allocation")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		check(reused.get_image().get_pixel(0,0)==Color.BLUE,"GPU reuse uploads replacement pixels")
	else:print("SKIP dummy renderer upload readback; verify in live renderer")
	for i in range(20):pool.offer({"color":ImageTexture.create_from_image(pixels)})
	check(pool.bytes<=pool.BUDGET,"GPU spare pool bounded separately")
	pool.clear()
	var field=load("res://scripts/map/map_field.gd").new()
	field.skip_ready_rebuild=true;root.add_child(field);field.set_process(false)
	field.pack=load("res://scripts/map/tilemap_pack.gd").load_pack("user://content/packs/default","Axel256")
	var snapshot=field.pack.render_snapshot()
	check(snapshot.sheets[0]==field.pack.sheets[0],"render snapshot reuses decoded sheets")
	check(snapshot.collision!=field.pack.collision,"renderer collision isolated from server")
	snapshot.collision.set_extra_blocked(1,1,true)
	check(not field.pack.collision.is_extra_blocked(1,1),"renderer occupancy cannot mutate server")
	snapshot.collision._stream_chunks["0,0"]=PackedInt32Array([1])
	check(not field.pack.collision._stream_chunks.has("0,0"),"streaming dictionary belongs to renderer")
	field.collision=field.pack.collision;field.tile_size=field.pack.tile_size
	field.grid_width=field.pack.width;field.grid_height=field.pack.height
	field._stream_ready=true;field._obs_cell=Vector2i(112,119)
	field._rebuild_chunks_around(field._obs_cell,false)
	var worker=load("res://scripts/map/field/chunk_bake_worker.gd").new()
	for coordinate in [Vector2i(7,7),Vector2i(7,8),Vector2i(8,11)]:
		field._obs_cell=coordinate*16+Vector2i(8,8);field._refresh_chunk_set()
		worker.start(field,coordinate)
		while not worker.ready():await process_frame
		var payload=worker.take()
		field._chunk_queue.clear();field._chunk_queue.append(coordinate)
		field._bake_next_chunk(false)
		var node=field._chunks[field._chunk_key(coordinate)]
		for bucket in payload.images:
			check(node.get_node(bucket).texture.get_image().get_data()==payload.images[bucket].get_data(),"worker matches synchronous color "+str(coordinate)+" "+bucket)
		var expected=field._surface_materials.bake_images(coordinate.x*16,coordinate.y*16,16,16)
		for channel in ["normals","emissions"]:
			for bucket in expected[channel]:
				var actual: Image=payload.materials[channel][bucket]
				if channel=="emissions" and actual.get_size()==Vector2i.ONE:
					check(expected[channel][bucket].is_invisible() and actual.is_invisible(),"constant emission preserves zero contribution "+bucket)
				else:check(expected[channel][bucket].get_data()==actual.get_data(),"worker matches "+channel+" "+bucket)
		check(expected.height.get_data()==payload.materials.height.get_data(),"padded height unchanged")
	worker.shutdown()
	# Returning to a recently evicted region restores nodes without baking.
	field._obs_cell=Vector2i(8,8);field._refresh_chunk_set()
	check(field._chunk_stream_module_logic.retired_bytes<=field._chunk_stream_module_logic.RETIRED_BUDGET,"retention memory bounded")
	var retained=field._chunk_stream_module_logic.retired.keys()
	if not retained.is_empty():
		var key=retained[-1];var cached=field._chunk_stream_module_logic.retired[key].node
		field._obs_cell=cached.chunk*16+Vector2i(8,8);field._refresh_chunk_set()
		check(field._chunks.get(key)==cached,"returning restores same GPU node")
	# Destroying during a background bake joins the worker before releasing data.
	field._chunk_queue.clear();field._chunk_queue.append(Vector2i(7,7))
	field._chunk_stream_module_logic.pump()
	var old_root=field._chunk_root
	var old_worker=field._chunk_stream_module_logic.worker
	var baked_count=field._chunk_stream_module_logic.stream_stats.baked
	var exported=field.export_bake()
	var next_field=field.get_script().new()
	next_field.skip_ready_rebuild=true;root.add_child(next_field);next_field.set_process(false)
	check(next_field.apply_bake(exported),"loading payload can be adopted")
	check(next_field._chunk_root==old_root,"loading transfers existing chunk nodes and GPU textures")
	check(next_field._chunk_stream_module_logic.worker==old_worker,"loading transfers in-flight worker")
	check(next_field._chunk_stream_module_logic.stream_stats.baked==baked_count,"adoption does not rebake chunks")
	field.free()
	next_field.free()
	exported.clear()
	print("WORKER TEST failures=",failed)
	quit(1 if failed else 0)
