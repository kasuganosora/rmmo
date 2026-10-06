extends SceneTree
## Fixed input/animation time, including walk transition; elapsed time never
## feeds back into the animation or solver. This complements real-world timing.
const Solver=preload("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
var final_points:=PackedByteArray()
var read_finished:=false
var candidate_read_finished:=false
var candidate_snapshot:Dictionary={}
func read_candidate_stats(solver:Node)->void:
	var result:Dictionary={}
	for entry in [["forward",solver._forward_candidates,solver._particle_count],["reverse",solver._reverse_candidates,solver._tri_count]]:
		var bytes:PackedByteArray=solver._rd.buffer_get_data(entry[1])
		var counts:Array[int]=[];var overflow:=0
		for i in int(entry[2]):
			var count:=bytes.decode_u32(i*2055*4);counts.append(count)
			if count>2048:overflow+=1
		counts.sort()
		result[entry[0]]={"p50":counts[counts.size()/2],"p95":counts[ceili(counts.size()*.95)-1],"max":counts[-1],"overflow":overflow,"queries":counts.size()}
	candidate_snapshot=result;candidate_read_finished=true
func read_points(solver:Node)->void:
	final_points=solver._rd.buffer_get_data(solver._positions_buffer)
	read_finished=true
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(240).timeout.connect(func():push_error("Replay timeout");quit(2))
	var result=await run_case(OS.get_cmdline_user_args())
	if result!=null:quit(0 if result.functional_pass else 2)
func run_case(args:PackedStringArray):
	read_finished=false;final_points=PackedByteArray()
	var shader_manifest:=preload("res://tools/gpu_shader_review_manifest.gd").collect()
	if shader_manifest.is_empty():quit(2);return
	var threshold_flag:=args.find("--candidate-threshold")
	preload("res://scripts/char/female_axis_body.gd").default_gpu_display="--cpu-display" not in args
	preload("res://scripts/char/garment_candidate_cloth.gd").default_shared_body_points="--shared-body-points" in args
	preload("res://scripts/char/garment_candidate_cloth.gd").default_resident_packet="--readback-packet" not in args
	Solver.default_candidate_padding=.012
	Solver.default_substep_tree_refit="--refit-tree" in args
	Solver.default_candidate_group_size=64
	Solver.default_cooperative_candidates=not "--serial-candidates" in args
	var group_flag:=args.find("--candidate-group-size")
	if group_flag>=0 and group_flag+1<args.size():Solver.default_candidate_group_size=int(args[group_flag+1])
	var padding_flag:=args.find("--candidate-padding")
	if padding_flag>=0 and padding_flag+1<args.size():Solver.default_candidate_padding=float(args[padding_flag+1])
	if threshold_flag>=0 and threshold_flag+1<args.size():Solver.default_candidate_motion_threshold_m=float(args[threshold_flag+1])
	var baseline:bool="--baseline" in args
	var world_motion:bool="--world-motion" in args
	var input_spikes:bool="--input-spikes" in args
	var uncapped:bool="--uncapped" in args
	if uncapped:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps=0
	Solver.default_batched_structure=not baseline
	Solver.default_adaptive_candidates=not "--all-substeps" in args
	Solver.default_combined_contacts=not "--split-contacts" in args
	Solver.default_substep_candidates=not "--frame-candidates" in args
	var view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(view)
	view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}},{"SurfaceEquipment":{"Clothing2":"maid_separate/item_01"},"SurfaceClothSlots":["Clothing2"]})
	view.model.set_process(false)
	view.model.play("idle","front",true)
	view.model._from_rotations.clear();view.model.pose_at(0)
	var cloth=view.model.axis_rig.cloth
	var solver=cloth.entries.Clothing2.adapter.solver
	var adapter=cloth.entries.Clothing2.adapter
	var iterations_flag:=args.find("--iterations")
	if iterations_flag>=0 and iterations_flag+1<args.size():solver.solver_iterations=clampi(int(args[iterations_flag+1]),1,64)
	var substeps_flag:=args.find("--substeps")
	if substeps_flag>=0 and substeps_flag+1<args.size():solver.substeps=clampi(int(args[substeps_flag+1]),1,8)
	while not solver._gpu_init_done:await process_frame
	for i in 65:
		view.model._process(1.0/60.0)
		await process_frame;await RenderingServer.frame_post_draw
	if not cloth.is_ready():push_error("Replay preparation failed");quit(2);return
	# Diagnostic ablation only: retain nodes/render state but skip cloth updates.
	# This is not a usable garment LOD and is never enabled by game code.
	var held_entries:Dictionary=cloth.entries.duplicate()
	if "--without-cloth" in args:cloth.entries.clear()
	solver.review_gpu_timing="--profile" in args
	view.model.play("walk","front",true)
	var times:Array[float]=[];var submits:=0.0
	var replay_time:=0.0;var frame_dt:Array[float]=[]
	var diagnostics:Array=[]
	for i in 180:
		var start:=Time.get_ticks_usec()
		var step_dt:=.12 if input_spikes and i in [2,3,25,90] else 1.0/60.0
		replay_time+=step_dt;frame_dt.append(step_dt)
		if world_motion:
			view.model.position=Vector3(float(i+1)*.04,0,float(i+1)*.02)
			view.model.rotation.y=PI*.25*(1.0-exp(-float(i+1)/6.0))
			if input_spikes:
				view.model.position=Vector3(2.4,0,1.2)*replay_time
				view.model.rotation.y=PI*.25*(1.0-exp(-replay_time*10.0))
		view.model._process(step_dt)
		await process_frame;await RenderingServer.frame_post_draw
		times.append((Time.get_ticks_usec()-start)/1000.0)
		submits+=adapter.last_simulate_ms
		diagnostics.append({"body_ms":adapter.body.last_solve_ms,"packet_ms":adapter.last_submit_ms,"render_submit_ms":solver.review_render_submit_ms,"previous_capture_gpu_ns":solver.review_gpu_ticks.duplicate() if solver.review_gpu_timing else {}})
		# Sideband readback deliberately perturbs timing: do not use this mode
		# as an FPS benchmark. Fixed simulation inputs remain reproducible.
		if "--candidate-stats" in args and i in [0,2,3,4,25,90,179]:
			candidate_read_finished=false
			RenderingServer.call_on_render_thread(read_candidate_stats.bind(solver))
			while not candidate_read_finished:await process_frame
			diagnostics[-1]["candidate_snapshot"]=candidate_snapshot.duplicate(true)
	cloth.entries=held_entries
	RenderingServer.call_on_render_thread(read_points.bind(solver))
	while not read_finished:await process_frame
	var folder:String=Art.review_path("character_3d/runtime_performance_06")
	DirAccess.make_dir_recursive_absolute(folder)
	var stage:String="baseline" if baseline else "batched"
	var stage_flag:=args.find("--stage")
	if stage_flag>=0 and stage_flag+1<args.size():stage=args[stage_flag+1]
	var file:=FileAccess.open(folder+"/replay_"+stage+".bin",FileAccess.WRITE)
	file.store_buffer(final_points);file.close()
	var ordered:=times.duplicate();ordered.sort()
	var result:Dictionary={"stage":stage,"substep_candidates":solver.substep_candidates,"candidate_motion_threshold_m":solver.candidate_motion_threshold_m,"combined_contacts":solver.combined_contacts,"packed_packet":cloth.entries.Clothing2.adapter.indexed_packet.packed_readback,"world_motion":world_motion,"uncapped":uncapped,"frames":180,"fixed_dt":null if input_spikes else 1.0/60.0,"input_spikes":input_spikes,"frame_dt":frame_dt,"median_ms":ordered[90],"p95_ms":ordered[170],"submit_ms":submits/180,"frame_times":times,"gpu":RenderingServer.get_video_adapter_name(),"functional_pass":cloth.error.is_empty(),"scope":"one actual skirt, fixed animation/solver clock; not whole-world 60fps acceptance"}
	result["iterations"]=solver.solver_iterations;result["substeps"]=solver.substeps
	result["candidate_padding"]=solver.candidate_padding
	result["substep_tree_refit"]=solver.substep_tree_refit
	result["candidate_group_size"]=solver.candidate_group_size
	result["cooperative_candidates"]=solver.cooperative_candidates
	result["gpu_display"]=preload("res://scripts/char/female_axis_body.gd").default_gpu_display
	result["shared_body_points"]=preload("res://scripts/char/garment_candidate_cloth.gd").default_shared_body_points
	result["resident_packet"]=adapter.indexed_packet.has_method("is_gpu_resident")
	if result.resident_packet:
		result["body_point_upload_bytes"]=adapter.indexed_packet.point_upload_bytes
		result["body_point_gpu_read_bytes"]=adapter.indexed_packet.shared_point_read_bytes
	result["cloth_disabled_diagnostic_only"]="--without-cloth" in args
	result["profile_instrumented"]=solver.review_gpu_timing
	result["candidate_readback_instrumented"]="--candidate-stats" in args
	result["diagnostics"]=diagnostics
	result["shader_manifest"]=shader_manifest
	result["quality_acceptance"]="Not a visual/contact acceptance; functional_pass only checks runtime errors. Reduced configurations are diagnostic only."
	file=FileAccess.open(folder+"/replay_"+stage+".json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	view.free();for i in 4:await process_frame
	print("REPLAY ",stage," median_ms=",result.median_ms," p95_ms=",result.p95_ms," functional_pass=",result.functional_pass);return result
