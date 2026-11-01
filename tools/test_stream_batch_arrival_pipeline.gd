extends SceneTree
## Real append/adopt -> WorldStream.sync -> GroundBatcher runtime requests.
## Only final GPU batch commit is replaced. Scheduling, collection, eligibility,
## preparation, packing, workers, lifetime signals and generation checks are real.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const FrameBudget=preload("res://scripts/world3d/frame_work_budget.gd")
const NEAR:=Vector3(8,0,8)
const AWAY:=Vector3(8192,0,8192)
var checks:=0
var failures:=0
var failures_by_kind:Dictionary={}
var assertions:Array=[]
var cases:Array=[]
var output_path:=""
var saved_frame_budget:=true

class NoGpuCommitBatch extends "res://scripts/world3d/ground_batcher.gd":
	var commit_categories:Dictionary={}
	var prepared_thread_ids:Dictionary={}
	var worker_receipt_commits:=0
	func _commit(group:Dictionary,data:Dictionary,started:int)->void:
		# Production already checked the worker target key/generation. Retain the
		# same live-member, source freeze and visual-lifetime contract, but omit
		# Geometry.upload and the GPU mesh/cache. No scheduler or gate is mocked.
		for node in group.members:
			if not is_instance_valid(node):return
		commit_categories[group.category]=int(commit_categories.get(group.category,0))+1
		if data.has("surface_prepare_thread"):
			var thread_id:int=data.surface_prepare_thread
			prepared_thread_ids[thread_id]=true
			if thread_id!=OS.get_main_thread_id():worker_receipt_commits+=1
		var visual:=MeshInstance3D.new();visual.set_meta("ground_render_batch",true)
		add_child(visual);group.visual=visual;group.data=data
		group.relative_pose=group.reference_pose.affine_inverse()*group.render_pose
		group.last_source_pose=group.members[0].global_transform
		visual.global_transform=group.last_source_pose*group.relative_pose if group.category=="building" else group.render_pose
		visual.visible=group.members[0].is_visible_in_tree()
		for at:int in group.members.size():freeze(group.members[at],group.cpu[at])
		group.erase("cpu");rebuild_count+=1
		last_build_ms=(Time.get_ticks_usec()-started)/1000.0

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output_path=argument.trim_prefix("--output=")
	create_timer(90.0).timeout.connect(func():push_error("STREAM_BATCH_ARRIVAL_PIPELINE watchdog timeout");quit(124))
	run.call_deferred()

func check(ok:bool,label:String,kind:String="correctness")->void:
	checks+=1;assertions.append({"ok":ok,"kind":kind,"label":label})
	print("PASS " if ok else "FAIL ",kind," ",label)
	if not ok:
		failures+=1;failures_by_kind[kind]=int(failures_by_kind.get(kind,0))+1

func fixture()->Dictionary:
	var host:=Node3D.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map)
	var batch:=NoGpuCommitBatch.new();batch.name="GroundRenderBatches";map.add_child(batch)
	# The real _process and worker path remain active. Runtime private GPU upload
	# is off because this fixture deliberately substitutes only the GPU endpoint.
	batch.runtime_private_upload=false
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.55,.47,.39)
	var mesh:=BoxMesh.new();mesh.size=Vector3(.4,.5,.4);mesh.material=material
	var library:Array=[];map.set_meta("stream_library",library)
	var index:Dictionary=Index.build(library,true)
	for key:String in index:map.set_meta(key,index[key])
	map.set_meta("stream_meshes",{});map.set_meta("stream_bodies",{})
	map.set_meta("stream_children",map.get_child_count(true))
	return {"host":host,"map":map,"batch":batch,"mesh":mesh,"next_group":0}

