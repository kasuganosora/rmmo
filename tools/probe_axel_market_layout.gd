extends "res://tools/test_world3d_mcp.gd"
## Read-only formal input, native staged transactions, no GPU and no map save.
const Content=preload("res://tools/axel_market_layout_content.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
var report:={"phase":"starting","saved":false,"gpu_review":"not run; root owns final scene review"}
func receipt():
	report.failures=failed
	FileAccess.open(Content.OUT+"/market_native_preflight.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
func stop()->bool:
	if not failed:return false
	report.phase="failed_no_map_save";receipt();quit(1);return true
func contents(snapshot:Dictionary)->Dictionary:return {"records":snapshot.records,"map_meta":snapshot.map_meta}
func run()->void:
	create_timer(1800).timeout.connect(func():check(false,"Market preflight timeout");receipt();quit(2))
	rpc_timeout_ms=300000
	var source_sha:=FileAccess.get_sha256(MAP);report.source_map_sha256=source_sha;report.plan_sha256=FileAccess.get_sha256(Content.PLAN);receipt()
	# Initialize the real editor on an empty native test map. Attach the formal
	# document as data only, avoiding a repeated complete scene/model load.
	var temporary:=Content.OUT+"/market_empty_fixture/map.gltf";DirAccess.make_dir_recursive_absolute(temporary.get_base_dir())
	var empty:=Doc.new();check(empty.save(temporary)==OK,"Empty native fixture created")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=temporary;session.world3d_editor_doc=empty
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=Content.OUT+"/market_preflight_drafts";root.add_child(editor)
	await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	while editor._ground_batches.stats().get("pending_groups",0)>0:await process_frame
	editor._doc=Doc.open_file(MAP);editor._city.refresh()
	check(editor._doc.map_meta.get("building_instances",{}).size()>=21,"Native source house records attached without whole-scene load")
	var before:Dictionary=editor._doc.recovery_snapshot();var original=editor._doc;var staged=Doc.new();staged.apply_recovery(before);editor._doc=staged
	var prepared:=Content.prepare(staged);check(prepared.ok,"Prepare market layout from unchanged native sources")
	if stop():return
	report.prepared={"houses":prepared.houses.map(func(h):var r=h.duplicate(true);r.erase("template");return r),"stalls":prepared.stalls,"terrain_request":prepared.terrain_request,"inputs":prepared.inputs};report.phase="prepared";receipt()
	var listener:=TCPServer.new();port=32440
	while listener.listen(port,"127.0.0.1")!=OK:port+=1
	listener.stop();check(editor.start_mcp(port).ok,"Current 3D HTTP starts on loopback")
	var terrain:=await call_tool("apply_terrain_layout",prepared.terrain_request);report.terrain_result=terrain
	if stop():return
	var roads:=Content.road_request(staged,prepared);report.road_request=roads;receipt()
	var route:=await call_tool("update_road_graph",roads);report.road_result=route
	if stop():return
	var result:=Content.apply_content(staged,prepared);report.content_result=result;check(result.ok,"Native complete houses and independent market assets placed")
	if not result.ok:print(JSON.stringify(result))
	if stop():return
	editor._city.refresh()
	var final_roads:Dictionary=editor._roads.prepare({});check(final_roads.ok,"Final native whole-road protection with all new content")
	report.final_roads={"ok":final_roads.ok,"error":final_roads.get("error",""),"conflicts":final_roads.get("conflicts",[]),"diff":final_roads.get("diff",{})}
	if stop():return
	check(final_roads.diff.added==0 and final_roads.diff.updated==0 and final_roads.diff.removed==0,"All road surface changes already committed in native staged document")
	check(staged.validate_save()==OK,"Native candidate save validation")
	check(staged.map_meta.building_instances.size()==before.map_meta.building_instances.size()+6,"Exactly six complete native buildings added")
	check(City.token(before.map_meta.terrain_rivers)==City.token(staged.map_meta.terrain_rivers),"Waterway ownership unchanged")
	check(City.token(City.resolve(before.map_meta).zones)==City.token(City.resolve(staged.map_meta).zones),"R1-R5 unchanged")
	for record:Dictionary in before.records:
		if record.has("terrain_mesh") or record.has("road_mesh"):continue
		check(City.token(record)==City.token(staged._find(record.uuid)),"Existing non-terrain object unchanged "+record.uuid)
	var after:Dictionary=staged.recovery_snapshot();original.apply_recovery(after);original.commit_recovery_change(before)
	check(original.undo() and City.token(contents(original.recovery_snapshot()))==City.token(contents(before)),"One native undo restores original content")
	check(original.redo() and City.token(contents(original.recovery_snapshot()))==City.token(contents(after)),"One native redo restores all market layout")
	check(FileAccess.get_sha256(MAP)==source_sha,"Formal map untouched")
	report.phase="native_preflight_passed" if failed==0 else "failed_no_map_save";report.native_building_count=staged.map_meta.building_instances.size();report.source_map_unchanged=FileAccess.get_sha256(MAP)==source_sha
	receipt();editor._mcp.stop();quit(0 if failed==0 else 1)
