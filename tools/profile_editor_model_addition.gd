extends "res://tools/test_world3d_mcp.gd"
const Pose=preload("res://scripts/world3d/pose_save.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const MODEL_NAME="方窗石砌窗套"
const MODEL_PATH="D:/code/rmmo_runtime/packs/default/assets/f1259543701ac5bf03968f2b2d24913c3a3b722dbea543fe43bd2c823311ea8f.glb"
const LIBRARY_PATH="D:/code/rmmo_runtime/packs/default/assets/library.json"
class MeasuredEditor:
	extends "res://scripts/world_editor/world_editor.gd"
	var commit_samples:Array=[]
	func _commit_records(ids:Array)->void:
		var started:=Time.get_ticks_usec()
		super._commit_records(ids)
		commit_samples.append({"ids":ids.duplicate(),"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0})
var report:Dictionary={}
var output_path:String
var temp_map:String
var initial_resources:Dictionary={}
func persist()->void:
	report.failures=failed
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
func save_phase(phase:String)->Dictionary:
	var start:=Time.get_ticks_usec()
	var pending:=await call_tool("save_world",{"background":true})
	check(pending.get("pending",false),phase+" starts actual HTTP background save")
	var next_update:=Time.get_ticks_msec()
	while editor._save_job.active:
		if Time.get_ticks_msec()>=next_update:
			var state:Dictionary=editor._save_job.state()
			print("MODEL_ADDITION_PROGRESS ",phase," ",JSON.stringify({"phase":state.phase,"completed":state.completed,"total":state.total,"elapsed_seconds":state.elapsed_seconds}))
			next_update=Time.get_ticks_msec()+15000
		await process_frame
	var result:Dictionary=editor._save_job.result.duplicate(true)
	var sample:Dictionary={"phase":phase,"endpoint_to_completion_ms":(Time.get_ticks_usec()-start)/1000.0,"result":result}
	report.runs.append(sample);persist()
	print("MODEL_ADDITION_SAVE ",phase," ",JSON.stringify(sample))
	check(result.get("saved",false),phase+" save succeeds")
	return result.get("timings",{}).get("export",{})
func instance_snapshot()->Dictionary:
	var nodes:Dictionary={};var bodies:Dictionary={};var batches:Dictionary={}
	for child:Node in editor._view.get_children():nodes[str(child.name)]=child.get_instance_id()
	for id:String in editor._bodies_by_uuid:
		var values:Array=[]
		for body:Node in editor._bodies_by_uuid[id]:values.append(body.get_instance_id())
		bodies[id]=values
	for key:String in editor._ground_batches.groups:
		var visual:Variant=editor._ground_batches.groups[key].get("visual")
		if is_instance_valid(visual):batches[key]=visual.get_instance_id()
	return {"view":editor._view.get_instance_id(),"nodes":nodes,"bodies":bodies,"batches":batches}
func unchanged_instances(before:Dictionary,after:Dictionary)->Dictionary:
	var changed:Dictionary={"view":before.view!=after.view,"nodes":[],"bodies":[],"batches":[]}
	for domain:String in ["nodes","bodies","batches"]:
		for key:String in before[domain]:
			if before[domain][key]!=after[domain].get(key):changed[domain].append(key)
	check(not changed.view and changed.nodes.is_empty(),"new model preserves all unrelated view node instance IDs")
	check(changed.bodies.is_empty(),"new model preserves all unrelated picking/collision body instance IDs")
	check(changed.batches.is_empty(),"new model preserves existing derived batch visual instance IDs")
	return {"before_counts":{"nodes":before.nodes.size(),"body_sets":before.bodies.size(),"batch_visuals":before.batches.size()},"changes":changed}
func read_resources()->Dictionary:
	var resources:Dictionary=Pose.dependencies(Pose._json(temp_map),temp_map,Paths.external_root(),Io)
	check(resources.ok,"temporary map resources pass complete SHA read")
	return resources.get("files",{})
func verify_retained(phase:String)->void:
	var current:=read_resources();var changes:Array=[]
	for uri:String in initial_resources:
		if current.get(uri)!=initial_resources[uri]:changes.append(uri)
	check(changes.is_empty(),phase+" retains all prior resource URI/SHA pairs")
	report.resource_checks.append({"phase":phase,"original_count":initial_resources.size(),"current_count":current.size(),"changed":changes});persist()
func material_evidence(holder:Node)->Dictionary:
	var result:Dictionary={"meshes":0,"surfaces":0,"materials":0,"textures":0,"valid":holder!=null}
	if holder==null:return result
	for mesh:MeshInstance3D in Paint.meshes(holder):
		result.meshes+=1
		if mesh.mesh==null:result.valid=false;continue
		for slot in mesh.mesh.get_surface_count():
			result.surfaces+=1
			var material:BaseMaterial3D=mesh.get_active_material(slot) as BaseMaterial3D
			if material==null:result.valid=false;continue
			result.materials+=1
			for texture_slot in BaseMaterial3D.TEXTURE_MAX:
				var texture:Texture2D=material.get_texture(texture_slot)
				if texture==null:continue
				result.textures+=1
				var image:=texture.get_image()
				if image==null or image.is_empty():result.valid=false
	result.valid=result.valid and result.meshes>0 and result.materials>0 and result.textures>0
	return result
func run()->void:
	Engine.max_fps=60;root.size=Vector2i(1280,900);root.content_scale_size=root.size;rpc_timeout_ms=30000
	create_timer(2400).timeout.connect(func():quit(2))
	var source:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var signature:=FileAccess.get_sha256(source);var library_sha:=FileAccess.get_sha256(LIBRARY_PATH);var model_sha:=FileAccess.get_sha256(MODEL_PATH)
	var directory:=Paths.cache_directory("town_model_addition_%d"%Time.get_ticks_usec());temp_map=directory.path_join("map.gltf")
	output_path=Art.review_path("editor_model_addition_town_20261007.json")
	var input:=FileAccess.open(MODEL_PATH,FileAccess.READ)
	check(input!=null,"real library model exists")
	var file_bytes:int=input.get_length() if input!=null else 0;input=null
	report={"source":source,"source_sha256":signature,"output":temp_map,"model":{"name":MODEL_NAME,"path":MODEL_PATH,"file_bytes":file_bytes,"sha256":model_sha},"runs":[],"resource_checks":[]}
	print("MODEL_ADDITION_OPEN_SOURCE ",source)
	var started:=Time.get_ticks_usec();var doc=Doc.open_file(source)
	report.source_open_ms=(Time.get_ticks_usec()-started)/1000.0
	check(doc!=null,"open actual town as read-only test input")
	if doc==null:persist();quit(1);return
	var source_paths:Dictionary={};Pose._paths(doc.records,source_paths)
	check(not source_paths.has(MODEL_PATH),"selected library model has never been referenced in current town authoring records")
	if source_paths.has(MODEL_PATH):persist();quit(1);return
	report.initial_records=doc.records.size();persist()
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=temp_map
	editor=MeasuredEditor.new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	started=Time.get_ticks_usec();root.add_child(editor);editor._safety.enabled=false;await settle()
	editor._ground_batches.flush();report.editor_init_ms=(Time.get_ticks_usec()-started)/1000.0
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual town HTTP server on loopback")
	var listed:=await call_tool("list_assets",{"query":MODEL_NAME,"limit":200})
	var candidates:Array=listed.get("assets",[]).filter(func(row):return row.get("name")==MODEL_NAME)
	check(candidates.size()==1,"actual shared library exposes exact chosen model")
	var entries:Array=editor.asset_items(MODEL_NAME).filter(func(row):return row.get("asset_path")==MODEL_PATH)
	check(entries.size()==1,"HTTP choice resolves to inspected real GLB path")
	if candidates.size()!=1 or entries.size()!=1:persist();editor._mcp.stop();editor.queue_free();await settle();quit(1);return
	report.library_entry=entries[0].duplicate(true);report.asset_id=candidates[0].asset_id;persist()
	var baseline:=await save_phase("fresh_full_baseline")
	check(baseline.get("mode")=="full_export","new temporary path establishes baseline through a real full export")
	initial_resources=read_resources();editor._ground_batches.flush()
	var before:=instance_snapshot();editor.commit_samples.clear()
	started=Time.get_ticks_usec()
	var added:=await call_tool("place_asset",{"asset_id":candidates[0].asset_id,"position":[20,0,20]})
	report.add_endpoint_ms=(Time.get_ticks_usec()-started)/1000.0
	report.commit_samples=editor.commit_samples.duplicate(true)
	var ids:Array=added.get("ids",[]);check(ids.size()==1,"library placement creates one independent model instance")
	if ids.size()!=1:persist();editor._mcp.stop();editor.queue_free();await settle();quit(1);return
	var id:String=ids[0];report.new_uuid=id
	await settle();editor._ground_batches.flush()
	report.instances=unchanged_instances(before,instance_snapshot())
	var holder:Node=editor._view.get_node_or_null(NodePath(id))
	report.live_model=material_evidence(holder)
	check(report.live_model.valid,"new editor model has real meshes, PBR materials and readable texture images")
	await call_tool("focus_selection");await settle();await RenderingServer.frame_post_draw
	var screenshot:=Art.review_path("editor_model_addition_town_20261007.png")
	check(root.get_texture().get_image().save_png(screenshot)==OK,"focused private viewport screenshot saved")
	report.screenshot=screenshot;persist()
	var saved:=await save_phase("add_new_library_source")
	check(saved.get("mode")=="incremental_reuse" and saved.get("exported_instances")==1,"new library model exports only its single added instance")
	check(saved.get("added_instances")==1 and saved.get("partial_export",{}).get("meshes")==report.live_model.meshes,"delta export mesh count matches the new model rather than the town")
	verify_retained("new model")
	await call_tool("undo")
	check(doc._find(id).is_empty(),"HTTP undo removes the newly placed model")
	var undone:=await save_phase("undo_model_addition")
	check(undone.get("mode")=="incremental_reuse" and undone.get("images_written",-1)==0,"undo save removes membership without texture export")
	await call_tool("redo")
	check(not doc._find(id).is_empty(),"HTTP redo restores the same model UUID")
	var redone:=await save_phase("redo_model_addition")
	check(redone.get("mode")=="incremental_reuse" and redone.get("exported_instances",0)<=1,"redo save never exports the entire town")
	verify_retained("redo")
	var expected:Dictionary=doc._find(id).duplicate(true);var expected_records:Array=doc.records;var expected_meta:Dictionary=doc.map_meta
	# Free the editor's GPU scene before loading the complete saved native scene.
	# This avoids holding two rendered towns during verification.
	editor._mcp.stop();editor.queue_free();await settle();await RenderingServer.frame_post_draw
	print("MODEL_ADDITION_REOPEN_AUTHORING ",temp_map)
	started=Time.get_ticks_usec();var reopened=Doc.open_file(temp_map);report.reopen_authoring_ms=(Time.get_ticks_usec()-started)/1000.0
	check(reopened!=null and Pose.same(Pose.extras(reopened.records,reopened.map_meta),Pose.extras(expected_records,expected_meta)),"saved temporary town reopens with all records and map metadata")
	check(reopened!=null and Pose.same(reopened._find(id),expected),"new model authoring state survives save/undo/redo/reopen")
	persist();print("MODEL_ADDITION_REOPEN_NATIVE ",temp_map)
	started=Time.get_ticks_usec();var native:=Io.load_scene(temp_map);report.native_load_ms=(Time.get_ticks_usec()-started)/1000.0
	check(native!=null,"complete saved town loads through native glTF importer")
	var native_holder:Node3D=Io.find_named(native,id) if native!=null else null
	report.native_model=material_evidence(native_holder)
	check(native_holder!=null and native_holder.transform.is_equal_approx(Pose.pose(expected)),"native added holder retains exact saved pose and UUID")
	check(report.native_model.valid and report.native_model.meshes==report.live_model.meshes,"native added model retains real mesh and readable material textures")
	if native!=null:native.free()
	report.source_sha256_after=FileAccess.get_sha256(source)
	check(report.source_sha256_after==signature,"formal town source SHA remains unchanged")
	check(FileAccess.get_sha256(MODEL_PATH)==model_sha and FileAccess.get_sha256(LIBRARY_PATH)==library_sha,"real model and asset library remain unchanged")
	persist();print("MODEL_ADDITION_TOWN_FINISHED failures=",failed," report=",output_path)
	quit(0 if failed==0 else 1)
