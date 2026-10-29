extends RefCounted
## Keyed main-thread lookup only. No loader, pool, renderer worker or global
## directory snapshot. A Run keeps reply owners until its main-thread release.
const Sharing=preload("res://scripts/world3d/native_texture_sharing.gd")
var lookup_override:Callable # CPU fixture only; configure before starting runs.
var _mutex:=Mutex.new()
var _runs:Dictionary={}
var _closed:=false

class Run extends RefCounted:
	var _mutex:=Mutex.new()
	var _closed:=false
	var _requests:Dictionary={}
	var _pending:Dictionary={}
	var _positive:Dictionary={} # Only keys actually requested by this run.
	var _positive_users:Dictionary={}
	var metadata_bytes:=0
	var lookups:=0
	var hits:=0
	var main_us:=0
	var max_pump_us:=0
	var released:=false
	func request(id:String,rows:Dictionary)->int:
		var keys:=rows.keys()
		var bytes:=512
		for key:String in keys:
			bytes+=1024+key.length()*4+str(rows[key].get("representation","")).length()*2
		_mutex.lock()
		if _closed or _requests.has(id):
			_mutex.unlock()
			return 0
		_requests[id]={"rows":rows,"keys":keys,"at":0,"ready":false,"retiring":false,"bytes":bytes,"tickets":{}}
		_pending[id]=true
		metadata_bytes+=bytes
		_mutex.unlock()
		return bytes
	func poll(id:String)->Dictionary:
		_mutex.lock()
		var result:Dictionary
		if _closed:
			result={"cancelled":true}
		elif not _requests.has(id):
			result={"retired":true}
		elif not _requests[id].ready:
			result={"pending":true}
		else:
			result={"tickets":_requests[id].tickets}
		_mutex.unlock()
		return result
	func retire(id:String)->void:
		_mutex.lock()
		if not _closed and _requests.has(id):
			_requests[id].retiring=true
			_pending[id]=true
		_mutex.unlock()
	func close()->void:
		# CPU-only: exit_tree can stop the coordinator without another main pump.
		_mutex.lock()
		if _closed:
			_mutex.unlock()
			return
		_closed=true
		_pending.clear()
		for request_:Dictionary in _requests.values():
			request_.rows={}
			request_["keys"]=[]
		_mutex.unlock()
	func pump_one(lookup:Callable)->bool:
		assert(Thread.is_main_thread())
		_mutex.lock()
		if _closed or _pending.is_empty():
			_mutex.unlock()
			return false
		var id:String
		for candidate:String in _pending:
			id=candidate
			break
		var request_:Dictionary=_requests[id]
		if request_.retiring:
			var owner:Dictionary={}
			var retiring_key:=""
			for key:String in request_.tickets:
				retiring_key=key
				break
			if not retiring_key.is_empty():
				owner=request_.tickets[retiring_key]
				request_.tickets.erase(retiring_key)
				_positive_users[retiring_key]-=1
				if _positive_users[retiring_key]==0:
					_positive.erase(retiring_key)
					_positive_users.erase(retiring_key)
			_pending.erase(id)
			if request_.tickets.is_empty():
				metadata_bytes-=int(request_.bytes)
				_requests.erase(id)
			else:
				_pending[id]=true
			_mutex.unlock()
			owner={}
			return true
		var key:String=request_["keys"][request_.at]
		var row:Dictionary=request_.rows[key]
		_mutex.unlock()
		# No cache/resource/renderer call under the mailbox mutex.
		var ticket:Dictionary=_positive.get(key,{})
		var observed:=ticket.is_empty()
		if observed:
			ticket=lookup.call(key,row)
		_mutex.lock()
		lookups+=int(observed)
		if not ticket.is_empty() and not ticket.get("pending",false):
			request_.tickets[key]=ticket
			hits+=1
			_positive[key]=ticket
			_positive_users[key]=int(_positive_users.get(key,0))+1
		if not _closed:
			_pending.erase(id)
			if not ticket.get("pending",false):
				request_.at+=1
			if request_.at==request_["keys"].size():
				request_.ready=true
				request_.rows={}
				request_["keys"]=[]
			else:
				_pending[id]=true # Round robin: one large/held table cannot fence another.
		_mutex.unlock()
		return true
	func snapshot()->Dictionary:
		_mutex.lock()
		var value:={"metadata_bytes":metadata_bytes,"lookups":lookups,"hits":hits,"pending":_pending.size(),"requests":_requests.size(),"closed":_closed,"released":released,"main_us":main_us,"max_pump_us":max_pump_us}
		_mutex.unlock()
		return value
	func release_now()->void:
		assert(Thread.is_main_thread())
		if released:
			return
		close()
		_mutex.lock()
		var owners:=_requests
		_requests={}
		metadata_bytes=0
		released=true
		_mutex.unlock()
		owners.clear()
		_positive.clear()
		_positive_users.clear() # Every worker/result alias must already have retired.

func open_run()->Run:
	var run:=Run.new()
	_mutex.lock()
	_runs[run.get_instance_id()]=run
	if _closed:
		run.close()
	_mutex.unlock()
	return run

func pump(budget_usec:int=1000)->void:
	assert(Thread.is_main_thread())
	var began:=Time.get_ticks_usec()
	_mutex.lock()
	var runs:=_runs.values()
	_mutex.unlock()
	var lookup:Callable=lookup_override if lookup_override.is_valid() else Sharing.ticket
	while true:
		var progressed:=false
		for run:Run in runs:
			var started:=Time.get_ticks_usec()
			var worked:=run.pump_one(lookup)
			run._mutex.lock()
			run.main_us+=Time.get_ticks_usec()-started
			run.max_pump_us=maxi(run.max_pump_us,Time.get_ticks_usec()-began)
			run._mutex.unlock()
			progressed=worked or progressed
			if Time.get_ticks_usec()-began>=budget_usec:
				return
		if not progressed:
			return

func release_run(run:Run)->void:
	assert(Thread.is_main_thread())
	run.release_now()
	_mutex.lock()
	_runs.erase(run.get_instance_id())
	_mutex.unlock()

func close()->void:
	_mutex.lock()
	_closed=true
	var runs:=_runs.values()
	_mutex.unlock()
	for run:Run in runs:
		run.close()

func release_now()->void:
	assert(Thread.is_main_thread())
	close()
	_mutex.lock()
	var runs:=_runs.values()
	_runs.clear()
	_mutex.unlock()
	for run:Run in runs:
		run.release_now()
