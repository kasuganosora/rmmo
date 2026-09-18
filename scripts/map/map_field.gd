extends Node2D
## Renders a tilemap pack to Ground/Objects/Upper sprites and exposes collision.

const TilemapPack = preload("res://scripts/map/tilemap_pack.gd")
const TileBlit = preload("res://scripts/map/tile_blit.gd")
const TileId = preload("res://scripts/map/tile_id.gd")
const MapChunk = preload("res://scripts/map/map_chunk.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const Weather = preload("res://scripts/map/weather.gd")
const WeatherFxScript = preload("res://scripts/map/weather_fx.gd")
const MapChunkStore = preload("res://scripts/map/map_chunk_store.gd")

const CHUNK_CELLS := 16
const PREFETCH_CHUNKS := 1
const UNLOAD_EXTRA_CHUNKS := 1
## Extra HD rows/cols in the walk direction (not clamped away by MAX_CHUNK_SPAN).
const FACE_PREFETCH_CHUNKS := 2
## When this close to a chunk edge, treat the neighbor as already wanted.
const LOOKAHEAD_CELLS := 10
## Town-sized maps (96×96 = 36 chunks): keep every HD chunk loaded so walking never bakes.
const ALL_HD_CHUNK_LIMIT := 36
## High-res chunks around the camera only. Zoomed-out view uses the 1px/cell overview.
const MAX_CHUNK_SPAN := 5
## MV Tilemap: animationFrame = floor(animationCount / 30) at 60fps → 0.5s/step.
const ANIM_STEP_SEC := 0.5

@export var pack_path: String = "res://demo_map"

var pack: RefCounted = null
var collision: RefCounted = null
var tile_size: int = 48
var grid_width: int = 0
var grid_height: int = 0

var _ground: Sprite2D
var _objects: Sprite2D
var _upper: Sprite2D
var _shadow: Sprite2D

var _ground_image: Image
var _upper_image: Image

## Low-res blended atlas for radar (baked once at rebuild; walking only scrolls a window).
const RADAR_ATLAS_SCALE: float = 0.5
var _radar_atlas_image: Image = null
var _radar_atlas_tex: ImageTexture = null
var _radar_atlas_scale: float = RADAR_ATLAS_SCALE
var _content_pixel_rect_cache: Rect2i = Rect2i()
## When true, _ready skips rebuild (Loading drives rebuild_async).
var skip_ready_rebuild: bool = false
var _content_pixel_rect_valid: bool = false

var _chunk_root: Node2D
var _chunks: Dictionary = {} ## "cx,cy" -> MapChunk
var _chunk_queue: Array[Vector2i] = []
var _obs_cell: Vector2i = Vector2i.ZERO
var _obs_facing: int = 2
var _roof_hidden: bool = false
var _stream_ready: bool = false
var _cached_void_id: int = 0
var _overview_ground_tex: ImageTexture = null
var _overview_upper_tex: ImageTexture = null
var _lofi_image: Image = null
var _lofi_sprite: Sprite2D
var _radar_origin_cell: Vector2i = Vector2i.ZERO
var _radar_obs_chunk: Vector2i = Vector2i(2147483647, 2147483647)
var _world_map_tex: Texture2D = null
var _wm_complete: bool = false
var _wm_jit_q: Array[Vector2i] = []
var _wm_jit_total: int = 0
var _wm_step: int = 1
var _wm_buf_cache: Dictionary = {}
var _wm_img_cache: Dictionary = {}
var _wm_bytes: PackedByteArray = PackedByteArray()
const WM_CACHE_MAX := 64
var edit_mode: bool = false
var edit_doc: RefCounted = null
var show_grid: bool = false
var edit_map_id: String = ""
var edit_start_cell: Vector2i = Vector2i(-1, -1)
var edit_show_passage: bool = false
var edit_passage_overlay: bool = false
var edit_bucket_alpha: Dictionary = {}
var _ref_sprite: Sprite2D
var _ref_alpha: float = 0.35
var edit_hover_cell: Vector2i = Vector2i(-1, -1)
var edit_cursor_cell: Vector2i = Vector2i(-1, -1)
var edit_rect_a: Vector2i = Vector2i(-1, -1)
var edit_rect_b: Vector2i = Vector2i(-1, -1)
var edit_stamp_size: Vector2i = Vector2i(1, 1)
var edit_spec_kind: String = ""
var edit_hidden_z: PackedByteArray = PackedByteArray([0, 0, 0, 0, 0, 0])
var edit_hidden_ext: Dictionary = {}
var _edit_overlay: Node2D
var _weather_fx: CanvasLayer
var last_atmosphere: Dictionary = {}
var _atm_light: int = 0
var _atm_kind: String = "clear"
var _atm_intensity: float = 0.0
var _anim_frame: int = 0
var _anim_accum: float = 0.0
var _last_obs_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _last_obs_facing: int = -1
var _bake_anim: bool = false
var _bake_anim_jobs: Array = []
var _bake_anim_shadows: Array = []
var _bake_anim_imgs: Dictionary = {}
var _cell_visual_cache: Dictionary = {}
var _cell_visual_ground: Image = null
var _cell_visual_upper: Image = null


func _ready() -> void:
	_ensure_sprites()
	if skip_ready_rebuild:
		return
	# Prefer spawn pack so we do not bake the scene default then rebuild.
	var session_pack: String = _session_pack_path()
	if session_pack != "":
		pack_path = session_pack
	if try_apply_session_bake():
		return
	rebuild()


func _ensure_sprites() -> void:
	# Ground: floors, rugs, non-higher z2/z3 furniture, shadows (below player ~5).
	_ground = get_node_or_null("Ground") as Sprite2D
	if _ground == null:
		_ground = get_node_or_null("Lower") as Sprite2D
	if _ground == null:
		_ground = Sprite2D.new()
		_ground.name = "Ground"
		add_child(_ground)
	_ground.centered = false
	_ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ground.z_index = 0
	_ground.z_as_relative = true

	# Objects: unused (kept for scene compat); non-higher tiles use Ground.
	_objects = get_node_or_null("Objects") as Sprite2D
	if _objects == null:
		_objects = Sprite2D.new()
		_objects.name = "Objects"
		add_child(_objects)
	_objects.centered = false
	_objects.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_objects.z_index = 3
	_objects.z_as_relative = true

	_shadow = get_node_or_null("Shadow") as Sprite2D
	if _shadow == null:
		_shadow = Sprite2D.new()
		_shadow.name = "Shadow"
		add_child(_shadow)
	_shadow.centered = false
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow.z_index = 1
	_shadow.z_as_relative = true

	# Upper: star/higher tiles only (flag 0x10); characters walk under.
	_upper = get_node_or_null("Upper") as Sprite2D
	if _upper == null:
		_upper = Sprite2D.new()
		_upper.name = "Upper"
		add_child(_upper)
	_upper.centered = false
	_upper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_upper.z_index = 10
	_upper.z_as_relative = true

	_ensure_lofi_sprite()


func _ensure_lofi_canvas() -> void:
	var gw: int = maxi(grid_width, 1)
	var gh: int = maxi(grid_height, 1)
	if _lofi_image == null or _lofi_image.get_width() != gw or _lofi_image.get_height() != gh:
		_lofi_image = Image.create(gw, gh, false, Image.FORMAT_RGBA8)
		_lofi_image.fill(Color(0, 0, 0, 1))


func _stamp_lofi_from_chunk(node: Node2D, c: Vector2i) -> void:
	if node == null:
		return
	_ensure_lofi_canvas()
	var ts: int = maxi(tile_size, 1)
	var x0: int = c.x * CHUNK_CELLS
	var y0: int = c.y * CHUNK_CELLS
	var cw: int = mini(CHUNK_CELLS, grid_width - x0)
	var ch: int = mini(CHUNK_CELLS, grid_height - y0)
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
				var color := _avg_tile_px(img, lx * ts, ly * ts, ts)
				if color.a < 0.25:
					continue
				_lofi_image.set_pixel(x0 + lx, y0 + ly, color)


func cell_visual_color(x: int, y: int) -> Color:
	var col = collision
	var sheets: Array = pack.sheets if pack else []
	var flags: PackedInt32Array = pack.flags if pack else PackedInt32Array()
	var t0: int = _src_tile(col, x, y, 0)
	var t1: int = _src_tile(col, x, y, 1)
	var t2: int = _src_tile(col, x, y, 2)
	var t3: int = _src_tile(col, x, y, 3)
	var sh: int = _src_tile(col, x, y, 4)
	var key := "%d:%d:%d:%d:%d" % [t0, t1, t2, t3, sh]
	if _cell_visual_cache.has(key):
		return _cell_visual_cache[key]
	var ts: int = 48
	if _cell_visual_ground == null or _cell_visual_ground.get_width() != ts:
		_cell_visual_ground = Image.create(ts, ts, false, Image.FORMAT_RGBA8)
		_cell_visual_upper = Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	_cell_visual_ground.fill(Color(0, 0, 0, 0))
	_cell_visual_upper.fill(Color(0, 0, 0, 0))
	var saved_ts: int = tile_size
	var saved_anim: bool = _bake_anim
	tile_size = ts
	_bake_anim = false
	_paint_cell(_cell_visual_ground, _cell_visual_upper, col, sheets, flags, _cached_void_id, x, y, 0, 0)
	_bake_anim = saved_anim
	tile_size = saved_ts
	var c: Color = _avg_tile_px(_cell_visual_ground, 0, 0, ts)
	var u: Color = _avg_tile_px(_cell_visual_upper, 0, 0, ts)
	if u.a >= 0.25:
		c = u
	if c.a < 0.15:
		c = Color(0, 0, 0, 1)
	_cell_visual_cache[key] = c
	return c


func _avg_tile_px(img: Image, ox: int, oy: int, ts: int) -> Color:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	var iw: int = img.get_width()
	var ih: int = img.get_height()
	for sy in [8, 24, 40]:
		for sx in [8, 24, 40]:
			var x: int = ox + sx
			var y: int = oy + sy
			if x < 0 or y < 0 or x >= iw or y >= ih:
				continue
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.12:
				continue
			r += c.r
			g += c.g
			b += c.b
			n += 1
	if n <= 0:
		return Color(0, 0, 0, 0)
	return Color(r / float(n), g / float(n), b / float(n), 1)


func _publish_lofi_atlas() -> void:
	if _lofi_image == null:
		return
	_ground_image = _lofi_image
	_radar_atlas_image = _lofi_image
	_radar_origin_cell = Vector2i.ZERO
	_radar_atlas_scale = 1.0 / float(maxi(tile_size, 1))
	if _radar_atlas_tex != null and _radar_atlas_tex.get_width() == _lofi_image.get_width() and _radar_atlas_tex.get_height() == _lofi_image.get_height():
		_radar_atlas_tex.update(_lofi_image)
	else:
		_radar_atlas_tex = ImageTexture.create_from_image(_lofi_image)
	_world_map_tex = _radar_atlas_tex
	_overview_ground_tex = _radar_atlas_tex
	_wm_complete = true
	_ensure_lofi_sprite()


func _ensure_lofi_sprite() -> void:
	if _lofi_sprite == null or not is_instance_valid(_lofi_sprite):
		_lofi_sprite = get_node_or_null("Lofi") as Sprite2D
		if _lofi_sprite == null:
			_lofi_sprite = Sprite2D.new()
			_lofi_sprite.name = "Lofi"
			add_child(_lofi_sprite)
			move_child(_lofi_sprite, 0)
		_lofi_sprite.centered = false
		_lofi_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_lofi_sprite.z_index = -2
		_lofi_sprite.z_as_relative = true
	if _lofi_image != null and _lofi_image.get_width() > 0:
		if _radar_atlas_tex == null:
			_radar_atlas_tex = ImageTexture.create_from_image(_lofi_image)
		var tex: Texture2D = _world_map_tex if _world_map_tex != null else _radar_atlas_tex
		_lofi_sprite.texture = tex
		if _lofi_image != null and _lofi_image.get_width() == grid_width:
			_lofi_sprite.scale = Vector2(float(maxi(tile_size, 1)), float(maxi(tile_size, 1)))
		elif _lofi_image != null and _lofi_image.get_width() > 0 and grid_width > 0:
			_lofi_sprite.scale = Vector2(
				float(grid_width * maxi(tile_size, 1)) / float(_lofi_image.get_width()),
				float(grid_height * maxi(tile_size, 1)) / float(maxi(_lofi_image.get_height(), 1))
			)
		else:
			_lofi_sprite.scale = Vector2(float(maxi(tile_size, 1)), float(maxi(tile_size, 1)))
		_lofi_sprite.visible = true
	elif _lofi_sprite != null:
		_lofi_sprite.visible = false



func _resolve_pack_path(p: String) -> String:
	p = p.strip_edges()
	if p.is_empty():
		p = "res://demo_map"
	var am: Node = get_node_or_null("/root/AssetManager")
	if am != null and am.has_method("resolve_map_pack_path"):
		return str(am.resolve_map_pack_path(p))
	return p


func rebuild() -> void:
	# Sync path (world fallback). Loading should call rebuild_async instead.
	_rebuild_internal_sync()


func _rebuild_internal_sync() -> void:
	_ensure_sprites()
	pack = TilemapPack.load_pack(_resolve_pack_path(pack_path), _resolved_map_id())
	if pack == null or pack.width <= 0:
		push_error("MapField: failed to load pack at %s" % pack_path)
		return
	collision = pack.collision
	tile_size = pack.tile_size
	grid_width = pack.width
	grid_height = pack.height
	_content_pixel_rect_valid = false
	_cached_void_id = _detect_border_void_tile_id(collision)
	_cell_visual_cache.clear()
	_hide_legacy_fullmap_sprites()
	_bake_lofi_overview()
	_stream_ready = true
	_apply_edit_doc_size()
	_obs_cell = _spawn_cell_from_session() if not edit_mode else _edit_observer_cell()
	_rebuild_chunks_around(_obs_cell, not edit_mode)
	if edit_mode:
		bake_observer_chunk()
	_ensure_edit_overlay()


func _rebuild_internal(do_yield: bool, progress: Callable) -> void:
	_ensure_sprites()
	_emit_progress(progress, 0.05)
	if do_yield:
		await get_tree().process_frame
		if not is_instance_valid(self):
			return
	pack = TilemapPack.load_pack(_resolve_pack_path(pack_path), _resolved_map_id())
	if pack == null or pack.width <= 0:
		push_error("MapField: failed to load pack at %s" % pack_path)
		return
	collision = pack.collision
	tile_size = pack.tile_size
	grid_width = pack.width
	grid_height = pack.height
	_content_pixel_rect_valid = false
	_cached_void_id = _detect_border_void_tile_id(collision)
	_cell_visual_cache.clear()
	_hide_legacy_fullmap_sprites()
	_emit_progress(progress, 0.12)
	if do_yield:
		await get_tree().process_frame
		if not is_instance_valid(self):
			return
	_bake_lofi_overview()
	_emit_progress(progress, 0.88)
	if do_yield:
		await get_tree().process_frame
		if not is_instance_valid(self):
			return
	_stream_ready = true
	_obs_cell = _spawn_cell_from_session()
	_rebuild_chunks_around(_obs_cell, not do_yield)
	if do_yield:
		while not _chunk_queue.is_empty():
			_bake_next_chunk()
			_emit_progress(progress, 0.88 + 0.12 * (1.0 - float(_chunk_queue.size()) / 8.0))
			await get_tree().process_frame
			if not is_instance_valid(self):
				return
		_publish_lofi_atlas()
	_emit_progress(progress, 1.0)


func _paint_cell(
	ground_img: Image,
	upper_img: Image,
	col,
	sheets: Array,
	flags: PackedInt32Array,
	void_id: int,
	x: int,
	y: int,
	dx: int = -1,
	dy: int = -1
) -> void:
	if dx < 0:
		dx = x * tile_size
	if dy < 0:
		dy = y * tile_size
	var t0: int = _src_tile(col, x, y, 0)
	var t1: int = _src_tile(col, x, y, 1)
	var t2: int = _src_tile(col, x, y, 2)
	var t3: int = _src_tile(col, x, y, 3)
	# Outdoor void filler -> keep pure black (match Void / clear color).
	# In the editor, collision still mirrors the last saved pack (often all-zero
	# on a new map). Skipping here would discard live edit_doc paints.
	if edit_doc == null and _is_void_filler_cell(col, x, y, void_id):
		return
	# Pack layer 4 holds corner-shadow bits (0..15); layer 5 is region id.
	# MV: shadowBits = readMapData(z=4) only — never treat z3 tileIds as shadows.
	# Tile IDs 1..15 are real B-sheet tiles (often 0x10 upper awnings); mis-reading
	# them as shadow quarters caused dark/checkered sidewalk patches on street_map.
	var shadow_bits: int = 0
	if col != null and col.has_method("tile_id"):
		shadow_bits = int(_src_tile(col, x, y, 4))
	var above_t1: int = 0
	if y > 0:
		above_t1 = int(_src_tile(col, x, y - 1, 1))

	# Match classic paint order: z0, z1, shadow, table-edge, z2, z3.
	# Each tile goes to ground or upper solely by flag 0x10 (not by z-layer).
	if is_layer_drawn_z(0):
		_blit_by_flag(ground_img, upper_img, t0, dx, dy, sheets, flags)
	if is_layer_drawn_z(1):
		_blit_by_flag(ground_img, upper_img, t1, dx, dy, sheets, flags)

	# Shadows blend into ground so transparent rug fringes stay clean.
	if is_layer_drawn_z(4) and shadow_bits > 0 and (shadow_bits & 0x0f) != 0:
		var bits: int = shadow_bits & 0x0f
		TileBlit.blit_shadow(ground_img, bits, dx, dy, tile_size, tile_size)
		if _bake_anim and _cell_has_ground_anim(t0, t1, t2, t3, flags):
			_bake_anim_shadows.append({"dx": dx, "dy": dy, "bits": bits})
			TileBlit.blit_shadow(_anim_image("Ground", ground_img), bits, dx, dy, tile_size, tile_size)

	# Table edge into lower when cell above z1 is a table and this z1 is not.
	if is_layer_drawn_z(1) and TileBlit.is_table_tile(above_t1, flags) and not TileBlit.is_table_tile(t1, flags):
		var shadowing: bool = TileId.is_tile_a3(t0) or TileId.is_tile_a4(t0)
		if not shadowing:
			TileBlit.blit_table_edge(ground_img, above_t1, dx, dy, sheets, tile_size, tile_size)

	# z2 then z3 on the same ground/upper bitmap (in-cell stack order).
	# Always paint z3 when visible (includes tileIds 1..15).
	if is_layer_drawn_z(2):
		_blit_by_flag(ground_img, upper_img, t2, dx, dy, sheets, flags)
	if is_layer_drawn_z(3):
		_blit_by_flag(ground_img, upper_img, t3, dx, dy, sheets, flags)



func _blit_by_flag(
	ground_img: Image,
	upper_img: Image,
	tile_id: int,
	dx: int,
	dy: int,
	sheets: Array,
	flags: PackedInt32Array
) -> void:
	if tile_id <= 0:
		return
	var dest: Image = ground_img
	var bucket: String = "Ground"
	if tile_id < flags.size() and (flags[tile_id] & 0x10) != 0:
		dest = upper_img
		bucket = "Upper"
	_route_blit(dest, bucket, tile_id, dx, dy, sheets, flags)



func _detect_border_void_tile_id(col) -> int:
	## Prefer MapCollision.void_tile_id (shared with passage / AStar).
	if col != null and col.has_method("is_void_cell"):
		return int(col.void_tile_id)
	## Fallback: most common z0-only tile on the map border.
	if col == null or grid_width <= 0 or grid_height <= 0:
		return 0
	var counts: Dictionary = {}
	for y in range(grid_height):
		for x in range(grid_width):
			if x != 0 and y != 0 and x != grid_width - 1 and y != grid_height - 1:
				continue
			var t0: int = int(col.tile_id(x, y, 0))
			var t1: int = int(col.tile_id(x, y, 1))
			var t2: int = int(col.tile_id(x, y, 2))
			var t3: int = int(col.tile_id(x, y, 3))
			if t0 <= 0:
				continue
			if t1 != 0 or t2 != 0 or t3 != 0:
				continue
			counts[t0] = int(counts.get(t0, 0)) + 1
	var best_id: int = 0
	var best_n: int = 0
	for k in counts.keys():
		var n: int = int(counts[k])
		if n > best_n:
			best_n = n
			best_id = int(k)
	if best_n < maxi(4, (grid_width + grid_height) / 2):
		return 0
	return best_id


func _is_void_filler_cell(col, x: int, y: int, void_id: int) -> bool:
	if col == null:
		return false
	if col.has_method("is_void_cell"):
		return bool(col.is_void_cell(x, y))
	var t0: int = int(col.tile_id(x, y, 0))
	var t1: int = int(col.tile_id(x, y, 1))
	var t2: int = int(col.tile_id(x, y, 2))
	var t3: int = int(col.tile_id(x, y, 3))
	if t0 == 0 and t1 == 0 and t2 == 0 and t3 == 0:
		return true
	if void_id > 0 and t0 == void_id and t1 == 0 and t2 == 0 and t3 == 0:
		return true
	return false


func get_content_cell_rect() -> Rect2i:
	## AABB of non-void cells (excludes outdoor border filler / fully empty).
	if collision == null or grid_width <= 0 or grid_height <= 0:
		return Rect2i(0, 0, maxi(grid_width, 0), maxi(grid_height, 0))
	if grid_width * grid_height > MapChunkStore.DENSE_MAX_CELLS:
		return Rect2i(0, 0, grid_width, grid_height)
	var void_id: int = _detect_border_void_tile_id(collision)
	var min_x: int = grid_width
	var min_y: int = grid_height
	var max_x: int = -1
	var max_y: int = -1
	for y in range(grid_height):
		for x in range(grid_width):
			if _is_void_filler_cell(collision, x, y, void_id):
				continue
			# Any remaining non-zero tile counts as content (walls/floors/props).
			var has: bool = false
			for z in range(4):
				if int(collision.tile_id(x, y, z)) > 0:
					has = true
					break
			if not has:
				continue
			if x < min_x:
				min_x = x
			if y < min_y:
				min_y = y
			if x > max_x:
				max_x = x
			if y > max_y:
				max_y = y
	if max_x < min_x or max_y < min_y:
		return Rect2i(0, 0, grid_width, grid_height)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func get_content_pixel_rect() -> Rect2i:
	## Pixel AABB covering content cells (tile_size scale). Cached after first compute per rebuild.
	if _content_pixel_rect_valid:
		return _content_pixel_rect_cache
	var cells := get_content_cell_rect()
	var ts: int = maxi(tile_size, 1)
	_content_pixel_rect_cache = Rect2i(
		cells.position.x * ts, cells.position.y * ts, cells.size.x * ts, cells.size.y * ts
	)
	_content_pixel_rect_valid = true
	return _content_pixel_rect_cache


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / float(tile_size))), int(floor(world_pos.y / float(tile_size))))


