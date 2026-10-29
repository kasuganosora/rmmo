extends RefCounted
## Paint is record data. Rebuild an instance mesh; never mutate shared source assets.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const CpuMesh = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const TextureCache=preload("res://scripts/world3d/runtime_texture_cache.gd")
const MAX_TRIANGLES := 50000
const MAX_OVERRIDES := 128
const MAP_FIELDS := ["texture_path", "normal_path", "roughness_path", "metallic_path", "ao_path", "height_path"]
static var preserve_complete_surfaces_enabled:=true
static var uv_projection_elision_enabled:=true
static var _textures := {}
static var prepared_images:Dictionary={}
## Main-only synchronous scope, borrowed from the admitted shared upload pool.
static var prepared_textures:Dictionary={}
static var _materials := {}
# Strong hot caches have a byte ceiling; weak catalogues reuse resources still
# owned by live maps after cache eviction, without extending their residency.
static var residency_budget_enabled:=true
static var cache_byte_budget:=256*1024*1024
static var _texture_refs:Dictionary={}
static var _material_refs:Dictionary={}
static var _cache_serial:=0
static var source_generation:=0
static var _cache_use:Dictionary={}
static var cache_residency_profile:Dictionary={}
static var incremental_cache_budget_enabled:=true # Diagnostic full-scan control.
# IDs/costs only: this conservative union never keeps a texture alive. Removing
# hot entries may overestimate until the next exact trim; it cannot undercount.
static var _cache_accounted:Dictionary={}
static var _cache_upper_bytes:=0
static var _cache_estimate_valid:=false
static var capacity_eviction_accounting_enabled:=true # Diagnostic legacy control.
static var native_cache_sort_enabled:=true # Diagnostic scripted-comparator control.
const TEXTURE_PROPERTIES=["albedo_texture","normal_texture","roughness_texture","metallic_texture","ao_texture","heightmap_texture"]
static func texture_key(path:String,flip:bool=false,normal:bool=false)->String:
	if path.is_empty():return ""
	return path+("|normal" if normal or flip else "")+("|flip_y" if flip else "")
static func texture_source_path(key:String)->String:
	return key.trim_suffix("|flip_y").trim_suffix("|normal")
static func definition_texture_key(definition:Dictionary,field:String)->String:
	var path:String=definition.get(field,"")
	if path.is_empty() and field=="texture_path":path=str(definition.get("pattern",""))
	return texture_key(path,field=="normal_path" and definition.get("normal_format","opengl")=="directx",field=="normal_path")
static func refresh_sources()->void:
	# A source refresh starts a new identity generation. Live consumers keep
	# their old resources; neither hot nor weak aliases may authorize new builds.
	_materials.clear();_textures.clear();prepared_images.clear();prepared_textures={}
	_material_refs.clear();_texture_refs.clear();_cache_use.clear()
	_sidecar_cache.clear()
	_cache_accounted.clear();_cache_upper_bytes=0;_cache_estimate_valid=false
	source_generation+=1

static func _touch_cache(kind:String,key:String)->void:
	_cache_serial+=1;_cache_use[kind+key]=_cache_serial
static func _remember_weak(catalog:Dictionary,key:String,value:RefCounted)->void:
	catalog[key]=weakref(value)
	# Live identities belong to external owners and have no count ceiling.
	# Rotate a bounded prefix after iteration, so dead entries behind live ones
	# are eventually reached without copying all keys or retaining resources.
	var prefix:Array[String]=[]
	for id:String in catalog:
		prefix.append(id)
		if prefix.size()==8:break
	for id:String in prefix:
		var reference:WeakRef=catalog[id]
		catalog.erase(id)
		if reference.get_ref()!=null:catalog[id]=reference
	if texture_profile_enabled:TextureCache._profile_count("paint.cache.weak_checks",prefix.size())
static func _texture_cost(texture:Texture2D)->int:
	if texture_profile_enabled:TextureCache._profile_count("paint.cache.cost_reads")
	if texture.has_meta("runtime_upload_bytes"):return int(texture.get_meta("runtime_upload_bytes"))
	return ceili(float(texture.get_width())*texture.get_height()*4.*4./3.)

static func _invalidate_cache_estimate()->void:
	_cache_estimate_valid=false
	if texture_profile_enabled:TextureCache._profile_count("paint.cache.resource_changes")
static func _watch_cache_resource(value:Resource)->void:
	if not value.changed.is_connected(_invalidate_cache_estimate):value.changed.connect(_invalidate_cache_estimate)
	# BaseMaterial3D.set_texture emits property_list_changed, not changed.
	if value is BaseMaterial3D and not value.property_list_changed.is_connected(_invalidate_cache_estimate):value.property_list_changed.connect(_invalidate_cache_estimate)
static func _account_texture(texture:Texture2D)->void:
	var id:=texture.get_instance_id()
	if _cache_accounted.has(id):return
	var bytes:=_texture_cost(texture)
	_cache_accounted[id]=bytes;_cache_upper_bytes+=bytes
	_watch_cache_resource(texture)
static func _forget_retired_texture_cost(retired_id:int)->bool:
	# Validate the actual current owners: a material can have changed while its
	# signals were blocked, and raw edits can replace keys without changing size.
	if not capacity_eviction_accounting_enabled or retired_id==0 or _cache_accounted.size()>1024 or _cache_use.size()>256:return false
	# The full scan also removes recency entries left by external raw erases.
	# Preserve that behavior before permitting a shortcut, even below its cap.
	for key:String in _cache_use:
		if not (_materials if key.begins_with("m:") else _textures).has(key.substr(2)):return false
	if not _cache_accounted.has(retired_id):return false
	# Hot dictionaries can be edited externally. Inspect actual remaining owner
	# IDs and costs; same-size raw replacement must never grant a stale proof.
	var checked:Dictionary={}
	for texture:Texture2D in _textures.values():
		var id:=texture.get_instance_id()
		if id==retired_id:return false
		if not checked.has(id):
			if not _cache_accounted.has(id) or _texture_cost(texture)>int(_cache_accounted[id]):return false
			checked[id]=true
	# Do not trust change notifications as proof: set_block_signals can hide a
	# slot replacement and set_meta can silently change runtime_upload_bytes.
	if texture_profile_enabled:TextureCache._profile_count("paint.cache.guard_material_property_reads",_materials.size()*TEXTURE_PROPERTIES.size())
	for material:Material in _materials.values():
		for property:String in TEXTURE_PROPERTIES:
			var texture:Texture2D=material.get(property)
			if texture==null:continue
			var id:=texture.get_instance_id()
			if id==retired_id:return false
			if not checked.has(id):
				if not _cache_accounted.has(id) or _texture_cost(texture)>int(_cache_accounted[id]):return false
				checked[id]=true
	_cache_upper_bytes-=int(_cache_accounted[retired_id]);_cache_accounted.erase(retired_id)
	if texture_profile_enabled:TextureCache._profile_count("paint.cache.capacity_accounting_reuses")
	return true
static func _trim_after_insert(value:Resource,retired_id:int=0)->void:
	if not residency_budget_enabled:_cache_estimate_valid=false;return
	if not incremental_cache_budget_enabled or not _cache_estimate_valid or cache_byte_budget<=0 or (value is BaseMaterial3D and _materials.size()==1 and _textures.is_empty()):
		if texture_profile_enabled:TextureCache._profile_count("paint.cache.full_insert_"+("legacy" if not incremental_cache_budget_enabled else ("dirty" if not _cache_estimate_valid else "small")))
		trim_cached_resources();return
	if value is Texture2D:_account_texture(value)
	else:
		_watch_cache_resource(value)
		if texture_profile_enabled:TextureCache._profile_count("paint.cache.material_property_reads",TEXTURE_PROPERTIES.size())
		for property:String in TEXTURE_PROPERTIES:
			var texture:Texture2D=value.get(property)
			if texture!=null:_account_texture(texture)
	if _cache_upper_bytes>maxi(0,cache_byte_budget) and retired_id!=0:_forget_retired_texture_cost(retired_id)
	if _cache_upper_bytes>maxi(0,cache_byte_budget) or _cache_accounted.size()>1024 or _cache_use.size()>256:
		if texture_profile_enabled:TextureCache._profile_count("paint.cache.full_insert_"+("budget" if _cache_upper_bytes>maxi(0,cache_byte_budget) else "metadata"))
		trim_cached_resources()
	elif texture_profile_enabled:TextureCache._profile_count("paint.cache.fast_checks")
