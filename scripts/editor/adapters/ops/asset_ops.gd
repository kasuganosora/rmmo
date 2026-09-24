extends RefCounted
## Domain ops: assets (import_asset).

var _owner: WeakRef
var ctrl:
	get:
		return _owner.get_ref()
func _init(c):
	_owner = weakref(c)

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
	return ["import_asset", "configure_tileset"]


func configure_tileset(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	if p == null:
		return ctrl.mcp._err("no pack")
	var id := str(args.get("tileset_id", "")).strip_edges().to_lower()
	if id.is_empty() or not id.is_valid_identifier():
		return ctrl.mcp._err("tileset_id must be an identifier")
	var names: Variant = args.get("sheets", null)
	if typeof(names) != TYPE_ARRAY or names.size() != 9:
		return ctrl.mcp._err("sheets must contain exactly 9 MV slots (A1-A5, B-E)")
	for sheet in names:
		if typeof(sheet) != TYPE_STRING or "/" in sheet or "\\" in sheet or ".." in sheet:
			return ctrl.mcp._err("sheet names must be asset identifiers")
	var extra: Variant = args.get("extra_sheets", [])
	if typeof(extra) != TYPE_ARRAY or extra.size() > 64:
		return ctrl.mcp._err("extra_sheets must contain at most 64 page identifiers")
	for sheet in extra:
		if typeof(sheet) != TYPE_STRING or sheet.is_empty() or "/" in sheet or "\\" in sheet or ".." in sheet:
			return ctrl.mcp._err("invalid extra sheet identifier")
	var flags: Variant = args.get("flags", null)
	if flags != null:
		if typeof(flags) != TYPE_ARRAY or flags.size() < 8192 or flags.size() > 32768:
			return ctrl.mcp._err("flags must contain 8192 MV flags, optionally extended up to 32768")
		for flag in flags:
			if typeof(flag) not in [TYPE_INT, TYPE_FLOAT] or float(flag) != floor(float(flag)) or int(flag) < 0 or int(flag) > 65535:
				return ctrl.mcp._err("invalid MV flag")
	var created: bool = not p.tilesets.has(id)
	if args.has("building_kits") and typeof(args.building_kits)!=TYPE_DICTIONARY:
		return ctrl.mcp._err("building_kits must be a dictionary")
	var profile: Variant = args.get("render_profile", null)
	if profile != null:
		if typeof(profile) != TYPE_DICTIONARY:
			return ctrl.mcp._err("render_profile must be a dictionary")
		for channel in ([] if profile.is_empty() else ["normal_sheets", "height_sheets", "emission_sheets"]):
			if channel == "emission_sheets" and not profile.has(channel):continue
			var pages: Variant = profile.get(channel, [])
			if typeof(pages) != TYPE_ARRAY or pages.size() != 9 + extra.size():
				return ctrl.mcp._err("render profile channels must match sheet count")
			for page in pages:
				if typeof(page) != TYPE_STRING or "/" in page or "\\" in page or ".." in page:
					return ctrl.mcp._err("render profile sheets must be asset identifiers")
	if created:
		id = p.create_tileset(id, str(args.get("name", id)))
	elif args.has("name"):
		p.rename_tileset(id, str(args.name))
	for slot in range(9):
		p.set_tileset_slot(id, slot, names[slot])
	if args.has("extra_sheets"):
		p.tilesets[id]["extraSheets"] = extra.duplicate()
	if flags != null:
		p.tilesets[id]["flags"] = flags.duplicate()
	if profile != null:
		p.tilesets[id]["renderProfile"] = profile.duplicate(true)
	if args.has("building_kits"):
		p.tilesets[id]["buildingKits"] = args.building_kits.duplicate(true)
	p.dirty = true
	if not p.save_dir():
		return ctrl.mcp._err("tileset configured in memory but save failed")
	if ctrl.ed() and ctrl.ed().has_method("_sync_palette"):
		ctrl.ed()._sync_palette()
	if ctrl.ed() and ctrl.ed().has_method("_reload_field"):
		ctrl.ed()._reload_field()
	return ctrl.mcp._ok({"tileset_id": id, "created": created, "saved": true})

func tools() -> Array:
	return [
		ctrl.mcp._tool("configure_tileset", "Create/update a pack tileset with 9 MV sheet slots and optional full passage flags. Validates all inputs before mutation; saves and refreshes the editor.", {
			"tileset_id": {"type": "string"}, "name": {"type": "string"},
			"sheets": {"type": "array"}, "flags": {"type": "array"},
			"extra_sheets": {"type": "array", "description": "Optional 768x768 baked curve pages, tile IDs 16384 + page*256 + MV sheet-cell index"},
			"render_profile": {"type": "object", "description": "Optional normal/height sheet channels, sunlight, shadows and fountain effects"},
			"building_kits": {"type":"object","description":"Reusable parameterized architectural component kits"},
		}, ["tileset_id", "sheets"]),
		ctrl.mcp._tool("import_asset", "导入素材文件。kind: charset|faces|tilesheet|audio/bgm|…", {
			"path": {"type": "string"}, "kind": {"type": "string"},
		}, ["path", "kind"]),
	]
