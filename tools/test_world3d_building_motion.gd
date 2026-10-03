extends "res://tools/test_world3d_buildings.gd"

func mouse(point: Vector2, pressed: bool) -> void:
	var event:=InputEventMouseButton.new(); event.position=editor._canvas.global_position+point
	event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; Input.parse_input_event(event); await physics()

func motion(point: Vector2) -> void:
	var event:=InputEventMouseMotion.new(); event.position=editor._canvas.global_position+point
	event.button_mask=MOUSE_BUTTON_MASK_LEFT; Input.parse_input_event(event); await physics()

func unchanged(before: Dictionary, history: int, label: String) -> void:
	check(equivalent(editor._doc.records,before.records) and equivalent(editor._doc.map_meta,before.map_meta) and editor._doc._undo.size()==history,label)

func run() -> void:
	create_timer(420).timeout.connect(func(): push_error("building motion timeout"); quit(2))
	root.size=Vector2i(1440,960); root.content_scale_size=root.size
	var directory:=Paths.cache_directory("building_motion_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]); var path:=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("ground",Vector3(0,-.1,0),Vector3(250,.2,250))
	var obstacle: String=doc.add_box("block",Vector3(30,10,0),Vector3(8,20,12)); doc._find(obstacle).editor_hidden=true; doc._find(obstacle).editor_locked=true
	check(doc.save(path)==OK,"create isolated whole-house fixture")
	Net.session().world3d_editor_doc=doc; Net.session().world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); editor._material_directory=directory.path_join("materials"); root.add_child(editor); await physics(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start actual HTTP MCP")
	var discovery:=await rpc("tools/list")
	var config: Array=discovery.result.tools.filter(func(t): return t.name=="configure_transform")
	check(discovery.result.tools.size()==114 and config[0].inputSchema.properties.has("component_edit"),"discover explicit component-edit schema in current 3D MCP")
	var made:=await call_tool("generate_buildings",{"parameters":{"layout":"urban_village","floors":3},"placements":[{"position":[0,0,0]}]})
	var id: String=made.building_ids[0]; var value: Dictionary=editor._buildings.instances()[id]
	var part: String=value.parts.values()[0]; var part_count: int=value.parts.size()
	var state:=await call_tool("select_objects",{"ids":[part]})
	check(part_count>256 and state.selection.size()==part_count and state.whole_building_selection,"one component selects the whole large house")
	check(editor._inspector.title.text.contains("整栋") and not editor._inspector.multi_scale.visible,"inspector identifies whole house and protects parameterized dimensions")
	var texture:=Image.create(4,4,false,Image.FORMAT_RGBA8); texture.fill(Color(.6,.7,.8)); texture.save_png(directory.path_join("paint.png"))
	var finish:=await call_tool("import_surface_material",{"path":directory.path_join("paint.png"),"name":"整栋搬动材质"})
	var surfaces:=await call_tool("list_object_surfaces",{"id":part})
	await call_tool("paint_surface",{"id":part,"target":surfaces.faces[0].target,"material_id":finish.material_id})
	var before:=doc.recovery_snapshot(); var history: int=doc._undo.size()
	await call_tool("set_object_transform",{"id":part,"position":[1,1,1]},false)
	await call_tool("transform_selection",{"rotation":[10,0,0]},false)
	await call_tool("transform_selection",{"scale":1.2},false)
	await call_tool("ungroup_selection",{},false)
	await call_tool("drop_selection",{},false)
	await call_tool("transform_selection",{"translation":[30,0,0]},false)
	unchanged(before,history,"illegal or colliding whole-building changes have no document/history effects")
	await call_tool("transform_selection",{"translation":[-12,0,-7],"rotation":[0,37,0]})
	value=editor._buildings.instances()[id]
	check(doc._undo.size()==history+1 and not equivalent(value.position,[0,0,0]) and is_equal_approx(value.yaw,37) and value.parts.size()==part_count and editor._buildings.conflicts(id).is_empty(),"rigid move and yaw update recipe and signatures in one transaction")
	check(equivalent(editor._building_panel.placement_values().position,value.position),"detailed UI follows relocated recipe instead of retaining stale origin")
	var moved:=doc.recovery_snapshot()
	await call_tool("undo"); unchanged(before,history,"one undo restores every component and its recipe")
	check(equivalent(editor._building_panel.placement_values().position,[0,0,0]),"undo synchronizes the detailed building position form")
	await call_tool("redo"); check(equivalent(doc.records,moved.records) and equivalent(doc.map_meta,moved.map_meta),"redo restores moved house without new IDs")
	var moved_position: Array=editor._buildings.instances()[id].position.duplicate()
	editor._building_panel.form.fields.seed.value=19
	editor._building_panel.update_building()
	check(editor._buildings.instances()[id].parameters.seed==19,"detailed UI updates a painted moved house without coordinate rounding drift")
	check(equivalent(editor._buildings.instances()[id].position,moved_position) and editor._buildings.conflicts(id).is_empty(),"regeneration stays at moved location and orientation")
	check(doc._find(part).has("surface_paint"),"rigid transform and compatible regeneration preserve painted faces")
	# Copy owns an independent registry/identity, is placed clear, and undo removes both.
	await call_tool("select_objects",{"ids":[part]}); before=doc.recovery_snapshot(); history=doc._undo.size()
	await call_tool("duplicate_selection")
	var copy_id: String=doc._find(editor._selection_tools.ids[0]).building.id
	check(copy_id!=id and editor._buildings.instances().size()==2 and editor._buildings.conflicts(copy_id).is_empty() and doc._undo.size()==history+1,"copy creates an independent clean building in nearby free space")
	await call_tool("update_building",{"id":copy_id,"parameters":{"seed":23}})
	check(editor._buildings.instances()[id].parameters.seed==19,"editing copy leaves source recipe unchanged")
	await call_tool("undo"); await call_tool("undo"); unchanged(before,history,"copy undo removes geometry and registry together")
	await call_tool("redo"); check(editor._buildings.instances().has(copy_id),"copy redo keeps independent building identity")
	var copied_part: String=editor._buildings.instances()[copy_id].parts.values()[0]
	await call_tool("select_objects",{"ids":[part,copied_part]}); before=doc.recovery_snapshot(); history=doc._undo.size()
	await call_tool("transform_selection",{"translation":[0,0,30],"rotation":[0,23,0]})
	check(editor._buildings.conflicts(id).is_empty() and editor._buildings.conflicts(copy_id).is_empty(),"multiple complete houses move and rotate together")
	await call_tool("undo"); unchanged(before,history,"multi-house move uses one undo entry")
	await call_tool("select_objects",{"group_id":copy_id}); before=doc.recovery_snapshot(); history=doc._undo.size()
	await call_tool("delete_selection"); check(not editor._buildings.instances().has(copy_id) and editor._buildings.instances().has(id),"delete selection removes one whole house and recipe")
	await call_tool("undo"); unchanged(before,history,"whole-house deletion undoes as one transaction")
	await call_tool("delete_building",{"id":copy_id})
	# Explicit mode enables a single component, retaining conflict detection after a whole move.
	await call_tool("select_objects",{"ids":[part]}); await call_tool("configure_transform",{"component_edit":true})
	state=await call_tool("select_objects",{"ids":[part]}); check(state.selection.size()==1 and state.building_component_edit,"component mode explicitly selects a single wall/slab")
	var position:=Blueprint.vec(doc._find(part).position)+Vector3(.2,0,0)
	await call_tool("set_object_transform",{"id":part,"position":Blueprint.arr(position)})
	check(not editor._buildings.conflicts(id).is_empty(),"manual part edit remains a regeneration conflict")
	await call_tool("configure_transform",{"component_edit":false})
	await call_tool("transform_selection",{"translation":[-2,1,0]})
	check(not editor._buildings.conflicts(id).is_empty() and is_equal_approx(doc._find(part).building.floor_y,1),"whole move updates floor elevation without clearing pre-existing hand edits")
	await call_tool("undo"); await call_tool("undo")
	# Protected members must never yield a partial selection or partial move.
	await call_tool("set_object_properties",{"ids":[part],"locked":true})
	# UI select-all skips protected buildings, not just their protected components.
	editor._selection_tools.set_ids(doc.records.map(func(r): return str(r.uuid)))
	check(editor._selection_tools.ids.size()==1 and doc._find(editor._selection_tools.ids[0]).surface_id=="ground","select-all skips the entire protected house and keeps editable ordinary objects")
	editor._selection_tools.set_ids([])
	var other: String=editor._buildings.instances()[id].parts.values()[1]
	before=doc.recovery_snapshot(); history=doc._undo.size(); await call_tool("select_objects",{"ids":[other]},false)
	check(editor._selection_tools.ids.is_empty(),"locking one member clears entire whole-house selection")
	unchanged(before,history,"failed protected selection leaves document/history unchanged")
	await call_tool("set_object_properties",{"group_id":id,"locked":false})
	await call_tool("set_floor_view",{"isolation":true,"base_height":0,"floor_height":3})
	await call_tool("select_objects",{"ids":[part]},false)
	await call_tool("set_floor_view",{"isolation":false})
	# The live viewport selects a component as a house and drags the shared pivot.
	await call_tool("select_objects",{"ids":[part]}); editor._dock_tabs.current_tab=0
	editor._camera.position=Vector3(-12,75,-7); editor._camera.look_at(Vector3(-12,0,-7),Vector3.FORWARD); await physics()
	var center: Vector3=editor._selection_tools.pivot()
	var screen: Vector2=editor._camera.unproject_position(center)
	await call_tool("select_objects",{"ids":[]}); await mouse(screen,true); await mouse(screen,false)
	check(editor._selection_tools.ids.size()==part_count,"real canvas click selects entire generated building")
	await call_tool("configure_transform",{"mode":"move","position_snap":0})
	center=editor._selection_tools.pivot(); screen=editor._camera.unproject_position(center)
	before=doc.recovery_snapshot(); history=doc._undo.size()
	await mouse(screen,true); check(editor._transform_drag.active,"live whole-house gizmo starts drag")
	var end: Vector2=editor._camera.unproject_position(center+Vector3(-4,0,2))
	await motion(end); await mouse(end,false)
	check(doc._undo.size()==history+1 and editor._buildings.conflicts(id).is_empty() and not equivalent(doc.map_meta,before.map_meta),"real drag commits geometry and recipe together")
	await call_tool("undo"); unchanged(before,history,"live drag undoes atomically")
	await call_tool("select_objects",{"ids":[part]})
	center=editor._selection_tools.pivot(); screen=editor._camera.unproject_position(center)
	var delta:=Vector3(30,0,0)-Blueprint.vec(editor._buildings.instances()[id].position)
	await mouse(screen,true); end=editor._camera.unproject_position(center+delta); await motion(end); await mouse(end,false)
	unchanged(before,history,"colliding live drag rolls the whole house back without undo entry")
	check(editor._status.text.contains("重叠"),"drag reports placement conflict")
	await mouse(screen,true); end=editor._camera.unproject_position(center+Vector3(1,0,1)); await motion(end)
	var escape:=InputEventKey.new(); escape.pressed=true; escape.keycode=KEY_ESCAPE; Input.parse_input_event(escape); await physics()
	unchanged(before,history,"Escape cancels whole-house drag")
	await call_tool("transform_selection",{"translation":[-1,0,1]})
	await call_tool("save_world"); await call_tool("open_world",{"path":path,"discard_changes":true}); doc=editor._doc
	check(editor._buildings.conflicts(id).is_empty(),"save/reopen preserves relocated building recipe and baselines")
	await call_tool("select_objects",{"ids":[part]})
	center=editor._selection_tools.pivot(); editor._camera.position=center+Vector3(23,20,26); editor._camera.look_at(center); editor._orbit_center=center; await physics()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_urban/whole_house.png"))
	editor.free(); Net.session().world3d_editor_doc=null; Net.session().world3d_editor_path=""; await physics()
	if failed==0: Io._remove_tree(directory)
	else: print("fixture="+directory)
	print("test_world3d_building_motion: %s"%("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)
