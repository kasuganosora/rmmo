extends RefCounted
const D=preload("res://scripts/world3d/bridge_data.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var directory:=Paths.cache_directory("bridge_prefabs")
func entries() -> Array:
	var out:=D.presets()
	if not Paths.allowed(directory): return out
	var dir:=DirAccess.open(directory)
	if dir==null: return out
	for file in dir.get_files():
		var path:=directory.path_join(file)
		if not file.ends_with(".json") or not Paths.allowed(path): continue
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if value is Dictionary and valid(value): out.append(value)
	return out
static func valid(value: Dictionary) -> bool:
	if value.get("format")!="rmmo_bridge_prefab" or value.get("version")!=1 or not value.get("id") is String or not value.get("name") is String: return false
	if not value.get("materials",{}) is Dictionary or not D.S.validate(value.get("recipe"),D.recipe_schema()).is_empty(): return false
	if value.has("asset_path") and (not value.asset_path is String or not Paths.allowed(value.asset_path) or not FileAccess.file_exists(value.asset_path)): return false
	for key in value.get("materials",{}):
		if key not in ["deck","masonry","trim"] or not Paint.material_valid(value.materials[key]): return false
	return Paint.missing([{"bridge_materials":value.get("materials",{})}]).is_empty()
func find(id: String) -> Dictionary:
	for entry in entries():
		if entry.id==id: return entry.duplicate(true)
	return {}
func save(record: Dictionary,label: String) -> Dictionary:
	if not D.valid(record) or not record.has("bridge_mesh") or label.strip_edges().is_empty() or label.length()>120: return {"ok":false,"error":"请选择程序桥梁并填写名称（最多 120 字）"}
	var value:={"format":"rmmo_bridge_prefab","version":1,"name":label.strip_edges(),"recipe":record.bridge_mesh.recipe.duplicate(true),"materials":record.get("bridge_materials",{}).duplicate(true)}
	value.asset_path=record.asset_path
	value.id="custom_"+JSON.stringify(value,"",true).sha256_text(); value.description="自定义桥型 · 放置时按跨度重新排列拱孔"
	var path:=directory.path_join(value.id+".json")
	if not valid(value) or not Paths.allowed(path): return {"ok":false,"error":"桥型依赖缺失或目录无效"}
	var err:=DirAccess.make_dir_recursive_absolute(directory)
	if err==OK and not FileAccess.file_exists(path): err=preload("res://scripts/world_editor/surface_material_library.gd")._write(path,JSON.stringify(value,"\t").to_utf8_buffer())
	return {"ok":true,"prefab":value} if err==OK else {"ok":false,"error":"桥型写入失败"}
