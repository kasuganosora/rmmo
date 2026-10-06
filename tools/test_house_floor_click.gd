extends "res://tools/test_house_loading_world.gd"
func measure_stairs(world:Node)->bool:
	var B=preload("res://scripts/world3d/building_blueprint.gd")
	var extras:Dictionary=preload("res://scripts/world3d/world_document.gd").authoritative_extras(MAP).extras
	var okay:=true
	var follow_camera:bool="--follow-camera" in OS.get_cmdline_user_args()
	for instance:Dictionary in extras.building_instances.values():
		var plan:Dictionary=B.generate(instance.parameters);var origin:Vector3=B.vec(instance.position)
		for room:Dictionary in plan.rooms:
			var floor_:int=room.floor
			var target:Vector3=origin+B.vec(room.center)+Vector3(1.1,.018,0)
			var start:=target-Vector3(2.2,0,0)
			world._player.position=start+Vector3.UP*.9;world._player.velocity=Vector3.ZERO
			var camera:Camera3D=world._camera.get_node("Camera3D")
			if follow_camera:
				world._camera.yaw=-PI/2;world._camera.pitch=deg_to_rad(18);world._camera._initialized=false
				for i in 45:await physics_frame
			else:
				world._camera.position=target+Vector3(-1.8,2.3,1.7);camera.look_at(target)
				world._camera.set_process(false);world.set_process(false)
				for i in 5:await physics_frame
			var pixel:=camera.unproject_position(target)
			print("FLOOR_PIXEL ",pixel," follow=",follow_camera)
			var hit:Dictionary=world._pick(pixel)
			var surface:String=str(hit.get("collider").get_meta("surface_id","missing")) if not hit.is_empty() else "empty"
			print("FLOOR_PICK ",instance.parameters.template," floor=",floor_," surface=",surface," target=",target," hit=",hit.get("position")," start_nav=",world._navigation.near_surface(start,.35)," target_nav=",world._navigation.near_surface(target))
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=pixel
			var motion:=InputEventMouseMotion.new();motion.position=pixel
			root.push_input(motion,true);root.push_input(event,true)
			event.pressed=false;root.push_input(event,true)
			await process_frame
			var accepted:bool=world._player.click_target is Vector3
			print("FLOOR_CLICK_ACCEPTED ",accepted)
			if not accepted:print("GUI_HOVER ",root.gui_get_hovered_control())
			okay=okay and accepted
			if accepted:
				var began:=Time.get_ticks_msec()
				while Time.get_ticks_msec()-began<5000 and Vector2(world._player.position.x-target.x,world._player.position.z-target.z).length()>.3:await physics_frame
				var reached:bool=Vector2(world._player.position.x-target.x,world._player.position.z-target.z).length()<.3
				print("FLOOR_CLICK_REACHED ",reached," elapsed=",Time.get_ticks_msec()-began," position=",world._player.position)
				okay=okay and reached
			world._player.click_target=null;world._player._route.clear()
	world.set_process(true)
	print("HOUSE_FLOOR_CLICK_FINISHED passed=",okay);return okay
