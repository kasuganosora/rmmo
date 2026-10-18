extends "res://tools/test_collision_instance_preparation.gd"
## Real small embedded PNG GLB and real rmres, with no import/texture decoding.
const NoneProof=preload("res://scripts/world3d/collision_not_required_preparation.gd")

class Observe extends RefCounted:
	var calls:=0
	var mutate_at:=-1
	var path:=""
	var bytes:=PackedByteArray()
	var cancel_at:=-1
	func is_cancelled()->bool:
		calls+=1
		if calls==mutate_at:
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
		return cancel_at>=0 and calls>=cancel_at

func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=true # Explicit source replacement diagnostic.
	var errors:=Errors.new();OS.add_logger(errors)
	folder=Paths.cache_directory("collision_none_test_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var model:=folder.path_join("fixture.glb");fixture(model)
	rewrite_nodes(model,func(data:Dictionary)->void:data.nodes[1].extras.merge({"rmmo_grass":true,"rmmo_leaf_backlight":[.18],"rmmo_visibility_range":[0,12],"rmmo_wind":{"kind":"foliage","amplitude":.055,"stiffness":.72}}))
	var original_model:=FileAccess.get_file_as_bytes(model)
	var helper:=MapFixture.new();helper.folder=folder;helper.content_root=folder
	var records:Array=[]
	for i in 32:records.append(placed("item_%02d"%i,model,[i*3,2,4],[0,37,0],[1,2,.5],"none"))
	records[1].collision="block";records[2].erase("collision");records[3].color=[.5,.5,.5,1]
	var map:=helper.fixture("map",records);var path:String=map.path
	var built:=Index.build(path,folder,records);var issued:=Index.read_for_loading(path,folder)
	check(built.ok and issued.ok and Cache.candidate(model,folder).is_empty(),"actual GLB/rmres source has a sealed index but no collision sidecar")
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
	var result:=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,watcher));var trace:=Trace.stop()
	check(result.ok and result.proofs.size()==29 and result.fallbacks.size()==3,"mixed batch proves only explicit-none ordinary instances")
	if not result.ok:print(result);helper.free();finish(errors);return
	check(result.fallbacks.item_01=="collision_not_explicit_none" and result.fallbacks.item_02=="collision_not_explicit_none" and result.fallbacks.item_03=="unsupported_record_semantics","same source does not transfer none to block/inherited/override records")
	check(result.profile.source_sha_calls==2 and result.profile.map_sha_calls==2,"32 instances share exactly one source/map verification transaction")
	check(result.render_imports==0 and result.image_decodes==0 and result.face_expansions==0 and count_label(trace,"deferred.model_parse")==0 and count_label(trace,"deferred.scene_generate")==0 and count_label(trace,"deferred.cpu_capture")==0 and count_label(trace,"collision_product.read")==0,"valid embedded-PNG proof does no import, decode, capture or sidecar read")
	var receipt:NoneProof.Receipt=result.proofs.item_00
	check(receipt.map_path()==path and receipt.map_sha()==FileAccess.get_sha256(path) and receipt.source_sha()==FileAccess.get_sha256(model) and receipt.record_sha()==req[0].compact_record.rmmo_ref.sha256,"receipt binds full source/map SHA and exact rmres identity")
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
	rewrite_nodes(model,func(data:Dictionary)->void:data.nodes[1].extras.rmmo_visibility_range=[0,13])
	denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes));put(model,original_model)
	check(not denied.ok and denied.reason=="source_manifest_changed" and not denied.has("proofs"),"same-size source JSON change cannot borrow the sealed directory bounds/semantics")
	var resource:=Store._location(req[0].compact_record.rmmo_ref.uri,req[0].compact_record.rmmo_ref.sha256,path,folder)
	var original_resource:=FileAccess.get_file_as_bytes(resource);var corrupt:=original_resource.duplicate();corrupt[-1]^=1
	put(resource,corrupt);denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes));put(resource,original_resource)
	check(not denied.ok and str(denied.reason).begins_with("reference:"),"true rmres SHA validation rejects corrupted compressed author content")
	# The source first SHA runs after map SHA and real reference hydration. Tiny
	# files each require one bounded hash block. Mutate on the first final-source
	# cancellation check, after JSON semantics/classification have been consumed.
	var changed:=original_model.duplicate();changed[-1]^=1
	watcher=Observe.new();watcher.path=model;watcher.bytes=changed;watcher.mutate_at=11
	denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,watcher));put(model,original_model)
	check(not denied.ok and denied.reason=="asset_changed" and not denied.has("proofs"),"same-length binary replacement after JSON validation fails final full GLB SHA")
	watcher=Observe.new();watcher.path=resource;watcher.bytes=corrupt;watcher.mutate_at=11
	denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,watcher));put(resource,original_resource)
	check(not denied.ok and denied.reason=="reference_changed","rmres modified after hydration fails final selected closure verification")
	watcher=Observe.new();watcher.path=path;watcher.bytes=original_map+" ".to_utf8_buffer();watcher.mutate_at=11
	denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,watcher));put(path,original_map)
	check(not denied.ok and denied.reason=="map_changed","map modified during preparation fails final full source SHA")
	watcher=Observe.new();watcher.cancel_at=11
	denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,watcher))
	check(not denied.ok and denied.cancelled and not denied.has("proofs"),"mid-transaction cancellation cannot seal partial proofs")
	for field:String in ["hostile","ally","kind","event","seat","fixture","building","unknown_behavior"]:
		var semantic:=folder.path_join("semantic_"+field+".glb");fixture(semantic)
		rewrite_nodes(semantic,func(data:Dictionary)->void:data.nodes[1].extras[field]=true)
		var semantic_records:Array=[placed("unsafe",semantic,[0,0,0],[0,0,0],[1,1,1],"none")]
		var semantic_map:=helper.fixture(field,semantic_records);var semantic_built:=Index.build(semantic_map.path,folder,semantic_records);var semantic_index:=Index.read_for_loading(semantic_map.path,folder)
		check(semantic_built.ok and semantic_index.ok,"real source "+field+" remains a normal indexed asset")
		if semantic_index.ok:
			var semantic_plan:=await worker(NoneProof.plan.bind(semantic_index.index,request(semantic_index.index,[0]),semantic_map.path,folder,semantic_index.proof))
			denied=await worker(NoneProof.prepare.bind(semantic_plan,semantic_plan.get("estimated_bytes",0)))
			check(not denied.ok and denied.reason=="unsupported_source_semantics" and not denied.has("proofs"),"record none cannot override source gameplay "+field)
	for field:String in ["animations","skins"]:
		var animated:=folder.path_join("source_"+field+".glb");fixture(animated)
		rewrite_nodes(animated,func(data:Dictionary)->void:data[field]=[{"name":"unsupported"}])
		var animated_records:Array=[placed("dynamic",animated,[0,0,0],[0,0,0],[1,1,1],"none")]
		var animated_map:=helper.fixture("source_"+field,animated_records);var animated_built:=Index.build(animated_map.path,folder,animated_records);var animated_index:=Index.read_for_loading(animated_map.path,folder)
		check(animated_built.ok and animated_index.ok,"actual "+field+" remains available to conservative directory fallback")
		if animated_index.ok:
			denied=await worker(NoneProof.plan.bind(animated_index.index,request(animated_index.index,[0]),animated_map.path,folder,animated_index.proof))
			check(not denied.ok and denied.reason=="unsupported_record","animated/deformed source "+field+" cannot obtain a static absence proof")
	for field:String in ["surface_paint","event","bridge_mesh","fixture","house_prefab","color","invisible"]:
		var special:Dictionary=records[0].duplicate(true);special[field]={}
		check(not NoneProof._supported(special),"special record "+field+" retains ordinary fallback")
	var weak:WeakRef=weakref(receipt);result.clear();receipt=null
	check(weak.get_ref()==null,"last proof owner releases without hidden global per-source receipt cache")
	check(FileAccess.get_file_as_bytes(model)==original_model and FileAccess.get_file_as_bytes(path)==original_map,"fixture source bytes restored after all mutations")
	helper.free();finish(errors)

func finish(errors:Logger)->void:
	remove_fixture(folder);OS.remove_logger(errors)
	check(errors.errors.is_empty(),"zero unexpected engine/script errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_NOT_REQUIRED passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
