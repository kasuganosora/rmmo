extends "res://tools/test_world3d_roads.gd"
const Scatter=preload("res://scripts/world3d/vegetation_scatter.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
var asset_ids: Array=[]

func fixture_model(path: String, broad: bool) -> void:
	var model:=Node3D.new(); model.name="ScatterFixture"
	var trunk:=MeshInstance3D.new(); trunk.name="Trunk"; var cylinder:=CylinderMesh.new(); cylinder.top_radius=.18; cylinder.bottom_radius=.25; cylinder.height=2.0; trunk.mesh=cylinder; trunk.position=Vector3(.6,1,0); model.add_child(trunk)
	var wood:=StandardMaterial3D.new(); wood.albedo_color=Color("826744"); trunk.material_override=wood
	var canopy:=MeshInstance3D.new(); canopy.name="Canopy"; var sphere:=SphereMesh.new(); sphere.radius=1.5 if broad else 1.0; sphere.height=3.0 if broad else 4.0; canopy.mesh=sphere; canopy.position=Vector3(.6,3,0); model.add_child(canopy)
	var leaf:=StandardMaterial3D.new(); leaf.albedo_color=Color("638348") if broad else Color("35583a"); canopy.material_override=leaf
	var exporter:=GLTFDocument.new(); var state:=GLTFState.new(); check(exporter.append_from_scene(model,state)==OK and exporter.write_to_filesystem(state,path)==OK,"temporary multi-mesh GLB fixture exported"); model.free()

func mesh_extras(node: Node) -> Array:
	var result: Array=[]
	if node is MeshInstance3D: result.append(node.get_meta("extras",{}))
	for child in node.get_children(): result.append_array(mesh_extras(child))
	return result

func run() -> void:
	create_timer(300).timeout.connect(func():quit(2))
	root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	directory=Paths.external_root().path_join("__scatter_test_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	var metadata:=FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE); metadata.store_string(JSON.stringify({"id":directory.get_file(),"name":"Temporary scatter acceptance"})); metadata.close()
	var library:=Library.new(directory.path_join("assets"))
	for i in 2:
		var path:=directory.path_join("fixture_%d.glb"%i); fixture_model(path,i==0)
		var imported:=library.import_file(path); check(imported.ok,"temporary model imported into scoped library"); asset_ids.append(imported.entry.asset_path)
	DirAccess.make_dir_recursive_absolute(directory.path_join("maps")); map_path=directory.path_join("maps/map.gltf")
	var doc:=Doc.new(); doc.add_box("ground",Vector3(0,-.25,0),Vector3(130,.5,130)); check(doc.save(map_path)==OK,"isolated scatter map saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=29995
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"scatter HTTP server starts")
	var definitions: Array=(await rpc("tools/list")).result.tools
	check(definitions.size()==114 and definitions.any(func(t):return t.name=="preview_vegetation_scatter" and t.annotations.readOnlyHint) and not definitions.any(func(t):return t.name=="paint_tile"),"114 current 3D tools expose readonly scatter preview; 2D remains retired")
	var catalog:=await call_tool("list_vegetation_scatter",{"query":"fixture_"}); check(catalog.assets.size()==2 and catalog.regions.is_empty(),"scoped model discovery and empty recipe list")
	var args:={"id":"test_grove","asset_ids":asset_ids,"polygon":[[-50,-50],[50,-50],[50,50],[-50,50]],"count":40,"seed":20,"spacing":5}
	var before: Dictionary=editor._doc.recovery_snapshot(); var history: int=editor._doc._undo.size()
	var preview:=await call_tool("preview_vegetation_scatter",args)
	if not preview.get("ok",false): quit(1); return
	check(preview.count==40 and equivalent(preview,await call_tool("preview_vegetation_scatter",args)),"seeded mixed model distribution reproducible through HTTP")
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"preview has no document or history effects")
	await atomic_reject("generate_vegetation_scatter",args.merged({"plan_token":"stale"}))
	await atomic_reject("generate_vegetation_scatter",args.merged({"asset_ids":[asset_ids[0],asset_ids[0]]},true))
	await atomic_reject("generate_vegetation_scatter",args.merged({"polygon":[[0,0],[10,10],[0,10],[10,0]]},true))
	await atomic_reject("generate_vegetation_scatter",args.merged({"scale_min":2,"scale_max":1},true))
	await atomic_reject("generate_vegetation_scatter",args.merged({"asset_ids":["C:/Windows/not_in_library.glb"]},true))
	var unsupported:=await call_tool("preview_vegetation_scatter",args.merged({"height":1},true)); check(unsupported.count==0 and unsupported.skipped.unsupported>0,"no floating plants above actual support")
	var target: Dictionary=preview.placements[0]
	var plant_record: Dictionary=editor._scatter.prepare(args).records[0]; var box:=Geometry.bounds([plant_record]); var obstacle: String=editor._doc.add_box("block",box.get_center(),box.size)
	editor._doc._find(obstacle).editor_hidden=true; editor._doc._find(obstacle).editor_locked=true; editor._rebuild()
	var blocked:=await call_tool("preview_vegetation_scatter",args)
	check(not blocked.placements.any(func(p):return p.id==target.id) and blocked.skipped.occupied>0,"hidden locked prop excludes overlapping full model footprint")
	await atomic_reject("generate_vegetation_scatter",args.merged({"plan_token":preview.plan_token}))
	editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=obstacle); editor._rebuild()
	var zone:={"id":"reserve","purpose":"no_vegetation","polygon":target.polygon,"min_y":-1,"max_y":20,"hidden":true}
	await call_tool("update_planning_zones",zone_request({"zones":[zone]}))
	blocked=await call_tool("preview_vegetation_scatter",args); check(not blocked.placements.any(func(p):return p.id==target.id),"hidden no-vegetation constraint is enforced")
	await call_tool("undo"); zone.hidden=false; zone.purpose="reserved_passage"
	await call_tool("update_planning_zones",zone_request({"zones":[zone]})); blocked=await call_tool("preview_vegetation_scatter",args); check(not blocked.placements.any(func(p):return p.id==target.id),"reserved passage excludes plants")
	await call_tool("undo"); zone.purpose="no_build"; await call_tool("update_planning_zones",zone_request({"zones":[zone]})); blocked=await call_tool("preview_vegetation_scatter",args); check(blocked.placements.any(func(p):return p.id==target.id),"no-build-only area still allows vegetation")
	await call_tool("undo")
	await call_tool("create_road_path",{"points":[[-60,0,0],[60,0,0]],"width":8})
	blocked=await call_tool("preview_vegetation_scatter",args); check(blocked.skipped.road>0 and blocked.placements.all(func(p):return p.polygon.all(func(v):return absf(v[1])>=4)),"unbuilt road skeleton reserves the entire street width")
	await call_tool("generate_road_surface",{})
	await call_tool("generate_buildings",{"parameters":{"floors":1},"placements":[{"position":[20,0,25]}]})
	preview=await call_tool("preview_vegetation_scatter",args); check(preview.skipped.occupied>0,"whole generated buildings reserve interior / fixture sweep against trees")
	before=editor._doc.recovery_snapshot(); history=editor._doc._undo.size()
	var generated:=await call_tool("generate_vegetation_scatter",args.merged({"plan_token":preview.plan_token})); check(generated.count==40 and editor._doc._undo.size()==history+1,"whole recipe plus plant batch commits in one transaction")
	var after: Dictionary=editor._doc.recovery_snapshot(); var id: String=generated.ids[0]
	await call_tool("undo"); check(equivalent(before.records,editor._doc.records) and equivalent(before.map_meta,editor._doc.map_meta),"undo restores plants and recipe atomically")
	await call_tool("redo"); check(equivalent(after,editor._doc.recovery_snapshot()),"redo restores exact stable IDs and transforms")
	history=editor._doc._undo.size(); var repeat_:=await call_tool("generate_vegetation_scatter",args); check(not repeat_.changed and history==editor._doc._undo.size(),"same recipe regeneration is no-op")
	for flag in ["locked","hidden"]:
		await call_tool("set_object_properties",{"ids":[id],flag:true}); await atomic_reject("generate_vegetation_scatter",args); await atomic_reject("remove_vegetation_scatter",{"id":"test_grove"}); await call_tool("undo")
	await call_tool("set_floor_view",{"isolation":true,"base_height":10}); await atomic_reject("generate_vegetation_scatter",args); await call_tool("undo")
	await call_tool("set_event_template",{"id":id,"template":"dialogue","parameters":{"text":"Preserve my tree"}})
	await atomic_reject("generate_vegetation_scatter",args); await atomic_reject("remove_vegetation_scatter",{"id":"test_grove","keep_objects":false})
	var decorated: Dictionary=editor._doc._find(id).duplicate(true)
	await call_tool("remove_vegetation_scatter",{"id":"test_grove"}); check(equivalent(decorated,editor._doc._find(id)) and editor._scatter.regions().is_empty(),"detach retains authored events and physical models")
	await call_tool("undo"); await call_tool("undo")
	await call_tool("select_objects",{"ids":[id]}); await call_tool("delete_selection")
	await atomic_reject("generate_vegetation_scatter",args); check((await call_tool("list_vegetation_scatter")).regions[0].modified_or_missing.has(id),"deleted member reported instead of silently respawned"); await call_tool("undo")
	var previous_position: Array=editor._doc._find(id).position.duplicate(); await call_tool("set_object_transform",{"id":id,"position":[previous_position[0]+1,previous_position[1],previous_position[2]]}); await atomic_reject("generate_vegetation_scatter",args); await call_tool("undo")
	await call_tool("generate_vegetation_scatter",args.merged({"seed":21},true)); check(not equivalent(after.records,editor._doc.records),"explicit reroll updates only owned vegetation")
	await call_tool("undo"); await call_tool("redo")
	await call_tool("save_editor_draft"); await call_tool("save_world"); var saved: Dictionary=editor._doc.recovery_snapshot()
	await call_tool("open_world",{"path":map_path}); check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"save/reopen retains GLB dependencies, recipe and ownership")
	var record: Dictionary=editor._doc._find(editor._scatter.regions()[0].parts[0].id)
	var visual: Node3D=editor._doc._asset(record); check(mesh_extras(visual).all(func(e):return e.get("rmmo_collision")=="block"),"GLB runtime meshes receive enabled collision override"); visual.free()
	await call_tool("generate_vegetation_scatter",args.merged({"seed":21,"collision":false},true))
	record=editor._doc._find(editor._scatter.regions()[0].parts[0].id); visual=editor._doc._asset(record); check(mesh_extras(visual).all(func(e):return e.get("rmmo_collision")=="none"),"disabled collisions reach every runtime GLB mesh"); visual.free()
	await call_tool("remove_vegetation_scatter",{"id":"test_grove","keep_objects":false}); check(editor._scatter.regions().is_empty() and not editor._doc.records.any(func(r):return r.kind=="asset"),"delete clears only owned plants and recipe"); await call_tool("undo")
	# Real canvas input and panel application share the exact MCP transaction.
	editor._dock_tabs.current_tab=9; await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":145})
	var panel: VBoxContainer=editor._city.panel.scatter_panel; panel.new_region(); panel.selected_assets=[asset_ids[0]]; panel.fields.fields.count.value=4; panel.fields.fields.name.text="UI acceptance grove"
	check(editor._city.begin_scatter(0).ok,"UI begins region drawing")
	for p in [Vector3(-58,0,20),Vector3(-35,0,20),Vector3(-35,0,45),Vector3(-58,0,45)]:
		var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=editor._camera.unproject_position(p)+editor._canvas.global_position; Input.parse_input_event(click); await settle()
		click=click.duplicate(); click.pressed=false; Input.parse_input_event(click); await settle()
	var enter:=InputEventKey.new(); enter.pressed=true; enter.keycode=KEY_ENTER; Input.parse_input_event(enter); await settle()
	check(not editor._city.busy() and panel.current.polygon.size()==4,"Enter completes four-vertex region without mutating document")
	panel.show_preview(); check(not panel.preview.is_empty(),"panel previews through shared planner")
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(directory.path_join("scatter_preview.png"))
	history=editor._doc._undo.size(); panel.apply(); check(editor._doc._undo.size()==history+1,"panel generation uses same single recovery transaction")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,3,0],"distance":115,"pitch":-50,"yaw":-30}); await settle(); await RenderingServer.frame_post_draw
	editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("scatter_acceptance.png"))
	await call_tool("save_world")
	var enabled_record: Dictionary=editor._doc.records.filter(func(r):return r.kind=="asset" and r.collision=="block")[0].duplicate(true)
	var disabled_record: Dictionary=editor._doc.records.filter(func(r):return r.kind=="asset" and r.collision=="none")[0].duplicate(true)
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"saved scatter runtime loads")
	if loaded[0]!=null:
		var host:=Node3D.new(); root.add_child(host); host.add_child(loaded[0])
		for r in [enabled_record,disabled_record]:
			var p:=Geometry.bounds([r]).get_center(); Stream.sync(loaded[0],host,p); await physics()
			var hit:=host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x,12,p.z),Vector3(p.x,-1,p.z)))
			check(not hit.is_empty() and (hit.position.y>2 if r.collision=="block" else absf(hit.position.y)<.01),"saved runtime ray sees %s collision behavior"%r.collision)
		host.free()
	if is_instance_valid(loader): loader.queue_free()
	await settle()
	print("SCATTER_ARTIFACTS "+directory); print("WORLD3D_SCATTER_FINISHED failures=%d"%failed)
	quit(0 if failed==0 else 1)
