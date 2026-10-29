extends "res://tools/test_editor_native_texture_join.gd"
## Cold editor consumers, private-template ownership and request cancellation.
## Native geometry/table IO is real; split upload/ownership use explicit stubs.
const ServicePath:="res://scripts/world_editor/editor_asset_preparation.gd"
const Preview=preload("res://scripts/world_editor/asset_preview.gd")
const Prefabs=preload("res://scripts/world_editor/prefab_library.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const PublishedGeometry=preload("res://scripts/world_editor/prepared_model_ownership.gd")
var replies:Dictionary={}

# Stub split pixels cannot satisfy the production StreamedTexture2D identity
# proof. This records only the ownership handoff protocol; embedded products
# delegate to the real tracker. Real split adoption belongs to the GPU test.
class OwnershipProtocol extends Node:
	var ledger:RefCounted
	var preflights:=0
	var adoptions:=0
	var charged:=true
	var owners:Array=[]
	func preflight(candidate:Dictionary,packet:Dictionary,bound:int)->Dictionary:
		if not candidate.has("texture_table"):
			return PublishedGeometry.for_tree(get_tree()).preflight(candidate,packet,bound)
		preflights+=1;charged=charged and ledger.reserved_bytes>=bound
		return {"ok":true,"ticket":{"packed":weakref(packet.packed),"source":candidate.source_sha,"bytes":bound}}
	func adopt(ticket:Variant)->Dictionary:
		if not ticket is Dictionary:return PublishedGeometry.for_tree(get_tree()).adopt(ticket)
		var packed:PackedScene=ticket.packed.get_ref()
		adoptions+=1;charged=charged and ledger.reserved_bytes>=ticket.bytes
		owners.append(ticket.packed)
		return {"ok":packed!=null and packed.get_meta("_rmmo_source_digest","")==ticket.source}

func configure(service:Node,pool:ControlledPool)->void:
	service.native_texture_pool=pool;service.native_texture_preparer=pixels
	var protocol:=OwnershipProtocol.new();protocol.ledger=service.ledger
	service.add_child(protocol);service.ownership_tracker=protocol

func fixture(name_:String,split:bool)->Dictionary:
	var model:Dictionary=super.fixture(name_,split)
	# The ownership contract requires the real converter's SHA-shaped generator.
	var index:=Compiled.index_path(model.path,content_root)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index));manifest.generator=SHA
	write(index,JSON.stringify(manifest))
	var descriptor:=Footprint.descriptor_path(model.path,content_root)
	var wrapper:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor))
	var body:Dictionary=JSON.parse_string(wrapper.body);body.generator=SHA
	wrapper.body=JSON.stringify(body);wrapper.sha256=str(wrapper.body).sha256_text();write(descriptor,JSON.stringify(wrapper))
	return model

class ThumbnailProbe extends "res://scripts/world_editor/asset_thumbnails.gd":
	var results:Array=[]
	func _present_model(model:Node3D,key:String,_importing:bool)->void:
		results.append({"key":key,"scene":model});_busy=false
	func clear_models()->void:
		for result:Dictionary in results:
			if result.scene!=null:preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(result.scene)
		results.clear()

func received(id:int,result:Dictionary)->void:replies[id]=result
func wait_reply(id:int)->Dictionary:
	var deadline:=Time.get_ticks_msec()+5000
	while not replies.has(id) and Time.get_ticks_msec()<deadline:await process_frame
	return replies.get(id,{})
func settle(ledger:RefCounted,pool:ControlledPool)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while (ledger.count()>0 or pool.snapshot().consumers>0) and Time.get_ticks_msec()<deadline:await process_frame
	check(ledger.count()==0 and ledger.reserved_bytes==0,"request retirement returns shared ledger to zero")
	check(pool.snapshot().consumers==0 and pool.snapshot().outputs==0,"finite request batch releases native pool consumers")
	check(ledger.byte_limit==4*1024*1024*1024,"metadata deductions restore exactly the configured allowance")

