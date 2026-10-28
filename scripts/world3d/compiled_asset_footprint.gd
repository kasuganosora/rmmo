extends RefCounted
## Offline native-resource accounting. Runtime trusts the package's published
## identity and budget; explicit audits can still check source and generators.
## Never fall back to GLTF inside a smaller native reservation.
const Compiled = preload("res://scripts/world3d/compiled_asset_cache.gd")
const Preparation = preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Atomic = preload("res://scripts/world3d/atomic_file.gd")
const Drainer = preload("res://scripts/world3d/asset_worker_drainer.gd")
# Serialized accounting contract. Incompatible estimate/format changes must
# bump this revision and republish; runtime reader edits are not format changes.
const VERSION := 1
const DIRECT_TEMPLATE_REUSE_VERSION := 1
const COLLISION_ABSENCE_VERSION := 1
const COLLISION_VISUAL_EXTRAS := ["uuid", "rmmo_collision", "rmmo_grass", "rmmo_leaf_backlight", "rmmo_visibility_range", "rmmo_wind"]
const FLOOR_BYTES := 64 * 1024 * 1024
const EXCLUSIVE_BYTES := 4 * 1024 * 1024 * 1024
const MAX_BYTES := 1024 * 1024 * 1024 * 1024
const MAX_DESCRIPTOR_BYTES := 65536
# Schema maximum: 4096 ASCII member IDs (<=180) each with a 180-character
# escaped part name, 256 region IDs and 256 fixture IDs (<=180 each), bounded
# finite numbers and structural keys. Worst-case JSON escaping is <=6 bytes per
# character; the outer body may escape each byte again. 16 MiB bounds that
# complete valid schema without changing the ordinary footprint read limit.
const BUILDING_DESCRIPTOR_MAX_BYTES := 16 * 1024 * 1024
const STAT_KEYS := ["nodes", "resources", "materials", "meshes", "textures", "images", "surfaces", "image_mip_bytes", "gpu_rgba_bytes", "mesh_storage_bytes", "mesh_capture_bytes", "collision_face_bytes", "other_packed_bytes", "container_bytes", "native_uncompressed_bytes"]

static func directory(content_root: String) -> String:
	return Compiled.directory(content_root).path_join("footprints_v1")

static func descriptor_path(path: String, content_root: String) -> String:
	return directory(content_root).path_join(_path(path).sha256_text() + ".json")

static func building_descriptor_path(path:String,content_root:String)->String:
	return directory(content_root).path_join(_path(path).sha256_text()+".building.json")

static func generator() -> String:
	# This invalidates only footprints, never an existing native product.
	return (str(VERSION) + ":" + FileAccess.get_sha256("res://scripts/world3d/compiled_asset_footprint.gd")).sha256_text()

