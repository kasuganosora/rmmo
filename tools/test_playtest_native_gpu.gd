extends "res://tools/test_editor_native_ui_gpu.gd"
## Actual editor, F5 input, HTTP MCP, native/STEX reader, ownership and play world.
## Native fixture setup is explicit; no production preparation/renderer stubs.
const Net=preload("res://scripts/net/net.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
var editor:Node3D
var asset_id:String
var asset_path:String
var map_path:String
var port:=28970
var rpc_serial:=0
var stage_ids:Dictionary={}
var owned_refs:Array[WeakRef]=[]
var native_preview:Control

class SessionObserver extends "res://scripts/world_editor/playtest_session.gd":
	var observe:Callable
	func _begin_probe(generation:int)->void:
		if observe.is_valid():observe.call("prepared",_asset_handles)
		super._begin_probe(generation)
	func _build_play_scene(clone:RefCounted,generation:int)->Node3D:
		var scene:Node3D=super._build_play_scene(clone,generation)
		if scene!=null and observe.is_valid():observe.call("play",scene)
		return scene

func packed_state(packed:PackedScene)->Dictionary:
	var state:=packed.get_state();var mesh:Mesh
	for node:int in state.get_node_count():
		for property:int in state.get_node_property_count(node):
			if state.get_node_property_name(node,property)==&"mesh":mesh=state.get_node_property_value(node,property);break
		if mesh!=null:break
	var texture:Texture2D=(mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture
	owned_refs.append(weakref(packed));owned_refs.append(weakref(mesh));owned_refs.append(weakref(texture))
	return {"packed":str(packed.get_instance_id()),"mesh":str(mesh.get_instance_id()),"texture":str(texture.get_instance_id()),"rid":str(texture.get_rid().get_id()),"class":texture.get_class()}

func observed(stage:String,value:Variant)->void:
	if stage=="prepared":stage_ids[stage]=packed_state(value[asset_path].packed)
	else:stage_ids[stage]=packed_state(value.get_node(NodePath(asset_id)).get_child(0).get_meta("_compiled_resource_owner"))

func rpc(method:String,params:Dictionary={})->Dictionary:
	rpc_serial+=1
	var body:=JSON.stringify({"jsonrpc":"2.0","id":rpc_serial,"method":method,"params":params}).to_utf8_buffer()
	var request:=("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n"%[port,body.size()]).to_utf8_buffer();request.append_array(body)
	var peer:=StreamPeerTCP.new();peer.connect_to_host("127.0.0.1",port)
	var deadline:=Time.get_ticks_msec()+30000;var sent:=false;var bytes:=PackedByteArray()
	while Time.get_ticks_msec()<deadline:
		await process_frame;peer.poll()
		if peer.get_status()!=StreamPeerTCP.STATUS_CONNECTED:continue
		if not sent:peer.put_data(request);sent=true
		if peer.get_available_bytes()>0:bytes.append_array(peer.get_partial_data(peer.get_available_bytes())[1])
		var split:int=editor._mcp._find_headers_end(bytes)
		if split<0:continue
		var length:=int(editor._mcp._header_value(bytes.slice(0,split).get_string_from_utf8(),"Content-Length"))
		if bytes.size()<split+4+length:continue
		peer.disconnect_from_host()
		var parsed:Variant=JSON.parse_string(bytes.slice(split+4,split+4+length).get_string_from_utf8())
		if parsed is Dictionary:return parsed
		break
	peer.disconnect_from_host();check(false,"HTTP response "+method);return {}

func call_tool(name_:String,args:Dictionary={},expected:=true)->Dictionary:
	var response:=await rpc("tools/call",{"name":name_,"arguments":args})
	var payload:Dictionary={};var result:Dictionary=response.get("result",{})
	for part:Dictionary in result.get("content",[]):
		if part.type=="text":payload=JSON.parse_string(part.text)
	check(payload.get("ok",false)==expected and result.get("isError",true)==not expected,"real HTTP "+name_)
	if expected and not payload.get("ok",false):print(payload)
	return payload

func wait_phase(expected:String)->bool:
	var deadline:=Time.get_ticks_msec()+60000
	while editor._playtest.phase!=expected and editor._playtest.phase!="failed" and Time.get_ticks_msec()<deadline:await process_frame
	var ready:bool=editor._playtest.phase==expected
	check(ready,"playtest "+expected+": "+editor._playtest.last_error)
	return ready

func expire_owners(label:String)->void:
	var deadline:=Time.get_ticks_msec()+20000
	var streaming:Object=Engine.get_singleton("TextureStreaming")
	while Time.get_ticks_msec()<deadline:
		tracker.collect_retired(100)
		if owned_refs.all(func(reference:WeakRef):return reference.get_ref()==null) and tracker.report().entries==0 and service.ledger.reserved_bytes==0 and streaming.call("get_memory_budget_bytes_used")==0:break
		await process_frame
	check(owned_refs.all(func(reference:WeakRef):return reference.get_ref()==null),label+": Packed/Mesh/Texture owners expire")
	check(tracker.report().entries==0 and service.ledger.reserved_bytes==0 and streaming.call("get_memory_budget_bytes_used")==0,label+": published/transient/engine accounting all zero")
	report[label+"_retired"]={"tracker":tracker.report(),"service":service.snapshot(),"engine_bytes":streaming.call("get_memory_budget_bytes_used")}
	owned_refs.clear()

func fixture_source_deleted(path:String)->void:
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	check(document.append_from_scene(original,state)==OK and document.write_to_filesystem(state,path)==OK,"export historical source GLB")
	var source_sha:=FileAccess.get_sha256(path)
	var index:=Compiled.index_path(path,folder);var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index));manifest.source_sha=source_sha;write_json(index,manifest)
	var descriptor:=Footprint.descriptor_path(path,folder);var wrapper:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor));var body:Dictionary=JSON.parse_string(wrapper.body)
	body.source_sha=source_sha;body.model_metadata.local_bounds=[-1,-1,-1,2,2,2];wrapper.body=JSON.stringify(body);wrapper.sha256=str(wrapper.body).sha256_text();write_json(descriptor,wrapper)
	check(DirAccess.remove_absolute(path)==OK and not FileAccess.file_exists(path),"delete tested model GLB before every runtime consumer")
	report.source_sha=source_sha