func blocked_case(label:String)->void:
	var model:=fixture(label,true);var embedded:=fixture(label+"_next",false)
	var host:=Host.new();root.add_child(host);var preview:=Preview.new();host.add_child(preview)
	var service:Node=load(ServicePath).for_consumer(preview);var pool:=ControlledPool.new();pool.hold=true
	configure(service,pool)
	var id:=0
	if label=="switch":preview.show_asset(model.path)
	else:id=service.request(model.path,preview,received)
	var deadline:=Time.get_ticks_msec()+5000
	while not pool.has_entered() and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.has_entered(),label+": real preparation worker is blocked in native upload")
	var began:=Time.get_ticks_msec()
	if label=="switch":preview.show_asset(embedded.path)
	elif label=="close":host.remove_child(preview);preview.free();service.close()
	elif label=="owner_exit":preview.free()
	else:check(service.cancel(id),label+": last subscriber cancellation accepted")
	check(Time.get_ticks_msec()-began<500,label+": cancellation/close does not join the blocked worker")
	await process_frame
	check(host._shared_preparation_ledger.count()>0,label+": detached running worker retains its charged lease")
	pool.gate.post()
	await settle(host._shared_preparation_ledger,pool)
	if label=="switch":
		deadline=Time.get_ticks_msec()+5000
		while preview.scene==null and Time.get_ticks_msec()<deadline:await process_frame
		check(preview.scene!=null and preview.current_path==embedded.path and not preview.scene.has_meta(Binding.TABLE_META),"selection generation shows only the replacement asset")
		preview.show_asset("")
	else:check(not replies.has(id),label+": obsolete consumer never receives completion")
	check(service.snapshot().groups==0 and service.snapshot().batches==0,label+": finite groups and batches retire")
	host.free();replies.clear();await process_frame

func leader_cancel_case()->void:
	var first:=fixture("leader_cancel_a",true);var second:=fixture("leader_cancel_b",true)
	var host:=Host.new();root.add_child(host);var consumer:=Node.new();host.add_child(consumer)
	var service:Node=load(ServicePath).for_consumer(consumer);var pool:=ControlledPool.new();pool.hold=true
	configure(service,pool)
	var a:int=service.request(first.path,consumer,received);var b:int=service.request(second.path,consumer,received)
	var deadline:=Time.get_ticks_msec()+5000
	while (not pool.has_entered() or int(pool.snapshot().waits)==0) and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.has_entered() and int(pool.snapshot().waits)>0,"different model follower waits for the shared texture leader")
	check(service.cancel(a),"cancel only the leader model's consumer")
	pool.gate.post()
	var result:Dictionary=await wait_reply(b)
	check(result.get("ok",false) and result.handle.ready(),"cancelled model producer still serves another model's active subscriber")
	check(not replies.has(a) and pool.audit.created==1,"cancelled leader is not published and texture production stays unique")
	result={};replies.clear();await settle(host._shared_preparation_ledger,pool)
	host.free();await process_frame
	deadline=Time.get_ticks_msec()+5000
	while pool.audit.releases.size()<pool.audit.created and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.audit.releases.size()==pool.audit.created,"last private handle releases every produced native texture")
	check(pool.audit.releases.all(func(thread_id):return thread_id==OS.get_main_thread_id()),"final private texture destruction remains on main")

func thumbnail_scroll_case(explicit_repair:bool)->void:
	var model:=fixture("thumbnail_explicit" if explicit_repair else "thumbnail_idle",true)
	var entry:={"asset_path":model.path};var host:=Host.new();root.add_child(host)
	var thumbnail:=ThumbnailProbe.new();host.add_child(thumbnail);thumbnail.set_process(false)
	var service:Node=load(ServicePath).for_consumer(thumbnail);var pool:=ControlledPool.new();pool.hold=true
	configure(service,pool)
	thumbnail._key=model.path;thumbnail._busy=true;thumbnail._active_idle=true;thumbnail._attempted[model.path]=true
	thumbnail._prepare_entry(entry,true)
	var deadline:=Time.get_ticks_msec()+5000
	while not pool.has_entered() and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.has_entered(),"thumbnail preparation reaches the shared worker")
	if explicit_repair:thumbnail.queue_import(entry)
	thumbnail.set_visible_entries([])
	if explicit_repair:check(thumbnail._busy and not thumbnail._active_idle,"explicit repair promotes a running idle job and survives scroll-away")
	else:check(not thumbnail._busy and thumbnail._request==0 and not thumbnail._attempted.has(model.path),"scroll-away cancels idle thumbnail preparation and allows a later retry")
	pool.gate.post()
	await settle(host._shared_preparation_ledger,pool)
	if explicit_repair:
		deadline=Time.get_ticks_msec()+5000
		while thumbnail.results.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check(thumbnail.results.size()==1 and thumbnail.results[0].scene!=null,"promoted explicit repair receives its prepared model")
	else:check(thumbnail.results.is_empty(),"cancelled offscreen thumbnail cannot publish a stale model")
	thumbnail.clear_models();thumbnail._busy=false
	thumbnail.queue_import(entry,true);thumbnail.queue_import(entry);thumbnail.set_visible_entries([])
	check(thumbnail._imports.size()==1 and not thumbnail._imports[0]._thumbnail_idle,"explicit repair also promotes and deduplicates a queued idle job")
	thumbnail._imports.clear();host.free();await process_frame

