extends "res://tools/test_world3d_mcp.gd"
## Candidate-only authoring. Every geometry change uses the current 3D HTTP
## business operation. No save occurs until the complete connected watercourse,
## terrain-following roads and bound stream bridge have passed together.
const City=preload("res://scripts/world3d/city_layout.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Layer=preload("res://scripts/world3d/terrain_river_layer.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const CANDIDATE="D:/code/rmmo_runtime/cache/world3d/axel_town_houses_20261014/map.gltf"
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
var report:Dictionary={"phase":"starting","operations":[],"saved":false}
var before:Dictionary
var baseline_build:Dictionary
var inputs:Dictionary={}
var live_document
var grass_moves:Array=[]
var grass_removals:Array=[]
var s10_tree_move:Dictionary={}
func data(name_:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join(name_)))
func write_json(path:String,value:Dictionary)->void:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	if f==null:check(false,"open report "+path);return
	f.store_string(JSON.stringify(value,"\t"));f.close()
func persist()->void:
	report.failures=failed;write_json(OUT+"/s12_watercourse_update.json",report)
func stopped()->bool:
	if failed==0:return false
	if is_instance_valid(editor) and editor._doc!=null and not report.get("saved",false):
		var snapshot:=FileAccess.open(OUT+"/s12_failed_native_stage.bin",FileAccess.WRITE)
		if snapshot!=null:
			snapshot.store_var({"snapshot":editor._doc.recovery_snapshot(),"report":report.duplicate(true)});snapshot.close()
			report.failed_stage_fixture=OUT+"/s12_failed_native_stage.bin"
	report.phase="failed_after_candidate_save" if report.get("saved",false) else "failed_without_candidate_save";persist()
	if is_instance_valid(editor) and editor._mcp!=null:editor._mcp.stop()
	quit(1);return true
func operation(name_:String,args:Dictionary)->Dictionary:
	report.phase=name_;persist();print("BEGIN ",name_)
	var result:=await call_tool(name_,args)
	report.operations.append({"tool":name_,"request":args.duplicate(true),"result":result.duplicate(true)})
	persist();return result
func wait_ready()->void:
	var deadline:=Time.get_ticks_msec()+300000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if editor._load_job!=null and editor._load_job.active:continue
		if editor._ground_batches.stats().get("pending_groups",0)>0:continue
		await settle();return
	check(false,"candidate native load ready")
func terrain_id(point:Array)->String:
	var p:=Vector3(point[0],0,point[1])
	for r:Dictionary in editor._doc.records:
		if r.has("terrain_mesh") and is_finite(Terrain.sample(r,Terrain.transform(r).affine_inverse()*p)):return r.uuid
	return ""
func ground_y(point:Array)->float:
	var p:=Vector3(point[0],0,point[1])
	for r:Dictionary in editor._doc.records:
		if not r.has("terrain_mesh"):continue
		var pose:=Terrain.transform(r);var local:=pose.affine_inverse()*p
		var h:=Terrain.sample(r,local)
		if is_finite(h):return (pose*Vector3(local.x,h,local.z)).y
	return NAN
func relocate_conflicting_grass()->void:
	check(FileAccess.file_exists(OUT+"/s12_grass_moves.json"),"measured minimal grass adjustment ready")
	if failed:return
	if not inputs.has("s12_grass_moves.json"):
		inputs["s12_grass_moves.json"]=FileAccess.get_sha256(OUT+"/s12_grass_moves.json")
		report.inputs=inputs
	var proposal:=data("s12_grass_moves.json")
	check(proposal.candidate_sha256==report.candidate_before_sha256,"grass adjustment measured on unchanged candidate")
	check(proposal.grading_sha256==inputs["s12_road_grading.json"],"grass adjustments match final approach grading")
	if failed:return
	for remove:Dictionary in proposal.get("removals",[]):
		var previous:Dictionary=editor._doc._find(remove.id).duplicate(true)
		check(previous.get("kind")=="asset" and equivalent(previous.get("position",[]),remove.expected_position),"exact obstructing grass removal "+str(remove.id))
		if failed:return
		await operation("select_objects",{"ids":[remove.id]})
		if failed:return
		check(editor._selection_tools.ids.size()==1 and editor._selection_tools.ids[0]==remove.id,"removal selects only the measured grass instance")
		if failed:return
		await operation("delete_selection",{})
		if failed:return
		check(editor._doc._find(remove.id).is_empty(),"surplus obstructing grass removed natively "+str(remove.id))
		grass_removals.append({"id":remove.id,"before":previous,"reason":remove.reason})
	report.grass_removals=grass_removals
	for move:Dictionary in proposal.moves:
		var previous:Dictionary=editor._doc._find(move.id).duplicate(true)
		check(not previous.is_empty() and previous.get("kind")=="asset","measured conflicting grass exists "+str(move.id))
		if failed:return
		var old_ground:=ground_y([previous.position[0],previous.position[2]])
		var new_ground:=ground_y(move.target_xz)
		check(is_finite(old_ground) and is_finite(new_ground),"grass source and target terrain support")
		if failed:return
		var next:Array=[move.target_xz[0],float(previous.position[1])+new_ground-old_ground,move.target_xz[1]]
		await operation("set_object_transform",{"id":move.id,"position":next})
		if failed:return
		grass_moves.append({"id":move.id,"before":previous,"position":next,"old_ground_y":old_ground,"target_ground_y_before_grade":new_ground,"reason":move.get("reason","measured road grading support conflict")})
	report.grass_moves=grass_moves
