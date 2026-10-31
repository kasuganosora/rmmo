extends SceneTree
## Reproduce the measured owner shapes: record Arrays as cache keys, CPU meshes
## as dictionary values, and per-group mesh owners retained by clear()'s loop.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Queue=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
class Journal extends RefCounted:
	var freed:=0
	var off_main:=0
class Owner extends Resource:
	var journal:Journal
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			journal.freed+=1
			if not Thread.is_main_thread():journal.off_main+=1
var checks:=0
var failures:Array=[]
var trials:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func owner(journal:Journal)->Resource:
	var value:=Owner.new();value.journal=journal;return value
func fixture(kind:String,journal:Journal)->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	var borrow:Dictionary={}
	if kind=="document":
		var queue:=Queue.new();queue.name="DeferredAssets";map.add_child(queue);queue.set_process(false)
		queue._doc.load_immutable_records=true;queue._doc.load_box_meshes={};queue._doc.load_material_pool={};queue._doc.load_paint_validation={}
		for i in 303:
			var polygons:Array=[]
			for j in 128:polygons.append([[float(i),float(j)],[float(i+1),float(j)],[float(i),float(j+1)]])
			var record:={"uuid":str(i),"road_mesh":{"polygons":polygons},"key_owner":owner(journal)}
			var mesh_owner:=owner(journal)
			queue._doc.load_box_meshes[["road_mesh",record,{}]]={"mesh":mesh_owner,"source":mesh_owner}
			if i==0:borrow=record
		for i in 36:queue._doc.load_material_pool[[{"slot":i}]]=owner(journal)
		for i in 333:queue._doc.load_paint_validation[[{"face":i,"uv":[1.,2.]}]]=true
		map.set_meta("expected_owners",642)
		queue.tree_exiting.connect(func():map.set_meta("exit_cache_count",queue._doc.load_box_meshes.size()))
	else:
		var batch:=Batch.new();batch.name="GroundRenderBatches";map.add_child(batch);batch.set_process(false)
		for i in 218:
			var group:={"members":[],"category":"ground","data":{"mesh":owner(journal)}}
			batch.groups[str(i)]=group
			if i==0:borrow=group
		map.set_meta("expected_owners",218)
	return {"map":map,"borrow":borrow}
func run()->void:
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	var service:Node=Retirement._service();service.set_process(false)
	var handoff_journal:=Journal.new();var handoff:=fixture("document",handoff_journal)
	var handoff_queue:Node=handoff.map.get_node("DeferredAssets");handoff_queue._scene_handoff=true
	root.remove_child(handoff.map)
	check(service.pending.is_empty() and not handoff_queue.get("_document_cache_owners_retiring"),"temporary handoff does not enqueue expiring cache retention")
	root.add_child(handoff.map)
	check(handoff_queue._doc.load_box_meshes.size()==303 and handoff_journal.freed==0,"handoff preserves live load caches for their new map owner")
	handoff.map.free();handoff={}
	check(handoff_journal.freed==642,"unretired handoff fixture cleans up all owners")
	for kind:String in ["document","batch"]:
		var journal:=Journal.new();var f:=fixture(kind,journal);var map:Node=f.map
		var expected:int=map.get_meta("expected_owners");var observed:Array=[]
		# A retained external key/group must remain usable throughout retirement.
		var borrow:Dictionary=f.borrow;f={}
		map.tree_exited.connect(func():observed.append(map.get_meta("exit_cache_count",0)))
		var started:=Time.get_ticks_usec();Stream.prepare_map_disposal(map,self);service.set_process(false)
		var prepare_us:=Time.get_ticks_usec()-started
		var pending:int=service.pending.size();Stream.prepare_map_disposal(map,self)
		check(service.pending.size()==pending,kind+": repeated prepare creates no duplicate retirement")
		check(journal.freed==0,kind+": preparation preserves all cache owners")
		started=Time.get_ticks_usec();map.free();map=null;var destroy_us:=Time.get_ticks_usec()-started
		service.set_process(false)
		check(journal.freed==0,kind+": map destruction does not synchronously release cache contents")
		if kind=="document":check(observed==[303],"exit callbacks retain the original document cache")
		var slices:=0;var max_slice:=0;var began:=Time.get_ticks_usec();var total_slice_us:=0
		while not service.pending.is_empty() and Time.get_ticks_usec()-began<10000000:
			started=Time.get_ticks_usec();service._process(0.);var elapsed:=Time.get_ticks_usec()-started
			total_slice_us+=elapsed;max_slice=maxi(max_slice,elapsed);slices+=1
			await process_frame
		check(service.pending.is_empty() and service.known.is_empty(),kind+": all retirement work drains")
		check(journal.freed==expected-1 and journal.off_main==0,kind+": owners release exactly once on main except the live borrower")
		check(borrow.road_mesh.polygons.size()==128 if kind=="document" else borrow.has("data"),kind+": borrowed nested data is unchanged")
		borrow={}
		check(journal.freed==expected and journal.off_main==0,kind+": releasing final borrower completes ownership")
		trials.append({"kind":kind,"prepare_us":prepare_us,"destroy_us":destroy_us,"slices":slices,"max_slice_us":max_slice,"total_slice_us":total_slice_us,"owners":expected})
	var report:={"checks":checks,"failures":failures,"trials":trials}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
