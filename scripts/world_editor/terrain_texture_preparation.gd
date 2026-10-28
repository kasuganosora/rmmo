extends RefCounted
## One-load CPU image handoff; shared render caches are touched only on main.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const TextureCache=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Compressed=preload("res://scripts/world3d/compressed_texture_source.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")

static func requests(record:Dictionary,checked:Dictionary,owners:Variant=null)->Dictionary:
	var result:Dictionary={}
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return result
	for definition in Paint.definitions(record):
		for field in Paint.MAP_FIELDS:
			var path:=str(definition.get(field,""))
			if path.is_empty():continue
			var flip:bool=field=="normal_path" and definition.get("normal_format","opengl")=="directx"
			var key:=Paint.texture_key(path,flip,field=="normal_path")
			if checked.has(key):
				var retained:=Paint.retained_texture(key)
				if retained!=null:
					# A published material can outlive the strong LRU entry. Borrow
					# that allocation only through this record's publication, including
					# waits for its other images; never create a second cache owner.
					if owners!=null:owners[key]=retained
					continue
			result[key]=[path,flip,field=="normal_path"]
	return result

static func owners_current(prepared:Dictionary)->bool:
	# Imports already in flight may refresh sources while LoadJob yields. A
	# borrowed old allocation must not resurrect an invalidated cache generation.
	for key:String in prepared.get("owners",{}):
		if Paint.retained_texture(key)!=prepared.owners[key]:return false
	# A worker can have captured PNG pixels before an import publishes the same
	# source as DDS. Return its CPU lease and borrow that GPU owner on the next
	# preparation pass; installing the old image would undo the import and upload
	# it again. Compare existing identities only, with no filesystem/cache scan.
	for key:String in prepared.get("images",{}):
		var image:Image=prepared.images[key]
		if image.get_meta("runtime_texture_representation","")!="source":continue
		var digest:String=image.get_meta("runtime_source_sha256","")
		if digest.is_empty():continue
		var retained:=Paint.retained_texture(key)
		if retained!=null and retained.get_meta("runtime_source_sha256","")==digest and str(retained.get_meta("runtime_texture_representation","")).begins_with("dds:"):return false
	return true

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

static func reconcile_pool(prepared:Dictionary,material_pool:Variant,sources:Dictionary)->int:
	if not material_pool is Dictionary or prepared.is_empty():return 0
	# Each source generation is reconciled once per load, including a GPU owner
	# just published by an import. Ordinary owner reuse must not rescan the pool
	# for every record. This table holds identities only, never resources/pixels.
	var changed:Dictionary={}
	for field:String in ["owners","images"]:
		for key:String in prepared.get(field,{}):
			var resource:Resource=prepared[field][key]
			var representation:Variant=resource.get_meta("runtime_texture_representation") if resource.has_meta("runtime_texture_representation") else null
			var identity:Array=[resource.get_meta("runtime_source_sha256",""),representation]
			if sources.get(key,[])!=identity:changed[key]=resource;sources[key]=identity
	for key:String in prepared.get("failed",[]):changed[key]=null;sources.erase(key)
	if changed.is_empty():return 0
	# Cook's per-load pool can still own materials after both global caches
	# were invalidated. Remove only entries whose actual texture changed; live
	# published meshes retain their original immutable material objects.
	var stale:Dictionary={}
	var inspected:=0
	for identity:Variant in material_pool.keys():
		var material:Variant=material_pool[identity]
		if not material is StandardMaterial3D:continue
		var id:int=material.get_instance_id()
		if not stale.has(id):
			inspected+=1
			stale[id]=false
			var definition:Dictionary=material.get_meta("runtime_paint_definition",{})
			for field:String in Prefab.TEXTURE_PROPERTIES:
				var key:=Paint.definition_texture_key(definition,field)
				if changed.has(key) and (changed[key]==null or not Paint._same_prepared_texture(material.get(Prefab.TEXTURE_PROPERTIES[field]),changed[key])):
					stale[id]=true;break
		if stale[id]:material_pool.erase(identity)
	return inspected

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
