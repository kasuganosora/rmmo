extends "res://tools/test_world3d_mcp.gd"
## Native temporary content candidate; never writes the formal birth map.
## Plan contains source_sha256, terrain_batches and fortification_request.
const City=preload("res://scripts/world3d/city_layout.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const SOURCE="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const CANDIDATE="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
var report:Dictionary={"phase":"starting","saved":false,"operations":[]}
var plan:Dictionary
var plan_path:=OUT+"/fortification_content_recipe.json"
var apply_requested:=false
var source_before:Dictionary
var allowed_relocations:Dictionary={}
func json_file(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func atomic_json(path:String,value:Dictionary)->void:
	var pending:=path+".pending";var f:=FileAccess.open(pending,FileAccess.WRITE)
	if f==null:push_error("Receipt write failed "+path);failed+=1;return
	f.store_string(JSON.stringify(value,"\t"));f.close()
	if Atomic.publish(pending,path)!=OK:failed+=1
func persist()->void:
	report.failures=failed;atomic_json(OUT+"/fortification_build.json",report)
func stopped()->bool:
	if failed==0:return false
	report.phase="failed";persist()
	if is_instance_valid(editor) and editor._mcp!=null:editor._mcp.stop()
	quit(1);return true
func wait_ready()->void:
	var deadline:=Time.get_ticks_msec()+360000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if editor._load_job!=null and editor._load_job.active:continue
		if editor._ground_batches.stats().get("pending_groups",0)>0:continue
		await settle();return
	check(false,"native scene preparation completed")
func operation(name_:String,args:Dictionary)->Dictionary:
	report.phase=name_;persist()
	var result:=await call_tool(name_,args)
	report.operations.append({"tool":name_,"request":args,"result":result});persist()
	return result
func identity(snapshot:Dictionary)->Dictionary:return {"records":snapshot.records,"map_meta":snapshot.map_meta}
func run()->void:
	create_timer(2400).timeout.connect(func():check(false,"content helper timeout");persist();quit(2))
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--apply":apply_requested=true
		elif arg.begins_with("--plan="):plan_path=arg.trim_prefix("--plan=")
	DirAccess.make_dir_recursive_absolute(OUT);rpc_timeout_ms=600000
	check(FileAccess.file_exists(plan_path),"native fortification content recipe exists")
	if stopped():return
	plan=json_file(plan_path)
	check(plan.get("source_sha256","")==FileAccess.get_sha256(SOURCE),"exact source pin before preparation")
	check(not FileAccess.file_exists(CANDIDATE),"new stage candidate not overwritten")
	if stopped():return
	report.merge({"source":SOURCE,"source_sha256":plan.source_sha256,"candidate":CANDIDATE,"plan_path":plan_path,"plan_sha256":FileAccess.get_sha256(plan_path),"apply":apply_requested})
	var formal=Doc.open_file(SOURCE);check(formal!=null,"native formal source opens")
	if stopped():return
	source_before=formal.recovery_snapshot()
	var doc=Doc.new();doc.apply_recovery(source_before)
	var temporary:=OUT+"/fortification_empty_fixture/map.gltf";DirAccess.make_dir_recursive_absolute(temporary.get_base_dir())
	var empty:=Doc.new();check(empty.save(temporary)==OK,"empty native test fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=temporary;session.world3d_editor_doc=empty
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=OUT+"/wall_drafts"
	root.add_child(editor);await settle();await wait_ready()
	if stopped():return
	editor._doc=doc;editor._city.refresh();editor._authoring.refresh()
	var listener:=TCPServer.new();port=32010
	while listener.listen(port,"127.0.0.1")!=OK:port+=1
	listener.stop();check(editor.start_mcp(port).ok,"current native 3D HTTP authoring starts")
	var discovery:=await rpc("tools/list")
	check(discovery.get("result",{}).get("tools",[]).any(func(t):return t.name=="generate_fortification"),"current fortification tool discoverable")
	if stopped():return
	var relocation_path:=OUT+"/fortification_vegetation_relocations.json"
	if FileAccess.file_exists(relocation_path):
		var relocations:=json_file(relocation_path)
		check(relocations.get("source_sha256","")==report.source_sha256,"grass relocation source revision matches")
		if stopped():return
		report.relocation_plan={"path":relocation_path,"sha256":FileAccess.get_sha256(relocation_path)}
		await operation("configure_transform",{"gravity_placement":false})
		if stopped():return
		for move:Dictionary in relocations.get("relocations",[]):
			var old:Dictionary=editor._doc._find(move.id).duplicate(true)
			check(not old.is_empty() and old.get("kind","")=="asset" and not old.has("building") and City.vec(old.position).distance_to(City.vec(move.old_position))<.001,"exact existing grass relocation "+str(move.id))
			if stopped():return
			var request:Dictionary={"id":move.id,"position":move.position}
			if move.has("rotation"):request.rotation=move.rotation
			await operation("set_object_transform",request)
			if stopped():return
			var actual:Dictionary=editor._doc._find(move.id)
			var without_pose:=actual.duplicate(true);without_pose.position=old.position;without_pose.rotation=old.rotation
			check(City.token(without_pose)==City.token(old) and City.vec(actual.position).distance_to(City.vec(move.position))<.001,"native relocation changes pose only "+str(move.id))
			allowed_relocations[move.id]=City.token(actual)
			if stopped():return
	for batch:Dictionary in plan.get("terrain_batches",[]):
		await operation("apply_terrain_layout",batch)
		if stopped():return
	if not plan.get("road_node_adjustments",[]).is_empty():
		var graph:Dictionary=City.resolve(editor._doc.map_meta).roads
		var adjusted:Array=[]
		var terrains:Array=editor._doc.records.filter(func(r):return r.has("terrain_mesh"))
		for move:Dictionary in plan.road_node_adjustments:
			var matches:Array=graph.nodes.filter(func(n):return n.id==move.id)
			check(matches.size()==1,"exact existing alley node "+str(move.id))
			if stopped():return
			var node:Dictionary=matches[0].duplicate(true)
			check(City.vec(node.position).distance_to(City.vec(move.source_position))<.001,"alley source position unchanged "+str(move.id))
			if stopped():return
			var point:=Vector3(move.target_xz[0],0,move.target_xz[1])
			point.y=preload("res://scripts/world_editor/bridge_tools.gd").ground_height(terrains,point)
			check(is_finite(point.y),"new alley node has native terrain support "+str(move.id))
			if stopped():return
			node.position=[point.x,point.y,point.z];adjusted.append(node)
		await operation("update_road_graph",{"expected_token":City.token(graph),"nodes":adjusted})
		if stopped():return
	var before_wall:Dictionary=editor._doc.recovery_snapshot()
	# A native temporary checkpoint preserves completed terrain authoring if a
	# subsequent preview reveals another real layout conflict. It is not published.
	var preparation_path:=CANDIDATE.get_base_dir()+"/prewall/map.gltf"
	DirAccess.make_dir_recursive_absolute(preparation_path.get_base_dir())
	editor._doc.accept_save(preparation_path,FileAccess.get_sha256(preparation_path))
	check(editor._doc.save(preparation_path)==OK,"native temporary prewall checkpoint")
	if stopped():return
	report.prewall_checkpoint={"path":preparation_path,"sha256":FileAccess.get_sha256(preparation_path)};persist()
	var preview:=await operation("preview_fortification",plan.fortification_request)
	if stopped():return
	var request:Dictionary=plan.fortification_request.duplicate(true);request.plan_token=preview.plan_token
	var applied:=await operation("generate_fortification",request)
	if stopped():return
	var after_wall:Dictionary=editor._doc.recovery_snapshot()
	check(editor._doc.undo() and City.token(identity(editor._doc.recovery_snapshot()))==City.token(identity(before_wall)),"native undo removes entire generated fortification")
	check(editor._doc.redo() and City.token(identity(editor._doc.recovery_snapshot()))==City.token(identity(after_wall)),"native redo restores entire generated fortification")
	check(City.token(editor._doc.map_meta.building_instances)==City.token(source_before.map_meta.building_instances),"existing 21 house identities and ownership unchanged")
	check(City.token(City.resolve(editor._doc.map_meta).zones)==City.token(City.resolve(source_before.map_meta).zones),"R1-R5 preserved")
	var untouched:=0
	for old:Dictionary in source_before.records:
		if old.has("terrain_mesh") or old.has("road_mesh"):continue
		if allowed_relocations.has(old.uuid):
			check(City.token(editor._doc._find(old.uuid))==allowed_relocations[old.uuid],"relocated grass retains intended placement "+str(old.uuid));continue
		if City.token(old)!=City.token(editor._doc._find(old.uuid)):
			check(false,"source object changed outside terrain/pavement "+str(old.uuid));break
		untouched+=1
	check(untouched>0,"source houses, props, rivers, six bridges and landmarks unchanged")
	var terrain_changes:Array=[]
	for old:Dictionary in source_before.records:
		if old.has("terrain_mesh") and City.token(old)!=City.token(editor._doc._find(old.uuid)):terrain_changes.append(old.uuid)
	check(editor._doc.validate_save()==OK,"complete native candidate save validation")
	check(FileAccess.get_sha256(SOURCE)==report.source_sha256 and FileAccess.get_sha256(plan_path)==report.plan_sha256,"source and recipe unchanged during preparation")
	if report.has("relocation_plan"):check(FileAccess.get_sha256(report.relocation_plan.path)==report.relocation_plan.sha256,"grass relocation plan unchanged during preparation")
	if stopped():return
	report.merge({"phase":"native_content_preflight_passed","preview":preview,"generated":applied,"terrain_records_changed":terrain_changes,"preserved_source_objects":untouched,"visual":"pending","runtime":"pending"});persist()
	if not apply_requested:editor._mcp.stop();quit(0);return
	editor._doc.map_meta.town_reference.fortification_layout={"project_supplementary_design":true,"source":plan_path,"phase":"native_candidate_review_pending","gates":preview.gates,"access_routes":preview.access_routes,"relocated_vegetation":allowed_relocations,"cameras":plan.get("cameras",[])}
	var final_snapshot:Dictionary=editor._doc.recovery_snapshot()
	DirAccess.make_dir_recursive_absolute(CANDIDATE.get_base_dir())
	editor._doc.accept_save(CANDIDATE, "")
	check(editor._doc.save(CANDIDATE)==OK,"native atomic temporary candidate save")
	if stopped():return
	report.saved=true;report.candidate_sha256=FileAccess.get_sha256(CANDIDATE);persist()
	var reopened=Doc.open_file(CANDIDATE)
	check(reopened!=null and reopened.validate_save()==OK,"native candidate reopens")
	if reopened!=null:check(City.token(identity(reopened.recovery_snapshot()))==City.token(identity(final_snapshot)),"native reopen preserves exact records and metadata")
	check(FileAccess.get_sha256(SOURCE)==report.source_sha256,"formal source remains unchanged")
	if stopped():return
	report.phase="native_candidate_complete_review_pending";persist()
	editor._mcp.stop();quit(0)
