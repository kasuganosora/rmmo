extends RefCounted
## CPU-only surface material import. The caller owns the thread, admission
## lease and cancellation token. A per-call CPU encoder is required; older
## engines without that API explicitly keep PNG instead of touching the global
## compression setting or invoking the GPU backend from a worker.
## prepare() may be shared by subscribers after canonical PNG identity is known.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const DDS=preload("res://scripts/world3d/compressed_texture_source.gd")
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
# Image::MAX_PIXELS is not exposed to GDScript in this engine version.
# The width and height constants are exposed; this pixel bound comes from the
# corresponding Image implementation, rather than an authoring policy.
const IMAGE_MAX_PIXELS:=268435456
const INT64_MAX:=9223372036854775807

# Probe only headers before admission; the same parser runs on the private
# byte snapshot immediately before decoding, so a changed source cannot make
# a small reservation cover a larger image.
static func _read_file(offset:int,count:int,file:FileAccess)->PackedByteArray:
	file.seek(offset);return file.get_buffer(count)
static func _read_bytes(offset:int,count:int,bytes:PackedByteArray)->PackedByteArray:
	return bytes.slice(offset,offset+count)
static func _be32(bytes:PackedByteArray,at:int)->int:
	return (int(bytes[at])<<24)|(int(bytes[at+1])<<16)|(int(bytes[at+2])<<8)|int(bytes[at+3])
static func _le24(bytes:PackedByteArray,at:int)->int:
	return int(bytes[at])|(int(bytes[at+1])<<8)|(int(bytes[at+2])<<16)
static func _dimensions(width:int,height:int)->Dictionary:
	if width<1 or height<1 or width>Image.MAX_WIDTH or height>Image.MAX_HEIGHT or width>IMAGE_MAX_PIXELS/height:return {}
	return {"width":width,"height":height}

static func _workspace(width:int,height:int,source_bytes:int)->Dictionary:
	# PNG's simplified decoder produces at most RGBA8, including 16-bit input.
	# The writer duplicates the image and preallocates PNG_IMAGE_PNG_SIZE_MAX:
	# raw rows, zlib's documented bound and IDAT chunk overhead. Charge a second
	# result buffer for allocator growth and keep source / pixels / encoded packet
	# until their actual last owner has retired. JPEG/WebP decoder workspace and
	# allocator/driver overhead are not RSS guarantees; the fixed allowance is
	# diagnostic headroom, not a per-asset eligibility limit.
	if _dimensions(width,height).is_empty() or source_bytes<1:return {}
	var raw:=width*height*4
	var rows:=raw+height
	var compressed:=rows+((rows+7)>>3)+((rows+63)>>6)+11
	var png_bound:=compressed+12*(compressed/8192)+128
	var mip:=0;var w:=width;var h:=height
	while true:
		mip+=w*h*4
		if w==1 and h==1:break
		w=maxi(1,w>>1);h=maxi(1,h>>1)
	# BC3 is the larger of the supported outputs. Count partial 4x4 blocks.
	var blocks:=0;w=width;h=height
	while true:
		blocks+=maxi(1,(w+3)/4)*maxi(1,(h+3)/4)*16
		if w==1 and h==1:break
		w=maxi(1,w>>1);h=maxi(1,h>>1)
	var fixed:=4*1024*1024
	var other:=maxi(raw*2+png_bound*2,mip*2+blocks*2+raw+png_bound*2)+fixed
	if source_bytes>(INT64_MAX-other)/2:return {}
	return {"estimated_bytes":source_bytes*2+other,"decoded_bytes":raw,"mip_bytes":mip,"png_bound_bytes":png_bound,"bc3_bytes":blocks}