static func candidate(path: String, content_root: String, expected_source: String = "", trusted_package: bool = false, expected_product_generator: String = "", metadata: Variant = null, file_identities: Variant = null) -> Dictionary:
	if content_root.is_empty() or not Compiled.enabled: return {}
	if not expected_source.is_empty() and not Compiled._sha(expected_source): return {}
	var identity := _identity(path, content_root, trusted_package, expected_product_generator, file_identities)
	if identity.is_empty() or (not expected_source.is_empty() and identity.source_sha != expected_source): return {}
	var filename := descriptor_path(path, content_root)
	if not Paths.allowed(filename, directory(content_root)): return {}
	var envelope := _read_json(filename, MAX_DESCRIPTOR_BYTES, file_identities)
	var body: Variant = envelope.get("body")
	if envelope.get("version") != VERSION or not body is String: return {}
	if not trusted_package and (not Compiled._sha(envelope.get("sha256")) or body.sha256_text() != envelope.sha256): return {}
	var descriptor: Variant = JSON.parse_string(body)
	if not descriptor is Dictionary or descriptor.get("version") != VERSION: return {}
	if not trusted_package and descriptor.get("footprint_generator") != generator(): return {}
	for key in ["source_path", "source_sha", "payload_sha", "generator", "bytes"]:
		if descriptor.get(key) != identity[key]: return {}
	var estimate:Dictionary
	if trusted_package:
		# These are offline decoded-resource bounds, never compressed file size.
		# Reader edits and instrumentation do not invalidate published accounting.
		if not _integer(descriptor.get("estimated_bytes"), MAX_BYTES, 1) or descriptor.get("resident_bytes") != descriptor.estimated_bytes: return {}
		var amount:int=int(descriptor.estimated_bytes)
		estimate={"estimated_bytes":amount,"resident_bytes":amount,"exclusive":amount>EXCLUSIVE_BYTES}
	else:
		if descriptor.get("source_bytes") != identity.source_bytes: return {}
		var stats: Variant = descriptor.get("stats")
		if not stats is Dictionary: return {}
		estimate=estimate_stats(stats)
		if estimate.is_empty() or descriptor.get("estimated_bytes") != estimate.estimated_bytes or descriptor.get("resident_bytes") != estimate.resident_bytes: return {}
	# Freeze the exact product identity. Do not derive it from another manifest
	# read later, and do not mistake these unhashed source bytes for verification.
	identity.merge(estimate)
	var direct:Variant=descriptor.get("direct_template_reuse")
	identity.direct_template_reuse_safe=direct is Dictionary and direct.get("version")==DIRECT_TEMPLATE_REUSE_VERSION and direct.get("safe") is bool and direct.safe
	var absence:Variant=descriptor.get("collision_absence")
	identity.collision_none_safe=absence is Dictionary and absence.get("version")==COLLISION_ABSENCE_VERSION and absence.get("safe_for_explicit_none") is bool and absence.safe_for_explicit_none
	if metadata is Dictionary: metadata.assign(descriptor)
	identity.erase("source_bytes")
	return identity

static func _identity(path: String, content_root: String, trusted_package:bool=false, expected_product_generator:String="", file_identities:Variant=null) -> Dictionary:
	path = _path(path)
	if content_root.is_empty(): return {}
	if not (Paths.asset_key_allowed(path,content_root) if trusted_package else Paths.allowed(path,content_root)): return {}
	var source_bytes:=-1
	if not trusted_package:
		var source := FileAccess.open(path, FileAccess.READ)
		if source == null: return {}
		source_bytes=source.get_length(); source.close()
	var folder := Compiled.directory(content_root)
	if not Paths.allowed(folder, content_root): return {}
	var index := Compiled.index_path(path, content_root)
	if not Paths.allowed(index, folder): return {}
	var manifest := _read_json(index, 8192, file_identities)
	if manifest.get("version") != Compiled.VERSION or not manifest.get("generator") is String: return {}
	if not trusted_package and manifest.generator != Compiled.generator(): return {}
	if not expected_product_generator.is_empty() and manifest.generator != expected_product_generator: return {}
	if not Compiled._sha(manifest.get("source_sha")) or not Compiled._sha(manifest.get("payload_sha")) or not Compiled.valid_payload_size(manifest.get("bytes")): return {}
	var product := folder.path_join(manifest.payload_sha + ".scn")
	if not Paths.allowed(product, folder): return {}
	var file := FileAccess.open(product, FileAccess.READ)
	if file == null: return {}
	var size := file.get_length(); file.close()
	if size != int(manifest.bytes): return {}
	return {"source_path":path, "source_sha":manifest.source_sha, "payload_sha":manifest.payload_sha, "generator":manifest.generator, "bytes":size, "source_bytes":source_bytes, "product":product}