func cell_to_world(cell: Vector2i) -> Vector2:
	# Bottom-center of the cell; character feet stand on the ground line.
	return Vector2(
		float(cell.x) * float(tile_size) + float(tile_size) * 0.5,
		float(cell.y) * float(tile_size) + float(tile_size)
	)


func is_valid_cell(cell: Vector2i) -> bool:
	return collision != null and collision.is_valid(cell.x, cell.y)


func get_ground_image() -> Image:
	return _ground_image


func get_upper_image() -> Image:
	return _upper_image


func get_ground_texture() -> Texture2D:
	if _ground != null and _ground.texture != null:
		return _ground.texture
	if _overview_ground_tex != null:
		return _overview_ground_tex
	if _ground_image != null:
		_overview_ground_tex = ImageTexture.create_from_image(_ground_image)
		return _overview_ground_tex
	return null


func get_upper_texture() -> Texture2D:
	if _upper != null and _upper.texture != null:
		return _upper.texture
	if _overview_upper_tex != null:
		return _overview_upper_tex
	if _upper_image != null:
		_overview_upper_tex = ImageTexture.create_from_image(_upper_image)
		return _overview_upper_tex
	return null


func get_radar_atlas_image() -> Image:
	return _radar_atlas_image


func get_radar_atlas_texture() -> Texture2D:
	return _radar_atlas_tex


