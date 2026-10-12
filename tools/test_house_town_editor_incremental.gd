extends "res://tools/test_house_editor_incremental_http.gd"
## Full town operation acceptance. Run only with run_godot_background.py.
## Existing immutable cache fixture; no town save, screenshots or interiors.
const SOURCE="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const EXPECTED_SHA="5d8137af367d2ce27e15b4155dec78be8a6c47a7c99c1fbc8cce1090d9b1a770"
const CHECKPOINT="D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf"
const OUTPUT="res://review_artifacts/house_town_editor_incremental_20261011.json"
const MODEL_NAME="方窗石砌窗套"
const MODEL_PATH="D:/code/rmmo_runtime/packs/default/assets/f1259543701ac5bf03968f2b2d24913c3a3b722dbea543fe43bd2c823311ea8f.glb"
const LIBRARY_PATH="D:/code/rmmo_runtime/packs/default/assets/library.json"
const ModelPaint=preload("res://scripts/world3d/surface_materials.gd")

class MeasuredEditor extends "res://scripts/world_editor/world_editor.gd":
	var full_rebuilds:=0
	var incremental:Array=[]
	func _begin_rebuild(timings:Dictionary={}) -> void:
		full_rebuilds+=1
		super._begin_rebuild(timings)
	func _commit_records(ids:Array)->void:
		var started:=Time.get_ticks_usec()
		super._commit_records(ids)
		incremental.append({"ids":ids.duplicate(),"count":ids.size(),"ms":(Time.get_ticks_usec()-started)/1000.})

var report:Dictionary={}
var baseline_rebuilds:=0
var anchor_states:Dictionary={}
var stage:="initial"
var model_sha:=""
var library_sha:=""
var output_path:=OUTPUT
var checkpoint_path:=CHECKPOINT
var expected_sha:=EXPECTED_SHA
var formal_sha:=""
var formal_sha_explicit:=false
var picking_probe:=false
var load_trace:=false
var model_name:=MODEL_NAME
var model_path:=MODEL_PATH

func persist()->void:
	report.failures=failed;report.stage=stage;report.operations=operations
	if is_instance_valid(editor):
		report.full_rebuilds=editor.full_rebuilds;report.baseline_full_rebuilds=baseline_rebuilds
		report.incremental=editor.incremental
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"  "));file.close()

func mark(value:String)->void:
	stage=value;print("TOWN_INCREMENTAL_STAGE ",value);persist()

func retained(label:String)->void:
	for uuid:String in anchor_states:unchanged_visual(uuid,anchor_states[uuid],label+": unrelated "+uuid+" retains view, node, mesh and bodies")
	check(editor.full_rebuilds==baseline_rebuilds,label+": no full rebuild")

func matches(snapshot:Dictionary,label:String)->void:
	check(equivalent(snapshot.records,editor._doc.records) and equivalent(snapshot.map_meta,editor._doc.map_meta),label+": complete records and registry restored")

func model_asset_id()->String:
	var listed:=await call_tool("list_assets",{"query":model_name,"limit":200})
	var rows:Array=listed.get("assets",[]).filter(func(row):return row.get("name")==model_name)
	var entries:Array=editor.asset_items(model_name).filter(func(row):return row.get("asset_path")==model_path)
	check(rows.size()==1 and entries.size()==1,"real stone window GLB found in existing library")
	return str(rows[0].asset_id) if rows.size()==1 and entries.size()==1 else ""