func source_node(mesh:Mesh,id:String,owner:String,part:int)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=id;node.mesh=mesh
	node.position=NEAR+Vector3(float(part%4)*.6,0,float(part/4)*.6)
	node.set_meta("extras",{"uuid":id,"rmmo_collision":"none"})
	node.set_meta("ground_batch_record",{"uuid":id,"kind":"box","surface_id":"stone","size":[.4,.5,.4],
		"position":[node.position.x,0,node.position.z],"rotation":[0,0,0],
		"building":{"id":owner,"floor":0,"part":id,"role":"wall"}})
	return node

func make_specs(f:Dictionary,group_count:int,parts:int=8)->Array:
	var result:Array=[]
	for unused:int in group_count:
		var owner:="arrival_house_%03d"%int(f.next_group);f.next_group+=1
		for part:int in parts:
			var id:="%s_part_%02d"%[owner,part]
			var node:=source_node(f.mesh,id,owner,part)
			var spec:Dictionary=Stream._spec(node,node.transform);node.free();result.append(spec)
	return result

func append(f:Dictionary,specs:Array,label:String)->bool:
	var result:Dictionary=Stream.append_specs(f.map,specs)
	check(result.get("ok",false),label+" uses successful real Stream.append_specs","fixture")
	return bool(result.get("ok",false))

func idle(batch:Node)->bool:
	return batch._preparation.is_empty() and batch._next_residency.is_empty() and batch.pending.is_empty() and batch._workers.is_empty()

func settle(f:Dictionary,origin:Vector3,label:String)->bool:
	var deadline:=Time.get_ticks_msec()+15000;var quiet:=0;var turns:=0
	while Time.get_ticks_msec()<deadline:
		Stream.sync(f.map,f.host,origin,Stream.FRAME_BUDGET);turns+=1
		var settled:bool=f.map.get_meta("stream_chunk",Vector2i(2147483647,0))==Stream.chunk_key(origin)
		settled=settled and f.map.get_meta("stream_jobs",[]).is_empty() and f.map.get_meta("stream_append_pending",[]).is_empty() and idle(f.batch)
		quiet=quiet+1 if settled else 0
		if quiet>=2:
			check(true,label+" settles through real sync and automatic batch process","fixture")
			return true
		await process_frame
	check(false,label+" settles through real sync and automatic batch process","fixture")
	print("PIPELINE_TIMEOUT ",label," ",turns," ",f.batch._preparation.get("phase","")," ",f.batch.pending.size()," ",f.batch._workers.size())
	return false

func snapshot(batch:Node)->Dictionary:
	var result:Dictionary={}
	for key:String in batch.groups:
		var group:Dictionary=batch.groups[key];var names:Array=[]
		for node:Node in group.members:names.append(str(node.name))
		var arrays:Array=group.get("data",{}).get("upload_cpu_arrays",[])
		if group.get("data",{}).has("slots"):
			arrays=[]
			for slot:Dictionary in group.data.slots:arrays.append(slot.arrays)
		elif group.get("data",{}).get("mesh") is Mesh:
			# The generic synchronous oracle has completed Geometry.upload; its
			# original CPU arrays are retained by that path's normal Cpu cache.
			arrays=Cpu.capture(group.data.mesh).surfaces
		var geometry:=HashingContext.new();geometry.start(HashingContext.HASH_SHA256);geometry.update(var_to_bytes(arrays))
		result[key]={"members":names,"signature":group.signature.duplicate(),"vertices":group.vertices,"keys":group.keys.duplicate(),"origin":group.origin,"category":group.category,"merge_base":group.merge_base,"geometry":geometry.finish().hex_encode()}
	return result

func membership(batch:Node)->Dictionary:
	var result:Dictionary={}
	for group:Dictionary in batch.groups.values():
		for node:Node in group.members:
			if is_instance_valid(node):result[str(node.name)]=node.get_instance_id()
	return result