func verify_grass_after_grade()->void:
	for move:Dictionary in grass_moves:
		var after_ground:=ground_y([move.position[0],move.position[2]])
		move.target_ground_y_after_grade=after_ground
		check(absf(after_ground-float(move.target_ground_y_before_grade))<.002,"relocated grass target remains outside changed road support "+str(move.id))
		report.grass_moves=grass_moves
func apply_planned_s10_tree()->void:
	var plan:=data("house_plan_s10_s12.json")
	inputs["house_plan_s10_s12.json"]=FileAccess.get_sha256(OUT+"/house_plan_s10_s12.json")
	var specification:Dictionary=plan.props.s10_tree
	check(specification.get("position_xz",[]).size()==2,"S10 tree correction has the approved plan courtyard anchor")
	var previous:Dictionary=editor._doc._find("obj_841").duplicate(true)
	check(previous.get("editor_name","")=="Axel reference s10_front_home/redfruit" and FileAccess.get_sha256(previous.get("asset_path",""))==specification.asset_sha256,"exact existing S10 fruit tree identity and model retained")
	if failed:return
	var low:=City.vec(previous.bounds_position);var size_:=City.vec(previous.bounds_size)
	var pivot:=Vector3(low.x+size_.x*.5,low.y,low.z+size_.z*.5)
	var anchor:=Vector3(specification.position_xz[0],ground_y(specification.position_xz),specification.position_xz[1])
	check(is_finite(anchor.y),"S10 target courtyard terrain sampled natively")
	if failed:return
	var basis:=Basis.from_euler(City.vec(previous.rotation)*PI/180.)
	var position:=City.xyz(anchor-basis*(pivot*City.vec(previous.size)))
	await operation("set_object_transform",{"id":previous.uuid,"position":position})
	if failed:return
	s10_tree_move={"id":previous.uuid,"key":"s10_front_home/redfruit","before":previous,"position":position,"rotation":previous.rotation,"scale":previous.size,"anchor":City.xyz(anchor),"plan_sha256":inputs["house_plan_s10_s12.json"],"reason":"Previously approved S10 courtyard move, required before full road regeneration because the old fruit tree occupies road clearance."}
	report.s10_tree_correction=s10_tree_move;persist()
func stable_contents(snapshot:Dictionary)->Dictionary:
	var copy:=snapshot.duplicate(true)
	for key in ["next","disk_signature","disk_path","dirty"]:copy.erase(key)
	return copy
func validate_stage_pins()->void:
	var pins:=data("s12_before_river_stage_pins.json")
	var mismatches:Array=[]
	for entry:Dictionary in pins.entries:
		if FileAccess.get_sha256(entry.path)!=entry.sha256:mismatches.append(entry.path)
	check(pins.candidate_sha256==report.candidate_before_sha256 and pins.formal_sha256==FileAccess.get_sha256(FORMAL),"native stage pins unchanged candidate and formal baseline")
	check(mismatches.is_empty(),"native source and existing CPU evidence unchanged "+str(mismatches))
