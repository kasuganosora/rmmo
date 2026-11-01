extends "res://tools/test_world3d_mcp.gd"
const AddressTools = preload("res://scripts/world_editor/world_address_tools.gd")
const LayoutTools = preload("res://scripts/world_editor/world_layout_tools.gd")
const LayoutStore = preload("res://scripts/world_editor/world_layout_store.gd")
var fixture_root := ""

func write_json(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"",true,true)); file.close()

func terrain(doc: RefCounted, width: int, depth: int) -> void:
	var id: String = doc.add_box_silent("ground",Vector3(width*.5,0,depth*.5),Vector3(width,1,depth))
	var record: Dictionary = doc._find(id)
	var heights := []; heights.resize((width+1)*(depth+1)); heights.fill(0.0)
	var holes := []; holes.resize(width*depth); holes.fill(false)
	record.terrain_mesh = {"version":1,"columns":width,"rows":depth,"floor":-16,"heights":heights,"holes":holes}

func field(dialog: Window, name_: String, value: String) -> void:
	var control := dialog.find_child("WorldLayout"+name_,true,false) as LineEdit
	check(control!=null,"UI field "+name_+" exists")
	if control!=null: control.text=value; control.text_changed.emit(value)

func option(dialog: Window, name_: String, value: String) -> void:
	var control := dialog.find_child("WorldLayout"+name_,true,false) as OptionButton
	for i in control.item_count:
		if control.get_item_metadata(i)==value:
			control.select(i); control.item_selected.emit(i); return
	check(false,"UI option "+name_+" includes "+value)

func press(dialog: Window, name_: String) -> void:
	var control := dialog.find_child("WorldLayout"+name_,true,false) as Button
	check(control!=null and not control.disabled,"UI "+name_+" enabled")
	if control==null or control.disabled: print("UI_ACTION_FAILURE ",name_," status=",dialog.find_child("WorldLayoutStatus",true,false).text," candidate=",dialog._candidate)
	if control!=null and not control.disabled: control.pressed.emit()

func placement(dialog: Window, id: String, number: String, ox: String, width: String) -> void:
	for pair in [["PlacementIdInput",id],["PlacementPackIdInput","wl_http"],["PlacementMapNumberInput",number],["PlacementPackVersionInput","1"],["OriginXInput",ox],["OriginYInput","0"],["OriginZInput","-10"],["MinXInput","0"],["MinZInput","0"],["MaxXInput",width],["MaxZInput","10"]]: field(dialog,pair[0],pair[1])
	press(dialog,"UpsertPlacementButton")

func history_args(document: Dictionary) -> Dictionary:
	return {"document_id":document.document_id,"expected_edit_revision":document.edit_revision}