func source_change_case()->void:
	var model:=fixture("source_changes",true);var host:=Host.new();root.add_child(host)
	var consumer:=Node.new();host.add_child(consumer);var service:Node=load(ServicePath).for_consumer(consumer)
	var pool:=ControlledPool.new();pool.hold=true;configure(service,pool)
	var id:int=service.request(model.path,consumer,received);var deadline:=Time.get_ticks_msec()+5000
	while not pool.has_entered() and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.has_entered(),"source-change fixture pauses after real geometry preparation")
	var index:=Compiled.index_path(model.path,content_root);var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index))
	manifest.source_sha="b".repeat(64);write(index,JSON.stringify(manifest));pool.gate.post()
	var result:Dictionary=await wait_reply(id)
	check(not result.get("ok",true),"changed native source identity is rejected before private publication")
	result={};replies.clear();await settle(host._shared_preparation_ledger,pool)
	host.free();await process_frame

func pending_bundle_case()->void:
	var embedded:=fixture("pending_bundle_geometry",false);var split:=fixture("pending_bundle_wait",true)
	var host:=Host.new();root.add_child(host);var consumer:=Node.new();host.add_child(consumer)
	var service:Node=load(ServicePath).for_consumer(consumer);var pool:=ControlledPool.new();pool.hold=true;configure(service,pool)
	var id:int=service.request_many([embedded.path,split.path],consumer,received)
	var deadline:=Time.get_ticks_msec()+5000
	while (not pool.has_entered() or not service._bundles[id].handles.has(embedded.path)) and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.has_entered() and service._bundles[id].handles.has(embedded.path),"bundle retains completed geometry while its native sibling is still preparing")
	var tracker:Node=PublishedGeometry.for_tree(self)
	var allocation:int=service._bundles[id].handles[embedded.path].packed.get_instance_id()
	check(tracker._entries.has(allocation),"waiting bundle's private geometry remains in the strict published baseline")
	service.cancel(id);pool.gate.post();await settle(host._shared_preparation_ledger,pool)
	check(not replies.has(id),"cancelled bundle discards partial private templates without callback")
	host.free();await process_frame
	deadline=Time.get_ticks_msec()+5000
	while tracker._entries.has(allocation) and Time.get_ticks_msec()<deadline:
		tracker.collect_retired(100);await process_frame
	check(not tracker._entries.has(allocation),"cancelled partial bundle's real published geometry retires")

