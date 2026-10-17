extends "res://tools/test_terrain_analysis.gd"
const Volume=preload("res://scripts/world3d/terrain_volume.gd")
func run()->void:
	create_timer(360).timeout.connect(func():quit(2));rpc_timeout_ms=120000;root.size=Vector2i(1600,1000)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var box:Dictionary={"uuid":"cave","kind":"box","surface_id":"ground","position":[0.,0.,0.],"rotation":[0.,0.,0.],"size":[10.,10.,10.],"collision":"walk","color":[.44,.43,.38],"terrain_volume":{"version":1,"resolution":12,"seed":"box","operations":[]}}
	var args:Dictionary={"id":"cave","surface":"all","height_min":-6.,"height_max":6.,"interval":.5,"slope_threshold":.15,"contours":true,"slopes":true,"seams":false}
	var plain:=Analysis.build([box],args)
	check(plain.ok and plain.vertical_triangles>0 and plain.max_grade==null,"vertical native faces have nullable grade and finite 90 degree angle")
	var top:=Analysis.build([box],args.merged({"surface":"upward"},true))
	check(top.ok and not top.slopes.is_empty() and top.slopes.all(func(t):return t.normal[1]>.05 and t.points.all(func(p):return p[1]>3.5)),"clockwise native winding classifies actual top surface upward")
	check(not Analysis.build([box],{"id":"cave"}).ok,"volume analysis requires explicit layer and surface selection")
	check(not Analysis.build([box],args.merged({"seams":true},true)).ok,"heightfield seam interpretation is never reused for volume")
	check(not Analysis.build([box],args.merged({"height_min":6.},true)).ok,"empty height band rejects")
	box.terrain_volume.operations.append({"mode":"subtract","a":[0.,0.,-6.],"b":[0.,0.,6.],"radius":2.2})
	var floor_query:=Analysis.build([box],args.merged({"surface":"upward","height_min":-3.,"height_max":0.},true))
	var ceiling_query:=Analysis.build([box],args.merged({"surface":"downward","height_min":0.,"height_max":3.},true))
	check(floor_query.ok and not floor_query.slopes.is_empty() and floor_query.slopes.all(func(t):return t.normal[1]>.05),"cave floor remains independently queryable below outer roof")
	check(ceiling_query.ok and not ceiling_query.slopes.is_empty() and ceiling_query.slopes.all(func(t):return t.normal[1]<-.05 and t.steep),"cave ceiling is independently selected and never shown as walkable floor")
	var clipped:=Analysis.build([box],args.merged({"height_min":-.25,"height_max":.25},true))
	check(clipped.ok and not clipped.slopes.is_empty() and clipped.slopes.all(func(t):return t.points.all(func(p):return p[1]>=-.250001 and p[1]<=.250001)),"actual triangles clipped at both world height planes")
	check(clipped.contours.all(func(c):return c.points.all(func(p):return absf(p[1]-c.height)<.000001)),"volume contours remain at exact world heights")
	var arrays:Array=Volume.arrays(box)[0];var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var matches:=true
	for tri:Dictionary in clipped.slopes:
		var at:int=tri.source_triangle*3;var a:Vector3=vertices[indices[at]];var normal:Vector3=(vertices[indices[at+2]]-a).cross(vertices[indices[at+1]]-a).normalized()
		for p:Array in tri.points:matches=matches and absf(normal.dot(City.vec(p)-a))<.00001
	check(matches,"every clipped output face lies on its actual native source triangle plane")
	var turned:=box.duplicate(true);turned.rotation=[25.,37.,10.];turned.position=[11.,5.,-7.]
	var rotated:=Analysis.build([turned],args.merged({"surface":"downward","height_min":2.,"height_max":8.},true))
	check(rotated.ok and not rotated.slopes.is_empty() and rotated.slopes.all(func(t):return t.normal[1]<-.05 and t.points.all(func(p):return p[1]>=1.99999 and p[1]<=8.00001)),"rotated volume selection uses world normals and world height band")
	var huge:=box.duplicate(true);huge.size=[64.,64.,64.]
	check(not Analysis.build([huge],args.merged({"height_min":-40.,"height_max":40.,"interval":.1},true)).ok,"volume contour expansion stops at explicit output budget")
	var path:=Paths.cache_directory("volume_analysis_%d"%Time.get_ticks_usec()).path_join("map.gltf");var doc:=Doc.new();doc.records=[box]
	check(doc.save(path)==OK,"temporary native cave map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=path.get_base_dir().path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=34130
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"isolated 3D loopback server")
	var definitions:Array=(await rpc("tools/list")).result.tools
	for name_:String in ["query_terrain_analysis","set_terrain_analysis"]:
		var definition:Dictionary=definitions.filter(func(t):return t.name==name_)[0]
		check(definition.inputSchema.properties.has("surface") and definition.inputSchema.properties.has("height_min"),"tool discovery includes volume parameters: "+name_)
	var before:=snapshot();var queried:=await call_tool("query_terrain_analysis",args)
	var shown:=await call_tool("set_terrain_analysis",args.merged({"enabled":true}))
	check(snapshot()==before and queried.geometry_token==shown.result.geometry_token,"volume HTTP query and visible overlay are authoring read-only")
	var panel=editor._terrain_panel.analysis;panel.refresh_targets()
	for i in panel.target.item_count:
		if panel.target.get_item_metadata(i)=="cave":panel.target.select(i)
	var values:=args.duplicate();values.erase("id");panel.fields.update_values(values)
	var ui:Dictionary=panel.show_analysis();check(ui.ok and ui.result.geometry_token==queried.geometry_token,"real UI selects volume and matches actual HTTP geometry")
	panel.fields.fields.height_min.value=6.
	var invalid_ui:Dictionary=panel.show_analysis();await settle()
	check(not invalid_ui.ok and not panel.error_text.is_empty() and panel.info.text==panel.error_text,"invalid UI band retains actionable error instead of old successful statistics")
	panel.fields.fields.height_min.value=-6.;panel.show_analysis()
	check(editor._terrain_analysis.overlay.get_children().all(func(n):return n is MeshInstance3D and n.get_child_count()==0),"volume overlay has no selectable or collision children")
	for bad in [{"height_min":6.},{"surface":"first"},{"seams":true}]:
		await call_tool("set_terrain_analysis",args.merged(bad,true).merged({"enabled":true}),false)
		check(snapshot()==before and editor._terrain_analysis.state().result.geometry_token==queried.geometry_token,"invalid query preserves authoring and previous visible overlay")
	for i in editor._dock_tabs.get_tab_count():
		if editor._dock_tabs.get_tab_control(i).is_ancestor_of(editor._terrain_panel):editor._dock_tabs.current_tab=i
	editor._terrain_panel.tasks.current_tab=3
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0.,0.,0.],"distance":23.,"pitch":-12.,"yaw":15.});await settle();await RenderingServer.frame_post_draw
	var screen:=root.get_texture().get_image();screen.save_webp(output+"/ui.webp",true,.9)
	FileAccess.open(output+"/compression.json",FileAccess.WRITE).store_string(JSON.stringify({"sha256":FileAccess.get_sha256(output+"/ui.webp"),"quality":90,"lossy":true,"width":screen.get_width(),"height":screen.get_height(),"encoder":"Godot Image.save_webp(lossy=true,quality=0.9)"},"\t"))
	await call_tool("sculpt_terrain_volume",{"id":"cave","mode":"subtract","points":[[2.,1.,-6.],[2.,1.,6.]],"radius":1.});await settle()
	var updated:=await call_tool("get_terrain_analysis");check(updated.result.geometry_token!=queried.geometry_token,"native volume carving invalidates overlay")
	await call_tool("undo");await settle();var undone:=await call_tool("query_terrain_analysis",args)
	check(equivalent(undone.slopes,queried.slopes) and equivalent(undone.contours,queried.contours),"undo restores multi-surface analysis")
	await call_tool("redo");await settle();check(editor._terrain_analysis.last.geometry_token!=undone.geometry_token,"redo refreshes volume overlay")
	await call_tool("undo");await call_tool("save_world");await call_tool("open_world",{"path":path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	await settle();var reopened:=await call_tool("query_terrain_analysis",args)
	check(reopened.base_version!=queried.base_version and equivalent(reopened.slopes,queried.slopes),"save/reopen preserves editable volume and refreshes session geometry")
	await call_tool("set_object_properties",{"ids":["cave"],"hidden":true});await settle();check(not is_instance_valid(editor._terrain_analysis.overlay),"hidden volume clears overlay")
	await call_tool("undo");await settle();check(is_instance_valid(editor._terrain_analysis.overlay),"undo hidden volume restores overlay")
	await call_tool("set_terrain_analysis",{"enabled":false});check(not is_instance_valid(editor._terrain_analysis.overlay),"disable releases volume analysis")
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":count,"failures":failed,"map":path,"map_sha256":FileAccess.get_sha256(path),"query_summary":shown,"scope":"actual volume triangles, UI and HTTP; no authoring changes from analysis; not runtime walkability or art acceptance"},"\t"))
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("VOLUME_ANALYSIS checks=",count," failures=",failed);quit(1 if failed else 0)
