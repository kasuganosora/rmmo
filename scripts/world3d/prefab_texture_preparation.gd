extends RefCounted
## Bounded CPU-only pixels for a reference job. Never accesses shared render
## caches. Its images remain owned by that job's admission lease until main
## publishes or discards them. Unsupported headers keep the ordinary path.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Headers=preload("res://scripts/world3d/asset_memory_estimate.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const FIELDS=["texture_path","normal_path","roughness_path","metallic_path","ao_path","height_path"]
const MAX_SOURCES=256
const MAX_SOURCE_BYTES=128*1024*1024
const MAX_OUTPUT_BYTES=512*1024*1024

static func sources(record:Dictionary)->Dictionary:
	var result:Dictionary={}
	if not record.has("house_prefab"):return result
	for definition:Dictionary in record.get("prefab_materials",[]):
		for field:String in FIELDS:
			var path:String=definition.get(field,"")
			if path.is_empty():continue
			var flip:bool=field=="normal_path" and definition.get("normal_format","opengl")=="directx"
			result[path+("|flip_y" if flip else "")]=[path,flip]
			if result.size()>MAX_SOURCES:return {} # Optional prefetch, never a new authoring limit.
	return result

static func valid_sources(value:Variant)->bool:
	if not value is Dictionary or value.size()>MAX_SOURCES:return false
	for key:Variant in value:
		var source:Variant=value[key]
		if not key is String or not source is Array or source.size()!=2 or not source[0] is String or not source[1] is bool:return false
		if source[0].is_empty() or key!=source[0]+("|flip_y" if source[1] else ""):return false
	return true

static func _header(path:String,root:String)->Dictionary:
	if root.is_empty() or not Paths.allowed(path,root):return {}
	var extension:=path.get_extension().to_lower()
	if extension not in ["png","jpg","jpeg"]:return {}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {}
	var length:int=file.get_length()
	if length<8 or length>MAX_SOURCE_BYTES:return {}
	var header:=Headers._image_header(file,0,length,"image/png" if extension=="png" else "image/jpeg")
	# Only 8-bit LDR inputs: float/16-bit codecs need a separate allocation proof.
	if header.is_empty() or header.pixel_bytes!=4 or header.width>4096 or header.height>4096:return {}
	return {"width":header.width,"height":header.height,"source_bytes":length,"extension":extension}

static func estimate(requested:Dictionary,root:String)->Dictionary:
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return {"rows":{},"estimated_bytes":0,"output_bytes":0}
	var rows:Dictionary={};var output:=0;var scratch:=0
	if not valid_sources(requested):return {"rows":{},"estimated_bytes":0,"output_bytes":0}
	var keys:Array=requested.keys();keys.sort()
	for key:String in keys:
		var source:Array=requested[key];var row:=_header(source[0],root)
		if row.is_empty():continue
		var pixels:int=Headers._mip_bytes(row.width,row.height,4)
		if output+pixels>MAX_OUTPUT_BYTES:continue
		row.path=source[0];row.flip=source[1];row.output_bytes=pixels
		# Cache reads reject larger envelopes BEFORE reading/Variant decoding.
		# Three envelopes cover bytes_to_var/copies; four pixel buffers cover
		# decompression, Image allocation, normal flip and RGB upload conversion.
		row.cache_limit=mini(134217760,maxi(pixels*2+65536,row.source_bytes*2+65536))
		rows[key]=row;output+=pixels
		scratch=maxi(scratch,row.cache_limit*3+pixels*4+row.source_bytes*2+4*1024*1024)
	# Retained CPU pixels plus eventual upload/staging; sequential preparation
	# uses only one decoder/cache workspace, not one workspace per texture.
	return {"rows":rows,"estimated_bytes":output*2+scratch,"output_bytes":output}

static func _cancelled(token:RefCounted)->bool:return token!=null and token.is_cancelled()

static func _fail(reason:String,cancelled:bool=false)->Dictionary:
	return {"error":reason,"cancelled":cancelled,"images":{},"sources":{},"profile":{}}

static func _digest(bytes:PackedByteArray)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes);return context.finish().hex_encode()

static func _cached(row:Dictionary,digest:String)->Image:
	var file:=FileAccess.open(Pixels.cache_path(row.path,row.flip),FileAccess.READ)
	if file==null or file.get_length()<=32 or file.get_length()>int(row.cache_limit):return null
	var expected:=file.get_buffer(32);var payload:=file.get_buffer(file.get_length()-32);file.close()
	if Pixels.Envelope.checksum(payload)!=expected:return null
	var data:Variant=bytes_to_var(payload)
	var version:int=3 if Pixels.upload_preparation_enabled else 1
	if not data is Dictionary or data.get("version")!=version or data.get("source")!=digest or not data.get("pixels") is PackedByteArray:return null
	if not Pixels.valid_pixels(data) or data.width!=row.width or data.height!=row.height or data.size>row.output_bytes:return null
	if data.format not in [Image.FORMAT_L8,Image.FORMAT_LA8,Image.FORMAT_R8,Image.FORMAT_RG8,Image.FORMAT_RGB8,Image.FORMAT_RGBA8]:return null
	if version==3 and not data.get("has_alpha") is bool:return null
	var raw:PackedByteArray=data.pixels.decompress(data.size,FileAccess.COMPRESSION_FASTLZ)
	if raw.size()!=data.size:return null
	var image:=Image.create_from_data(data.width,data.height,true,data.format,raw)
	if version==3:image.set_meta("runtime_upload_has_alpha",data.has_alpha)
	return image

