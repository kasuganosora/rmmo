extends Node
## Runtime content manager — does NOT use Godot ResourceLoader for UGC images.
## See docs/asset_manager_design.md.
##
## P1/P1b: local resolve + Image/JSON + cache + Gate ensure_many + stream queue + budget.
## P2c: actor AOI rings (VIEW/AOI/PREFETCH/COLD) + bind refs + cancel LOW + LRU protect.
## P3: remote fetch + sha256 verify (API ready, download stubbed).

const ContentRef = preload("res://scripts/asset/content_ref.gd")
const ActorInterestModule = preload("res://scripts/asset/actor_interest_module.gd")
var _actor_interest_module_logic: ActorInterestModule = ActorInterestModule.new(self)
const ContentPathResolver = preload("res://scripts/asset/content_path_resolver.gd")
var _content_path_resolver_logic: ContentPathResolver = ContentPathResolver.new(self)
const ContentConfigModule = preload("res://scripts/asset/content_config_module.gd")
var _content_config_module_logic: ContentConfigModule = ContentConfigModule.new(self)
const PlaceholderTex = preload("res://scripts/asset/placeholder_tex.gd")

const DEFAULT_PACK_ID := "default"

## Writable content root (user://content by default).
@export var content_root_override: String = ""

var _content_cfg: Dictionary = {}
var _content_cfg_loaded: bool = false
## alias id -> folder id (from content.json + pack.json content_id)
var _pack_aliases: Dictionary = {}

## path -> Image
var _image_cache: Dictionary = {}
## path -> approx RGBA8 bytes
var _image_cache_bytes: Dictionary = {}
## LRU oldest-first absolute paths
var _image_lru: Array[String] = []
var _image_bytes_total: int = 0
## path -> Dictionary (json)
var _json_cache: Dictionary = {}

## Re-entrancy guard for ensure(ref)
var _ensuring: Dictionary = {}

## AOI rings: actor_id -> VIEW|AOI|PREFETCH|COLD
var _actor_rings: Dictionary = {}
## actor_id -> Array[String] content refs (charset/look)
var _actor_refs: Dictionary = {}
## ref -> true when marked evictable (left AOI / entered COLD)
var _evictable_refs: Dictionary = {}
## ref -> msec when marked evictable (hysteresis before soft eviction)
var _evictable_at_msec: Dictionary = {}
## Soft-eviction hysteresis after leaving AOI / entering COLD (ms).
var evict_hysteresis_msec: int = 7000

signal ensure_finished(ref: String, ok: bool)
signal progress(ref: String, loaded_bytes: int, total_bytes: int)
signal gate_progress(phase: String, fraction: float, label: String)
signal queue_changed(pending: int)

enum Priority { LOW = 0, NORMAL = 1, HIGH = 2, CRITICAL = 3 }

const RING_VIEW := "VIEW"
const RING_AOI := "AOI"
const RING_PREFETCH := "PREFETCH"
const RING_COLD := "COLD"

## Stream queue: Array of {ref, priority}
var _queue: Array = []
var _inflight: Dictionary = {}  # ref -> true
var _max_concurrent: int = 3

## Soft/hard decoded-image budget (MB).
var budget_soft_mb: float = 192.0
var budget_hard_mb: float = 256.0

## RPG Maker MV IconSet: 32×32 cells, 16 columns. Crops cached by atlas path + index.
const MV_ICON_CELL := 32
const MV_ICON_COLS := 16
## "atlas_abs#index" -> Image
var _mv_icon_crop_cache: Dictionary = {}

## Future CDN (P3)
var _remote_base_url: String = ""
var _remote_headers: Dictionary = {}

## Last gate_progress snapshot, so a loading screen can poll load_state() instead of
## (or in addition to) subscribing to the gate_progress signal.
var _last_gate_phase: String = ""
var _last_gate_fraction: float = 0.0
var _last_gate_label: String = ""


func _ready() -> void:
	if not gate_progress.is_connected(_record_gate):
		gate_progress.connect(_record_gate)
	var root := content_root()
	DirAccess.make_dir_recursive_absolute(root)
	DirAccess.make_dir_recursive_absolute("%s/cache/downloads" % root)
	DirAccess.make_dir_recursive_absolute("%s/cache/verified" % root)
	DirAccess.make_dir_recursive_absolute("%s/manifests" % root)
	DirAccess.make_dir_recursive_absolute("%s/packs" % root)
	DirAccess.make_dir_recursive_absolute("%s/packs/ui" % root)
	DirAccess.make_dir_recursive_absolute("%s/assets/charset" % root)
	DirAccess.make_dir_recursive_absolute("%s/assets/fx" % root)
	DirAccess.make_dir_recursive_absolute("%s/assets/icon" % root)
	DirAccess.make_dir_recursive_absolute("%s/data" % root)


