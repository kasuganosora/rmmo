extends "res://tools/test_world3d_roads.gd"

func run() -> void:
	create_timer(210).timeout.connect(func():quit(2))
	directory=Paths.external_root().path_join("__road_protection_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	var metadata:=FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE); metadata.store_string(JSON.stringify({"id":"road_test","name":"Road test fixture"})); metadata.close()
	map_path=directory.path_join("maps/test/map.gltf")
	var doc:=Doc.new(); doc.add_box("ground",Vector3(0,-.25,0),Vector3(180,.5,180)); var center_prop: String=doc.add_box("block",Vector3(0,.5,0),Vector3.ONE)
	check(doc.save(map_path)==OK,"protection fixture saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=29940
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"protection HTTP starts")
	await call_tool("create_road_path",{"points":[[-25,0,-25],[25,0,-25],[25,0,25],[-25,0,25],[-25,0,-25]],"width":4})
	await call_tool("generate_road_surface")
	check(editor._doc.has_uuid(center_prop),"ring union leaves existing courtyard prop untouched")
	await call_tool("select_objects",{"ids":[center_prop]}); await call_tool("delete_selection")
	var house:=await call_tool("generate_buildings",{"parameters":{"floors":1},"placements":[{"position":[0,0,0]}]})
	if not house.ok: quit(1); return
	await call_tool("select_objects",{"group_id":house.building_ids[0]})
	await atomic_reject("transform_selection",{"translation":[25,0,0]})
	var zone:={"id":"blocked","polygon":[[38,38],[70,38],[70,70],[38,70]],"min_y":-2,"max_y":60,"purpose":"no_build","hidden":true}
	await call_tool("update_planning_zones",zone_request({"zones":[zone]}))
	await atomic_reject("transform_selection",{"translation":[52,0,52]})
	await atomic_reject("generate_region_buildings",{"from":[40,0,40],"to":[68,0,68],"mode":"single","style":"medieval"})
	await call_tool("transform_selection",{"translation":[-52,0,-52]})
	check(absf(editor._buildings.instances()[house.building_ids[0]].position[0]+52)<.001,"whole-house movement still works outside roads and reservations")
	# A new physical blocker on the actual road or in its headroom rejects regeneration.
	var obstacle: String=editor._doc.add_box("block",Vector3(0,1.5,25),Vector3.ONE); editor._rebuild()
	await atomic_reject("generate_road_surface",{})
	await call_tool("select_objects",{"ids":[obstacle]}); await call_tool("delete_selection")
	await call_tool("generate_road_surface")
	var road: Dictionary=editor._doc.records.filter(func(r):return r.has("road_mesh"))[0]
	await call_tool("set_event_template",{"id":road.uuid,"template":"dialogue","parameters":{"text":"road junction"}})
	await call_tool("generate_road_surface")
	var graph: Dictionary=City.resolve(editor._doc.map_meta).roads
	var edges: Array=graph.edges.duplicate(true)
	for edge in edges: edge.width_start=8; edge.width_end=8
	await call_tool("update_road_graph",graph_request({"edges":edges})); await atomic_reject("generate_road_surface",{}); await call_tool("undo")
	await call_tool("clear_event_template",{"id":road.uuid})
	# Manual geometry conflicts persist until explicitly detached.
	await call_tool("set_object_transform",{"id":road.uuid,"position":[road.position[0],float(road.position[1])+1,road.position[2]]})
	await atomic_reject("generate_road_surface",{}); await call_tool("undo")
	await call_tool("select_objects",{"ids":[road.uuid]})
	await call_tool("duplicate_selection")
	var copied: Dictionary=editor._doc._find(editor._selection_tools.ids[0]); check(copied.has("road_mesh") and not copied.has("road_source"),"ordinary road copies release live ownership")
	await call_tool("undo")
	await call_tool("select_objects",{"ids":[road.uuid]})
	var prefab:=await call_tool("save_prefab",{"name":"Road fragment","pack_root":directory})
	await call_tool("place_asset",{"asset_id":prefab.asset_id,"position":[60,0,-60]})
	copied=editor._doc._find(editor._selection_tools.ids[0]); check(copied.has("road_mesh") and not copied.has("road_source"),"prefab snapshot preserves mesh and releases ownership")
	await call_tool("undo")
	var before: Array=editor._doc.records.duplicate(true)
	await call_tool("detach_road_surface")
	check(editor._doc.records.size()==before.size() and not editor._doc.records.any(func(r):return r.has("road_source")) and not City.resolve(editor._doc.map_meta).has("road_surface"),"detach keeps physical pavement, removes recipe ownership only")
	await call_tool("undo"); check(equivalent(before,editor._doc.records),"detach undo restores all records and ownership")
	await call_tool("redo"); await call_tool("save_world"); await call_tool("open_world",{"path":map_path})
	check(editor._doc.records.any(func(r):return r.has("road_mesh")) and not City.resolve(editor._doc.map_meta).has("road_surface"),"detached roads survive save/reopen")
	print("ROAD_PROTECTION_ARTIFACTS "+directory); print("ROAD_PROTECTION_FINISHED failures=%d"%failed); editor.queue_free(); await settle(); quit(0 if failed==0 else 1)
