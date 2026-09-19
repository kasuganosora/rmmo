extends RefCounted
## Domain module: chunk streaming (JIT load/unload HD chunks around camera/observer).

var ctrl
func _init(c):
	ctrl = c

const TileId = preload("res://scripts/map/tile_id.gd")
const MapChunk = preload("res://scripts/map/map_chunk.gd")
const MapChunkStore = preload("res://scripts/map/map_chunk_store.gd")
const CHUNK_CELLS := 16
const PREFETCH_CHUNKS := 1
const UNLOAD_EXTRA_CHUNKS := 1
const FACE_PREFETCH_CHUNKS := 2
const LOOKAHEAD_CELLS := 10
const ALL_HD_CHUNK_LIMIT := 36
const MAX_CHUNK_SPAN := 5

func current_chunk() -> Vector2i:
	return cell_to_chunk(ctrl._obs_cell)



func current_chunk_rect(cell: Vector2i = Vector2i(-9999, -9999)) -> Rect2i:
	if cell.x < -9000:
		cell = ctrl._obs_cell
	var ch: Vector2i = cell_to_chunk(cell)
	var o = Vector2i(ch.x * CHUNK_CELLS, ch.y * CHUNK_CELLS)
	var cw = mini(CHUNK_CELLS, maxi(ctrl.grid_width - o.x, 1))
	var chh = mini(CHUNK_CELLS, maxi(ctrl.grid_height - o.y, 1))
	if o.x < 0:
		o.x = 0
	if o.y < 0:
		o.y = 0
	return Rect2i(o.x, o.y, cw, chh)



func bake_observer_chunk() -> void:
	if not ctrl._stream_ready or ctrl.pack == null:
		return
	var pri: Vector2i = cell_to_chunk(ctrl._obs_cell)
	_prioritize_chunk(pri)
	_bake_next_chunk()



func _prioritize_chunk(ch: Vector2i) -> void:
	var key = _chunk_key(ch)
	if ctrl._chunks.has(key):
		return
	for i in range(ctrl._chunk_queue.size()):
		if ctrl._chunk_queue[i] == ch:
			if i > 0:
				ctrl._chunk_queue.remove_at(i)
				ctrl._chunk_queue.insert(0, ch)
			return
	ctrl._chunk_queue.insert(0, ch)



func rebake_loaded_chunks() -> void:
	if not ctrl._stream_ready:
		return
	for key in ctrl._chunks.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 2:
			continue
		var ch = Vector2i(int(parts[0]), int(parts[1]))
		var queued = false
		for q in ctrl._chunk_queue:
			if q == ch:
				queued = true
				break
		if not queued:
			ctrl._chunk_queue.append(ch)



func set_observer(cell: Vector2i, facing: int = 2) -> void:
	ctrl._obs_cell = cell
	ctrl._obs_facing = facing
	ctrl._apply_indoor_from_cell(cell)
	ctrl._apply_far_parallax()



func _update_observer_from_camera() -> void:
	var cam = ctrl.get_viewport().get_camera_2d() if ctrl.get_viewport() else null
	if cam == null:
		return
	var center: Vector2 = cam.get_screen_center_position()
	ctrl._obs_cell = ctrl.world_to_cell(center)



func _chunk_key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]



func cell_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(cell.x) / float(CHUNK_CELLS))),
		int(floor(float(cell.y) / float(CHUNK_CELLS)))
	)



