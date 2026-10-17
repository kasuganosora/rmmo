extends "res://tools/test_world3d_mcp.gd"
## Read-only-on-disk layout study. Does not apply a block candidate or save a town map.
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_s2_reference_20261017/house_swap_preview_b"
const SOURCE="D:/code/rmmo_runtime/cache/world3d/axel_s2_props_a_20261017/map.gltf"
const EXPECTED="3cf72b3d5787c3b6e23f49382da6593f81aae5ac55306b3e1db11a2a92ef18e0"
var result:Dictionary={"applied":false,"formal_map_modified":false,"operations":[]}
func write_result()->void:
	var file:=FileAccess.open(OUT+"/preview.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(result,"\t"));file.close()
func query(name_:String,args:Dictionary)->Dictionary:
	var response:=await rpc("tools/call",{"name":name_,"arguments":args})
	var value:Dictionary={}
	for item:Dictionary in response.get("result",{}).get("content",[]):
		if item.get("type")=="text":value=JSON.parse_string(item.text)
	result.operations.append({"name":name_,"request":args,"response":value});write_result()
	return value
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if FileAccess.get_sha256(SOURCE)!=EXPECTED:quit(1);return
	result.source={"path":SOURCE,"sha256":EXPECTED}
	create_timer(900).timeout.connect(func():result.timeout=true;write_result();quit(2))
	rpc_timeout_ms=600000
	var fixture:=OUT+"/empty/map.gltf";DirAccess.make_dir_recursive_absolute(fixture.get_base_dir())
	var empty:=Doc.new();if empty.save(fixture)!=OK:quit(1);return
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=fixture;session.world3d_editor_doc=empty
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=OUT+"/drafts";root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	editor._doc=Doc.open_file(SOURCE);editor._city.refresh();editor._authoring.refresh()
	var socket:=TCPServer.new();port=32740
	while socket.listen(port,"127.0.0.1")!=OK:port+=1
	socket.stop();if not editor.start_mcp(port).ok:quit(1);return
	var discovery:=await rpc("tools/list")
	result.block_tool_discovered=discovery.get("result",{}).get("tools",[]).any(func(t):return t.name=="preview_residential_block")
	for id:String in ["building_f071e80c8c5e3f5175bd","building_b94c9e7bc872f916faa5"]:
		var entrance:=await query("inspect_residential_entrances",{"building_id":id})
		if not entrance.get("ok",false):editor._mcp.stop();quit(0);return
	# These two authored legacy paths have no native access binding. Explicitly
	# remove only them through the current native operation in this private study.
	var layout:=await query("get_city_layout",{})
	var removed:=await query("update_road_graph",{"expected_token":layout.road_token,"remove_edges":["home_e_s2_south_oculus_0","home_e_s2_south_neighbor_0"],"remove_nodes":["home_n_0d54c4d26840","home_n_53960d5431fa"]})
	if not removed.get("ok",false):editor._mcp.stop();quit(0);return
	var baseline:Dictionary=editor._doc.recovery_snapshot()
	var request:={"homes":[
		{"id":"oculus_east","residential":{"building_id":"building_f071e80c8c5e3f5175bd","position":[349.5,6.210976,283],"road_edge_id":"axel_e_00f190d77468_h212","old_access":"keep","elevation_min":0,"elevation_max":0,"setback_min":2.2,"setback_max":2.2,"width":1.6}},
		{"id":"plain_home_west","residential":{"building_id":"building_b94c9e7bc872f916faa5","position":[336.5,6.137338,283],"road_edge_id":"axel_e_600b42cfb188_h210","old_access":"keep","elevation_min":0,"elevation_max":0,"setback_min":2.2,"setback_max":2.2,"width":1.6}}
	]}
	var plan:=await query("preview_residential_block",request)
	result.preview_ok=plan.get("ok",false)
	result.preview_preserved_document=equivalent(baseline,editor._doc.recovery_snapshot())
	if plan.get("ok",false):await query("discard_residential_block",{"plan_token":plan.plan_token})
	result.source_unchanged=FileAccess.get_sha256(SOURCE)==EXPECTED
	result.completed=true;write_result();editor._mcp.stop();quit(0)