static func _trim_changed_cache()->void:
	if incremental_cache_budget_enabled and (not _cache_estimate_valid or _cache_upper_bytes>maxi(0,cache_byte_budget)):
		if texture_profile_enabled:TextureCache._profile_count("paint.cache.full_hit_"+("dirty" if not _cache_estimate_valid else "budget"))
		trim_cached_resources()
static func remember_texture_owner(key:String,texture:Texture2D)->void:
	# The admitted job already owns this GPU object. Reinstalling every ticket
	# into the strong cache causes immediate budget evictions before any bind.
	# Actual texture() consumers promote only the identities they use.
	if incremental_cache_budget_enabled and residency_budget_enabled:
		if not _texture_refs.has(key) or _texture_refs[key].get_ref()!=texture:_remember_weak(_texture_refs,key,texture)
		if texture_profile_enabled:TextureCache._profile_count("paint.cache.weak_tickets")
		return
	# Preserve the diagnostic and disabled-budget handoff without new trimming.
	if not _textures.has(key) and _textures.size()>=64:_textures.erase(_textures.keys()[0])
	_textures[key]=texture
	_cache_estimate_valid=false
static func _same_prepared_texture(texture:Texture2D,prepared:Resource)->bool:
	if texture==null or prepared==null:return false
	if texture.get_meta("runtime_source_sha256","")!=prepared.get_meta("runtime_source_sha256",""):return false
	# Immutable game packets have no representation identity and retain their
	# previous cache behavior; editor snapshots distinguish DDS/PNG generations.
	return not prepared.has_meta("runtime_texture_representation") or texture.get_meta("runtime_texture_representation","")==prepared.get_meta("runtime_texture_representation")
static func _prepared_resource(key:String)->Resource:
	# CPU images remain authoritative for the existing image+upload pair. A
	# native streaming packet instead supplies a texture with no full Image.
	return prepared_images.get(key,prepared_textures.get(key))
static func retained_texture(key:String)->Texture2D:
	var texture:Texture2D=_textures.get(key)
	if texture==null and residency_budget_enabled and _texture_refs.has(key):texture=_texture_refs[key].get_ref()
	var prepared:=_prepared_resource(key)
	if texture!=null and prepared!=null and not _same_prepared_texture(texture,prepared):return null
	return texture

static func publish_import_texture(path:String,image:Image)->bool:
	# Called on main only after the import worker joined, while its CPU Image
	# remains covered by the queue lease. No file read or hidden mesh prewarm.
	if not Thread.is_main_thread() or path.is_empty() or image==null or image.is_empty():return false
	var key:=texture_key(path)
	var current:=retained_texture(key)
	if current!=null and _same_prepared_texture(current,image):return true
	var began:=Time.get_ticks_usec() if texture_profile_enabled else 0
	var texture:=ImageTexture.create_from_image(image)
	if texture==null or texture.get_width()!=image.get_width() or texture.get_height()!=image.get_height():return false
	texture.set_meta("runtime_upload_bytes",image.get_data_size())
	texture.set_meta("surface_has_alpha",bool(image.get_meta("runtime_upload_has_alpha",false)))
	texture.set_meta("runtime_normal_xy",image.get_format()==Image.FORMAT_RGTC_RG)
	texture.set_meta("runtime_source_sha256",image.get_meta("runtime_source_sha256",""))
	texture.set_meta("runtime_texture_representation",image.get_meta("runtime_texture_representation",""))
	var retired_id:=0
	if not _textures.has(key) and _textures.size()>=64:
		var oldest:String=_textures.keys()[0]
		if capacity_eviction_accounting_enabled:retired_id=_textures[oldest].get_instance_id()
		_textures.erase(oldest);_cache_use.erase("t:"+oldest)
	_textures[key]=texture;_touch_cache("t:",key);_remember_weak(_texture_refs,key,texture);_trim_after_insert(texture,retired_id)
	if texture_profile_enabled:TextureCache._profile_elapsed("paint.texture.import_upload",began,{"path":path,"bytes":image.get_data_size()})
	return true
static func trim_cached_resources()->Dictionary:
	if not residency_budget_enabled:return {}
	if texture_profile_enabled:
		TextureCache._profile_count("paint.cache.full_scans")
		TextureCache._profile_count("paint.cache.material_property_reads",_materials.size()*TEXTURE_PROPERTIES.size())
	# Legacy publication owners may clear either hot dictionary directly.
	for id:String in _cache_use.keys():
		if not (_materials if id.begins_with("m:") else _textures).has(id.substr(2)):_cache_use.erase(id)
	var counts:Dictionary={};var costs:Dictionary={};var dependencies:Dictionary={};var candidates:Array=[];var total:=0
	var watched_textures:Dictionary={}
	for kind:String in ["m:","t:"]:
		var cache:Dictionary=_materials if kind=="m:" else _textures
		for key:String in cache:
			var ids:Array=[];var textures:Array=[]
			if kind=="t:":textures.append(cache[key])
			else:
				for property:String in TEXTURE_PROPERTIES:
					var texture:Texture2D=cache[key].get(property)
					if texture!=null:textures.append(texture)
			for texture:Texture2D in textures:
				var id:=texture.get_instance_id()
				if id in ids:continue
				ids.append(id);counts[id]=int(counts.get(id,0))+1
				if not costs.has(id):
					costs[id]=_texture_cost(texture);total+=costs[id]
					if incremental_cache_budget_enabled:watched_textures[id]=texture
			dependencies[kind+key]=ids;candidates.append({"kind":kind,"key":key,"use":int(_cache_use.get(kind+key,0))})
	var before:=total;var materials:=0;var textures:=0
	if not incremental_cache_budget_enabled or total>maxi(0,cache_byte_budget):
		if texture_profile_enabled:TextureCache._profile_count("paint.cache.sort_candidates",candidates.size())
		_sort_cache_candidates(candidates)
	for candidate:Dictionary in candidates:
		if total<=maxi(0,cache_byte_budget):break
		var kind:String=candidate.kind;var key:String=candidate.key
		if kind=="m:":_remember_weak(_material_refs,key,_materials[key]);_materials.erase(key);materials+=1
		else:_remember_weak(_texture_refs,key,_textures[key]);_textures.erase(key);textures+=1
		for id:int in dependencies[kind+key]:
			counts[id]-=1
			if counts[id]==0:total-=costs[id]
		_cache_use.erase(kind+key)
	if incremental_cache_budget_enabled:
		for id:int in counts:
			if counts[id]==0:costs.erase(id)
		_cache_accounted=costs;_cache_upper_bytes=total;_cache_estimate_valid=true
		# Subscribe only surviving owners. A zero-budget admission can discard
		# its entire material; watching those outgoing objects repeats useless work.
		for material:Material in _materials.values():_watch_cache_resource(material)
		for id:int in costs:_watch_cache_resource(watched_textures[id])
	else:_cache_estimate_valid=false
	cache_residency_profile={"before_bytes":before,"after_bytes":total,"budget_bytes":cache_byte_budget,"evicted_materials":materials,"evicted_textures":textures,"scope":"unique decoded upload footprint held by hot cache references; not process RSS or measured VRAM"}
	return cache_residency_profile.duplicate()

