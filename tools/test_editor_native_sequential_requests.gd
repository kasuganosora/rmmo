extends "res://tools/test_editor_native_asset_requests.gd"
## Regression for completed private-model reuse. Embedded native
## geometry uses the production reader and ownership tracker. The split case
## substitutes only texture upload/ownership; it cannot prove GPU texture reuse.
var observations:Array=[]
var output:=""
var deliveries:Dictionary={}

# Protocol probe: model another owner's release precisely inside get_ref,
# without a timing-sensitive worker or any production lifecycle hook.
class WeakBorrowProbe extends RefCounted:
	var reference:WeakRef
	var held:PackedScene
	var drop_on_get:=false
	var reads:=0
	func get_ref()->Variant:
		reads+=1
		var borrowed:Variant=reference.get_ref()
		if drop_on_get:held=null
		return borrowed

func borrow_probe(reference:WeakRef,last_owner:bool)->WeakBorrowProbe:
	var probe:=WeakBorrowProbe.new();probe.reference=reference;probe.drop_on_get=last_owner
	if last_owner:probe.held=reference.get_ref()
	return probe

func borrow_lifetime_case(kind:String)->void:
	var model:=fixture("borrow_"+kind,false)
	var host:=Host.new();root.add_child(host)
	var consumer:=Node.new();host.add_child(consumer)
	var service:Node=load(ServicePath).for_consumer(consumer)
	var pool:=ControlledPool.new();configure(service,pool)
	var first:=await capture_scene(service,consumer,host,model.path)
	check(first.get("ok",false),kind+": probe starts from real adopted native allocation")
	await quiet(service,pool)
	var candidate:=Assets.native_candidate(model.path,content_root)
	var key:String=service._private_key(model.path,candidate)
	var probe:=borrow_probe(first.packed,kind=="invalid_last_borrow")
	service._private_models[key].packed=probe
	if kind=="prune":
		service._prune_private()
		check(probe.reads==0,"dead-index cleanup never acquires a temporary resource reference")
	elif kind=="candidate_mismatch":
		var changed:=candidate.duplicate(true);changed.estimated_bytes*=2
		check(service._borrow_private(model.path,changed)==null,"different candidate cannot borrow old allocation")
		check(probe.reads==0,"candidate mismatch is rejected before acquiring its old resource")
	else:
		invalidate_template(first.packed,"identity_metadata")
		Drainer.dispose_scene(first.scene);first.scene=null
		await quiet(service,pool)
		var allocation:int=int(first.packed_id)
		check(is_instance_id_valid(allocation),"external probe owner is alive before final borrow")
		check(service._borrow_private(model.path,candidate)==null and probe.reads==1,"invalid final borrow is rejected after the other owner releases")
		var retirement:Node=root.get_node_or_null("ResourceRetirement")
		check(is_instance_id_valid(allocation) and retirement!=null and retirement.known.has(allocation),"rejected final borrow transfers to existing sliced retirement before local release")
	var references:Array=[first.packed,first.mesh];var scenes:Array=[]
	if is_instance_valid(first.scene):scenes.append(first.scene)
	first={};clear_owned(scenes,[]);await quiet(service,pool);await retired(PublishedGeometry.for_tree(self),references)
	check(references.all(func(reference:WeakRef):return expired(reference)),kind+": probe leaves no native owners")
	observations.append({"case":"borrow_"+kind,"get_ref_calls":probe.reads,"final_published":PublishedGeometry.for_tree(self).report()})
	service.close();host.free();await process_frame

func expired(reference:WeakRef)->bool:return reference.get_ref()==null

func quiet(service:Node,pool:ControlledPool)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		var retirement:Node=root.get_node_or_null("ResourceRetirement")
		if service.snapshot().requests==0 and service.snapshot().bundles==0 and service.snapshot().groups==0 and service.snapshot().batches==0 and service.ledger.count()==0 and pool.snapshot().consumers==0 and (retirement==null or retirement.pending.is_empty()):return
		await process_frame
	check(false,"finite request and retirement queues become quiet")

