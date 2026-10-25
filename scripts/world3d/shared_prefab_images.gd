extends RefCounted
## Operation-local CPU Images. The scheduler alone creates/releases leases and
## writes the admission ledger. Workers publish/fetch immutable pixels under a
## mutex. All keys for a job are claimed atomically before its thread starts;
## missing dependencies return to the scheduler; no worker blocks on a sibling.
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Preparation=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const HASH_SCRATCH=8*1024*1024
var admission:RefCounted
var _mutex:=Mutex.new()
var _entries:Dictionary={}
var _consumers:Dictionary={}
var _cancelled:Dictionary={}
var _source_identities:Dictionary={} # Mounted operation only; String SHA values, no pixel/resource owners.
var profile:Dictionary={"produced":0,"shared_hits":0,"waits":0,"peak_outputs":0,"retained_bytes":0,"peak_retained_bytes":0}

func consumer_active(consumer:String)->bool:
	_mutex.lock();var active:bool=_consumers.has(consumer) and not _cancelled.has(consumer);_mutex.unlock();return active

func source_identity(consumer:String,path:String)->String:
	_mutex.lock()
	var digest:String=_source_identities.get(path,"") if _consumers.has(consumer) and not _cancelled.has(consumer) else ""
	_mutex.unlock();return digest

func remember_source_identity(consumer:String,path:String,digest:String)->bool:
	if path.is_empty() or digest.length()!=64:return false
	# Workers perform all filesystem reads and hashes BEFORE this lock. A racing
	# first miss may read twice; it never waits for another worker's I/O, and the
	# first accepted digest cannot be replaced by a conflicting later reader.
	_mutex.lock()
	var valid:bool=_consumers.has(consumer) and not _cancelled.has(consumer)
	if valid:
		var previous:String=_source_identities.get(path,"")
		valid=previous.is_empty() or previous==digest
		if previous.is_empty():_source_identities[path]=digest
	_mutex.unlock();return valid

func offer(plan:Dictionary,cached:Dictionary={},revisions:Dictionary={})->Dictionary:
	var result:Dictionary={"rows":plan.get("rows",{}),"bindings":{},"leaders":{},"retained":{},"cached":cached.duplicate(),"scratch_bytes":HASH_SCRATCH}
	var candidates:Array=[]
	# Plans and identities are private immutable inputs. Resolve their fields,
	# memory contract and serialized keys BEFORE taking the shared-state lock:
	# a script error here must not leave producers blocked behind that mutex.
	for key:String in result.rows:
		if cached.has(key):continue
		var row:Dictionary=result.rows[key]
		var identity:Array=[key,row.width,row.height,row.source_bytes,row.output_bytes,Pixels.upload_preparation_enabled,revisions.get(row.path,"")]
		var binding:String="prefab_pixels:"+var_to_bytes(identity).hex_encode().sha256_text()
		result.bindings[key]=binding
		candidates.append({"key":key,"binding":binding,"retained":int(row.output_bytes)*2,"scratch":Preparation.workspace_bytes(row)})
	_mutex.lock()
	for candidate:Dictionary in candidates:
		if not _entries.has(candidate.binding):
			result.leaders[candidate.key]=true;result.retained[candidate.binding]=candidate.retained
			result.scratch_bytes=maxi(result.scratch_bytes,candidate.scratch)
	_mutex.unlock()
	return result

func commit(consumer:String,offer_:Dictionary)->void:
	_mutex.lock()
	assert(not _consumers.has(consumer))
	var bindings:Dictionary=offer_.bindings.duplicate();_consumers[consumer]=bindings
	for key:String in bindings:
		var binding:String=bindings[key]
		if not _entries.has(binding):
			var bytes:int=offer_.retained[binding]
			_entries[binding]={"owner":consumer,"consumers":{},"state":"pending","digest":"","image":null,"bytes":bytes,"output_bytes":int(offer_.rows[key].output_bytes)}
			profile.retained_bytes+=bytes
		_entries[binding].consumers[consumer]=true
	profile.peak_outputs=maxi(int(profile.peak_outputs),_entries.size());profile.peak_retained_bytes=maxi(int(profile.peak_retained_bytes),int(profile.retained_bytes))
	_mutex.unlock()

func publish(consumer:String,key:String,digest:String,image:Image)->bool:
	_mutex.lock()
	var binding:String=_consumers.get(consumer,{}).get(key,"");var row:Dictionary=_entries.get(binding,{})
	var valid:bool=not row.is_empty() and row.owner==consumer and row.state=="pending" and not _cancelled.has(consumer) and image!=null and image.get_data_size()<=int(row.output_bytes)
	if valid:
		row.image=image;row.digest=digest;row.state="ready";profile.produced+=1
	_mutex.unlock();return valid

func fetch(consumer:String,key:String,digest:String,token:RefCounted)->Dictionary:
	if token!=null and token.is_cancelled():return {"error":"Shared image consumer cancelled","cancelled":true}
	_mutex.lock()
	var binding:String=_consumers.get(consumer,{}).get(key,"");var row:Dictionary=_entries.get(binding,{})
	var answer:Dictionary
	if _cancelled.has(consumer) or row.is_empty():answer={"error":"Shared image consumer cancelled","cancelled":true}
	elif row.state=="ready":
		answer={"error":"","image":row.image} if row.digest==digest else {"error":"Shared image source changed","retry_pixels":true}
		if answer.error.is_empty():profile.shared_hits+=1
	elif row.state=="failed":answer={"error":"Shared image producer retired","retry_pixels":true}
	else:answer={"error":"","pending":true};profile.waits+=1
	_mutex.unlock();return answer

func ready(consumer:String)->bool:
	_mutex.lock();var result:bool=_consumers.has(consumer)
	for binding:String in _consumers.get(consumer,{}).values():
		if _entries.get(binding,{}).get("state","")=="pending":result=false;break
	_mutex.unlock();return result

func cancel(consumer:String)->void:
	_mutex.lock();_cancelled[consumer]=true
	for binding:String in _consumers.get(consumer,{}).values():
		var row:Dictionary=_entries.get(binding,{})
		if row.is_empty():continue
		if row.owner==consumer and row.state=="pending":
			row.state="failed"
	_mutex.unlock()

func release(consumer:String)->void:
	# Main only, AFTER join and clearing this consumer's result/packet aliases.
	# Other consumers retain the same Image and its complete unique reservation.
	var retired:Array[String]=[]
	_mutex.lock()
	for binding:String in _consumers.get(consumer,{}).values():
		var row:Dictionary=_entries.get(binding,{})
		if row.is_empty():continue
		row.consumers.erase(consumer)
		if row.owner==consumer and row.state=="pending":
			row.state="failed"
		if row.consumers.is_empty():
			profile.retained_bytes-=int(row.bytes);row.image=null;_entries.erase(binding);retired.append(binding)
	_consumers.erase(consumer);_cancelled.erase(consumer);_mutex.unlock()
	for binding:String in retired:admission.release(binding)

func snapshot()->Dictionary:
	_mutex.lock();var value:Dictionary=profile.duplicate();value.outputs=_entries.size();value.consumers=_consumers.size();value.source_identities=_source_identities.size();_mutex.unlock();return value