func capture(dialog: Window, filename: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot:=Paths.external_root().path_join("review_artifacts/world_layout_d2_20261101/"+filename+".png")
	check(dialog.get_texture().get_image().save_png(screenshot)==OK,"actual UI capture "+filename+" saved externally")

func run() -> void:
	Engine.max_fps=60; root.size=Vector2i(1600,1000); rpc_timeout_ms=15000
	fixture_root=Paths.external_root().path_join("cache/world_layout_http_%d"%Time.get_ticks_usec())
	var pack_root:=fixture_root.path_join("packs/wl_http")
	write_json(pack_root.path_join("metadata.json"),{"id":"wl_http","name":"世界布局验证包","version":"1"})
	var path_a:=pack_root.path_join("maps/Map1.gltf")
	var path_b:=pack_root.path_join("maps/Map2.gltf")
	var first:=Doc.new(); first.map_meta.map_ref="wl_http/a"; terrain(first,10,10)
	var second:=Doc.new(); second.map_meta.map_ref="wl_http/b"; terrain(second,20,10)
	check(first.save(path_a)==OK and second.save(path_b)==OK,"native terrain fixtures saved externally")
	var source_sha:=[FileAccess.get_sha256(path_a),FileAccess.get_sha256(path_b)]
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=first; session.world3d_editor_path=path_a
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=fixture_root.path_join("drafts")
	editor._world_address_tools=AddressTools.new(editor,fixture_root)
	root.add_child(editor); editor._safety.enabled=false
	await settle()
	var probe:=TCPServer.new(); port=29030
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"isolated 3D HTTP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(LayoutTools.tool_specs().all(func(spec):return definitions.any(func(row):return row.name==spec.name)),"all D2 tools discoverable")
	var listing:=await call_tool("list_world_maps")
	var catalog_doc:Dictionary=listing.documents[0]
	for row:Dictionary in listing.maps:
		var registered:=await call_tool("register_world_map",{"entry_id":row.entry_id,"map_number":row.suggested_number,"expected_edit_revision":catalog_doc.edit_revision})
		catalog_doc=registered.document
	await call_tool("save_world_catalog",history_args(catalog_doc).merged({"expected_disk_sha":catalog_doc.disk_sha}))
	var catalog_sha:=FileAccess.get_sha256(catalog_doc.path)
	var map_history:int=editor._doc._undo.size(); var records:Array=editor._doc.records.duplicate(true)
	var empty:=await call_tool("list_worlds")
	check(empty.worlds.is_empty() and not DirAccess.dir_exists_absolute(pack_root.path_join("worlds")),"listing creates no world directories")
	for menu:Node in editor.find_children("*","MenuButton",true,false):
		if menu.text=="文件":menu.get_popup().id_pressed.emit(9);break
	await settle()
	var dialog:=editor.get_node_or_null("WorldLayoutDialog") as Window
	check(dialog!=null and dialog.visible,"File menu opens actual layout UI")
	if dialog==null:quit(1);return
	field(dialog,"WorldKeyInput","mixed_sizes"); press(dialog,"NewButton")
	placement(dialog,"city","1","-10","10")
	placement(dialog,"field","2","0","20")
	field(dialog,"SeamIdInput","city_field")
	option(dialog,"SeamAPlacementPicker","city");option(dialog,"SeamBPlacementPicker","field")
	option(dialog,"SeamAEdgePicker","x_max");option(dialog,"SeamBEdgePicker","x_min")
	for name_ in ["SeamAStartInput","SeamBStartInput"]:field(dialog,name_,"0")
	for name_ in ["SeamAEndInput","SeamBEndInput"]:field(dialog,name_,"10")
	press(dialog,"UpsertSeamButton");press(dialog,"PreviewButton")
	var before_apply:=await call_tool("editor_state")
	check(not before_apply.world_layouts.dirty and not DirAccess.dir_exists_absolute(pack_root.path_join("worlds")),"UI preview writes no author file or history")
	await call_tool("close_editor",{"action":"discard"},false)
	press(dialog,"ApplyButton")
	listing=await call_tool("list_worlds")
	check(listing.documents.size()==1 and listing.documents[0].dirty,"UI apply is visible to HTTP as separate unsaved document")
	if listing.documents.is_empty():quit(1);return
	var document:Dictionary=listing.documents[0]
	var current:=await call_tool("get_world_layout",{"document_id":document.document_id})
	check(current.layout.spaces[0].placements.size()==2 and current.bindings.size()==2,"different size map placements have pinned source bindings")
	check(not FileAccess.file_exists(document.path),"apply does not silently save")
	var address:=await call_tool("resolve_world_address",{"document_id":document.document_id,"address":"wl_http:1:9,0,5"})
	check(address.space_position_m[0]==-1.0 and address.space_position_m[1]==0.0 and address.space_position_m[2]==-5.0 and not address.can_transfer,"world address converts by explicit origin without transfer")
	await call_tool("select_objects",{"ids":[editor._doc.records[0].uuid]})
	var current_address:=await call_tool("get_current_world_address",{"document_id":document.document_id,"anchor_kind":"object_origin"})
	check(current_address.world_position_available and current_address.space_position_m[0]==-5.0 and current_address.anchor_kind=="object_origin","current object address preserves anchor while applying layout origin")
	await call_tool("resolve_world_address",{"document_id":document.document_id,"address":"wl_http:1:1,0,1","pack_root":pack_root},false)
	var owner:=await call_tool("locate_world_position",{"document_id":document.document_id,"space_id":"main","space_position_m":[0,0,-5]})
	check(owner.map_number=="2" and owner.local_position_m[0]==0.0 and owner.local_position_m[1]==0.0 and owner.local_position_m[2]==5.0,"exact seam uses half-open neighboring ownership")
	await call_tool("locate_world_position",{"document_id":document.document_id,"space_id":"main","space_position_m":[20,0,-5]},false)
	await call_tool("resolve_world_address",{"address":"wl_http:1:1,0,1","space_id":"main"},false)
	var report:=await call_tool("validate_world_seams",{"document_id":document.document_id})
	check(report.heightfields_match and not report.continuous_ready and report.inputs.size()==2,"saved native edges match without granting runtime readiness")
	var bad:Dictionary=current.layout.duplicate(true);bad.spaces[0].placements[1].origin_m[0]=-1
	await call_tool("preview_world_layout",{"mode":"update","document_id":document.document_id,"layout":bad,"expected_edit_revision":document.edit_revision},false)
	var still:=await call_tool("get_world_layout",{"document_id":document.document_id})
	check(still.document.edit_revision==document.edit_revision and still.layout==current.layout,"overlap preview leaves authoring unchanged")
	await call_tool("apply_world_layout",{"candidate_id":"unknown","expected_edit_revision":document.edit_revision},false)
	press(dialog,"SaveButton")
	current=await call_tool("get_world_layout",{"document_id":document.document_id});document=current.document
	check(FileAccess.file_exists(document.path) and not document.dirty,"UI saves world config separately")
	var saved_sha:=FileAccess.get_sha256(document.path)
	var reopened:=LayoutStore.new(editor._world_address_tools.catalog)
	check(reopened.list_worlds().worlds.size()==1 and equivalent(reopened.get_layout(document.document_id).layout,current.layout),"fresh service reopens saved world")
	var next:Dictionary=current.layout.duplicate(true);next.spaces[0].placements[1].ownership_xz_m[2]=25
	var candidate:=await call_tool("preview_world_layout",{"mode":"update","document_id":document.document_id,"layout":next,"expected_edit_revision":document.edit_revision})
	await call_tool("apply_world_layout",{"candidate_id":candidate.candidate_id,"expected_edit_revision":document.edit_revision+1},false)
	var applied:=await call_tool("apply_world_layout",{"candidate_id":candidate.candidate_id,"expected_edit_revision":document.edit_revision})
	var undone:=await call_tool("undo_world_edit",history_args(applied.document))
	check(undone.layout==current.layout,"world undo does not use map history")
	var redone:=await call_tool("redo_world_edit",history_args(undone.document))
	check(equivalent(redone.layout,next),"world redo restores same entire layout")
	await call_tool("save_world_layout",history_args(redone.document).merged({"expected_disk_sha":"invalid"}),false)
	check(FileAccess.get_sha256(document.path)==saved_sha,"invalid save leaves disk bytes unchanged")
	await call_tool("discard_world_layout",history_args(redone.document))
	# A new map revision invalidates candidates and height reports, never auto-adopts it.
	current=await call_tool("get_world_layout",{"document_id":document.document_id})
	candidate=await call_tool("preview_world_layout",{"mode":"update","document_id":document.document_id,"layout":next,"expected_edit_revision":current.document.edit_revision})
	var bytes:=FileAccess.get_file_as_bytes(path_b)
	var changed:=FileAccess.open(path_b,FileAccess.WRITE);changed.store_buffer(bytes);changed.store_string("\n");changed.close()
	await call_tool("apply_world_layout",{"candidate_id":candidate.candidate_id,"expected_edit_revision":current.document.edit_revision},false)
	await call_tool("validate_world_seams",{"document_id":document.document_id},false)
	var stale_address:=await call_tool("get_current_world_address",{"document_id":document.document_id,"anchor_kind":"object_origin"},false)
	check(stale_address.reason_code=="layout_inputs_changed","current-address diagnostic reports source revision conflict")
	changed=FileAccess.open(path_b,FileAccess.WRITE);changed.store_buffer(bytes);changed.close()
	current=await call_tool("get_world_layout",{"document_id":document.document_id})
	await call_tool("discard_world_layout",history_args(current.document))
	check(editor._doc.records==records and editor._doc._undo.size()==map_history,"layout edits preserve current scene and map undo history")
	check(FileAccess.get_sha256(path_a)==source_sha[0] and FileAccess.get_sha256(path_b)==source_sha[1] and FileAccess.get_sha256(catalog_doc.path)==catalog_sha,"map and catalogue paths and bytes remain unchanged")
	# Reload actual window after HTTP history and exercise address/diagnostic UI.
	dialog.refresh();option(dialog,"WorldPicker",document.document_id);press(dialog,"LoadButton")
	press(dialog,"ValidateSeamsButton")
	field(dialog,"AddressInput","wl_http:1:9,0,5");press(dialog,"ResolveAddressButton")
	for pair in [["SpaceXInput","0"],["SpaceYInput","0"],["SpaceZInput","-5"]]:field(dialog,pair[0],pair[1])
	press(dialog,"LocatePositionButton")
	check(dialog.find_child("WorldLayoutAddressResult",true,false).text.contains("wl_http:2:0,0,5"),"UI inverse lookup matches HTTP boundary owner")
	check(not dialog.has_local_changes(),"read-only UI checks leave no draft")
	if DisplayServer.get_name()!="headless":
		await capture(dialog,"ui")
		var scrolling:ScrollContainer=dialog.find_children("*","ScrollContainer",true,false)[0]
		scrolling.scroll_vertical=100000
		await capture(dialog,"ui_addresses")
		scrolling.scroll_vertical=0
		var tabs:TabContainer=dialog.find_child("WorldLayoutFormTabs",true,false)
		tabs.current_tab=1
		var seam_tree:Tree=dialog.find_child("WorldLayoutSeamTree",true,false)
		seam_tree.get_root().get_first_child().select(0);seam_tree.item_selected.emit()
		await capture(dialog,"ui_seam")
		tabs.current_tab=0
	# Invalid UI draft must display the same overlap diagnosis as HTTP, without application.
	var place_tree:Tree=dialog.find_child("WorldLayoutPlacementTree",true,false)
	for item:TreeItem in place_tree.get_root().get_children():
		if item.get_metadata(0).id=="field":item.select(0);place_tree.item_selected.emit();break
	field(dialog,"OriginXInput","-1");press(dialog,"UpsertPlacementButton");press(dialog,"PreviewButton")
	var issues:Tree=dialog.find_child("WorldLayoutDiagnostics",true,false)
	var overlap:TreeItem=issues.get_root().get_first_child()
	check(overlap!=null and overlap.get_metadata(0).code=="ownership_overlap" and dialog.find_child("WorldLayoutApplyButton",true,false).disabled,"UI overlap diagnosis blocks application")
	if overlap!=null:overlap.select(0);issues.item_selected.emit()
	if DisplayServer.get_name()!="headless":await capture(dialog,"ui_diagnostic")
	field(dialog,"OriginXInput","123")
	check(editor._world_layout_tools.has_unsaved_work(),"unapplied form text participates in exit protection")
	dialog.request_close()
	check(dialog.get_node("WorldLayoutCloseConfirmation").visible,"closing pending form prompts instead of discarding")
	dialog.get_node("WorldLayoutCloseConfirmation").custom_action.emit("keep")
	editor._safety.request_exit(false)
	check(dialog.visible and dialog.has_local_changes(),"editor exit reopens retained local draft")
	check(FileAccess.get_sha256(document.path)==saved_sha,"close protection never autosaves local form")
	editor._mcp.stop();dialog.hide();editor.queue_free();await settle()
	session.world3d_editor_doc=null;session.world3d_editor_path=""
	print("WORLD_LAYOUT_HTTP_FIXTURE ",fixture_root)
	print("test_world_layout_editor_http: ","PASS" if failed==0 else "FAIL (%d)"%failed)
	quit(0 if failed==0 else 1)
