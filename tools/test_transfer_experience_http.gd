extends "res://tools/test_world3d_mcp.gd"
const Net=preload("res://scripts/net/net.gd")
const Templates=preload("res://scripts/world3d/event_templates.gd")
var directory:="D:/code/rmmo_runtime/review_artifacts/transfer_experience_20261017"
var evidence:Dictionary={"checks":[],"transfers":[]}
func check(ok:bool,label_:String)->void:
	super.check(ok,label_);evidence.checks.append({"ok":ok,"label":label_})
func wait_phase(phase:String)->void:
	var deadline:=Time.get_ticks_msec()+90000
	while editor._playtest.phase!=phase and editor._playtest.phase!="failed" and Time.get_ticks_msec()<deadline:await process_frame
	check(editor._playtest.phase==phase,"playtest phase "+phase+" "+editor._playtest.last_error)
func trigger(id:String,destination:Vector3)->void:
	var world:Node3D=editor._playtest.world
	var camera:Camera3D=world._camera.camera
	var fov:=camera.fov;var aa:=world.get_viewport().msaa_3d;var size:Vector2i=world.get_viewport().size
	var actions:Array=Net.server().world3d_events.run(id)
	print("EVENT_DIAGNOSTIC ",JSON.stringify({"id":id,"targets":Net.server().world3d_events.targets.keys(),"actions":actions,"ready":world.is_world_ready(),"records":Io.extras_of(world._map_root).get("rmmo_records",[]).size()}))
	check(actions.size()==1 and actions[0].type=="world3d_transfer","saved event compiles to one current 3D transfer action")
	world.apply_actions(actions)
	var deadline:=Time.get_ticks_msec()+90000
	var saw:=false;var frozen:=true;var viewport_valid:=true
	while world._transfer_pending and Time.get_ticks_msec()<deadline:
		var cover:Node=world.get_node_or_null("TransferLoading")
		if cover!=null:
			saw=true;frozen=frozen and world._player.input_locked
			viewport_valid=viewport_valid and cover.get_viewport()==world.get_viewport()
		await process_frame
	var profile:Dictionary=world.get_meta("transfer_loading_profile",{})
	check(saw and frozen and viewport_valid and profile.get("ok",false),"authored event uses shared fade inside the actual playtest viewport")
	check(world._player.global_position.distance_to(destination)<.03 and not world._player.input_locked,"authored feet convert once to body center and input resumes")
	check(camera.fov==fov and world.get_viewport().msaa_3d==aa and world.get_viewport().size==size,"transfer preserves FOV, antialiasing and output resolution")
	check(profile.get("input_restored_ms",0)>=profile.get("revealed_ms",1) and profile.get("ready_frame",-1)>profile.get("drawn_frame",0),"real target frame and fade finish before input resumes")
	evidence.transfers.append(profile)
