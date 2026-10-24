extends "res://tools/test_completed_owner_drain.gd"
## Real Thread arrival behind a currently serviced large completed owner.
## Semaphore gates control readiness, never the selector or private cursors.
## --without-completed-owner-drain is the old RR control, not an isolated toggle
## of only the later-ready reconsideration inside completed-owner drain.
const SMALL_PATH:="reference:building:arrival1"
const SEVENTH_PATH:="reference:building:arrival6"
class ArrivalQueue extends Queue:
	var gates:Dictionary={}
	var released:Dictionary={}
	var accepted_service_origin:=-1
	var seventh_start_units:=-1
	func _make_prepare_task(path:String,digest:String,token:RefCounted,row:Dictionary,faces:bool,reference_root:String,requests_arg:Array,native:bool,need_model:bool)->Callable:
		if path==SEVENTH_PATH:seventh_start_units=int(profile.get("publication_units",0))
		var prepare:Callable=super._make_prepare_task(path,digest,token,row,faces,reference_root,requests_arg,native,need_model)
		return wait_and_work.bind(gates[path],prepare) if gates.has(path) else prepare
	static func wait_and_work(gate:Semaphore,prepare:Callable)->Dictionary:
		gate.wait();return prepare.call()
	func open_gate(path:String)->void:
		if gates.has(path) and not released.has(path):released[path]=true;gates[path].post()
	func open_all()->void:
		for path:String in gates:open_gate(path)
	func _publish_ready(began:int,budget:int=INTERACTIVE_BUDGET_US)->Dictionary:
		if accepted_service_origin<0 and _jobs.has(SMALL_PATH) and _jobs[SMALL_PATH].get("accepted",false):accepted_service_origin=int(profile.get("publication_units",0))
		return super._publish_ready(began,budget)
func arrival_fixture(count:int,big_members:int)->Dictionary:
	var rows:Array=[];var compact:Array=[];var groups:Dictionary={};var sizes:Dictionary={}
	for number:int in count:
		var group:="building:arrival%d"%number;var members:Array=[];var size:=big_members if number==0 else 1
		for part:int in size:
			var row:=item("arrival%d_part%d"%[number,part],float(number*100)+float(part)*0.01,10,"reference:"+group)
			row.group_id=group;members.append(compact.size());compact.append(row.record);rows.append(row)
		groups[group]={"members":members};sizes[group]=size
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",[]);map.set_meta("extras",{"rmmo_records":[]})
	var index:=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	var queue:=ArrivalQueue.new();var document:=GraphDocument.new();queue._doc=document;queue.pending=rows;queue._reference_root="D:/code/rmmo"
	queue._reference_index={"groups":groups,"extras":{"rmmo_records":compact}}
	if count>1:
		for number:int in range(1,mini(count,6)):queue.gates["reference:building:arrival%d"%number]=Semaphore.new()
	map.add_child(queue);queue.activate(map);queue._admission.byte_limit=100000;queue._admission.worker_limit=6
	queue.set_demand("background",AABB(Vector3(-1000,-1,-1),Vector3(2000,3,3)),10);queue.set_process(false);queue._refresh_demanded()
	return {"map":map,"queue":queue,"document":document,"groups":groups,"sizes":sizes,"atomic":true,"bounded":true}
func observe(f:Dictionary)->void:
	var queue:ArrivalQueue=f.queue
	f.bounded=f.bounded and queue._jobs.size()<=6 and queue._admission.reserved_bytes<=queue._admission.byte_limit
	for group:String in f.groups:
		var remaining:=0
		for row:Dictionary in queue.pending:
			if row.get("group_id","")==group:remaining+=1
		if remaining not in [0,int(f.sizes[group])]:f.atomic=false
func one_member_cost()->int:
	var f:=arrival_fixture(1,1);var queue:ArrivalQueue=f.queue;var deadline:=Time.get_ticks_msec()+5000
	while not queue.is_complete() and Time.get_ticks_msec()<deadline:await tick(queue);observe(f)
	var units:=int(queue.profile.get("publication_units",0))
	check(queue.is_complete() and queue.group_is_published("building:arrival0") and f.document.calls=={"arrival0_part0":1} and queue._admission.reserved_bytes==0,"calibration: one real member commits once and releases its lease")
	queue.open_all();await queue.quiesce();f.map.free();return units