func _wanted_chunks(center_cell: Vector2i, facing: int) -> Dictionary:
	var out = {}
	if ctrl.grid_width <= 0 or ctrl.tile_size <= 0:
		return out
	var max_cx = int(ceil(float(ctrl.grid_width) / float(CHUNK_CELLS))) - 1
	var max_cy = int(ceil(float(ctrl.grid_height) / float(CHUNK_CELLS))) - 1
	## Continent editor: only the chunk under the camera (rest is overview).
	if ctrl.edit_mode and ctrl._uses_radar_window():
		var oc0 = cell_to_chunk(center_cell)
		oc0.x = clampi(oc0.x, 0, maxi(max_cx, 0))
		oc0.y = clampi(oc0.y, 0, maxi(max_cy, 0))
		out[_chunk_key(oc0)] = oc0
		return out
	## 96×96 town (36 chunks): keep every HD chunk so a north walk never bakes mid-stride.
	if not ctrl.edit_mode and (max_cx + 1) * (max_cy + 1) <= ALL_HD_CHUNK_LIMIT:
		for cy in range(max_cy, -1, -1):
			for cx in range(max_cx, -1, -1):
				out[_chunk_key(Vector2i(cx, cy))] = Vector2i(cx, cy)
		return out
	var vis = ctrl.get_viewport().get_visible_rect().size if ctrl.get_viewport() else Vector2(2560, 1440)
	var z = 1.0
	var cam = ctrl.get_viewport().get_camera_2d() if ctrl.get_viewport() else null
	if cam != null:
		z = maxf(cam.zoom.x, 0.05)
	var half_cells = Vector2i(
		int(ceil(vis.x / (float(ctrl.tile_size) * z) * 0.5)) + CHUNK_CELLS,
		int(ceil(vis.y / (float(ctrl.tile_size) * z) * 0.5)) + CHUNK_CELLS
	)
	var min_c = cell_to_chunk(center_cell - half_cells)
	var max_c = cell_to_chunk(center_cell + half_cells)
	min_c -= Vector2i(PREFETCH_CHUNKS, PREFETCH_CHUNKS)
	max_c += Vector2i(PREFETCH_CHUNKS, PREFETCH_CHUNKS)
	var obs_c = cell_to_chunk(center_cell)
	var half_span = int(MAX_CHUNK_SPAN / 2)
	## Cap zoom-out to ±2 around the camera, then expand in the walk direction.
	min_c.x = clampi(min_c.x, obs_c.x - half_span, obs_c.x + half_span)
	max_c.x = clampi(max_c.x, obs_c.x - half_span, obs_c.x + half_span)
	min_c.y = clampi(min_c.y, obs_c.y - half_span, obs_c.y + half_span)
	max_c.y = clampi(max_c.y, obs_c.y - half_span, obs_c.y + half_span)
	if not ctrl.edit_mode:
		var fd: Vector2i = TileId.dir_delta(facing)
		if fd.x < 0:
			min_c.x -= FACE_PREFETCH_CHUNKS
		elif fd.x > 0:
			max_c.x += FACE_PREFETCH_CHUNKS
		if fd.y < 0:
			min_c.y -= FACE_PREFETCH_CHUNKS
		elif fd.y > 0:
			max_c.y += FACE_PREFETCH_CHUNKS
		var local_x: int = posmod(center_cell.x, CHUNK_CELLS)
		var local_y: int = posmod(center_cell.y, CHUNK_CELLS)
		if fd.x < 0 and local_x < LOOKAHEAD_CELLS:
			min_c.x -= 1
		elif fd.x > 0 and local_x >= CHUNK_CELLS - LOOKAHEAD_CELLS:
			max_c.x += 1
		if fd.y < 0 and local_y < LOOKAHEAD_CELLS:
			min_c.y -= 1
		elif fd.y > 0 and local_y >= CHUNK_CELLS - LOOKAHEAD_CELLS:
			max_c.y += 1
	for cy in range(mini(max_c.y, max_cy), maxi(min_c.y, 0) - 1, -1):
		for cx in range(mini(max_c.x, max_cx), maxi(min_c.x, 0) - 1, -1):
			if cx < 0 or cy < 0:
				continue
			out[_chunk_key(Vector2i(cx, cy))] = Vector2i(cx, cy)
	return out



func _rebuild_chunks_around(cell: Vector2i, bake_sync: bool) -> void:
	_clear_chunks()
	_refresh_chunk_set()
	if bake_sync:
		while not ctrl._chunk_queue.is_empty():
			_bake_next_chunk()
		ctrl._publish_lofi_atlas()