static func _image_dimensions(read:Callable,length:int,extension:String)->Dictionary:
	if length<12:return {}
	var head:PackedByteArray=read.call(0,mini(length,32))
	if extension=="png":
		if head.size()<24 or head.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]) or head.slice(12,16).get_string_from_ascii()!="IHDR":return {}
		return _dimensions(_be32(head,16),_be32(head,20))
	if extension in ["jpg","jpeg"]:
		if head[0]!=255 or head[1]!=216:return {}
		var at:=2
		while at+4<=length:
			var marker:PackedByteArray=read.call(at,2)
			if marker.size()!=2 or marker[0]!=255:return {}
			at+=2
			while marker[1]==255 and at<length:
				var next:PackedByteArray=read.call(at,1)
				if next.size()!=1:return {}
				marker[1]=next[0];at+=1
			var code:=int(marker[1])
			if code in [0,216,217,218]:return {}
			if code==1 or (code>=208 and code<=215):continue
			var size_bytes:PackedByteArray=read.call(at,2)
			if size_bytes.size()!=2:return {}
			var size:=(int(size_bytes[0])<<8)|int(size_bytes[1])
			if size<2 or at+size>length:return {}
			if code in [192,193,194,195,197,198,199,201,202,203,205,206,207]:
				var data:PackedByteArray=read.call(at+2,5)
				if size<7 or data.size()!=5:return {}
				return _dimensions((int(data[3])<<8)|int(data[4]),(int(data[1])<<8)|int(data[2]))
			at+=size
		return {}
	if extension=="webp":
		if head.slice(0,4).get_string_from_ascii()!="RIFF" or head.slice(8,12).get_string_from_ascii()!="WEBP":return {}
		var at:=12
		while at+8<=length:
			var chunk:PackedByteArray=read.call(at,8)
			if chunk.size()!=8:return {}
			var tag:=chunk.slice(0,4).get_string_from_ascii();var size:=int(chunk.decode_u32(4));at+=8
			if size>length-at:return {}
			var data:PackedByteArray=read.call(at,mini(size,10))
			if tag=="VP8X" and data.size()>=10:return _dimensions(_le24(data,4)+1,_le24(data,7)+1)
			if tag=="VP8L" and data.size()>=5 and data[0]==47:
				var bits:=int(data.decode_u32(1));return _dimensions((bits&16383)+1,((bits>>14)&16383)+1)
			if tag=="VP8 " and data.size()>=10 and data.slice(3,6)==PackedByteArray([157,1,42]):
				return _dimensions(int(data.decode_u16(6))&16383,int(data.decode_u16(8))&16383)
			at+=size+(size&1)
	return {}

static func probe(path:String,directory:String,token:RefCounted,root:String="")->Dictionary:
	if OS.get_thread_caller_id()==OS.get_main_thread_id():return _fail("贴图导入必须在后台执行")
	if root.is_empty():root=Paths.external_root()
	var extension:=path.get_extension().to_lower()
	if _cancelled(token) or not Paths.allowed(path,root) or not Paths.allowed(directory,root) or extension not in ["png","jpg","jpeg","webp"]:return _fail("贴图路径无效或导入已取消")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return _fail("贴图文件不可读")
	var length:=file.get_length()
	if length<=0:return _fail("贴图文件不可读或为空")
	var dimensions:=_image_dimensions(_read_file.bind(file),length,extension)
	if dimensions.is_empty():return _fail("贴图头部无效或超过引擎图像尺寸范围")
	var workspace:=_workspace(dimensions.width,dimensions.height,length)
	if workspace.is_empty():return _fail("贴图工作量超出可表示范围")
	dimensions.merge(workspace)
	dimensions.source_bytes=length;dimensions.ok=true
	return dimensions

static func _cancelled(token:RefCounted)->bool:
	return token!=null and token.is_cancelled()

static func _fail(message:String)->Dictionary:
	return {"ok":false,"error":message}

static func _digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	return hash.finish().hex_encode()

static func _decode(bytes:PackedByteArray,extension:String)->Image:
	var image:=Image.new();var error:=ERR_FILE_UNRECOGNIZED
	match extension:
		"png":error=image.load_png_from_buffer(bytes)
		"jpg","jpeg":error=image.load_jpg_from_buffer(bytes)
		"webp":error=image.load_webp_from_buffer(bytes)
	if error!=OK or image.is_empty() or _dimensions(image.get_width(),image.get_height()).is_empty():return null
	return image

