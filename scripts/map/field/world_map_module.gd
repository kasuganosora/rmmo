extends RefCounted
## Domain module: world map (continent canvas bake, chunk cache, save).

var ctrl
func _init(c):
	ctrl = c

const MapChunkStore = preload("res://scripts/map/map_chunk_store.gd")
const CHUNK_CELLS := 16
const WM_CACHE_MAX := 64

func world_map_complete() -> bool:
	return ctrl._wm_complete or not ctrl._uses_radar_window()



func world_map_progress() -> float:
	if world_map_complete():
		return 1.0
	if ctrl._wm_jit_total <= 0:
		return 0.0
	return clampf(1.0 - float(ctrl._wm_jit_q.size()) / float(ctrl._wm_jit_total), 0.0, 1.0)



func ensure_world_map() -> void:
	if not ctrl._uses_radar_window():
		ctrl._wm_complete = true
		return
	if ctrl._wm_complete and ctrl._lofi_image != null and ctrl._lofi_image.get_width() > 8:
		return
	_alloc_world_map_canvas()
	# Do not clear/rebuild an in-flight JIT queue on every pan kick.
	if ctrl._wm_jit_q.is_empty() and not ctrl._wm_complete:
		_fill_world_map_queue()



func world_map_step(n: int = 4) -> bool:
	if ctrl._wm_complete:
		return true
	if ctrl._wm_jit_q.is_empty():
		# Already drained (or never queued) — finalize once, never re-commit every pan kick.
		if ctrl._uses_radar_window() and ctrl._lofi_image != null:
			ctrl._wm_complete = true
			_commit_world_map_tex()
			_try_save_world_map()
		else:
			ctrl._wm_complete = true
		return ctrl._wm_complete
	n = maxi(n, 1)
	var sheets: Array = ctrl.pack.sheets if ctrl.pack else []
	var flags: PackedInt32Array = ctrl.pack.flags if ctrl.pack else PackedInt32Array()
	var did = 0
	while did < n and not ctrl._wm_jit_q.is_empty():
		var ch: Vector2i = ctrl._wm_jit_q.pop_front()
		_stamp_world_chunk(ch.x, ch.y, _world_chunk_buf(ch.x, ch.y), sheets, flags)
		did += 1
	# Commit when batch done or queue drained; avoid uploading full overview every pan.
	if ctrl._wm_jit_q.is_empty():
		ctrl._wm_complete = true
		_commit_world_map_tex()
		_try_save_world_map()
	elif did > 0 and (ctrl._wm_jit_q.size() % 16 == 0):
		_commit_world_map_tex()
	return ctrl._wm_complete



func sample_world_chunk(cx: int, cy: int) -> Image:
	var key = ctrl._chunk_key(Vector2i(cx, cy))
	if ctrl._wm_img_cache.has(key):
		return ctrl._wm_img_cache[key]
	var buf: PackedInt32Array = _world_chunk_buf(cx, cy)
	if buf.is_empty() or MapChunkStore.is_empty_buf(buf):
		return null
	var img = Image.create(CHUNK_CELLS, CHUNK_CELLS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var sheets: Array = ctrl.pack.sheets if ctrl.pack else []
	var flags: PackedInt32Array = ctrl.pack.flags if ctrl.pack else PackedInt32Array()
	for ly in range(CHUNK_CELLS):
		for lx in range(CHUNK_CELLS):
			var col: Color = MapChunkStore.sample_cell_color(buf, lx, ly, CHUNK_CELLS, CHUNK_CELLS, sheets, flags)
			if col.a < 0.2:
				continue
			img.set_pixel(lx, ly, col)
	ctrl._wm_img_cache[key] = img
	_evict_wm_cache(ctrl._wm_img_cache)
	return img



func _alloc_world_map_canvas() -> void:
	var m: Dictionary = MapChunkStore.overview_metrics(ctrl.grid_width, ctrl.grid_height)
	ctrl._wm_step = maxi(int(m.get("step", 1)), 1)
	var iw: int = int(m.get("w", 1))
	var ih: int = int(m.get("h", 1))
	if ctrl._lofi_image != null and ctrl._lofi_image.get_width() == iw and ctrl._lofi_image.get_height() == ih:
		if ctrl._wm_bytes.is_empty():
			ctrl._wm_bytes = ctrl._lofi_image.get_data()
		if ctrl._wm_complete:
			return
		# Canvas already sized for this map — keep baking into it.
		ctrl._ground_image = ctrl._lofi_image
		ctrl._ensure_lofi_sprite()
		return
	var img = Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.04, 0.05, 0.05, 1))
	ctrl._lofi_image = img
	ctrl._ground_image = img
	ctrl._wm_bytes = img.get_data()
	_commit_world_map_tex()
	ctrl._ensure_lofi_sprite()



