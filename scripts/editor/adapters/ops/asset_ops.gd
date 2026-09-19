extends RefCounted
## Domain ops: assets (import_asset).

var ctrl
func _init(c):
	ctrl = c

func import_asset(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	if p == null:
		return ctrl.mcp._err("no pack")
	var path = str(args.get("path", "")).strip_edges()
	var kind = str(args.get("kind", "charset")).strip_edges()
	if path == "":
		return ctrl.mcp._err("path required")
	if p.root.is_empty() and p.has_method("save_dir"):
		p.save_dir()
	var id: String = p.import_asset_file(path, kind)
	if id == "":
		return ctrl.mcp._err("import failed")
	return ctrl.mcp._ok({"id": id, "kind": kind})

func op_names() -> Array:
	return ["import_asset"]

func tools() -> Array:
	return [
		ctrl.mcp._tool("import_asset", "导入素材文件。kind: charset|faces|tilesheet|audio/bgm|…", {
			"path": {"type": "string"}, "kind": {"type": "string"},
		}, ["path", "kind"]),
	]
