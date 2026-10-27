extends SceneTree
## Independent pressure probe. All allocation/fill/upload is
## outside the timed release. --dds=<absolute file> adds real complete DXT/BC5
## payloads; --gpu runs ImageTexture tickets on a private desktop only.
## Output is per sample, not an FPS, RSS, VRAM, or production-impact claim.
## The 16-image RGBA case touches 256 MiB; do not run with a real-map timing sample.
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Compressed=preload("res://scripts/world3d/compressed_texture_source.gd")
const DIGEST="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

class TimedPool extends Pool:
	# Same ownership operations as Pool.release; timing instrumentation changes
	# execution cost and is used only to locate a candidate, never as baseline.
	var details:Dictionary={}
	func release(consumer:String)->void:
		var total:=Time.get_ticks_usec();var retired:Dictionary={}
		var locked:=Time.get_ticks_usec();_mutex.lock()
		for binding:String in _consumers.get(consumer,{}).values():
			var row:Dictionary=_entries.get(binding,{})
			if row.is_empty():continue
			row.consumers.erase(consumer)
			if row.owner==consumer and row.state in ["pending","uploading"]:row.state="failed"
			if row.consumers.is_empty():
				profile.retained_bytes-=int(row.bytes);retired[binding]=row;_entries.erase(binding)
		_consumers.erase(consumer);_cancelled.erase(consumer);_mutex.unlock()
		var lock_us:=Time.get_ticks_usec()-locked
		var image_us:=0;var texture_us:=0;var admission_us:=0
		for binding:String in retired:
			var began:=Time.get_ticks_usec();retired[binding].image=null;image_us+=Time.get_ticks_usec()-began
			began=Time.get_ticks_usec();retired[binding].texture=null;texture_us+=Time.get_ticks_usec()-began
			began=Time.get_ticks_usec();admission.release(binding);admission_us+=Time.get_ticks_usec()-began
		details={"total_us":Time.get_ticks_usec()-total,"lock_us":lock_us,"image_us":image_us,"texture_us":texture_us,"admission_us":admission_us,"retired":retired.size()}

var errors:Array[String]=[]
var touch_checksum:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	if not value:errors.append(label);printerr("FAIL ",label)
func alive(weak:WeakRef)->bool:
	# Do not leave a VM temporary reference in the measuring caller.
	return weak!=null and weak.get_ref()!=null
func dds_row(path:String)->Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {}
	var length:=file.get_length();var header:=file.get_buffer(mini(length,148))
	var row:=Compressed._header(header,length,false)
	if row.is_empty():row=Compressed._header(header,length,true)
	if not row.is_empty():row.file=path
	return row
func make_plan(count_:int,mode:String,dds:Dictionary)->Dictionary:
	var rows:Dictionary={}
	for i:int in count_:
		var key:="image_%d"%i
		if mode=="dds":
			var row:Dictionary=dds.duplicate();row.path="fixture://image_%d.png"%i;rows[key]=row
		else:
			var pixels:=2048*2048*4 # no mipmaps; constant 16 MiB per independent Image
			rows[key]={"path":"fixture://image_%d.png"%i,"width":2048,"height":2048,"source_bytes":1024,"output_bytes":pixels,"extension":"png","cache_limit":pixels*2+65536}
	return {"rows":rows}
func publish_one(pool:Variant,key:String,row:Dictionary,mode:String)->WeakRef:
	var image:Image
	if mode=="dds":
		var file:=FileAccess.open(row.file,FileAccess.READ)
		if file==null:check(false,"DDS reopen");return null
		file.seek(int(row.header_bytes))
		var data:PackedByteArray=file.get_buffer(int(row.output_bytes))
		if data.size()!=int(row.output_bytes):check(false,"DDS complete payload");return null
		for at:int in range(0,data.size(),4096):touch_checksum^=int(data[at])
		image=Image.create_from_data(int(row.width),int(row.height),int(row.mip_count)>1,int(row.format),data)
		data=PackedByteArray()
	else:
		image=Image.create_empty(int(row.width),int(row.height),false,Image.FORMAT_RGBA8)
		image.fill(Color(.1,.3,.7,1))
		var data:PackedByteArray=image.get_data()
		for at:int in range(0,data.size(),4096):touch_checksum^=int(data[at])
		data=PackedByteArray()
	if image==null or image.is_empty() or image.get_data_size()!=int(row.output_bytes):check(false,"actual image size/format");return null
	var weak:WeakRef=weakref(image)
	check(pool.publish("producer",key,DIGEST,image),"publish "+key)
	image=null
	return weak
func retain_borrowed(pool:Variant,key:String,borrowed:Array[Image])->void:
	var answer:Dictionary=pool.fetch("follower",key,DIGEST,null)
	borrowed.append(answer.get("image"))
	answer.clear()
