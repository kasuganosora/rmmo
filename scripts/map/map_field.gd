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

@export var pack_path: String = ""

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
const TileAnimModule = preload("res://scripts/map/field/tile_anim_module.gd")
const ChunkStreamModule = preload("res://scripts/map/field/chunk_stream_module.gd")
const RadarModule = preload("res://scripts/map/field/radar_module.gd")
const WorldMapModule = preload("res://scripts/map/field/world_map_module.gd")
const AtmosphereModule = preload("res://scripts/map/field/atmosphere_module.gd")
const EditModule = preload("res://scripts/map/field/edit_module.gd")
var _edit_module_logic: EditModule = EditModule.new(self)
var _atmosphere_module_logic: AtmosphereModule = AtmosphereModule.new(self)
var _world_map_module_logic: WorldMapModule = WorldMapModule.new(self)
var _radar_module_logic: RadarModule = RadarModule.new(self)
var _chunk_stream_module_logic: ChunkStreamModule = ChunkStreamModule.new(self)
var _tile_anim_module_logic: TileAnimModule = TileAnimModule.new(self)
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
	_radar_module_logic._ensure_lofi_canvas()
func _stamp_lofi_from_chunk(node: Node2D, c: Vector2i) -> void:
	_radar_module_logic._stamp_lofi_from_chunk(node, c)
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
	_radar_module_logic._publish_lofi_atlas()
func _ensure_lofi_sprite() -> void:
	_radar_module_logic._ensure_lofi_sprite()
func _resolve_pack_path(p: String) -> String:
	p = p.strip_edges()
	var am: Node = get_node_or_null("/root/AssetManager")
	if p.is_empty() and am != null and am.has_method("start_map_pack_ref"):
		p = str(am.start_map_pack_ref())
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
	return _radar_module_logic.get_radar_atlas_image()
func get_radar_atlas_texture() -> Texture2D:
	return _radar_module_logic.get_radar_atlas_texture()
func get_radar_atlas_scale() -> float:
	return _radar_module_logic.get_radar_atlas_scale()
func get_lofi_image() -> Image:
	return _radar_module_logic.get_lofi_image()
func get_lofi_texture() -> Texture2D:
	return _radar_module_logic.get_lofi_texture()
func get_radar_origin_cell() -> Vector2i:
	return _radar_module_logic.get_radar_origin_cell()
func _uses_radar_window() -> bool:
	return _radar_module_logic._uses_radar_window()
func world_map_complete() -> bool:
	return _world_map_module_logic.world_map_complete()
func world_map_progress() -> float:
	return _world_map_module_logic.world_map_progress()
func ensure_world_map() -> void:
	_world_map_module_logic.ensure_world_map()
func world_map_step(n: int = 4) -> bool:
	return _world_map_module_logic.world_map_step(n)
func sample_world_chunk(cx: int, cy: int) -> Image:
	return _world_map_module_logic.sample_world_chunk(cx, cy)
func _alloc_world_map_canvas() -> void:
	_world_map_module_logic._alloc_world_map_canvas()
func _fill_world_map_queue() -> void:
	_world_map_module_logic._fill_world_map_queue()
func _world_chunk_dir() -> String:
	return _world_map_module_logic._world_chunk_dir()
func _evict_wm_cache(cache: Dictionary) -> void:
	_world_map_module_logic._evict_wm_cache(cache)
func _world_chunk_buf(cx: int, cy: int) -> PackedInt32Array:
	return _world_map_module_logic._world_chunk_buf(cx, cy)
func _stamp_world_chunk(cx: int, cy: int, buf: PackedInt32Array, sheets: Array, flags: PackedInt32Array) -> void:
	_world_map_module_logic._stamp_world_chunk(cx, cy, buf, sheets, flags)
func _commit_world_map_tex() -> void:
	_world_map_module_logic._commit_world_map_tex()
func _try_save_world_map() -> void:
	_world_map_module_logic._try_save_world_map()
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
	_radar_module_logic._bake_radar_atlas(ground_img, upper_img, w_px, h_px)
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
	_edit_module_logic.set_edit_camera_cell(cell)
func _edit_observer_cell() -> Vector2i:
	return _edit_module_logic._edit_observer_cell()
func current_chunk() -> Vector2i:
	return _chunk_stream_module_logic.current_chunk()
func current_chunk_rect(cell: Vector2i = Vector2i(-9999, -9999)) -> Rect2i:
	return _chunk_stream_module_logic.current_chunk_rect(cell)
func bake_observer_chunk() -> void:
	_chunk_stream_module_logic.bake_observer_chunk()
func _prioritize_chunk(ch: Vector2i) -> void:
	_chunk_stream_module_logic._prioritize_chunk(ch)
func is_layer_drawn_z(z: int) -> bool:
	return _edit_module_logic.is_layer_drawn_z(z)
func is_layer_drawn_ext(id: String) -> bool:
	return _edit_module_logic.is_layer_drawn_ext(id)
func set_layer_hidden_z(z: int, hidden: bool) -> void:
	_edit_module_logic.set_layer_hidden_z(z, hidden)
func set_layer_hidden_ext(id: String, hidden: bool) -> void:
	_edit_module_logic.set_layer_hidden_ext(id, hidden)
func rebake_loaded_chunks() -> void:
	_chunk_stream_module_logic.rebake_loaded_chunks()