func run()->void:
	create_timer(240).timeout.connect(func():print("TRANSFER_HTTP_TIMEOUT");quit(2))
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(directory)
	var fixture:=Paths.cache_directory("transfer_experience_%d"%Time.get_ticks_usec())
	var path:=fixture.path_join("source.gltf");var target:=fixture.path_join("target.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.1,0),Vector3(32,.2,32));doc.map_meta={"spawn":[0,.9,0]}
	check(doc.save(path)==OK and doc.save(target)==OK,"create isolated native maps")
	Net.session().world3d_editor_path=path;Net.session().world3d_editor_doc=doc
	preload("res://tools/world3d_test_character.gd").ensure(self)
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=fixture.path_join("drafts");root.add_child(editor);await settle();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start isolated loopback 3D MCP")
	var discovery:=await rpc("tools/list");var found:=false
	for tool:Dictionary in discovery.result.tools:
		if tool.name=="create_event_template":found=str(tool.description).contains("淡出淡入")
	check(found,"real discovery documents shared transfer presentation")
	var baseline:Dictionary=doc.recovery_snapshot();var count:int=doc._undo.size()
	await call_tool("create_event_template",{"template":"transfer","position":[-8,0,-8],"parameters":{"map_path":fixture.path_join("missing.gltf")}},false)
	await call_tool("create_event_template",{"template":"transfer","position":[-8,0,-8],"parameters":{"map_path":path,"spawn":[1,2]}},false)
	check(equivalent(baseline,doc.recovery_snapshot()) and count==doc._undo.size(),"invalid requests leave author data and history untouched")
	var created:=await call_tool("create_event_template",{"template":"transfer","position":[-8,0,-8],"parameters":{"map_path":path,"spawn":[2,0,1]}})
	var id:String=created.id
	await call_tool("undo");check(doc._find(id).is_empty(),"event undo removes exact instance")
	await call_tool("redo");check(not doc._find(id).is_empty(),"event redo restores identity")
	await call_tool("select_objects",{"ids":[id]})
	var panel:VBoxContainer=editor._event_panel
	var values:Dictionary=Templates.defaults("transfer");values.merge({"map_path":path,"spawn":[3,0,1]},true)
	panel.type_select.select(Templates.LABELS.keys().find("transfer"));panel.fill(values);panel.apply_button.pressed.emit()
	check(equivalent(doc._find(id).event_template.parameters.spawn,[3,0,1]) and panel.transfer_hint.visible,"UI event form applies shared parameters and shows automatic transition help")
	var other:=await call_tool("create_event_template",{"template":"transfer","position":[8,0,8],"parameters":{"map_path":target,"spawn":[-3,0,1]}})
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(equivalent(doc._find(id).event_template.parameters.spawn,[3,0,1]) and doc._find(other.id).event_template.parameters.map_path==target,"UI and MCP authored events survive native save/reopen")
	var sha:=FileAccess.get_sha256(path);var target_sha:=FileAccess.get_sha256(target)
	var source_server:Node=Net.server();var source_inventory:Dictionary=source_server.inventory.capture_session_state()
	await call_tool("set_playtest_spawn",{"position":[0,0,0]});await call_tool("start_playtest");await wait_phase("running")
	if editor._playtest.phase=="running":
		check(Io.extras_of(editor._playtest.world._map_root).get("rmmo_records",[]).size()==doc.records.size(),"playtest mounts real native author records instead of reference glTF proxies")
		await trigger(id,Vector3(3,.9,1))
		await trigger(other.id,Vector3(-3,.9,1))
		var live_world:Node3D=editor._playtest.world
		var live_viewport:SubViewport=editor._playtest.viewport
		live_world.transfer_map(target,Vector3(5,.9,1))
		var deadline:=Time.get_ticks_msec()+5000
		while is_instance_valid(live_world) and not live_viewport.disable_3d and Time.get_ticks_msec()<deadline:await process_frame
		check(live_viewport.disable_3d and live_world._transfer_pending,"exit probe reaches real covered transfer")
		await call_tool("stop_playtest");await wait_phase("idle")
		check(not is_instance_valid(live_world) and not is_instance_valid(live_viewport),"stop during covered transfer destroys only owned world, viewport and cover")
	await call_tool("start_playtest");await wait_phase("running")
	if editor._playtest.phase=="running":
		var blocked_world:Node3D=editor._playtest.world
		var blocked_view:SubViewport=editor._playtest.viewport
		var previous:Vector3=blocked_world._player.global_position
		blocked_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
		var entered:bool=await blocked_world.transfer_map(path,Vector3(3,.9,1))
		var held:Node=blocked_world.get_node_or_null("TransferLoading")
		check(not entered and blocked_world._player.input_locked and blocked_world._player.global_position==previous and held!=null and held.phase=="failed" and held._back!=null,"undrawable source viewport yields explicit failure exit without moving/unlocking actor")
		blocked_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		await call_tool("stop_playtest");await wait_phase("idle")
	check(Net.server()==source_server and source_server.inventory.capture_session_state()==source_inventory,"playtest restores real server and inventory without edits")
	check(FileAccess.get_sha256(path)==sha and FileAccess.get_sha256(target)==target_sha,"runtime experience leaves both authored maps unchanged")
	evidence.failures=failed;evidence.passed=evidence.checks.size()-failed;evidence.fixture=fixture
	FileAccess.open(directory.path_join("http.json"),FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "))
	editor.free();Net.session().world3d_editor_doc=null;Net.session().world3d_editor_path=""
	print("TRANSFER_EXPERIENCE_HTTP_FINISHED passed=",evidence.passed," failures=",failed);quit(1 if failed else 0)
