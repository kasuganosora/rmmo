extends Node
## Visible thumbnails share the editor admission ledger. Full source decoding
## follows a small header/cache probe; only small images reach publication.
signal available(id: String, texture: Texture2D)
const MAX_CACHE := 96
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Queue = preload("res://scripts/world_editor/load_preparation_queue.gd")
const Worker = preload("res://scripts/world_editor/surface_texture_import_worker.gd")
const Drainer = preload("res://scripts/world3d/asset_worker_drainer.gd")
const PROBE_BYTES := 512 * 1024
var shared_ledger: RefCounted
var _queue: Node
var _content_root := ""
var _serial := 0
var directory := ""
var placeholder: Texture2D
var cache := {}
var _lru: Array[String] = []
var _wanted := {}
var _pending: Array = []
var _job := {}
var decode_count := 0
var source_decode_count := 0
var disk_hit_count := 0
var cache_write_count := 0
var max_upload_usec := 0
var imported_thumbnail_hits := 0
var last_error := ""

static func prepare(entry: Dictionary, content_root: String = "") -> void:
	var material: Dictionary = entry.material
	var path := str(material.get("texture_path", ""))
	var allowed := not path.is_empty() and preload("res://scripts/world3d/map_paths.gd").allowed(path, content_root) and FileAccess.file_exists(path)
	entry["thumbnail_path"] = path if allowed else ""
	# An image thumbnail is unaffected by the material label. All labels of one
	# source share its small output; procedural swatches retain their parameters.
	entry["thumbnail_key"] = ("v2|" + (path + "|" + str(FileAccess.get_modified_time(path)) if allowed else JSON.stringify(material))).sha256_text()

func _ready() -> void:
	if directory.is_empty(): directory = Paths.cache_directory("surface_material_thumbnails")
	if not Paths.allowed(directory) or DirAccess.make_dir_recursive_absolute(directory) != OK: directory = ""
	_content_root = Paths.external_root()
	_queue = Queue.new()
	if shared_ledger != null:
		_queue.ledger = shared_ledger; _queue.shared_ledger_enabled = true
	add_child(_queue); _queue.set_process(false); set_process(false)

func lookup(entry: Dictionary) -> Texture2D:
	var key: String = entry.thumbnail_key
	if not cache.has(key): return placeholder
	_lru.erase(key); _lru.append(key)
	return cache[key]

func request(entries: Array) -> void:
	_wanted.clear(); _pending.clear()
	var queued := {}
	for entry in entries:
		var key: String = entry.thumbnail_key
		_wanted[str(entry.material_id)] = key
		if cache.has(key) or queued.has(key) or (not _job.is_empty() and _job.key == key and not _job.token.is_cancelled()): continue
		queued[key] = true
		_pending.append({"key":key, "path":entry.thumbnail_path, "material":entry.material.duplicate(true)})
	if not _job.is_empty() and not _wanted.values().has(_job.key): _job.token.cancel()
	set_process(not _job.is_empty() or not _pending.is_empty())
	_queue.set_process(is_processing())

func _process(_delta: float) -> void:
	if not _job.is_empty():
		if not _queue.is_ready(_job.task): return
		var result: Dictionary = _queue.acquire(_job.task)
		if not _job.token.is_cancelled() and result.has("estimate"):
			var estimate: Dictionary = result.estimate.duplicate()
			var expected: Dictionary = result.expected.duplicate()
			_queue.release(_job.task); _queue.forget_terminal(_job.task)
			_enqueue(_load_source.bind(_job.path, _job.material, _job.cache_path, expected, _job.token, _content_root), estimate, "source")
			return
		if not _job.token.is_cancelled() and result.get("retry_probe", false):
			_queue.release(_job.task); _queue.forget_terminal(_job.task)
			_enqueue_probe(); return
		if not _job.token.is_cancelled() and _wanted.values().has(_job.key): _publish(result)
		_queue.release(_job.task); _queue.forget_terminal(_job.task); _job = {}
	if _pending.is_empty():
		set_process(false); _queue.set_process(false)
		return
	_job = _pending.pop_front()
	var cache_path := directory.path_join(str(_job.key) + ".png") if not directory.is_empty() else ""
	if not cache_path.is_empty() and not Paths.allowed(cache_path): cache_path = ""
	_job.cache_path = cache_path; _job.token = Drainer.CancelToken.new()
	decode_count += 1
	_enqueue_probe()