func get_radar_atlas_scale() -> float:
	return _radar_atlas_scale


func get_lofi_image() -> Image:
	return _lofi_image


func get_lofi_texture() -> Texture2D:
	if _world_map_tex != null:
		return _world_map_tex
	if _radar_atlas_tex != null and not _uses_radar_window():
		return _radar_atlas_tex
	if _lofi_image != null and not _uses_radar_window():
		_radar_atlas_tex = ImageTexture.create_from_image(_lofi_image)
		return _radar_atlas_tex
	return _world_map_tex


func get_radar_origin_cell() -> Vector2i:
	return _radar_origin_cell


func _uses_radar_window() -> bool:
	if pack != null and "streaming" in pack and bool(pack.streaming):
		return true
	return grid_width * grid_height > MapChunkStore.DENSE_MAX_CELLS


func world_map_complete() -> bool:
	return _wm_complete or not _uses_radar_window()


func world_map_progress() -> float:
	if world_map_complete():
		return 1.0
	if _wm_jit_total <= 0:
		return 0.0
	return clampf(1.0 - float(_wm_jit_q.size()) / float(_wm_jit_total), 0.0, 1.0)


func ensure_world_map() -> void:
	if not _uses_radar_window():
		_wm_complete = true
		return
	if _wm_complete and _lofi_image != null and _lofi_image.get_width() > 8:
		return
	_alloc_world_map_canvas()
	# Do not clear/rebuild an in-flight JIT queue on every pan kick.
	if _wm_jit_q.is_empty() and not _wm_complete:
		_fill_world_map_queue()


func world_map_step(n: int = 4) -> bool:
	if _wm_complete:
		return true
	if _wm_jit_q.is_empty():
		# Already drained (or never queued) — finalize once, never re-commit every pan kick.
		if _uses_radar_window() and _lofi_image != null:
			_wm_complete = true
			_commit_world_map_tex()
			_try_save_world_map()
		else:
			_wm_complete = true
		return _wm_complete
	n = maxi(n, 1)
	var sheets: Array = pack.sheets if pack else []
	var flags: PackedInt32Array = pack.flags if pack else PackedInt32Array()
	var did := 0
	while did < n and not _wm_jit_q.is_empty():
		var ch: Vector2i = _wm_jit_q.pop_front()
		_stamp_world_chunk(ch.x, ch.y, _world_chunk_buf(ch.x, ch.y), sheets, flags)
		did += 1
	# Commit when batch done or queue drained; avoid uploading full overview every pan.
	if _wm_jit_q.is_empty():
		_wm_complete = true
		_commit_world_map_tex()
		_try_save_world_map()
	elif did > 0 and (_wm_jit_q.size() % 16 == 0):
		_commit_world_map_tex()
	return _wm_complete


func sample_world_chunk(cx: int, cy: int) -> Image:
	var key := _chunk_key(Vector2i(cx, cy))
	if _wm_img_cache.has(key):
		return _wm_img_cache[key]
	var buf: PackedInt32Array = _world_chunk_buf(cx, cy)
	if buf.is_empty() or MapChunkStore.is_empty_buf(buf):
		return null
	var img := Image.create(CHUNK_CELLS, CHUNK_CELLS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var sheets: Array = pack.sheets if pack else []
	var flags: PackedInt32Array = pack.flags if pack else PackedInt32Array()
	for ly in range(CHUNK_CELLS):
		for lx in range(CHUNK_CELLS):
			var col: Color = MapChunkStore.sample_cell_color(buf, lx, ly, CHUNK_CELLS, CHUNK_CELLS, sheets, flags)
			if col.a < 0.2:
				continue
			img.set_pixel(lx, ly, col)
	_wm_img_cache[key] = img
	_evict_wm_cache(_wm_img_cache)
	return img


func _alloc_world_map_canvas() -> void:
	var m: Dictionary = MapChunkStore.overview_metrics(grid_width, grid_height)
	_wm_step = maxi(int(m.get("step", 1)), 1)
	var iw: int = int(m.get("w", 1))
	var ih: int = int(m.get("h", 1))
	if _lofi_image != null and _lofi_image.get_width() == iw and _lofi_image.get_height() == ih:
		if _wm_bytes.is_empty():
			_wm_bytes = _lofi_image.get_data()
		if _wm_complete:
			return
		# Canvas already sized for this map — keep baking into it.
		_ground_image = _lofi_image
		_ensure_lofi_sprite()
		return
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.04, 0.05, 0.05, 1))
	_lofi_image = img
	_ground_image = img
	_wm_bytes = img.get_data()
	_commit_world_map_tex()
	_ensure_lofi_sprite()


func _fill_world_map_queue() -> void:
	_wm_jit_q.clear()
	var seen := {}
	var coords: Array[Vector2i] = []
	var map_dir := _world_chunk_dir()
	if map_dir != "":
		coords.append_array(MapChunkStore.list_chunk_coords(map_dir))
	if edit_doc != null and "_chunk_cache" in edit_doc:
		for k in edit_doc._chunk_cache.keys():
			var parts: PackedStringArray = str(k).split(",")
			if parts.size() >= 2:
				coords.append(Vector2i(int(parts[0]), int(parts[1])))
	if collision != null and collision.has_method("stream_chunk_keys"):
		for k2 in collision.stream_chunk_keys():
			var p2: PackedStringArray = str(k2).split(",")
			if p2.size() >= 2:
				coords.append(Vector2i(int(p2[0]), int(p2[1])))
	var obs: Vector2i = cell_to_chunk(_obs_cell)
	if coords.size() <= 256:
		coords.sort_custom(func(a, b): return absi(a.x - obs.x) + absi(a.y - obs.y) < absi(b.x - obs.x) + absi(b.y - obs.y))
	else:
		_wm_jit_q.append(obs)
		seen[_chunk_key(obs)] = true
	for c in coords:
		var key := _chunk_key(c)
		if seen.has(key):
			continue
		seen[key] = true
		_wm_jit_q.append(c)
	_wm_jit_total = maxi(_wm_jit_q.size(), 1)
	_wm_complete = _wm_jit_q.is_empty()


func _world_chunk_dir() -> String:
	if pack != null and "chunk_map_dir" in pack:
		return str(pack.chunk_map_dir)
	if edit_doc != null and "_store_dir" in edit_doc:
		return str(edit_doc._store_dir)
	return ""


func _evict_wm_cache(cache: Dictionary) -> void:
	if cache.size() <= WM_CACHE_MAX:
		return
	var keys: Array = cache.keys()
	var drop_n: int = cache.size() - WM_CACHE_MAX
	for i in range(mini(drop_n, keys.size())):
		cache.erase(keys[i])


func _world_chunk_buf(cx: int, cy: int) -> PackedInt32Array:
	var ck := _chunk_key(Vector2i(cx, cy))
	if _wm_buf_cache.has(ck):
		return _wm_buf_cache[ck]
	var buf := PackedInt32Array()
	if edit_doc != null and edit_doc.has_method("chunk_buffer"):
		buf = edit_doc.chunk_buffer(cx, cy)
	if buf.is_empty() and pack != null and pack.has_method("load_chunk_data"):
		buf = pack.load_chunk_data(cx, cy)
	if buf.is_empty():
		var dir := _world_chunk_dir()
		if dir != "":
			buf = MapChunkStore.load_chunk(dir, cx, cy)
	if not buf.is_empty():
		_wm_buf_cache[ck] = buf
		_evict_wm_cache(_wm_buf_cache)
		return buf
	if not _uses_radar_window() and collision != null:
		buf = MapChunkStore.empty_buf()
		var origin: Vector2i = MapChunkStore.chunk_origin(cx, cy)
		for ly in range(CHUNK_CELLS):
			for lx in range(CHUNK_CELLS):
				var gx := origin.x + lx
				var gy := origin.y + ly
				if gx < 0 or gy < 0 or gx >= grid_width or gy >= grid_height:
					continue
				for z in range(6):
					buf[MapChunkStore.local_index(lx, ly, z)] = _src_tile(collision, gx, gy, z)
		_wm_buf_cache[ck] = buf
		_evict_wm_cache(_wm_buf_cache)
		return buf
	return PackedInt32Array()


