extends "res://tools/test_world3d_ground_batching.gd"
## Read-only verification of the formal town through the actual editor and loader.
const TOWN="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_walls/formal_batch_activation.json"
func run() -> void:
	create_timer(900).timeout.connect(func():quit(2)); Engine.max_fps=60
	directory=Paths.cache_directory("formal_wall_batch_check_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	var hash_before:=FileAccess.get_sha256(TOWN)
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=TOWN; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); editor._safety.enabled=false
	await flush()
	check(not editor._load_failed,"formal town opens through the editor")
	if editor._load_failed: editor.free(); quit(1); return
	var probe:=TCPServer.new(); port=32160
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"read-only formal town HTTP diagnostics")
	var defs: Array=(await rpc("tools/list")).result.tools
	check(defs.size()==118 and defs.filter(func(d):return d.name=="editor_state").size()==1,"current 3D MCP exposes diagnostics")
	var state:=await call_tool("editor_state")
	var walls: Array=editor._doc.records.filter(func(r):return r.has("fortification"))
	var frozen:=0; var dynamic:=0
	for r in walls:
		var visual=editor._view.get_node_or_null(str(r.uuid))
		if visual is MeshInstance3D and visual.mesh is Cpu: frozen+=1
		if r.has("fixture"):
			dynamic+=1
			check(visual is MeshInstance3D and not visual.mesh is Cpu,"moving fixture remains independent: "+str(r.uuid))
	var render: Dictionary=state.fortification_batching
	var collision: Dictionary=state.fortification_collision_batching
	check(walls.size()>4000 and render.source_objects>4000,"formal city defense participates in batching")
	check(frozen==render.source_objects,"batched source meshes have no duplicate GPU draw")
	check(render.groups<render.source_objects*.2 and render.render_surfaces<render.source_surfaces*.2,"formal town static meshes collapse into spatial batches")
	check(collision.bodies<collision.source_objects*.2,"formal town static collision bodies are merged")
	var settings: Dictionary=editor._doc.map_meta.editor_layout.fortifications[0].settings
	var locations: Array=[]
	for i in [0,settings.tower_indices.size()/2,settings.tower_indices.size()-1]:
		var p: Array=settings.points[int(settings.tower_indices[i])]; locations.append(Vector3(p[0],0,p[1]))
	var report:={"formal_sha256":hash_before,"logical_wall_records":walls.size(),"independent_fixture_records":dynamic,"cpu_only_sources":frozen,"editor_render":render,"editor_collision":collision,"runtime":[]}
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(TOWN); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"formal town opens through runtime loader")
	if loaded[0]!=null:
		var host:=Node3D.new(); root.add_child(host); var scene: Node3D=loaded[0]; host.add_child(scene)
		for point in locations:
			Stream.sync(scene,host,point); await physics()
			var rs: Dictionary=scene.get_node("GroundRenderBatches").stats("fortification")
			var cs: Dictionary=scene.get_node("FortificationCollisionBatches").stats()
			check(rs.source_objects>20 and rs.render_surfaces<rs.source_surfaces*.5,"runtime wall render batches at "+str(point))
			check(cs.source_objects>20 and cs.bodies<cs.source_objects*.4,"runtime wall collision batches at "+str(point))
			report.runtime.append({"point":[point.x,point.y,point.z],"render":rs,"collision":cs})
		host.free()
	check(FileAccess.get_sha256(TOWN)==hash_before,"formal map never rewritten by cache verification")
	report.failures=failed
	var file:=FileAccess.open(OUT,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("FORMAL_WALL_BATCH_ACTIVATION failures=",failed," records=",walls.size()," sources=",frozen," groups=",render.groups," bodies=",collision.bodies)
	quit(1 if failed else 0)
