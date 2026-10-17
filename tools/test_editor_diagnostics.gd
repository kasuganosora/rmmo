extends "res://tools/test_world3d_mcp.gd"
const Diagnostics=preload("res://scripts/world_editor/editor_diagnostics.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
var count:=0
var output:="D:/code/rmmo_runtime/review_artifacts/editor_diagnostics_20261017"
func check(ok_:bool,label_:String)->void:count+=1;super.check(ok_,label_)
func snapshot()->String:return City.token([editor._doc.recovery_snapshot(),editor._doc._undo,editor._doc._redo,editor._dirty,editor._selection_tools.ids])
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=90000;root.size=Vector2i(1600,1000)
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var path:=Paths.cache_directory("diagnostics_%d"%Time.get_ticks_usec()).path_join("map.gltf")
	check(Doc.new().save(path)==OK,"native disposable map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=path.get_base_dir().path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32910
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"independent loopback server")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(t):return t.name=="focus_editor_diagnostic") and definitions.any(func(t):return t.name=="clear_editor_diagnostic") and not definitions.any(func(t):return t.name=="paint_tile"),"current 3D diagnostic tools discovered")
	var terrain:=await call_tool("create_terrain",{"center":[0.,0.,0.],"width":24.,"depth":24.,"cell_size":1.})
	var args:Dictionary={"id":terrain.id,"start":[-5.,0.,0.],"end":[5.,4.,0.],"width":3.,"blend_margin":2.,"cross_tiles":true}
	var before:=snapshot();var result:=await call_tool("preview_terrain_ramp",args,false)
	check(result.diagnostic.category=="conflict" and result.diagnostic.items[0].values.limits.absolute_grade_max==.15,"real grade rejection includes measured value and actual limit")
	check(snapshot()==before,"failed diagnostic preparation leaves author history selection and dirty unchanged")
	var panel=editor._terrain_panel.ramp;editor._terrain_panel.refresh(terrain.id);var fields:=args.duplicate();fields.erase("id");panel.fields.update_values(fields)
	var ui:Dictionary=panel.execute(false)
	check(equivalent(ui.diagnostic,result.diagnostic) and ui.diagnostic_token==result.diagnostic_token,"actual ramp UI and HTTP share identical structured diagnosis")
	var focused:=await call_tool("focus_editor_diagnostic",{"diagnostic_token":result.diagnostic_token,"index":0})
	check(is_instance_valid(editor._diagnostics.overlay) and editor._orbit_center.distance_to(Vector3(5,4,0))<.001,"HTTP focuses actual failure witness and renders transient highlight")
	check(snapshot()==before,"focus does not select or mutate authoring")
	await call_tool("clear_editor_diagnostic");check(not is_instance_valid(editor._diagnostics.overlay),"clear releases derived highlight")
	panel.diagnostics.locate.pressed.emit();check(is_instance_valid(editor._diagnostics.overlay),"real UI locate button shares highlight operation")
	await call_tool("focus_editor_diagnostic",{"diagnostic_token":result.diagnostic_token,"index":31},false)
	await call_tool("set_object_properties",{"ids":[terrain.id],"name":"changed after diagnosis"});await settle()
	var edited:=snapshot();await call_tool("focus_editor_diagnostic",{"diagnostic_token":result.diagnostic_token},false)
	check(snapshot()==edited and not is_instance_valid(editor._diagnostics.overlay),"map revision invalidates highlight and old focus without overriding later edit")
	await call_tool("undo")
	var stamp:Dictionary={"id":terrain.id,"mode":"flatten","shape":"rectangle","points":[[0.,0.]],"plot_width":8.,"plot_depth":8.,"target_height":0.,"strength":1.,"blend_margin":2.}
	await call_tool("set_object_properties",{"ids":[terrain.id],"locked":true})
	before=snapshot();var joint:=await call_tool("preview_terrain_layout",{"strokes":[stamp]},false)
	check(joint.diagnostic.items[0].object_ids==[terrain.id],"joint terrain failure identifies protected terrain")
	var joint_panel=editor._terrain_panel.terrain_layout;joint_panel.strokes=[stamp];joint_panel._execute(false)
	check(equivalent(joint_panel.diagnostics.info,joint.diagnostic),"joint layout UI shares object diagnosis")
	await call_tool("focus_editor_diagnostic",{"diagnostic_token":joint.diagnostic_token})
	check(snapshot()==before,"object-bound focus preserves locked state and history")
	await call_tool("undo")
	var house:Dictionary={"asset_id":"missing_prefab","position":[0.,0.,0.],"road_edge_id":"missing_road"}
	for name_:String in ["preview_residential_placement","preview_residential_site"]:
		var request_:Dictionary=house if name_.ends_with("placement") else {"residential":house,"terrain":{"strokes":[stamp]}}
		before=snapshot();var rejected:=await call_tool(name_,request_,false)
		check(rejected.has("diagnostic_token") and rejected.diagnostic.operation==name_ and snapshot()==before,"residential and combined failures share read-only diagnostic envelope: "+name_)
		var residence=editor._building_panel.residential;residence.site_enabled.button_pressed=name_.ends_with("site");residence.report(rejected)
		check(equivalent(residence.diagnostics.info,rejected.diagnostic),"real residential panel shows HTTP diagnostic: "+name_)
	var nested:=Diagnostics.normalize({"ok":false,"code":"search_exhausted","error":"search","last_failure":{"code":"unsupported","error":"unknown geometry","lower_witness":{"terrain_id":terrain.id,"position":[1.,2.,3.],"terrain_height":2.},"upper_witness":{"terrain_id":terrain.id,"position":[3.,4.,5.],"floor_bottom":4.}}},"test")
	check(nested.category=="search_exhausted" and nested.items[1].category=="unsupported" and nested.items.size()==4,"bounded normalization preserves search outcome, unsupported cause and both witnesses")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(editor._doc.validate_save()==OK,"diagnostic UI does not alter saved document contract")
	var old_diagnosis:=await call_tool("preview_terrain_ramp",args,false)
	await call_tool("open_world",{"path":path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var stale:=await call_tool("focus_editor_diagnostic",{"diagnostic_token":old_diagnosis.diagnostic_token},false)
	check(stale.code=="diagnostic_stale","freshly reopened zero-revision document cannot reuse another document diagnosis")
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":count,"failures":failed,"ramp_failure":result,"nested":nested,"map":path,"map_sha256":FileAccess.get_sha256(path)},"\t"))
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("EDITOR_DIAGNOSTICS checks=",count," failures=",failed);quit(1 if failed else 0)