func _enqueue_probe() -> void:
	_enqueue(_probe.bind(_job.path, _job.material, _job.cache_path, _content_root, _job.token), {"estimated_bytes": PROBE_BYTES, "exclusive": false}, "probe")

func _enqueue(task: Callable, estimate: Dictionary, stage: String) -> void:
	_serial += 1; _job.task = "material_thumbnail:%d" % _serial
	estimate.cpu_only = true; estimate.stage = "material_thumbnail_" + stage
	if not _queue.enqueue(_job.task, task, estimate, "texture"):
		last_error = "Cannot enqueue material thumbnail"
		_job = {}

func _publish(result: Dictionary) -> void:
	source_decode_count += int(result.get("source_read", false))
	disk_hit_count += int(result.get("disk_hit", false))
	cache_write_count += int(result.get("cache_write", false))
	imported_thumbnail_hits += int(result.get("imported_hit", false))
	var texture: Texture2D = placeholder
	var image: Image = result.get("image")
	if image != null:
		var start := Time.get_ticks_usec()
		texture = ImageTexture.create_from_image(image)
		max_upload_usec = maxi(max_upload_usec, Time.get_ticks_usec() - start)
	else: last_error = str(result.get("error", "Thumbnail preparation failed"))
	cache[_job.key] = texture
	_lru.erase(_job.key); _lru.append(_job.key)
	while _lru.size() > MAX_CACHE: cache.erase(_lru.pop_front())
	for id in _wanted:
		if _wanted[id] == _job.key: available.emit(id, texture)

static func _small_image(path: String, content_root: String) -> Image:
	if path.is_empty() or not Paths.allowed(path, content_root): return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > 131072: return null
	var bytes := file.get_buffer(file.get_length()); file.close()
	# Bound dimensions from the exact bytes before PNG can allocate pixels.
	var size := Worker._image_dimensions(Worker._read_bytes.bind(bytes), bytes.size(), "png")
	if size.is_empty() or size.width > 104 or size.height > 64: return null
	var image := Image.new()
	return image if image.load_png_from_buffer(bytes) == OK else null

static func _imported_thumbnail(path: String, content_root: String) -> Image:
	if not preload("res://scripts/world3d/compiled_asset_cache.gd")._sha(path.get_file().get_basename()): return null
	if not Paths.allowed(path, content_root) or not Paths.allowed(path + ".thumbnail.json", content_root) or not Paths.allowed(path + ".thumbnail.png", content_root): return null
	var file := FileAccess.open(path + ".thumbnail.json", FileAccess.READ)
	if file == null or file.get_length() > 2048: return null
	var parser := JSON.new(); var error := parser.parse(file.get_as_text()); file.close()
	if error != OK: return null
	var value: Variant = parser.data
	if not value is Dictionary or value.get("version") != 1 or value.get("source_sha256") != path.get_file().get_basename() or value.get("source_modified_time") != FileAccess.get_modified_time(path): return null
	file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != value.get("source_bytes"): return null
	return _small_image(path + ".thumbnail.png", content_root)

static func _probe(path: String, material: Dictionary, cache_path: String, content_root: String, token: RefCounted) -> Dictionary:
	if token.is_cancelled(): return {}
	var cached := _small_image(cache_path, content_root)
	if cached != null: return {"image": cached, "disk_hit": true}
	if not path.is_empty() and not Paths.allowed(path, content_root): return {"error": "Thumbnail source is outside the content root"}
	var imported := _imported_thumbnail(path, content_root) if not path.is_empty() else null
	if imported != null: return {"image": imported, "imported_hit": true, "cache_write": _persist(imported, cache_path, content_root)}
	if path.is_empty():
		var swatch := decode("", material)
		return {"image": swatch, "cache_write": _persist(swatch, cache_path, content_root)}
	if path.get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp"]:
		# Preserve other engine-supported authoring formats. Their unknown codec
		# workspace uses the existing exclusive admission policy, not a file cap.
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: return {"error": "Thumbnail source cannot be read"}
		return {"estimate": {"estimated_bytes": preload("res://scripts/world3d/asset_memory_estimate.gd").UNKNOWN_BYTES, "exclusive": true}, "expected": {"unknown_codec": true, "source_bytes": file.get_length()}}
	var expected := Worker.probe(path, path.get_base_dir(), token, content_root)
	if not expected.get("ok", false): return expected
	return {"estimate": {"estimated_bytes": expected.estimated_bytes, "exclusive": false}, "expected": expected}