func _stamp_world_chunk(cx: int, cy: int, buf: PackedInt32Array, sheets: Array, flags: PackedInt32Array) -> void:
	if _lofi_image == null or buf.is_empty():
		return
	var iw: int = _lofi_image.get_width()
	var ih: int = _lofi_image.get_height()
	if _wm_bytes.size() != iw * ih * 4:
		_wm_bytes = _lofi_image.get_data()
	MapChunkStore.stamp_overview_bytes(_wm_bytes, iw, ih, _wm_step, cx, cy, buf, sheets, flags, grid_width, grid_height)


func _commit_world_map_tex() -> void:
	if _lofi_image == null:
		return
	var iw: int = _lofi_image.get_width()
	var ih: int = _lofi_image.get_height()
	if _wm_bytes.size() == iw * ih * 4:
		_lofi_image.set_data(iw, ih, false, Image.FORMAT_RGBA8, _wm_bytes)
	if _world_map_tex is ImageTexture:
		var t: ImageTexture = _world_map_tex
		if t.get_width() == iw and t.get_height() == ih:
			t.update(_lofi_image)
			_overview_ground_tex = t
			return
	_world_map_tex = ImageTexture.create_from_image(_lofi_image)
	_overview_ground_tex = _world_map_tex


func _try_save_world_map() -> void:
	if _lofi_image == null:
		return
	var path := ""
	if pack != null and "overview_path" in pack:
		path = str(pack.overview_path)
	if path == "" and edit_doc != null and "_store_dir" in edit_doc:
		path = MapChunkStore.overview_path(str(edit_doc._store_dir))
	if path == "":
		return
	if path.begins_with("res://"):
		return
	_lofi_image.save_png(path)


func _resolved_map_id() -> String:
	if edit_map_id.strip_edges() != "":
		return edit_map_id
	var sess := get_node_or_null("/root/GameSession")
	if sess == null:
		return ""
	var spawn: Variant = sess.get("spawn_data")
	if typeof(spawn) == TYPE_DICTIONARY:
		return str(spawn.get("map_id", "")).strip_edges()
	return ""


func _session_pack_path() -> String:
	## Pack path from GameSession.spawn_data when entering/transferring via Loading.
	var sess := get_node_or_null("/root/GameSession")
	if sess == null:
		return ""
	var spawn: Variant = sess.get("spawn_data")
	if typeof(spawn) != TYPE_DICTIONARY:
		return ""
	return str(spawn.get("pack_path", "")).strip_edges()


func try_apply_session_bake() -> bool:
	## Consume Loading-phase bake so world enter skips tile blit + radar downsample.
	var sess := get_node_or_null("/root/GameSession")
	if sess == null:
		return false
	var bake_v: Variant = sess.get("map_bake")
	if typeof(bake_v) != TYPE_DICTIONARY:
		return false
	var bake: Dictionary = bake_v
	if bake.is_empty():
		return false
	if str(bake.get("pack_path", "")) != pack_path:
		return false
	if not apply_bake(bake):
		return false
	# Drop session copy; textures/images now owned by this MapField.
	sess.map_bake = {}
	return true


func apply_bake(bake: Dictionary) -> bool:
	_ensure_sprites()
	var baked_pack = bake.get("pack", null)
	if baked_pack != null:
		pack = baked_pack
	else:
		pack = TilemapPack.load_pack(_resolve_pack_path(pack_path))
	if pack == null or pack.width <= 0:
		return false
	collision = pack.collision
	tile_size = int(bake.get("tile_size", pack.tile_size))
	grid_width = int(bake.get("grid_width", pack.width))
	grid_height = int(bake.get("grid_height", pack.height))
	_ground_image = bake.get("ground_image", null)
	_upper_image = bake.get("upper_image", null)
	_radar_atlas_image = bake.get("radar_atlas_image", null)
	_radar_atlas_scale = float(bake.get("radar_atlas_scale", RADAR_ATLAS_SCALE))
	var rtex = bake.get("radar_atlas_tex", null)
	if rtex != null:
		_radar_atlas_tex = rtex
	elif _radar_atlas_image != null:
		_radar_atlas_tex = ImageTexture.create_from_image(_radar_atlas_image)
	_hide_legacy_fullmap_sprites()
	_content_pixel_rect_valid = false
	_cached_void_id = _detect_border_void_tile_id(collision)
	var lofi_v: Variant = bake.get("lofi_image", null)
	if lofi_v is Image:
		_lofi_image = lofi_v
	elif _radar_atlas_image != null and _radar_atlas_image.get_width() == grid_width:
		_lofi_image = _radar_atlas_image
	if _lofi_image != null:
		_ground_image = _lofi_image
		_overview_ground_tex = _radar_atlas_tex
	elif _ground_image != null:
		_overview_ground_tex = ImageTexture.create_from_image(_ground_image)
	if _upper_image != null:
		_overview_upper_tex = ImageTexture.create_from_image(_upper_image)
	_ensure_lofi_sprite()
	_stream_ready = true
	_obs_cell = _spawn_cell_from_session()
	_rebuild_chunks_around(_obs_cell, true)
	return true


func export_bake() -> Dictionary:
	return {
		"pack_path": pack_path,
		"pack": pack,
		"tile_size": tile_size,
		"grid_width": grid_width,
		"grid_height": grid_height,
		"ground_image": _ground_image,
		"upper_image": _upper_image,
		"ground_tex": _ground.texture if _ground else null,
		"upper_tex": _upper.texture if _upper else null,
		"radar_atlas_image": _radar_atlas_image,
		"radar_atlas_tex": _radar_atlas_tex,
		"radar_atlas_scale": _radar_atlas_scale,
		"lofi_image": _lofi_image,
	}


## Awaitable rebuild for Loading: yields each few rows + after radar atlas bake.
func rebuild_async(progress: Callable = Callable()) -> void:
	await _rebuild_internal(true, progress)


func _emit_progress(progress: Callable, value: float) -> void:
	if progress.is_valid():
		progress.call(clampf(value, 0.0, 1.0))


func _bake_radar_atlas(ground_img: Image, upper_img: Image, w_px: int, h_px: int) -> void:
	## One-time nearest downsample + upper blend. Radar scrolls a window; never resamples full map.
	var sc: float = RADAR_ATLAS_SCALE
	if sc <= 0.001:
		sc = 0.5
	var aw: int = maxi(1, int(round(float(w_px) * sc)))
	var ah: int = maxi(1, int(round(float(h_px) * sc)))
	if ground_img == null or ground_img.get_width() <= 0:
		_radar_atlas_image = null
		_radar_atlas_tex = null
		_radar_atlas_scale = sc
		return
	var atlas: Image = ground_img.duplicate()
	atlas.resize(aw, ah, Image.INTERPOLATE_NEAREST)
	if upper_img != null and upper_img.get_width() > 0:
		var u: Image = upper_img.duplicate()
		u.resize(aw, ah, Image.INTERPOLATE_NEAREST)
		atlas.blend_rect(u, Rect2i(0, 0, aw, ah), Vector2i.ZERO)
	_radar_atlas_image = atlas
	_radar_atlas_scale = sc
	_radar_atlas_tex = ImageTexture.create_from_image(atlas)


func _hide_legacy_fullmap_sprites() -> void:
	if _ground:
		_ground.visible = false
		_ground.texture = null
	if _upper:
		_upper.visible = false
		_upper.texture = null
	if _objects:
		_objects.visible = false
		_objects.texture = null
	if _shadow:
		_shadow.visible = false
		_shadow.texture = null


func _spawn_cell_from_session() -> Vector2i:
	var sess := get_node_or_null("/root/GameSession")
	if sess == null:
		return Vector2i.ZERO
	var spawn: Variant = sess.get("spawn_data")
	if typeof(spawn) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	var cell_v: Variant = spawn.get("cell", null)
	if typeof(cell_v) == TYPE_DICTIONARY:
		return Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	if typeof(cell_v) == TYPE_VECTOR2I:
		return cell_v
	return Vector2i.ZERO


func _process(delta: float) -> void:
	if not _stream_ready or pack == null:
		return
	_update_observer_from_camera()
	if _obs_cell != _last_obs_cell or _obs_facing != _last_obs_facing or not _chunk_queue.is_empty():
		_last_obs_cell = _obs_cell
		_last_obs_facing = _obs_facing
		_refresh_chunk_set()
	if not _chunk_queue.is_empty():
		var n := 0
		var cap := 12 if edit_mode else 1
		while not _chunk_queue.is_empty() and n < cap:
			_bake_next_chunk(false)
			n += 1
	_pump_anim_prebake()
	if not _wm_jit_q.is_empty():
		world_map_step(12 if edit_mode else 8)
	_ensure_edit_overlay()
	_apply_far_parallax()
	_tick_tile_anim(delta)


func _src_tile(col, x: int, y: int, z: int) -> int:
	if edit_doc != null and edit_doc.has_method("tile") and z <= 5:
		return int(edit_doc.tile(x, y, z))
	if col != null and col.has_method("tile_id"):
		return int(col.tile_id(x, y, z))
	return 0


func rebuild_dirty_cells(cells: Array) -> void:
	if not _stream_ready:
		return
	_patch_lofi_cells(cells)
	var seen := {}
	for c in cells:
		var cell: Vector2i = c
		var ch := cell_to_chunk(cell)
		var key := _chunk_key(ch)
		if seen.has(key):
			continue
		seen[key] = true
		var queued := false
		for q in _chunk_queue:
			if _chunk_key(q) == key:
				queued = true
				break
		if not queued:
			_chunk_queue.append(ch)


func set_edit_camera_cell(cell: Vector2i) -> void:
	var prev: Vector2i = cell_to_chunk(_obs_cell)
	_obs_cell = cell
	_refresh_chunk_set()
	var now: Vector2i = cell_to_chunk(_obs_cell)
	if now != prev or not _chunks.has(_chunk_key(now)):
		bake_observer_chunk()


func _edit_observer_cell() -> Vector2i:
	if edit_start_cell.x >= 0 and edit_start_cell.y >= 0:
		return Vector2i(clampi(edit_start_cell.x, 0, maxi(grid_width - 1, 0)), clampi(edit_start_cell.y, 0, maxi(grid_height - 1, 0)))
	return Vector2i(clampi(2, 0, maxi(grid_width - 1, 0)), clampi(2, 0, maxi(grid_height - 1, 0)))


