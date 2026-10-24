extends "res://tools/test_private_geometry_retirement.gd"
## Exact native terrain Shape leaves only. No author maps or timing assertions.
const Terrain=preload("res://scripts/world3d/terrain_collision_preparer.gd")
const Owners=preload("res://scripts/world3d/model_resource_owners.gd")
var checks:=0
class WatchedShape extends ConcavePolygonShape3D:
	var receipt:Dictionary={}
	var label:=""
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:receipt.events.append({"label":label,"thread":OS.get_thread_caller_id()})
func check(ok:bool,label:String)->void:
	checks+=1;super.check(ok,label)
func alive(watch:WeakRef)->bool:return watch.get_ref()!=null
func triangle()->PackedVector3Array:return PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK])
func shape(label:String,receipt:Dictionary)->ConcavePolygonShape3D:
	var child:=WatchedShape.new();child.label=label;child.receipt=receipt;child.set_faces(triangle());return child
func owner(geometry:bool=true)->Mesh:
	var value:Mesh=Cpu.new()
	if geometry:
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=triangle()
		value.surfaces=[arrays];value.lods=[{}];value._collision_faces=arrays[Mesh.ARRAY_VERTEX];value.materials.append(null)
	return value
func put_identity(value:Mesh,count:int,receipt:Dictionary,prefix:String)->Array:
	var shapes:Array=[];var watches:Array=[]
	for i:int in count:
		var child:ConcavePolygonShape3D=shape(prefix+str(i),receipt);shapes.append(child);watches.append(weakref(child))
	Terrain._store_shapes(value,shapes);return watches
func identity_state(count:int,geometry:bool=true)->Dictionary:
	var receipt:={"events":[]};var value:Mesh=owner(geometry)
	var watches:Array=put_identity(value,count,receipt,"identity_")
	return {"owner":value,"owner_watch":weakref(value),"receipt":receipt,"children":watches,"count":count}
func queue_owner(state:Dictionary)->bool:
	var values:Array=[state.owner];state.owner=null
	return Retirement.defer_private_array(values,true)
func drop_owner_direct(state:Dictionary)->void:state.owner=null
func advance_front(target:Node)->bool:
	var done:bool=target._advance(target.pending[0],1);target.set_process(false)
	if done:target._finish_front()
	return done
func private_rows(target:Node)->int:
	var rows:=0
	for ticket:Dictionary in target.pending:
		if ticket.get("kind","")=="private_array":rows+=ticket.values.size()
	return rows
func drain_atomic(target:Node,receipt:Dictionary,initial_max:int=0)->Dictionary:
	var maximum:=initial_max;var units:=0;var geometry_tickets:=0
	while not target.pending.is_empty():
		var before:int=receipt.events.size();var ticket:Dictionary=target.pending[0]
		if ticket.get("kind","")=="private_array":
			# One real production atomic unit, independent of clock resolution.
			Retirement._drop_private_value(ticket.values,false);units+=1
			if ticket.values.is_empty():target._finish_front()
		else:
			var done:bool=target._advance(ticket,1);target.set_process(false)
			if done:geometry_tickets+=int(ticket.get("kind","")=="cpu_geometry");target._finish_front()
			else:await process_frame
		maximum=maxi(maximum,receipt.events.size()-before)
	check(target.known.is_empty(),"queue ownership is empty after all child units")
	return {"max_unique_deaths_per_atomic_unit":maximum,"private_child_units":units,"geometry_tickets":geometry_tickets}
func check_threads(receipt:Dictionary,label:String)->void:
	check(receipt.events.all(func(e):return e.thread==OS.get_main_thread_id()),label+" Shape PREDELETE stays on main")
func check_default_mirrors()->void:
	var value:Mesh=owner(false)
	check(value._retirement_terrain_shapes==null and value._retirement_terrain_basis_entries==null,"ordinary CPU owner allocates no terrain mirror containers")
func trial_direct_release()->Dictionary:
	var target:Node=service();var state:Dictionary=identity_state(2,false)
	drop_owner_direct(state);target.set_process(false)
	check(not alive(state.owner_watch),"direct last Variant release destroys the production CPU owner")
	check(private_rows(target)==(2 if Cpu.terrain_shape_retirement_enabled else 0),"PREDELETE also covers last release outside a private queue")
	var report:Dictionary=await drain_atomic(target,state.receipt)
	check(state.receipt.events.size()==2 and state.children.all(func(w):return not alive(w)),"direct-release Shape owners drain exactly once")
	check(target.profile.get("geometry_batches",0)==0,"direct metadata-only release starts no packed worker")
	check_threads(state.receipt,"direct release");report.case="direct_metadata_release";target.free();return report