func clear_owned(scenes:Array,handles:Array)->void:
	for scene:Node in scenes:Drainer.dispose_scene(scene)
	scenes.clear();handles.clear();replies.clear()
	Drainer.synchronize_transfer()

func retired(tracker:Node,refs:Array)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		tracker.collect_retired(100)
		if tracker.report().entries==0 and refs.all(func(reference:WeakRef):return expired(reference)):return
		await process_frame
	check(false,"all private models and published ownership retire")

func native_reads(trace:Dictionary)->int:
	var count_:=0
	for row:Dictionary in trace.get("stats",[]):
		if row.label=="compiled.native_read":count_+=int(row.count)
	return count_

func scene_received(id:int,result:Dictionary,host:Node,path:String,keep_handles:bool,handles:Array)->void:
	if not result.get("ok",false):deliveries[id]={"ok":false};return
	var handle:Variant=result.handles[path]
	var scene:Node3D=handle.instantiate()
	if scene==null:deliveries[id]={"ok":false};return
	host.add_child(scene)
	if keep_handles:handles.append(handle)
	# Like the real preview callback, retain a Node and scalar/weak observations,
	# never its callback result. An awaited result can linger in the test VM.
	deliveries[id]={"ok":true,"scene":scene,"retains_packed":scene.get_meta("_compiled_resource_owner")==handle.packed,"packed_id":str(handle.packed.get_instance_id()),"mesh_id":str(scene.get_child(0).mesh.get_instance_id()),"packed":weakref(handle.packed),"mesh":weakref(scene.get_child(0).mesh),"handle":weakref(handle)}

func wait_scene(id:int)->Dictionary:
	var deadline:=Time.get_ticks_msec()+5000
	while not deliveries.has(id) and Time.get_ticks_msec()<deadline:await process_frame
	return deliveries.get(id,{})

func change_candidate(path:String)->Dictionary:
	var index:=Compiled.index_path(path,content_root)
	var value:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index));value.source_sha="b".repeat(64)
	write(index,JSON.stringify(value))
	var descriptor:=Footprint.descriptor_path(path,content_root)
	var wrapper:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor))
	var body:Dictionary=JSON.parse_string(wrapper.body);body.source_sha=value.source_sha
	wrapper.body=JSON.stringify(body);wrapper.sha256=str(wrapper.body).sha256_text();write(descriptor,JSON.stringify(wrapper))
	return Assets.native_candidate(path,content_root)

func change_budget(path:String)->Dictionary:
	var descriptor:=Footprint.descriptor_path(path,content_root)
	var wrapper:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor))
	var body:Dictionary=JSON.parse_string(wrapper.body)
	body.estimated_bytes*=2;body.resident_bytes=body.estimated_bytes
	wrapper.body=JSON.stringify(body);wrapper.sha256=str(wrapper.body).sha256_text();write(descriptor,JSON.stringify(wrapper))
	return Assets.native_candidate(path,content_root)

func invalidate_template(reference:WeakRef,kind:String)->void:
	var packed:PackedScene=reference.get_ref()
	match kind:
		"not_ready":packed.remove_meta(Ready.READY_META)
		"geometry_only":packed.set_meta(Ready.GEOMETRY_ONLY_META,true)
		"identity_metadata":packed.set_meta("_rmmo_native_payload_sha","c".repeat(64))

func capture_scene(service:Node,consumer:Node,host:Node,path:String)->Dictionary:
	var id:int=service.request_many([path],consumer,scene_received.bind(host,path,false,[]))
	var result:Dictionary=await wait_scene(id)
	deliveries.erase(id)
	return result

func index_consistent(service:Node)->bool:
	if service._private_models.size()!=service._private_order.size():return false
	for slot:int in service._private_order.size():
		var key:String=service._private_order[slot]
		if not service._private_models.has(key) or service._private_models[key].slot!=slot:return false
	return service._private_cursor==0 if service._private_order.is_empty() else service._private_cursor>=0 and service._private_cursor<service._private_order.size()

