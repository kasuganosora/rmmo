extends "res://tools/test_playtest_native_gpu.gd"
## Actual GLB kit importer, cold LoadJob, controls, F5/HTTP and MapLoader.
## No model, texture, preparation, ownership or renderer stubs.
const Kits=preload("res://scripts/world3d/auto_tile_kit.gd")
const MapLoader=preload("res://scripts/world3d/map_loader.gd")
var kit_paths:Array[String]=[]
var kit_data:Dictionary={}
var kit_ids:Array[String]=[]

func remember_scene(scene:Node3D)->Dictionary:
	var states:Dictionary={}
	for owner:PackedScene in scene.get_node(NodePath(asset_id)).mesh.get_meta("_compiled_resource_owners",[]):
		states[str(owner.get_instance_id())]=packed_state(owner)
	return states

func observed(stage:String,value:Variant)->void:
	var states:Dictionary={}
	if stage=="prepared":
		for path:String in kit_paths:
			var packed:PackedScene=value[path].packed
			states[str(packed.get_instance_id())]=packed_state(packed)
	else:states=remember_scene(value)
	stage_ids[stage]=states

func make_record(document:RefCounted,position:Vector3)->String:
	var uuid:String=document.add_box("native cliff",position,Vector3.ONE)
	var record:Dictionary=document.records[-1];record.collision="none"
	preload("res://scripts/world3d/auto_tile_rules.gd").configure(record,Vector2i(int(position.x),int(position.z)),"cliff",1.,position.y+.5,{"base_height":position.y-.5,"kit":kit_data.duplicate(true)})
	record.tile3d.drops=[1.,0.,0.,0.]
	check(preload("res://scripts/world3d/auto_tile_rules.gd").valid(record),"kit fixture uses a valid authored cliff height")
	return uuid

func import_native_kit()->bool:
	var source_folder:=folder.path_join("art_sources/kit")
	DirAccess.make_dir_recursive_absolute(source_folder)
	var sources:Array[String]=[]
	for label:String in ["top","edge"]:
		original.name="Kit_"+label
		var document:=GLTFDocument.new();var state:=GLTFState.new()
		var path:=source_folder.path_join(label+".glb");sources.append(path)
		check(document.append_from_scene(original,state)==OK and document.write_to_filesystem(state,path)==OK,"export actual textured kit source "+label)
	var manifest:=source_folder.path_join("kit.json")
	write_json(manifest,{"version":1,"family":"cliff","name":"native GPU cliff","pieces":{"top":"top.glb","edge":"edge.glb"}})
	var library:=Kits.new(folder.path_join("kit_library"))
	var imported:Dictionary=library.import_kit(manifest)
	check(imported.get("ok",false),"real kit importer compiles both actual GLBs")
	if not imported.get("ok",false):report.import_error=imported;return false
	var loaded:Dictionary=library.read(imported.kit_id)
	check(loaded.get("ok",false),"real imported kit manifest opens")
	if not loaded.get("ok",false):return false
	kit_data=loaded.kit
	for path:String in kit_data.pieces.values():
		kit_paths.append(path)
		check(Assets.native_candidate(path).has("texture_table"),"actual kit importer publishes split-native texture metadata")
	for path:String in sources+kit_paths:check(DirAccess.remove_absolute(path)==OK,"delete fixture GLB "+path.get_file())
	check(library.read(imported.kit_id).get("ok",false),"kit manifest remains usable after original and library GLBs are deleted")
	report.kit_import={"entry":imported,"paths":kit_paths,"source_glbs":sources}
	return true

