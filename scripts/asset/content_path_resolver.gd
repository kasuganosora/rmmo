extends RefCounted
## Domain module: content:// -> filesystem path resolution — map/ui pack dirs, charset /
## tilesheet / look / ui / assets-kind paths, pack-by-content-id lookup, dependency
## collection and filesystem-path normalization. content.json config + caches stay on
## the AssetManager (ctrl); this module owns the resolution rules (the extension point
## for new content kinds / pack layouts).

var ctrl
func _init(c):
	ctrl = c

const ContentRef = preload("res://scripts/asset/content_ref.gd")

func _pack_dir_with_json(base: String) -> String:
	if ctrl._pack_json_exists(base):
		return base
	if not DirAccess.dir_exists_absolute(base):
		return ""
	var d := DirAccess.open(base)
	if d == null:
		return ""
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			var cand := "%s/%s" % [base, name]
			if ctrl._pack_json_exists(cand):
				return cand
		name = d.get_next()
	return ""

func default_map_pack_path() -> String:
	var v: String = ctrl.start_map_pack_id()
	if ctrl._pack_json_exists(v):
		return v
	var from_id: String = ctrl._resolve_map_pack_dir(v, "")
	if ctrl._pack_json_exists(from_id):
		return from_id
	from_id = ctrl._resolve_map_pack_dir(ctrl.DEFAULT_PACK_ID, "")
	if ctrl._pack_json_exists(from_id):
		return from_id
	return from_id

func resolve_map_pack_path(pack_path_or_id: String) -> String:
	var s := pack_path_or_id.strip_edges()
	if s.is_empty():
		return ctrl.default_map_pack_path()
	if s.begins_with("content:") or s.begins_with(ContentRef.SCHEME):
		var cr = ContentRef.parse(s)
		if cr.is_valid() and cr.kind == "map_pack":
			var resolved: String = ctrl._resolve_map_pack_dir(cr.id, cr.version)
			if ctrl._pack_json_exists(resolved):
				return ctrl._prefer_res_if_project(resolved)
			return resolved
		# content:// without kind treated as map_pack id
		if cr.is_valid():
			var r2: String = ctrl._resolve_map_pack_dir(cr.id, cr.version)
			if ctrl._pack_json_exists(r2):
				return ctrl._prefer_res_if_project(r2)
	if ctrl._pack_json_exists(s):
		return s
	var glob := ProjectSettings.globalize_path(s) if s.begins_with("res://") else s
	if ctrl._pack_json_exists(glob):
		return s if s.begins_with("res://") else glob
	# Bare id / content_id
	var from_id: String = ctrl._resolve_map_pack_dir(s, "")
	if ctrl._pack_json_exists(from_id):
		return ctrl._prefer_res_if_project(from_id)
	for candidate in ["res://%s" % s, "res://%s_map" % s]:
		if ctrl._pack_json_exists(candidate):
			return candidate
	return s

func collect_map_pack_deps(pack_dir: String) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	var dir: String = ctrl.resolve_map_pack_path(pack_dir)
	var pack_json_path := "%s/pack.json" % dir
	var pack_data: Dictionary = ctrl.load_json_file(pack_json_path)
	if pack_data.is_empty():
		var glob := ProjectSettings.globalize_path(pack_json_path)
		pack_data = ctrl.load_json_file(glob)
	var cid := str(pack_data.get("content_id", "")).strip_edges()
	var ver := str(pack_data.get("version", "")).strip_edges()
	if cid != "":
		ctrl._add_dep(out, seen, ContentRef.make("map_pack", cid, ver))
	else:
		# Ensure the pack directory itself as a filesystem ref for Gate
		ctrl._add_dep(out, seen, dir)

	var deps_v: Variant = pack_data.get("deps", [])
	if typeof(deps_v) == TYPE_ARRAY:
		for d in deps_v:
			if typeof(d) == TYPE_DICTIONARY:
				var dd: Dictionary = d
				var kind := str(dd.get("kind", "charset")).strip_edges()
				var id := str(dd.get("id", "")).strip_edges()
				var dv := str(dd.get("version", "")).strip_edges()
				if id != "":
					ctrl._add_dep(out, seen, ContentRef.make(kind, id, dv))
			else:
				var ds := str(d).strip_edges()
				if ds.is_empty():
					continue
				if ds.begins_with("content:"):
					ctrl._add_dep(out, seen, ds)
				else:
					ctrl._add_dep(out, seen, ContentRef.make("charset", ds))

	# Auto from npcs.json / pack npcs
	var npcs_rel := str(pack_data.get("npcs_file", "npcs.json")).strip_edges()
	if npcs_rel == "":
		npcs_rel = "npcs.json"
	var npcs_data: Dictionary = ctrl.load_json_file("%s/%s" % [dir, npcs_rel])
	var npcs_list: Array = []
	if not npcs_data.is_empty():
		var nv: Variant = npcs_data.get("npcs", [])
		if typeof(nv) == TYPE_ARRAY:
			npcs_list = nv
	elif typeof(pack_data.get("npcs", null)) == TYPE_ARRAY:
		npcs_list = pack_data.get("npcs", [])
	for item in npcs_list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var cs := str(item.get("charset", "")).strip_edges()
		if cs != "":
			ctrl._add_dep(out, seen, ContentRef.make("charset", cs))
	return out

