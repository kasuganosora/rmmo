extends SceneTree
## Deterministic private-retirement units, not a timing/FPS benchmark.
const House=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
var checks:=0
var failures:=0
var split:=true

class OwnerWitness extends RefCounted:
	var receipt:Dictionary={}
	var label:=""
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:receipt.owners.append({"label":label,"thread":OS.get_thread_caller_id()})
class WatchedMaterial extends StandardMaterial3D:
	var receipt:Dictionary={}
	var label:=""
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:receipt.materials.append({"label":label,"thread":OS.get_thread_caller_id()})

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func owner(label:String,receipt:Dictionary,channels:Array)->Mesh:
	var value:=Cpu.new();value.surfaces=channels;value.lods=[{}]
	value._collision_faces=channels[0][Mesh.ARRAY_VERTEX]
	var witness:=OwnerWitness.new();witness.label=label;witness.receipt=receipt
	value.set_meta("retirement168_owner_witness",witness)
	var material:=WatchedMaterial.new();material.label=label;material.receipt=receipt
	value.materials=[material]
	return value
func prepare_case(key:String,alias:bool,borrow_dictionary:bool,render_cache:bool,borrow_channels:bool)->Dictionary:
	var receipt:={"owners":[],"materials":[]}
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK])
	var channels:Array=[arrays]
	var render:Mesh=owner("render",receipt,channels)
	var source:Mesh=render if alias else owner("source",receipt,channels)
	var entry:={"mesh":render,"source":source}
	House._meshes[key]=entry
	if render_cache:House._render_meshes["retirement168:"+key]=render
	var borrower:Mesh=null
	if borrow_channels:
		borrower=Cpu.new();borrower.surfaces=channels;borrower.lods=[{}]
		borrower._collision_faces=arrays[Mesh.ARRAY_VERTEX]
	return {"receipt":receipt,"watches":[weakref(render),weakref(source)],
		"material_watches":[weakref(render.materials[0]),weakref(source.materials[0])],
		"borrowed":entry if borrow_dictionary else {},"borrower":borrower,
		"before_channels":var_to_bytes(channels),"channels":channels,
		"owner_ids":[render.get_instance_id(),source.get_instance_id()]}
func dead_unique(watches:Array)->int:
	# WeakRef count can include two aliases; owner witness records unique deaths.
	var result:=0
	for reference:WeakRef in watches:
		if reference.get_ref()==null:result+=1
	return result
func verify_dictionary_borrower(state:Dictionary)->void:
	var borrowed:Dictionary=state.borrowed
	check(borrowed.size()==2 and borrowed.has("mesh") and borrowed.has("source"),"borrowed entry keeps exactly its original fields")
	check(borrowed.mesh.get_instance_id()==state.owner_ids[0] and borrowed.source.get_instance_id()==state.owner_ids[1],"borrowed entry retains exact owners after cache eviction")
	check(var_to_bytes(borrowed.mesh.surfaces)==state.before_channels and var_to_bytes(borrowed.source.surfaces)==state.before_channels,"borrowed entry channels remain byte exact")
func retain_external_owner(state:Dictionary)->void:
	state.external_owner=state.borrowed.mesh
func release_external_owner(state:Dictionary)->void:
	state.external_owner=null
func release_borrowed_entry(state:Dictionary)->void:
	# Drop our reference; never clear a shared dictionary or mesh field.
	state.borrowed={}
func release_cpu_borrower(state:Dictionary)->void:
	state.borrower=null
func drain(target:Node)->void:
	var deadline:=Time.get_ticks_msec()+10000
	while not target.pending.is_empty() and Time.get_ticks_msec()<deadline:
		var complete:bool=target._advance(target.pending[0],1000)
		target.set_process(false)
		if complete:target._finish_front()
		else:await process_frame
	check(target.pending.is_empty() and target.known.is_empty(),"all private/CPU transfer tickets finish")