static func build(path: String, content_root: String = "", preserve_published:bool = false) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or DisplayServer.get_name() == "headless": return {"ok":false, "reason":"main_graphics_thread_required"}
	if content_root.is_empty(): content_root = Paths.external_root()
	var before := _identity(path, content_root, preserve_published)
	if before.is_empty(): return {"ok":false, "reason":"native_identity_unknown"}
	# Explicit migration may measure an already published conversion without
	# rebuilding its SCN solely because today's producer code hash changed.
	# Preserve the original generator and require the actual import source to
	# match; a changed source needs a deliberate reimport, never relabelling.
	if preserve_published:
		if not Paths.allowed(path,content_root) or FileAccess.get_sha256(path)!=before.source_sha:return {"ok":false,"reason":"reimport_required"}
		var source:=FileAccess.open(path,FileAccess.READ)
		if source==null:return {"ok":false,"reason":"source_missing"}
		before.source_bytes=source.get_length();source.close()
	# Freeze the payload itself: a manifest A -> B -> A change must never bind
	# statistics for B to the descriptor for A.
	var loaded := Preparation.read(before.source_path, before, content_root,Callable(),false,false,"",preserve_published)
	if loaded.get("error", FAILED) != OK or loaded.get("fallback_required", false) or loaded.get("packed") == null:
		var reason := str(loaded.get("cache_reason", loaded.get("error", "unknown")))
		Drainer.synchronize_transfer(); loaded.clear()
		return {"ok":false, "reason":"native_read:" + reason}
	var reuse:Dictionary={}
	var stats := measure(loaded.packed,reuse)
	var building:Dictionary=load("res://scripts/world3d/imported_building.gd").describe_packed(loaded.packed,before.source_sha)
	var absence:=collision_absence_from_packed(loaded.packed)
	Drainer.synchronize_transfer()
	loaded.clear()
	if stats.is_empty(): return {"ok":false, "reason":"unsupported_resource_statistics"}
	if not building.get("ok",false):return {"ok":false,"reason":"invalid_native_building_descriptor"}
	var uncompressed := native_uncompressed_bytes(before.product)
	if uncompressed <= 0: return {"ok":false, "reason":"native_compression_header_unknown"}
	stats.native_uncompressed_bytes = uncompressed
	var estimate := estimate_stats(stats)
	if estimate.is_empty(): return {"ok":false, "reason":"unbounded_estimate"}
	var model_metadata:=_source_metadata(path)
	if model_metadata.is_empty():return {"ok":false,"reason":"source_bounds_unknown"}
	# Statistics can perform renderer readback. Recheck the complete source and
	# product afterward, and ensure the index did not change while measuring.
	var after:=_identity(path, content_root, preserve_published)
	if preserve_published and not after.is_empty():after.source_bytes=before.source_bytes
	if after != before or FileAccess.get_sha256(before.source_path) != before.source_sha or FileAccess.get_sha256(before.product) != before.payload_sha:
		return {"ok":false, "reason":"identity_changed_during_measurement"}
	var descriptor := before.duplicate()
	descriptor.erase("product")
	descriptor.merge({"version":VERSION, "footprint_generator":generator(), "stats":stats, "estimated_bytes":estimate.estimated_bytes, "resident_bytes":estimate.resident_bytes})
	descriptor.model_metadata=model_metadata
	descriptor.direct_template_reuse={"version":DIRECT_TEMPLATE_REUSE_VERSION,"safe":reuse.get("safe",false)}
	descriptor.collision_absence=absence
	var building_error:=_publish_building(path,content_root,before,building)
	if building_error!=OK:return {"ok":false,"reason":"building_descriptor_write","error":building_error}
	var destination := descriptor_path(path, content_root)
	var result := _publish(descriptor, destination, content_root)
	if result != OK: return {"ok":false, "reason":"descriptor_write", "error":result}
	return {"ok":true, "path":before.source_path, "descriptor":destination, "candidate":candidate(path, content_root, before.source_sha,preserve_published), "stats":stats,"building_present":building.present}

# Immutable source facts alongside the existing full native budget.
# No geometry or texture data is duplicated. JSON carries AABB as six numbers.
static func _source_metadata(path:String)->Dictionary:
	var bounds:Dictionary=preload("res://scripts/world3d/asset_bounds_manifest.gd").read(path)
	if not bounds.get("known",false) or not bounds.get("local_bounds") is AABB:return {}
	var box:AABB=bounds.local_bounds
	return {"version":1,"local_bounds":[box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z],"json_sha256":bounds.json_sha256,"file_length":bounds.file_length,"json_bytes":bounds.json_bytes}