func trial_identity()->Dictionary:
	var target:Node=service();var state:Dictionary=identity_state(29)
	check(queue_owner(state),"identity uses the actual private queue")
	var began:=Time.get_ticks_usec();var done:=advance_front(target)
	var owner_wall_us:=Time.get_ticks_usec()-began
	check(done,"one CPU private unit completes");var root_deaths:int=state.receipt.events.size()
	var rows:int=private_rows(target)
	check(not alive(state.owner_watch),"CPU owner is gone before child units")
	check(target.profile.terrain_shape_arrays==(1 if Cpu.terrain_shape_retirement_enabled else 0) and target.profile.terrain_shape_refs==rows,"successful terrain donation counters count arrays and direct refs without deduplicating")
	check(root_deaths==0,"WORK CPU owner does not synchronously destroy its 29 terrain Shapes")
	var report:Dictionary=await drain_atomic(target,state.receipt,root_deaths)
	check(report.max_unique_deaths_per_atomic_unit<=1,"WORK each private atomic unit releases at most one terrain Shape")
	check(state.children.all(func(w):return not alive(w)) and state.receipt.events.size()==29,"identity destroys each unique Shape once")
	check(target.profile.get("geometry_unmeasured_owners",0)==1 and target.profile.get("geometry_last_thread_id",OS.get_main_thread_id())!=OS.get_main_thread_id(),"identity packed geometry still retires on a worker")
	check_threads(state.receipt,"identity")
	report.merge({"case":"identity","shape_refs":29,"copied_child_refs":rows,"cpu_private_unit_wall_us":owner_wall_us,"root_deaths":root_deaths});target.free();return report
func basis_state()->Dictionary:
	var receipt:={"events":[]};var value:Mesh=owner()
	var shared:ConcavePolygonShape3D=shape("shared",receipt);var a:ConcavePolygonShape3D=shape("a",receipt);var b:ConcavePolygonShape3D=shape("b",receipt)
	Terrain._store_variant(value,"a",[shared,a]);Terrain._store_variant(value,"b",[shared,b])
	Terrain._store_shapes(value,[shared]) # Same Shape is also borrowed by the identity cache.
	var borrowed:Array=value.get_meta(Terrain.BASIS_CACHE_META).entries.b.shapes
	var body:=StaticBody3D.new();root.add_child(body);var collision:=CollisionShape3D.new();collision.shape=shared;body.add_child(collision)
	return {"owner":value,"receipt":receipt,"children":[weakref(shared),weakref(a),weakref(b)],"borrowed":borrowed,"body":body}
func verify_basis_borrower(state:Dictionary)->void:
	check(state.borrowed.size()==2 and state.borrowed[0]==state.children[0].get_ref() and state.borrowed[1]==state.children[2].get_ref(),"basis borrowed array keeps exact Shape identities")
	for child:ConcavePolygonShape3D in state.borrowed:check(var_to_bytes(child.get_faces())==var_to_bytes(triangle()),"basis borrowed faces remain byte exact")
func release_array(state:Dictionary)->void:state.borrowed=[]
func release_body(state:Dictionary)->void:
	var body:Node=state.body;state.body=null;body.free()
func trial_basis()->Dictionary:
	var target:Node=service();var state:Dictionary=basis_state()
	check(queue_owner(state),"basis uses actual private queue");check(advance_front(target),"basis CPU unit completes")
	var root_deaths:int=state.receipt.events.size();var rows:int=private_rows(target)
	check(root_deaths==0,"WORK basis CPU owner defers its unborrowed Shape")
	var report:Dictionary=await drain_atomic(target,state.receipt,root_deaths)
	check(state.receipt.events.size()==1 and not alive(state.children[1]) and alive(state.children[0]) and alive(state.children[2]),"only unborrowed basis Shape dies after cache units")
	verify_basis_borrower(state);release_array(state)
	check(state.receipt.events.size()==2 and alive(state.children[0]) and not alive(state.children[2]),"borrowed array release frees only its private Shape")
	release_body(state)
	check(state.receipt.events.size()==3 and state.children.all(func(w):return not alive(w)),"shared basis alias dies once after final body")
	check_threads(state.receipt,"basis");report.merge({"case":"basis_borrowers","copied_child_refs":rows,"root_deaths":root_deaths});target.free();return report
func put_variant(value:Mesh,key:String,receipt:Dictionary,label:String)->WeakRef:
	var child:ConcavePolygonShape3D=shape(label,receipt);Terrain._store_variant(value,key,[child]);return weakref(child)