func current_chunk() -> Vector2i:
	return cell_to_chunk(_obs_cell)


func current_chunk_rect(cell: Vector2i = Vector2i(-9999, -9999)) -> Rect2i:
	if cell.x < -9000:
		cell = _obs_cell
	var ch: Vector2i = cell_to_chunk(cell)
	var o := Vector2i(ch.x * CHUNK_CELLS, ch.y * CHUNK_CELLS)
	var cw := mini(CHUNK_CELLS, maxi(grid_width - o.x, 1))
	var chh := mini(CHUNK_CELLS, maxi(grid_height - o.y, 1))
	if o.x < 0:
		o.x = 0
	if o.y < 0:
		o.y = 0
	return Rect2i(o.x, o.y, cw, chh)


func bake_observer_chunk() -> void:
	if not _stream_ready or pack == null:
		return
	var pri: Vector2i = cell_to_chunk(_obs_cell)
	_prioritize_chunk(pri)
	_bake_next_chunk()


func _prioritize_chunk(ch: Vector2i) -> void:
	var key := _chunk_key(ch)
	if _chunks.has(key):
		return
	for i in range(_chunk_queue.size()):
		if _chunk_queue[i] == ch:
			if i > 0:
				_chunk_queue.remove_at(i)
				_chunk_queue.insert(0, ch)
			return
	_chunk_queue.insert(0, ch)


func is_layer_drawn_z(z: int) -> bool:
	if not edit_mode:
		return true
	if z < 0 or z >= edit_hidden_z.size():
		return true
	return int(edit_hidden_z[z]) == 0


func is_layer_drawn_ext(id: String) -> bool:
	if not edit_mode:
		return true
	return not bool(edit_hidden_ext.get(id, false))


func set_layer_hidden_z(z: int, hidden: bool) -> void:
	if z < 0 or z > 5:
		return
	if edit_hidden_z.size() < 6:
		edit_hidden_z.resize(6)
	edit_hidden_z[z] = 1 if hidden else 0
	rebake_loaded_chunks()


func set_layer_hidden_ext(id: String, hidden: bool) -> void:
	if hidden:
		edit_hidden_ext[id] = true
	else:
		edit_hidden_ext.erase(id)
	rebake_loaded_chunks()


func rebake_loaded_chunks() -> void:
	if not _stream_ready:
		return
	for key in _chunks.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 2:
			continue
		var ch := Vector2i(int(parts[0]), int(parts[1]))
		var queued := false
		for q in _chunk_queue:
			if q == ch:
				queued = true
				break
		if not queued:
			_chunk_queue.append(ch)


func _apply_edit_doc_size() -> void:
	if edit_doc == null:
		return
	grid_width = int(edit_doc.width)
	grid_height = int(edit_doc.height)
	tile_size = maxi(int(edit_doc.tile_size), 1)


func set_edit_flags(flags: PackedInt32Array) -> void:
	if pack != null:
		pack.flags = flags
		if pack.collision != null:
			pack.collision.flags = flags


func edit_cell_passable(x: int, y: int) -> int:
	## 0 walk, 1 block, 2 force-pass, 3 force-block.
	if x < 0 or y < 0 or x >= grid_width or y >= grid_height or edit_doc == null:
		return 1
	var meta := 0
	if edit_doc.has_method("ext_tile"):
		meta = int(edit_doc.ext_tile("meta", x, y))
	if (meta & MapExt.META_FORCE_BLOCK) != 0:
		return 3
	if (meta & MapExt.META_FORCE_PASS) != 0:
		return 2
	var t0: int = int(edit_doc.tile(x, y, 0))
	var t1: int = int(edit_doc.tile(x, y, 1))
	var t2: int = int(edit_doc.tile(x, y, 2))
	var t3: int = int(edit_doc.tile(x, y, 3))
	if t0 == 0 and t1 == 0 and t2 == 0 and t3 == 0:
		return 1
	var flags: PackedInt32Array = pack.flags if pack != null else PackedInt32Array()
	for z in [3, 2, 1, 0]:
		var t: int = int(edit_doc.tile(x, y, z))
		if t <= 0:
			continue
		var f: int = int(flags[t]) if t < flags.size() else 0
		if (f & 0x10) != 0:
			continue
		if (f & 0x0F) == 0x0F:
			return 1
		return 0
	return 1


func _ensure_edit_overlay() -> void:
	if not edit_mode:
		if _edit_overlay != null and is_instance_valid(_edit_overlay):
			_edit_overlay.visible = false
		return
	if _edit_overlay == null or not is_instance_valid(_edit_overlay):
		_edit_overlay = preload("res://scripts/map/map_edit_overlay.gd").new()
		_edit_overlay.name = "EditOverlay"
		_edit_overlay.z_as_relative = false
		_edit_overlay.z_index = 4096
		add_child(_edit_overlay)
	_edit_overlay.visible = true
	move_child(_edit_overlay, get_child_count() - 1)


func set_observer(cell: Vector2i, facing: int = 2) -> void:
	_obs_cell = cell
	_obs_facing = facing
	_apply_indoor_from_cell(cell)
	_apply_far_parallax()


func light_fx_color() -> Color:
	if edit_doc != null and "light_fx_color" in edit_doc:
		return edit_doc.light_fx_color
	if pack != null and "light_fx_color" in pack:
		return pack.light_fx_color
	if pack != null and pack.get("ext") != null and "light_color" in pack.ext:
		return pack.ext.light_color
	if collision != null and collision.ext != null and "light_color" in collision.ext:
		return collision.ext.light_color
	return Color(1, 1, 1, 1)


func apply_light_fx_color() -> void:
	var c := light_fx_color()
	for key in _chunks.keys():
		var ch: Node2D = _chunks[key]
		if ch != null and ch.has_method("set_fx_modulate"):
			ch.set_fx_modulate(c)


func set_bucket_alpha(bucket: String, a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	edit_bucket_alpha[bucket] = a
	for key in _chunks.keys():
		var ch: Node = _chunks[key]
		if ch == null:
			continue
		var spr: Sprite2D = ch.get_node_or_null(bucket) as Sprite2D
		if spr:
			var m: Color = spr.modulate
			m.a = a
			spr.modulate = m
		var anim: Sprite2D = ch.get_node_or_null(bucket + "Anim") as Sprite2D
		if anim:
			var m2: Color = anim.modulate
			m2.a = a
			anim.modulate = m2


func map_is_indoor() -> bool:
	if edit_doc != null and "environment" in edit_doc:
		return MapExt.normalize_environment(edit_doc.environment) == MapExt.ENV_INDOOR
	if pack != null and "environment" in pack:
		return MapExt.normalize_environment(pack.environment) == MapExt.ENV_INDOOR
	return false


func set_atmosphere(light_id: int, kind: String, intensity: float) -> Dictionary:
	_atm_light = light_id
	_atm_kind = str(kind)
	_atm_intensity = intensity
	var atm: Dictionary = Weather.compose(light_id, kind, intensity, map_is_indoor())
	last_atmosphere = atm
	_ensure_weather_fx()
	if _weather_fx and _weather_fx.has_method("apply"):
		_weather_fx.apply(atm)
	_sync_weather_eaves()
	return atm


func weather_display_modulate() -> Color:
	if _weather_fx != null and is_instance_valid(_weather_fx) and _weather_fx.has_method("display_modulate"):
		return _weather_fx.display_modulate()
	var c: Variant = last_atmosphere.get("modulate", Color.WHITE)
	if typeof(c) == TYPE_COLOR:
		return c
	return Color.WHITE


func _ensure_weather_fx() -> void:
	if _weather_fx != null and is_instance_valid(_weather_fx):
		return
	_weather_fx = WeatherFxScript.new()
	_weather_fx.name = "WeatherFx"
	_weather_fx.layer = Weather.CANVAS_ATMOSPHERE
	add_child(_weather_fx)


func _sync_weather_eaves() -> void:
	if _weather_fx == null or not _weather_fx.has_method("set_eaves"):
		return
	var eaves := false
	if collision != null and collision.has_method("meta_at"):
		eaves = (int(collision.meta_at(_obs_cell.x, _obs_cell.y)) & MapExt.META_INDOOR) != 0
	elif edit_doc != null and edit_doc.has_method("ext_tile"):
		eaves = (int(edit_doc.ext_tile("meta", _obs_cell.x, _obs_cell.y)) & MapExt.META_INDOOR) != 0
	_weather_fx.set_eaves(eaves)


func set_reference_image(path: String, alpha: float = 0.35) -> void:
	_ref_alpha = clampf(alpha, 0.0, 1.0)
	if _ref_sprite == null or not is_instance_valid(_ref_sprite):
		_ref_sprite = Sprite2D.new()
		_ref_sprite.name = "RefOverlay"
		_ref_sprite.centered = false
		_ref_sprite.z_as_relative = false
		_ref_sprite.z_index = 3500
		add_child(_ref_sprite)
	if path.strip_edges() == "":
		_ref_sprite.texture = null
		_ref_sprite.visible = false
		return
	var img := Image.new()
	if img.load(path) != OK:
		var glob := ProjectSettings.globalize_path(path)
		if img.load(glob) != OK:
			_ref_sprite.visible = false
			return
	var mw := float(maxi(grid_width, 1) * maxi(tile_size, 1))
	var mh := float(maxi(grid_height, 1) * maxi(tile_size, 1))
	_ref_sprite.texture = ImageTexture.create_from_image(img)
	_ref_sprite.visible = true
	_ref_sprite.modulate = Color(1, 1, 1, _ref_alpha)
	if _ref_sprite.texture:
		_ref_sprite.scale = Vector2(mw / float(maxi(_ref_sprite.texture.get_width(), 1)), mh / float(maxi(_ref_sprite.texture.get_height(), 1)))


func far_scroll_vec() -> Vector2:
	if edit_doc != null and "far_scroll" in edit_doc:
		return edit_doc.far_scroll
	if pack != null and "ext" in pack and pack.ext != null and "far_scroll" in pack.ext:
		return pack.ext.far_scroll
	if collision != null and collision.ext != null and "far_scroll" in collision.ext:
		return collision.ext.far_scroll
	return Vector2.ZERO


func _apply_far_parallax() -> void:
	var sc := far_scroll_vec()
	var off := Vector2.ZERO
	if sc != Vector2.ZERO:
		var cam := get_viewport().get_camera_2d() if get_viewport() else null
		var origin := Vector2.ZERO
		if cam != null:
			origin = cam.get_screen_center_position()
		off = Vector2(origin.x * sc.x, origin.y * sc.y)
	for key in _chunks.keys():
		var ch: Node2D = _chunks[key]
		if ch != null and ch.has_method("set_below_offset"):
			ch.set_below_offset(off)


func _apply_indoor_from_cell(cell: Vector2i) -> void:
	var indoor := false
	if collision != null and collision.has_method("meta_at"):
		indoor = (int(collision.meta_at(cell.x, cell.y)) & MapExt.META_INDOOR) != 0
	if indoor == _roof_hidden:
		return
	_roof_hidden = indoor
	for key in _chunks.keys():
		var ch: Node2D = _chunks[key]
		if ch != null and ch.has_method("set_roof_visible"):
			ch.set_roof_visible(not _roof_hidden)
	_sync_weather_eaves()


func _update_observer_from_camera() -> void:
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam == null:
		return
	var center: Vector2 = cam.get_screen_center_position()
	_obs_cell = world_to_cell(center)


func _chunk_key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


func cell_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(cell.x) / float(CHUNK_CELLS))),
		int(floor(float(cell.y) / float(CHUNK_CELLS)))
	)


