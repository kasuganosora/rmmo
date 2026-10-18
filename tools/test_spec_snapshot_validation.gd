extends "res://tools/test_stream_index_retire.gd"
const Validation=preload("res://scripts/world3d/spec_snapshot_validation.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
func packet()->Dictionary:
	var values:Array=[];var snapshots:Array=[];var by_id:Dictionary={};var mesh:=BoxMesh.new()
	for i:int in 4600:
		var row:={"uuid":"part%d"%i,"mesh":mesh,"nested":{"id":"unit"}}
		values.append(row);snapshots.append(row.duplicate(true));by_id[row.uuid]=row
	return {"values":values,"snapshots":snapshots,"owners":values.duplicate(),"by_id":by_id,"watch":weakref(mesh)}
func agree(p:Dictionary,label:String)->bool:
	Validation.workers=0;var serial:=Validation.matches(p.values,p.snapshots,p.owners,p.by_id)
	Validation.workers=4;var parallel:=Validation.matches(p.values,p.snapshots,p.owners,p.by_id)
	check(serial==parallel,"same complete native/identity decision: "+label)
	return parallel
func released()->WeakRef:
	var p:=packet();p.values[0].nested.id=17
	check(not agree(p,"first partition failure"),"failed equality rejects while all other readers are still joined")
	return p.watch
func run()->void:
	var p:=packet();check(agree(p,"fresh"),"matching sources authorize the same complete snapshot")
	Trace.methods_enabled=true;Trace.method_labels={"method.spec_snapshot_validation.slice":true};Trace.start()
	check(Validation.matches(p.values,p.snapshots,p.owners,p.by_id),"traced verification succeeds")
	var trace:=Trace.stop();Trace.methods_enabled=false;Trace.method_labels.clear()
	var threads:Dictionary={}
	for row:Dictionary in trace.stats:threads[row.thread_id]=true
	check(threads.size()==mini(4,OS.get_processor_count()) and (threads.size()==1 or not threads.has(OS.get_main_thread_id())),"bounded pure native equality readers run on actual worker threads")
	p.values[-1].nested.id=StringName("unit");check(not agree(p,"nested exact type"),"StringName cannot pass the captured String schema")
	p.values[-1].nested.id="unit"
	var first:Dictionary=p.values[0];p.values[0]=first.duplicate();check(not agree(p,"source alias"),"equal-value source replacement is refused");p.values[0]=first
	p.by_id[first.uuid]=first.duplicate();check(not agree(p,"index alias"),"equal-value index replacement is refused")
	p.by_id[first.uuid]=first;p.values.reverse();check(not agree(p,"order"),"source order remains part of the transaction proof")
	check(released().get_ref()==null,"failed/joined snapshot readers retain no resources after return")
	print("SPEC_SNAPSHOT_VALIDATION checks=",checks," failures=",failures);quit(1 if failures else 0)