func replacement_state()->Dictionary:
	var receipt:={"events":[]};var value:Mesh=owner(false)
	var identity_old:Array=put_identity(value,1,receipt,"identity_old")
	var identity_new:Array=put_identity(value,1,receipt,"identity_new")
	check(not alive(identity_old[0]),"identity replacement is not pinned by the mirror")
	var old:WeakRef=put_variant(value,"same",receipt,"same_old")
	var current:WeakRef=put_variant(value,"same",receipt,"same_new")
	check(not alive(old),"same-key basis replacement releases the old Shape")
	var borrowed:Array=value.get_meta(Terrain.BASIS_CACHE_META).entries.same.shapes
	var evicted:WeakRef=put_variant(value,"will_evict",receipt,"evicted")
	var watches:Array=identity_new+[current,evicted]
	for i:int in 8:watches.append(put_variant(value,"key"+str(i),receipt,"key"+str(i)))
	var cache:Dictionary=value.get_meta(Terrain.BASIS_CACHE_META)
	check(cache.entries.size()==Terrain.BASIS_VARIANT_LIMIT and not cache.entries.has("same") and not cache.entries.has("will_evict"),"basis cache still evicts to exactly eight variants")
	check(not alive(evicted) and alive(current),"evicted private Shape is gone but external array still borrows its Shape")
	check(is_same(value._retirement_terrain_shapes,value.get_meta("runtime_terrain_shapes")) and is_same(value._retirement_terrain_basis_entries,cache.entries),"mirrors share current containers without copying or retaining old versions")
	return {"owner":value,"receipt":receipt,"children":watches,"borrowed":borrowed,"borrowed_watch":current}
func trial_replacement()->Dictionary:
	var target:Node=service();var state:Dictionary=replacement_state()
	release_array(state);check(not alive(state.borrowed_watch),"dropping evicted external array releases its final Shape promptly")
	check(queue_owner(state),"replacement owner queued");check(advance_front(target),"replacement CPU unit completes")
	var report:Dictionary=await drain_atomic(target,state.receipt)
	check(state.children.all(func(w):return not alive(w)),"all retained current variants drain without stale owner")
	check_threads(state.receipt,"replacement");report.case="replacement_and_lru";target.free();return report
func clear_terrain_cache(state:Dictionary)->void:
	state.owner.set_terrain_shapes([])
	state.owner.set_terrain_basis_cache({"entries":{},"serial":0})
func trial_cache_reset()->void:
	var target:Node=service();var state:Dictionary=identity_state(1,false)
	state.children.append(put_variant(state.owner,"only",state.receipt,"reset_basis"))
	clear_terrain_cache(state)
	check(state.children.all(func(w):return not alive(w)) and state.receipt.events.size()==2,"explicit empty cache replacement releases identity and basis owners while CPU lives")
	drop_owner_direct(state);target.set_process(false)
	check(target.pending.is_empty(),"empty cached sets produce no redundant retirement ticket")
	target.free()
func stress_state(repeats:int)->Dictionary:
	var receipt:={"events":[]};var value:Mesh=owner(false);var watches:Array=[]
	for slot:int in 9:
		var child:ConcavePolygonShape3D=shape("stress"+str(slot),receipt);watches.append(weakref(child))
		var refs:Array=[];refs.resize(repeats);refs.fill(child)
		if slot==0:Terrain._store_shapes(value,refs)
		else:Terrain._store_variant(value,str(slot),refs)
	return {"owner":value,"receipt":receipt,"children":watches}
func trial_ref_work()->Dictionary:
	var target:Node=service();var state:Dictionary=stress_state(1024)
	check(queue_owner(state),"reference-count stress owner queued")
	var began:=Time.get_ticks_usec();var done:=advance_front(target)
	var wall_us:=Time.get_ticks_usec()-began
	check(done,"reference-count stress CPU unit completes");var rows:int=private_rows(target)
	check(rows==(9216 if Cpu.terrain_shape_retirement_enabled else 0),"known nine sets copy exactly 9216 direct refs only when enabled")
	check(target.profile.terrain_shape_refs==rows,"many-ref workload counter counts refs rather than nine unique Shapes")
	await drain(target)
	check(state.receipt.events.size()==9 and state.children.all(func(w):return not alive(w)),"9216 aliases destroy exactly nine native Shapes")
	check_threads(state.receipt,"ref work");target.free()
	return {"case":"many_known_refs","known_sets":9,"input_shape_refs":9216,"copied_child_refs":rows,"unique_shapes":9,"cpu_private_unit_wall_us":wall_us,"hard_budget_claim":false}
func callback_done(receipt:Dictionary,target:Node)->void:
	receipt.calls+=1;receipt.deaths_at_callback=receipt.events.size()
	receipt.worker_joined_thread_at_callback=target.profile.get("geometry_last_thread_id",0)
	receipt.geometry_pending_at_callback=0
	for ticket:Dictionary in target.pending:
		receipt.geometry_pending_at_callback+=int(ticket.get("kind","")=="cpu_geometry")