func _apply_edit_doc_size() -> void:
	_edit_module_logic._apply_edit_doc_size()
func set_edit_flags(flags: PackedInt32Array) -> void:
	_edit_module_logic.set_edit_flags(flags)
func edit_cell_passable(x: int, y: int) -> int:
	return _edit_module_logic.edit_cell_passable(x, y)
func _ensure_edit_overlay() -> void:
	_edit_module_logic._ensure_edit_overlay()
func set_observer(cell: Vector2i, facing: int = 2) -> void:
	_chunk_stream_module_logic.set_observer(cell, facing)
func light_fx_color() -> Color:
	return _atmosphere_module_logic.light_fx_color()
func apply_light_fx_color() -> void:
	_atmosphere_module_logic.apply_light_fx_color()
func set_bucket_alpha(bucket: String, a: float) -> void:
	_atmosphere_module_logic.set_bucket_alpha(bucket, a)
func map_is_indoor() -> bool:
	return _atmosphere_module_logic.map_is_indoor()
func set_atmosphere(light_id: int, kind: String, intensity: float) -> Dictionary:
	return _atmosphere_module_logic.set_atmosphere(light_id, kind, intensity)
func weather_display_modulate() -> Color:
	return _atmosphere_module_logic.weather_display_modulate()
func _ensure_weather_fx() -> void:
	_atmosphere_module_logic._ensure_weather_fx()
func _sync_weather_eaves() -> void:
	_atmosphere_module_logic._sync_weather_eaves()
func set_reference_image(path: String, alpha: float = 0.35) -> void:
	_edit_module_logic.set_reference_image(path, alpha)
func far_scroll_vec() -> Vector2:
	return _atmosphere_module_logic.far_scroll_vec()
func _apply_far_parallax() -> void:
	_atmosphere_module_logic._apply_far_parallax()
func _apply_indoor_from_cell(cell: Vector2i) -> void:
	_atmosphere_module_logic._apply_indoor_from_cell(cell)
func _update_observer_from_camera() -> void:
	_chunk_stream_module_logic._update_observer_from_camera()
func _chunk_key(c: Vector2i) -> String:
	return _chunk_stream_module_logic._chunk_key(c)
func cell_to_chunk(cell: Vector2i) -> Vector2i:
	return _chunk_stream_module_logic.cell_to_chunk(cell)
func _wanted_chunks(center_cell: Vector2i, facing: int) -> Dictionary:
	return _chunk_stream_module_logic._wanted_chunks(center_cell, facing)
func _rebuild_chunks_around(cell: Vector2i, bake_sync: bool) -> void:
	_chunk_stream_module_logic._rebuild_chunks_around(cell, bake_sync)
func _clear_chunks() -> void:
	_chunk_stream_module_logic._clear_chunks()
func _refresh_chunk_set() -> void:
	_chunk_stream_module_logic._refresh_chunk_set()
func _sync_stream_data(wanted: Dictionary) -> void:
	_chunk_stream_module_logic._sync_stream_data(wanted)
func _enqueue_chunk(c: Vector2i) -> void:
	_chunk_stream_module_logic._enqueue_chunk(c)
func _chunk_is_ahead(c: Vector2i) -> bool:
	return _chunk_stream_module_logic._chunk_is_ahead(c)
func _bake_next_chunk(full_anim: bool = true) -> void:
	_chunk_stream_module_logic._bake_next_chunk(full_anim)
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
	return _tile_anim_module_logic._cell_has_ground_anim(t0, t1, t2, t3, flags)
func _anim_image(bucket: String, like: Image) -> Image:
	return _tile_anim_module_logic._anim_image(bucket, like)
func _begin_anim_bake() -> void:
	_tile_anim_module_logic._begin_anim_bake()
func _finish_anim_bake(node: Node2D, full_anim: bool = true) -> void:
	_tile_anim_module_logic._finish_anim_bake(node, full_anim)
func _anim_layer_z(bucket: String) -> int:
	return _tile_anim_module_logic._anim_layer_z(bucket)
func _tick_tile_anim(delta: float) -> void:
	_tile_anim_module_logic._tick_tile_anim(delta)
func tick_tile_anim() -> int:
	return _tile_anim_module_logic.tick_tile_anim()
func tile_anim_mix() -> float:
	return _tile_anim_module_logic.tile_anim_mix()
func tile_anim_frame() -> int:
	return _tile_anim_module_logic.tile_anim_frame()
func _refresh_chunk_anims(mix_t: float = 0.0) -> void:
	_tile_anim_module_logic._refresh_chunk_anims(mix_t)
func _set_chunk_anim_mix(mix_t: float) -> void:
	_tile_anim_module_logic._set_chunk_anim_mix(mix_t)
func _pump_anim_prebake() -> void:
	_tile_anim_module_logic._pump_anim_prebake()
func _bake_radar_mv_only(do_yield: bool, progress: Callable) -> void:
	_radar_module_logic._bake_radar_mv_only(do_yield, progress)
func _bake_lofi_overview() -> void:
	_radar_module_logic._bake_lofi_overview()
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
	_radar_module_logic._rebuild_radar_window()
func _patch_lofi_cells(cells: Array) -> void:
	_radar_module_logic._patch_lofi_cells(cells)
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
	return _radar_module_logic._render_lofi_preview(x0, y0, cells_w, cells_h, px)
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
