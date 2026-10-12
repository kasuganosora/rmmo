extends "res://tools/test_editor_native_admission_gpu.gd"
## Real renderer resources, private resident ownership and HTTP editor handoff.
## Temporary fixtures only. Run on the private desktop, never headless except parse.
const Ownership=preload("res://scripts/world_editor/prepared_model_ownership.gd")
const LaneFixture=preload("res://tools/test_editor_preparation_lanes_gpu.gd")
var _dispatch_lanes:Array=[]

class RetirementAudit extends Ownership:
	var syncs:Array=[]
	func _synchronize_retirement()->void:
		syncs.append({"main":OS.get_thread_caller_id()==OS.get_main_thread_id(),"before":report()})
		super._synchronize_retirement()

class GatedNative extends LaneFixture.OwnedAudit:
	var entered:=Semaphore.new()
	var leave:=Semaphore.new()
	func read_then_wait(path:String,content_root:String,candidate:Dictionary)->Dictionary:
		var packet:=read_native(path,content_root,candidate)
		entered.post();leave.wait()
		return packet

func native_estimate(candidate:Dictionary)->Dictionary:
	return {"estimated_bytes":int(candidate.estimated_bytes),"exclusive":bool(candidate.exclusive),"stage":"compiled_read"}

func resident_queue(candidate:Dictionary)->Node:
	var queue:=Queue.new();queue.resident_enabled=true;queue.lanes_enabled=true;queue.diagnostics_enabled=true
	queue.resident_eligible=func(key:String,packet:Dictionary)->bool:
		return queue.rows[key].lane=="model" and queue.rows[key].estimate.get("stage")=="compiled_read" and not packet.get("cancelled",false) and Job._native_result_action(candidate,packet)=="ready"
	root.add_child(queue);queue.set_process(false)
	return queue

func until_ready(queue:Node,keys:Array,dispatch:bool=true)->void:
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		queue._pump(Time.get_ticks_usec()+(50000 if dispatch else 0))
		if keys.all(func(key):return queue.is_ready(key)):return
		await process_frame
	check(false,"real resident workers join before fixture deadline: "+str(keys))

func drain_workers()->void:
	var drainer:=Drainer.for_tree(self);var deadline:=Time.get_ticks_msec()+15000
	while not drainer.jobs.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(drainer.jobs.is_empty(),"private fixture leaves no detached worker in the drainer")

func packed_texture(packet:Dictionary)->Texture2D:
	var packed:PackedScene=packet.get("packed")
	if packed==null:return null
	var state:=packed.get_state()
	for node in state.get_node_count():
		for property in state.get_node_property_count(node):
			var value:Variant=state.get_node_property_value(node,property)
			if value is Mesh:
				for surface in value.get_surface_count():
					var material:Material=value.surface_get_material(surface)
					if material is BaseMaterial3D and material.albedo_texture!=null:return material.albedo_texture
	return null

