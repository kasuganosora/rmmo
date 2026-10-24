extends SceneTree
## Run in the empty external profiler project. Two callers intentionally use
## the same native method; four workers share code but own different objects.
const WORKERS:=4
var workers:Array[Thread]=[]
func _initialize()->void:run.call_deferred()
static func query_a(value:RefCounted)->bool:return value.has_meta("fixture")
static func query_b(value:RefCounted)->bool:return value.has_meta("fixture")
static func work()->int:
	var value:=RefCounted.new();value.set_meta("fixture",true)
	var hits:=0
	for i:int in 1000:hits+=int(query_a(value))
	for i:int in 2000:hits+=int(query_b(value))
	return hits
func run()->void:
	Engine.max_fps=240
	print("PROFILE_CALLERS_BEGIN")
	await create_timer(2.).timeout
	for i:int in WORKERS:
		var thread:=Thread.new();workers.append(thread)
		if thread.start(work)!=OK:quit(1);return
	while workers.any(func(thread:Thread):return thread.is_alive()):await process_frame
	var count:=0
	for thread:Thread in workers:count+=thread.wait_to_finish()
	workers.clear()
	await create_timer(.5).timeout
	print("PROFILE_CALLERS_COMPLETE hits=",count)
	quit(0 if count==12000 else 1)
