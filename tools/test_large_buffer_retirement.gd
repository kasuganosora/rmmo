extends SceneTree
## Reproduce final ownership of large import buffers without GPU resources.
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
var failed:=0
var checks:=0
class Ledger extends Admission:
	var releases:=0
	var released_on:=0
	func release(key:String)->void:
		releases+=1;released_on=OS.get_thread_caller_id();super.release(key)
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1;print("PASS " if value else "FAIL ",label)
	if not value:failed+=1
func buffers()->Array:
	var result:Array=[]
	for mb:int in [128,64,128,64]:
		var value:=PackedByteArray();value.resize(mb*1024*1024);value.fill(73)
		result.append(value)
	return result
func service()->Node:
	var value:Node=Retirement.new();root.add_child(value);value.set_process(false);return value
func install(target:Node,ledger:Ledger)->Dictionary:
	ledger.reserve("bytes",{"estimated_bytes":384*1024*1024,"exclusive":false});ledger.park("bytes")
	var states:Array[GLTFState]=[]
	var ticket:Dictionary=target._import_ticket(states,Callable(ledger,"release").bind("bytes"),ledger)
	ticket.source_id="bytes";target.pending.append(ticket);target.known.bytes=true
	return ticket
func trial(background:bool)->Dictionary:
	Retirement.background_byte_release_enabled=background
	var target:=service();var ledger:=Ledger.new();var ticket:=install(target,ledger)
	ticket.phase=1;ticket.resources=buffers()
	var began:=Time.get_ticks_usec();var maximum:=0;var slices:=0
	while true:
		var before:=Time.get_ticks_usec();var done:bool=target._advance(ticket,1000)
		maximum=maxi(maximum,Time.get_ticks_usec()-before);slices+=1
		if done:target._finish_front();break
		if ticket.cpu_worker!=null:
			check(ledger.releases==0 and ledger.reserved_bytes==384*1024*1024,"in-flight byte disposal retains its original reservation")
		await process_frame
	var report:Dictionary={"background":background,"main_max_us":maximum,"wall_us":Time.get_ticks_usec()-began,"slices":slices,"profile":target.profile.duplicate()}
	check(target.pending.is_empty() and target.known.is_empty() and ledger.releases==1 and ledger.count()==0,"ticket completion releases reservation exactly once")
	check(ledger.released_on==OS.get_main_thread_id(),"admission callback runs on main")
	check(target.profile.import_values==4,"all four owned buffers are accounted for")
	if background:
		check(target.profile.get("cpu_bytes",0)==384*1024*1024 and target.profile.cpu_values==4,"worker receives the same logical bytes and values")
		check(target.profile.cpu_last_thread_id!=OS.get_main_thread_id(),"last byte references are released on a different thread")
	target.free();return report
func borrowed_and_exit()->void:
	Retirement.background_byte_release_enabled=true
	var target:=service();var ledger:=Ledger.new();var ticket:=install(target,ledger)
	var state:=GLTFState.new();var value:=PackedByteArray();value.resize(16*1024*1024);value.fill(37)
	var borrower:PackedByteArray=value
	state.buffers=[value];state.glb_data=value;state.json={"extras":{"same_bytes":value}}
	var watches:Array=[weakref(state)];ticket.states.append(state);target._retain(ticket,state)
	state=null;value=PackedByteArray()
	while not target._advance(ticket,1000):await process_frame
	target._finish_front()
	check(watches[0].get_ref()==null and borrower.size()==16*1024*1024 and borrower[0]==37 and borrower[-1]==37,"actual GLTFState graph releases while borrowed packed bytes remain intact")
	var copy:PackedByteArray=borrower.duplicate();copy[0]=91
	check(borrower[0]==37 and copy[0]==91,"an explicit packed-buffer copy remains isolated from the borrower")
	check(ledger.releases==1 and ledger.reserved_bytes==0,"shared-buffer graph completes its callback once")
	target.free();borrower=PackedByteArray();copy=PackedByteArray()
	target=service();ledger=Ledger.new();ticket=install(target,ledger)
	ticket.phase=1;ticket.resources=buffers()
	# A one-microsecond slice starts the worker only after all source slots clear.
	while ticket.cpu_worker==null:target._advance(ticket,1)
	target.free()
	check(ledger.releases==1 and ledger.count()==0 and ticket.cpu_worker==null and ticket.cpu_buffers.is_empty(),"tree exit joins outstanding byte work before callback and destroys no live Thread")
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	var errors:=Errors.new();OS.add_logger(errors)
	var args:=OS.get_cmdline_user_args()
	if "--gdb-witness" in args:
		print("BUFFER_WITNESS_READY pid=",OS.get_process_id())
		await create_timer(15).timeout
	var reports:Array=[]
	for enabled:bool in [false,true,true,false]:reports.append(await trial(enabled))
	await borrowed_and_exit()
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script/engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	Retirement.background_byte_release_enabled=true
	print("LARGE_BUFFER_RETIREMENT ",JSON.stringify({"checks":checks,"failures":failed,"trials":reports}))
	quit(0 if failed==0 else 1)