func publication_lifetime(path:String,candidate:Dictionary)->void:
	Library.evict_cached_scene(path)
	var tracker:=RetirementAudit.new();root.add_child(tracker);tracker.set_process(false)
	var queue:=resident_queue(candidate)
	for key in ["model:a","model:b"]:
		check(queue.enqueue(key,Job._parse_native_asset.bind(path,Paths.external_root(),candidate),native_estimate(candidate),"model"),"independent real native allocation enqueued: "+key)
	await until_ready(queue,["model:a","model:b"])
	var a:Dictionary=queue.acquire("model:a");var b:Dictionary=queue.acquire("model:b")
	check(a.get("packed") is PackedScene and b.get("packed") is PackedScene and a.packed!=b.packed,"IGNORE_DEEP reads of one source create different actual PackedScene allocations")
	var texture_a:Texture2D=packed_texture(a);var texture_b:Texture2D=packed_texture(b)
	check(texture_a is ImageTexture and texture_b is ImageTexture and texture_a!=texture_b,"independent native reads own distinct actual renderer textures")
	if not a.get("packed") is PackedScene or not b.get("packed") is PackedScene:
		queue.cancel();queue.free();tracker.free();return
	var weak_a:WeakRef=weakref(a.packed);var weak_b:WeakRef=weakref(b.packed)
	var bytes:int=candidate.estimated_bytes
	var bad:Dictionary=a.duplicate();bad.source_digest="0".repeat(64)
	var rejected:Dictionary=tracker.preflight(candidate,bad,bytes)
	check(not rejected.ok and tracker.report().published_envelope_bytes==0 and not Library._scenes.has(path),"identity-invalid preflight never publishes or creates a published charge")
	var job:=Job.new();root.add_child(job);job._model_ownership=tracker;job._model_candidates[path]=candidate
	job._timings={"asset_lookahead":{"ownership_rejections":{}}}
	var invalid_scene:Node=job._publish_owned_native(path,bad,bytes)
	check(invalid_scene==null and not Library._scenes.has(path) and job._timings.asset_lookahead.ownership_rejections.has(path),"real LoadJob publication rejects invalid preflight without caching or instantiating")
	job.free();bad.clear()
	check(not tracker.preflight(candidate,a,bytes-1).ok,"preflight cannot silently replace the complete native envelope with a smaller resident claim")
	var receipt_a:Dictionary=tracker.preflight(candidate,a,bytes)
	check(receipt_a.get("ok",false) and int(receipt_a.get("weak_owner_count",0))>=5,"valid preflight inventories PackedScene SceneState mesh material and texture weak owners")
	if not receipt_a.get("ok",false):
		print("PREFLIGHT_FAILURE ",receipt_a);queue.cancel();queue.free();tracker.free();return
	check(not Library.cache_packed(path,a.packed,"invalid") and not Library._scenes.has(path) and tracker.report().entries==0,"cache rejection after successful preflight leaves no publication or baseline charge")
	check(not tracker.adopt(receipt_a.ticket).ok and tracker.report().entries==0,"an unaccepted cache assignment cannot adopt its valid preflight ticket")
	check(Library.cache_packed(path,a.packed,candidate.source_sha),"first valid native allocation enters actual AssetLibrary cache")
	var adopted_a:Dictionary=tracker.adopt(receipt_a.ticket)
	check(adopted_a.ok and not adopted_a.reused and tracker.report().published_envelope_bytes==bytes,"cache handoff adopts the entire native envelope before transient credit is released")
	check(queue.ledger.reserved_bytes==2*bytes,"both private native leases remain charged throughout preflight cache and adoption")
	check(tracker.adopt(receipt_a.ticket).get("reused",false) and tracker.report().entries==1,"re-adopting the same real allocation is idempotent")
	var scene_a:Node=Library.instantiate(path)
	check(scene_matches(scene_a,1,8) and scene_a.has_meta("_compiled_resource_owner"),"real instance retains the compiled owner and exact textured visual")
	var receipt_b:Dictionary=tracker.preflight(candidate,b,bytes)
	check(receipt_b.get("ok",false) and Library.cache_packed(path,b.packed,candidate.source_sha),"second allocation can replace only the cache template")
	var adopted_b:Dictionary=tracker.adopt(receipt_b.get("ticket"))
	check(adopted_b.get("ok",false) and not adopted_b.get("reused",true) and adopted_b.get("entry_id")==b.packed.get_instance_id() and adopted_b.get("entry_id")!=adopted_a.get("entry_id"),"different native allocations sharing one source identity are never merged")
	queue.release("model:a");queue.release("model:b")
	check(a.is_empty() and b.is_empty() and queue.ledger.reserved_bytes==0,"published handoff clears both private aliases and returns only their transient leases")
	check(tracker.report().entries==2 and tracker.report().published_envelope_bytes==2*bytes,"instance-owned and cache-only native allocations both retain full published baseline charges")
	tracker.collect_retired(32)
	check(tracker.report().entries==2 and weak_b.get_ref()!=null,"cache-only allocation stays charged even when no instance was created")
	scene_a.remove_meta("_compiled_resource_owner")
	check(weak_a.get_ref()==null and scene_matches(scene_a,1,8),"PackedScene may die while its real instance still owns mesh material and texture")
	tracker.collect_retired(32)
	check(tracker.report().entries==2,"subresources keep the first baseline charged after its PackedScene dies")
	Drainer.dispose_scene(scene_a);scene_a=null;Library.evict_cached_scene(path)
	check(weak_a.get_ref()==null and weak_b.get_ref()==null and texture_a.get_width()==8 and texture_b.get_width()==8,"both template caches and instances can retire while independently held native textures remain alive")
	tracker.collect_retired(32)
	check(tracker.report().published_envelope_bytes==2*bytes and tracker.syncs.is_empty(),"live leaf textures prevent premature envelope release and renderer retirement sync")
	texture_a=null
	var retired_a:Dictionary=tracker.collect_retired(32)
	check(retired_a.retired==1 and retired_a.retired_envelope_bytes==bytes and tracker.report().published_envelope_bytes==bytes,"last first-graph texture release retires exactly its own allocation envelope")
	texture_b=null
	var retired_b:Dictionary=tracker.collect_retired(32)
	check(retired_b.retired==1 and tracker.report().entries==0 and tracker.report().weak_owner_count==0 and tracker.report().published_envelope_bytes==0,"last second-graph texture release leaves no published owner or byte charge")
	check(tracker.syncs.size()==2 and tracker.syncs.all(func(row):return row.main and row.before.published_envelope_bytes>0),"each actual retirement synchronizes the renderer on main before subtracting its published credit")
	check(receipt_a.has("ticket") and receipt_b.has("ticket") and weak_a.get_ref()==null and weak_b.get_ref()==null,"retained preflight tickets never strongly pin native resource graphs")
	results.append({"mode":"publication_resource_graph","queue":queue.snapshot(),"ownership":tracker.report(),"retirement_syncs":tracker.syncs.duplicate(true)})
	queue.free();tracker.free();await process_frame

