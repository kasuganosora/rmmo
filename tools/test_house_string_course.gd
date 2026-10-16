extends "res://tools/test_world3d_mcp.gd"
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Arch=preload("res://scripts/world3d/house_arched_entrance.gd")
const Wall=preload("res://scripts/world3d/house_wall_mesh.gd")
const Prism=preload("res://scripts/world3d/roof_mesh.gd")
func parameters()->Dictionary:
	return {"layout":"hall","template":"house","width":12.0,"depth":12.0,"floors":2,"floor_height":3.3,"rooms_per_floor":2,"style":"plaster","compound":"none","roof_axis":"depth","roof_pitch":39.0,"dormers":2,"front_canopy":false,"jetty":0.0,"window_style":"cross_lattice","base_height":.3,"entrance_style":"round_arch_hall","entrance_arch_width":2.28,"entrance_arch_spring":3.67}
func small_parameters()->Dictionary:
	return {"layout":"townhouse","template":"house","width":8.0,"depth":8.0,"floors":1,"style":"plaster","compound":"none","base_height":.15,"roof_axis":"width","roof_pitch":34.0,"dormers":0,"chimney":true,"front_canopy":false}
func front_faces(plan:Dictionary)->PackedVector3Array:
	var result:=PackedVector3Array()
	for r:Dictionary in plan.records:
		if not str(r.building.part).contains("/north/") or r.building.role!="wall":continue
		var mesh:Mesh=Wall.mesh(r,null) if r.has("wall_grid") else Prism.mesh(r,null)
		for p:Vector3 in mesh.get_faces():result.append(p+Vector3(r.position[0],r.position[1],r.position[2]))
	return result
func hit(faces:PackedVector3Array,x:float,y:float,z:float)->bool:
	for i in range(0,faces.size(),3):
		if Geometry3D.segment_intersects_triangle(Vector3(x,y,z-.5),Vector3(x,y,z+.5),faces[i],faces[i+1],faces[i+2])!=null:return true
	return false
func geometry_checks(p:Dictionary)->void:
	var plan:=B.generate(p);check(plan.get("ok",false),"S12 hall generates: "+str(plan.get("error","")))
	if not plan.get("ok",false):return
	var u:=Arch.center(plan.parameters);var front:float=-p.depth/2+.1;var base:float=p.base_height
	var faces:=front_faces(plan)
	for y in [.15,1.8,3.29,3.31,3.65,4.3,4.7]:check(not hit(faces,u,base+y,front),"true aperture at head height "+str(y))
	check(hit(faces,u,base+4.87,front),"masonry above arch crown is solid")
	check(hit(faces,u+1.08,base+4.15,front),"upper rectangular corner is filled by curved spandrel")
	check(not hit(faces,u+.8,base+4.15,front),"inside circular arch remains open")
	check(hit(faces,u+1.3,base+1.8,front),"jamb-side masonry remains solid")
	check(plan.records.filter(func(r):return r.building.part.contains("arch_infill")).all(func(r):return Prism.valid(r) and r.get("collision","")!="none"),"all curved wall prisms retain valid real collision")
	check(not plan.records.any(func(r):return r.building.part=="f0/north/course"),"storey string course does not cut across the aperture")
	check(not plan.records.any(func(r):return r.get("fixture",{}).get("id","").begins_with("f0/north/entrance")),"no rectangular door leaf spans the high arch")
	check(plan.records.any(func(r):return r.building.part.begins_with("f0/north/entry_step")),"raised arch receives real entrance steps")
	var blocking:Array=plan.records.filter(func(r):return r.building.floor==1 and r.building.role=="floor" and r.position[2]-r.size[2]/2<front+.4)
	check(blocking.is_empty(),"shared hall floor void keeps arch free of upper slab")
	check(plan.rooms.any(func(r):return r.floor==1) and not plan.stairs.is_empty(),"rear residential upper floor and stair semantics remain")
	var legacy:Dictionary=p.duplicate();legacy.erase("entrance_style");legacy.erase("entrance_arch_width");legacy.erase("entrance_arch_spring")
	var explicit:=legacy.merged({"entrance_style":"rectangular"})
	check(equivalent(B.generate(legacy).records,B.generate(explicit).records),"optional field preserves old rectangular geometry exactly")
