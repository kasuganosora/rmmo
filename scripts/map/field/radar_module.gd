extends RefCounted
## Domain module: radar/lofi overview (low-res atlas bake, scroll window, radar downsample).

var ctrl
func _init(c):
	ctrl = c

const MapChunkStore = preload("res://scripts/map/map_chunk_store.gd")
const CHUNK_CELLS := 16
const RADAR_ATLAS_SCALE: float = 0.5

func _ensure_lofi_canvas() -> void:
	var gw: int = maxi(ctrl.grid_width, 1)
	var gh: int = maxi(ctrl.grid_height, 1)
	if ctrl._lofi_image == null or ctrl._lofi_image.get_width() != gw or ctrl._lofi_image.get_height() != gh:
		ctrl._lofi_image = Image.create(gw, gh, false, Image.FORMAT_RGBA8)
		ctrl._lofi_image.fill(Color(0, 0, 0, 1))



func _stamp_lofi_from_chunk(node: Node2D, c: Vector2i) -> void:
	if node == null:
		return
	_ensure_lofi_canvas()
	var ts: int = maxi(ctrl.tile_size, 1)
	var x0: int = c.x * CHUNK_CELLS
	var y0: int = c.y * CHUNK_CELLS
	var cw: int = mini(CHUNK_CELLS, ctrl.grid_width - x0)
	var ch: int = mini(CHUNK_CELLS, ctrl.grid_height - y0)
	if cw <= 0 or ch <= 0:
		return
	## GroundAnim holds A1 water (static Ground is empty there).
	for bucket in ["Ground", "GroundAnim", "Upper", "UpperAnim"]:
		var spr: Sprite2D = node.get_node_or_null(bucket) as Sprite2D
		if spr == null or spr.texture == null:
			continue
		var tex: Texture2D = spr.texture
		var img: Image = tex.get_image() if tex is ImageTexture else null
		if img == null:
			continue
		for ly in range(ch):
			for lx in range(cw):
				var color = ctrl._avg_tile_px(img, lx * ts, ly * ts, ts)
				if color.a < 0.25:
					continue
				ctrl._lofi_image.set_pixel(x0 + lx, y0 + ly, color)



func _publish_lofi_atlas() -> void:
	if ctrl._lofi_image == null:
		return
	ctrl._ground_image = ctrl._lofi_image
	ctrl._radar_atlas_image = ctrl._lofi_image
	ctrl._radar_origin_cell = Vector2i.ZERO
	ctrl._radar_atlas_scale = 1.0 / float(maxi(ctrl.tile_size, 1))
	if ctrl._radar_atlas_tex != null and ctrl._radar_atlas_tex.get_width() == ctrl._lofi_image.get_width() and ctrl._radar_atlas_tex.get_height() == ctrl._lofi_image.get_height():
		ctrl._radar_atlas_tex.update(ctrl._lofi_image)
	else:
		ctrl._radar_atlas_tex = ImageTexture.create_from_image(ctrl._lofi_image)
	ctrl._world_map_tex = ctrl._radar_atlas_tex
	ctrl._overview_ground_tex = ctrl._radar_atlas_tex
	ctrl._wm_complete = true
	_ensure_lofi_sprite()



func _ensure_lofi_sprite() -> void:
	if ctrl._lofi_sprite == null or not is_instance_valid(ctrl._lofi_sprite):
		ctrl._lofi_sprite = ctrl.get_node_or_null("Lofi") as Sprite2D
		if ctrl._lofi_sprite == null:
			ctrl._lofi_sprite = Sprite2D.new()
			ctrl._lofi_sprite.name = "Lofi"
			ctrl.add_child(ctrl._lofi_sprite)
			ctrl.move_child(ctrl._lofi_sprite, 0)
		ctrl._lofi_sprite.centered = false
		ctrl._lofi_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ctrl._lofi_sprite.z_index = -2
		ctrl._lofi_sprite.z_as_relative = true
	if ctrl._lofi_image != null and ctrl._lofi_image.get_width() > 0:
		if ctrl._radar_atlas_tex == null:
			ctrl._radar_atlas_tex = ImageTexture.create_from_image(ctrl._lofi_image)
		var tex: Texture2D = ctrl._world_map_tex if ctrl._world_map_tex != null else ctrl._radar_atlas_tex
		ctrl._lofi_sprite.texture = tex
		if ctrl._lofi_image != null and ctrl._lofi_image.get_width() == ctrl.grid_width:
			ctrl._lofi_sprite.scale = Vector2(float(maxi(ctrl.tile_size, 1)), float(maxi(ctrl.tile_size, 1)))
		elif ctrl._lofi_image != null and ctrl._lofi_image.get_width() > 0 and ctrl.grid_width > 0:
			ctrl._lofi_sprite.scale = Vector2(
				float(ctrl.grid_width * maxi(ctrl.tile_size, 1)) / float(ctrl._lofi_image.get_width()),
				float(ctrl.grid_height * maxi(ctrl.tile_size, 1)) / float(maxi(ctrl._lofi_image.get_height(), 1))
			)
		else:
			ctrl._lofi_sprite.scale = Vector2(float(maxi(ctrl.tile_size, 1)), float(maxi(ctrl.tile_size, 1)))
		ctrl._lofi_sprite.visible = true
	elif ctrl._lofi_sprite != null:
		ctrl._lofi_sprite.visible = false




