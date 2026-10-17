extends "res://tools/test_world3d_blocks.gd"
var checks:Array=[]
var evidence:Dictionary={}
var output:="D:/code/rmmo_runtime/review_artifacts/joint_candidate_20261017/http.json"

func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"label":label});super.check(ok,label)

func finish()->void:
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failed,"map_path":map_path,"directory":directory,"engine":Engine.get_version_info().string,"evidence":evidence},"\t"))
	print("JOINT_CANDIDATE checks=%d failures=%d"%[checks.size(),failed])
	if is_instance_valid(editor):editor.queue_free();await settle()
	quit(0 if failed==0 else 1)

func run()->void:
	rpc_timeout_ms=120000
	create_timer(650).timeout.connect(func():check(false,"timeout");finish())
	root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	directory=Paths.cache_directory("joint_candidate_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(directory);map_path=directory.path_join("map.gltf")
	var doc:=Doc.new();var ground:String=doc.add_box("ground",Vector3(0,-.25,0),Vector3(180,.5,160))
	check(doc.save(map_path)==OK,"isolated native map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job.active:await process_frame
	editor._safety.enabled=false
	var probe:=TCPServer.new();port=32400
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"private loopback starts")
	var defs:Array=(await rpc("tools/list")).result.tools
	check(defs.filter(func(t):return t.name in ["list_joint_candidate_operations","preview_joint_candidate","apply_joint_candidate","discard_joint_candidate"]).size()==4 and not defs.any(func(t):return t.name=="paint_tile"),"3D discovery advertises joint lifecycle only")
	var catalog:=await call_tool("list_joint_candidate_operations")
	check(catalog.operations.size()==17,"native schema registry exposes every bounded adapter")
	await contract_cases()
	var original:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var steps:Array=[]
	var zones:String=JSON.stringify(City.resolve(editor._doc.map_meta).get("zones",[])).sha256_text()
	for i in 35:
		steps.append({"id":"zone_%d"%i,"update_planning_zones":{"expected_token":zones,"zones":[{"id":"zone_%d"%i,"purpose":"no_vegetation","polygon":[[65+i*.1,60],[66+i*.1,60],[66+i*.1,62],[65+i*.1,62]],"min_y":-1.,"max_y":10.}]}})
	steps.append({"id":"roads","create_road_path":{"points":[[-35,0,-35],[35,0,-35],[35,0,35],[-35,0,35],[-35,0,-35]],"width":4.}})
	steps.append({"id":"surface","generate_road_surface":{"material_id":"pack:default:paving/historic_cobble/material"}})
	steps.append({"id":"houses","generate_block_buildings":{"max_buildings":2}})
	var args:Dictionary={"steps":steps};evidence.request=args
	var candidate:=await call_tool("preview_joint_candidate",args)
	if not candidate.ok:evidence.last_failure=candidate;await finish();return
	check(candidate.step_count==38 and candidate.steps.back().result.building_ids.size()==2,"38 native operations prepare two houses and roads")
	check(equivalent(original,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"private preview changes no author records or history")
	var again:=await call_tool("preview_joint_candidate",args);check(again.plan_token==candidate.plan_token,"same request reuses pinned candidate")
	var bad:=args.duplicate(true);bad.steps.append({"id":"last","generate_waterway":{"id":"bad","ground_ids":["missing"],"points":[[0,0],[10,0]]}})
	var failure:Dictionary=await call_tool("preview_joint_candidate",bad,false)
	check(not failure.ok and equivalent(original,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"last failure has no author side effects")
	check(failure.get("step_id")=="last" and failure.get("step_index")==38,"last step failure reports precise position after 38 private operations")
	candidate=await call_tool("preview_joint_candidate",args)
	await atomic_reject("apply_joint_candidate",{"plan_token":"wrong"})
	var applied:=await call_tool("apply_joint_candidate",{"plan_token":candidate.plan_token})
	if not applied.ok:await finish();return
	check(editor._doc._undo.size()==history+1,"more than 32 native steps publish exactly one outer undo")
	var after:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");check(equivalent(original.records,editor._doc.records) and equivalent(original.map_meta,editor._doc.map_meta),"one undo restores all tools and metadata")
	await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"one redo restores final identities")
	check(equivalent(original.records[0],editor._doc._find(ground)),"untouched ground record stays byte equivalent")
	var house_id:String=editor._buildings.instances().keys()[0]
	var part:Dictionary=editor._doc._find(editor._buildings.instances()[house_id].parts.values()[0])
	var bounds:=Geometry.bounds(editor._doc.records.filter(func(r):return r.get("building",{}).get("id")==house_id))
	var blocking:={"id":"block_access","purpose":"no_build","polygon":[[bounds.position.x-1,bounds.position.z-1],[bounds.end.x+1,bounds.position.z-1],[bounds.end.x+1,bounds.end.z+1],[bounds.position.x-1,bounds.end.z+1]],"min_y":-10.,"max_y":60.}
	var rejected:=await call_tool("preview_joint_candidate",{"steps":[{"id":"later_zone","update_planning_zones":zone_request({"zones":[blocking]})}]},false)
	check(rejected.get("stage")=="joint_final" and equivalent(after,editor._doc.recovery_snapshot()),"final proof rejects a later zone invading existing house and preserves map")
	await ui_cases()
	await call_tool("save_world")
	while editor.saving():await process_frame
	var reopened=Doc.open_file(map_path);check(reopened!=null,"native save reopens")
	check(equivalent(editor._doc.records,reopened.records) and equivalent(editor._doc.map_meta,reopened.map_meta),"saved author records and metadata round trip")
	editor._ground_batches.flush();await settle();var deadline:=Time.get_ticks_msec()+60000
	while editor._ground_batches.stats().pending_groups>0 and Time.get_ticks_msec()<deadline:await process_frame
	evidence.editor_batches=editor._ground_batches.stats()
	check(evidence.editor_batches.pending_groups==0 and evidence.editor_batches.source_surfaces>evidence.editor_batches.render_surfaces,"joint candidate publishes actual shared static batches")
	await finish()

func contract_cases()->void:
	var baseline:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var zone:={"id":"single","purpose":"no_vegetation","polygon":[[70,60],[73,60],[73,63],[70,63]],"min_y":-1.,"max_y":8.}
	var args:={"steps":[{"id":"zone","update_planning_zones":zone_request({"zones":[zone]})}]}
	await atomic_reject("preview_joint_candidate",{"steps":[]})
	await atomic_reject("preview_joint_candidate",{"steps":[{"id":"save","save_world":{}}]})
	await atomic_reject("preview_joint_candidate",{"steps":[{"id":"dual","generate_road_surface":{},"create_road_path":{"points":[[0,0,0],[0,0,10]]}}]})
	await atomic_reject("preview_joint_candidate",{"steps":[args.steps[0],args.steps[0]]})
	await atomic_reject("preview_joint_candidate",{"steps":[{"id":"stale","update_planning_zones":{"expected_token":"stale","zones":[zone]}}]})
	await atomic_reject("preview_joint_candidate",{"steps":[{"id":"old","generate_road_surface":{"plan_token":"old"}}]})
	var many:Array=[]
	for i in 65:many.append({"id":"s%d"%i,"generate_road_surface":{}})
	await atomic_reject("preview_joint_candidate",{"steps":many})
	var plan:=await call_tool("preview_joint_candidate",args)
	await call_tool("discard_joint_candidate",{"plan_token":plan.plan_token});await atomic_reject("apply_joint_candidate",{"plan_token":plan.plan_token})
	plan=await call_tool("preview_joint_candidate",args)
	editor._joint_candidate._candidate.after.records[0].position[1]+=.1
	await atomic_reject("apply_joint_candidate",{"plan_token":plan.plan_token})
	plan=await call_tool("preview_joint_candidate",args)
	await call_tool("update_planning_zones",zone_request({"zones":[zone]}));await call_tool("undo")
	await atomic_reject("apply_joint_candidate",{"plan_token":plan.plan_token})
	plan=await call_tool("preview_joint_candidate",args)
	var dependency:=directory.path_join("pinned_resource.bin");FileAccess.open(dependency,FileAccess.WRITE).store_string("original")
	editor._joint_candidate._candidate.dependencies[dependency]=FileAccess.get_sha256(dependency)
	FileAccess.open(dependency,FileAccess.WRITE).store_string("changed")
	await atomic_reject("apply_joint_candidate",{"plan_token":plan.plan_token})
	plan=await call_tool("preview_joint_candidate",args);editor._dirty=false
	await call_tool("apply_joint_candidate",{"plan_token":plan.plan_token})
	check(editor._dirty and editor._doc._undo.size()==history+1,"metadata-only candidate marks dirty and adds one history entry")
	var noop:={"steps":[{"id":"noop","update_planning_zones":zone_request({"zones":[zone]})}]}
	plan=await call_tool("preview_joint_candidate",noop);var count:int=editor._doc._undo.size()
	await call_tool("apply_joint_candidate",{"plan_token":plan.plan_token})
	check(not plan.changed and count==editor._doc._undo.size(),"no-op candidate leaves history intact")
	await call_tool("undo")
	check(equivalent(baseline.records,editor._doc.records) and equivalent(baseline.map_meta,editor._doc.map_meta),"contract checks restore initial map")

func choose_source(panel:VBoxContainer,id:String)->void:
	for i in panel.sources.item_count:
		if panel.sources.get_item_metadata(i)==id:panel.sources.select(i);return
	check(false,"missing UI source "+id)

func ui_cases()->void:
	var panel=editor._city.panel.joint_panel
	choose_source(panel,"surface");panel.capture(false);panel.capture(false)
	check(panel.steps.size()==2 and panel.steps[0].has("generate_road_surface"),"UI snapshots native panel arguments")
	var first:String=panel.steps[0].id;panel.queue.select(1);panel.move_step(-1)
	check(panel.steps[1].id==first,"UI reorders steps")
	panel.capture(true);check(panel.steps.size()==2,"UI replaces selected step without adding")
	panel.remove_step();check(panel.steps.size()==1,"UI removes selected step")
	panel.preview();check(not panel.token.is_empty() and not panel.apply_button.disabled,"UI uses shared preview and apply lifecycle")
	panel.capture(false);check(panel.token.is_empty() and panel.apply_button.disabled,"queue mutation invalidates preview")
	panel.preview();var token:String=panel.token
	editor._doc.checkpoint_recovery();await process_frame
	check(panel.token.is_empty() and panel.apply_button.disabled,"document revision invalidates UI preview")
	await atomic_reject("apply_joint_candidate",{"plan_token":token})
	editor._doc._undo.pop_back()
	panel.preview();editor._dock_tabs.current_tab=9
	# Expand the joint section and bring its queue into view.
	var body:Node=panel.queue.get_parent();body.show()
	var parent:Node=body.get_parent()
	for child:Node in parent.get_children():
		if child is Button and "跨工具联合候选" in child.text:child.button_pressed=true
	var scroll:Node=body
	while scroll!=null and not scroll is ScrollContainer:scroll=scroll.get_parent()
	await settle()
	if scroll!=null:scroll.ensure_control_visible(panel.apply_button)
	await settle();await RenderingServer.frame_post_draw
	var screenshot:=output.get_base_dir().path_join("ui.webp");var img:=root.get_texture().get_image();img.save_webp(screenshot,true,.9)
	FileAccess.open(output.get_base_dir().path_join("compression.json"),FileAccess.WRITE).store_string(JSON.stringify({"sha256":FileAccess.get_sha256(screenshot),"quality":90,"lossy":true,"width":img.get_width(),"height":img.get_height(),"encoder":"Godot Image.save_webp(lossy=true,quality=0.9)"},"\t"))
	panel.apply_candidate();check(panel.steps.is_empty() and panel.token.is_empty(),"UI shared apply clears completed queue")