static func _decode(row:Dictionary,bytes:PackedByteArray)->Image:
	if not _snapshot_matches(row,bytes):return null
	var image:=Image.new()
	var error:int=image.load_png_from_buffer(bytes) if row.extension=="png" else image.load_jpg_from_buffer(bytes)
	if error!=OK or image.is_empty() or image.get_width()!=row.width or image.get_height()!=row.height:return null
	if row.flip:
		image.convert(Image.FORMAT_RGBA8)
		var raw:=image.get_data()
		for at:int in range(1,raw.size(),4):raw[at]=255-raw[at]
		image=Image.create_from_data(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8,raw)
	if image.generate_mipmaps()!=OK:return null
	return image

static func _stage(profile:Dictionary,name:String,began:int,details:Dictionary={})->void:
	profile[name+"_us"]=int(profile.get(name+"_us",0))+Time.get_ticks_usec()-began
	Trace.elapsed("prefab_pixels."+name,began,details)

static func _authorize_cache(path:String,digest:String,root:String,token:RefCounted,profile:Dictionary)->bool:
	var began:=Time.get_ticks_usec()
	var valid:bool=not _cancelled(token) and Paths.allowed(path,root) and FileAccess.get_sha256(path)==digest and Paths.allowed(path,root) and not _cancelled(token)
	_stage(profile,"persist_source_sha",began,{"path":path,"valid":valid})
	return valid

static func _source_sha(path:String,root:String,token:RefCounted)->String:
	if _cancelled(token) or not Paths.allowed(path,root):return ""
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>MAX_SOURCE_BYTES:return ""
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
	var left:int=file.get_length()
	while left>0:
		if _cancelled(token):return ""
		var bytes:=file.get_buffer(mini(left,4*1024*1024))
		if bytes.is_empty():return ""
		context.update(bytes);left-=bytes.size()
	return context.finish().hex_encode() if Paths.allowed(path,root) else ""

static func _retry(reason:String,revisions:Dictionary={})->Dictionary:
	var result:=_fail(reason);result.retry_pixels=true;result.source_revisions=revisions.duplicate();return result

static func _snapshot_matches(row:Dictionary,bytes:PackedByteArray)->bool:
	# Validate dimensions from the SAME immutable bytes used by the codec. A
	# filesystem header recheck alone has a resize race before Image allocation.
	if row.extension=="png":
		return bytes.size()>=33 and bytes.slice(0,8)==PackedByteArray([137,80,78,71,13,10,26,10]) and Headers._be32(bytes,8)==13 and bytes.slice(12,16).get_string_from_ascii()=="IHDR" and Headers._be32(bytes,16)==row.width and Headers._be32(bytes,20)==row.height and bytes[24]<=8
	if bytes.size()<4 or bytes[0]!=255 or bytes[1]!=216:return false
	var at:=2;var end:=mini(bytes.size(),Headers.MAX_HEADER)
	for _segment in 1024:
		if at+2>end or bytes[at]!=255:return false
		at+=1;var marker:int=bytes[at];at+=1
		while marker==255 and at<end:marker=bytes[at];at+=1
		if marker in [0,216,217,218] or at+2>end:return false
		if marker==1 or (marker>=208 and marker<=215):continue
		var length:int=(int(bytes[at])<<8)|bytes[at+1]
		if length<2 or length>end-at:return false
		if marker in [192,193,194]:
			if length<8:return false
			return bytes[at+2]==8 and ((int(bytes[at+3])<<8)|bytes[at+4])==row.height and ((int(bytes[at+5])<<8)|bytes[at+6])==row.width
		at+=length
	return false

