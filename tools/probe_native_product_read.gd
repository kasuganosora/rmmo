extends SceneTree
## Exact initial native-reader isolation; optional external gate is diagnostic only.
const ROOT="D:/code/rmmo_runtime"
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Reader=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
var phase:="setup"
var frames:Array=[]
var previous_frame:=0
func _initialize()->void:run.call_deferred()
func observe()->void:
	var now:=Time.get_ticks_usec()
	if previous_frame>0:frames.append({"phase":phase,"us":now-previous_frame})
	previous_frame=now
func pipelines()->Dictionary:
	var result:Dictionary={}
	for pair:Array in [["canvas",RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS],["mesh",RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH],["surface",RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE],["draw",RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW],["specialization",RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]]:
		result[pair[0]]=RenderingServer.get_rendering_info(pair[1])
	return result
func product_owner(packet:Dictionary)->WeakRef:
	return weakref(packet.get("packed"))
func inventory(packet:Dictionary)->Dictionary:
	var packed:PackedScene=packet.packed
	var capture_stats:Dictionary={}
	var pending:Array=[packed];var states:Dictionary={};var meshes:Dictionary={};var materials:Dictionary={};var shaders:Dictionary={};var nodes:=0;var surfaces:=0
	while not pending.is_empty():
		var current:PackedScene=pending.pop_back()
		if states.has(current.get_instance_id()):continue
		states[current.get_instance_id()]=true
		var state:=current.get_state();nodes+=state.get_node_count()
		for at:int in state.get_node_count():
			var child:PackedScene=state.get_node_instance(at)
			if child!=null:pending.append(child)
			for slot:int in state.get_node_property_count(at):
				if state.get_node_property_name(at,slot)!=&"mesh":continue
				var mesh:Mesh=state.get_node_property_value(at,slot)
				if mesh==null or meshes.has(mesh.get_instance_id()):continue
				meshes[mesh.get_instance_id()]=true
				if capture_stats.is_empty() and mesh.has_meta(&"_rmmo_native_cpu_hint"):
					var hint:Resource=mesh.get_meta(&"_rmmo_native_cpu_hint")
					if hint.capture!=null:capture_stats=hint.capture.get_statistics()
				for surface:int in mesh.get_surface_count():
					surfaces+=1
					var material:Material=mesh.surface_get_material(surface)
					if material==null or materials.has(material.get_instance_id()):continue
					materials[material.get_instance_id()]=true
					# These surface materials were already bound by _set_surfaces.
					# Do not inspect unrelated node overrides that could be lazy.
					shaders[material.get_shader_rid().get_id()]=true
	return {"scene_states":states.size(),"nodes":nodes,"unique_meshes":meshes.size(),"surface_slots":surfaces,"surface_material_owners":materials.size(),"surface_shader_rids":shaders.size(),"native_capture":capture_stats}
func draw_frame()->void:
	await process_frame;await RenderingServer.frame_post_draw
func show_product(packet:Dictionary)->Dictionary:
	var display_began:=Time.get_ticks_usec()
	var began:=display_began;var model:Node3D=packet.packed.instantiate()
	var instantiated:=Time.get_ticks_usec()-began
	var bounds:=AABB();var first:=true;var pending:Array=[model]
	while not pending.is_empty():
		var node:Node=pending.pop_back();pending.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh!=null:
			var transform:Transform3D=node.transform;var parent:=node.get_parent()
			while parent is Node3D:transform=parent.transform*transform;parent=parent.get_parent()
			var box:AABB=transform*node.mesh.get_aabb()
			bounds=box if first else bounds.merge(box);first=false
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.02,.02,.02)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;stage.add_child(environment)
	var camera:=Camera3D.new();stage.add_child(camera);camera.current=true
	var center:=bounds.get_center();var extent:=maxf(bounds.size.length(),1.)
	camera.position=center+Vector3(.65,.45,.85)*extent;camera.look_at(center)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);stage.add_child(light)
	await draw_frame();var background:=root.get_texture().get_image().get_data()
	began=Time.get_ticks_usec();stage.add_child(model);var attached:=Time.get_ticks_usec()-began
	phase="first_draw";began=Time.get_ticks_usec();await draw_frame();var first_draw:=Time.get_ticks_usec()-began
	var display_ready:=Time.get_ticks_usec()-display_began
	var first_image:=root.get_texture().get_image().get_data()
	phase="settle_draw";began=Time.get_ticks_usec()
	for at:int in 12:await draw_frame()
	var settle:=Time.get_ticks_usec()-began;var final_image:=root.get_texture().get_image().get_data()
	phase="remove_visible";began=Time.get_ticks_usec();stage.free();var removed:=Time.get_ticks_usec()-began
	return {"instantiate_us":instantiated,"attach_us":attached,"first_draw_us":first_draw,"complete_to_first_draw_us":display_ready,"settle_12_draw_us":settle,"remove_nodes_us":removed,"first_nonblank":first_image!=background,"settled_nonblank":final_image!=background,"first_matches_settled":first_image==final_image,"bounds":bounds}
