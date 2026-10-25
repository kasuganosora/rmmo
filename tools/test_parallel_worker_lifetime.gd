extends SceneTree
const Pair=preload("res://scripts/world3d/parallel_chunk_worker.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
class FailingPair extends Pair:
	var fail_pixels:=false
	func _start_thread(worker:Thread,task:Callable)->int:
		if (worker==_pixels)==fail_pixels:return ERR_CANT_CREATE
		return super(worker,task)
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
static func geometry()->Dictionary:return {"error":"","records":[],"read_profile":{}}
static func pixels()->Dictionary:return {"error":"","images":{},"sources":{},"profile":{}}
func run()->void:
	var ledger:=Admission.new();ledger.byte_limit=100;ledger.worker_limit=2
	check(ledger.reserve_bundle("pair",{"estimated_bytes":60,"exclusive":false},{"image":40}) and ledger.add_worker_slot("pair"),"two CPU slots share one original 100-byte bundle")
	check(ledger.reserved_bytes==100 and ledger.active_workers()==2 and not ledger.add_worker_slot("pair"),"split cannot exceed the cap or add bytes")
	ledger.finish_worker_slot("pair")
	check(ledger.active_workers()==1 and not ledger.shrink_joined("pair",1),"live sibling prevents early workspace shrinking")
	ledger.finish_worker_slot("pair")
	check(ledger.active_workers()==0 and ledger.resume_worker("pair") and ledger.active_workers()==1,"parked split packet resumes with exactly one continuation slot")
	ledger.park("pair");ledger.release("pair");ledger.release("image")
	for fail_pixels:bool in [false,true]:
		ledger.reserve("failure",{"estimated_bytes":100,"exclusive":false});ledger.add_worker_slot("failure")
		var worker:=FailingPair.new();worker.admission=ledger;worker.path="failure";worker.pixels=pixels;worker.fail_pixels=fail_pixels
		var status:=worker.start(geometry)
		if fail_pixels:
			check(status==OK,"second start failure retains the live first worker for normal joining")
			while worker.is_alive():await process_frame
			var result:=worker.wait_to_finish()
			check(not result.error.is_empty() and ledger.active_workers()==0 and ledger.reserved_bytes==100,"failed second start cannot orphan the first worker or prematurely release bytes")
		else:check(status==ERR_CANT_CREATE and not worker.is_started() and ledger.active_workers()==1,"failed first start rolls back only the reserved extra execution slot")
		ledger.release("failure")
	check(ledger.reserved_bytes==0 and ledger.count()==0,"all startup failure paths fully release their lease")
	print("PARALLEL_WORKER_LIFETIME failures=",failures);quit(1 if failures else 0)