func prefab_case(service:Node,host:Node,model:Dictionary)->void:
	var second:=fixture("request_prefab_second",true)
	var doc:=Doc.new();doc.add_asset({"asset_path":model.path},Vector3.ZERO);doc.add_asset({"asset_path":second.path},Vector3.RIGHT*2)
	doc.add_box("block",Vector3.UP*2,Vector3.ONE)
	var source:Dictionary=doc.records[-1].duplicate(true)
	source.building={"id":"fixture","part":"floor","floor":0,"floor_y":0.,"role":"floor"}
	var baked:Dictionary=preload("res://scripts/world3d/house_prefab.gd").bake([source])
	check(baked.get("ok",false),"small real frozen geometry fixture bakes")
	if baked.get("ok",false):
		var frozen:Dictionary=baked.records[0];frozen.uuid="frozen"
		var frozen_loaded:={"ok":true,"records":[frozen],"building_instances":{}}
		check(Prefabs.preview_dependencies(frozen_loaded).is_empty(),"saved frozen geometry needs no source-model preparation")
		var frozen_scene:=Prefabs.preview_prepared(frozen_loaded,{})
		check(frozen_scene!=null and frozen_scene.get_node("frozen").get_meta("house_prefab",false),"frozen record still follows its saved inline geometry path")
		if frozen_scene!=null:Drainer.dispose_scene(frozen_scene)
	var path:=content_root.path_join("assets/prefabs/request_preview.json")
	write(path,JSON.stringify({"format":"rmmo_prefab","version":1,"records":doc.records,"building_instances":{}}))
	var entry:={"prefab_path":path};var loaded:=Prefabs.read(entry)
	check(loaded.get("ok",false),"mixed native/procedural prefab passes the production reader")
	if not loaded.get("ok",false):print(loaded);return
	check(Prefabs.preview_dependencies(loaded).size()==2,"prefab requests only ordinary native model dependencies")
	var preview:=Preview.new();host.add_child(preview)
	var thumbnail:=ThumbnailProbe.new();host.add_child(thumbnail)
	var producers:int=service.profile.producers;var created:int=service.native_texture_pool.audit.created
	preview.show_prefab(entry);thumbnail._busy=true;thumbnail._key=path;thumbnail._prepare_entry(entry,true)
	var deadline:=Time.get_ticks_msec()+5000
	while (preview.scene==null or thumbnail.results.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
	check(preview.scene!=null and preview.scene.get_child_count()==3,"private prefab preview preserves model and procedural records")
	check(thumbnail.results.size()==1 and thumbnail.results[0].scene!=null,"thumbnail consumer joins private prefab preparation")
	check(service.profile.producers-producers==2,"preview plus thumbnail prepare each distinct model only once")
	check(service.native_texture_pool.audit.created-created==1,"two prefab models share one native texture producer")
	check(service.ownership_tracker.adoptions>0 and service.ownership_tracker.charged,"private split handoff protocol adopts before releasing the queue envelope")
	check(not Assets._scenes.has(model.path) and not Assets._scenes.has(second.path),"prefab preview does not grow global template cache")
	preview.free();thumbnail.clear_models();thumbnail.free()
	await settle(host._shared_preparation_ledger,service.native_texture_pool)

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(45).timeout.connect(func():printerr("EDITOR_ASSET_PREPARATION watchdog");quit(2))
	var model:=fixture("request_cold",true)
	var host:=Host.new();root.add_child(host)
	var preview:=Preview.new();host.add_child(preview)
	if not FileAccess.file_exists(ServicePath):
		preview.show_asset(model.path);await process_frame
		check(preview.scene!=null and Ready.scene_ready(preview.scene),"cold UI preview resolves split native without a warmed global cache")
		check(false,"editor has a cancellable shared native request entry")
		preview.free();host.free();print("EDITOR_ASSET_PREPARATION checks=",checks," failures=",failures);quit(1);return
	var service_script:Script=load(ServicePath)
	var service:Node=service_script.for_consumer(preview)
	check(service!=null and service.ledger==host._shared_preparation_ledger,"preview service uses editor's existing ledger")
	var pool:=ControlledPool.new();configure(service,pool)
	preview.show_asset(model.path)
	var deadline:=Time.get_ticks_msec()+5000
	while preview.scene==null and Time.get_ticks_msec()<deadline:await process_frame
	check(preview.scene!=null and Ready.scene_ready(preview.scene),"cold UI preview resolves split native without a warmed global cache")
	check(not Assets._scenes.has(model.path),"one-shot preview does not populate AssetLibrary._scenes")
	preview.show_asset("");await settle(host._shared_preparation_ledger,pool)
	var consumer:=Node.new();host.add_child(consumer)
	var before:int=service.profile.producers
	var first:int=service.request(model.path,consumer,received)
	var second:int=service.request(model.path,consumer,received)
	check(service.cancel(first),"one subscriber can cancel its request")
	var result:Dictionary=await wait_reply(second)
	check(result.get("ok",false) and result.handle.ready(),"sibling request survives subscriber cancellation")
	check(not replies.has(first),"cancelled subscriber receives no completion")
	check(service.profile.producers==before+1,"identical in-flight models use one geometry producer")
	var scene:Node3D=result.handle.instantiate()
	check(scene!=null and Ready.scene_ready(scene),"private request handle instantiates complete native scene")
	if scene!=null:Drainer.dispose_scene(scene)
	result={};replies.clear();await settle(host._shared_preparation_ledger,pool)
	var absent:=content_root.path_join("assets/no_native.glb")
	var failed:int=service.request(absent,consumer,received)
	result=await wait_reply(failed)
	check(not result.get("ok",true),"missing product fails without source fallback")
	result={};replies.clear()
	var embedded:=fixture("request_embedded",false)
	var ordinary:int=service.request(embedded.path,consumer,received)
	result=await wait_reply(ordinary)
	check(result.get("ok",false) and result.handle.ready(),"ordinary embedded native uses the same asynchronous entry")
	check(PublishedGeometry.for_tree(self).report().entries>0,"ordinary embedded private result uses the strict production ownership tracker")
	check(not Assets._scenes.has(embedded.path),"ordinary request also leaves global scene cache unchanged")
	result={};replies.clear();await settle(host._shared_preparation_ledger,pool)
	await prefab_case(service,host,model)
	preview.free();consumer.free();host.free();await process_frame
	for label:String in ["cancel","switch","owner_exit","close"]:await blocked_case(label)
	await leader_cancel_case()
	await thumbnail_scroll_case(false)
	await thumbnail_scroll_case(true)
	await source_change_case()
	await pending_bundle_case()
	var tracker:Node=PublishedGeometry.for_tree(self)
	deadline=Time.get_ticks_msec()+5000
	while tracker.report().entries>0 and Time.get_ticks_msec()<deadline:
		tracker.collect_retired(100);await process_frame
	check(tracker.report().entries==0 and tracker.report().published_envelope_bytes==0,"all strict private published geometry returns to zero")
	print("EDITOR_ASSET_PREPARATION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
