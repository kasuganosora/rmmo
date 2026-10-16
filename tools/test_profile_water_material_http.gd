extends "res://tools/test_world3d_mcp.gd"
## Steep longitudinal water remains visible in both editor and runtime indexing.
const River=preload("res://scripts/world3d/river_materials.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Layer=preload("res://scripts/world3d/terrain_river_layer.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
var checks:Array=[]
func check(ok:bool,label:String)->void:
	checks.append({"passed":ok,"label":label});super.check(ok,label)
func materials(doc,ids:Array,label:String)->void:
	var old_hidden:=0;var mixed:=0;var editor_ok:=true;var cpu_ok:=true;var hidden_ok:=true
	for id:String in ids:
		var record:Dictionary=doc._find(id)
		var editable:MeshInstance3D=doc._mesh(record)
		var arrays:Array=editable.mesh.surface_get_arrays(0);var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		if normals[0].y<=.99:old_hidden+=1
		var flat:=false;var steep:=false
		for n:Vector3 in normals:
			flat=flat or n.y>.99;steep=steep or n.y<=.99
		if flat and steep:mixed+=1
		editor_ok=editor_ok and editable.get_active_material(0) is ShaderMaterial and editable.get_active_material(0).resource_name=="River depth water"
		hidden_ok=hidden_ok and editable.get_active_material(1)==River.hidden_slab and editable.get_active_material(2)==River.hidden_slab
		var indexed:=MeshInstance3D.new();var source:=Channel.mesh(record,StandardMaterial3D.new());indexed.mesh=Cpu.capture(source)
		var geometry:=City.token(Cpu.capture(source).surfaces)
		River.apply(indexed,record,{},null,true,true)
		var overrides:Array=indexed.get_meta(River.CPU_SURFACE_OVERRIDES_META,[])
		cpu_ok=cpu_ok and indexed.mesh is Cpu and overrides.size()==3 and overrides[0].resource_name=="River depth water" and overrides[1]==River.hidden_slab and overrides[2]==River.hidden_slab
		cpu_ok=cpu_ok and City.token(indexed.mesh.surfaces)==geometry
		editable.free();indexed.free()
	check(old_hidden>0,label+": actual fixture exercises the old steep-top disappearance")
	check(mixed>0,label+": one native top surface mixes flat and steep triangles")
	check(editor_ok,label+": every native editable profile top gets water shader")
	check(cpu_ok,label+": runtime CPU indexing keeps identical geometry and correct water slots")
	check(hidden_ok,label+": all underside and vertical edge slots remain hidden")
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var directory:=Paths.cache_directory("profile_water_material_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");check(Doc.new().save(path)==OK,"isolated native fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32940
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real 3D HTTP MCP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(t):return t.name=="generate_terrain_river" and t.inputSchema.properties.has("water_levels")),"existing 3D profile schema remains discoverable without new parameters")
	var terrain:=await call_tool("create_terrain",{"center":[0,0,0],"width":32,"depth":16,"cell_size":.5})
	var request:={"id":"steep_material_fixture","terrain_ids":[terrain.id],"points":[[-12,0],[-7,0],[5,0],[12,0]],"water_level":-.3,"water_levels":[-.3,-.3,-4,-4],"width":3.,"bank_width":1.,"depth":.6,"curved":false,"natural_materials":false}
	var before:Dictionary=editor._doc.recovery_snapshot()
	var invalid:=request.duplicate(true);invalid.water_levels[2]=1
	await call_tool("generate_terrain_river",invalid,false)
	check(equivalent(before,editor._doc.recovery_snapshot()),"invalid uphill profile remains atomic")
	await call_tool("preview_terrain_river",request)
	check(equivalent(before,editor._doc.recovery_snapshot()),"profile preview has no document side effects")
	var generated:=await call_tool("generate_terrain_river",request)
	if generated.get("water_ids",[]).is_empty():quit(1);return
	materials(editor._doc,generated.water_ids,"generated")
	var panel=editor._terrain_panel.river_panel
	check(panel.load_river(request.id) and equivalent(panel.args().water_levels,request.water_levels),"UI loads the same native steep profile used by HTTP")
	var record:Dictionary=editor._doc._find(generated.water_ids[0])
	check(not River.water_top(record,1,PackedVector3Array([Vector3.UP])) and not River.water_top(record,2,PackedVector3Array([Vector3.UP])),"semantic underside/edge slots never become water even with upward test normals")
	check(not River.water_top(record,0,PackedVector3Array([Vector3.DOWN])) and not River.water_top(record,0,PackedVector3Array([Vector3.UP,Vector3.DOWN])),"malformed top with inverted normals remains hidden")
	var flat:=record.duplicate(true);flat.channel_mesh.erase("elevations")
	check(River.water_top(flat,0,PackedVector3Array([Vector3.UP])) and not River.water_top(flat,1,PackedVector3Array([Vector3.DOWN])) and not River.water_top(flat,2,PackedVector3Array([Vector3.RIGHT])),"legacy flat water top and hidden slab behavior unchanged")
	var painted:=record.duplicate(true);painted.surface_paint=[]
	check(not River.water_top(painted,0,PackedVector3Array([Vector3(.3,.9,0).normalized()])),"painted/reordered slots do not claim native slab identity")
	var after:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"one undo restores river geometry and metadata")
	await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"redo restores exact native river identity")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(Layer.valid(editor._doc.map_meta),"saved profiled river ownership remains valid")
	materials(editor._doc,generated.water_ids,"native reopen")
	await call_tool("generate_terrain_river",request)
	var ids:Array=editor._doc.map_meta.terrain_rivers[0].water.map(func(w):return w.id)
	materials(editor._doc,ids,"native regenerate")
	check(Layer.valid(editor._doc.map_meta),"regeneration retains native editable ownership")
	var report:={"status":"passed" if failed==0 else "failed","failures":failed,"checks":checks,"fixture":path,"scope":"real HTTP profile generation/regeneration, native save/reopen, editor and runtime CPU material assignment; no GPU visual approval","limits":["Native profile channel slabs without surface_paint only; painted meshes may merge/reorder original surfaces and retain prior conservative classification.","No geometry, ownership, water level, schema or collision change."],"river_materials_sha256":FileAccess.get_sha256("res://scripts/world3d/river_materials.gd")}
	var file:=FileAccess.open(OUT+"/profile_water_material_http.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("PROFILE_WATER_MATERIAL_HTTP failures=",failed," checks=",checks.size());editor._mcp.stop();editor.queue_free();await settle();quit(failed)
