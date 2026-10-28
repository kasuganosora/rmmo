extends "res://tools/test_world3d_mcp.gd"
const Local=preload("res://scripts/world_editor/terrain_local_publish.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
func triangles(faces:PackedVector3Array)->Dictionary:
	var result:Dictionary={}
	for i in range(0,faces.size(),3):
		var key:=var_to_bytes(faces.slice(i,i+3)).hex_encode();result[key]=result.get(key,0)+1
	return result
func run()->void:
	create_timer(120).timeout.connect(func():quit(2));Engine.max_fps=60;rpc_timeout_ms=60000
	var directory:=Paths.cache_directory("local_picking_load_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var doc:=Doc.new();var id:String=doc.add_box("grass",Vector3.ZERO,Vector3(64,1,64))
	var record:Dictionary=doc._find(id);record.collision="block"
	var heights:Array=[];var holes:Array=[]
	for z in 65:
		for x in 65:heights.append(sin(x*.11)*cos(z*.17)*.3)
	for z in 64:
		for x in 64:holes.append((x+z)%2==1 or (x==32 and z==32))
	record.terrain_mesh={"version":1,"columns":64,"rows":64,"floor":-2.,"heights":heights,"holes":holes}
	var path:=directory.path_join("map.gltf");var saved:=doc.save(path);check(saved==OK,"temporary dense terrain map saved")
	if saved!=OK:quit(1);return
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=Doc.new();session.world3d_editor_path=""
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;root.add_child(editor);editor._safety.enabled=false
	var server:=TCPServer.new()
	while server.listen(port,"127.0.0.1")!=OK:port+=1
	server.stop();check(editor.start_mcp(port).ok,"actual HTTP editor started")
	var previous:=Local.enabled;var local_hits:Array=[]
	for local:bool in [true,false]:
		Local.enabled=local
		await call_tool("open_world",{"path":path,"discard_changes":true})
		var state:Dictionary=editor._load_job.state();var units:Dictionary=state.timings.build.units
		check(state.phase=="complete",("local" if local else "fallback")+": actual LoadJob completed")
		var visual:MeshInstance3D=editor._view.get_node_or_null(id)
		var cpu:Mesh=Cpu.capture(visual.get_meta("paint_source",visual.mesh))
		if local:
			for field:String in ["surface_paint","terrain_grade"]:
				var excluded:Dictionary=record.duplicate(true);excluded[field]={}
				check(not Local.can_initialize(visual,excluded),field+": ineligible terrain keeps the whole-shape fallback")
			var unsupported:=MeshInstance3D.new();unsupported.mesh=BoxMesh.new()
			check(not Local.can_initialize(unsupported,record),"noncanonical surface topology keeps fallback");unsupported.free()
		check(cpu._collision_faces.is_empty() if local else not cpu._collision_faces.is_empty(),("local" if local else "fallback")+": full triangle soup exists only when consumed")
		check(editor._picking_shapes._entries.size()==(0 if local else 1),("local" if local else "fallback")+": full shape cache contains only consumed geometry")
		check(int(units.get("picking_shape",{}).get("count",0))==(0 if local else 1),("local" if local else "fallback")+": no discarded whole-shape preparation call")
		check(int(units.get("picking_faces_prepare",{}).get("count",0))==(0 if local else 1),("local" if local else "fallback")+": no discarded whole-face worker")
		var body:StaticBody3D=editor._bodies_by_uuid[id][0]
		check(body.get_child_count()==(16 if local else 1),("local" if local else "fallback")+": expected exact collider partition")
		if local:
			var soup:=PackedVector3Array()
			for child:CollisionShape3D in body.get_children():soup.append_array(child.shape.get_faces())
			# Build an independent oracle after work assertions; never prime the
			# production CPU mesh or its full-shape cache before load/measurement.
			var oracle:=Cpu.new();oracle.surfaces=Terrain.arrays(record)
			check(triangles(soup)==triangles(oracle.collision_faces()),"partition contains exactly the original ordered triangles with no loss/duplicates")
		await physics_frame;await physics_frame
		for point:Vector3 in [Vector3(-23.7,0,-13.8),Vector3(10.3,0,20.2),Vector3(.2,0,.2)]:
			var query:=PhysicsRayQueryParameters3D.create(point+Vector3(0,5,0),point-Vector3(0,5,0),1)
			var hit:Dictionary=editor.get_world_3d().direct_space_state.intersect_ray(query)
			var result:Dictionary={"hit":not hit.is_empty()}
			if not hit.is_empty():result.position=hit.position;result.normal=hit.normal;check(hit.collider==body,"picking returns the original terrain record body")
			query.collision_mask=preload("res://scripts/world_editor/walk_mode.gd").WALK_MASK
			var walked:Dictionary=editor.get_world_3d().direct_space_state.intersect_ray(query)
			check(walked.is_empty()==hit.is_empty() and (walked.is_empty() or (walked.collider==body and walked.position.distance_to(hit.position)<.0001)),"walk collision preserves the same surface and open holes")
			if local:local_hits.append(result)
			else:
				var expected:Dictionary=local_hits.pop_front()
				check(result.hit==expected.hit and (not result.hit or (result.position.distance_to(expected.position)<.0001 and result.normal.distance_to(expected.normal)<.0001)),"partitioned and whole collider return the same hit position/normal or hole")
		await call_tool("save_world");check(editor._save_job.result.get("saved",false),"actual save preserves terrain")
		print("LOCAL_PICKING_WORK ",JSON.stringify({"local":local,"picking_shape":units.get("picking_shape",{}),"picking_faces_prepare":units.get("picking_faces_prepare",{}),"entries":editor._picking_shapes._entries.size()}))
	Local.enabled=previous;editor.queue_free();await settle()
	print("EDITOR_LOCAL_TERRAIN_PICKING_FAILED=",failed);quit(1 if failed else 0)
