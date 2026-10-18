extends "res://tools/test_stream_index_retire.gd"
const Residency=preload("res://scripts/world3d/asset_residency.gd")
class Host extends Node3D:
	var _navigation:Node
class Queue extends Node:
	var _jobs:Dictionary={}
	var _demands:Dictionary={}
	var _prepared_paths:Dictionary={"shared.glb":true}
	var calls:Array=[]
	var batches:=0
	func requeue_reference(entry:Dictionary)->bool:calls.append(entry.compact_record.uuid);batches+=1;return true
	func requeue_references(entries:Array)->int:
		batches+=1
		for entry:Dictionary in entries:calls.append(entry.compact_record.uuid)
		return entries.size()
	static func _intersects(a:AABB,b:AABB)->bool:
		return a.position.x<=b.end.x and a.end.x>=b.position.x and a.position.z<=b.end.z and a.end.z>=b.position.z
class CacheScope extends RefCounted:
	var releases:Array=[]
	func release(path:String)->bool:releases.append(path);return true
class ObservedResidency extends Residency:
	var observed:Array=[]
	func _eligible(uuid:String,now_msec:int)->bool:
		observed.append(uuid);return super._eligible(uuid,now_msec)
func fixture(count:int,parts:int=2)->Dictionary:
	var host:=Host.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map)
	var queue:=Queue.new();map.add_child(queue)
	var residency:=ObservedResidency.new();map.add_child(residency);residency.name="AssetResidency";residency.set_process(false)
	residency._host=host;residency._map=map;residency._deferred=queue;residency.grace_msec=10
	var library:Array=[];var records:Array=[]
	for i:int in count:
		var id:="p%d"%i;var record:Dictionary={"uuid":id,"kind":"asset","asset_path":"shared.glb"};records.append(record)
		residency._catalog[id]={"compact_record":record,"asset_path":"shared.glb","bounds":AABB(Vector3(3200+i,0,0),Vector3.ONE)}
		residency._remember_traits(record)
		for part:int in parts:library.append(spec(id+"__"+str(part),Vector2i(100,0),Vector2i(100,0),record))
	map.set_meta("stream_library",library);map.set_meta("extras",{"rmmo_records":records})
	var data:=Index.build(library)
	for key:String in data:map.set_meta(key,data[key])
	map.set_meta("stream_chunk",Vector2i.ZERO)
	residency.observe(library)
	for resident:Dictionary in residency._resident.values():resident.outside_since=0
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new();host.add_child(nav);host._navigation=nav
	nav.configure_streaming_geometry(func(_clip:AABB):return {"ok":true,"error":""})
	nav.map=NavigationServer3D.map_create();nav.ready_for_queries=true;nav.set_process(false)
	check(nav.append_specs(library).ok,"fixture navigation owns all complete namespaces")
	var scope:=CacheScope.new();map.set_meta("runtime_asset_cache_scope",scope)
	return {"host":host,"map":map,"queue":queue,"service":residency,"nav":nav,"scope":scope,"library":library}
