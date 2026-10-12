extends RefCounted
## Run on the loader's coordinator worker, not the scene thread. Each hash uses
## FileAccess.get_sha256's independent streaming file handle; source bytes are
## never retained in an Array/PackedByteArray or trusted by timestamp/size alone.
## cancel() is thread-safe and sticky. A running file hash is indivisible, so
## cancellation stops new work and joins already-started workers before return.
const Paths=preload("res://scripts/world3d/map_paths.gd")
var _mutex:=Mutex.new()
var _cancelled:=false
var _running:=false
var _active:=0
var _peak_active:=0
var _hash_calls:=0

func cancel()->void:
	_mutex.lock();_cancelled=true;_mutex.unlock()

func is_cancelled()->bool:
	_mutex.lock();var value:=_cancelled;_mutex.unlock();return value

func run(paths:Array,content_root:String,worker_limit:int=4,thread_starter:Callable=Callable(),hash_reader:Callable=Callable())->Dictionary:
	_mutex.lock()
	if _running:
		_mutex.unlock()
		return {"error":ERR_BUSY,"error_path":"","reason":"Source hashing is already running","cancelled":false,"entries":[],"signatures":{}}
	_running=true;_active=0;_peak_active=0;_hash_calls=0
	_mutex.unlock()
	var started:=Time.get_ticks_usec()
	var result:Dictionary={"error":OK,"error_path":"","reason":"","entries":[],"signatures":{},"unique_count":0,"worker_limit":clampi(worker_limit,1,4),"threads_started":0,"threads_joined":0,"fallback_count":0,"preflight_us":0,"hash_us":0}
	if content_root.is_empty() or not content_root.is_absolute_path() or content_root.contains("://"):
		result.error=ERR_INVALID_PARAMETER;result.reason="An explicit absolute content root is required"
		return _finish(result,started)
	var unique:Array[String]=[];var seen:Dictionary={}
	# Validate the entire input before hashing any source, including malformed or
	# missing tail entries. Preserve exact authored path keys and first-use order.
	for value:Variant in paths:
		if is_cancelled():return _finish(result,started)
		if not value is String or value.is_empty():
			result.error=ERR_INVALID_PARAMETER;result.reason="Invalid model source path"
			return _finish(result,started)
		var path:String=value
		if not Paths.allowed(path,content_root):
			result.error=ERR_INVALID_PARAMETER;result.error_path=path;result.reason="Model source is outside the content root or traverses a link"
			return _finish(result,started)
		if not FileAccess.file_exists(path):
			result.error=ERR_FILE_NOT_FOUND;result.error_path=path;result.reason="Model source is missing"
			return _finish(result,started)
		if not seen.has(path):seen[path]=true;unique.append(path)
	result.preflight_us=Time.get_ticks_usec()-started;result.unique_count=unique.size()
	var pending:Array=[];var completed:Dictionary={};var next:=0;var saw_error:=false
	while next<unique.size() or not pending.is_empty():
		var draining:bool=saw_error or is_cancelled()
		var at:=0
		while at<pending.size():
			var item:Dictionary=pending[at]
			if item.has("thread") and item.thread.is_alive() and not draining:at+=1;continue
			var reply:Dictionary=item.thread.wait_to_finish() if item.has("thread") else item.result
			if item.has("thread"):result.threads_joined+=1
			pending.remove_at(at);completed[item.index]=reply
			if reply.error!=OK:saw_error=true;draining=true
		if saw_error or is_cancelled():
			if pending.is_empty():break
			continue
		while next<unique.size() and pending.size()<int(result.worker_limit):
			if is_cancelled():break
			var worker:=Thread.new();var task:=_hash_one.bind(unique[next],content_root,hash_reader)
			var launch:int=thread_starter.call(worker,task) if thread_starter.is_valid() else worker.start(task)
			var item:Dictionary={"index":next};next+=1
			if launch==OK:
				result.threads_started+=1;item.thread=worker;pending.append(item)
			else:
				# A failed launch has no live thread to join. Run this exact task on
				# the coordinator, still within the same total active-worker bound.
				result.fallback_count+=1;item.result=task.call();pending.append(item)
				break # Observe a synchronous error before starting another source.
		if not pending.is_empty():OS.delay_usec(500)
	for index in unique.size():
		if not completed.has(index):continue
		var entry:Dictionary=completed[index]
		result.entries.append(entry);result.hash_us+=int(entry.elapsed_us)
		# Report actual failures deterministically by input order, not the order
		# workers completed. Cancellation is recorded separately by _finish.
		if result.error==OK and entry.error not in [OK,ERR_SKIP]:
			result.error=entry.error;result.error_path=entry.path;result.reason=entry.reason
		if entry.error==OK:result.signatures[entry.path]=entry.digest
	return _finish(result,started)

func _hash_one(path:String,content_root:String,reader:Callable)->Dictionary:
	var started:=Time.get_ticks_usec()
	var result:Dictionary={"path":path,"error":OK,"reason":"","digest":"","elapsed_us":0}
	if is_cancelled():result.error=ERR_SKIP;return result
	# Recheck on the worker: a queued source or ancestor could have changed
	# since full-input preflight. Never follow a replacement symlink outside root.
	if not Paths.allowed(path,content_root):
		result.error=ERR_INVALID_PARAMETER;result.reason="Model source path changed before hashing";return result
	if not FileAccess.file_exists(path):
		result.error=ERR_FILE_NOT_FOUND;result.reason="Model source disappeared before hashing";return result
	_mutex.lock()
	if _cancelled:_mutex.unlock();result.error=ERR_SKIP;return result
	_active+=1;_peak_active=maxi(_peak_active,_active);_hash_calls+=1;_mutex.unlock()
	var digest:Variant=reader.call(path) if reader.is_valid() else FileAccess.get_sha256(path)
	_mutex.lock();_active-=1;_mutex.unlock()
	result.elapsed_us=Time.get_ticks_usec()-started
	preload("res://scripts/world3d/load_trace.gd").elapsed("model.source_hash",started,{"path":path})
	if is_cancelled():result.error=ERR_SKIP;return result
	if not Paths.allowed(path,content_root):
		result.error=ERR_INVALID_PARAMETER;result.reason="Model source path changed during hashing";return result
	if not FileAccess.file_exists(path):
		result.error=ERR_FILE_NOT_FOUND;result.reason="Model source disappeared during hashing";return result
	if not digest is String or digest.length()!=64 or not digest.is_valid_hex_number(false):
		result.error=ERR_FILE_CANT_READ;result.reason="Could not read the complete model SHA-256";return result
	result.digest=digest.to_lower()
	return result

func _finish(result:Dictionary,started:int)->Dictionary:
	result.elapsed_us=Time.get_ticks_usec()-started
	_mutex.lock()
	result.cancelled=_cancelled;result.peak_active=_peak_active;result.hash_calls=_hash_calls;result.active_at_return=_active
	if _cancelled and result.error==OK:result.error=ERR_SKIP;result.reason="Source hashing was cancelled"
	_running=false
	_mutex.unlock()
	# A partial set is useful for diagnostics only. Callers may consume the
	# authoritative identity dictionary only after every required source succeeds.
	if result.error!=OK:result.signatures.clear()
	return result
