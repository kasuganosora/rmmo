extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var view=preload("res://scripts/char/character_view_3d.gd").new()
	root.add_child(view)
	# Deliberately construct the full shader before toggling the viewport: this
	# diagnostic measures the engine limitation, not the production fallback.
	view.viewport.transparent_bg=false
	view.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":0}},{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE})
	view.model.set_process(false);view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.3)
	view.viewport.size=Vector2i(640,640);view.viewport.msaa_3d=Viewport.MSAA_4X
	view.camera.size=.8;view.camera.position=Vector3(0,1.5,4);view.camera.look_at(Vector3(0,1.5,0))
	var folder:String=Art.review_path("character_3d/skin_viewport_parity_01")
	DirAccess.make_dir_recursive_absolute(folder)
	for mode in ["opaque_sss","transparent_sss","opaque_no_sss"]:
		view.viewport.transparent_bg=mode=="transparent_sss"
		if mode=="opaque_no_sss":
			var mesh:MeshInstance3D=view.model.axis_rig.body.mesh_instance
			var changed:=0
			for i in mesh.mesh.get_surface_count():
				var old:Material=mesh.get_active_material(i)
				if not old is ShaderMaterial or not old.shader.code.contains("SSS_STRENGTH = 0.1;"):continue
				var mat:ShaderMaterial=old.duplicate()
				mat.shader=Shader.new();mat.shader.code=old.shader.code.replace("SSS_STRENGTH = 0.1;","")
				mesh.set_surface_override_material(i,mat);changed+=1
			assert(changed==16)
		for frame in 6:await process_frame
		await RenderingServer.frame_post_draw
		view.viewport.get_texture().get_image().save_png(folder+"/"+mode+".png")
	view.free()
	for frame in 3:await process_frame
	print("WROTE identical-view skin transparency and SSS controls")
	quit()
