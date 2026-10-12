extends "res://tools/test_world3d_city_layout.gd"
## Real 3D HTTP + editor integration, on disposable content only.
var operations:Array=[]

func stable(uuid:String)->Dictionary:
	var node:Node3D=editor._view.get_node(uuid)
	return {"view":editor._view,"node":node,"mesh":node.mesh if node is MeshInstance3D else null,"bodies":editor._bodies_by_uuid.get(uuid,[]).duplicate()}

func unchanged_visual(uuid:String,old:Dictionary,message:String)->void:
	var node:Node3D=editor._view.get_node_or_null(uuid)
	check(editor._view==old.view and node==old.node and (not node is MeshInstance3D or node.mesh==old.mesh) and editor._bodies_by_uuid.get(uuid,[])==old.bodies,message)

func timed_tool(name_:String,args:Dictionary={})->Dictionary:
	var started:=Time.get_ticks_usec()
	var result:=await call_tool(name_,args)
	operations.append({"tool":name_,"ms":(Time.get_ticks_usec()-started)/1000.0})
	return result

func run()->void:
	create_timer(180).timeout.connect(func():push_error("House incremental HTTP timeout");quit(2))
	Engine.max_fps=60
	root.size=Vector2i(1280,900);root.content_scale_size=root.size
	directory=Paths.cache_directory("house_incremental_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new()
	var ground:String=doc.add_box("ground",Vector3(0,-.5,0),Vector3(160,1,100))
	var ordinary:String=doc.add_box("block",Vector3(55,1,0),Vector3(2,2,2))
	check(doc.save(path)==OK,"temporary map saved")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new();port=29872
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real loopback MCP starts")
	var defs:Array=(await rpc("tools/list")).result.tools
	check(defs.size()==preload("res://scripts/world_editor/mcp_schema.gd").tools().size() and not defs.any(func(t):return t.name=="paint_tile"),"current 3D discovery and schemas")
	var anchor:=stable(ordinary)
	var made:=await timed_tool("generate_buildings",{"parameters":{"floors":1},"placements":[{"position":[-20,0,0]},{"position":[20,0,0]}]})
	if not made.get("ok",false):quit(1);return
	editor._ground_batches.flush();await settle()
	unchanged_visual(ordinary,anchor,"generating two houses preserves unrelated node mesh and bodies")
	var first:String=made.building_ids[0];var second:String=made.building_ids[1]
	var first_part:String=editor._buildings.instances()[first].parts.values()[0]
	var second_part:String=editor._buildings.instances()[second].parts.values()[0]
	var other:=stable(second_part)
	var listed:=await timed_tool("list_buildings")
	check(listed.buildings.size()==2 and listed.buildings.all(func(b):return b.conflicts.is_empty()),"indexed list returns exact intact house conflicts")
	await call_tool("select_objects",{"ids":[first_part]});editor._ground_batches.flush()
	var selected:=stable(first_part);var history:int=doc._undo.size()
	await timed_tool("set_object_properties",{"group_id":first,"name":"住宅一"})
	unchanged_visual(first_part,selected,"name change preserves selected house nodes meshes and bodies")
	unchanged_visual(second_part,other,"name change preserves other house")
	check(doc._undo.size()==history+1,"metadata has one undo snapshot")
	await timed_tool("set_object_properties",{"group_id":first,"name":"住宅一"})
	check(doc._undo.size()==history+1,"no-op name creates no history")
	await call_tool("undo");unchanged_visual(first_part,selected,"name undo preserves geometry")
	await call_tool("redo");unchanged_visual(first_part,selected,"name redo preserves geometry")
	await timed_tool("set_object_properties",{"group_id":first,"locked":true})
	check(editor._selection_tools.ids.is_empty(),"locking group clears protected whole-house selection")
	unchanged_visual(first_part,selected,"locking preserves physical house")
	await atomic_reject("set_object_properties",{"group_id":first,"name":"不可修改"})
	await atomic_reject("set_object_properties",{"ids":[first_part],"hidden":"invalid"})
	await call_tool("set_object_properties",{"group_id":first,"locked":false})
	await timed_tool("set_object_properties",{"group_id":first,"hidden":true})
	editor._ground_batches.flush()
	check(editor._view.get_node(first_part)==selected.node and not selected.node.is_visible_in_tree() and editor._bodies_by_uuid.get(first_part,[]).is_empty(),"hidden house retains visual identity but leaves picking/physical bodies")
	unchanged_visual(second_part,other,"hiding preserves unrelated house")
	await call_tool("undo");editor._ground_batches.flush()
	check(editor._view.get_node(first_part)==selected.node and selected.node.is_visible_in_tree() and not editor._bodies_by_uuid.get(first_part,[]).is_empty(),"hidden undo restores visibility and picking without mesh reconstruction")
	await call_tool("redo");editor._ground_batches.flush()
	check(not selected.node.is_visible_in_tree(),"hidden redo remains hidden after batching")
	await call_tool("set_object_properties",{"group_id":first,"hidden":false})
	await call_tool("select_objects",{"ids":[first_part]})
	var original_ids:Array=editor._selection_tools.ids.duplicate()
	editor._camera.position=Vector3(-20,50,0);editor._camera.look_at(Vector3(-20,0,0),Vector3.FORWARD);await settle()
	editor._selection_tools.begin_box(Vector2.ZERO,false)
	editor._selection_tools.end=Vector2(editor._canvas.size)
	editor._selection_tools.finish_box()
	check(original_ids.all(func(id):return editor._selection_tools.ids.has(id)),"marquee operation index keeps whole-house expansion")
	await call_tool("select_objects",{"ids":[first_part]})
	await timed_tool("transform_selection",{"translation":[0,0,5],"rotation":[0,15,0]})
	check(editor._buildings.conflicts(first).is_empty(),"broad-phase move preserves clean registry")
	unchanged_visual(second_part,other,"rigid move preserves unrelated house")
	await atomic_reject("transform_selection",{"translation":[40,0,-5]})
	await atomic_reject("update_building",{"id":first,"parameters":{"width":14}})
	var before_delete:Dictionary=doc.recovery_snapshot()
	await timed_tool("delete_building",{"id":first})
	check(not editor._buildings.instances().has(first) and editor._view.get_node_or_null(first_part)==null,"dedicated delete removes registry and components")
	unchanged_visual(second_part,other,"dedicated delete preserves other house")
	unchanged_visual(ordinary,anchor,"dedicated delete preserves unrelated ordinary object")
	await call_tool("undo")
	check(equivalent(before_delete.records,doc.records) and equivalent(before_delete.map_meta,doc.map_meta),"building deletion undoes atomically")
	unchanged_visual(second_part,other,"building delete undo preserves other house")
	await call_tool("redo");unchanged_visual(second_part,other,"building delete redo preserves other house")
	await call_tool("undo")
	await timed_tool("save_world")
	var saved:Dictionary=doc.recovery_snapshot()
	await timed_tool("open_world",{"path":path,"discard_changes":true})
	check(equivalent(saved.records,editor._doc.records) and editor._buildings.conflicts(first).is_empty(),"save reopen keeps house states transforms and identities")
	var result:={"failures":failed,"operations":operations,"scope":"Temporary two-house real 3D HTTP and renderer integration; not full-town latency baseline","fixture":path}
	var file:=FileAccess.open("res://review_artifacts/house_editor_incremental_http_20261011.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	print("HOUSE_EDITOR_INCREMENTAL_HTTP failures=",failed)
	quit(0 if failed==0 else 1)