func prefab_controls(document:RefCounted)->void:
	var records:Array=document.records.filter(func(record:Dictionary):return record.uuid in kit_ids)
	var path:=folder.path_join("assets/prefabs/native_kit.json")
	write_json(path,{"format":"rmmo_prefab","version":1,"records":records,"building_instances":{}})
	var entry:={"prefab_path":path,"thumbnail_path":folder.path_join("kit_thumbnail.png")}
	check(Prefabs.read(entry).get("ok",false),"real prefab reader accepts kit with no GLB")
	var preview:=Preview.new();preview.position=Vector2(840,100);preview.size=Vector2(384,288);editor.add_child(preview)
	var thumbnail:=Thumbnails.new();editor.add_child(thumbnail)
	var before:int=service.profile.producers;var cache_before:int=Assets._scenes.size()
	preview.show_prefab(entry);thumbnail.queue_import(entry)
	var deadline:=Time.get_ticks_msec()+30000
	while (preview.scene==null or preview._readiness.active() or not FileAccess.file_exists(entry.thumbnail_path)) and Time.get_ticks_msec()<deadline:await process_frame
	check(preview.scene!=null and preview.streaming_error.is_empty() and FileAccess.file_exists(entry.thumbnail_path),"actual kit prefab preview and persistent thumbnail finish texture readiness")
	if preview.scene!=null:
		var mesh:Mesh=preview.scene.get_node(NodePath(asset_id)).mesh
		var expected:int=1+records[0].tile3d.drops.filter(func(drop):return float(drop)>0).size()
		check(mesh.get_surface_count()==expected and mesh.get_meta("_compiled_resource_owners",[]).size()==2,"prefab renders actual top and exposed cliff pieces")
		capture_file("kit_prefab_preview",preview.viewport_.get_texture().get_image())
		mesh=null
	check(service.profile.producers==before and Assets._scenes.size()==cache_before,"preview and thumbnail borrow existing native owners without producers/cache growth")
	var png:=Image.load_from_file(entry.thumbnail_path) if FileAccess.file_exists(entry.thumbnail_path) else null
	check(png!=null and png.get_width()>0,"saved kit thumbnail is readable")
	if png!=null:capture_file("kit_persistent_thumbnail",png)
	preview.free();thumbnail.free()

func kit_session(via_ui:bool,expected:Dictionary={})->void:
	var label:="kit_f5" if via_ui else "kit_cold_http"
	var before:Dictionary=editor._doc.recovery_snapshot();var undo:int=editor._doc._undo.size();var map_sha:=FileAccess.get_sha256(map_path)
	var server:Node=Net.server();var producers:int=service.profile.producers;stage_ids.clear()
	if via_ui:
		root.gui_release_focus()
		var press:=InputEventKey.new();press.keycode=KEY_F5;press.physical_keycode=KEY_F5;press.pressed=true;Input.parse_input_event(press)
		var release:=InputEventKey.new();release.keycode=KEY_F5;release.physical_keycode=KEY_F5;Input.parse_input_event(release)
	else:await call_tool("start_playtest",{"position":[0,0,5]})
	if not await wait_phase("running"):return
	check(stage_ids.get("prepared",{})==stage_ids.get("play",{}) and stage_ids.get("play",{}).size()==2,label+": two fresh roots share both exact Packed/Mesh/Texture/RIDs")
	if expected.is_empty():check(service.profile.producers==producers+2,label+": truly cold native kit prepares each model once")
	else:check(stage_ids.play==expected and service.profile.producers==producers,label+": live editor native owners are reused")
	var by_id:Dictionary=editor._playtest.world._map_root.get_meta("stream_by_id",{})
	check(kit_ids.all(func(uuid:String):return by_id.has(uuid) and by_id[uuid].mesh.get_meta("_compiled_resource_owners",[]).size()==2),label+": actual runtime stream contains both authored kit records")
	by_id={}
	await call_tool("save_world",{},false)
	var player:Node=editor._playtest.world._player;var hidden:Array=[]
	for mesh:MeshInstance3D in player.find_children("*","MeshInstance3D",true,false):hidden.append([mesh,mesh.visible]);mesh.visible=false
	await RenderingServer.frame_post_draw;capture_file(label,root.get_texture().get_image())
	for pair:Array in hidden:
		if is_instance_valid(pair[0]):pair[0].visible=pair[1]
	hidden.clear()
	var temporary:String=editor._playtest.map_path
	if via_ui:
		var buttons:Array=editor._playtest._overlay.find_children("*","Button",true,false).filter(func(button:Button):return button.text=="结束试玩，返回编辑器")
		check(buttons.size()==1,"real kit playtest exit button exists")
		if buttons.size()==1:
			var position:Vector2=buttons[0].get_global_rect().get_center()
			var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.position=position;press.pressed=true;Input.parse_input_event(press)
			var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=position;Input.parse_input_event(release)
	else:await call_tool("stop_playtest")
	await wait_phase("idle")
	check(Net.server()==server and editor._doc.recovery_snapshot()==before and editor._doc._undo.size()==undo,label+": stop restores editor/server without author/history changes")
	check(FileAccess.get_sha256(map_path)==map_sha and not FileAccess.file_exists(temporary) and kit_paths.all(func(path:String):return not FileAccess.file_exists(path)),label+": formal bytes preserved, temporary map removed, no GLB fallback")
	report[label]={"states":stage_ids.duplicate(true),"producer_delta":service.profile.producers-producers}