func _add_dep(out: Array[String], seen: Dictionary, ref: String) -> void:
	ref = ref.strip_edges()
	if ref.is_empty() or seen.has(ref):
		return
	seen[ref] = true
	out.append(ref)

func _resolve_charset_path(charset_id: String) -> String:
	## Order: assets/charset → content_root/characters → charset_root → mv_img/characters → exe data → legacy.
	var id := charset_id.strip_edges()
	if id.to_lower().ends_with(".png"):
		id = id.substr(0, id.length() - 4)
	var file_name := "%s.png" % id
	var candidates: Array[String] = []
	candidates.append("%s/assets/charset/%s" % [ctrl.content_root(), file_name])
	candidates.append("%s/characters/%s" % [ctrl.content_root(), file_name])
	if ProjectSettings.has_setting("rmmo/charset_root"):
		var root := str(ProjectSettings.get_setting("rmmo/charset_root", "")).strip_edges().rstrip("/").rstrip("\\")
		if root != "":
			candidates.append("%s/%s" % [root, file_name])
	var mv: String = ctrl.mv_img_root()
	if mv != "":
		candidates.append("%s/characters/%s" % [mv, file_name])
	candidates.append("%s/data/characters/%s" % [OS.get_executable_path().get_base_dir(), file_name])
	candidates.append("D:/code/rmmo_runtime/characters/%s" % file_name)
	for c in candidates:
		var hit: String = ctrl._existing_file(c)
		if hit != "":
			return hit
	return candidates[0]  # expected path even if missing

func _resolve_tilesheet_path(sheet_name: String) -> String:
	var name := sheet_name.strip_edges()
	if name.to_lower().ends_with(".png"):
		name = name.substr(0, name.length() - 4)
	var file_name := "%s.png" % name
	var candidates: Array[String] = []
	candidates.append("%s/assets/tilesheet/%s" % [ctrl.content_root(), file_name])
	var mv: String = ctrl.mv_img_root()
	if mv != "":
		candidates.append("%s/tilesets/%s" % [mv, file_name])
	for c in candidates:
		var hit: String = ctrl._existing_file(c)
		if hit != "":
			return hit
	return candidates[0]

func _existing_file(p: String) -> String:
	if p.is_empty():
		return ""
	if FileAccess.file_exists(p):
		return p
	var alt := p.replace("/", "\\")
	if alt != p and FileAccess.file_exists(alt):
		return alt
	var alt2 := p.replace("\\", "/")
	if alt2 != p and FileAccess.file_exists(alt2):
		return alt2
	return ""

func _resolve_map_pack_dir(pack_id: String, version: String) -> String:
	var root: String = ctrl.content_root()
	var ids: Array[String] = []
	var raw: String = ctrl._strip_pack_token(pack_id)
	var aliased: String = ctrl.alias_map_pack_id(pack_id)
	for x in [raw, aliased, raw.get_file()]:
		var id := str(x).strip_edges()
		if id != "" and id not in ids:
			ids.append(id)
	for id in ids:
		var bases: Array[String] = [
			"%s/packs/map_pack/%s" % [root, id],
			"%s/packs/%s" % [root, id],
			ProjectSettings.globalize_path("user://content/packs/%s" % id),
		]
		for base0 in bases:
			var base: String = str(base0)
			if version != "":
				var vdir := "%s/%s" % [base, version]
				if ctrl._pack_json_exists(vdir):
					return vdir
			if ctrl._pack_json_exists(base):
				return base
			if DirAccess.dir_exists_absolute(base):
				var d := DirAccess.open(base)
				if d:
					d.list_dir_begin()
					var name := d.get_next()
					while name != "":
						if d.current_is_dir() and not name.begins_with("."):
							var cand := "%s/%s" % [base, name]
							if ctrl._pack_json_exists(cand):
								return cand
						name = d.get_next()
	var by_cid: String = ctrl._find_pack_by_content_id(pack_id)
	if by_cid != "":
		return by_cid
	return "%s/packs/map_pack/%s" % [root, aliased]

