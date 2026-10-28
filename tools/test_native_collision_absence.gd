extends "res://tools/test_collision_dependency_loader.gd"
## GPU setup publishes real native SCN; the measured/checked consumer phase
## runs only CPU workers with the authoring GLB removed. Fresh external files.
const NoneProof=preload("res://scripts/world3d/collision_not_required_preparation.gd")
const GeometryProof=preload("res://scripts/world3d/collision_instance_preparation.gd")
const NativeCompiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Native=preload("res://scripts/world3d/native_model_product.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")

class Observe extends RefCounted:
	var calls:=0
	var cancel_at:=-1
	func is_cancelled()->bool:
		calls+=1
		return cancel_at>=0 and calls>=cancel_at

func placed(id:String,path:String,at:int)->Dictionary:
	return {"uuid":id,"kind":"asset","asset_path":path,"position":[at*3,2,4],"rotation":[0,37,0],"size":[1,2,.5],"collision":"none"}

func packed_metadata(extra:Dictionary,group:bool=false)->PackedScene:
	var node:=Node3D.new();node.set_meta("extras",extra)
	if group:node.add_to_group("gameplay_test",true)
	var packed:=PackedScene.new();var error:=packed.pack(node);node.free()
	check(error==OK,"metadata fixture packs an actual SceneState")
	return packed

