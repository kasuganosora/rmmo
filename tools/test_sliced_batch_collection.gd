extends SceneTree
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func collect(batch:Node)->Dictionary:
	var slices:=0;var maximum:=0.
	while not batch._preparation.is_empty() and batch._preparation.phase=="collect" and slices<20000:
		batch._prepare_step(1);maximum=maxf(maximum,batch.last_prepare_slice_ms);slices+=1
	check(not batch._preparation.is_empty() and batch._preparation.phase=="prepare","collection finishes before any mesh preparation")
	return {"names":batch._preparation.named.keys(),"excluded":batch._preparation.excluded.duplicate(),"slices":slices,"max_slice_ms":maximum}
func run()->void:
	var host:=Node3D.new();var nodes:Array=[];var components:Array=[]
	for i:int in 4000:
		var node:=Node3D.new();node.name="flat%d"%i;host.add_child(node);nodes.append(node)
	var imported:=Node3D.new();imported.name="large_model";host.add_child(imported)
	for i:int in 2200:
		var node:=Node3D.new();node.name="part%d"%i;imported.add_child(node);components.append(node)
	imported.set_meta("model_component_batch_sources",components);nodes.append(imported)
	var stale:=Node3D.new();nodes.append(stale);stale.free()
	var timings:Array=[];var expected:Dictionary={}
	for fast:bool in [false,true,true,false]:
		Batch.sliced_source_collection_enabled=fast
		var batch:=Batch.new();root.add_child(batch);batch.set_process(false)
		var began:=Time.get_ticks_usec();batch.request_sync(nodes,["large_model","flat17"]);var request_us:=Time.get_ticks_usec()-began
		if fast:check(batch._preparation.cursor==0 and batch._preparation.named.is_empty() and batch._preparation.components.is_empty(),"request only snapshots root handles; no source expansion runs before the budget")
		var result:=collect(batch)
		if expected.is_empty():expected=result
		check(result.names==expected.names and result.excluded==expected.excluded,"exact flat/component order and whole-model exclusion match synchronous expansion")
		check(result.names.size()==6200 and result.excluded.size()==2202,"all sources and selected child exclusions survive; freed input is ignored")
		timings.append({"sliced":fast,"request_us":request_us,"collection_slices":result.slices,"max_slice_ms":result.max_slice_ms})
		batch.free()
	Batch.sliced_source_collection_enabled=true
	var batch:=Batch.new();root.add_child(batch);batch.set_process(false)
	batch.request_sync([imported]);batch._prepare_step(1)
	check(batch._preparation.phase=="collect" and batch._preparation.component_cursor<2200,"a single 2200-part root cannot consume its children in one tiny slice")
	# Replacing a partially collected request must not leak its children or mask
	# an immediately excluded source. The new root list is a private snapshot.
	var fresh:Array=nodes.slice(0,1000);batch.request_sync(fresh,["flat17"]);fresh.clear()
	var result:=collect(batch)
	check(result.names.size()==1000 and not result.names.has("part0") and result.excluded==["flat17"],"superseding partial collection discards old components and owns its root snapshot")
	batch.clear();check(batch._preparation.is_empty(),"clear cancels pending collection")
	batch.free();host.free()
	print("SLICED_BATCH_COLLECTION ",JSON.stringify(timings)," failures=",failures)
	quit(1 if failures else 0)