static func _sort_cache_candidates(candidates:Array)->void:
	if native_cache_sort_enabled:
		# Unique serials make the old comparator's order unambiguous. Pairs use
		# native Variant sorting and only retain integer indices, never Resources.
		# Duplicated serials, including multiple missing ones, keep the legacy
		# comparator and tie behavior.
		var order:Array=[];var seen:Dictionary={};var unique:=true
		for i:int in candidates.size():
			var use:int=int(candidates[i].use)
			if seen.has(use):unique=false;break
			seen[use]=true;order.append([use,i])
		if unique:
			order.sort();var original:=candidates.duplicate()
			for i:int in order.size():candidates[i]=original[order[i][1]]
			if texture_profile_enabled:TextureCache._profile_count("paint.cache.native_sort_calls")
			return
		if texture_profile_enabled:TextureCache._profile_count("paint.cache.native_sort_tie_fallbacks")
	if texture_profile_enabled:TextureCache._profile_count("paint.cache.scripted_sort_calls")
	candidates.sort_custom(func(a,b):return a.use<b.use)
static func _material_current(material:StandardMaterial3D)->bool:
	var definition:Dictionary=material.get_meta("runtime_paint_definition",{})
	for i in MAP_FIELDS.size():
		var path:String=definition.get(MAP_FIELDS[i],"")
		if path.is_empty():continue
		var key:=definition_texture_key(definition,MAP_FIELDS[i])
		var texture:Texture2D=material.get(TEXTURE_PROPERTIES[i])
		var prepared:=_prepared_resource(key)
		if prepared!=null and not _same_prepared_texture(texture,prepared):return false
		if _textures.has(key) and not _same_prepared_texture(texture,_textures[key]):return false
	return true

# Enable before starting the measured operation. Uses Pixels' mutex-protected
# aggregate, so either reset_profile clears both paint.* and texture.* stages.
static var texture_profile_enabled:=false
## Optional offline DDS sidecars generated by the content pipeline. They let a
## material upload a block-compressed texture without decoding/uploading RGBA.
static var compressed_sidecars_enabled:=true
static var _sidecar_cache:Dictionary={}

static func refresh_texture_source_if_needed(path:String,sidecar:String,dds_sha:String,changed:bool=false)->void:
	var key:=texture_key(path)
	var cached:Texture2D=_textures.get(key)
	if cached==null and _texture_refs.has(key):cached=_texture_refs[key].get_ref()
	var negative:bool=_sidecar_cache.has(key) and str(_sidecar_cache[key])!=sidecar
	var representation:String=cached.get_meta("runtime_texture_representation","") if cached!=null else ""
	# Direct runtime reads use their immutable sidecar path, while mutable editor
	# preparation records a verified byte digest; both describe the same file.
	if changed or negative or (cached!=null and representation not in ["dds:"+sidecar,"dds:"+dds_sha]):
		refresh_texture_source(path)

static func refresh_texture_source(path:String)->void:
	# New sidecars must invalidate this source's old PNG/negative-cache entries.
	# Existing scene owners keep their resources; no material is mutated.
	for normal:bool in [false,true]:
		for flip:bool in ([false,true] if normal else [false]):
			var key:=texture_key(path,flip,normal)
			_sidecar_cache.erase(key);_textures.erase(key);_texture_refs.erase(key)
			prepared_images.erase(key);prepared_textures.erase(key);_cache_use.erase("t:"+key)
	var affected:Dictionary={texture_key(path):true,texture_key(path,false,true):true,texture_key(path,true,true):true}
	load("res://scripts/world3d/river_materials.gd").invalidate_texture_source(path)
	load("res://scripts/world3d/house_prefab.gd").invalidate_texture_materials(affected)
	for catalogue:Dictionary in [_materials,_material_refs]:
		for key:String in catalogue.keys():
			var material:Variant=catalogue[key]
			if material is WeakRef:material=material.get_ref()
			if not material is Material:continue
			var definition:Variant=material.get_meta("runtime_paint_definition",{})
			if not definition is Dictionary:continue
			for field:String in MAP_FIELDS:
				if definition.get(field,"")==path:
					catalogue.erase(key);_cache_use.erase("m:"+key);break
	_cache_estimate_valid=false

static func reset_profile()->void:TextureCache.reset_profile()
static func profile_snapshot()->Dictionary:return TextureCache.profile_snapshot("paint.")

static func prepare_images(images:Dictionary)->void:
	_discard_stale_prepared_owners(images)
	prepared_images.merge(images,true)

static func prepare_textures(textures:Dictionary)->void:
	# Borrowed only for this publication scope. Producers supply source/variant,
	# alpha, normal encoding and conservative byte metadata without get_image().
	_discard_stale_prepared_owners(textures)
	prepared_textures=textures

static func _discard_stale_prepared_owners(resources:Dictionary)->void:
	var changed:=false
	for key in resources:
		var weak:Variant=_texture_refs.get(key)
		if weak!=null:
			var texture:Texture2D=weak.get_ref()
			if texture!=null and not _same_prepared_texture(texture,resources[key]):_texture_refs.erase(key);changed=true
		if _textures.has(key) and not _same_prepared_texture(_textures[key],resources[key]):
			_textures.erase(key);changed=true
	if changed:_materials.clear();_material_refs.clear();_cache_estimate_valid=false

static func fail(message: String) -> Dictionary: return {"ok": false, "error": message}

static func numbers(value: Variant, count: int, low: float, high: float) -> bool:
	if not value is Array or value.size() != count: return false
	for n in value:
		if not (n is int or n is float) or not is_finite(float(n)) or n < low or n > high: return false
	return true

static func material_valid(value: Variant, relative: bool = false, content_root: String = "", validation_cache: Variant = null) -> bool:
	# Callers may share this only within one immutable document validation.
	# Never persist it across loads, edits, or filesystem operations.
	if validation_cache==null: validation_cache={}
	var cache_key:Array=[relative,content_root,value]
	if validation_cache.has(cache_key): return true
	if not value is Dictionary or not value.get("name") is String: return false
	if not numbers(value.get("color"), 4, 0, 1) or not numbers([value.get("roughness")], 1, 0, 1): return false
	if value.get("pattern", "") not in ["", "checker"]: return false
	if value.get("normal_format", "opengl") not in ["opengl", "directx"]: return false
	if not numbers([value.get("normal_strength", 1.0)], 1, 0, 4): return false
	if not numbers([value.get("metallic", 0.0)], 1, 0, 1): return false
	if not numbers(value.get("tile_size", [1.0, 1.0]), 2, 0.01, 100): return false
	for field in MAP_FIELDS:
		var path: Variant = value.get(field, "")
		if not path is String: return false
		if path.is_empty(): continue
		if path.get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp"]: return false
		if not Paths.allowed(path,content_root) and not (relative and not path.is_absolute_path() and not path.contains(":") and not ".." in path.replace("\\", "/").split("/")): return false
	validation_cache[cache_key]=true
	return true

