extends SceneTree
const Queue=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture()->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	var queue:=Queue.new();map.add_child(queue);queue.set_process(false);queue._map=map
	queue._reference_index={"models":{}}
	var records:Array=[];var entries:Array=[]
	for i:int in 256:
		var heights:Array=[];heights.resize(4096);heights.fill(float(i))
		var row:={"uuid":"tile%d"%i,"terrain_mesh":{"heights":heights,"holes":heights.duplicate()}}
		records.append(row);queue._runtime_record_ids[row.uuid]=row
		entries.append({"compact_record":{"uuid":row.uuid},"asset_path":"model.res","bounds":AABB(Vector3.ZERO,Vector3.ONE),"record_index":i})
	map.set_meta("extras",{"rmmo_records":records})
	return {"map":map,"queue":queue,"entries":entries}
func drain()->void:
	var service:Node=root.get_node_or_null(Retirement.NODE_NAME)
	if service==null:return
	service.set_process(false)
	var steps:=0
	while not service.pending.is_empty() and steps<20000:
		if service._advance(service.pending[0],1000):service._finish_front()
		steps+=1
		if steps%64==0:OS.delay_usec(100)
	check(service.pending.is_empty() and service.known.is_empty(),"all release tickets finish")
func run()->void:
	var trials:Array=[]
	for background:bool in [false,true,true,false]:
		Retirement.background_decoded_release_enabled=background
		var f:=fixture();var borrowed:Array=f.queue._runtime_record_ids.tile1.terrain_mesh.heights
		var began:=Time.get_ticks_usec()
		var count:int=f.queue.requeue_references(f.entries);var elapsed:=Time.get_ticks_usec()-began
		check(count==256 and f.queue.pending_count()==256 and f.map.get_meta("extras").rmmo_records.is_empty() and f.queue._runtime_record_ids.is_empty(),"requeue releases decoded owners and restores exact compact membership")
		check(f.queue.requeue_references(f.entries)==0,"duplicate requeue changes no ownership")
		trials.append({"background":background,"main_us":elapsed,"records":count})
		drain();check(borrowed.size()==4096 and borrowed[0]==1.,"borrowed nested array is never cleared")
		borrowed=[];f.map.free();f={};drain()
	Retirement.background_decoded_release_enabled=true
	print("REQUEUE_RECORD_RELEASE ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
