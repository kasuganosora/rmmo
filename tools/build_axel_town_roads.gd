extends "res://tools/test_world3d_mcp.gd"
## Task-owned candidate; all road and bridge authoring goes through real 3D HTTP.
const City=preload("res://scripts/world3d/city_layout.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014"
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const CANDIDATE="D:/code/rmmo_runtime/cache/world3d/axel_town_roads_20261014/map.gltf"
const OLD="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
var recipe:Dictionary
var bridges:Array=[]
var report:Dictionary={}

func persist()->void:
	report.failures=failed
	var f:=FileAccess.open(OUT.path_join("build.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"));f.close()
func stopped()->bool:
	if failed==0:return false
	persist()
	if is_instance_valid(editor) and editor._mcp!=null:editor._mcp.stop()
	quit(1);return true
func wait_view()->void:
	var deadline:=Time.get_ticks_msec()+240000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if editor._load_job!=null and editor._load_job.active:continue
		if editor._ground_batches.stats().get("pending_groups",0)>0:continue
		await settle();return
	check(false,"background native geometry finishes")
func ground_at(records:Array,p:Vector2)->float:
	for r:Dictionary in records:
		if not r.has("terrain_mesh"):continue
		var v:=Vector3(p.x-r.position[0],0,p.y-r.position[2])
		if absf(v.x)<=r.size[0]*.5+.00001 and absf(v.z)<=r.size[2]*.5+.00001:
			var y:=Terrain.sample(r,v)
			if is_finite(y):return y+r.position[1]
	return NAN
func native_candidate()->void:
	var original=Doc.open_file(FORMAL)
	check(original!=null,"formal source opens natively")
	if stopped():return
	report.source_signature=original._disk_signature
	var doc=Doc.new();doc.records=original.records.duplicate(true);doc.map_meta=original.map_meta.duplicate(true)
	# Exact terrain recipe is narrowly authored against the pinned source SHA.
	check(FileAccess.get_sha256(FORMAL)==recipe.source_map_sha256,"recipe uses current formal map")
	var patches:Array=recipe.get("terrain_adjustments",[])
	for patch:Dictionary in patches:
		var old:Dictionary=doc._find(patch.id)
		var changed:=old.duplicate(true);changed.terrain_mesh=patch.terrain_mesh.duplicate(true)
		check(old.has("terrain_mesh") and Terrain.valid(changed),"valid local approach terrain "+str(patch.id))
		for i in doc.records.size():
			if doc.records[i].uuid==patch.id:doc.records[i]=changed
	for patch:Dictionary in recipe.get("river_rebase_adjustments",[]):
		for layer:Dictionary in doc.map_meta.terrain_rivers:
			if layer.id!=patch.get("river_id",""):continue
			for pair:Dictionary in layer.terrains:
				if pair.after.uuid!=patch.get("terrain_id",""):continue
				for i in patch.indices.size():
					var at:int=patch.indices[i];var delta:float=patch.deltas[i]
					pair.before.terrain_mesh.heights[at]+=delta
					pair.after.terrain_mesh.heights[at]+=delta
	for layer:Dictionary in doc.map_meta.terrain_rivers:
		for pair:Dictionary in layer.terrains:
			var restored:Dictionary=preload("res://scripts/world3d/terrain_river_layer.gd").restore(doc._find(pair.after.uuid),pair.before,pair.after)
			check(restored.ok,"river recovery remains valid for "+str(pair.after.uuid))
			if not restored.ok:print(restored)
	if stopped():return
	report.terrain_records_changed=patches.size()
	if FileAccess.file_exists(CANDIDATE):doc.accept_save(CANDIDATE,Doc.open_file(CANDIDATE)._disk_signature)
	check(doc.save(CANDIDATE)==OK,"native atomic temporary candidate")
	if stopped():return
func capture(label:String,camera:Dictionary)->void:
	await call_tool("set_editor_camera",camera);await settle()
	for i in 20:await process_frame
	await RenderingServer.frame_post_draw
	var im:Image=editor._camera.get_viewport().get_texture().get_image()
	var path:=OUT.path_join(label+".webp")
	check(im.save_webp(path,false,.9)==OK,"scene capture "+label)
	report.images.append({"path":path,"camera":camera,"width":im.get_width(),"height":im.get_height(),"sha256":FileAccess.get_sha256(path)})
	var viewport:RID=editor._camera.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	var gpu:=0.;var draws:=0.
	for i in 30:
		await process_frame;await RenderingServer.frame_post_draw
		gpu+=RenderingServer.viewport_get_measured_render_time_gpu(viewport)
		draws+=RenderingServer.viewport_get_render_info(viewport,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	report.images[-1].viewport_metrics={"frames":30,"gpu_ms_mean":gpu/30,"draw_calls_mean":draws/30,"scope":"this fixed editor viewport; not full-town gameplay performance"}
func run()->void:
	create_timer(1750).timeout.connect(func():check(false,"build timeout");persist();quit(2))
	Engine.max_fps=60;rpc_timeout_ms=300000;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(OUT)
	recipe=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("recipe.json")))
	bridges=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("bridges.json"))).requests
	report={"phase":"native_candidate","source_sha256":FileAccess.get_sha256(FORMAL),"old_sha256":FileAccess.get_sha256(OLD),"images":[],"bridges":[],"grass_moves":[],"candidate":CANDIDATE}
	if "--review-only" in OS.get_cmdline_user_args() or "--resume-roads" in OS.get_cmdline_user_args():
		report=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("build.json")));report.images=[]
	if not "--review-only" in OS.get_cmdline_user_args() and not "--resume-roads" in OS.get_cmdline_user_args():
		native_candidate()
		if stopped():return
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=CANDIDATE;session.world3d_editor_doc=null
	report.phase="loading_editor";persist()
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts")
	root.add_child(editor);await settle();await wait_view()
	var probe:=TCPServer.new();port=31560
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"native 3D HTTP starts")
	var discovery:=await rpc("tools/list");var names:Array=discovery.get("result",{}).get("tools",[]).map(func(t):return t.name)
	check(["update_road_graph","preview_road_surface","generate_road_surface","preview_bridge","generate_bridge"].all(func(n):return n in names),"current 3D tools discoverable")
	if stopped():return
	if not "--review-only" in OS.get_cmdline_user_args():
		await author()
		if stopped():return
	if editor._grid!=null:editor._grid.visible=false
	if editor._authoring.marker!=null:editor._authoring.marker.visible=false
	await call_tool("select_objects",{"ids":[]})
	report.phase="candidate_visual_review";persist()
	await capture("roads_overview",{"projection":"top","center":[225,5,180],"span":480,"yaw":0,"pitch":-89})
	for bridge:Dictionary in bridges:
		var a:=City.vec(bridge.start);var b:=City.vec(bridge.end);var center:Vector3=(a+b)*.5
		await capture(bridge.id+"_context",{"projection":"perspective","center":City.xyz(center-Vector3.UP),"distance":43,"yaw":30,"pitch":-27})
	await capture("guild_paths",{"projection":"perspective","center":[156,7.5,218],"distance":100,"yaw":-20,"pitch":-40})
	await capture("guild_road_kerb_detail",{"projection":"perspective","center":[159,7.55,209],"distance":4,"yaw":75,"pitch":-23})
	await capture("north_market_road_shoulder",{"projection":"perspective","center":[185,8,48],"distance":50,"yaw":-35,"pitch":-26})
	await capture("church_road_shoulder",{"projection":"perspective","center":[285,7,88],"distance":45,"yaw":40,"pitch":-27})
	await capture("s1_bridge_street_angle",{"projection":"perspective","center":[281,8,241],"distance":43,"yaw":30,"pitch":-11})
	for view:Dictionary in editor._doc.map_meta.editor_layout.bookmarks:
		if view.id in ["s1_bridge_banks","s12_stream"]:await capture("reference_"+str(view.id),view.camera)
	var assets:Dictionary=preload("res://tools/audit_axel_bridge_assets.gd").write_report(editor._doc,CANDIDATE,OUT.path_join("bridge_assets"))
	report.bridge_asset_audit=assets
	check(assets.get("passed",false),"five frozen bridge resources and actual materials pass audit")
	var captures:Variant=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("bridge_assets/bridge_capture_plan.json")))
	if captures is Dictionary:
		for group:Dictionary in captures.get("bridges",[]):
			for label:String in group.views:
				await capture(str(group.id)+"_"+label,group.views[label].camera)
	report.ground_batching=editor._ground_batches.stats()
	report.candidate_sha256=FileAccess.get_sha256(CANDIDATE);report.phase="candidate_complete"
	check(FileAccess.get_sha256(FORMAL)==report.source_sha256,"formal map remains untouched during candidate review")
	check(FileAccess.get_sha256(OLD)==report.old_sha256,"old town remains unchanged")
	persist();editor._mcp.stop();editor.queue_free();await settle();quit(1 if failed else 0)