func compare_full(f:Dictionary,label:String)->void:
	# The oracle alone takes the generic full-reconcile route. Actual production
	# requests come exclusively from WorldStream.sync, never from this test.
	var oracle_host:=Node3D.new();root.add_child(oracle_host)
	var oracle:=NoGpuCommitBatch.new();oracle_host.add_child(oracle);oracle.set_process(false)
	var nodes:Array=f.map.get_meta("stream_meshes",{}).values()
	oracle.request_sync(nodes);oracle.flush()
	check(snapshot(f.batch)==snapshot(oracle),label+" membership/signature/limits/origin equals generic full rebuild")
	var owners:Dictionary=membership(f.batch);var canonical:Dictionary=f.map.get_meta("stream_meshes",{})
	var exact:=owners.size()==canonical.size()
	for id:String in canonical:
		exact=exact and is_instance_valid(canonical[id]) and owners.get(id,0)==canonical[id].get_instance_id()
	check(exact,label+" every canonical live source occurs in its actual batch")
	oracle.clear(false);oracle_host.free()

func work(batch:Node)->Dictionary:
	return {"prepared":batch.prepared_source_visits,"packed":batch.packed_source_visits,"sync_count":batch.sync_count,
		"prefix_reuses":batch.completed_prefix_reuses,"source_visits_avoided":batch.completed_source_visits_avoided,
		"immutable_snapshot":batch._residency_bins.get("immutable_append",false),
		"commit_categories":batch.commit_categories.duplicate(),"prepared_thread_ids":batch.prepared_thread_ids.keys(),
		"worker_receipt_commits":batch.worker_receipt_commits}

func dispose(f:Dictionary)->void:
	var tracker:WeakRef=weakref(f.map.get_meta(Stream.BATCH_ARRIVALS_META)) if f.map.has_meta(Stream.BATCH_ARRIVALS_META) else null
	f.batch.clear(false);f.host.free()
	check(tracker==null or tracker.get_ref()==null,"arrival ledger does not retain a disposed map","fixture")

func incremental_work()->void:
	var f:=fixture();var initial:=make_specs(f,12)
	if not append(f,initial,"N initial"):
		dispose(f);return
	if not await settle(f,NEAR,"N initial"):
		dispose(f);return
	compare_full(f,"N initial")
	check(f.batch.commit_categories.size()==1 and f.batch.commit_categories.has("building"),"shared BoxMesh uses the real building branch and reaches the GPU commit stub","fixture")
	check(f.batch.worker_receipt_commits>0,"accepted batch data contains a real non-main surface preparation thread receipt","fixture")
	check(f.batch.prepared_source_visits==96,"initial N=96 prepares exactly N sources","work")
	var rounds:Array=[]
	for round_:int in 3:
		var before:=work(f.batch);var added:=make_specs(f,2)
		if not append(f,added,"append M round %d"%round_):break
		if not await settle(f,NEAR,"append M round %d"%round_):break
		var after:=work(f.batch);compare_full(f,"append M round %d"%round_)
		var prepared_delta:int=int(after.prepared)-int(before.prepared)
		var packed_delta:int=int(after.packed)-int(before.packed)
		check(prepared_delta==added.size(),"completed N + M round %d prepares only M=%d (actual=%d)"%[round_,added.size(),prepared_delta],"work")
		check(packed_delta==added.size(),"completed N + M round %d packs only independent M=%d (actual=%d)"%[round_,added.size(),packed_delta],"work")
		rounds.append({"round":round_,"added":added.size(),"before":before,"after":after,"prepared_delta":prepared_delta,"packed_delta":packed_delta})
	var ledger:RefCounted=f.map.get_meta(Stream.BATCH_ARRIVALS_META)
	check(ledger.profile.full_roster_builds==0 and ledger.profile.full_roster_rows==0 and ledger.profile.appended_roots==144,"pure arrivals never enumerate the old canonical roster","work")
	check(ledger.profile.early_requests==0 and ledger.profile.verified_members==0 and f.batch.sync_count==4,"arrival accounting preserves four checkpoints without early closure scans","work")
	check(ledger.profile.owner_loss_repairs==0,"pure arrivals do not create owner-loss repair work","work")
	var before_quiet:int=f.batch.sync_count
	for turn:int in 4:Stream.sync(f.map,f.host,NEAR,Stream.FRAME_BUDGET)
	check(f.batch.sync_count==before_quiet,"settled residency does not repeat batch requests","work")
	cases.append({"case":"real_sync_completed_prefix","initial":96,"rounds":rounds,"final":work(f.batch),"roster":ledger.profile.duplicate()})
	ledger=null
	dispose(f)