static func valid(record: Dictionary, relative: bool = false, content_root: String = "", validation_cache: Variant = null, immutable_paint_id:Variant=null) -> bool:
	if record.has("road_kerb_material"):
		if not record.get("road_mesh",{}).has("kerbs") or not material_valid(record.road_kerb_material,relative,content_root,validation_cache):return false
		if record.road_kerb_material.color[3]!=1:return false
	if not preload("res://scripts/world3d/rock_bank_mesh.gd").valid(record):return false
	for definition in record.get("rock_bank_materials",{}).values():
		if not material_valid(definition,relative,content_root,validation_cache):return false
		if definition.color[3]!=1:return false
	if validation_cache==null: validation_cache={}
	if not preload("res://scripts/world3d/streetlamp_banner.gd").valid(record):return false
	if record.has("banner") and not material_valid(record.banner.get("material"),relative,content_root,validation_cache):return false
	if record.has("fortification_art"):
		if not record.get("fortification_materials") is Dictionary or record.fortification_materials.size()!=4: return false
		for role in ["stone","trim","door","iron"]:
			if not material_valid(record.fortification_materials.get(role),relative,content_root,validation_cache): return false
			if record.fortification_materials[role].color[3]!=1: return false
	elif record.has("fortification_materials"): return false
	if not preload("res://scripts/world3d/bridge_data.gd").valid(record): return false
	if record.has("bridge_mesh"):
		if not record.get("bridge_materials") is Dictionary or record.bridge_materials.size()!=3: return false
		for role in ["deck","masonry","trim"]:
			if not material_valid(record.bridge_materials.get(role),relative,content_root,validation_cache): return false
			if record.bridge_materials[role].color[3]!=1: return false
	if not preload("res://scripts/world3d/river_material_data.gd").valid(record): return false
	if not preload("res://scripts/world3d/terrain_regions.gd").valid(record): return false
	if preload("res://scripts/world3d/terrain_furrows.gd").maximum_height(record)>0:
		if not preload("res://scripts/world3d/terrain_surface.gd").valid(record): return false
		if not preload("res://scripts/world3d/terrain_furrows.gd").generate(record).ok: return false
	if record.has("terrain_saturation") and (not record.has("terrain_mesh") or not numbers([record.terrain_saturation],1,0,1)): return false
	if record.has("terrain_saturation") and record.has("surface_paint"): return false
	for definition in record.get("terrain_regions",{}).get("materials",[]):
		if not material_valid(definition,relative,content_root,validation_cache) or definition.color[3]!=1: return false
	if record.has("terrain_depth_blend"):
		for key in ["sand_material","rock_material"]:
			if not material_valid(record.terrain_depth_blend[key],relative,content_root,validation_cache): return false
			if record.terrain_depth_blend[key].color[3]!=1: return false
	if record.has("terrain_material") and not material_valid(record.terrain_material,relative,content_root,validation_cache): return false
	if record.has("terrain_slope_blend"):
		if not material_valid(record.terrain_slope_blend.rock_material,relative,content_root,validation_cache) or record.terrain_slope_blend.rock_material.color[3]!=1: return false
	for field in ["terrain_depth_blend","terrain_slope_blend"]:
		if record.get(field,{}).has("transition_material"):
			var definition: Variant=record[field].transition_material
			if not material_valid(definition,relative,content_root,validation_cache) or definition.color[3]!=1: return false
	if (record.has("terrain_depth_blend") or record.has("terrain_slope_blend") or record.has("terrain_regions") or record.has("terrain_saturation")) and record.has("terrain_material") and record.terrain_material.color[3]!=1: return false
	# Cache only the repeated face-paint portion, after all terrain/bridge/river
	# constraints above. Caller cache lifetime is one immutable operation.
	# MapMetadataCache can supply its operation-local paint table index. That
	# avoids deeply hashing the same shared array once for every wall fragment.
	var paint_key:Array=["paint_record",relative,content_root,record.has("bank_wetness"),immutable_paint_id if immutable_paint_id!=null else record.get("surface_paint",[])]
	if validation_cache.has(paint_key):return true
	var entries: Variant = record.get("surface_paint", [])
	if not entries is Array or entries.size() > MAX_OVERRIDES: return false
	var seen := {}
	var checked_materials: Array = []
	for entry in entries:
		if not entry is Dictionary or not entry.get("mesh") is String or not entry.get("geometry") is String: return false
		if not numbers([entry.get("surface"), entry.get("face")], 2, 0, 1000000): return false
		if entry.surface != floor(entry.surface) or entry.face != floor(entry.face): return false
		var definition: Variant = entry.get("material")
		if not definition in checked_materials:
			if not material_valid(definition, relative, content_root,validation_cache): return false
			checked_materials.append(definition)
		if record.has("bank_wetness") and definition.color[3]!=1: return false
		if not numbers(entry.get("scale"), 2, 0.01, 100) or not numbers(entry.get("offset"), 2, -100, 100): return false
		if not numbers([entry.get("rotation")], 1, -3600, 3600) or entry.get("mapping") not in ["planar", "uv", "meters"]: return false
		var key := face_key(entry)
		if seen.has(key): return false
		seen[key] = true
	validation_cache[paint_key]=true
	return true

static func face_key(entry: Dictionary) -> String:
	return "%s|%d|%d" % [entry.mesh, entry.surface, entry.face]

static func meshes(root: Node) -> Array[MeshInstance3D]:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.surface_materials.meshes") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var result: Array[MeshInstance3D] = []
	if root.get_meta("editor_shadow_proxy",false):return result
	if root is MeshInstance3D and root.mesh != null: result.append(root)
	for child in root.get_children(): result.append_array(meshes(child))
	return result

static func source(node: MeshInstance3D) -> Mesh:
	return node.get_meta("paint_source", node.mesh)

static func _root_of(parents: PackedInt32Array, at: int) -> int:
	while parents[at] != at: at = parents[at]
	return at

static func _vertex_key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 100000), roundi(point.y * 100000), roundi(point.z * 100000)]

static func geometry(node: MeshInstance3D, first_surface_only:bool=false) -> Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.surface_materials.geometry") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if node.has_meta("paint_geometry"):
		var cached:Dictionary=node.get_meta("paint_geometry")
		return {"ok":true,"surfaces":cached.surfaces.slice(0,1)} if first_surface_only else cached
	var mesh := source(node)
	if mesh == null or (mesh is ArrayMesh and mesh.get_blend_shape_count() > 0) or node.skin != null: return fail("蒙皮或变形模型暂不支持表面绘制")
	if mesh.get_surface_count() > 128: return fail("模型材质槽超过 128 个")
	var source_arrays:Array=[]
	for slot:int in mesh.get_surface_count():
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(slot)!=Mesh.PRIMITIVE_TRIANGLES:return fail("仅支持三角网格表面")
		source_arrays.append(mesh.get_meta("ground_cpu_cache").surfaces[slot] if mesh.has_meta("ground_cpu_cache") else CpuMesh.primitive_arrays(mesh,slot))
	var result:=geometry_arrays(source_arrays,mesh is BoxMesh or (mesh is CpuMesh and mesh.box_size!=Vector3.ZERO),first_surface_only)
	# A partial result must never hide faces from later manual painting.
	if result.ok and not first_surface_only:node.set_meta("paint_geometry",result)
	return result

static func geometry_arrays(source_arrays:Array,box_geometry:bool=false,first_surface_only:bool=false)->Dictionary:
	# Shared pure topology kernel: no Nodes, Materials, render caches or RIDs.
	if source_arrays.size()>128:return fail("模型材质槽超过 128 个")
	var surfaces:Array=[]
	for slot:int in source_arrays.size():
		var arrays:Array=source_arrays[slot]
		if arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_BONES].size() > 0: return fail("蒙皮模型暂不支持表面绘制")
		for channel in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM3 + 1):
			if arrays[channel] != null and arrays[channel].size() > 0: return fail("含自定义顶点通道的模型暂不支持表面绘制")
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := (vertices.size() if indices.is_empty() else indices.size()) / 3
		if count > MAX_TRIANGLES or count < 1: return fail("单个材质槽需包含 1–50000 个三角面")
		# Default road paint only uses the pavement slot. Still validate every
		# slot above: an oversized kerb or unsupported channel must reject just
		# as before, even though its face grouping/signature will not be used.
		if first_surface_only and slot>0:continue
		# Unpainted slots need only the count/channel checks above. Do not
		# allocate and fill sequential indices that would immediately be dropped.
		if indices.is_empty():
			indices.resize(vertices.size())
			for index:int in vertices.size():indices[index]=index
		var parents := PackedInt32Array()
		var normals := PackedVector3Array()
		var origins := PackedVector3Array()
		var edges := {}
		for triangle in count:
			parents.append(triangle)
			var a := vertices[indices[triangle * 3]]
			var b := vertices[indices[triangle * 3 + 1]]
			var c := vertices[indices[triangle * 3 + 2]]
			var normal := (c - a).cross(b - a).normalized()
			normals.append(normal); origins.append(a)
			var points := [_vertex_key(a), _vertex_key(b), _vertex_key(c)]
			for edge in 3:
				var x: String = points[edge]
				var y: String = points[(edge + 1) % 3]
				var key := x + ";" + y if x < y else y + ";" + x
				if edges.has(key):
					var other: int = edges[key]
					if normal.dot(normals[other]) > 0.99999 and absf(normal.dot(origins[other] - a)) < 0.0001:
						var p := _root_of(parents, triangle)
						var q := _root_of(parents, other)
						parents[maxi(p, q)] = mini(p, q)
				else: edges[key] = triangle
		var faces := {}
		for triangle in count:
			var face := _root_of(parents, triangle)
			parents[triangle] = face
			if not faces.has(face): faces[face] = {"triangles": [], "normal": normals[face], "center": Vector3.ZERO}
			faces[face].triangles.append(triangle)
			for corner in 3: faces[face].center += vertices[indices[triangle * 3 + corner]]
		for face in faces.values(): face.center /= float(face.triangles.size() * 3)
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256); hasher.update(var_to_bytes([vertices, indices]))
		var signature := "box-v1" if box_geometry else hasher.finish().hex_encode()
		surfaces.append({"arrays": arrays, "indices": indices, "face_for_triangle": parents, "faces": faces, "signature": signature})
	return {"ok":true,"surfaces":surfaces}

