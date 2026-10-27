extends SceneTree
## ABBA compares whole pool.release on independent Images. --dds supplies a real
## complete DDS; the caller never writes it. Allocation/I/O are not timed.
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Compressed=preload("res://scripts/world3d/compressed_texture_source.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var failures:=0
var dds_path:=""
func check(value:bool,label:String)->void:
	if not value:failures+=1;printerr("FAIL ",label)
func _initialize()->void:run.call_deferred()
func create_and_publish(pool:RefCounted,key:String,row:Dictionary,mode:String)->WeakRef:
	var image:Image
	if mode=="dds":
		var file:=FileAccess.open(dds_path,FileAccess.READ);file.seek(int(row.header_bytes))
		var bytes:PackedByteArray=file.get_buffer(int(row.output_bytes))
		image=Image.create_from_data(row.width,row.height,row.mip_count>1,row.format,bytes)
		bytes=PackedByteArray()
	else:
		image=Image.create_empty(row.width,row.height,false,Image.FORMAT_RGBA8);image.fill(Color(.3,.4,.5))
	check(image!=null and image.get_data_size()==row.output_bytes,"independent Image created")
	var weak:WeakRef=weakref(image);check(pool.publish("job",key,"digest",image),"publish independent image")
	return weak
func alive(weak:WeakRef)->bool:return weak.get_ref()!=null
func sample(mode:String,row:Dictionary,enabled:bool,sequence:int)->void:
	Pool.background_pixel_retirement_enabled=enabled
	var ledger:=Admission.new();ledger.byte_limit=1024*1024*1024
	var pool:=Pool.new();pool.admission=ledger
	var rows:Dictionary={}
	for i:int in 16:
		var copy:Dictionary=row.duplicate();copy.path="fixture_%d.png"%i;rows["image_%d"%i]=copy
	var offer:Dictionary=pool.offer({"rows":rows})
	check(ledger.reserve_bundle("job",{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained),"admit batch")
	pool.commit("job",offer)
	var weak:Array[WeakRef]=[]
	for key:String in rows:weak.append(create_and_publish(pool,key,rows[key],mode))
	ledger.park("job")
	var began:=Time.get_ticks_usec();pool.release("job");var release_us:=Time.get_ticks_usec()-began
	ledger.release("job")
	var pending_bytes:int=ledger.retiring_pixel_bytes
	var largest_frame_us:=0;var previous:=Time.get_ticks_usec()
	while ledger.retiring_pixel_outputs>0 and Time.get_ticks_usec()-began<10000000:
		await process_frame
		var now:=Time.get_ticks_usec();largest_frame_us=maxi(largest_frame_us,now-previous);previous=now
	var drain_us:=Time.get_ticks_usec()-began
	check(ledger.reserved_bytes==0 and pool.snapshot().retiring_outputs==0,"all batch leases released")
	for item:WeakRef in weak:check(not alive(item),"Image object released")
	print("PIXEL_RETIRE_BENCH ",JSON.stringify({"mode":mode,"enabled":enabled,"sequence":sequence,"images":16,"logical_bytes":row.output_bytes*16,"release_us":release_us,"drain_us":drain_us,"max_observed_wait_frame_us":largest_frame_us,"pending_bytes":pending_bytes,"failures_so_far":failures}))
func run()->void:
	check(Retirement._service()!=null,"retirement service ready")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--dds="):dds_path=arg.trim_prefix("--dds=")
	var rgba:Dictionary={"width":2048,"height":2048,"output_bytes":2048*2048*4,"source_bytes":1,"extension":"dds"}
	var cases:Array=[{"mode":"rgba","row":rgba}]
	if not dds_path.is_empty():
		var file:=FileAccess.open(dds_path,FileAccess.READ)
		if file==null:check(false,"DDS file opens")
		else:
			var row:Dictionary=Compressed._header(file.get_buffer(148),file.get_length(),false)
			if row.is_empty():check(false,"complete DDS header")
			else:cases.append({"mode":"dds","row":row})
	for item:Dictionary in cases:
		var sequence:=0
		for enabled:bool in [false,true,true,false]:
			await sample(item.mode,item.row,enabled,sequence);sequence+=1
	Pool.background_pixel_retirement_enabled=true
	print("PIXEL_RETIRE_BENCH_DONE failures=",failures);quit(0 if failures==0 else 1)
