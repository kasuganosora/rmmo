extends SceneTree
## Deliberately held CPU tasks verify no live join during detach/retirement.
## No author maps, GPU geometry or performance load are used.
const Retirement=preload("res://scripts/world3d/cpu_worker_retirement.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Ground=preload("res://scripts/world3d/ground_batcher.gd")
const Collision=preload("res://scripts/world3d/stream_collision_preparer.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
var passed:=0
var failed:=0

class Receipt extends RefCounted:
	var released_on:int=-1
class Owner extends Resource:
	var receipt:Receipt
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE and receipt!=null:receipt.released_on=OS.get_thread_caller_id()
class Gate extends RefCounted:
	var mutex:=Mutex.new()
	var opened:=false
	var entered:=false
	func open()->void:
		mutex.lock();opened=true;mutex.unlock()
	func has_entered()->bool:
		mutex.lock();var value:=entered;mutex.unlock();return value
	static func work(gate:Gate,packet:Dictionary)->Dictionary:
		gate.mutex.lock();gate.entered=true;gate.mutex.unlock()
		# A failing old implementation must fail assertions, not hang the host
		# forever while its scene-thread timeout cannot be processed.
		var deadline:=Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<deadline:
			gate.mutex.lock();var done:=gate.opened;gate.mutex.unlock()
			if done:break
			OS.delay_usec(100)
		return packet
class ReentryGround extends Ground:
	var rebuilt:=0
	func _prepare_step(_budget:int)->void:pass
	func _build_next(_background:bool=false)->void:
		pending.pop_front();rebuilt+=1

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failed+=1

func held_retirement(kind:String,direct_exit:bool)->void:
	var host:=Node3D.new();root.add_child(host)
	var node:Node=Ground.new() if kind=="ground" else Collision.new();host.add_child(node);node.set_process(false)
	var owner:=Owner.new();var receipt:=Receipt.new();owner.receipt=receipt
	var reference:WeakRef=weakref(owner);var gate:=Gate.new();var thread:=Thread.new()
	var ticket:=Retirement.watch(thread,self,[owner])
	var token:RefCounted=ticket.token;var lease:WeakRef=weakref(ticket.lease)
	check(thread.start(Gate.work.bind(gate,{"retained_resources":[owner],"faces":PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK])}))==OK,kind+" CPU worker starts with a leased source")
	owner=null
	while not gate.has_entered():await process_frame
	if kind=="ground":node._workers.append({"key":"cancelled_group","generation":1,"started":Time.get_ticks_usec(),"thread":thread,"retirement":ticket})
	elif kind=="ordinary":node._thread=thread;node._retirement=ticket
	else:node._terrain._thread=thread;node._terrain._retirement=ticket
	# This would deadlock until timeout with the old unconditional _exit_tree join.
	if not direct_exit:node.retire_workers(self)
	host.free()
	check(thread.is_alive() and token.is_cancelled(),kind+" "+("exit" if direct_exit else "explicit retirement")+" returns while CPU work is still running")
	check(reference.get_ref()!=null and lease.get_ref()!=null and token.has_meta("admission_owner"),kind+" source and same lifetime lease survive the removed map")
	var frame_before:=Engine.get_process_frames()
	await process_frame;await process_frame
	check(Engine.get_process_frames()>frame_before and reference.get_ref()!=null,kind+" later frames continue while old worker holds its input")
	gate.open()
	var deadline:=Time.get_ticks_msec()+5000
	while token.has_meta("admission_owner") and Time.get_ticks_msec()<deadline:await process_frame
	check(not token.has_meta("admission_owner") and lease.get_ref()==null and reference.get_ref()==null,kind+" drainer joins and clears output owners before releasing its lease")
	check(receipt.released_on==OS.get_main_thread_id(),kind+" last Resource owner releases on main")

