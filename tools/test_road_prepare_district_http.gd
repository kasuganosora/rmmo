extends "res://tools/test_world3d_roads.gd"
## Isolated district integration. Graphical runs belong on the private desktop.
## Uses existing native bridge geometry; does not create or modify any model asset.
const Net = preload("res://scripts/net/net.gd")
const MaterialChoice = preload("res://scripts/world_editor/material_choice.gd")
const Paint = preload("res://scripts/world3d/surface_materials.gd")
var report_path := ""
var checks: Array = []
var report: Dictionary = {}
var started_ms := Time.get_ticks_msec()
var blocker_id := ""
var far_records: Dictionary = {}
var pavement_material := ""
var kerb_material_id := ""

func check(ok: bool, label: String) -> void:
	checks.append({"ok":ok,"label":label})
	super.check(ok,label)

func digest(value: Variant) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value)); return hash.finish().hex_encode()

func snapshot() -> Dictionary:
	return {"document":digest(editor._doc.recovery_snapshot()),"history":digest([editor._doc._undo,editor._doc._redo]),"selection":editor._selection_tools.ids.duplicate(),"dirty":editor._doc.editor_dirty}

func same_snapshot(before: Dictionary, label: String) -> void:
	check(before==snapshot(),label)

func atomic_reject(name_: String, args: Dictionary) -> void:
	var before := snapshot()
	var result := await call_tool(name_,args,false)
	same_snapshot(before,"invalid operation preserves exact document/history/selection/dirty: "+name_)
	report.get_or_add("rejections",[]).append({"tool":name_,"arguments":args,"result":result})

func authored_equal(a: Dictionary, b: Dictionary) -> bool:
	var left := a.duplicate(true); var right := b.duplicate(true)
	# Native undo intentionally retains the monotonic object-ID allocator.
	left.erase("next"); right.erase("next")
	return equivalent(left,right)

func graph_fixture() -> Dictionary:
	var nodes: Array = []
	for item in [["west",-90,0],["junction",-60,0],["approach_w",-26,0],["approach_e",26,0],["east",90,0],["south",-60,-45],["north",-60,45],["far_a",40,60],["far_b",85,60]]:
		nodes.append({"id":item[0],"position":[float(item[1]),0.0,float(item[2])]})
	var edges: Array = []
	for item in [["west_lane","west","junction"],["approach_lane","junction","approach_w"],["stone_span","approach_w","approach_e"],["east_lane","approach_e","east"],["south_lane","south","junction"],["north_lane","junction","north"],["untouched_lane","far_a","far_b"]]:
		edges.append({"id":item[0],"from":item[1],"to":item[2],"width_start":6.0,"width_end":6.0,"kind":"bridge" if item[0]=="stone_span" else "ground","name":item[0]})
	return {"nodes":nodes,"edges":edges}

