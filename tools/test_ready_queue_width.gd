extends SceneTree
## Fixed completed work with a wide queue. No models, workers, or GPU resources.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
class Probe extends Deferred:
	var eligibility_calls:=0
	var index_calls:=0
	var blocked:Dictionary={}
	func _publication_eligible(item:Dictionary,staged:Dictionary)->bool:
		eligibility_calls+=1
		return super._publication_eligible(item,staged)
	func _index_pending()->void:index_calls+=1
	func _collision_publication_status(uuid:String)->Dictionary:
		return {"owned":true,"pending":true} if blocked.has(uuid) else EMPTY_DEMAND
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if not ok:failures+=1
func fixture(buildings:int,members:int,props:int=0)->Probe:
	var p:=Probe.new();root.add_child(p);p.set_process(false)
	p._candidates_revision=0;p._demand_revision=0
	for i:int in buildings+props:
		var building:=i<buildings
		var group:="building:%d"%i if building else ""
		var path:="reference:"+group if building else "reference:prop:%d"%i
		var items:Array=[]
		for j:int in members if building else 8:
			var id:="%d_%d"%[i,j]
			var item:={"record":{"uuid":id},"path":path,"group_id":group,"native_reference":true}
			items.append(item);p._demanded_by_id[id]=item;p._demanded_rank[id]=i*members+j;p._demanded_priority[id]=0
		p._demanded_by_path[path]=items;p._path_first[path]=items[0]
		p._prepared_paths[path]=true;p._jobs[path]={"accepted":true,"staged":{}}
	return p
func dispose(p:Probe)->void:p._jobs.clear();p.free()
func drain(p:Probe)->Dictionary:
	var selected:Dictionary={};var groups:Array=[];var began:=Time.get_ticks_usec()
	while not p._demanded_by_id.is_empty():
		var heads:Array=p._publication_ready()
		if heads.is_empty():break
		var item:Dictionary=p._publication_order.choose(heads,p._demanded_priority,p._demanded_rank,p._jobs)
		var id:String=item.record.uuid
		if selected.has(id):break
		selected[id]=true;item.published=true;p._demanded_by_id.erase(id)
		var remaining:Array=p._demanded_by_path[item.path].filter(func(v):return not v.get("published",false))
		p._demanded_by_path[item.path]=remaining
		if remaining.is_empty():
			groups.append(item.path);p._path_first.erase(item.path);p._jobs.erase(item.path)
		else:p._path_first[item.path]=remaining[0]
	return {"selected":selected.size(),"remaining":p._demanded_by_id.size(),"groups":groups,"eligible_calls":p.eligibility_calls,"index_calls":p.index_calls,"us":Time.get_ticks_usec()-began}
func run()->void:
	for width:int in [3,12,24]:
		var p:=fixture(width,int(768/width),4);var row:=drain(p)
		check(row.selected==800 and row.remaining==0,"same 800 objects complete exactly once at queue width "+str(width))
		check(row.eligible_calls<=800*6,"later same-priority houses do not repeat readiness checks at width "+str(width))
		check(row.index_calls==0,"objects without runtime supports do not request the pending index")
		print("READY_QUEUE_WIDTH ",JSON.stringify(row));dispose(p)
	var p:=fixture(3,1,1);p.blocked["0_0"]=true
	var heads:=p._publication_ready();var item:Dictionary=p._publication_order.choose(heads,p._demanded_priority,p._demanded_rank,p._jobs)
	check(item.record.uuid=="1_0","a blocked nearest house does not hide the next ready house")
	p.blocked.clear();p._demanded_priority["2_0"]=-2;p._demanded_rank["2_0"]=-1
	heads=p._publication_ready();item=p._publication_order.choose(heads,p._demanded_priority,p._demanded_rank,p._jobs)
	check(item.record.uuid=="2_0","a later inserted critical house preempts visual houses immediately")
	# A shared model can contain independent objects; never prune it as one house.
	var mixed:Dictionary=p._demanded_by_id["0_0"];mixed.path="shared_model"
	p._jobs.shared_model=p._jobs["reference:building:0"];p._jobs.erase("reference:building:0")
	p._prepared_paths.shared_model=true;p._demanded_by_path.shared_model=[mixed];p._path_first.shared_model=mixed
	p._publication_queues.clear();heads=p._publication_ready()
	check(heads.any(func(v):return v.path=="shared_model"),"shared model paths retain full candidate checks")
	dispose(p)
	p=fixture(3,1);p._candidates_revision=-1;heads=p._publication_ready()
	check(heads.size()==3,"stale demand ranks disable house pruning")
	p._candidates_revision=0;Deferred.fair_publication_enabled=false;heads=p._publication_ready()
	check(heads.size()==3,"legacy distance selection keeps every ready house")
	Deferred.fair_publication_enabled=true;dispose(p)
	p=fixture(3,1)
	var paths:Array=p._jobs.keys();paths.reverse();var reversed:Dictionary={}
	for path:String in paths:reversed[path]=p._jobs[path]
	p._jobs=reversed;heads=p._publication_ready()
	check(heads[0].record.uuid=="0_0","insertion order cannot prune a later encountered nearer house")
	p._runtime_building_supports["0_0"]={"terrain":true};p._pending_by_record_id.terrain={"record":{"uuid":"terrain"},"path":"terrain"}
	check(not p._runtime_supports_ready("0_0") and p.index_calls>0,"real support dependencies still consult the index and block until published")
	dispose(p)
	print("READY_QUEUE_WIDTH failures=",failures);quit(1 if failures else 0)
