extends RefCounted
## Lossless decoded pixels/mipmaps. Invalidate using the source file's SHA256,
## including normal-map orientation. Never change the authored image files.
const Envelope=preload("res://scripts/world3d/map_metadata_cache.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const DIR:="user://world3d_textures"
# Probe-only switch. Ordinary game/editor loads consume the same upload-ready
# pixels. Keep legacy entries separate so an A/B never converts its own input.
static var upload_preparation_enabled:=true
# Diagnostic wall spans only; enable/reset before dispatching an operation,
# snapshot after its workers drain. No Image/Texture owners enter statistics.
static var profile_enabled:=false
static var _profile_mutex:=Mutex.new()
static var _profile_stages:Dictionary={}
static var _profile_counters:Dictionary={}

static func reset_profile()->void:
	_profile_mutex.lock();_profile_stages.clear();_profile_counters.clear();_profile_mutex.unlock()

static func profile_snapshot(prefix:String="texture.")->Dictionary:
	var stages:Dictionary={};var counters:Dictionary={}
	_profile_mutex.lock()
	for key:String in _profile_stages:
		if key.begins_with(prefix):stages[key]=_profile_stages[key].duplicate()
	for key:String in _profile_counters:
		if key.begins_with(prefix):counters[key]=_profile_counters[key]
	_profile_mutex.unlock()
	return {"stages":stages,"counters":counters,"note":"Elapsed wall spans overlap/nest; not additive CPU time. Trace events retain scalar path/variant details only."}

static func _profile_count(label:String,amount:int=1)->void:
	_profile_mutex.lock();_profile_counters[label]=int(_profile_counters.get(label,0))+amount;_profile_mutex.unlock()

static func _profile_elapsed(label:String,began:int,details:Dictionary={})->void:
	var elapsed:=Time.get_ticks_usec()-began
	_profile_mutex.lock()
	var row:Dictionary=_profile_stages.get(label,{"calls":0,"total_us":0,"max_us":0})
	row.calls+=1;row.total_us+=elapsed;row.max_us=maxi(row.max_us,elapsed);_profile_stages[label]=row
	_profile_mutex.unlock()
	Trace.elapsed(label,began,details)

static func cache_path(path:String,flip:bool)->String:return DIR.path_join((path+str(flip)+("|upload_v3" if upload_preparation_enabled else "")).sha256_text()+".bin")

static func prepare_upload(image:Image)->Image:
	# Own CPU Images only. Generate mips before this call: preserve their exact
	# channels rather than regenerating them after a format change. RD converts
	# RGB8 to RGBA8 on upload anyway; do it once on the preparation worker.
	var began:=Time.get_ticks_usec() if profile_enabled else 0
	var original_format:int=image.get_format() if profile_enabled else -1
	if image.get_format()==Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGBA8)
		image.set_meta("runtime_upload_has_alpha",false)
	elif not image.has_meta("runtime_upload_has_alpha"):
		image.set_meta("runtime_upload_has_alpha",image.detect_alpha()!=Image.ALPHA_NONE)
	if profile_enabled:_profile_elapsed("texture.image.upload_prepare",began,{"from_format":original_format,"to_format":image.get_format(),"width":image.get_width(),"height":image.get_height()})
	return image
static func valid_pixels(data:Dictionary)->bool:
	for field in ["width","height","format","size"]:
		if not data.get(field) is int:return false
	if data.width<1 or data.height<1 or data.width>4096 or data.height>4096:return false
	var strides:={Image.FORMAT_L8:1,Image.FORMAT_LA8:2,Image.FORMAT_R8:1,Image.FORMAT_RG8:2,Image.FORMAT_RGB8:3,Image.FORMAT_RGBA8:4,Image.FORMAT_RF:4,Image.FORMAT_RGF:8,Image.FORMAT_RGBF:12,Image.FORMAT_RGBAF:16}
	if not strides.has(data.format):return false
	var width:int=data.width;var height:int=data.height;var expected:=0
	while true:
		expected+=width*height*int(strides[data.format])
		if width==1 and height==1:break
		width=maxi(1,width>>1);height=maxi(1,height>>1)
	return data.size==expected and expected<134217728

static func store_pixels(path:String,flip:bool,image:Image,digest:String,limit:int=134217760,authorize:Callable=Callable())->bool:
	# Optional derived output, never an authored file. The caller owns image and
	# proves its snapshot/source identity; a worker may veto publication after
	# compression (cancellation or a source replacement). Keep RGB compact here.
	if image==null or digest.length()!=64 or limit<=32:return false
	var version:=3 if upload_preparation_enabled else 1
	var data:Dictionary={"version":version,"source":digest,"width":image.get_width(),"height":image.get_height(),"format":image.get_format(),"size":image.get_data_size()}
	if not valid_pixels(data):return false
	if version==3:
		if not image.has_meta("runtime_upload_has_alpha"):image.set_meta("runtime_upload_has_alpha",image.detect_alpha()!=Image.ALPHA_NONE)
		data.has_alpha=image.get_meta("runtime_upload_has_alpha")
	data.pixels=image.get_data().compress(FileAccess.COMPRESSION_FASTLZ)
	var payload:=var_to_bytes(data)
	if payload.size()+32>mini(limit,134217760):return false
	if DirAccess.make_dir_recursive_absolute(DIR)!=OK:return false
	var target:=cache_path(path,flip)
	var temporary:=target+".%d.%d.%d.tmp"%[OS.get_process_id(),OS.get_thread_caller_id(),Time.get_ticks_usec()]
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return false
	file.store_buffer(Envelope.checksum(payload));file.store_buffer(payload);file.flush()
	var written:bool=file.get_error()==OK and file.get_position()==payload.size()+32
	file.close()
	if not written or (authorize.is_valid() and not authorize.call()) or DirAccess.rename_absolute(temporary,target)!=OK:
		DirAccess.remove_absolute(temporary);return false
	return true

