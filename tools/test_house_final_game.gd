extends "res://tools/test_house_loading_world.gd"
func measure_stairs(world:Node)->bool:
	var okay:bool=true if "--lights-only" in OS.get_cmdline_user_args() else await super.measure_stairs(world)
	var extras:Dictionary=preload("res://scripts/world3d/world_document.gd").authoritative_extras(MAP).extras
	var lamp:Dictionary={}
	for r:Dictionary in extras.rmmo_records:
		if r.get("building_shape")=="candle_sconce" and r.building.floor==0:lamp=r;break
	if lamp.is_empty():return false
	var B=preload("res://scripts/world3d/building_blueprint.gd")
	var normal:=Basis.from_euler(B.vec(lamp.rotation)*PI/180)*Vector3.BACK
	world._player.position=B.vec(lamp.position)+normal*2.5-Vector3.UP*1.25
	world._player.velocity=Vector3.ZERO;world._player.click_target=null;world._player._route.clear()
	# The walk benchmark above uses normal gameplay. These inspection images
	# frame the actual installed sconce independently of avatar orbit occlusion.
	world.set_process(false);world._player.set_physics_process(false)
	world._camera.camera.global_position=B.vec(lamp.position)+normal*2.6+normal.cross(Vector3.UP)*.65+Vector3.UP*.15
	world._camera.camera.look_at(B.vec(lamp.position)-Vector3.UP*.1)
	for hour in [23.0,12.0]:
		var applied:Dictionary=world._request_environment({"time_hours":hour,"time_speed":0,"weather_transition":0})
		for i in 60:await process_frame
		var lit:int=world._house_candles.lit_count()
		var good:bool=applied.get("ok",false) and (lit>0 and lit<=2 if hour==23 else lit==0)
		okay=okay and good;print("HOUSE_GAME_LIGHTS hour=",hour," actual=",world._house_candles.hours," lit=",lit," passed=",good)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/code/rmmo_runtime/review_artifacts/house_revision_v10/room_%s.png"%("night" if hour==23 else "day"))
	return okay
