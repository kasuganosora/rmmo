extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(600,900)
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
	studio.camera.size=1.1;studio.camera.position=Vector3(0,1.24,5);studio.camera.look_at(Vector3(0,1.24,0))
	var prefix:="anatomy";var args=OS.get_cmdline_user_args();if not args.is_empty():prefix=args[0]
	var material:=StandardMaterial3D.new();material.albedo_color=Color("a9a2a0");material.roughness=.7
	var body:MeshInstance3D=studio.model.gear.Body.filter(func(m):return m.name=="Body")[0];body.material_override=material
	for category in studio.model.gear:
		for mesh in studio.model.gear[category]:mesh.visible=mesh==body
	for view in ["front","left","back","back_left"]:
		studio.model.play("idle",view,true);studio.model.pose_at(0)
		for i in 4:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(Art.review_path("character_3d/%s_%s.png"%[prefix,view]))
	studio.free();print("PASS anatomical contour review captures");quit()
