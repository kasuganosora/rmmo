extends SceneTree
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var checks:=0
var failures:Array[String]=[]
class Probe extends RefCounted:
	var log:Array
	var id:int
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:log.append(id)
class Controlled extends "res://scripts/world3d/resource_retirement.gd":
	var attempts:Array=[]
	var budgets:Array=[]
	func _advance_ticket(ticket:Dictionary,budget_usec:int)->bool:
		attempts.append(ticket.source_id);budgets.append(budget_usec)
		if ticket.get("test_hold",false):return ticket.ready
		if ticket.get("test_overrun",false):OS.delay_msec(3);return true
		return super._advance_ticket(ticket,budget_usec)
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func values(log:Array,id:int)->Array:
	var value:=Probe.new();value.log=log;value.id=id;return [value]
func add_test(service:Node,ticket:Dictionary)->void:
	service.pending.append(ticket);service.known[ticket.source_id]=true
func drain(service:Node)->void:
	for i in 100:
		if service.pending.is_empty():return
		service._process(0.);service.set_process(false);await process_frame
	check(false,"test queue eventually drains")
func run()->void:
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	var service:=Controlled.new();service.name=Retirement.NODE_NAME;root.add_child(service);service.set_process(false)
	var log:Array=[]
	for i in 8:service._enqueue_private_array(values(log,i))
	service.set_process(false);service._process(0.)
	check(log.size()>1,"one eligible callback continues past a completed cheap ticket")
	check(log==range(log.size()),"MAIN destructors preserve FIFO while making progress")
	check(service.budgets[0]<=1000 and service.budgets.all(func(b):return b>0 and b<=1000),"all attempts consume the same 1ms allowance")
	await drain(service)
	check(log==range(8) and service.known.is_empty(),"every donated owner dies exactly once")
	log.clear();service.attempts.clear();service.budgets.clear()
	var first:Dictionary=service._enqueue_private_array(values(log,11))
	first.on_done=func():service._enqueue_private_array(values(log,33))
	service._enqueue_private_array(values(log,22));service.set_process(false);service._process(0.)
	check(log==[11,22,33],"completion callback appends behind existing ownership fences in the same allowance")
	await drain(service)
	log.clear();service.attempts.clear()
	var waiting:={"kind":"test_wait","source_id":"hold","test_hold":true,"ready":false}
	add_test(service,waiting);service._enqueue_private_array(values(log,44));service.set_process(false)
	service._process(0.)
	check(service.attempts==["hold"] and log.is_empty(),"an unfinished dependent ticket stops the callback without spinning or skipping its fence")
	waiting.ready=true;await drain(service)
	check(log==[44],"dependent owners progress after their blocker completes")
	log.clear();service.attempts.clear()
	add_test(service,{"kind":"test_overrun","source_id":"slow","test_overrun":true})
	service._enqueue_private_array(values(log,55));service.set_process(false);service._process(0.)
	check(service.attempts==["slow"] and log.is_empty(),"an indivisible 3ms overrun cannot admit another ticket")
	await drain(service)
	check(log==[55],"the deferred owner resumes in a later callback")
	log.clear();service.attempts.clear()
	var pixel:={"kind":"pixel_buffers","source_id":"pixel","test_hold":true,"ready":false,"slot_blocked":true,"completions":[],"admission":null}
	add_test(service,pixel);service._enqueue_private_array(values(log,66));service.set_process(false);service._process(0.)
	check(service.attempts==["pixel"] and service.pending[0].source_id!="pixel","an independent slot-blocked pixel ticket rotates only once")
	service.attempts.clear();service._process(0.)
	check(log==[66] and service.attempts.count("pixel")<=1,"rotation permits later slot release without a busy loop")
	pixel.ready=true;await drain(service)
	check(service.pending.is_empty() and service.known.is_empty(),"completion bookkeeping drains after all paths")
	service.free()
	var result:={"checks":checks,"failures":failures,"scope":"queue progress and ownership; not a map performance score"}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("RETIREMENT_QUEUE_PROGRESS ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
