extends "res://tools/test_medieval_town_houses.gd"
const Author=preload("res://tools/adjust_town_roof_color.gd")
func run()->void:
	create_timer(600).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1440,900)
	output_directory=Author.REPORT
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output_directory+"/review.json"))
	var published:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output_directory+"/published.json"))
	check(published.failures==0 and published.sha256==FileAccess.get_sha256(Author.FORMAL),"published roof map matches")
	if failures:quit(1);return
	var extras:Dictionary=Author.Doc.authoritative_extras(Author.FORMAL).extras
	var records:Array=extras.rmmo_records.filter(func(r):return r.get("building",{}).get("id","")==report.sample_house)
	var bounds:AABB=preload("res://scripts/world_editor/selection_geometry.gd").bounds(records)
	var center:Vector3=bounds.get_center();var span:float=maxf(bounds.size.x,bounds.size.z)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession");session.world3d_map_path=Author.FORMAL;session.world3d_spawn=center+Vector3(span,0,span)
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(Author.FORMAL)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"full game map loaded")
	if loaded[0]==null:quit(1);return
	session.prepared_world3d=loaded[0];session.world3d_loading=true;world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	for child in world.get_children():
		if child is CanvasLayer:child.hide()
	await teleport(center+Vector3(span,0,span));world._player.hide()
	await capture("game_house_after",center+Vector3(span*1.35,span*.85,span*1.4),center)
	await capture("game_back_after",center+Vector3(-span*1.35,span*.85,-span*1.4),center)
	var f:=FileAccess.open(output_directory+"/game_review.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures,"sha256":FileAccess.get_sha256(Author.FORMAL)}));f.close()
	world.free();quit(failures)
