extends SceneTree
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture()->Dictionary:
	var queue:=Deferred.new();var map:=Node3D.new();queue._map=map;queue._reference_index={"models":{}}
	map.set_meta("extras",{"rmmo_records":[]})
	var entries:Dictionary={}
	for i:int in 4600:
		var id:="item%d"%i
		var bounds:=AABB(Vector3((i%80)*16.,0.,(i/80)*16.),Vector3(512.,1.,512.) if i%23==0 else Vector3(12,1,12))
		var record:={"uuid":id}
		var entry:={"compact_record":record,"asset_path":"model%d.glb"%(i%8),"group_id":"","record_index":i,"bounds":bounds}
		entries[id]=entry
		queue.pending.append({"record":record,"path":entry.asset_path,"bounds":bounds,"reference_entry":entry})
	queue._index_pending();return {"queue":queue,"map":map,"entries":entries}
func signatures(rows:Array)->Array:
	var result:Array=[]
	for row:Dictionary in rows:result.append([row.record.uuid,row.path,row.bounds])
	return result
func update(f:Dictionary,ids:Array,extra_ids:Array,incremental:bool,round_:int)->int:
	Deferred.incremental_pending_index_enabled=incremental
	var published:Array=[];var entries:Array=[]
	for id:String in ids:
		entries.append(f.entries[id]);published.append(f.queue._pending_by_record_id[id])
	for id:String in extra_ids:published.append(f.queue._pending_by_record_id[id])
	for item:Dictionary in published:item.published=true
	f.queue._remove_published_demand(published)
	if round_%2==0:f.queue._runtime_building_records[ids[0]]=AABB(Vector3(-100,0,-100),Vector3(900,1,900))
	else:f.queue._runtime_building_records[ids[0]]=AABB(Vector3(400,0,400),Vector3(8,1,8))
	var began:=Time.get_ticks_usec()
	check(f.queue.requeue_references(entries)==ids.size(),"complete selected entries return once")
	f.queue._index_pending()
	return Time.get_ticks_usec()-began
func run()->void:
	var full:=fixture();var incremental:=fixture();var control_us:=0;var incremental_us:=0
	var queries:Array=[AABB(Vector3(-200,0,-200),Vector3(2000,1,2000)),AABB(Vector3(10,0,10),Vector3(48,1,48)),AABB(Vector3(400,0,400),Vector3(64,1,64)),AABB(Vector3(0,0,0),Vector3(800,1,600))]
	for round_:int in 12:
		var ids:Array=[]
		for i:int in 8:ids.append(full.queue.pending[(i*313+round_*17)%full.queue.pending.size()].record.uuid)
		var extra:Array=["item24","item25","item26"] if round_==0 else []
		control_us+=update(full,ids,extra,false,round_);incremental_us+=update(incremental,ids,extra,true,round_)
		check(signatures(full.queue.pending)==signatures(incremental.queue.pending),"stable pending order and learned bounds match full rebuild")
		check(full.queue._pending_index.size()==incremental.queue._pending_index.size() and full.queue._large_pending.size()==incremental.queue._large_pending.size(),"active spatial size stays bounded across repeated return/unload")
		for clip:AABB in queries:
			check(signatures(full.queue._in_clip(clip))==signatures(incremental.queue._in_clip(clip)),"exact spatial candidates and tie order match reference")
			check(full.queue._has_pending_in_clip(clip)==incremental.queue._has_pending_in_clip(clip),"exact readiness matches reference")
			full.queue.set_demand("sample",clip,0);incremental.queue.set_demand("sample",clip,0)
			full.queue._refresh_demanded();incremental.queue._refresh_demanded()
			check(signatures(full.queue._demanded)==signatures(incremental.queue._demanded),"scheduler rank and path order match reference")
	print("INCREMENTAL_PENDING_INDEX ",JSON.stringify({"control_us":control_us,"incremental_us":incremental_us,"control":full.queue.profile,"incremental":incremental.queue.profile}))
	check(full.queue.profile.pending_index_builds==13 and incremental.queue.profile.pending_index_builds==1 and incremental.queue.profile.pending_indexed_items==4696,"requeue indexes only 96 changed rows, never the whole 4600-row directory")
	Deferred.incremental_pending_index_enabled=true
	full.queue.free();full.map.free();incremental.queue.free();incremental.map.free()
	print("INCREMENTAL_PENDING_INDEX failures=",failures);quit(1 if failures else 0)
