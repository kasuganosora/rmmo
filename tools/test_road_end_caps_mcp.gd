extends "res://tools/test_world3d_city_layout.gd"
const Surface=preload("res://scripts/world3d/road_surface.gd")
var shots:Array=[]
var batch_stats:Dictionary={}
var source_cost:Dictionary={}
func verify_batches(label_:String)->void:
	editor._ground_batches.flush()
	var deadline:=Time.get_ticks_msec()+30000
	while int(editor._ground_batches.stats().get("pending_groups",0))>0 and Time.get_ticks_msec()<deadline:await process_frame
	var stats:Dictionary=editor._ground_batches.stats();batch_stats[label_]=stats
	check(stats.pending_groups==0 and stats.groups>0 and stats.source_surfaces>stats.render_surfaces,label_+" actual derived batches reduce surfaces")
	check(roads().all(func(r):return is_instance_valid(editor._view.get_node_or_null(r.uuid)) and not editor._bodies_by_uuid.get(r.uuid,[]).is_empty()),label_+" batching retains independent road and picking identities")
	var vertices:=0;var triangles:=0;var surfaces:=0
	for record:Dictionary in roads():
		var mesh:Mesh=editor._view.get_node(record.uuid).mesh
		for slot in mesh.get_surface_count():
			var arrays:=mesh.surface_get_arrays(slot);vertices+=arrays[Mesh.ARRAY_VERTEX].size();surfaces+=1
			triangles+=(arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3
	source_cost[label_]={"vertices":vertices,"triangles":triangles,"surfaces":surfaces}
func capture(label_:String)->void:
	if DisplayServer.get_name()=="headless":return
	await settle();await RenderingServer.frame_post_draw
	var pixels:Image=editor._camera.get_viewport().get_texture().get_image()
	var path:=directory.path_join(label_+".webp")
	check(pixels.save_webp(path,false,.9)==OK,"capture actual "+label_+" geometry as lossy WebP Q90")
	shots.append({"path":path,"sha256":FileAccess.get_sha256(path),"lossy":true,"quality":90,"width":pixels.get_width(),"height":pixels.get_height(),"camera":editor._city.camera_state()})
func capture_views(label_:String)->void:
	for view:Dictionary in [{"name":"near","distance":8},{"name":"medium","distance":20},{"name":"far","distance":42}]:
		await call_tool("set_editor_camera",{"projection":"perspective","center":[16,0,80],"distance":view.distance,"pitch":-55,"yaw":155})
		await capture(label_+"_"+view.name)
func roads()->Array:return editor._doc.records.filter(func(r):return r.has("road_mesh"))
func surface_height(p:Vector3)->float:
	var hit:Dictionary=editor._camera.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p-Vector3.UP))
	return float(hit.position.y) if not hit.is_empty() else -1000.
