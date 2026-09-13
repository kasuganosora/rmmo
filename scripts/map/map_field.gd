extends Node2D
## Renders a tilemap pack to Ground/Objects/Upper sprites and exposes collision.

const TilemapPack = preload("res://scripts/map/tilemap_pack.gd")
const TileBlit = preload("res://scripts/map/tile_blit.gd")
const TileId = preload("res://scripts/map/tile_id.gd")
const MapChunk = preload("res://scripts/map/map_chunk.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")

const CHUNK_CELLS := 16
const PREFETCH_CHUNKS := 1
const UNLOAD_EXTRA_CHUNKS := 1

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
var edit_mode: bool = false
var edit_doc: RefCounted = null
var show_grid: bool = false
var edit_map_id: String = ""
var edit_start_cell: Vector2i = Vector2i(-1, -1)
var edit_show_passage: bool = false
var edit_hover_cell: Vector2i = Vector2i(-1, -1)
var edit_rect_a: Vector2i = Vector2i(-1, -1)
var edit_rect_b: Vector2i = Vector2i(-1, -1)
var _edit_overlay: Node2D


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
	_hide_legacy_fullmap_sprites()
	if not edit_mode:
		_bake_radar_mv_only(false, Callable())
	_stream_ready = true
	_apply_edit_doc_size()
	_obs_cell = _spawn_cell_from_session() if not edit_mode else Vector2i(grid_width / 2, grid_height / 2)
	_rebuild_chunks_around(_obs_cell, not edit_mode)
	_ensure_edit_overlay()


func _rebuild_internal(do_yield: bool, progress: Callable) -> void:
	_ensure_sprites()
	_emit_progress(progress, 0.05)
	if do_yield:
		await get_tree().process_frame
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
	_hide_legacy_fullmap_sprites()
	_emit_progress(progress, 0.12)
	if do_yield:
		await get_tree().process_frame
	_bake_radar_mv_only(do_yield, progress)
	_emit_progress(progress, 0.88)
	if do_yield:
		await get_tree().process_frame
	_stream_ready = true
	_obs_cell = _spawn_cell_from_session()
	_rebuild_chunks_around(_obs_cell, not do_yield)
	if do_yield:
		while not _chunk_queue.is_empty():
			_bake_next_chunk()
			_emit_progress(progress, 0.88 + 0.12 * (1.0 - float(_chunk_queue.size()) / 8.0))
			await get_tree().process_frame
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
	if col.has_method("tile_id"):
		shadow_bits = int(_src_tile(col, x, y, 4))
	var above_t1: int = 0
	if y > 0:
		above_t1 = int(_src_tile(col, x, y - 1, 1))

	# Match classic paint order: z0, z1, shadow, table-edge, z2, z3.
	# Each tile goes to ground or upper solely by flag 0x10 (not by z-layer).
	_blit_by_flag(ground_img, upper_img, t0, dx, dy, sheets, flags)
	_blit_by_flag(ground_img, upper_img, t1, dx, dy, sheets, flags)

	# Shadows blend into ground so transparent rug fringes stay clean.
	if shadow_bits > 0 and (shadow_bits & 0x0f) != 0:
		TileBlit.blit_shadow(ground_img, shadow_bits & 0x0f, dx, dy, tile_size, tile_size)

	# Table edge into lower when cell above z1 is a table and this z1 is not.
	if TileBlit.is_table_tile(above_t1, flags) and not TileBlit.is_table_tile(t1, flags):
		var shadowing: bool = TileId.is_tile_a3(t0) or TileId.is_tile_a4(t0)
		if not shadowing:
			TileBlit.blit_table_edge(ground_img, above_t1, dx, dy, sheets, tile_size, tile_size)

	# z2 then z3 on the same ground/upper bitmap (in-cell stack order).
	# Always paint z3 when visible (includes tileIds 1..15).
	_blit_by_flag(ground_img, upper_img, t2, dx, dy, sheets, flags)
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
	if tile_id < flags.size() and (flags[tile_id] & 0x10) != 0:
		dest = upper_img
	TileBlit.blit_tile(dest, tile_id, dx, dy, sheets, tile_size, tile_size, flags, 0)



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
	if _ground_image != null:
		_overview_ground_tex = ImageTexture.create_from_image(_ground_image)
	if _upper_image != null:
		_overview_upper_tex = ImageTexture.create_from_image(_upper_image)
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


func _process(_delta: float) -> void:
	if not _stream_ready or pack == null:
		return
	_update_observer_from_camera()
	_refresh_chunk_set()
	if not _chunk_queue.is_empty():
		var n := 0
		var cap := 12 if edit_mode else 1
		while not _chunk_queue.is_empty() and n < cap:
			_bake_next_chunk()
			n += 1
	_ensure_edit_overlay()


func _src_tile(col, x: int, y: int, z: int) -> int:
	if edit_doc != null and edit_doc.has_method("tile") and z <= 5:
		return int(edit_doc.tile(x, y, z))
	if col != null and col.has_method("tile_id"):
		return int(col.tile_id(x, y, z))
	return 0


func rebuild_dirty_cells(cells: Array) -> void:
	if not _stream_ready:
		return
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
	_obs_cell = cell
	_refresh_chunk_set()


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
	var vis := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
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
	var extra := Vector2i.ZERO
	match facing:
		2:
			extra = Vector2i(0, 1)
		4:
			extra = Vector2i(-1, 0)
		6:
			extra = Vector2i(1, 0)
		8:
			extra = Vector2i(0, -1)
	min_c -= Vector2i(PREFETCH_CHUNKS, PREFETCH_CHUNKS)
	max_c += Vector2i(PREFETCH_CHUNKS, PREFETCH_CHUNKS)
	if extra != Vector2i.ZERO:
		if extra.x < 0:
			min_c.x += extra.x
		if extra.x > 0:
			max_c.x += extra.x
		if extra.y < 0:
			min_c.y += extra.y
		if extra.y > 0:
			max_c.y += extra.y
	var max_cx := int(ceil(float(grid_width) / float(CHUNK_CELLS))) - 1
	var max_cy := int(ceil(float(grid_height) / float(CHUNK_CELLS))) - 1
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


