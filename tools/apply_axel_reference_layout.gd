extends "res://tools/test_world3d_mcp.gd"
## Scoped scene placement through the current editor's real HTTP operations.
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
var output:=""
var report:Dictionary={"saved":false,"checks":[],"operations":[],"placements":[]}
func before_placements(_recipe:Dictionary)->void:
	pass
func after_placements(recipe:Dictionary)->void:
	if recipe.get("validate_roads",false):
		var roads:Dictionary=editor._roads.prepare({})
		check(roads.get("ok",false),"full native road clearance after scoped placement")
		report.road_validation={"ok":roads.get("ok",false),"error":roads.get("error",""),"conflicts":roads.get("conflicts",[])}
func check(ok:bool,label:String)->void:
	super.check(ok,label);report.checks.append({"name":label,"passed":ok})
func persist()->void:
	if output.is_empty():return
	report.failures=failed
	var f:=FileAccess.open(output.path_join("authoring.json"),FileAccess.WRITE)
	if f!=null:f.store_string(JSON.stringify(report,"\t"));f.close()
func operation(tool:String,args:Dictionary)->Dictionary:
	var result:=await call_tool(tool,args)
	report.operations.append({"tool":tool,"request":args,"ok":result.get("ok",false),"error":result.get("error",""),"ids":result.get("ids",[])})
	persist();return result
func road_gap(record:Dictionary)->float:
	var box:AABB=Foot.record_shape(record).bounds;var rect:=Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z))
	var corners:=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	var graph:Dictionary=City.resolve(editor._doc.map_meta).roads;var analysis:Dictionary=City.analyze(graph);var nearest:=INF
	if not analysis.ok:return -INF
	for edge:Dictionary in graph.edges:
		var path:Array=analysis.paths[edge.id]
		for i in path.size()-1:
			var a:=Vector2(path[i].x,path[i].z);var b:=Vector2(path[i+1].x,path[i+1].z);var distance:=INF
			for point:Vector2 in corners:distance=minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b)))
			for point:Vector2 in [a,b]:distance=minf(distance,point.distance_to(point.clamp(rect.position,rect.end)))
			for j in 4:
				if Geometry2D.segment_intersects_segment(a,b,corners[j],corners[(j+1)%4])!=null:distance=0
			nearest=minf(nearest,distance-maxf(edge.width_start,edge.width_end)*.5)
	return nearest
