extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func body_only(model:Node3D)->void:
	for category in model.gear:
		if category=="Body":continue
		for mesh in model.gear[category]:mesh.visible=false
func render_body(model:Node3D,parts:Dictionary,action:String,view:String)->Image:
	model.set_equipment(parts);body_only(model)
	# Keep the same pose: hand clearance depends on visible clothing.
	model.play(action,view,true,"attack_jab" if action=="attack" else "");model.pose_at(.35)
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Requires a real renderer to test body coverage");quit(1);return
	root.size=Vector2i(320,480);root.content_scale_size=root.size
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("18385d");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.6;root.add_child(env)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.6;root.add_child(camera);camera.position=Vector3(0,1.1,4);camera.look_at(Vector3(0,1,0))
	var model=Model.create("female",{},{});root.add_child(model);model.set_process(false)
	var failed:=false
	for gender in ["female","male"]:
		model.configure(gender,{}, {})
		for action in ["idle","attack","sit_chair","sit_ground","death"]:
			for view in ["front","left","back"]:
				var bare:Image=await render_body(model,{},action,view)
				var dressed:Image=await render_body(model,{"Clothing1":2},action,view)
				var changed:=0
				for y in bare.get_height():
					for x in bare.get_width():
						var a:Color=bare.get_pixel(x,y);var b:Color=dressed.get_pixel(x,y)
						if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.04:changed+=1
				if changed>8:
					push_error("Body disappears with skirt: %s %s %s (%d pixels)"%[gender,action,view,changed]);failed=true
		print("Body render coverage checked: ",gender," front/side/back, idle/attack/chair/ground/death")
	model.free();print("FAIL" if failed else "PASS skirt preserves the full rendered body");quit(1 if failed else 0)
