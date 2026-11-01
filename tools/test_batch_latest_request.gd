extends SceneTree
## Reproduce latest-request loss through the real sliced preparation pipeline.
## No GPU build is needed: membership, callbacks and worker-generation gates
## are real; the CPU fixture's restore and final GPU commit are observed only.
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
var checks:=0
var reports:Array=[]

class FixtureCpu extends Cpu:
	func restore()->Mesh:return self

class ObservedBatch extends Batch:
	var requests:Array=[]
	var commits:Array=[]
	func request_residency_sync(nodes:Array,excluded:Array=[],immutable_append:bool=false)->void:
		requests.append({"size":nodes.size(),"names":node_names(nodes),"phase":_preparation.get("phase","")})
		super.request_residency_sync(nodes,excluded,immutable_append)
	static func node_names(nodes:Array)->Array:
		var result:Array=[]
		for node:Node in nodes:result.append(str(node.name))
		return result
	func _commit(group:Dictionary,data:Dictionary,_started:int)->void:
		commits.append(group.generation);group.data=data

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func source(f:Dictionary,id:String)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=id;node.mesh=f.mesh
	node.set_meta("ground_batch_record",{"uuid":id,"kind":"box","size":[1,1,1],"building":{"id":"house","floor":0,"part":id,"role":"wall"}})
	f.host.add_child(node)
	return node

func fixture()->Dictionary:
	var host:=Node3D.new();root.add_child(host)
	var mesh:=FixtureCpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	mesh.surfaces=[arrays];mesh.bounds=AABB(Vector3.ZERO,Vector3.ONE);mesh.materials=[StandardMaterial3D.new()]
	var batch:=ObservedBatch.new();host.add_child(batch);batch.set_process(false)
	var f:Dictionary={"host":host,"mesh":mesh,"batch":batch,"nodes":[]}
	for i:int in 40:f.nodes.append(source(f,"base_%03d"%i))
	batch.request_residency_sync(f.nodes,[],false);drain(batch)
	return f

func drain(batch:Node)->void:
	var guard:=0
	while not batch._preparation.is_empty() and guard<100000:
		batch._prepare_step(1);guard+=1
	check(batch._preparation.is_empty() and batch._next_residency.is_empty(),"preparation drains both active and pending requests")

func seek(batch:Node,phase:String)->bool:
	var guard:=0
	while not batch._preparation.is_empty() and batch._preparation.phase!=phase and guard<100000:
		batch._prepare_step(1);guard+=1
	var found:bool=not batch._preparation.is_empty() and batch._preparation.phase==phase
	check(found,"real sliced pipeline reaches "+phase)
	return found

func members(batch:Node)->Array:
	var result:Array=[]
	for group:Dictionary in batch.groups.values():
		for node:Node in group.members:result.append(str(node.name))
	result.sort();return result

func verify(f:Dictionary,expected:Array,label:String)->void:
	drain(f.batch)
	var wanted:Array=ObservedBatch.node_names(expected);wanted.sort()
	check(members(f.batch)==wanted,label+": final membership equals latest requested identities")
	var oracle:=Batch.new();f.host.add_child(oracle);oracle.set_process(false)
	oracle.request_sync(expected);drain(oracle)
	var actual:Dictionary={};var reference:Dictionary={}
	for key:String in f.batch.groups:actual[key]=f.batch.groups[key].signature
	for key:String in oracle.groups:reference[key]=oracle.groups[key].signature
	check(actual==reference,label+": exact keys and signatures equal a fresh full preparation")
	reports.append({"case":label,"requests":f.batch.requests,"members":members(f.batch),"prepared_visits":f.batch.prepared_source_visits,"packed_visits":f.batch.packed_source_visits})
	oracle.clear(false);oracle.free()

func finish(f:Dictionary)->void:
	f.batch.clear(false);f.host.free()