func create_fixture() -> bool:
	directory=Paths.external_root().path_join("__road_prepare_district_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata := FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"id":"district_%d"%OS.get_process_id(),"name":"Temporary road preparation district"})); metadata.close()
	map_path=directory.path_join("maps/test/map.gltf")
	var doc := Doc.new()
	doc.add_box("stone",Vector3(0,-5.25,0),Vector3(230,.5,190))
	var water: String=doc.add_box("water",Vector3(0,-2.04,0),Vector3(30,.08,170));doc._find(water).collision="none"
	for side in [-1,1]: doc.add_box("grass",Vector3(side*65,-.25,0),Vector3(90,.5,180))
	blocker_id=doc.add_box("block",Vector3(-77,1,20),Vector3(2,2,2))
	# Sparse courtyard geometry must not become a coarse whole-district obstacle.
	for i in 4: doc.add_box("stone",Vector3(45+i*3,.5,32),Vector3(2,1,2))
	var data := City.resolve({});data.roads=graph_fixture()
	var settings := RoadPlan.defaults()
	var planned := RoadPlan.build(data.roads,settings)
	check(planned.ok,"native planner creates the disposable original bridge-road slab")
	if not planned.ok:return false
	var parts: Array=[]
	for record: Dictionary in planned.records:
		doc.records.append(record)
		parts.append({"key":record.road_source,"id":record.uuid,"signature":Surface.signature(record),"paint_signature":City.token(record.get("surface_paint",[]))})
	data.road_surface={"version":1,"settings":settings,"graph_token":City.token(data.roads),"parts":parts};doc.map_meta.editor_layout=data
	var ok := doc.save(map_path)==OK
	check(ok,"fixture saves only inside its unique temporary resource pack")
	return ok

func material_id(preferred: String, name_: String, color: Color) -> String:
	editor._material_tool.library.include_shared=true
	var value: Dictionary=editor._material_tool.library.find(preferred)
	if not value.is_empty() and Paint.material_valid(value) and value.color[3]==1 and Paint.missing([{"road_kerb_material":value}]).is_empty():return preferred
	var image:=Image.create(8,8,false,Image.FORMAT_RGB8);image.fill(color)
	var path:=directory.path_join(name_+".png");check(image.save_png(path)==OK,"temporary material image stays inside the fixture pack")
	var result:=await call_tool("import_surface_material",{"path":path,"name":name_})
	return str(result.get("material_id",""))

func press(label: String) -> bool:
	for button in editor._city.panel.find_children("*","Button",true,false):
		if button.text==label:button.pressed.emit();return true
	return false

func far_snapshot() -> Dictionary:
	var result: Dictionary={}
	for record: Dictionary in editor._doc.records:
		# Road record.position is the 32 m chunk anchor, not the footprint
		# centroid. In particular the z=60 lane belongs to a z=48 anchor.
		if road_intersects(record,Rect2(30,50,65,20)):result[record.uuid]=var_to_bytes(record)
	return result

func road_intersects(record: Dictionary, area: Rect2) -> bool:
	if not record.has("road_mesh"):return false
	var mask:Array=[area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]
	for shape:Dictionary in Foot.record_shapes(record):
		if not RoadPlan.intersection(Array(shape.polygon).slice(0,-1),mask).is_empty():return true
	return false

func far_unchanged(label: String) -> void:
	var current := far_snapshot()
	check(not far_records.is_empty() and current==far_records,label+": every distant road ID and serialized record byte is unchanged")

func wait_batches() -> void:
	editor._ground_batches.flush()
	var deadline:=Time.get_ticks_msec()+60000
	while int(editor._ground_batches.stats().get("pending_groups",0))>0 and Time.get_ticks_msec()<deadline:await process_frame
	await physics_frame;await physics_frame
	var stats:Dictionary=editor._ground_batches.stats();report.batch_stats=stats
	check(int(stats.get("pending_groups",-1))==0,"all editor derived groups finish before batch assertions")
	check(stats.get("enabled",false) and int(stats.get("groups",0))>0 and int(stats.get("source_surfaces",0))>int(stats.get("render_surfaces",0)),"actual editor batching reduces surfaces")
	var roads:Array=editor._doc.records.filter(func(record):return record.has("road_mesh"))
	check(not roads.is_empty() and roads.all(func(record):return is_instance_valid(editor._view.get_node_or_null(record.uuid)) and not editor._bodies_by_uuid.get(record.uuid,[]).is_empty()),"batched roads retain independent authoring nodes and editor picking identities")

func run() -> void:
	create_timer(600).timeout.connect(func():print("DISTRICT_TIMEOUT");quit(2))
	rpc_timeout_ms=120000;Engine.max_fps=60;root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	if not create_fixture():await finish();return
	var session=Net.session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	editor._safety.enabled=false
	var probe:=TCPServer.new();port=31910
	while port<32010 and probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(port<32010 and editor.start_mcp(port).ok,"isolated real HTTP MCP binds an available loopback port")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var defs:Array=(await rpc("tools/list")).get("result",{}).get("tools",[])
	var names:Array=defs.map(func(value):return value.name)
	check(["preview_road_surface","generate_road_surface","update_road_graph","preview_bridge","generate_bridge"].all(func(value):return names.has(value)) and not names.has("paint_tile"),"discovery exposes current 3D road and bridge tools without a stale tool-count assumption")
	check(defs.any(func(value):return value.name=="preview_road_surface" and value.annotations.readOnlyHint and value.inputSchema.properties.has("kerb_enabled")),"real road preview schema includes kerbs and declares read-only behavior")
	pavement_material=await material_id("pack:default:paving/historic_cobble/material","district_paving",Color(.44,.42,.38))
	kerb_material_id=await material_id("pack:default:paving/automatic_limestone_kerb/material","district_kerb",Color(.7,.67,.6))
	var bridge_args:Dictionary={"id":"district_stone_span","road_edge_id":"stone_span","prefab_id":"stone_segmental","start":[-20,.025,0],"end":[20,.025,0],"width":7.2,"depth":5.0,"camber":.6}
	var before:=snapshot();var bridge_preview:=await call_tool("preview_bridge",bridge_args)
	same_snapshot(before,"native stone bridge preview leaves the district untouched")
	if not bridge_preview.get("ok",false):await finish();return
	await call_tool("generate_bridge",bridge_args.merged({"plan_token":bridge_preview.plan_token},true))
	check(editor._doc._find("district_stone_span").has("bridge_mesh"),"bridgehead fixture uses the existing native stone bridge generator")
	var params:Dictionary={"material_id":pavement_material,"kerb_material_id":kerb_material_id,"kerb_enabled":true,"kerb_height":.055}
	before=snapshot();var preview:=await call_tool("preview_road_surface",params)
	same_snapshot(before,"district road preview is exactly read-only")
	if not preview.get("ok",false):await finish();return
	await atomic_reject("generate_road_surface",params.merged({"plan_token":"stale"},true))
	await atomic_reject("preview_road_surface",params.merged({"kerb_width":2.0},true))
	var baseline:Dictionary=editor._doc.recovery_snapshot();var undos:int=editor._doc._undo.size()
	await call_tool("generate_road_surface",params.merged({"plan_token":preview.plan_token},true))
	var committed:Dictionary=editor._doc.recovery_snapshot()
	check(editor._doc._undo.size()==undos+1,"district surface and kerbs commit as one undo transaction")
	await call_tool("undo");check(authored_equal(baseline,editor._doc.recovery_snapshot()),"one undo restores complete graph, bridge binding and road records")
	await call_tool("redo");check(authored_equal(committed,editor._doc.recovery_snapshot()),"redo restores identical district IDs and geometry")
	var ui:VBoxContainer=editor._city.panel.road_surface_panel
	ui.settings.update_values(params);MaterialChoice.choose(ui.material_select,pavement_material);MaterialChoice.choose(ui.kerb_material_select,kerb_material_id)
	var ui_params:Dictionary=ui.args();before=snapshot();preview=await call_tool("preview_road_surface",ui_params)
	check(press("预览铺面变化") and ui.token==preview.get("plan_token",""),"actual UI preview button and HTTP return the same plan token for identical inputs")
	same_snapshot(before,"UI and HTTP previews preserve exact authored and history state")
	# Exercise an actual changed UI apply, then the same request through HTTP.
	ui.settings.fields.kerb_height.value=.065
	var changed_params:Dictionary=ui.args();baseline=editor._doc.recovery_snapshot();undos=editor._doc._undo.size()
	check(press("预览铺面变化") and not ui.token.is_empty(),"actual UI prepares a changed kerb height")
	check(press("应用铺面方案"),"actual UI apply button is connected")
	var from_ui:Dictionary=editor._doc.recovery_snapshot()
	check(editor._doc._undo.size()==undos+1 and is_equal_approx(City.resolve(editor._doc.map_meta).road_surface.settings.kerb_height,.065),"UI change commits through the native single transaction")
	await call_tool("undo");check(authored_equal(baseline,editor._doc.recovery_snapshot()),"UI change undo restores the exact authored state")
	await call_tool("generate_road_surface",changed_params)
	check(authored_equal(from_ui,editor._doc.recovery_snapshot()),"HTTP and UI same-input applications produce equivalent complete documents")
	params=changed_params
	var near:Array=editor._doc.records.filter(func(record):return road_intersects(record,Rect2(-79,.5,2,1)))
	check(not near.is_empty(),"local generated pavement is available for ownership protections")
	if near.is_empty():await finish();return
	var protected_id:String=near[0].uuid
	for flag:String in ["locked","hidden"]:
		await call_tool("set_object_properties",{"ids":[protected_id],flag:true})
		await atomic_reject("preview_road_surface",params);await atomic_reject("generate_road_surface",params)
		await call_tool("undo")
	for flag:String in ["locked","hidden"]:
		var node:Dictionary=City.resolve(editor._doc.map_meta).roads.nodes.filter(func(value):return value.id=="west")[0].duplicate(true)
		node[flag]=true;await call_tool("update_road_graph",graph_request({"nodes":[node]}))
		await atomic_reject("generate_road_surface",params);await call_tool("undo")
	# A hidden physical obstacle remains a blocker; broad-phase skips cannot waive it.
	await call_tool("set_object_transform",{"id":blocker_id,"position":[-78,1,0]})
	await call_tool("set_object_properties",{"ids":[blocker_id],"hidden":true})
	await atomic_reject("generate_road_surface",params)
	await call_tool("undo");await call_tool("undo")
	var paint_before:=snapshot()
	var paint_authored:Dictionary=editor._doc.recovery_snapshot()
	var paint_undo_count:int=editor._doc._undo.size()
	var paint_undo_sha:=digest(editor._doc._undo)
	await call_tool("clear_surface_material",{"id":protected_id})
	var painted:Dictionary=editor._doc._find(protected_id).duplicate(true)
	await call_tool("generate_road_surface",params)
	check(editor._doc._find(protected_id).get("surface_paint",[])==painted.get("surface_paint",[]),"repeat generation retains explicit hand-cleared pavement paint")
	var widened:Dictionary=City.resolve(editor._doc.map_meta).roads.edges.filter(func(value):return value.id=="west_lane")[0].duplicate(true)
	widened.width_start=10.0;widened.width_end=10.0
	await atomic_reject("update_road_graph",graph_request({"edges":[widened]}))
	# A connected kerb perimeter may change a protected fragment's UV span.
	# Finish this negative case before exercising a legal district edit. Undo
	# every native transaction added by clear/repeat-generation, not just one.
	var undo_attempts:=0
	while editor._doc._undo.size()>paint_undo_count and undo_attempts<32:
		await call_tool("undo");undo_attempts+=1
	var paint_restored:bool=authored_equal(paint_authored,editor._doc.recovery_snapshot()) and editor._doc._undo.size()==paint_undo_count and digest(editor._doc._undo)==paint_undo_sha
	check(paint_restored,"native undo restores all authored data and the original undo stack before legal local editing")
	report.manual_paint_restoration={"before":paint_before,"after":snapshot(),"native_undo_calls":undo_attempts,"restored":paint_restored}
	if not paint_restored:await finish();return
	# Reopen before testing byte identity: JSON numeric representation must not
	# turn a distant unchanged road into a regeneration update.
	await call_tool("save_world");await call_tool("open_world",{"path":map_path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var reopened_before:=snapshot()
	var reopened_no_op:=await call_tool("generate_road_surface",params)
	check(not reopened_no_op.get("changed",true),"direct native regeneration after save/reopen is a no-op before any local edit")
	same_snapshot(reopened_before,"direct repeat after reopen preserves document bytes, history, selection and dirty state")
	report.reopened_no_op={"result":reopened_no_op,"before":reopened_before,"after":snapshot()}
	far_records=far_snapshot();report.far_before={}
	for id:String in far_records:report.far_before[id]=digest(editor._doc._find(id))
	baseline=editor._doc.recovery_snapshot();undos=editor._doc._undo.size()
	var north:Dictionary=City.resolve(editor._doc.map_meta).roads.nodes.filter(func(value):return value.id=="north")[0].duplicate(true);north.position[2]=49.0
	var edited:=await call_tool("update_road_graph",graph_request({"nodes":[north]}))
	check(edited.get("surface_updated",false) and editor._doc._undo.size()==undos+1,"local graph edit automatically prepares road and kerbs in one transaction")
	if not edited.get("ok",false) or not edited.get("surface_updated",false):
		report.local_edit=edited;await finish();return
	far_unchanged("local endpoint edit after reopen")
	committed=editor._doc.recovery_snapshot();report.local_edit=edited
	await call_tool("undo");check(authored_equal(baseline,editor._doc.recovery_snapshot()),"local district undo restores graph and generated geometry");far_unchanged("undo")
	await call_tool("redo");check(authored_equal(committed,editor._doc.recovery_snapshot()),"local district redo preserves IDs and geometry");far_unchanged("redo")
	before=snapshot()
	var settings_before:Dictionary=City.resolve(editor._doc.map_meta).road_surface.settings.duplicate(true)
	var no_op:=await call_tool("generate_road_surface",params)
	report.no_op={"request":params,"settings_before":settings_before,"result":no_op,"before":before,"after":snapshot()}
	check(not no_op.get("changed",true),"identical district regeneration is a native no-op");same_snapshot(before,"no-op regeneration does not add undo or replace author records")
	await wait_batches()
	await call_tool("save_world");committed=editor._doc.recovery_snapshot()
	await call_tool("open_world",{"path":map_path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(equivalent(committed.records,editor._doc.records) and equivalent(committed.map_meta,editor._doc.map_meta),"district native save/reopen preserves bridge, roads, manual paint and graph")
	far_unchanged("second save/reopen")
	var kerbed:Array=editor._doc.records.filter(func(record):return not record.get("road_mesh",{}).get("kerbs",[]).is_empty())
	check(not kerbed.is_empty() and kerbed.all(func(record):return Paint.material_valid(record.get("road_kerb_material",{})) and Paint.missing([record]).is_empty()),"saved district retains real kerb profiles and resolved material dependencies")
	report.road_ids=editor._doc.records.filter(func(record):return record.has("road_mesh")).map(func(record):return record.uuid)
	report.settings=City.resolve(editor._doc.map_meta).road_surface.settings
	editor._mcp.stop();editor.queue_free();await settle();editor=null
	await collision_probes()
	await finish()

func collision_probes() -> void:
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(map_path)
	var loaded:Array=await loader.finished;var scene:Node3D=loaded[0]
	check(scene!=null,"native runtime loader reopens the saved district")
	if scene==null:
		if is_instance_valid(loader):loader.queue_free()
		return
	var host:=Node3D.new();root.add_child(host);host.add_child(scene)
	var results:Array=[]
	for entry in [["junction",-60.0,0.0],["chunk_left",-64.05,0.0],["chunk_right",-63.95,0.0],["west_approach",-20.05,0.0],["west_bridge",-19.95,0.0],["east_bridge",19.95,0.0],["east_approach",20.05,0.0],["changed_north",-60.0,50.0],["far_lane",50.0,60.0],["empty_courtyard",-76.0,14.0]]:
		var at:=Vector3(entry[1],.9,entry[2])
		var clip:=AABB(at-Vector3(.35,1,.35),Vector3(.7,2,.7))
		var deadline:=Time.get_ticks_msec()+20000
		var ready:Dictionary={"ok":false}
		while not ready.get("ok",false) and Time.get_ticks_msec()<deadline:
			Stream.sync(scene,host,at)
			await physics_frame;await process_frame
			ready=Stream.collision_readiness(scene,clip)
		check(ready.get("ok",false),"native physics publication is ready before probing "+entry[0])
		var hit:=host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,4,at.z),Vector3(at.x,-1,at.z),1))
		var expected:float=0.0 if entry[0]=="empty_courtyard" else .025
		var height:float=hit.position.y if not hit.is_empty() else -1000.0
		check(not hit.is_empty() and absf(height-expected)<.035,"actual native collider supports the intended surface at "+entry[0])
		results.append({"label":entry[0],"point":[at.x,at.z],"height":height,"expected":expected,"readiness":ready})
	for pair in [[3,4],[5,6]]:
		check(absf(float(results[pair[0]].height)-float(results[pair[1]].height))<.035,"native bridgehead and approach collision heights meet continuously")
	report.collision_probes=results
	report.collision_probes_verified=results.all(func(value):return value.readiness.get("ok",false) and absf(value.height-value.expected)<.035)
	report.runtime_scope="Native saved-map collision publication and surface rays at road junction, chunk seams, bridgeheads, changed endpoint and far lane; no capsule traversal in this test."
	var deferred:=scene.get_node_or_null("DeferredAssets")
	if deferred!=null:await deferred.quiesce()
	host.free()
	if is_instance_valid(loader):loader.queue_free()
	await settle()

func finish() -> void:
	report.merge({"failures":failed,"checks":checks,"fixture":map_path,"directory":directory,"graphical":DisplayServer.get_name()!="headless","elapsed_ms":Time.get_ticks_msec()-started_ms,"engine":Engine.get_version_info(),"port":port},true)
	if not map_path.is_empty() and FileAccess.file_exists(map_path):report.map_sha256=FileAccess.get_sha256(map_path)
	if report_path.is_empty():report_path=directory.path_join("district_result.json")
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	if is_instance_valid(editor):editor._mcp.stop();editor.queue_free();await settle()
	Net.session().world3d_editor_doc=null;Net.session().world3d_editor_path=""
	print("ROAD_PREPARE_DISTRICT_REPORT "+report_path)
	print("ROAD_PREPARE_DISTRICT_FINISHED checks=%d failures=%d"%[checks.size(),failed])
	quit(0 if failed==0 else 1)
