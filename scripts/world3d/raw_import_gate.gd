extends RefCounted
## Shared private imports may overlap; unknown imports retain exclusive access.
## FIFO groups prevent an exclusive waiter from starving behind new readers.
var mutex:=Mutex.new()
var active:=0
var exclusive:=false
var waiting:Array=[]
class Waiter extends RefCounted:
	var shared:=false
	var ready:=Semaphore.new()
func try_acquire(shared:bool)->bool:
	# Main-thread callers must yield while a worker can need a render callback.
	if not mutex.try_lock():return false
	var admitted:=waiting.is_empty() and not exclusive and (active==0 or shared)
	if admitted:active+=1;exclusive=not shared
	mutex.unlock()
	return admitted
func acquire(shared:bool)->void:
	mutex.lock()
	if waiting.is_empty() and not exclusive and (active==0 or shared):
		active+=1;exclusive=not shared;mutex.unlock();return
	var waiter:=Waiter.new();waiter.shared=shared;waiting.append(waiter);mutex.unlock()
	waiter.ready.wait()
func release()->void:
	mutex.lock();active-=1
	if active==0:
		exclusive=false
		while not waiting.is_empty():
			var waiter:Waiter=waiting[0]
			if active>0 and not waiter.shared:break
			waiting.pop_front();active+=1;exclusive=not waiter.shared;waiter.ready.post()
			if exclusive:break
	mutex.unlock()
