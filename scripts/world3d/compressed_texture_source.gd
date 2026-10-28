extends RefCounted
## CPU-only admission and reading of complete BC1/BC3/BC5 2D DDS mip chains.
## Trusted game plan/read never hash package bytes. The explicit mutable-source
## editor route binds derived DDS bytes to an already-read authored snapshot.
const Paths=preload("res://scripts/world3d/map_paths.gd")
# Image::MAX_PIXELS in core/io/image.h is not exposed as a GDScript constant.
# Unlike the old cache policy limits, this is an actual Image allocation limit.
const IMAGE_MAX_PIXELS:=1<<28
# JSON numbers are parsed as floats; values above this are not all exactly
# representable, so they cannot safely identify a source byte count.
const JSON_MAX_EXACT_INTEGER:=9007199254740991

static func sidecar_path(path:String,flip:bool=false,normal:bool=false)->String:
	var suffixes:=([".flip.dxt5.dds",".flip.dxt1.dds"] if flip else [".dxt5.dds",".dxt1.dds"])
	if normal or flip:suffixes.push_front(".flip.bc5.dds" if flip else ".bc5.dds")
	for suffix:String in suffixes:
		if FileAccess.file_exists(path+suffix):return path+suffix
	return ""

static func _header(bytes:PackedByteArray,length:int,normal:bool)->Dictionary:
	if length<128 or bytes.size()<128:return {}
	if bytes.slice(0,4).get_string_from_ascii()!="DDS " or bytes.decode_u32(4)!=124 or bytes.decode_u32(76)!=32:return {}
	var width:=int(bytes.decode_u32(16));var height:=int(bytes.decode_u32(12))
	# decode_u32 fits in a signed 64-bit integer. Reject the Image engine limits
	# before multiplication, so the product and all BC mip sizes fit in int64.
	if width<1 or height<1 or width>Image.MAX_WIDTH or height>Image.MAX_HEIGHT:return {}
	if width*height>IMAGE_MAX_PIXELS:return {}
	# Volumes, cube maps and arrays have a different ownership/allocation contract.
	if bytes.decode_u32(24)>1 or bytes.decode_u32(112)!=0 or (bytes.decode_u32(80)&4)==0:return {}
	var fourcc:=bytes.slice(84,88).get_string_from_ascii()
	var format:=-1;var block_bytes:=16;var alpha:=false;var header_bytes:=128
	match fourcc:
		"DXT1":format=Image.FORMAT_DXT1;block_bytes=8;alpha=(bytes.decode_u32(80)&1)!=0
		"DXT5":format=Image.FORMAT_DXT5;alpha=true
		"ATI2","BC5U":format=Image.FORMAT_RGTC_RG
		"DX10":
			if bytes.size()<148 or length<148:return {}
			if bytes.decode_u32(132)!=3 or bytes.decode_u32(140)!=1 or (bytes.decode_u32(136)&4)!=0:return {}
			header_bytes=148
			match bytes.decode_u32(128):
				71,72:format=Image.FORMAT_DXT1;block_bytes=8;alpha=(bytes.decode_u32(144)&7) in [1,2]
				77,78:format=Image.FORMAT_DXT5;alpha=true
				83:format=Image.FORMAT_RGTC_RG
				_:return {}
		_:return {}
	if format==Image.FORMAT_RGTC_RG and not normal:return {}
	var mip_count:=1;var output_bytes:=0;var w:=width;var h:=height
	while true:
		output_bytes+=maxi(1,(w+3)/4)*maxi(1,(h+3)/4)*block_bytes
		if w==1 and h==1:break
		w=maxi(1,w/2);h=maxi(1,h/2);mip_count+=1
	# Only complete chains are prepared; unsupported legacy files retain fallback.
	if maxi(1,int(bytes.decode_u32(28)))!=mip_count or length!=header_bytes+output_bytes:return {}
	return {"width":width,"height":height,"source_bytes":length,"output_bytes":output_bytes,"format":format,"alpha":alpha,"header_bytes":header_bytes,"mip_count":mip_count,"extension":"dds"}

