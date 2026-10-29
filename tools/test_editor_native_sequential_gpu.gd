extends "res://tools/test_editor_native_ui_gpu.gd"
## Real sequential UI consumers over the uninjected service. Observers retain
## scalar identities and WeakRefs only; all preparation/render methods are super.
const WorkTrace=preload("res://scripts/world3d/load_trace.gd")
var owner_refs:Array[WeakRef]=[]
var handle_refs:Array[WeakRef]=[]
var third:Node3D
var third_result:Dictionary={}
var late_callbacks:Array[int]=[]

class SequencePreview extends "res://scripts/world_editor/asset_preview.gd":
	var handles:Array[WeakRef]=[]
	func _prepared(id:int,result:Dictionary,generation:int,prefab:Dictionary)->void:
		for handle:Variant in result.get("handles",{}).values():handles.append(weakref(handle))
		super._prepared(id,result,generation,prefab)

class SequenceThumbnail extends "res://scripts/world_editor/asset_thumbnails.gd":
	var handles:Array[WeakRef]=[]
	var observe:Callable
	func _model_prepared(id:int,result:Dictionary,serial:int,entry:Dictionary,prefab:Dictionary,importing:bool)->void:
		for handle:Variant in result.get("handles",{}).values():handles.append(weakref(handle))
		super._model_prepared(id,result,serial,entry,prefab,importing)
	func _present_model(model:Node3D,key:String,importing:bool)->void:
		super._present_model(model,key,importing)
		if model!=null:observe.call("bound",self)
	func _finish(serial:int)->void:
		if serial==_render_serial and is_inside_tree() and is_instance_valid(_model):observe.call("capture",self)
		super._finish(serial)

func allocation_ids(scene:Node3D)->Dictionary:
	var packed:PackedScene=scene.get_meta("_compiled_resource_owner")
	var mesh:Mesh=scene.get_child(0).mesh
	var texture:=texture_of(scene)
	return {"packed":str(packed.get_instance_id()),"mesh":str(mesh.get_instance_id()),"texture":str(texture.get_instance_id()),"rid":str(texture.get_rid().get_id()),"class":texture.get_class(),"active":texture.call("is_streaming_active"),"mip":texture.call("get_streaming_mip_level")}

func observe_owners(scene:Node3D)->void:
	owner_refs.append(weakref(scene.get_meta("_compiled_resource_owner")))
	owner_refs.append(weakref(scene.get_child(0).mesh))
	owner_refs.append(weakref(texture_of(scene)))

func same_ids(a:Dictionary,b:Dictionary)->bool:
	return ["packed","mesh","texture","rid"].all(func(key:String):return a[key]==b[key])

func dead(reference:WeakRef)->bool:return reference.get_ref()==null

func thumbnail_sequence(stage:String,thumbnail:SequenceThumbnail)->void:
	observations["thumbnail_"+stage]=allocation_ids(thumbnail._model)
	if stage=="bound":
		observe_owners(thumbnail._model)
		baselines.thumbnail=baseline_for(thumbnail._viewport,thumbnail._camera)
	else:
		captures.thumbnail_settled=thumbnail._viewport.get_texture().get_image()
		observations.thumbnail_readiness=thumbnail._readiness.snapshot()

func third_ready(_id:int,result:Dictionary,path:String)->void:
	third_result={"ok":result.get("ok",false)}
	if not third_result.ok:return
	var handle:Variant=result.handles[path];handle_refs.append(weakref(handle))
	third=handle.instantiate()
	if third==null:third_result.ok=false;return
	ui_host.add_child(third);observe_owners(third)
	third_result.ids=allocation_ids(third)

func late_reply(id:int,_result:Dictionary)->void:late_callbacks.append(id)

func wait_finite()->void:
	var deadline:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		var retirement:Node=root.get_node_or_null("ResourceRetirement")
		var state:Dictionary=service.snapshot()
		if state.requests==0 and state.bundles==0 and state.groups==0 and state.batches==0 and state.ledger.reserved_bytes==0 and (retirement==null or retirement.pending.is_empty()):return
		await process_frame
	check(false,"finite service and retirement queues settle")