static func image(path:String,flip:bool)->Image:
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return null
	var began:=Time.get_ticks_usec() if profile_enabled else 0
	var result:=_image(path,flip)
	if profile_enabled:
		_profile_count("texture.image."+("success" if result!=null else "failed"))
		_profile_elapsed("texture.image",began,{"path":path,"flip":flip,"ok":result!=null})
	return result

static func _image(path:String,flip:bool)->Image:
	var began:=Time.get_ticks_usec() if profile_enabled else 0
	var digest:=FileAccess.get_sha256(path)
	if profile_enabled:_profile_elapsed("texture.image.source_sha",began,{"path":path,"flip":flip})
	var version:=3 if upload_preparation_enabled else 1
	var target:=cache_path(path,flip)
	began=Time.get_ticks_usec() if profile_enabled else 0
	var file:=FileAccess.open(target,FileAccess.READ)
	if file!=null and file.get_length()>32 and file.get_length()<134217760:
		var hash:=file.get_buffer(32);var payload:=file.get_buffer(file.get_length()-32)
		if profile_enabled:_profile_elapsed("texture.image.cache_read",began,{"path":path,"flip":flip,"bytes":payload.size()})
		began=Time.get_ticks_usec() if profile_enabled else 0
		var checksum_valid:bool=Envelope.checksum(payload)==hash
		if profile_enabled:_profile_elapsed("texture.image.cache_checksum",began,{"path":path,"flip":flip,"valid":checksum_valid})
		if checksum_valid:
			began=Time.get_ticks_usec() if profile_enabled else 0
			var data:Variant=bytes_to_var(payload)
			if profile_enabled:_profile_elapsed("texture.image.cache_variant",began,{"path":path,"flip":flip})
			if data is Dictionary and data.get("version")==version and data.get("source")==digest and data.get("pixels") is PackedByteArray and valid_pixels(data) and (version==1 or data.get("has_alpha") is bool):
				began=Time.get_ticks_usec() if profile_enabled else 0
				var pixels:PackedByteArray=data.pixels.decompress(data.size,FileAccess.COMPRESSION_FASTLZ)
				if profile_enabled:_profile_elapsed("texture.image.cache_decompress",began,{"path":path,"flip":flip,"bytes":pixels.size()})
				if pixels.size()==data.size:
						began=Time.get_ticks_usec() if profile_enabled else 0
						var cached:=Image.create_from_data(data.width,data.height,true,data.format,pixels)
						if profile_enabled:_profile_elapsed("texture.image.cache_image",began,{"path":path,"flip":flip,"format":data.format,"width":data.width,"height":data.height})
						cached.set_meta("runtime_source_sha256",digest)
						if version==3:
							cached.set_meta("runtime_upload_has_alpha",data.has_alpha)
							prepare_upload(cached)
						if profile_enabled:_profile_count("texture.image.cache_hit")
						return cached
	elif profile_enabled:_profile_elapsed("texture.image.cache_read",began,{"path":path,"flip":flip,"bytes":0})
	file=null
	if profile_enabled:_profile_count("texture.image.cache_miss")
	began=Time.get_ticks_usec() if profile_enabled else 0
	var result:=Image.load_from_file(path)
	if profile_enabled:_profile_elapsed("texture.image.source_decode",began,{"path":path,"flip":flip,"ok":result!=null})
	if result==null or result.is_empty() or result.get_width()>4096 or result.get_height()>4096:return null
	if flip:
		began=Time.get_ticks_usec() if profile_enabled else 0
		result.convert(Image.FORMAT_RGBA8)
		var pixels:=result.get_data()
		for at in range(1,pixels.size(),4):pixels[at]=255-pixels[at]
		result=Image.create_from_data(result.get_width(),result.get_height(),false,Image.FORMAT_RGBA8,pixels)
		if profile_enabled:_profile_elapsed("texture.image.normal_flip",began,{"path":path,"flip":flip})
	began=Time.get_ticks_usec() if profile_enabled else 0
	result.generate_mipmaps()
	if profile_enabled:_profile_elapsed("texture.image.mipmaps",began,{"path":path,"flip":flip})
	result.set_meta("runtime_source_sha256",digest)
	# Keep the compact source channel layout in the pixel cache. Persisting
	# expanded RGB as RGBA increased warm read/decompression time in the town
	# probe. Convert only our private CPU Image, after cache I/O, before upload.
	if version==3:
		began=Time.get_ticks_usec() if profile_enabled else 0
		result.set_meta("runtime_upload_has_alpha",result.detect_alpha()!=Image.ALPHA_NONE)
		if profile_enabled:_profile_elapsed("texture.image.alpha",began,{"path":path,"flip":flip})
	began=Time.get_ticks_usec() if profile_enabled else 0
	store_pixels(path,flip,result,digest)
	if profile_enabled:_profile_elapsed("texture.image.cache_store",began,{"path":path,"flip":flip})
	if version==3:prepare_upload(result)
	return result
