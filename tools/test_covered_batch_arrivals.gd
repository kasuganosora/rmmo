extends SceneTree
## Delayed producer fixture: real membership and geometry, deterministic arrivals.
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
class Producer extends Node:
	var covered:=true
	var idle:=false
	func _covered_loading_ready()->bool:return covered
	func is_idle()->bool:return idle
class CountedBatch extends "res://scripts/world3d/ground_batcher.gd":
	var submitted_vertices:=0
	func _commit(group:Dictionary,data:Dictionary,started:int)->void:
		submitted_vertices+=int(data.get("source_vertices",0))
		super._commit(group,data,started)

var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func pump(batch:Node,allow_hold:bool)->void:
	for i:int in 2000:
		batch._process_work(2000)
		if batch.stats().pending_groups==0:return
		if allow_hold and batch._preparation.get("phase")=="await_sources" and batch.pending.is_empty() and batch._workers.is_empty():return
		if not batch._workers.is_empty():OS.delay_usec(100)
	check(false,"bounded scheduler converges")
func add_sources(host:Node,all:Array,mesh:Mesh,count:int,ground:bool=true)->void:
	for i:int in count:
		var node:=MeshInstance3D.new();node.name="part%04d"%all.size();node.mesh=mesh
		node.position=Vector3(2+all.size()%12,1,2+all.size()/12)
		var record:={"uuid":str(node.name),"kind":"box","size":[1,1,1]}
		if ground:record.surface_id="ground"
		else:record.building={"id":"house","floor":0,"part":str(node.name),"role":"wall"}
		node.set_meta("ground_batch_record",record)
		host.add_child(node);all.append(node)
func fixture(covered:bool)->Dictionary:
	var host:=Node3D.new();root.add_child(host)
	var producer:=Producer.new();producer.name="DeferredAssets";producer.covered=covered;host.add_child(producer)
	var batch:=CountedBatch.new();host.add_child(batch);batch.set_process(false)
	return {"host":host,"producer":producer,"batch":batch,"nodes":[],"mesh":BoxMesh.new()}
func trial(covered:bool,coalesced:bool)->Dictionary:
	var f:=fixture(covered);var began:=Time.get_ticks_usec()
	for wave:int in 8:
		add_sources(f.host,f.nodes,f.mesh,12)
		f.batch.request_residency_sync(f.nodes,[],true)
		pump(f.batch,coalesced and covered)
		check(f.nodes.size()==12*(wave+1),"delayed arrivals retain every source")
		if not covered or not coalesced:check(f.batch.rebuild_count>=wave+1,"visible partial district continues publishing")
		else:check(f.batch.rebuild_count==0,"opaque initial cover avoids intermediate geometry submissions")
	# Geometry producers finish independently of render membership. Readiness
	# still includes this final batch; the gate must release without a new request.
	f.producer.idle=true;pump(f.batch,false)
	check(f.batch.groups.size()==6 and f.batch._member_groups.size()==96,"all delayed sources join final membership within the 16-source limit")
	check(f.nodes.all(func(node):return node.mesh is Cpu),"final combined draw owns all immutable source meshes")
	var reference:=Batch.new();f.host.add_child(reference);reference.set_process(false)
	reference.sync(f.nodes);reference.flush()
	var vertices:=0
	for key:String in f.batch.groups:
		var group:Dictionary=f.batch.groups[key];var expected:Dictionary=reference.groups[key]
		vertices+=group.data.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		check(var_to_bytes(group.data.mesh.surface_get_arrays(0))==var_to_bytes(expected.data.mesh.surface_get_arrays(0)),"delayed and one-shot arrivals produce identical geometry")
		check(group.signature==expected.signature,"final member identity and poses match one-shot grouping")
	check(vertices==2304,"geometry comparison contains all 96 box vertex buffers")
	var report:={"covered":covered,"coalesced":coalesced,"builds":f.batch.rebuild_count,"submitted_vertices":f.batch.submitted_vertices,"packed_sources":f.batch.packed_source_visits,"syncs":f.batch.sync_count,"elapsed_us":Time.get_ticks_usec()-began}
	reference.clear(false);f.batch.clear(false);f.host.free()
	return report
func interruption_cases()->void:
	for action:String in ["uncover","delete","flush","clear","editor"]:
		var f:=fixture(true);add_sources(f.host,f.nodes,f.mesh,12)
		f.batch.request_residency_sync(f.nodes,[],true);pump(f.batch,true)
		check(f.batch.stats().pending_groups>0 and f.batch.groups.is_empty(),"held membership remains explicitly pending: "+action)
		match action:
			"uncover":f.producer.covered=false;pump(f.batch,false)
			"delete":
				f.nodes.pop_front().free();f.batch.request_residency_sync(f.nodes,[],true)
				f.producer.idle=true;pump(f.batch,false)
			"flush":f.batch.flush()
			"clear":f.batch.clear(false);f.producer.idle=true;pump(f.batch,false)
			"editor":f.batch.sync(f.nodes);f.batch.flush()
		if action=="clear":check(f.batch.groups.is_empty() and f.batch.stats().pending_groups==0,"cleared preparation cannot reappear")
		else:check(f.batch.groups.size()==1 and f.batch._member_groups.size()==f.nodes.size(),"interrupted cover converges with exact live membership: "+action)
		f.batch.clear(false);f.host.free()
func mixed_arrivals()->void:
	var f:=fixture(true);add_sources(f.host,f.nodes,f.mesh,12)
	f.batch.request_residency_sync(f.nodes,[],true);pump(f.batch,true)
	add_sources(f.host,f.nodes,f.mesh,2,false)
	f.batch.request_residency_sync(f.nodes,[],true);pump(f.batch,true)
	check(f.batch.rebuild_count==1 and f.batch.groups.values()[0].category=="building","stable building work keeps running while growing ground waits")
	check(f.batch.stats().pending_groups>0,"held ground remains part of readiness after building publication")
	f.producer.idle=true;pump(f.batch,false)
	check(f.batch.groups.size()==2 and f.batch._member_groups.size()==14,"ground and independent building both settle")
	f.batch.clear(false);f.host.free()
	# Existing batch lifetime callbacks can revoke raw-bin reuse while waiting.
	f=fixture(false);add_sources(f.host,f.nodes,f.mesh,12)
	f.batch.request_residency_sync(f.nodes,[],true);pump(f.batch,false)
	f.producer.covered=true;add_sources(f.host,f.nodes,f.mesh,12)
	f.batch.request_residency_sync(f.nodes,[],true);pump(f.batch,true)
	f.nodes.pop_front().free();f.producer.idle=true;pump(f.batch,false)
	check(f.batch._member_groups.size()==23,"source exit during wait recovers from invalidated raw bins")
	f.batch.clear(false);f.host.free()
func run()->void:
	var coalesced:bool="--expect-coalesced" in OS.get_cmdline_user_args()
	Batch.covered_source_coalescing_enabled=coalesced
	print("COVERED_BATCH_ARRIVALS ",JSON.stringify(trial(true,coalesced)))
	print("COVERED_BATCH_ARRIVALS ",JSON.stringify(trial(false,coalesced)))
	if coalesced:interruption_cases();mixed_arrivals()
	print("COVERED_BATCH_ARRIVALS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
