extends SceneTree
## New-process proof: custom override is loaded before rendering starts.
func _initialize()->void:run.call_deferred()
func run()->void:
	var expected:=false;var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--enabled":expected=true
		if arg.begins_with("--image="):output=arg.trim_prefix("--image=")
	var contact:bool=ProjectSettings.get_setting("rendering/lights_and_shadows/contact_shadow/enabled",false)
	var ao:bool=ProjectSettings.get_setting("rendering/lights_and_shadows/multi_bounce_occlusion/enabled",false)
	print("RENDERING_STARTUP ",JSON.stringify({"contact_shadows":contact,"multi_bounce_ao":ao,"expected":expected,"renderer":RenderingServer.get_current_rendering_method(),"override":ProjectSettings.get_setting("application/config/project_settings_override"),"content_root":ProjectSettings.get_setting("rmmo/content_root")}))
	if contact!=expected or ao!=expected:push_error("startup settings mismatch");quit(1);return
	if output.is_empty():quit(0);return
	var scene:=Node3D.new();root.add_child(scene)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();scene.add_child(environment)
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.08,.08,.08)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=1.0
	var shader:=Shader.new();shader.code="shader_type spatial; void fragment(){ALBEDO=vec3(0.8,0.12,0.03); ROUGHNESS=0.9; AO=0.15;}"
	var material:=ShaderMaterial.new();material.shader=shader
	for i:int in 3:
		var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(1.0,1.0+i*.5,1.0);mesh.mesh=box;mesh.material_override=material;mesh.position=Vector3(i*1.5-1.5,box.size.y/2,0);scene.add_child(mesh)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(20,20);floor.mesh=plane;scene.add_child(floor)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=.6;light.shadow_enabled=true;scene.add_child(light)
	var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(5,4,7);camera.look_at(Vector3(0,.6,0));camera.current=true
	for i:int in 45:await process_frame
	await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png(output)
	print("RENDERING_STARTUP_IMAGE ",output," error=",error)
	quit(0 if error==OK else 1)