func run_case(label:String,alias:bool=false,borrow_dictionary:bool=false,render_cache:bool=false,borrow_channels:bool=false)->Dictionary:
	var target:Node=Retirement._service();target.set_process(false)
	check(target.pending.is_empty(),label+" starts with no retirement work")
	var key:="retirement168_"+label
	var state:=prepare_case(key,alias,borrow_dictionary,render_cache,borrow_channels)
	House.evict_geometry({key:true});target.set_process(false)
	check(not House._meshes.has(key) and not House._render_meshes.has("retirement168:"+key),label+" logical cache eviction is immediate")
	check(state.receipt.owners.is_empty() and state.receipt.materials.is_empty(),label+" donation retains all resources until retirement")
	check(target.pending.size()==1 and target.pending[0].kind=="private_array",label+" producer donates only the private owner container")
	if target.pending.size()!=1 or target.pending[0].kind!="private_array":await drain(target);return {}
	var ticket:Dictionary=target.pending[0]
	var expected_units:int=(2 if split else 1)+(1 if render_cache else 0)
	check(ticket.values.size()==expected_units,label+" exact producer unit count")
	if split:
		check(ticket.values.all(func(v):return v is Mesh),label+" typed direct Mesh owners are individual units")
	else:check(ticket.values[0] is Dictionary,label+" old control retains dictionary as one unit")
	var deaths_per_unit:Array[int]=[]
	while not ticket.values.is_empty():
		var before:int=state.receipt.owners.size()
		# Exercise the exact production atomic unit, without a clock-dependent
		# 1-us budget assertion. Its full VM frame unwinds before observing deaths.
		Retirement._drop_private_value(ticket.values,false)
		target.set_process(false)
		deaths_per_unit.append(state.receipt.owners.size()-before)
	target._finish_front()
	var maximum:int=deaths_per_unit.max() if not deaths_per_unit.is_empty() else 0
	if not alias and not borrow_dictionary:
		check(maximum<=1,"WORK "+label+" destroys at most one owner per atomic retirement unit")
		check(deaths_per_unit.count(1)==2 if split else deaths_per_unit.count(2)==1,label+" old/new unit topology exposes both same total owner deaths")
	if alias:
		check(deaths_per_unit==([0,1] if split else [1]),"same-owner alias releases exactly once without alias scans")
	if borrow_dictionary:
		check(state.receipt.owners.is_empty() and dead_unique(state.watches)==0,"borrowed dictionary still owns both resources after queue drain")
		verify_dictionary_borrower(state)
		retain_external_owner(state)
		release_borrowed_entry(state)
		check(state.receipt.owners.size()==1 and state.watches[0].get_ref()!=null and state.watches[1].get_ref()==null,"independent external Mesh owner survives after borrowed entry releases")
		check(var_to_bytes(state.external_owner.surfaces)==state.before_channels,"external Mesh owner still exposes original shared channels")
		release_external_owner(state)
	check(state.receipt.owners.size()==(1 if alias else 2) and dead_unique(state.watches)==2,label+" each unique mesh owner eventually dies exactly once")
	check(state.receipt.materials.size()==(1 if alias else 2) and dead_unique(state.material_watches)==2,label+" materials eventually release exactly once per unique owner")
	check(state.receipt.owners.all(func(v):return v.thread==OS.get_main_thread_id()) and state.receipt.materials.all(func(v):return v.thread==OS.get_main_thread_id()),label+" Resource and GPU-material destruction remain on main")
	await drain(target)
	check(int(target.profile.get("geometry_last_thread_id",OS.get_main_thread_id()))!=OS.get_main_thread_id(),label+" pure CPU transfer processing runs on worker")
	check(int(target.profile.get("geometry_unmeasured_owners",0))==(1 if alias else 2),label+" exactly the original unique CPU mesh owners donate geometry")
	check(var_to_bytes(state.channels)==state.before_channels,label+" CPU donation never mutates borrowed nested channels")
	if borrow_channels:
		check(var_to_bytes(state.borrower.surfaces)==state.before_channels and state.borrower._collision_faces.size()==3,"live CPU borrower keeps exact shared channels after workers finish")
		release_cpu_borrower(state);target.set_process(false);await drain(target)
	var report:={"case":label,"split":split,"units":expected_units,"deaths_per_unit":deaths_per_unit,"max_unique_owner_deaths":maximum,"owner_deaths":state.receipt.owners.size(),"material_deaths":state.receipt.materials.size(),"cpu_geometry_owners":target.profile.get("geometry_unmeasured_owners",0)}
	check(House._meshes.is_empty() and House._render_meshes.is_empty(),label+" leaves no cache owners")
	target.free();return report
func run()->void:
	create_timer(30).timeout.connect(func():push_error("owner-unit fixture deadline");quit(2))
	var errors:=Errors.new();OS.add_logger(errors)
	split="--legacy-owner-units" not in OS.get_cmdline_user_args()
	House.split_retirement_owner_units_enabled=split
	Retirement.background_geometry_release_enabled=true;Retirement.batched_geometry_release_enabled=true
	check(House._meshes.is_empty() and House._render_meshes.is_empty() and House._decoded.is_empty(),"isolated fixture has no pre-existing cache owners")
	var reports:Array=[]
	reports.append(await run_case("independent"))
	reports.append(await run_case("alias",true))
	reports.append(await run_case("dictionary_borrower",false,true))
	reports.append(await run_case("render_cache_alias",false,false,true))
	reports.append(await run_case("shared_cpu_borrower",false,false,false,true))
	House.split_retirement_owner_units_enabled=true
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script/engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("PREFAB_RETIREMENT_OWNER_UNITS ",JSON.stringify({"checks":checks,"failures":failures,"legacy":not split,"reports":reports,"performance_sample":false}))
	quit(1 if failures else 0)
