extends "res://tools/test_world3d_buildings.gd"
func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	var directory:=Paths.external_root().path_join("__house_prefab_mcp_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata:=FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"id":"house_prefab_test","name":"固定房屋临时测试包"}));metadata.close()
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.2,0),Vector3(150,.4,150));check(doc.save(path)==OK,"temporary map")
	Net.session().world3d_editor_path=path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await physics();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real loopback HTTP MCP")
	var discovery:=await rpc("tools/list")
	check(discovery.result.tools.any(func(tool):return tool.name=="bake_building"),"3D bake tool discovered")
	var before:=doc.recovery_snapshot();var history:int=doc._undo.size()
	await call_tool("bake_building",{"id":"missing"},false)
	await call_tool("generate_buildings",{"parameters":{"floors":0},"placements":[{"position":[0,0,0]}]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid calls are atomic")
	# A small legacy fixture exercises the explicit migration transaction as
	# well as the automatic bake-on-placement path below.
	var legacy:={"version":Blueprint.VERSION,"parameters":Blueprint.defaults(),"position":[50,0,0],"yaw":0,"parts":{},"signatures":{}}
	for i in 3:
		var uuid:String=doc._push("box","block",Vector3(50+i,1,0),Vector3(.5,2,.5))
		var r:Dictionary=doc._find(uuid);r.building={"id":"legacy_fixture","part":"post_%d"%i,"role":"shell","floor":0,"floor_y":0};r.editor_group="legacy_fixture"
		legacy.parts[r.building.part]=uuid;legacy.signatures[r.building.part]=Blueprint.geometry_signature(r)
	doc.map_meta.building_instances={"legacy_fixture":legacy};editor._rebuild()
	await call_tool("bake_building",{"id":"legacy_fixture"})
	check(doc.map_meta.building_instances.legacy_fixture.baked and doc.map_meta.building_instances.legacy_fixture.parts.size()==1,"explicit legacy bake collapses source pieces")
	await call_tool("undo");check(doc.map_meta.building_instances.legacy_fixture.parts.size()==3,"migration undo restores editable legacy structure")
	await call_tool("redo");check(doc.map_meta.building_instances.legacy_fixture.baked,"migration redo restores fixed structure")
	await call_tool("delete_building",{"id":"legacy_fixture"})
	before=doc.recovery_snapshot();history=doc._undo.size()
	var made:=await call_tool("generate_buildings",{"parameters":Blueprint.medieval_presets()[0].parameters,"placements":[{"position":[0,0,0]}]})
	if not made.get("ok",false):quit(1);return
	var id:String=made.building_ids[0];var registry:Dictionary=doc.map_meta.building_instances[id]
	check(registry.baked and registry.parts.size()<100,"placement is compact fixed prefab")
	var frozen:Array=doc.records.duplicate(true)
	check_door_materials(doc.records,"generated")
	await call_tool("undo");check(doc.records==before.records,"undo complete placement")
	await call_tool("redo");check(doc.records==frozen,"redo frozen geometry")
	before=doc.recovery_snapshot();history=doc._undo.size()
	await call_tool("update_building",{"id":id,"parameters":{"width":16}},false)
	await call_tool("detach_building",{"id":id},false)
	await call_tool("configure_transform",{"component_edit":true})
	var member:String=registry.parts.values()[0]
	await call_tool("set_object_transform",{"id":member,"position":[1,0,0]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"cannot regenerate detach or move an internal piece")
	await call_tool("select_objects",{"ids":[member]})
	check(editor._selection_tools.ids.size()==registry.parts.size() and editor._selection_tools.whole,"component mode still selects whole prefab")
	await call_tool("transform_selection",{"translation":[20,0,0],"rotation":[0,90,0]})
	check(doc.map_meta.building_instances[id].position!=registry.position,"rigid whole-prefab move")
	await call_tool("undo");check(doc.records==frozen,"undo rigid move")
	var components:=await call_tool("list_building_components",{"id":id})
	print("PREFAB_COMPONENT_RESPONSE ",JSON.stringify(components).left(150))
	var fixture_rows:Array=preload("res://scripts/world3d/building_fixtures.gd").rows(doc.records,id)
	var door:Dictionary=fixture_rows.filter(func(row):return row.kind=="door" and row.id.contains("partition"))[0]
	before=doc.recovery_snapshot();history=doc._undo.size()
	await call_tool("set_building_component_state",{"id":id,"component_id":door.id,"open":1.5},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid door angle has no side effects")
	await call_tool("set_building_component_state",{"id":id,"component_id":door.id,"open":.6})
	check(is_equal_approx(float(preload("res://scripts/world3d/building_fixtures.gd").rows(doc.records,id).filter(func(row):return row.id==door.id)[0].open),.6),"door state remains adjustable")
	await call_tool("undo")
	await call_tool("duplicate_selection")
	check(doc.map_meta.building_instances.size()==2,"duplicate preserves a second fixed instance")
	await call_tool("undo")
	await call_tool("set_object_properties",{"ids":[member],"locked":true})
	before=doc.recovery_snapshot();await call_tool("delete_building",{"id":id},false)
	check(doc.recovery_snapshot()==before,"locked prefab protected")
	await call_tool("undo")
	await call_tool("select_objects",{"ids":[member]})
	var saved:=await call_tool("save_prefab",{"name":"固定房屋测试","pack_root":directory})
	if not saved.get("ok",false):editor.free();quit(1);return
	before=doc.recovery_snapshot();history=doc._undo.size()
	await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[0,0,0]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"overlapping prefab placement is atomic")
	await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[35,0,0]})
	check(doc.map_meta.building_instances.size()==2,"resource library restores complete fixed house identity")
	check_door_materials(doc.records,"library copy")
	check(preload("res://scripts/world3d/building_fixtures.gd").rows(doc.records,doc.map_meta.building_instances.keys()[1]).size()==fixture_rows.size(),"library retains moving door and window groups")
	await call_tool("undo");check(doc.records==frozen,"undo library placement")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(equivalent(doc.records,frozen),"save reopen keeps baked geometry and identity")
	check_door_materials(doc.records,"save reopen")
	check((await call_tool("list_buildings")).buildings[0].baked,"reopened instance remains immutable")
	var holder:=Node3D.new();root.add_child(holder)
	var scene:=doc.build();holder.add_child(scene);Stream.sync(scene,holder,Vector3.ZERO)
	check(scene.get_meta("stream_library").size()==frozen.size(),"runtime never expands source pieces")
	holder.free();editor.free();Net.session().world3d_editor_doc=null;Net.session().world3d_editor_path=""
	print("HOUSE_PREFAB_MCP_FINISHED failures=",failed);quit(1 if failed else 0)

func check_door_materials(records:Array,stage:String)->void:
	var count:=0;var interiors:=0;var good:=true
	for record:Dictionary in records:
		if record.get("fixture",{}).get("kind")!="door":continue
		count+=1
		var geometry:Dictionary=preload("res://scripts/world3d/house_prefab.gd").geometry(record)
		good=good and not geometry.is_empty() and geometry.mesh.get_surface_count()==2 and geometry.mesh.collision_faces().size() in [846*3,576*3] and geometry.source.collision_faces().size()==36
		var is_interior:bool=geometry.mesh.collision_faces().size()==576*3
		if is_interior:interiors+=1
		var tinted:=false
		for slot in geometry.mesh.get_surface_count():
			var material:Material=geometry.mesh.surface_get_material(slot)
			if material is StandardMaterial3D and material.albedo_texture!=null:
				tinted=material.vertex_color_use_as_albedo
				var colors:PackedColorArray=geometry.mesh.surfaces[slot][Mesh.ARRAY_COLOR];var tones:Dictionary={}
				for color in colors:tones[color]=true
				good=good and tones.size()==(4 if is_interior else 3)
		good=good and tinted
	check(count>interiors and interiors>0 and good,stage+": approved 576 interior / 846 exterior triangles, 12 collision triangles, texture and board colours")
