extends "res://tools/test_world3d_mcp.gd"
## Native candidate-only market integration; never writes the formal town.
const Content=preload("res://tools/axel_market_layout_content.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
var path:="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
var expected_sha:=""
var apply_requested:=false
var report:Dictionary={"saved":false,"phase":"starting","operations":[],"phase_elapsed_ms":{}}
func persist()->void:
	report.failures=failed
	var file:=Content.OUT+"/market_build.json";var pending:=file+".pending"
	var f:=FileAccess.open(pending,FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close();Atomic.publish(pending,file)
func stopped()->bool:
	if failed==0:return false
	report.phase="failed";persist()
	if is_instance_valid(editor) and editor._mcp!=null:editor._mcp.stop()
	quit(1);return true
func identity(snapshot:Dictionary)->Dictionary:return {"records":snapshot.records,"map_meta":snapshot.map_meta}
func run()->void:
	create_timer(1800).timeout.connect(func():check(false,"market authoring timeout");persist();quit(2));rpc_timeout_ms=600000
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--apply":apply_requested=true
		elif arg.begins_with("--map="):path=arg.trim_prefix("--map=").replace("\\","/").simplify_path()
		elif arg.begins_with("--expected-sha="):expected_sha=arg.trim_prefix("--expected-sha=")
	check(path.begins_with("D:/code/rmmo_runtime/cache/world3d/") and path!=FORMAL,"candidate-only target")
	check(not expected_sha.is_empty() and FileAccess.file_exists(path) and FileAccess.get_sha256(path)==expected_sha,"exact candidate revision")
	if stopped():return
	report.merge({"map":path,"input_sha256":expected_sha,"formal_before_sha256":FileAccess.get_sha256(FORMAL),"apply":apply_requested})
	var temporary:=Content.OUT+"/market_apply_fixture/map.gltf";DirAccess.make_dir_recursive_absolute(temporary.get_base_dir())
	var empty:=Doc.new();check(empty.save(temporary)==OK,"native empty test fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=temporary;session.world3d_editor_doc=empty
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=Content.OUT+"/market_apply_drafts";root.add_child(editor)
	await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	while editor._ground_batches.stats().get("pending_groups",0)>0:await process_frame
	var original=Doc.open_file(path);check(original!=null,"native candidate opens")
	if stopped():return
	var before:Dictionary=original.recovery_snapshot();var staged=Doc.new();staged.apply_recovery(before);editor._doc=staged;editor._city.refresh();editor._authoring.refresh()
	var prepared:=Content.prepare(staged);check(prepared.ok,"complete market inputs and native terrain plan")
	if stopped():return
	report.inputs=prepared.inputs;report.phase="prepared";persist()
	var listener:=TCPServer.new();port=32770
	while listener.listen(port,"127.0.0.1")!=OK:port+=1
	listener.stop();check(editor.start_mcp(port).ok,"current 3D loopback authoring")
	report.phase="native_joint_terrain";persist();var phase_started:=Time.get_ticks_msec()
	var result:=await call_tool("apply_terrain_layout",prepared.terrain_request);report.phase_elapsed_ms.terrain=Time.get_ticks_msec()-phase_started;report.operations.append({"tool":"apply_terrain_layout","result":result});persist()
	if stopped():return
	report.phase="native_entry_roads";persist();phase_started=Time.get_ticks_msec()
	result=await call_tool("update_road_graph",Content.road_request(staged,prepared));report.phase_elapsed_ms.roads=Time.get_ticks_msec()-phase_started;report.operations.append({"tool":"update_road_graph","result":result});persist()
	if stopped():return
	report.phase="native_content_placement";persist();phase_started=Time.get_ticks_msec()
	result=Content.apply_content(staged,prepared);report.phase_elapsed_ms.content=Time.get_ticks_msec()-phase_started;report.content=result;check(result.ok,"native full house and market placements")
	if stopped():return
	report.phase="whole_road_validation";persist();phase_started=Time.get_ticks_msec()
	editor._city.refresh();var roads:Dictionary=editor._roads.prepare({});report.phase_elapsed_ms.road_validation=Time.get_ticks_msec()-phase_started;check(roads.ok,"whole-road protection after final placements")
	report.road_validation={"ok":roads.ok,"error":roads.get("error",""),"diff":roads.get("diff",{})};persist()
	if stopped():return
	check(roads.diff.added==0 and roads.diff.updated==0 and roads.diff.removed==0,"native road mesh already reflects final graph")
	check(staged.validate_save()==OK,"native market candidate is saveable")
	check(staged.map_meta.building_instances.size()==before.map_meta.building_instances.size()+prepared.houses.size(),"new houses retain native ownership")
	check(City.token(before.map_meta.terrain_rivers)==City.token(staged.map_meta.terrain_rivers),"watercourse ownership unchanged")
	check(City.token(City.resolve(before.map_meta).zones)==City.token(City.resolve(staged.map_meta).zones),"R1-R5 preserved")
	var preserved:=0
	for record:Dictionary in before.records:
		if record.has("terrain_mesh") or record.has("road_mesh"):continue
		if City.token(record)!=City.token(staged._find(record.uuid)):check(false,"pre-existing content changed: "+record.uuid);break
		preserved+=1
	report.preserved_source_objects=preserved
	var after:Dictionary=staged.recovery_snapshot();original.apply_recovery(after);original.commit_recovery_change(before)
	check(original.undo() and City.token(identity(original.recovery_snapshot()))==City.token(identity(before)),"one native undo restores before market")
	check(original.redo() and City.token(identity(original.recovery_snapshot()))==City.token(identity(after)),"one native redo restores whole market")
	check(FileAccess.get_sha256(path)==expected_sha and FileAccess.get_sha256(FORMAL)==report.formal_before_sha256,"candidate and formal unchanged during staging")
	if stopped():return
	if apply_requested:
		check(original.save(path)==OK,"native atomic candidate market save")
		if stopped():return
		report.saved=true;report.candidate_sha256=FileAccess.get_sha256(path)
		var reopened=Doc.open_file(path)
		check(reopened!=null and City.token(identity(reopened.recovery_snapshot()))==City.token(identity(after)),"native market save reopens exactly")
	report.phase="native_market_complete_review_pending";persist();editor._mcp.stop();quit(0 if failed==0 else 1)
