extends RefCounted
## One-load CPU image handoff; shared render caches are touched only on main.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const TextureCache=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Compressed=preload("res://scripts/world3d/compressed_texture_source.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")

static func requests(record:Dictionary,checked:Dictionary)->Dictionary:
	var result:Dictionary={}
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return result
	for definition in Paint.definitions(record):
		for field in Paint.MAP_FIELDS:
			var path:=str(definition.get(field,""))
			if path.is_empty():continue
			var flip:bool=field=="normal_path" and definition.get("normal_format","opengl")=="directx"
			var key:=Paint.texture_key(path,flip,field=="normal_path")
			if checked.has(key) and Paint._textures.has(key):continue
			result[key]=[path,flip,field=="normal_path"]
	return result

static func decode(requested:Dictionary,content_root:String)->Dictionary:
	var started:=Time.get_ticks_usec();var images:Dictionary={};var failed:Array=[]
	for key:String in requested:
		var source:Array=requested[key];var image:Image
		if Paths.allowed(source[0],content_root) and FileAccess.file_exists(source[0]):
			var normal:bool=source[2] if source.size()>2 else source[1]
			# Unsupported bounded formats retain an exclusive fallback lease. Its
			# decoded source supplies the identity; never hash the same file again.
			image=TextureCache.image(source[0],source[1],true)
			if image!=null and Paint.compressed_sidecars_enabled:
				var digest:String=image.get_meta("runtime_source_sha256","")
				var plan:=Compressed.plan_mutable(source[0],source[1],normal,content_root,digest)
				if not plan.is_empty() and plan.width==image.get_width() and plan.height==image.get_height():
					var compressed:=Compressed.read(plan)
					if compressed!=null:
						compressed.set_meta("runtime_source_sha256",digest)
						compressed.set_meta("runtime_texture_representation","dds:"+str(plan.mutable_dds_sha256));image=compressed
			if image!=null and not image.has_meta("runtime_texture_representation"):image.set_meta("runtime_texture_representation","source")
		if image==null:failed.append(key)
		else:images[key]=image
	return {"images":images,"failed":failed,"elapsed_us":Time.get_ticks_usec()-started}

static func install(prepared:Dictionary)->Dictionary:
	var previous:Dictionary=Paint.prepared_images
	Paint.prepared_images={}
	var invalidated:Dictionary={}
	for key in prepared.failed:
		Paint._textures.erase(key);Paint._texture_refs.erase(key);invalidated[key]=true
		TextureCache.discard_failed_source(Paint.texture_source_path(key),str(key).ends_with("|flip_y"),true)
	for key in prepared.images:
		var retained:Texture2D=Paint.retained_texture(key)
		if retained==null or not Paint._same_prepared_texture(retained,prepared.images[key]):invalidated[key]=true
	# Materials can outlive their texture's LRU entry. Invalidating only the
	# texture dictionary would retain old pixels through cached material refs.
	if not invalidated.is_empty():
		Paint._materials.clear();Paint._material_refs.clear();River.cache.clear();Prefab.invalidate_texture_materials(invalidated)
	Paint.prepare_images(prepared.images)
	return previous

static func restore(previous:Dictionary,failed:Array=[])->void:
	# Do not retain a newly constructed fallback shader as if it were a valid
	# material after the missing image is repaired or another operation uploads it.
	if not failed.is_empty():
		Paint._materials.clear();Paint._material_refs.clear();River.cache.clear()
		var invalidated:Dictionary={}
		for key in failed:
			Paint._textures.erase(key);Paint._texture_refs.erase(key);invalidated[key]=true
			TextureCache.discard_failed_source(Paint.texture_source_path(key),str(key).ends_with("|flip_y"),true)
		Prefab.invalidate_texture_materials(invalidated)
	Paint.prepared_images=previous
