extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(700,800);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
	# Material baseline stays static; joint validation has its own pose captures.
	studio.regional_preview=preload("res://scripts/char/character_regional_skin.gd").create_preview()
	if studio.regional_preview:studio.add_child(studio.regional_preview);studio.model.visible=false
	if studio.regional_preview==null:quit(1);return
	var materials:Dictionary={}
	var triangles:=0
	for mesh:MeshInstance3D in studio.regional_preview.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var arrays:Array=mesh.mesh.surface_get_arrays(surface)
			triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
			if arrays[Mesh.ARRAY_TEX_UV].size()!=arrays[Mesh.ARRAY_VERTEX].size():push_error("Missing display UV");quit(1);return
			var material:Material=mesh.get_surface_override_material(surface)
			if material is ShaderMaterial:materials[material.resource_name]=material
	if materials.size()!=3:push_error("Expected exactly three regional skin materials");quit(1);return
	if triangles!=168716 or root.msaa_3d!=Viewport.MSAA_8X:push_error("Expected subdivided review mesh and 8x MSAA");quit(1);return
	for material:ShaderMaterial in materials.values():
		for semantic in ["albedo","normal","gloss","specular"]:
			var texture:Texture2D=material.get_shader_parameter(semantic+"_map")
			if texture==null or texture.get_width()!=4096:push_error("Missing full-resolution map");quit(1);return
	var sheet:=Image.create(1400,800,false,Image.FORMAT_RGB8)
	for light_index in 2:
		if light_index==1:studio.toggle_lighting()
		for view in ["portrait","side","back","body"]:
			studio.regional_preview.rotation.y={"portrait":.12,"side":PI/2,"back":PI,"body":0.0}[view]
			studio.camera.size=.45 if view!="body" else 2.15
			studio.camera.position.y=1.60 if view!="body" else .9
			for frame in 8:await process_frame
			await RenderingServer.frame_post_draw
			var picture:=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8)
			picture.save_png(Art.review_path("character_3d/porcelain_%s_%s.png"%["studio" if light_index==0 else "game",view]))
			if view=="portrait":sheet.blit_rect(picture,Rect2i(0,0,700,800),Vector2i(light_index*700,0))
	sheet.save_png(Art.review_path("character_3d/porcelain_runtime_comparison.png"))
	studio.free();print("PASS skin_porcelain_01: 16 skin surfaces, three regions, 12 full 4K maps, two lights, four views");quit()
