extends SceneTree
## Read-only CPU diagnostic. Never calls cache writers or creates GPU objects.
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Envelope=preload("res://scripts/world3d/map_metadata_cache.gd")
const BASE="D:/code/rmmo_runtime/packs/default/assets/materials/walls/stone_tiles_facade/"
const FILES=["texture.jpg","normal.png","roughness.png","ao.png"]
var report:Dictionary={"scope":"read-only CPU pixels; no GPU, scene, cache writes or source changes","rounds":[],"assets":[],"checks":[],"native_hash":[]}
var failures:=0

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	report.checks.append({"ok":ok,"label":label})
	if not ok:failures+=1

static func read_bytes(path:String)->PackedByteArray:
	var file:=FileAccess.open(path,FileAccess.READ)
	return file.get_buffer(file.get_length()) if file!=null else PackedByteArray()

static func probe(name:String,verify_pixels:bool=false)->Dictionary:
	var path:=BASE+name
	var began:=Time.get_ticks_usec();var stamp:=began;var row:Dictionary={"file":name,"stages_us":{}}
	var digest:=FileAccess.get_sha256(path)
	row.stages_us.source_sha=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
	var file:=FileAccess.open(Pixels.cache_path(path,false),FileAccess.READ)
	if file==null:return {"file":name,"error":"cache_missing"}
	var expected:=file.get_buffer(32);var payload:=file.get_buffer(file.get_length()-32);file.close()
	row.stages_us.cache_read=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
	if Envelope.checksum(payload)!=expected:return {"file":name,"error":"checksum"}
	row.stages_us.cache_checksum=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
	var data:Variant=bytes_to_var(payload)
	row.stages_us.cache_variant=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
	if not data is Dictionary or data.get("version")!=3 or data.get("source")!=digest or not Pixels.valid_pixels(data):return {"file":name,"error":"cache_identity_or_format"}
	row.stages_us.cache_validate=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
	var raw:PackedByteArray=data.pixels.decompress(data.size,FileAccess.COMPRESSION_FASTLZ)
	row.stages_us.decompress=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
	if raw.size()!=data.size:return {"file":name,"error":"pixel_length"}
	var image:=Image.create_from_data(data.width,data.height,true,data.format,raw)
	row.stages_us.image_create=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
	image.set_meta("runtime_upload_has_alpha",data.has_alpha)
	Pixels.prepare_upload(image)
	row.stages_us.upload_prepare=Time.get_ticks_usec()-stamp
	row.total_us=Time.get_ticks_usec()-began
	row.source_sha=digest;row.width=data.width;row.height=data.height;row.cache_format=data.format;row.output_format=image.get_format()
	row.payload_bytes=payload.size();row.compressed_bytes=data.pixels.size();row.raw_bytes=raw.size();row.output_bytes=image.get_data_size();row.mip_count=image.get_mipmap_count()
	if verify_pixels:row.output_sha=Envelope.checksum(image.get_data()).hex_encode()
	return row

func batch(parallel:bool,round_index:int)->void:
	var start:=Time.get_ticks_usec();var rows:Array=[];var threads:Array[Thread]=[]
	if parallel:
		for name:String in FILES:
			var thread:=Thread.new();check(thread.start(probe.bind(name))==OK,"start independent CPU image worker")
			threads.append(thread)
		for thread:Thread in threads:
			rows.append(thread.wait_to_finish())
	else:
		for name:String in FILES:rows.append(probe(name))
	var span:=Time.get_ticks_usec()-start
	for row:Dictionary in rows:check(not row.has("error"),"valid cached source "+str(row.get("file","")))
	report.rounds.append({"mode":"four_workers" if parallel else "sequential","round":round_index,"batch_wall_us":span,"images":rows})
	print("PROBE ",round_index," ","parallel" if parallel else "serial"," ",span)

func hash_micro(name:String)->Dictionary:
	var path:=BASE+name;var packed:=read_bytes(Pixels.cache_path(path,false))
	var payload:=packed.slice(32);packed.clear()
	var source:=read_bytes(path);var results:Array=[]
	for repeat_index:int in 5:
		var row:Dictionary={"round":repeat_index}
		var began:=Time.get_ticks_usec();var digest:=Envelope.checksum(payload)
		row.payload_sha_us=Time.get_ticks_usec()-began
		began=Time.get_ticks_usec();var source_digest:=Envelope.checksum(source)
		row.source_memory_sha_us=Time.get_ticks_usec()-began
		began=Time.get_ticks_usec();var file_digest:=FileAccess.get_sha256(path)
		row.source_file_sha_us=Time.get_ticks_usec()-began
		check(digest.size()==32 and source_digest.hex_encode()==file_digest,"memory/file SHA preserve digest "+name)
		results.append(row)
	return {"file":name,"payload_bytes":payload.size(),"source_bytes":source.size(),"samples":results}

func run()->void:
	Pixels.profile_enabled=false
	for name:String in FILES:
		var path:=BASE+name;var cache:=ProjectSettings.globalize_path(Pixels.cache_path(path,false))
		check(FileAccess.file_exists(path) and FileAccess.file_exists(cache),"preexisting source/cache "+name)
		if failures:quit(1);return
		var file:=FileAccess.open(path,FileAccess.READ);var size:=file.get_length();file.close()
		report.assets.append({"path":path,"source_bytes":size,"cache":cache,"cache_sha_before":FileAccess.get_sha256(cache),"source_sha_before":FileAccess.get_sha256(path)})
	# S/P/P/S repeated twice; no renderer/world concurrency, caches not flushed.
	for i:int in 8:batch(i%4 in [1,2],i)
	for name:String in FILES:report.native_hash.append(hash_micro(name))
	for row:Dictionary in report.assets:
		check(FileAccess.get_sha256(row.path)==row.source_sha_before,"source unchanged")
		check(FileAccess.get_sha256(row.cache)==row.cache_sha_before,"pixel cache unchanged")
	for name:String in FILES:
		var original:=probe(name,true);var worker:=Thread.new()
		check(worker.start(probe.bind(name,true))==OK,"verification worker starts")
		var concurrent:Dictionary=worker.wait_to_finish()
		check(original.output_sha==concurrent.output_sha,"sequential/worker pixel and mip equality "+name)
	report.failures=failures
	var output:=FileAccess.open("res://review_artifacts/bridge_texture_cache_deep_20261011.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"));output.close()
	print("BRIDGE_CACHE_DEEP failures=",failures)
	quit(1 if failures else 0)
