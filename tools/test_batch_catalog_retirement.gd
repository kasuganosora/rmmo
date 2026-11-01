extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func fill(batch:Node,target:Node,count:int)->Array:
	var watches:Array=[];var prepared:Dictionary={};var desired:Dictionary={}
	for i in count:
		var reference:WeakRef=weakref(target);watches.append(weakref(reference))
		var descriptor:={"reference":reference,"pose":Transform3D.IDENTITY,"base":"base_%d"%i,"keys":["stone","glass"],"category":"building","vertices":256,"limit":32}
		batch._residency_descriptors[i]=descriptor;prepared[str(i)]=descriptor
		if i%32==0:desired[str(i)]={"members":[target],"data":{"mesh":BoxMesh.new()}}
	batch._residency_bins={"prepared_descriptors":prepared,"desired":desired,"runtime_roots":[target]}
	# Same raw table in an active preparation: preserve once, without deep scans.
	batch._preparation={"phase":"add","prepared_descriptors":prepared,"desired":desired,"raw_desired":desired}
	return watches
func run()->void:
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	var map:=Node3D.new();root.add_child(map)
	var batch:=Batch.new();batch.name="GroundRenderBatches";map.add_child(batch);batch.set_process(false)
	var target:=Node3D.new();map.add_child(target)
	var watches:Array=fill(batch,target,4096)
	var borrowed:Dictionary=batch._residency_descriptors[0]
	var started:=Time.get_ticks_usec();Stream.prepare_map_disposal(map,self);var prepare_us:=Time.get_ticks_usec()-started
	var service:Node=root.get_node_or_null(Retirement.NODE_NAME)
	if service!=null:service.set_process(false)
	check(batch._preparation.is_empty() and batch._residency_bins.is_empty() and batch._residency_descriptors.is_empty(),"logical catalog invalidation remains immediate")
	check(watches.all(func(w:WeakRef):return w.get_ref()!=null),"permanent preparation keeps each final descriptor owner out of the commit")
	check(service!=null and not service.pending.is_empty(),"catalog owners enter the existing MAIN retirement queue")
	map.free()
	var slice_us:=0;var max_slice_us:=0;var calls:=0
	if service!=null:
		var deadline:=Time.get_ticks_msec()+10000
		while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:
			started=Time.get_ticks_usec();service._process(0.);var elapsed:=Time.get_ticks_usec()-started
			slice_us+=elapsed;max_slice_us=maxi(max_slice_us,elapsed);calls+=1
			service.set_process(false);await process_frame
		check(service.pending.is_empty() and service.known.is_empty(),"all donated layers drain through the production scheduler")
	check(watches.slice(1).all(func(w:WeakRef):return w.get_ref()==null),"all unborrowed native WeakRef owners are eventually released")
	check(borrowed.keys==["stone","glass"] and borrowed.category=="building" and watches[0].get_ref()!=null,"a surviving descriptor borrower is never cleared or edited")
	borrowed={}
	check(watches[0].get_ref()==null,"the final external borrower releases normally")
	var result:={"checks":checks,"failures":failures,"descriptors":4096,"prepare_us":prepare_us,"retirement_us":slice_us,"max_slice_us":max_slice_us,"callbacks":calls,"scope":"native WeakRef/catalog ownership component; no map performance claim"}
	if service!=null:result.profile=service.profile.duplicate();service.free()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("BATCH_CATALOG_RETIREMENT ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
