extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Overhead=preload("res://scripts/char/character_overhead_label.gd")
var failed:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failed+=1;push_error(label)
func run()->void:
	root.size=Vector2i(1000,850)
	var camera:=Camera3D.new();root.add_child(camera)
	camera.fov=40
	camera.position=Vector3(0,2.5,3.5);camera.look_at(Vector3(0,1.1,0))
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("8ba5b4")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.42
	root.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,32,0);sun.light_energy=1.15;root.add_child(sun)
	for gender in ["male","female","young_male","young_female"]:
		var model=Model.create(gender,{},preload("res://scripts/char/starter_equipment.gd").PARTS);root.add_child(model);model.set_process(false)
		var label:=Overhead.new();label.model=model;label.text="guide 测试名字";label.pixel_size=.003;root.add_child(label)
		for factor in [.7,1.0,1.5]:
			model.scale=Vector3.ONE*factor
			for action in ["idle","walk","dash","sit_chair"]:
				model.play(action,"front",true);model.pose_at(.2)
				label.update_anchor()
				var head:Vector3=(model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.bones.head)).origin
				check(camera.unproject_position(label.global_position).y<camera.unproject_position(head).y-5,"label stays above animated head: "+gender+action)
		model.scale=Vector3.ONE
		for hair in [0,1,14]:
			model.configure(gender,{"part_ids":{"FrontHair1":hair}},preload("res://scripts/char/starter_equipment.gd").PARTS)
			model.pose_at(0);label.update_anchor()
			check(label.global_position.is_finite(),"hair change retains valid anchor")
		model.configure(gender,{},preload("res://scripts/char/starter_equipment.gd").PARTS)
		model.play("idle","front",true);model.pose_at(0)
		if DisplayServer.get_name()!="headless" and gender in ["male","female"]:
			for shaded in 2:
				sun.visible=shaded==0
				for frame in 4:await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/overhead_%s_%d.png"%[gender,shaded]))
				sun.visible=true
		label.free();model.free()
	var npc=preload("res://scripts/world3d/world_npc.gd").new()
	npc.configure({"uuid":"cast_test","mesh":BoxMesh.new(),"transform":Transform3D.IDENTITY,"extras":{}})
	root.add_child(npc)
	npc.cast_label.text="施法 1.5s";npc.cast_label.show()
	npc.cast_label.update_anchor()
	check(npc.cast_label.model==npc.model and npc.cast_label.global_position.y>npc.position.y,"combat casting uses the same adaptive label")
	npc.free()
	print("test_character_overhead: "+("PASS" if failed==0 else "FAIL"))
	quit(failed)