func get_radar_atlas_image() -> Image:
	return ctrl._radar_atlas_image



func get_radar_atlas_texture() -> Texture2D:
	return ctrl._radar_atlas_tex



func get_radar_atlas_scale() -> float:
	return ctrl._radar_atlas_scale



func get_lofi_image() -> Image:
	return ctrl._lofi_image



func get_lofi_texture() -> Texture2D:
	if ctrl._world_map_tex != null:
		return ctrl._world_map_tex
	if ctrl._radar_atlas_tex != null and not _uses_radar_window():
		return ctrl._radar_atlas_tex
	if ctrl._lofi_image != null and not _uses_radar_window():
		ctrl._radar_atlas_tex = ImageTexture.create_from_image(ctrl._lofi_image)
		return ctrl._radar_atlas_tex
	return ctrl._world_map_tex



func get_radar_origin_cell() -> Vector2i:
	return ctrl._radar_origin_cell



func _uses_radar_window() -> bool:
	if ctrl.pack != null and "streaming" in ctrl.pack and bool(ctrl.pack.streaming):
		return true
	return ctrl.grid_width * ctrl.grid_height > MapChunkStore.DENSE_MAX_CELLS



func _bake_radar_atlas(ground_img: Image, upper_img: Image, w_px: int, h_px: int) -> void:
	## One-time nearest downsample + upper blend. Radar scrolls a window; never resamples full map.
	var sc: float = RADAR_ATLAS_SCALE
	if sc <= 0.001:
		sc = 0.5
	var aw: int = maxi(1, int(round(float(w_px) * sc)))
	var ah: int = maxi(1, int(round(float(h_px) * sc)))
	if ground_img == null or ground_img.get_width() <= 0:
		ctrl._radar_atlas_image = null
		ctrl._radar_atlas_tex = null
		ctrl._radar_atlas_scale = sc
		return
	var atlas: Image = ground_img.duplicate()
	atlas.resize(aw, ah, Image.INTERPOLATE_NEAREST)
	if upper_img != null and upper_img.get_width() > 0:
		var u: Image = upper_img.duplicate()
		u.resize(aw, ah, Image.INTERPOLATE_NEAREST)
		atlas.blend_rect(u, Rect2i(0, 0, aw, ah), Vector2i.ZERO)
	ctrl._radar_atlas_image = atlas
	ctrl._radar_atlas_scale = sc
	ctrl._radar_atlas_tex = ImageTexture.create_from_image(atlas)



func _bake_radar_mv_only(do_yield: bool, progress: Callable) -> void:
	_bake_lofi_overview()
	if do_yield:
		ctrl._emit_progress(progress, 0.82)