func _fill_world_map_queue() -> void:
	ctrl._wm_jit_q.clear()
	var seen = {}
	var coords: Array[Vector2i] = []
	var map_dir = _world_chunk_dir()
	if map_dir != "":
		coords.append_array(MapChunkStore.list_chunk_coords(map_dir))
	if ctrl.edit_doc != null and "_chunk_cache" in ctrl.edit_doc:
		for k in ctrl.edit_doc._chunk_cache.keys():
			var parts: PackedStringArray = str(k).split(",")
			if parts.size() >= 2:
				coords.append(Vector2i(int(parts[0]), int(parts[1])))
	if ctrl.collision != null and ctrl.collision.has_method("stream_chunk_keys"):
		for k2 in ctrl.collision.stream_chunk_keys():
			var p2: PackedStringArray = str(k2).split(",")
			if p2.size() >= 2:
				coords.append(Vector2i(int(p2[0]), int(p2[1])))
	var obs: Vector2i = ctrl.cell_to_chunk(ctrl._obs_cell)
	if coords.size() <= 256:
		coords.sort_custom(func(a, b): return absi(a.x - obs.x) + absi(a.y - obs.y) < absi(b.x - obs.x) + absi(b.y - obs.y))
	else:
		ctrl._wm_jit_q.append(obs)
		seen[ctrl._chunk_key(obs)] = true
	for c in coords:
		var key = ctrl._chunk_key(c)
		if seen.has(key):
			continue
		seen[key] = true
		ctrl._wm_jit_q.append(c)
	ctrl._wm_jit_total = maxi(ctrl._wm_jit_q.size(), 1)
	ctrl._wm_complete = ctrl._wm_jit_q.is_empty()



func _world_chunk_dir() -> String:
	if ctrl.pack != null and "chunk_map_dir" in ctrl.pack:
		return str(ctrl.pack.chunk_map_dir)
	if ctrl.edit_doc != null and "_store_dir" in ctrl.edit_doc:
		return str(ctrl.edit_doc._store_dir)
	return ""



func _evict_wm_cache(cache: Dictionary) -> void:
	if cache.size() <= WM_CACHE_MAX:
		return
	var keys: Array = cache.keys()
	var drop_n: int = cache.size() - WM_CACHE_MAX
	for i in range(mini(drop_n, keys.size())):
		cache.erase(keys[i])



func _world_chunk_buf(cx: int, cy: int) -> PackedInt32Array:
	var ck = ctrl._chunk_key(Vector2i(cx, cy))
	if ctrl._wm_buf_cache.has(ck):
		return ctrl._wm_buf_cache[ck]
	var buf = PackedInt32Array()
	if ctrl.edit_doc != null and ctrl.edit_doc.has_method("chunk_buffer"):
		buf = ctrl.edit_doc.chunk_buffer(cx, cy)
	if buf.is_empty() and ctrl.pack != null and ctrl.pack.has_method("load_chunk_data"):
		buf = ctrl.pack.load_chunk_data(cx, cy)
	if buf.is_empty():
		var dir = _world_chunk_dir()
		if dir != "":
			buf = MapChunkStore.load_chunk(dir, cx, cy)
	if not buf.is_empty():
		ctrl._wm_buf_cache[ck] = buf
		_evict_wm_cache(ctrl._wm_buf_cache)
		return buf
	if not ctrl._uses_radar_window() and ctrl.collision != null:
		buf = MapChunkStore.empty_buf()
		var origin: Vector2i = MapChunkStore.chunk_origin(cx, cy)
		for ly in range(CHUNK_CELLS):
			for lx in range(CHUNK_CELLS):
				var gx = origin.x + lx
				var gy = origin.y + ly
				if gx < 0 or gy < 0 or gx >= ctrl.grid_width or gy >= ctrl.grid_height:
					continue
				for z in range(6):
					buf[MapChunkStore.local_index(lx, ly, z)] = ctrl._src_tile(ctrl.collision, gx, gy, z)
		ctrl._wm_buf_cache[ck] = buf
		_evict_wm_cache(ctrl._wm_buf_cache)
		return buf
	return PackedInt32Array()



func _stamp_world_chunk(cx: int, cy: int, buf: PackedInt32Array, sheets: Array, flags: PackedInt32Array) -> void:
	if ctrl._lofi_image == null or buf.is_empty():
		return
	var iw: int = ctrl._lofi_image.get_width()
	var ih: int = ctrl._lofi_image.get_height()
	if ctrl._wm_bytes.size() != iw * ih * 4:
		ctrl._wm_bytes = ctrl._lofi_image.get_data()
	MapChunkStore.stamp_overview_bytes(ctrl._wm_bytes, iw, ih, ctrl._wm_step, cx, cy, buf, sheets, flags, ctrl.grid_width, ctrl.grid_height)



func _commit_world_map_tex() -> void:
	if ctrl._lofi_image == null:
		return
	var iw: int = ctrl._lofi_image.get_width()
	var ih: int = ctrl._lofi_image.get_height()
	if ctrl._wm_bytes.size() == iw * ih * 4:
		ctrl._lofi_image.set_data(iw, ih, false, Image.FORMAT_RGBA8, ctrl._wm_bytes)
	if ctrl._world_map_tex is ImageTexture:
		var t: ImageTexture = ctrl._world_map_tex
		if t.get_width() == iw and t.get_height() == ih:
			t.update(ctrl._lofi_image)
			ctrl._overview_ground_tex = t
			return
	ctrl._world_map_tex = ImageTexture.create_from_image(ctrl._lofi_image)
	ctrl._overview_ground_tex = ctrl._world_map_tex



func _try_save_world_map() -> void:
	if ctrl._lofi_image == null:
		return
	var path = ""
	if ctrl.pack != null and "overview_path" in ctrl.pack:
		path = str(ctrl.pack.overview_path)
	if path == "" and ctrl.edit_doc != null and "_store_dir" in ctrl.edit_doc:
		path = MapChunkStore.overview_path(str(ctrl.edit_doc._store_dir))
	if path == "":
		return
	if path.begins_with("res://"):
		return
	ctrl._lofi_image.save_png(path)