## Encoder is optional injection for CPU contract testing; the normal path uses
## the engine's editor-only S3TC encoder. Empty output means PNG fallback.
static func encode_dds(image:Image,encoder:Callable=Callable())->Dictionary:
	var width:=image.get_width();var height:=image.get_height()
	if width%4!=0 or height%4!=0:return {"ok":false,"reason":"dimensions_not_multiple_of_four"}
	var alpha:=image.detect_alpha()!=Image.ALPHA_NONE
	var candidate:=image.duplicate() as Image
	if candidate.generate_mipmaps()!=OK:return {"ok":false,"reason":"mipmap_failed"}
	var channels:=Image.USED_CHANNELS_RGBA if alpha else Image.USED_CHANNELS_RGB
	var error:int=ERR_UNAVAILABLE
	if encoder.is_valid():error=encoder.call(candidate,channels)
	elif candidate.has_method("compress_from_channels_cpu"):
		error=candidate.call("compress_from_channels_cpu",Image.COMPRESS_S3TC,channels)
	if error!=OK:return {"ok":false,"reason":"encoder_unavailable_or_failed"}
	var expected:=Image.FORMAT_DXT5 if alpha else Image.FORMAT_DXT1
	if candidate.get_format()!=expected or candidate.get_width()!=width or candidate.get_height()!=height:return {"ok":false,"reason":"unsupported_encoder_output"}
	var bytes:=candidate.save_dds_to_buffer()
	var info:=DDS._header(bytes,bytes.size(),false)
	if info.is_empty() or info.width!=width or info.height!=height or info.format!=expected:return {"ok":false,"reason":"invalid_dds_output"}
	return {"ok":true,"bytes":bytes,"image":candidate,"format":expected,"suffix":".dxt5.dds" if alpha else ".dxt1.dds"}

## Source bytes are read once. The content ID is the SHA of the canonical PNG,
## exactly matching the existing library naming and mutable DDS source schema.
static func prepare(path:String,directory:String,token:RefCounted,root:String="",expected:Dictionary={},read_observer:Callable=Callable())->Dictionary:
	if OS.get_thread_caller_id()==OS.get_main_thread_id():return _fail("贴图导入必须在后台执行")
	if root.is_empty():root=Paths.external_root()
	if _cancelled(token):return _fail("贴图导入已取消")
	var extension:=path.get_extension().to_lower()
	if not Paths.allowed(path,root) or not Paths.allowed(directory,root) or extension not in ["png","jpg","jpeg","webp"]:return _fail("请选择内容目录内的 PNG / JPEG / WebP 贴图")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return _fail("贴图文件不可读")
	var length:=file.get_length()
	if length<=0:return _fail("贴图文件不可读或为空")
	# Reject a changed byte envelope before allocating its buffer. Dimensions are
	# then checked against the exact captured bytes before decoder allocation.
	if not expected.is_empty() and int(expected.get("source_bytes",0))!=length:
		file.close();return {"ok":false,"error":"贴图在导入期间变化","retry_probe":true}
	if read_observer.is_valid():read_observer.call(length)
	var source:=file.get_buffer(length);file.close()
	if source.size()!=length:return _fail("贴图文件读取不完整")
	if _cancelled(token):return _fail("贴图导入已取消")
	var dimensions:=_image_dimensions(_read_bytes.bind(source),source.size(),extension)
	if dimensions.is_empty():return _fail("贴图头部无效或超过引擎图像尺寸范围")
	if not expected.is_empty() and (int(expected.get("width",0))!=dimensions.width or int(expected.get("height",0))!=dimensions.height or int(expected.get("source_bytes",0))!=length):
		return {"ok":false,"error":"贴图在导入期间变化","retry_probe":true}
	var image:=_decode(source,extension);source=PackedByteArray()
	if image==null or image.get_width()!=dimensions.width or image.get_height()!=dimensions.height:return _fail("贴图无效或解码尺寸与头部不一致")
	var png:=image.save_png_to_buffer()
	if png.is_empty():return _fail("贴图 PNG 编码失败")
	var content_id:=_digest(png)
	var texture_path:=directory.path_join(content_id+".png")
	if not Paths.allowed(texture_path,root) or not Paths.allowed(texture_path+".previous",root):return _fail("材质库路径无效")
	if _cancelled(token):return _fail("贴图导入已取消")
	# The caller retains this packet under its original lease until encoding and
	# publication finish. PNG and image are borrowed, not copied by phase two.
	return {"ok":true,"texture_path":texture_path,"content_id":content_id,"source_name":path.get_file().get_basename(),"png":png,"image":image}

