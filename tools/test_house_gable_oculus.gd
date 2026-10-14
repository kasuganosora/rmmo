extends "res://tools/test_world3d_buildings.gd"
const Oculus=preload("res://scripts/world3d/house_gable_oculus.gd")
const Prism=preload("res://scripts/world3d/roof_mesh.gd")

func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var p:Dictionary=Blueprint.defaults().merged({"layout":"townhouse","template":"house","width":9.,"depth":11.,"floors":1,"floor_height":3.5,"base_height":.3,"style":"plaster","roof_axis":"depth","roof_pitch":36.,"chimney":false,"front_canopy":false,"gable_oculus":true},true)
	var plan:=Blueprint.generate(p)
	check(plan.get("ok",false),"native roof builds a real front oculus")
	if not plan.get("ok",false):print(plan);quit(1);return
	var opening:Array=plan.openings.filter(func(o):return o.id=="gable_oculus")
	check(opening.size()==1 and opening[0].shape=="circle" and is_equal_approx(opening[0].width,1.12),"fixed attic window describes its real 1.12m clear opening")
	var o:Dictionary=opening[0];var cy:float=o.floor_y+o.bottom+o.height*.5;var z:float=-p.depth/2.
	check(not wall_hit(plan.records,Vector3(.18,cy+.18,z-.5),Vector3(.18,cy+.18,z+.5)),"actual native collision triangles leave the oculus clear of plaster")
	check(wall_hit(plan.records,Vector3(.85,cy,z-.5),Vector3(.85,cy,z+.5)),"solid gable adjacent to the oculus retains collision")
	check(not wall_hit(plan.records,Vector3(-.3,cy-.22,z-.5),Vector3(-.3,cy-.22,z+.5)),"off-axis lower circle also cuts through both wall faces")
	check(plan.records.filter(func(r):return str(r.building.part).begins_with("roof/oculus/frame")).size()==32,"continuous 32-segment rebated timber ring")
	check(plan.records.filter(func(r):return str(r.building.part).begins_with("roof/oculus/stone_ring") and r.building.role=="stone_trim").size()==32,"separate pale stone surround preserves the approved window material layout")
	check(plan.records.filter(func(r):return str(r.building.part).begins_with("roof/oculus/")).all(func(r):return r.building.floor==1),"frame glazing and mullions retain roof-level hiding semantics")
	check(plan.records.all(func(r):return not r.has("roof_mesh") or Prism.valid(r)),"all output uses valid editable native convex prisms")
	var old:Dictionary=p.duplicate(true);old.erase("gable_oculus")
	check(equivalent(Blueprint.generate(old).records,Blueprint.generate(old.merged({"gable_oculus":false},true)).records),"omitted field and false preserve pre-existing house geometry")
	check(not Blueprint.generate(p.merged({"width":5.5,"roof_pitch":25.},true)).ok,"insufficient gable stone margins are rejected")
	var directory:=Paths.cache_directory("house_oculus_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.2,0),Vector3(50,.4,50));check(doc.save(path)==OK,"isolated oculus map saved")
	Net.session().world3d_editor_path=path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await physics();editor._safety.enabled=false
	var probe:=TCPServer.new();port=31920
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real loopback 3D HTTP MCP started")
	var templates:=await call_tool("list_building_templates")
	check(templates.parameters_schema.properties.get("gable_oculus",{}).get("type")=="boolean","shared UI/MCP schema discovers optional gable_oculus")
	var before:=doc.recovery_snapshot();var history:int=doc._undo.size()
	for invalid:Dictionary in [{"roof_axis":"width"},{"style":"timber"},{"roof_solver":"legacy"},{"gable_oculus":"yes"}]:
		await call_tool("generate_buildings",{"parameters":p.merged(invalid,true),"placements":[{"position":[0,0,0]}]},false)
	check(equivalent(before,doc.recovery_snapshot()) and history==doc._undo.size(),"invalid combinations have no map or undo side effects")
	var args:Dictionary={"parameters":p,"placements":[{"position":[0,0,0]}]}
	var preview:=await call_tool("preview_buildings",args)
	check(preview.get("ok",false) and equivalent(before,doc.recovery_snapshot()),"real HTTP preview is non-mutating")
	var made:=await call_tool("generate_buildings",args)
	if not made.get("ok",false):editor.free();quit(1);return
	var id:String=made.building_ids[0];var frozen:Array=doc.records.duplicate(true)
	check(doc.map_meta.building_instances[id].get("baked",false) and doc.map_meta.building_instances[id].parameters.gable_oculus,"native generation bakes compact geometry while preserving the recipe")
	check(doc._undo.size()==history+1,"house creation is one undo transaction")
	await call_tool("undo");check(equivalent(doc.records,before.records),"undo restores the complete prior map")
	await call_tool("redo");check(equivalent(doc.records,frozen),"redo restores identical native geometry")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(equivalent(editor._doc.records,frozen) and editor._doc.map_meta.building_instances[id].parameters.gable_oculus,"actual save and reopen preserve circular geometry and optional field")
	check(Blueprint.valid_meta({"building_instances":{id:{"version":Blueprint.VERSION,"parameters":old,"position":[0,0,0],"yaw":0,"parts":{},"signatures":{},"baked":true}}}),"version-8 native metadata remains valid without the new optional field")
	editor._mcp.stop();editor.queue_free();await settle();Net.session().world3d_editor_path="";Net.session().world3d_editor_doc=null
	print("HOUSE_GABLE_OCULUS_HTTP ",directory," failures=",failed);quit(failed)

func wall_hit(records:Array,a:Vector3,b:Vector3)->bool:
	for r:Dictionary in records:
		if not str(r.get("building",{}).get("part","")).begins_with("roof/gable0/"):continue
		var mesh:Mesh=Prism.mesh(r,null);var faces:=mesh.get_faces();var pose:=Transform3D(Basis.IDENTITY,Blueprint.vec(r.position))
		for i in range(0,faces.size(),3):
			if Geometry3D.segment_intersects_triangle(a,b,pose*faces[i],pose*faces[i+1],pose*faces[i+2])!=null:return true
	return false