# Explicit offline conversion of existing native footprints. Never modifies the
# SCN or source. The before/after observations protect the publication transaction;
# no part of this work runs in the gameplay reader.
static func refresh_bounds(path:String,content_root:String)->Dictionary:
	if content_root.is_empty() or not Paths.allowed(path,content_root):return {"ok":false,"reason":"source_path"}
	var descriptor:Dictionary={}
	var candidate_:=candidate(path,content_root,"",true,"",descriptor)
	if candidate_.is_empty():return {"ok":false,"reason":"native_footprint_missing"}
	var target:=descriptor_path(path,content_root)
	var descriptor_sha:=FileAccess.get_sha256(target)
	if FileAccess.get_sha256(path)!=candidate_.source_sha or FileAccess.get_sha256(candidate_.product)!=candidate_.payload_sha:
		return {"ok":false,"reason":"source_or_product_changed"}
	var observation:=_source_metadata(path)
	if observation.is_empty() or observation.file_length!=descriptor.get("source_bytes"):
		return {"ok":false,"reason":"source_bounds_unknown"}
	if FileAccess.get_sha256(path)!=candidate_.source_sha or FileAccess.get_sha256(target)!=descriptor_sha or candidate(path,content_root,"",true)!=candidate_:
		return {"ok":false,"reason":"identity_changed_during_refresh"}
	descriptor.model_metadata=observation
	var error:=_publish(descriptor,target,content_root)
	return {"ok":error==OK,"error":error,"descriptor":target,"source":path,"product":candidate_.product}

# Explicit offline refresh for already published descriptors. The source and
# product stay unchanged; never perform this resource walk during gameplay.
static func refresh_direct_template_reuse(path:String,content_root:String)->Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or DisplayServer.get_name()=="headless":return {"ok":false,"reason":"main_graphics_thread_required"}
	if content_root.is_empty() or not Paths.asset_key_allowed(path,content_root):return {"ok":false,"reason":"source_path"}
	var descriptor:Dictionary={}
	var offered:=candidate(path,content_root,"",true,"",descriptor)
	if offered.is_empty():return {"ok":false,"reason":"native_footprint_missing"}
	var target:=descriptor_path(path,content_root);var descriptor_sha:=FileAccess.get_sha256(target)
	if FileAccess.get_sha256(offered.product)!=offered.payload_sha:return {"ok":false,"reason":"product_changed"}
	var packet:=Preparation.read(path,offered,content_root,Callable(),true)
	if packet.get("error",FAILED)!=OK or not packet.get("packed") is PackedScene:
		Drainer.dispose_result(packet);return {"ok":false,"reason":"native_read"}
	var reuse:Dictionary={};var stats:=measure(packet.packed,reuse)
	Drainer.dispose_result(packet)
	if stats.is_empty():return {"ok":false,"reason":"unsupported_resource_statistics"}
	if FileAccess.get_sha256(offered.product)!=offered.payload_sha or FileAccess.get_sha256(target)!=descriptor_sha or candidate(path,content_root,"",true)!=offered:
		return {"ok":false,"reason":"identity_changed_during_measurement"}
	descriptor.direct_template_reuse={"version":DIRECT_TEMPLATE_REUSE_VERSION,"safe":reuse.get("safe",false)}
	var error:=_publish(descriptor,target,content_root)
	return {"ok":error==OK,"error":error,"descriptor":target,"safe":descriptor.direct_template_reuse.safe}

## Explicit offline migration for an existing published product; no source GLB.
## Product is read before the sidecar is atomically published and bound to the
## exact source/payload identity observed through the existing footprint.
static func refresh_imported_building(path:String,content_root:String)->Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or DisplayServer.get_name()=="headless":return {"ok":false,"reason":"main_graphics_thread_required"}
	if content_root.is_empty() or not Paths.asset_key_allowed(path,content_root):return {"ok":false,"reason":"source_path"}
	var offered:=candidate(path,content_root,"",true)
	if offered.is_empty():return {"ok":false,"reason":"native_footprint_missing"}
	var packet:=Preparation.read(path,offered,content_root,Callable(),true,false,"",true)
	if packet.get("error",FAILED)!=OK or not packet.get("packed") is PackedScene:
		Drainer.dispose_result(packet);return {"ok":false,"reason":"native_read"}
	var result:Dictionary=load("res://scripts/world3d/imported_building.gd").describe_packed(packet.packed,offered.source_sha)
	Drainer.dispose_result(packet)
	if not result.get("ok",false):return {"ok":false,"present":true,"reason":"invalid_native_building_descriptor"}
	if candidate(path,content_root,"",true)!=offered:return {"ok":false,"reason":"native_identity_changed"}
	var error:=_publish_building(path,content_root,offered,result)
	return {"ok":error==OK,"present":result.present,"error":error,"descriptor":building_descriptor_path(path,content_root)}