func author()->void:
	# Concrete steps filled by the graph recipe; no changes to formal map here.
	if not "--resume-roads" in OS.get_cmdline_user_args():
		await clear_grass()
		if stopped():return
		report.phase="road_graph";persist()
		var graph:Dictionary=recipe.get("graph",{})
		check(not graph.is_empty(),"native road graph recipe exists")
		if stopped():return
		var state:=await call_tool("get_city_layout")
		await call_tool("update_road_graph",{"expected_token":state.road_token,"nodes":graph.nodes,"edges":graph.edges})
		if stopped():return
		report.phase="bridges";persist()
		for args:Dictionary in bridges:
			var number:=int(str(args.id).get_slice("_",2))
			args.road_edge_id=recipe.bridge_connections[number-1].edge_id
			var p:=await call_tool("preview_bridge",args)
			if stopped():return
			report.bridges.append(p);persist()
			await call_tool("generate_bridge",args.merged({"plan_token":p.plan_token}))
			if stopped():return
		await call_tool("save_world")
		report.phase="bridges_saved";persist()
	report.phase="road_surface";persist()
	var settings:Dictionary=recipe.road_surface_settings
	var preview:=await call_tool("preview_road_surface",settings)
	report.road_preview=preview;persist()
	if stopped():return
	await call_tool("generate_road_surface",settings.merged({"plan_token":preview.plan_token}))
	if stopped():return
	var after:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");await call_tool("redo")
	check(equivalent(after,editor._doc.recovery_snapshot()),"road surface single transaction undo/redo")
	await clear_grass(true)
	if stopped():return
	# Keep the reserved trading pockets open beside the native six-metre access.
	# Their final paving belongs to the later guild forecourt layout, not a second
	# independently overlaid road surface with conflicting internal kerbs.
	editor._doc.map_meta.name="阿克塞尔新城镇"
	editor._doc.map_meta.town_reference.phase="terrain_grass_roads_bridges"
	editor._doc.map_meta.town_reference.road_layout={"source_plan":recipe.source_plan,"source_plan_sha256":recipe.source_plan_sha256,"future_home_adjustments":recipe.future_home_adjustments,"design_note":"项目补充设计：路网按实际干岸微调，五座石桥以通行宽度和桥下净空接入缓坡；公会前留空供玩家摆摊。"}
	await call_tool("save_world")
	var saved:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("open_world",{"path":CANDIDATE});await wait_view()
	check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"all content survives native save/reopen")
	report.road_count=editor._doc.records.filter(func(r):return r.has("road_mesh")).size()
	report.bridge_count=editor._doc.records.filter(func(r):return r.has("bridge_mesh")).size()

