extends "res://tools/test_world3d_mcp.gd"
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Library=preload("res://scripts/world_editor/prefab_library.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Support=preload("res://tools/axel_house_placement_support.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const CANDIDATE="D:/code/rmmo_runtime/cache/world3d/axel_town_houses_20261014/map.gltf"
var recipe:Dictionary
var report:Dictionary={}
var templates:Dictionary={}
func data(name_:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join(name_)))
func verify_authoring_inputs()->void:
	for name_:String in report.get("authoring_inputs",{}):
		check(FileAccess.get_sha256(OUT.path_join(name_))==report.authoring_inputs[name_],"authored input remains pinned "+name_)
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
	var refreshing:bool="--refresh-props" in OS.get_cmdline_user_args()
	if reviewing or resuming or refreshing:report=data("build.json");report.images=[];failed=0
	if not reviewing and not resuming and not refreshing:
		report.authoring_inputs={}
		for name_:String in ["housing_recipe.json","house_templates.json","house_plan_s1_s2.json","house_plan_s10_s12.json"]:
			report.authoring_inputs[name_]=FileAccess.get_sha256(OUT.path_join(name_))
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
	if refreshing:
		await refresh_reference_props()
		if stopped():return
	elif not reviewing:
		if not resuming:await author_ground_roads()
		if stopped():return
		verify_authoring_inputs()
		if stopped():return
		await author_houses()
		if stopped():return
	await wait_view();await call_tool("select_objects",{"ids":[]})
	FileAccess.open(OUT.path_join("s12_live_asset_diagnostic.json"),FileAccess.WRITE).store_string(JSON.stringify(preload("res://tools/diagnose_axel_reference_render.gd").inspect(editor),"\t"))
	if editor._grid!=null:editor._grid.visible=false
	if editor._authoring.marker!=null:editor._authoring.marker.visible=false
	await capture_overview()
	for view:Dictionary in recipe.cameras:await capture_reference(view)
	await capture_reference({"id":"s1_bridge_close","position":[293.1,7.2,256.2],"target":[341,10,268],"fov":45})
	await capture_reference({"id":"s1_bank_close","position":[287,7.6,242],"target":[336,9.8,267],"fov":45})
	await capture_reference({"id":"s12_stream_close","position":[323,8.58,129],"target":[358,11,117],"fov":55})
	await capture_reference({"id":"s2_oculus_detail","position":[329.7,12.4,270.4],"target":[336.5,11.4,277.5],"fov":50})
	await capture_reference({"id":"s12_arch_detail","position":[337,11.5,118.5],"target":[345,11,113.3],"fov":55})
	if report.get("watercourse",{}).get("continuous",false):
		await capture_reference({"id":"s12_watercourse_overview","position":[467,181,210],"target":[361,5,83],"fov":62})
		await capture_reference({"id":"s12_watercourse_source","position":[429,24,38],"target":[408,8,-9],"fov":58})
		await capture_reference({"id":"s12_stream_crossing","position":[319,12.5,116],"target":[335,8,126],"fov":58})
		await capture_reference({"id":"s12_stream_rapid","position":[309,13,126],"target":[323,5,136],"fov":56})
		await capture_reference({"id":"s12_stream_confluence","position":[296,14,151],"target":[320,3,147],"fov":58})
	report.ground_batching=editor._ground_batches.stats();report.phase="candidate_complete";report.candidate_sha256=FileAccess.get_sha256(CANDIDATE)
	verify_authoring_inputs()
	check(FileAccess.get_sha256(FORMAL)==recipe.source.sha256,"formal map untouched during candidate review")
	persist();editor._mcp.stop();editor.queue_free();await settle();quit(1 if failed else 0)
