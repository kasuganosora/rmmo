extends RefCounted
## JSON helpers (shared; avoid rewriting per catalog / loader).


## Absolute `{content_root}/data/{rel}` (catalogs, map presets, RTP tables).
static func data_path(rel: String) -> String:
	rel = rel.strip_edges().replace("\\", "/").lstrip("/")
	if rel.begins_with("data/"):
		rel = rel.substr(5)
	var am = _am()
	if am != null and am.has_method("data_file"):
		return str(am.data_file(rel))
	for root in ["D:/code/rmmo_runtime", "/workspace/rmmo_runtime"]:
		if DirAccess.dir_exists_absolute(root):
			return "%s/data/%s" % [root, rel]
	return rel


static func parse_data(rel: String) -> Variant:
	return parse_file(data_path(rel))


## Parse a JSON file. Returns the parsed Variant, or null if missing/unreadable.
static func parse_file(path: String) -> Variant:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)


## First existing path whose contents parse as a Dictionary wins; else null.
## Relative entries are resolved as `{content_root}/data/{rel}`.
static func load_first(paths: Array) -> Variant:
	for p in paths:
		var path := str(p).strip_edges()
		if path.is_empty():
			continue
		if not path.contains("://") and not path.is_absolute_path():
			path = data_path(path)
		var parsed: Variant = parse_file(path)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return null


static func _am():
	var loop = Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("AssetManager")