func _wanted_chunks(center_cell: Vector2i, facing: int) -> Dictionary:
	var out := {}
	if grid_width <= 0 or tile_size <= 0:
		return out
	var max_cx := int(ceil(float(grid_width) / float(CHUNK_CELLS))) - 1
	var max_cy := int(ceil(float(grid_height) / float(CHUNK_CELLS))) - 1
	## Continent editor: only the chunk under the camera (rest is overview).
	if edit_mode and _uses_radar_window():
		var oc0 := cell_to_chunk(center_cell)
		oc0.x = clampi(oc0.x, 0, maxi(max_cx, 0))
		oc0.y = clampi(oc0.y, 0, maxi(max_cy, 0))
		out[_chunk_key(oc0)] = oc0
		return out
	## 96×96 town (36 chunks): keep every HD chunk so a north walk never bakes mid-stride.
	if not edit_mode and (max_cx + 1) * (max_cy + 1) <= ALL_HD_CHUNK_LIMIT:
		for cy in range(max_cy, -1, -1):
			for cx in range(max_cx, -1, -1):
				out[_chunk_key(Vector2i(cx, cy))] = Vector2i(cx, cy)
		return out
	var vis := get_viewport().get_visible_rect().size if get_viewport() else Vector2(2560, 1440)
	var z := 1.0
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam != null:
		z = maxf(cam.zoom.x, 0.05)
	var half_cells := Vector2i(
		int(ceil(vis.x / (float(tile_size) * z) * 0.5)) + CHUNK_CELLS,
		int(ceil(vis.y / (float(tile_size) * z) * 0.5)) + CHUNK_CELLS
	)
	var min_c := cell_to_chunk(center_cell - half_cells)
	var max_c := cell_to_chunk(center_cell + half_cells)
	min_c -= Vector2i(PREFETCH_CHUNKS, PREFETCH_CHUNKS)
	max_c += Vector2i(PREFETCH_CHUNKS, PREFETCH_CHUNKS)
	var obs_c := cell_to_chunk(center_cell)
	var half_span := int(MAX_CHUNK_SPAN / 2)
	## Cap zoom-out to ±2 around the camera, then expand in the walk direction.
	min_c.x = clampi(min_c.x, obs_c.x - half_span, obs_c.x + half_span)
	max_c.x = clampi(max_c.x, obs_c.x - half_span, obs_c.x + half_span)
	min_c.y = clampi(min_c.y, obs_c.y - half_span, obs_c.y + half_span)
	max_c.y = clampi(max_c.y, obs_c.y - half_span, obs_c.y + half_span)
	if not edit_mode:
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
		while not _chunk_queue.is_empty():
			_bake_next_chunk()
		_publish_lofi_atlas()


func _clear_chunks() -> void:
	for key in _chunks.keys():
		var n: Node = _chunks[key]
		if n != null and is_instance_valid(n):
			n.queue_free()
	_chunks.clear()
	_chunk_queue.clear()
	_last_obs_cell = Vector2i(2147483647, 2147483647)
	_last_obs_facing = -1
	if _chunk_root != null and is_instance_valid(_chunk_root):
		_chunk_root.queue_free()
	_chunk_root = Node2D.new()
	_chunk_root.name = "Chunks"
	add_child(_chunk_root)


func _refresh_chunk_set() -> void:
	var wanted := _wanted_chunks(_obs_cell, _obs_facing)
	_sync_stream_data(wanted)
	var obs_ch := cell_to_chunk(_obs_cell)
	if _uses_radar_window() and obs_ch != _radar_obs_chunk:
		_rebuild_radar_window()
	for key in wanted.keys():
		if _chunks.has(key):
			continue
		var already := false
		for q in _chunk_queue:
			if _chunk_key(q) == key:
				already = true
				break
		if not already:
			_enqueue_chunk(wanted[key])
	# Hysteresis unload: keep UNLOAD_EXTRA beyond wanted. Collect first — do not erase while iterating.
	var to_drop: Array[String] = []
	for key2 in _chunks.keys():
		if wanted.has(key2):
			continue
		var node_keep = _chunks[key2]
		var c: Vector2i = node_keep.chunk if node_keep else Vector2i.ZERO
		var drop := true
		for k3 in wanted.keys():
			var w: Vector2i = wanted[k3]
			if absi(c.x - w.x) <= UNLOAD_EXTRA_CHUNKS and absi(c.y - w.y) <= UNLOAD_EXTRA_CHUNKS:
				drop = false
				break
		if drop:
			to_drop.append(str(key2))
	for dk in to_drop:
		var node: Node = _chunks.get(dk)
		_chunks.erase(dk)
		if node != null and is_instance_valid(node):
			node.queue_free()


func _sync_stream_data(wanted: Dictionary) -> void:
	if collision == null or not ("streaming" in collision and bool(collision.streaming)):
		return
	var map_dir := ""
	if pack != null and "chunk_map_dir" in pack and str(pack.chunk_map_dir) != "":
		map_dir = str(pack.chunk_map_dir)
	for key in wanted.keys():
		var c: Vector2i = wanted[key]
		if collision.has_method("has_stream_chunk") and collision.has_stream_chunk(c.x, c.y):
			continue
		var buf := PackedInt32Array()
		if edit_doc != null and edit_doc.has_method("chunk_buffer"):
			buf = edit_doc.chunk_buffer(c.x, c.y)
		elif pack != null and pack.has_method("load_chunk_data"):
			buf = pack.load_chunk_data(c.x, c.y)
		elif map_dir != "":
			buf = MapChunkStore.load_chunk(map_dir, c.x, c.y)
		if collision.has_method("ingest_stream_chunk"):
			collision.ingest_stream_chunk(c.x, c.y, buf)
	if not collision.has_method("stream_chunk_keys"):
		return
	var keys: Array = collision.stream_chunk_keys()
	for key2 in keys:
		if wanted.has(key2):
			continue
		var parts: PackedStringArray = str(key2).split(",")
		if parts.size() < 2:
			continue
		var c2 := Vector2i(int(parts[0]), int(parts[1]))
		var keep := false
		for k3 in wanted.keys():
			var w: Vector2i = wanted[k3]
			if absi(c2.x - w.x) <= UNLOAD_EXTRA_CHUNKS and absi(c2.y - w.y) <= UNLOAD_EXTRA_CHUNKS:
				keep = true
				break
		if not keep and collision.has_method("drop_stream_chunk"):
			collision.drop_stream_chunk(c2.x, c2.y)


func _enqueue_chunk(c: Vector2i) -> void:
	var key := _chunk_key(c)
	if _chunks.has(key):
		return
	for q in _chunk_queue:
		if _chunk_key(q) == key:
			return
	if _chunk_is_ahead(c):
		_chunk_queue.insert(0, c)
	else:
		_chunk_queue.append(c)


func _chunk_is_ahead(c: Vector2i) -> bool:
	var fd: Vector2i = TileId.dir_delta(_obs_facing)
	if fd == Vector2i.ZERO:
		return false
	var obs: Vector2i = cell_to_chunk(_obs_cell)
	var rel: Vector2i = c - obs
	return rel.x * fd.x + rel.y * fd.y > 0


func _bake_next_chunk(full_anim: bool = true) -> void:
	if _chunk_queue.is_empty() or pack == null:
		return
	if _chunk_root == null or not is_instance_valid(_chunk_root):
		_chunk_root = Node2D.new()
		_chunk_root.name = "Chunks"
		add_child(_chunk_root)
	var c: Vector2i = _chunk_queue.pop_front()
	var key := _chunk_key(c)
	var x0 := c.x * CHUNK_CELLS
	var y0 := c.y * CHUNK_CELLS
	if x0 >= grid_width or y0 >= grid_height:
		return
	var cw := mini(CHUNK_CELLS, grid_width - x0)
	var ch := mini(CHUNK_CELLS, grid_height - y0)
	var ts := tile_size
	var img_w := cw * ts
	var img_h := ch * ts
	var below := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	var ground := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	var upper := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	var roof := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	var fx := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	below.fill(Color(0, 0, 0, 0))
	ground.fill(Color(0, 0, 0, 0))
	upper.fill(Color(0, 0, 0, 0))
	roof.fill(Color(0, 0, 0, 0))
	fx.fill(Color(0, 0, 0, 0))
	var sheets: Array = pack.sheets
	var flags: PackedInt32Array = pack.flags
	var col = collision
	var void_id: int = _cached_void_id
	_begin_anim_bake()
	for y in range(ch):
		for x in range(cw):
			var gx := x0 + x
			var gy := y0 + y
			var dx := x * ts
			var dy := y * ts
			_paint_cell(ground, upper, col, sheets, flags, void_id, gx, gy, dx, dy)
			_paint_ext_cell(below, ground, upper, roof, fx, col, sheets, flags, gx, gy, dx, dy)
	var node: Node2D = _chunks.get(key) as Node2D
	if node == null or not is_instance_valid(node):
		node = MapChunk.new()
		node.setup(c, Vector2(x0 * ts, y0 * ts))
		_chunk_root.add_child(node)
		_chunks[key] = node
	if node.has_method("clear_visuals"):
		node.clear_visuals()
	node.apply_bucket("Below", below, -20)
	node.apply_bucket("Ground", ground, 0)
	node.apply_bucket("Upper", upper, 10)
	node.apply_bucket("Roof", roof, 12)
	node.apply_bucket("Fx", fx, 16, true)
	_finish_anim_bake(node, full_anim)
	if node.has_method("set_fx_modulate"):
		node.set_fx_modulate(light_fx_color())
	if node.has_method("set_roof_visible"):
		node.set_roof_visible(not _roof_hidden)
	_stamp_lofi_from_chunk(node, c)
	if not full_anim:
		_publish_lofi_atlas()
	_ensure_edit_overlay()


