extends "res://tools/test_world3d_ground_batching.gd"
func run() -> void:
	create_timer(900).timeout.connect(func():quit(2)); Engine.max_fps=60
	check_shared_materials()
	directory=Paths.cache_directory("fortification_batch_%d"%Time.get_ticks_usec()); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("ground",Vector3(0,-.25,0),Vector3(180,.5,140)); check(doc.save(map_path)==OK,"temporary fortification map")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); port=31920
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"fortification batch real HTTP")
	var defs: Array=(await rpc("tools/list")).result.tools
	check(defs.filter(func(d):return d.name=="editor_state")[0].description.contains("fortification_batching"),"discovery documents static fortification batches")
	await call_tool("generate_fortification",{"id":"batch_wall","points":[[-60,0],[60,0]],"tower_indices":[0,1],"gates":[{"id":"gate","segment":0,"t":.5,"width":6,"height":5,"open":1}]}); await flush()
	var state:=await call_tool("editor_state"); var stats: Dictionary=state.fortification_batching
	check(stats.source_objects>40 and stats.render_surfaces<stats.source_surfaces*.5,"static wall surfaces collapse by more than half")
	check(stats.instanced_groups>0,"repeated masonry shares instanced geometry")
	var collision_stats: Dictionary=state.fortification_collision_batching
	check(collision_stats.source_objects>40 and collision_stats.bodies<collision_stats.source_objects*.4,"HTTP reports spatial collision bodies reduced by more than 60 percent")
	var parts: Array=editor._doc.records.filter(func(r):return r.has("fortification")); var static_parts: Array=parts.filter(func(r):return not r.has("fixture")); var id: String=static_parts.filter(func(r):return r.fortification.role=="battlement")[0].uuid
	check(parts.filter(func(r):return r.has("fixture")).all(func(r):return not editor._view.get_node(r.uuid).mesh is Cpu),"hinged leaves and attached moving iron stay separate")
	var baseline: Array=editor._doc.records.duplicate(true)
	await atomic_reject("set_fortification_gate",{"id":"batch_wall","gate_id":"gate","open":2})
	check(editor._fortification_collisions.rebuild_count==collision_stats.rebuild_count,"invalid MCP call leaves collision cache intact")
	await call_tool("configure_transform",{"component_edit":true}); await call_tool("select_objects",{"ids":[id]}); await flush()
	check(not editor._view.get_node(id).mesh is Cpu,"selected wall component restores editable GPU mesh")
	check(editor._bodies_by_uuid.has(id),"selected component restores its independently excludable collision body")
	var painted: Dictionary=static_parts.filter(func(r):return r.has("surface_paint"))[0]
	await call_tool("select_objects",{"ids":[painted.uuid]}); await flush()
	var mesh_before: int=editor._view.get_node(str(painted.uuid)).mesh.get_instance_id()
	var sync_before: int=editor._ground_batches.sync_count
	var old_position: Array=painted.position.duplicate()
	await call_tool("set_editor_camera",{"projection":"top","center":painted.position,"span":30})
	var drag_origin:=Vector3(float(old_position[0]),float(old_position[1]),float(old_position[2]))
	var start_screen: Vector2=editor._camera.unproject_position(drag_origin)
	check(editor._transform_drag.begin(editor,start_screen,3),"real gizmo drag begins")
	for step in 5:
		editor._transform_drag.update(editor._camera.unproject_position(drag_origin+Vector3.RIGHT*(step+1)),true)
	check(editor._ground_batches.sync_count==sync_before,"drag frames do not rescan unrelated city batches")
	check(editor._view.get_node(str(painted.uuid)).mesh.get_instance_id()==mesh_before,"painted masonry translation reuses mesh and surface bindings")
	check(absf(editor._inspector.fields.position_0.value-float(painted.position[0]))<=.00051,"real drag refreshes inspector position within 0.001 m field precision (field=%.7f record=%.7f)"%[editor._inspector.fields.position_0.value,float(painted.position[0])])
	check(not is_equal_approx(float(painted.position[0]),float(old_position[0])),"real drag actually moves selected masonry")
	check(editor._bodies_by_uuid.has(str(painted.uuid)),"drag keeps independent selected collider")
	for body in editor._bodies_by_uuid.get(str(painted.uuid),[]):
		check(body.transform.is_equal_approx(body.get_meta("visual").global_transform),"drag keeps collider aligned with visual")
	editor._transform_drag.finish(true)
	check(painted.position==old_position,"cancel restores original transform")
	check(editor._view.get_node(str(painted.uuid)).position.is_equal_approx(drag_origin),"cancel restores visual transform")
	var numeric_syncs: int=editor._ground_batches.sync_count
	await call_tool("set_object_transform",{"id":painted.uuid,"position":[old_position[0]+1,old_position[1],old_position[2]]})
	check(editor._ground_batches.sync_count==numeric_syncs+1,"selected numeric/MCP transform performs one global sync")
	await call_tool("undo"); await call_tool("redo"); await call_tool("undo"); await flush()
	await call_tool("select_objects",{"ids":[id]}); await flush()
	var geo:=preload("res://scripts/world3d/surface_materials.gd").geometry(editor._view.get_node(id)); check(geo.ok,"surface picking keeps original face geometry")
	await call_tool("select_objects",{"ids":[]}); await flush()
	check(not editor._bodies_by_uuid.has(id),"deselected wall component returns to collision batch")
	await physics()
	var roof_ray:=PhysicsRayQueryParameters3D.create(Vector3(-30,9,0),Vector3(-30,6,0))
	var wall_hit:=editor.get_world_3d().direct_space_state.intersect_ray(roof_ray)
	var hit_id:=preload("res://scripts/world3d/fortification_collision_batcher.gd").hit_uuid(wall_hit)
	check(not wall_hit.is_empty() and not editor._doc._find(hit_id).is_empty() and wall_hit.collider.has_meta("fortification_collision_ranges"),"merged triangle hit resolves original wall UUID")
	await call_tool("set_editor_camera",{"projection":"top","center":[-30,0,0],"span":24})
	var screen: Vector2=editor._camera.unproject_position(Vector3(-30,7.5,0))
	check(editor._pick_object(screen)==hit_id,"UI object picking resolves merged collision UUID")
	var picked:=await call_tool("pick_surface",{"screen":[screen.x,screen.y]})
	check(picked.get("id")==hit_id,"HTTP surface picking resolves original mesh through merged collider")
	if picked.get("ok",false):
		await call_tool("paint_surface",{"id":hit_id,"target":picked.target,"material_id":"builtin:white"}); await flush(); await physics()
		check(preload("res://scripts/world3d/fortification_collision_batcher.gd").hit_uuid(editor.get_world_3d().direct_space_state.intersect_ray(roof_ray))==hit_id,"paint rebuild preserves original collision identity")
		await call_tool("undo"); await flush()
	await call_tool("set_object_transform",{"id":id,"position":[80,8.3,30]}); await call_tool("select_objects",{"ids":[]}); await flush(); await physics()
	var moved_ray:=PhysicsRayQueryParameters3D.create(Vector3(80,12,30),Vector3(80,6,30))
	check(preload("res://scripts/world3d/fortification_collision_batcher.gd").hit_uuid(editor.get_world_3d().direct_space_state.intersect_ray(moved_ray))==id,"moved component has collision at its new spatial chunk")
	await call_tool("undo"); await flush(); await physics()
	check(editor.get_world_3d().direct_space_state.intersect_ray(moved_ray).is_empty(),"undo removes stale merged collision at previous location")
	for property in ["hidden","locked"]:
		await call_tool("set_object_properties",{"ids":[id],property:true}); await flush()
		await atomic_reject("set_object_transform",{"id":id,"position":[0,99,0]})
		if property=="hidden": check(not editor._view.get_node(id).mesh is Cpu,"hidden wall is removed from combined geometry")
		await call_tool("undo"); await flush()
	await call_tool("set_floor_view",{"isolation":true,"base_height":100}); await flush(); check(editor._ground_batches.stats("fortification").groups==0,"floor isolation hides all derived wall meshes")
	check(editor._fortification_collisions.stats().bodies==0,"floor isolation also removes hidden picking collision batches")
	await call_tool("undo"); await flush()
	await call_tool("set_fortification_gate",{"id":"batch_wall","gate_id":"gate","open":0}); await flush(); await call_tool("undo"); await call_tool("redo"); await call_tool("undo"); await flush()
	check(equivalent(baseline,editor._doc.records),"gate rebuild and undo preserve logical wall records")
	await call_tool("save_world"); await call_tool("open_world",{"path":map_path}); await flush(); check(equivalent(baseline,editor._doc.records),"native save/reopen excludes render-only batch geometry")
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"batched wall runtime loads")
	if loaded[0]!=null:
		var host:=Node3D.new(); root.add_child(host); var scene: Node3D=loaded[0]; host.add_child(scene); Stream.sync(scene,host,Vector3.ZERO); await physics()
		var batcher=scene.get_node("GroundRenderBatches"); check(batcher.stats("fortification").source_objects>10,"streaming uses static wall batches")
		var collision_batcher=scene.get_node("FortificationCollisionBatches"); check(collision_batcher.stats().source_objects>10 and collision_batcher.stats().bodies<collision_batcher.stats().source_objects*.5,"runtime streams merged collision bodies")
		var space:=host.get_world_3d().direct_space_state
		var a:=Vector3(0,2,-7); var b:=Vector3(0,2,7)
		check(space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b)).is_empty(),"open gate keeps empty collision")
		check(preload("res://scripts/world3d/building_fixtures.gd").set_runtime(scene,"fortification:batch_wall","gate",0,0).ok,"runtime gate moves independently of combined masonry"); await physics()
		check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(a+Vector3.RIGHT,b+Vector3.RIGHT)).is_empty(),"closed moving gate blocks collision")
		var count: int=batcher.rebuild_count
		for i in 10: Stream.sync(scene,host,Vector3.ZERO)
		check(batcher.rebuild_count==count,"stationary wall does not rebuild")
		Stream.sync(scene,host,Vector3(1000,0,1000)); check(batcher.stats("fortification").groups==0,"leaving wall region releases combined GPU meshes")
		check(collision_batcher.stats().bodies==0,"leaving wall region releases all collision batches")
		var hits_before: int=collision_batcher.cache_hits
		Stream.sync(scene,host,Vector3.ZERO); await physics(); check(collision_batcher.stats().source_objects>10,"returning to wall recreates collision residency")
		check(collision_batcher.cache_hits>hits_before,"returning to recent chunks reuses exact cooked collision shapes")
		check(collision_batcher.stats().shape_cache_groups<=64 and collision_batcher.stats().shape_cache_triangles<=262144,"collision shape reuse has bounded retention")
		host.free()
	print("FORTIFICATION_BATCH_HTTP_FINISHED failures=",failed); quit(1 if failed else 0)

func check_shared_materials() -> void:
	var host:=Node3D.new(); root.add_child(host)
	var mesh:=BoxMesh.new(); var nodes: Array=[]
	var red:=StandardMaterial3D.new(); red.albedo_color=Color.RED
	var blue:=StandardMaterial3D.new(); blue.albedo_color=Color.BLUE
	for i in 6:
		var node:=MeshInstance3D.new(); node.name="shared_%d"%i; node.mesh=mesh; node.material_override=red if i<3 else blue; node.position=Vector3(i+1,0,1); node.set_meta("ground_batch_record",{"kind":"box","fortification":{}}); host.add_child(node); nodes.append(node)
	var batch:=preload("res://scripts/world3d/ground_batcher.gd").new(); host.add_child(batch); batch.sync(nodes); batch.flush()
	check(batch.stats("fortification").instanced_groups==2,"same geometry with different painted materials has separate batches")
	batch.clear()
	for i in nodes.size(): check(nodes[i].get_active_material(0)==(red if i<3 else blue),"source material survives shared-mesh batch restoration %d"%i)
	host.free()
