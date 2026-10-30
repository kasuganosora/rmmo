extends RefCounted
## Native templates used by record construction; contains no loading or owners.
const Kits=preload("res://scripts/world3d/auto_tile_kit.gd")

static func model(record:Dictionary)->bool:
	return record.get("kind")=="asset" and not record.has("house_prefab") and not record.has("bridge_mesh")

static func for_record(record:Dictionary,content_root:String="")->Array[String]:
	var result:Array[String]=[]
	if model(record):result.append(str(record.get("asset_path","")))
	if record.has("tile3d"):result.append_array(Kits.required_paths(record.tile3d,content_root))
	return result

static func has_models(record:Dictionary,content_root:String="")->bool:
	return not for_record(record,content_root).is_empty()

static func paths(records:Array,content_root:String="")->Array[String]:
	var seen:Dictionary={};var result:Array[String]=[]
	for record:Dictionary in records:
		for path:String in for_record(record,content_root):
			var key:=path.replace("\\","/").simplify_path()
			if not seen.has(key):seen[key]=true;result.append(key)
	return result
