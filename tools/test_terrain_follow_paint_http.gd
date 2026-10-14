extends "res://tools/test_world3d_mcp.gd"
const City=preload("res://scripts/world3d/city_layout.gd")
const Follow=preload("res://scripts/world_editor/terrain_follow_tools.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
func run()->void:
	create_timer(210).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	var directory:=Paths.cache_directory("terrain_follow_paint_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc=Doc.new()
	var heights:Array=[];heights.resize(289);heights.fill(0.);var holes:Array=[];holes.resize(256);holes.fill(false)
	doc.records=[{"uuid":"ground","kind":"box","surface_id":"ground","position":[16.,0.,16.],"rotation":[0,0,0],"size":[32.,1.,32.],"color":[.3,.4,.2],"collision":"walk","terrain_mesh":{"version":1,"columns":16,"rows":16,"floor":-8.,"heights":heights,"holes":holes}}]
	doc.map_meta.editor_layout=City.defaults();doc.map_meta.editor_layout.roads={"nodes":[{"id":"a","position":[6.,0.,16.]},{"id":"b","position":[26.,0.,16.]}],"edges":[{"id":"lane","from":"a","to":"b","width_start":4.,"width_end":4.,"kind":"ground"}]}
	check(doc.save(path)==OK,"isolated default-paint fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31990
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real default-paint HTTP listens on loopback")
	var discovery:=await rpc("tools/list");var names:Array=discovery.get("result",{}).get("tools",[]).map(func(t):return t.name)
	check(names.has("sculpt_terrain") and names.has("generate_road_surface") and not names.has("paint_tile"),"current 3D terrain and road tools discovered")
	await call_tool("generate_road_surface",{"follow_terrain":true,"material_id":"pack:default:paving/outdoor_flagstone/material"})
	var roads:Array=editor._doc.records.filter(func(r):return r.has("road_mesh"));check(not roads.is_empty(),"native textured terrain-follow road exists")
	# Reproduce authored JSON evidence: JSON decodes integer zero as float.
	# This is fixture ingress, not an alternative edit path under test.
	for r:Dictionary in roads:r.surface_paint=JSON.parse_string(JSON.stringify(r.surface_paint))
	check(roads.all(func(r):return r.surface_paint[0].offset[0] is float and Follow.automatic_paint(r.surface_paint)),"JSON zero offsets retain valid automatic UV paint")
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var stroke:={"id":"ground","mode":"raise","points":[[16.,16.]],"radius":6.,"strength":.05}
	await call_tool("sculpt_terrain",stroke)
	var after:Dictionary=editor._doc.recovery_snapshot()
	check(not equivalent(before.records,after.records) and history+1==editor._doc._undo.size(),"JSON default paint permits one terrain-and-road transaction")
	check(after.records.filter(func(r):return r.has("road_mesh")).all(func(r):return Surface.valid(r) and Paint.valid(r) and Follow.automatic_paint(r.surface_paint)),"refitted pavement retains valid default PBR paint")
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"undo restores terrain pavement and JSON paint together")
	await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"redo restores complete follower transaction")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(equivalent(after.records,editor._doc.records) and equivalent(after.map_meta,editor._doc.map_meta),"JSON-paint sculpt result survives native save and reopen")
	var normal:Dictionary=editor._doc.recovery_snapshot();roads=editor._doc.records.filter(func(r):return r.has("road_mesh"));roads.sort_custom(func(a,b):return a.surface_paint.size()>b.surface_paint.size())
	var id:String=roads[0].uuid;check(roads[0].surface_paint.size()>1,"sloped fixture has distinct faces for mixed-material protection")
	for kind in ["offset","rotation","scale","mixed_material"]:
		editor._doc.apply_recovery(normal)
		var changed:Dictionary=editor._doc._find(id);changed.surface_paint=JSON.parse_string(JSON.stringify(changed.surface_paint))
		match kind:
			"offset":changed.surface_paint[0].offset[0]=.125
			"rotation":changed.surface_paint[0].rotation=15.
			"scale":changed.surface_paint[0].scale[0]*=1.25
			"mixed_material":changed.surface_paint[0].material=changed.surface_paint[0].material.duplicate(true);changed.surface_paint[0].material.color=[.8,1.,1.,1.]
		check(Paint.valid(changed) and not Follow.automatic_paint(changed.surface_paint),"valid manual "+kind+" is distinguished from default paint")
		var manual:Dictionary=editor._doc.recovery_snapshot();history=editor._doc._undo.size()
		var rejection:=await call_tool("sculpt_terrain",stroke,false)
		check(str(rejection.get("error","")).contains("手工刷面"),"manual "+kind+" rejects for paint protection specifically")
		check(equivalent(manual,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"manual "+kind+" rejection has no terrain road metadata or history side effects")
	editor._doc.apply_recovery(normal);editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("TERRAIN_FOLLOW_PAINT_HTTP ",directory," failures=",failed);quit(1 if failed else 0)