func _find_pack_by_content_id(content_id: String) -> String:
	content_id = ctrl.alias_map_pack_id(content_id)
	if content_id.is_empty():
		return ""
	var root := "%s/packs/map_pack" % ctrl.content_root()
	if not DirAccess.dir_exists_absolute(root):
		return ""
	var d := DirAccess.open(root)
	if d == null:
		return ""
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			var base := "%s/%s" % [root, name]
			var hit := base if ctrl._pack_json_exists(base) else ""
			if hit == "":
				var d2 := DirAccess.open(base)
				if d2:
					d2.list_dir_begin()
					var ver := d2.get_next()
					while ver != "":
						if d2.current_is_dir() and not ver.begins_with("."):
							var cand := "%s/%s" % [base, ver]
							if ctrl._pack_json_exists(cand):
								hit = cand
								break
						ver = d2.get_next()
			if hit != "":
				var data: Dictionary = ctrl.load_json_file("%s/pack.json" % hit)
				var cid := str(data.get("content_id", data.get("id", ""))).strip_edges()
				if cid == content_id or name == content_id:
					return hit
		name = d.get_next()
	return ""

func _resolve_look_path(look_id: String) -> String:
	return ctrl._resolve_assets_kind_path("look", look_id)

func _resolve_ui_pack_dir(pack_id: String = "", version: String = "") -> String:
	if pack_id.strip_edges() == "":
		pack_id = ctrl.ui_pack_id()
	var root: String = ctrl.content_root()
	var bases: Array[String] = [
		"%s/packs/ui/%s" % [root, pack_id],
		"%s/packs/ui_pack/%s" % [root, pack_id],
	]
	for base0 in bases:
		var base: String = str(base0)
		if version != "":
			var vdir := "%s/%s" % [base, version]
			if ctrl._pack_json_exists(vdir):
				return vdir
		if ctrl._pack_json_exists(base):
			return base
		if DirAccess.dir_exists_absolute(base):
			var d := DirAccess.open(base)
			if d:
				d.list_dir_begin()
				var name := d.get_next()
				while name != "":
					if d.current_is_dir() and not name.begins_with("."):
						var cand := "%s/%s" % [base, name]
						if ctrl._pack_json_exists(cand):
							return cand
					name = d.get_next()
	return bases[0]

func _resolve_ui_path(asset_id: String) -> String:
	asset_id = asset_id.strip_edges().lstrip("/").replace("\\", "/")
	var pack_dir: String = ctrl._resolve_ui_pack_dir("", "")
	var candidates: Array[String] = []
	if pack_dir != "":
		candidates.append("%s/%s" % [pack_dir.rstrip("/").rstrip("\\"), asset_id])
	candidates.append("%s/assets/ui/%s" % [ctrl.content_root(), asset_id])
	for c in candidates:
		var hit: String = ctrl._existing_file(c)
		if hit != "":
			return hit
		if not c.to_lower().ends_with(".png"):
			hit = ctrl._existing_file("%s.png" % c)
			if hit != "":
				return hit
	return candidates[0] if not candidates.is_empty() else ""

func _resolve_assets_kind_path(kind: String, asset_id: String) -> String:
	asset_id = asset_id.strip_edges().lstrip("/").replace("\\", "/")
	var bare := "%s/assets/%s/%s" % [ctrl.content_root(), kind.strip_edges(), asset_id]
	var with_png := bare if bare.to_lower().ends_with(".png") else ("%s.png" % bare)
	var hit: String = ctrl._existing_file(with_png)
	if hit != "":
		return hit
	hit = ctrl._existing_file(bare)
	if hit != "":
		return hit
	return with_png

func _pack_json_exists(dir_path: String) -> bool:
	if dir_path.is_empty():
		return false
	if FileAccess.file_exists("%s/pack.json" % dir_path):
		return true
	var glob := ProjectSettings.globalize_path(dir_path) if dir_path.begins_with("res://") else dir_path
	return FileAccess.file_exists("%s/pack.json" % glob)

func _prefer_res_if_project(abs_or_res: String) -> String:
	if abs_or_res.begins_with("res://"):
		return abs_or_res
	var project_res := ProjectSettings.globalize_path("res://").rstrip("/").rstrip("\\")
	var norm := abs_or_res.replace("\\", "/")
	var proj := project_res.replace("\\", "/")
	# Require a directory boundary so D:/code/rmmo_runtime is not treated as res://.
	if norm == proj or norm.begins_with(proj + "/"):
		var rel := norm.substr(proj.length()).lstrip("/")
		return "res://%s" % rel
	return abs_or_res

func _is_filesystem_pack_or_file(ref: String) -> bool:
	if ref.begins_with("res://") or ref.begins_with("user://"):
		return true
	if ref.begins_with("/") or ref.begins_with("\\"):
		return true
	# Windows drive
	if ref.length() >= 3 and ref[1] == ":" and (ref[2] == "/" or ref[2] == "\\"):
		return true
	return false

func _normalize_fs_path(ref: String) -> String:
	return ref.rstrip("/").rstrip("\\")