func mutable_rebuild()->void:
	for mode:String in ["geometry","material","record","pose"]:
		var f:=fixture();append(f,make_specs(f,1),"mutable "+mode)
		if not await settle(f,NEAR,"mutable baseline "+mode):
			dispose(f);continue
		var previous:=snapshot(f.batch);var owners:=membership(f.batch);var before:=work(f.batch)
		var changed_mesh:=BoxMesh.new();changed_mesh.size=Vector3(.7,.5,.4);changed_mesh.material=f.mesh.material
		var changed_material:=StandardMaterial3D.new();changed_material.albedo_color=Color(.12,.31,.74)
		for node:MeshInstance3D in f.map.get_meta("stream_meshes").values():
			if mode=="geometry":node.mesh=changed_mesh
			elif mode=="material":node.material_override=changed_material
			elif mode=="record":
				var record:Dictionary=node.get_meta("ground_batch_record").duplicate(true)
				record.building.floor=1;node.set_meta("ground_batch_record",record)
			else:node.position+=Vector3(3,0,0)
		# The real explicit full-rebuild contract must revoke immutable owners;
		# a newly allocated Array with the same Node identities does not do that.
		f.map.set_meta("stream_children",-1)
		await settle(f,NEAR,"mutable rebuild "+mode)
		check(membership(f.batch)==owners,"mutable "+mode+" preserves the same canonical Node owners")
		check(snapshot(f.batch)!=previous,"mutable "+mode+" changes the actual prepared group")
		compare_full(f,"same-node explicit rebuild "+mode)
		cases.append({"case":"same_node_mutable","mode":mode,"before":before,"after":work(f.batch)})
		dispose(f)

func suspended_return()->void:
	var f:=fixture();append(f,make_specs(f,2),"suspended baseline")
	if not await settle(f,NEAR,"suspended baseline"):
		dispose(f);return
	var retained:Dictionary={};var before:=work(f.batch)
	# Interrupt the real one-source departure cursor after its first batch drop.
	# The remaining members use the production SUSPENDED_DRAW optimization.
	for turn:int in 100:
		Stream.sync(f.map,f.host,AWAY,1)
		for id:String in f.map.get_meta("stream_meshes"):
			var node:Node=f.map.get_meta("stream_meshes")[id]
			if node.has_meta(Batch.SUSPENDED_DRAW):retained[id]=node.get_instance_id()
		if not retained.is_empty():break
		await process_frame
	check(not retained.is_empty(),"real interrupted departure creates suspended live sources","fixture")
	await settle(f,NEAR,"interrupted suspended return")
	var restored:=not retained.is_empty()
	for id:String in retained:
		var node:Node=f.map.get_meta("stream_meshes").get(id)
		restored=restored and is_instance_valid(node) and node.get_instance_id()==retained[id] and not node.has_meta(Batch.SUSPENDED_DRAW)
	check(restored,"return restores the same suspended Node owners")
	check(f.map.get_meta(Stream.BATCH_ARRIVALS_META).profile.owner_loss_repairs==0,"interrupted owned departure does not manufacture an owner-loss replan","work")
	compare_full(f,"same-node CPU/GPU restore")
	cases.append({"case":"suspended_return","retained":retained.size(),"before":before,"after":work(f.batch)})
	dispose(f)