static func texture(material: Dictionary, field: String = "texture_path",path_checks:Variant=null) -> Texture2D:
	var began:=Time.get_ticks_usec() if texture_profile_enabled else 0
	var result:=_texture(material,field,path_checks)
	if texture_profile_enabled:
		TextureCache._profile_elapsed("paint.texture",began,{"path":str(material.get(field,"")),"field":field,"ok":result!=null})
	return result

static func compressed_sidecar_path(path:String,flip:bool=false,normal:bool=false)->String:
	# Worker-safe filesystem selection. Never reads or writes the main-only cache.
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return ""
	if not compressed_sidecars_enabled or path.is_empty():return ""
	return preload("res://scripts/world3d/compressed_texture_source.gd").sidecar_path(path,flip,normal)

static func has_compressed_sidecar(path:String,flip:bool=false,normal:bool=false)->bool:
	# Main-thread callers memoize the worker-safe selector for this generation.
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return false
	if not compressed_sidecars_enabled or path.is_empty():return false
	var key:=texture_key(path,flip,normal)
	if not _sidecar_cache.has(key):_sidecar_cache[key]=compressed_sidecar_path(path,flip,normal)
	return not str(_sidecar_cache[key]).is_empty()

static func _load_compressed_sidecar(path:String,flip:bool,normal:bool)->Dictionary:
	if not has_compressed_sidecar(path,flip,normal):return {}
	if texture_profile_enabled:TextureCache._profile_count("paint.texture.sidecar_main_reads")
	var sidecar:=str(_sidecar_cache[texture_key(path,flip,normal)])
	var bytes:=FileAccess.get_file_as_bytes(sidecar)
	if bytes.is_empty():return {}
	var image:=Image.new()
	if image.load_dds_from_buffer(bytes)!=OK:return {}
	return {"image":image,"alpha":sidecar.contains("dxt5"),"path":sidecar}

static func _texture(material:Dictionary,field:String,path_checks:Variant)->Texture2D:
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return null
	var path := str(material.get(field, ""))
	# A caller-owned immutable-load scope checks each path once, never across
	# separate loads or edits. Texture cache hits alone do not authorize a path.
	if not path.is_empty() and (path_checks==null or not path_checks.has(path)):
		var checked:=Time.get_ticks_usec() if texture_profile_enabled else 0
		var allowed:bool=Paths.allowed(path) and FileAccess.file_exists(path)
		if texture_profile_enabled:TextureCache._profile_elapsed("paint.texture.path_check",checked,{"path":path,"field":field,"allowed":allowed})
		if not allowed:return null
		if path_checks!=null:path_checks[path]=true
	var key := path if not path.is_empty() else (str(material.get("pattern", "")) if field == "texture_path" else "")
	var flip_normal: bool = field == "normal_path" and material.get("normal_format", "opengl") == "directx"
	var cache_key := texture_key(key,flip_normal,field=="normal_path")
	if key.is_empty(): return null
	var restored_weak:=false
	var capacity_retired_id:=0
	if not _textures.has(cache_key) and residency_budget_enabled and _texture_refs.has(cache_key):
		var retained:Texture2D=_texture_refs[cache_key].get_ref()
		var prepared:=_prepared_resource(cache_key)
		if retained!=null and (prepared==null or _same_prepared_texture(retained,prepared)):
			if _textures.size()>=64:
				var oldest:String=_textures.keys()[0]
				if capacity_eviction_accounting_enabled:capacity_retired_id=_textures[oldest].get_instance_id()
				_textures.erase(oldest);_cache_use.erase("t:"+oldest)
			_textures[cache_key]=retained;restored_weak=true
	if _textures.has(cache_key):
		_touch_cache("t:",cache_key)
		if texture_profile_enabled:TextureCache._profile_count("paint.texture.gpu_cache_hit")
		prepared_images.erase(cache_key)
		var cached:Texture2D=_textures[cache_key]
		if restored_weak:_trim_after_insert(cached,capacity_retired_id)
		else:_trim_changed_cache()
		return cached
	if not prepared_images.has(cache_key) and prepared_textures.has(cache_key):
		# A completed native streaming product already owns its GPU identity.
		# Never call get_image(), decode the source or upload a replacement here.
		var began:=Time.get_ticks_usec() if texture_profile_enabled else 0
		var texture:Texture2D=prepared_textures[cache_key]
		_store_texture(cache_key,texture)
		if texture_profile_enabled:
			TextureCache._profile_count("paint.texture.background_handoffs")
			TextureCache._profile_count("paint.texture.texture_only_handoffs")
			TextureCache._profile_elapsed("paint.texture.background_handoff",began,{"path":path,"flip":flip_normal,"texture_only":true})
		return texture
	if key!="checker" and not prepared_images.has(cache_key):
		var side:=_load_compressed_sidecar(path,flip_normal,field=="normal_path")
		if not side.is_empty():
			var side_started:=Time.get_ticks_usec() if texture_profile_enabled else 0
			var side_texture:=ImageTexture.create_from_image(side.image)
			side_texture.set_meta("runtime_texture_representation","dds:"+str(side.path))
			side_texture.set_meta("surface_has_alpha",bool(side.alpha))
			side_texture.set_meta("runtime_upload_bytes",side.image.get_data_size())
			side_texture.set_meta("runtime_normal_xy",side.image.get_format()==Image.FORMAT_RGTC_RG)
			side_texture.set_meta("runtime_source_sha256",path.sha256_text())
			if _textures.size()>=64:
				var oldest:String=_textures.keys()[0]
				if capacity_eviction_accounting_enabled:capacity_retired_id=_textures[oldest].get_instance_id()
				_textures.erase(oldest);_cache_use.erase("t:"+oldest)
			_textures[cache_key]=side_texture
			_touch_cache("t:",cache_key);_remember_weak(_texture_refs,cache_key,side_texture);_trim_after_insert(side_texture,capacity_retired_id)
			if texture_profile_enabled:
				TextureCache._profile_elapsed("paint.texture.sidecar_upload",side_started,{"path":path,"bytes":side.image.get_data_size(),"sidecar":side.path})
				TextureCache._profile_count("paint.texture.sidecar_uploads")
				TextureCache._profile_count("paint.texture.sidecar_upload_bytes",side.image.get_data_size())
				TextureCache._profile_count("paint.texture.upload_bytes",side.image.get_data_size())
			return side_texture
	var image: Image
	if texture_profile_enabled:TextureCache._profile_count("paint.texture.gpu_cache_miss")
	if key == "checker":
		image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64: image.set_pixel(x, y, Color("cba574") if (x / 16 + y / 16) % 2 == 0 else Color("526477"))
	else:
		image = prepared_images.get(cache_key)
		prepared_images.erase(cache_key)
		if texture_profile_enabled:TextureCache._profile_count("paint.texture."+("prepared_image_hit" if image!=null else "runtime_image_lookup"))
		if image==null:image = TextureCache.image(path,flip_normal)
		if image==null:return null
	# Prepared DDS already owns its complete chain. A 1x1 chain has no mip flag,
	# but still cannot be passed through the uncompressed mip generator.
	if not image.has_mipmaps() and not image.is_compressed():
		var mip_started:=Time.get_ticks_usec() if texture_profile_enabled else 0
		image.generate_mipmaps()
		if texture_profile_enabled:TextureCache._profile_elapsed("paint.texture.mipmaps",mip_started,{"path":path,"flip":flip_normal})
	# Prepared pixels are immutable for this load. Their worker already scanned
	# alpha, including RGB8's known opaque expansion; arbitrary caller images
	# retain the ordinary scan. Never infer alpha from the cached GPU texture.
	var began:=Time.get_ticks_usec() if texture_profile_enabled else 0
	var alpha_prepared:bool=image.has_meta("runtime_upload_has_alpha")
	var has_alpha:bool=image.get_meta("runtime_upload_has_alpha") if alpha_prepared else image.detect_alpha()!=Image.ALPHA_NONE
	if texture_profile_enabled:TextureCache._profile_elapsed("paint.texture.alpha",began,{"path":path,"flip":flip_normal,"prepared":alpha_prepared})
	began=Time.get_ticks_usec() if texture_profile_enabled else 0
	var result:Texture2D=prepared_textures.get(cache_key)
	# Use the exact prepared variant only while its source identity still matches.
	if result!=null and not _same_prepared_texture(result,image):result=null
	var uploaded:=result!=null
	if not uploaded:result=ImageTexture.create_from_image(image)
	if texture_profile_enabled:
		TextureCache._profile_elapsed("paint.texture.background_handoff" if uploaded else "paint.texture.upload",began,{"path":path,"flip":flip_normal,"format":image.get_format(),"width":image.get_width(),"height":image.get_height(),"bytes":image.get_data_size()})
		if uploaded:TextureCache._profile_count("paint.texture.background_handoffs")
		else:TextureCache._profile_count("paint.texture.upload_bytes",image.get_data_size())
		if not uploaded and image.has_meta("runtime_compressed_sidecar_path"):
			TextureCache._profile_count("paint.texture.sidecar_uploads")
			TextureCache._profile_count("paint.texture.sidecar_upload_bytes",image.get_data_size())
			TextureCache._profile_count("paint.texture.prepared_sidecar_uploads")
	result.set_meta("runtime_upload_bytes",image.get_data_size())
	result.set_meta("surface_has_alpha",has_alpha)
	result.set_meta("runtime_normal_xy",image.get_format()==Image.FORMAT_RGTC_RG)
	result.set_meta("runtime_source_sha256",image.get_meta("runtime_source_sha256",""))
	if image.has_meta("runtime_texture_representation"):result.set_meta("runtime_texture_representation",image.get_meta("runtime_texture_representation"))
	_store_texture(cache_key,result)
	return result