func seed_editor_view()->Dictionary:
	var packed:PackedScene=native_preview.scene.get_meta("_compiled_resource_owner")
	var ids:=packed_state(packed);var candidate:=Assets.native_candidate(asset_path)
	# Fixture-only initial view construction through the baseline editor rebuild.
	# Evict immediately: actual playtest requests must use the private index.
	check(Assets.cache_packed(asset_path,packed,candidate.source_sha,candidate),"seed actual editor view with the already adopted template")
	editor._rebuild();Assets.evict_cached_scene(asset_path)
	check(editor._view.get_node(NodePath(asset_id)).get_meta("missing_asset",false)==false and not Assets._scenes.has(asset_path),"actual native editor view remains alive after global eviction")
	return ids

func run_session(label:String,via_ui:bool,expected:Dictionary={})->Dictionary:
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size();var map_sha:=FileAccess.get_sha256(map_path)
	var selection:Array=editor._selection_tools.ids.duplicate();var camera:Transform3D=editor._camera.transform
	var original_server:Node=Net.server();var inventory:Dictionary=original_server.inventory.capture_session_state()
	var producer_before:int=service.profile.producers;stage_ids.clear();Trace.start()
	if via_ui:
		root.gui_release_focus()
		var event:=InputEventKey.new();event.keycode=KEY_F5;event.physical_keycode=KEY_F5;event.pressed=true;Input.parse_input_event(event)
		event=InputEventKey.new();event.keycode=KEY_F5;event.physical_keycode=KEY_F5;event.pressed=false;Input.parse_input_event(event)
		await process_frame
		check(editor._playtest.active(),"actual F5 input starts the graphical playtest")
	else:await call_tool("start_playtest",{"position":[0,0,5]})
	if not await wait_phase("running"):return {}
	var traced:=Trace.stop();var reads:=0
	for row:Dictionary in traced.stats:
		if row.label=="compiled.native_read":reads+=int(row.count)
	var state:=await call_tool("playtest_state")
	check(Net.server()!=original_server and FileAccess.file_exists(state.temporary_path),label+": real private gameplay server and temporary map are running")
	check(stage_ids.prepared==stage_ids.play and stage_ids.play.class=="StreamedTexture2D",label+": probe and fresh play root share exact Packed/Mesh/Texture/RID")
	if not expected.is_empty():check(stage_ids.play==expected and service.profile.producers==producer_before and reads==0,label+": live editor/preview native template is reused without a producer/read")
	else:check(service.profile.producers==producer_before+1 and reads==1,label+": fully cold native prepares once for both builds")
	check(editor._playtest._asset_handles.is_empty() and editor._playtest._asset_templates.is_empty() and not Assets._scenes.has(asset_path),label+": play root owns publication with no handle or global-cache pin")
	var specs:Array=editor._playtest.world._map_root.get_meta("stream_library",[])
	var matching:Array=specs.filter(func(spec:Dictionary):return str(spec.get("uuid","")).begins_with(asset_id+"__"))
	check(matching.size()==1 and matching[0].mesh.get_instance_id()==int(stage_ids.play.mesh),label+": real streamed gameplay map contains the original native mesh")
	await call_tool("save_world",{},false)
	# Capture after readiness, hiding only player mesh rendering for the image.
	var player:Node=editor._playtest.world._player;var hidden:Array=[]
	for mesh:MeshInstance3D in player.find_children("*","MeshInstance3D",true,false):hidden.append([mesh,mesh.visible]);mesh.visible=false
	await RenderingServer.frame_post_draw
	capture_file(label+"_running",root.get_texture().get_image())
	for pair:Array in hidden:
		if is_instance_valid(pair[0]):pair[0].visible=pair[1]
	hidden.clear();specs=[];matching=[]
	var ids:Dictionary=stage_ids.play.duplicate();var temporary:String=state.temporary_path
	if via_ui:
		var buttons:Array=editor._playtest._overlay.find_children("*","Button",true,false).filter(func(button:Button):return button.text=="结束试玩，返回编辑器")
		check(buttons.size()==1,"actual playtest exit button is available")
		if buttons.size()==1:
			var position:Vector2=buttons[0].get_global_rect().get_center()
			var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.position=position;press.pressed=true;Input.parse_input_event(press)
			var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=position;release.pressed=false;Input.parse_input_event(release)
	else:await call_tool("stop_playtest")
	await wait_phase("idle")
	check(Net.server()==original_server and original_server.inventory.capture_session_state()==inventory,label+": stop restores source gameplay server and progress")
	check(editor._doc.recovery_snapshot()==before and editor._doc._undo.size()==history and editor._selection_tools.ids==selection and editor._camera.transform==camera,label+": source document/history/selection/camera unchanged")
	check(FileAccess.get_sha256(map_path)==map_sha and not FileAccess.file_exists(temporary) and not FileAccess.file_exists(asset_path),label+": formal map unchanged, private map removed, tested GLB still absent")
	check(editor.process_mode!=Node.PROCESS_MODE_DISABLED and not editor._playtest.active(),label+": existing editor resumes after stop")
	report[label]={"ids":ids,"native_reads":reads,"producer_delta":service.profile.producers-producer_before,"map_sha":map_sha,"service":service.snapshot()}
	return ids

