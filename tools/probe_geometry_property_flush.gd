extends SceneTree
## Reproduce unrelated shader compilation forced by a geometry property query.
## These deliberately fresh shaders are diagnostic workload, not map timings.
var output:=""
var checks:=0
var failures:Array=[]
var rows:Array=[]
var retained:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func names(node:Node)->Array:
	var result:Array=[]
	for property:Dictionary in node.get_property_list():
		if str(property.name).begins_with("instance_shader_parameters/"):result.append(str(property.name))
	return result
func shader_material(uniform_name:String,value:float)->ShaderMaterial:
	var shader:=Shader.new()
	shader.code="shader_type spatial; render_mode unshaded; instance uniform float "+uniform_name+" = "+str(value)+"; void fragment(){ ALBEDO=vec3("+uniform_name+"); }"
	var material:=ShaderMaterial.new();material.shader=shader
	return material
func contract()->void:
	var node:=MeshInstance3D.new();node.name="subject";node.mesh=BoxMesh.new()
	var surface:=shader_material("surface_gain",.25)
	node.mesh.material=surface
	check(names(node).has("instance_shader_parameters/surface_gain"),"surface uniform appears before any rendered frame")
	check(is_equal_approx(float(node.property_get_revert("instance_shader_parameters/surface_gain")),.25),"surface uniform default is current")
	node.set_instance_shader_parameter(&"surface_gain",.6)
	var packed:=PackedScene.new();check(packed.pack(node)==OK,"pack current instance shader value")
	var copy:MeshInstance3D=packed.instantiate()
	check(is_equal_approx(float(copy.get_instance_shader_parameter(&"surface_gain")),.6),"packed value survives instantiate")
	copy.free();packed=null
	var override:=shader_material("override_gain",.4);node.material_override=override
	var parameters:=names(node)
	check(parameters.has("instance_shader_parameters/override_gain") and not parameters.has("instance_shader_parameters/surface_gain"),"material override changes the property set immediately")
	check(is_equal_approx(float(node.property_get_revert("instance_shader_parameters/override_gain")),.4),"override default updates before drawing")
	var overlay:=shader_material("overlay_gain",.7);node.material_overlay=overlay
	parameters=names(node)
	check(parameters.has("instance_shader_parameters/override_gain") and parameters.has("instance_shader_parameters/overlay_gain"),"overlay contributes its current uniform")
	override.next_pass=shader_material("next_gain",.8)
	check(names(node).has("instance_shader_parameters/next_gain"),"next pass contributes its current uniform")
	var replacement:=shader_material("replacement_gain",.3);override.shader=replacement.shader
	parameters=names(node)
	check(parameters.has("instance_shader_parameters/replacement_gain") and not parameters.has("instance_shader_parameters/override_gain"),"shader replacement invalidates old property names")
	node.material_override=null;node.material_overlay=null
	check(names(node).has("instance_shader_parameters/surface_gain"),"clearing overrides restores surface uniforms")
	node.mesh=BoxMesh.new()
	check(names(node).is_empty(),"replacing with an unmaterialed mesh removes previous uniforms")
	node.free()
	var multi:=MultiMeshInstance3D.new();multi.multimesh=MultiMesh.new()
	multi.multimesh.transform_format=MultiMesh.TRANSFORM_3D;multi.multimesh.mesh=BoxMesh.new()
	multi.multimesh.mesh.material=surface;multi.multimesh.instance_count=1
	check(names(multi).has("instance_shader_parameters/surface_gain"),"multimesh reads its current mesh material")
	multi.multimesh.mesh=BoxMesh.new()
	check(names(multi).is_empty(),"multimesh mesh change removes old uniforms")
	multi.free()
	var particles:=GPUParticles3D.new();particles.emitting=false
	var particle_mesh:=BoxMesh.new();particle_mesh.material=surface
	particles.draw_passes=1;particles.draw_pass_1=particle_mesh
	check(names(particles).has("instance_shader_parameters/surface_gain"),"particles read their draw-pass material")
	particles.draw_pass_1=BoxMesh.new()
	check(names(particles).is_empty(),"particle draw-pass change removes old uniforms")
	particles.free()
func visible_contract()->void:
	root.size=Vector2i(128,128);root.use_taa=false;root.msaa_3d=Viewport.MSAA_DISABLED
	var source:=MeshInstance3D.new();source.mesh=BoxMesh.new();source.mesh.material=shader_material("visible_gain",.2)
	source.set_instance_shader_parameter(&"visible_gain",.8)
	var packed:=PackedScene.new();check(packed.pack(source)==OK,"pack visible parameter before any draw");source.free()
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK;stage.add_child(environment)
	var camera:=Camera3D.new();camera.position=Vector3(0,0,3);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.;stage.add_child(camera);camera.current=true
	var visual:MeshInstance3D=packed.instantiate();stage.add_child(visual)
	await process_frame;await RenderingServer.frame_post_draw
	var first:=root.get_texture().get_image().get_pixel(64,64)
	await process_frame;await RenderingServer.frame_post_draw
	var settled:=root.get_texture().get_image().get_pixel(64,64)
	check(first.is_equal_approx(settled) and first.r>.7,"first visible pixels use the packed instance parameter")
	visual.set_instance_shader_parameter(&"visible_gain",.15)
	await process_frame;await RenderingServer.frame_post_draw
	var changed:=root.get_texture().get_image().get_pixel(64,64)
	check(changed.r<first.r-.2,"renderer publishes a subsequent instance parameter change")
	stage.free();packed=null
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/") or DisplayServer.get_name()=="headless":quit(2);return
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	contract()
	await visible_contract()
	for i:int in 12:await process_frame
	var code:=FileAccess.get_file_as_string("res://scripts/world3d/river_terrain.gdshader")
	for operation:String in ["node_properties","mesh_properties","mesh_pack"]:
		var subject:Node=Node3D.new() if operation=="node_properties" else MeshInstance3D.new()
		var packed:=PackedScene.new()
		var create_began:=Time.get_ticks_usec()
		for variant:int in 3:
			var shader:=Shader.new()
			var changed:=code.replace("void vertex() {","void vertex() { VERTEX.x += "+str((Time.get_ticks_usec()%1000000+variant)*.000000001)+";")
			check(changed!=code,"fresh unrelated shader variant is actually different")
			shader.code=changed
			var material:=ShaderMaterial.new();material.shader=shader
			check(material.get_rid().is_valid(),"unrelated material queued")
			retained.append([material,shader])
		var began:=Time.get_ticks_usec()
		if operation=="mesh_pack":check(packed.pack(subject)==OK,"empty mesh scene packs while unrelated shaders are pending")
		else:check(not subject.get_property_list().is_empty(),"subject property query completes")
		var finished:=Time.get_ticks_usec()
		RenderingServer.force_draw(false)
		var drained:=Time.get_ticks_usec()
		rows.append({"operation":operation,"queued_materials":3,"create_us":began-create_began,"query_us":finished-began,"next_draw_us":drained-finished,"total_us":drained-create_began})
		subject.free();packed=null;retained.clear()
		for i:int in 12:await process_frame
	var report:={"checks":checks,"failures":failures,"rows":rows,"diagnostic":true,"normal_performance_sample":false,"targeted_query":OS.get_environment("RMMO_TARGETED_INSTANCE_PROPERTY_QUERY")=="1"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("GEOMETRY_PROPERTY_FLUSH ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