func mutable_worker()->void:
	var f:=fixture();f.batch.set_process(false)
	append(f,make_specs(f,1),"mutable pending worker")
	# Keep the real pipeline, but stop between CPU launch and main acceptance to
	# make the lifecycle boundary deterministic even for a tiny worker result.
	for turn:int in 100:
		Stream.sync(f.map,f.host,NEAR,Stream.FRAME_BUDGET)
		if f.map.has_meta("stream_chunk"):break
	while not f.batch._preparation.is_empty():f.batch._prepare_step(0)
	f.batch._build_next(true)
	check(f.batch._workers.size()==1 and f.batch.worker_receipt_commits==0,"real worker is dispatched but not yet accepted before explicit mutation","fixture")
	var changed_mesh:=BoxMesh.new();changed_mesh.size=Vector3(.9,.5,.4);changed_mesh.material=f.mesh.material
	for node:MeshInstance3D in f.map.get_meta("stream_meshes").values():node.mesh=changed_mesh
	f.map.set_meta("stream_children",-1)
	Stream.sync(f.map,f.host,NEAR,Stream.FRAME_BUDGET)
	while not f.batch._workers.is_empty():f.batch._finish_worker(0)
	check(f.batch.worker_receipt_commits==0,"explicit mutable rebuild rejects the old generation before it can freeze sources")
	var unchanged:=true
	for node:MeshInstance3D in f.map.get_meta("stream_meshes").values():unchanged=unchanged and node.mesh==changed_mesh
	check(unchanged,"rejected old worker cannot overwrite edited source geometry")
	f.batch.set_process(true)
	await settle(f,NEAR,"new mutable worker generation")
	compare_full(f,"new generation after pending worker mutation")
	cases.append({"case":"same_node_mutable_worker","final":work(f.batch)})
	dispose(f)

func late_ledger_owner_loss()->void:
	var f:=fixture();append(f,make_specs(f,2),"late ledger baseline")
	if not await settle(f,NEAR,"late ledger baseline"):
		dispose(f);return
	f.map.get_meta(Stream.BATCH_ARRIVALS_META).dispose();f.map.remove_meta(Stream.BATCH_ARRIVALS_META)
	var before_sync:int=f.batch.sync_count
	Stream.sync(f.map,f.host,NEAR,Stream.FRAME_BUDGET)
	check(f.batch.sync_count==before_sync,"attaching an unseeded ledger to settled sources adds no checkpoint","work")
	var meshes:Dictionary=f.map.get_meta("stream_meshes");var id:String=meshes.keys()[1]
	var old_identity:int=meshes[id].get_instance_id();var old_count:int=f.map.get_child_count(true)
	meshes[id].free()
	var service:=Node3D.new();service.set_meta("stream_instance",true);f.map.add_child(service)
	check(f.map.get_child_count(true)==old_count,"external source loss plus service arrival keeps the direct child count","fixture")
	await settle(f,NEAR,"late ledger equal-count repair")
	var repaired:Variant=f.map.get_meta("stream_meshes").get(id)
	check(is_instance_valid(repaired) and repaired.get_instance_id()!=old_identity,"unseeded ledger still repairs a canonical owner lost at equal child count")
	check(f.map.get_meta(Stream.BATCH_ARRIVALS_META).profile.owner_loss_repairs==1,"equal-count external loss requests exactly one repair","work")
	compare_full(f,"late ledger equal-count owner repair")
	cases.append({"case":"late_ledger_owner_loss","final":work(f.batch),"roster":f.map.get_meta(Stream.BATCH_ARRIVALS_META).profile.duplicate()})
	dispose(f)

