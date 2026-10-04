extends RefCounted
## Lossless decoded pixels/mipmaps. Invalidate using the source file's SHA256,
## including normal-map orientation. Never change the authored image files.
const Envelope=preload("res://scripts/world3d/map_metadata_cache.gd")
const DIR:="user://world3d_textures"
static func cache_path(path:String,flip:bool)->String:return DIR.path_join((path+str(flip)).sha256_text()+".bin")
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

static func image(path:String,flip:bool)->Image:
	var digest:=FileAccess.get_sha256(path)
	var target:=cache_path(path,flip)
	var file:=FileAccess.open(target,FileAccess.READ)
	if file!=null and file.get_length()>32 and file.get_length()<134217760:
		var hash:=file.get_buffer(32);var payload:=file.get_buffer(file.get_length()-32)
		if Envelope.checksum(payload)==hash:
			var data:Variant=bytes_to_var(payload)
			if data is Dictionary and data.get("version")==1 and data.get("source")==digest and data.get("pixels") is PackedByteArray and valid_pixels(data):
				var pixels:PackedByteArray=data.pixels.decompress(data.size,FileAccess.COMPRESSION_FASTLZ)
				if pixels.size()==data.size:
						var cached:=Image.create_from_data(data.width,data.height,true,data.format,pixels)
						cached.set_meta("runtime_source_sha256",digest)
						return cached
	file=null
	var result:=Image.load_from_file(path)
	if result==null or result.is_empty() or result.get_width()>4096 or result.get_height()>4096:return null
	if flip:
		result.convert(Image.FORMAT_RGBA8)
		var pixels:=result.get_data()
		for at in range(1,pixels.size(),4):pixels[at]=255-pixels[at]
		result=Image.create_from_data(result.get_width(),result.get_height(),false,Image.FORMAT_RGBA8,pixels)
	result.generate_mipmaps()
	result.set_meta("runtime_source_sha256",digest)
	if DirAccess.make_dir_recursive_absolute(DIR)==OK:
		var pixels:=result.get_data()
		var data:={"version":1,"source":digest,"width":result.get_width(),"height":result.get_height(),"format":result.get_format(),"size":pixels.size(),"pixels":pixels.compress(FileAccess.COMPRESSION_FASTLZ)}
		var payload:=var_to_bytes(data)
		var temporary:=target+".%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
		file=FileAccess.open(temporary,FileAccess.WRITE)
		if file!=null:
			file.store_buffer(Envelope.checksum(payload));file.store_buffer(payload);file.close()
			if DirAccess.rename_absolute(temporary,target)!=OK:DirAccess.remove_absolute(temporary)
	return result
