extends RefCounted
## Shared model-library import and transactional relink for UI/current 3D MCP.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Catalog=preload("res://scripts/world_editor/resource_pack_catalog.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Thumbnails=preload("res://scripts/world_editor/asset_thumbnails.gd")

static func fail(message:String)->Dictionary:return {"ok":false,"error":message}

static func source_scope_issue(path:String)->String:
	# This is the MCP file-access boundary, not a second geometry validator.
	if not Paths.allowed(path):return "模型源文件不在允许的资源根内"
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return "模型源文件不存在或无法读取"
	var raw:Variant
	if path.get_extension().to_lower()=="glb":
		if file.get_length()<20 or file.get_32()!=0x46546c67 or file.get_32()!=2:return "GLB 文件头无效"
		var length:=file.get_32();var json_length:=file.get_32()
		if file.get_32()!=0x4e4f534a or length!=file.get_length() or json_length>length-20:return "GLB JSON 区段无效"
		raw=JSON.parse_string(file.get_buffer(json_length).get_string_from_utf8())
	elif path.get_extension().to_lower()=="gltf":raw=JSON.parse_string(file.get_as_text())
	else:return "只支持 GLB / glTF 模型源文件"
	file.close()
	if not raw is Dictionary:return "模型 JSON 无效"
	var pending:Array=[raw]
	while not pending.is_empty():
		var value:Variant=pending.pop_back()
		if value is Array:pending.append_array(value)
		elif value is Dictionary:
			for key:Variant in value:
				if key=="uri":
					if not value[key] is String:return "模型依赖 URI 无效"
					var uri:String=value[key]
					if uri.begins_with("data:"):continue
					var relative:=Io.decode_dependency_uri(uri)
					if relative.is_empty() or not Paths.allowed(path.get_base_dir().path_join(relative)):return "模型依赖不在允许的资源根内"
				elif value[key] is Dictionary or value[key] is Array:pending.append(value[key])
	return ""

static func import_model(editor:Node3D,path:String,pack_root:String,external_source:bool=false,select_imported:bool=false)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	if DisplayServer.get_name()=="headless":return fail("模型导入需要图形编辑器")
	var destination:=pack_root.path_join("assets")
	if not Paths.allowed(pack_root) or not Catalog.new().packs().any(func(pack):return str(pack.root)==pack_root):return fail("请选择 list_resource_packs 返回的资源包")
	for output:String in [destination,destination.path_join("library.json"),destination.path_join("thumbnails")]:
		if not Paths.allowed(output):return fail("素材库路径超出允许的资源根")
	if not external_source:
		var issue:=source_scope_issue(path)
		if not issue.is_empty():return fail(issue)
	var library:=Library.new(destination)
	var result:=library.import_file(path)
	if not result.get("ok",false):return result
	if select_imported:editor._asset_pack_root=pack_root
	if editor._asset_pack_root==pack_root:editor._assets=library
	editor._shared_assets=editor._shared_assets.filter(func(old):return old.directory!=destination)
	if editor._asset_pack_root!=pack_root:editor._shared_assets.append(library)
	if select_imported:editor._query="";editor._asset_category=""
	editor._refresh_palette()
	if select_imported:
		var entries:Array=editor._library_items()
		for index in entries.size():
			if entries[index].get("asset_path")==result.entry.asset_path:editor._pick=index;break
		editor._refresh_palette()
	editor._thumbnails.queue_import(result.entry)
	result.asset_id=Thumbnails.key_for(result.entry)
	return result

static func relink_model(editor:Node3D,id:String,asset_id:String)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	var record:Dictionary=editor._doc._find(id)
	if record.get("kind")!="asset" or not editor._record_editable(record):return fail("请选择可编辑的模型物件")
	if record.has("house_prefab") or record.has("bridge_mesh") or record.has("baked_house_member"):return fail("生成结构请使用对应房屋、桥梁或组件编辑工具")
	var entries:Array=editor.asset_items().filter(func(entry):return Thumbnails.key_for(entry)==asset_id)
	if entries.is_empty() or not entries[0].has("asset_path"):return fail("请选择素材库中的原生模型")
	var entry:Dictionary=entries[0]
	if not Library.native_available(str(entry.asset_path)):return fail("模型缺少完整原生产物，请重新导入")
	var next:=record.duplicate(true)
	next.erase("model_building")
	next.merge(entry,true)
	return editor._replace_records({id:next},[],null,{"ok":true,"id":id,"asset_id":asset_id})