func wait_preview(preview:SequencePreview)->void:
	var deadline:=Time.get_ticks_msec()+20000
	while (preview.scene==null or preview._readiness.active()) and Time.get_ticks_msec()<deadline:await process_frame
	check(preview.scene!=null and preview._readiness.snapshot().state=="complete","real preview reaches its finite verified presentation")

func read_count(trace:Dictionary)->int:
	var amount:=0
	for row:Dictionary in trace.get("stats",[]):
		if row.label=="compiled.native_read":amount+=int(row.count)
	return amount

func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root()
	if not folder.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(150).timeout.connect(func():printerr("EDITOR_SEQUENTIAL_GPU watchdog");quit(2))
	Paint.refresh_sources();Prep.Pixels.Policy.verify_packages=false
	original=fixture();var prepared:=Products.prepare(original,folder)
	check(prepared.ok and prepared.stats.textures==1,"sequence uses one actual multi-mip STEX product")
	var path:=publish_fixture(original,prepared,"sequential_ui")
	Products.restore(prepared);prepared.clear()
	ui_host=Host.new();root.add_child(ui_host)
	var preview:=SequencePreview.new();preview.size=Vector2(384,288);ui_host.add_child(preview)
	var thumbnail:=SequenceThumbnail.new();thumbnail.observe=thumbnail_sequence;ui_host.add_child(thumbnail)
	service=Service.for_consumer(preview);tracker=Ownership.for_tree(self)
	check(service.native_texture_pool==null and not service.native_texture_preparer.is_valid() and service.ownership_tracker==null,"sequential GPU uses all production preparation and ownership paths")
	var cache_before:=Assets._scenes.size()
	WorkTrace.minimum_event_us=0;WorkTrace.start()
	preview.show_asset(path)
	var batch:Dictionary=service._batches.values()[0];var helper:RefCounted=batch.native;batch={}
	await wait_preview(preview);await wait_finite()
	if preview.scene==null:finish();return
	observations.preview=allocation_ids(preview.scene);observe_owners(preview.scene)
	handle_refs.append_array(preview.handles)
	check(handle_refs.all(dead),"original preview handle is gone while its scene owns the adopted template")
	check(observations.preview["class"]=="StreamedTexture2D" and observations.preview.active,"preview owns a real engine-registered StreamedTexture2D")
	report.after_preview={"service":service.snapshot(),"published":tracker.report(),"native":helper.snapshot()}
	baselines.preview=baseline_for(preview.viewport_,preview.camera)
	await process_frame;await RenderingServer.frame_post_draw
	captures.preview_settled=preview.viewport_.get_texture().get_image()
	captures.preview_source=baselines.preview.get_texture().get_image()
	check(mismatch(captures.preview_settled,captures.preview_source)==0,"settled sequential preview equals source pixels")
	var png:=folder.path_join("sequential_thumbnail.png")
	thumbnail.queue_import({"asset_path":path,"thumbnail_path":png})
	var deadline:=Time.get_ticks_msec()+20000
	while not FileAccess.file_exists(png) and Time.get_ticks_msec()<deadline:await process_frame
	check(FileAccess.file_exists(png) and observations.has("thumbnail_capture"),"later actual thumbnail queue saves a completed PNG")
	if not FileAccess.file_exists(png):finish();return
	await wait_finite();handle_refs.append_array(thumbnail.handles)
	check(same_ids(observations.preview,observations.thumbnail_bound) and same_ids(observations.preview,observations.thumbnail_capture),"later real thumbnail shares exact PackedScene mesh texture and RID")
	captures.thumbnail_png=Image.load_from_file(png)
	captures.thumbnail_source=baselines.thumbnail.get_texture().get_image()
	check(mismatch(captures.thumbnail_png,captures.thumbnail_source)==0,"sequential persisted thumbnail equals source pixels")
	report.after_thumbnail={"service":service.snapshot(),"published":tracker.report(),"native":helper.snapshot()}
	var consumer:=Node.new();ui_host.add_child(consumer)
	service.request_many([path],consumer,third_ready.bind(path))
	deadline=Time.get_ticks_msec()+10000
	while third_result.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(third_result.get("ok",false) and Ready.scene_ready(third),"third real service consumer instantiates an already-ready native model")
	await wait_finite()
	check(same_ids(observations.preview,third_result.ids),"third sequential instance shares every original allocation identity")
	report.sequential_native_reads=read_count(WorkTrace.stop())
	report.after_three={"service":service.snapshot(),"published":tracker.report(),"native":helper.snapshot()}
	check(service.profile.producers==1 and report.sequential_native_reads==1 and service.profile.table_reads==1,"three sequential consumers perform one geometry production read and table load")
	check(helper.snapshot().pool.produced==1 and helper.snapshot().pool.streamed_loads==1,"three sequential consumers create and register one actual STEX allocation")
	check(tracker.report().entries==1 and tracker.report().published_envelope_bytes==67108864 and tracker.report().peak_published_envelope_bytes==67108864,"one adopted native geometry allocation keeps exactly one published envelope")
	check(handle_refs.all(dead),"all completed request handles expire while live scenes retain shared geometry")
	check(Assets._scenes.size()==cache_before,"sequential UI consumers add no global template cache entries")
	for action:String in ["cancel","owner_exit"]:
		var owner:=Node.new();ui_host.add_child(owner)
		var request:int=service.request_many([path],owner,late_reply)
		if action=="cancel":check(service.cancel(request),"warm GPU request can cancel before deferred delivery")
		else:owner.free()
		await process_frame;await wait_finite()
		check(not late_callbacks.has(request) and service.profile.producers==1,action+": no late callback or duplicate native producer")
		check(same_ids(observations.preview,allocation_ids(preview.scene)) and same_ids(observations.preview,allocation_ids(third)),action+": original live consumers keep their exact native owners")
		if is_instance_valid(owner):owner.free()
	for label:String in captures:capture_file(label,captures[label])
	preview.free();thumbnail.free();consumer.free()
	for view:SubViewport in baselines.values():view.free()
	baselines.clear();await wait_finite()
	check(same_ids(observations.preview,allocation_ids(third)) and tracker.report().entries==1,"last ordinary scene survives both UI owners and retirement")
	Drainer.dispose_scene(third);third=null;await wait_clean("after_all_sequence_owners");await wait_finite()
	check(owner_refs.all(dead) and handle_refs.all(dead),"all first-generation PackedScene mesh texture and Handle weak references expire")
	WorkTrace.start()
	var reopened:=SequencePreview.new();reopened.size=Vector2(384,288);ui_host.add_child(reopened)
	reopened.show_asset(path)
	batch=service._batches.values()[0];var fresh_helper:RefCounted=batch.native;batch={}
	await wait_preview(reopened);await wait_finite()
	observations.reopened=allocation_ids(reopened.scene);observe_owners(reopened.scene);handle_refs.append_array(reopened.handles)
	report.reopened_native_reads=read_count(WorkTrace.stop())
	check(service.profile.producers==2 and report.reopened_native_reads==1,"expired model starts one genuinely fresh native producer")
	check(["packed","mesh","texture","rid"].all(func(key:String):return observations.reopened[key]!=observations.preview[key]),"cold reopen gets new PackedScene mesh texture and RID identities")
	check(fresh_helper.snapshot().pool.produced==1 and fresh_helper.snapshot().pool.streamed_loads==1 and service.profile.table_reads==2,"cold reopen reads and registers one fresh STEX after original release")
	check(tracker.report().entries==1 and tracker.report().published_envelope_bytes==67108864,"reopen replaces the expired baseline instead of accumulating it")
	report.after_reopen={"service":service.snapshot(),"published":tracker.report(),"native":fresh_helper.snapshot()}
	reopened.free();await wait_clean("after_reopen_close");await wait_finite()
	check(owner_refs.all(dead) and handle_refs.all(dead) and Assets._scenes.size()==cache_before,"final observers and service retain no resource owners or global cache entries")
	report.observations=observations;report.third=third_result
	report.final=service.snapshot();ui_host.free();original.free();original=null
	finish()
