extends RefCounted
## Runtime MV-style charset atlas (3x4 per character). Loads via Image.load — not res:// import.
## Prefers AssetManager when autoload is present; falls back to legacy roots for headless tests.

const SETTING_ROOT := "rmmo/charset_root"
## Editor/dev fallback (outside Godot project tree). Production: set ProjectSettings or pack charset_root.
const DEFAULT_DEV_ROOT := "D:/code/rmmo_runtime/characters"

## Cache: absolute path -> Image (dual-cache with AssetManager; prefer Manager)
static var _image_cache: Dictionary = {}


static func charset_root() -> String:
	if ProjectSettings.has_setting(SETTING_ROOT):
		var v: String = str(ProjectSettings.get_setting(SETTING_ROOT, "")).strip_edges()
		if v != "":
			return v.rstrip("/").rstrip("\\")
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	var beside_exe: String = "%s/data/characters" % exe_dir
	if DirAccess.dir_exists_absolute(beside_exe):
		return beside_exe
	if DirAccess.dir_exists_absolute(DEFAULT_DEV_ROOT):
		return DEFAULT_DEV_ROOT
	return beside_exe


static func _asset_manager() -> Node:
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		var tree := loop as SceneTree
		var n: Node = tree.root.get_node_or_null("AssetManager")
		if n != null:
			return n
	return null


static func resolve_sheet_path(charset: String, pack_dir: String = "") -> String:
	var file_name: String = "%s.png" % charset
	# 0) Prefer AssetManager content://charset/{id} when autoload present
	var am: Node = _asset_manager()
	if am != null and am.has_method("path"):
		var cref := "content://charset/%s" % charset
		var am_path: String = str(am.path(cref))
		if am_path != "" and FileAccess.file_exists(am_path):
			return am_path
		var am_alt: String = am_path.replace("/", "\\")
		if am_path != "" and FileAccess.file_exists(am_alt):
			return am_alt
	# 1) Pack-adjacent characters/ only if that folder is outside the imported project tree.
	if pack_dir != "":
		var pack_abs: String = ProjectSettings.globalize_path(pack_dir).rstrip("/").rstrip("\\")
		var local: String = "%s/characters/%s" % [pack_abs, file_name]
		if FileAccess.file_exists(local):
			var project_res: String = ProjectSettings.globalize_path("res://").rstrip("/").rstrip("\\")
			if not local.begins_with(project_res):
				return local
	# 2) Configured / runtime charset root (legacy fallback for headless without autoload)
	var root: String = charset_root()
	var path: String = "%s/%s" % [root, file_name]
	if FileAccess.file_exists(path):
		return path
	# Windows path normalize
	path = path.replace("/", "\\")
	if FileAccess.file_exists(path):
		return path
	# 3) content_root/characters + mv_img/characters (苍蓝星) when AssetManager available
	if am != null:
		if am.has_method("content_root"):
			var cr_chars: String = "%s/characters/%s" % [str(am.content_root()), file_name]
			if FileAccess.file_exists(cr_chars):
				return cr_chars
		if am.has_method("mv_img_root"):
			var mv: String = str(am.mv_img_root()).strip_edges()
			if mv != "":
				var mv_path: String = "%s/characters/%s" % [mv, file_name]
				if FileAccess.file_exists(mv_path):
					return mv_path
				var mv_alt: String = mv_path.replace("/", "\\")
				if FileAccess.file_exists(mv_alt):
					return mv_alt
	# If AssetManager resolved an expected path, return it for diagnostics
	if am != null and am.has_method("path"):
		var expected: String = str(am.path("content://charset/%s" % charset))
		if expected != "":
			return expected
	return "%s/%s" % [root, file_name]


static func load_image(path: String) -> Image:
	if path.is_empty():
		return null
	# Prefer AssetManager shared cache (content ref or absolute path)
	var am: Node = _asset_manager()
	if am != null and am.has_method("load_image"):
		var via_am: Image = am.load_image(path)
		if via_am != null:
			_image_cache[path] = via_am
			return via_am
		if path.begins_with("content:"):
			return null
	if _image_cache.has(path):
		var cached: Variant = _image_cache[path]
		if cached is Image:
			return cached
	var img := Image.new()
	var err: Error = img.load(path)
	if err != OK:
		var alt: String = path.replace("\\", "/")
		err = img.load(alt)
	if err != OK:
		push_warning("charset_sheet: cannot load %s (%s)" % [path, error_string(err)])
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_image_cache[path] = img
	return img


