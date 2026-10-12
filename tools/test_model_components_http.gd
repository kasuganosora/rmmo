extends "res://tools/test_world3d_city_layout.gd"
const Components=preload("res://scripts/world3d/model_components.gd")
func review_timeout()->float:return 180.0
func expected_components()->int:return 1
func verify_loaded()->void:pass
func make_source(source_path:String)->void:
	var model:=Node3D.new();model.name="Cabinet";model.set_meta("extras",{"asset_id":"test_cabinet","delivery_stage":"textured_repair_v2"})
	for i in 3:
		var mesh:=MeshInstance3D.new();mesh.name="Door%d"%i;mesh.mesh=BoxMesh.new();mesh.mesh.size=Vector3(.6,1,.05)
		mesh.position=Vector3(i,1,0);mesh.set_meta("extras",{"delivery_stage":"textured_repair_v2","rmmo_hinge":{"id":"door","angle":95,"open":0},"semantic_group":"32_Furniture_L1"})
		model.add_child(mesh)
	check(Io.save_scene(model,source_path)==OK,"source with synchronized material members saved");model.free()
func run()->void:
	create_timer(review_timeout()).timeout.connect(func():push_error("Model component HTTP timeout");quit(2))
	Engine.max_fps=60;root.size=Vector2i(1000,750)
	directory=Paths.cache_directory("model_components_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var source_path:=directory.path_join("cabinet.glb")
	make_source(source_path)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new()
	var id:String=doc.add_asset({"asset_path":source_path,"label":"柜门验收","bounds_position":[0,0,0],"bounds_size":[3,2,1]},Vector3.ZERO)
	check(doc.save(path)==OK,"isolated author map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor)
	for i in 12000:
		await process_frame
		if i>60 and not editor.saving() and editor._view!=null and editor._view.get_node_or_null(id)!=null:break
	check(not editor.saving(),"editor load and derived preparation fully complete")
	verify_loaded()
	var probe:=TCPServer.new();port=29950
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"3D loopback HTTP starts")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var names:Array=(await rpc("tools/list")).result.tools.map(func(t):return t.name)
	check(names.has("list_building_components") and names.has("set_building_component_state"),"current 3D discovery contains shared component API")
	var listed:=await call_tool("list_building_components",{"id":id})
	check(listed.get("components",[]).size()==expected_components(),"expected independently operated component groups")
	if listed.get("components",[]).is_empty():quit(1);return
	var closed:Array=listed.components.filter(func(r):return r.open==0.0 and not str(r.id).contains("architecture:"))
	check(not closed.is_empty(),"closed cabinet leaf available")
	if closed.is_empty():quit(1);return
	var component:String=closed[0].id
	await call_tool("select_objects",{"ids":[id]})
	check(editor._inspector.model_component_panel.visible,"selected imported model exposes UI control")
	var history:int=editor._doc._undo.size()
	await call_tool("set_building_component_state",{"id":id,"component_id":component,"open":1.0})
	check(editor._doc._undo.size()==history+1,"one undo checkpoint for all moving parts")
	var rows:=Components.rows(editor._view.get_node(id)).filter(func(r):return r.id==component);check(rows[0].open==1.0,"actual instantiated hinge state updated")
	for body:StaticBody3D in editor._bodies_by_uuid[id]:check(body.global_transform.is_equal_approx(body.get_meta("visual").global_transform),"editor collider follows open member")
	await atomic_reject("set_building_component_state",{"id":id,"component_id":"missing","open":1.0})
	await atomic_reject("set_building_component_state",{"id":id,"component_id":component,"open":2.0})
	await call_tool("undo");check(Components.rows(editor._view.get_node(id)).filter(func(r):return r.id==component)[0].open==0.0,"undo restores closed geometry")
	await call_tool("redo");check(Components.rows(editor._view.get_node(id)).filter(func(r):return r.id==component)[0].open==1.0,"redo restores open geometry")
	await call_tool("save_world")
	var reopened=Doc.open_file(path);check(reopened!=null,"saved map reopened")
	check(reopened._find(id).get("model_component_states",{}).get(component)==1.0,"per-instance state survives map resource roundtrip")
	var invalid:Dictionary=editor._doc._find(id).duplicate(true);invalid.model_component_states={"bad":NAN}
	check(not Components.valid(invalid) and editor._doc.validate_save_record(invalid)!=OK,"invalid saved state rejected")
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	print("MODEL_COMPONENT_HTTP_RESULT failures=",failed," evidence=",directory)
	quit(0 if failed==0 else 1)
