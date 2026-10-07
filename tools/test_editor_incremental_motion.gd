extends "res://tools/test_world3d_city_layout.gd"

func run() -> void:
	Engine.max_fps=60
	root.size=Vector2i(1440,960); root.content_scale_size=root.size
	directory=Paths.cache_directory("incremental_motion_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	var ground: String=doc.add_box("ground",Vector3(0,-.5,0),Vector3(120,1,120))
	var heights: Array=[]; heights.resize(81); heights.fill(.5)
	var holes: Array=[]; holes.resize(64); holes.fill(false)
	doc._find(ground).terrain_mesh={"version":1,"columns":8,"rows":8,"floor":-1.,"heights":heights,"holes":holes}
	var obstacle: String=doc.add_box("block",Vector3(30,10,0),Vector3(8,20,12))
	doc._find(obstacle).editor_hidden=true; doc._find(obstacle).editor_locked=true
	var box: String=doc.add_box("block",Vector3(-35,1,0),Vector3(2,2,2))
	check(doc.save(path)==OK,"isolated terrain/building motion fixture")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=doc; session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); editor._material_directory=directory.path_join("materials")
	root.add_child(editor); editor._safety.enabled=false; await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real HTTP motion server")
	var defs: Array=(await rpc("tools/list")).result.tools
	check(defs.size()==preload("res://scripts/world_editor/mcp_schema.gd").tools().size() and not defs.any(func(t):return t.name=="paint_tile"),"current 3D schema only")
	var generated:=await call_tool("generate_buildings",{"parameters":{"floors":2},"placements":[{"position":[0,0,0]}]})
	if not generated.get("ok",false): editor.queue_free(); await settle(); quit(1); return
	var building: String=generated.building_ids[0]
	var part: String=editor._buildings.instances()[building].parts.values()[0]
	await call_tool("select_objects",{"ids":[part]}); editor._ground_batches.flush(); await settle()
	var snapshot: Dictionary=doc.recovery_snapshot(); var history: int=doc._undo.size()
	await atomic_reject("transform_selection",{"rotation":[15,0,0]})
	await atomic_reject("transform_selection",{"translation":[30,0,0]})
	# Nearby terrain still participates in the exact per-cell collision test.
	await atomic_reject("transform_selection",{"translation":[0,-.5,0]})
	var view: Node=editor._view
	var nodes := {}; var meshes := {}; var bodies := {}
	for node in view.get_children():
		nodes[str(node.name)]=node.get_instance_id()
		if node is MeshInstance3D: meshes[str(node.name)]=node.mesh
	for id in editor._selection_tools.ids: bodies[id]=editor._bodies_by_uuid.get(id,[]).duplicate()
	await call_tool("transform_selection",{"translation":[-12,1,-7],"rotation":[0,25,0]})
	check(editor._view==view and view.get_children().all(func(node):return nodes[str(node.name)]==node.get_instance_id()),"move preserves every scene node instead of rebuilding the map")
	check(editor._selection_tools.ids.all(func(id):return view.get_node(id).mesh==meshes[id] and editor._bodies_by_uuid.get(id,[])==bodies[id]),"selected prefab meshes and collision bodies survive rigid motion")
	check(doc._undo.size()==history+1 and editor._buildings.conflicts(building).is_empty(),"single undo transaction and clean building recipe")
	for id in editor._selection_tools.ids:
		var visual: Node3D=view.get_node(id)
		check(visual.get_meta("extras").building==doc._find(id).building,"render metadata follows moved floor elevation")
		for body in bodies[id]: check(body.transform.is_equal_approx(visual.global_transform),"picking collider follows moved component")
	var moved: Dictionary=doc.recovery_snapshot()
	await call_tool("select_objects",{"ids":[box]}); editor._ground_batches.flush()
	await call_tool("undo"); check(equivalent(snapshot.records,doc.records) and equivalent(snapshot.map_meta,doc.map_meta),"undo restores all poses and recipe")
	check(editor._view==view and view.get_children().all(func(node):return nodes[str(node.name)]==node.get_instance_id()),"undo unselected merged building preserves scene nodes")
	editor._ground_batches.flush()
	await call_tool("redo"); check(equivalent(moved.records,doc.records) and equivalent(moved.map_meta,doc.map_meta),"redo restores motion")
	check(editor._view==view and view.get_children().all(func(node):return nodes[str(node.name)]==node.get_instance_id()),"redo unselected merged building preserves scene nodes")
	await call_tool("select_objects",{"ids":[part]})
	var center: Vector3=editor._selection_tools.pivot()
	editor._city.apply_camera({"center":[center.x,center.y,center.z],"distance":35.,"pitch":-35.,"yaw":0.,"span":80.,"projection":"perspective"})
	await settle()
	var screen: Vector2=editor._camera.unproject_position(center)
	check(editor._transform_drag.begin(editor,screen,0),"UI gizmo begins")
	editor._transform_drag.update(screen+Vector2(25,0),true)
	editor._transform_drag.finish(true)
	check(equivalent(moved.records,doc.records) and equivalent(moved.map_meta,doc.map_meta),"cancelled UI drag restores document without new history")
	var texture:=Image.create(4,4,false,Image.FORMAT_RGBA8); texture.fill(Color(.6,.7,.8)); texture.save_png(directory.path_join("paint.png"))
	var material:=await call_tool("import_surface_material",{"path":directory.path_join("paint.png"),"name":"局部材质"})
	var surfaces:=await call_tool("list_object_surfaces",{"id":box})
	await call_tool("paint_surface",{"id":box,"target":surfaces.faces[0].target,"material_id":material.material_id})
	await call_tool("select_objects",{"ids":[box]}); editor._ground_batches.flush()
	var painted: Mesh=editor._view.get_node(box).mesh
	await call_tool("transform_selection",{"translation":[0,2,0],"rotation":[0,15,0]})
	check(editor._view.get_node(box).mesh==painted,"painted rigid transform retains local mesh and UVs")
	await call_tool("transform_selection",{"scale":1.5})
	check(editor._view.get_node(box).mesh!=painted,"size edit regenerates painted geometry")
	await call_tool("select_objects",{"ids":[]}); editor._ground_batches.flush()
	await call_tool("set_object_properties",{"ids":[box],"locked":true})
	await atomic_reject("set_object_transform",{"id":box,"position":[0,0,0]})
	await call_tool("undo")
	await call_tool("set_floor_view",{"isolation":true,"base_height":100})
	editor._ground_batches.flush()
	check(editor._ground_batches.stats().source_objects==0,"floor isolation excludes all hidden geometry from batches")
	await call_tool("undo")
	await call_tool("save_world"); var saved: Dictionary=doc.recovery_snapshot()
	await call_tool("open_world",{"path":path}); editor._ground_batches.flush()
	var expected_meta: Dictionary=saved.map_meta.duplicate(true)
	for field in ["rmmo_format","rmmo_version","rmmo_unit"]: expected_meta[field]=editor._doc.map_meta[field]
	check(equivalent(saved.records,editor._doc.records) and equivalent(expected_meta,editor._doc.map_meta),"save/reopen preserves authoring data and rebuilt batches")
	editor.queue_free(); await settle()
	print("EDITOR_INCREMENTAL_MOTION failures=",failed)
	quit(0 if failed==0 else 1)
