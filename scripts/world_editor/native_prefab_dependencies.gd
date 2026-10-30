extends RefCounted
## Immutable pack-local registrations, sharing the same root's native products.
## No scene, image, GLB import, texture table read or pixel copy is performed.
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")

static func _envelope(body:Dictionary)->String:
	var encoded:=JSON.stringify(body,"",true,true)
	return JSON.stringify({"version":1,"body":encoded,"sha256":encoded.sha256_text()},"",true,true)

static func capture(source:String,directory:String,processed:Dictionary)->Dictionary:
	source=source.replace("\\","/").simplify_path()
	if processed.has(source):return processed[source]
	var root:=Paths.external_root();var descriptor:Dictionary={};var index:Dictionary={}
	var candidate:=Footprint.candidate(source,root,"",true,"",descriptor,null,index)
	if candidate.is_empty():return {"ok":false,"error":"预制件模型缺少原生产物："+source}
	var building:Variant=null
	if FileAccess.file_exists(Footprint.building_descriptor_path(source,root)):
		building=Footprint._building_metadata(source,root,candidate)
		if building.is_empty():return {"ok":false,"error":"预制件模型建筑合同损坏："+source}
	# Include all validated registration and footprint fields, including budget,
	# collision/reuse proofs and optional building versions. Only location changes.
	descriptor.source_path="model.glb"
	var snapshot:={"version":1,"index":index,"footprint":descriptor,"building":building}
	var identity:=JSON.stringify(snapshot,"",true,true).sha256_text()
	var parent:=directory.path_join("native_models_v1")
	var target:=parent.path_join(identity)
	if not Paths.allowed_many([parent,target],root):return {"ok":false,"error":"预制件原生登记目录无效"}
	var files:={"index.json":JSON.stringify(index,"",true,true),"footprint.json":_envelope(descriptor)}
	if building!=null:files["building.json"]=_envelope(building)
	for name:String in files:
		var maximum:int=8192 if name=="index.json" else (Footprint.MAX_DESCRIPTOR_BYTES if name=="footprint.json" else Footprint.BUILDING_DESCRIPTOR_MAX_BYTES)
		if str(files[name]).to_utf8_buffer().size()>maximum:return {"ok":false,"error":"预制件原生登记超过读取合同限制"}
	if DirAccess.dir_exists_absolute(target):
		if not _same(target,files,root):return {"ok":false,"error":"已有预制件原生登记与内容身份不一致"}
	else:
		var staged:=parent.path_join("staging_%d_%d_%d"%[OS.get_process_id(),OS.get_thread_caller_id(),Time.get_ticks_usec()])
		if not Paths.allowed(staged,root) or DirAccess.make_dir_recursive_absolute(staged)!=OK:return {"ok":false,"error":"预制件原生登记暂存失败"}
		var error:Error=OK
		for name:String in files:
			var file:=FileAccess.open(staged.path_join(name),FileAccess.WRITE)
			if file==null:error=FileAccess.get_open_error();break
			file.store_string(files[name]);file.flush();error=file.get_error();file.close()
			if error!=OK:break
		# Publish the complete directory in one rename. A populated immutable
		# destination cannot be replaced by directory rename on supported systems.
		if error==OK:error=DirAccess.rename_absolute(staged,target)
		if error!=OK and DirAccess.dir_exists_absolute(target) and _same(target,files,root):error=OK
		_cleanup(staged,files,root)
		if error!=OK:return {"ok":false,"error":"预制件原生登记发布失败："+error_string(error)}
	var result:={"ok":true,"path":target.path_join("model.glb")}
	processed[source]=result;return result

static func _same(folder:String,files:Dictionary,root:String)->bool:
	for name:String in files:
		var path:=folder.path_join(name)
		if not Paths.allowed(path,root):return false
		var file:=FileAccess.open(path,FileAccess.READ)
		if file==null or file.get_length()!=str(files[name]).to_utf8_buffer().size():return false
		var value:=file.get_as_text();file.close()
		if value!=files[name]:return false
	return not FileAccess.file_exists(folder.path_join("building.json")) or files.has("building.json")

static func _cleanup(folder:String,files:Dictionary,root:String)->void:
	if not Paths.allowed(folder,root):return
	for name:String in files:
		var path:=folder.path_join(name)
		if Paths.allowed(path,root) and FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder) # Owned empty staging directory only.