func _clear_chunks() -> void:
	for key in ctrl._chunks.keys():
		var n: Node = ctrl._chunks[key]
		if n != null and is_instance_valid(n):
			n.queue_free()
	ctrl._chunks.clear()
	ctrl._chunk_queue.clear()
	ctrl._last_obs_cell = Vector2i(2147483647, 2147483647)
	ctrl._last_obs_facing = -1
	if ctrl._chunk_root != null and is_instance_valid(ctrl._chunk_root):
		ctrl._chunk_root.queue_free()
	ctrl._chunk_root = Node2D.new()
	ctrl._chunk_root.name = "Chunks"
	ctrl.add_child(ctrl._chunk_root)



func _refresh_chunk_set() -> void:
	var wanted = _wanted_chunks(ctrl._obs_cell, ctrl._obs_facing)
	_sync_stream_data(wanted)
	var obs_ch = cell_to_chunk(ctrl._obs_cell)
	if ctrl._uses_radar_window() and obs_ch != ctrl._radar_obs_chunk:
		ctrl._rebuild_radar_window()
	for key in wanted.keys():
		if ctrl._chunks.has(key):
			continue
		var already = false
		for q in ctrl._chunk_queue:
			if _chunk_key(q) == key:
				already = true
				break
		if not already:
			_enqueue_chunk(wanted[key])
	# Hysteresis unload: keep UNLOAD_EXTRA beyond wanted. Collect first — do not erase while iterating.
	var to_drop: Array[String] = []
	for key2 in ctrl._chunks.keys():
		if wanted.has(key2):
			continue
		var node_keep = ctrl._chunks[key2]
		var c: Vector2i = node_keep.chunk if node_keep else Vector2i.ZERO
		var drop = true
		for k3 in wanted.keys():
			var w: Vector2i = wanted[k3]
			if absi(c.x - w.x) <= UNLOAD_EXTRA_CHUNKS and absi(c.y - w.y) <= UNLOAD_EXTRA_CHUNKS:
				drop = false
				break
		if drop:
			to_drop.append(str(key2))
	for dk in to_drop:
		var node: Node = ctrl._chunks.get(dk)
		ctrl._chunks.erase(dk)
		if node != null and is_instance_valid(node):
			node.queue_free()



func _sync_stream_data(wanted: Dictionary) -> void:
	if ctrl.collision == null or not ("streaming" in ctrl.collision and bool(ctrl.collision.streaming)):
		return
	var map_dir = ""
	if ctrl.pack != null and "chunk_map_dir" in ctrl.pack and str(ctrl.pack.chunk_map_dir) != "":
		map_dir = str(ctrl.pack.chunk_map_dir)
	for key in wanted.keys():
		var c: Vector2i = wanted[key]
		if ctrl.collision.has_method("has_stream_chunk") and ctrl.collision.has_stream_chunk(c.x, c.y):
			continue
		var buf = PackedInt32Array()
		if ctrl.edit_doc != null and ctrl.edit_doc.has_method("chunk_buffer"):
			buf = ctrl.edit_doc.chunk_buffer(c.x, c.y)
		elif ctrl.pack != null and ctrl.pack.has_method("load_chunk_data"):
			buf = ctrl.pack.load_chunk_data(c.x, c.y)
		elif map_dir != "":
			buf = MapChunkStore.load_chunk(map_dir, c.x, c.y)
		if ctrl.collision.has_method("ingest_stream_chunk"):
			ctrl.collision.ingest_stream_chunk(c.x, c.y, buf)
	if not ctrl.collision.has_method("stream_chunk_keys"):
		return
	var keys: Array = ctrl.collision.stream_chunk_keys()
	for key2 in keys:
		if wanted.has(key2):
			continue
		var parts: PackedStringArray = str(key2).split(",")
		if parts.size() < 2:
			continue
		var c2 = Vector2i(int(parts[0]), int(parts[1]))
		var keep = false
		for k3 in wanted.keys():
			var w: Vector2i = wanted[k3]
			if absi(c2.x - w.x) <= UNLOAD_EXTRA_CHUNKS and absi(c2.y - w.y) <= UNLOAD_EXTRA_CHUNKS:
				keep = true
				break
		if not keep and ctrl.collision.has_method("drop_stream_chunk"):
			ctrl.collision.drop_stream_chunk(c2.x, c2.y)