func real_dispatch()->void:
	var host:=Node3D.new();root.add_child(host)
	var preparer:=Collision.new();host.add_child(preparer)
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK]);mesh.surfaces=[arrays];mesh.materials=[null]
	var spec:Dictionary={"uuid":"dispatch","mesh":mesh,"collision_mesh":mesh,"transform":Transform3D.IDENTITY,"extras":{}}
	check(not preparer.prepare(spec,host) and not preparer._retirement.is_empty(),"actual ordinary dispatch registers a drainer lease before handoff")
	var token:RefCounted=preparer._retirement.token
	host.free()
	var deadline:=Time.get_ticks_msec()+5000
	while token.has_meta("admission_owner") and Time.get_ticks_msec()<deadline:await process_frame
	check(not token.has_meta("admission_owner"),"actual extraction packet can be abandoned and drained after its node is freed")
	var rows:Array=[arrays];var snapshot:=Retirement.snapshot_surfaces(rows)
	rows[0][Mesh.ARRAY_VERTEX]=PackedVector3Array()
	check(snapshot[0][Mesh.ARRAY_VERTEX].size()==3,"input snapshots isolate both Array containers while packed channels use COW")

func reentry(kind:String)->void:
	var first:=Node3D.new();var second:=Node3D.new();root.add_child(first);root.add_child(second)
	var node:Node=ReentryGround.new() if kind=="ground" else Collision.new();first.add_child(node);node.set_process(false)
	var gates:Array=[];var tokens:Array=[]
	var count_:int=Ground.MAX_WORKERS if kind=="ground" else 1
	for at:int in count_:
		var gate:=Gate.new();gates.append(gate);var thread:=Thread.new()
		var ticket:=Retirement.watch(thread,self,[]);tokens.append(ticket.token)
		thread.start(Gate.work.bind(gate,{"faces":PackedVector3Array()}))
		while not gate.has_entered():await process_frame
		if kind=="ground":
			var key:="group_"+str(at);node.groups[key]={"generation":1}
			node._workers.append({"key":key,"generation":1,"started":Time.get_ticks_usec(),"thread":thread,"retirement":ticket})
		elif kind=="ordinary":node._thread=thread;node._retirement=ticket
		else:node._terrain._thread=thread;node._terrain._retirement=ticket
	node.reparent(second)
	check(not node._retiring_workers,kind+" same-tree reparent resumes scheduling instead of permanently retiring the target")
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();vertices.resize(3075 if kind=="terrain" else 3)
	arrays[Mesh.ARRAY_VERTEX]=vertices;mesh.surfaces=[arrays];mesh.materials=[null]
	var spec:Dictionary={"uuid":"reentry","mesh":mesh,"collision_mesh":mesh,"transform":Transform3D.IDENTITY,"extras":{}}
	if kind=="ground":
		node._process(0.)
		check(node.rebuilt==0 and node.pending.size()==count_,"reparented Ground retains pending generations while retired workers still occupy all original slots")
	else:
		check(not node.prepare(spec,second) and node._thread==null and node._terrain._thread==null,kind+" reparent cannot start replacement CPU work before the old lease drains")
	for gate:Gate in gates:gate.open()
	var deadline:=Time.get_ticks_msec()+5000
	while tokens.any(func(token):return token.has_meta("admission_owner")) and Time.get_ticks_msec()<deadline:await process_frame
	if kind=="ground":
		node._process(0.)
		check(node.rebuilt==count_ and node.pending.is_empty(),"current Ground generations resume after retired slots are released")
	else:
		check(not node.prepare(spec,second) and (node._thread!=null or node._terrain._thread!=null),kind+" reparented collision preparer accepts new work after its old owner has drained")
	first.free();second.free()
	await process_frame;await process_frame

func run()->void:
	create_timer(30).timeout.connect(func():push_error("CPU retirement timeout");quit(2))
	var errors:=Errors.new();OS.add_logger(errors)
	for kind:String in ["ground","ordinary","terrain"]:
		await held_retirement(kind,false)
		await held_retirement(kind,true)
		await reentry(kind)
	await real_dispatch()
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script/engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("CPU_WORKER_RETIREMENT passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