func invalidation_case(kind:String)->void:
	var model:=fixture("invalidate_"+kind,kind=="not_ready")
	var host:=Host.new();root.add_child(host)
	var consumer:=Node.new();host.add_child(consumer)
	var service:Node=load(ServicePath).for_consumer(consumer)
	var pool:=ControlledPool.new();configure(service,pool)
	var candidate:=Assets.native_candidate(model.path,content_root)
	var first:=await capture_scene(service,consumer,host,model.path)
	check(first.get("ok",false),kind+": initial adopted template is available")
	if not first.get("ok",false):service.close();host.free();return
	await quiet(service,pool)
	if kind=="budget_candidate":
		var changed:=change_budget(model.path)
		check(changed!=candidate and service._identity(model.path,changed,content_root)!=service._identity(model.path,candidate,content_root),"budget changes create a separate complete preparation identity")
	else:invalidate_template(first.packed,kind)
	var second:=await capture_scene(service,consumer,host,model.path)
	check(second.get("ok",false) and second.packed_id!=first.packed_id and service.profile.producers==2,kind+": invalid private row cannot be reused")
	check(service.snapshot().private_templates==(2 if kind=="budget_candidate" else 1) and index_consistent(service),kind+": distinct live candidates retain only correctly indexed weak entries")
	check(Ready.scene_ready(first.scene) and Ready.scene_ready(second.scene),kind+": original instance survives while replacement is ready")
	var references:Array=[first.packed,first.mesh,second.packed,second.mesh]
	var scenes:Array=[first.scene,second.scene];first={};second={}
	clear_owned(scenes,[]);await quiet(service,pool);await retired(PublishedGeometry.for_tree(self),references)
	service.close();check(service.snapshot().private_templates==0,"close drops scalar/weak index rows")
	host.free();await process_frame

func warm_cancel_cases()->void:
	var model:=fixture("warm_cancel",false)
	var host:=Host.new();root.add_child(host)
	var original:=Node.new();host.add_child(original)
	var service:Node=load(ServicePath).for_consumer(original)
	var pool:=ControlledPool.new();configure(service,pool)
	var first:=await capture_scene(service,original,host,model.path)
	check(first.get("ok",false),"warm cancellation retains original native scene")
	await quiet(service,pool)
	for kind:String in ["cancel","owner_exit","close"]:
		var consumer:=Node.new();host.add_child(consumer)
		var before:int=service.profile.producers
		var id:int=service.request_many([model.path],consumer,received)
		match kind:
			"cancel":check(service.cancel(id),"warm deferred request is cancellable")
			"owner_exit":consumer.free()
			"close":service.close()
		await process_frame;await quiet(service,pool)
		check(not replies.has(id) and service.profile.producers==before,kind+": warm cancelled request delivers nothing and starts no producer")
		check(not expired(first.packed) and Ready.scene_ready(first.scene),kind+": cancellation preserves the unrelated original instance")
		if is_instance_valid(consumer):consumer.free()
	check(service.snapshot().private_templates==0 and not service.is_processing(),"closed service has no private index or polling")
	var refs:Array=[first.packed,first.mesh];var scenes:Array=[first.scene];first={}
	clear_owned(scenes,[]);await quiet(service,pool);await retired(PublishedGeometry.for_tree(self),refs)
	host.free();await process_frame

func geometry_product(path:String)->void:
	var candidate:=Assets.native_candidate(path,content_root)
	var raw:PackedScene=ResourceLoader.load(candidate.product,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var query:Node3D=raw.instantiate();query.set_meta(Ready.GEOMETRY_ONLY_META,true)
	var packed:=PackedScene.new();check(packed.pack(query)==OK,"pack explicit geometry-query product");query.free()
	var staging:=Compiled.directory(content_root).path_join("geometry_query.scn")
	check(ResourceSaver.save(packed,staging,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save explicit geometry-query product")
	var digest:=FileAccess.get_sha256(staging)
	var product:=Compiled.directory(content_root).path_join(digest+".scn")
	check(DirAccess.rename_absolute(staging,product)==OK,"publish explicit geometry-query fixture")
	var size:=FileAccess.get_file_as_bytes(product).size()
	var index:=Compiled.index_path(path,content_root)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index));manifest.payload_sha=digest;manifest.bytes=size
	write(index,JSON.stringify(manifest))
	var descriptor:=Footprint.descriptor_path(path,content_root)
	var wrapper:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor))
	var body:Dictionary=JSON.parse_string(wrapper.body);body.payload_sha=digest;body.bytes=size
	wrapper.body=JSON.stringify(body);wrapper.sha256=str(wrapper.body).sha256_text();write(descriptor,JSON.stringify(wrapper))

