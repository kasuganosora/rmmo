extends SceneTree
## Private GPU desktop: interleaved complete houses expose the difference
## between waiting for every source and repeatedly building partial houses.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const DisplayState=preload("res://scripts/util/display_state.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const HOUSES:=64
const PARTS:=16
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func membership(batch:Node)->Dictionary:
	var result:Dictionary={}
	for key:String in batch.groups:
		result[key]=[]
		for node:Node in batch.groups[key].members:result[key].append(str(node.name))
	return result
func settle_residency(map:Node3D,at:Vector3,budget:int)->bool:
	var deadline:=Time.get_ticks_usec()+60000000
	while Time.get_ticks_usec()<deadline:
		Stream.sync(map,map,at,budget)
		var batch:Node=map.get_node("GroundRenderBatches")
		if map.has_meta("stream_chunk") and map.get_meta("stream_chunk")==Stream.chunk_key(at) and batch._preparation.is_empty() and batch.pending.is_empty() and batch._workers.is_empty():return true
		await process_frame
	return false
func run()->void:
	var output:="";var progressive:=false;var closed:=false;var source_budget:=Stream.FRAME_BUDGET;var closed_first:=false;var early:=false;var exercise_return:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--legacy-progressive":progressive=true
		elif arg=="--closed-buildings":closed=true
		elif arg=="--closed-first":closed_first=true
		elif arg=="--early-arrivals":early=true
		elif arg=="--exercise-return":exercise_return=true
		elif arg.begins_with("--source-budget="):source_budget=clampi(arg.trim_prefix("--source-budget=").to_int(),1,Stream.FRAME_BUDGET)
	if output.is_empty() or FileAccess.file_exists(output) or DisplayServer.get_name()=="headless":
		push_error("Require a new external output path and private GPU desktop");quit(2);return
	Stream.progressive_white_batches_enabled=progressive
	Stream.closed_building_arrivals_enabled=early
	Batch.closed_building_preparation_enabled=closed
	# The native geometry path is also used by the current map-texture stage.
	# Keep actual textures here; do not whiten the material to satisfy the gate.
	Controls.native_geometry_only=true
	Engine.max_fps=60;root.size=Vector2i(640,480)
	DisplayState.set_vsync_mode(DisplayServer.VSYNC_DISABLED,root.get_window_id())
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(7,12,18);camera.look_at(Vector3(4,0,4));camera.current=true
	var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color(.4,.2,.1))
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_texture=ImageTexture.create_from_image(image)
	var box:=BoxMesh.new();box.size=Vector3(.2,.2,.2);box.material=material
	var cpu:Mesh=Cpu.capture(box);var original:=var_to_bytes(cpu.surfaces)
	var library:Array=[]
	# Each arrival wave adds one part to every house. A size/time checkpoint
	# cannot prove any house complete until its last member actually arrives.
	for part:int in PARTS:
		for house:int in HOUSES:
			var id:="house_%03d_part_%03d"%[house,part]
			var at:=Vector3((house%8)*1.1+(part%4)*.22,0,(house/8)*1.1+(part/4)*.22)
			var record:Dictionary={"uuid":id,"kind":"box","collision":"none","size":[.2,.2,.2],"position":[at.x,0,at.z],"rotation":[0,0,0],"building":{"id":"house_%03d"%house,"floor":0,"part":id,"role":"wall"}}
			library.append({"uuid":id,"position":at,"rotation":Vector3.ZERO,"transform":Transform3D(Basis.IDENTITY,at),"chunk":Stream.chunk_key(at),"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"mesh":cpu,"material_override":null,"surface_overrides":[],"cast_shadow":GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"extras":{"rmmo_collision":"none","building":record.building},"ground_batch_record":record})
	if closed_first:library.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.uuid<b.uuid)
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",library)
	var indexed:=Index.build(library)
	for key:String in indexed:map.set_meta(key,indexed[key])
	var started:=Time.get_ticks_usec();var deadline:=started+60000000
	var rows:Array=[];var peak_early_batched:=0;var early_prepared:=0;var batch:Node
	while Time.get_ticks_usec()<deadline:
		Stream.sync(map,map,Vector3(4,0,4),source_budget)
		batch=map.get_node_or_null("GroundRenderBatches")
		var pending:int=map.get_meta("stream_jobs",[]).size()-int(map.get_meta("stream_cursor",0))
		if batch!=null:
			var stats:Dictionary=batch.stats()
			if pending>0:peak_early_batched=maxi(peak_early_batched,int(stats.source_objects))
			if batch.prepared_source_visits<HOUSES*PARTS:early_prepared=maxi(early_prepared,int(stats.source_objects))
			rows.append({"at_us":Time.get_ticks_usec()-started,"pending_sources":pending,"batched":stats.source_objects,"groups":stats.groups,"builds":stats.rebuild_count,"prepare":batch._preparation.get("phase",""),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
			if map.has_meta("stream_chunk") and batch._preparation.is_empty() and batch.pending.is_empty() and batch._workers.is_empty():break
		await process_frame
	check(batch!=null and map.has_meta("stream_chunk") and batch._preparation.is_empty() and batch.pending.is_empty() and batch._workers.is_empty(),"source and batch queues drain within deadline")
	if batch==null:quit(1);return
	var measured:Dictionary=batch.stats();var elapsed:=Time.get_ticks_usec()-started
	check(measured.source_objects==HOUSES*PARTS and measured.groups==HOUSES,"all textured house parts are represented exactly once in final groups")
	check(peak_early_batched>0 if progressive or early else peak_early_batched==0,"complete arrival/control exposes early groups or the global source barrier")
	if closed:
		check(early_prepared>0,"complete textured houses render while other houses are still being prepared")
		check(measured.rebuild_count==HOUSES and batch.prepared_source_visits==HOUSES*PARTS and batch.packed_source_visits==HOUSES*PARTS,"closed unit pipeline adds no descriptor, packing or partial mesh builds")
	var expected:=membership(batch)
	batch.sync(map.get_meta("stream_meshes").values());batch.flush()
	check(expected==membership(batch),"final membership and ordering equal full synchronous reconciliation")
	check(original==var_to_bytes(cpu.surfaces) and material.albedo_texture!=null,"source arrays and textured material preserved")
	check(batch.live_worker_joins==0,"interactive path never joins a live geometry worker")
	var arrival_profile:Dictionary=map.get_meta(Stream.BATCH_ARRIVALS).profile.duplicate() if map.has_meta(Stream.BATCH_ARRIVALS) else {}
	var return_work:Dictionary={}
	if exercise_return:
		check(await settle_residency(map,Vector3(8192,0,8192),source_budget),"real stream departure drains source and batch queues")
		check(map.get_meta("stream_meshes").is_empty() and batch.groups.is_empty(),"departure removes every source and render group")
		if early:
			var ledger:RefCounted=map.get_meta(Stream.BATCH_ARRIVALS)
			check(not ledger.needs_full and ledger.roots.is_empty() and ledger.unsubmitted.is_empty(),"completed departure clears the arrival prefix without retaining stale nodes")
		var before_return:Dictionary=batch.stats()
		check(await settle_residency(map,Vector3(4,0,4),source_budget),"same UUIDs return through the actual residency path")
		check(membership(batch)==expected,"returned new nodes preserve exact grouping and member order")
		for key:String in ["rebuild_count","prepared_source_visits","packed_source_visits"]:return_work[key]=int(batch.stats()[key])-int(before_return[key])
		if early and closed:check(return_work.rebuild_count==HOUSES and return_work.prepared_source_visits==HOUSES*PARTS and return_work.packed_source_visits==HOUSES*PARTS,"return adds exactly one build per group and one prepare/pack per source")
		check(original==var_to_bytes(cpu.surfaces) and material.albedo_texture!=null and batch.live_worker_joins==0,"unload/return preserves textured source data without live worker joins")
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"legacy_progressive":progressive,"closed_buildings":closed,"early_arrivals":early,"arrival_profile":arrival_profile,"return_work":return_work,"source_budget":source_budget,"closed_first":closed_first,"us":elapsed,"early_batched":peak_early_batched,"early_prepared":early_prepared,"stats":measured,"rows":rows,"contract":"Independent source arrival workload, real production Stream/Batcher and GPU; capped 60 FPS with explicit source count control, not an axel_town speed claim. Stats captured before full-reconcile oracle; optional unload/return counters are separate."},"\t"));file.close()
	batch.clear(false);map.free();camera.free();await process_frame
	print("STREAM_BATCH_COMPLETION ",JSON.stringify({"checks":checks,"failures":failures,"progressive":progressive,"builds":measured.rebuild_count,"early_batched":peak_early_batched,"us":elapsed}))
	quit(1 if failures else 0)