static func _store_texture(cache_key:String,result:Texture2D)->void:
	var capacity_retired_id:=0
	if _textures.size() >= 64:
		var oldest:String=_textures.keys()[0]
		if capacity_eviction_accounting_enabled:capacity_retired_id=_textures[oldest].get_instance_id()
		_textures.erase(oldest);_cache_use.erase("t:"+oldest)
	_textures[cache_key] = result
	_touch_cache("t:",cache_key);_remember_weak(_texture_refs,cache_key,result);_trim_after_insert(result,capacity_retired_id)

static func texture_error(record: Dictionary, checks: Variant = null) -> String:
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return ""
	# A declared image that cannot decode must not silently become an untextured
	# material in a new export. Cache only within the caller's immutable operation.
	for definition: Dictionary in definitions(record):
		for field: String in MAP_FIELDS:
			var path: String=definition.get(field,"")
			if path.is_empty():continue
			var key: Array=["decoded_texture",definition_texture_key(definition,field)]
			var valid_image: bool
			if checks!=null and checks.has(key):valid_image=checks[key]
			else:
				valid_image=texture(definition,field,checks)!=null
				if checks!=null:checks[key]=valid_image
			if not valid_image:return "材质贴图无法读取："+path
	return ""

static func make_material(value: Dictionary, cull_mode: int = BaseMaterial3D.CULL_BACK) -> StandardMaterial3D:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.surface_materials.make_material") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var began:=Time.get_ticks_usec() if texture_profile_enabled else 0
	var result:=_make_material(value,cull_mode)
	if texture_profile_enabled:TextureCache._profile_elapsed("paint.material",began,{"name":str(value.get("name","")),"cull":cull_mode})
	return result

static func _make_material(value:Dictionary,cull_mode:int)->StandardMaterial3D:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.surface_materials._make_material") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Paint definitions are immutable; UVs live on the mesh. Reuse equivalent
	# materials so glTF packs ORM textures once, not once for every wall face.
	var key := str(cull_mode) + "|" + JSON.stringify(value, "", true)
	var restored_weak:=false
	if not _materials.has(key) and residency_budget_enabled and _material_refs.has(key):
		var retained:StandardMaterial3D=_material_refs[key].get_ref()
		if retained!=null and _material_current(retained):
			if _materials.size()>=128:
				var oldest:String=_materials.keys()[0];_materials.erase(oldest);_cache_use.erase("m:"+oldest)
			_materials[key]=retained;restored_weak=true
	if _materials.has(key):
		_touch_cache("m:",key)
		if texture_profile_enabled:TextureCache._profile_count("paint.material.cache_hit")
		var cached:StandardMaterial3D=_materials[key]
		if restored_weak:_trim_after_insert(cached)
		else:_trim_changed_cache()
		return cached
	if texture_profile_enabled:TextureCache._profile_count("paint.material.cache_miss")
	var result := StandardMaterial3D.new()
	result.cull_mode = cull_mode
	result.resource_name = value.name
	result.albedo_color = Color(value.color[0], value.color[1], value.color[2], value.color[3])
	result.roughness = value.roughness
	result.albedo_texture = texture(value)
	result.normal_texture = texture(value, "normal_path")
	result.normal_enabled = result.normal_texture != null
	result.normal_scale = float(value.get("normal_strength", 1.0))
	result.roughness_texture = texture(value, "roughness_path")
	result.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	result.metallic_texture = texture(value, "metallic_path")
	result.metallic = float(value.get("metallic", 1.0 if result.metallic_texture != null else 0.0))
	result.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	result.ao_texture = texture(value, "ao_path")
	result.ao_enabled = result.ao_texture != null
	result.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	result.texture_repeat = true
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if result.albedo_color.a < 1 or (result.albedo_texture != null and bool(result.albedo_texture.get_meta("surface_has_alpha",false))): result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if _materials.size() >= 128:
		var oldest:String=_materials.keys()[0];_materials.erase(oldest);_cache_use.erase("m:"+oldest)
	result.set_meta("runtime_paint_definition",value.duplicate(true))
	_materials[key] = result
	_touch_cache("m:",key);_remember_weak(_material_refs,key,result);_trim_after_insert(result)
	return result

static func _uvs(data: Dictionary, entry: Dictionary) -> PackedVector2Array:
	var vertices: PackedVector3Array = data.arrays[Mesh.ARRAY_VERTEX]
	var original: Variant = data.arrays[Mesh.ARRAY_TEX_UV]
	if uv_projection_elision_enabled and entry.mapping=="uv" and original!=null and original.size()==vertices.size():
		# Authored UV coordinates do not depend on the face plane or its bounds.
		# Transform a private packed array; do not traverse every triangle only
		# to discard the projection, or rebuild the same transform per vertex.
		var result:PackedVector2Array=original.duplicate()
		var angle:=deg_to_rad(entry.rotation)
		var scale_:=Vector2(entry.scale[0],entry.scale[1])
		var offset_:=Vector2(0.5+entry.offset[0],0.5+entry.offset[1])
		for i:int in result.size():result[i]=(result[i]-Vector2(0.5,0.5)).rotated(angle)*scale_+offset_
		return result
	var uv := PackedVector2Array()
	var face: Dictionary = data.faces[int(entry.face)]
	var normal: Vector3 = face.normal
	var u := (Vector3.RIGHT - normal * normal.x).normalized() if absf(normal.x) < 0.9 else (Vector3.BACK - normal * normal.z).normalized()
	var v := normal.cross(u).normalized()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for triangle in face.triangles:
		for corner in 3:
			var vertex := vertices[data.indices[triangle * 3 + corner]]
			var point := Vector2(vertex.dot(u), vertex.dot(v))
			low = low.min(point); high = high.max(point)
	var dimensions := (high - low).max(Vector2(0.00001, 0.00001))
	for i in vertices.size():
		var point: Vector2 = original[i] if entry.mapping == "uv" and original != null and original.size() == vertices.size() else (Vector2(vertices[i].dot(u), vertices[i].dot(v)) - low) / dimensions
		if entry.mapping == "meters":
			var tile: Array = entry.material.get("tile_size", [1.0, 1.0])
			point = (Vector2(vertices[i].dot(u), vertices[i].dot(v)) - low) / Vector2(tile[0], tile[1])
		point = (point - Vector2(0.5, 0.5)).rotated(deg_to_rad(entry.rotation)) * Vector2(entry.scale[0], entry.scale[1]) + Vector2(0.5 + entry.offset[0], 0.5 + entry.offset[1])
		uv.append(point)
	return uv