func mixed_private_cancel(path:String,candidate:Dictionary,png:String)->void:
	var queue:=resident_queue(candidate)
	var pixels_estimate:={"estimated_bytes":8*1024*1024,"exclusive":false,"cpu_only":true,"stage":"pixels"}
	var digest:=FileAccess.get_sha256(png)
	for key in ["texture:a","texture:b"]:queue.enqueue(key,LaneFixture.read_pixels.bind(png,digest),pixels_estimate,"texture")
	await until_ready(queue,["texture:a","texture:b"])
	var held_image:Dictionary=queue.acquire("texture:a")
	var audits:Array=[];var keys:Array=[]
	for index in 11:
		var key:="model:%02d"%index;var audit:=LaneFixture.OwnedAudit.new();audit.ledger=weakref(queue.ledger);audit.owner_key=key
		audits.append(audit);queue.enqueue(key,audit.read_native.bind(path,Paths.external_root(),candidate),native_estimate(candidate),"model")
		if index<10:keys.append(key)
	await until_ready(queue,keys)
	var held_native:Dictionary=queue.acquire("model:00")
	var stats:Dictionary=queue.snapshot()
	check(stats.resident_current==8 and stats.inflight_current==4 and queue.ledger.count()==12 and queue.rows["model:10"].state=="pending","real resources reach eight private residents plus four inflight results while a thirteenth stays pending")
	check(queue.rows["model:00"].held_origin=="resident" and queue.rows["texture:a"].state=="held" and queue.rows["texture:b"].state=="ready","mixed cancellation fixture includes resident-held native and ready/held decoded PNG ownership")
	check(stats.peak_resident==8 and stats.peak_inflight<=4 and stats.ledger.peak_workers<=2 and stats.peak_private_bytes<=queue.byte_limit,"real dispatches respect two workers four inflight eight residents and the shared byte ceiling")
	check(queue.ledger.reserved_bytes==10*int(candidate.estimated_bytes)+2*pixels_estimate.estimated_bytes,"resident promotion preserves every full native and image envelope")
	check(not Library._scenes.has(path) and held_native.get("packed") is PackedScene,"speculative resident packets stay private and do not publish into AssetLibrary")
	queue.cancel()
	check(held_image.is_empty() and held_native.is_empty() and queue.ledger.reserved_bytes==0,"mixed cancel clears consumer aliases and every completed private lease")
	check(audits.slice(0,10).all(func(audit):return audit.charged_main_retirement()),"all ten real native renderer graphs are destroyed on main while still charged")
	check(audits.slice(0,10).all(func(audit):return not audit.owning_lease_present.is_empty() and audit.owning_lease_present.all(func(value):return value)),"every native resource destructor observes its own exact lease before credit return")
	check(not audits[10].alive() and audits[10].resources.is_empty(),"pending thirteenth task creates no hidden renderer allocation")
	results.append({"mode":"bounded_private_mixed_cancel","before":stats,"after":queue.snapshot(),"releases":audits.slice(0,10).map(func(audit):return audit.releases.duplicate(true))})
	queue.free();await drain_workers()