func run()->void:
	var saved:=Residency.retirement_batching_enabled;Residency.retirement_batching_enabled=true
	var f:=fixture(10);var first_frame:=Engine.get_process_frames();f.service.poll(100)
	check(f.service.profile.retired_instances==8 and f.service.profile.retirement_transactions==1 and f.queue.batches==1,"eight complete namespaces share one transaction and requeue")
	check(f.library.size()==4 and f.nav._spec_ids.size()==4 and f.service._resident.size()==2,"index/navigation/residency remove exactly the selected sixteen parts")
	check(f.scope.releases.is_empty(),"surviving namespace retains its shared model cache")
	# A deferred initial run can resume on process_frame while the frame counter
	# is still zero. The second transaction must receive a fresh budget frame.
	while Engine.get_process_frames()==first_frame:await process_frame
	f.service.poll(120)
	check(f.library.is_empty() and f.nav._spec_ids.is_empty() and f.queue.calls.size()==10,"next bounded transaction drains the remaining complete namespaces")
	check(f.scope.releases==["shared.glb"] and not f.queue._prepared_paths.has("shared.glb"),"shared model is evicted once after its final namespace retires")
	f.host.free();await process_frame
	f=fixture(9,20);f.service.poll(100)
	check(f.service.profile.retired_instances==6 and f.service.profile.retired_specs==120,"128-spec cap never splits a twenty-part namespace")
	f.host.free();await process_frame
	f=fixture(2,130);f.service.poll(100)
	check(f.service.profile.retired_instances==1 and f.service.profile.retired_specs==130,"an individually large namespace keeps its atomic legacy path")
	f.host.free();await process_frame
	f=fixture(8)
	f.service._resident.p1.pinned="gameplay";f.service._resident.p2.outside_since=-1;f.service._resident.p3.outside_since=95
	f.queue._demands={"local":{"clip":AABB(Vector3(3204,0,0),Vector3.ZERO),"kind":"all"}}
	# Separate bounds make the needed owner distinct even with the 64 m margin.
	for id:String in f.service._catalog:
		f.service._catalog[id].bounds=AABB(Vector3(4000+100*int(id.trim_prefix("p")),0,0),Vector3.ONE)
	f.queue._demands.local.clip=f.service._catalog.p4.bounds
	f.service.poll(100)
	check(f.service._resident.has("p1") and f.service._resident.has("p2") and f.service._resident.has("p3") and f.service._resident.has("p4"),"pinned, newly outside, in-grace and demanded namespaces remain protected")
	check(f.service._resident.p2.outside_since==100 and f.service._resident.p4.outside_since==-1,"lookahead preserves outside and needed timestamp rules")
	f.host.free();await process_frame
	f=fixture(4);f.queue._jobs["shared.glb"]={};f.service.poll(100)
	check(f.library.size()==8 and f.queue.calls.is_empty(),"an in-flight model protects every shared namespace")
	f.queue._jobs.clear();f.host.free();await process_frame
	f=fixture(80)
	for resident:Dictionary in f.service._resident.values():resident.pinned="test"
	f.service.poll(100)
	check(f.service.observed.size()==32 and f.service._cursor==32,"a poll observes at most 32 protected owners")
	f.service.poll(120)
	check(f.service.observed.size()==64 and f.service.observed[32]=="p32","next poll continues its bounded round-robin observation")
	f.host.free();await process_frame
	f=fixture(8);f.nav.ready_for_queries=false;f.service.poll(100)
	check(f.library.size()==16 and f.nav._spec_ids.size()==16 and f.queue.calls.is_empty() and f.scope.releases.is_empty(),"busy navigation rejects the entire bundle without releasing owners or sources")
	await process_frame;f.nav.ready_for_queries=true;f.service.poll(120)
	check(f.service.profile.retired_instances>0,"navigation readiness permits the fresh individual retry")
	f.host.free();await process_frame
	f=fixture(4)
	# The source catalogue still knows both parts. A bad caller's incomplete
	# first request must reject the whole bundle and permit later singles.
	f.service._resident.p0.ids.resize(1)
	f.service.poll(100)
	check(f.library.size()==8 and f.nav._spec_ids.size()==8 and f.queue.calls.is_empty(),"invalid namespace in a bundle fails without partial index/navigation/requeue effects")
	check(f.service._retry_individually,"bundle rejection arms fresh individual retries")
	for turn:int in 6:
		await process_frame;f.service.poll(120+turn*20)
	check(f.service._resident.has("p0") and f.service.profile.retired_instances==3 and f.queue.calls.size()==3,"invalid first namespace cannot starve its valid neighbours")
	check(f.library.size()==2 and f.nav._spec_ids.size()==2 and f.scope.releases.is_empty(),"rejected namespace keeps both parts and shared model ownership")
	f.host.free();await process_frame
	for busy_field:String in ["stream_jobs","stream_append_pending"]:
		f=fixture(32);f.map.set_meta(busy_field,[f.library[0]])
		f.service.poll(100)
		check(f.service.profile.retirement_attempts==1 and not f.service._retry_individually,"map-wide busy refusal stops this poll without degrading its next batch: "+busy_field)
		check(f.library.size()==64 and f.nav._spec_ids.size()==64 and f.queue.calls.is_empty(),"map-wide busy refusal preserves all ownership: "+busy_field)
		f.map.remove_meta(busy_field);await process_frame;f.service.poll(120)
		check(f.service.profile.retired_instances==8,"a fresh next-frame check resumes full batching after busy work ends: "+busy_field)
		f.host.free();await process_frame
	Residency.retirement_batching_enabled=false;f=fixture(4);f.service.poll(100)
	check(f.service.profile.retired_instances==1 and f.queue.batches==1,"diagnostic control retains single-namespace retirement")
	f.host.free();Residency.retirement_batching_enabled=saved;await process_frame
	print("ASSET_RETIREMENT_BATCHING checks=",checks," failures=",failures);quit(1 if failures else 0)
