extends RefCounted
## Eligibility only; GLTFDocument still validates the staged model before publication.
## Unknown containers/extensions retain the normal dependency-packing import path.
const BoundsManifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
static func can_copy(path: String) -> bool:
	if path.get_extension().to_lower() != "glb": return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 28: return false
	var length := file.get_length()
	if file.get_32() != 0x46546c67 or file.get_32() != 2 or file.get_32() != length: return false
	var json_length := file.get_32()
	if file.get_32() != 0x4e4f534a or json_length < 4 or json_length > 4 * 1024 * 1024 or json_length % 4 != 0 or 28 + json_length > length: return false
	var raw: Variant = JSON.parse_string(file.get_buffer(json_length).get_string_from_utf8())
	if not raw is Dictionary or not raw.get("asset") is Dictionary or raw.asset.get("version") != "2.0": return false
	var bin_length := file.get_32()
	if file.get_32() != 0x004e4942 or bin_length % 4 != 0 or file.get_position() + bin_length != length: return false
	var materials:Variant=raw.get("materials",[])
	if not materials is Array:return false
	for material:Variant in materials:
		if not material is Dictionary:return false
	if not _plain(raw): return false
	var buffers: Variant = raw.get("buffers")
	if not buffers is Array or buffers.size() != 1 or not buffers[0] is Dictionary: return false
	var size: Variant = buffers[0].get("byteLength")
	if not _uint(size) or size <= 0 or size > bin_length or bin_length - size > 3: return false
	var views: Variant = raw.get("bufferViews", [])
	if not views is Array: return false
	for view in views:
		if not view is Dictionary or view.get("buffer") != 0: return false
		var offset: Variant = view.get("byteOffset", 0)
		var count: Variant = view.get("byteLength")
		if not _uint(offset) or not _uint(count) or count <= 0 or offset > size or count > size - offset: return false
	var images: Variant = raw.get("images", [])
	if not images is Array: return false
	for image in images:
		if not image is Dictionary or not _uint(image.get("bufferView")) or image.bufferView >= views.size() or image.get("mimeType") not in ["image/png", "image/jpeg"]: return false
	return true

static func _uint(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value == floor(float(value))

static func _plain(value: Variant, path:Array=[]) -> bool:
	if value is Dictionary:
		for key in value:
			# Conservatively include extras: custom URI/extension contracts are unknown.
			if key == "uri": return false
			if key in ["extensionsUsed","extensionsRequired"]:
				if not path.is_empty():return false
				if value[key]==null:continue
				if not value[key] is Array:return false
				# Match the existing native bounds/compiler contract exactly. Required
				# extensions and unknown contracts still use the packing fallback.
				if key=="extensionsRequired" and not value[key].is_empty():return false
				for extension:Variant in value[key]:
					if extension not in BoundsManifest.MATERIAL_EXTENSIONS:return false
			if key == "extensions":
				if not value[key] is Dictionary:return false
				if not value[key].is_empty():
					# No node/mesh/image/extras extension is admitted. The shared list
					# describes optional material payloads only, without external URIs.
					if path.size()!=2 or path[0]!="materials" or not path[1] is int:return false
					for extension:Variant in value[key]:
						if extension not in BoundsManifest.MATERIAL_EXTENSIONS or not value[key][extension] is Dictionary:return false
			if not _plain(value[key],path+[key]): return false
	elif value is Array:
		for index in value.size():
			if not _plain(value[index],path+[index]): return false
	return true
