extends SceneTree

# Engine regression: a coarse alpha mip must be able to request its finer mip
# even when every coarse texel fails the built-in alpha-scissor test. The
# occluder case also checks that relaxing the prepass EQUAL test remains safe.
var failed:=0
var observed:Dictionary={}
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failed+=1
func observation(value:Dictionary)->void:observed=value
func _initialize()->void:call_deferred("run")
func argument(prefix:String)->String:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):return arg.substr(prefix.length())
	return ""
func native_texture(path:String)->Texture2D:
	var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D")
	check(texture.call("load",path)==OK,"load fresh native texture owner")
	return texture
func quad(view:SubViewport,texture:Texture2D,z:float,size:float)->void:
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	if texture!=null:
		material.albedo_texture=texture
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold=.5
		material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:material.albedo_color=Color(.1,.2,.8)
	var mesh:=QuadMesh.new();mesh.size=Vector2.ONE*size;mesh.material=material
	var node:=MeshInstance3D.new();node.mesh=mesh;node.position.z=z;view.add_child(node)
func view_for(texture:Texture2D,occluded:bool)->SubViewport:
	var view:=SubViewport.new();view.size=Vector2i(384,384);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.05,.05,.05);view.add_child(environment)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2.2;camera.position=Vector3(0,0,5);view.add_child(camera)
	quad(view,null,.5 if occluded else -.5,3.)
	quad(view,texture,0.,2.)
	return view
func pixel_counts(image:Image)->Dictionary:
	var green:=0;var blue:=0
	for y:int in image.get_height():
		for x:int in image.get_width():
			var p:=image.get_pixel(x,y)
			green+=int(p.g>p.r*1.5 and p.g>p.b*1.5)
			blue+=int(p.b>p.r*1.5 and p.b>p.g*1.5)
	return {"green":green,"blue":blue}
func run()->void:
	create_timer(60).timeout.connect(func():quit(2));Engine.max_fps=60
	var path:=argument("--texture=");var output:=argument("--output=")
	check(not path.is_empty() and not output.is_empty(),"explicit external fixture and evidence directory")
	if failed:quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	var visible:=native_texture(path);var hidden:=native_texture(path)
	var reference:=ImageTexture.create_from_image(visible.get_image())
	var views:Array[SubViewport]=[view_for(visible,false),view_for(hidden,true),view_for(reference,false)]
	var streaming:Object=Engine.get_singleton("TextureStreaming")
	var ticket:=int(streaming.call("begin_texture_observation",[visible,hidden]))
	for _frame:int in 120:await process_frame
	streaming.call("query_texture_observation",ticket,Callable(self,"observation"))
	var deadline:=Time.get_ticks_msec()+3000
	while observed.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	var startup_observation:=observed
	streaming.call("cancel_texture_observation",ticket)
	# Each observation records one exact buffer period. The initial period can
	# precede shader readiness; query a second period after actual drawing starts.
	observed={};ticket=int(streaming.call("begin_texture_observation",[visible,hidden]))
	for _frame:int in 20:await process_frame
	streaming.call("query_texture_observation",ticket,Callable(self,"observation"))
	deadline=Time.get_ticks_msec()+3000
	while observed.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(observed.get("covered",false),"feedback observation completed")
	var visible_row:Dictionary={};var hidden_row:Dictionary={}
	for row:Dictionary in observed.get("textures",[]):
		if row.texture_id==visible.get_instance_id():visible_row=row
		if row.texture_id==hidden.get_instance_id():hidden_row=row
	check(visible_row.get("visible_demand",false) and int(visible_row.get("current_mip",99))==0,"visible cutout requests and reaches mip zero")
	var prepass:bool=ProjectSettings.get_setting("rendering/driver/depth_prepass/enable",true)
	if prepass:
		check(not hidden_row.get("visible_demand",true) and int(hidden_row.get("current_mip",-1))>0,"depth prepass prevents hidden cutout feedback")
	else:
		# Without prepass, alpha discard requires late depth testing. Fragment
		# atomics may run for subsequently occluded samples; verify pixels below.
		check(hidden_row.get("valid",false),"late-depth cutout retains a valid texture owner")
	await RenderingServer.frame_post_draw
	var combined:=Image.create(1152,384,false,Image.FORMAT_RGBA8)
	var counts:Array=[]
	for index:int in views.size():
		var capture:=views[index].get_texture().get_image();capture.convert(Image.FORMAT_RGBA8)
		counts.append(pixel_counts(capture));combined.blit_rect(capture,Rect2i(0,0,384,384),Vector2i(index*384,0))
	check(counts[2].green>100 and counts[2].blue>100,"full resident reference contains leaves and transparent holes")
	check(counts[0].green>=counts[2].green*.97 and abs(counts[0].blue-counts[2].blue)<=500,"streamed cutout matches full resident silhouette and holes")
	check(counts[1].green==0 and counts[1].blue==384*384,"foreground occluder remains completely opaque")
	check(combined.save_png(output.path_join("cutout_feedback.png"))==OK,"capture visible, occluded, reference panels")
	var report:={"failed":failed,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"depth_prepass":prepass,"visible_id":visible.get_instance_id(),"hidden_id":hidden.get_instance_id(),"startup_observation":startup_observation,"observation":observed,"counts":counts}
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("CUTOUT_FEEDBACK_RESULT ",JSON.stringify(report))
	streaming.call("cancel_texture_observation",ticket)
	for view:SubViewport in views:view.queue_free()
	await process_frame;await process_frame
	quit(1 if failed else 0)
