extends SceneTree
## Read-only comparison: original image decode + mip construction, no cache store.
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Envelope=preload("res://scripts/world3d/map_metadata_cache.gd")
const BASE="D:/code/rmmo_runtime/packs/default/assets/materials/walls/stone_tiles_facade/"
const FILES=["texture.jpg","normal.png","roughness.png","ao.png"]
static func probe(name:String)->Dictionary:
	var path:=BASE+name;var row:Dictionary={"file":name,"stages_us":{}};var began:=Time.get_ticks_usec();var stamp:=began
	row.source_sha=FileAccess.get_sha256(path);row.stages_us.source_sha=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
	var image:=Image.load_from_file(path)
	row.stages_us.source_read_decode=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
	if image==null:return {"error":"decode"}
	if image.generate_mipmaps()!=OK:return {"error":"mips"}
	row.stages_us.mips=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
	image.set_meta("runtime_upload_has_alpha",image.detect_alpha()!=Image.ALPHA_NONE)
	Pixels.prepare_upload(image)
	row.stages_us.alpha_upload_prepare=Time.get_ticks_usec()-stamp
	row.total_us=Time.get_ticks_usec()-began;row.output_bytes=image.get_data_size()
	return row
func _initialize()->void:run.call_deferred()
func run()->void:
	var report:Dictionary={"scope":"source SHA + original decode + mips + upload preparation; NO derived cache write or GPU upload; not full production cache-miss timing","rounds":[],"failures":0}
	for repeat_index:int in 4:
		var rows:Array=[];var started:=Time.get_ticks_usec()
		for name:String in FILES:
			var path:=BASE+name;var row:Dictionary={"file":name,"stages_us":{}};var began:=Time.get_ticks_usec();var stamp:=began
			row.source_sha=FileAccess.get_sha256(path);row.stages_us.source_sha=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
			var image:=Image.load_from_file(path)
			row.stages_us.source_read_decode=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
			if image==null:report.failures+=1;continue
			var error:=image.generate_mipmaps()
			row.stages_us.mips=Time.get_ticks_usec()-stamp;stamp=Time.get_ticks_usec()
			image.set_meta("runtime_upload_has_alpha",image.detect_alpha()!=Image.ALPHA_NONE)
			Pixels.prepare_upload(image)
			row.stages_us.alpha_upload_prepare=Time.get_ticks_usec()-stamp
			row.total_us=Time.get_ticks_usec()-began
			row.output_bytes=image.get_data_size();row.format=image.get_format();row.mips=image.get_mipmap_count()
			if error!=OK:report.failures+=1
			rows.append(row)
		report.rounds.append({"round":repeat_index,"wall_us":Time.get_ticks_usec()-started,"images":rows})
		print("SOURCE_PROBE ",repeat_index," ",report.rounds[-1].wall_us)
	# Exact bytes verified outside timed rounds, using cache read-only restoration.
	for name:String in FILES:
		var path:=BASE+name;var original:=Image.load_from_file(path);original.generate_mipmaps();Pixels.prepare_upload(original)
		var file:=FileAccess.open(Pixels.cache_path(path,false),FileAccess.READ)
		var expected:=file.get_buffer(32);var payload:=file.get_buffer(file.get_length()-32);file.close()
		var data:Dictionary=bytes_to_var(payload)
		var raw:PackedByteArray=data.pixels.decompress(data.size,FileAccess.COMPRESSION_FASTLZ)
		var cached:=Image.create_from_data(data.width,data.height,true,data.format,raw);Pixels.prepare_upload(cached)
		if Envelope.checksum(payload)!=expected or data.source!=FileAccess.get_sha256(path) or original.get_data()!=cached.get_data():report.failures+=1
	var file:=FileAccess.open("res://review_artifacts/bridge_texture_source_decode_20261011.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("SOURCE_DECODE failures=",report.failures);quit(1 if report.failures else 0)
