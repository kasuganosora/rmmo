extends "res://tools/test_world3d_roads.gd"
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Furrows=preload("res://scripts/world3d/terrain_furrows.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/terrain_furrows"
func batches() -> void:
	while editor._ground_batches.stats().pending_groups>0: await process_frame
	await settle()
func shot(label_: String) -> void:
	await settle(); await RenderingServer.frame_post_draw
	editor._camera.get_viewport().get_texture().get_image().save_png(OUT.path_join(label_+".png"))
func run() -> void:
	create_timer(440).timeout.connect(func():quit(2)); Engine.max_fps=60
	root.size=Vector2i(1500,1100); root.content_scale_size=root.size
	directory=Paths.cache_directory("furrows_%d"%Time.get_ticks_usec()); map_path=directory.path_join("map.gltf"); DirAccess.make_dir_recursive_absolute(OUT)
	var doc:=Doc.new(); check(doc.save(map_path)==OK,"temporary furrow map")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); port=31030
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"furrow HTTP server")
	var definitions: Array=(await rpc("tools/list")).result.tools
	check(definitions.size()==118 and definitions.any(func(d):return d.name=="set_terrain_furrows") and definitions.all(func(d):return d.name!="paint_tile"),"118 current 3D tools, legacy 2D disabled")
	var ids: Array=[]
	for x in [16,48]:
		var result:=await call_tool("create_terrain",{"center":[x,0,16],"width":32,"depth":32,"cell_size":2.,"material_id":"pack:default:terrain/mossy_grass_vcjmej0s/material"})
		if not result.ok: quit(1); return
		ids.append(result.id)
	await call_tool("paint_terrain_region",{"id":"farm","terrain_ids":ids,"polygon":[[4,6],[60,6],[60,26],[4,26]],"material_id":"pack:default:terrain/natural_dirt/material","feather":2.})
	var before: Array=editor._doc.records.duplicate(true)
	var original_material:=preload("res://scripts/world3d/river_materials.gd").terrain(before[0])
	var args:={"id":"farm","terrain_ids":ids,"spacing":1.6,"height":.18,"angle":12.,"margin":2.}
	await atomic_reject("set_terrain_furrows",args.merged({"height":2.},true))
	editor._doc._find(ids[1]).editor_locked=true; await atomic_reject("set_terrain_furrows",args); editor._doc._find(ids[1]).erase("editor_locked")
	editor._doc._find(ids[1]).editor_hidden=true; await atomic_reject("set_terrain_furrows",args); editor._doc._find(ids[1]).erase("editor_hidden")
	await call_tool("set_floor_view",{"isolation":true,"base_height":30}); await atomic_reject("set_terrain_furrows",args); await call_tool("undo")
	var blocker: String=editor._doc.add_box("block",Vector3(15,.15,15),Vector3(2,.2,2)); editor._rebuild(); await atomic_reject("set_terrain_furrows",args); editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=blocker); editor._rebuild()
	var history: int=editor._doc._undo.size(); await call_tool("set_terrain_furrows",args); await batches()
	check(editor._doc._undo.size()==history+1,"two patches are one undo transaction")
	var expected: Array=editor._doc.records.duplicate(true); var triangles:=0
	check(original_material==preload("res://scripts/world3d/river_materials.gd").terrain(expected[0]),"furrow-only changes reuse PBR material and coverage texture")
	for r in expected:
		var generated:=Furrows.generate(r); triangles+=generated.triangles
		check(generated.ok and generated.triangles>0,"real raised field geometry")
		for v in generated.vertices:
			if v.y<-.00001 or v.y>.181: check(false,"ridge height bounds"); break
	check(expected[0].terrain_mesh==before[0].terrain_mesh,"base heightfield stays unchanged")
	await call_tool("undo"); check(equivalent(before,editor._doc.records),"undo restores flat field"); await call_tool("redo"); check(equivalent(expected,editor._doc.records),"redo restores exact recipe")
	await call_tool("save_world"); await call_tool("open_world",{"path":map_path}); await batches(); check(equivalent(expected,editor._doc.records),"native save/reopen preserves furrows")
	var catalog:=await call_tool("list_terrains"); check(catalog.terrains[0].ground_regions.regions[0].has("furrows"),"catalog exposes editable furrow parameters")
	await physics(); var max_hit:=0.; var min_hit:=1.
	for x in range(100,240,2):
		var hit:=editor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x*.1,2,16),Vector3(x*.1,-2,16)))
		if not hit.is_empty(): max_hit=maxf(max_hit,hit.position.y); min_hit=minf(min_hit,hit.position.y)
	check(max_hit>.15 and min_hit<.025,"collision distinguishes ridge crest and trough")
	var pawn:=CharacterBody3D.new(); var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.radius=.3; capsule.height=1.8; shape.shape=capsule; shape.position.y=.9; pawn.add_child(shape); root.add_child(pawn); pawn.position=Vector3(10,1,16); pawn.floor_snap_length=.4
	for frame in 380:
		await physics_frame; pawn.velocity=Vector3(4.,pawn.velocity.y-9.8/60.,0); pawn.move_and_slide()
	check(pawn.position.x>34. and pawn.position.y>-.1 and pawn.position.y<.35,"capsule walks over ridges and shared patch edge without falling/sticking"); pawn.queue_free(); await settle()
	var block_on_ridge: String=editor._doc.add_box("block",Vector3(15,.31,15),Vector3(2,.2,2)); editor._rebuild()
	await atomic_reject("set_terrain_furrows",{"id":"farm","terrain_ids":ids,"enabled":false})
	editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=block_on_ridge); editor._rebuild(); await batches()
	editor._terrain_panel._refresh_furrows(); check(is_equal_approx(editor._terrain_panel.furrow_fields.fields.angle.value,12.),"UI reads persisted furrow direction")
	await call_tool("set_environment",{"preset":"day","sky_enabled":true,"sun_rotation":[-35,32,0],"ambient_energy":.45})
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	await call_tool("set_editor_camera",{"projection":"perspective","center":[32,0,16],"distance":46,"pitch":-48,"yaw":20}); await shot("field_wide")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[30,.1,16],"distance":9,"pitch":-35,"yaw":15}); await shot("field_close")
	var field_index:=0
	for i in editor._terrain_panel.region_list.item_count:
		if editor._terrain_panel.region_list.get_item_metadata(i)=="farm": field_index=i
	editor._terrain_panel.region_list.select(field_index); editor._terrain_panel._apply_furrows(false); await settle()
	check(not editor._doc._find(ids[0]).terrain_regions.regions[0].has("furrows"),"UI removes furrows retaining soil"); await call_tool("undo")
	check(equivalent(expected,editor._doc.records),"UI removal uses shared undo")
	var stats: Dictionary=editor._ground_batches.stats()
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"streaming runtime loads field geometry")
	if loaded[0]!=null: loaded[0].free()
	var file:=FileAccess.open(OUT.path_join("result.json"),FileAccess.WRITE); file.store_string(JSON.stringify({"failures":failed,"triangles":triangles,"collision_min":min_hit,"collision_max":max_hit,"batching":stats,"fixture":map_path},"\t")); file.close()
	print("FURROWS_FINISHED failures=",failed); quit(1 if failed else 0)
