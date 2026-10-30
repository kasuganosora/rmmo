extends SceneTree
## Diagnostic: the real prepared-surface API and terrain shader, with private
## mesh/material owners. No production switch or hidden-mesh warmup.
var output:=""
var sequence:=0
var rows:Array=[]
var frame_times:Array=[]
var phase:="settle"
var last:=0
var failures:Array=[]
var keep:Array=[]
func _initialize()->void:run.call_deferred()
func observe()->void:
	var now:=Time.get_ticks_usec()
	if last>0:frame_times.append({"phase":phase,"at_us":now,"us":now-last})
	last=now
func make_mesh(packed:Dictionary,code:String)->Dictionary:
	var began:=Time.get_ticks_usec()
	var shader:=Shader.new();shader.code=code
	var material:=ShaderMaterial.new();material.shader=shader
	var material_done:=Time.get_ticks_usec()
	var surface:=packed.duplicate();surface.material=material
	var mesh:=ArrayMesh.new();mesh.set("_surfaces",[surface])
	return {"mesh":mesh,"material":material,"shader":shader,"create_material_us":material_done-began,"submit_us":Time.get_ticks_usec()-material_done,"total_us":Time.get_ticks_usec()-began,"thread":OS.get_thread_caller_id()}
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/"):quit(2);return
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var stage:=Node3D.new();root.add_child(stage)
	var camera:=Camera3D.new();camera.position=Vector3(0,2,5);stage.add_child(camera);camera.look_at(Vector3.ZERO);camera.current=true
	var light:=DirectionalLight3D.new();stage.add_child(light)
	var source:=PlaneMesh.new();source.subdivide_width=32;source.subdivide_depth=32
	var arrays:=source.surface_get_arrays(0)
	var prepared:Dictionary=RenderingServer.call("mesh_prepare_surface_from_arrays",Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},0)
	var code:=FileAccess.get_file_as_string("res://scripts/world3d/river_terrain.gdshader")
	process_frame.connect(observe)
	for i in 120:await process_frame
	var diagnostic:bool="--gdb-wait" in OS.get_cmdline_user_args()
	if diagnostic:
		FileAccess.open(output.get_base_dir().path_join("phase.log"),FileAccess.WRITE).store_line("SHADER_PROBE_READY")
		await create_timer(5.).timeout
	for background:bool in ([true,true,true,true,true,true,true,true] if diagnostic else [false,true,true,false]):
		sequence+=1;phase=("worker_" if background else "main_")+str(sequence)
		# Keep SPIR-V identities distinct so a preceding trial cannot prepay the
		# following trial's first shader compilation. This is a diagnostic load,
		# not an exact-content A/B performance acceptance sample.
		var variant:=code.replace("void vertex() {","void vertex() { VERTEX.x += "+str((Time.get_ticks_usec()%100000+sequence)*0.000000001)+";")
		var started:=Time.get_ticks_usec();var result:Dictionary
		if background:
			var worker:=Thread.new()
			if worker.start(make_mesh.bind(prepared,variant))!=OK:failures.append("worker start");break
			while worker.is_alive():await process_frame
			result=worker.wait_to_finish()
		else:result=make_mesh(prepared,variant)
		var ready:=Time.get_ticks_usec()
		phase="install_"+str(sequence)
		var node:=MeshInstance3D.new();node.mesh=result.mesh;stage.add_child(node)
		var installed:=Time.get_ticks_usec()
		var row:={"sequence":sequence,"background":background,"started_us":started,"ready_us":ready,"installed_us":installed,"worker_wall_us":ready-started,"install_us":installed-ready,"submit_us":result.submit_us,"create_material_us":result.create_material_us,"thread":result.thread,"shader_sha":variant.sha256_text()}
		keep.append(result)
		for i in 12:await process_frame
		phase="validation_"+str(sequence)
		var validation_started:=Time.get_ticks_usec()
		if result.mesh.surface_get_material(0)!=result.material:failures.append("material identity")
		if var_to_bytes(result.mesh.surface_get_arrays(0))!=var_to_bytes(arrays):failures.append("geometry mismatch")
		row.validation_started_us=validation_started;row.validation_us=Time.get_ticks_usec()-validation_started
		rows.append(row)
		for i in 3:await process_frame
		node.free();phase="between"
		for i in 30:await process_frame
	process_frame.disconnect(observe)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"frames":frame_times,"failures":failures,"diagnostic":true,"normal_performance_sample":false},"\t"))
	print("SHADER_SUBMIT_DIAGNOSTIC ",JSON.stringify(rows)," failures=",failures)
	if diagnostic:await create_timer(15.).timeout
	stage.free();keep.clear();await process_frame;quit(0 if failures.is_empty() else 1)