func runtime_loader()->void:
	var loader:=MapLoader.new();root.add_child(loader);var received:Dictionary={}
	loader.finished.connect(func(scene:Node,_path:String,error:String):received.scene=scene;received.error=error)
	loader.start(map_path)
	var deadline:=Time.get_ticks_msec()+30000
	while not received.has("scene") and Time.get_ticks_msec()<deadline:await process_frame
	check(received.get("scene")!=null and received.get("error","").is_empty(),"actual GPU MapLoader.start loads saved kit without GLB")
	var scene:Node3D=received.get("scene")
	if scene!=null:
		var specs:Array=scene.get_meta("stream_library",[])
		check(specs.filter(func(spec:Dictionary):return spec.uuid in kit_ids).all(func(spec:Dictionary):return spec.mesh.get_meta("_compiled_resource_owners",[]).size()==2),"GPU runtime specs retain both kit source templates")
		remember_runtime_owners(specs)
		report.runtime_profile=scene.get_meta("load_profile")
		specs=[];scene.free()
	received.clear();await process_frame
	if is_instance_valid(loader):loader.cancel()

func remember_runtime_owners(specs:Array)->void:
	for spec:Dictionary in specs:
		if not kit_ids.has(spec.uuid):continue
		for owner:PackedScene in spec.mesh.get_meta("_compiled_resource_owners",[]):packed_state(owner)

func wait_edit()->void:
	var deadline:=Time.get_ticks_msec()+30000
	while (editor.saving() or editor._asset_operations.snapshot().pending>0) and Time.get_ticks_msec()<deadline:await process_frame
	check(not editor.saving() and editor._asset_operations.snapshot().pending==0,"native kit editing transaction finishes")

func neighbor_ready()->bool:
	var node:Node=editor._view.get_node_or_null(NodePath(kit_ids[1]))
	return node is MeshInstance3D and node.mesh!=null and not node.has_meta("tile_error") and node.mesh.get_meta("_compiled_resource_owners",[]).size()==2

func edit_neighbors()->void:
	var before:Array=editor._doc.records.duplicate(true)
	await call_tool("select_objects",{"ids":[kit_ids[0]]})
	await call_tool("delete_selection");await wait_edit()
	check(neighbor_ready(),"deleting native kit cell rebuilds its neighbor with READY templates")
	await call_tool("undo");await wait_edit()
	check(editor._doc.records==before and neighbor_ready(),"native kit deletion undo restores records and neighbor geometry")
	await call_tool("set_object_transform",{"id":kit_ids[0],"position":[8,1,0]});await wait_edit()
	check(neighbor_ready(),"manual native kit detach rebuilds its neighbor with READY templates")
	await call_tool("undo");await wait_edit()
	check(editor._doc.records==before and neighbor_ready(),"native kit transform undo restores records and neighbor geometry")
	await call_tool("select_objects",{"ids":[kit_ids[0]]})
	await call_tool("transform_selection",{"translation":[2,0,0]});await wait_edit()
	check(neighbor_ready(),"selection transform publishes prepared native neighbor")
	await call_tool("undo");await wait_edit()
	await call_tool("select_objects",{"ids":[kit_ids[0]]})
	editor._rotate_selected(1);await wait_edit()
	check(neighbor_ready(),"UI rotate prepares native neighbor")
	await call_tool("undo");await wait_edit()
	await call_tool("select_objects",{"ids":[kit_ids[0]]})
	var center:Vector3=editor._selection_tools.pivot()
	editor._city.apply_camera({"center":[center.x,center.y,center.z],"distance":35.,"pitch":-35.,"yaw":0.,"span":80.,"projection":"perspective"})
	for frame in 4:await process_frame
	var screen:Vector2=editor._camera.unproject_position(center)
	check(editor._transform_drag.begin(editor,screen,0),"actual native kit gizmo begins")
	editor._transform_drag.update(screen+Vector2(25,0),true)
	check(editor._doc.records!=before,"native gizmo previews a changed pose")
	editor._transform_drag.finish();await wait_edit()
	check(neighbor_ready() and editor._doc.records!=before,"gizmo commit publishes native neighbor with changed pose")
	await call_tool("undo");await wait_edit()
	check(editor._doc.records==before and neighbor_ready(),"gizmo undo restores native cells and geometry")
	await call_tool("select_objects",{"ids":[kit_ids[0]]})
	var undo_count:int=editor._doc._undo.size()
	check(editor._transform_drag.begin(editor,screen,0),"cancelable native kit gizmo begins")
	editor._transform_drag.update(screen+Vector2(25,0),true);editor._transform_drag.finish(true)
	check(editor._doc.records==before and editor._doc._undo.size()==undo_count and neighbor_ready(),"cancelled native gizmo preserves document history and geometry")
	var index_path:String=preload("res://scripts/world3d/compiled_asset_cache.gd").index_path(kit_paths[0],folder)
	var withheld:=index_path+".withheld"
	check(DirAccess.rename_absolute(index_path,withheld)==OK,"withhold one fixture native registration")
	await call_tool("set_object_transform",{"id":kit_ids[0],"position":[8,1,0]},false);await wait_edit()
	check(editor._doc.records==before and editor._doc._undo.size()==undo_count and neighbor_ready(),"failed native preparation leaves document history and displayed neighbor intact")
	check(DirAccess.rename_absolute(withheld,index_path)==OK,"restore fixture native registration")

