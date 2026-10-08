extends RefCounted
## Opt-in, bounded diagnostic events. No file I/O on loading workers.
## Wall spans can overlap/nest; they must not be added as exclusive CPU time.
static var enabled:=false
static var _mutex:=Mutex.new()
static var _events:Array=[]
static var _stats:Dictionary={}
static var _dropped:=0
const MAX_EVENTS=40000

static func start()->void:
	_mutex.lock()
	_events=[];_stats={};_dropped=0;enabled=true
	_mutex.unlock()

static func begin(_label:String)->int:
	# Godot thread IDs are internal IDs, not Win32 TIDs.
	return Time.get_ticks_usec()

static func elapsed(label:String,started:int,details:Dictionary={})->void:
	if not enabled:return
	var ended:=Time.get_ticks_usec()
	var duration:=maxi(0,ended-started)
	var tid:=OS.get_thread_caller_id()
	var key:=label+"|"+str(tid)
	_mutex.lock()
	if enabled:
		var stat:Dictionary=_stats.get(key,{"label":label,"thread_id":tid,"count":0,"total_us":0,"max_us":0})
		stat.count+=1;stat.total_us+=duration;stat.max_us=maxi(stat.max_us,duration);_stats[key]=stat
		if duration>=500:
			if _events.size()<MAX_EVENTS:
				_events.append({"label":label,"thread_id":tid,"start_us":started,"end_us":ended,"duration_us":duration,"details":details})
			else:_dropped+=1
	_mutex.unlock()

static func stop()->Dictionary:
	_mutex.lock()
	enabled=false
	var result:={"events":_events,"stats":_stats.values(),"dropped":_dropped,"minimum_event_us":500}
	_events=[];_stats={}
	_mutex.unlock()
	return result
