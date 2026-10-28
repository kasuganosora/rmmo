extends SceneTree
const Queue=preload("res://scripts/world_editor/load_preparation_queue.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
var passed:=0
var failed:=0

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS ",label)
	else:failed+=1;push_error("FAIL "+label)
static func held(gate:Semaphore)->Dictionary:
	gate.wait()
	return {"error":OK}
func make_queue(ledger:RefCounted)->Node:
	var q:=Queue.new();q.ledger=ledger;q.shared_ledger_enabled=true;q.ready_limit=1
	root.add_child(q)
	return q
func run()->void:
	var ledger:=Admission.new();ledger.worker_limit=2;ledger.byte_limit=100
	var loading:=make_queue(ledger);var importing:=make_queue(ledger)
	var load_gate:=Semaphore.new();var import_gate:=Semaphore.new()
	loading.enqueue("model:a",held.bind(load_gate),{"estimated_bytes":60,"exclusive":false,"cpu_only":true})
	importing.enqueue("import:b",held.bind(import_gate),{"estimated_bytes":50,"exclusive":false,"cpu_only":true})
	loading.pump();importing.pump()
	check(loading.rows["model:a"].state=="running" and importing.rows["import:b"].state=="pending","combined byte budget prevents overcommit")
	check(ledger.reserved_bytes==60 and ledger.worker_limit==2 and ledger.byte_limit==100,"both queues retain one configured ledger")
	loading.cancel()
	check(ledger.reserved_bytes==60 and not importing.cancelled,"cancelling load leaves import active and its live worker lease charged")
	importing.pump();check(importing.rows["import:b"].state=="pending","abandoned worker remains charged before exit")
	load_gate.post()
	var deadline:=Time.get_ticks_msec()+5000
	while ledger.reserved_bytes==60 and Time.get_ticks_msec()<deadline:await process_frame
	importing.pump()
	check(importing.rows["import:b"].state=="running" and ledger.reserved_bytes==50,"only the exited load frees admission for import")
	import_gate.post()
	while not importing.is_ready("import:b") and Time.get_ticks_msec()<deadline:await process_frame
	check(importing.is_ready("import:b") and ledger.reserved_bytes==50,"joined import retains its own lease")
	importing.release("import:b")
	check(ledger.count()==0 and ledger.reserved_bytes==0,"all leases return after consumption")
	loading.queue_free();importing.queue_free()
	# Successive operations can request the same logical model while the prior
	# cancelled worker is still exiting. Their ledger ownership must not alias.
	var first:=make_queue(ledger);var second:=make_queue(ledger)
	var first_gate:=Semaphore.new();var second_gate:=Semaphore.new()
	first.enqueue("model:same",held.bind(first_gate),{"estimated_bytes":40,"exclusive":false,"cpu_only":true})
	second.enqueue("model:same",held.bind(second_gate),{"estimated_bytes":40,"exclusive":false,"cpu_only":true})
	first.pump();second.pump()
	check(first.rows["model:same"].state=="running" and second.rows["model:same"].state=="running" and ledger.reserved_bytes==80,"same logical key in independent operations owns two distinct leases")
	first.cancel();first_gate.post()
	deadline=Time.get_ticks_msec()+5000
	while ledger.reserved_bytes==80 and Time.get_ticks_msec()<deadline:await process_frame
	check(ledger.reserved_bytes==40 and second.rows["model:same"].state=="running","old operation retirement does not release the newer lease")
	second_gate.post()
	while not second.is_ready("model:same") and Time.get_ticks_msec()<deadline:await process_frame
	check(second.is_ready("model:same") and ledger.reserved_bytes==40,"new operation continues with its own retained result")
	second.release("model:same");check(ledger.count()==0,"both same-key generations eventually release")
	first.queue_free();second.queue_free()
	print("SHARED_BUDGET pass=%d fail=%d"%[passed,failed]);quit(1 if failed else 0)