## Explicit optional migration only. A missing/unsafe contract merely disables
## the collision:none shortcut; it never prevents normal native rendering.
## Read the already published SCN once, without opening its authoring source.
static func refresh_collision_absence(path:String,content_root:String)->Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or DisplayServer.get_name()=="headless":return {"ok":false,"reason":"main_graphics_thread_required"}
	var descriptor:Dictionary={}
	var offered:=candidate(path,content_root,"",true,"",descriptor)
	if offered.is_empty():return {"ok":false,"reason":"native_footprint_missing"}
	var target:=descriptor_path(path,content_root);var before:=FileAccess.get_sha256(target)
	var packet:=Preparation.read(path,offered,content_root,Callable(),false,false,"",true)
	if packet.get("error",FAILED)!=OK or not packet.get("packed") is PackedScene:
		Drainer.dispose_result(packet);return {"ok":false,"reason":"native_read"}
	var absence:=collision_absence_from_packed(packet.packed)
	Drainer.dispose_result(packet)
	if FileAccess.get_sha256(offered.product)!=offered.payload_sha or FileAccess.get_sha256(target)!=before or candidate(path,content_root,"",true)!=offered:
		return {"ok":false,"reason":"native_identity_changed"}
	descriptor.collision_absence=absence
	var error:=_publish(descriptor,target,content_root)
	return {"ok":error==OK,"error":error,"safe_for_explicit_none":absence.safe_for_explicit_none,"descriptor":target}

## A static node graph with only the previous visual extras whitelist cannot
## create interactions when a plain map record explicitly overrides collision
## to none. Inspect SceneState/metadata, never mesh arrays or image pixels.
static func collision_absence_from_packed(packed:PackedScene)->Dictionary:
	var safe:=packed!=null and packed.get_script()==null
	if safe:
		var state:=packed.get_state();var seen:Dictionary={}
		safe=state.get_node_count()>0 and state.get_connection_count()==0
		for at:int in state.get_node_count():
			if not safe:break
			if state.get_node_type(at) not in [&"Node3D",&"MeshInstance3D"] or state.get_node_instance(at)!=null or not state.get_node_instance_placeholder(at).is_empty() or not state.get_node_groups(at).is_empty():safe=false;break
			for slot:int in state.get_node_property_count(at):
				var name_:String=str(state.get_node_property_name(at,slot));var value:Variant=state.get_node_property_value(at,slot)
				if name_=="script" and value!=null:safe=false;break
				if name_.begins_with("metadata/") and (name_!="metadata/extras" or not _collision_visual_extras(value)):safe=false;break
				if not _collision_visual_value(value,seen,0):safe=false;break
	return {"version":COLLISION_ABSENCE_VERSION,"safe_for_explicit_none":safe}

static func _collision_visual_extras(value:Variant)->bool:
	if not value is Dictionary:return false
	for field:Variant in value:
		if field not in COLLISION_VISUAL_EXTRAS:return false
	return true

static func _collision_visual_value(value:Variant,seen:Dictionary,depth:int)->bool:
	if depth>32:return false
	if value is Resource:
		if value.get_script()!=null:return false
		if not value is ArrayMesh and not value is StandardMaterial3D and not value is ImageTexture and not value is Image:return false
		var id:int=value.get_instance_id()
		if seen.has(id):return true
		seen[id]=true
		for name_:StringName in value.get_meta_list():
			var meta:Variant=value.get_meta(name_)
			if name_==&"extras" and not _collision_visual_extras(meta):return false
			if not _collision_visual_value(meta,seen,depth+1):return false
		if value is ArrayMesh:
			for slot:int in value.get_surface_count():
				if not _collision_visual_value(value.surface_get_material(slot),seen,depth+1):return false
	elif value is Dictionary:
		for key:Variant in value:
			if key=="extras" and not _collision_visual_extras(value[key]):return false
			if not _collision_visual_value(value[key],seen,depth+1):return false
	elif value is Array:
		for item:Variant in value:
			if not _collision_visual_value(item,seen,depth+1):return false
	elif value is Object or value is Callable or value is Signal or value is RID:return false
	return true

