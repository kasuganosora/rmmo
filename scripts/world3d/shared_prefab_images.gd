extends RefCounted
## Operation-local Images and optional completed GPU uploads. The scheduler creates/releases leases and
## writes the admission ledger. Workers publish/fetch immutable pixels under a
## mutex. All keys for a job are claimed atomically before its thread starts;
## missing dependencies return to the scheduler; no worker blocks on a sibling.
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Preparation=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const HASH_SCRATCH=8*1024*1024
## Candidate: preserve the CPU path until whole-map loading/return evidence passes.
static var background_upload_enabled:=false
static var background_pixel_retirement_enabled:=true
const RETIRE_PIXEL_MIN_BYTES:=256*1024
var _upload_enabled:bool=background_upload_enabled and RenderingServer.get_rendering_device()!=null
var admission:RefCounted
var _mutex:=Mutex.new()
var _entries:Dictionary={}
var _consumers:Dictionary={}
var _cancelled:Dictionary={}
var _source_identities:Dictionary={} # Mounted operation only; String SHA values, no pixel/resource owners.
var profile:Dictionary={"produced":0,"shared_hits":0,"waits":0,"peak_outputs":0,"retained_bytes":0,"peak_retained_bytes":0,"retiring_bytes":0,"retiring_outputs":0,"uploads":0,"upload_bytes":0,"upload_us":0,"upload_max_us":0,"discarded_uploads":0}

func consumer_active(consumer:String)->bool:
	_mutex.lock();var active:bool=_consumers.has(consumer) and not _cancelled.has(consumer);_mutex.unlock();return active

func source_identity(consumer:String,path:String)->String:
	_mutex.lock()
	var digest:String=_source_identities.get(path,"") if _consumers.has(consumer) and not _cancelled.has(consumer) else ""
	_mutex.unlock();return digest

func source_identities_match(consumer:String,expected:Dictionary)->bool:
	# Final handoff compares immutable scalar identities only. One snapshot,
	# no filesystem/GPU work and no per-path unlock/relock cycle.
	_mutex.lock()
	var valid:bool=_consumers.has(consumer) and not _cancelled.has(consumer)
	if valid:
		for path:String in expected:
			var digest:String=_source_identities.get(path,"")
			if digest.is_empty() or digest!=expected[path]:valid=false;break
	_mutex.unlock();return valid

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
		# A trusted mounted source is immutable for this explicit refresh generation.
		# A follower's observed digest must not create a second binding when the
		# original producer is cancelled. Mutable diagnostic sources keep revisions.
		var revision:String="" if Pixels.Policy.trusted() else str(revisions.get(row.path,""))
		var identity:Array=[key,row.width,row.height,row.source_bytes,row.output_bytes,Pixels.upload_preparation_enabled,preload("res://scripts/world3d/surface_materials.gd").source_generation,revision,_upload_enabled,row.get("product",""),row.get("representation","")]
		var binding:String="prefab_pixels:"+var_to_bytes(identity).hex_encode().sha256_text()
		result.bindings[key]=binding
		candidates.append({"key":key,"binding":binding,"retained":int(row.output_bytes)*2,"scratch":Preparation.workspace_bytes(row)})
	_mutex.lock()
	for candidate:Dictionary in candidates:
		if not _entries.has(candidate.binding):
			result.leaders[candidate.key]=true;result.retained[candidate.binding]=candidate.retained
			result.scratch_bytes=maxi(result.scratch_bytes,candidate.scratch)
		elif _entries[candidate.binding].state=="failed":
			# Its output charge is still held by existing consumers. Only a newly
			# admitted decoder workspace is needed to take over pending production.
			result.leaders[candidate.key]=true
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
			_entries[binding]={"owner":consumer,"consumers":{},"state":"pending","digest":"","image":null,"texture":null,"bytes":bytes,"output_bytes":int(offer_.rows[key].output_bytes)}
			profile.retained_bytes+=bytes
		elif offer_.leaders.has(key) and _entries[binding].state=="failed":
			# offer -> reserve_bundle -> commit is one scheduler transaction. The
			# old cancelled worker retains its private workspace until joined; its
			# late publish/release cannot mutate the new owner's shared output.
			_entries[binding].owner=consumer;_entries[binding].state="pending"
		_entries[binding].consumers[consumer]=true
	profile.peak_outputs=maxi(int(profile.peak_outputs),_entries.size());profile.peak_retained_bytes=maxi(int(profile.peak_retained_bytes),int(profile.retained_bytes))
	_mutex.unlock()
	if background_pixel_retirement_enabled and Thread.is_main_thread():
		for key:String in offer_.leaders:
			if int(offer_.rows[key].output_bytes)>=RETIRE_PIXEL_MIN_BYTES:
				preload("res://scripts/world3d/resource_retirement.gd").request_shared_pixel_service();break

