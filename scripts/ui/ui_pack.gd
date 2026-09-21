extends RefCounted
## Load UI chrome from the external ui pack (`content://ui/{skin}/{path}`).
## Never ResourceLoader / res:// for these PNGs.

static var _tex_cache: Dictionary = {}


static func tex(rel: String) -> Texture2D:
	rel = rel.strip_edges().lstrip("/").replace("\\", "/")
	if rel.is_empty():
		return null
	if _tex_cache.has(rel):
		return _tex_cache[rel] as Texture2D
	var t: Texture2D = null
	var am = _am()
	if am != null and am.has_method("load_texture"):
		t = am.load_texture("content://ui/%s" % rel)
	_tex_cache[rel] = t
	return t


static func has(rel: String) -> bool:
	return tex(rel) != null


static func _am():
	var loop = Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("AssetManager")
