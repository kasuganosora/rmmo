extends "res://tools/test_ground_batching.gd"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
func run()->void:
	Engine.max_fps=60;root.size=Vector2i(1280,800)
	var checkpoint_path:="D:/code/rmmo_runtime/review_artifacts/house_revision/painted_checkpoint.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint="):checkpoint_path=arg.trim_prefix("--checkpoint=")
	var checkpoint:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(checkpoint_path))
	var house:Dictionary=checkpoint.houses[0];var origin:=Vector3(house.position[0],0,house.position[2])
	var doc:=Doc.new();doc.records=checkpoint.records.filter(func(r):return not r.has("building") or r.building.id==house.building_id)
	viewport=SubViewport.new();viewport.size=Vector2i(1280,800);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.45,.55,.65);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.5;viewport.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-43,145,0);viewport.add_child(sun)
	camera=Camera3D.new();viewport.add_child(camera);camera.position=origin+Vector3(19,14,-23);camera.look_at(origin+Vector3(0,3,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24
	var scene:=doc.build();viewport.add_child(scene);sources=scene.get_children()
	var before:=await measure();await RenderingServer.frame_post_draw;var original:=viewport.get_texture().get_image()
	var batcher:=Batch.new();viewport.add_child(batcher);batcher.sync(sources);batcher.flush()
	var after:=await measure();await RenderingServer.frame_post_draw;var merged:=viewport.get_texture().get_image()
	# Shared primitive meshes can already trigger native automatic instancing.
	# Verify actual merged surfaces as well as draws, not an artificial unshared baseline.
	var stats:Dictionary=batcher.stats("building")
	check(stats.render_surfaces<stats.source_surfaces*.5,"house source surfaces consolidated by at least half")
	check(after.draw_calls<=before.draw_calls,"mesh merging does not increase native instanced draw calls")
	var diff:=difference(original,merged);check(diff<.015,"merged house retains the rendered appearance")
	for group in batcher.groups.values():
		if group.category!="building":continue
		var first:Dictionary=group.members[0].get_meta("ground_batch_record")
		check(group.members.all(func(n):var r:Dictionary=n.get_meta("ground_batch_record");return r.building.id==first.building.id and r.building.floor==first.building.floor and r.get("fixture",{}).get("id","")==first.get("fixture",{}).get("id","")),"batch preserves storey and articulated fixture boundary")
	for node in sources:
		var r:Dictionary=node.get_meta("ground_batch_record",{})
		if r.get("building",{}).get("floor",0)>0:node.hide()
	await frames(2)
	check(batcher.groups.values().filter(func(g):return g.category=="building").all(func(g):return g.visual.visible==(g.members[0].get_meta("ground_batch_record").building.floor==0)),"upper storeys hide while ground floor stays visible")
	for node in sources:node.show()
	# Open a door from the closed pose, with both iron handles and straps attached.
	var door_id:=""
	for r in doc.records:
		if r.get("fixture",{}).get("kind")=="door":door_id=r.fixture.id;break
	for r in doc.records:
		if r.get("fixture",{}).get("id","")!=door_id:continue
		var closed:Dictionary=r.duplicate(true);closed.fixture.open=.35
		scene.get_node(NodePath(r.uuid)).transform=Fixtures.transform(closed)
	await frames(3);await RenderingServer.frame_post_draw;var articulated:=viewport.get_texture().get_image()
	batcher.clear();await frames(3);await RenderingServer.frame_post_draw
	check(difference(articulated,viewport.get_texture().get_image())<.015,"batched door and both handles follow the hinge exactly")
	var result:={"failures":failed,"before":before,"after":after,"image_difference":diff,"objects":doc.records.size(),"batches":stats}
	var file:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/house_revision/batching.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("HOUSE_BATCH_FINISHED ",JSON.stringify(result));quit(1 if failed else 0)
