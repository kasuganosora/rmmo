extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(950,750);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
	var model:Node3D=studio.model
	model.configure("female",{"body_model":"female_base_v2"},{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE})
	assert(model.axis_rig!=null);var body:Node3D=model.axis_rig.body
	studio.add_white_box(studio,Vector3(6,.04,6),Vector3(0,-.02,0))
	var label=preload("res://scripts/char/character_overhead_label.gd").new();label.model=model;label.text="共享人物入口";label.font_size=30;label.pixel_size=.002;studio.add_child(label)
	var folder:String=Art.review_path("character_3d/axis_model_01");DirAccess.make_dir_recursive_absolute(folder)
	for clip:String in ["idle","walk","cast","attack","sit_chair","death"]:
		model.play(clip,"front",true);model._from_rotations.clear()
		model.pose_at(model.action_duration()*(1.0 if clip in ["death","sit_chair"] else .4))
		for view:String in ["front","side"]:
			var bounds:=AABB(model.rig.transform*body.posed_points[0],Vector3.ZERO)
			for point:Vector3 in body.posed_points:bounds=bounds.expand(model.rig.transform*point)
			var center:Vector3=bounds.get_center();studio.camera.size=maxf(2.35,bounds.size.z*1.3)
			studio.camera.position=center+({"front":Vector3(.2,.1,5),"side":Vector3(5,.1,.2)}[view]);studio.camera.look_at(center)
			label.update_anchor()
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/"+clip+"_"+view+".png")
	model.play("walk","front",true);model._from_rotations.clear();model.pose_at(.4)
	model.play("cast","front")
	for frame in 5:model._process(.016)
	studio.camera.size=2.35;studio.camera.position=Vector3(0,1,5);studio.camera.look_at(Vector3(0,1,0))
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/blend_walk_cast.png")
	studio.free()
	for frame in 3:await process_frame
	print("PASS 13 captures through shared CharacterModel3D, not direct studio body");quit()