static func _compact(arrays: Array) -> Array:
	# Keep only referenced vertices; each painted face must not duplicate the whole model.
	var old_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var unique := PackedInt32Array()
	var indices := PackedInt32Array()
	var remap := {}
	for old in old_indices:
		if not remap.has(old): remap[old] = unique.size(); unique.append(old)
		indices.append(remap[old])
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var result := arrays.duplicate()
	for channel in Mesh.ARRAY_INDEX:
		var values: Variant = arrays[channel]
		if values == null or values.size() == 0: continue
		var stride: int = values.size() / count
		var packed: Variant = values.slice(0, 0)
		for old in unique:
			for component in stride: packed.append(values[old * stride + component])
		result[channel] = packed
	result[Mesh.ARRAY_INDEX] = indices
	return result

static func source_material(node: MeshInstance3D, slot: int) -> Material:
	# Runtime wind is a temporary instance override, never an authored paint source.
	if node.has_meta("wind_original"):
		var original: Dictionary = node.get_meta("wind_original")
		if original.override != null: return original.override
		if original.surfaces[slot] != null: return original.surfaces[slot]
		return node.mesh.surface_get_material(slot)
	return node.get_active_material(slot)

static func paint_texture_error(entries:Array,texture_checks:Variant=null,texture_owners:Variant=null)->String:
	var checked:Array=[]
	for entry:Dictionary in entries:
		if entry.material in checked:continue
		checked.append(entry.material)
		var key:=var_to_str(entry.material)
		if texture_checks!=null and texture_checks.has(key):continue
		for field:String in MAP_FIELDS:
			if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures or str(entry.material.get(field,"")).is_empty():continue
			var owner:=texture(entry.material,field)
			if owner==null:return "表面贴图缺失或损坏："+field
			if texture_owners!=null:texture_owners.append(owner)
		if texture_checks!=null:texture_checks[key]=true
	return ""

static func validate_paint(node:MeshInstance3D,entries:Array,texture_checks:Variant=null)->Dictionary:
	# An editor transaction needs these checks before changing the document,
	# not a temporary GPU mesh/material that is immediately discarded.
	var first_only:bool=not entries.is_empty() and entries.all(func(entry):return int(entry.surface)==0)
	var geo := geometry(node,first_only)
	if not geo.ok: return geo
	var mesh := source(node)
	var overrides := {}
	var checked_materials: Array = []
	var texture_owners:Array[Texture2D]=[]
	for entry in entries:
		var slot := int(entry.surface)
		if slot >= geo.surfaces.size() or not geo.surfaces[slot].faces.has(int(entry.face)) or geo.surfaces[slot].signature != entry.geometry: return fail("模型几何已改变，请先清除旧面材质再重新绘制")
		# The optional cache belongs to one immutable runtime load. Ordinary
		# editor paint operations still check paths/textures afresh every time.
		if not entry.material in checked_materials:
			var texture_issue:=paint_texture_error([entry],texture_checks,texture_owners)
			if not texture_issue.is_empty():return fail(texture_issue)
			checked_materials.append(entry.material)
		var source_uv: Variant = geo.surfaces[slot].arrays[Mesh.ARRAY_TEX_UV]
		if entry.mapping == "uv" and (source_uv == null or source_uv.size() != geo.surfaces[slot].arrays[Mesh.ARRAY_VERTEX].size()): return fail("这个模型没有原始 UV，请选择平面投影")
		overrides["%d:%d" % [slot, entry.face]] = entry
	if mesh.get_surface_count() + entries.size() > 256: return fail("绘制后材质槽超过 256 个，请拆分模型")
	# Transaction-scoped GPU owners survive cache eviction until the final mesh
	# owns them. This does not increase the retained-cache budget or copy pixels.
	return {"ok":true,"geometry":geo,"overrides":overrides,"texture_owners":texture_owners}

static func painted_mesh(node: MeshInstance3D, entries: Array, keep_cpu: bool=false, texture_checks: Variant=null, defer_upload:bool=false, prepared_paint:Dictionary={}) -> Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.surface_materials.painted_mesh") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if defer_upload and not prepared_paint.is_empty():
		var prepared:Dictionary=load("res://scripts/world3d/surface_paint_preparation.gd").publish(node,entries,prepared_paint,texture_checks)
		if not prepared.is_empty():return prepared
	if keep_cpu: CpuMesh.capture(source(node))
	var validation:=validate_paint(node,entries,texture_checks)
	if not validation.ok:return validation
	var geo:Dictionary=validation.geometry
	var overrides:Dictionary=validation.overrides
	var mesh:=source(node)
	var output:Mesh
	var cpu_arrays: Array=[]
	var output_materials:Array=[]
	var merged:Dictionary={}
	for slot in mesh.get_surface_count():
		# Surface-zero paint (ordinary roads) needs face topology only there.
		# geometry() still validated every other slot's topology/channel limits.
		# Untouched surfaces keep their exact vertices, indices and material.
		var data:Dictionary
		if slot<geo.surfaces.size():data=geo.surfaces[slot]
		else:
			var arrays:Array=CpuMesh.capture(mesh).surfaces[slot]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			if indices.is_empty():
				indices.resize(arrays[Mesh.ARRAY_VERTEX].size())
				for i in indices.size():indices[i]=i
			data={"arrays":arrays,"indices":indices,"faces":{},"face_for_triangle":PackedInt32Array()}
		var groups := {}
		var group_entries := {}
		var face_groups := {}
		# Original UV mapping is independent of the face plane. Identical UV
		# paint can share a draw surface while retaining per-face authoring data.
		# Curved walls otherwise export thousands of identical material slots.
		for face in data.faces:
			var face_key := "%d:%d" % [slot, face]
			if not overrides.has(face_key): continue
			var entry: Dictionary = overrides[face_key]
			var group_key := face_key
			if entry.mapping == "uv": group_key = "uv:" + JSON.stringify([entry.material, entry.scale, entry.offset, entry.rotation], "", true)
			face_groups[face_key] = group_key
			group_entries[group_key] = entry
		for triangle in data.face_for_triangle.size():
			var face: int = data.face_for_triangle[triangle]
			var key := "%d:%d" % [slot, face]
			key = face_groups.get(key, "original")
			if not groups.has(key): groups[key] = PackedInt32Array()
			for corner in 3: groups[key].append(data.indices[triangle * 3 + corner])
		if slot>=geo.surfaces.size():groups.original=data.indices
		for key in groups:
			var arrays: Array = data.arrays.duplicate()
			arrays[Mesh.ARRAY_INDEX] = groups[key]
			var material: Material = node.get_meta("paint_source_materials")[slot] if node.has_meta("paint_source_materials") else source_material(node,slot)
			if key != "original":
				arrays[Mesh.ARRAY_TEX_UV] = _uvs(data, group_entries[key])
				# Painted diffuse UVs differ from the source normal-map tangent space.
				arrays[Mesh.ARRAY_TANGENT] = null
				var painted := make_material(group_entries[key].material, material.cull_mode if material is BaseMaterial3D else BaseMaterial3D.CULL_BACK)
				material = painted
			# An untouched complete surface already has its exact vertex/index
			# mapping. Repacking every kerb vertex performs no useful geometry work.
			var source_indices:Variant=data.arrays[Mesh.ARRAY_INDEX]
			var complete_vertices:bool=source_indices==null or source_indices.is_empty()
			var compact:Array=arrays if preserve_complete_surfaces_enabled and key=="original" and groups.size()==1 and complete_vertices else _compact(arrays)
			if key != "original" and material is BaseMaterial3D and material.normal_enabled:
				# SurfaceTool reads Mesh arrays. Keep this temporary on the CPU:
				# uploading then reading every painted face stalls the render queue.
				var temporary := CpuMesh.new()
				temporary.surfaces = [compact]
				temporary.materials = [material]
				var builder := SurfaceTool.new()
				builder.create_from(temporary, 0); builder.generate_tangents()
				compact = builder.commit_to_arrays()
			# UVs/tangents are already baked per face. Their identical materials
			# now share one GPU surface instead of allocating a RID for every face.
			var layout:=0
			for channel in Mesh.ARRAY_MAX:
				if compact[channel]!=null and not compact[channel].is_empty():layout|=1<<channel
			var merge_key:=str(material.get_instance_id() if material!=null else 0)+":"+str(layout)
			if not merged.has(merge_key):
				merged[merge_key]={"builder":null,"arrays":compact,"material":material}
				if preserve_complete_surfaces_enabled:continue
			var row:Dictionary=merged[merge_key]
			if row.builder==null:
				row.builder=SurfaceTool.new()
				if preserve_complete_surfaces_enabled:
					var first:=CpuMesh.new();first.surfaces=[row.arrays];first.materials=[material]
					row.builder.append_from(first,0,Transform3D.IDENTITY)
				row.arrays=[]
			var cpu:=CpuMesh.new();cpu.surfaces=[compact];cpu.materials=[material]
			row.builder.append_from(cpu,0,Transform3D.IDENTITY)
	for row in merged.values():
		var arrays:Array=row.arrays if row.builder==null else row.builder.commit_to_arrays()
		cpu_arrays.append(arrays);output_materials.append(row.material)
	if defer_upload:output=CpuMesh.from_surfaces(cpu_arrays,output_materials)
	else:
		output=ArrayMesh.new()
		for slot in cpu_arrays.size():
			output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,cpu_arrays[slot])
			output.surface_set_material(slot,output_materials[slot])
		if keep_cpu:CpuMesh.remember(output,cpu_arrays)
	return {"ok": true, "mesh": output}

