extends SceneTree
## Exercise final handoff itself, without codec, GPU or authored map costs.
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Base=preload("res://tools/test_prefab_texture_preparation.gd")
var failures:=0
var checks:=0
var folder:=""
var paths:Array[String]=[]
class Admission extends RefCounted:
	func release(_id:String)->void:pass
class CancelAfter extends RefCounted:
	var remaining:=1
	func is_cancelled()->bool:
		remaining-=1;return remaining<=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func set_fast(enabled:bool)->void:
	Prep.batched_final_handoff_enabled=enabled
func worker(sources:Dictionary,shared:Dictionary,rounds:int)->Dictionary:
	var packet:={"sources":sources,"profile":{}}
	var valid:=true;var began:=Time.get_ticks_usec()
	for i:int in rounds:valid=Prep.verify(packet,folder,null,shared,true) and valid
	return {"valid":valid,"us":Time.get_ticks_usec()-began,"profile":packet.profile}
func run()->void:
	var logger:=Base.Errors.new();OS.add_logger(logger)
	folder=Prep.Paths.cache_directory("texture_handoff_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var sources:Dictionary={};var pool:=Pool.new();pool.admission=Admission.new()
	var shared:={"pool":pool,"consumer":"resident"}
	pool.commit("resident",pool.offer({"rows":{}}))
	for i:int in 64:
		var path:=folder.path_join("source_%d.bin"%i);paths.append(path)
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string("final handoff fixture "+str(i));file.close()
		sources[path]=path.sha256_text()
		pool.remember_source_identity("resident",path,sources[path])
	Prep.Pixels.Policy.verify_packages=false
	var trials:Array=[]
	for fast:bool in [false,true,true,false]:
		set_fast(fast)
		for count:int in [3,64]:
			var subset:Dictionary={}
			for i:int in count:subset[paths[i]]=sources[paths[i]]
			var rounds:=120 if count==3 else 24
			var began:=Time.get_ticks_usec();var workers:Array[Thread]=[]
			for i:int in 6:
				var thread:=Thread.new();check(thread.start(worker.bind(subset,shared,rounds))==OK,"start independent final-handoff worker");workers.append(thread)
			var results:Array=[]
			for thread:Thread in workers:
				while thread.is_alive():await process_frame
				results.append(thread.wait_to_finish())
			trials.append({"requested_fast":fast,"actual_fast":Prep.batched_final_handoff_enabled,"sources":count,"rounds":rounds,"wall_us":Time.get_ticks_usec()-began,"workers":results})
			check(results.all(func(row):return row.valid and row.profile.get("final_sha_reads",0)==0 and row.profile.final_source_identity_hits==count*rounds),"parallel handoffs preserve identities without file reads")
			check(results.all(func(row):return int(row.profile.get("final_identity_batches",0))==(rounds if fast else 0)),"requested A/B path actually executed")
	for fast:bool in [false,true]:
		set_fast(fast)
		check(Prep.verify({"sources":sources},folder,null,shared,true),"valid mounted handoff")
		check(Prep.verify({"sources":sources},folder),"trusted standalone handoff")
		var wrong:=sources.duplicate();wrong[paths[0]]="0".repeat(64)
		check(not Prep.verify({"sources":wrong},folder,null,shared,true),"reject mismatched mounted identity")
		check(not Prep.verify({"sources":wrong},folder),"reject mismatched standalone identity")
		check(not Prep.verify({"sources":sources},folder.path_join("other"),null,shared,true),"reject wrong content root even with a valid identity")
		check(not Prep.verify({"sources":sources},folder,CancelAfter.new(),shared,true),"reject cancellation before handoff")
		var token:=CancelAfter.new();token.remaining=2
		check(not Prep.verify({"sources":sources},folder,token,shared,true),"reject cancellation during handoff")
		check(not Prep.verify({"sources":{}},folder,CancelAfter.new(),shared,true),"empty handoff still checks cancellation")
		Prep.Pixels.Policy.verify_packages=true
		var packet:={"sources":{paths[0]:FileAccess.get_sha256(paths[0])},"profile":{}}
		check(Prep.verify(packet,folder) and packet.profile.final_sha_reads==1,"strict standalone still reads actual source")
		var file:=FileAccess.open(paths[0],FileAccess.WRITE);file.store_string("changed "+str(fast));file.close()
		check(not Prep.verify(packet,folder),"strict standalone rejects replaced bytes")
		Prep.Pixels.Policy.verify_packages=false
	pool.cancel("resident")
	check(not Prep.verify({"sources":{}},folder,null,shared,true),"cancelled pool consumer cannot authorize empty packet")
	pool.release("resident")
	check(not Prep.verify({"sources":sources},folder,null,shared,true),"released consumer cannot authorize known identities")
	check(pool.snapshot().outputs==0 and pool.snapshot().consumers==0,"all shared owners retired")
	for path:String in paths:DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	print("TEXTURE_FINAL_HANDOFF ",JSON.stringify({"trials":trials,"checks":checks,"failures":failures}))
	quit(0 if failures==0 else 1)
