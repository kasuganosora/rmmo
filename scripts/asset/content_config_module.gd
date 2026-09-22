extends RefCounted
## Domain module: content.json config accessors — start/street/ui pack ids + refs,
## spawn cells, alias table build/scan and pack-id token stripping. Config state
## (_content_cfg / _pack_aliases) lives on the AssetManager (ctrl); this module owns
## the content.json interpretation rules.

var ctrl
func _init(c):
	ctrl = c

const ContentRef = preload("res://scripts/asset/content_ref.gd")

func content_config() -> Dictionary:
	ctrl._ensure_content_cfg()
	return ctrl._content_cfg

func start_map_pack_id() -> String:
	ctrl._ensure_content_cfg()
	var id := str(ctrl._content_cfg.get("start_map_pack", "")).strip_edges()
	if id.is_empty():
		id = str(ProjectSettings.get_setting("rmmo/default_pack", "")).strip_edges()
	if id.is_empty() or id.begins_with("res://"):
		id = ctrl.DEFAULT_PACK_ID
	return ctrl.alias_map_pack_id(id)

func start_map_pack_ref() -> String:
	return ContentRef.make("map_pack", ctrl.start_map_pack_id())

func street_map_pack_id() -> String:
	ctrl._ensure_content_cfg()
	var id := str(ctrl._content_cfg.get("street_map_pack", "")).strip_edges()
	if id.is_empty():
		id = ctrl.start_map_pack_id()
	return ctrl.alias_map_pack_id(id)

func street_map_pack_ref() -> String:
	return ContentRef.make("map_pack", ctrl.street_map_pack_id())

func street_map_id() -> String:
	ctrl._ensure_content_cfg()
	var id := str(ctrl._content_cfg.get("street_map_id", "")).strip_edges()
	if id.is_empty():
		id = ctrl.street_map_pack_id()
	return id

func street_spawn_cell() -> Vector2i:
	return ctrl._cfg_cell("street_spawn")

func start_spawn_cell() -> Vector2i:
	return ctrl._cfg_cell("start_spawn")

func _cfg_cell(key: String) -> Vector2i:
	ctrl._ensure_content_cfg()
	var d: Variant = ctrl._content_cfg.get(key, {})
	if typeof(d) == TYPE_DICTIONARY:
		return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
	return Vector2i.ZERO

func ui_pack_id() -> String:
	ctrl._ensure_content_cfg()
	var id := str(ctrl._content_cfg.get("ui_pack", "")).strip_edges()
	if id.is_empty():
		id = str(ProjectSettings.get_setting("rmmo/ui_pack", "")).strip_edges()
	if id.is_empty():
		id = ctrl.DEFAULT_PACK_ID
	return id

func alias_map_pack_id(pack_id: String) -> String:
	var s: String = ctrl._strip_pack_token(pack_id)
	if s.is_empty():
		return s
	ctrl._ensure_content_cfg()
	if ctrl._pack_aliases.has(s):
		return str(ctrl._pack_aliases[s])
	return s

func _strip_pack_token(pack_id: String) -> String:
	var s := pack_id.strip_edges()
	if s.begins_with("res://"):
		s = s.substr(6)
	if s.begins_with(ContentRef.SCHEME):
		var cr = ContentRef.parse(s)
		if cr.is_valid():
			s = str(cr.id)
	s = s.rstrip("/")
	var at := s.rfind("@")
	if at >= 0:
		s = s.substr(0, at)
	if s.find("/") >= 0:
		s = s.get_file()
	return s

func _ensure_content_cfg() -> void:
	if ctrl._content_cfg_loaded:
		return
	ctrl._content_cfg_loaded = true
	ctrl._content_cfg = ctrl.load_json_file("%s/content.json" % ctrl.content_root())
	ctrl._pack_aliases.clear()
	var av: Variant = ctrl._content_cfg.get("aliases", {})
	if typeof(av) == TYPE_DICTIONARY:
		for k in (av as Dictionary).keys():
			var dst := str((av as Dictionary)[k]).strip_edges()
			if dst != "":
				ctrl._pack_aliases[str(k).strip_edges()] = dst
	ctrl._scan_pack_aliases()

func _scan_pack_aliases() -> void:
	var root := "%s/packs/map_pack" % ctrl.content_root()
	if not DirAccess.dir_exists_absolute(root):
		return
	var d := DirAccess.open(root)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			var hit: String = ctrl._pack_dir_with_json("%s/%s" % [root, name])
			if hit != "":
				var data: Dictionary = ctrl.load_json_file("%s/pack.json" % hit)
				var cid := str(data.get("content_id", "")).strip_edges()
				if cid != "" and cid != name and not ctrl._pack_aliases.has(cid):
					ctrl._pack_aliases[cid] = name
		name = d.get_next()
