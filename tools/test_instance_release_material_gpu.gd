extends SceneTree
## Dirty material updates must survive unrelated/private/shared-instance teardown
## and still reach the first rendered frame. Run in a private GPU desktop.
var output:=""
var shader_path:=""
var failures:Array=[]
var passes:=0
var samples:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passes+=1
	else:failures.append(label)
func draw_frame()->void:
	await process_frame
	await RenderingServer.frame_post_draw
func material(code:String,tint:Color)->ShaderMaterial:
	var shader:=Shader.new();shader.code=code
	var result:=ShaderMaterial.new();result.shader=shader
	result.set_shader_parameter("albedo",tint)
	result.set_shader_parameter("uv1_scale",Vector3.ONE)
	result.set_shader_parameter("roughness",1.)
	result.set_shader_parameter("specular",0.)
	result.set_shader_parameter("metallic",0.)
	var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
	result.set_shader_parameter("texture_albedo",ImageTexture.create_from_image(image))
	check(result.get_rid().is_valid(),"actual captured material owns a rendering RID")
	return result
func same_pixels(a:Image,b:Image)->bool:
	return a.get_size()==b.get_size() and a.get_format()==b.get_format() and a.get_data()==b.get_data()
func render_case(stage:Node3D,mesh:Mesh,code:String,pending:bool,sharing:bool,tint:Color)->Image:
	var owner:=material(code,Color.RED)
	var visible:=MeshInstance3D.new();visible.mesh=mesh;visible.material_override=owner;stage.add_child(visible)
	var temporary:=MeshInstance3D.new();temporary.mesh=mesh
	if sharing:temporary.material_override=owner
	owner.set_shader_parameter("albedo",tint)
	if not pending:await draw_frame()
	var began:=Time.get_ticks_usec();temporary.free()
	var release_us:=Time.get_ticks_usec()-began
	began=Time.get_ticks_usec();await draw_frame()
	var image:=root.get_texture().get_image()
	samples.append({"pending":pending,"shared":sharing,"release_us":release_us,"first_draw_us":Time.get_ticks_usec()-began})
	check(is_instance_valid(visible) and visible.material_override==owner,"surviving instance keeps its exact shared material")
	visible.free();owner=null;await draw_frame()
	return image
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9).replace("\\","/")
		elif arg.begins_with("--shader="):shader_path=arg.substr(9).replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/") or not shader_path.begins_with("D:/code/rmmo_runtime/review_artifacts/") or not FileAccess.file_exists(shader_path):quit(2);return
	check(DisplayServer.get_name()!="headless","real renderer")
	root.size=Vector2i(256,256);root.use_taa=false;Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.02,.02,.02)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=1.
	stage.add_child(environment)
	var camera:=Camera3D.new();camera.position=Vector3(0,0,3);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.;stage.add_child(camera);camera.current=true
	var code:=FileAccess.get_file_as_string(shader_path)
	var mesh:=BoxMesh.new();mesh.size=Vector3.ONE
	await draw_frame()
	var tint:=Color(.08,.7,.15)
	var reference:Image=await render_case(stage,mesh,code,false,false,tint)
	var center:=reference.get_pixel(reference.get_width()/2,reference.get_height()/2)
	check(center.g>center.r+.05 and center.g>center.b+.05,"reference is nonblank and displays requested green material")
	for sharing:bool in [false,true]:
		var image:Image=await render_case(stage,mesh,code,true,sharing,tint)
		check(same_pixels(reference,image),"first draw matches explicit material flush, shared="+str(sharing))
	# Release material and instance before a draw; the dirty queue must remove
	# its invalid entries rather than later touching a freed owner.
	for iteration:int in 12:
		var transient:=material(code,Color(.2,.3,.4))
		var temporary:=MeshInstance3D.new();temporary.mesh=mesh;temporary.material_override=transient
		transient.set_shader_parameter("albedo",Color.BLUE)
		temporary.free();transient=null
	await draw_frame()
	var after:Image=await render_case(stage,mesh,code,true,true,tint)
	check(same_pixels(reference,after),"pending-owner cancellation leaves later shared material rendering intact")
	stage.free();mesh=null;await draw_frame()
	var report:={"passes":passes,"failures":failures,"shader_sha":FileAccess.get_sha256(shader_path),"samples":samples,"engine":Engine.get_version_info()}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("INSTANCE_RELEASE_MATERIAL ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