func grass_fitted(old:Dictionary,center:Vector2)->Dictionary:
	var yaw:=float(old.rotation[1]);var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
	var half_x:float=old.bounds_size[0]*old.size[0]*.5
	var half_z:float=old.bounds_size[2]*old.size[2]*.5
	var mean:=0.0;var rows:Array=[];var xx:=0.;var zz:=0.;var xz:=0.;var xy:=0.;var zy:=0.
	for iz in [-1,0,1]:
		for ix in [-1,0,1]:
			var d:=basis*Vector3(ix*half_x,0,iz*half_z)
			var h:=ground_at(editor._doc.records,center+Vector2(d.x,d.z))
			if not is_finite(h):return {}
			rows.append([d.x,d.z,h]);mean+=h
	mean/=9
	for row:Array in rows:
		xx+=row[0]*row[0];zz+=row[1]*row[1];xz+=row[0]*row[1];xy+=row[0]*(row[2]-mean);zy+=row[1]*(row[2]-mean)
	var det:=xx*zz-xz*xz
	if det<.000001:return {}
	var normal:=Vector3(-(xy*zz-zy*xz)/det,1,-(zy*xx-xy*xz)/det).normalized()
	if normal.y<cos(deg_to_rad(35)):return {}
	var forward:=(basis.z-normal*basis.z.dot(normal)).normalized()
	basis=Basis(normal.cross(forward).normalized(),normal,forward)
	var r:=old.duplicate(true)
	var local_center:=City.vec(r.bounds_position)+Vector3(r.bounds_size[0]*.5,0,r.bounds_size[2]*.5)
	r.rotation=City.xyz(basis.get_euler()*180/PI)
	r.position=City.xyz(Vector3(center.x,mean-.012,center.y)-basis*(local_center*City.vec(r.size)))
	return r