func _paint_ext_cell(
	below: Image,
	ground: Image,
	upper: Image,
	roof: Image,
	fx: Image,
	col,
	sheets: Array,
	flags: PackedInt32Array,
	gx: int,
	gy: int,
	dx: int,
	dy: int
) -> void:
	if edit_doc != null and edit_doc.has_method("ext_tile"):
		if is_layer_drawn_ext("far"):
			_blit_to(below, int(edit_doc.ext_tile("far", gx, gy)), dx, dy, sheets, flags, false, "Below")
		if is_layer_drawn_ext("water"):
			_blit_to(ground, int(edit_doc.ext_tile("water", gx, gy)), dx, dy, sheets, flags, false, "Ground")
		if is_layer_drawn_ext("ground_fx"):
			_blit_to(ground, int(edit_doc.ext_tile("ground_fx", gx, gy)), dx, dy, sheets, flags, false, "Ground")
		if is_layer_drawn_ext("props_low"):
			_blit_by_flag(ground, upper, int(edit_doc.ext_tile("props_low", gx, gy)), dx, dy, sheets, flags)
		if is_layer_drawn_ext("props_high"):
			_blit_by_flag(ground, upper, int(edit_doc.ext_tile("props_high", gx, gy)), dx, dy, sheets, flags)
		if is_layer_drawn_ext("roof"):
			_blit_to(roof, int(edit_doc.ext_tile("roof", gx, gy)), dx, dy, sheets, flags, false, "Roof")
		if is_layer_drawn_ext("sky"):
			_blit_to(upper, int(edit_doc.ext_tile("sky", gx, gy)), dx, dy, sheets, flags, false, "Upper")
		if is_layer_drawn_ext("light"):
			_blit_to(fx, int(edit_doc.ext_tile("light", gx, gy)), dx, dy, sheets, flags, false, "Fx")
		return
	if pack == null or pack.get("ext") == null:
		return
	var ext = pack.ext
	if ext == null or not bool(ext.get("valid")):
		return
	if not ext.has_method("has_tiles"):
		return
	if ext.has_tiles("far"):
		_blit_to(below, ext.tile("far", gx, gy), dx, dy, sheets, flags, false, "Below")
	if ext.has_tiles("water"):
		_blit_to(ground, ext.tile("water", gx, gy), dx, dy, sheets, flags, false, "Ground")
	if ext.has_tiles("ground_fx"):
		_blit_to(ground, ext.tile("ground_fx", gx, gy), dx, dy, sheets, flags, false, "Ground")
	if ext.has_tiles("props_low"):
		_blit_by_flag(ground, upper, ext.tile("props_low", gx, gy), dx, dy, sheets, flags)
	if ext.has_tiles("props_high"):
		_blit_by_flag(ground, upper, ext.tile("props_high", gx, gy), dx, dy, sheets, flags)
	if ext.has_tiles("roof"):
		_blit_to(roof, ext.tile("roof", gx, gy), dx, dy, sheets, flags, false, "Roof")
	if ext.has_tiles("sky"):
		_blit_to(upper, ext.tile("sky", gx, gy), dx, dy, sheets, flags, false, "Upper")
	if ext.has_tiles("light"):
		_blit_to(fx, ext.tile("light", gx, gy), dx, dy, sheets, flags, false, "Fx")


func _blit_to(
	dest: Image,
	tile_id: int,
	dx: int,
	dy: int,
	sheets: Array,
	flags: PackedInt32Array,
	_force_upper: bool,
	bucket: String = "Ground"
) -> void:
	if tile_id <= 0 or dest == null:
		return
	_route_blit(dest, bucket, tile_id, dx, dy, sheets, flags)


func _route_blit(
	dest: Image,
	bucket: String,
	tile_id: int,
	dx: int,
	dy: int,
	sheets: Array,
	flags: PackedInt32Array
) -> void:
	if dest == null or tile_id <= 0:
		return
	if _bake_anim and TileId.is_animated_a1(tile_id):
		var aimg: Image = _anim_image(bucket, dest)
		_bake_anim_jobs.append({
			"bucket": bucket,
			"dx": dx,
			"dy": dy,
			"tile_id": tile_id,
		})
		TileBlit.blit_tile(aimg, tile_id, dx, dy, sheets, tile_size, tile_size, flags, _anim_frame)
		return
	TileBlit.blit_tile(dest, tile_id, dx, dy, sheets, tile_size, tile_size, flags, 0)


func _cell_has_ground_anim(t0: int, t1: int, t2: int, t3: int, flags: PackedInt32Array) -> bool:
	var tiles := PackedInt32Array([t0, t1, t2, t3])
	for t in tiles:
		if not TileId.is_animated_a1(t):
			continue
		if t < flags.size() and (flags[t] & 0x10) != 0:
			continue
		return true
	return false


