extends RefCounted
## Scheduling estimate only, never import eligibility or source validation.
## Reads bounded JSON/image headers; no Image, ResourceLoader or GPU operations.
## Budget includes fallback GLTF buffers and transient decoded/upload copies even
## when a smaller native product exists. It deliberately does not assume dedup.
const MAX_JSON := 4 * 1024 * 1024
const MAX_ITEMS := 65536
const MAX_IMAGES := 4096
const MAX_HEADER := 1024 * 1024
const IMAGE_MAX_PIXELS := 268435456 # Image::MAX_PIXELS; not bound in GDScript.
const MAX_ESTIMATE := 1024 * 1024 * 1024 * 1024
const UNKNOWN_BYTES := 8 * 1024 * 1024 * 1024
const EXCLUSIVE_BYTES := 4 * 1024 * 1024 * 1024
const MATERIAL_EXTENSIONS := ["KHR_materials_specular", "KHR_materials_transmission", "KHR_materials_unlit", "KHR_materials_emissive_strength", "KHR_materials_pbrSpecularGlossiness", "KHR_materials_clearcoat", "KHR_materials_ior"]

static func _unknown(reason: String, source: int = 0) -> Dictionary:
	return {"estimated_bytes":maxi(UNKNOWN_BYTES, mini(MAX_ESTIMATE / 2, source) * 2), "exclusive":true, "known":false, "source_bytes":source,
		"decoded_bytes":0, "mesh_bytes":0, "output_bytes":0, "texture_bytes":0, "reason":reason}

static func stage_profile(value:Dictionary)->Dictionary:
	# Cache file bytes are compressed storage, not peak live resource bytes.
	# Until compiled decode/upload lifetimes are measured and source-bound, keep
	# the full fallback envelope for BOTH routes. This is a diagnostic account,
	# not a new estimator or proof that a source may be imported in parallel.
	var bounded:Dictionary=value
	if not value.get("estimated_bytes") is int or value.estimated_bytes<=0 or not value.get("exclusive") is bool:
		bounded=_unknown("invalid_estimator")
	var total:int=bounded.estimated_bytes
	var components:Dictionary={}
	for key in ["source_bytes","decoded_bytes","mesh_bytes","texture_bytes","collision_bytes","output_bytes","overhead_bytes"]:
		components[key]=maxi(0,int(bounded.get(key,0)))
	return {"estimated_bytes":total,"known":bounded.get("known",false)==true,"exclusive":bounded.exclusive,
		"components":components,"compiled_read_reservation_bytes":total,"raw_import_reservation_bytes":total,
		"retained_result_charge_bytes":total,"policy":"full_fallback_envelope_no_compiled_discount",
		"components_overlap":true,"source_identity_verified":false,"loading_eligible":false}

static func from_manifest(path:String,manifest:Dictionary)->Dictionary:
	# Scheduling metadata is generated with the dependency directory and shares
	# its source/generator invalidation. Keep the SAME full raw/native envelope,
	# including textures; this reuse changes no admission limit or residency charge.
	var memory:Variant=manifest.get("memory")
	if preload("res://scripts/world3d/runtime_package_policy.gd").trusted() and memory is Dictionary and memory.get("estimated_bytes") is int and memory.estimated_bytes>0 and memory.estimated_bytes<=MAX_ESTIMATE and memory.get("exclusive") is bool and memory.get("source_bytes")==manifest.get("file_length"):
		return memory.duplicate()
	return estimate(path)

