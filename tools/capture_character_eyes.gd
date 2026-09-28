extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func fail(message:String)->void:push_error(message);quit(2)
func run()->void:
	root.size=Vector2i(700,800);root.content_scale_size=root.size
	for dynamic:bool in ([true] if OS.get_cmdline_user_args().has("--dynamic-only") else [false,true]):
		print("EYES begin dynamic=",dynamic)
		var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
		print("EYES studio ready")
		if dynamic:studio.show_new_base()
		else:
			studio.regional_preview=preload("res://scripts/char/character_regional_skin.gd").create_preview()
			if studio.regional_preview==null:studio.free();fail("Missing eye/body material source");return
			studio.add_child(studio.regional_preview);studio.model.visible=false
		var count:=0
		for mesh:MeshInstance3D in studio.regional_preview.find_children("*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():
				var material:Material=mesh.get_active_material(surface)
				if material is ShaderMaterial and material.shader.code.contains("uniform float roughness_value"):
					count+=1
					var map:Texture2D=material.get_shader_parameter("albedo_map")
					if map==null or map.get_width()!=2048:studio.free();fail("Eye atlas missing on actual rendered surface");return
					if dynamic and not material.shader.code.contains("body_positions"):studio.free();fail("Eye did not join body deformation");return
		if count!=3:studio.free();fail("Expected iris/pupil/sclera surfaces, got %d"%count);return
		print("EYES material checks passed")
		for light in 2:
			if light==1:studio.toggle_lighting()
			for side in 2:
				studio.regional_preview.rotation.y=.12 if side==0 else .65
				studio.camera.size=.45;studio.camera.position=Vector3(0,1.6,5);studio.camera.look_at(Vector3(0,1.6,0))
				for frame in 8:await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(Art.review_path("character_3d/eyes_%s_%s_%s.png"%["dynamic" if dynamic else "static","studio" if light==0 else "game","front" if side==0 else "side"]))
		print("EYES captures complete dynamic=",dynamic)
		studio.free()
		for frame in 3:await process_frame
	print("PASS eye atlas on three surfaces; scope=", "dynamic_only" if OS.get_cmdline_user_args().has("--dynamic-only") else "static_and_dynamic", "; two lights and two views captured");quit()