static func encode_publish(prepared:Dictionary,token:RefCounted,root:String="",encoder:Callable=Callable(),writer:Callable=Callable(),retain_pixels:bool=false)->Dictionary:
	if OS.get_thread_caller_id()==OS.get_main_thread_id():return _fail("贴图导入必须在后台执行")
	if root.is_empty():root=Paths.external_root()
	if _cancelled(token):return _fail("贴图导入已取消")
	if not prepared.get("ok",false):return prepared
	var texture_path:=str(prepared.texture_path)
	var content_id:=str(prepared.content_id)
	var directory:=texture_path.get_base_dir()
	var png:PackedByteArray=prepared.png
	var image:Image=prepared.image
	if not Paths.allowed(texture_path,root) or not Paths.allowed(directory,root):return _fail("材质库路径无效")
	var error:=DirAccess.make_dir_recursive_absolute(directory)
	if error!=OK:return _fail("无法创建材质库")
	if FileAccess.file_exists(texture_path):
		# Only an explicit editor import may reach this collision. Compare the
		# already-owned canonical PNG without hashing or reopening the input.
		var existing_status:=_matches_existing(texture_path,png,token)
		if existing_status=="cancelled":return _fail("贴图导入已取消")
		if existing_status!="match":return _fail("已有材质贴图内容冲突，未覆盖原文件")
	else:
		error=_write(texture_path,png,writer)
		if error!=OK:return _fail("贴图写入失败："+error_string(error))
	# One content-addressed, disposable thumbnail shared by every label. It is
	# produced from this already decoded source, before its worker lease retires.
	# Failure is a cache miss, never a failed or partially published material.
	var thumb_path:=texture_path+".thumbnail.png"
	var thumb_metadata:=texture_path+".thumbnail.json"
	var source_mtime:=FileAccess.get_modified_time(texture_path)
	if Paths.allowed(thumb_path,root) and Paths.allowed(thumb_metadata,root) and not _thumbnail_current(thumb_path,thumb_metadata,content_id,png.size(),source_mtime) and not _cancelled(token):
		var thumbnail:=image.duplicate() as Image
		var factor:=minf(104.0/image.get_width(),64.0/image.get_height())
		thumbnail.resize(maxi(1,roundi(image.get_width()*factor)),maxi(1,roundi(image.get_height()*factor)),Image.INTERPOLATE_BILINEAR)
		var thumb_bytes:=thumbnail.save_png_to_buffer()
		if not thumb_bytes.is_empty() and not _cancelled(token) and Library._write(thumb_path,thumb_bytes)==OK:
			var source_file:=FileAccess.open(texture_path,FileAccess.READ)
			var source_unchanged:bool=source_file!=null and source_file.get_length()==png.size() and FileAccess.get_modified_time(texture_path)==source_mtime
			if source_file!=null:source_file.close()
			var thumb_identity:={"version":1,"source_sha256":content_id,"source_bytes":png.size(),"source_modified_time":source_mtime}
			if source_unchanged and not _cancelled(token):Library._write(thumb_metadata,JSON.stringify(thumb_identity).to_utf8_buffer())
	# Ordinary game/package reads never perform this explicit-import comparison.
	var result:={"ok":true,"texture_path":texture_path,"content_id":content_id,"source_name":str(prepared.source_name),"dds_ready":false,"dds_reason":""}
	if _cancelled(token):return _fail("贴图导入已取消")
	var expected:=Image.FORMAT_DXT5 if image.detect_alpha()!=Image.ALPHA_NONE else Image.FORMAT_DXT1
	var existing:=DDS.plan_mutable(texture_path,false,false,root,content_id)
	var existing_image:Image=DDS.read(existing) if not existing.is_empty() and existing.format==expected else null
	if existing_image!=null:
		result.dds_ready=true;result.dds_reused=true;result.dds_path=existing.sidecar;result.dds_sha=existing.mutable_dds_sha256
		if retain_pixels:result.prepared_image=_prepared_image(existing_image,content_id,"dds:"+str(result.dds_sha),expected==Image.FORMAT_DXT5)
		return result
	# Runtime's trusted reader selects any existing sidecar by name. Do not
	# advertise PNG fallback when an invalid old file could still be consumed.
	if not DDS.sidecar_path(texture_path,false,false).is_empty():return _fail("已有 DDS 副产物无效或身份不匹配，请先处理该副产物")
	var encoded:=encode_dds(image,encoder)
	if not encoded.ok:
		result.dds_reason=encoded.reason
		if retain_pixels:result.prepared_image=_prepared_image(image,content_id,"source",image.detect_alpha()!=Image.ALPHA_NONE)
		return result
	if _cancelled(token):return _fail("贴图导入已取消")
	var target:=texture_path+str(encoded.suffix);var identity_path:=target+".source.json"
	for value:String in [target,identity_path,target+".previous",identity_path+".previous"]:
		if not Paths.allowed(value,root):return _fail("材质库路径无效")
	var bytes:PackedByteArray=encoded.bytes
	var identity:={"version":1,"encoder_version":1,"source_sha256":content_id,"source_bytes":png.size(),"dds_sha256":_digest(bytes),"dds_bytes":bytes.size(),"normal":false,"flip":false}
	# This is a new content-addressed sidecar and the discovery check above
	# found no existing target. Publish its identity first: an interrupted write
	# before the DDS appears is an ordinary PNG cache miss. This avoids deleting
	# another process's concurrently published sidecar on an identity failure.
	error=_write(identity_path,JSON.stringify(identity).to_utf8_buffer(),writer)
	if error!=OK:
		if DDS.sidecar_path(texture_path,false,false).is_empty():
			result.dds_reason="dds_identity_write_failed"
			if retain_pixels:result.prepared_image=_prepared_image(image,content_id,"source",image.detect_alpha()!=Image.ALPHA_NONE)
			return result
		return _fail("DDS 身份写入失败且副产物状态不确定："+error_string(error))
	if _cancelled(token):return _fail("贴图导入已取消")
	error=_write(target,bytes,writer)
	if error!=OK:
		if DDS.sidecar_path(texture_path,false,false).is_empty():
			result.dds_reason="dds_write_failed"
			if retain_pixels:result.prepared_image=_prepared_image(image,content_id,"source",image.detect_alpha()!=Image.ALPHA_NONE)
			return result
		return _fail("DDS 写入失败且副产物状态不确定："+error_string(error))
	# The encoded in-memory DDS was checked before publishing, and the initial
	# sidecar discovery found no competing sibling. Do not reread it here.
	result.dds_ready=true;result.dds_reused=false;result.dds_path=target;result.dds_sha=identity.dds_sha256
	if retain_pixels:result.prepared_image=_prepared_image(encoded.image,content_id,"dds:"+str(result.dds_sha),expected==Image.FORMAT_DXT5)
	return result