static func plan(path:String,flip:bool,normal:bool,root:String)->Dictionary:
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return {}
	if path.is_empty() or (flip and not normal) or root.is_empty() or not Paths.allowed(path,root):return {}
	var sidecar:=sidecar_path(path,flip,normal)
	if sidecar.is_empty() or not Paths.allowed(sidecar,root):return {}
	var file:=FileAccess.open(sidecar,FileAccess.READ)
	if file==null:return {}
	var length:=file.get_length()
	if length<128:return {}
	var row:=_header(file.get_buffer(mini(length,148)),length,normal)
	if row.is_empty():return {}
	row.path=path;row.sidecar=sidecar;row.flip=flip;row.normal=normal;row.root=root
	return row

static func _sha(value:Variant)->bool:
	if not value is String or value.length()!=64:return false
	for character:String in value:
		if not character in "0123456789abcdef":return false
	return true

static func plan_mutable(path:String,flip:bool,normal:bool,root:String,source_sha256:String)->Dictionary:
	# Caller owns the already-read PNG snapshot and its full fallback reservation.
	# Old sidecars without producer identity stay usable for trusted game packages
	# but cannot establish freshness for an editable same-path source.
	if not _sha(source_sha256):return {}
	var row:=plan(path,flip,normal,root)
	if row.is_empty():return {}
	var metadata_path:=str(row.sidecar)+".source.json"
	if not Paths.allowed(metadata_path,root):return {}
	var file:=FileAccess.open(metadata_path,FileAccess.READ)
	if file==null or file.get_length()<=0 or file.get_length()>2048:return {}
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK:return {}
	var metadata:Variant=parser.data
	if not metadata is Dictionary or metadata.get("version")!=1 or metadata.get("encoder_version")!=1:return {}
	if metadata.get("normal")!=normal or metadata.get("flip")!=flip:return {}
	if metadata.get("source_sha256")!=source_sha256 or not _sha(metadata.get("dds_sha256")):return {}
	var source_bytes:Variant=metadata.get("source_bytes")
	if not source_bytes is float and not source_bytes is int:return {}
	if source_bytes<=0 or source_bytes>JSON_MAX_EXACT_INTEGER or source_bytes!=int(source_bytes):return {}
	if metadata.get("dds_bytes")!=row.source_bytes:return {}
	row.mutable_source=true
	row.mutable_source_sha256=source_sha256
	row.mutable_dds_sha256=metadata.dds_sha256
	return row

static func read(row:Dictionary)->Image:
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return null
	var sidecar:=str(row.get("sidecar",""));var root:=str(row.get("root",""))
	if root.is_empty() or sidecar.is_empty() or not Paths.allowed(sidecar,root):return null
	var file:=FileAccess.open(sidecar,FileAccess.READ)
	if file==null or file.get_length()!=int(row.get("source_bytes",0)):return null
	var length:=file.get_length()
	if length<128:return null
	var header:=file.get_buffer(mini(length,148))
	var actual:=_header(header,length,bool(row.get("normal",false)))
	if actual.is_empty():return null
	for field:String in actual:
		if actual[field]!=row.get(field):return null
	file.seek(actual.header_bytes)
	var payload:=file.get_buffer(actual.output_bytes)
	if payload.size()!=actual.output_bytes:return null
	if row.get("mutable_source",false):
		if not _sha(row.get("mutable_source_sha256")) or not _sha(row.get("mutable_dds_sha256")):return null
		var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256)
		hash_.update(header.slice(0,actual.header_bytes));hash_.update(payload)
		if hash_.finish().hex_encode()!=row.mutable_dds_sha256:return null
	var image:=Image.create_from_data(actual.width,actual.height,actual.mip_count>1,actual.format,payload)
	if image==null or image.is_empty() or image.get_data_size()!=actual.output_bytes:return null
	image.set_meta("runtime_upload_has_alpha",actual.alpha)
	image.set_meta("runtime_compressed_sidecar_path",sidecar)
	image.set_meta("runtime_normal_xy",actual.format==Image.FORMAT_RGTC_RG)
	return image
