extends SceneTree
var inspected:=false
func inspect(solver:Node)->void:
	for entry in [["forward",solver._forward_candidates,solver._particle_count],["reverse",solver._reverse_candidates,solver._tri_count]]:
		var bytes:PackedByteArray=solver._rd.buffer_get_data(entry[1]);var counts:Array[int]=[];var over:=0
		for i in entry[2]:
			var count:=bytes.decode_u32(i*2055*4);counts.append(count)
			if count>2048:over+=1
		counts.sort();print("CANDIDATES ",entry[0]," p50=",counts[counts.size()/2]," p95=",counts[int(counts.size()*.95)]," overflow=",over,"/",counts.size())
	inspected=true
func _initialize()->void:call_deferred("run")
func run()->void:
	if preload("res://tools/gpu_shader_review_manifest.gd").collect().is_empty():quit(2);return
	create_timer(120).timeout.connect(func():push_error("Profile timeout");quit(2))
	var view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(view)
	view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}},{"SurfaceEquipment":{"Clothing2":"maid_separate/item_01"},"SurfaceClothSlots":["Clothing2"]})
	while not view.model.axis_rig.cloth.is_ready():await process_frame
	var solver=view.model.axis_rig.cloth.entries.Clothing2.adapter.solver
	solver.review_gpu_timing=true
	RenderingServer.call_on_render_thread(inspect.bind(solver))
	while not inspected:await process_frame
	for i in 15:
		await process_frame;await RenderingServer.frame_post_draw
		if i>8:print("GPU raw ns ",solver.review_gpu_ticks," render_submit_ms=",solver.review_render_submit_ms)
	view.free();for i in 4:await process_frame
	quit()