static func _prepared_image(image:Image,source_sha:String,representation:String,alpha:bool)->Image:
	if image==null:return null
	if not image.is_compressed() and not image.has_mipmaps() and image.generate_mipmaps()!=OK:return null
	if not image.is_compressed():preload("res://scripts/world3d/runtime_texture_cache.gd").prepare_upload(image)
	image.set_meta("runtime_source_sha256",source_sha)
	image.set_meta("runtime_texture_representation",representation)
	image.set_meta("runtime_upload_has_alpha",alpha)
	return image

static func _thumbnail_current(path:String,metadata_path:String,source_sha:String,source_bytes:int,source_mtime:int)->bool:
	if not FileAccess.file_exists(path):return false
	var file:=FileAccess.open(metadata_path,FileAccess.READ)
	if file==null or file.get_length()<=0 or file.get_length()>2048:return false
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK:return false
	var value:Variant=parser.data
	return value is Dictionary and value.get("version")==1 and value.get("source_sha256")==source_sha and value.get("source_bytes")==source_bytes and value.get("source_modified_time")==source_mtime

static func _matches_existing(path:String,expected:PackedByteArray,token:RefCounted)->String:
	if _cancelled(token):return "cancelled"
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return "different"
	if file.get_length()!=expected.size():file.close();return "different"
	var at:=0
	while at<expected.size():
		if _cancelled(token):file.close();return "cancelled"
		var count:=mini(1024*1024,expected.size()-at)
		var actual:=file.get_buffer(count)
		if actual.size()!=count or actual!=expected.slice(at,at+count):file.close();return "different"
		at+=count
	if file.get_length()!=expected.size():file.close();return "different"
	file.close()
	return "cancelled" if _cancelled(token) else "match"

