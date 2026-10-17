extends "res://tools/test_block_planning_update_http.gd"

func run()->void:
	output="D:/code/rmmo_runtime/review_artifacts/block_planning_20261017/boundaries.json"
	var source_report:="D:/code/rmmo_runtime/review_artifacts/block_planning_20261017/http.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
		if arg.begins_with("--source-report="):source_report=arg.trim_prefix("--source-report=")
	create_timer(900).timeout.connect(func():check(false,"timeout");finish())
	root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_report));check(source.get("failures",1)==0,"source fixture passed its own lifecycle checks")
	directory=Paths.cache_directory("block_boundaries_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(directory);map_path=directory.path_join("map.gltf")
	var doc=Doc.open_file(source.map_path);check(doc!=null and doc.save(map_path)==OK,"native source fixture copied to independent temporary map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	var deadline:=Time.get_ticks_msec()+60000
	while editor.saving() and Time.get_ticks_msec()<deadline:await process_frame
	check(not editor.saving(),"native fixture loading completed")
	if editor.saving():await finish();return
	var probe:=TCPServer.new();port=32400
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"boundary HTTP server uses an unused loopback port")
	var data:=City.resolve(editor._doc.map_meta);var binding:Dictionary=data.block_layout.lots[0];var block_id:String=binding.block_id;var building:String=binding.building_id
	var lots:=Blocks.lots(Blocks.extract(data.roads).blocks[0],Blocks.extract(data.roads).blocks,data.roads,data.block_layout.settings)
	var front:String=lots.lots.filter(func(l):return l.id==binding.lot_id)[0].edge_id
	var base:Dictionary=editor._doc.recovery_snapshot()
	# Legacy v1 records do not carry anchors; only recover from a still-matching baseline.
	for row:Dictionary in editor._doc.map_meta.editor_layout.block_layout.lots:row.erase("anchor")
	check(editor._doc.validate_save()==OK,"legacy anchor-free binding remains a valid document")
	var old:Dictionary=editor._doc.recovery_snapshot()
	var edge:Dictionary=data.roads.edges.filter(func(e):return e.id==front)[0].duplicate(true);edge.width_start=7.;edge.width_end=7.
	var candidate:=await call_tool("preview_block_update",{"road_changes":graph_request({"edges":[edge]})})
	if not candidate.ok:await finish();return
	check(equivalent(old,editor._doc.recovery_snapshot()),"legacy baseline adoption is read only until apply")
	await call_tool("apply_block_update",{"plan_token":candidate.plan_token})
	check(City.resolve(editor._doc.map_meta).block_layout.lots.all(func(b):return b.has("anchor")),"legacy source anchors and joint road update commit together")
	await call_tool("undo");check(equivalent(old,editor._doc.recovery_snapshot()),"legacy upgrade undo restores original format")
	await call_tool("update_road_graph",graph_request({"edges":[edge]}))
	await atomic_reject("preview_block_update",{"block_ids":[block_id]})
	await call_tool("undo");editor._doc.apply_recovery(base);editor._rebuild();await settle()
	# No nearest-neighbour reassignment or deletion when a graph/lot cannot map.
	await atomic_reject("preview_block_update",{"road_changes":graph_request({"remove_edges":[front]})})
	await atomic_reject("preview_block_update",{"block_ids":[block_id,block_id]})
	await atomic_reject("preview_block_update",{"block_ids":[block_id],"lot_width":8.})
	var member:String=editor._buildings.instances()[building].parts.values()[0]
	var original:Dictionary=editor._doc._find(member).duplicate(true)
	editor._doc._find(member).size[0]*=1.01
	await atomic_reject("preview_block_update",{"setback":3.})
	for i in editor._doc.records.size():
		if editor._doc.records[i].uuid==member:editor._doc.records[i]=original
	# Unrelated linked houses remain byte-identical through another frontage update.
	var added:=await call_tool("generate_block_buildings",{"block_ids":[block_id],"max_buildings":4})
	if not added.ok:await finish();return
	var before:Dictionary=editor._doc.recovery_snapshot()
	candidate=await call_tool("preview_block_update",{"road_changes":graph_request({"edges":[edge]})})
	if not candidate.ok:await finish();return
	check(candidate.retained_building_ids.size()>0 and candidate.updated_building_ids.size()>0,"update classifies affected and unaffected frontages")
	var retained:Array=candidate.retained_building_ids.duplicate()
	await call_tool("apply_block_update",{"plan_token":candidate.plan_token})
	for house:String in retained:
		check(var_to_bytes(before.map_meta.building_instances[house])==var_to_bytes(editor._buildings.instances()[house]),"unaffected registry bytes unchanged: "+house)
		for uuid:String in editor._buildings.instances()[house].parts.values():check(var_to_bytes(before.records.filter(func(r):return r.uuid==uuid)[0])==var_to_bytes(editor._doc._find(uuid)),"unaffected component bytes unchanged: "+uuid)
	await call_tool("undo")
	# Actual road property UI opts into the same joint operation.
	var city:VBoxContainer=editor._city.panel;var panel:VBoxContainer=city.block_panel
	panel.follow_roads.button_pressed=true;city.refresh()
	for i in city.edges.item_count:
		if city.edges.get_item_metadata(i)==front:city.edges.select(i);city.fill_edge();break
	city.edge_form.fields.width_start.value=7.;city.edge_form.fields.width_end.value=7.
	var history:int=editor._doc._undo.size();city.apply_edge()
	check(editor._doc._undo.size()==history+1 and City.resolve(editor._doc.map_meta).roads.edges.filter(func(e):return e.id==front)[0].width_start==7.,"road property UI updates linked houses in one transaction")
	await call_tool("undo");panel.follow_roads.button_pressed=false
	# A graph-preserving rigid road edit changes house positions and headings together.
	var nodes:Array=City.resolve(editor._doc.map_meta).roads.nodes.duplicate(true)
	var turn:=Basis(Vector3.UP,deg_to_rad(10.))
	for node:Dictionary in nodes:node.position=City.xyz(turn*City.vec(node.position)+Vector3(1,0,1))
	var before_rotation:Dictionary=editor._doc.recovery_snapshot()
	candidate=await call_tool("preview_block_update",{"road_changes":graph_request({"nodes":nodes})})
	if not candidate.ok:await finish();return
	check(candidate.updated_building_ids.size()==editor._buildings.instances().size(),"node movement and rotation map every linked house without rebuilding")
	await call_tool("apply_block_update",{"plan_token":candidate.plan_token})
	for house:String in editor._buildings.instances():
		var prior:Dictionary=before_rotation.map_meta.building_instances[house];var next:Dictionary=editor._buildings.instances()[house]
		check(City.vec(next.position).distance_to(turn*City.vec(prior.position)+Vector3(1,0,1))<.0001 and absf(wrapf(float(next.yaw)-float(prior.yaw)-10.,-180,180))<.0001 and equivalent(prior.parts,next.parts),"joint road rotation preserves house identity and manual offset: "+house)
	await call_tool("undo");check(equivalent(before_rotation,editor._doc.recovery_snapshot()),"one undo restores the full rotated road and house transaction")
	for house:String in editor._buildings.instances():
		check(editor._buildings.instances()[house].parts.values().any(func(uuid):return not editor._bodies_by_uuid.get(uuid,[]).is_empty()),"house retains its own real editor physics and picking bodies: "+house)
	panel.scan();panel.fields.fields.setback.value=3.;panel.show_update()
	check(not panel.preview.is_empty(),"UI candidate for stale-parameter test")
	history=editor._doc._undo.size();var snap:Dictionary=editor._doc.recovery_snapshot();panel.fields.fields.setback.value=3.5;panel.apply_update()
	check(history==editor._doc._undo.size() and equivalent(snap,editor._doc.recovery_snapshot()),"changing fields after preview requires a fresh UI preview")
	# Real native terrain river in an independent map, including curved riverbanks.
	var fresh:=Doc.new();var ground:String=fresh.add_box("ground",Vector3(0,-.5,0),Vector3(180,1,160));var river_path:String=directory.path_join("river.gltf")
	check(fresh.save(river_path)==OK,"separate natural-river fixture saved")
	var opened:=await call_tool("open_world",{"path":river_path,"discard_changes":true})
	if not opened.ok:await finish();return
	map_path=river_path
	await call_tool("create_terrain",{"source_id":ground,"cell_size":4.,"bedrock_depth":8.})
	await call_tool("generate_terrain_river",{"id":"curved","terrain_ids":[ground],"points":[[-25,-12],[0,0],[25,-12]],"width":4.,"bank_width":2.,"water_level":-1.,"depth":1.,"natural_materials":false})
	await call_tool("create_road_path",{"points":[[-40,0,-40],[40,0,-40],[40,0,40],[-40,0,40],[-40,0,-40]],"width":4})
	var river_preview:=await call_tool("preview_block_buildings",{"max_buildings":1})
	check(river_preview.ok and river_preview.reservations.any(func(r):return r.kind=="river") and river_preview.lots.any(func(l):return l.status=="river_reserved"),"curved heightfield river protects real sampled bank envelope through HTTP")
	# Show the new controls and automatic reservations in the real editor.
	editor._dock_tabs.current_tab=9;panel=editor._city.panel.block_panel;panel.scan();panel.show_preview()
	for child:Node in editor._city.panel.get_children():
		if child is Button and "街区围合" in child.text:child.button_pressed=true
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":110})
	await settle()
	var owner:Node=panel.follow_roads.get_parent()
	while owner!=null:
		if owner is ScrollContainer:owner.ensure_control_visible(panel.follow_roads);break
		owner=owner.get_parent()
	await settle();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("planning_ui.png"))
	await call_tool("save_world")
	await finish()