func content_root() -> String:
	if content_root_override.strip_edges() != "":
		return content_root_override.strip_edges().rstrip("/").rstrip("\\")
	if ProjectSettings.has_setting("rmmo/content_root"):
		var v := str(ProjectSettings.get_setting("rmmo/content_root", "")).strip_edges()
		if v != "" and DirAccess.dir_exists_absolute(v):
			return v.rstrip("/").rstrip("\\")
	# Luna / playtest fallbacks when ProjectSettings unset (苍蓝星: external runtime, not res://).
	var win_rt := "D:/code/rmmo_runtime"
	if DirAccess.dir_exists_absolute(win_rt):
		return win_rt
	var linux_rt := "/workspace/rmmo_runtime"
	if DirAccess.dir_exists_absolute(linux_rt):
		return linux_rt
	var user_root := ProjectSettings.globalize_path("user://content")
	return user_root.rstrip("/").rstrip("\\")


## `{content_root}/data/{rel}` — catalogs, map presets, RTP tables (never res://).
func data_file(rel: String) -> String:
	rel = rel.strip_edges().replace("\\", "/").lstrip("/")
	if rel.begins_with("data/"):
		rel = rel.substr(5)
	var p := "%s/data/%s" % [content_root(), rel]
	var hit := _existing_file(p)
	if hit != "":
		return hit
	return p


## RPG Maker MV www/img root (苍蓝星 external — never copy into res://).
## Discovery: ProjectSettings rmmo/mv_img_root → {content_root}/mv_img → D:/Games/*v50.5*/www/img → Linux mock.
func mv_img_root() -> String:
	if ProjectSettings.has_setting("rmmo/mv_img_root"):
		var v := str(ProjectSettings.get_setting("rmmo/mv_img_root", "")).strip_edges()
		if v != "" and DirAccess.dir_exists_absolute(v):
			return v.rstrip("/").rstrip("\\")
	var junction := "%s/mv_img" % content_root()
	if DirAccess.dir_exists_absolute(junction):
		return junction.rstrip("/").rstrip("\\")
	# Windows: scan installed 苍蓝星 tree under D:/Games
	var games := "D:/Games"
	if DirAccess.dir_exists_absolute(games):
		var d := DirAccess.open(games)
		if d:
			d.list_dir_begin()
			var name := d.get_next()
			while name != "":
				if d.current_is_dir() and not name.begins_with(".") and name.find("v50.5") >= 0:
					var cand := "%s/%s/www/img" % [games, name]
					if DirAccess.dir_exists_absolute(cand):
						return cand.rstrip("/").rstrip("\\")
					var cand_bs := cand.replace("/", "\\")
					if DirAccess.dir_exists_absolute(cand_bs):
						return cand_bs.rstrip("/").rstrip("\\")
				name = d.get_next()
	var linux_mock := "/workspace/rmmo_runtime/mv_img"
	if DirAccess.dir_exists_absolute(linux_mock):
		return linux_mock
	return ""


func set_remote(base_url: String, headers: Dictionary = {}) -> void:
	_remote_base_url = base_url.strip_edges()
	_remote_headers = headers.duplicate(true)


func set_budget(soft_mb: float, hard_mb: float) -> void:
	budget_soft_mb = maxf(soft_mb, 32.0)
	budget_hard_mb = maxf(hard_mb, budget_soft_mb)
	evict_lru_if_needed()