func closure_opt_in()->void:
	var ledger:=Stream.BatchArrivals.new();var nodes:Array=[];var specs:Array=[]
	for part:int in 2:
		var node:=MeshInstance3D.new();node.name="closure_%d"%part;nodes.append(node)
		specs.append({"uuid":str(node.name),"render_building":"closure_house","ground_batch_record":{"kind":"box","building":{"id":"closure_house"}}})
	var groups:={"closure_house":specs}
	ledger.arrived(specs[0],nodes[0],groups)
	check(ledger.pending.has("closure_house") and ledger.ready.is_empty(),"legacy explicit three-argument helper tracks an incomplete closure")
	ledger.arrived(specs[1],nodes[1],groups)
	check(ledger.ready.has("closure_house") and ledger.profile.early_requests==0,"legacy explicit helper recognizes closure without dispatching it")
	ledger.dispose()
	for node:Node in nodes:node.free()

func pending_retirement_rejection()->void:
	var f:=fixture();var specs:Array=[]
	for part:int in 8:
		var node:=source_node(f.mesh,"unseen_far_%d"%part,"unseen_far_house",part);node.position+=AWAY
		specs.append(Stream._spec(node,node.transform));node.free()
	append(f,specs,"unseen retirement")
	check(not f.map.has_meta(Stream.BATCH_ARRIVALS_META),"unseen retirement has no arrival ledger","fixture")
	var ids:Array=[]
	for spec:Dictionary in specs:ids.append(spec.uuid)
	var result:Dictionary=Stream.retire_specs(f.map,ids,true)
	check(not result.get("ok",true) and result.get("error")=="stream_busy","pending source publication refuses premature retirement through the real barrier")
	check(f.map.get_meta("stream_by_id",{}).size()==8,"failed premature retirement preserves all source identities")
	check(not f.map.has_meta(Stream.BATCH_ARRIVALS_META),"unseen retirement adds no batch accounting work","work")
	cases.append({"case":"pending_retirement_rejection","error":result.get("error","")})
	dispose(f)

func late_adoption()->void:
	var f:=fixture();append(f,make_specs(f,1),"adoption baseline")
	if not await settle(f,NEAR,"adoption baseline"):
		dispose(f);return
	var before_revision:int=f.map.get_meta("stream_visibility_revision",0)
	var before:=work(f.batch)
	for part:int in 4:
		var node:=source_node(f.mesh,"late_adopt_part_%02d"%part,"late_adopt_house",part)
		f.map.add_child(node)
	check(int(f.map.get_meta("stream_visibility_revision",0))==before_revision,"late adoption fixture does not manually bump visibility_revision","fixture")
	await settle(f,NEAR,"late adoption")
	check(f.map.get_meta("stream_meshes",{}).size()==12,"real adoption owns all four new flat sources")
	compare_full(f,"late adoption without forced revision")
	cases.append({"case":"late_adoption","revision_before":before_revision,"revision_after":f.map.get_meta("stream_visibility_revision",0),"before":before,"after":work(f.batch)})
	dispose(f)

func depart_return()->void:
	var f:=fixture();append(f,make_specs(f,2),"departure baseline")
	if not await settle(f,NEAR,"departure baseline"):
		dispose(f);return
	var old_owners:=membership(f.batch)
	await settle(f,AWAY,"departure")
	check(f.map.get_meta("stream_meshes",{}).is_empty() and f.batch.groups.is_empty(),"real departure removes all old source and batch membership")
	await settle(f,NEAR,"return")
	compare_full(f,"return after departure")
	var current:=membership(f.batch);var renewed:=current.size()==16
	for id:String in current:renewed=renewed and current[id]!=old_owners.get(id,0)
	check(renewed,"return obtains new live owners for every former UUID")
	check(f.map.get_meta(Stream.BATCH_ARRIVALS_META).profile.owner_loss_repairs==0,"normal departure and return do not create owner-loss repairs","work")
	cases.append({"case":"depart_return","final":work(f.batch)})
	dispose(f)

