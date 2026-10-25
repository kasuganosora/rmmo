extends SceneTree
## Resident-texture CPU regression: no authored assets, GPU upload or game map.
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
var failures:=0
var folder:=""
var paths:Array[String]=[]
var packets:Array=[]
class Admission extends RefCounted:
	func release(_id:String)->void:pass
class Cancelled extends RefCounted:
	func is_cancelled()->bool:return true
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func context(pool:RefCounted,plan:Dictionary,consumer:String,cached:Dictionary)->Dictionary:
	var offer:Dictionary=pool.offer(plan,cached);pool.commit(consumer,offer)
	return {"pool":pool,"consumer":consumer,"leaders":offer.leaders,"cached":offer.cached}
func resident_round(pool:RefCounted,requested:Dictionary,plan:Dictionary,cached:Dictionary,rounds:int,prefix:String)->Dictionary:
	var totals:={"source_sha_reads":0,"source_sha_bytes":0,"source_identity_hits":0,"final_sha_reads":0,"final_source_identity_hits":0,"persist_sha_reads":0}
	var valid:=true;var began:=Time.get_ticks_usec()
	for i:int in rounds:
		var shared:=context(pool,plan,prefix+str(i),cached)
		var packet:=Prep.prepare(requested,plan,folder,null,true,shared,true)
		valid=valid and packet.error.is_empty() and packet.images.is_empty() and int(packet.profile.get("resident_hits",0))==requested.size()
		for field:String in totals:totals[field]+=int(packet.profile.get(field,0))
		pool.release(shared.consumer)
	return {"valid":valid,"totals":totals,"elapsed_us":Time.get_ticks_usec()-began}
func new_pool()->RefCounted:
	var pool:=Pool.new();pool.admission=Admission.new();return pool
func save_source(path:String,color:Color)->void:
	var image:=Image.create(19,13,false,Image.FORMAT_RGBA8);image.fill(color)
	check(image.save_png(path)==OK,"write isolated tiny PNG")
func threaded_prepare(requested:Dictionary,plan:Dictionary,shared:Dictionary)->Dictionary:
	return Prep.prepare(requested,plan,folder,null,true,shared,true)