func run()->void:
	var errors:=Errors.new();OS.add_logger(errors)
	var policy:=preload("res://scripts/world3d/runtime_package_policy.gd")
	var old_policy:bool=policy.verify_packages;policy.verify_packages=true
	var manager:=root.get_node("AssetManager");var old_root:String=manager.content_root_override
	var old_none:bool=Loader.no_collision_proof_enabled;Loader.no_collision_proof_enabled=true
	folder=Paths.external_root().path_join("review_artifacts/native_collision_absence_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder);manager.content_root_override=folder
	var model:=folder.path_join("fixture.glb");fixture(model)
	var original_model:=FileAccess.get_file_as_bytes(model);var source_sha:=FileAccess.get_sha256(model)
	var built:=NativeCompiled.build(model);var measured:=Footprint.build(model,folder) if built.get("ok",false) else {}
	check(built.get("ok",false) and measured.get("ok",false),"explicit setup imports a real embedded-PNG model and publishes its native contract")
	var native:=Native.read(model,folder)
	check(not native.is_empty() and native.get("native_candidate",{}).get("collision_none_safe",false),"actual published SceneState is safe for an explicit-none ordinary record")
	if native.is_empty() or not native.native_candidate.get("collision_none_safe",false):
		manager.content_root_override=old_root;policy.verify_packages=old_policy;Loader.no_collision_proof_enabled=old_none;finish_contract(errors);return
	var product_path:String=native.native_product_path;var product_sha:=FileAccess.get_sha256(product_path)
	var index_path:=NativeCompiled.index_path(model,folder);var index_before:=FileAccess.get_file_as_bytes(index_path)
	var footprint_path:=Footprint.descriptor_path(model,folder);var footprint_before:=FileAccess.get_file_as_bytes(footprint_path)
	var building_path:=Footprint.building_descriptor_path(model,folder);var building_before:=FileAccess.get_file_as_bytes(building_path)
	var helper:=MapFixture.new();helper.folder=folder;helper.content_root=folder
	var records:Array=[]
	for i:int in 32:records.append(placed("item_%02d"%i,model,i))
	records[1].collision="block";records[2].erase("collision");records[3].color=[.5,.5,.5,1]
	var map_data:=helper.fixture("map",records);var path:String=map_data.path
	var indexed:=Index.build(path,folder,records);var issued:=Index.read_for_loading(path,folder)
	check(indexed.ok and issued.ok,"real rmres map receives a sealed dependency proof")
	if not issued.ok:
		helper.free();manager.content_root_override=old_root;policy.verify_packages=old_policy;Loader.no_collision_proof_enabled=old_none;finish_contract(errors);return
	var entries:Array=[]
	for i:int in records.size():entries.append(entry(issued.index,i))
	check(DirAccess.rename_absolute(model,model+".held")==OK,"remove optional authoring GLB before every consumer test")
	check(not NoneProof.plan(issued.index,entries,path,folder,issued.proof).ok,"main-thread absence work is refused")
	var plan:=await worker(NoneProof.plan.bind(issued.index,entries,path,folder,issued.proof))
	check(plan.ok and plan.positions.size()==32 and plan.native_model.payload_sha==product_sha,"one source-less native plan freezes all 32 instances and actual payload identity")
	if plan.ok:
		var denied:=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes-1))
		check(not denied.ok and denied.reason=="budget_not_admitted","under-admitted native proof does not hydrate definitions")
		var forged:=plan.duplicate();forged.estimated_bytes=1
		denied=await worker(NoneProof.prepare.bind(forged,1))
		check(not denied.ok and denied.reason=="plan_changed","caller cannot reduce recomputed metadata/reference budget")
		var observer:=Observe.new();Trace.start()
		var result:=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,observer));var trace:=Trace.stop()
		check(result.ok and result.proofs.size()==29 and result.fallbacks.size()==3,"source-less strict worker proves only explicit-none ordinary records")
		if result.ok:
			check(result.profile.source_sha_calls==0 and result.profile.native_identity_reads==2 and result.profile.map_sha_calls==2,"32 records share two native identity observations and zero GLB hashes")
			check(result.render_imports==0 and result.image_decodes==0 and result.face_expansions==0 and count_label(trace,"compiled.native_read")==0 and count_label(trace,"deferred.model_parse")==0,"consumer does not load SCN resources, import GLB, decode textures or expand faces")
			var receipt:NoneProof.Receipt=result.proofs.item_00
			check(receipt.source_sha()==source_sha and receipt.native_payload_sha()==product_sha and receipt.rule_version()==2,"typed receipt binds published source and payload identities")
			check(receipt.matches_context(issued.index,path,folder,issued.proof) and receipt.matches_entry(entries[0]) and not receipt.matches_entry(entries[1]),"receipt cannot authorize another instance or detached map context")
			check(result.retained_bytes==29*NoneProof.RECEIPT_BYTES,"receipt retention is charged per independent instance")
			var weak:WeakRef=weakref(receipt);receipt=null;result.clear()
			check(weak.get_ref()==null,"last proof owner releases without a hidden global receipt cache")
		var token:=Drainer.CancelToken.new();token.cancel()
		denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,token))
		check(not denied.ok and denied.cancelled and not denied.has("proofs"),"pre-cancel cannot seal a native absence receipt")
		var mid:=Observe.new();mid.cancel_at=maxi(2,observer.calls/2)
		denied=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes,mid))
		check(not denied.ok and denied.cancelled and not denied.has("proofs"),"mid-transaction cancellation retains no partial proof")
		var service:=Loader.new();var map:=attach(service,issued,path)
		check(service.request(entries,0,"native-none").ok,"real scheduler accepts source-less records")
		await wait_terminal(service,entries)
		check(service.status("item_00").state=="not_required" and service.status("item_01").state=="fallback","scheduler installs the typed none receipt and keeps block record on full-native fallback")
		var snapshot:Dictionary=service.snapshot()
		check(snapshot.store.get("owned_bodies",0)==0 and snapshot.store.get("shape_count",0)==0 and snapshot.none_proof_bytes==29*NoneProof.RECEIPT_BYTES,"absence publication creates no physics resources and accounts retained receipts")
		service.release_request("native-none")
		check(service.snapshot().none_proof_bytes==0,"releasing the request returns proof memory accounting to zero")
		service.cancel();var planning:RefCounted=service._planning;var preparing:RefCounted=service._preparing
		map.free();await wait_drained(planning,preparing)
		check(planning.count()==0 and preparing.count()==0,"scheduler worker reservations drain on disposal")
	# Old footprints are still valid normal native products, merely ineligible
	# for this opt-in shortcut. Refresh reads the same SCN while GLB is absent.
	var descriptor:Dictionary={};Footprint.candidate(model,folder,"",true,"",descriptor)
	descriptor.erase("collision_absence")
	check(Footprint._publish(descriptor,footprint_path,folder)==OK,"test publishes an actual legacy footprint without the optional field")
	var old_plan:=await worker(NoneProof.plan.bind(issued.index,entries,path,folder,issued.proof))
	check(not old_plan.ok and old_plan.reason=="native_collision_absence_unavailable" and not Native.read(model,folder).is_empty(),"missing absence metadata safely retains the complete native render route")
	var fallback:=await worker(Loader._plan_task.bind(issued.index,entries,path,folder,issued.proof,Drainer.CancelToken.new(),true,true))
	check(not fallback.ok and fallback.reason=="native_collision_absence_unavailable","scheduler forwards missing contract as full-native fallback without a GLB retry")
	var refreshed:=Footprint.refresh_collision_absence(model,folder)
	check(refreshed.get("ok",false) and refreshed.get("safe_for_explicit_none",false),"offline refresh derives the contract from published SCN with no GLB present")
	check(FileAccess.get_file_as_bytes(index_path)==index_before and FileAccess.get_sha256(product_path)==product_sha,"refresh preserves index and SCN bytes")
	# Replacing authoring bytes alone has no authority over a published model.
	put(model,"not a GLB; must never be parsed by a consumer".to_utf8_buffer())
	if plan.ok:
		var same:=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes))
		check(same.ok and same.proofs.size()==29,"changed optional source bytes do not invalidate the unchanged native publication")
		same.clear()
	put(model,original_model)
	for field:String in ["hostile","ally","event","seat","fixture","building","rmmo_model_components","unknown_behavior"]:
		var extra:Dictionary={};extra[field]=true
		check(not Footprint.collision_absence_from_packed(packed_metadata(extra)).safe_for_explicit_none,"SceneState gameplay metadata "+field+" cannot prove absence")
	check(not Footprint.collision_absence_from_packed(packed_metadata({"uuid":"visual"},true)).safe_for_explicit_none,"persistent gameplay groups cannot prove absence")
	check(Footprint.collision_absence_from_packed(packed_metadata({"uuid":"visual","rmmo_collision":"block","rmmo_wind":{"kind":"foliage"}})).safe_for_explicit_none,"visual whitelist remains eligible only when the record later explicitly requests none")
	# Geometry sidecars also consume published identity after their explicit
	# offline producer has completed, including the final transaction gate.
	var collision:=await worker(Builder.build.bind(model,folder,Builder.estimate(model,folder).estimated_bytes))
	var collision_ok:bool=collision.get("ok",false)
	check(collision_ok,"explicit producer creates real collision geometry before source removal")
	Drainer.dispose_result(collision)
	check(DirAccess.remove_absolute(model)==OK,"remove only the fixture's rewritten authoring copy")
	if collision_ok:
		var geometry_plan:=await worker(GeometryProof.plan.bind(issued.index,[entries[1]],path,folder,issued.proof))
		var geometry:=await worker(GeometryProof.prepare.bind(geometry_plan,int(geometry_plan.get("estimated_bytes",0))))
		check(geometry_plan.ok and geometry.ok and geometry.get("render_imports",1)==0,"geometry adapter reads CPU collision products and seals its batch without final GLB hashing")
		geometry.clear()
	put(model,original_model)
	# A deliberate new native publication invalidates the old frozen plan.
	fixture(model,4)
	var rebuilt:=NativeCompiled.build(model);var remeasured:=Footprint.build(model,folder) if rebuilt.get("ok",false) else {}
	check(rebuilt.get("ok",false) and remeasured.get("ok",false),"explicit reimport publishes an actual different native payload")
	if plan.ok:
		var stale:=await worker(NoneProof.prepare.bind(plan,plan.estimated_bytes))
		check(not stale.ok and not stale.has("proofs"),"old plan cannot borrow another native version after explicit reimport")
	put(model,original_model);put(index_path,index_before);put(footprint_path,footprint_before);put(building_path,building_before)
	check(FileAccess.get_sha256(model)==source_sha and FileAccess.get_sha256(product_path)==product_sha,"test restores original source/publication bytes and retains evidence files")
	helper.free();manager.content_root_override=old_root;policy.verify_packages=old_policy;Loader.no_collision_proof_enabled=old_none
	finish_contract(errors)

func finish_contract(errors:Logger)->void:
	OS.remove_logger(errors)
	check(errors.errors.is_empty(),"zero unexpected engine/script errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("NATIVE_COLLISION_ABSENCE passed=",passed," failures=",failed," root=",folder)
	quit(0 if failed==0 else 1)
