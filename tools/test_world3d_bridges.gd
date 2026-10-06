extends "res://tools/test_world3d_waterways.gd"
const BridgeData=preload("res://scripts/world3d/bridge_data.gd")
const BridgeMesh=preload("res://scripts/world3d/bridge_mesh.gd")
var cases: Array=[]
func run() -> void:
	create_timer(400).timeout.connect(func():quit(2))
	root.size=Vector2i(1500,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("stone_bridges_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("stone",Vector3(0,-5.25,0),Vector3(160,.5,150))
	for i in 3:
		var length_: float=[14.,30.,58.][i]; var z: float=(i-1)*40
		for side in [-1,1]: doc.add_box("grass",Vector3(side*(length_*.5+5),-.25,z),Vector3(10,.5,16))
		cases.append({"id":"test_bridge_%d"%i,"prefab_id":["stone_rustic","stone_pointed","stone_segmental"][i],"start":[-length_*.5,0,z],"end":[length_*.5,0,z],"width":[5.,7.,9.][i],"depth":5.0,"camber":[0.,.8,2.][i]})
	check(doc.save(map_path)==OK,"temporary bridge test map saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	editor._bridges.library.directory=directory.path_join("prefabs")
	var probe:=TCPServer.new(); port=30660
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"bridge HTTP MCP starts")
	var definitions: Array=(await rpc("tools/list")).result.tools
	check(definitions.size()==118 and definitions.any(func(d):return d.name=="preview_bridge" and d.annotations.readOnlyHint) and not definitions.any(func(d):return d.name=="paint_tile"),"118 current 3D tools; no legacy 2D")
	check((await call_tool("list_bridge_prefabs")).prefabs.size()>=3,"three Blender bridge prefab choices")
	var baseline: Dictionary=editor._doc.recovery_snapshot()
	for args in cases:
		var preview:=await call_tool("preview_bridge",args)
		if not preview.ok: quit(1); return
		var history: int=editor._doc._undo.size()
		await atomic_reject("generate_bridge",args.merged({"plan_token":"stale"}))
		await call_tool("generate_bridge",args.merged({"plan_token":preview.plan_token})); check(editor._doc._undo.size()==history+1,"one transaction per bridge")
		var r: Dictionary=editor._doc._find(args.id); var mesh:=BridgeMesh.new().build(r)
		check(mesh!=null and mesh.get_surface_count()==3,"single batched mesh with three PBR slots")
		var triangles:=0
		for slot in mesh.get_surface_count():
			var mat: StandardMaterial3D=mesh.surface_get_material(slot)
			check(mat.albedo_texture!=null and mat.normal_enabled and mat.normal_texture!=null,"actual default-library albedo and normal")
			triangles+=mesh.surface_get_array_index_len(slot)/3
		print("BRIDGE_MESH ",args.id," triangles=",triangles," bounds=",mesh.get_aabb())
		print("BRIDGE_LODS ",mesh.get_meta("bridge_lods")," BUILD_MS ",mesh.get_meta("bridge_build_ms"))
		check(mesh.get_meta("bridge_lods").slice(1).all(func(levels):return not levels.is_empty()),"masonry and stone details include distance LODs; simple deck stays exact")
		check(triangles<100000,"bounded bridge geometry budget")
		check(mesh.get_aabb().position.y>=-5.01 and mesh.get_aabb().end.y<args.camber+1.51,"generated bridge bounds and foundations")
		await call_tool("undo"); check(editor._doc._find(args.id).is_empty(),"undo removes entire bridge")
		await call_tool("redo"); check(equivalent(r,editor._doc._find(args.id)),"redo exact IDs and params")
		var no_op:=await call_tool("generate_bridge",args); check(not no_op.changed,"identical request is idempotent")
	for bad in [{"prefab_id":"missing"},{"camber":5.},{"width":1.},{"arches":20},{"end":[7,2,-40]}]: await atomic_reject("generate_bridge",cases[0].merged(bad,true))
	for flag in ["locked","hidden"]:
		await call_tool("set_object_properties",{"ids":[cases[0].id],flag:true}); await atomic_reject("generate_bridge",cases[0]); await call_tool("undo")
	await call_tool("set_floor_view",{"isolation":true,"base_height":40}); await atomic_reject("generate_bridge",cases[0]); await call_tool("undo")
	var obstacle: String=editor._doc.add_box("block",Vector3(0,1,-40),Vector3(1,2,1)); editor._doc._find(obstacle).editor_hidden=true; editor._rebuild()
	await atomic_reject("generate_bridge",cases[0]); editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=obstacle); editor._rebuild()
	var saved:=await call_tool("save_bridge_prefab",{"id":cases[1].id,"name":"测试自定义石桥"}); check(saved.ok,"custom bridge recipe saved")
	check((await call_tool("list_bridge_prefabs")).prefabs.any(func(p):return p.id==saved.prefab.id),"custom prefab discovered")
	for dimensions in [[1.5,16.0],[15.0,3.0]]:
		var boundary: Dictionary=editor._doc._find(cases[1].id).duplicate(true); boundary.bridge_mesh.depth=dimensions[0]; boundary.bridge_mesh.width=dimensions[1]
		var mesh:=BridgeMesh.new().build(boundary); var box: AABB=mesh.get_aabb(); var expected:=BridgeData.dimensions(boundary.bridge_mesh)
		check(absf(box.position.y+dimensions[0])<.001 and box.size.z<=expected.z and box.end.y<boundary.bridge_mesh.camber+1.7,"shallow/deep narrow/wide geometry stays within placement bounds")
	await call_tool("generate_bridge",cases[1].merged({"prefab_id":saved.prefab.id},true)); check(editor._doc._find(cases[1].id).bridge_mesh.prefab_id==saved.prefab.id,"saved prefab used through real HTTP"); await call_tool("undo")
	var ui: VBoxContainer=editor._city.panel.bridge_panel; editor._dock_tabs.current_tab=9
	ui.current_id=cases[1].id; ui.build({"start":cases[1].start,"end":cases[1].end,"width":7.,"depth":5.,"camber":.7,"arches":0})
	ui.show_preview(); check(not ui.preview.is_empty(),"UI actual mesh preview uses shared planner")
	var before: Dictionary=editor._doc.recovery_snapshot(); check(editor._bridges.preview_node!=null,"preview geometry exists outside document")
	ui.apply(); check(editor._doc._find(cases[1].id).bridge_mesh.camber==.7,"UI applies camber"); await call_tool("undo"); check(equivalent(before,editor._doc.recovery_snapshot()),"UI undo restores exact bridge")
	await call_tool("save_world"); var saved_doc: Dictionary=editor._doc.recovery_snapshot(); await call_tool("open_world",{"path":map_path}); check(equivalent(saved_doc.records,editor._doc.records),"save/reopen retains module recipe and textures")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,-.3,0],"distance":102,"pitch":-32,"yaw":28}); editor._grid.hide(); await settle(); await RenderingServer.frame_post_draw
	editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("three_bridges.png"))
	for i in 3:
		await call_tool("set_editor_camera",{"projection":"perspective","center":[0,-.6,cases[i].start[2]],"distance":[20,34,65][i],"pitch":-18,"yaw":20}); await settle(); await RenderingServer.frame_post_draw
		editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("bridge_%d.png"%i))
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"saved modular bridge runtime loads")
	if loaded[0]!=null: await bridge_runtime(loaded[0])
	print("BRIDGE_ARTIFACTS "+directory); print("WORLD3D_BRIDGES_FINISHED failures=%d"%failed); quit(0 if failed==0 else 1)
