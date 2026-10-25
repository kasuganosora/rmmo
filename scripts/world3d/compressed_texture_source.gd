extends RefCounted
## CPU-only admission and reading of complete BC1/BC3/BC5 2D DDS mip chains.
## Never touches render caches, hashes package bytes, expands pixels or builds mips.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const MAX_DIMENSION=4096
const MAX_SOURCE_BYTES=128*1024*1024

static func sidecar_path(path:String,flip:bool=false,normal:bool=false)->String:
	var suffixes:=([".flip.dxt5.dds",".flip.dxt1.dds"] if flip else [".dxt5.dds",".dxt1.dds"])
	if normal or flip:suffixes.push_front(".flip.bc5.dds" if flip else ".bc5.dds")
	for suffix:String in suffixes:
		if FileAccess.file_exists(path+suffix):return path+suffix
	return ""

static func _header(bytes:PackedByteArray,length:int,normal:bool)->Dictionary:
	if length<128 or length>MAX_SOURCE_BYTES or bytes.size()<128:return {}
	if bytes.slice(0,4).get_string_from_ascii()!="DDS " or bytes.decode_u32(4)!=124 or bytes.decode_u32(76)!=32:return {}
	var width:=int(bytes.decode_u32(16));var height:=int(bytes.decode_u32(12))
	if width<1 or height<1 or width>MAX_DIMENSION or height>MAX_DIMENSION:return {}
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
	if length<128 or length>MAX_SOURCE_BYTES:return {}
	var row:=_header(file.get_buffer(mini(length,148)),length,normal)
	if row.is_empty():return {}
	row.path=path;row.sidecar=sidecar;row.flip=flip;row.normal=normal;row.root=root
	return row

static func read(row:Dictionary)->Image:
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return null
	var sidecar:=str(row.get("sidecar",""));var root:=str(row.get("root",""))
	if root.is_empty() or sidecar.is_empty() or not Paths.allowed(sidecar,root):return null
	var file:=FileAccess.open(sidecar,FileAccess.READ)
	if file==null or file.get_length()!=int(row.get("source_bytes",0)):return null
	var length:=file.get_length()
	if length<128 or length>MAX_SOURCE_BYTES:return null
	var actual:=_header(file.get_buffer(mini(length,148)),length,bool(row.get("normal",false)))
	if actual.is_empty():return null
	for field:String in actual:
		if actual[field]!=row.get(field):return null
	file.seek(actual.header_bytes)
	var payload:=file.get_buffer(actual.output_bytes)
	if payload.size()!=actual.output_bytes:return null
	var image:=Image.create_from_data(actual.width,actual.height,actual.mip_count>1,actual.format,payload)
	if image==null or image.is_empty() or image.get_data_size()!=actual.output_bytes:return null
	image.set_meta("runtime_upload_has_alpha",actual.alpha)
	image.set_meta("runtime_compressed_sidecar_path",sidecar)
	image.set_meta("runtime_normal_xy",actual.format==Image.FORMAT_RGTC_RG)
	return image