## Absolute path for a content ref if resolvable; empty if invalid ref.
func path(ref: String) -> String:
	ref = ref.strip_edges()
	if ref.is_empty():
		return ""
	# Allow absolute / res:// passthrough for Gate helpers
	if _is_filesystem_pack_or_file(ref):
		return _normalize_fs_path(ref)
	var cr = ContentRef.parse(ref)
	if not cr.is_valid():
		return ""
	match cr.kind:
		"charset":
			return _resolve_charset_path(cr.id)
		"tilesheet":
			return _resolve_tilesheet_path(cr.id)
		"map_pack":
			return _resolve_map_pack_dir(cr.id, cr.version)
		"look":
			return _resolve_look_path(cr.id)
		"system":
			return _resolve_assets_kind_path("system", cr.id)
		"fx":
			return _resolve_assets_kind_path("fx", cr.id)
		"icon":
			return _resolve_assets_kind_path("icon", cr.id)
		"ui":
			return _resolve_ui_path(cr.id)
		"data":
			return data_file(cr.id)
		_:
			# Prefer file with .png for image-like kinds; also try bare path.
			var base := "%s/assets/%s/%s" % [content_root(), cr.kind, cr.id]
			var with_png := base if base.to_lower().ends_with(".png") else ("%s.png" % base)
			if FileAccess.file_exists(with_png):
				return with_png
			if FileAccess.file_exists(base) or DirAccess.dir_exists_absolute(base):
				return base
			return with_png


func has(ref: String) -> bool:
	ref = ref.strip_edges()
	if ref.is_empty():
		return false
	if ref.begins_with("content:") or ref.begins_with(ContentRef.SCHEME):
		var cr = ContentRef.parse(ref)
		if not cr.is_valid():
			return false
		var p := path(ref)
		if p.is_empty():
			return false
		if cr.kind == "map_pack":
			return FileAccess.file_exists("%s/pack.json" % p) or FileAccess.file_exists("%s/pack.json" % p.replace("\\", "/"))
		return FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p)
	# Filesystem / res path
	var n := _normalize_fs_path(ref)
	if FileAccess.file_exists("%s/pack.json" % n):
		return true
	return FileAccess.file_exists(n) or DirAccess.dir_exists_absolute(n)


## Ensure local availability. P1: local only. P3: download stub.
## Re-entrancy safe: nested ensure(same ref) returns current has() without re-entry loops.
func ensure(ref: String) -> Error:
	ref = ref.strip_edges()
	if ref.is_empty():
		ensure_finished.emit(ref, false)
		return ERR_INVALID_PARAMETER
	if _ensuring.get(ref, false):
		# Re-entrant: do not recurse; report current presence.
		var ok_re := has(ref)
		return OK if ok_re else ERR_BUSY
	_ensuring[ref] = true
	var result: Error = OK
	if has(ref):
		progress.emit(ref, 1, 1)
		ensure_finished.emit(ref, true)
		result = OK
	else:
		# P3 stub: would HTTP GET from manifest when _remote_base_url set.
		if _remote_base_url != "":
			push_warning("AssetManager: remote fetch not implemented yet for %s" % ref)
		push_warning("AssetManager: missing content (no remote yet): %s" % ref)
		ensure_finished.emit(ref, false)
		result = ERR_FILE_NOT_FOUND
	_ensuring.erase(ref)
	return result


## Gate: ensure all refs. Charset/look/icon soft-miss by default (placeholders + stream).
## Map pack / filesystem pack hard-fail. Emits gate_progress.
func ensure_many(refs: Array, phase_label: String = "资源", soft_optional: bool = true) -> Error:
	var list: Array = []
	for r in refs:
		var s := str(r).strip_edges()
		if s != "" and s not in list:
			list.append(s)
	if list.is_empty():
		gate_progress.emit("done", 1.0, "完成")
		return OK
	var i := 0
	var hard_err: Error = OK
	for ref_v in list:
		var ref := str(ref_v)
		var frac := float(i) / float(list.size())
		gate_progress.emit("ensure", frac, "%s %d/%d" % [phase_label, i + 1, list.size()])
		var err := ensure(ref)
		if err != OK:
			var soft := soft_optional and _is_soft_ref(ref)
			if soft:
				push_warning("AssetManager: soft-miss %s (placeholder/stream)" % ref)
				gate_progress.emit("ensure", frac, "缺失(占位)：%s" % ref)
			else:
				gate_progress.emit("error", frac, "缺失：%s" % ref)
				hard_err = err
				return err
		i += 1
	gate_progress.emit("done", 1.0, "资源就绪")
	return hard_err


func _is_soft_ref(ref: String) -> bool:
	if ref.begins_with("content://charset/") or ref.begins_with("content://look/") or ref.begins_with("content://icon/"):
		return true
	if ref.begins_with("content://system/") or ref.begins_with("content://audio/") or ref.begins_with("content://tilesheet/"):
		return true
	if ref.begins_with("content://ui/") or ref.begins_with("content://fx/"):
		return true
	if ref.begins_with("content://data/"):
		return true
	return false