func grass_clear(record:Dictionary,corridors:Array,waters:Array)->bool:
	var polygon:=PackedVector2Array()
	for p:Vector3 in Geometry.corners(record):polygon.append(Vector2(p.x,p.z))
	polygon=Geometry2D.convex_hull(polygon)
	var wider:=Geometry2D.offset_polygon(polygon,.13)
	if wider.size()!=1:return false
	polygon=wider[0]
	var bounds:Rect2=area(polygon).bounds
	for blocked:Dictionary in corridors+waters:
		if bounds.intersects(blocked.bounds,true) and not Geometry2D.intersect_polygons(polygon,blocked.polygon).is_empty():return false
	for zone:Dictionary in editor._doc.map_meta.editor_layout.get("zones",[]):
		var raw:PackedVector2Array=[]
		for p:Array in zone.polygon:raw.append(Vector2(p[0],p[1]))
		if not Geometry2D.intersect_polygons(polygon,raw).is_empty():return false
	return true
func area(polygon:PackedVector2Array)->Dictionary:
	var bounds:=Rect2(polygon[0],Vector2.ZERO)
	for p:Vector2 in polygon:bounds=bounds.expand(p)
	return {"polygon":polygon,"bounds":bounds}
func clear_grass(actual:bool=false)->void:
	var graph:Dictionary=recipe.graph;var nodes:Dictionary={};var corridors:Array=[];var waters:Array=[]
	for n:Dictionary in graph.nodes:nodes[n.id]=City.vec(n.position)
	for e:Dictionary in graph.edges:
		var a3:Vector3=nodes[e.from];var b3:Vector3=nodes[e.to]
		var a:=Vector2(a3.x,a3.z);var b:=Vector2(b3.x,b3.z);var d:Vector2=(b-a).normalized()
		var n:=Vector2(-d.y,d.x)*(maxf(e.width_start,e.width_end)*.5+.8)
		corridors.append(area(PackedVector2Array([a-d*.8-n,b+d*.8-n,b+d*.8+n,a-d*.8+n])))
	for args:Dictionary in bridges:
		var bridge:Dictionary=editor._bridges.make_record(args,editor._bridges.library.find(args.prefab_id))
		corridors.append(area(PackedVector2Array(Foot.record_shape(bridge).polygon)))
	corridors.append(area(PackedVector2Array([Vector2(142,198),Vector2(180,198),Vector2(180,237),Vector2(142,237)])))
	for r:Dictionary in editor._doc.records:
		if actual and r.has("road_mesh"):
			for shape:Dictionary in Foot.record_shapes(r):corridors.append(area(PackedVector2Array(shape.polygon)))
		if r.get("surface_id")!="water":continue
		for shape:Dictionary in Foot.record_shapes(r):waters.append(area(PackedVector2Array(shape.polygon)))
	for old:Dictionary in editor._doc.records.duplicate():
		if not str(old.uuid).begins_with("obj_") or not old.has("asset_path"):continue
		var local:=City.vec(old.bounds_position)+Vector3(old.bounds_size[0]*.5,0,old.bounds_size[2]*.5)
		var root_:Vector3=Transform3D(Basis.from_euler(City.vec(old.rotation)*PI/180).scaled(City.vec(old.size)),City.vec(old.position))*local
		var center:=Vector2(root_.x,root_.z)
		if grass_clear(old,corridors,waters) and absf(ground_at(editor._doc.records,center)-root_.y)<.07:continue
		var proposed:Dictionary={}
		for ring in 15:
			for angle in 16:
				var offset:=Vector2(cos(angle*TAU/16),sin(angle*TAU/16))*ring*.75
				var candidate:=grass_fitted(old,center+offset)
				if not candidate.is_empty() and grass_clear(candidate,corridors,waters):proposed=candidate;break
			if not proposed.is_empty():break
		check(not proposed.is_empty(),"find dry road-free location for grass "+str(old.uuid))
		if proposed.is_empty():return
		await call_tool("set_object_transform",{"id":old.uuid,"position":proposed.position,"rotation":proposed.rotation,"size":proposed.size})
		report.grass_moves.append({"id":old.uuid,"before":old.position,"after":proposed.position})
	report.phase="grass_clearance_complete";persist()
