extends "res://tools/test_collision_instance_preparation.gd"
## GPU-only setup publishes real native SCN; consumers run CPU-only after
## authoring GLB removal. Real rmres, no fabricated receipt or native identity.
const NoneProof=preload("res://scripts/world3d/collision_not_required_preparation.gd")
const NativeFixture=preload("res://tools/collision_native_fixture.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
var previous_policy:=false
var previous_root:=""
var baseline_calls:=0

class Observe extends RefCounted:
	var calls:=0
	var mutate_at:=-1
	var action:Callable
	var mutated:=false
	var mutation_ok:=false
	var cancel_at:=-1
	func is_cancelled()->bool:
		calls+=1
		if calls==mutate_at:
			mutated=true;mutation_ok=action.call()
		return cancel_at>=0 and calls>=cancel_at

func final_mutation(plan:Dictionary,action:Callable,restore:Callable,reason:String,final_label:String="")->Dictionary:
	# Probe observed cancellation boundaries, never an old GLB hash count.
	# A pass requires the precise post-consumption gate, not merely any failure.
	for boundary:int in range(2,baseline_calls+1):
		var observer:=Observe.new();observer.mutate_at=boundary;observer.action=action
		Trace.start()
		var result:=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,observer));var trace:=Trace.stop()
		var restored:bool=restore.call()
		if not restored:return {"matched":false,"reason":"fixture_restore_failed"}
		if observer.mutated and observer.mutation_ok and not result.ok and result.reason==reason and not result.has("proofs") and (final_label.is_empty() or count_label(trace,final_label)==1):
			return {"matched":true,"boundary":boundary,"reason":reason}
	return {"matched":false,"reason":"final_gate_not_reached"}