func author_ground_roads()->void:
	# The plan records only verified conflicting grass instances. A generic
	# outward push can put otherwise safe bank vegetation onto a neighbouring road.
	for move:Dictionary in recipe.get("grass_moves",[]):
		var r:Dictionary=editor._doc._find(str(move.id))
		check(not r.is_empty() and r.get("kind")=="asset","authored grass instance exists "+str(move.id))
		if stopped():return
		var next:=Vector3(move.position[0],0,move.position[1]);next.y=ground(next)
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
	# Native prefab/asset operations each create history entries. Author into a
	# separate document so their 32-entry history cannot evict the outer batch's
	# checkpoint. Publish the fully validated native snapshot as one recovery
	# change on the live editor document.
	var live_doc=editor._doc;var before:Dictionary=live_doc.recovery_snapshot()
	var doc=Doc.new();doc.apply_recovery(before)
	var final_houses:Dictionary={}
	for h:Dictionary in recipe.houses:
		var t:Dictionary=templates[h.template_id];var loaded:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(t.loaded_path));var local:=oriented(loaded,h.yaw)
		var pos:=Vector3(h.position[0],h.ground_y,h.position[1]);var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw))
		var parameters:Dictionary=t.parameters
		var support:=Support.sample(doc,loaded.records,pos,basis,parameters)
		check(support.ok,"real ground-floor support found "+h.id)
		if stopped():return
		pos=support.position
		var highest:float=support.highest;var lowest:float=support.lowest
		check(pos.y-h.ground_y<.18,"doorstep remains close to graded path "+h.id)
		if stopped():return
		var result:=Library.place_buildings(doc,local,pos,h.label)
		check(result.ok,"native residential prefab placement "+h.id)
		if not result.ok:report.placement_error={"house":h,"result":result};persist();stopped();return
		var actual_id:String=doc._find(result.ids[0]).building.id
		var row:Dictionary={"id":h.id,"shot":h.shot,"label":h.label,"building_id":actual_id,"template_id":h.template_id,"position":B.arr(pos),"yaw":h.yaw,"parameters":doc.map_meta.building_instances[actual_id].parameters,"entrance":B.arr(pos+basis*B.vec(t.entrance)),"terrain_range":[lowest,highest],"component_ids":result.ids}
		report.houses.append(row);final_houses[h.id]=row;doc._undo.clear();doc._redo.clear();persist()
	var plans:Array=[data("house_plan_s1_s2.json"),data("house_plan_s10_s12.json")]
	var props:=Props.build_requests(doc,plans,final_houses);check(props.ok,"formal reference props discovered")
	if not props.ok:report.props_error=props;persist();stopped();return
	var placed:=Props.apply_requests(doc,props);check(placed.ok,"native lamps courtyard trees and planters placed");report.props=placed
	if stopped():return
	doc.map_meta.town_reference.house_layout={"phase":"reference_houses","date":"2026-10-15","placements":report.houses,"cameras":recipe.cameras}
	check(B.valid_ownership(doc.map_meta,doc.records),"independent building floor roof and fixture ownership retained")
	check(doc.validate_save()==OK,"complete staged native house layout is valid")
	if stopped():return
	var after:Dictionary=doc.recovery_snapshot()
	live_doc.apply_recovery(after);live_doc.commit_recovery_change(before);doc=live_doc
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
func refresh_reference_props()->void:
	# Revisit accepted house placement through ordinary native object transforms.
	# This mode cannot replace models, regenerate roads, or move a residence.
	check(FileAccess.get_sha256(CANDIDATE)==report.get("candidate_sha256",""),"prop refinement starts from the reviewed candidate")
	check(FileAccess.get_sha256(FORMAL)==report.source_sha256,"prop refinement preserves formal baseline")
	check(FileAccess.get_sha256(OUT.path_join("house_templates.json"))==report.authoring_inputs.get("house_templates.json",""),"prop refinement cannot change house template sources")
	var actual:Dictionary={}
	for h:Dictionary in report.houses:actual[h.id]=h
	check(recipe.houses.size()==actual.size(),"prop refinement preserves house count")
	for h:Dictionary in recipe.houses:
		var saved:Dictionary=actual.get(h.id,{})
		check(not saved.is_empty() and saved.template_id==h.template_id and absf(float(saved.yaw)-float(h.yaw))<.001 and Vector2(saved.position[0],saved.position[2]).distance_to(Vector2(h.position[0],h.position[1]))<.001,"prop refinement preserves house "+str(h.id))
	if stopped():return
	var requests:=Props.build_requests(editor._doc,[data("house_plan_s1_s2.json"),data("house_plan_s10_s12.json")],actual)
	check(requests.ok,"refined prop requests use formal assets")
	if stopped():return
	var scratch=Doc.new();var desired:=Props.apply_requests(scratch,requests)
	check(desired.ok and desired.placements.size()==report.props.placements.size(),"refined props preserve instance count")
	if stopped():return
	var previous:Dictionary={}
	for row:Dictionary in report.props.placements:previous[row.key]=row
	var changed:Array=[]
	for row:Dictionary in desired.placements:
		var prior:Dictionary=previous.get(row.key,{})
		check(not prior.is_empty() and prior.asset_sha256==row.asset_sha256,"prop refinement retains model "+str(row.key))
		if stopped():return
		var record:Dictionary=editor._doc._find(str(prior.id))
		check(not record.is_empty() and record.editor_name=="Axel reference "+str(row.key),"prop refinement retains editable identity "+str(row.key))
		if stopped():return
		row.id=prior.id
		var properties:Dictionary={}
		for pair:Array in [["position","position"],["rotation","rotation"],["size","scale"]]:
			if B.vec(record[pair[0]]).distance_to(B.vec(row[pair[1]]))>.0001:properties[pair[0]]=row[pair[1]]
		if properties.is_empty():continue
		var before:Dictionary=record.duplicate(true)
		await call_tool("set_object_transform",properties.merged({"id":row.id}))
		if stopped():return
		var after:Dictionary=editor._doc._find(str(row.id)).duplicate(true)
		check(B.vec(after.position).distance_to(B.vec(row.position))<.0001 and B.vec(after.rotation).distance_to(B.vec(row.rotation))<.0001 and B.vec(after.size).distance_to(B.vec(row.scale))<.0001,"refined prop reaches intended transform "+str(row.key))
		check(editor._doc.undo() and equivalent(editor._doc._find(str(row.id)),before),"refined prop transform undo "+str(row.key))
		check(editor._doc.redo() and equivalent(editor._doc._find(str(row.id)),after),"refined prop transform redo "+str(row.key))
		changed.append({"key":row.key,"id":row.id,"from":before.position,"to":after.position})
	if stopped():return
	desired.ids=[]
	for row:Dictionary in desired.placements:desired.ids.append(row.id)
	report.props=desired;report.prop_refinements=changed
	editor._doc.map_meta.town_reference.house_layout.cameras=recipe.cameras
	check(editor._doc.validate_save()==OK,"refined native layout validates")
	if stopped():return
	var expected:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("save_world")
	await call_tool("open_world",{"path":CANDIDATE});await wait_view()
	check(equivalent(expected.records,editor._doc.records) and equivalent(expected.map_meta,editor._doc.map_meta),"refined prop and camera native save reopen matches")
	for name_:String in ["housing_recipe.json","house_templates.json","house_plan_s1_s2.json","house_plan_s10_s12.json"]:report.authoring_inputs[name_]=FileAccess.get_sha256(OUT.path_join(name_))
	report.candidate_sha256=FileAccess.get_sha256(CANDIDATE)
	report.phase="refined_props_saved";persist()
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