static func estimate(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _unknown("missing")
	var source := file.get_length()
	if path.get_extension().to_lower() != "glb" or source < 28 or source > 4294967295: return _unknown("container",source)
	if file.get_32() != 0x46546c67 or file.get_32() != 2 or file.get_32() != source: return _unknown("glb_header",source)
	var json_size := file.get_32()
	if file.get_32() != 0x4e4f534a or json_size < 4 or json_size > MAX_JSON or json_size % 4 != 0 or json_size > source - 28: return _unknown("json_chunk",source)
	var bytes := file.get_buffer(json_size)
	if bytes.size() != json_size: return _unknown("short_json",source)
	var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not raw is Dictionary or not raw.get("asset") is Dictionary or raw.asset.get("version") != "2.0": return _unknown("json",source)
	var bin_size := file.get_32()
	if file.get_32() != 0x004e4942 or bin_size % 4 != 0 or bin_size != source - file.get_position(): return _unknown("bin_chunk",source)
	var bin_start := file.get_position()
	if not _bounded_plain(raw): return _unknown("external_or_unknown_encoding",source)
	for key in ["skins", "animations"]:
		if raw.has(key) and (not raw[key] is Array or not raw[key].is_empty()): return _unknown("deformation",source)
	var buffers: Variant = raw.get("buffers")
	if not buffers is Array or buffers.size() != 1 or not buffers[0] is Dictionary: return _unknown("buffers",source)
	var bin_bytes: Variant = buffers[0].get("byteLength")
	if not _uint(bin_bytes) or bin_bytes <= 0 or bin_bytes > bin_size or bin_size - int(bin_bytes) > 3: return _unknown("buffer_length",source)
	var views: Variant = raw.get("bufferViews",[])
	var images: Variant = raw.get("images",[])
	var accessors: Variant = raw.get("accessors",[])
	var meshes: Variant = raw.get("meshes",[])
	var nodes: Variant = raw.get("nodes",[])
	var materials: Variant = raw.get("materials",[])
	for list: Variant in [views,images,accessors,meshes,nodes,materials]:
		if not list is Array or list.size() > MAX_ITEMS: return _unknown("array_limit",source)
	if images.size() > MAX_IMAGES: return _unknown("image_limit",source)
	for view: Variant in views:
		if not view is Dictionary or view.get("buffer") != 0 or not _uint(view.get("byteOffset",0)) or not _uint(view.get("byteLength")): return _unknown("view",source)
		if view.byteLength <= 0 or view.get("byteOffset",0) > bin_bytes or view.byteLength > bin_bytes - view.get("byteOffset",0): return _unknown("view_range",source)
	var texture_bytes := 0
	for image: Variant in images:
		if not image is Dictionary or not _index(image.get("bufferView"),views.size()): return _unknown("image_view",source)
		var view: Dictionary = views[int(image.bufferView)]
		var dimensions := _image_header(file,bin_start + int(view.get("byteOffset",0)),int(view.byteLength),str(image.get("mimeType","")))
		if dimensions.is_empty(): return _unknown("image_header",source)
		texture_bytes += _mip_bytes(dimensions.width,dimensions.height,dimensions.pixel_bytes)
		if texture_bytes > MAX_ESTIMATE / 4: return _unknown("texture_limit",source)
	var layouts: Array = []
	for accessor: Variant in accessors:
		var layout := _accessor(accessor,views)
		if layout.is_empty(): return _unknown("accessor",source)
		layouts.append(layout)
	var mesh_bytes := 0
	var collision_bytes := 0
	for mesh: Variant in meshes:
		if not mesh is Dictionary or mesh.has("weights") or not mesh.get("primitives") is Array or mesh.primitives.size() > MAX_ITEMS: return _unknown("mesh",source)
		for primitive: Variant in mesh.primitives:
			if not primitive is Dictionary or primitive.has("targets") or primitive.get("mode",4) != 4 or not primitive.get("attributes") is Dictionary: return _unknown("primitive",source)
			var attributes: Dictionary = primitive.attributes
			if not _index(attributes.get("POSITION"),layouts.size()): return _unknown("position",source)
			var position: Dictionary = layouts[int(attributes.POSITION)]
			if position.components != 3: return _unknown("position_layout",source)
			for index: Variant in attributes.values():
				if not _index(index,layouts.size()) or layouts[int(index)].count != position.count: return _unknown("attribute",source)
				mesh_bytes += int(layouts[int(index)].decoded_bytes)
			# Reserve generated normals/tangents as well as imported channels.
			mesh_bytes += int(position.count) * 28
			var triangle_indices: int = position.count
			if primitive.has("indices"):
				if not _index(primitive.indices,layouts.size()): return _unknown("indices",source)
				var indices: Dictionary = layouts[int(primitive.indices)]
				if indices.components != 1 or indices.component_type not in [5121,5123,5125]: return _unknown("index_layout",source)
				triangle_indices = indices.count
				mesh_bytes += triangle_indices * 4
			if triangle_indices % 3 != 0: return _unknown("triangle_count",source)
			# Triangle soup plus room for the eventual physics acceleration data.
			collision_bytes += triangle_indices * 24
			if mesh_bytes + collision_bytes > MAX_ESTIMATE / 4: return _unknown("mesh_limit",source)
	var overhead: int = 16 * 1024 * 1024 + json_size * 8 + nodes.size() * 2048 + materials.size() * 4096
	var decoded_bytes := texture_bytes * 2 + mesh_bytes * 2
	var output_bytes := texture_bytes + mesh_bytes + collision_bytes
	var total: int = source * 2 + decoded_bytes + output_bytes + overhead
	if total > MAX_ESTIMATE: return _unknown("estimate_limit",source)
	return {"estimated_bytes":total, "exclusive":total >= EXCLUSIVE_BYTES, "known":true, "source_bytes":source, "decoded_bytes":decoded_bytes,
		"mesh_bytes":mesh_bytes, "output_bytes":output_bytes, "texture_bytes":texture_bytes, "collision_bytes":collision_bytes, "overhead_bytes":overhead, "reason":"bounded_glb_headers"}

static func _accessor(value: Variant, views: Array) -> Dictionary:
	if not value is Dictionary or value.has("sparse") or not _index(value.get("bufferView"),views.size()) or not _uint(value.get("count")) or value.count <= 0 or not _uint(value.get("byteOffset",0)): return {}
	var widths := {5120:1,5121:1,5122:2,5123:2,5125:4,5126:4}
	var types := {"SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4}
	if not _uint(value.get("componentType")) or not widths.has(int(value.componentType)) or not types.has(value.get("type")): return {}
	var components: int = types[value.type]
	var element: int = components * int(widths[int(value.componentType)])
	var view: Dictionary = views[int(value.bufferView)]
	var stride: Variant = view.get("byteStride",element)
	var offset: int = value.get("byteOffset",0)
	if not _uint(stride) or stride < element or stride > 252 or int(stride) % int(widths[int(value.componentType)]) != 0: return {}
	if offset > view.byteLength or view.byteLength - offset < element or value.count - 1 > (view.byteLength - offset - element) / int(stride): return {}
	return {"count":int(value.count),"components":components,"component_type":int(value.componentType),"decoded_bytes":int(value.count) * components * 4}

static func _image_header(file: FileAccess, offset: int, length: int, mime: String) -> Dictionary:
	if length < 8: return {}
	file.seek(offset)
	if mime == "image/png":
		if length < 33: return {}
		var header := file.get_buffer(33)
		if header.size() != 33 or header.slice(0,8) != PackedByteArray([137,80,78,71,13,10,26,10]): return {}
		if _be32(header,8) != 13 or header.slice(12,16).get_string_from_ascii() != "IHDR": return {}
		var bits := int(header[24]); var color := int(header[25])
		var valid_bits := {0:[1,2,4,8,16],2:[8,16],3:[1,2,4,8],4:[8,16],6:[8,16]}
		if not valid_bits.has(color) or bits not in valid_bits[color] or header[26] != 0 or header[27] != 0 or header[28] > 1: return {}
		return _dimensions(_be32(header,16),_be32(header,20),8 if bits == 16 else 4)
	if mime != "image/jpeg" or file.get_8() != 255 or file.get_8() != 216: return {}
	var end := offset + mini(length,MAX_HEADER)
	for _segment in 1024:
		if file.get_position() + 2 > end or file.get_8() != 255: return {}
		var marker := file.get_8()
		while marker == 255 and file.get_position() < end: marker = file.get_8()
		if marker in [0,216,217,218] or file.get_position() + 2 > end: return {}
		if marker == 1 or (marker >= 208 and marker <= 215): continue
		var size := (file.get_8() << 8) | file.get_8()
		if size < 2 or size - 2 > end - file.get_position(): return {}
		if marker in [192,193,194]:
			if size < 8: return {}
			var bits := file.get_8()
			var height := (file.get_8() << 8) | file.get_8()
			var width := (file.get_8() << 8) | file.get_8()
			var channels := file.get_8()
			if bits != 8 or channels not in [1,3,4] or size != 8 + 3 * channels: return {}
			return _dimensions(width,height,4)
		file.seek(file.get_position() + size - 2)
	return {}

static func _dimensions(width: int, height: int, pixel_bytes: int) -> Dictionary:
	if width <= 0 or height <= 0 or width > Image.MAX_WIDTH or height > Image.MAX_HEIGHT or width > IMAGE_MAX_PIXELS / height: return {}
	return {"width":width,"height":height,"pixel_bytes":pixel_bytes}

static func _mip_bytes(width: int, height: int, pixel_bytes: int) -> int:
	var total := 0
	while true:
		total += width * height * pixel_bytes
		if width == 1 and height == 1: return total
		width = maxi(1,width >> 1); height = maxi(1,height >> 1)
	return total

static func _be32(bytes: PackedByteArray, at: int) -> int:
	return (int(bytes[at]) << 24) | (int(bytes[at+1]) << 16) | (int(bytes[at+2]) << 8) | int(bytes[at+3])

static func _uint(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 4294967295 and value == floor(float(value))

static func _index(value: Variant, size: int) -> bool: return _uint(value) and value < size

static func _bounded_plain(value: Dictionary) -> bool:
	# Unknown compressed/extension representations can expand beyond accessor
	# counts. Only familiar material modifiers leave this estimate usable.
	# Scalar leaves cannot hold URI/extension declarations. Count their depth
	# and quantity here, but enqueue only containers and retain no wrapper dict.
	var pending:Array=[value]
	var depths:Array[int]=[0]
	var visited:=1
	while not pending.is_empty():
		var current:Variant=pending.pop_back()
		var depth:int=depths.pop_back()
		var children:int=current.size()
		visited+=children
		if visited>200000 or depth>32 or (depth==32 and children>0):return false
		if current is Dictionary:
			if current.has("uri"): return false
			for field in ["rmmo_format","rmmo_records","rmmo_storage","rmmo_resource_dependencies"]:
				if current.has(field): return false
			for field in ["extensionsUsed","extensionsRequired"]:
				if not current.has(field) or current[field] == null: continue
				if not current[field] is Array: return false
				for extension: Variant in current[field]:
					if extension not in MATERIAL_EXTENSIONS: return false
			if current.has("extensions"):
				if not current.extensions is Dictionary: return false
				for key: Variant in current.extensions:
					if key not in MATERIAL_EXTENSIONS: return false
			for key:Variant in current:
				var child:Variant=current[key]
				if child is Dictionary or child is Array:pending.append(child);depths.append(depth+1)
		elif current is Array:
			if current.size() > MAX_ITEMS: return false
			for child:Variant in current:
				if child is Dictionary or child is Array:pending.append(child);depths.append(depth+1)
	return true
