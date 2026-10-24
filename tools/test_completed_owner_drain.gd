extends "res://tools/test_deferred_backpressure.gd"
## Service-work regression: completed owners may all advance while a full result
## cap prevents the next producer from starting. Do not use elapsed wall time as
## the assertion: identical real private cursors calibrate one owner's drain.
const PublicationOrder=preload("res://scripts/world3d/publication_order.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const MEMBERS:=16
class GraphDocument extends Document:
	func _mesh(record:Dictionary,_effects:bool=true,_timings:Variant=null)->Node3D:
		calls[record.uuid]=int(calls.get(record.uuid,0))+1
		var holder:=Node3D.new()
		# Force multiple cursor operations even when the machine is very fast.
		for i:int in 4:holder.add_child(Node3D.new())
		return holder
func owner_fixture(count:int)->Dictionary:
	var rows:Array=[];var compact:Array=[];var groups:Dictionary={}
	for number:int in count:
		var group:="building:drain%d"%number;var members:Array=[]
		for part:int in MEMBERS:
			var row:=item("drain%d_part%d"%[number,part],float(number*100)+float(part)*0.01,10,"reference:"+group)
			row.group_id=group;members.append(compact.size());compact.append(row.record);rows.append(row)
		groups[group]={"members":members}
	var f:=fixture(rows);var queue:Queue=f.queue;var document:=GraphDocument.new()
	queue._doc=document;f.document=document;f.groups=groups
	queue._reference_index={"groups":groups,"extras":{"rmmo_records":compact}}
	queue.set_demand("background",AABB(Vector3(-1000,-1,-1),Vector3(2000,3,3)),10)
	queue.set_process(false);queue._admission.worker_limit=6;queue.paused=true
	return f
func prefill(f:Dictionary,count:int)->void:
	var queue:Queue=f.queue;var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		if queue._jobs.size()==count and queue._jobs.values().all(func(job):return job.get("accepted",false)) and queue._admission.active_workers()==0:break
	check(queue._job_limit()==6 and queue._jobs.size()==count and queue.started.size()==count,"prefill%d: fixed production six-slot cap holds the expected completed results"%count)
	check(queue._jobs.values().all(func(job):return job.get("accepted",false)) and queue._admission.active_workers()==0,"prefill%d: every owner accepted with no live worker"%count)
func measure(count:int)->Dictionary:
	var f:=owner_fixture(count);var queue:Queue=f.queue;await prefill(f,mini(count,6))
	var generations:Dictionary={}
	for path:String in queue._jobs:generations[path]=queue._jobs[path].token.get_instance_id()
	if count==7:check(not queue.started.has("reference:building:drain6") and queue._admission.reserved_bytes==60,"pressure starts with six real leases and seventh source unstarted")
	var origin:=int(queue.profile.get("publication_units",0));var first_release:=-1;var seventh_start:=-1
	var atomic:=true;var bounded:=true;var committed_release:=true;var deadline:=Time.get_ticks_msec()+15000
	queue.paused=false
	while Time.get_ticks_msec()<deadline:
		await tick(queue)
		var units:=int(queue.profile.get("publication_units",0))-origin
		if first_release<0:
			for path:String in generations:
				if not queue._jobs.has(path) or queue._jobs[path].token.get_instance_id()!=generations[path]:
					first_release=units;committed_release=queue.group_is_published(path.trim_prefix("reference:"));break
		if seventh_start<0 and queue.started.has("reference:building:drain6"):seventh_start=units
		for group:String in f.groups:
			var remaining:=0
			for row:Dictionary in queue.pending:
				if row.get("group_id","")==group:remaining+=1
			if remaining not in [0,MEMBERS]:atomic=false
		bounded=bounded and queue._jobs.size()<=6 and queue._admission.reserved_bytes<=queue._admission.byte_limit
		if queue.is_complete():break
	check(first_release>0 and committed_release,"%d owners: first real generation release follows complete atomic publication"%count)
	check(atomic and queue.is_complete() and f.groups.keys().all(func(group):return queue.group_is_published(group)),"%d owners: every group stays atomic and fully publishes"%count)
	var starts:Dictionary={}
	for path:String in queue.started:starts[path]=int(starts.get(path,0))+1
	check(f.document.calls.size()==count*MEMBERS and f.document.calls.values().all(func(n):return n==1) and starts.size()==count and starts.values().all(func(n):return n==1),"%d owners: each member instantiates once and each source starts once"%count)
	check(bounded and int(queue.profile.max_total_jobs)<=6 and queue._admission.peak_workers<=6 and queue._admission.reserved_bytes==0 and queue._jobs.is_empty(),"%d owners: no widened job/worker/byte cap and zero final ownership"%count)
	var result:={"owners":count,"single_members":MEMBERS,"first_release_units":first_release,"seventh_start_units":seventh_start,"all_units":int(queue.profile.get("publication_units",0))-origin}
	print("OWNER_DRAIN_METRICS ",JSON.stringify(result))
	await queue.quiesce();f.map.free();return result
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var old_white:bool=Controls.white_materials;var old_discard:bool=Controls.discard_map_textures
	Controls.white_materials=true;Controls.discard_map_textures=true
	# Root adds the switch with the production fix. An absent baseline property
	# must not become the reason this workload regression fails.
	var selector_script:Script=PublicationOrder
	var drain=selector_script.get("completed_owner_drain_enabled")
	if drain!=null and OS.get_cmdline_user_args().has("--without-completed-owner-drain"):selector_script.set("completed_owner_drain_enabled",false)
	var single:Dictionary=await measure(1);var loaded:Dictionary=await measure(7)
	var allowance:=maxi(int(ceil(float(single.first_release_units)*0.5)),5*PublicationOrder.MAX_BURST)
	var bound:=int(single.first_release_units)+allowance
	print("OWNER_DRAIN_BOUND ",JSON.stringify({"single_units":single.first_release_units,"fair_service_allowance":allowance,"maximum_first_release_units":bound,"drain_switch_present":drain!=null,"drain_enabled":selector_script.get("completed_owner_drain_enabled")}))
	check(int(loaded.first_release_units)<=bound,"WORK: full completed cap releases one owner within a single-owner drain plus bounded fair service")
	check(int(loaded.seventh_start_units)>0 and int(loaded.seventh_start_units)<=bound+1,"WORK: seventh producer starts within the same bound plus one scheduler tick")
	if drain!=null:selector_script.set("completed_owner_drain_enabled",drain)
	Controls.white_materials=old_white;Controls.discard_map_textures=old_discard
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("COMPLETED_OWNER_DRAIN passed=",passed," failures=",failed);quit(0 if failed==0 else 1)