func _anim_image(bucket: String, like: Image) -> Image:
	if _bake_anim_imgs.has(bucket):
		return _bake_anim_imgs[bucket]
	var w: int = like.get_width() if like != null else 1
	var h: int = like.get_height() if like != null else 1
	var img := Image.create(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_bake_anim_imgs[bucket] = img
	return img


func _begin_anim_bake() -> void:
	_bake_anim = true
	_bake_anim_jobs = []
	_bake_anim_shadows = []
	_bake_anim_imgs = {}


func _finish_anim_bake(node: Node2D, full_anim: bool = true) -> void:
	_bake_anim = false
	if node == null:
		return
	if node.has_method("set_anim_data"):
		node.set_anim_data(_bake_anim_jobs, _bake_anim_shadows, _bake_anim_imgs)
	for b in _bake_anim_imgs.keys():
		var bucket: String = str(b)
		var img: Image = _bake_anim_imgs[b]
		var additive: bool = bucket == "Fx"
		if node.has_method("apply_bucket"):
			node.apply_bucket(bucket + "Anim", img, _anim_layer_z(bucket), additive)
	if full_anim and node.has_method("refresh_anim"):
		var sheets: Array = pack.sheets if pack else []
		var flags: PackedInt32Array = pack.flags if pack else PackedInt32Array()
		node.refresh_anim(_anim_frame, sheets, flags, tile_size, 0.0)
	_bake_anim_jobs = []
	_bake_anim_shadows = []
	_bake_anim_imgs = {}


func _anim_layer_z(bucket: String) -> int:
	match bucket:
		"Below":
			return -21
		"Ground":
			return -1
		"Upper":
			return 9
		"Roof":
			return 11
		"Fx":
			return 15
		_:
			return -1


func _tick_tile_anim(delta: float) -> void:
	_anim_accum += delta
	var advanced := false
	while _anim_accum >= ANIM_STEP_SEC:
		_anim_accum -= ANIM_STEP_SEC
		_anim_frame = (_anim_frame + 1) % 4
		advanced = true
	var mix_t: float = clampf(_anim_accum / ANIM_STEP_SEC, 0.0, 1.0)
	if advanced:
		_refresh_chunk_anims(mix_t)
	else:
		_set_chunk_anim_mix(mix_t)


func tick_tile_anim() -> int:
	_anim_frame = (_anim_frame + 1) % 4
	_anim_accum = 0.0
	_refresh_chunk_anims(0.0)
	return _anim_frame


func tile_anim_mix() -> float:
	return clampf(_anim_accum / ANIM_STEP_SEC, 0.0, 1.0)


func tile_anim_frame() -> int:
	return _anim_frame


func _refresh_chunk_anims(mix_t: float = 0.0) -> void:
	if pack == null:
		return
	var sheets: Array = pack.sheets
	var flags: PackedInt32Array = pack.flags
	for key in _chunks.keys():
		var ch: Node = _chunks[key]
		if ch != null and ch.has_method("refresh_anim"):
			ch.refresh_anim(_anim_frame, sheets, flags, tile_size, mix_t, false)


func _set_chunk_anim_mix(mix_t: float) -> void:
	for key in _chunks.keys():
		var ch: Node = _chunks[key]
		if ch != null and ch.has_method("set_anim_mix_only"):
			ch.set_anim_mix_only(mix_t)


func _pump_anim_prebake() -> void:
	if pack == null:
		return
	var sheets: Array = pack.sheets
	var flags: PackedInt32Array = pack.flags
	var n := 0
	for key in _chunks.keys():
		var ch: Node = _chunks[key]
		if ch == null or not ch.has_method("prebake_next_anim_frame"):
			continue
		if bool(ch.prebake_next_anim_frame(sheets, flags, tile_size)):
			n += 1
			if n >= 1:
				return


func _bake_radar_mv_only(do_yield: bool, progress: Callable) -> void:
	_bake_lofi_overview()
	if do_yield:
		_emit_progress(progress, 0.82)


func _bake_lofi_overview() -> void:
	_wm_buf_cache.clear()
	_wm_img_cache.clear()
	var gw: int = maxi(grid_width, 1)
	var gh: int = maxi(grid_height, 1)
	if _uses_radar_window():
		_load_offline_overview()
		_rebuild_radar_window()
		_ensure_lofi_sprite()
		return
	var img := Image.create(gw, gh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var sheets: Array = pack.sheets if pack else []
	var flags: PackedInt32Array = pack.flags if pack else PackedInt32Array()
	var col = collision
	var void_id: int = _cached_void_id
	if void_id == 0:
		void_id = _detect_border_void_tile_id(col)
	for y in range(gh):
		for x in range(gw):
			if edit_doc == null and _is_void_filler_cell(col, x, y, void_id):
				continue
			img.set_pixel(x, y, cell_visual_color(x, y))
	_lofi_image = img
	_ground_image = img
	_upper_image = null
	_radar_atlas_image = img
	_radar_origin_cell = Vector2i.ZERO
	_radar_atlas_scale = 1.0 / float(maxi(tile_size, 1))
	_radar_atlas_tex = ImageTexture.create_from_image(img)
	_overview_ground_tex = _radar_atlas_tex
	_overview_upper_tex = null
	_world_map_tex = _radar_atlas_tex
	_wm_complete = true
	_wm_jit_q.clear()
	_wm_step = 1
	_ensure_lofi_sprite()


func _load_offline_overview() -> void:
	_world_map_tex = null
	var paths: Array[String] = []
	if pack != null and "overview_path" in pack and str(pack.overview_path) != "":
		paths.append(str(pack.overview_path))
	if edit_doc != null and "_store_dir" in edit_doc and str(edit_doc._store_dir) != "":
		paths.append(MapChunkStore.overview_path(str(edit_doc._store_dir)))
	if pack_path != "":
		var mid := _resolved_map_id()
		if mid != "":
			paths.append("%s/maps/%s/overview.png" % [pack_path.rstrip("/"), mid])
		paths.append("%s/overview.png" % pack_path.rstrip("/"))
	var img: Image = null
	for p in paths:
		if p == "" or not (FileAccess.file_exists(p) or FileAccess.file_exists(ProjectSettings.globalize_path(p))):
			continue
		img = Image.new()
		if img.load(p) == OK:
			break
		img = null
	if img == null:
		_wm_complete = false
		_alloc_world_map_canvas()
		return
	_wm_complete = true
	_wm_jit_q.clear()
	var m: Dictionary = MapChunkStore.overview_metrics(grid_width, grid_height)
	_wm_step = maxi(int(m.get("step", 1)), 1)
	_lofi_image = img
	_ground_image = img
	_world_map_tex = ImageTexture.create_from_image(img)
	_overview_ground_tex = _world_map_tex
	_ensure_lofi_sprite()


func _rebuild_radar_window() -> void:
	var oc := cell_to_chunk(_obs_cell)
	_radar_obs_chunk = oc
	var min_c := Vector2i(maxi(oc.x - 1, 0), maxi(oc.y - 1, 0))
	var counts: Vector2i = MapChunkStore.chunk_counts(grid_width, grid_height)
	var max_c := Vector2i(mini(oc.x + 1, counts.x - 1), mini(oc.y + 1, counts.y - 1))
	var x0: int = min_c.x * CHUNK_CELLS
	var y0: int = min_c.y * CHUNK_CELLS
	var x1: int = mini((max_c.x + 1) * CHUNK_CELLS, grid_width)
	var y1: int = mini((max_c.y + 1) * CHUNK_CELLS, grid_height)
	var ww: int = maxi(x1 - x0, 1)
	var hh: int = maxi(y1 - y0, 1)
	var img := Image.create(ww, hh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var sheets: Array = pack.sheets if pack else []
	var flags: PackedInt32Array = pack.flags if pack else PackedInt32Array()
	var col = collision
	for y in range(hh):
		for x in range(ww):
			img.set_pixel(x, y, cell_visual_color(x0 + x, y0 + y))
	_radar_origin_cell = Vector2i(x0, y0)
	_radar_atlas_image = img
	_radar_atlas_scale = 1.0 / float(maxi(tile_size, 1))
	_radar_atlas_tex = ImageTexture.create_from_image(img)


func _patch_lofi_cells(cells: Array) -> void:
	if _lofi_image == null or cells.is_empty():
		return
	var sheets: Array = pack.sheets if pack else []
	var flags: PackedInt32Array = pack.flags if pack else PackedInt32Array()
	var col = collision
	var gw: int = _lofi_image.get_width()
	var gh: int = _lofi_image.get_height()
	var changed := false
	for item in cells:
		var c: Vector2i = item
		if c.x < 0 or c.y < 0 or c.x >= gw or c.y >= gh:
			continue
		_lofi_image.set_pixel(c.x, c.y, cell_visual_color(c.x, c.y))
		changed = true
	if not changed:
		return
	if _radar_atlas_tex != null:
		_radar_atlas_tex.update(_lofi_image)
	else:
		_radar_atlas_tex = ImageTexture.create_from_image(_lofi_image)
	_radar_atlas_image = _lofi_image
	_overview_ground_tex = _radar_atlas_tex
	_ensure_lofi_sprite()


func _any_sheet(sheets: Array) -> bool:
	for s in sheets:
		if s != null:
			return true
	return false


func ensure_pack_for_preview() -> bool:
	_apply_edit_doc_size()
	if pack != null and _any_sheet(pack.sheets):
		return true
	var path := _resolve_pack_path(pack_path)
	if path.strip_edges() == "":
		return edit_doc != null
	var mid := _resolved_map_id()
	if edit_doc != null and "tileset_id" in edit_doc:
		mid = str(edit_map_id) if str(edit_map_id).strip_edges() != "" else mid
	var loaded = TilemapPack.load_pack(path, mid)
	if loaded != null and int(loaded.width) > 0 and _any_sheet(loaded.sheets):
		pack = loaded
		collision = loaded.collision
	if pack != null and _any_sheet(pack.sheets):
		if edit_doc == null:
			grid_width = int(pack.width)
			grid_height = int(pack.height)
			tile_size = int(pack.tile_size)
		else:
			_apply_edit_doc_size()
		return true
	if edit_doc == null:
		return false
	_apply_edit_doc_size()
	return true


func render_preview(x0: int, y0: int, cells_w: int, cells_h: int, px_override: int = 0) -> Image:
	if not ensure_pack_for_preview():
		return null
	## Never 48px-blit more than a 3×3 chunk window (continent hitch).
	if px_override <= 0 and cells_w * cells_h > CHUNK_CELLS * CHUNK_CELLS * 9:
		var r: Rect2i = current_chunk_rect(Vector2i(x0, y0))
		x0 = r.position.x
		y0 = r.position.y
		cells_w = r.size.x
		cells_h = r.size.y
	if px_override > 0 and px_override <= 4:
		return _render_lofi_preview(x0, y0, cells_w, cells_h, px_override)
	var saved_ts: int = tile_size
	if px_override > 0:
		tile_size = px_override
	var img: Image = _render_preview_body(x0, y0, cells_w, cells_h)
	tile_size = saved_ts
	return img


func _render_lofi_preview(x0: int, y0: int, cells_w: int, cells_h: int, px: int) -> Image:
	var gw: int = maxi(grid_width, 1)
	var gh: int = maxi(grid_height, 1)
	x0 = clampi(x0, 0, gw - 1)
	y0 = clampi(y0, 0, gh - 1)
	cells_w = clampi(cells_w, 1, gw - x0)
	cells_h = clampi(cells_h, 1, gh - y0)
	px = maxi(px, 1)
	if _lofi_image != null and _lofi_image.get_width() == gw and _lofi_image.get_height() == gh:
		var chip := Image.create(cells_w, cells_h, false, Image.FORMAT_RGBA8)
		chip.blit_rect(_lofi_image, Rect2i(x0, y0, cells_w, cells_h), Vector2i.ZERO)
		if px > 1:
			chip.resize(cells_w * px, cells_h * px, Image.INTERPOLATE_NEAREST)
		return chip
	var dest := Image.create(cells_w * px, cells_h * px, false, Image.FORMAT_RGBA8)
	dest.fill(Color(0, 0, 0, 1))
	for y in range(cells_h):
		for x in range(cells_w):
			var acc: Color = cell_visual_color(x0 + x, y0 + y)
			if px == 1:
				dest.set_pixel(x, y, acc)
			else:
				for py in range(px):
					for pxx in range(px):
						dest.set_pixel(x * px + pxx, y * px + py, acc)
	return dest


func _render_preview_body(x0: int, y0: int, cells_w: int, cells_h: int) -> Image:
	var ts: int = maxi(tile_size, 1)
	var gw: int = maxi(grid_width, 1)
	var gh: int = maxi(grid_height, 1)
	x0 = clampi(x0, 0, gw - 1)
	y0 = clampi(y0, 0, gh - 1)
	cells_w = clampi(cells_w, 1, gw - x0)
	cells_h = clampi(cells_h, 1, gh - y0)
	var px_w: int = cells_w * ts
	var px_h: int = cells_h * ts
	var below := Image.create(px_w, px_h, false, Image.FORMAT_RGBA8)
	var ground := Image.create(px_w, px_h, false, Image.FORMAT_RGBA8)
	var upper := Image.create(px_w, px_h, false, Image.FORMAT_RGBA8)
	var roof := Image.create(px_w, px_h, false, Image.FORMAT_RGBA8)
	var fx := Image.create(px_w, px_h, false, Image.FORMAT_RGBA8)
	below.fill(Color(0, 0, 0, 0))
	ground.fill(Color(0, 0, 0, 0))
	upper.fill(Color(0, 0, 0, 0))
	roof.fill(Color(0, 0, 0, 0))
	fx.fill(Color(0, 0, 0, 0))
	var sheets: Array = pack.sheets if pack else []
	var flags: PackedInt32Array = pack.flags if pack else PackedInt32Array()
	var col = collision
	var void_id: int = _cached_void_id
	if void_id == 0:
		void_id = _detect_border_void_tile_id(col)
	var prev_anim := _bake_anim
	_bake_anim = false
	for y in range(cells_h):
		for x in range(cells_w):
			var gx := x0 + x
			var gy := y0 + y
			var dx := x * ts
			var dy := y * ts
			_paint_cell(ground, upper, col, sheets, flags, void_id, gx, gy, dx, dy)
			_paint_ext_cell(below, ground, upper, roof, fx, col, sheets, flags, gx, gy, dx, dy)
	_bake_anim = prev_anim
	var dest := Image.create(px_w, px_h, false, Image.FORMAT_RGBA8)
	dest.fill(Color(0, 0, 0, 1))
	var full := Rect2i(0, 0, px_w, px_h)
	dest.blend_rect(below, full, Vector2i.ZERO)
	dest.blend_rect(ground, full, Vector2i.ZERO)
	dest.blend_rect(upper, full, Vector2i.ZERO)
	dest.blend_rect(roof, full, Vector2i.ZERO)
	var fx_mod: Color = light_fx_color()
	_blend_fx_additive(dest, fx, fx_mod)
	var preset := 0
	if edit_doc != null and "light_preset" in edit_doc:
		preset = int(edit_doc.light_preset)
	elif pack != null and "light_preset" in pack:
		preset = int(pack.light_preset)
	_multiply_rgb(dest, MapExt.light_modulate(preset))
	return dest


func _blend_fx_additive(dest: Image, fx: Image, mod: Color) -> void:
	if dest == null or fx == null:
		return
	var used: Rect2i = fx.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return
	var dw: int = dest.get_width()
	var dh: int = dest.get_height()
	for py in range(used.position.y, used.position.y + used.size.y):
		if py < 0 or py >= dh:
			continue
		for px in range(used.position.x, used.position.x + used.size.x):
			if px < 0 or px >= dw:
				continue
			var f: Color = fx.get_pixel(px, py)
			if f.a <= 0.001:
				continue
			var d: Color = dest.get_pixel(px, py)
			var a: float = f.a
			d.r = clampf(d.r + f.r * a * mod.r, 0.0, 1.0)
			d.g = clampf(d.g + f.g * a * mod.g, 0.0, 1.0)
			d.b = clampf(d.b + f.b * a * mod.b, 0.0, 1.0)
			dest.set_pixel(px, py, d)


func _multiply_rgb(img: Image, m: Color) -> void:
	if img == null:
		return
	if is_equal_approx(m.r, 1.0) and is_equal_approx(m.g, 1.0) and is_equal_approx(m.b, 1.0):
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y in range(h):
		for x in range(w):
			var c: Color = img.get_pixel(x, y)
			c.r *= m.r
			c.g *= m.g
			c.b *= m.b
			img.set_pixel(x, y, c)