func run_case(mode:String,count_:int,timed:bool,borrow:bool,gpu:bool,dds:Dictionary,sequence:int)->void:
	var ledger:=Admission.new();ledger.byte_limit=4*1024*1024*1024;ledger.worker_limit=2
	Pool.background_upload_enabled=gpu
	var pool:Variant=TimedPool.new() if timed else Pool.new()
	Pool.background_upload_enabled=false
	pool.admission=ledger
	check(not gpu or bool(pool._upload_enabled),"GPU upload actually enabled")
	var plan:=make_plan(count_,mode,dds);var offer:Dictionary=pool.offer(plan)
	var ok:bool=ledger.reserve_bundle("producer",{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained)
	check(ok,"producer admission")
	if not ok:return
	pool.commit("producer",offer)
	var other:Dictionary=pool.offer(plan)
	check(other.retained.is_empty() and other.leaders.is_empty(),"follower deduplicates all outputs")
	ok=ledger.reserve_bundle("follower",{"estimated_bytes":other.scratch_bytes,"exclusive":false},other.retained)
	check(ok,"follower admission")
	if not ok:return
	pool.commit("follower",other)
	var weak:Array[WeakRef]=[];var logical_bytes:=0
	for key:String in plan.rows:
		logical_bytes+=int(plan.rows[key].output_bytes)
		weak.append(publish_one(pool,key,plan.rows[key],mode))
	ledger.park("producer");ledger.park("follower")
	check(pool.ready("follower"),"all follower images ready")
	if gpu:RenderingServer.force_sync()
	var borrowed:Array[Image]=[]
	if borrow:retain_borrowed(pool,"image_0",borrowed)
	var unique_before:int=pool.snapshot().retained_bytes
	pool.release("producer");ledger.release("producer")
	check(pool.snapshot().retained_bytes==unique_before and alive(weak[0]),"follower retains unique images and charge")
	var before:=Time.get_ticks_usec();pool.release("follower");var elapsed:=Time.get_ticks_usec()-before
	ledger.release("follower")
	check(pool.snapshot().retained_bytes==0 and pool.snapshot().outputs==0 and ledger.reserved_bytes==0,"last consumer clears current pool and ledger")
	for i:int in weak.size():check(alive(weak[i])==(borrow and i==0),"weak owner after final pool release %d"%i)
	var borrow_before:=Time.get_ticks_usec();borrowed.clear();var borrow_release_us:=Time.get_ticks_usec()-borrow_before
	for w:WeakRef in weak:check(not alive(w),"weak owner gone after borrower release")
	var result:Dictionary={"mode":mode,"count":count_,"traced":timed,"borrow_one":borrow,"gpu":gpu,"sequence":sequence,"logical_image_bytes":logical_bytes,"ledger_unique_bytes":unique_before,"last_release_us":elapsed,"borrow_release_us":borrow_release_us,"failed_so_far":errors.size()}
	if timed:result.breakdown=pool.details.duplicate()
	print("RECLAIM_SAMPLE ",JSON.stringify(result))
func run()->void:
	var dds_path:="";var gpu:=false;var only_count:=0;var only_mode:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--dds="):dds_path=arg.trim_prefix("--dds=")
		if arg=="--gpu":gpu=true
		if arg.begins_with("--count="):only_count=int(arg.trim_prefix("--count="))
		if arg.begins_with("--mode="):only_mode=arg.trim_prefix("--mode=")
	if gpu and (DisplayServer.get_name()=="headless" or RenderingServer.get_rendering_device()==null):
		printerr("GPU test requires the private-desktop renderer");quit(2);return
	var dds:Dictionary={}
	if not dds_path.is_empty():
		dds=dds_row(dds_path);check(not dds.is_empty(),"complete DXT/BC5 DDS with mip chain")
	var modes:Array[String]=["rgba"]
	if not dds.is_empty():modes.append("dds")
	if not only_mode.is_empty():
		if only_mode not in modes:printerr("requested mode unavailable");quit(2);return
		modes=[only_mode]
	var counts:Array[int]=[1,4,16]
	if only_count>0:counts=[only_count]
	# ABBA is baseline (A) vs same operations with sub-operation timers (B), not
	# an optimization comparison. Fixture parameters are identical within each.
	for mode:String in modes:
		for count_:int in counts:
			for borrow:bool in [false,true]:
				var sequence:=0
				for timed:bool in [false,true,true,false]:
					run_case(mode,count_,timed,borrow,gpu,dds,sequence);sequence+=1
	print("RECLAIM_DONE failures=",errors.size()," checksum=",touch_checksum)
	quit(0 if errors.is_empty() else 1)
