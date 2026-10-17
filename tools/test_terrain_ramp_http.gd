extends "res://tools/test_world3d_mcp.gd"
const Ramp=preload("res://scripts/world_editor/terrain_ramp_tools.gd")
const T=preload("res://scripts/world3d/terrain_surface.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
var OUT="D:/code/rmmo_runtime/review_artifacts/terrain_ramp_20261017"
var evidence:Array=[]
func snapshot()->Dictionary:
	var value:Dictionary=editor._doc.recovery_snapshot()
	for key:String in ["next","disk_signature","disk_path","dirty"]:value.erase(key)
	return value
func rejected(tool:String,args:Dictionary,label:String)->Dictionary:
	var before:=City.token(snapshot());var history:int=editor._doc._undo.size();var dirty:bool=editor._dirty;var selection:String=City.token(editor._inspector.selection)
	var result:=await call_tool(tool,args,false)
	check(before==City.token(snapshot()) and history==editor._doc._undo.size() and dirty==editor._dirty and selection==City.token(editor._inspector.selection),label+" is atomic including dirty/history/selection")
	evidence.append({"case":label,"result":result});return result
func run()->void:
	create_timer(360).timeout.connect(func():print("TERRAIN_RAMP_HTTP_TIMEOUT");quit(2));rpc_timeout_ms=90000;root.size=Vector2i(1600,1000)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):OUT=argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(OUT)
	var directory:=Paths.cache_directory("terrain_ramp_http_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");check(Doc.new().save(path)==OK,"isolated native map created")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32810
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"private editor exposes true loopback HTTP")
	var definitions:Array=(await rpc("tools/list")).result.tools
	for name_:String in ["sample_terrain_height","preview_terrain_ramp","apply_terrain_ramp"]:check(definitions.any(func(t):return t.name==name_),name_+" discovered in current 3D MCP")
	check(not definitions.any(func(t):return t.name=="paint_tile"),"retired 2D tools remain unregistered")
	var left:=await call_tool("create_terrain",{"center":[-8.,0.,0.],"width":16.,"depth":24.,"cell_size":1.})
	var right:=await call_tool("create_terrain",{"center":[8.,0.,0.],"width":16.,"depth":24.,"cell_size":2.})
	# Same-resolution neighbor in the left tile's spatial bin provides an actual
	# eligible merge pair; the two ramp tiles alone intentionally have different grids.
	await call_tool("create_terrain",{"center":[-24.,0.,0.],"width":16.,"depth":24.,"cell_size":1.})
	var args:={"id":left.id,"start":[-6.3,0.,-.3],"end":[6.3,1.2,1.1],"width":3.,"blend_margin":2.,"cross_tiles":true}
	await rejected("sample_terrain_height",{"id":"absent","point":[0.,0.]},"unknown terrain id")
	await rejected("sample_terrain_height",{"id":left.id,"point":[100.,100.]},"out-of-map sample")
	await rejected("apply_terrain_ramp",args.merged({"start":args.end},true),"zero length")
	await rejected("apply_terrain_ramp",args.merged({"end":[6.3,4.,1.1]},true),"excessive grade")
	await rejected("apply_terrain_ramp",args.merged({"width":0.},true),"invalid width schema")
	await rejected("apply_terrain_ramp",args.merged({"cross_tiles":false},true),"cross-tile opt out")
	for property:String in ["locked","hidden"]:
		await call_tool("set_object_properties",{"ids":[right.id],property:true})
		await rejected("apply_terrain_ramp",args,"protected adjacent terrain "+property);await call_tool("undo")
	await call_tool("set_floor_view",{"isolation":true,"base_height":30.})
	await rejected("apply_terrain_ramp",args,"floor isolation");await call_tool("undo")
	# Adversarial source fixtures remain entirely in this disposable document.
	var record:Dictionary=editor._doc._find(right.id)
	record.surface_paint=[];await rejected("apply_terrain_ramp",args,"manual surface override");record.erase("surface_paint")
	record.terrain_mesh.holes[6*int(record.terrain_mesh.columns)]=true
	await rejected("apply_terrain_ramp",args,"hole between endpoints across full corridor")
	await rejected("sample_terrain_height",{"id":left.id,"point":[1.,1.]},"sample hole")
	record.terrain_mesh.holes[6*int(record.terrain_mesh.columns)]=false
	var duplicate:=record.duplicate(true);duplicate.uuid="overlap";duplicate.position[1]=3.;editor._doc.records.append(duplicate)
	await rejected("apply_terrain_ramp",args,"stacked heightfield");editor._doc.records.pop_back()
	record.collision="none";await rejected("apply_terrain_ramp",args,"missing physical terrain support");record.collision="walk"
	var obstacle:={"uuid":"protected_prop","kind":"box","position":[3.,.8,.5],"rotation":[0.,0.,0.],"size":[1.,1.6,1.],"color":[.4,.4,.4],"collision":"solid"}
	editor._doc.records.append(obstacle);await rejected("apply_terrain_ramp",args,"existing prop intrusion");editor._doc.records.pop_back()
	var city:=await call_tool("get_city_layout")
	await call_tool("update_planning_zones",{"expected_token":city.zone_token,"zones":[{"id":"protected_zone","purpose":"no_build","polygon":[[2.,-1.],[4.,-1.],[4.,2.],[2.,2.]],"min_y":-1.,"max_y":3.}]})
	await rejected("apply_terrain_ramp",args,"planning zone");await call_tool("undo")
	city=await call_tool("get_city_layout")
	await call_tool("update_road_graph",{"expected_token":city.road_token,"nodes":[{"id":"west","position":[-5.,0.,.4]},{"id":"east","position":[5.,0.,.4]}],"edges":[{"id":"road","from":"west","to":"east","kind":"ground","width_start":1.6,"width_end":1.6}]})
	await call_tool("generate_road_surface",{"follow_terrain":true,"kerb_enabled":false})
	var road_id:String=editor._doc.records.filter(func(r):return r.has("road_mesh"))[0].uuid
	await call_tool("set_object_properties",{"ids":[road_id],"locked":true});await rejected("apply_terrain_ramp",args,"locked following road");await call_tool("undo")
	editor._terrain_panel.refresh(left.id)
	var panel=editor._terrain_panel.ramp;var values:=args.duplicate(true);values.erase("id");panel.fields.update_values(values)
	check(equivalent(panel.request(),args),"real UI form emits same endpoint parameters")
	var sampled:=await call_tool("sample_terrain_height",{"id":left.id,"point":[-6.3,-.3]})
	check(equivalent(panel.sample_endpoint("start"),sampled),"real UI height sampling equals HTTP")
	editor._dock_tabs.current_tab=10;editor._terrain_panel.tasks.current_tab=2;await settle()
	var before:=snapshot();var history:int=editor._doc._undo.size();var dirty:bool=editor._dirty
	panel.preview_button.pressed.emit()
	var preview:=await call_tool("preview_terrain_ramp",args)
	check(equivalent(panel.preview_result,preview),"actual UI preview callback equals true HTTP preview")
	check(City.token(before)==City.token(snapshot()) and history==editor._doc._undo.size() and dirty==editor._dirty,"both previews are read-only")
	if not preview.get("ok",false):print("PREVIEW FAILURE ",preview);quit(1);return
	check(preview.max_height_error<=.0002 and preview.max_seam_step<=.0002 and preview.max_grade<=.15001,"full-width diagonal ramp satisfies endpoints and mixed-resolution seams")
	check(is_instance_valid(panel.overlay) and panel.overlay.is_visible_in_tree(),"checked ramp outline is an actual visible editor overlay")
	# Capture only the editor UI; no avatar renderer or portrait exists here.
	editor._camera.position=Vector3(14.,13.,19.);editor._camera.look_at(Vector3(0.,.5,0.))
	await settle();await RenderingServer.frame_post_draw
	var screenshot:=root.get_texture().get_image();check(screenshot.save_webp(OUT+"/ramp_ui.webp",true,.9)==OK,"UI capture encoded as lossy WebP quality 90")
	FileAccess.open(OUT+"/ramp_ui_compression.json",FileAccess.WRITE).store_string(JSON.stringify({"path":OUT+"/ramp_ui.webp","sha256":FileAccess.get_sha256(OUT+"/ramp_ui.webp"),"format":"WebP","lossy":true,"quality":90,"width":screenshot.get_width(),"height":screenshot.get_height(),"encoder":"Godot Image.save_webp(lossy=true, quality=0.9)","avatar":"not instantiated"},"\t"))
	panel.fields.fields.width.value=3.1
	check(panel.apply_button.disabled and panel.preview_result.is_empty() and not is_instance_valid(panel.overlay),"changing UI constraint invalidates preview and disables apply")
	panel.fields.update_values(values);panel.preview_button.pressed.emit()
	await rejected("apply_terrain_ramp",args.merged({"expected_token":"stale"},true),"stale preview token")
	await rejected("apply_terrain_ramp",args.merged({"expected_token":preview.token,"width":3.1},true),"parameters changed after preview")
	var source:Dictionary=editor._doc._find(right.id);source.terrain_mesh.heights[0]=.01
	await rejected("apply_terrain_ramp",args.merged({"expected_token":preview.token},true),"map changed after preview");source.terrain_mesh.heights[0]=0.
	var applied:=await call_tool("apply_terrain_ramp",args.merged({"expected_token":preview.token},true))
	if not applied.get("ok",false):quit(1);return
	var after:=snapshot()
	check(editor._doc._undo.size()==history+1,"both terrain tiles and following road are a single transaction")
	check(editor._doc.records.filter(func(r):return r.has("road_mesh")).all(func(r):return r.has("terrain_follow")),"road retains native follow/edit/save semantics")
	for endpoint:Array in [args.start,args.end]:
		var query:=await call_tool("sample_terrain_height",{"id":left.id,"point":[endpoint[0],endpoint[2]]})
		check(absf(query.height-endpoint[1])<=.0002,"endpoint interior to grid reaches exact requested height")
	await call_tool("undo");check(equivalent(before,snapshot()),"one undo restores whole ramp and road")
	await call_tool("redo");check(equivalent(after,snapshot()),"one redo restores whole ramp and road")
	await call_tool("undo");panel.fields.update_values(values);panel.preview_button.pressed.emit();panel.apply_button.pressed.emit()
	check(equivalent(after,snapshot()) and panel.preview_result.is_empty(),"actual UI apply callback matches HTTP and clears draft preview")
	var noop_history:int=editor._doc._undo.size();var noop:=await call_tool("apply_terrain_ramp",args)
	# Blend is a stamp: reapplying can advance its exterior interpolation. A flat
	# full-map zero-height request below separately proves true no-op behavior.
	check(noop.ok and editor._doc._undo.size()<=noop_history+1,"repeated ramp remains one bounded transaction")
	await call_tool("save_world");var saved:=snapshot();await call_tool("open_world",{"path":path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(equivalent(saved,snapshot()),"save/reopen preserves endpoint ground and road metadata")
	await call_tool("select_objects",{"ids":[]})
	editor._ground_batches.flush();await settle();await physics_frame;await physics_frame
	var batch_stats:Dictionary=editor._ground_batches.stats();check(int(batch_stats.get("pending_groups",0))==0,"native automatic derived batches finish publication")
	check(int(batch_stats.get("groups",0))>0 and int(batch_stats.get("source_surfaces",0))>int(batch_stats.get("render_surfaces",0)),"actual native terrain/road batching reduces surfaces after publication")
	check(applied.affected_ids.all(func(id):return is_instance_valid(editor._view.get_node_or_null(NodePath(id))) and not editor._bodies_by_uuid.get(id,[]).is_empty()),"every affected terrain/road retains independent editor and picking identity")
	# True no-op plus the pre-existing layout caller exercise the shared commit boundary.
	var flat:=await call_tool("create_terrain",{"center":[50.,0.,0.],"width":16.,"depth":16.,"cell_size":1.})
	var flat_args:={"id":flat.id,"start":[46.,0.,0.],"end":[54.,0.,0.],"width":2.,"blend_margin":1.}
	var flat_before:=City.token(snapshot());var flat_history:int=editor._doc._undo.size()
	var flat_result:=await call_tool("apply_terrain_ramp",flat_args)
	check(not flat_result.changed and flat_before==City.token(snapshot()) and flat_history==editor._doc._undo.size(),"true flat no-op preserves metadata/history")
	var layout_args:={"strokes":[{"id":flat.id,"mode":"flatten","shape":"rectangle","points":[[50.,0.]],"plot_width":8.,"plot_depth":8.,"target_height":.1,"strength":1.,"blend_margin":1.}]}
	await call_tool("apply_terrain_layout",layout_args);await call_tool("undo");check(flat_before==City.token(snapshot()),"existing joint-layout apply/undo retains shared transaction behavior")
	var rotated:Dictionary=editor._doc._find(flat.id);rotated.rotation=[0.,30.,0.]
	var descending:=await call_tool("preview_terrain_ramp",flat_args.merged({"start":[46.,.4,-1.],"end":[54.,-.4,1.]},true))
	check(descending.grade<0 and descending.max_height_error<=.0002 and descending.earthwork.cut_m3>0 and descending.earthwork.fill_m3>0,"rotated terrain supports descending two-endpoint ramp with both cut and fill")
	rotated.rotation=[0.,0.,0.]
	var bridge_ground:=await call_tool("create_terrain",{"center":[80.,8.175,0.],"width":20.,"depth":20.,"cell_size":.5})
	await call_tool("generate_bridge",{"id":"protected_arch","prefab_id":"stone_segmental","start":[76.,8.2,0.],"end":[84.,8.2,0.],"width":6.2,"depth":1.5,"camber":0.,"arches":1,"wing_length":0.,"auto_clearance":false,"clearance_mode":"stream"})
	var bridge_reject:=await rejected("apply_terrain_ramp",{"id":bridge_ground.id,"start":[78.,9.,0.],"end":[82.,9.,0.],"width":2.,"blend_margin":.5},"solid bridge body cannot be filled")
	check(bridge_reject.get("conflicts",[]).has("protected_arch"),"bridge rejection names actual protected body")
	check(evidence.size()>=19,"all negative HTTP cases actually executed")
	var result:={"failures":failed,"map":path,"map_sha256":FileAccess.get_sha256(path),"preview":preview,"apply":applied,"cases":evidence,"batch_stats":batch_stats,"scope":"true loopback HTTP and native UI in isolated background desktop; disposable map only"}
	FileAccess.open(OUT+"/http.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("TERRAIN_RAMP_HTTP failures=",failed);quit(1 if failed else 0)
