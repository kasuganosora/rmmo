extends RefCounted
## Opt-in lifecycle evidence. The scheduler is the only writer; workers return
## their clock marks in their private result instead of touching this journal.
static var enabled:=false
static var events:Array=[]
static var dropped:=0
const LIMIT:=50000

static func record(path:String,generation:int,event:String,details:Dictionary={},at_us:int=-1)->void:
	if not enabled:return
	if events.size()>=LIMIT:dropped+=1;return
	events.append({"at_us":Time.get_ticks_usec() if at_us<0 else at_us,"path":path,"generation":generation,"event":event,"details":details})

static func start()->void:
	events=[];dropped=0;enabled=true

static func work(prepare:Callable)->Dictionary:
	# One clock pair for every actual worker invocation, including continuations.
	# Transport marks stay private until main joins; no worker journal or I/O.
	var began:=Time.get_ticks_usec()
	var result:Dictionary=prepare.call()
	result.audit_worker_start_us=began;result.audit_worker_end_us=Time.get_ticks_usec()
	return result

static func joined(path:String,generation:int,result:Dictionary)->void:
	if result.has("audit_worker_end_us"):
		record(path,generation,"worker_finished",{"started_us":result.audit_worker_start_us},int(result.audit_worker_end_us))
		# These are diagnostic transport fields, not part of the production
		# result schema (which intentionally rejects unexpected retry payloads).
		result.erase("audit_worker_start_us");result.erase("audit_worker_end_us")
	record(path,generation,"joined")

static func release(admission:RefCounted,path:String,generation:int)->void:
	# A static callback survives destruction of the map/queue, unlike a bound
	# Node method. Retain the original ledger until its real retirement callback.
	var bytes:int=int(admission._entries.get(path,{}).get("bytes",0))
	admission.release(path)
	record(path,generation,"lease_released",{"bytes":bytes})

static func snapshot(origin_us:int)->Dictionary:
	return {"events":events,"timebase":"absolute_godot_ticks_us","origin_us":origin_us,"dropped":dropped}