func running_cancel(path:String,candidate:Dictionary,png:String)->void:
	var queue:=resident_queue(candidate)
	var resident:=LaneFixture.OwnedAudit.new();resident.ledger=weakref(queue.ledger);resident.owner_key="model:resident"
	queue.enqueue(resident.owner_key,resident.read_native.bind(path,Paths.external_root(),candidate),native_estimate(candidate),"model")
	queue.enqueue("texture:held",LaneFixture.read_pixels.bind(png,FileAccess.get_sha256(png)),{"estimated_bytes":8*1024*1024,"exclusive":false,"cpu_only":true,"stage":"pixels"},"texture")
	await until_ready(queue,[resident.owner_key,"texture:held"])
	var held:Dictionary=queue.acquire("texture:held")
	var gated:=GatedNative.new();gated.ledger=weakref(queue.ledger);gated.owner_key="model:running"
	queue.enqueue(gated.owner_key,gated.read_then_wait.bind(path,Paths.external_root(),candidate),native_estimate(candidate),"model")
	queue._pump(Time.get_ticks_usec()+50000)
	var entered:=false;var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		if gated.entered.try_wait():entered=true;break
		await process_frame
	check(entered and gated.alive() and queue.rows[gated.owner_key].state=="running","running cancel fixture holds a worker after it created real native GPU resources")
	var ledger:RefCounted=queue.ledger
	queue.cancel()
	check(held.is_empty() and resident.charged_main_retirement(),"cancel immediately retires joined residents and held image packets safely")
	check(ledger.reserved_bytes==candidate.estimated_bytes and ledger._entries.has(gated.owner_key) and gated.alive(),"cancel detaches the live worker without returning its still-owned native budget")
	queue.free();gated.leave.post();await drain_workers()
	check(ledger.reserved_bytes==0 and gated.native_packet.is_empty() and gated.charged_main_retirement(),"SceneTree drainer joins and retires abandoned native resources on main before returning their lease")
	check(gated.owning_lease_present.all(func(value):return value),"detached worker retirement retains its own ledger even after the operation queue is freed")
	results.append({"mode":"running_mixed_cancel","resident_releases":resident.releases.duplicate(true),"running_releases":gated.releases.duplicate(true),"ledger":ledger.snapshot()})

func prepare_fixture_job(path:String,candidate:Dictionary)->Dictionary:
	var value:Dictionary=super.prepare_fixture_job(path,candidate)
	var queue:Node=value.queue;var job:Node=value.job;var audit:Audit=value.audit;var key:String=value.key
	queue.rows[key].lane="model";queue.resident_enabled=true;queue.lanes_enabled=true;queue.diagnostics_enabled=true
	job._model_ownership=Ownership.for_tree(self);job._timings.asset_lookahead.ownership_rejections={}
	queue.resident_eligible=func(request:String,packet:Dictionary)->bool:
		return queue.rows[request].estimate.get("stage")=="compiled_read" and not packet.get("cancelled",false) and Job._native_result_action(candidate,packet)=="ready"
	_dispatch_lanes=[]
	queue.thread_starter=func(worker:Thread,task:Callable)->int:
		_dispatch_lanes.append(queue.rows[key].lane)
		return audit.start(worker,task,queue,key)
	return value

func http_case(path:String)->void:
	var tracker:Node=Ownership.for_tree(self)
	var observed:={"queue_seen":false,"all_resident":true,"completed":false,"published_entries":0,"published_bytes":0}
	var watch:=func()->void:
		if not is_instance_valid(editor):return
		var job:Node=editor._load_job
		if job==null:return
		if job.phase=="complete":observed.completed=observed.completed or job._timings.get("preparation",{}).get("resident_enabled",false)
		if is_instance_valid(job._preparation):
			observed.queue_seen=true;observed.all_resident=observed.all_resident and job._preparation.resident_enabled
		var stats:Dictionary=tracker.report()
		observed.published_entries=maxi(observed.published_entries,stats.entries);observed.published_bytes=maxi(observed.published_bytes,stats.published_envelope_bytes)
	process_frame.connect(watch)
	await super.http_case(path)
	process_frame.disconnect(watch)
	check(observed.queue_seen and observed.all_resident and observed.completed,"real HTTP editor load and reopen use resident handoff through the shared UI business path")
	check(observed.published_entries>=1 and observed.published_bytes>0,"real HTTP cache/instance publication records native resource ownership beyond preparation completion")
	tracker.collect_retired(128)
	results.append({"mode":"http_resident_load_edit_save_reopen","observed":observed,"after_editor_close":tracker.report()})