func run()->void:
	var output:="";var gate:="";var draw:=false;var inspect_inventory:=false;var capture_cpu:=true
	var path:=ROOT+"/packs/default/assets/7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9).replace("\\","/")
		elif arg.begins_with("--gate="):gate=arg.substr(7).replace("\\","/")
		elif arg=="--draw":draw=true
		elif arg=="--inventory":inspect_inventory=true
		elif arg=="--without-cpu-capture":capture_cpu=false
	if not output.begins_with(ROOT+"/review_artifacts/") or (not gate.is_empty() and not gate.begins_with(ROOT+"/review_artifacts/")):quit(2);return
	if DisplayServer.get_name()=="headless":quit(2);return
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size=Vector2i(512,512);root.use_taa=false
	process_frame.connect(observe)
	var candidate:=Assets.native_candidate(path,ROOT)
	if candidate.is_empty():print("FAIL missing exact native product");quit(1);return
	if not gate.is_empty():
		FileAccess.open(gate+".ready",FileAccess.WRITE).store_string(str(OS.get_process_id()))
		var limit:=Time.get_ticks_msec()+120000
		while not FileAccess.file_exists(gate) and Time.get_ticks_msec()<limit:await process_frame
		if not FileAccess.file_exists(gate):print("FAIL diagnostic gate timeout");quit(1);return
	Trace.minimum_event_us=0;Trace.start();phase="native_read"
	var pipelines_before:=pipelines()
	var began:=Time.get_ticks_usec();var thread:=Thread.new()
	var code:=thread.start(Reader.read.bind(path,candidate,ROOT,Callable(),true,false,"",true,capture_cpu))
	if code!=OK:print("FAIL native reader thread");quit(1);return
	while thread.is_alive():await process_frame
	var result:Dictionary=thread.wait_to_finish();var elapsed:=Time.get_ticks_usec()-began
	if not gate.is_empty():FileAccess.open(gate+".done",FileAccess.WRITE).store_string(str(elapsed))
	phase="join_sync";began=Time.get_ticks_usec()
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	var synchronized:=Time.get_ticks_usec()-began
	var okay:bool=result.get("error",FAILED)==OK and result.get("packed") is PackedScene
	var owner:WeakRef=product_owner(result) if okay else null
	var report:={"ok":okay,"candidate":candidate,"elapsed_us":elapsed,"cache_us":result.get("cache_us",0),"join_sync_us":synchronized,"gated_diagnostic":not gate.is_empty(),"async_pipelines":OS.get_environment("RMMO_ASYNC_MESH_PIPELINES")=="1","batch_pipelines":OS.get_environment("RMMO_BATCH_MESH_PIPELINES")=="1","pipelines_before":pipelines_before,"pipelines_after_read":pipelines()}
	report.capture_cpu=capture_cpu;report.pipeline_batch=result.get("native_pipeline_batch",{})
	report.native_cpu_hint_meshes=result.get("native_cpu_hint_meshes",0)
	if okay:
		if draw:
			report.draw=await show_product(result)
			okay=okay and report.draw.first_nonblank and report.draw.settled_nonblank
		# Resource inspection is an explicit diagnostic. It must not give pending
		# compilation extra time before the measured first draw or cancellation.
		if inspect_inventory:
			phase="inventory";began=Time.get_ticks_usec();report.inventory=inventory(result);report.inventory_us=Time.get_ticks_usec()-began
			report.pipelines_after_inventory=pipelines()
	phase="release_product";began=Time.get_ticks_usec();result.clear();report.release_product_us=Time.get_ticks_usec()-began
	report.owner_freed=owner==null or owner.get_ref()==null
	okay=okay and report.owner_freed
	phase="after_release"
	for at:int in 3:await draw_frame()
	report.ok=okay;report.pipelines_after_release=pipelines();report.frames=frames;report.trace=Trace.stop()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PASS " if okay else "FAIL ","NATIVE_PRODUCT_READ ",elapsed)
	quit(0 if okay else 1)