static func apply(root: Node3D, record: Dictionary, validation_cache: Variant=null, texture_checks: Variant=null, defer_upload:bool=false, prepared_paint:Dictionary={}) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.surface_materials.apply") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not record.has("surface_paint"): return
	if not valid(record,false,"",validation_cache): root.set_meta("paint_error", "表面材质记录损坏"); return
	var unresolved: Array = record.surface_paint.duplicate()
	for node in meshes(root):
		var path := str(root.get_path_to(node))
		var entries: Array = record.surface_paint.filter(func(entry): return entry.mesh == path)
		if entries.is_empty(): continue
		for entry in entries: unresolved.erase(entry)
		var result := painted_mesh(node, entries, true, texture_checks,defer_upload,prepared_paint if path=="." else {})
		if not result.ok: root.set_meta("paint_error", result.error); continue
		var originals: Array = []
		for slot in node.mesh.get_surface_count(): originals.append(source_material(node,slot))
		node.set_meta("paint_source_materials", originals)
		node.set_meta("paint_source", node.mesh)
		# Reset the old per-instance slots while detaching their render mesh.
		# CPU-only meshes deliberately have no renderer surfaces, so setters for
		# their logical slots cannot be sent to RenderingServer.
		node.mesh = null
		node.mesh = result.mesh
		node.material_override = null
	if not unresolved.is_empty(): root.set_meta("paint_error", "模型节点已改变，请清除旧面材质")

static func definitions(record: Dictionary, include_paint:bool=true) -> Array:
	if record.has("house_prefab"):
		var definitions_:Array=record.get("prefab_materials",[]).duplicate()
		if include_paint:
			for entry in record.get("surface_paint",[]):definitions_.append(entry.material)
		return definitions_
	var result: Array=[]
	if record.has("road_kerb_material"):result.append(record.road_kerb_material)
	if record.has("banner"):result.append(record.banner.material)
	result.append_array(record.get("bridge_materials",{}).values())
	result.append_array(record.get("rock_bank_materials",{}).values())
	result.append_array(record.get("fortification_materials",{}).values())
	result.append_array(record.get("terrain_regions",{}).get("materials",[]))
	if include_paint:
		for entry in record.get("surface_paint",[]): result.append(entry.material)
	if record.has("terrain_material"): result.append(record.terrain_material)
	if record.has("terrain_depth_blend"):
		for key in ["sand_material","rock_material"]: result.append(record.terrain_depth_blend[key])
	if record.has("terrain_slope_blend"): result.append(record.terrain_slope_blend.rock_material)
	for field in ["terrain_depth_blend","terrain_slope_blend"]:
		if record.get(field,{}).has("transition_material"): result.append(record[field].transition_material)
	return result

static func missing(records: Array) -> Array:
	var paths: Array = []
	var checked:Dictionary={}
	for record in records:
		if record.has("fortification_art"):
			var model_path:String=record.fortification_art.asset_path
			if not checked.has(model_path):checked[model_path]=preload("res://scripts/world_editor/asset_library.gd").native_available(model_path)
			if not checked[model_path]:paths.append(model_path)
		for definition in definitions(record):
			for field in MAP_FIELDS:
				var path := str(definition.get(field, ""))
				if path.is_empty():continue
				if not checked.has(path):checked[path]=FileAccess.file_exists(path)
				if not checked[path] and not paths.has(path):paths.append(path)
	return paths

static func _face_shape(data: Dictionary, face: int) -> Array:
	# Import/export can reorder or weld vertices. Compare actual triangles at fixed precision.
	var triangles: Array = []
	var vertices: PackedVector3Array = data.arrays[Mesh.ARRAY_VERTEX]
	for triangle in data.faces[face].triangles:
		var points: Array = []
		for corner in 3: points.append(_vertex_key(vertices[data.indices[triangle * 3 + corner]]))
		points.sort(); triangles.append(";".join(points))
	triangles.sort()
	return triangles

static func remap(entries: Array, before: Node3D, after: Node3D) -> Dictionary:
	var result: Array = []
	var old_meshes := {}; var new_meshes := {}
	for node in meshes(before): old_meshes[str(before.get_path_to(node))] = node
	for node in meshes(after): new_meshes[str(after.get_path_to(node))] = node
	for entry in entries:
		if not old_meshes.has(entry.mesh) or not new_meshes.has(entry.mesh): return fail("打包模型的节点结构改变，无法匹配已绘制表面")
		var old_geo := geometry(old_meshes[entry.mesh])
		var new_geo := geometry(new_meshes[entry.mesh])
		if not old_geo.ok or not new_geo.ok: return fail("模型网格不支持材质重映射")
		var slot := int(entry.surface)
		if slot >= old_geo.surfaces.size() or not old_geo.surfaces[slot].faces.has(int(entry.face)) or old_geo.surfaces[slot].signature != entry.geometry: return fail("原模型表面已变化")
		var old_data: Dictionary = old_geo.surfaces[slot]
		var shape := _face_shape(old_data, int(entry.face))
		var matches: Array = []
		for new_slot in new_geo.surfaces.size():
			var data: Dictionary = new_geo.surfaces[new_slot]
			for face in data.faces:
				if data.faces[face].triangles.size() != old_data.faces[int(entry.face)].triangles.size(): continue
				if data.faces[face].normal.dot(old_data.faces[int(entry.face)].normal) < 0.99999: continue
				if _face_shape(data, face) == shape: matches.append({"surface": new_slot, "face": face, "geometry": data.signature})
		if matches.size() != 1: return fail("打包模型的表面匹配不唯一，预制件未保存")
		var copy: Dictionary = entry.duplicate(true)
		copy.merge(matches[0], true)
		result.append(copy)
	return {"ok": true, "entries": result}