func _enqueue_chunk(c: Vector2i) -> void:
	var key = _chunk_key(c)
	if ctrl._chunks.has(key):
		return
	for q in ctrl._chunk_queue:
		if _chunk_key(q) == key:
			return
	if _chunk_is_ahead(c):
		ctrl._chunk_queue.insert(0, c)
	else:
		ctrl._chunk_queue.append(c)



func _chunk_is_ahead(c: Vector2i) -> bool:
	var fd: Vector2i = TileId.dir_delta(ctrl._obs_facing)
	if fd == Vector2i.ZERO:
		return false
	var obs: Vector2i = cell_to_chunk(ctrl._obs_cell)
	var rel: Vector2i = c - obs
	return rel.x * fd.x + rel.y * fd.y > 0



func _bake_next_chunk(full_anim: bool = true) -> void:
	if ctrl._chunk_queue.is_empty() or ctrl.pack == null:
		return
	if ctrl._chunk_root == null or not is_instance_valid(ctrl._chunk_root):
		ctrl._chunk_root = Node2D.new()
		ctrl._chunk_root.name = "Chunks"
		ctrl.add_child(ctrl._chunk_root)
	var c: Vector2i = ctrl._chunk_queue.pop_front()
	var key = _chunk_key(c)
	var x0 = c.x * CHUNK_CELLS
	var y0 = c.y * CHUNK_CELLS
	if x0 >= ctrl.grid_width or y0 >= ctrl.grid_height:
		return
	var cw = mini(CHUNK_CELLS, ctrl.grid_width - x0)
	var ch = mini(CHUNK_CELLS, ctrl.grid_height - y0)
	var ts = ctrl.tile_size
	var img_w = cw * ts
	var img_h = ch * ts
	var below = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	var ground = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	var upper = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	var roof = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	var fx = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	below.fill(Color(0, 0, 0, 0))
	ground.fill(Color(0, 0, 0, 0))
	upper.fill(Color(0, 0, 0, 0))
	roof.fill(Color(0, 0, 0, 0))
	fx.fill(Color(0, 0, 0, 0))
	var sheets: Array = ctrl.pack.sheets
	var flags: PackedInt32Array = ctrl.pack.flags
	var col = ctrl.collision
	var void_id: int = ctrl._cached_void_id
	ctrl._begin_anim_bake()
	for y in range(ch):
		for x in range(cw):
			var gx = x0 + x
			var gy = y0 + y
			var dx = x * ts
			var dy = y * ts
			ctrl._paint_cell(ground, upper, col, sheets, flags, void_id, gx, gy, dx, dy)
			ctrl._paint_ext_cell(below, ground, upper, roof, fx, col, sheets, flags, gx, gy, dx, dy)
	var node: Node2D = ctrl._chunks.get(key) as Node2D
	if node == null or not is_instance_valid(node):
		node = MapChunk.new()
		node.setup(c, Vector2(x0 * ts, y0 * ts))
		ctrl._chunk_root.add_child(node)
		ctrl._chunks[key] = node
	if node.has_method("clear_visuals"):
		node.clear_visuals()
	node.apply_bucket("Below", below, -20)
	node.apply_bucket("Ground", ground, 0)
	node.apply_bucket("Upper", upper, 10)
	node.apply_bucket("Roof", roof, 12)
	node.apply_bucket("Fx", fx, 16, true)
	ctrl._finish_anim_bake(node, full_anim)
	if node.has_method("set_fx_modulate"):
		node.set_fx_modulate(ctrl.light_fx_color())
	if node.has_method("set_roof_visible"):
		node.set_roof_visible(not ctrl._roof_hidden)
	ctrl._stamp_lofi_from_chunk(node, c)
	if not full_anim:
		ctrl._publish_lofi_atlas()
	ctrl._ensure_edit_overlay()