func before_editor_free()->void:pass

func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root()
	if not folder.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(180).timeout.connect(func():printerr("PLAYTEST_NATIVE_GPU watchdog");quit(2))
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	Paint.refresh_sources();original=fixture();var prepared:=Products.prepare(original,folder)
	check(prepared.ok and prepared.stats.textures==1,"publish actual multi-mip native test texture")
	asset_path=publish_fixture(original,prepared,"playtest_cube");Products.restore(prepared);prepared.clear();fixture_source_deleted(asset_path)
	var document:=Doc.new();document.add_box("ground",Vector3(0,-.1,0),Vector3(20,.2,20))
	map_path=folder.path_join("maps/playtest/map.gltf");check(document.save(map_path)==OK,"save initial isolated authoring map")
	Net.session().world3d_editor_path=map_path;Net.session().world3d_editor_doc=document
	preload("res://tools/world3d_test_character.gd").ensure(self)
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=folder.path_join("drafts");root.add_child(editor)
	for _frame:int in 4:await process_frame
	editor._safety.enabled=false;editor._playtest.free();editor._playtest=SessionObserver.new();editor._playtest.editor=editor;editor._playtest.observe=observed;editor.add_child(editor._playtest)
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual editor serves HTTP MCP on loopback")
	var discovery:=await rpc("tools/list");var names:Array=discovery.result.tools.map(func(tool:Dictionary):return tool.name)
	check(["start_playtest","stop_playtest","playtest_state"].all(func(name_:String):return names.has(name_)),"HTTP discovers playtest tools")
	native_preview=Preview.new();native_preview.position=Vector2(850,100);native_preview.size=Vector2(384,288);editor.add_child(native_preview)
	service=Service.for_consumer(native_preview);tracker=Ownership.for_tree(self);ui_host=editor
	check(service.native_texture_pool==null and service.ownership_tracker==null and not service.native_texture_preparer.is_valid(),"actual service/renderer/ownership have no stubs")
	native_preview.show_asset(asset_path)
	var deadline:=Time.get_ticks_msec()+20000
	while native_preview.scene==null and Time.get_ticks_msec()<deadline:await process_frame
	check(native_preview.scene!=null,"actual native preview prepares the source privately")
	if native_preview.scene==null:finish();return
	asset_id=document.add_asset({"asset_path":asset_path,"collision":"none"},Vector3(0,1,0))
	var warm:=seed_editor_view()
	await call_tool("set_playtest_spawn",{"position":[0,0,5]})
	check(document.save(map_path)==OK,"save native record while its authoring GLB is absent")
	await run_session("private_live_ui",true,warm)
	native_preview.show_asset("")
	# Force the real editor teardown boundary while preserving authored data;
	# this makes the following public HTTP start genuinely resource-cold.
	editor._begin_rebuild()
	await expire_owners("before_cold")
	var cold:=await run_session("cold_http",false)
	check(not cold.is_empty() and cold.packed!=warm.packed and cold.texture!=warm.texture,"cold HTTP run uses new native allocation identities")
	await expire_owners("after_cold")
	await before_editor_free()
	if is_instance_valid(editor):editor.free()
	editor=null;Net.session().world3d_editor_doc=null;Net.session().world3d_editor_path=""
	original.free();original=null
	await process_frame
	report.scope="Playtest correctness and ownership; no whole-map performance claim. Target model GLB removed; approved actor GLB is a separate unchanged external dependency. Cold case uses actual editor view teardown to release the last owner while keeping document data."
	finish()