## In-map stream: non-blocking queue. Dedupes; bumps priority if already queued.
func enqueue(refs: Array, priority: int = Priority.NORMAL) -> void:
	for r in refs:
		var ref := str(r).strip_edges()
		if ref.is_empty():
			continue
		if has(ref) or _inflight.get(ref, false):
			continue
		var found := false
		for item in _queue:
			if str(item.get("ref", "")) == ref:
				item["priority"] = maxi(int(item.get("priority", 0)), priority)
				found = true
				break
		if not found:
			_queue.append({"ref": ref, "priority": priority})
	# Prefetch queue cap (drop oldest LOW when > 8 LOW entries)
	var low_count := 0
	for item in _queue:
		if int(item.get("priority", 0)) <= Priority.LOW:
			low_count += 1
	while low_count > 8:
		var drop_i := -1
		for qi in range(_queue.size() - 1, -1, -1):
			if int(_queue[qi].get("priority", 0)) <= Priority.LOW:
				drop_i = qi
				break
		if drop_i < 0:
			break
		_queue.remove_at(drop_i)
		low_count -= 1
	_queue.sort_custom(func(a, b): return int(a.get("priority", 0)) > int(b.get("priority", 0)))
	queue_changed.emit(_queue.size())
	call_deferred("_pump_queue")


func cancel_priority_below(min_priority: int) -> void:
	var kept: Array = []
	for item in _queue:
		if int(item.get("priority", 0)) >= min_priority:
			kept.append(item)
	_queue = kept
	queue_changed.emit(_queue.size())


func _pump_queue() -> void:
	while _inflight.size() < _max_concurrent and not _queue.is_empty():
		# Prefetch throttle: skip LOW while HIGH/CRITICAL waiting
		if not prefetch_allowed():
			var advanced := false
			for qi in range(_queue.size()):
				if int(_queue[qi].get("priority", 0)) >= Priority.HIGH:
					var item_h: Dictionary = _queue.pop_at(qi)
					_run_queue_item(item_h)
					advanced = true
					break
			if not advanced:
				# Only LOW/NORMAL left but HIGH inflight — wait
				break
			continue
		var item: Dictionary = _queue.pop_front()
		_run_queue_item(item)
	queue_changed.emit(_queue.size() + _inflight.size())


func _run_queue_item(item: Dictionary) -> void:
	var ref := str(item.get("ref", ""))
	if ref.is_empty() or has(ref):
		return
	_inflight[ref] = true
	var err := ensure(ref)
	_inflight.erase(ref)
	if err != OK:
		push_warning("AssetManager stream miss: %s" % ref)


## Pause LOW prefetch when HIGH/CRITICAL work is waiting.
func prefetch_allowed() -> bool:
	for item in _queue:
		if int(item.get("priority", 0)) >= Priority.HIGH:
			return false
	for ref_k in _inflight.keys():
		# Inflight HIGH is fine; prefetch still paused if HIGH queued
		pass
	return true


func bind_actor_refs(actor_id: String, refs: Array) -> void:
	_actor_interest_module_logic.bind_actor_refs(actor_id, refs)


func clear_actor_refs(actor_id: String) -> void:
	_actor_interest_module_logic.clear_actor_refs(actor_id)


func get_actor_refs(actor_id: String) -> Array:
	return _actor_interest_module_logic.get_actor_refs(actor_id)


func note_actor_ring(actor_id: String, ring: String) -> void:
	_actor_interest_module_logic.note_actor_ring(actor_id, ring)


func get_actor_ring(actor_id: String) -> String:
	return _actor_interest_module_logic.get_actor_ring(actor_id)


## Assign rings for actors currently in interest; anyone previously tracked but not listed → COLD.
## view_ids win over aoi_ids over prefetch_ids if an id appears in multiple lists.
func set_interest(view_ids: Array, aoi_ids: Array, prefetch_ids: Array) -> void:
	_actor_interest_module_logic.set_interest(view_ids, aoi_ids, prefetch_ids)


## Remove unstarted LOW queue items bound to this actor (shared refs kept if another non-COLD actor needs them).
func cancel_actor_low_jobs(actor_id: String) -> void:
	_actor_interest_module_logic.cancel_actor_low_jobs(actor_id)


func _ref_needed_by_non_cold(ref: String, exclude_actor: String) -> bool:
	return _actor_interest_module_logic._ref_needed_by_non_cold(ref, exclude_actor)