func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Run via tools/run_godot_background.py with a GPU backend");quit(2);return
	Engine.max_fps=60;rpc_timeout_ms=30000
	create_timer(150).timeout.connect(func():push_error("EDITOR_PREPARATION_RESIDENCY_GPU timeout");quit(2))
	var original_native:bool=Job.native_model_footprints_enabled;var original_resident:bool=Job.prepared_model_residency_enabled
	var original_lanes:bool=Job.preparation_lanes_enabled;var previous_precheck:bool=Native.source_precheck_enabled
	var require_default:bool="--require-residency-default" in OS.get_cmdline_user_args()
	if require_default:check(original_resident,"production resident handoff is enabled by default")
	Job.native_model_footprints_enabled=true;Job.prepared_model_residency_enabled=true;Job.preparation_lanes_enabled=false;Native.source_precheck_enabled=false
	temporary_directory=Paths.cache_directory("preparation_residency_gpu_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(temporary_directory)
	var path:=temporary_directory.path_join("fixture.glb");var changed:=temporary_directory.path_join("changed.glb")
	check(fixture(path,1,8,Color(.7,.2,.1)),"temporary closed ordinary textured GLB exported")
	check(fixture(changed,4,2048,Color(.1,.6,.2)),"larger temporary replacement source exported for separately admitted raw retry")
	var original:=FileAccess.get_file_as_bytes(path);var replacement:=FileAccess.get_file_as_bytes(changed)
	check(Compiled.build(path).get("ok",false),"actual native PackedScene product compiled")
	check(Footprint.build(path).get("ok",false),"actual native product footprint compiled")
	var candidate:=Footprint.candidate(path,Paths.external_root())
	check(not candidate.is_empty(),"fixed native candidate binds source product and full peak estimate")
	if candidate.is_empty():quit(1);return
	var product:String=candidate.product;var product_bytes:=FileAccess.get_file_as_bytes(product)
	var png:=temporary_directory.path_join("pixels.png");var pixels:=Image.create(512,512,false,Image.FORMAT_RGBA8);pixels.fill(Color(.2,.4,.6,1))
	check(pixels.save_png(png)==OK,"temporary PNG supplies real CPU texture results for mixed queues");pixels=null
	await publication_lifetime(path,candidate)
	await mixed_private_cancel(path,candidate,png)
	await running_cancel(path,candidate,png)
	check(put(path,replacement),"source replacement precedes the frozen native reader candidate")
	await direct_case(path,candidate,"source_retry",4,2048)
	check(_dispatch_lanes==["model","model"] and results[-1].queue.resident_entered==0,"real source-error packet and its separately admitted raw retry never enter the native resident pool and preserve model lane")
	check(put(path,original),"temporary source restored after raw retry")
	var damaged:=product_bytes.duplicate();damaged[-1]=damaged[-1]^1
	check(put(product,damaged),"only the temporary native product is damaged for a real fallback packet")
	await direct_case(path,candidate,"corrupt_product",1,8)
	check(results[-1].queue.resident_entered==0,"real checksum fallback and raw result cannot pass native residency gate")
	check(put(product,product_bytes),"temporary compiled product restored before HTTP validation")
	await http_case(path)
	check(FileAccess.get_sha256(path)==candidate.source_sha and FileAccess.get_sha256(product)==candidate.payload_sha,"source and native product identities end unchanged")
	await drain_workers()
	Job.native_model_footprints_enabled=original_native;Job.prepared_model_residency_enabled=original_resident;Job.preparation_lanes_enabled=original_lanes;Native.source_precheck_enabled=previous_precheck
	var report:={"passed":passed,"failures":failed,"fixture_directory":temporary_directory,"cases":results,"required_production_default":require_default,"original_residency_default":original_resident,"contract":"2 workers + 4 inflight + 8 private resident under unchanged private byte admission; published native envelopes are separate conservative accounting, not a total process cap; source proof is reader-completion snapshot"}
	var output:=Paths.external_root().path_join("review_artifacts/editor_preparation_residency_gpu_20261011.json")
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("EDITOR_PREPARATION_RESIDENCY_GPU passed=",passed," failures=",failed);quit(1 if failed else 0)