func correct_bridge_approaches()->void:
	var correction:=data("s12_bridge_approach_correction.json")
	inputs["s12_bridge_approach_correction.json"]=FileAccess.get_sha256(OUT+"/s12_bridge_approach_correction.json")
	check(correction.candidate_sha256==report.candidate_before_sha256 and correction.base_delta_sha256==inputs["s12_road_delta.json"],"minimal bridge approach correction matches the native stage")
	var graph:Dictionary=City.resolve(editor._doc.map_meta).roads
	for expected:Dictionary in correction.expected_nodes:
		var found:Array=graph.nodes.filter(func(n):return n.id==expected.id)
		check(found.size()==1 and equivalent(found[0],expected),"exact previous approach node "+str(expected.id))
	for expected:Dictionary in correction.expected_edges:
		var found:Array=graph.edges.filter(func(e):return e.id==expected.id)
		check(found.size()==1 and equivalent(found[0],expected),"exact redundant old stub edge "+str(expected.id))
	for id:String in correction.remove_nodes:
		check(graph.edges.filter(func(e):return e.from==id or e.to==id).size()==1,"removed west stub has no house or through-road connection "+id)
	if failed:return
	await operation("update_road_graph",{"expected_token":City.token(graph),"nodes":correction.nodes,"edges":correction.edges,"remove_nodes":correction.remove_nodes,"remove_edges":correction.remove_edges})
	report.bridge_approach_correction=correction;report.inputs=inputs;persist()
func finish_appearance(request:Dictionary)->void:
	var ids:Array=[]
	var water_appearance:Dictionary={}
	for river:Dictionary in editor._doc.map_meta.terrain_rivers:
		if river.id==request.id:ids=river.water.map(func(w):return w.id)
		if river.id==request.outlet.river_id and not river.water.is_empty():water_appearance=editor._doc._find(river.water[0].id).get("water_depth_effect",{}).duplicate(true)
	check(not water_appearance.is_empty(),"receiving river actual water appearance available")
	if failed:return
	water_appearance.water_ids=ids
	await operation("set_river_materials",water_appearance)
	report.water_appearance_source={"river":request.outlet.river_id,"actual_parameters":water_appearance.duplicate(true)}
	# Current user priority is the complete layout skeleton. Retain the
	# existing bank regions; new sand/rock masks and planting await that stage.
	report.deferred_details=["new bank sand/rock material regions","new riverbank planting and decoration"]

func verify_preserved()->void:
	var now:Dictionary=editor._doc.recovery_snapshot()
	check(equivalent(before.map_meta.get("building_instances",{}),now.map_meta.get("building_instances",{})),"14 native house instances unchanged")
	check(equivalent(City.resolve(before.map_meta).get("zones",[]),City.resolve(now.map_meta).get("zones",[])),"R1-R5 unchanged")
	for r:Dictionary in before.records:
		if r.has("terrain_mesh") or r.has("road_mesh") or str(r.uuid).begins_with("river_axel_s12_stream_"):continue
		if not s10_tree_move.is_empty() and r.uuid==s10_tree_move.id:
			var expected:=r.duplicate(true);expected.position=s10_tree_move.position
			check(City.token(expected)==City.token(editor._doc._find(r.uuid)),"only approved S10 fruit-tree position changed")
			continue
		if grass_removals.any(func(remove):return remove.id==r.uuid):
			check(editor._doc._find(r.uuid).is_empty(),"approved obstructing grass removal stays removed "+str(r.uuid))
			continue
		if grass_moves.any(func(move):return move.id==r.uuid):
			var expected:=r.duplicate(true)
			expected.position=grass_moves.filter(func(move):return move.id==r.uuid)[0].position
			check(City.token(expected)==City.token(editor._doc._find(r.uuid)),"only approved grass position changed "+str(r.uuid))
			continue
		check(City.token(r)==City.token(editor._doc._find(r.uuid)),"unrelated native record unchanged "+str(r.uuid))
	var river:Dictionary={}
	for item:Dictionary in now.map_meta.get("terrain_rivers",[]):
		if item.id=="axel_s12_stream":river=item
	check(not river.is_empty() and river.request.get("outlet",{}).get("river_id")=="axel_main_river","continuous river has explicit native outlet")
	check(Layer.valid(now.map_meta),"river recovery ownership remains valid")
	check(editor._doc.validate_save()==OK,"whole candidate native save validation")