static func _write(path:String,bytes:PackedByteArray,writer:Callable)->Error:
	return writer.call(path,bytes) if writer.is_valid() else Library._write(path,bytes)

static func prepare_label(prepared:Dictionary,label:String,token:RefCounted,fallback_name:String="")->Dictionary:
	if OS.get_thread_caller_id()==OS.get_main_thread_id():return _fail("材质名称准备必须在后台执行")
	if _cancelled(token):return _fail("贴图导入已取消")
	var name:=label.strip_edges()
	if name.is_empty():name=fallback_name
	var id:=(str(prepared.content_id)+name).sha256_text()
	if _cancelled(token):return _fail("贴图导入已取消")
	# Return only the fixed-size identity. The original request owns the label;
	# no large normalized copy survives after this worker's lease is released.
	return {"ok":true,"material_id":id}

static func publish_material(prepared:Dictionary,label:String,token:RefCounted,root:String="",known_id:String="",fallback_name:String="")->Dictionary:
	if OS.get_thread_caller_id()==OS.get_main_thread_id():return _fail("贴图导入必须在后台执行")
	if root.is_empty():root=Paths.external_root()
	if _cancelled(token):return _fail("贴图导入已取消")
	if not prepared.get("ok",false):return prepared
	var texture_path:=str(prepared.texture_path)
	var name:=label.strip_edges()
	if name.is_empty():name=fallback_name if not known_id.is_empty() else str(prepared.source_name)
	var id:=known_id if not known_id.is_empty() else (str(prepared.content_id)+name).sha256_text()
	var metadata:=texture_path.get_base_dir().path_join(id+".json")
	if not Paths.allowed(metadata,root) or not Paths.allowed(metadata+".previous",root):return _fail("材质库路径无效")
	var material:={"name":name,"texture_path":texture_path.get_file(),"color":[1,1,1,1],"roughness":0.9}
	if _cancelled(token):return _fail("贴图导入已取消")
	# Cancellation and publication race through one short state transition.
	# Once claimed, cancellation reports that the atomic commit has begun; it
	# never waits for filesystem I/O on the scene thread.
	if token!=null and token.has_method("begin_commit") and not token.begin_commit():return _fail("贴图导入已取消")
	var error:=Library._write(metadata,JSON.stringify({"material":material}).to_utf8_buffer())
	if error!=OK:return _fail("材质写入失败："+error_string(error))
	material.texture_path=texture_path
	return {"ok":true,"material_id":id,"material":material,"dds_ready":prepared.dds_ready,"dds_reason":prepared.dds_reason,"dds_reused":prepared.get("dds_reused",false),"dds_sha":prepared.get("dds_sha","")}

static func run(path:String,directory:String,label:String,token:RefCounted,root:String="",encoder:Callable=Callable())->Dictionary:
	var prepared:=prepare(path,directory,token,root)
	if not prepared.get("ok",false):return prepared
	return publish_material(encode_publish(prepared,token,root,encoder),label,token,root)
