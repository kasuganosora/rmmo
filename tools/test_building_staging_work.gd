extends SceneTree
## Reproduce quadratic component arrival and cross-group staging ownership.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
class Probe extends Deferred:
	var commits:Array=[]
	func _publish_items(items:Array,specs:Array)->bool:
		commits.append({"ids":items.map(func(item):return item.record.uuid),"specs":specs.duplicate()})
		return true
var failed:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if not ok:failed+=1
func fixture(count:int,groups:int=1)->Dictionary:
	var service:=Probe.new();var all:Array=[]
	service._jobs.shared={"accepted":true,"token":Deferred.Drainer.CancelToken.new()}
	service._reference_index={"groups":{},"extras":{"rmmo_records":[]}}
	for group:int in groups:
		var items:Array=[];var members:Array=[];var group_id:="building:%d"%group
		for i:int in count:
			var record:={"uuid":"%d_%d"%[group,i]}
			members.append(service._reference_index.extras.rmmo_records.size());service._reference_index.extras.rmmo_records.append(record)
			var item:={"record":record,"path":"shared","group_id":group_id};items.append(item)
		service._reference_index.groups[group_id]={"members":members};all.append(items)
	return {"service":service,"groups":all}
func run()->void:
	var f:=fixture(1800);var service:Probe=f.service;var items:Array=f.groups[0]
	var began:=Time.get_ticks_usec()
	for i:int in items.size():service._stage_building(items[i],[i])
	var elapsed:=Time.get_ticks_usec()-began
	check(service.commits.size()==1 and service.commits[0].ids==items.map(func(item):return item.record.uuid) and service.commits[0].specs==range(1800),"large ordered group publishes exact members and specs once")
	print("BUILDING_STAGING members=1800 elapsed_us=",elapsed," member_visits=",service.profile.get("staging_member_visits",-1))
	if not "--baseline" in OS.get_cmdline_user_args():check(int(service.profile.get("staging_member_visits",-1))==1800,"successful staging visits each group member once")
	service.free()
	f=fixture(4,2);service=f.service
	service._stage_building(f.groups[1][2],[12])
	for i:int in [2,0,2,3]:service._stage_building(f.groups[0][i],[i])
	check(service.commits.is_empty(),"duplicate and out-of-order arrivals cannot publish an incomplete group")
	service._stage_building(f.groups[0][1],[1])
	check(service.commits.size()==1 and service.commits[0].specs==[0,1,2,3] and service._jobs.shared.staged.has("1_2"),"one group's commit preserves another group's partial staging")
	for i:int in [3,1,0]:service._stage_building(f.groups[1][i],[10+i])
	check(service.commits.size()==2 and service.commits[1].specs==[10,11,12,13] and service._jobs.shared.staged.is_empty(),"interleaved shared-path groups finish in authored order without reconstructing members")
	service.free()
	f=fixture(3,2);service=f.service
	service._stage_building(f.groups[1][0],[10]);service._stage_building(f.groups[0][0],[0])
	service._instance_failed("0_2","fixture failure")
	service._stage_building(f.groups[0][1],[1])
	check(service.instance_errors.size()==3 and service.commits.is_empty() and service._jobs.shared.staged.size()==1 and service._jobs.shared.staged.has("1_0"),"failed member invalidates its entire group, preserving unrelated staged owners")
	for i:int in [1,2]:service._stage_building(f.groups[1][i],[10+i])
	check(service.commits.size()==1 and service.commits[0].specs==[10,11,12],"independent group still completes after another group fails")
	service.free()
	print("BUILDING_STAGING failures=",failed)
	quit(0 if failed==0 else 1)