func retired_leader_round(path:String)->Dictionary:
	var requested:={path:[path,false],path+"|flip_y":[path,true]}
	var plan:=Prep.estimate(requested,folder);var pool:=new_pool()
	var seed_context:=context(pool,plan,"retired_seed",{})
	var seed:=Prep.prepare(requested,plan,folder,null,true,seed_context,true)
	check(seed.error.is_empty() and seed.images.size()==2,"seed both orientation caches through a genuine leader")
	var expected:Dictionary={}
	for key:String in seed.images:expected[key]=seed.images[key].get_data()
	seed.clear();pool.release(seed_context.consumer)
	var reads:=0;var hits:=0;var valid:=true
	for i:int in 20:
		var shared:=context(pool,plan,"retired_%d"%i,{})
		var packet:=Prep.prepare(requested,plan,folder,null,true,shared,true)
		valid=valid and packet.error.is_empty() and packet.images.size()==2 and int(packet.profile.get("final_sha_reads",0))==0
		for key:String in packet.images:valid=valid and packet.images[key].get_data()==expected[key]
		reads+=int(packet.profile.get("source_sha_reads",0));hits+=int(packet.profile.get("cache_hits",0))
		packet.clear();pool.release(shared.consumer)
	check(valid and hits==40,"retired pixels reload both normal orientations exactly from derived caches")
	check(reads==0,"known mounted leader cache hits do zero full source reads after pixel retirement")
	check(pool.snapshot().outputs==0 and pool.snapshot().consumers==0,"retired cache-hit leaders leave no pixel owners or consumers")
	DirAccess.remove_absolute(Prep.Pixels.cache_path(path,true))
	var miss_context:=context(pool,plan,"retired_miss",{})
	var miss:=Prep.prepare(requested,plan,folder,null,true,miss_context,true)
	check(miss.error.is_empty() and miss.profile.source_sha_reads==1 and miss.profile.decoded==1 and miss.profile.cache_hits==1,"only the missing orientation reads source bytes and decodes")
	for key:String in miss.images:check(miss.images[key].get_data()==expected[key],"cache-miss orientation preserves complete mip pixels")
	miss.clear();pool.release(miss_context.consumer)
	var corrupt:=FileAccess.open(Prep.Pixels.cache_path(path,false),FileAccess.WRITE);corrupt.store_buffer(PackedByteArray([1,2,3]));corrupt.close()
	var bad_context:=context(pool,plan,"retired_bad_cache",{})
	var bad:=Prep.prepare(requested,plan,folder,null,true,bad_context,true)
	check(bad.error.is_empty() and bad.profile.source_sha_reads==1 and bad.profile.decoded==1 and bad.profile.cache_hits==1,"truncated derived cache falls back to one bounded source decode")
	check(bad.error.is_empty() and bad.images[path].get_data()==expected[path],"bad derived cache cannot substitute different pixels")
	if bad.error.is_empty():check(Prep.Pixels.store_pixels(path,false,bad.images[path],"f".repeat(64)),"write isolated wrong-generation derived cache")
	bad.clear();pool.release(bad_context.consumer)
	var stale_context:=context(pool,plan,"retired_stale_cache",{})
	var stale:=Prep.prepare(requested,plan,folder,null,true,stale_context,true)
	check(stale.error.is_empty() and stale.profile.source_sha_reads==1 and stale.profile.decoded==1 and stale.images[path].get_data()==expected[path],"wrong-generation cache is rejected without changing the operation identity")
	stale.clear();pool.release(stale_context.consumer)
	var cancel_context:=context(pool,plan,"retired_cancel",{})
	check(Prep.prepare(requested,plan,folder,Cancelled.new(),true,cancel_context,true).cancelled,"token cancellation still rejects known cache-hit leader")
	pool.cancel(cancel_context.consumer)
	check(not Prep.prepare(requested,plan,folder,null,true,cancel_context,true).error.is_empty(),"cancelled consumer cannot restore a known cached image")
	pool.release(cancel_context.consumer)
	var strict_context:=context(pool,plan,"retired_strict",{})
	var strict:=Prep.prepare(requested,plan,folder,null,true,strict_context,false)
	check(strict.error.is_empty() and strict.profile.source_sha_reads==2 and strict.profile.final_sha_reads==1,"strict caller still reads actual source for both variants and verifies the final identity")
	strict.clear();pool.release(strict_context.consumer)
	var original:=FileAccess.get_file_as_bytes(path);save_source(path,Color(.8,.6,.1,1.))
	var next_requested:={path:[path,false]};var next_plan:=Prep.estimate(next_requested,folder)
	var next_pool:=new_pool();var next_context:=context(next_pool,next_plan,"retired_new_operation",{})
	var fresh:=Prep.prepare(next_requested,next_plan,folder,null,true,next_context,true)
	check(fresh.error.is_empty() and fresh.profile.source_sha_reads==1 and fresh.profile.decoded==1 and fresh.sources[path]==FileAccess.get_sha256(path) and fresh.images[path].get_data()!=expected[path],"new operation reads changed same-path source and invalidates the old derived cache")
	fresh.clear();next_pool.release(next_context.consumer)
	var restored:=FileAccess.open(path,FileAccess.WRITE);restored.store_buffer(original);restored.close()
	return {"rounds":20,"cache_hits":hits,"source_sha_reads":reads,"pixels_equal":valid}