func arrival_test(single_units:int)->void:
	var f:=arrival_fixture(7,16);var queue:ArrivalQueue=f.queue;queue.paused=true;var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await tick(queue);observe(f)
		if queue._jobs.size()==6 and queue._jobs.get("reference:building:arrival0",{}).get("accepted",false) and queue._admission.active_workers()==5:break
	check(queue._job_limit()==6 and queue._jobs.size()==6 and queue.started.size()==6 and not queue.started.has(SEVENTH_PATH),"arrival: six jobs fill the production cap and seventh has never started")
	check(queue._jobs.get("reference:building:arrival0",{}).get("accepted",false) and not queue._jobs.get(SMALL_PATH,{}).get("accepted",false) and queue._admission.active_workers()==5,"arrival: only large result accepted while five real worker Threads wait on gates")
	queue.paused=false
	for i:int in 8:await tick(queue);observe(f)
	check(f.document.calls.get("arrival0_part0",0)==1 and not queue.group_is_published("building:arrival0") and not f.document.calls.has("arrival1_part0"),"arrival: large owner has started a real private cursor before the short worker is released")
	var large_generation:int=queue._jobs["reference:building:arrival0"].token.get_instance_id()
	var small_generation:int=queue._jobs[SMALL_PATH].token.get_instance_id()
	queue.open_gate(SMALL_PATH)
	var first_release:=-1;var small_committed:=false;var large_still_owned:=false;deadline=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await tick(queue);observe(f)
		if not queue._jobs.has(SMALL_PATH) or queue._jobs[SMALL_PATH].token.get_instance_id()!=small_generation:
			first_release=int(queue.profile.get("publication_units",0))-queue.accepted_service_origin
			small_committed=queue.group_is_published("building:arrival1")
			large_still_owned=queue._jobs.has("reference:building:arrival0") and queue._jobs["reference:building:arrival0"].token.get_instance_id()==large_generation and not queue.group_is_published("building:arrival0")
			break
	var bound:=single_units+PublicationOrder.MAX_BURST
	check(queue.accepted_service_origin>=0 and small_committed and large_still_owned,"arrival: short result really commits and releases before the original large generation completes")
	check(first_release>0 and first_release<=bound,"WORK: newly accepted short owner releases within single-member service plus one old fair burst")
	check(queue.seventh_start_units>=queue.accepted_service_origin and queue.seventh_start_units-queue.accepted_service_origin<=bound+1,"WORK: short owner's real release admits the seventh source without widening capacity")
	# Release every Semaphore before draining or shutting down, including failures.
	queue.open_all();deadline=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await tick(queue);observe(f)
		if queue.is_complete():break
	var starts:Dictionary={}
	for path:String in queue.started:starts[path]=int(starts.get(path,0))+1
	check(f.atomic and queue.is_complete() and f.groups.keys().all(func(group):return queue.group_is_published(group)),"arrival: all seven groups remain atomic and complete after every gate opens")
	check(f.document.calls.size()==22 and f.document.calls.values().all(func(n):return n==1) and starts.size()==7 and starts.values().all(func(n):return n==1),"arrival: all 22 members instantiate once and all seven source Threads start once")
	check(f.bounded and int(queue.profile.max_total_jobs)<=6 and queue._admission.peak_workers<=6 and queue._jobs.is_empty() and queue._admission.reserved_bytes==0,"arrival: fixed six-job/worker limits, bounded bytes and zero final ownership")
	print("OWNER_ARRIVAL_METRICS ",JSON.stringify({"drain_enabled":PublicationOrder.completed_owner_drain_enabled,"single_member_units":single_units,"maximum_after_accept_units":bound,"first_release_after_accept_units":first_release,"seventh_start_after_accept_units":queue.seventh_start_units-queue.accepted_service_origin,"total_units":queue.profile.get("publication_units",0),"large_still_owned_at_small_release":large_still_owned}))
	queue.open_all();await queue.quiesce();f.map.free()
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var old_white:bool=Controls.white_materials;var old_discard:bool=Controls.discard_map_textures;var old_drain:bool=PublicationOrder.completed_owner_drain_enabled
	Controls.white_materials=true;Controls.discard_map_textures=true
	PublicationOrder.completed_owner_drain_enabled=not OS.get_cmdline_user_args().has("--without-completed-owner-drain")
	var single_units:int=await one_member_cost();await arrival_test(single_units)
	PublicationOrder.completed_owner_drain_enabled=old_drain;Controls.white_materials=old_white;Controls.discard_map_textures=old_discard
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("COMPLETED_OWNER_ARRIVAL passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
