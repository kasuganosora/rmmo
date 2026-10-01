extends SceneTree
const Assets=preload("res://scripts/char/character_axis_assets.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(90).timeout.connect(func():push_error("Preload timeout");quit(2))
	var start:=Time.get_ticks_usec()
	var login=load("res://scenes/login.tscn").instantiate();root.add_child(login)
	var setup_ms:float=(Time.get_ticks_usec()-start)/1000.0
	var frames:Array[float]=[]
	while not Assets.poll_preload():
		var frame_start:=Time.get_ticks_usec()
		await process_frame
		frames.append((Time.get_ticks_usec()-frame_start)/1000.0)
	assert(frames.size()>0 and not login.login_btn.disabled)
	assert(Assets.preloaded.size()==2)
	var preload_ms:float=(Time.get_ticks_usec()-start)/1000.0
	# Reopening the screen reuses one request per immutable resource.
	var retained:=Assets.preloaded.duplicate()
	Assets.begin_preload();assert(Assets.poll_preload() and Assets.preloaded==retained)
	login.free()
	var hud=load("res://scenes/ui/game_hud.tscn").instantiate()
	hud._character={"id":45,"name":"Benchmark","gender":"female","customization":{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}}
	start=Time.get_ticks_usec()
	root.add_child(hud);hud._windows.character.visible=true;hud._fill_window("character")
	var hud_ms:float=(Time.get_ticks_usec()-start)/1000.0
	var view=hud._equipment_panel_logic._character_view
	frames.sort()
	var result:Dictionary={"login_setup_ms":setup_ms,"background_preload_ms":preload_ms,"responsive_frames":frames.size(),"preload_frame_p95_ms":frames[mini(frames.size()-1,int(frames.size()*.95))],"hud_after_login_ms":hud_ms,"body_phases":view.model.axis_rig.body.load_timings}
	var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_03/preload.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	hud.free();await process_frame
	print("PASS ",JSON.stringify(result));quit()