func _mark_actor_evictable(actor_id: String) -> void:
	_actor_interest_module_logic._mark_actor_evictable(actor_id)


func _clear_actor_evictable(actor_id: String) -> void:
	_actor_interest_module_logic._clear_actor_evictable(actor_id)


func _ref_held_by_rings(ref: String, rings: Array) -> bool:
	return _actor_interest_module_logic._ref_held_by_rings(ref, rings)


func _paths_for_ref(ref: String) -> Array[String]:
	return _actor_interest_module_logic._paths_for_ref(ref)


func _is_path_view_protected(p: String) -> bool:
	return _actor_interest_module_logic._is_path_view_protected(p)


func _is_path_aoi_protected(p: String) -> bool:
	return _actor_interest_module_logic._is_path_aoi_protected(p)


func _path_evict_score(p: String, hard: bool) -> int:
	return _actor_interest_module_logic._path_evict_score(p, hard)


func load_image(ref_or_path: String) -> Image:
	var p := ref_or_path.strip_edges()
	if p.is_empty():
		return null
	if p.begins_with("content:") or p.begins_with(ContentRef.SCHEME):
		var err := ensure(p)
		if err != OK:
			return null
		p = path(p)
	if p.is_empty():
		return null
	if _image_cache.has(p):
		var cached: Variant = _image_cache[p]
		if cached is Image:
			_touch_lru(p)
			return cached
	# Also try alt slash form
	var alt := p.replace("\\", "/")
	if alt != p and _image_cache.has(alt):
		var cached2: Variant = _image_cache[alt]
		if cached2 is Image:
			_touch_lru(alt)
			return cached2
	if not FileAccess.file_exists(p) and not FileAccess.file_exists(alt):
		return null
	var load_path := p if FileAccess.file_exists(p) else alt
	var img := Image.new()
	var e: Error = img.load(load_path)
	if e != OK:
		e = img.load(load_path.replace("\\", "/"))
	if e != OK:
		push_error("AssetManager: Image.load failed %s (%s)" % [load_path, error_string(e)])
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_put_image_cache(load_path, img)
	return img


func load_mv_icon(icon_index: int, atlas_ref: String = "content://system/IconSet") -> Image:
	if icon_index < 0:
		return null
	atlas_ref = atlas_ref.strip_edges()
	if atlas_ref.is_empty():
		atlas_ref = "content://system/IconSet"
	var atlas_path := ""
	if atlas_ref.begins_with("content:") or atlas_ref.begins_with(ContentRef.SCHEME):
		var err := ensure(atlas_ref)
		if err != OK:
			return null
		atlas_path = path(atlas_ref)
	else:
		atlas_path = atlas_ref
	if atlas_path.is_empty():
		return null
	# Prefer .png if resolvers returned bare path without extension.
	if not FileAccess.file_exists(atlas_path):
		var alt := atlas_path if atlas_path.to_lower().ends_with(".png") else ("%s.png" % atlas_path)
		var alt2 := atlas_path.replace("\\", "/")
		if FileAccess.file_exists(alt):
			atlas_path = alt
		elif FileAccess.file_exists(alt2):
			atlas_path = alt2
		elif FileAccess.file_exists("%s.png" % alt2):
			atlas_path = "%s.png" % alt2
		else:
			return null
	var cache_key := "%s#%d" % [atlas_path.replace("\\", "/"), icon_index]
	if _mv_icon_crop_cache.has(cache_key):
		var cached: Variant = _mv_icon_crop_cache[cache_key]
		if cached is Image:
			return cached
	var atlas := load_image(atlas_path)
	if atlas == null:
		return null
	var cols := MV_ICON_COLS
	var cell := MV_ICON_CELL
	var col := icon_index % cols
	var row := int(icon_index / cols)
	var x := col * cell
	var y := row * cell
	if x + cell > atlas.get_width() or y + cell > atlas.get_height():
		push_warning("AssetManager: MV icon_index %d out of atlas bounds (%dx%d)" % [icon_index, atlas.get_width(), atlas.get_height()])
		return null
	var crop := atlas.get_region(Rect2i(x, y, cell, cell))
	if crop == null or crop.is_empty():
		return null
	if crop.get_format() != Image.FORMAT_RGBA8:
		crop.convert(Image.FORMAT_RGBA8)
	_mv_icon_crop_cache[cache_key] = crop
	return crop


