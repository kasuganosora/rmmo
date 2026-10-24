extends SceneTree
const Gate=preload("res://scripts/world3d/raw_import_gate.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
class Work extends RefCounted:
	var entered:=Semaphore.new()
	var finish:=Semaphore.new()
	var started:=false
	var mutex:=Mutex.new()
	func run(gate:RefCounted,shared:bool)->void:
		gate.acquire(shared);mutex.lock();started=true;mutex.unlock();entered.post();finish.wait();gate.release()
	func is_started()->bool:
		mutex.lock();var value:=started;mutex.unlock();return value
func queued(gate:RefCounted,count:int)->bool:
	var deadline:=Time.get_ticks_msec()+3000
	while Time.get_ticks_msec()<deadline:
		gate.mutex.lock();var size:int=gate.waiting.size();gate.mutex.unlock()
		if size==count:return true
		OS.delay_msec(1)
	return false
func _initialize()->void:
	var gate:=Gate.new();var jobs:Array=[];var workers:Array[Thread]=[]
	for i:int in 4:jobs.append(Work.new());workers.append(Thread.new())
	workers[0].start(jobs[0].run.bind(gate,true));jobs[0].entered.wait()
	workers[1].start(jobs[1].run.bind(gate,true));jobs[1].entered.wait()
	check(gate.active==2,"two independent imports overlap")
	check(not gate.try_acquire(false),"nonblocking exclusive admission cannot overlap active shared imports")
	var shared:=gate.try_acquire(true)
	check(shared and gate.active==3,"nonblocking private import can join active shared imports")
	if shared:gate.release()
	workers[2].start(jobs[2].run.bind(gate,false));check(queued(gate,1),"unknown import waits for all active private imports")
	workers[3].start(jobs[3].run.bind(gate,true));check(queued(gate,2),"later private import cannot bypass waiting exclusive import")
	check(not gate.try_acquire(true) and not gate.try_acquire(false),"polling callers cannot bypass queued imports")
	jobs[0].finish.post();workers[0].wait_to_finish()
	check(not jobs[2].is_started() and not jobs[3].is_started(),"one remaining reader still protects the exclusive boundary")
	jobs[1].finish.post();workers[1].wait_to_finish();jobs[2].entered.wait()
	check(gate.active==1 and gate.exclusive and not jobs[3].is_started(),"unknown import runs alone after every reader joins")
	check(not gate.try_acquire(true) and not gate.try_acquire(false),"polling callers respect an active exclusive import")
	jobs[2].finish.post();workers[2].wait_to_finish();jobs[3].entered.wait()
	check(gate.active==1 and not gate.exclusive,"queued private import resumes after exclusive completion")
	jobs[3].finish.post();workers[3].wait_to_finish()
	check(gate.active==0 and gate.waiting.is_empty() and not gate.exclusive,"all waiters and active admissions drain")
	var alone:=gate.try_acquire(false)
	check(alone and gate.active==1 and gate.exclusive,"nonblocking exclusive admission owns the same gate")
	if alone:gate.release()
	print("RAW_IMPORT_GATE failures=",failures);quit(1 if failures else 0)
