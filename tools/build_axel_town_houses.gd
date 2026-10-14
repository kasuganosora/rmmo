extends "res://tools/test_world3d_mcp.gd"
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Library=preload("res://scripts/world_editor/prefab_library.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const CANDIDATE="D:/code/rmmo_runtime/cache/world3d/axel_town_houses_20261014/map.gltf"
var recipe:Dictionary
var report:Dictionary={}
var templates:Dictionary={}
func data(name_:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join(name_)))
func persist()->void:
	report.failures=failed
	FileAccess.open(OUT+"/build.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
func stopped()->bool:
	if failed==0:return false
	persist();if is_instance_valid(editor) and editor._mcp!=null:editor._mcp.stop()
	quit(1);return true
func wait_view()->void:
	var deadline:=Time.get_ticks_msec()+300000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if editor._load_job!=null and editor._load_job.active:continue
		if editor._ground_batches.stats().get("pending_groups",0)>0:continue
		await settle();return
	check(false,"native background scene preparation finishes")
func ground(p:Vector3)->float:return Props.ground(editor._doc,p)
func oriented(loaded:Dictionary,yaw:float)->Dictionary:
	var copy:=loaded.duplicate(true);var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
	for r:Dictionary in copy.records:
		r.position=B.arr(basis*B.vec(r.position));r.rotation=B.arr((basis*Basis.from_euler(B.vec(r.rotation)*PI/180)).get_euler()*180/PI)
	for v:Dictionary in copy.building_instances.values():v.position=[0,0,0];v.yaw=yaw
	return copy
func run()->void:
	create_timer(1750).timeout.connect(func():check(false,"candidate timeout");persist();quit(2))
	Engine.max_fps=60;rpc_timeout_ms=300000;root.size=Vector2i(1878,1000);root.content_scale_size=root.size
	recipe=data("housing_recipe.json")
	for t:Dictionary in data("house_templates.json").templates:templates[t.id]=t
	report={"phase":"begin","source_sha256":FileAccess.get_sha256(FORMAL),"source_signature":recipe.source.signature,"candidate":CANDIDATE,"houses":[],"plots":[],"grass_moves":[],"images":[]}
	var reviewing:bool="--review-only" in OS.get_cmdline_user_args()
	var resuming:bool="--resume" in OS.get_cmdline_user_args()
	if reviewing or resuming:report=data("build.json");report.images=[];failed=0
	if not reviewing and not resuming:
		check(report.source_sha256==recipe.source.sha256,"formal source pinned")
		for h:Dictionary in recipe.houses:check(templates.has(h.template_id),"native template ready "+str(h.template_id))
		if stopped():return
		var source=Doc.open_file(FORMAL)
		if FileAccess.file_exists(CANDIDATE):source.accept_save(CANDIDATE,Doc.open_file(CANDIDATE)._disk_signature)
		check(source.save(CANDIDATE)==OK,"native candidate created atomically")
		if stopped():return
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=CANDIDATE;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=CANDIDATE.get_base_dir()+"/drafts";root.add_child(editor);await settle();await wait_view()
	var probe:=TCPServer.new();port=31860
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"candidate current 3D HTTP starts")
	if not reviewing:
		if not resuming:await author_ground_roads()
		if stopped():return
		await author_houses()
		if stopped():return
	await wait_view();await call_tool("select_objects",{"ids":[]})
	if editor._grid!=null:editor._grid.visible=false
	if editor._authoring.marker!=null:editor._authoring.marker.visible=false
	await capture_overview()
	for view:Dictionary in recipe.cameras:await capture_reference(view)
	await capture_reference({"id":"s1_bridge_close","position":[293.1,7.2,256.2],"target":[341,10,268],"fov":45})
	await capture_reference({"id":"s1_bank_close","position":[287,7.6,242],"target":[336,9.8,267],"fov":45})
	await capture_reference({"id":"s12_stream_close","position":[323,8.58,129],"target":[358,11,117],"fov":55})
	await capture_reference({"id":"s2_oculus_detail","position":[329.7,12.4,270.4],"target":[336.5,11.4,277.5],"fov":50})
	await capture_reference({"id":"s12_arch_detail","position":[337,11.5,118.5],"target":[345,11,113.3],"fov":55})
	report.ground_batching=editor._ground_batches.stats();report.phase="candidate_complete";report.candidate_sha256=FileAccess.get_sha256(CANDIDATE)
	check(FileAccess.get_sha256(FORMAL)==recipe.source.sha256,"formal map untouched during candidate review")
	persist();editor._mcp.stop();editor.queue_free();await settle();quit(1 if failed else 0)