static func is_big_sheet(charset: String) -> bool:
	## $ prefix (after optional !) => single-character sheet (3x4).
	var n: String = charset
	if n.begins_with("!"):
		n = n.substr(1)
	return n.begins_with("$")


static func is_object_sheet(charset: String) -> bool:
	return charset.begins_with("!")


static func frame_size(img: Image, charset: String) -> Vector2i:
	if img == null:
		return Vector2i(48, 48)
	var big: bool = is_big_sheet(charset)
	var fw: int = img.get_width() / (3 if big else 12)
	var fh: int = img.get_height() / (4 if big else 8)
	return Vector2i(maxi(fw, 1), maxi(fh, 1))


static func atlas_rect(img: Image, charset: String, index: int, direction: int, pattern: int) -> Rect2i:
	var fs: Vector2i = frame_size(img, charset)
	var big: bool = is_big_sheet(charset)
	var idx: int = 0 if big else clampi(index, 0, 7)
	var pat: int = clampi(pattern, 0, 2)
	var dir_row: int = clampi(int(direction / 2) - 1, 0, 3)  # 2,4,6,8 -> 0..3
	var col_base: int = (idx % 4) * 3
	var row_base: int = int(idx / 4) * 4
	if big:
		col_base = 0
		row_base = 0
	var sx: int = (col_base + pat) * fs.x
	var sy: int = (row_base + dir_row) * fs.y
	return Rect2i(sx, sy, fs.x, fs.y)


static func make_frame_texture(img: Image, charset: String, index: int, direction: int, pattern: int) -> AtlasTexture:
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = atlas_rect(img, charset, index, direction, pattern)
	return at


## Build idle (+ optional walk) SpriteFrames for one character slot.
static func build_sprite_frames(charset: String, index: int, pack_dir: String = "") -> SpriteFrames:
	var path: String = resolve_sheet_path(charset, pack_dir)
	var img: Image = null
	# Try content ref through AssetManager first when available
	var am: Node = _asset_manager()
	if am != null and am.has_method("load_image"):
		img = am.load_image("content://charset/%s" % charset)
	# Legacy path only if file actually exists (avoid noisy miss after AM soft-fail)
	if img == null and path != "" and FileAccess.file_exists(path):
		img = load_image(path)
	elif img == null and path != "":
		var altp: String = path.replace("\\", "/")
		if altp != path and FileAccess.file_exists(altp):
			img = load_image(altp)
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	if img == null:
		return frames
	var dirs: Dictionary = {"front": 2, "left": 4, "right": 6, "back": 8}
	var object_like: bool = is_object_sheet(charset)
	for facing in dirs.keys():
		var d: int = int(dirs[facing])
		var idle_name: String = "idle_%s" % facing
		frames.add_animation(idle_name)
		frames.set_animation_speed(idle_name, 1.0)
		frames.set_animation_loop(idle_name, true)
		# Idle uses middle pattern (1); objects often use pattern 0/1 still.
		var idle_pat: int = 1
		var idle_tex: AtlasTexture = make_frame_texture(img, charset, index, d, idle_pat)
		if idle_tex:
			frames.add_frame(idle_name, idle_tex)

		var walk_name: String = "walk_%s" % facing
		frames.add_animation(walk_name)
		frames.set_animation_loop(walk_name, true)
		if object_like:
			# Objects: gentle 3-frame shimmer if sheet has columns.
			frames.set_animation_speed(walk_name, 4.0)
			for pat in range(3):
				var t: AtlasTexture = make_frame_texture(img, charset, index, d, pat)
				if t:
					frames.add_frame(walk_name, t)
		else:
			frames.set_animation_speed(walk_name, 12.0)
			for pat in [0, 1, 2, 1]:
				var t2: AtlasTexture = make_frame_texture(img, charset, index, d, pat)
				if t2:
					frames.add_frame(walk_name, t2)
	return frames


static func facing_from_dir(d: int) -> String:
	match d:
		4:
			return "left"
		6:
			return "right"
		8:
			return "back"
		_:
			return "front"


static func dir_from_facing(facing: String) -> int:
	match facing:
		"left":
			return 4
		"right":
			return 6
		"back":
			return 8
		_:
			return 2


static func reverse_dir(d: int) -> int:
	match d:
		2:
			return 8
		4:
			return 6
		6:
			return 4
		8:
			return 2
		_:
			return 2
