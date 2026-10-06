extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
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
	create_timer(600).timeout.connect(func():push_error("Cloth benchmark timeout");quit(2))
	if OS.get_cmdline_user_args().size()>1:sample_frames=maxi(30,int(OS.get_cmdline_user_args()[1]))
	var stage:String=OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "before"
	var result:Dictionary={"gpu":RenderingServer.get_video_adapter_name(),"scope":"independent viewports, same maid skirt and 24 iterations / 4 substeps; no inter-character collisions; wall-frame time"}
	var count_before:=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for count in [1,2,4]:
		while views.size()<count:
			var view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(view)
			view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}},{"SurfaceEquipment":{"Clothing2":"maid_separate/item_01"},"SurfaceClothSlots":["Clothing2"]})
			view.position=Vector2(120+views.size()*200,350);views.append(view)
		var preparing_frames:=0
		while true:
			await process_frame;await RenderingServer.frame_post_draw
			preparing_frames+=1
			var ready:=true
			for view in views:
				var cloth=view.model.axis_rig.cloth
				if not cloth.error.is_empty():push_error(cloth.error);quit(3);return
				ready=ready and cloth.is_ready()
				if preparing_frames%20==0:print("Prepare ",preparing_frames," actor ",view.get_instance_id()," state ",cloth.entries.Clothing2.prepared_frames)
			if preparing_frames>90:push_error("Preparation did not finish");quit(4);return
			if ready:break
		for frame in 30:await process_frame
		result[str(count)+"_idle"]=await sample()
		print("Measured ",count," clothed actors: ",result[str(count)+"_idle"])
	for view in views:view.play("walk","front",true)
	for frame in 12:await process_frame
	result["4_walk"]=await sample()
	for view in views:
		assert(view.model.axis_rig.cloth.error.is_empty())
		view.free()
	views.clear()
	for frame in 4:await process_frame
	result["node_delta_after_release"]=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))-count_before
	var performance_pass:=true
	for key in ["1_idle","2_idle","4_idle","4_walk"]:
		result[key]["meets_60fps"]=result[key].p95_ms<=FRAME_BUDGET_MS
		performance_pass=performance_pass and result[key].meets_60fps
	result["frame_budget_ms"]=FRAME_BUDGET_MS
	result["performance_pass"]=performance_pass
	result["lifecycle_pass"]=result.node_delta_after_release==0
	var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_03/cloth_"+stage+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("PERFORMANCE ","PASS " if performance_pass else "FAIL ",JSON.stringify(result))
	quit(0 if performance_pass and result.lifecycle_pass else 5)
