extends "res://tools/test_world3d_roads.gd"
const Cpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Terrain = preload("res://scripts/world3d/terrain_surface.gd")
func flush() -> void:
	editor._ground_batches.flush()
	await settle()
func run() -> void:
	create_timer(240).timeout.connect(func():quit(2)); Engine.max_fps=60
	directory=Paths.cache_directory("ground_batch_%d"%Time.get_ticks_usec()); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new()
	for x in 6:
		var id: String=doc.add_box("ground",Vector3(8+x*16,0,16),Vector3(16,1,16))
		var r: Dictionary=doc._find(id)
		var heights: Array=[]; heights.resize(81); heights.fill(0.0)
		var holes: Array=[]; holes.resize(64); holes.fill(false)
		r.terrain_mesh={"version":1,"columns":8,"rows":8,"floor":-4.,"heights":heights,"holes":holes}
	var first: String=doc.records[0].uuid; var second: String=doc.records[1].uuid
	check(doc.save(map_path)==OK,"temporary batch map saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false
	editor._selection_tools.ids.clear(); editor._refresh_selection(); await flush()
	var probe:=TCPServer.new(); port=30930
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real HTTP batch verification server")
	var defs: Array=(await rpc("tools/list")).result.tools
	check(defs.size()==118 and defs.filter(func(d):return d.name=="editor_state")[0].description.contains("ground_batching"),"3D discovery exposes batching stats without old 2D tools")
	var state:=await call_tool("editor_state",{})
	check(state.ground_batching.source_objects==6 and state.ground_batching.render_surfaces==1,"HTTP state reports 6 records / 12 surfaces merged into 1 draw surface")
	check(editor._view.get_node(first).mesh is Cpu,"editor original is CPU-only")
	var before: Array=editor._doc.records.duplicate(true); var undo: int=editor._doc._undo.size()
	var args:={"id":first,"mode":"raise","points":[[8.,16.]],"radius":4.,"strength":1.}
	await atomic_reject("sculpt_terrain",args.merged({"radius":-1.},true))
	check(equivalent(editor._ground_batches.stats(),state.ground_batching),"invalid call leaves render cache unchanged")
	var sculpt:=await call_tool("sculpt_terrain",args); await flush()
	check(sculpt.ok and sculpt.changed and editor._doc._undo.size()==undo+1,"HTTP sculpt remains one authoring transaction")
	var after: Array=editor._doc.records.duplicate(true)
	await call_tool("undo",{}); await flush(); check(equivalent(before,editor._doc.records),"undo restores independently editable terrain")
	await call_tool("redo",{}); await flush(); check(equivalent(after,editor._doc.records),"redo restores sculpt and merge")
	await physics()
	var hit:=editor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(8,10,16),Vector3(8,-10,16)))
	check(not hit.is_empty() and hit.collider.get_meta("uuid")==first and hit.position.y>.9,"physics hits original UUID and sculpted geometry")
	for property in ["hidden","locked"]:
		await call_tool("set_object_properties",{"ids":[first],property:true}); await flush(); await atomic_reject("sculpt_terrain",args)
		if property=="hidden": check(not editor._view.get_node(first).mesh is Cpu,"hidden record is not included in batch")
		await call_tool("undo",{}); await flush()
	await call_tool("set_floor_view",{"isolation":true,"base_height":100}); await flush()
	check(editor._ground_batches.stats().source_objects==0,"isolated floors do not leak through combined mesh")
	await call_tool("undo",{}); await flush()
	var paint:=preload("res://scripts/world3d/surface_materials.gd").geometry(editor._view.get_node(second))
	check(paint.ok and paint.surfaces.size()==2,"surface selection sees original terrain slots")
	await call_tool("save_world",{}); var saved: Array=editor._doc.records.duplicate(true)
	await call_tool("open_world",{"path":map_path}); await flush()
	check(equivalent(saved,editor._doc.records),"save/reopen preserves records, excludes derived batches")
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"runtime loads native map")
	if loaded[0]!=null:
		var map: Node3D=loaded[0]; var host:=Node3D.new(); root.add_child(host); host.add_child(map)
		var library: Array=map.get_meta("stream_library")
		check(library.all(func(spec):return spec.mesh is Cpu and not spec.mesh.get_rid().is_valid()),"offscreen runtime library holds no ground GPU meshes")
		Stream.sync(map,host,Vector3(32,0,16)); await physics()
		var batcher=map.get_node("GroundRenderBatches")
		check(batcher.stats().source_objects>1,"runtime uses spatial combined rendering")
		var ray:=host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(8,10,16),Vector3(8,-10,16)))
		check(not ray.is_empty() and ray.position.y>.9,"runtime collision uses sculpted CPU mesh")
		var build_count: int=batcher.rebuild_count
		for i in 10: Stream.sync(map,host,Vector3(32,0,16))
		check(batcher.rebuild_count==build_count,"stationary streaming does not rebuild batches")
		Stream.sync(map,host,Vector3(1000,0,1000)); await settle()
		check(batcher.stats().groups==0 and map.get_meta("stream_meshes").is_empty(),"leaving region drops source and combined GPU meshes")
		Stream.sync(map,host,Vector3(32,0,16)); await physics()
		check(batcher.stats().source_objects>1,"returning region recreates spatial batch")
		host.queue_free(); await settle()
	print("GROUND_BATCH_MCP_FINISHED failures=",failed); quit(1 if failed else 0)
