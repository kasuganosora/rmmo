extends "res://tools/test_world3d_city_layout.gd"

class MeasuredEditor extends "res://scripts/world_editor/world_editor.gd":
	var rebuilds:=0
	var commits:Array=[]
	var last_refresh_ms:=0.
	func _rebuild()->void:
		rebuilds+=1
		super._rebuild()
	func _commit_records(ids:Array)->void:
		var started:=Time.get_ticks_usec()
		super._commit_records(ids)
		commits.append({"ids":ids.size(),"ms":(Time.get_ticks_usec()-started)/1000.,"view_ms":last_refresh_ms})
	func _refresh_records(ids:Array[String])->void:
		var started:=Time.get_ticks_usec()
		super._refresh_records(ids)
		last_refresh_ms=(Time.get_ticks_usec()-started)/1000.

var sentinel:String
var held:Dictionary

func capture()->Dictionary:
	var forts:Dictionary={};var batches:Dictionary={}
	for key in editor._fortification_collisions.groups:forts[key]=editor._fortification_collisions.groups[key].body.get_instance_id()
	for key in editor._ground_batches.groups:
		var group:Dictionary=editor._ground_batches.groups[key]
		if group.category=="fortification":batches[key]=group.visual.get_instance_id()
	return {"view":editor._view.get_instance_id(),"sentinel":editor._view.get_node(sentinel).get_instance_id(),"body":editor._bodies_by_uuid[sentinel][0].get_instance_id(),"forts":forts,"batches":batches,"rebuilds":editor.rebuilds,"fort_sync":editor._fortification_collisions.sync_count}

func retained(label:String)->void:
	var current:=capture()
	check(current==held,label+": unaffected view/node/collider/render batches/fort collision groups stay identical with no fort rescan")

func batches()->void:
	for i in 240:
		if editor._ground_batches.stats().pending_groups==0:break
		await process_frame
	check(editor._ground_batches.stats().pending_groups==0,"derived render work settles on frame budget")