func run()->void:
	create_timer(300).timeout.connect(func():quit(2));rpc_timeout_ms=180000
	var p:=parameters();geometry_checks(p)
	var old:=B.generate(p)
	check(equivalent(old.records,B.generate(p.merged({"front_string_course":"full"})).records),"default full geometry unchanged")
	p.front_string_course="none"
	var revised:=B.generate(p)
	var retained:Array=old.records.filter(func(r):return not (str(r.building.part).begins_with("f") and str(r.building.part).ends_with("/north/course")))
	check(equivalent(retained,revised.records),"only main front course removed, every other component unchanged")
	var small:=small_parameters();var small_plan:=B.generate(small)
	check(small_plan.ok and small_plan.entrance==[-2.8,0,-5.0],"native 8x8 single-storey cottage has correct outdoor entrance")
	check(not B.generate(small.merged({"floors":2},true)).ok,"short depth cannot shrink multi-storey stair run")
	check(not B.generate(small.merged({"layout":"hall"},true)).ok,"short depth does not bypass hall sizing")
	for height in [3.0,4.0]:
		var adjusted:=p.merged({"floor_height":height,"depth":15.0},true)
		var plan:=B.generate(adjusted);check(plan.ok and plan.records.filter(func(r):return r.building.part.contains("arch_infill")).all(func(r):return Prism.valid(r)),"arch clips correctly at "+str(height)+" m storey")
	if "--geometry-only" in OS.get_cmdline_user_args():quit(1 if failed else 0);return
	var directory:=Paths.cache_directory("arched_entrance_http_%d"%OS.get_process_id());var path:=directory.path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.3,0),Vector3(50,.6,50))
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start real 3D HTTP")
	var defs:=await call_tool("list_building_templates")
	check(defs.parameters_schema.properties.entrance_style.enum.has("round_arch_hall"),"arched hall schema discoverable")
	check(float(defs.parameters_schema.properties.depth.minimum)==8.0,"native 8m cottage depth discoverable")
	check(defs.parameters_schema.properties.front_string_course.enum==["full","none"],"string course schema discovery")
	var invalid_before:=doc.recovery_snapshot()
	for invalid in ["partial",false,1]:
		await call_tool("generate_buildings",{"parameters":p.merged({"front_string_course":invalid},true),"placements":[{"position":[0,0,0]}]},false)
		check(equivalent(invalid_before,doc.recovery_snapshot()),"invalid string course atomic rejection "+str(invalid))
	var small_before:=doc.recovery_snapshot()
	var small_preview:=await call_tool("preview_buildings",{"parameters":small,"placements":[{"position":[15,0,0],"yaw":180}]})
	check(small_preview.get("ok",false) and equivalent(small_before,doc.recovery_snapshot()),"8x8 cottage real HTTP preview is side-effect free")
	await call_tool("generate_buildings",{"parameters":small.merged({"floors":2},true),"placements":[{"position":[15,0,0]}]},false)
	check(equivalent(small_before,doc.recovery_snapshot()),"invalid short two-storey cottage fails HTTP without side effects")
	var before:=doc.recovery_snapshot();var args:={"parameters":p,"placements":[{"position":[0,0,0],"yaw":90}]}
	await call_tool("preview_buildings",args);check(equivalent(before,doc.recovery_snapshot()),"arch preview has no side effects")
	await call_tool("generate_buildings",{"parameters":p.merged({"layout":"townhouse"},true),"placements":[{"position":[0,0,0]}]},false)
	check(equivalent(before,doc.recovery_snapshot()),"invalid upper-floor obstruction fails atomically")
	var made:=await call_tool("generate_buildings",args)
	if not made.get("ok",false):editor._mcp.stop();editor.free();quit(1);return
	var id:String=made.building_ids[0];var generated:=doc.recovery_snapshot()
	check(doc.map_meta.building_instances[id].baked,"native arch freezes with house ownership")
	check(B.valid_ownership(doc.map_meta,doc.records),"native arch preserves editable floor/fixture ownership")
	await call_tool("undo")
	# Native history intentionally keeps the ID allocator monotonic to avoid
	# reusing identities held by asynchronous derived work after an undo.
	var undone:=doc.recovery_snapshot();var before_content:=before.duplicate(true)
	check(int(undone.next)>=int(before.next),"undo preserves native monotonic identity allocator")
	undone.erase("next");before_content.erase("next")
	check(equivalent(before_content,undone),"undo removes complete arch house and metadata")
	await call_tool("redo");check(equivalent(generated,doc.recovery_snapshot()),"redo restores complete arch house")
	await call_tool("save_world");var reopened=Doc.open_file(path)
	check(reopened!=null and equivalent(doc.records,reopened.records) and equivalent(doc.map_meta,reopened.map_meta),"native arch save/reopen identity retained")
	editor._mcp.stop();editor.queue_free();await settle();print("ARCHED_ENTRANCE_HTTP failures=",failed);quit(1 if failed else 0)