func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root()
	if not folder.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(180).timeout.connect(func():printerr("NATIVE_KIT_CONSUMERS_GPU watchdog");quit(2))
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;Paint.refresh_sources();original=fixture()
	if not import_native_kit():original.free();finish();return
	var document:=Doc.new();document.add_box("ground",Vector3(0,-.1,0),Vector3(20,.2,20))
	asset_id=make_record(document,Vector3(0,1,0));kit_ids.append(asset_id);kit_ids.append(make_record(document,Vector3(1,1,0)))
	preload("res://scripts/world3d/auto_tile_rules.gd").refresh_all(document.records)
	map_path=folder.path_join("maps/native_kit/map.gltf");check(document.save(map_path)==OK,"save native kit map without any tested GLB")
	Net.session().world3d_editor_path=map_path;Net.session().world3d_editor_doc=null
	preload("res://tools/world3d_test_character.gd").ensure(self)
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=folder.path_join("drafts");root.add_child(editor)
	var deadline:=Time.get_ticks_msec()+30000
	while editor._load_job.active and Time.get_ticks_msec()<deadline:await process_frame
	check(editor._load_job.result.get("ok",false),"actual editor LoadJob cold reopens saved native-only kit map")
	if not editor._load_job.result.get("ok",false):report.load_error=editor._load_job.result;editor.free();original.free();finish();return
	editor._safety.enabled=false;service=Service.for_consumer(editor);tracker=Ownership.for_tree(self);ui_host=editor
	check(service.native_texture_pool==null and service.ownership_tracker==null,"GPU consumers use real native ownership and streaming")
	report.load_profile=editor._load_job.result.timings
	check(editor._load_job.result.timings.asset_lookahead.consumed==2,"repeated kit records consume two unique native products")
	var warm:=remember_scene(editor._view)
	check(warm.size()==2 and warm.values().all(func(state:Dictionary):return state.class=="StreamedTexture2D"),"real editor tiles retain two complete streamed native templates")
	await prefab_controls(editor._doc)
	# LoadJob intentionally retains its existing global publication policy.
	# Evict those explicit cache owners; the editor view keeps both templates.
	for path:String in kit_paths:Assets.evict_cached_scene(path)
	editor._playtest.free();editor._playtest=SessionObserver.new();editor._playtest.editor=editor;editor._playtest.observe=observed;editor.add_child(editor._playtest)
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual kit editor starts HTTP MCP")
	if OS.get_cmdline_user_args().has("--edit-neighbors"):
		await edit_neighbors()
		warm=remember_scene(editor._view)
	await call_tool("set_playtest_spawn",{"position":[0,0,5]})
	await kit_session(true,warm)
	editor._begin_rebuild();await expire_owners("before_cold_kit")
	await kit_session(false);await expire_owners("after_cold_kit")
	await runtime_loader();await expire_owners("after_runtime_loader")
	editor.free();editor=null;Net.session().world3d_editor_doc=null;Net.session().world3d_editor_path="";original.free();original=null
	report.scope="Real GLB kit import with isolated default-split candidate, deleted original/copied GLBs, cold editor open, prefab consumers, F5/HTTP and runtime load. LoadJob global cache owners explicitly evicted per unchanged policy. UI brush authoring/pack relocation validated separately."
	finish()
