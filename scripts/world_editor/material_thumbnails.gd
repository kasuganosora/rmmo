extends Node
## One CPU decoder; only small completed images reach the rendering thread.
signal available(id: String, texture: Texture2D)
const MAX_CACHE := 96
const Paths = preload("res://scripts/world3d/map_paths.gd")
var directory := ""
var placeholder: Texture2D
var cache := {}
var _lru: Array[String] = []
var _wanted := {}
var _pending: Array = []
var _thread: Thread
var _job := {}
var decode_count := 0
var source_decode_count := 0
var disk_hit_count := 0
var cache_write_count := 0
var max_upload_usec := 0

static func prepare(entry: Dictionary, content_root: String = "") -> void:
	var material: Dictionary = entry.material
	var path := str(material.get("texture_path", ""))
	var allowed := not path.is_empty() and preload("res://scripts/world3d/map_paths.gd").allowed(path, content_root) and FileAccess.file_exists(path)
	entry["thumbnail_path"] = path if allowed else ""
	entry["thumbnail_key"] = ("v1|" + JSON.stringify(material) + str(FileAccess.get_modified_time(path) if allowed else 0)).sha256_text()

func _ready() -> void:
	if directory.is_empty(): directory = Paths.cache_directory("surface_material_thumbnails")
	if not Paths.allowed(directory) or DirAccess.make_dir_recursive_absolute(directory) != OK: directory = ""

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
		if cache.has(key) or queued.has(key) or (_thread != null and _job.key == key): continue
		queued[key] = true
		_pending.append({"key":key, "path":entry.thumbnail_path, "material":entry.material.duplicate(true)})
	set_process(_thread != null or not _pending.is_empty())

func _process(_delta: float) -> void:
	if _thread != null:
		if _thread.is_alive(): return
		var result: Dictionary = _thread.wait_to_finish()
		source_decode_count += int(result.source_read)
		disk_hit_count += int(result.disk_hit)
		cache_write_count += int(result.cache_write)
		_thread = null
		var start := Time.get_ticks_usec()
		var texture := ImageTexture.create_from_image(result.image)
		max_upload_usec = maxi(max_upload_usec, Time.get_ticks_usec() - start)
		cache[_job.key] = texture
		_lru.erase(_job.key); _lru.append(_job.key)
		while _lru.size() > MAX_CACHE: cache.erase(_lru.pop_front())
		for id in _wanted:
			if _wanted[id] == _job.key: available.emit(id, texture)
	if _pending.is_empty():
		set_process(false)
		return
	_job = _pending.pop_front()
	_thread = Thread.new()
	var cache_path := directory.path_join(str(_job.key) + ".png") if not directory.is_empty() else ""
	if not cache_path.is_empty() and not Paths.allowed(cache_path): cache_path = ""
	var error := _thread.start(load_thumbnail.bind(_job.path, _job.material, cache_path))
	if error != OK:
		_thread = null
		# A failed worker must not fall back to synchronous multi-megabyte IO.
		cache[_job.key] = placeholder
		_lru.append(_job.key)
		while _lru.size() > MAX_CACHE: cache.erase(_lru.pop_front())
	else:
		decode_count += 1

static func load_thumbnail(path: String, material: Dictionary, cache_path: String) -> Dictionary:
	if not cache_path.is_empty() and FileAccess.file_exists(cache_path):
		var file := FileAccess.open(cache_path, FileAccess.READ)
		if file != null:
			var bytes := file.get_buffer(file.get_length()) if file.get_length() <= 131072 else PackedByteArray()
			file.close()
			var cached := Image.new()
			if not bytes.is_empty() and cached.load_png_from_buffer(bytes) == OK and cached.get_width() <= 104 and cached.get_height() <= 64:
				return {"image":cached, "disk_hit":true, "source_read":false, "cache_write":false}
	var image := decode(path, material)
	var written := false
	if not cache_path.is_empty():
		# Cache is disposable and content-addressed; never expose a partial PNG.
		var staging := cache_path + ".tmp_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
		if image.save_png(staging) == OK:
			if FileAccess.file_exists(cache_path): DirAccess.remove_absolute(cache_path)
			written = DirAccess.rename_absolute(staging, cache_path) == OK
			if not written: DirAccess.remove_absolute(staging)
	return {"image":image, "disk_hit":false, "source_read":not path.is_empty(), "cache_write":written}

static func decode(path: String, material: Dictionary) -> Image:
	# Worker owns its Image and immutable inputs; never touches nodes or GPU resources.
	var image: Image
	if not path.is_empty(): image = Image.load_from_file(path)
	if image != null and not image.is_empty():
		var factor := minf(104.0 / image.get_width(), 64.0 / image.get_height())
		image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_BILINEAR)
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
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
