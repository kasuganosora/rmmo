extends "res://tools/test_initial_native_texture_join.gd"
var metadata_gate:=Semaphore.new()
var metadata_entered:=false
var metadata_reads:=0
var held_sha:String
var candidates:Dictionary={}

func read_table(descriptor:Dictionary,root_:String)->Dictionary:
	counter_mutex.lock();metadata_reads+=1
	var held:bool=descriptor.texture_table.sha256==held_sha
	if held:metadata_entered=true
	counter_mutex.unlock()
	if held:metadata_gate.wait()
	return Binding.candidate_plan(descriptor,root_,{})

func run()->void:
	await metadata_case(false)
	await metadata_case(true)
	print("INITIAL_NATIVE_METADATA_ORDER ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func metadata_case(cancelled:bool)->void:
	geometry_reads=0;metadata_reads=0;metadata_entered=false
	make_fixture()
	var original_path:=content_root.path_join("cache/world3d/compiled_assets_v1/texture_tables_v1/"+str(candidate.texture_table.sha256)+".json")
	var encoded:=FileAccess.get_file_as_string(original_path)+" "
	var other_candidate:Dictionary=candidate.duplicate(true)
	other_candidate.texture_table.sha256=encoded.sha256_text();other_candidate.texture_table.bytes=encoded.to_utf8_buffer().size()
	var file:=FileAccess.open(original_path.get_base_dir().path_join(encoded.sha256_text()+".json"),FileAccess.WRITE);file.store_string(encoded);file.close()
	var other_scene:=packed.instantiate();other_scene.set_meta(Binding.TABLE_META,encoded.sha256_text())
	var other_packed:=PackedScene.new();check(other_packed.pack(other_scene)==OK,"second native model uses a separate immutable table");other_scene.free()
	var path:=content_root.path_join("held.glb");var other_path:=content_root.path_join("unblocked.glb")
	fixtures={path:{"packed":packed},other_path:{"packed":other_packed}};candidates={path:candidate,other_path:other_candidate}
	held_sha=candidate.texture_table.sha256
	var prep:=Preparation.new();var pool:=ControlledPool.new()
	prep.native_texture_pool=pool;prep.native_texture_preparer=fake_pixels;prep.native_texture_table_reader=read_table
	prep.require_native_products=true
	prep.memory_estimator=func(_path:String)->Dictionary:return {"estimated_bytes":4096,"exclusive":false}
	prep.candidate_provider=func(model:String)->Dictionary:return candidates[model]
	prep.candidate_reader=read_candidate
	var worker:=Thread.new();check(worker.start(prep.run.bind([path,other_path,path],Callable(),2,Callable(),content_root))==OK,"start initial coordinator")
	var deadline:=Time.get_ticks_msec()+5000;var independent:=false
	while worker.is_alive() and Time.get_ticks_msec()<deadline:
		if pool.snapshot().get("handoff_outputs",0)==1:independent=true;break
		await process_frame
	counter_mutex.lock();var reads:=geometry_reads;var entered:=metadata_entered;counter_mutex.unlock()
	check(independent and entered and reads==2,"one held table leaves the other model free to read geometry, load pixels, bind and hand off")
	if cancelled:prep.cancel();check(worker.is_alive(),"cancellation keeps the held metadata worker owned until join")
	metadata_gate.post()
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish();var metrics:Dictionary=result.native_texture_profile
	check(result.error==(ERR_SKIP if cancelled else OK),"all initial models preserve success/cancellation after the held table resumes")
	check(metadata_reads==2 and metrics.get("table_jobs",0)==2,"each root/table identity reads exactly once despite repeated model paths")
	check(pool.snapshot().streamed_loads==1 and metrics.unique_products==1,"different tables still share one native pixel producer")
	check(metrics.worker_slots_peak<=2 and result.threads_started==result.threads_joined,"table, geometry, pixel and binding stages share worker cap and join contract")
	check(metrics.get("metadata_peak_bytes",0)>0 and metrics.get("metadata_reserved_at_return",-1)==0,"retained scalar metadata is accounted until all consumers finish")
	var ledger:RefCounted=pool.admission
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(result)
	check(ledger.reserved_bytes==0 and ledger.count()==0 and pool.snapshot().consumers==0,"retirement clears every operation reservation")
	fixtures.clear();candidates.clear();material.albedo_texture=null;other_packed=null;packed=null;material=null
	print("METADATA_CASE ",JSON.stringify({"cancelled":cancelled,"profile":metrics}))