static func ensure_imported_building(path:String,content_root:String,force:bool=false)->Dictionary:
	if not force:
		var offered:=candidate(path,content_root,"",true)
		if offered.is_empty():return {"ok":false,"reason":"native_footprint_missing"}
		var existing:=_building_metadata(path,content_root,offered)
		if not existing.is_empty():return {"ok":true,"present":existing.present,"reused":true,"descriptor":building_descriptor_path(path,content_root)}
	return refresh_imported_building(path,content_root)

static func _building_metadata(path:String,content_root:String,identity:Dictionary)->Dictionary:
	var target:=building_descriptor_path(path,content_root)
	if not Paths.allowed(target,directory(content_root)):return {}
	var file:=FileAccess.open(target,FileAccess.READ)
	if file==null or file.get_length()<=0 or file.get_length()>BUILDING_DESCRIPTOR_MAX_BYTES:return {}
	var outer:=JSON.new()
	if outer.parse(file.get_as_text())!=OK or not outer.data is Dictionary:return {}
	var envelope:Dictionary=outer.data
	if envelope.get("version")!=1 or not envelope.get("body") is String:return {}
	var parser:=JSON.new()
	if parser.parse(envelope.body)!=OK:return {}
	var value:Variant=parser.data
	if not value is Dictionary or value.get("version")!=1 or value.get("source_sha")!=identity.source_sha or value.get("payload_sha")!=identity.payload_sha or not value.get("present") is bool:return {}
	if value.present:
		var building:Variant=value.get("descriptor")
		if not load("res://scripts/world3d/imported_building.gd").valid_descriptor(building) or building.source_sha!=identity.source_sha:return {}
	return value

static func _publish_building(path:String,content_root:String,identity:Dictionary,building:Dictionary)->Error:
	var value:={"version":1,"source_sha":identity.source_sha,"payload_sha":identity.payload_sha,"present":building.present}
	if building.present:value.descriptor=building.descriptor
	return _publish(value,building_descriptor_path(path,content_root),content_root,BUILDING_DESCRIPTOR_MAX_BYTES)

static func estimate_stats(stats: Dictionary) -> Dictionary:
	for key in STAT_KEYS:
		if not _integer(stats.get(key), MAX_BYTES): return {}
	if stats.nodes < 1 or stats.native_uncompressed_bytes < 1: return {}
	# A deliberately overlapping envelope, not measured RSS: two serialized
	# streams/loader working sets, image decode/readback + upload copies, packed
	# GPU mesh plus unpacked CpuMesh captures and exact collision faces. No term
	# derives a decoded bound from compressed .scn size. Keep the full charge
	# resident until the owning queue explicitly releases it.
	var peak: int = FLOOR_BYTES + int(stats.native_uncompressed_bytes) * 2
	peak += int(stats.image_mip_bytes) * 3 + int(stats.gpu_rgba_bytes) * 3
	peak += int(stats.mesh_storage_bytes) * 4 + int(stats.mesh_capture_bytes) * 4
	peak += int(stats.collision_face_bytes) * 3 + int(stats.other_packed_bytes) * 3
	peak += int(stats.container_bytes) * 4 + int(stats.nodes) * 16384 + int(stats.materials) * 8192 + int(stats.resources) * 4096
	if peak > MAX_BYTES: return {}
	return {"estimated_bytes":peak, "resident_bytes":peak, "exclusive":peak > EXCLUSIVE_BYTES}

