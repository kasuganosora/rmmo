extends RefCounted
## JSON helpers (shared; avoid rewriting per catalog / loader).


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
static func load_first(paths: Array) -> Variant:
	for p in paths:
		var parsed: Variant = parse_file(str(p))
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return null