func publish(consumer:String,key:String,digest:String,image:Image)->bool:
	var texture:ImageTexture # Late/cancelled owner dies only AFTER unlocking below.
	_mutex.lock()
	var binding:String=_consumers.get(consumer,{}).get(key,"");var row:Dictionary=_entries.get(binding,{})
	var valid:bool=not row.is_empty() and row.owner==consumer and row.state=="pending" and not _cancelled.has(consumer) and image!=null and image.get_data_size()<=int(row.output_bytes)
	if valid and _upload_enabled:
		# Claim before leaving the lock: duplicate callers cannot upload twice.
		# The existing admitted producer owns decoder/staging scratch until join;
		# the unique retained reservation covers Image + Texture payloads after join.
		row.state="uploading";_mutex.unlock()
		var began:=Time.get_ticks_usec();texture=_upload(image)
		var elapsed:=Time.get_ticks_usec()-began
		preload("res://scripts/world3d/load_trace.gd").elapsed("prefab_pixels.gpu_upload",began,{"key":key,"bytes":image.get_data_size()})
		_mutex.lock()
		profile.uploads+=1;profile.upload_bytes+=image.get_data_size();profile.upload_us+=elapsed;profile.upload_max_us=maxi(int(profile.upload_max_us),elapsed)
		# Cancellation can transfer production to another admitted owner while the
		# old driver call completes. Never publish its late result into that row.
		valid=row.owner==consumer and row.state=="uploading" and not _cancelled.has(consumer) and texture!=null
		if valid:row.texture=texture;row.state="pending"
		else:
			profile.discarded_uploads+=1
			if row.owner==consumer and row.state=="uploading":row.state="failed"
	if valid:
		row.image=image;row.digest=digest;row.state="ready";profile.produced+=1
	_mutex.unlock();return valid

func _upload(image:Image)->ImageTexture:
	# Private upload only. Never touch Paint's global caches or mutate the Image.
	var texture:=ImageTexture.create_from_image(image)
	if texture!=null:
		texture.set_meta("runtime_source_sha256",image.get_meta("runtime_source_sha256",""))
	return texture

func _load_stream(plan:Dictionary,digest:String)->Texture2D:
	return Preparation.Streamed.read(plan,digest)

func load_stream(consumer:String,key:String,digest:String,plan:Dictionary)->bool:
	# Claim before file/GPU work; a duplicate producer cannot even start a load.
	# Cancellation can transfer ownership while the native call is in flight.
	_mutex.lock()
	var binding:String=_consumers.get(consumer,{}).get(key,"");var row:Dictionary=_entries.get(binding,{})
	var valid:bool=not row.is_empty() and row.owner==consumer and row.state=="pending" and not _cancelled.has(consumer)
	if not valid:_mutex.unlock();return false
	row.state="uploading";_mutex.unlock()
	var began:=Time.get_ticks_usec()
	var texture:=_load_stream(plan,digest)
	var elapsed:=Time.get_ticks_usec()-began
	_mutex.lock()
	profile.streamed_loads=int(profile.get("streamed_loads",0))+1
	profile.streamed_load_us=int(profile.get("streamed_load_us",0))+elapsed
	profile.streamed_load_max_us=maxi(int(profile.get("streamed_load_max_us",0)),elapsed)
	valid=row.owner==consumer and row.state=="uploading" and not _cancelled.has(consumer) and texture!=null
	if valid:
		row.texture=texture;row.digest=digest;row.state="ready";profile.produced+=1
	else:
		profile.discarded_uploads+=1
		if row.owner==consumer and row.state=="uploading":row.state="failed"
	_mutex.unlock();return valid

func textures(consumer:String)->Dictionary:
	# Main after join. Explicit ownership, never hidden in Image metadata/arrays.
	var result:Dictionary={};_mutex.lock()
	if not _cancelled.has(consumer):
		for key:String in _consumers.get(consumer,{}):
			var row:Dictionary=_entries.get(_consumers[consumer][key],{})
			if row.get("state")=="ready" and row.get("texture")!=null:result[key]=row.texture
	_mutex.unlock();return result