func enqueue_admitted(target:Node,kind:String,geometry_mode:String)->Dictionary:
	var receipt:={"events":[],"calls":0,"deaths_at_callback":-1};var admission:=RefCounted.new();var watch:WeakRef=weakref(admission)
	var first:Mesh=owner(geometry_mode!="empty");var last:Mesh=owner(geometry_mode=="both")
	put_identity(first,2,receipt,"first");put_identity(last,2,receipt,"last")
	if kind=="model":
		var owners:=Owners.new();owners.visuals.append(last);owners.visuals.append(first)
		check(Retirement.defer_model_packet({"resource_owners":owners},callback_done.bind(receipt,target),admission),"model admission accepted")
	else:
		# Use the real import state walker without the public >64-node heuristic.
		var state:=GLTFState.new();state.set_meta("first_cpu",first);state.set_meta("last_cpu",last)
		var states:Array[GLTFState]=[state]
		target._enqueue_import(states,callback_done.bind(receipt,target),admission)
	return {"receipt":receipt,"watch":watch}
func trial_fence(kind:String,geometry_mode:String)->Dictionary:
	var target:Node=service();var state:Dictionary=enqueue_admitted(target,kind,geometry_mode)
	while not advance_front(target):await process_frame
	var rows:int=private_rows(target);var kinds:Array=[]
	for ticket:Dictionary in target.pending:kinds.append(ticket.get("kind",""))
	if Cpu.terrain_shape_retirement_enabled:
		check(state.receipt.calls==0 and alive(state.watch),kind+" "+geometry_mode+" admission survives CPU destruction and child donation")
	var report:Dictionary=await drain_atomic(target,state.receipt)
	check(state.receipt.calls==1 and state.receipt.deaths_at_callback==4,kind+" "+geometry_mode+" callback follows every Shape child and geometry worker")
	check(not alive(state.watch),kind+" "+geometry_mode+" admission releases exactly at completion")
	check(state.receipt.geometry_pending_at_callback==0,kind+" "+geometry_mode+" callback has no pending geometry worker")
	if geometry_mode!="empty":check(state.receipt.worker_joined_thread_at_callback!=0 and state.receipt.worker_joined_thread_at_callback!=OS.get_main_thread_id(),kind+" "+geometry_mode+" callback observes the joined CPU worker")
	check_threads(state.receipt,kind+" fence")
	if geometry_mode=="both":check(target.profile.get("geometry_batches",0)==1 and target.profile.get("geometry_unmeasured_owners",0)==2,kind+" still reuses one geometry batch for both owners")
	if geometry_mode=="empty":check(target.profile.get("geometry_batches",0)==0,kind+" metadata-only owner starts no geometry worker")
	report.merge({"case":kind+"_"+geometry_mode,"fifo_after_parent":kinds,"child_refs":rows,"callback_deaths":state.receipt.deaths_at_callback,"worker_joined_thread_at_callback":state.receipt.worker_joined_thread_at_callback,"geometry_pending_at_callback":state.receipt.geometry_pending_at_callback});target.free();return report
func trial_shutdown()->void:
	var target:Node=service();var state:Dictionary=identity_state(3)
	check(queue_owner(state),"shutdown owner enters private queue")
	target.free()
	check(state.receipt.events.size()==3 and state.children.all(func(w):return not alive(w)),"shutdown fallback releases all children without leaked queue")
	check_threads(state.receipt,"shutdown")
func run()->void:
	create_timer(60).timeout.connect(func():push_error("terrain shape retirement fixture deadline");quit(2))
	Cpu.terrain_shape_retirement_enabled=not "--legacy-terrain-units" in OS.get_cmdline_user_args()
	Retirement.ordered_retirement_tail_enabled=not "--legacy-retirement-tail" in OS.get_cmdline_user_args()
	Retirement.background_geometry_release_enabled=true;Retirement.batched_geometry_release_enabled=true
	var errors:=Errors.new();OS.add_logger(errors);var reports:Array=[]
	check_default_mirrors()
	var only_fences:bool="--only-fences" in OS.get_cmdline_user_args()
	if not only_fences:
		reports.append(await trial_identity());reports.append(await trial_basis());reports.append(await trial_replacement());reports.append(await trial_direct_release());trial_cache_reset();reports.append(await trial_ref_work());trial_shutdown()
	for kind:String in ["model","import"]:
		for mode:String in ["both","mixed","empty"]:reports.append(await trial_fence(kind,mode))
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script/engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("TERRAIN_SHAPE_RETIREMENT ",JSON.stringify({"checks":checks,"failures":failures,"split":Cpu.terrain_shape_retirement_enabled,"ordered_tail":Retirement.ordered_retirement_tail_enabled,"reports":reports,"performance_sample":false}))
	quit(1 if failures else 0)
