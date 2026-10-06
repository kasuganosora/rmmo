extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const Solver=preload("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd")
const Packet=preload("res://addons/godot_gpu_cloth/src/cloth_indexed_packet.gd")
var views:Array=[]
var sample_frames:=120
const FRAME_BUDGET_MS:=1000.0/60.0
func _initialize()->void:call_deferred("run")
func sample()->Dictionary:
	var frames:Array[float]=[];var submit:=0.0;var simulate:=0.0
	for frame in sample_frames:
		var start:=Time.get_ticks_usec()
		await process_frame;await RenderingServer.frame_post_draw
		frames.append((Time.get_ticks_usec()-start)/1000.0)
		for view in views:
			var adapter=view.model.axis_rig.cloth.entries.Clothing2.adapter
			submit+=adapter.last_submit_ms;simulate+=adapter.last_simulate_ms
	frames.sort()
	return {"frames":sample_frames,"median_ms":frames[sample_frames/2],"p95_ms":frames[ceili(sample_frames*.95)-1],"p99_ms":frames[ceili(sample_frames*.99)-1],"max_ms":frames[-1],"over_33ms":frames.filter(func(v):return v>33.333).size(),"over_50ms":frames.filter(func(v):return v>50).size(),"submit_per_actor_ms":submit/(sample_frames*views.size()),"simulate_dispatch_per_actor_ms":simulate/(sample_frames*views.size())}
func run()->void:
	if preload("res://tools/gpu_shader_review_manifest.gd").collect().is_empty():quit(2);return
	create_timer(600).timeout.connect(func():push_error("Paired cloth benchmark timeout");quit(2))
	var result:Dictionary={"gpu":RenderingServer.get_video_adapter_name(),"scope":"four actual skirts; baseline disables substep candidates, combined dispatch; both use separate packet readbacks; original precision; same process sequential phases"}
	for mode in ["baseline","current"]:
		Solver.default_substep_candidates=mode=="current"
		Solver.default_combined_contacts=mode=="current"
		Packet.default_packed_readback=false
		for i in 4:
			var view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(view)
			view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}},{"SurfaceEquipment":{"Clothing2":"maid_separate/item_01"},"SurfaceClothSlots":["Clothing2"]})
			views.append(view)
		while true:
			await process_frame;await RenderingServer.frame_post_draw
			var ready:=true
			for view in views:
				var cloth=view.model.axis_rig.cloth
				assert(cloth.error.is_empty());ready=ready and cloth.is_ready()
			if ready:break
		for i in 30:await process_frame
		result[mode+"_idle"]=await sample()
		for view in views:view.play("walk","front",true)
		for i in 12:await process_frame
		result[mode+"_walk"]=await sample()
		for view in views:view.free()
		views.clear()
		for i in 8:await process_frame
		print("PAIRED ",mode," ",result[mode+"_idle"]," ",result[mode+"_walk"])
	var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_06/four_paired.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("PAIR COMPLETE");quit()