func bridge_runtime(scene: Node3D) -> void:
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene); Stream.sync(scene,host,Vector3.ZERO); await physics()
	var body:=CharacterBody3D.new(); var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.height=2.1; capsule.radius=.3; shape.shape=capsule; body.add_child(shape); host.add_child(body); body.floor_snap_length=.3
	for c in cases:
		var length_: float=c.end[0]-c.start[0]
		for direction in [1,-1]:
			body.position=Vector3((-length_*.5-1)*direction,1.08,c.start[2]); body.velocity=Vector3.ZERO; var grounded:=true
			for frame in 1800:
				await physics_frame; body.velocity=Vector3(7*direction,-2,0); body.move_and_slide()
				if frame>8: grounded=grounded and body.is_on_floor()
				if body.position.x*direction>length_*.5+.8: break
			check(grounded and body.position.x*direction>length_*.5+.8,"2.1m capsule crosses flat/cambered bridge both ways: "+c.id+" / "+str(direction))
		body.position=Vector3(0,c.camber+1.08,c.start[2]); body.velocity=Vector3.ZERO
		for frame in 150:
			await physics_frame; body.velocity=Vector3(0,-2,5); body.move_and_slide()
		check(body.is_on_floor() and body.position.z<c.start[2]+c.width*.5-.4,"stone parapet blocks a walking capsule: "+c.id)
		# Cast across an arch opening; a bounding-box collider would incorrectly block it.
		var preset:=BridgeData.preset(c.prefab_id); var count:=ceili((length_-2+preset.recipe.pier_width)/(preset.recipe.max_span+preset.recipe.pier_width)); var opening: float=(length_-2-(count-1)*preset.recipe.pier_width)/count
		var x: float=-length_*.5+1+opening*.5
		var hit:=host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,-1,c.start[2]-c.width),Vector3(x,-1,c.start[2]+c.width)))
		check(hit.is_empty(),"arch opening retains true empty collision space: "+c.id)
	host.free()
