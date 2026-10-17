extends "res://tools/test_world3d_blocks.gd"
const Reservations=preload("res://scripts/world_editor/block_constraints.gd")
var checks:Array=[]
var output:="D:/code/rmmo_runtime/review_artifacts/block_planning_20261017/http.json"
var evidence:Dictionary={}

func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"label":label});super.check(ok,label)

func finish()->void:
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failed,"map_path":map_path,"directory":directory,"engine":Engine.get_version_info().string,"evidence":evidence},"\t"));file.close()
	print("BLOCK_PLANNING_UPDATE checks=%d failures=%d"%[checks.size(),failed])
	if is_instance_valid(editor):editor.queue_free();await settle()
	quit(0 if failed==0 else 1)

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	create_timer(700).timeout.connect(func():check(false,"timeout");finish())
	root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	directory=Paths.cache_directory("block_update_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(directory);map_path=directory.path_join("map.gltf")
	var doc:=Doc.new();var ground:String=doc.add_box("ground",Vector3(0,-.25,0),Vector3(180,.5,160))
	check(doc.save(map_path)==OK,"isolated native map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	var deadline:=Time.get_ticks_msec()+30000
	while (editor._load_job.active or editor._save_job.active) and Time.get_ticks_msec()<deadline:await process_frame
	check(not (editor._load_job.active or editor._save_job.active) and editor._doc.records.size()==1,"initial native map load has completed")
	if (editor._load_job.active or editor._save_job.active):await finish();return
	var probe:=TCPServer.new();port=32300
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"private loopback HTTP starts")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var defs:Array=(await rpc("tools/list")).result.tools
	check(defs.any(func(t):return t.name=="preview_block_update" and t.annotations.readOnlyHint) and defs.any(func(t):return t.name=="apply_block_update") and defs.any(func(t):return t.name=="discard_block_update") and not defs.any(func(t):return t.name=="paint_tile"),"3D discovery exposes shared block update lifecycle, no 2D tools")
	await call_tool("create_road_path",{"points":[[-40,0,-40],[40,0,-40],[40,0,40],[-40,0,40],[-40,0,-40]],"width":4})
	await call_tool("generate_road_surface",{"material_id":"pack:default:paving/historic_cobble/material"})
	var catalog:=await call_tool("get_city_blocks");var id:String=catalog.blocks[0].id;var args:={"block_ids":[id],"max_buildings":2}
	var initial:=await call_tool("preview_block_buildings",args)
	if not initial.ok:await finish();return
	var target:Dictionary=initial.lots.filter(func(l):return l.status=="ready")[0]
	var center:=Vector2.ZERO
	for p:Array in target.polygon:center+=Vector2(p[0],p[1])/4.
	var river_args:={"id":"planning_river","ground_ids":[ground],"points":[[center.x-5,center.y],[center.x+5,center.y]],"width":3.,"bank_width":.5,"bank_height":0.}
	var river:=await call_tool("generate_waterway",river_args)
	if not river.ok:await finish();return
	var snapshot:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var water_plan:=await call_tool("preview_block_buildings",args)
	check(water_plan.ok and water_plan.lots.any(func(l):return l.id==target.id and l.status=="river_reserved") and water_plan.reservations.any(func(r):return r.kind=="river"),"native river and both banks automatically reserve affected frontage lots")
	check(equivalent(snapshot,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"automatic reservation preview is read only")
	await call_tool("undo")
	initial=await call_tool("preview_block_buildings",args)
	var generated:=await call_tool("generate_block_buildings",args.merged({"plan_token":initial.plan_token}))
	if not generated.ok:await finish();return
	var bindings:Array=City.resolve(editor._doc.map_meta).block_layout.lots
	check(bindings.size()==2 and bindings.all(func(b):return b.has("anchor")),"new lot bindings save explicit reflow anchors")
	var building:String=generated.building_ids[0];var value:Dictionary=editor._buildings.instances()[building];var member:String=value.parts.values()[0]
	await call_tool("set_event_template",{"id":member,"template":"dialogue","parameters":{"text":"Preserve authored event"}})
	await call_tool("set_object_properties",{"ids":[member],"name":"Authored house label"})
	var surfaces:=await call_tool("list_object_surfaces",{"id":member})
	check(not surfaces.get("faces",[]).is_empty(),"native component exposes editable surface targets")
	if surfaces.get("faces",[]).is_empty():await finish();return
	# Native fixed prefabs intentionally reject face painting; reflow must not relax that contract.
	await atomic_reject("paint_surface",{"id":member,"target":surfaces.faces[0].target,"material_id":"pack:default:paving/historic_cobble/material","rotation":19.,"scale":[1.1,.9]})
	var hinged:Array=editor._doc.records.filter(func(r):return r.get("building",{}).get("id","")==building and r.has("fixture"))
	check(not hinged.is_empty(),"native generated house has editable fixtures")
	if hinged.is_empty():await finish();return
	await call_tool("set_building_component_state",{"id":building,"component_id":hinged[0].fixture.id,"open":.65})
	await call_tool("select_objects",{"group_id":building})
	await call_tool("transform_selection",{"translation":[.04,0,.03]})
	var original:Dictionary=editor._doc.recovery_snapshot();var original_registry:Dictionary=editor._buildings.instances().duplicate(true)
	var front:String=initial.lots.filter(func(l):return l.get("building_id","")==building)[0].edge_id if initial.lots.any(func(l):return l.get("building_id","")==building) else target.edge_id
	var edge:Dictionary=City.resolve(editor._doc.map_meta).roads.edges.filter(func(e):return e.id==front)[0].duplicate(true);edge.width_start=6.;edge.width_end=6.
	var request:={"block_ids":[id],"road_changes":graph_request({"edges":[edge]})}
	var candidate:=await call_tool("preview_block_update",request)
	if not candidate.ok:await finish();return
	check(candidate.updated_building_ids.size()==2 and equivalent(original,editor._doc.recovery_snapshot()),"road width and both linked house poses are staged without live effects")
	var repeat:=await call_tool("preview_block_update",request);check(equivalent(candidate,repeat),"unchanged candidate and version are reused deterministically")
	await atomic_reject("apply_block_update",{"plan_token":"stale"})
	await atomic_reject("preview_block_update",{"road_changes":{"expected_token":"stale","edges":[edge]}})
	await atomic_reject("preview_block_update",{"lot_width":2})
	candidate=await call_tool("preview_block_update",request)
	history=editor._doc._undo.size()
	var applied:=await call_tool("apply_block_update",{"plan_token":candidate.plan_token})
	if not applied.ok:await finish();return
	check(editor._doc._undo.size()==history+1,"roads, building transforms and bindings commit as one undo")
	var after:Dictionary=editor._doc.recovery_snapshot()
	for house:String in generated.building_ids:
		var old:Dictionary=original_registry[house];var current:Dictionary=editor._buildings.instances()[house]
		check(equivalent(old.parts,current.parts) and equivalent(old.parameters,current.parameters),"building / component identity, recipe and seed preserved: "+house)
		for uuid:String in old.parts.values():
			var a:Dictionary=original.records.filter(func(r):return r.uuid==uuid)[0].duplicate(true);var b:Dictionary=editor._doc._find(uuid).duplicate(true)
			for field:String in ["position","rotation"]:a.erase(field);b.erase(field)
			a.building.erase("floor_y");b.building.erase("floor_y")
			check(equivalent(a,b),"native geometry, materials, events and fixture states preserved: "+uuid)
	check(editor._doc._find(member).get("event_template",{}).get("parameters",{}).get("text","")=="Preserve authored event","manual event remains attached to original component")
	await call_tool("undo");check(equivalent(original,editor._doc.recovery_snapshot()),"undo restores exact pre-update records and metadata")
	await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"redo restores final joint result")
	candidate=await call_tool("preview_block_update",{"block_ids":[id]});history=editor._doc._undo.size()
	if not candidate.ok:await finish();return
	var noop:=await call_tool("apply_block_update",{"plan_token":candidate.plan_token})
	check(not noop.changed and editor._doc._undo.size()==history,"unchanged reflow has no extra history entry")
	# Actual UI uses the same preview/apply service for a further setback change.
	var panel:VBoxContainer=editor._city.panel.block_panel;panel.scan();panel.fields.fields.setback.value=2.5;panel.show_update()
	check(not panel.preview.is_empty() and panel.update_preview,"UI previews existing street update")
	if panel.preview.is_empty():await finish();return
	var ui_token:String=panel.preview.plan_token;var ui_count:int=panel.preview.updated_building_ids.size()
	history=editor._doc._undo.size();panel.apply_update()
	check(ui_count==2 and editor._doc._undo.size()==history+1 and editor._block_update.preview_visual(ui_token).is_empty(),"UI applies exactly one shared transaction")
	await call_tool("undo")
	# Protection and stale-source failures preserve later edits.
	await call_tool("set_object_properties",{"ids":[member],"locked":true})
	await atomic_reject("preview_block_update",{"block_ids":[id],"setback":3.});await call_tool("undo")
	candidate=await call_tool("preview_block_update",{"block_ids":[id],"setback":3.})
	await call_tool("set_object_properties",{"ids":[member],"name":"Later edit"})
	await atomic_reject("apply_block_update",{"plan_token":candidate.plan_token});await call_tool("undo")
	candidate=await call_tool("preview_block_update",{"block_ids":[id],"setback":3.})
	await call_tool("discard_block_update",{"plan_token":candidate.plan_token});await atomic_reject("apply_block_update",{"plan_token":candidate.plan_token})
	# Existing road API supports atomic opt-in reflow too.
	edge=City.resolve(editor._doc.map_meta).roads.edges.filter(func(e):return e.id==front)[0].duplicate(true);edge.width_start=7.;edge.width_end=7.
	history=editor._doc._undo.size()
	var linked:=await call_tool("update_road_graph",graph_request({"edges":[edge],"update_blocks":true}))
	check(linked.ok and editor._doc._undo.size()==history+1 and linked.updated_building_ids.size()==2,"real road HTTP entry shares joint block transaction")
	await call_tool("undo")
	# A missing building remains a tombstone through an update.
	await call_tool("delete_building",{"id":building})
	candidate=await call_tool("preview_block_update",{"block_ids":[id],"setback":2.5})
	check(candidate.ok and candidate.missing_building_ids.has(building),"deleted linked building is reported, never silently recreated")
	if candidate.ok:await call_tool("apply_block_update",{"plan_token":candidate.plan_token});check(not editor._buildings.instances().has(building),"tombstone survives reflow");await call_tool("undo")
	await call_tool("undo")
	await call_tool("save_world");var saved:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("open_world",{"path":map_path})
	check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"native save / reopen preserves bindings, native materials and component identities")
	candidate=await call_tool("preview_block_update",{"block_ids":[id],"setback":2.5})
	check(candidate.ok and candidate.updated_building_ids.size()==2,"reflow remains available after native reopen")
	editor._ground_batches.flush();await settle();deadline=Time.get_ticks_msec()+60000
	while editor._ground_batches.stats().pending_groups>0 and Time.get_ticks_msec()<deadline:await process_frame
	evidence.editor_batches=editor._ground_batches.stats()
	check(evidence.editor_batches.pending_groups==0 and evidence.editor_batches.source_surfaces>evidence.editor_batches.render_surfaces,"updated houses and roads publish to real shared static batches")
	for house:String in generated.building_ids:
		check(editor._buildings.instances()[house].parts.values().all(func(uuid):return is_instance_valid(editor._view.get_node_or_null(uuid))),"each updated component remains independently addressable: "+house)
	await settle();await RenderingServer.frame_post_draw
	await finish()