func author_ground_roads()->void:
	# Move just grass overlapping the construction plots, preserving every instance.
	for r:Dictionary in editor._doc.records.duplicate():
		if r.get("kind")!="asset":continue
		var point:=B.vec(r.position);var next:=point
		for h:Dictionary in recipe.houses:
			var g:Dictionary=h.grade;var center:=Vector3(g.center[0],0,g.center[1]);var basis:=Basis(Vector3.UP,deg_to_rad(g.yaw));var local:=basis.inverse()*(next-center)
			var margin:float=3.2
			if absf(local.x)<g.width*.5+margin and absf(local.z)<g.depth*.5+margin:
				var dx:float=g.width*.5+margin-absf(local.x);var dz:float=g.depth*.5+margin-absf(local.z)
				if dx<dz:local.x=signf(local.x if local.x!=0 else 1.)*(g.width*.5+margin)
				else:local.z=signf(local.z if local.z!=0 else 1.)*(g.depth*.5+margin)
				next=center+basis*local
		if next.distance_to(point)>.01:
			next.y=ground(next)
			var old_position:Array=r.position.duplicate()
			await call_tool("set_object_transform",{"id":r.uuid,"position":B.arr(next)})
			report.grass_moves.append({"id":r.uuid,"from":old_position,"to":B.arr(next)})
			if stopped():return
	report.phase="grading_house_plots";persist()
	for h:Dictionary in recipe.houses:
		if not h.grade.required:continue
		var g:Dictionary=h.grade;var p:=Vector3(g.center[0],0,g.center[1]);var target:=""
		for r:Dictionary in editor._doc.records:
			if r.has("terrain_mesh") and is_finite(Terrain.sample(r,Terrain.transform(r).affine_inverse()*p)):target=r.uuid;break
		var args:={"id":target,"mode":"flatten","shape":"rectangle","points":[g.center],"plot_width":g.width,"plot_depth":g.depth,"plot_yaw":g.yaw,"blend_margin":g.margin,"target_height":g.height,"strength":1,"cross_tiles":true}
		var result:=await call_tool("sculpt_terrain",args);report.plots.append({"house":h.id,"request":args,"result":result});persist()
		if stopped():return
	await call_tool("save_world")
	report.phase="house_access_roads";persist()
	var state:=await call_tool("get_city_layout")
	var graph:Dictionary=recipe.road_graph
	await call_tool("update_road_graph",{"expected_token":state.road_token,"nodes":graph.nodes,"edges":graph.edges,"remove_nodes":recipe.remove_nodes,"remove_edges":recipe.remove_edges})
	if stopped():return
	var settings:Dictionary=recipe.road_settings
	var preview:=await call_tool("preview_road_surface",settings)
	if stopped():return
	await call_tool("generate_road_surface",settings.merged({"plan_token":preview.plan_token}))
	if stopped():return
	await call_tool("save_world");report.phase="ground_roads_saved";persist()