static func measure(packed: PackedScene, direct_reuse:Variant=null) -> Dictionary:
	if packed == null or not packed.get_meta("compiled_asset_validated", false) or not Compiled._valid_packed(packed): return {}
	var stats := empty_stats()
	var state := packed.get_state()
	stats.nodes = state.get_node_count()
	var context := {"ok":true, "seen":{}, "retained":[], "visits":0,"direct_safe":not packed.resource_local_to_scene and packed.get_script()==null}
	for node in state.get_node_count():
		for property in state.get_node_property_count(node):
			var name_:String=str(state.get_node_property_name(node,property))
			var value:Variant=state.get_node_property_value(node, property)
			if name_=="metadata/extras" and value is Dictionary and value.get("rmmo_grass",false)==true:context.direct_safe=false
			if name_=="script" and value!=null:context.direct_safe=false
			_walk(value, stats, context, 0, false)
	if direct_reuse is Dictionary:direct_reuse.assign({"safe":bool(context.ok and context.direct_safe)})
	return stats if context.ok else {}

static func empty_stats() -> Dictionary:
	var result := {}
	for key in STAT_KEYS: result[key] = 0
	return result

static func _walk(value: Variant, stats: Dictionary, context: Dictionary, depth: int, mesh_storage: bool) -> void:
	context.visits += 1
	if not context.ok: return
	if depth > 32 or context.visits > 2000000: context.ok = false; return
	if value is Resource:
		if value.resource_local_to_scene or value.get_script()!=null:context.direct_safe=false
		var id: int = value.get_instance_id()
		if context.seen.has(id): return
		context.seen[id] = true; context.retained.append(value)
		stats.resources += 1
		if value is Image:
			var image_stats := image_footprint(value)
			if image_stats.is_empty(): context.ok = false; return
			stats.images += 1; stats.image_mip_bytes += image_stats.image_mip_bytes; stats.gpu_rgba_bytes += image_stats.gpu_rgba_bytes
			return
		elif value is ImageTexture:
			stats.textures += 1
			var image: Image = value.get_image()
			if image == null: context.ok = false; return
			_walk(image, stats, context, depth + 1, false)
		elif value is ArrayMesh:
			stats.meshes += 1
			for surface in value.get_surface_count():
				stats.surfaces += 1
				var arrays: Array = value.surface_get_arrays(surface)
				if arrays.size() != Mesh.ARRAY_MAX: context.ok = false; return
				for array in arrays: stats.mesh_capture_bytes += _packed_bytes(array)
				var count: int = value.surface_get_array_index_len(surface)
				if count == 0: count = value.surface_get_array_len(surface)
				var primitive: int = value.surface_get_primitive_type(surface)
				# CpuMesh currently captures every surface's indices/vertices;
				# reserve these even for non-triangle topology, plus a possible
				# expanded strip. Do not undercount partial/degenerate triangles.
				var face_vertices := count
				if primitive == Mesh.PRIMITIVE_TRIANGLE_STRIP: face_vertices = maxi(count, maxi(0, count - 2) * 3)
				stats.collision_face_bytes += face_vertices * (24 if OS.has_feature("double") else 12)
		elif value is StandardMaterial3D: stats.materials += 1
		else: context.ok = false; return
		for property: Dictionary in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				if value is ImageTexture and property.name == "image": continue
				_walk(value.get(property.name), stats, context, depth + 1, value is ArrayMesh)
	elif value is Dictionary:
		stats.container_bytes += 64 + value.size() * 64
		for key in value:
			_walk(key, stats, context, depth + 1, mesh_storage)
			_walk(value[key], stats, context, depth + 1, mesh_storage)
	elif value is Array:
		stats.container_bytes += 32 + value.size() * 32
		for item in value: _walk(item, stats, context, depth + 1, mesh_storage)
	elif value is String or value is StringName or value is NodePath: stats.container_bytes += str(value).length() * 4 + 32
	elif value is Object or value is Callable or value is Signal or value is RID: context.ok = false
	else:
		var size := _packed_bytes(value)
		if mesh_storage: stats.mesh_storage_bytes += size
		else: stats.other_packed_bytes += size

