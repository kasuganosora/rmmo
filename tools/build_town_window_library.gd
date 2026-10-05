extends "res://tools/build_house_playground.gd"
const Rhythm=preload("res://tools/town_frontage_rhythm.gd")
func run()->void:
	create_timer(2400).timeout.connect(func():quit(2));Engine.max_fps=30;root.size=Vector2i(1280,900);root.content_scale_size=root.size
	review_directory="town_window_library_20261005";rpc_timeout_ms=240000
	DEST="D:/code/rmmo_runtime/cache/world3d/town_window_library_20261005/map.gltf"
	DirAccess.make_dir_recursive_absolute(DEST.get_base_dir());DirAccess.make_dir_recursive_absolute(Review.review_path(review_directory))
	var all_rows:=Rhythm.sequence("shop",20261005)+Rhythm.sequence("house",20261006);var unique:Dictionary={}
	for row:Dictionary in all_rows:unique[row.id]=row
	var library=Doc.new();library.map_meta.map_name="错落街区 · 整栋窗口方案";library.map_meta.environment={"interior_cutaway":false};library.map_meta.building_instances={}
	var index:=0;var seen_styles:Dictionary={};var report_rows:Array=[]
	for row:Dictionary in unique.values():
		var plan:=Blueprint.generate(row.parameters);check(plan.ok,"generate "+row.id)
		if not plan.ok:print(plan);quit(1);return
		var doc=Doc.new();doc.map_meta.environment={"interior_cutaway":false};doc.map_meta.building_instances={}
		var id:String="style_"+row.id;var value:={"version":Blueprint.VERSION,"parameters":plan.parameters,"position":[0,0,0],"yaw":0.0,"parts":{},"signatures":{}}
		for r:Dictionary in plan.records:
			r.uuid="obj_%d"%doc._next;doc._next+=1;r.building.id=id;r.editor_group=id;r.editor_group_name=row.name
			value.parts[r.building.part]=r.uuid;value.signatures[r.building.part]=Blueprint.geometry_signature(r);doc.records.append(r)
		doc.map_meta.building_instances[id]=value
		var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=""
		editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=DEST.get_base_dir().path_join("drafts");root.add_child(editor);await settle();editor._safety.enabled=false
		var probe:=TCPServer.new()
		while probe.listen(port,"127.0.0.1")!=OK:port+=1
		probe.stop();check(editor.start_mcp(port).ok,"HTTP authoring")
		if index==0:
			var templates:=await call_tool("list_building_templates");check(templates.window_styles.size()==6,"all window families and whole-house random discoverable")
		await call_tool("set_environment",{"preset":"day","sun_rotation":[-43,145,0],"sun_energy":1.15,"ambient_energy":.58,"sun_shadows":true,"ambient_occlusion":true})
		await paint_gallery()
		if failed:editor.free();quit(1);return
		await call_tool("bake_building",{"id":id})
		var frozen:Dictionary=doc.map_meta.building_instances[id];check(frozen.baked and frozen.parts.size()<100,"two-digit fixed components "+row.id+" count="+str(frozen.parts.size()))
		if index==0:
			await call_tool("undo");check(not doc.map_meta.building_instances[id].get("baked",false),"undo window bake")
			await call_tool("redo");check(doc.map_meta.building_instances[id].baked,"redo window bake")
		if failed:editor.free();quit(1);return
		editor._ground_batches.enabled=false;editor._ground_batches.clear();editor._grid.hide()
		await capture(row.id,Vector3(22,15,-27),Vector3(0,5,0),23)
		var style:String=plan.parameters.window_style
		if not seen_styles.has(style):
			seen_styles[style]=true
			var windows:Array=plan.openings.filter(func(o):return o.type=="window" and o.wall.ends_with("north"))
			if windows.is_empty():windows=plan.openings.filter(func(o):return o.type=="window" and o.wall.ends_with("west"))
			var opening:Dictionary=windows[0]
			var target:=Blueprint.wall_position(opening.axis,opening.fixed,opening.u,opening.floor_y+opening.bottom+opening.height/2)
			await capture("detail_"+style,target+(Vector3(1.4,.55,-5) if opening.axis=="x" else Vector3(-5,.55,1.4)),target,3.5)
		var at:=Vector3((index%5)*30,0,floori(index/5.)*30)
		var stored:Dictionary=frozen.duplicate(true);stored.position=Blueprint.arr(at);stored.parts={};stored.signatures={}
		for source:Dictionary in doc.records:
			var r:Dictionary=source.duplicate(true);r.uuid="obj_%d"%library._next;library._next+=1;r.position=Blueprint.arr(Blueprint.vec(r.position)+at)
			stored.parts[r.building.part]=r.uuid;stored.signatures[r.building.part]=Blueprint.geometry_signature(r);library.records.append(r)
		library.map_meta.building_instances[id]=stored
		report_rows.append({"id":row.id,"window_style":style,"parts":frozen.parts.size(),"parameters":plan.parameters})
		print("WINDOW_LIBRARY_PROGRESS ",index+1,"/",unique.size());index+=1
		editor.free();editor=null;doc=null;await settle()
	check(library.save(DEST)==OK,"native fixed library save")
	var reopened=Doc.open_file(DEST);check(reopened!=null and Blueprint.valid_ownership(reopened.map_meta,reopened.records) and equivalent(reopened.records,library.records),"native fixed library reopen")
	var file:=FileAccess.open(Review.review_path(review_directory+"/result.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failed,"variants":report_rows,"sha256":FileAccess.get_sha256(DEST)},"\t"));file.close()
	print("WINDOW_LIBRARY failures=",failed);quit(1 if failed else 0)