func reject_geometry_product()->void:
	var model:=fixture("geometry_product",false);geometry_product(model.path)
	var host:=Host.new();root.add_child(host)
	var consumer:=Node.new();host.add_child(consumer)
	var service:Node=load(ServicePath).for_consumer(consumer)
	var pool:=ControlledPool.new();configure(service,pool)
	var id:int=service.request_many([model.path],consumer,received)
	var result:Dictionary=await wait_reply(id)
	check(not result.get("ok",true),"geometry-query root never publishes a rendering handle")
	check(service.snapshot().private_templates==0 and PublishedGeometry.for_tree(self).report().entries==0,"geometry-query product never enters adopted weak index or baseline")
	result={};replies.clear();await quiet(service,pool)
	service.close();host.free();await process_frame

func cursor_churn()->void:
	var host:=Host.new();root.add_child(host)
	var consumer:=Node.new();host.add_child(consumer)
	var service:Node=load(ServicePath).for_consumer(consumer)
	var pool:=ControlledPool.new();configure(service,pool)
	var live:Array=[];var refs:Array=[];var paths:Array=[]
	for index:int in 145:
		var model:=fixture("cursor_%d"%index,false);paths.append(model.path)
		var before:int=service.profile.private_scanned
		var result:=await capture_scene(service,consumer,host,model.path)
		check(result.get("ok",false),"churn %d: native allocation is prepared"%index)
		live.append(result.scene);refs.append(result.packed);result={}
		await quiet(service,pool)
		check(service.profile.private_scanned-before<=service.PRIVATE_PRUNE_STEP*2 and index_consistent(service),"churn %d: cleanup visits fixed small steps with a valid cursor"%index)
	check(service.snapshot().private_templates==145,"all 145 live native owners remain discoverable without a size eviction threshold")
	var released:Array=[]
	for index:int in 145:
		if index%36!=0:Drainer.dispose_scene(live[index]);live[index]=null;released.append(refs[index])
	Drainer.synchronize_transfer();await quiet(service,pool)
	check(released.all(func(reference:WeakRef):return expired(reference)),"released churn owners are dead before index cleanup")
	for index:int in 96:
		var slot:int=(index%5)*36
		var before:int=service.profile.private_scanned
		var id:int=service.request_many([paths[slot]],consumer,received)
		check(service.cancel(id),"churn hit can cancel before delivery")
		await quiet(service,pool)
		check(service.profile.private_scanned-before<=service.PRIVATE_PRUNE_STEP and index_consistent(service),"warm churn cleanup is bounded and cursor survives swap-removal")
	check(service.profile.producers==145 and service.snapshot().private_templates==5,"dead rows retire incrementally while every live anchor reuses its allocation")
	var scans:int=service.profile.private_scanned
	for _index:int in 10:await process_frame
	check(service.profile.private_scanned==scans and not service.is_processing(),"idle service neither scans the index nor polls scene resources")
	var remaining:Array=[]
	for scene:Variant in live:
		if is_instance_valid(scene):remaining.append(scene)
	live.clear();clear_owned(remaining,[]);await quiet(service,pool);await retired(PublishedGeometry.for_tree(self),refs)
	service.close();check(service.snapshot().private_templates==0 and index_consistent(service),"close clears only weak index metadata after churn")
	host.free();await process_frame

