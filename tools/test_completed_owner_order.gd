extends SceneTree
## Sequence oracle for completed owners under admission pressure. The selector
## receives ready heads only; tests never turn an unavailable dependency ready.
const Order=preload("res://scripts/world3d/publication_order.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
var checks:=0
var failures:=0
var selections:=0
var owner_cost_queries:=0
var cost_snapshots:=0
var inputs_intact:=true
var returns_ready_head:=true
var sequences:Dictionary={}

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func fixture(rows:Array)->Dictionary:
	var value:Dictionary={"heads":[],"jobs":{},"priorities":{},"ranks":{},"remaining":{}}
	for row:Dictionary in rows:add_owner(value,str(row.path),int(row.remaining),int(row.get("priority",0)),int(row.get("rank",value.heads.size())))
	return value

func add_owner(value:Dictionary,path:String,left:int,priority:int=0,rank:int=0)->void:
	var uuid:=path+"_head"
	value.heads.append({"path":path,"record":{"uuid":uuid,"marker":[path]},"group_id":"building:"+path})
	value.jobs[path]={"token":RefCounted.new(),"accepted":true,"result":{"marker":[path]}}
	value.priorities[uuid]=priority;value.ranks[uuid]=rank;value.remaining[path]=left

func remove_owner(value:Dictionary,path:String)->void:
	for i:int in range(value.heads.size()-1,-1,-1):
		if value.heads[i].path==path:value.heads.remove_at(i)
	value.jobs.erase(path);value.remaining.erase(path)
	value.priorities.erase(path+"_head");value.ranks.erase(path+"_head")

func select(order:RefCounted,value:Dictionary,pressure:bool=true)->Dictionary:
	var before:Dictionary=value.duplicate(true)
	# Match the loader handshake: cost is supplied only when a ready-generation
	# transition actually needs a new target, never for a sticky service unit.
	var costs:Dictionary={}
	if pressure and not value.heads.is_empty() and int(value.priorities[value.heads[0].record.uuid])>=0 and order.needs_drain_target(value.heads,value.jobs):
		costs=value.remaining;cost_snapshots+=1
	var selected:Dictionary=order.choose(value.heads,value.priorities,value.ranks,value.jobs,pressure,costs)
	selections+=1;inputs_intact=inputs_intact and value==before
	returns_ready_head=returns_ready_head and ((selected.is_empty() and value.heads.is_empty()) or value.heads.any(func(head):return is_same(head,selected)))
	return selected

func path(order:RefCounted,value:Dictionary,pressure:bool=true)->String:
	return str(select(order,value,pressure).get("path",""))

func fresh()->Dictionary:
	return fixture([{"path":"near","remaining":80},{"path":"short","remaining":5},{"path":"far","remaining":19}])

func shortest_and_sticky()->void:
	var value:=fresh();var order:=Order.new()
	check(path(order,value)=="short","pressure selects the ready owner nearest to completion, not distance rank")
	value.remaining.far=1
	var turns:Array=[]
	for i:int in 5:turns.append(path(order,value))
	check(turns==["short","short","short","short","short"],"a later shorter ready owner does not replace an active drain target")
	# Remaining work is caller-owned preparation work, not total members. The
	# two same-sized source groups deliberately have different staged prefixes.
	value=fresh();order=Order.new()
	value.jobs.near.publication_ids=["n1","n2","n3","n4","n5","n6"]
	value.jobs.short.publication_ids=["s1","s2","s3","s4","s5","s6"]
	value.jobs.short.staged={"s1":true,"s2":true,"s3":true}
	value.jobs.short.collision_staged={"s4":{},"s5":{}}
	value.remaining={"near":6,"short":1,"far":8}
	check(path(order,value)=="short","selection consumes remaining work after staged members were deducted")
	value=fresh();order=Order.new();value.remaining={"near":8,"short":8,"far":8}
	check(path(order,value)=="near","equal completion distance retains deterministic rank order")
	value=fresh();order=Order.new();value.remaining={"near":8,"short":0,"far":3}
	check(path(order,value)=="short","ready zero-preparation owner can perform its final commit immediately")

func new_ready_short_owner()->void:
	# D2 pattern: a vegetation owner makes real progress, then small ready road
	# and model owners arrive. Their tokens are new to the ready set, unlike an
	# already observed peer whose remaining number merely changed above.
	var value:=fixture([{"path":"vegetation","remaining":54}]);var order:=Order.new()
	var prefix:Array=[]
	for i:int in 17:
		prefix.append(path(order,value));value.remaining.vegetation-=1
	check(prefix.all(func(p):return p=="vegetation") and value.remaining.vegetation==37,"D2 fixture reaches vegetation 54 to 37 through actual selected services")
	add_owner(value,"new_road",1,10,1);add_owner(value,"new_model",1,10,2)
	check(path(order,value)=="new_road","newly ready one-member road immediately preempts an unprotected 37-member target")
	remove_owner(value,"new_road")
	check(path(order,value)=="new_model","next newly ready one-member model drains before returning to the long owner")
	check(value.jobs.size()==2,"short-owner completion releases its existing slot without increasing admitted capacity")
	value=fixture([{"path":"vegetation","remaining":37}]);order=Order.new();path(order,value)
	add_owner(value,"new_long",100,10,1)
	check(path(order,value)=="vegetation","new readiness alone does not interrupt a shorter current target")
	value=fixture([{"path":"vegetation","remaining":37},{"path":"peer","remaining":80}]);order=Order.new();path(order,value)
	value.jobs.peer.token=RefCounted.new();value.remaining.peer=1
	check(path(order,value)=="peer","new ready generation on an existing path is detected independently of path and UUID")

func safety_and_blocked()->void:
	var value:=fresh();var order:=Order.new()
	check(path(order,value)=="short","safety fixture establishes a drain target")
	add_owner(value,"safety",100,-3,-1)
	var safety:Dictionary=value.heads.pop_back();value.heads.push_front(safety)
	var choices:Array=[]
	for i:int in 20:choices.append(path(order,value))
	check(choices.all(func(p):return p=="safety"),"negative priority interrupts immediately and is never delayed by fairness")
	remove_owner(value,"safety")
	check(path(order,value)=="short","visual draining resumes after safety work leaves readiness")
	# The target stays in admitted jobs, but a dependency removes its ready head.
	var blocked:Dictionary=value.heads[1];value.heads.remove_at(1)
	value.remaining.far=2
	check(path(order,value)=="far","blocked target immediately yields to another actual ready owner")
	value.heads.insert(1,blocked);value.remaining.short=1
	check(path(order,value)=="short","recovered newly ready shorter generation may displace an unprotected target")
	sequences.safety=choices

func target_lifecycle()->void:
	var value:=fresh();var order:=Order.new()
	check(path(order,value)=="short","generation fixture establishes its first owner")
	var old_token:WeakRef=weakref(value.jobs.short.token)
	value.jobs.short.token=RefCounted.new();value.remaining.short=100;value.remaining.near=3
	check(path(order,value)=="near","same path with a new token cannot inherit the old sticky target")
	check(old_token.get_ref()==null,"selector retains token IDs rather than owning retired tokens")
	value=fresh();order=Order.new();path(order,value);value.remaining.near=1
	check(path(order,value,false)=="near","pressure loss immediately restores normal distance/priority service")
	check(path(order,value)=="near","pressure recovery reselects instead of resurrecting the former target")
	value=fresh();order=Order.new();path(order,value)
	var ready:Array=value.heads;value.heads=[]
	check(select(order,value).is_empty(),"empty readiness selects no owner")
	value.heads=ready;value.remaining.near=1
	check(path(order,value)=="near","readiness recovery starts a new eligible drain target")
	value=fresh();order=Order.new();path(order,value)
	old_token=weakref(value.jobs.short.token);remove_owner(value,"short");value.remaining.far=1
	check(path(order,value)=="far" and old_token.get_ref()==null,"retired owner loses sticky state and all token ownership")
	# Safety bypasses ordinary service accounting, but cannot preserve a target
	# across an independently ended pressure episode.
	value=fresh();order=Order.new();path(order,value)
	add_owner(value,"safety",10,-1,-1)
	var safety:Dictionary=value.heads.pop_back();value.heads.push_front(safety)
	value.remaining.near=1
	check(path(order,value,false)=="safety","safety remains first when slot pressure disappears simultaneously")
	remove_owner(value,"safety")
	check(path(order,value)=="near","pressure loss during safety service still invalidates the previous drain target")

func bounded_side_turns()->void:
	var value:=fixture([{"path":"target","remaining":1000},{"path":"other_a","remaining":2000},{"path":"other_b","remaining":3000},{"path":"other_c","remaining":4000}])
	var order:=Order.new();var history:Array=[];var others:Array=[];var bursts_valid:=true
	for round_:int in 4:
		for i:int in 16:
			var chosen:=path(order,value);history.append(chosen)
			bursts_valid=bursts_valid and chosen=="target"
			if not chosen.is_empty():value.remaining[chosen]-=1
		var chosen:=path(order,value);history.append(chosen);others.append(chosen)
		if not chosen.is_empty():value.remaining[chosen]-=1
	check(bursts_valid,"drain target retains each sixteen-unit productive burst")
	check(others==["other_a","other_b","other_c","other_a"],"each sixteen target services give the longest-unserved ready peer one turn")
	check(history.count("target")==64 and others.size()==4,"fairness bounds peer waiting without discarding the drain target")
	sequences.side_turns=history

func mixed_visual_priorities()->void:
	var value:=fixture([{"path":"near_a","remaining":2000,"priority":0,"rank":0},{"path":"near_b","remaining":2100,"priority":0,"rank":1},{"path":"far_target","remaining":1000,"priority":10,"rank":100},{"path":"far_b","remaining":3000,"priority":10,"rank":101},{"path":"far_c","remaining":3100,"priority":10,"rank":102},{"path":"far_d","remaining":3200,"priority":10,"rank":103}])
	var order:=Order.new();var first:Dictionary={};var history:Array=[]
	for i:int in 85:
		var chosen:=path(order,value);history.append(chosen)
		if not first.has(chosen):first[chosen]=i+1
		if not chosen.is_empty():value.remaining[chosen]-=1
	check(history[0]=="far_target","full-slot pressure may drain the least remaining nonnegative-priority owner across priorities 0/10")
	check(first.size()==6 and first.values().all(func(at):return at<=85),"all six ready visual heads receive service within 85 ordinary units")
	check(history.count("far_target")==80 and first.near_a==17 and first.near_b==34,"pressure policy is bounded peer service, not the ordinary four-to-one nearby share")
	add_owner(value,"safety",100,-2,-1)
	var safety:Dictionary=value.heads.pop_back();value.heads.push_front(safety)
	check(path(order,value)=="safety","negative priority still interrupts a mixed-priority pressure episode immediately")
	sequences.mixed_priorities={"first_service":first,"choices":history}

func remaining_cost(queue:Node,owner:Dictionary)->int:
	var before:Dictionary={"owner":owner.duplicate(true),"demanded":queue._demanded_by_id.duplicate(true),"paths":queue._demanded_by_path.duplicate(true),"errors":queue.instance_errors.duplicate(true)}
	var amount:int=queue._remaining_owner_members(owner)
	owner_cost_queries+=1
	inputs_intact=inputs_intact and owner==before.owner and queue._demanded_by_id==before.demanded and queue._demanded_by_path==before.paths and queue.instance_errors==before.errors
	return amount

func remaining_owner_contract()->void:
	var queue:=Deferred.new()
	var owner:Dictionary={"token":RefCounted.new(),"publication_ids":["active_a","active_b","staged","packet","failed","withdrawn"],"staged":{"staged":{"specs":[]}},"collision_staged":{"packet":{"specs":[]}}}
	for uuid:String in owner.publication_ids:
		queue._demanded_by_id[uuid]={"path":"shared","record":{"uuid":uuid}}
	queue._demanded_by_id.erase("withdrawn");queue.instance_errors.failed="fixture failure"
	queue._demanded_by_path.shared=queue._demanded_by_id.values()
	check(remaining_cost(queue,owner)==2,"remaining count excludes staged, retained collision packet, failed and withdrawn members")
	for i:int in 7:
		var uuid:="late_"+str(i);var row:Dictionary={"path":"shared","record":{"uuid":uuid}}
		queue._demanded_by_id[uuid]=row;queue._demanded_by_path.shared.append(row)
	check(remaining_cost(queue,owner)==2,"later demand sharing a model path is excluded from the current token publication IDs")
	# Diagnostic private_finished is cumulative history. A prior projection can
	# have been discarded; only a currently retained staged output subtracts work.
	owner.private_finished={"active_a":true,"active_b":true,"staged":true,"packet":true}
	var trace=Deferred.CompletedTrace;var was_enabled:bool=trace.enabled;var prior_events:Array=trace.events;var prior_dropped:int=trace.dropped
	trace.start()
	for uuid:String in owner.private_finished:trace.record("shared",owner.token.get_instance_id(),"private_finished",{"uuid":uuid})
	check(remaining_cost(queue,owner)==2,"cumulative private_finished events do not claim the current members are retained or committed")
	owner.collision_staged.erase("packet")
	check(remaining_cost(queue,owner)==3,"discarded collision packet becomes work again despite prior private_finished history")
	owner.staged.erase("staged")
	check(remaining_cost(queue,owner)==4,"discarded building stage becomes work again despite prior private_finished history")
	var next_owner:Dictionary={"token":RefCounted.new(),"publication_ids":["late_0","late_1"]}
	check(remaining_cost(queue,next_owner)==2 and remaining_cost(queue,owner)==4,"new same-path token and old token keep separate transaction membership")
	for uuid:String in ["active_a","active_b","staged","packet"]:queue._demanded_by_id.erase(uuid)
	check(remaining_cost(queue,owner)==1,"fully prepared or withdrawn owner retains only the final commit cost floor")
	trace.enabled=was_enabled;trace.events=prior_events;trace.dropped=prior_dropped
	queue.free()

func long_owner_under_short_arrivals()->void:
	var value:=fixture([{"path":"long","remaining":40},{"path":"short","remaining":2}])
	var order:=Order.new();var episodes:=0;var before_first:=-1;var long_services:=0;var history:Array=[]
	for i:int in 90:
		var chosen:=path(order,value);history.append(chosen)
		if chosen=="long":
			if before_first<0:before_first=episodes
			long_services+=1
		if chosen.is_empty():break
		value.remaining[chosen]-=1
		if value.remaining[chosen]>0:continue
		if chosen=="long":break
		episodes+=1
		remove_owner(value,"short");add_owner(value,"short",2,0,1)
	check(before_first>=0 and before_first<=4,"four completed short-owner episodes are enough to promote the waiting long owner")
	check(long_services==40 and value.remaining.long==0,"promoted long owner drains fully despite a continuous supply of short owners")
	check(history.size()<=52,"forty long members finish within four short episodes plus bounded side turns")
	sequences.short_arrivals={"choices":history,"short_episodes":episodes,"before_first_long":before_first}

func replacement_resets_age()->void:
	var value:=fixture([{"path":"long","remaining":40},{"path":"short","remaining":1}])
	var order:=Order.new();var first:Array=[]
	for i:int in 3:
		first.append(path(order,value));remove_owner(value,"short");add_owner(value,"short",1,0,1)
	check(first==["short","short","short"],"age fixture records three completed peer drain episodes")
	var retired:WeakRef=weakref(value.jobs.long.token);value.jobs.long.token=RefCounted.new()
	var after:Array=[]
	for i:int in 2:
		after.append(path(order,value));remove_owner(value,"short");add_owner(value,"short",1,0,1)
	check(after==["short","short"] and retired.get_ref()==null,"new token cannot inherit an older generation's accumulated drain age")

func protected_target_under_new_generation_churn()->void:
	var value:=fixture([{"path":"long","remaining":40},{"path":"short","remaining":1}])
	var order:=Order.new();var history:Array=[];var long_services:=0;var first_long:=-1
	var costs_after_promotion:=-1;var side_turns:=0;var max_jobs:=0;var safety_observed:=false
	for i:int in 60:
		if i>0:
			remove_owner(value,"short");add_owner(value,"short",1,0,1)
		max_jobs=maxi(max_jobs,value.jobs.size())
		if long_services==20 and not safety_observed:
			# Reuse the same second slot for urgent work, then restore a fresh
			# short generation; this fixture never increases admitted capacity.
			remove_owner(value,"short");add_owner(value,"safety",1,-2,-1)
			var urgent:Dictionary=value.heads.pop_back();value.heads.push_front(urgent)
			safety_observed=path(order,value)=="safety";history.append("safety")
			remove_owner(value,"safety");add_owner(value,"short",1,0,1)
		var chosen:=path(order,value);history.append(chosen)
		if chosen=="long":
			if first_long<0:first_long=i;costs_after_promotion=cost_snapshots
			long_services+=1
		elif first_long>=0:side_turns+=1
		if chosen.is_empty():break
		value.remaining[chosen]-=1
		if chosen=="long" and value.remaining.long==0:break
		if chosen=="short" and value.remaining.short==0:remove_owner(value,"short")
	check(first_long>=0 and first_long<=4,"waiting long owner is age-promoted within four distinct short-generation drain choices")
	check(long_services==40 and value.remaining.long==0 and side_turns<=2,"age-protected owner completes despite a fresh one-member generation at every service boundary")
	check(costs_after_promotion>=0 and cost_snapshots==costs_after_promotion,"protected drain does not request repeated remaining-work scans for new ready generations")
	check(max_jobs==2 and history.size()<=47,"new short arrivals keep the two admitted slots and bounded completion service")
	check(safety_observed,"negative priority interrupts even an age-protected target immediately")
	sequences.protected_new_generations={"first_long":first_long,"side_turns":side_turns,"max_jobs":max_jobs,"choices":history}
	# Being unavailable ends protection; returning ready does not resurrect it.
	value=fixture([{"path":"long","remaining":40},{"path":"short","remaining":1}]);order=Order.new()
	for i:int in 4:
		path(order,value);remove_owner(value,"short");add_owner(value,"short",1,0,1)
	check(path(order,value)=="long","blocked-target fixture establishes age protection")
	var blocked:Dictionary=value.heads[0];value.heads.remove_at(0)
	check(path(order,value)=="short","an age-protected target becoming blocked immediately releases selection")
	value.heads.push_front(blocked)
	check(path(order,value)=="short","returning long target does not inherit protection from its blocked episode")

func legacy_gates()->void:
	for mode:String in ["no_pressure","not_white","textures","disabled"]:
		Controls.white_materials=mode!="not_white";Controls.discard_map_textures=mode!="textures"
		var value:=fresh();value.priorities.short_head=10;value.priorities.far_head=10
		var expected_order:=Order.new();var expected:Array=[]
		Order.completed_owner_drain_enabled=false
		for i:int in 24:expected.append(str(expected_order.choose(value.heads,value.priorities,value.ranks,value.jobs).path))
		Order.completed_owner_drain_enabled=mode!="disabled"
		var actual_order:=Order.new();var actual:Array=[]
		for i:int in 24:actual.append(path(actual_order,value,mode!="no_pressure"))
		check(actual==expected,mode+": new optional inputs retain the exact ordinary selector sequence")
	Controls.white_materials=true;Controls.discard_map_textures=true;Order.completed_owner_drain_enabled=true
	var value:=fresh();var order:=Order.new();path(order,value);value.remaining.near=1
	Order.completed_owner_drain_enabled=false;path(order,value)
	Order.completed_owner_drain_enabled=true
	check(path(order,value)=="near","disabling and re-enabling the policy does not restore an obsolete target")

func run()->void:
	var white:=Controls.white_materials;var discard:=Controls.discard_map_textures
	var drain:bool=Order.completed_owner_drain_enabled
	Controls.white_materials=true;Controls.discard_map_textures=true;Order.completed_owner_drain_enabled=true
	shortest_and_sticky();new_ready_short_owner();safety_and_blocked();target_lifecycle();bounded_side_turns();mixed_visual_priorities();remaining_owner_contract()
	long_owner_under_short_arrivals();replacement_resets_age();protected_target_under_new_generation_churn();legacy_gates()
	check(inputs_intact,"all selections leave ready heads, jobs, records, priorities, ranks and remaining counts unchanged")
	check(returns_ready_head,"every returned item is the original ready-head object, never a synthetic or blocked item")
	Controls.white_materials=white;Controls.discard_map_textures=discard;Order.completed_owner_drain_enabled=drain
	print("COMPLETED_OWNER_ORDER ",JSON.stringify({"checks":checks,"failures":failures,"selections":selections,"owner_cost_queries":owner_cost_queries,"cost_snapshots":cost_snapshots,"sequences":sequences}))
	quit(1 if failures else 0)
