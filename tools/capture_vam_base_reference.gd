extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(600,800);root.content_scale_size=root.size
	var world:=WorldEnvironment.new();world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color("42474c")
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=.5;root.add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-30,0);root.add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.15;root.add_child(camera)
	for gender in ["female","male"]:
		var path:String=Art.path("characters/source_models/vam_base_reference/"+gender+"/base_original.glb")
		var state:=GLTFState.new();var doc:=GLTFDocument.new()
		if doc.append_from_file(path,state)!=OK:push_error("Cannot load extracted body");quit(1);return
		var model:Node3D=doc.generate_scene(state);root.add_child(model)
		var bounds:=AABB();var first:=true;var triangles:=0
		for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			bounds=mesh.get_aabb() if first else bounds.merge(mesh.get_aabb());first=false
			var mat:=StandardMaterial3D.new();mat.albedo_color=Color("bababa");mat.roughness=.7;mesh.material_override=mat
			for surface in mesh.mesh.get_surface_count():
				var arrays:Array=mesh.mesh.surface_get_arrays(surface)
				if arrays[Mesh.ARRAY_TEX_UV].size()!=arrays[Mesh.ARRAY_VERTEX].size():push_error("Missing UVs");quit(1);return
				triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
		if first or triangles!=42162 or bounds.size.y<1.5 or bounds.size.y>2.1:push_error("Unexpected body geometry");quit(1);return
		var center:Vector3=bounds.get_center()
		var sheet:=Image.create(1800,800,false,Image.FORMAT_RGB8)
		var views:Array[Vector3]=[Vector3(0,0,5),Vector3(5,0,0),Vector3(0,0,-5)]
		for index in 3:
			camera.position=center+views[index];camera.look_at(center)
			light.position=center+views[index]+Vector3(-2,3,0);light.look_at(center)
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			var picture:=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(picture,Rect2i(0,0,600,800),Vector2i(index*600,0))
		sheet.save_png(Art.review_path("character_3d/vam_"+gender+"_base.png"))
		print("PASS extracted ",gender," body: ",triangles," triangles, UVs present, bounds ",bounds)
		model.free()
	quit()