func sequential(label:String,keep_handles:bool,split:bool)->void:
	var model:=fixture(label,split)
	var host:=Host.new();root.add_child(host)
	var consumer:=Node.new();host.add_child(consumer)
	var service:Node=load(ServicePath).for_consumer(consumer)
	var pool:=ControlledPool.new();configure(service,pool)
	var tracker:Node=PublishedGeometry.for_tree(self)
	var initial_baseline:int=tracker.report().published_envelope_bytes
	var candidate:=Assets.native_candidate(model.path,content_root)
	check(not candidate.is_empty() and not FileAccess.file_exists(model.path),label+": real published native candidate has no authoring GLB")
	var steps:Array=[];var scenes:Array=[];var handles:Array=[];var packed_refs:Array=[];var mesh_refs:Array=[]
	var packed_ids:Array=[];var mesh_ids:Array=[];var handle_refs:Array=[];var total_reads:=0
	for index:int in 3:
		Trace.minimum_event_us=0;Trace.start()
		var id:int=service.request_many([model.path],consumer,scene_received.bind(host,model.path,keep_handles,handles))
		var during:Dictionary=service.ledger.snapshot()
		var published_during:Dictionary=tracker.report()
		var result:Dictionary=await wait_scene(id)
		var trace:=Trace.stop();var reads:=native_reads(trace);total_reads+=reads
		check(result.get("ok",false),label+": sequential consumer %d completes"%index)
		if not result.get("ok",false):break
		var scene:Node3D=result.scene
		check(scene!=null and Ready.scene_ready(scene),label+": sequential instance is READY")
		check(result.retains_packed,label+": instance retains its private adopted PackedScene")
		packed_ids.append(result.packed_id);mesh_ids.append(result.mesh_id)
		packed_refs.append(result.packed);mesh_refs.append(result.mesh);handle_refs.append(result.handle)
		scenes.append(scene);scene=null;result={};deliveries.erase(id)
		await quiet(service,pool)
		check(service.snapshot().groups==0 and service.snapshot().batches==0,label+": completed group and finite texture batch are closed")
		check(keep_handles or expired(handle_refs.back()),label+": original request handle can disappear while scene stays alive")
		check(not expired(packed_refs[0]) and not expired(mesh_refs[0]),label+": first preview geometry is still alive before the next request")
		steps.append({"consumer":["preview","thumbnail","placement"][index],"producers":service.profile.producers,"compiled_native_reads":reads,"packed_id":packed_ids.back(),"mesh_id":mesh_ids.back(),"during_transient":during,"during_published":published_during,"after_transient":service.ledger.snapshot(),"after_published":tracker.report(),"service":service.snapshot()})
	check(service.profile.producers==1,label+": completed live model is prepared only once across sequential consumers")
	check(total_reads==1,label+": completed live model is read from native storage only once")
	check(packed_ids.size()==3 and packed_ids.all(func(id:String):return id==packed_ids[0]),label+": sequential consumers share the exact adopted PackedScene")
	check(mesh_ids.size()==3 and mesh_ids.all(func(id:String):return id==mesh_ids[0]),label+": sequential instances share the exact mesh allocation")
	if not split:
		check(tracker.report().published_envelope_bytes-initial_baseline==candidate.estimated_bytes,label+": one live geometry allocation has one published envelope")
	check(not Assets._scenes.has(model.path),label+": private consumers leave the global template cache empty")
	var record:={"case":label,"split_texture_stub":split,"handle_kept_alive":keep_handles,"candidate_envelope_bytes":candidate.estimated_bytes,"steps":steps,"producers_after_sequential":service.profile.producers,"native_reads_after_sequential":total_reads,"packed_ids":packed_ids,"mesh_ids":mesh_ids,"baseline_after_sequential":tracker.report(),"split_protocol_adoptions":service.ownership_tracker.adoptions,"texture_stub_creations":pool.audit.created}
	if label=="scene_only":
		var before_cancel:int=service.profile.producers
		var cancelled:int=service.request_many([model.path],consumer,received)
		check(service.cancel(cancelled),"live-template pending consumer can cancel independently")
		await quiet(service,pool)
		check(not replies.has(cancelled) and not expired(packed_refs[0]),"cancelled follower has no callback and cannot destroy the earlier preview")
		check(service.profile.producers==before_cancel,"cancelled completed-template lookup starts no duplicate producer")
		record.cancel={"producer_delta":service.profile.producers-before_cancel,"callback_received":replies.has(cancelled),"after_transient":service.ledger.snapshot(),"after_published":tracker.report()}
		var next_candidate:=change_candidate(model.path)
		check(not next_candidate.is_empty() and next_candidate!=candidate,"new candidate identity is visible while original scene stays alive")
		var before_changed:int=service.profile.producers
		var changed:int=service.request_many([model.path],consumer,received)
		var changed_result:Dictionary=await wait_reply(changed)
		check(changed_result.get("ok",false) and changed_result.handles[model.path].current(),"changed candidate gets a current native handle")
		if changed_result.get("ok",false):
			var current:Variant=changed_result.handles[model.path]
			check(str(current.packed.get_instance_id())!=packed_ids[0] and service.profile.producers==before_changed+1,"changed candidate never reuses the prior source allocation")
			var replacement:Node3D=current.instantiate();host.add_child(replacement);scenes.append(replacement)
			packed_refs.append(weakref(current.packed));mesh_refs.append(weakref(replacement.get_child(0).mesh))
			record.changed_candidate={"producer_delta":service.profile.producers-before_changed,"source_sha":current.candidate.source_sha,"packed_id":str(current.packed.get_instance_id())}
			current=null;replacement=null
		changed_result={};replies.erase(changed);await quiet(service,pool)
	var texture_only:Texture2D=scenes[0].get_child(0).mesh.surface_get_material(0).albedo_texture if split else null
	clear_owned(scenes,handles);await quiet(service,pool);await retired(tracker,packed_refs+mesh_refs)
	if split:
		check(texture_only!=null and packed_refs.all(func(reference:WeakRef):return expired(reference)) and mesh_refs.all(func(reference:WeakRef):return expired(reference)),"retaining only a split texture leaf cannot keep native geometry alive")
		record.texture_leaf_only={"texture_still_alive":texture_only!=null,"all_geometry_expired":packed_refs.all(func(reference:WeakRef):return expired(reference))}
	texture_only=null
	check(packed_refs.all(func(reference:WeakRef):return expired(reference)) and mesh_refs.all(func(reference:WeakRef):return expired(reference)),label+": service alone pins neither PackedScene nor geometry")
	check(service.ledger.count()==0 and tracker.report().entries==0 and tracker.report().published_envelope_bytes==0,label+": all temporary and published geometry envelopes return to zero")
	record.after_release={"service":service.snapshot(),"published":tracker.report(),"pool":pool.snapshot()}
	var before_reopen:int=service.profile.producers
	var reopened:int=service.request_many([model.path],consumer,received)
	var reopened_result:Dictionary=await wait_reply(reopened)
	check(reopened_result.get("ok",false) and service.profile.producers==before_reopen+1,label+": expired private allocation requires fresh preparation")
	record.after_expiry={"producer_delta":service.profile.producers-before_reopen,"ok":reopened_result.get("ok",false)}
	reopened_result={};replies.erase(reopened);await quiet(service,pool)
	await retired(tracker,[])
	service.close();host.free();await process_frame
	record.final_published=tracker.report();observations.append(record)

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	output=content_root.get_base_dir().path_join("observations.json")
	create_timer(120).timeout.connect(func():printerr("EDITOR_NATIVE_SEQUENTIAL watchdog");quit(2))
	if OS.get_cmdline_user_args().has("--borrow-probes"):
		for kind:String in ["prune","candidate_mismatch","invalid_last_borrow"]:await borrow_lifetime_case(kind)
		write(output,JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
		print("EDITOR_NATIVE_SEQUENTIAL checks=",checks," failures=",failures)
		quit(0 if failures==0 else 1);return
	await sequential("scene_only",false,false)
	await sequential("handle_alive",true,false)
	await sequential("split_protocol",false,true)
	for kind:String in ["not_ready","geometry_only","identity_metadata","budget_candidate"]:await invalidation_case(kind)
	await warm_cancel_cases()
	await reject_geometry_product()
	await cursor_churn()
	for kind:String in ["prune","candidate_mismatch","invalid_last_borrow"]:await borrow_lifetime_case(kind)
	write(output,JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	print("EDITOR_NATIVE_SEQUENTIAL checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
