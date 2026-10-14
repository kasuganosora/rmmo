extends "res://tools/test_world3d_mcp.gd"
## Actual HTTP error reporting for an intentionally steep native terrain.
const City=preload("res://scripts/world3d/city_layout.gd")

func run()->void:
	create_timer(90).timeout.connect(func():quit(2));rpc_timeout_ms=45000
	var directory:String=Paths.cache_directory("terrain_grade_diagnostic_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:String=directory.path_join("map.gltf");var doc=Doc.new();var heights:Array=[];var holes:Array=[]
	for z in 13:
		for x in 13:heights.append((x*2.-12.)*.25)
	holes.resize(144);holes.fill(false)
	doc.records=[{"uuid":"known_quarter_slope","kind":"box","surface_id":"ground","position":[512.,5.,512.],"rotation":[0,0,0],"size":[24.,1.,24.],"color":[.3,.4,.2],"collision":"walk","terrain_mesh":{"version":1,"columns":12,"rows":12,"floor":-8.,"heights":heights,"holes":holes}}]
	doc.map_meta.editor_layout=City.defaults()
	doc.map_meta.editor_layout.roads={"nodes":[{"id":"a","position":[508.,5.,512.]},{"id":"b","position":[516.,5.,512.]}],"edges":[{"id":"test_road","from":"a","to":"b","width_start":4.,"width_end":4.,"kind":"ground"}]}
	check(doc.save(path)==OK,"isolated native slope fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31980
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"slope diagnostic HTTP listens on loopback")
	var args:Dictionary={"follow_terrain":true,"material_id":"pack:default:paving/outdoor_flagstone/material"}
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var preview:=await call_tool("preview_road_surface",args,false)
	check(equivalent(preview,editor._roads.summary(args)),"HTTP and UI expose the same slope diagnostic")
	check(preview.get("code","")=="terrain_projection_grade_limit" and preview.get("terrain_id","")=="known_quarter_slope" and not str(preview.get("record_id","")).is_empty(),"HTTP preserves concrete terrain and road identity")
	check(absf(preview.get("grade",0.)-.25)<.0001 and preview.get("max_grade",0.)==.15,"HTTP reports actual 25 percent grade and unchanged 15 percent limit")
	var at:Array=preview.get("position",[])
	check(at.size()==3 and absf(at[1]-(5.+.25*(at[0]-512.)))<.0001 and absf(at[2]-512.)<=2.01,"HTTP position locates the actual overlapping terrain plane")
	var triangle:Array=preview.get("triangle_world",[])
	check(triangle.size()==3 and triangle.all(func(p):return absf(p[1]-(5.+.25*(p[0]-512.)))<.0001) and preview.get("cell",[]).size()==2 and int(preview.get("triangle_index",-1)) in [0,1],"HTTP retains cell index and exact world triangle")
	check(str(preview.get("error","")).contains("known_quarter_slope") and str(preview.error).contains("25.000%") and str(preview.error).contains("15.000%"),"user-facing error includes the terrain and readable grade percentages")
	var generated:=await call_tool("generate_road_surface",args,false)
	check(equivalent(generated,preview),"preview and generation return the same actionable failure")
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"failed slope preview and generation leave map and undo unchanged")
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("TERRAIN_GRADE_DIAGNOSTIC_HTTP ",directory," failures=",failed);quit(failed)
