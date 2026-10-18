extends RefCounted
## A private worker can make synchronous renderer queries during node creation,
## mip preparation and packing. A loading screen drawing at 60 Hz otherwise
## services each dependency only once per frame. Never join that live worker.
const Trace=preload("res://scripts/world3d/load_trace.gd")
static var _mutex:=Mutex.new()
static var _active:=0
static var loading_budget_usec:=8000
func _init()->void:
	_mutex.lock();_active+=1;_mutex.unlock()
func _notification(what:int)->void:
	if what==NOTIFICATION_PREDELETE:
		_mutex.lock();_active-=1;_mutex.unlock()
static func active()->bool:
	_mutex.lock();var result:bool=_active>0;_mutex.unlock();return result
static func pump(budget_usec:int)->void:
	if DisplayServer.get_name()=="headless" or OS.get_thread_caller_id()!=OS.get_main_thread_id() or not active():return
	var began:=Time.get_ticks_usec();var calls:=0
	while Time.get_ticks_usec()-began<budget_usec and active():
		RenderingServer.force_sync();calls+=1
		# Let the producer issue its next query instead of spinning on the same
		# empty queue. The deadline covers this handoff as well as renderer work.
		OS.delay_usec(25)
	Trace.elapsed("model.render_pump",began,{"calls":calls,"budget_usec":budget_usec})
