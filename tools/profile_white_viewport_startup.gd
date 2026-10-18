extends SceneTree
## Empty-world control: separates first 3D renderer work from map work.
var spans:Array=[]
var before:=0
var began:=0
var output:=""
var with_mesh:=false
func _initialize()->void:run.call_deferred()
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--mesh":with_mesh=true
	if output.is_empty() or not preload("res://scripts/world3d/map_paths.gd").allowed(output,"D:/code/rmmo_runtime/review_artifacts"):quit(2);return
	Engine.max_fps=60;root.size=Vector2i(1440,900)
	root.content_scale_size=root.size;root.debug_draw=Viewport.DEBUG_DRAW_UNSHADED
	RenderingServer.frame_pre_draw.connect(func():before=Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func():spans.append((Time.get_ticks_usec()-before)/1000.))
	began=Time.get_ticks_usec()
	var host:=Node3D.new();root.add_child(host)
	var camera:=Camera3D.new();host.add_child(camera);camera.current=true
	if with_mesh:
		var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.position.z=-3
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override=material;host.add_child(mesh)
	await create_timer(4.).timeout
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"no map, images or gameplay", "box_meshes":1 if with_mesh else 0,"wall_ms":(Time.get_ticks_usec()-began)/1000.,"render_spans_ms":spans,"max_render_span_ms":spans.max(),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)},"\t"));file.close()
	print("EMPTY_WHITE_VIEWPORT max_render_span_ms=",spans.max())
	quit()