func run()->void:
	previous_policy=Policy.verify_packages;Policy.verify_packages=true # Explicit rmres/map mutation diagnostic.
	var manager:=root.get_node("AssetManager");previous_root=manager.content_root_override
	var errors:=Errors.new();OS.add_logger(errors)
	folder=Paths.external_root().path_join("review_artifacts/collision_none_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder);manager.content_root_override=folder
	var model:=folder.path_join("fixture.glb");fixture(model)
	rewrite_nodes(model,func(data:Dictionary)->void:data.nodes[1].extras.merge({"rmmo_grass":true,"rmmo_leaf_backlight":[.18],"rmmo_visibility_range":[0,12],"rmmo_wind":{"kind":"foliage","amplitude":.055,"stiffness":.72}}))
	var original_model:=FileAccess.get_file_as_bytes(model)
	var publication:=NativeFixture.publish(model,folder)
	check(publication.get("ok",false) and publication.get("model",{}).get("native_candidate",{}).get("collision_none_safe",false),"actual GPU setup publishes the safe native SceneState")
	if not publication.get("ok",false):print(publication);finish(errors);return
	fixture(model,4)
	var replacement:=NativeFixture.publish(model,folder)
	check(replacement.get("ok",false) and replacement.get("payload_sha")!=publication.payload_sha,"explicit setup creates a different real native publication")
	if not replacement.get("ok",false):print(replacement);finish(errors);return
	check(NativeFixture.install(publication),"restore the original complete native publication")
	put(model,original_model)
	check(DirAccess.rename_absolute(model,model+".held")==OK,"remove authoring GLB before runtime consumers")
	var helper:=MapFixture.new();helper.folder=folder;helper.content_root=folder
	var records:Array=[]
	for i in 32:records.append(placed("item_%02d"%i,model,[i*3,2,4],[0,37,0],[1,2,.5],"none"))
	records[1].collision="block";records[2].erase("collision");records[3].color=[.5,.5,.5,1]
	var map:=helper.fixture("map",records);var path:String=map.path
	var built:=NativeFixture.index_build(path,folder,records);var issued:=NativeFixture.index_read(path,folder)
	check(built.ok and issued.ok and Cache.candidate(model,folder).is_empty(),"actual native/rmres source has a sealed index but no collision sidecar")
	if not issued.ok:helper.free();finish(errors);return
	var positions:Array=[]
	for i in records.size():positions.append(i)
	var req:=request(issued.index,positions)
	check(not NoneProof.plan(issued.index,req,path,folder,issued.proof).ok,"main-thread proof preparation is refused")
	var shell:=NoneProof.Receipt.new()
	check(shell.uuid().is_empty() and shell.map_path().is_empty() and shell.retained_bytes()==0 and not shell.matches_entry(req[0]),"unsealed typed shell grants no authority")
	var plan:=await worker(NoneProof.plan.bind(issued.index,req,path,folder,issued.proof))
	check(plan.ok and plan.positions.size()==32 and plan.retained_upper_bytes==32*NoneProof.RECEIPT_BYTES,"one bounded same-source plan covers 32 distinct instances")
	if not plan.ok:print(plan);helper.free();finish(errors);return
	var denied:=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes-1))
	check(not denied.ok and denied.reason=="budget_not_admitted","under-admitted workspace cannot hydrate definitions or create proofs")
	var fake:=plan.duplicate();fake.estimated_bytes=1
	denied=await worker(NoneProof.prepare.bind(fake,1))
	check(not denied.ok and denied.reason=="plan_changed","caller estimate cannot lower independently recomputed charge")
	denied=await worker(NoneProof.plan.bind(issued.index,req,path,folder,null))
	check(not denied.ok and denied.reason=="index_proof","ownership proof cannot be omitted")
	denied=await worker(NoneProof.plan.bind(issued.index.duplicate(true),req,path,folder,issued.proof))
	check(not denied.ok and denied.reason=="index_proof","copied index cannot borrow original sealed proof")
	var wrong:=req.duplicate(true);wrong[0].compact_record.position[0]+=1
	denied=await worker(NoneProof.plan.bind(issued.index,wrong,path,folder,issued.proof))
	check(not denied.ok and denied.reason=="entry_identity","caller pose cannot replace real compact identity")
	var watcher:=Observe.new();Trace.start()
	var result:=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,watcher));var trace:=Trace.stop();baseline_calls=watcher.calls
	check(result.ok and result.proofs.size()==29 and result.fallbacks.size()==3,"mixed batch proves only explicit-none ordinary instances")
	if not result.ok:print(result);helper.free();finish(errors);return
	check(result.fallbacks.item_01=="collision_not_explicit_none" and result.fallbacks.item_02=="collision_not_explicit_none" and result.fallbacks.item_03=="unsupported_record_semantics","same source does not transfer none to block/inherited/override records")
	check(result.profile.source_sha_calls==0 and result.profile.native_identity_reads==2 and result.profile.map_sha_calls==2,"32 instances share native before/after identity and map checks with zero GLB hashes")
	check(result.render_imports==0 and result.image_decodes==0 and result.face_expansions==0 and count_label(trace,"deferred.model_parse")==0 and count_label(trace,"deferred.scene_generate")==0 and count_label(trace,"deferred.cpu_capture")==0 and count_label(trace,"collision_product.read")==0 and count_label(trace,"compiled.native_read")==0,"source-less proof does no render import, native resource load, decode, capture or geometry-sidecar read")
	var receipt:NoneProof.Receipt=result.proofs.item_00
	check(receipt.map_path()==path and receipt.map_sha()==FileAccess.get_sha256(path) and receipt.source_sha()==publication.source_sha and receipt.native_payload_sha()==publication.payload_sha and receipt.rule_version()==2 and receipt.record_sha()==req[0].compact_record.rmmo_ref.sha256,"receipt binds published source/payload, full map SHA and exact rmres identity")
	check(receipt.matches_context(issued.index,path,folder,issued.proof) and receipt.matches_entry(req[0]) and not receipt.matches_entry(req[1]) and not receipt.matches_context(issued.index,path+"x",folder,issued.proof),"receipt cannot authorize another UUID or map context")
	var holder:=Node3D.new();holder.position=Index._vec(records[0].position);holder.rotation_degrees=Index._vec(records[0].rotation);holder.scale=Index._vec(records[0].size)
	check(receipt.pose()==holder.transform and receipt.bounds()==req[0].bounds,"receipt uses actual Node3D-equivalent pose and source-classified bounds");holder.free()
	var copy:=receipt.record_identity();copy.position[0]=999
	check(receipt.record_identity()==req[0].compact_record and receipt.retained_bytes()==NoneProof.RECEIPT_BYTES and result.retained_bytes==29*NoneProof.RECEIPT_BYTES,"receipt getters isolate aliases and retained charge is per independent metadata owner")
	check(not Library._scenes.has(model),"no private proof mutates the render asset library")
	var cancel:=Drainer.CancelToken.new();cancel.cancel()
	denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,cancel))
	check(not denied.ok and denied.cancelled and not denied.has("proofs"),"pre-cancel publishes no proof")
	var original_map:=FileAccess.get_file_as_bytes(path)
	put(path,original_map+" ".to_utf8_buffer());denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes));put(path,original_map)
	check(not denied.ok and denied.reason=="map_changed","changed map before preparation refuses stale ownership")
	put(model,"optional authoring bytes are not a runtime source".to_utf8_buffer())
	var unchanged:=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes))
	check(unchanged.ok and unchanged.proofs.size()==29,"optional GLB changes cannot invalidate the same published native product")
	unchanged.clear();check(DirAccess.remove_absolute(model)==OK,"remove optional authoring bytes again")
	check(NativeFixture.install(replacement),"switch to the actual replacement publication before prepare")
	denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes))
	check(NativeFixture.install(publication),"restore original native publication after stale-plan attempt")
	check(not denied.ok and denied.reason in ["native_manifest_changed","plan_changed"] and not denied.has("proofs"),"a changed native publication cannot borrow the old sealed plan")
	var resource:=Store._location(req[0].compact_record.rmmo_ref.uri,req[0].compact_record.rmmo_ref.sha256,path,folder)
	var original_resource:=FileAccess.get_file_as_bytes(resource);var corrupt:=original_resource.duplicate();corrupt[-1]^=1
	put(resource,corrupt);denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes));put(resource,original_resource)
	check(not denied.ok and str(denied.reason).begins_with("reference:"),"true rmres SHA validation rejects corrupted compressed author content")
	var race:=await final_mutation(plan,NativeFixture.install.bind(replacement),NativeFixture.install.bind(publication),"native_product_changed")
	check(race.matched,"native publication replacement after preparation fails final published-identity observation")
	race=await final_mutation(plan,NativeFixture.write_bytes.bind(resource,corrupt),NativeFixture.write_bytes.bind(resource,original_resource),"reference_changed")
	check(race.matched,"rmres modified after hydration fails final selected closure verification")
	race=await final_mutation(plan,NativeFixture.write_bytes.bind(path,original_map+" ".to_utf8_buffer()),NativeFixture.write_bytes.bind(path,original_map),"map_changed","collision.none.map_sha_after")
	check(race.matched,"map modified during preparation fails the final map hash, not just preflight")
	watcher=Observe.new();watcher.cancel_at=maxi(2,baseline_calls/2)
	denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,watcher))
	check(watcher.calls>=watcher.cancel_at and not denied.ok and denied.cancelled and not denied.has("proofs"),"mid-transaction cancellation cannot seal partial proofs")
	for field:String in ["hostile","ally","kind","event","seat","fixture","building","unknown_behavior"]:
		var semantic:=folder.path_join("semantic_"+field+".glb");fixture(semantic)
		rewrite_nodes(semantic,func(data:Dictionary)->void:data.nodes[1].extras[field]=true)
		var semantic_publication:=NativeFixture.publish(semantic,folder)
		check(semantic_publication.get("ok",false),"actual source "+field+" publishes a normal native product")
		if not semantic_publication.get("ok",false):print(semantic_publication);continue
		check(DirAccess.rename_absolute(semantic,semantic+".held")==OK,"remove "+field+" authoring source before consumers")
		var semantic_records:Array=[placed("unsafe",semantic,[0,0,0],[0,0,0],[1,1,1],"none")]
		var semantic_map:=helper.fixture(field,semantic_records);var semantic_built:=NativeFixture.index_build(semantic_map.path,folder,semantic_records);var semantic_index:=NativeFixture.index_read(semantic_map.path,folder)
		check(semantic_built.ok and semantic_index.ok,"native gameplay "+field+" remains a normal indexed asset")
		if semantic_index.ok:
			denied=await worker(NoneProof.plan.bind(semantic_index.index,request(semantic_index.index,[0]),semantic_map.path,folder,semantic_index.proof))
			check(not denied.ok and denied.reason=="native_collision_absence_unavailable" and not denied.has("proofs") and not NativeFixture.Native.read(semantic,folder).is_empty(),"record none cannot override native gameplay "+field+"; full native product remains valid")
	for field:String in ["animations","skins"]:
		var dynamic:=NativeFixture.structural_scene({},field)
		check(dynamic!=null and dynamic.get_state().get_node_count()==2,"actual "+field+" SceneState retains its dynamic node")
		var absence:=NativeFixture.Footprint.collision_absence_from_packed(dynamic)
		check(not absence.safe_for_explicit_none,"animated/deformed native structure "+field+" cannot obtain a static absence proof")
	for field:String in ["surface_paint","event","bridge_mesh","fixture","house_prefab","color","invisible"]:
		var special:Dictionary=records[0].duplicate(true);special[field]={}
		check(not NoneProof._supported(special),"special record "+field+" retains ordinary fallback")
	var weak:WeakRef=weakref(receipt);result.clear();receipt=null
	check(weak.get_ref()==null,"last proof owner releases without hidden global per-source receipt cache")
	check(not FileAccess.file_exists(model) and FileAccess.get_file_as_bytes(model+".held")==original_model and FileAccess.get_file_as_bytes(path)==original_map and NativeFixture.Native.read(model,folder).native_candidate.payload_sha==publication.payload_sha,"authoring stays absent and original native/map identities survive all mutations")
	helper.free();finish(errors)

func finish(errors:Logger)->void:
	root.get_node("AssetManager").content_root_override=previous_root;Policy.verify_packages=previous_policy
	remove_fixture(folder);OS.remove_logger(errors)
	check(errors.errors.is_empty(),"zero unexpected engine/script errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_NOT_REQUIRED passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