func run()->void:
	rpc_timeout_ms=90000;create_timer(240).timeout.connect(func():quit(2))
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9)
	if output.is_empty():quit(2);return
	directory=output.get_base_dir();root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	var path:=directory.path_join("road_caps.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(16,-.2,40),Vector3(40,.4,110));check(doc.save(path)==OK,"save isolated support map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real 3D HTTP server starts")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var definitions:Array=(await rpc("tools/list")).result.tools
	var schema:Dictionary=definitions.filter(func(d):return d.name=="update_road_graph")[0].inputSchema.properties.edges.items.properties
	check(schema.cap_start.enum==["round","flat"] and schema.cap_end.enum==["round","flat"],"HTTP discovery exposes independent flat and round ends")
	# Several 32 m road pieces share a 128 m rendering cell. The original short
	# road straddled both zero axes, leaving one piece per cell and no batch.
	await call_tool("create_road_path",{"points":[[16,0,0],[16,0,80]],"width":6})
	await call_tool("generate_road_surface",{"material_id":"builtin:checker","kerb_enabled":true,"kerb_material_id":"builtin:white"})
	await call_tool("set_editor_camera",{"projection":"perspective","center":[16,0,80],"distance":20,"pitch":-55,"yaw":155})
	editor._grid.hide();editor._city.overlay.hide()
	for i in 4:await physics_frame
	check(absf(surface_height(Vector3(16,0,81))-.025)<.004,"round endpoint has real pavement and collision beyond its node")
	await verify_batches("round")
	await capture_views("round")
	var edge:Dictionary=City.resolve(doc.map_meta).roads.edges[0].duplicate(true)
	var bad:=edge.duplicate(true);bad.cap_end="square"
	await atomic_reject("update_road_graph",graph_request({"edges":[bad]}))
	var before:=doc.recovery_snapshot();var ids:=roads().map(func(r):return r.uuid);var undos:int=doc._undo.size()
	var panel:VBoxContainer=editor._city.panel;panel.edges.select(0);panel.fill_edge()
	check(panel.edge_form.values().cap_start=="round" and panel.edge_form.values().cap_end=="round","UI reads legacy endpoints as round")
	panel.edge_form.fields.cap_end.select(1);panel.apply_edge();await settle()
	check(City.resolve(doc.map_meta).roads.edges[0].cap_end=="flat" and doc._undo.size()==undos+1,"UI changes the endpoint and automatic pavement in one transaction")
	check(roads().all(func(r):return Surface.valid(r) and ids.has(r.uuid)) and roads().any(func(r):return not r.road_mesh.get("kerbs",[]).is_empty()),"flat update retains stable parts and valid continuous kerbs")
	for i in 4:await physics_frame
	check(absf(surface_height(Vector3(16,0,81)))<.004 and absf(surface_height(Vector3(16,0,79.5))-.025)<.004,"flat endpoint collision ends at the authored section without losing interior support")
	var generated:=doc.recovery_snapshot()
	await verify_batches("flat")
	await capture_views("flat")
	await call_tool("undo");check(equivalent(before,doc.recovery_snapshot()),"undo restores original graph and generated round geometry")
	await call_tool("redo");check(equivalent(generated,doc.recovery_snapshot()),"redo restores flat geometry and metadata")
	edge=City.resolve(doc.map_meta).roads.edges[0].duplicate(true);edge.locked=true
	await call_tool("update_road_graph",graph_request({"edges":[edge]}))
	bad=edge.duplicate(true);bad.cap_end="round"
	await atomic_reject("update_road_graph",graph_request({"edges":[bad]}))
	edge.locked=false;await call_tool("update_road_graph",graph_request({"edges":[edge]}))
	await call_tool("save_world");var saved:=doc.recovery_snapshot()
	await call_tool("open_world",{"path":path})
	check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"actual HTTP save/reopen preserves flat end, texture and kerb records")
	panel=editor._city.panel;panel.edges.select(0);panel.fill_edge()
	check(panel.edge_form.values().cap_end=="flat","UI reopens with the saved flat end selected")
	var count:int=editor._doc._undo.size();await call_tool("generate_road_surface")
	check(editor._doc._undo.size()==count,"unchanged flat regeneration is a no-op")
	for i in 4:await physics_frame
	check(absf(surface_height(Vector3(16,0,81)))<.004,"reopened physical world keeps the flat collision boundary")
	await verify_batches("reopened")
	await capture_views("reopened")
	var parts:int=roads().size()
	editor._mcp.stop();editor.queue_free();await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(path)
	var loaded:Array=await loader.finished
	check(loaded[0]!=null,"game loader opens the saved flat-end map")
	if loaded[0]!=null:
		var host:=Node3D.new();root.add_child(host);host.add_child(loaded[0])
		preload("res://scripts/world3d/world_stream.gd").sync(loaded[0],host,Vector3(16,0,76))
		for i in 4:await physics_frame
		var space:=host.get_world_3d().direct_space_state
		var outside:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(16,2,81),Vector3(16,-1,81)))
		var inside:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(16,2,79.5),Vector3(16,-1,79.5)))
		check(not outside.is_empty() and not inside.is_empty() and absf(outside.position.y)<.004 and absf(inside.position.y-.025)<.004,"real game collision retains the flat end")
		batch_stats.runtime=loaded[0].get_node("GroundRenderBatches").stats()
		check(batch_stats.runtime.source_objects>1 and batch_stats.runtime.source_surfaces>batch_stats.runtime.render_surfaces,"saved flat roads use runtime combined rendering")
		host.free();await settle()
	var f:=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failed,"map":path,"map_sha256":FileAccess.get_sha256(path),"map_bytes":FileAccess.get_file_as_bytes(path).size(),"shots":shots,"road_parts":parts,"batch_stats":batch_stats,"source_cost":source_cost}));f.close()
	print("ROAD_END_CAPS_HTTP_FINISHED failures=",failed);quit(1 if failed else 0)