static func prepare(requested:Dictionary,plan:Dictionary,root:String,token:RefCounted=null,verify_at_end:bool=true,shared:Dictionary={})->Dictionary:
	var began:=Time.get_ticks_usec()
	var profile:Dictionary={"cache_hits":0,"decoded":0,"cache_writes":0,"cache_write_skips":0}
	if _cancelled(token):return _fail("Prefab texture preparation cancelled",true)
	if not valid_sources(requested) or not plan.get("rows") is Dictionary:return _fail("Invalid prefab texture preparation plan")
	# Recompute header bounds before allocation. A source resized after admission
	# cannot silently exceed that immutable reservation or fall back on this worker.
	var mark:=Time.get_ticks_usec();var actual:=estimate(requested,root)
	_stage(profile,"header",mark,{"sources":requested.size(),"images":plan.rows.size()})
	if actual!=plan:return _retry("Prefab texture dimensions changed after admission") if not shared.is_empty() else _fail("Prefab texture dimensions changed after admission")
	var images:Dictionary={};var identities:Dictionary={};var cache_hits:=0;var decoded:=0;var output:=0;var waiting:=false
	for key:String in plan.rows:
		if _cancelled(token):return _fail("Prefab texture preparation cancelled",true)
		var row:Dictionary=plan.rows[key]
		mark=Time.get_ticks_usec()
		if not shared.is_empty() and (shared.cached.has(key) or not shared.leaders.has(key)):
			var digest:String=identities.get(row.path,"")
			if digest.is_empty():digest=_source_sha(row.path,root,token)
			_stage(profile,"read_sha",mark,{"path":row.path,"streamed":true})
			if digest.is_empty():return _fail("Unable to verify shared prefab texture",_cancelled(token))
			identities[row.path]=digest
			if shared.cached.has(key):
				if digest!=shared.cached[key]:return _retry("Resident prefab texture source changed",identities)
				profile.resident_hits=int(profile.get("resident_hits",0))+1;continue
			mark=Time.get_ticks_usec()
			var fetched:Dictionary=shared.pool.fetch(shared.consumer,key,digest,token)
			_stage(profile,"shared_wait",mark,{"path":row.path})
			if not fetched.error.is_empty():return _retry(fetched.error,identities) if fetched.get("retry_pixels",false) else _fail(fetched.error,fetched.get("cancelled",false))
			if fetched.get("pending",false):waiting=true;continue
			images[key]=fetched.image;output+=fetched.image.get_data_size();profile.shared_hits=int(profile.get("shared_hits",0))+1;continue
		if not Paths.allowed(row.path,root):return _fail("Prefab texture path changed")
		var file:=FileAccess.open(row.path,FileAccess.READ)
		if file==null or file.get_length()!=row.source_bytes:return _fail("Prefab texture source changed")
		var bytes:=file.get_buffer(row.source_bytes);file.close()
		if bytes.size()!=row.source_bytes:return _fail("Incomplete prefab texture source")
		var digest:=_digest(bytes)
		_stage(profile,"read_sha",mark,{"path":row.path,"bytes":row.source_bytes})
		# Several orientations may share one source path. Bind its FIRST observed
		# digest so a replacement between variants cannot overwrite that proof.
		if identities.has(row.path) and identities[row.path]!=digest:return _fail("Prefab texture changed between prepared variants")
		mark=Time.get_ticks_usec();var image:=_cached(row,digest)
		_stage(profile,"cache_decode",mark,{"path":row.path,"hit":image!=null})
		if image==null:
			mark=Time.get_ticks_usec();image=_decode(row,bytes);decoded+=1
			_stage(profile,"source_decode",mark,{"path":row.path,"flip":row.flip})
			if image!=null:
				mark=Time.get_ticks_usec()
				# A complete source proof gates the atomic rename. The ordinary final
				# proof below/at Chunk handoff remains mandatory after all preparation.
				var wrote:=Pixels.store_pixels(row.path,row.flip,image,digest,row.cache_limit,_authorize_cache.bind(row.path,digest,root,token,profile))
				profile["cache_writes" if wrote else "cache_write_skips"]+=1
				_stage(profile,"cache_encode_write",mark,{"path":row.path,"written":wrote})
		else:cache_hits+=1
		if image==null:return _fail("Unable to prepare prefab texture: "+row.path)
		mark=Time.get_ticks_usec()
		if Pixels.upload_preparation_enabled:Pixels.prepare_upload(image)
		_stage(profile,"upload_prepare",mark,{"path":row.path})
		if image.get_data_size()>row.output_bytes:return _fail("Prefab texture output exceeds its admitted bound")
		image.set_meta("runtime_source_sha256",digest)
		if not shared.is_empty() and not shared.pool.publish(shared.consumer,key,digest,image):return _fail("Shared prefab image producer cancelled",true)
		images[key]=image;identities[row.path]=digest;output+=image.get_data_size()
	profile.merge({"elapsed_us":Time.get_ticks_usec()-began,"cache_hits":cache_hits,"decoded":decoded,"images":images.size(),"output_bytes":output,"estimated_bytes":plan.estimated_bytes},true)
	var result:Dictionary={"error":"","cancelled":false,"images":images,"sources":identities,"profile":profile,"waiting_pixels":waiting}
	if verify_at_end and not verify(result,root,token):return _fail("Prefab texture source changed or preparation cancelled",_cancelled(token))
	profile.elapsed_us=Time.get_ticks_usec()-began
	return result

static func verify(packet:Dictionary,root:String,token:RefCounted=null)->bool:
	var began:=Time.get_ticks_usec();var valid:=true
	for path:String in packet.get("sources",{}):
		if _cancelled(token) or not Paths.allowed(path,root):valid=false;break
		if FileAccess.get_sha256(path)!=packet.sources[path] or not Paths.allowed(path,root):valid=false;break
	valid=valid and not _cancelled(token)
	if not packet.has("profile"):packet.profile={}
	_stage(packet.profile,"final_sha",began,{"sources":packet.get("sources",{}).size(),"valid":valid})
	return valid
