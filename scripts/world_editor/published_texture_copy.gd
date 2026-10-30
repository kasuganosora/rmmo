extends RefCounted
## Portable texture closure. Preserve encoded mip products and variant identity;
## copying only PNG silently discards alpha coverage and streaming on placement.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Streamed=preload("res://scripts/world3d/streamed_texture_source.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
static func capture(source:String,directory:String,root:String)->Dictionary:
	if not Paths.allowed(source,root) or not Paths.allowed(directory,root):return _fail()
	var copies:Dictionary={};var signature:Array=[]
	for normal:bool in [false,true]:
		for flip:bool in ([false,true] if normal else [false]):
			for compressed:bool in [false,true]:
				var descriptor:=Streamed.descriptor_path(source,flip,normal,compressed)
				if not FileAccess.file_exists(descriptor):continue
				if not Paths.allowed(descriptor,root):return _fail()
				var file:=FileAccess.open(descriptor,FileAccess.READ)
				if file==null or file.get_length()>4096:return _fail()
				var bytes:=file.get_buffer(file.get_length());file.close()
				var data:Variant=JSON.parse_string(bytes.get_string_from_utf8())
				if not data is Dictionary or not data.get("file") is String:return _fail()
				var name:String=data.file
				if name!=name.get_file() or not name.ends_with(".stex"):return _fail()
				copies[descriptor]=[true,descriptor.trim_prefix(source)]
				copies[source.get_base_dir().path_join(name)]=[false,name]
				signature.append([descriptor.trim_prefix(source),bytes.hex_encode().sha256_text()])
	for suffix:String in [".dxt1.dds",".dxt5.dds",".bc5.dds",".flip.dxt1.dds",".flip.dxt5.dds",".flip.bc5.dds"]:
		if not FileAccess.file_exists(source+suffix):continue
		copies[source+suffix]=[true,suffix]
		if FileAccess.file_exists(source+suffix+".source.json"):
			copies[source+suffix+".source.json"]=[true,suffix+".source.json"]
			signature.append([suffix,FileAccess.get_sha256(source+suffix+".source.json")])
	var digest:=FileAccess.get_sha256(source)
	if digest.is_empty():return _fail()
	var folder:=directory.path_join(JSON.stringify([digest,signature]).sha256_text())
	var name:=digest+(".source" if source.get_file().get_basename().ends_with(".source") else "")+"."+source.get_extension().to_lower()
	var target:=folder.path_join(name)
	if not Paths.allowed(target,root) or DirAccess.make_dir_recursive_absolute(folder)!=OK:return _fail()
	# Publish immutable payloads before their descriptors/reference. Native file
	# copying avoids retaining complete STEX/DDS byte arrays on the scene thread.
	for descriptors:bool in [false,true]:
		for input:String in copies:
			if input.ends_with(".json")!=descriptors:continue
			var destination:String=target+copies[input][1] if copies[input][0] else folder.path_join(copies[input][1])
			if not _copy(input,destination,root):return _fail()
	if not _copy(source,target,root):return _fail()
	return {"ok":true,"path":target}

static func _copy(source:String,target:String,root:String)->bool:
	if not Paths.allowed(source,root) or not Paths.allowed(target,root):return false
	if FileAccess.file_exists(target):return true
	var staging:=target+".copy-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	if not Paths.allowed(staging,root):return false
	var error:=DirAccess.copy_absolute(source,staging)
	if error==OK:error=Atomic.publish_new(staging,target)
	if FileAccess.file_exists(staging):DirAccess.remove_absolute(staging)
	return error in [OK,ERR_ALREADY_EXISTS]
static func _fail()->Dictionary:return {"ok":false,"error":"预制件贴图及流式产物打包失败"}