func author_houses()->void:
	report.houses=[];report.erase("placement_error");report.phase="placing_reference_houses";persist()
	var doc=editor._doc;var before:Dictionary=doc.recovery_snapshot();doc.checkpoint_recovery();var checkpoint:int=doc._undo.size()
	var final_houses:Dictionary={}
	for h:Dictionary in recipe.houses:
		var t:Dictionary=templates[h.template_id];var loaded:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(t.loaded_path));var local:=oriented(loaded,h.yaw)
		var pos:=Vector3(h.position[0],h.ground_y,h.position[1]);var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw))
		var highest:=-INF;var lowest:=INF
		# Cover the doorway and foundation envelope, including adjacent terrain cells.
		var bounds:AABB=preload("res://scripts/world_editor/building_footprint.gd").local_bounds(loaded.records)
		for ix in 9:
			for iz in 9:
				var p:=pos+basis*Vector3(lerpf(bounds.position.x,bounds.end.x,ix/8.),0,lerpf(bounds.position.z,bounds.end.z,iz/8.))
				var y:=ground(p);highest=maxf(highest,y);lowest=minf(lowest,y)
		var parameters:Dictionary=t.parameters
		var raised:float=float(parameters.get("base_height",0)) if parameters.get("layout") in ["townhouse","hall"] else 0.
		pos.y=maxf(pos.y,highest-raised+.025)
		check(pos.y-h.ground_y<.18,"doorstep remains close to graded path "+h.id)
		if stopped():return
		var result:=Library.place_buildings(doc,local,pos,h.label)
		check(result.ok,"native residential prefab placement "+h.id)
		if not result.ok:report.placement_error={"house":h,"result":result};persist();stopped();return
		var actual_id:String=doc._find(result.ids[0]).building.id
		var row:Dictionary={"id":h.id,"shot":h.shot,"label":h.label,"building_id":actual_id,"template_id":h.template_id,"position":B.arr(pos),"yaw":h.yaw,"parameters":doc.map_meta.building_instances[actual_id].parameters,"entrance":B.arr(pos+basis*B.vec(t.entrance)),"terrain_range":[lowest,highest],"component_ids":result.ids}
		report.houses.append(row);final_houses[h.id]=row;doc._undo.resize(checkpoint);persist()
	var plans:Array=[data("house_plan_s1_s2.json"),data("house_plan_s10_s12.json")]
	var props:=Props.build_requests(doc,plans,final_houses);check(props.ok,"formal reference props discovered")
	if not props.ok:report.props_error=props;persist();stopped();return
	var placed:=Props.apply_requests(doc,props);check(placed.ok,"native lamps courtyard trees and planters placed");report.props=placed;doc._undo.resize(checkpoint)
	if stopped():return
	doc.map_meta.town_reference.house_layout={"phase":"reference_houses","date":"2026-10-14","placements":report.houses,"cameras":recipe.cameras}
	check(B.valid_ownership(doc.map_meta,doc.records),"independent building floor roof and fixture ownership retained")
	var after:Dictionary=doc.recovery_snapshot()
	var undone:bool=doc.undo()
	var undo_state:Dictionary=doc.recovery_snapshot()
	var before_content:Dictionary=before.duplicate(true);before_content.erase("next")
	var undone_content:Dictionary=undo_state.duplicate(true);undone_content.erase("next")
	check(undone and equivalent(before_content,undone_content) and int(undo_state.get("next",0))>=int(before.get("next",0)),"one undo restores pre-house layout with monotonic IDs")
	check(doc.redo() and equivalent(after,doc.recovery_snapshot()),"redo restores full reference housing")
	if stopped():return
	var new_ids:Array=[]
	for row:Dictionary in report.houses:new_ids.append_array(row.component_ids)
	new_ids.append_array(placed.ids)
	editor._commit_records(new_ids);await wait_view()
	await call_tool("save_world")
	await call_tool("open_world",{"path":CANDIDATE});await wait_view()
	check(equivalent(after.records,editor._doc.records) and B.valid_ownership(editor._doc.map_meta,editor._doc.records),"house layout native save reopen matches")
	report.phase="houses_saved";persist()
func save_image(label:String,camera:Dictionary)->void:
	for i in 25:await process_frame
	await RenderingServer.frame_post_draw
	var im:Image=editor._camera.get_viewport().get_texture().get_image();var path:=OUT.path_join(label+".webp")
	check(im.save_webp(path,false,.9)==OK,"outdoor image "+label)
	report.images.append({"path":path,"camera":camera,"width":im.get_width(),"height":im.get_height(),"sha256":FileAccess.get_sha256(path)});persist()
	var viewport:RID=editor._camera.get_viewport().get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
	var draws:=0.;var gpu:=0.
	for i in 30:
		await process_frame;await RenderingServer.frame_post_draw
		draws+=RenderingServer.viewport_get_render_info(viewport,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		gpu+=RenderingServer.viewport_get_measured_render_time_gpu(viewport)
	report.images[-1].viewport_metrics={"frames":30,"draw_calls_mean":draws/30.,"gpu_ms_mean":gpu/30.,"scope":"fixed editor outdoor viewport; not full gameplay load/RSS/VRAM"};persist()
func capture_reference(view:Dictionary)->void:
	editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE;editor._camera.fov=view.fov;editor._camera.position=B.vec(view.position);editor._camera.look_at(B.vec(view.target))
	await save_image(str(view.id).to_lower(),view)
func capture_overview()->void:
	for group:Array in [["east_residential_overview",[349,6,268],80,-35,-43],["fruit_court_overview",[103,8,134],42,150,-34],["stream_houses_overview",[353,8,122],64,-58,-35]]:
		var cam:Dictionary={"projection":"perspective","center":group[1],"distance":group[2],"yaw":group[3],"pitch":group[4]}
		await call_tool("set_editor_camera",cam);await save_image(group[0],cam)