func _clear_chunks() -> void:
	for key in _chunks.keys():
		var n: Node = _chunks[key]
		if n != null and is_instance_valid(n):
			n.queue_free()
	_chunks.clear()
	_chunk_queue.clear()
	if _chunk_root != null and is_instance_valid(_chunk_root):
		_chunk_root.queue_free()
	_chunk_root = Node2D.new()
	_chunk_root.name = "Chunks"
	add_child(_chunk_root)


func _refresh_chunk_set() -> void:
	var wanted := _wanted_chunks(_obs_cell, _obs_facing)
	for key in wanted.keys():
		if _chunks.has(key):
			continue
		var already := false
		for q in _chunk_queue:
			if _chunk_key(q) == key:
				already = true
				break
		if not already:
			_chunk_queue.append(wanted[key])
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


func _bake_next_chunk() -> void:
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
	if node.has_method("set_roof_visible"):
		node.set_roof_visible(not _roof_hidden)
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
		_blit_to(below, int(edit_doc.ext_tile("far", gx, gy)), dx, dy, sheets, flags, false)
		_blit_to(ground, int(edit_doc.ext_tile("water", gx, gy)), dx, dy, sheets, flags, false)
		_blit_to(ground, int(edit_doc.ext_tile("ground_fx", gx, gy)), dx, dy, sheets, flags, false)
		_blit_by_flag(ground, upper, int(edit_doc.ext_tile("props_low", gx, gy)), dx, dy, sheets, flags)
		_blit_by_flag(ground, upper, int(edit_doc.ext_tile("props_high", gx, gy)), dx, dy, sheets, flags)
		_blit_to(roof, int(edit_doc.ext_tile("roof", gx, gy)), dx, dy, sheets, flags, false)
		_blit_to(upper, int(edit_doc.ext_tile("sky", gx, gy)), dx, dy, sheets, flags, false)
		_blit_to(fx, int(edit_doc.ext_tile("light", gx, gy)), dx, dy, sheets, flags, false)
		return
	if pack == null or pack.get("ext") == null:
		return
	var ext = pack.ext
	if ext == null or not bool(ext.get("valid")):
		return
	if not ext.has_method("has_tiles"):
		return
	if ext.has_tiles("far"):
		_blit_to(below, ext.tile("far", gx, gy), dx, dy, sheets, flags, false)
	if ext.has_tiles("water"):
		_blit_to(ground, ext.tile("water", gx, gy), dx, dy, sheets, flags, false)
	if ext.has_tiles("ground_fx"):
		_blit_to(ground, ext.tile("ground_fx", gx, gy), dx, dy, sheets, flags, false)
	if ext.has_tiles("props_low"):
		_blit_by_flag(ground, upper, ext.tile("props_low", gx, gy), dx, dy, sheets, flags)
	if ext.has_tiles("props_high"):
		_blit_by_flag(ground, upper, ext.tile("props_high", gx, gy), dx, dy, sheets, flags)
	if ext.has_tiles("roof"):
		_blit_to(roof, ext.tile("roof", gx, gy), dx, dy, sheets, flags, false)
	if ext.has_tiles("sky"):
		_blit_to(upper, ext.tile("sky", gx, gy), dx, dy, sheets, flags, false)
	if ext.has_tiles("light"):
		_blit_to(fx, ext.tile("light", gx, gy), dx, dy, sheets, flags, false)


func _blit_to(
	dest: Image,
	tile_id: int,
	dx: int,
	dy: int,
	sheets: Array,
	flags: PackedInt32Array,
	_force_upper: bool
) -> void:
	if tile_id <= 0 or dest == null:
		return
	TileBlit.blit_tile(dest, tile_id, dx, dy, sheets, tile_size, tile_size, flags, 0)


func _bake_radar_mv_only(do_yield: bool, progress: Callable) -> void:
	var w_px: int = grid_width * tile_size
	var h_px: int = grid_height * tile_size
	if w_px <= 0 or h_px <= 0:
		return
	var ground_img := Image.create(w_px, h_px, false, Image.FORMAT_RGBA8)
	ground_img.fill(Color(0, 0, 0, 0))
	var upper_img := Image.create(w_px, h_px, false, Image.FORMAT_RGBA8)
	upper_img.fill(Color(0, 0, 0, 0))
	var sheets: Array = pack.sheets if pack else []
	var flags: PackedInt32Array = pack.flags if pack else PackedInt32Array()
	var col = collision
	var void_id: int = _detect_border_void_tile_id(col)
	var total_y: int = maxi(grid_height, 1)
	for y in range(grid_height):
		for x in range(grid_width):
			_paint_cell(ground_img, upper_img, col, sheets, flags, void_id, x, y)
		if do_yield:
			_emit_progress(progress, 0.12 + 0.70 * float(y + 1) / float(total_y))
	_ground_image = ground_img
	_upper_image = upper_img
	_overview_ground_tex = ImageTexture.create_from_image(ground_img)
	_overview_upper_tex = ImageTexture.create_from_image(upper_img)
	_bake_radar_atlas(ground_img, upper_img, w_px, h_px)
