extends SceneTree
var records:Array=[]
var frame_id:=0
var images:Array[Image]=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,800)
	change_scene_to_file("res://scenes/content_editor.tscn")
	while current_scene==null:await process_frame
	current_scene._select_map("Axel256");current_scene._playtest.call_deferred()
	var deadline:=Time.get_ticks_msec()+60000
	while current_scene==null or current_scene.name!="World":
		if Time.get_ticks_msec()>deadline:push_error("World timeout");quit(1);return
		await process_frame
	await create_timer(3).timeout
	var player=current_scene.player
	player.character_3d.configure("female",{"part_ids":{"FrontHair1":15}},preload("res://scripts/char/starter_equipment.gd").PARTS)
	var server=root.get_node("MockServer")
	var start:=Vector2i(-1,-1)
	for y in range(105,135):
		for x in range(100,135):
			var clear:=true
			for n in range(18):
				if not server.map_collision.can_pass(x+n,y,6):clear=false;break
			if clear:start=Vector2i(x,y);break
		if start.x>=0:break
	assert(start.x>=0,"No real map corridor found")
	player.place_at_cell(start,current_scene.map_field);server.set_player_cell(start.x,start.y)
	player.input_locked=false
	var settings=root.get_node("GameSettings");var old:bool=settings.always_run
	settings.always_run=true
	DirAccess.make_dir_recursive_absolute(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/world_run_frames"))
	await create_timer(.5).timeout
	await travel(player,"ui_right",2.0,"run")
	settings.always_run=false
	await travel(player,"ui_left",1.0,"walk")
	settings.always_run=true
	await travel(player,"ui_left",1.3,"run_return")
	server.inventory.add_item("boots_swift",1)
	var effect:Dictionary=server.try_use_item("boots_swift")
	assert(effect.get("ok",false),"Speed buff failed")
	await travel(player,"ui_right",.8,"run_boost")
	settings.always_run=old
	for i in range(images.size()):images[i].save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/world_run_frames/%03d.png")%i)
	var file:=FileAccess.open(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/world_run_metrics.json"),FileAccess.WRITE);file.store_string(JSON.stringify(records));file.close()
	print("WORLD_RUN_OK start=",start," frames=",frame_id);quit()
func travel(player:Node,key:String,seconds:float,label:String)->void:
	Input.action_press(key)
	var start:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<seconds*1000:
		await create_timer(.033).timeout
		await RenderingServer.frame_post_draw
		var view=player.character_3d;var model=view.model
		var hip:Vector3=model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.bones.hips).origin
		var head:Vector3=model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.bones.head).origin
		records.append({"segment":label,"ms":Time.get_ticks_msec(),"position":[player.global_position.x,player.global_position.y],"sample_position":[view._last_map_position.x,view._last_map_position.y],"elapsed":model.elapsed,"rate":model.locomotion_rate,"action":model.action,"lean_forward":(model.rig.global_transform.basis.inverse()*(head-hip)).z})
		images.append(root.get_texture().get_image());frame_id+=1
	Input.action_release(key)
	while player.moving:await process_frame
	await create_timer(.15).timeout