static func _load_source(path: String, material: Dictionary, cache_path: String, expected: Dictionary, token: RefCounted, content_root: String) -> Dictionary:
	if token.is_cancelled(): return {}
	if not Paths.allowed(path, content_root): return {"error": "Thumbnail source is outside the content root"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "Thumbnail source cannot be read"}
	if file.get_length() != expected.source_bytes: return {"retry_probe": true}
	var bytes := file.get_buffer(file.get_length()); file.close()
	if bytes.size() != expected.source_bytes: return {"retry_probe": true}
	if token.is_cancelled(): return {}
	if expected.get("unknown_codec", false):
		var other := _decode_snapshot(bytes, path.get_extension().to_lower(), content_root)
		bytes = PackedByteArray()
		if other == null: other = decode("", material)
		if token.is_cancelled(): return {}
		_resize(other)
		return {"image": other, "source_read": true, "cache_write": _persist(other, cache_path, content_root)}
	var dimensions := Worker._image_dimensions(Worker._read_bytes.bind(bytes), bytes.size(), path.get_extension().to_lower())
	if dimensions.is_empty(): return {"error": "Thumbnail source header is invalid"}
	if dimensions.width != expected.width or dimensions.height != expected.height: return {"retry_probe": true}
	if token.is_cancelled(): return {}
	var image := Worker._decode(bytes, path.get_extension().to_lower()); bytes = PackedByteArray()
	if image == null: image = decode("", material)
	if token.is_cancelled(): return {}
	_resize(image)
	return {"image": image, "source_read": true, "cache_write": _persist(image, cache_path, content_root)}

static func _decode_snapshot(bytes: PackedByteArray, extension: String, content_root: String) -> Image:
	var image := Image.new()
	var method := "load_" + extension + "_from_buffer"
	if image.has_method(method): return image if int(image.call(method, bytes)) == OK else null
	# A few codecs (for example HDR) expose only a file API. Decode the same
	# captured bytes from an isolated temporary file, never reopen a changed
	# authoring path. This uncommon route remains under the exclusive lease.
	var folder := content_root.path_join("cache/surface_thumbnail_snapshots")
	var temporary := folder.path_join("%d_%d.%s" % [OS.get_process_id(), Time.get_ticks_usec(), extension])
	if not Paths.allowed(temporary, content_root) or DirAccess.make_dir_recursive_absolute(folder) != OK: return null
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return null
	file.store_buffer(bytes); var written := file.get_error() == OK; file.close()
	if written: image = Image.load_from_file(temporary)
	else: image = null
	if Paths.allowed(temporary, content_root): DirAccess.remove_absolute(temporary)
	return image

static func _persist(image: Image, cache_path: String, content_root: String) -> bool:
	var written := false
	if not cache_path.is_empty() and Paths.allowed(cache_path, content_root):
		# Cache is disposable and content-addressed; never expose a partial PNG.
		var staging := cache_path + ".tmp_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
		if not Paths.allowed(staging, content_root): return false
		if image.save_png(staging) == OK:
			if FileAccess.file_exists(cache_path): DirAccess.remove_absolute(cache_path)
			written = DirAccess.rename_absolute(staging, cache_path) == OK
			if not written: DirAccess.remove_absolute(staging)
	return written

static func _resize(image: Image) -> void:
	var factor := minf(104.0 / image.get_width(), 64.0 / image.get_height())
	image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_BILINEAR)

static func decode(path: String, material: Dictionary) -> Image:
	# Worker owns its Image and immutable inputs; never touches nodes or GPU resources.
	var image: Image
	if not path.is_empty(): image = Image.load_from_file(path)
	if image != null and not image.is_empty():
		_resize(image)
		return image
	image = Image.create(104, 64, false, Image.FORMAT_RGBA8)
	var color: Array = material.get("color", [1, 1, 1, 1])
	image.fill(Color(color[0], color[1], color[2], color[3]))
	if material.get("pattern", "") == "checker":
		for y in 64:
			for x in 104: image.set_pixel(x, y, Color("cba574") if (x / 16 + y / 16) % 2 == 0 else Color("526477"))
	return image

func _exit_tree() -> void:
	_pending.clear()
	if not _job.is_empty(): _job.token.cancel()
	if is_instance_valid(_queue): _queue.cancel()