func run()->void:
	create_timer(240).timeout.connect(func():quit(2));Engine.max_fps=60
	root.size=Vector2i(1440,960);root.content_scale_size=root.size
	directory=Paths.cache_directory("incremental_records_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	for i in 240:doc.add_box_silent("block",Vector3(100+(i%24)*3,1,150+int(i/24)*3),Vector3(2,2,2))
	sentinel=str(doc.records[0].uuid)
	for i in 6:doc.add_box_silent("ground",Vector3(400+i*4,-.5,400),Vector3(4,1,4))
	doc.add_box_silent("ground",Vector3(0,-.5,90),Vector3(90,1,30))
	check(doc.save(path)==OK,"save temporary incremental fixture")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=MeasuredEditor.new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"HTTP MCP server starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.size()==preload("res://scripts/world_editor/mcp_schema.gd").tools().size(),"current 3D tool discovery remains in sync")
	# Current creation bakes house_prefab meshes that intentionally bypass the
	# legacy batcher. Build a valid pre-bake fixture to exercise retained groups.
	var wall:Dictionary=editor._fortifications.prepare({"id":"unchanged_wall","points":[[-20,90],[20,90]],"closed":false,"style":"plain","corner_towers":false,"battlements":true})
	check(wall.get("ok",false),"prepare legacy unbaked fortification fixture")
	if not wall.get("ok",false):quit(1);return
	editor._doc.records.append_array(wall.records);editor._doc.map_meta.editor_layout=wall.metadata;editor._rebuild()
	await call_tool("select_objects",{"ids":[]});await batches();held=capture()
	var unchanged_row:int=editor._object_list._items[sentinel].get_instance_id()
	check(not held.forts.is_empty() and not held.batches.is_empty(),"fixture contains real render and collision fortification batches")
	var entries:Array=editor._mcp._ops.assets()
	var ordinary:Array=entries.filter(func(entry):return not entry.has("asset_path") and not entry.has("prefab_path") and not entry.has("auto_family") and entry.get("surface_id","")=="bridge_deck")
	check(not ordinary.is_empty(),"ordinary box palette entry exists")
	if ordinary.is_empty():quit(1);return
	var box_asset:String=editor._mcp._ops.asset_id(ordinary[0])
	var undo_count:int=editor._doc._undo.size()
	var placed:=await call_tool("place_asset",{"asset_id":box_asset,"position":[0,0,0]})
	var box:String=placed.ids[0];await batches();retained("HTTP box addition")
	check(editor._bodies_by_uuid.has(box) and editor._doc._undo.size()==undo_count+1,"new object has independent collision and one undo transaction")
	await call_tool("undo");await batches();retained("undo addition")
	check(not editor._doc.has_uuid(box) and not editor._bodies_by_uuid.has(box),"undo removes only newly added object/body")
	await call_tool("redo");await batches();retained("redo addition")
	await call_tool("select_objects",{"ids":[box]});await call_tool("delete_selection");await batches();retained("HTTP ordinary deletion")
	check(not editor._doc.has_uuid(box) and not editor._view.has_node(NodePath(box)),"deleted object and visual both disappear")
	await call_tool("undo");await batches();retained("undo deletion")
	await call_tool("redo");await batches();retained("redo deletion")
	# Import a genuine tiny GLB into an isolated library, then use real HTTP place.
	var model:=Node3D.new();var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();model.add_child(mesh)
	var gltf:=GLTFDocument.new();var state:=GLTFState.new();var model_path:=directory.path_join("model.glb")
	check(gltf.append_from_scene(model,state)==OK and gltf.write_to_filesystem(state,model_path)==OK,"create private static model");model.free()
	var library=preload("res://scripts/world_editor/asset_library.gd").new(directory.path_join("assets"))
	var imported:Dictionary=library.import_file(model_path);check(imported.ok,"import private model");editor._shared_assets.append(library)
	placed=await call_tool("place_asset",{"asset_id":editor._mcp._ops.asset_id(imported.entry),"position":[8,0,0]});var asset:String=placed.ids[0]
	await batches();retained("HTTP imported asset addition")
	check(editor._bodies_by_uuid.has(asset),"imported asset keeps namespaced picking collision")
	await call_tool("delete_selection");await call_tool("undo");await batches();retained("imported asset delete/undo")
	check(editor._object_list._items[sentinel].get_instance_id()==unchanged_row,"ordinary add/delete/undo retain unaffected object-list rows")
	await physics_frame;await physics_frame
	var hit:Dictionary=editor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(8,10,0),Vector3(8,-10,0)))
	check(not hit.is_empty() and hit.collider.get_meta("uuid","")==asset,"new imported asset has working physical picking with its UUID")
	# The real UI placement path must ignore repeated visits to the same cell.
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,-20],"span":40})
	editor._palette_items=[{"surface_id":"ground","size":Vector3(4,.2,4),"paint":true}];editor._pick=0;editor._mode=0
	await physics_frame;await physics_frame
	var screen:Vector2=editor._camera.unproject_position(Vector3(0,0,-20))
	editor._place(screen,true);var painted_count:int=editor._doc.records.size();var commits:int=editor.commits.size();var undo_before:int=editor._doc._undo.size()
	editor._dirty=false
	for i in 20:editor._place(screen,false)
	check(editor.commits.size()==commits and editor._doc.records.size()==painted_count and editor._doc._undo.size()==undo_before and not editor._dirty,"20 repeated UI ground visits are no-op: no view commit, history, dirty flag or record")
	editor._stroke.end();await batches();retained("UI ground stroke")
	var river_control:int=editor._terrain_panel.river_fields.fields.water_level.get_instance_id()
	var slope_control:int=editor._terrain_panel.slope_fields.fields.steep_start.get_instance_id()
	var terrain:=await call_tool("create_terrain",{"center":[40,0,-40],"width":8,"depth":8,"cell_size":2})
	await batches();retained("new sculptable terrain")
	var terrain_id:String=terrain.id
	await call_tool("undo");await call_tool("redo");await batches();retained("terrain creation undo/redo")
	check(editor._doc._find(terrain_id).has("terrain_mesh") and editor._bodies_by_uuid.has(terrain_id),"terrain survives undo/redo with collision")
	check(editor._terrain_panel.river_fields.fields.water_level.get_instance_id()==river_control and editor._terrain_panel.slope_fields.fields.steep_start.get_instance_id()==slope_control,"terrain selection/add/delete reuse unchanged form controls and catalogs")
	var form=editor._terrain_panel.river_fields
	var initial_values:Dictionary=form.values();var next_values:=initial_values.duplicate(true)
	next_values.water_level=12.5;next_values.shallow_color=[.2,.3,.4]
	var emitted:Array=[];form.fields.water_level.value_changed.connect(func(_value):emitted.append(true))
	check(form.update_values(next_values) and equivalent(form.values(),next_values) and emitted.is_empty(),"reused form updates bound numbers/colors without triggering edit signals")
	next_values.sand_material_id="missing-option-for-test"
	var before_invalid:Dictionary=form.values()
	check(not form.update_values(next_values) and equivalent(before_invalid,form.values()),"unknown catalog value requests rebuild without partial value updates")
	form.update_values(initial_values)
	await physics_frame;await physics_frame
	hit=editor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(40,10,-40),Vector3(40,-20,-40)))
	check(not hit.is_empty() and hit.collider.get_meta("uuid","")==terrain_id,"new terrain collision supports picking after redo")
	await call_tool("paint_auto_tiles",{"family":"road","points":[[0,0,-60],[8,0,-60]],"cell_size":4})
	var roads:Array=editor._doc.records.filter(func(r):return r.get("tile3d",{}).get("family","")=="road")
	var middle:String=roads[1].uuid;var before:Array=editor._doc.records.duplicate(true)
	await call_tool("select_objects",{"ids":[middle]});await call_tool("delete_selection");await batches();retained("automatic tile removal and neighbors")
	check(editor._doc.records.filter(func(r):return r.has("tile3d")).all(func(r):return editor._view.has_node(NodePath(str(r.uuid)))),"surviving neighbor visuals remain present")
	await call_tool("undo");await batches();check(equivalent(before,editor._doc.records),"tile delete undo restores adjacency records exactly");retained("tile delete undo")
	# Validation keeps locked/hidden members uneditable without refreshing scene.
	await call_tool("set_object_properties",{"ids":[asset],"locked":true,"hidden":true})
	await batches();held=capture()
	await atomic_reject("select_objects",{"ids":[asset]});retained("locked/hidden rejection")
	await call_tool("undo");await batches()
	await call_tool("save_world");var saved:Array=editor._doc.records.duplicate(true)
	await call_tool("open_world",{"path":path});await batches()
	check(equivalent(saved,editor._doc.records),"incremental authoring survives native save and reopen")
	print("INCREMENTAL_COMMIT_SAMPLES ",JSON.stringify(editor.commits))
	editor._mcp.stop();editor.queue_free();await settle()
	print("EDITOR_INCREMENTAL_RECORDS_FINISHED failures=",failed);quit(1 if failed else 0)