func late_growth(accept_phase:String)->void:
	var f:=fixture();var batch:ObservedBatch=f.batch
	batch.request_residency_sync(f.nodes,[],false)
	if not seek(batch,"prune"):finish(f);return
	var older:Array=f.nodes.duplicate();older.append(source(f,"late_a"))
	batch.request_residency_sync(older,[],false)
	check(not batch._next_residency.is_empty(),"prune queues an older appended snapshot")
	if not seek(batch,accept_phase):finish(f);return
	var latest:Array=older.duplicate();latest.append(source(f,"late_b"))
	batch.request_residency_sync(latest,[],false)
	var accepted:int=batch.requests.size()
	verify(f,latest,"queued prune then newer "+accept_phase)
	check(batch.requests.size()==accepted,"accepted "+accept_phase+" growth never replays the obsolete pending snapshot")
	finish(f)

func latest_at_phase(phase:String,change:String)->void:
	var f:=fixture();var batch:ObservedBatch=f.batch
	batch.request_residency_sync(f.nodes,[],false)
	if not seek(batch,phase):finish(f);return
	var older:Array=f.nodes.duplicate();older.append(source(f,"obsolete"))
	batch.request_residency_sync(older,[],false)
	var latest:Array=f.nodes.duplicate()
	if change=="grow":latest.append(older.back());latest.append(source(f,"newest"))
	elif change=="remove":latest.remove_at(0)
	# "cancel" deliberately returns to the active prefix: the queued addition
	# never became current and must not be resurrected when this pass finishes.
	batch.request_residency_sync(latest,[],false)
	verify(f,latest,phase+" latest "+change)
	finish(f)

func worker_result(gate:Semaphore)->Dictionary:
	gate.wait();return {"observed_worker_result":true}

func stale_worker()->void:
	var f:=fixture();var batch:ObservedBatch=f.batch
	var key:String=batch.groups.keys()[0]
	var original_generation:int=batch.groups[key].generation
	var gate:=Semaphore.new();var worker:=Thread.new()
	check(worker.start(worker_result.bind(gate))==OK,"real background result starts behind a controlled gate")
	batch._workers.append({"thread":worker,"key":key,"generation":original_generation,"started":Time.get_ticks_usec()})
	batch.request_residency_sync(f.nodes,[],false)
	if seek(batch,"prune"):
		var older:Array=f.nodes.duplicate();older.append(source(f,"late_a"))
		batch.request_residency_sync(older,[],false)
		if seek(batch,"prepare"):
			var latest:Array=older.duplicate();latest.append(source(f,"late_b"))
			batch.request_residency_sync(latest,[],false)
			verify(f,latest,"latest membership while an old worker remains live")
			check(worker.is_alive(),"membership replacement does not join the gated live worker")
			check(batch.groups.has(key) and batch.groups[key].generation!=original_generation,"replacement owns a new generation before the old result completes")
	gate.post()
	# Completion is deliberately controlled, never a timing assertion.
	while worker.is_alive():await process_frame
	batch._finish_worker(0)
	check(batch.commits.is_empty(),"obsolete worker result cannot publish into the newer membership")
	check(batch._workers.is_empty() and batch.live_worker_joins==0,"completed old worker is retired without a live join")
	finish(f)

func run()->void:
	Batch.closed_building_preparation_enabled=false
	for phase:String in ["prepare","bin"]:late_growth(phase)
	for phase:String in ["collect","prune","prepare","bin","unique","filter","drop","add"]:
		for change:String in ["grow","cancel","remove"]:latest_at_phase(phase,change)
	await stale_worker()
	var result:Dictionary={"checks":checks,"failures":failures,"cases":reports}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var file:=FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE)
			file.store_string(JSON.stringify(result,"\t"));file.close()
	print("BATCH_LATEST_REQUEST ",JSON.stringify({"checks":checks,"failures":failures,"cases":reports.size()}))
	quit(1 if failures else 0)
