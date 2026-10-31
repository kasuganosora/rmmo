extends RefCounted
## Native, per-thread memory capture. Record IDs/scalars, never Resource owners.
## Register labels/control on main. begin/end must stay on one native thread;
## for an async task crossing threads use marks with the same task ID instead.
## Export only after stop, outside the measured work. No GDScript log or mutex.

# Engine capabilities do not change during a process. Resolve once, before
# worker handoff, rather than repeating reflection and StringName lookup for
# every event. These handles remain immutable for the script's lifetime.
static var _available:bool=Performance.has_method("debug_trace_start") and Performance.has_method("debug_trace_task_name")
static var _start:Callable=Callable(Performance,"debug_trace_start") if _available else Callable()
static var _label:Callable=Callable(Performance,"debug_trace_register_label") if _available else Callable()
static var _begin:Callable=Callable(Performance,"debug_trace_begin") if _available else Callable()
static var _end:Callable=Callable(Performance,"debug_trace_end") if _available else Callable()
static var _mark:Callable=Callable(Performance,"debug_trace_mark") if _available else Callable()
static var _name:Callable=Callable(Performance,"debug_trace_task_name") if _available else Callable()
static var _stop:Callable=Callable(Performance,"debug_trace_stop") if _available else Callable()
static var _status:Callable=Callable(Performance,"debug_trace_status") if _available else Callable()
static var _export:Callable=Callable(Performance,"debug_trace_export") if _available else Callable()

static func available()->bool:
	return _available

static func start(event_capacity:int=1048576,cpu_clock:bool=false)->Error:
	if not _available:return ERR_UNAVAILABLE
	return _start.call(event_capacity,cpu_clock)

static func label(name:String)->int:
	return _label.call(name) if _available else -1

static func begin(label_id:int,task_id:int=0,context:int=0)->int:
	return _begin.call(label_id,task_id,context) if _available else 0

static func end(span:int)->void:
	if span!=0 and _available:_end.call(span)

static func mark(label_id:int,task_id:int=0,value:int=0)->void:
	if _available:_mark.call(label_id,task_id,value)

# Optional metadata; use once at enqueue/entry, not once per vertex or loop.
# First use of each distinct name allocates in that native thread's own table.
static func task_name(task_id:int,context:int,name_:String)->void:
	if _available:_name.call(task_id,context,name_)

static func stop()->Dictionary:
	return _stop.call() if _available else {"error":ERR_UNAVAILABLE}

static func status()->Dictionary:
	return _status.call() if _available else {"error":ERR_UNAVAILABLE}

static func export_capture(path:String)->Error:
	if not _available:return ERR_UNAVAILABLE
	return _export.call(path)