func model_evidence(uuid:String)->Dictionary:
	var holder:Node=editor._view.get_node_or_null(NodePath(uuid))
	var value:={"meshes":0,"surfaces":0,"materials":0,"textures":0,"vertices":0,"picking_shapes":0,"valid":holder!=null}
	if holder==null:return value
	for visual:MeshInstance3D in ModelPaint.meshes(holder):
		value.meshes+=1
		if visual.mesh==null:value.valid=false;continue
		for slot in visual.mesh.get_surface_count():
			value.surfaces+=1;value.vertices+=visual.mesh.surface_get_array_len(slot)
			var material:BaseMaterial3D=visual.get_active_material(slot) as BaseMaterial3D
			if material==null:value.valid=false;continue
			value.materials+=1
			for texture_slot in BaseMaterial3D.TEXTURE_MAX:
				var texture:Texture2D=material.get_texture(texture_slot)
				if texture==null:continue
				value.textures+=1
				var pixels:Image=texture.get_image()
				if pixels==null or pixels.is_empty():value.valid=false
	for body:Node in editor._bodies_by_uuid.get(uuid,[]):
		for child:Node in body.get_children():
			if child is CollisionShape3D and child.shape!=null:value.picking_shapes+=1
	value.valid=value.valid and value.meshes>0 and value.materials>0 and value.textures>0 and value.vertices>24 and value.picking_shapes>0
	return value

