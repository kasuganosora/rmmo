extends SceneTree
## Attribute private VisualInstance destruction separately from pending shader work.
## Fresh shader variants deliberately defeat warm shader reuse; diagnostic only.
var output:=""
var diagnostic:=false
var rows:Array=[]
var retained:Array=[]
func _initialize()->void:run.call_deferred()
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
		elif arg=="--gdb-wait":diagnostic=true
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/"):quit(2);return
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in 120:await process_frame
	var code:=FileAccess.get_file_as_string("res://scripts/world3d/river_terrain.gdshader")
	if diagnostic:
		# Let the external sampler load symbols before entering this short probe.
		await create_timer(30.).timeout
		FileAccess.open(output.get_base_dir().path_join("phase.log"),FileAccess.WRITE).store_line("WHITE_TRAVERSAL private_release")
	for trial in (32 if diagnostic else 4):
		var visual:bool=trial%2==1
		var private:Node=MeshInstance3D.new() if visual else Node3D.new()
		var variant:=code.replace("void vertex() {","void vertex() { VERTEX.x += "+str((Time.get_ticks_usec()%1000000+trial)*0.000000001)+";")
		var began:=Time.get_ticks_usec()
		var shader:=Shader.new();shader.code=variant
		var material:=ShaderMaterial.new();material.shader=shader
		var rid:=material.get_rid()
		var created:=Time.get_ticks_usec()
		private.free()
		var released:=Time.get_ticks_usec()
		# Charge all deferred work too: deferring the queue drain is not speedup.
		RenderingServer.force_draw(false)
		var drained:=Time.get_ticks_usec()
		retained.append([material,shader])
		rows.append({"trial":trial,"visual":visual,"material_rid_valid":rid.is_valid(),"create_us":created-began,"release_us":released-created,"next_draw_us":drained-released,"combined_us":drained-began,"shader_sha":variant.sha256_text()})
		for i in 12:await process_frame
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"diagnostic":true,"normal_performance_sample":false},"\t"))
	print("PRIVATE_INSTANCE_RELEASE ",JSON.stringify(rows))
	retained.clear();await process_frame;quit()
