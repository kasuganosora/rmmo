extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const MV=preload("res://scripts/char/mv_generator.gd")
func _initialize()->void:call_deferred("run")
func chest_color(frame:Image)->Color:
	# Fixed orthographic framing: this patch is bare upper chest for both
	# reference bodies, away from the face atlas and base-clothing edges.
	var mean:=Vector3.ZERO
	for y in range(360,385):
		for x in range(280,320):
			var c:=frame.get_pixel(x,y);mean+=Vector3(c.r,c.g,c.b)
	mean/=1000.0
	return Color(mean.x,mean.y,mean.z)
func run()->void:
	root.size=Vector2i(600,800)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("899ba6")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("b8c2d1")
	environment.environment.ambient_light_energy=.42;root.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,32,0);light.light_energy=1.15;root.add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.3;root.add_child(camera)
	camera.position=Vector3(0,1.42,5);camera.look_at(Vector3(0,1.40,0))
	var palette:=MV.palette_for("skin")
	palette.sort_custom(func(a,b):return a.color.get_luminance()<b.color.get_luminance())
	assert(not palette.is_empty())
	var reference=Model.create("male",{},{});root.add_child(reference);reference.visible=false;reference.set_process(false)
	var reference_face=reference.gear.Body.filter(func(m):return m.name=="Face")[0]
	var measurements:Dictionary={}
	for gender in ["male","female"]:
		var model=Model.create(gender,{},{});root.add_child(model);model.set_process(false)
		var rig=model.rig
		var cases=[{}, {"skin_on":true,"skin_row":palette[0].index,"eye_color":"#5276a5"}, {"skin_on":true,"skin_row":palette[-1].index}, {}]
		for i in cases.size():
			model.configure(gender,cases[i],{})
			model.play("idle","front",true);model.pose_at(0)
			assert(model.rig==rig,"Skin edits must retain mesh/rig/expressions")
			var face=model.gear.Body.filter(func(m):return m.name=="Face")[0]
			var body=model.gear.Body.filter(func(m):return m.name=="Body")[0]
			var color=model._color(cases[i],"skin",Color("ffeadb"))
			assert(face.get_active_material(0).get_shader_parameter("skin_color")==color)
			assert(body.material_override.get_shader_parameter("skin_color")==color)
			assert(body.material_override.get_shader_parameter("skin_maps_enabled"),"Regenerated skin maps must actually be loaded")
			for map_name in ["skin_basecolor","skin_normal","skin_orm"]:
				var texture:Texture2D=body.material_override.get_shader_parameter(map_name)
				assert(texture!=null and texture.get_width()==2048 and texture.get_height()==2048)
			assert(body.mesh.get_meta("skin_detail_match_ratio",0)>.98,"Skin bake must match the actual runtime body")
			assert(face.mesh.get_blend_shape_count()==56,"57 Blender keys include the non-morph Basis")
			assert(reference_face.get_active_material(0).get_shader_parameter("skin_color")==Color("ffeadb"),"Characters must not recolour each other")
			for mesh in model.gear.Boots:
				if mesh.name=="MaidStockings":assert(mesh.material_override.get_shader_parameter("skin_color")==color)
			if DisplayServer.get_name()!="headless":
				var samples:Array[Color]=[]
				for lighting in 2:
					light.visible=lighting==0
					for frame in 3:await process_frame
					await RenderingServer.frame_post_draw
					var path=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/skin_%s_%d_%d.png"%[gender,i,lighting])
					var frame_image:=root.get_texture().get_image()
					frame_image.save_png(path);samples.append(chest_color(frame_image))
				measurements["%s_%d"%[gender,i]]={"day":samples[0].to_html(false),"ambient":samples[1].to_html(false)}
				if i==0 or i==3:
					if samples[1].get_luminance()/samples[0].get_luminance()<.68 or samples[1].get_luminance()<.60 or samples[0].r>.998:
						push_error("Default skin becomes grey in shade or clips in daylight: %s"%[samples]);quit(1);return
				elif i==1 and samples[0].get_luminance()>.65:
					push_error("Dark skin palette was washed out");quit(1);return
				light.visible=true
		model.free()
	reference.free();camera.free();light.free();environment.free()
	if not measurements.is_empty():
		var report=FileAccess.open(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/skin_measurements.json"),FileAccess.WRITE)
		report.store_string(JSON.stringify(measurements,"  "))
	print("PASS shared face/body skin, palette edits/reset, stockings, expressions, instance isolation")
	quit()
