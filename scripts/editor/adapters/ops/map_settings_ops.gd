extends RefCounted
## Domain ops: map settings (settings/tileset/layers/regions/bookmarks/reference/weather).

var ctrl
func _init(c):
	ctrl = c

const MapExt = preload("res://scripts/map/map_ext.gd")

func set_map_settings(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	var p = ctrl.pack()
	if d == null:
		return ctrl.mcp._err("no map")
	if args.has("name"):
		var nm = str(args.get("name", "")).strip_edges()
		if nm != "" and p and p.has_method("rename_map"):
			p.rename_map(str(d.map_id), nm)
		elif nm != "":
			d.display_name = nm
			d.dirty = true
	if args.has("bgm"):
		d.bgm = str(args.get("bgm", ""))
		d.dirty = true
	if args.has("light_preset"):
		d.light_preset = int(args.get("light_preset", 0))
		d.dirty = true
		if ctrl.ed() and ctrl.ed().has_method("_apply_editor_light"):
			ctrl.ed()._apply_editor_light()
			ctrl.ed()._sync_light_controls()
	if args.has("light_fx_color"):
		d.light_fx_color = ctrl._parse_color(args.get("light_fx_color"), d.light_fx_color)
		d.dirty = true
		if ctrl.ed() and ctrl.ed().has_method("_apply_editor_fx_color"):
			ctrl.ed()._apply_editor_fx_color()
			ctrl.ed()._sync_fx_color_controls()
	if args.has("start_x") or args.has("start_y"):
		d.start_cell = Vector2i(
			clampi(int(args.get("start_x", d.start_cell.x)), 0, int(d.width) - 1),
			clampi(int(args.get("start_y", d.start_cell.y)), 0, int(d.height) - 1)
		)
		d.dirty = true
		if ctrl.ed() and ctrl.ed().get("map_field"):
			ctrl.ed().map_field.edit_start_cell = d.start_cell
	if args.has("tileset_id"):
		set_map_tileset({"tileset_id": args.get("tileset_id")})
	if args.has("water_through"):
		d.water_through = bool(args.get("water_through"))
		d.dirty = true
	if args.has("environment") or args.has("indoor"):
		if args.has("environment"):
			d.environment = MapExt.normalize_environment(args.get("environment"))
		else:
			d.environment = MapExt.normalize_environment(args.get("indoor"))
		d.dirty = true
	if args.has("far_scroll_x") or args.has("far_scroll_y"):
		d.far_scroll = Vector2(float(args.get("far_scroll_x", d.far_scroll.x)), float(args.get("far_scroll_y", d.far_scroll.y)))
		d.dirty = true
	if bool(args.get("start_map", false)) and p:
		p.start_map = str(d.map_id)
		p.dirty = true
	if p:
		p.dirty = true
	ctrl._persist()
	return ctrl.dispatch("get_map_settings", {})



func set_map_tileset(args: Dictionary) -> Dictionary:
	var p = ctrl.pack()
	var d = ctrl.doc()
	if p == null or d == null:
		return ctrl.mcp._err("no map")
	var ts = str(args.get("tileset_id", args.get("tileset", ""))).strip_edges()
	if ts == "" or not p.tilesets.has(ts):
		return ctrl.mcp._err("unknown tileset")
	p.set_map_tileset(str(d.map_id), ts)
	ctrl._persist()
	if ctrl.ed() and ctrl.ed().has_method("_sync_palette"):
		ctrl.ed()._sync_palette()
	if ctrl.ed() and ctrl.ed().has_method("_reload_field"):
		ctrl.ed()._reload_field()
	return ctrl.mcp._ok({"tileset_id": ts, "map_id": str(d.map_id)})



func set_layer(args: Dictionary) -> Dictionary:
	var paint = ctrl._ensure_paint()
	if args.has("ext") and str(args.get("ext", "")).strip_edges() != "":
		var ext = str(args.get("ext", "")).strip_edges()
		if MapExt.LAYER_IDS.find(ext) < 0:
			return ctrl.mcp._err("unknown ext layer")
		paint.layer_z = -1
		paint.ext_layer = ext
	elif args.has("z"):
		paint.layer_z = clampi(int(args.get("z", 0)), 0, 5)
		paint.ext_layer = ""
	else:
		return ctrl.mcp._err("z or ext required")
	return ctrl.mcp._ok({"z": paint.layer_z, "ext": str(paint.ext_layer)})



func set_layer_visible(args: Dictionary) -> Dictionary:
	var field = ctrl.ed().get("map_field") if ctrl.ed() else null
	if field == null:
		return ctrl.mcp._err("no map field")
	var vis = bool(args.get("visible", true))
	if args.has("ext") and str(args.get("ext", "")) != "":
		field.set_layer_hidden_ext(str(args.get("ext")), not vis)
		return ctrl.mcp._ok({"ext": str(args.get("ext")), "visible": vis})
	var z = int(args.get("z", 0))
	field.set_layer_hidden_z(z, not vis)
	return ctrl.mcp._ok({"z": z, "visible": vis})



func add_bookmark(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	if not ("bookmarks" in d):
		d.bookmarks = []
	var c: Vector2i = ctrl.mcp._cursor()
	var bm = {
		"name": str(args.get("name", "")).strip_edges(),
		"x": int(args.get("x", c.x)),
		"y": int(args.get("y", c.y)),
	}
	if str(bm["name"]) == "":
		return ctrl.mcp._err("name required")
	d.bookmarks.append(bm)
	d.dirty = true
	return ctrl.mcp._ok({"bookmark": bm})



func list_bookmarks(_args := {}) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var bms: Array = d.bookmarks if "bookmarks" in d else []
	return ctrl.mcp._ok({"bookmarks": bms})



func goto_bookmark(args: Dictionary) -> Dictionary:
	var name = str(args.get("name", "")).strip_edges()
	for bm in list_bookmarks().get("bookmarks", []):
		if typeof(bm) == TYPE_DICTIONARY and str(bm.get("name", "")) == name:
			ctrl.mcp.call_tool("set_cursor", {"x": int(bm.get("x", 0)), "y": int(bm.get("y", 0))})
			return ctrl.mcp._ok({"bookmark": bm})
	return ctrl.mcp._err("bookmark not found")



func add_region(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	if not ("regions" in d):
		d.regions = []
	var r = {
		"name": str(args.get("name", "")).strip_edges(),
		"x": int(args.get("x", 0)),
		"y": int(args.get("y", 0)),
		"w": maxi(int(args.get("w", 1)), 1),
		"h": maxi(int(args.get("h", 1)), 1),
	}
	d.regions.append(r)
	d.dirty = true
	return ctrl.mcp._ok({"region": r})



func list_regions(_args := {}) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	return ctrl.mcp._ok({"regions": d.regions if "regions" in d else []})



func set_reference(args: Dictionary) -> Dictionary:
	var field = ctrl.ed().get("map_field") if ctrl.ed() else null
	if field == null:
		return ctrl.mcp._err("no map field")
	var path = str(args.get("path", "")).strip_edges()
	var alpha = clampf(float(args.get("alpha", 0.35)), 0.0, 1.0)
	if field.has_method("set_reference_image"):
		field.set_reference_image(path, alpha)
	return ctrl.mcp._ok({"path": path, "alpha": alpha})



func set_layer_alpha(args: Dictionary) -> Dictionary:
	var field = ctrl.ed().get("map_field") if ctrl.ed() else null
	if field == null or not field.has_method("set_bucket_alpha"):
		return ctrl.mcp._err("no map field")
	var a = clampf(float(args.get("alpha", 1)), 0.0, 1.0)
	field.set_bucket_alpha(str(args.get("bucket", "Ground")), a)
	return ctrl.mcp._ok({"bucket": str(args.get("bucket")), "alpha": a})



func set_weather_preview(args: Dictionary) -> Dictionary:
	var e = ctrl.ed()
	if e == null:
		return ctrl.mcp._err("no editor")
	var Weather = load("res://scripts/map/weather.gd")
	var kind: String = Weather.normalize(str(args.get("kind", "clear")))
	var inten = clampf(float(args.get("intensity", 0.8)), 0.0, 1.0)
	if kind == "clear":
		inten = 0.0
	e._preview_weather = kind
	e._preview_weather_i = inten
	if e.get("_weather_bar") != null:
		var bar: OptionButton = e._weather_bar
		for i in range(bar.item_count):
			if str(bar.get_item_metadata(i)) == kind:
				bar.select(i)
				break
	if e.has_method("_apply_editor_atmosphere"):
		e._apply_editor_atmosphere()
	elif e.has_method("_apply_editor_light"):
		e._apply_editor_light()
	return ctrl.dispatch("get_weather", {})

func op_names() -> Array:
	return ["set_map_settings", "set_map_tileset", "set_layer", "set_layer_visible", "set_layer_alpha", "set_reference", "set_weather_preview", "add_region", "list_regions", "add_bookmark", "list_bookmarks", "goto_bookmark"]

func tools() -> Array:
	return [
		ctrl.mcp._tool("set_map_settings", "改地图设置。environment: outdoor|indoor；或 indoor: bool。", {
			"name": {"type": "string"}, "bgm": {"type": "string"},
			"light_preset": {"type": "integer"},
			"light_fx_color": {"type": "string", "description": "#rrggbb 或 r,g,b"},
			"start_x": {"type": "integer"}, "start_y": {"type": "integer"},
			"tileset_id": {"type": "string"}, "start_map": {"type": "boolean"},
			"water_through": {"type": "boolean"},
			"far_scroll_x": {"type": "number"}, "far_scroll_y": {"type": "number"},
			"environment": {"type": "string", "description": "outdoor|indoor"},
			"indoor": {"type": "boolean"},
		}),
		ctrl.mcp._tool("set_map_tileset", "当前地图换图块套。", {"tileset_id": {"type": "string"}}, ["tileset_id"]),
		ctrl.mcp._tool("set_layer", "当前绘制层。z: 0-5 或 ext: far|water|roof|light|…", {
			"z": {"type": "integer"}, "ext": {"type": "string"},
		}),
		ctrl.mcp._tool("set_layer_visible", "显示/隐藏图层（仅预览）。", {
			"z": {"type": "integer"}, "ext": {"type": "string"}, "visible": {"type": "boolean"},
		}),
		ctrl.mcp._tool("set_layer_alpha", "预览桶透明度。bucket: Ground|Upper|Roof|Below|Fx", {
			"bucket": {"type": "string"}, "alpha": {"type": "number"},
		}, ["bucket"]),
		ctrl.mcp._tool("set_reference", "参考图半透明叠在地图上。path 空则清除。", {
			"path": {"type": "string"}, "alpha": {"type": "number"},
		}),
		ctrl.mcp._tool("add_region", "命名区域。", {
			"name": {"type": "string"},
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
		}, ["name", "x", "y"]),
		ctrl.mcp._tool("list_regions", "列出区域。", {}),
		ctrl.mcp._tool("add_bookmark", "书签。", {
			"name": {"type": "string"}, "x": {"type": "integer"}, "y": {"type": "integer"},
		}, ["name"]),
		ctrl.mcp._tool("list_bookmarks", "列出书签。", {}),
		ctrl.mcp._tool("goto_bookmark", "跳到书签。", {"name": {"type": "string"}}, ["name"]),
	]