func load_mv_icon_texture(icon_index: int, atlas_ref: String = "content://system/IconSet") -> ImageTexture:
	var img := load_mv_icon(icon_index, atlas_ref)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


func load_texture(ref_or_path: String) -> ImageTexture:
	var img := load_image(ref_or_path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


func clear_mv_icon_cache() -> void:
	_mv_icon_crop_cache.clear()


func load_json(ref_or_path: String) -> Dictionary:
	## Accept content:// ref or filesystem/res path. Never ResourceLoader for UGC JSON.
	var s := ref_or_path.strip_edges()
	if s.is_empty():
		return {}
	if s.begins_with("content:") or s.begins_with(ContentRef.SCHEME):
		var err := ensure(s)
		if err != OK:
			return {}
		var p := path(s)
		if p.is_empty():
			return {}
		# map_pack → pack.json
		var cr = ContentRef.parse(s)
		if cr.is_valid() and cr.kind == "map_pack":
			return load_json_file("%s/pack.json" % p)
		if DirAccess.dir_exists_absolute(p):
			return load_json_file("%s/pack.json" % p)
		return load_json_file(p)
	return load_json_file(s)


func load_json_file(abs_path: String) -> Dictionary:
	abs_path = abs_path.strip_edges()
	if abs_path.is_empty():
		return {}
	# Support res://
	var open_path := abs_path
	if not FileAccess.file_exists(open_path):
		var glob := ProjectSettings.globalize_path(abs_path)
		if FileAccess.file_exists(glob):
			open_path = glob
		else:
			return {}
	if _json_cache.has(open_path):
		var v: Variant = _json_cache[open_path]
		if typeof(v) == TYPE_DICTIONARY:
			return (v as Dictionary).duplicate(true)
	var f := FileAccess.open(open_path, FileAccess.READ)
	if f == null:
		return {}
	var raw: Variant = JSON.parse_string(f.get_as_text())
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	_json_cache[open_path] = (raw as Dictionary).duplicate(true)
	return (raw as Dictionary).duplicate(true)


func clear_cache() -> void:
	clear_image_cache()
	_json_cache.clear()


func clear_image_cache() -> void:
	_image_cache.clear()
	_image_cache_bytes.clear()
	_image_lru.clear()
	_image_bytes_total = 0
	clear_mv_icon_cache()


func evict_image(ref_or_path: String) -> void:
	var p := path(ref_or_path) if ref_or_path.begins_with("content:") else ref_or_path
	_evict_one(p)


func make_letter_texture(text: String, size: int = 48) -> ImageTexture:
	return PlaceholderTex.make_letter_texture(text, size)


func make_letter_sprite_frames(text: String, size: int = 48) -> SpriteFrames:
	return PlaceholderTex.make_letter_sprite_frames(text, size)


# --- map pack helpers -------------------------------------------------------

func content_config() -> Dictionary:
	return _content_config_module_logic.content_config()


func start_map_pack_id() -> String:
	return _content_config_module_logic.start_map_pack_id()


func start_map_pack_ref() -> String:
	return _content_config_module_logic.start_map_pack_ref()


func street_map_pack_id() -> String:
	return _content_config_module_logic.street_map_pack_id()


func street_map_pack_ref() -> String:
	return _content_config_module_logic.street_map_pack_ref()


func street_map_id() -> String:
	return _content_config_module_logic.street_map_id()


func street_spawn_cell() -> Vector2i:
	return _content_config_module_logic.street_spawn_cell()


func start_spawn_cell() -> Vector2i:
	return _content_config_module_logic.start_spawn_cell()


func _cfg_cell(key: String) -> Vector2i:
	return _content_config_module_logic._cfg_cell(key)


func ui_pack_id() -> String:
	return _content_config_module_logic.ui_pack_id()


func alias_map_pack_id(pack_id: String) -> String:
	return _content_config_module_logic.alias_map_pack_id(pack_id)


func _strip_pack_token(pack_id: String) -> String:
	return _content_config_module_logic._strip_pack_token(pack_id)


func _ensure_content_cfg() -> void:
	_content_config_module_logic._ensure_content_cfg()


func _scan_pack_aliases() -> void:
	_content_config_module_logic._scan_pack_aliases()


func _pack_dir_with_json(base: String) -> String:
	return _content_path_resolver_logic._pack_dir_with_json(base)


## Resolve res:// packs, content ids, absolute dirs → usable pack directory path.
func default_map_pack_path() -> String:
	return _content_path_resolver_logic.default_map_pack_path()


func resolve_map_pack_path(pack_path_or_id: String) -> String:
	return _content_path_resolver_logic.resolve_map_pack_path(pack_path_or_id)


## Collect Gate deps: pack.json deps + npcs.json charset ids → content:// refs.
func collect_map_pack_deps(pack_dir: String) -> Array[String]:
	return _content_path_resolver_logic.collect_map_pack_deps(pack_dir)


func _add_dep(out: Array[String], seen: Dictionary, ref: String) -> void:
	_content_path_resolver_logic._add_dep(out, seen, ref)


# --- image cache / LRU ------------------------------------------------------

func _approx_image_bytes(img: Image) -> int:
	if img == null:
		return 0
	return img.get_width() * img.get_height() * 4


func _put_image_cache(p: String, img: Image) -> void:
	if _image_cache.has(p):
		_image_bytes_total -= int(_image_cache_bytes.get(p, 0))
	var nbytes := _approx_image_bytes(img)
	_image_cache[p] = img
	_image_cache_bytes[p] = nbytes
	_image_bytes_total += nbytes
	_touch_lru(p)
	evict_lru_if_needed()


func _touch_lru(p: String) -> void:
	var idx := _image_lru.find(p)
	if idx >= 0:
		_image_lru.remove_at(idx)
	_image_lru.append(p)


func _evict_one(p: String) -> void:
	if not _image_cache.has(p):
		return
	_image_bytes_total -= int(_image_cache_bytes.get(p, 0))
	_image_cache.erase(p)
	_image_cache_bytes.erase(p)
	var idx := _image_lru.find(p)
	if idx >= 0:
		_image_lru.remove_at(idx)


func evict_lru_if_needed() -> void:
	var soft := int(budget_soft_mb * 1024.0 * 1024.0)
	var hard_budget := int(budget_hard_mb * 1024.0 * 1024.0)
	var over_hard := _image_bytes_total > hard_budget
	var limit := soft
	if over_hard:
		limit = int(soft * 0.75)  # aggressive toward soft
	var guard := 0
	while _image_bytes_total > limit and not _image_lru.is_empty() and guard < _image_lru.size() + 8:
		guard += 1
		var best_i := -1
		var best_score := 999999
		# Prefer oldest among best (lowest) scores; scan LRU oldest-first for ties
		for i in range(_image_lru.size()):
			var p: String = _image_lru[i]
			var sc := _path_evict_score(p, over_hard)
			if sc < 0:
				continue
			if sc < best_score:
				best_score = sc
				best_i = i
				# Perfect COLD/evictable hit at oldest slot — take it
				if sc <= 20 and i == 0:
					break
		if best_i < 0:
			# Nothing safe to evict (all VIEW / AOI soft-protected)
			break
		_evict_one(_image_lru[best_i])


func image_cache_stats() -> Dictionary:
	return {
		"entries": _image_cache.size(),
		"bytes": _image_bytes_total,
		"soft_mb": budget_soft_mb,
		"hard_mb": budget_hard_mb,
	}


## Record the latest gate_progress so load_state() can report it without a subscription.
func _record_gate(phase: String, fraction: float, label: String) -> void:
	_last_gate_phase = phase
	_last_gate_fraction = clampf(fraction, 0.0, 1.0)
	_last_gate_label = label


## Loading-state snapshot for the loading screen (and any progress UI).
## `busy` is true while the stream queue, in-flight loads, ensure-gate, or an
## unfinished gate phase are still active. `progress` is a 0..1 estimate: the gate
## fraction while a gate phase runs, otherwise derived from queue drain.
func load_state() -> Dictionary:
	var pending: int = _queue.size()
	var inflight: int = _inflight.size()
	var active: int = pending + inflight
	var ensuring: int = _ensuring.size()
	var gate_active: bool = _last_gate_phase != "" and _last_gate_phase != "done" and _last_gate_fraction < 1.0
	var busy: bool = active > 0 or ensuring > 0 or gate_active
	var progress: float = 1.0
	if gate_active:
		progress = _last_gate_fraction
	elif active > 0:
		# Fewer items left = closer to done; unknown total, so report a soft estimate.
		progress = clampf(float(inflight) / float(maxi(active, 1)), 0.0, 0.99)
	return {
		"busy": busy,
		"progress": progress,
		"pending": pending,
		"inflight": inflight,
		"active": active,
		"ensuring": ensuring,
		"max_concurrent": _max_concurrent,
		"gate_phase": _last_gate_phase,
		"gate_fraction": _last_gate_fraction,
		"gate_label": _last_gate_label,
		"cache_entries": _image_cache.size(),
		"cache_bytes": _image_bytes_total,
		"budget_soft_mb": budget_soft_mb,
		"budget_hard_mb": budget_hard_mb,
	}


# --- resolvers (P1 local) -------------------------------------------------

func _resolve_charset_path(charset_id: String) -> String:
	return _content_path_resolver_logic._resolve_charset_path(charset_id)


## Tilesheet PNG: content_root/assets/tilesheet → mv_img/tilesets (苍蓝星). Soft-miss OK.
func _resolve_tilesheet_path(sheet_name: String) -> String:
	return _content_path_resolver_logic._resolve_tilesheet_path(sheet_name)


func _existing_file(p: String) -> String:
	return _content_path_resolver_logic._existing_file(p)


func _resolve_map_pack_dir(pack_id: String, version: String) -> String:
	return _content_path_resolver_logic._resolve_map_pack_dir(pack_id, version)


func _find_pack_by_content_id(content_id: String) -> String:
	return _content_path_resolver_logic._find_pack_by_content_id(content_id)


func _resolve_look_path(look_id: String) -> String:
	return _content_path_resolver_logic._resolve_look_path(look_id)


## UI chrome pack: content://ui/{skin}/{rel} → packs/ui/<id>/<ver>/{skin}/{rel}.
func _resolve_ui_pack_dir(pack_id: String = "", version: String = "") -> String:
	return _content_path_resolver_logic._resolve_ui_pack_dir(pack_id, version)


func _resolve_ui_path(asset_id: String) -> String:
	return _content_path_resolver_logic._resolve_ui_path(asset_id)


## Flat files under {content_root}/assets/{kind}/{id} (system / fx / icon / ...).
func _resolve_assets_kind_path(kind: String, asset_id: String) -> String:
	return _content_path_resolver_logic._resolve_assets_kind_path(kind, asset_id)


## Resolve slot icon: prefer MV icon_index, else standalone content://icon/{id}.
## Returns ImageTexture or null (caller keeps letter avatar).
func resolve_slot_icon_texture(icon_index: int = -1, icon_id_or_ref: String = "") -> ImageTexture:
	if icon_index >= 0:
		var tex := load_mv_icon_texture(icon_index)
		if tex != null:
			return tex
	var ref := icon_id_or_ref.strip_edges()
	if ref.is_empty():
		return null
	if not ref.begins_with("content:"):
		ref = "content://icon/%s" % ref
	var img := load_image(ref)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


## Shared drag preview: TextureRect when atlas/file resolves, else letter Label.
func make_drag_preview(display_name: String, icon_index: int = -1, icon_ref: String = "", size: Vector2 = Vector2(40, 40)) -> Control:
	var preview := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.16, 0.15, 0.14, 0.92)
	psb.border_color = Color(0.75, 0.6, 0.3, 1)
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(3)
	psb.set_content_margin_all(4)
	preview.add_theme_stylebox_override("panel", psb)
	preview.custom_minimum_size = size
	var tex: ImageTexture = resolve_slot_icon_texture(icon_index, icon_ref)
	if tex != null:
		var tr := TextureRect.new()
		tr.name = "Icon"
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(maxi(int(size.x) - 8, 16), maxi(int(size.y) - 8, 16))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(tr)
	else:
		var pl := Label.new()
		pl.name = "Letter"
		var nm := display_name.strip_edges()
		pl.text = nm.substr(0, 1) if not nm.is_empty() else "?"
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pl.add_theme_font_size_override("font_size", 22)
		pl.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(pl)
	return preview


func _pack_json_exists(dir_path: String) -> bool:
	return _content_path_resolver_logic._pack_json_exists(dir_path)


func _prefer_res_if_project(abs_or_res: String) -> String:
	return _content_path_resolver_logic._prefer_res_if_project(abs_or_res)


func _is_filesystem_pack_or_file(ref: String) -> bool:
	return _content_path_resolver_logic._is_filesystem_pack_or_file(ref)


func _normalize_fs_path(ref: String) -> String:
	return _content_path_resolver_logic._normalize_fs_path(ref)
