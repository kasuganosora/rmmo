extends "res://tools/test_world3d_roads.gd"
const Blocks=preload("res://scripts/world3d/city_blocks.gd")

func run() -> void:
	create_timer(300).timeout.connect(func():quit(2))
	root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("city_blocks_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("ground",Vector3(0,-.25,0),Vector3(180,.5,160)); check(doc.save(map_path)==OK,"isolated block fixture")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=29990
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"block HTTP starts")
	var tools_: Array=(await rpc("tools/list")).result.tools
	check(tools_.size()==114 and tools_.any(func(t):return t.name=="get_city_blocks" and t.annotations.readOnlyHint) and tools_.any(func(t):return t.name=="generate_block_buildings") and not tools_.any(func(t):return t.name=="paint_tile"),"114 current tools expose block workflow; 2D remains retired")
	await atomic_reject("preview_block_buildings",{})
	await call_tool("create_road_path",{"points":[[-40,0,-40],[40,0,-40],[40,0,40],[-40,0,40],[-40,0,-40]],"width":4})
	await call_tool("generate_road_surface",{"material_id":"pack:default:paving/historic_cobble/material"})
	var catalog:=await call_tool("get_city_blocks"); check(catalog.blocks.size()==1,"HTTP exposes closed block")
	var id: String=catalog.blocks[0].id; var args:={"block_ids":[id],"max_buildings":2}
	var before: Dictionary=editor._doc.recovery_snapshot(); var history: int=editor._doc._undo.size()
	var preview:=await call_tool("preview_block_buildings",args)
	if not preview.get("ok",false): quit(1); return
	check(preview.building_count==2 and preview.lots.size()>=8,"first vacant-frontage batch contains two houses")
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"preview is readonly")
	check(equivalent(preview,await call_tool("preview_block_buildings",args)),"same seed gives identical preview and token")
	editor._blocks.overlay_plan=preview
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":110})
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("blocks_preview.png"))
	await atomic_reject("generate_block_buildings",args.merged({"plan_token":"stale"}))
	await atomic_reject("generate_block_buildings",{"block_ids":[id,id]})
	await atomic_reject("generate_block_buildings",{"lot_width":2})
	# Hidden blockers and vertically overlapping reservations stay active.
	var target: Dictionary=preview.lots.filter(func(l):return l.status=="ready")[0]
	var center:=City.vec(target.building_position); var prop: String=editor._doc.add_box("block",center+Vector3.UP,Vector3(2,2,2)); editor._doc._find(prop).editor_hidden=true; editor._rebuild()
	await atomic_reject("generate_block_buildings",args.merged({"plan_token":preview.plan_token}))
	var blocked:=await call_tool("preview_block_buildings",args)
	check(blocked.lots.filter(func(l):return l.id==target.id)[0].status=="occupied","hidden object blocks entire parcel")
	editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=prop); editor._rebuild()
	var zone:={"id":"garden","purpose":"no_build","polygon":target.polygon,"min_y":-2,"max_y":50,"hidden":true}
	await call_tool("update_planning_zones",zone_request({"zones":[zone]}))
	blocked=await call_tool("preview_block_buildings",args)
	check(blocked.lots.filter(func(l):return l.id==target.id)[0].status=="reserved","hidden no-build polygon prevents generation")
	await call_tool("undo")
	preview=await call_tool("preview_block_buildings",args)
	# Door-to-road approach is validated independently of the building footprint.
	target=preview.lots.filter(func(l):return l.status=="ready")[0]
	var facing:=Basis(Vector3.UP,deg_to_rad(target.yaw)); var midpoint: Vector3=City.vec(target.position)-facing*Vector3.BACK
	prop=editor._doc.add_box("block",midpoint+Vector3.UP,Vector3(14,2,.5)); editor._doc._find(prop).rotation=[0,target.yaw,0]; editor._rebuild()
	blocked=await call_tool("preview_block_buildings",args)
	check(blocked.lots.filter(func(l):return l.id==target.id)[0].status=="access_blocked","barrier outside the lot prevents a house with inaccessible entrance")
	editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=prop); editor._rebuild()
	preview=await call_tool("preview_block_buildings",args); history=editor._doc._undo.size(); before=editor._doc.recovery_snapshot()
	var generated:=await call_tool("generate_block_buildings",args.merged({"plan_token":preview.plan_token}))
	if not generated.get("ok",false): quit(1); return
	check(generated.building_ids.size()==2 and editor._doc._undo.size()==history+1,"batch houses and lot bindings are one undo transaction")
	var after: Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo"); check(equivalent(before.records,editor._doc.records) and equivalent(before.map_meta,editor._doc.map_meta),"undo restores both buildings and city metadata (object allocator stays monotonic)")
	await call_tool("redo"); check(equivalent(after,editor._doc.recovery_snapshot()),"redo restores stable building and parcel IDs")
	var building_id: String=generated.building_ids[0]; var member: String=editor._buildings.instances()[building_id].parts.values()[0]
	await call_tool("set_event_template",{"id":member,"template":"dialogue","parameters":{"text":"Keep this house"}})
	var decorated: Dictionary=editor._doc._find(member).duplicate(true)
	var next:=await call_tool("generate_block_buildings",args)
	check(next.building_ids.size()==2 and equivalent(decorated,editor._doc._find(member)),"next batch fills vacant lots and preserves earlier event / geometry")
	var all_ids: Array=editor._buildings.instances().keys()
	check(all_ids.size()==4,"repeat batch does not duplicate linked lots")
	await call_tool("select_objects",{"group_id":building_id})
	check(editor._selection_tools.ids.size()==editor._buildings.instances()[building_id].parts.size(),"generated house selects as one whole building")
	await call_tool("transform_selection",{"translation":[90,0,0]})
	var moved:=await call_tool("preview_block_buildings",args)
	check(moved.lots.filter(func(l):return l.get("building_id","")==building_id)[0].status=="retained","moving a whole house keeps original lot reserved")
	await call_tool("undo")
	await call_tool("delete_building",{"id":building_id})
	var deleted:=await call_tool("preview_block_buildings",args)
	check(deleted.lots.filter(func(l):return l.get("building_id","")==building_id)[0].status=="missing","deleted house is never silently recreated")
	await call_tool("undo")
	await atomic_reject("generate_block_buildings",args.merged({"lot_width":15}))
	await call_tool("set_object_properties",{"ids":[member],"locked":true})
	await atomic_reject("detach_block_buildings",{"block_ids":[id]}); await call_tool("undo")
	var node: Dictionary=City.resolve(editor._doc.map_meta).roads.nodes[0].duplicate(true); node.locked=true
	await call_tool("update_road_graph",graph_request({"nodes":[node]})); await atomic_reject("generate_block_buildings",args); await call_tool("undo")
	var graph: Dictionary=City.resolve(editor._doc.map_meta).roads; var edge: Dictionary=graph.edges[0].duplicate(true); edge.width_start=5; edge.width_end=5
	await call_tool("update_road_graph",graph_request({"edges":[edge]})); await atomic_reject("generate_block_buildings",args); await call_tool("undo")
	var original: Array=editor._doc.records.duplicate(true)
	await call_tool("detach_block_buildings",{"block_ids":[id]})
	check(equivalent(original,editor._doc.records) and editor._buildings.instances().size()==4 and City.resolve(editor._doc.map_meta).block_layout.lots.is_empty(),"detach preserves buildings and only releases city parcel association")
	await call_tool("undo"); await call_tool("redo"); await call_tool("undo")
	await call_tool("save_world"); await call_tool("open_world",{"path":map_path})
	check(City.resolve(editor._doc.map_meta).block_layout.lots.size()==4 and editor._buildings.instances().size()==4,"save/reopen retains all parcel and building ownership")
	await call_tool("preview_block_buildings",args)
	await call_tool("generate_block_buildings",args.merged({"max_buildings":8},true))
	var completed_count: int=editor._doc._undo.size()
	var exhausted:=await call_tool("generate_block_buildings",args)
	check(not exhausted.changed and exhausted.building_ids.is_empty() and completed_count==editor._doc._undo.size(),"full block repeated generation is a no-op without an undo entry")
	await call_tool("save_world")
	# Real canvas click chooses the district and displays a preview using the shared operation.
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":120})
	editor._dock_tabs.current_tab=9; var panel: VBoxContainer=editor._city.panel.block_panel; panel.scan(); panel.picking.button_pressed=true
	await settle()
	var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=editor._camera.unproject_position(Vector3.ZERO)+editor._canvas.global_position
	Input.parse_input_event(click); await settle()
	check(not panel.preview.is_empty() and panel.choice.get_item_metadata(panel.choice.selected)==id,"canvas click selects block and previews buildable lots")
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("blocks_editor.png"))
	editor._blocks.overlay_plan={}; panel.picking.button_pressed=false
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,3,0],"distance":130,"yaw":-25,"pitch":-50})
	await settle(); await RenderingServer.frame_post_draw
	editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("block_houses.png"))
	print("CITY_BLOCKS_ARTIFACTS "+directory); print("WORLD3D_BLOCKS_FINISHED failures=%d"%failed)
	editor.queue_free(); await settle(); quit(0 if failed==0 else 1)