func run()->void:
	create_timer(2400).timeout.connect(func():check(false,"watercourse authoring timeout");persist();quit(2))
	rpc_timeout_ms=300000;Engine.max_fps=60
	var dry:bool="--preflight-only" in OS.get_cmdline_user_args()
	var request:=data("s12_river_request.json");var patch:=data("s12_road_delta.json");var grading:=data("s12_road_grading.json")
	baseline_build=data("build.json")
	for name_:String in ["s12_river_request.json","s12_road_delta.json","s12_road_grading.json","housing_recipe.json"]:inputs[name_]=FileAccess.get_sha256(OUT.path_join(name_))
	report.merge({"candidate":CANDIDATE,"candidate_before_sha256":FileAccess.get_sha256(CANDIDATE),"formal_before_sha256":FileAccess.get_sha256(FORMAL),"preflight_only":dry,"inputs":inputs},true)
	check(report.candidate_before_sha256==patch.candidate_sha256,"candidate matches measured content request")
	check(baseline_build.candidate_sha256==report.candidate_before_sha256 and baseline_build.failures==0,"existing build receipt pinned")
	check(inputs["housing_recipe.json"]==patch.source_housing_recipe_sha256,"housing recipe unchanged since road delta")
	if stopped():return
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=CANDIDATE;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=OUT+"/watercourse_drafts";root.add_child(editor);await settle();await wait_ready()
	before=editor._doc.recovery_snapshot()
	live_document=editor._doc
	var staged=Doc.new();staged.apply_recovery(before);editor._doc=staged
	var probe:=TCPServer.new();port=31890
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"candidate 3D HTTP starts")
	if stopped():return
	var bridge:Dictionary=patch.bridge_geometry_candidate.duplicate(true)
	var preview:Dictionary={}
	if "--resume-river-stage" in OS.get_cmdline_user_args():
		validate_stage_pins()
		if stopped():return
		var stage_file:=FileAccess.open(OUT+"/s12_before_river_stage.bin",FileAccess.READ)
		check(stage_file!=null,"previous native pre-river diagnostic fixture exists")
		if stopped():return
		var checkpoint:Dictionary=stage_file.get_var();stage_file.close()
		check(checkpoint.candidate_sha256==report.candidate_before_sha256,"resume fixture belongs to unchanged native candidate")
		for name_:String in checkpoint.inputs:
			if name_=="s12_river_request.json":continue
			check(FileAccess.get_sha256(OUT.path_join(name_))==checkpoint.inputs[name_],"resume stage inputs unchanged "+name_)
		check(City.token(stable_contents(checkpoint.before))==City.token(stable_contents(before)),"resume fixture preserves exact native baseline")
		if stopped():return
		staged.apply_recovery(checkpoint.snapshot)
		grass_moves=checkpoint.grass_moves;grass_removals=checkpoint.grass_removals;s10_tree_move=checkpoint.s10_tree_move
		inputs=checkpoint.inputs.duplicate(true);inputs["s12_river_request.json"]=FileAccess.get_sha256(OUT+"/s12_river_request.json")
		inputs["s12_before_river_stage_pins.json"]=FileAccess.get_sha256(OUT+"/s12_before_river_stage_pins.json")
		report.inputs=inputs;report.operations=checkpoint.operations.duplicate(true)
		report.grass_moves=grass_moves;report.grass_removals=grass_removals;report.s10_tree_correction=s10_tree_move
		report.resumed_native_stage=true
	else:
		# Restore the old closed channel first. Its owned endcaps disappear with it.
		# This is in memory only; a failure leaves the saved candidate untouched.
		await operation("remove_terrain_river",{"id":"axel_s12_stream"})
		if stopped():return
		await relocate_conflicting_grass()
		if stopped():return
		await apply_planned_s10_tree()
		if stopped():return
		var strokes:Array=[]
		for plot:Dictionary in grading.plots:
			var args:Dictionary=plot.request.duplicate(true);args.id=terrain_id(args.points[0])
			check(not str(args.id).is_empty(),"road approach has native terrain "+str(plot.id))
			if stopped():return
			strokes.append(args)
		# One native final-state operation, shared with the interactive terrain UI.
		# The old road crosses the temporarily unfinished shoulder of either plot;
		# the final north-wide/south-narrow plane and minor road realignment are
		# validated together without deleting live roads or relaxing any guard.
		var joint_nodes:Array=patch.nodes.filter(func(n):return n.id=="axel_n_3167d4e232cb")
		check(joint_nodes.size()==1,"joint layout carries exactly the measured main-road realignment")
		if stopped():return
		var joint_layout:=await operation("get_city_layout",{})
		if stopped():return
		await operation("apply_terrain_layout",{"strokes":strokes,"road_nodes":joint_nodes,"expected_road_token":joint_layout.road_token})
		if stopped():return
		verify_grass_after_grade()
		if stopped():return
		var layout:=await operation("get_city_layout",{})
		if stopped():return
		await operation("update_road_graph",{"expected_token":layout.road_token,"nodes":patch.nodes,"edges":patch.edges,"remove_nodes":patch.remove_nodes,"remove_edges":patch.remove_edges})
		if stopped():return
		preview=await operation("preview_bridge",bridge)
		if stopped():return
		await operation("generate_bridge",bridge.merged({"plan_token":preview.plan_token},true))
		if stopped():return
		var fixture:=FileAccess.open(OUT+"/s12_before_river_stage.bin",FileAccess.WRITE)
		check(fixture!=null,"persist exact native stage before river entrance validation")
		if stopped():return
		fixture.store_var({"candidate_sha256":report.candidate_before_sha256,"before":before,"snapshot":editor._doc.recovery_snapshot(),"inputs":inputs.duplicate(true),"grass_moves":grass_moves,"grass_removals":grass_removals,"s10_tree_move":s10_tree_move,"operations":report.operations})
		fixture.close()
	if "--stage-before-river" in OS.get_cmdline_user_args():
		report.phase="native_pre_river_stage_saved";persist();editor._mcp.stop();quit(0);return
	await correct_bridge_approaches()
	if stopped():return
	# Rebuild the complete native road plan after the bridge conversion. The
	# immediate conversion clips existing patches, while the new T junctions
	# and portal boundary must also be regenerated before terrain followers run.
	var before_river_settings:Dictionary=data("housing_recipe.json").road_settings
	preview=await operation("preview_road_surface",before_river_settings)
	if stopped():return
	await operation("generate_road_surface",before_river_settings.merged({"plan_token":preview.plan_token},true))
	if stopped():return
	if "--preview-river-only" in OS.get_cmdline_user_args():
		var entrance_before:Dictionary=editor._doc.recovery_snapshot()
		await operation("preview_terrain_river",request)
		check(City.token(editor._doc.recovery_snapshot())==City.token(entrance_before),"complete native river entrance preview has no side effects")
		if stopped():return
		report.phase="complete_native_river_preview_passed";persist();editor._mcp.stop();quit(0);return
	await operation("generate_terrain_river",request)
	if stopped():return
	# Validate against the actual final profile water, including the full wet
	# width. The earlier preview had no water beneath the new crossing yet.
	var actual_bridge:Dictionary=editor._doc._find(bridge.id)
	var clearance:Dictionary=preload("res://scripts/world_editor/bridge_clearance.gd").fit(actual_bridge.duplicate(true),editor._doc.records,false)
	report.final_bridge_clearance=clearance;check(clearance.ok,"frozen bridge full wet-width clearance")
	check(clearance.get("applicable",false) and clearance.get("mode","")=="stream" and float(clearance.get("clearance",-INF))>=.2,"stream clearance covers actual water with required minimum")
	var ports:=preload("res://scripts/world3d/road_bridges.gd").resolve(City.resolve(editor._doc.map_meta))
	check(ports.ok,"six native bridge bindings valid")
	var matching_portals:=0
	if ports.ok:
		for portal:Dictionary in ports.portals:
			if portal.deck_id==bridge.id:
				matching_portals+=1
				var verified:Dictionary=preload("res://scripts/world_editor/bridge_road_tools.gd").verify(editor,portal)
				check(verified.ok,"new frozen bridge agrees with bound road endpoints")
	check(matching_portals==1,"exactly one native portal belongs to the stream bridge")
	if stopped():return
	# The road plan was generated before carving. The river's shared terrain
	# follower already refits and validates every affected owned pavement in
	# the same operation; unchanged topology needs no second full regeneration.
	await finish_appearance(request)
	if stopped():return
	verify_preserved()
	var resource_preflight:=preload("res://tools/audit_axel_bridge_assets.gd").audit_document(editor._doc,"",[bridge.id])
	check(resource_preflight.passed,"new frozen bridge resource preflight before save")
	check(FileAccess.get_sha256(CANDIDATE)==report.candidate_before_sha256,"no intermediate map save")
	check(FileAccess.get_sha256(FORMAL)==report.formal_before_sha256,"formal map untouched")
	if stopped():return
	# Collapse the private operation sequence into one native recovery change.
	# Preserve existing history; never resize a capped history by stale indices.
	var after:Dictionary=editor._doc.recovery_snapshot()
	editor._doc=live_document;editor._doc.apply_recovery(after);editor._doc.commit_recovery_change(before)
	check(editor._doc.undo(),"whole watercourse native undo")
	check(equivalent(stable_contents(editor._doc.recovery_snapshot()),stable_contents(before)),"undo restores pre-watercourse contents")
	check(editor._doc.redo(),"whole watercourse native redo")
	check(equivalent(stable_contents(editor._doc.recovery_snapshot()),stable_contents(after)),"redo restores full connected watercourse")
	if stopped():return
	if dry:
		report.phase="native_preflight_complete";persist();editor._mcp.stop();quit(0);return
	for name_:String in inputs:check(FileAccess.get_sha256(OUT.path_join(name_))==inputs[name_],"input remains pinned "+name_)
	if report.get("resumed_native_stage",false):validate_stage_pins()
	if stopped():return
	await operation("save_world",{})
	if stopped():return
	report.saved=true
	var reopened=Doc.open_file(CANDIDATE)
	check(reopened!=null and reopened.validate_save()==OK,"saved candidate native reopens")
	if reopened!=null:
		check(City.token(reopened.records)==City.token(editor._doc.records) and City.token(reopened.map_meta)==City.token(editor._doc.map_meta),"native save/reopen identity")
	if stopped():return
	report.saved=true;report.candidate_sha256=FileAccess.get_sha256(CANDIDATE);report.phase="candidate_watercourse_complete";persist()
	var resource_audit:=preload("res://tools/audit_axel_bridge_assets.gd").write_report(reopened,CANDIDATE,OUT+"/s12_stream_bridge_assets",[bridge.id])
	check(resource_audit.passed,"new stream bridge frozen resource audit")
	if stopped():return
	var recipe:=data("housing_recipe.json")
	recipe.road_graph=City.resolve(reopened.map_meta).roads.duplicate(true)
	recipe.road_settings=City.resolve(reopened.map_meta).road_surface.settings.duplicate(true)
	write_json(OUT+"/housing_recipe.json",recipe)
	baseline_build.candidate_sha256=report.candidate_sha256
	baseline_build.authoring_inputs["housing_recipe.json"]=FileAccess.get_sha256(OUT+"/housing_recipe.json")
	for placement:Dictionary in baseline_build.props.placements:
		if placement.id==s10_tree_move.id:
			placement.position=s10_tree_move.position;placement.rotation=s10_tree_move.rotation;placement.scale=s10_tree_move.scale
	baseline_build.s10_tree_correction=s10_tree_move.duplicate(true)
	var final_profile:=preload("res://scripts/world3d/terrain_river_profile.gd").prepare(request)
	var actual_length:=0.
	for i in range(1,final_profile.path.size()):
		actual_length+=Vector2(final_profile.path[i][0],final_profile.path[i][1]).distance_to(Vector2(final_profile.path[i-1][0],final_profile.path[i-1][1]))
	baseline_build.watercourse={"continuous":true,"actual_length_m":actual_length,"request":request,"bridge":bridge,"report":OUT+"/s12_watercourse_update.json","candidate_sha256":report.candidate_sha256,"project_supplementary":true,"visual_acceptance":"pending new watercourse cameras"}
	# Keep house/prop receipts and the unapplied S10 plan hash exactly as before.
	write_json(OUT+"/build.json",baseline_build)
	write_json(OUT+"/s12_watercourse_applied_20261015.json",{
		"status":"native_candidate_applied_visual_pending","candidate_sha256":report.candidate_sha256,
		"reference_observation":"S12 animation shows a narrow shallow stream, stepping stones and arched residential frontage; it does not establish a complete geographic catchment.",
		"project_supplementary_design":true,"request":request,"actual_length_m":actual_length,
		"source_boundary":{"xz":request.points.front(),"actual_terrain_north_edge_z":-30,"open_channel_reaches_boundary":true},
		"receiving_river":{"id":"axel_main_river","level":3,"tail_same_level_before_junction":true},
		"bridge":bridge,"full_wet_clearance":clearance,
		"terrain_design":"Native smooth banks with one continuous descending rapid; detailed bank rock/sand materials remain deferred. No isolated flat pools or claim of simulated waterfall hydraulics.",
		"water_appearance":report.get("water_appearance_source",{}),
		"supersedes_design_only":"s12_hydrology_design_20261015.json remains preliminary historical evidence; final request and actual sampled length are recorded here.",
		"formal_map_unchanged":true,"visual_review":"pending parent GPU watercourse cameras"})
	editor._mcp.stop();quit(0 if failed==0 else 1)