func model_texture_observation(scene:Node)->Dictionary:
	var cache=preload("res://scripts/world3d/model_texture_cache.gd")
	var textures:Dictionary={};var keyed:Dictionary={};var shared_keys:=0;var duplicate_objects:=0
	for material:StandardMaterial3D in cache._materials(scene):
		for info:Dictionary in material.get_property_list():
			if not (int(info.usage)&PROPERTY_USAGE_STORAGE):continue
			var texture:Variant=material.get(info.name)
			if not texture is Texture2D or textures.has(texture.get_instance_id()):continue
			textures[texture.get_instance_id()]=true
			var key:Variant=texture.get_meta(cache.PIXEL_KEY,"")
			if cache._valid_key(key):keyed[key]=int(keyed.get(key,0))+1
	for count:int in keyed.values():
		if count>1:shared_keys+=1;duplicate_objects+=count-1
	var live_pool:=0
	for weak:WeakRef in cache._textures.values():
		if weak.get_ref()!=null:live_pool+=1
	return {"scope":"post-load descriptor observation of reachable StandardMaterial3D textures; no pixel readback; renderer memory is process-global, not per-asset VRAM",
		"texture_objects":textures.size(),"stamped_pixel_keys":keyed.size(),"pixel_keys_with_multiple_objects":shared_keys,
		"duplicate_stamped_objects":duplicate_objects,"live_pool_keys":live_pool,
		"renderer_texture_memory_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)}

func finish()->void:
	check(FileAccess.get_sha256(SOURCE)==formal_sha,"formal town stays byte-identical")
	check(Paths.allowed(checkpoint_path,Paths.external_root().path_join("cache/world3d")) and FileAccess.file_exists(checkpoint_path) and FileAccess.get_sha256(checkpoint_path)==expected_sha,"cache checkpoint stays byte-identical; no full-town save")
	check(model_sha.length()==64 and FileAccess.get_sha256(model_path)==model_sha,"external model source stays byte-identical")
	check(library_sha.length()==64 and FileAccess.get_sha256(LIBRARY_PATH)==library_sha,"existing asset catalog stays byte-identical")
	stage="finished";persist()
	if is_instance_valid(editor):
		if editor._mcp!=null:editor._mcp.stop()
		editor.queue_free();await settle()
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=null;session.world3d_editor_path=""
	print("HOUSE_TOWN_EDITOR_INCREMENTAL failures=",failed," report=",output_path)
	quit(0 if failed==0 else 1)

func run()->void:
	Engine.max_fps=60;rpc_timeout_ms=120000
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--prefab-warm-workers="):
			var count:=arg.trim_prefix("--prefab-warm-workers=")
			if count not in ["1","2"]:push_error("Expected --prefab-warm-workers=1 or 2");quit(2);return
			preload("res://scripts/world3d/document_open_cursor.gd").prefab_warm_workers=int(count)
		elif arg.begins_with("--output="):output_path=arg.trim_prefix("--output=")
		elif arg.begins_with("--map="):checkpoint_path=arg.trim_prefix("--map=")
		elif arg.begins_with("--expected-sha="):expected_sha=arg.trim_prefix("--expected-sha=")
		elif arg=="--formal-sha" or arg.begins_with("--formal-sha="):
			formal_sha=arg.trim_prefix("--formal-sha=");formal_sha_explicit=true
		elif arg=="--picking-probe":picking_probe=true
		elif arg=="--load-trace":load_trace=true
		elif arg=="--picking-lod" or arg.begins_with("--picking-lod="):
			var mode:=arg.trim_prefix("--picking-lod=")
			if mode not in ["off","on"]:push_error("Expected --picking-lod=off or on");quit(2);return
			preload("res://scripts/world_editor/picking_lod_policy.gd").enabled=mode=="on"
		elif arg=="--model-texture-sharing" or arg.begins_with("--model-texture-sharing="):
			var mode:=arg.trim_prefix("--model-texture-sharing=")
			if mode not in ["off","on"]:push_error("Expected --model-texture-sharing=off or on");quit(2);return
			preload("res://scripts/world3d/model_texture_cache.gd").enabled=mode=="on"
		elif arg.begins_with("--model-residency="):
			var mode:=arg.trim_prefix("--model-residency=")
			if mode not in ["off","on"]:push_error("Expected --model-residency=off or on");quit(2);return
			preload("res://scripts/world_editor/load_job.gd").prepared_model_residency_enabled=mode=="on"
		elif arg.begins_with("--preparation-lanes="):
			var mode:=arg.trim_prefix("--preparation-lanes=")
			if mode not in ["fifo","fair"]:push_error("Expected --preparation-lanes=fifo or fair");quit(2);return
			preload("res://scripts/world_editor/load_job.gd").preparation_lanes_enabled=mode=="fair"
		elif arg.begins_with("--native-model-budget="):
			var mode:=arg.trim_prefix("--native-model-budget=")
			if mode not in ["full","compiled"]:push_error("Expected --native-model-budget=full or compiled");quit(2);return
			preload("res://scripts/world_editor/load_job.gd").native_model_footprints_enabled=mode=="compiled"
	if expected_sha.length()!=64:push_error("Expected --expected-sha with exactly 64 hexadecimal characters");quit(2);return
	for character in expected_sha:
		if character not in "0123456789abcdefABCDEF":push_error("Expected --expected-sha with exactly 64 hexadecimal characters");quit(2);return
	expected_sha=expected_sha.to_lower()
	if not formal_sha_explicit:formal_sha=expected_sha
	if formal_sha.length()!=64:push_error("Expected --formal-sha with exactly 64 hexadecimal characters");quit(2);return
	for character in formal_sha:
		if character not in "0123456789abcdefABCDEF":push_error("Expected --formal-sha with exactly 64 hexadecimal characters");quit(2);return
	formal_sha=formal_sha.to_lower()
	checkpoint_path=checkpoint_path.replace("\\","/").simplify_path()
	if not Paths.allowed(checkpoint_path,Paths.external_root().path_join("cache/world3d")) or not FileAccess.file_exists(checkpoint_path):push_error("Test map must be an existing file inside cache/world3d");quit(2);return
	var resolved:=ProjectSettings.globalize_path(output_path).simplify_path().replace("\\","/")
	var repository_output:=ProjectSettings.globalize_path("res://review_artifacts").simplify_path().replace("\\","/")
	var runtime_output:=Paths.external_root().path_join("review_artifacts")
	if not Paths.allowed(resolved,repository_output) and not Paths.allowed(resolved,runtime_output):push_error("Test output must stay inside review_artifacts");quit(2);return
	if resolved.get_extension().to_lower()!="json":push_error("Test output must be JSON");quit(2);return
	output_path=resolved
	root.size=Vector2i(1280,900);root.content_scale_size=root.size
	report={"source":SOURCE,"checkpoint":checkpoint_path,"expected_sha256":expected_sha,"formal_sha256":formal_sha,"scope":"Actual 4437-record, 61-house editor; operation timings include real HTTP round-trip, not a controlled cold-load benchmark."}
	report.prefab_warm_workers=preload("res://scripts/world3d/document_open_cursor.gd").prefab_warm_workers
	report.native_model_footprints=preload("res://scripts/world_editor/load_job.gd").native_model_footprints_enabled
	report.preparation_lanes=preload("res://scripts/world_editor/load_job.gd").preparation_lanes_enabled
	report.model_residency=preload("res://scripts/world_editor/load_job.gd").prepared_model_residency_enabled
	report.picking_lod=preload("res://scripts/world_editor/picking_lod_policy.gd").enabled
	report.model_texture_sharing=preload("res://scripts/world3d/model_texture_cache.gd").enabled
	model_sha=FileAccess.get_sha256(model_path);library_sha=FileAccess.get_sha256(LIBRARY_PATH)
	report.external_model={"path":model_path,"sha256":model_sha,"catalog_sha256":library_sha}
	create_timer(1200).timeout.connect(func():report.timeout=true;persist();quit(2))
	check(FileAccess.get_sha256(SOURCE)==formal_sha,"formal source matches required immutable town revision")
	check(Paths.allowed(checkpoint_path,Paths.external_root().path_join("cache/world3d")) and FileAccess.get_sha256(checkpoint_path)==expected_sha,"existing isolated checkpoint matches required immutable test revision")
	check(model_sha.length()==64 and library_sha.length()==64,"real external GLB and existing catalog available without import or library changes")
	if failed>0:await finish();return
	directory=Paths.cache_directory("house_town_incremental_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var initial:=Doc.new();initial.add_box("block",Vector3.ZERO,Vector3.ONE)
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=initial;session.world3d_editor_path=directory.path_join("initial_unsaved.gltf")
	editor=MeasuredEditor.new();editor._mcp_autostart=false
	if picking_probe:editor._picking_shapes=preload("res://tools/picking_cache_probe.gd").new()
	editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new();port=29888
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real loopback MCP for town operations")
	var defs:Array=(await rpc("tools/list")).get("result",{}).get("tools",[])
	check(defs.size()==preload("res://scripts/world_editor/mcp_schema.gd").tools().size() and defs.any(func(t):return t.name=="delete_building"),"current 3D tools discoverable")
	mark("loading")
	if load_trace:preload("res://scripts/world3d/load_trace.gd").start()
	report.load_start_epoch_s=Time.get_unix_time_from_system()
	var started:=Time.get_ticks_usec()
	var pending:=await timed_tool("open_world",{"path":checkpoint_path,"background":true,"discard_changes":true})
	check(pending.get("pending",false),"actual HTTP open_world starts asynchronous town loading")
	var next_log:=Time.get_ticks_msec()+5000
	while editor._load_job.active:
		if Time.get_ticks_msec()>=next_log:
			print("TOWN_INCREMENTAL_LOAD ",editor._load_job.phase," ",editor._load_job.completed,"/",editor._load_job.total)
			next_log=Time.get_ticks_msec()+5000
		await process_frame
	report.load_ms=(Time.get_ticks_usec()-started)/1000.
	report.load_end_epoch_s=Time.get_unix_time_from_system()
	if load_trace:report.load_trace=preload("res://scripts/world3d/load_trace.gd").stop()
	report.load_result=editor._load_job.result.duplicate(true)
	if picking_probe:report.picking_probe=editor._picking_shapes.snapshot()
	check(editor._load_job.result.get("ok",false),"actual town loading completes successfully")
	if not editor._load_job.result.get("ok",false):await finish();return
	var doc=editor._doc
	check(doc.records.size()==4437 and editor._buildings.instances().size()==61,"actual town contains 4437 records and 61 houses")
	if doc.records.size()!=4437 or editor._buildings.instances().size()!=61:await finish();return
	# Drain initial derived batches before measuring authoring operations.
	editor._ground_batches.flush();await settle()
	# Post-timer, descriptor-only observation: never read back texture pixels.
	report.model_texture_observation=model_texture_observation(editor._view)
	baseline_rebuilds=editor.full_rebuilds;editor.incremental.clear()
	mark("list_buildings")
	started=Time.get_ticks_usec();var direct:Dictionary=editor._buildings.list_buildings()
	report.list_business_ms=(Time.get_ticks_usec()-started)/1000.
	var listed:=await timed_tool("list_buildings")
	check(equivalent(direct,listed) and listed.buildings.size()==61,"HTTP list matches shared indexed business results for all 61 houses")
	var eligible:Array=[]
	for row:Dictionary in listed.buildings:
		if not row.conflicts.is_empty():continue
		var ids:Array=editor._buildings.instances()[row.id].parts.values()
		if ids.any(func(id):return not editor._bodies_by_uuid.get(id,[]).is_empty()):eligible.append(row.id)
	check(eligible.size()>=3,"at least three intact editable houses provide target and unrelated sentinels")
	if eligible.size()<3:await finish();return
	var target:String=eligible[0];var members:Array=editor._buildings.instances()[target].parts.values()
	var first:String=members.filter(func(id):return not editor._bodies_by_uuid.get(id,[]).is_empty())[0]
	for other:String in eligible.slice(1,3):
		var candidates:Array=editor._buildings.instances()[other].parts.values().filter(func(id):return not editor._bodies_by_uuid.get(id,[]).is_empty())
		anchor_states[candidates[0]]=stable(candidates[0])
	report.target={"id":target,"members":members.size(),"first":first};report.sentinels=anchor_states.keys()
	await call_tool("select_objects",{"ids":[first]});editor._ground_batches.flush()
	var target_before:=stable(first);var pristine:Dictionary=doc.recovery_snapshot()
	mark("rename")
	await timed_tool("set_object_properties",{"group_id":target,"name":"城镇增量验收临时名"})
	unchanged_visual(first,target_before,"town rename retains target geometry");retained("town rename")
	await timed_tool("undo");matches(pristine,"rename undo");retained("rename undo")
	mark("lock")
	await timed_tool("set_object_properties",{"group_id":target,"locked":true})
	check(editor._selection_tools.ids.is_empty(),"locking actual town house clears selection")
	unchanged_visual(first,target_before,"town lock retains target geometry");retained("town lock")
	var protected_state:={"dirty":editor._dirty,"selection":editor._selection_tools.ids.duplicate(),"commits":editor.incremental.size(),"view":editor._view}
	await atomic_reject("delete_building",{"id":target})
	await atomic_reject("set_object_properties",{"group_id":target,"name":"应被拒绝"})
	await atomic_reject("set_object_properties",{"ids":[first],"hidden":"invalid"})
	check(editor._dirty==protected_state.dirty and editor._selection_tools.ids==protected_state.selection and editor.incremental.size()==protected_state.commits and editor._view==protected_state.view,"rejection also preserves dirty state, selection, commit count and view")
	retained("protected/invalid rejection")
	await timed_tool("undo");matches(pristine,"lock undo");retained("lock undo")
	mark("hide")
	await timed_tool("set_object_properties",{"group_id":target,"hidden":true})
	editor._ground_batches.flush()
	check(editor._view.get_node(first)==target_before.node and not target_before.node.visible and editor._bodies_by_uuid.get(first,[]).is_empty(),"hidden town house keeps its visual while removing picking body")
	retained("town hide")
	await timed_tool("undo");editor._ground_batches.flush()
	check(editor._view.get_node(first)==target_before.node and target_before.node.visible and not editor._bodies_by_uuid.get(first,[]).is_empty(),"town visibility undo restores picking without mesh rebuild")
	matches(pristine,"hide undo");retained("hide undo")
	mark("delete_house")
	await timed_tool("delete_building",{"id":target})
	check(not editor._buildings.instances().has(target) and members.all(func(id):return editor._view.get_node_or_null(id)==null),"house delete removes registry and all member visuals")
	check(doc.records.size()==4437-members.size(),"house deletion changes only member record count")
	retained("town house deletion")
	await timed_tool("undo");editor._ground_batches.flush()
	matches(pristine,"house deletion undo");retained("house deletion undo")
	mark("add_delete_box")
	var entries:Array=editor._mcp._ops.assets()
	var ordinary:Array=entries.filter(func(entry):return not entry.has("asset_path") and not entry.has("prefab_path") and not entry.has("auto_family") and entry.get("surface_id","")=="bridge_deck")
	check(not ordinary.is_empty(),"ordinary box palette entry available")
	if ordinary.is_empty():await finish();return
	var placed:=await timed_tool("place_asset",{"asset_id":editor._mcp._ops.asset_id(ordinary[0]),"position":[5000.,1.,5000.]})
	if not placed.get("ok",false):await finish();return
	check(placed.get("ids",[]).size()==1,"ordinary far-away placement adds one box")
	if placed.get("ids",[]).size()!=1:await finish();return
	var added:String=placed.ids[0]
	check(doc.records.size()==4438 and editor._view.has_node(added) and editor._bodies_by_uuid.has(added),"added box has independent visual and picking body")
	retained("ordinary box addition")
	await call_tool("select_objects",{"ids":[added]})
	await timed_tool("delete_selection")
	check(not doc.has_uuid(added) and not editor._view.has_node(added),"ordinary box deletion removes its record and visual")
	matches(pristine,"all operation reversals");retained("ordinary box deletion")
	mark("add_external_glb")
	var asset_id:=await model_asset_id()
	if asset_id.is_empty():await finish();return
	var model_placed:=await timed_tool("place_asset",{"asset_id":asset_id,"position":[5010.,1.,5000.]})
	check(model_placed.get("ids",[]).size()==1,"external GLB placement adds exactly one independent instance")
	if not model_placed.get("ok",false) or model_placed.get("ids",[]).size()!=1:await finish();return
	var model_id:String=model_placed.ids[0]
	var model_record:Dictionary=doc._find(model_id).duplicate(true)
	report.external_model.uuid=model_id;report.external_model.placed=model_evidence(model_id)
	check(doc.records.size()==4438 and model_record.get("kind")=="asset" and model_record.get("asset_path")==model_path,"new town instance references the actual external GLB")
	check(report.external_model.placed.valid,"new external GLB has actual mesh, materials, readable textures and picking shapes")
	retained("external GLB addition")
	mark("undo_redo_external_glb")
	await timed_tool("undo")
	check(not doc.has_uuid(model_id) and not editor._view.has_node(model_id) and editor._bodies_by_uuid.get(model_id,[]).is_empty(),"external GLB undo removes its visual and picking bodies")
	matches(pristine,"external GLB undo");retained("external GLB undo")
	await timed_tool("redo")
	check(doc.records.size()==4438 and equivalent(doc._find(model_id),model_record),"external GLB redo preserves UUID and complete authored instance")
	report.external_model.redone=model_evidence(model_id)
	check(report.external_model.redone.valid,"external GLB redo restores real textured geometry and picking")
	retained("external GLB redo")
	mark("delete_external_glb")
	await call_tool("select_objects",{"ids":[model_id]})
	await timed_tool("delete_selection")
	check(not doc.has_uuid(model_id) and not editor._view.has_node(model_id) and editor._bodies_by_uuid.get(model_id,[]).is_empty(),"external GLB deletion removes only its instance, visual and picking")
	matches(pristine,"external GLB deletion");retained("external GLB deletion")
	check(editor._buildings.instances().size()==61 and doc.records.size()==4437,"complete actual town restored after transaction acceptance")
	report.final_record_count=doc.records.size();report.final_house_count=editor._buildings.instances().size()
	await after_town_transactions(model_id,model_record,pristine)
	await finish()

func after_town_transactions(_model_id:String,_model_record:Dictionary,_pristine:Dictionary)->void:
	# Optional test-only extension. The ordinary 113-check town run is unchanged.
	pass