func _bake_lofi_overview() -> void:
	ctrl._wm_buf_cache.clear()
	ctrl._wm_img_cache.clear()
	var gw: int = maxi(ctrl.grid_width, 1)
	var gh: int = maxi(ctrl.grid_height, 1)
	if _uses_radar_window():
		ctrl._load_offline_overview()
		_rebuild_radar_window()
		_ensure_lofi_sprite()
		return
	var img = Image.create(gw, gh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var sheets: Array = ctrl.pack.sheets if ctrl.pack else []
	var flags: PackedInt32Array = ctrl.pack.flags if ctrl.pack else PackedInt32Array()
	var col = ctrl.collision
	var void_id: int = ctrl._cached_void_id
	if void_id == 0:
		void_id = ctrl._detect_border_void_tile_id(col)
	for y in range(gh):
		for x in range(gw):
			if ctrl.edit_doc == null and ctrl._is_void_filler_cell(col, x, y, void_id):
				continue
			img.set_pixel(x, y, ctrl.cell_visual_color(x, y))
	ctrl._lofi_image = img
	ctrl._ground_image = img
	ctrl._upper_image = null
	ctrl._radar_atlas_image = img
	ctrl._radar_origin_cell = Vector2i.ZERO
	ctrl._radar_atlas_scale = 1.0 / float(maxi(ctrl.tile_size, 1))
	ctrl._radar_atlas_tex = ImageTexture.create_from_image(img)
	ctrl._overview_ground_tex = ctrl._radar_atlas_tex
	ctrl._overview_upper_tex = null
	ctrl._world_map_tex = ctrl._radar_atlas_tex
	ctrl._wm_complete = true
	ctrl._wm_jit_q.clear()
	ctrl._wm_step = 1
	_ensure_lofi_sprite()



func _rebuild_radar_window() -> void:
	var oc = ctrl.cell_to_chunk(ctrl._obs_cell)
	ctrl._radar_obs_chunk = oc
	var min_c = Vector2i(maxi(oc.x - 1, 0), maxi(oc.y - 1, 0))
	var counts: Vector2i = MapChunkStore.chunk_counts(ctrl.grid_width, ctrl.grid_height)
	var max_c = Vector2i(mini(oc.x + 1, counts.x - 1), mini(oc.y + 1, counts.y - 1))
	var x0: int = min_c.x * CHUNK_CELLS
	var y0: int = min_c.y * CHUNK_CELLS
	var x1: int = mini((max_c.x + 1) * CHUNK_CELLS, ctrl.grid_width)
	var y1: int = mini((max_c.y + 1) * CHUNK_CELLS, ctrl.grid_height)
	var ww: int = maxi(x1 - x0, 1)
	var hh: int = maxi(y1 - y0, 1)
	var img = Image.create(ww, hh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var sheets: Array = ctrl.pack.sheets if ctrl.pack else []
	var flags: PackedInt32Array = ctrl.pack.flags if ctrl.pack else PackedInt32Array()
	var col = ctrl.collision
	for y in range(hh):
		for x in range(ww):
			img.set_pixel(x, y, ctrl.cell_visual_color(x0 + x, y0 + y))
	ctrl._radar_origin_cell = Vector2i(x0, y0)
	ctrl._radar_atlas_image = img
	ctrl._radar_atlas_scale = 1.0 / float(maxi(ctrl.tile_size, 1))
	ctrl._radar_atlas_tex = ImageTexture.create_from_image(img)



func _patch_lofi_cells(cells: Array) -> void:
	if ctrl._lofi_image == null or cells.is_empty():
		return
	var sheets: Array = ctrl.pack.sheets if ctrl.pack else []
	var flags: PackedInt32Array = ctrl.pack.flags if ctrl.pack else PackedInt32Array()
	var col = ctrl.collision
	var gw: int = ctrl._lofi_image.get_width()
	var gh: int = ctrl._lofi_image.get_height()
	var changed = false
	for item in cells:
		var c: Vector2i = item
		if c.x < 0 or c.y < 0 or c.x >= gw or c.y >= gh:
			continue
		ctrl._lofi_image.set_pixel(c.x, c.y, ctrl.cell_visual_color(c.x, c.y))
		changed = true
	if not changed:
		return
	if ctrl._radar_atlas_tex != null:
		ctrl._radar_atlas_tex.update(ctrl._lofi_image)
	else:
		ctrl._radar_atlas_tex = ImageTexture.create_from_image(ctrl._lofi_image)
	ctrl._radar_atlas_image = ctrl._lofi_image
	ctrl._overview_ground_tex = ctrl._radar_atlas_tex
	_ensure_lofi_sprite()



func _render_lofi_preview(x0: int, y0: int, cells_w: int, cells_h: int, px: int) -> Image:
	var gw: int = maxi(ctrl.grid_width, 1)
	var gh: int = maxi(ctrl.grid_height, 1)
	x0 = clampi(x0, 0, gw - 1)
	y0 = clampi(y0, 0, gh - 1)
	cells_w = clampi(cells_w, 1, gw - x0)
	cells_h = clampi(cells_h, 1, gh - y0)
	px = maxi(px, 1)
	if ctrl._lofi_image != null and ctrl._lofi_image.get_width() == gw and ctrl._lofi_image.get_height() == gh:
		var chip = Image.create(cells_w, cells_h, false, Image.FORMAT_RGBA8)
		chip.blit_rect(ctrl._lofi_image, Rect2i(x0, y0, cells_w, cells_h), Vector2i.ZERO)
		if px > 1:
			chip.resize(cells_w * px, cells_h * px, Image.INTERPOLATE_NEAREST)
		return chip
	var dest = Image.create(cells_w * px, cells_h * px, false, Image.FORMAT_RGBA8)
	dest.fill(Color(0, 0, 0, 1))
	for y in range(cells_h):
		for x in range(cells_w):
			var acc: Color = ctrl.cell_visual_color(x0 + x, y0 + y)
			if px == 1:
				dest.set_pixel(x, y, acc)
			else:
				for py in range(px):
					for pxx in range(px):
						dest.set_pixel(x * px + pxx, y * px + py, acc)
	return dest


