extends "res://tools/test_world3d_mcp.gd"
const Analysis=preload("res://scripts/world_editor/terrain_analysis.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
var count:=0
var output:="D:/code/rmmo_runtime/review_artifacts/terrain_analysis_20261017"
func check(ok_:bool,label_:String)->void:count+=1;super.check(ok_,label_)
func snapshot()->String:return City.token([editor._doc.recovery_snapshot(),editor._doc._undo,editor._doc._redo,editor._dirty,editor._selection_tools.ids])
func ground(id:String,x:float,columns:int=4)->Dictionary:
	var heights:Array=[];var holes:Array=[]
	for z in 5:
		for col in columns+1:heights.append((x-2.+float(col)/columns*4.)*.2)
	holes.resize(columns*4);holes.fill(false)
	return {"uuid":id,"kind":"box","surface_id":"ground","position":[x,0.,0.],"rotation":[0.,0.,0.],"size":[4.,1.,4.],"color":[.3,.4,.2],"collision":"walk","terrain_mesh":{"version":1,"columns":columns,"rows":4,"floor":-16.,"heights":heights,"holes":holes}}
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=90000;root.size=Vector2i(1600,1000)
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var left:=ground("left",-2.);var right:=ground("right",2.,2)
	var data:=Analysis.build([left,right],{"id":"left","interval":.2})
	check(data.ok and absf(data.max_grade-.2)<.00001 and data.slopes.size()==32,"native triangle slopes on analytic plane")
	check(not data.contours.is_empty() and data.contours.all(func(c):return c.points.all(func(p):return absf(p[1]-c.height)<.00001 and absf(p[1]-p[0]*.2)<.00001)),"negative and zero contours follow actual triangle elevations")
	check(not data.seams.is_empty() and data.max_boundary_step<.00001,"mixed resolution shared edge is continuous")
	right.position[1]=.3
	var stepped:=Analysis.build([left,right],{"id":"left"});check(absf(stepped.max_boundary_step-.3)<.00001,"native neighboring height step measured")
	left.terrain_mesh.holes[5]=true
	var holes:=Analysis.build([left],{"id":"left"});check(holes.slopes.size()==30 and holes.holes==1,"hole cells never get slope surfaces")
	left.rotation[1]=25.
	check(absf(Analysis.build([left],{"id":"left"}).max_grade-.2)<.00001,"yaw rotation preserves real slope")
	left.rotation[0]=1.;check(not Analysis.build([left],{"id":"left"}).ok,"tilted terrain explicitly unsupported")
	left.rotation=[0.,0.,0.];left.terrain_mesh.holes[5]=false
	var flat:=ground("flat",0.);flat.terrain_mesh.heights.fill(0.)
	check(Analysis.build([flat],{"id":"flat"}).contours.is_empty(),"flat plane at a contour elevation does not emit whole-cell edges")
	var excessive:=ground("excessive",0.)
	for i in excessive.terrain_mesh.heights.size():excessive.terrain_mesh.heights[i]=900. if i%2==0 else 0.
	check(not Analysis.build([excessive],{"id":"excessive","interval":.1}).ok,"contour expansion rejects bounded output overflow")
	var path:=Paths.cache_directory("analysis_%d"%Time.get_ticks_usec()).path_join("map.gltf");var doc:=Doc.new();doc.records=[left,right]
	check(doc.save(path)==OK,"native analytic disposable map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=path.get_base_dir().path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32930
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"independent loopback server")
	var definitions:Array=(await rpc("tools/list")).result.tools
	for name_:String in ["query_terrain_analysis","set_terrain_analysis","get_terrain_analysis"]:check(definitions.any(func(t):return t.name==name_),"discovered "+name_)
	var before:=snapshot();var request_:Dictionary={"id":"left","interval":.2,"slope_threshold":.15,"contours":true,"slopes":true,"seams":true}
	var queried:=await call_tool("query_terrain_analysis",request_)
	var shown:=await call_tool("set_terrain_analysis",request_.merged({"enabled":true}))
	check(queried.geometry_token==shown.result.geometry_token and snapshot()==before,"query and visible overlay share geometry/version with no author effects")
	var panel=editor._terrain_panel.analysis;editor._terrain_panel.refresh("left");var values:=request_.duplicate();values.erase("id");panel.fields.update_values(values)
	var ui:Dictionary=panel.show_analysis();check(ui.result.geometry_token==queried.geometry_token,"real UI uses same query and overlay")
	check(editor._terrain_analysis.overlay.get_child_count()==2 and editor._terrain_analysis.overlay.get_children().all(func(n):return n is MeshInstance3D and n.get_child_count()==0),"overlays only render meshes without selectable or physics children")
	for i in editor._dock_tabs.get_tab_count():
		if editor._dock_tabs.get_tab_control(i).is_ancestor_of(editor._terrain_panel):editor._dock_tabs.current_tab=i
	editor._terrain_panel.tasks.current_tab=3
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0.,0.,0.],"distance":15.,"pitch":-40.,"yaw":25.});await settle();await RenderingServer.frame_post_draw
	var screen:=root.get_texture().get_image();screen.save_webp(output+"/ui.webp",true,.9)
	FileAccess.open(output+"/compression.json",FileAccess.WRITE).store_string(JSON.stringify({"sha256":FileAccess.get_sha256(output+"/ui.webp"),"quality":90,"lossy":true,"width":screen.get_width(),"height":screen.get_height(),"encoder":"Godot Image.save_webp(lossy=true, quality=0.9)"},"\t"))
	await call_tool("set_terrain_analysis",request_.merged({"enabled":true,"interval":0.},true),false)
	check(snapshot()==before,"invalid overlay parameters are atomic")
	await call_tool("sculpt_terrain",{"id":"left","mode":"raise","points":[[-3.,0.]],"radius":.5,"strength":.1,"hardness":1.,"cross_tiles":false});await settle()
	var updated:=await call_tool("get_terrain_analysis");check(updated.result.geometry_token!=queried.geometry_token,"native sculpt automatically refreshes overlay version")
	await call_tool("undo");await settle();var undone:=await call_tool("query_terrain_analysis",request_)
	check(equivalent(undone.slopes,queried.slopes) and equivalent(undone.contours,queried.contours),"undo restores analytic overlay geometry")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	await settle();var reopened:=await call_tool("get_terrain_analysis");check(reopened.enabled and reopened.result.base_version!=queried.base_version and reopened.triangle_count==32,"reopen refreshes overlay against new document")
	await call_tool("set_object_properties",{"ids":["left"],"hidden":true});await settle();check(not is_instance_valid(editor._terrain_analysis.overlay),"hidden target clears visible analysis")
	await call_tool("undo");await settle();check(is_instance_valid(editor._terrain_analysis.overlay),"undo hide restores analysis")
	await call_tool("set_terrain_analysis",{"enabled":false});check(not is_instance_valid(editor._terrain_analysis.overlay),"disable releases overlay")
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":count,"failures":failed,"map":path,"map_sha256":FileAccess.get_sha256(path),"query_summary":shown,"scope":"native analytic geometry and current 3D HTTP/UI; read-only visualization, not runtime walkability"},"\t"))
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("TERRAIN_ANALYSIS checks=",count," failures=",failed);quit(1 if failed else 0)