func run()->void:
	folder=Prep.Paths.cache_directory("texture_source_identity_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var requested:Dictionary={};var cached:Dictionary={};var source_bytes:=0
	for i:int in 3:
		var path:=folder.path_join("source_%d.png"%i);paths.append(path);save_source(path,Color(.2+i*.1,.3,.7,1.))
		var digest:=FileAccess.get_sha256(path);source_bytes+=FileAccess.get_file_as_bytes(path).size()
		requested[path]=[path,false];requested[path+"|flip_y"]=[path,true]
		cached[path]=digest;cached[path+"|flip_y"]=digest
	var plan:=Prep.estimate(requested,folder)
	var original_switch:bool=Prep.mounted_source_reuse_enabled;Prep.mounted_source_reuse_enabled=false
	var legacy_pool:=new_pool();var legacy:=resident_round(legacy_pool,requested,plan,cached,100,"legacy_")
	check(legacy.valid and legacy.totals.source_sha_reads==300 and legacy.totals.final_sha_reads==300,"diagnostic old path reproduces 600 SHA reads for 100 consumers and 3 sources")
	Prep.mounted_source_reuse_enabled=true
	var pool:=new_pool();var optimized:=resident_round(pool,requested,plan,cached,100,"mounted_")
	check(optimized.valid,"100 resident consumers reuse three sources in both orientations without producing images")
	check(optimized.totals.source_sha_reads==3 and optimized.totals.source_sha_bytes==source_bytes,"mounted source reads scale with unique paths rather than consumers or variants")
	check(optimized.totals.source_identity_hits==297,"later consumers use scalar source identities before opening the source")
	check(optimized.totals.final_sha_reads==0 and optimized.totals.final_source_identity_hits==300,"mounted final checks do no extra source reads")
	check(pool.snapshot().consumers==0 and pool.snapshot().outputs==0 and pool.snapshot().source_identities==3,"released consumers retain only three operation-local scalar identities")
	var known:=context(pool,plan,"known",cached)
	var cancelled:=Prep.prepare(requested,plan,folder,Cancelled.new(),true,known,true)
	check(cancelled.cancelled and not cancelled.error.is_empty(),"cancellation token rejects even a cached mounted identity")
	pool.cancel(known.consumer)
	check(not Prep.verify({"sources":{},"profile":{}},folder,null,known,true),"cancelled consumer cannot authorize even an empty final packet")
	check(not pool.remember_source_identity(known.consumer,paths[0],cached[paths[0]]),"cancelled consumer cannot insert or refresh source identity")
	pool.release(known.consumer)
	check(not Prep.prepare(requested,plan,folder,null,true,known,true).error.is_empty(),"released consumer cannot authorize another mounted packet")
	var wrong:=cached.duplicate();wrong[paths[0]]="0".repeat(64)
	var wrong_context:=context(pool,plan,"wrong_ticket",wrong)
	check(not Prep.prepare(requested,plan,folder,null,true,wrong_context,true).error.is_empty(),"resident ticket must still match the first observed source identity")
	pool.release(wrong_context.consumer)
	var original:=FileAccess.get_file_as_bytes(paths[0])
	save_source(paths[0],Color(.9,.1,.2,1.))
	var changed_digest:=FileAccess.get_sha256(paths[0])
	var single:={paths[0]:[paths[0],false]};var changed_plan:=Prep.estimate(single,folder)
	var conflict:=context(pool,changed_plan,"changed_leader",{})
	check(not Prep.prepare(single,changed_plan,folder,null,true,conflict,true).error.is_empty(),"new leader hashes actual bytes and rejects a conflicting first identity")
	check(pool.source_identity(conflict.consumer,paths[0])==cached[paths[0]],"a conflicting reader cannot overwrite the operation first identity")
	pool.release(conflict.consumer)
	var next_pool:=new_pool();var fresh_context:=context(next_pool,changed_plan,"new_load",{paths[0]:changed_digest})
	var fresh:=Prep.prepare(single,changed_plan,folder,null,true,fresh_context,true)
	check(fresh.error.is_empty() and fresh.sources[paths[0]]==changed_digest and fresh.profile.source_sha_reads==1,"a new load/pool hashes the updated same-path source afresh")
	var mutable_packet:={"sources":{paths[0]:changed_digest},"profile":{}}
	var file:=FileAccess.open(paths[0],FileAccess.WRITE);file.store_buffer(original);file.close()
	check(not Prep.verify(mutable_packet,folder) and mutable_packet.profile.final_sha_reads==1,"standalone default strict verification rejects a source changed after prepare")
	check(Prep.verify(fresh,folder,null,fresh_context,true) and fresh.profile.final_sha_reads==0,"mounted snapshot intentionally does not track external mutations during the same load")
	next_pool.release(fresh_context.consumer)
	# First misses may race; neither worker waits for the other's file I/O.
	var parallel_pool:=new_pool();var workers:Array[Thread]=[];var contexts:Array=[]
	for i:int in 2:
		var shared:=context(parallel_pool,plan,"parallel_%d"%i,cached);contexts.append(shared)
		var worker:=Thread.new();check(worker.start(threaded_prepare.bind(requested,plan,shared))==OK,"independent identity worker starts");workers.append(worker)
	var reads:=0;var parallel_ok:=true
	for i:int in workers.size():
		while workers[i].is_alive():await process_frame
		var packet:Dictionary=workers[i].wait_to_finish()
		parallel_ok=parallel_ok and packet.error.is_empty() and packet.profile.final_sha_reads==0
		reads+=int(packet.profile.get("source_sha_reads",0));parallel_pool.release(contexts[i].consumer)
	check(parallel_ok and reads>=3 and reads<=6 and parallel_pool.snapshot().source_identities==3,"concurrent first misses complete independently with at most one read per worker/source")
	var queue:=Deferred.new();queue.configure_references({},"fixture",folder)
	var first_pool:RefCounted=queue._shared_images;first_pool.admission=Admission.new()
	var first_operation:=resident_round(first_pool,requested,plan,cached,1,"queue_first_")
	queue.configure_references({},"fixture",folder)
	var second_pool:RefCounted=queue._shared_images;second_pool.admission=Admission.new()
	var second_operation:=resident_round(second_pool,requested,plan,cached,1,"queue_second_")
	check(first_pool!=second_pool and first_operation.valid and second_operation.valid and first_operation.totals.source_sha_reads==3 and second_operation.totals.source_sha_reads==3,"reconfiguring an idle queue creates a fresh pool and hashes each source again")
	queue._jobs["fixture"]={};queue.configure_references({},"fixture",folder)
	check(queue._shared_images==second_pool,"reconfiguration cannot replace a pool while jobs still own its consumers")
	queue._jobs.clear();queue.free()
	# A genuine leader still reads/hashes bytes before decoding and persistence.
	var leader_plan:=Prep.estimate(single,folder)
	var leader_pool:=new_pool();var leader_context:=context(leader_pool,leader_plan,"leader",{})
	var leader:=Prep.prepare(single,leader_plan,folder,null,true,leader_context,true)
	packets.append(leader)
	check(leader.error.is_empty() and leader.images.size()==1 and leader.profile.source_sha_reads==1,"leader reads the actual source bytes for its derived-cache identity")
	check(leader.error.is_empty() and leader.profile.final_sha_reads==0 and leader.profile.persist_sha_reads==0 and int(leader.profile.get("persist_source_identity_hits",0))==1,"mounted cache persistence and final handoff perform no second SHA read")
	packets.clear();leader.clear();leader_pool.release(leader_context.consumer)
	var retired:=retired_leader_round(paths[0])
	Prep.mounted_source_reuse_enabled=original_switch
	for path:String in paths:
		for flip:bool in [false,true]:
			var cache:String=Prep.Pixels.cache_path(path,flip)
			if FileAccess.file_exists(cache):DirAccess.remove_absolute(cache)
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	print("PREFAB_TEXTURE_SOURCE_IDENTITY ",JSON.stringify({"legacy":legacy,"optimized":optimized,"parallel_first_miss_reads":reads,"retired_leaders":retired,"failures":failures}));quit(0 if failures==0 else 1)