func fetch(consumer:String,key:String,digest:String,token:RefCounted,count_shared_hit:bool=true)->Dictionary:
	if token!=null and token.is_cancelled():return {"error":"Shared image consumer cancelled","cancelled":true}
	_mutex.lock()
	var binding:String=_consumers.get(consumer,{}).get(key,"");var row:Dictionary=_entries.get(binding,{})
	var answer:Dictionary
	if _cancelled.has(consumer) or row.is_empty():answer={"error":"Shared image consumer cancelled","cancelled":true}
	elif row.state=="ready":
		answer={"error":"","image":row.image,"texture":row.texture} if row.digest==digest else {"error":"Shared image source changed","retry_pixels":true}
		if answer.error.is_empty() and count_shared_hit:profile.shared_hits+=1
	elif row.state=="failed":answer={"error":"Shared image producer retired","retry_pixels":true}
	else:answer={"error":"","pending":true};profile.waits+=1
	_mutex.unlock();return answer

func ready(consumer:String)->bool:
	_mutex.lock();var result:bool=_consumers.has(consumer)
	for binding:String in _consumers.get(consumer,{}).values():
		if _entries.get(binding,{}).get("state","") in ["pending","uploading"]:result=false;break
	_mutex.unlock();return result

func cancel(consumer:String)->void:
	_mutex.lock();_cancelled[consumer]=true
	for binding:String in _consumers.get(consumer,{}).values():
		var row:Dictionary=_entries.get(binding,{})
		if row.is_empty():continue
		if row.owner==consumer and row.state in ["pending","uploading"]:
			row.state="failed"
	_mutex.unlock()

func release(consumer:String)->void:
	# Main only, AFTER join and clearing this consumer's result/packet aliases.
	# Other consumers retain the same Image and its complete unique reservation.
	var retired:Dictionary={}
	_mutex.lock()
	for binding:String in _consumers.get(consumer,{}).values():
		var row:Dictionary=_entries.get(binding,{})
		if row.is_empty():continue
		row.consumers.erase(consumer)
		if row.owner==consumer and row.state in ["pending","uploading"]:
			row.state="failed"
		if row.consumers.is_empty():
			# Atomically move accounting with the logical output removal, so a
			# concurrent snapshot cannot observe neither live nor retiring charge.
			var image:Image=row.image
			if background_pixel_retirement_enabled and Thread.is_main_thread() and image!=null and image.get_data_size()>=RETIRE_PIXEL_MIN_BYTES:
				var lease:String=admission.retire_shared_pixels(binding)
				if not lease.is_empty():
					row.retiring_lease=lease;profile.retiring_bytes+=int(row.bytes);profile.retiring_outputs+=1
			profile.retained_bytes-=int(row.bytes);retired[binding]=row;_entries.erase(binding)
	_consumers.erase(consumer);_cancelled.erase(consumer);_mutex.unlock()
	# Image/GPU destruction must not hold the pool lock while siblings publish.
	# Image/Texture remain on main. Only a COW byte reference is transferred;
	# the worker starts in a later frame after these stack aliases have unwound.
	var values:Array=[];var completions:Array=[]
	for binding:String in retired:
		var row:Dictionary=retired[binding]
		var image:Image=row.image
		var lease:String=row.get("retiring_lease","")
		if not lease.is_empty():values.append(image.get_data());completions.append({"owner":self,"lease":lease,"bytes":int(row.bytes)})
		row.image=null;row.texture=null;image=null
		if lease.is_empty():admission.release(binding)
	if not values.is_empty() and not preload("res://scripts/world3d/resource_retirement.gd").defer_shared_pixel_buffers(values,completions,admission):
		# No live tree service: drop the COW aliases synchronously and honour
		# every original charge. Never report a queued release without a ticket.
		values.clear()
		for completion:Dictionary in completions:_complete_pixel_retirement(admission,completion.lease,int(completion.bytes))

func _complete_pixel_retirement(ledger:RefCounted,lease:String,bytes:int)->void:
	# Completion means the worker's COW alias is gone, not that unrelated
	# Image borrowers or GPU residency have disappeared.
	ledger.release(lease)
	_mutex.lock();profile.retiring_bytes-=bytes;profile.retiring_outputs-=1;_mutex.unlock()

func snapshot()->Dictionary:
	_mutex.lock();var value:Dictionary=profile.duplicate();value.outputs=_entries.size();value.consumers=_consumers.size();value.source_identities=_source_identities.size();_mutex.unlock();return value