static func _packed_bytes(value: Variant) -> int:
	match typeof(value):
		TYPE_PACKED_BYTE_ARRAY: return value.size()
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY: return value.size() * 4
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY: return value.size() * 8
		TYPE_PACKED_VECTOR2_ARRAY: return value.size() * (16 if OS.has_feature("double") else 8)
		TYPE_PACKED_VECTOR3_ARRAY: return value.size() * (24 if OS.has_feature("double") else 12)
		TYPE_PACKED_VECTOR4_ARRAY: return value.size() * (32 if OS.has_feature("double") else 16)
		TYPE_PACKED_COLOR_ARRAY: return value.size() * 16
		TYPE_PACKED_STRING_ARRAY:
			var size: int = value.size() * 32
			for item in value: size += item.length() * 4
			return size
	return 0

static func image_footprint(image: Image) -> Dictionary:
	if image == null or image.is_empty() or image.get_width() > 65536 or image.get_height() > 65536: return {}
	var raw := image.get_data().size()
	if raw <= 0: return {}
	# RGBA32F covers all built-in Image channel formats including HDR/compressed
	# formats. Ordinary LDR uses RGBA8; full mip allocation is reserved even when
	# the stored image has no mips. Original mip bytes are accounted separately.
	var format := image.get_format()
	var bytes_per_pixel := 4 if format <= Image.FORMAT_RGBA8 else 16
	var width := image.get_width(); var height := image.get_height(); var gpu := 0
	while true:
		gpu += width * height * bytes_per_pixel
		if width == 1 and height == 1: break
		width = maxi(1, width / 2); height = maxi(1, height / 2)
	if raw > MAX_BYTES or gpu > MAX_BYTES: return {}
	return {"image_mip_bytes":raw, "gpu_rgba_bytes":maxi(raw, gpu)}

static func native_uncompressed_bytes(path: String) -> int:
	# Godot 4.x FileAccessCompressed: magic, LE mode/block_size/total_u32,
	# (total/block_size + 1) compressed block lengths, payload, trailing magic.
	# Read only the bounded table, not the decompressed resource. The build path
	# has already verified and loaded the full content-addressed product.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 20: return 0
	var size := file.get_length()
	var magic := file.get_buffer(4).get_string_from_ascii()
	if magic == "RSRC": file.close(); return size
	if magic != "RSCC": file.close(); return 0
	var mode := file.get_32(); var block := file.get_32(); var total := file.get_32()
	if mode > 4 or block == 0 or block > 64 * 1024 * 1024 or total == 0: file.close(); return 0
	var count: int = total / block + 1
	if count > 1048576 or 16 + count * 4 + 4 > size: file.close(); return 0
	var end := 16 + count * 4
	for index in count:
		end += file.get_32()
		if end > size - 4: file.close(); return 0
	if end != size - 4: file.close(); return 0
	file.seek(end)
	var valid := file.get_buffer(4).get_string_from_ascii() == "RSCC"
	file.close()
	return total if valid else 0

static func _publish(descriptor: Dictionary, destination: String, content_root: String, maximum:int=MAX_DESCRIPTOR_BYTES) -> Error:
	var folder := directory(content_root)
	if not Paths.allowed(folder, content_root) or not Paths.allowed(destination, folder): return ERR_FILE_BAD_PATH
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return ERR_CANT_CREATE
	var body := JSON.stringify(descriptor)
	var encoded := JSON.stringify({"version":VERSION, "body":body, "sha256":body.sha256_text()})
	if encoded.to_utf8_buffer().size() > maximum: return ERR_OUT_OF_MEMORY
	var temporary := destination + ".%d.%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not Paths.allowed(temporary, folder): return ERR_FILE_BAD_PATH
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(encoded); file.flush(); var error := file.get_error(); file.close()
	if error == OK: error = Atomic.publish(temporary, destination)
	if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
	return error

static func _read_json(path: String, maximum: int, file_identities:Variant=null) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > maximum: return {}
	var text:String
	if file_identities is Dictionary:
		var bytes:=file.get_buffer(file.get_length())
		var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(bytes)
		file_identities[path]=hash_.finish().hex_encode()
		text=bytes.get_string_from_utf8()
	else: text=file.get_as_text()
	file.close()
	var parser:=JSON.new()
	if parser.parse(text)!=OK:return {}
	var data: Variant = parser.data
	return data if data is Dictionary else {}

static func _integer(value: Variant, maximum: int, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum and value == int(value)

static func _path(path: String) -> String:
	return path.replace("\\", "/").simplify_path()