func same_uuid_replacement()->void:
	var f:=fixture();var specs:=make_specs(f,1);append(f,specs,"replacement baseline")
	if not await settle(f,NEAR,"replacement baseline"):
		dispose(f);return
	var old_owners:=membership(f.batch);var ids:Array=[]
	for spec:Dictionary in specs:ids.append(str(spec.uuid))
	# Runtime index retirement correctly refuses currently demanded sources.
	# Leave through real residency first; do not falsify the pin/source tables.
	if not await settle(f,AWAY,"replacement leaves demand"):
		dispose(f);return
	var retired:Dictionary=Stream.retire_specs(f.map,ids,true)
	check(retired.get("ok",false),"same UUID replacement uses real unpinned complete-unit retirement: "+str(retired.get("error","")),"fixture")
	if not retired.get("ok",false):
		dispose(f);return
	check(f.batch.groups.is_empty() and f.map.get_meta("stream_meshes",{}).is_empty(),"old replacement owners are absent immediately after retirement")
	var replacement:Array=[]
	var mesh:=BoxMesh.new();mesh.size=Vector3(.7,.5,.4);mesh.material=f.mesh.material
	for part:int in ids.size():
		var node:=source_node(mesh,ids[part],"arrival_house_000",part)
		var spec:Dictionary=Stream._spec(node,node.transform);node.free();replacement.append(spec)
	append(f,replacement,"same UUID new geometry")
	await settle(f,NEAR,"same UUID replacement")
	compare_full(f,"same UUID replacement")
	var current:=membership(f.batch);var changed:=current.size()==ids.size()
	for id:String in current:changed=changed and current[id]!=old_owners.get(id,0)
	check(changed,"same UUID replacement never reuses a retired Node identity")
	cases.append({"case":"same_uuid_replacement","final":work(f.batch)})
	dispose(f)

func unexpected_destruction()->void:
	var f:=fixture();append(f,make_specs(f,2),"unexpected-free baseline")
	if not await settle(f,NEAR,"unexpected-free baseline"):
		dispose(f);return
	var meshes:Dictionary=f.map.get_meta("stream_meshes");var id:String=meshes.keys()[1]
	var victim:Node=meshes[id];var old_identity:int=victim.get_instance_id()
	var old_group:String=f.batch._member_groups[id]
	# No Stream._drop, helper notification, revision bump or forced replan.
	# Exercise production tree-exit invalidation and lost-owner/_live repair.
	victim.free()
	check(not f.batch.groups.has(old_group),"unexpected non-leading source destruction immediately invalidates its live batch")
	await settle(f,NEAR,"unexpected source repair")
	compare_full(f,"unexpected source destruction and repair")
	var repaired:Variant=f.map.get_meta("stream_meshes",{}).get(id)
	check(is_instance_valid(repaired) and repaired.get_instance_id()!=old_identity,"real sync repairs destroyed UUID with a fresh source")
	cases.append({"case":"unexpected_destruction","id":id,"old_identity":old_identity,"final":work(f.batch)})
	dispose(f)

func run()->void:
	saved_frame_budget=FrameBudget.enabled;FrameBudget.enabled=false
	await incremental_work()
	await late_adoption()
	await depart_return()
	await same_uuid_replacement()
	await unexpected_destruction()
	await mutable_rebuild()
	await suspended_return()
	await mutable_worker()
	await late_ledger_owner_loss()
	closure_opt_in()
	pending_retirement_rejection()
	FrameBudget.enabled=saved_frame_budget
	var result:={"checks":checks,"failures":failures,"failures_by_kind":failures_by_kind,"cases":cases,"assertions":assertions,
		"mock_boundary":"final GPU commit only; real Stream.sync, eligibility, preparation, worker and generation paths",
		"sources":{"world_stream":FileAccess.get_sha256("res://scripts/world3d/world_stream.gd"),"ground_batcher":FileAccess.get_sha256("res://scripts/world3d/ground_batcher.gd"),"test":FileAccess.get_sha256("res://tools/test_stream_batch_arrival_pipeline.gd")}}
	if not output_path.is_empty():FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("STREAM_BATCH_ARRIVAL_PIPELINE ",JSON.stringify(result));quit(1 if failures else 0)