func run()->void:
	var source:="";var target:="";var expected:="";var recipe_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):source=arg.trim_prefix("--map=")
		elif arg.begins_with("--save="):target=arg.trim_prefix("--save=")
		elif arg.begins_with("--expected-sha="):expected=arg.trim_prefix("--expected-sha=")
		elif arg.begins_with("--recipe="):recipe_path=arg.trim_prefix("--recipe=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	if not Paths.allowed(output) or not Paths.allowed(target) or not target.contains("/cache/world3d/") or FileAccess.file_exists(target):quit(1);return
	DirAccess.make_dir_recursive_absolute(output);DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	check(expected.length()==64 and FileAccess.get_sha256(source)==expected,"exact authored source")
	if failed: persist();quit(1);return
	var recipe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(recipe_path))
	report.merge({"source":source,"source_sha256":expected,"target":target,"recipe":recipe_path,"recipe_sha256":FileAccess.get_sha256(recipe_path),"scope":"S12 existing asset instances and reference camera; no model, road, river, house or performance changes"})
	if recipe.has("parent_authoring"):
		var parent:Dictionary=recipe.parent_authoring
		check(FileAccess.get_sha256(parent.path)==parent.sha256,"exact previous scoped authoring receipt")
		var history:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(parent.path))
		check(history.get("saved",false) and history.get("failures",-1)==0 and history.get("target_sha256","")==expected,"previous native output is current input")
		report.parent_authoring=parent;report.placements=history.placements.duplicate(true)
		if history.has("deleted_records"):
			for field:String in ["deleted_records","changed_records","new_records"]:report[field]=history[field].duplicate(true)
			report.root_source_sha256=history.get("root_source_sha256",history.source_sha256)
			report.scope="S12 residence transaction with subsequent native layout refinements"
		if failed:persist();quit(1);return
	create_timer(900).timeout.connect(func():check(false,"authoring timeout");persist();quit(2))
	rpc_timeout_ms=180000
	var fixture:=output.path_join("empty_editor/map.gltf");DirAccess.make_dir_recursive_absolute(fixture.get_base_dir())
	var empty:=Doc.new();check(empty.save(fixture)==OK,"native temporary editor fixture")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=fixture;session.world3d_editor_doc=empty
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=output.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var original=Doc.open_file(source);check(original!=null,"native source opens")
	if failed:persist();quit(1);return
	var before:Dictionary=original.recovery_snapshot();var staged:=Doc.new();staged.apply_recovery(before);editor._doc=staged;editor._city.refresh();editor._authoring.refresh()
	var socket:=TCPServer.new();port=32640
	while socket.listen(port,"127.0.0.1")!=OK:port+=1
	socket.stop();check(editor.start_mcp(port).ok,"current 3D HTTP starts")
	var discovery:=await rpc("tools/list");check(not discovery.get("result",{}).get("tools",[]).is_empty(),"current tools discovered")
	await operation("configure_transform",{"gravity_placement":false})
	await before_placements(recipe)
	if failed:persist();quit(1);return
	for row:Dictionary in recipe.placements:
		var id:=str(row.get("id",""))
		if id.is_empty():
			var found:Dictionary={}
			for entry:Dictionary in editor.asset_items(""):
				var asset_path:=str(entry.get("asset_path",entry.get("prefab_path","")))
				if asset_path.replace("\\","/")==str(row.asset).replace("\\","/"):found=entry;break
			check(not found.is_empty() and FileAccess.get_sha256(row.asset)==row.sha256,"exact formal library asset "+str(row.key))
			if failed:break
			var placed:=await operation("place_asset",{"asset_id":found.get("asset_path",found.get("prefab_path","")),"position":row.point})
			if not placed.get("ok",false):break
			check(placed.ids.size()==1,"one independent instance "+str(row.key))
			if failed:break
			id=placed.ids[0]
		var changed:=await operation("set_object_transform",{"id":id,"rotation":row.get("rotation",[0,0,0]),"size":row.get("scale",[1,1,1])})
		if not changed.get("ok",false):break
		var record:Dictionary=staged._find(id);var box:AABB=Foot.record_shape(record).bounds
		var point:=Vector3(row.point[0],row.point[1],row.point[2])
		if row.get("grounded",false):
			point.y=Props.ground(staged,point)
			if row.get("ground_fit","")=="lowest":
				for x in [-.5,0,.5]:
					for z in [-.5,0,.5]:point.y=minf(point.y,Props.ground(staged,point+Vector3(box.size.x*x,0,box.size.z*z)))
			point.y+=float(row.get("embed",-.02))
		var position:=point if row.get("anchor","")=="origin" else City.vec(record.position)+point-Vector3(box.get_center().x,box.position.y,box.get_center().z)
		await operation("set_object_transform",{"id":id,"position":City.xyz(position)})
		await operation("set_object_properties",{"ids":[id],"name":"Axel reference "+str(row.key)})
		if row.get("keep_off_roads",false):
			var clearance:=road_gap(staged._find(id));check(clearance>=.12,"complete footprint clears authored road widths "+str(row.key))
			if not report.has("road_clearance"):report.road_clearance=[]
			report.road_clearance.append({"id":id,"key":row.key,"minimum_m":clearance})
		report.placements=report.placements.filter(func(prior):return prior.id!=id)
		report.placements.append({"key":row.key,"id":id,"position":staged._find(id).position,"scale":staged._find(id).size,"bounds_bottom":point.y})
		if failed:break
	if failed==0:await after_placements(recipe)
	if failed==0 and recipe.has("bookmark"):
		await operation("set_editor_camera",recipe.bookmark.camera)
		await operation("save_view_bookmark",{"id":recipe.bookmark.id,"name":recipe.bookmark.name})
	check(FileAccess.get_sha256(source)==expected,"formal source unchanged during candidate authoring")
	check(staged.validate_save()==OK,"native save validation")
	if failed==0:
		var after:Dictionary=staged.recovery_snapshot()
		original.apply_recovery(after);original.commit_recovery_change(before)
		check(original.undo() and equivalent(original.records,before.records) and equivalent(original.map_meta,before.map_meta),"single scoped undo")
		check(original.redo() and equivalent(original.records,after.records) and equivalent(original.map_meta,after.map_meta),"single scoped redo")
		if failed==0:
			check(original.save(target)==OK,"native candidate atomic save")
			var reopened=Doc.open_file(target)
			check(reopened!=null and reopened.validate_save()==OK and equivalent(reopened.records,original.records) and equivalent(reopened.map_meta,original.map_meta),"candidate save and reopen identical")
			report.saved=failed==0;report.target_sha256=FileAccess.get_sha256(target)
	persist();editor._mcp.stop();quit(0 if failed==0 else 1)
