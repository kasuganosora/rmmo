extends RefCounted
## One-load CPU image handoff; shared render caches are touched only on main.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const TextureCache=preload("res://scripts/world3d/runtime_texture_cache.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")

static func requests(record:Dictionary,checked:Dictionary)->Dictionary:
	var result:Dictionary={}
	for definition in Paint.definitions(record):
		for field in Paint.MAP_FIELDS:
			var path:=str(definition.get(field,""))
			if path.is_empty():continue
			var flip:bool=field=="normal_path" and definition.get("normal_format","opengl")=="directx"
			var key:=path+("|flip_y" if flip else "")
			if checked.has(key) and Paint._textures.has(key):continue
			result[key]=[path,flip]
	return result

static func decode(requested:Dictionary,content_root:String)->Dictionary:
	var started:=Time.get_ticks_usec();var images:Dictionary={};var failed:Array=[]
	for key:String in requested:
		var source:Array=requested[key];var image:Image
		if Paths.allowed(source[0],content_root) and FileAccess.file_exists(source[0]):image=TextureCache.image(source[0],source[1])
		if image==null:failed.append(key)
		else:images[key]=image
	return {"images":images,"failed":failed,"elapsed_us":Time.get_ticks_usec()-started}

static func install(prepared:Dictionary)->Dictionary:
	var previous:Dictionary=Paint.prepared_images
	Paint.prepared_images={}
	var invalidated:Dictionary={}
	for key in prepared.failed:Paint._textures.erase(key);invalidated[key]=true
	for key in prepared.images:
		if not Paint._textures.has(key) or Paint._textures[key].get_meta("runtime_source_sha256","")!=prepared.images[key].get_meta("runtime_source_sha256",""):invalidated[key]=true
	# Materials can outlive their texture's LRU entry. Invalidating only the
	# texture dictionary would retain old pixels through cached material refs.
	if not invalidated.is_empty():
		Paint._materials.clear();River.cache.clear();Prefab.invalidate_texture_materials(invalidated)
	Paint.prepare_images(prepared.images)
	return previous

static func restore(previous:Dictionary,failed:Array=[])->void:
	# Do not retain a newly constructed fallback shader as if it were a valid
	# material after the missing image is repaired or another operation uploads it.
	if not failed.is_empty():
		Paint._materials.clear();River.cache.clear()
		var invalidated:Dictionary={}
		for key in failed:invalidated[key]=true
		Prefab.invalidate_texture_materials(invalidated)
	Paint.prepared_images=previous
