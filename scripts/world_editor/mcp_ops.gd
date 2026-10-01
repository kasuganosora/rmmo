extends RefCounted
const Schema = preload("res://scripts/world_editor/mcp_schema.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Prefabs = preload("res://scripts/world_editor/prefab_library.gd")
const Library = preload("res://scripts/world_editor/asset_library.gd")
const Catalog = preload("res://scripts/world_editor/resource_pack_catalog.gd")
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
var editor: Node3D

func ok(data: Dictionary = {}) -> Dictionary:
	return {"ok": true}.merged(data)

func error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func xyz(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

static func array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func state() -> Dictionary:
	return ok({"editor": "world3d", "map_path": editor._path, "units": "meters", "up_axis": "Y",
		"object_count": editor._doc.records.size(), "selection": editor._selection_tools.ids.duplicate(),
		"dirty": editor._dirty, "read_only": editor._load_failed, "undo_count": editor._doc._undo.size(), "redo_count": editor._doc._redo.size(),
		"editor_view": editor._authoring.settings.duplicate(true), "playtest":editor._playtest.state(), "spawn_picking":editor._authoring.picking,
		"transform_mode": ["move", "rotate", "scale"][editor._transform_mode], "space": "local" if editor._local_transform else "world",
		"effective_space": "world" if editor._selection_tools.ids.size() > 1 else ("local" if editor._local_transform or editor._transform_mode == 2 else "world"),
		"position_snap": editor._snap, "rotation_snap": editor._rotation_snap, "scale_snap": editor._scale_snap,
		"pivot": array3(editor._selection_tools.pivot()), "canvas_size": [editor._canvas.size.x, editor._canvas.size.y],
		"surface_placement_active": editor._placement_tools.active,
		"surface_brush_active": editor._material_tool.active,
		"autosave": editor._safety.state(),
		"camera_position": array3(editor._camera.position), "camera_rotation": array3(editor._camera.rotation_degrees)})

func execute(name: String, args: Dictionary) -> Dictionary:
	match name:
		"list_building_templates": return editor._buildings.templates()
		"list_buildings": return editor._buildings.list_buildings()
		"preview_buildings":
			var request: Dictionary = args.duplicate(true); request.erase("replace_id")
			return editor._buildings.summary(editor._buildings.prepare(request,str(args.get("replace_id",""))))
		"generate_buildings": return editor._buildings.generate(args)
		"preview_street_buildings": return editor._buildings.summary(editor._buildings.prepare_street(args))
		"generate_street_buildings": return editor._buildings.generate_street(args)
		"update_building": return editor._buildings.update(args.id,args.get("parameters",{}),args.get("position"),args.get("yaw"))
		"delete_building": return editor._buildings.remove(args.id)
		"detach_building": return editor._buildings.remove(args.id,true)
		"get_editor_view": return ok({"view": editor._authoring.settings.duplicate(true)})
		"set_floor_view": return editor._authoring.set_settings(args)
		"set_playtest_spawn": return editor._authoring.set_settings({"spawn":args.position})
		"pick_playtest_spawn": return editor._authoring.pick(Vector2(args.screen[0],args.screen[1]))
		"start_playtest": return editor._playtest.start(args.get("position"))
		"stop_playtest": return editor._playtest.stop()
		"playtest_state": return editor._playtest.state()
		"list_event_templates":
			var templates: Array = []
			var definitions = preload("res://scripts/world3d/event_templates.gd")
			for id in definitions.LABELS: templates.append({"id": id, "name": definitions.LABELS[id], "defaults": definitions.defaults(id)})
			return ok({"templates": templates, "parameters_schema": definitions.parameters_schema()})
		"list_event_resources":
			var resources: Dictionary = editor._gameplay.resources()
			var query := str(args.get("query", "")).to_lower()
			var items: Array = resources.items.filter(func(row): return query.is_empty() or (str(row.id) + str(row.name)).to_lower().contains(query))
			var shops: Array = resources.shops.filter(func(row): return query.is_empty() or (str(row.id) + str(row.name)).to_lower().contains(query))
			return ok({"items": page(items, args), "shops": page(shops, args), "item_total": items.size(), "shop_total": shops.size()})
		"create_event_template": return editor._gameplay.create_event(args.template, xyz(args.position), args.get("parameters", {}))
		"set_event_template": return editor._gameplay.set_event(args.id, args.get("template", ""), args.parameters)
		"clear_event_template": return editor._gameplay.clear_event(args.id)
		"get_environment": return ok({"environment": preload("res://scripts/world3d/environment_settings.gd").resolve(editor._doc.map_meta)})
		"set_environment": return editor._gameplay.set_environment(args)
		"list_auto_tile_kits": return ok({"kits": editor._auto_panel.library.entries()})
		"import_auto_tile_kit":
			var imported: Dictionary = editor._auto_panel.library.import_kit(args.path)
			if imported.ok: editor._auto_panel.refresh(imported.kit_id)
			return imported
		"list_surface_materials":
			var entries: Array = editor._material_tool.library.entries().filter(func(entry): return str(entry.material.name).to_lower().contains(str(args.get("query", "")).to_lower()))
			return ok({"materials": page(entries, args), "total": entries.size()})
		"import_surface_material":
			var result: Dictionary = editor._material_tool.library.import_texture(args.path, args.get("name", ""))
			if result.ok: editor._material_panel.refresh(result.material_id)
			return result
		"list_object_surfaces": return editor._material_tool.list_faces(args.id, int(args.get("offset", 0)), int(args.get("limit", 50)))
		"pick_surface": return editor._material_tool.pick(Vector2(args.screen[0], args.screen[1]))
		"paint_surface": return editor._material_tool.paint(args.id, args.target, args.material_id, args)
		"clear_surface_material": return editor._material_tool.clear_paint(args.id, args.get("target", {}))
		"editor_state": return state()
		"list_objects":
			var needle := str(args.get("query", "")).to_lower()
			var records: Array = editor._doc.records.filter(func(r): return needle.is_empty() or (Geometry.label(r) + " " + str(r.uuid) + " " + str(r.kind) + " " + str(r.get("editor_group_name", ""))).to_lower().contains(needle))
			var rows: Array = []
			for record in page(records, args):
				rows.append({"id": record.uuid, "name": Geometry.label(record), "kind": record.kind, "position": record.position, "rotation": record.rotation, "size": record.size,
					"group_id": record.get("editor_group", ""), "group_name": record.get("editor_group_name", ""), "hidden": record.get("editor_hidden", false), "locked": record.get("editor_locked", false), "in_current_floor":editor._authoring.includes(record)})
			return ok({"objects": rows, "total": records.size()})
		"get_object":
			var record: Dictionary = editor._doc._find(args.id)
			return error("Object not found") if record.is_empty() else ok({"record": record.duplicate(true)})
		"select_objects":
			if not args.has("ids") and not args.has("group_id"): return error("ids or group_id is required")
			var target := targets(args)
			if not target.ok: return target
			var selected: Array = editor._selection_tools.ids.duplicate() if args.get("append", false) else []
			for id in target.ids:
				if not selected.has(id): selected.append(id)
			if selected.size() > Schema.MAX_SELECTION: return error("Selection exceeds 256 objects")
			editor._selection_tools.set_ids(selected)
			editor._set_mode(1)
			return state()
		"select_rectangle":
			var from := Vector2(args.from[0], args.from[1])
			var to := Vector2(args.to[0], args.to[1])
			if from.x > editor._canvas.size.x or from.y > editor._canvas.size.y or to.x > editor._canvas.size.x or to.y > editor._canvas.size.y: return error("Rectangle is outside the canvas")
			var previous: Array = editor._selection_tools.ids.duplicate()
			editor._selection_tools.begin_box(from, args.get("append", false))
			editor._selection_tools.move_box(to)
			editor._selection_tools.finish_box()
			if editor._selection_tools.ids.size() > Schema.MAX_SELECTION:
				editor._selection_tools.set_ids(previous)
				return error("Selection exceeds 256 objects; use a smaller rectangle")
			editor._set_mode(1)
			return state()
		"configure_transform":
			if args.get("space") == "local" and editor._selection_tools.ids.size() > 1: return error("Multi-selection uses world axes")
			if args.has("mode"): editor._set_transform_mode(["move", "rotate", "scale"].find(args.mode))
			if args.has("space"): editor._local_transform = args.space == "local"
			if args.has("position_snap"): editor._snap = args.position_snap
			if args.has("rotation_snap"): editor._rotation_snap = args.rotation_snap
			if args.has("scale_snap"): editor._scale_snap = args.scale_snap
			for field in Schema.SNAP_VALUES:
				if args.has(field): editor._snap_controls[field].select(Schema.SNAP_VALUES[field].find(float(args[field])))
			editor._update_space_button()
			return state()
		"set_object_transform":
			var changes: Dictionary = args.duplicate(true)
			changes.erase("id")
			if changes.is_empty(): return error("At least one transform field is required")
			if not editor._selection_tools.set_object_transform(args.id, changes): return error("Object missing, hidden, locked or outside the active floor")
			return state()
		"transform_selection":
			var valid := targets({})
			if not valid.ok or valid.ids.is_empty(): return error("Select editable objects first")
			var delta := xyz(args.get("translation", [0, 0, 0]))
			var rotation := Basis.from_euler(xyz(args.get("rotation", [0, 0, 0])) * PI / 180)
			var factor := float(args.get("scale", 1.0))
			var pivot: Vector3 = editor._selection_tools.pivot()
			for record in editor._selection_tools.records():
				var position := pivot + rotation * ((Geometry.vector(record, "position") - pivot) * factor) + delta
				var size_ := Geometry.vector(record, "size") * factor
				if not position.is_finite() or not size_.is_finite() or position.abs()[position.abs().max_axis_index()] > 1000000 or size_[size_.min_axis_index()] < 0.001 or size_[size_.max_axis_index()] > 100000: return error("Resulting transform is outside supported bounds")
			editor._selection_tools.apply_transform(delta, rotation, factor)
			return state()
		"drop_selection": return editor._placement_tools.drop_selection(args.get("align_normal", false), args.get("max_distance", 100.0), args.get("offset", 0.0))
		"snap_selection_to_surface": return editor._placement_tools.snap_to_surface(Vector2(args.screen[0], args.screen[1]), args.get("align_normal", true), args.get("offset", 0.0))
		"align_selection": return editor._placement_tools.align_selection(["x", "y", "z"].find(args.axis), args.get("anchor", "center"))
		"distribute_selection": return editor._placement_tools.distribute_selection(["x", "y", "z"].find(args.axis), args.get("spacing", "gaps"))
		"group_selection", "ungroup_selection", "duplicate_selection", "delete_selection", "focus_selection":
			var valid := targets({})
			if not valid.ok or valid.ids.is_empty(): return error("Select editable objects first")
			match name:
				"group_selection":
					if valid.ids.size() < 2: return error("At least two objects are required")
					editor._selection_tools.group()
				"ungroup_selection":
					for record in editor._selection_tools.records():
						if record.has("editor_group") and editor._selection_tools.members(record.uuid).is_empty(): return error("Show and unlock every group member before ungrouping")
					editor._selection_tools.ungroup()
				"duplicate_selection": editor._duplicate_selected()
				"delete_selection": editor._selection_tools.remove()
				"focus_selection": editor._focus_selected()
			return state()
		"set_object_properties":
			var target := targets(args, true)
			if not target.ok: return target
			if target.ids.is_empty(): return error("No target objects")
			var properties := {}
			if args.has("name"):
				if str(args.name).strip_edges().is_empty(): return error("Name must not be empty")
				properties["editor_group_name" if args.has("group_id") else "editor_name"] = str(args.name).strip_edges()
			if args.has("hidden"): properties.editor_hidden = args.hidden
			if args.has("locked"): properties.editor_locked = args.locked
			if properties.is_empty(): return error("No properties supplied")
			if not editor._selection_tools.set_properties(target.ids, properties): return error("Cannot rename hidden, locked or off-floor objects")
			return ok({"affected_ids": target.ids, "selection": editor._selection_tools.ids.duplicate()})
		"list_assets":
			var entries := assets(str(args.get("query", "")))
			var rows: Array = []
			for entry in page(entries, args): rows.append({"asset_id": asset_id(entry), "name": entry.get("label", ""), "category": entry.get("category", ""), "prefab": entry.has("prefab_path"), "part_count": entry.get("part_count", 1), "auto_family": entry.get("auto_family", "")})
			return ok({"assets": rows, "total": entries.size()})
		"list_resource_packs": return ok({"packs": Catalog.new().packs()})
		"save_prefab": return save_prefab(args)
		"place_asset": return place_asset(args)
		"paint_auto_tiles": return paint(args)
		"undo":
			editor._undo()
			return state()
		"redo":
			editor._redo()
			return state()
		"save_world":
			var path := str(args.get("path", editor._path))
			if not allowed_path(path) or path.get_extension().to_lower() != "gltf": return error("Save path must be a .gltf file inside the external content root")
			var dependencies := validate_assets(editor._doc.records)
			if not dependencies.is_empty(): return error(dependencies)
			if not editor._save_to(path): return error(editor._status.text)
			return ok({"path": path, "saved": true})
		"open_world":
			var path: String = args.path
			if not allowed_path(path) or path.get_extension().to_lower() != "gltf" or not FileAccess.file_exists(path): return error("Open path must be an existing .gltf file inside the external content root")
			if editor._dirty and not args.get("discard_changes", false): return error("Unsaved changes: save first or explicitly set discard_changes")
			var checked := validate_map_file(path)
			if not checked.is_empty(): return error(checked)
			if not editor.open_document(path): return error(editor._status.text)
			return state()
		"configure_autosave": return editor._safety.configure(args.get("enabled", editor._safety.enabled), args.get("interval_seconds", editor._safety.interval_seconds))
		"list_editor_drafts": return editor._safety.store.list_drafts(int(args.get("offset", 0)), int(args.get("limit", 50)))
		"save_editor_draft": return editor._safety.save_draft()
		"restore_editor_draft": return editor._safety.restore(args.draft_id, args.get("discard_changes", false))
		"discard_editor_draft": return editor._safety.discard(args.draft_id)
		"close_editor":
			editor._safety._close_window = true
			return editor._safety.close_action(args.action)
		"preview_map":
			if DisplayServer.get_name() == "headless": return error("Preview requires a graphical renderer; use the background desktop host")
			var viewport: SubViewport = editor._playtest.viewport if editor._playtest.viewport != null else editor._canvas.get_child(0)
			var image := viewport.get_texture().get_image()
			if image == null or image.is_empty(): return error("No rendered frame yet")
			if image.get_width() > 1280: image.resize(1280, maxi(1, roundi(image.get_height() * 1280.0 / image.get_width())))
			return ok({"png_base64": Marshalls.raw_to_base64(image.save_png_to_buffer()), "width": image.get_width(), "height": image.get_height()})
	return error("Unsupported tool: " + name)

func targets(args: Dictionary, allow_protected: bool = false) -> Dictionary:
	if args.has("ids") and args.has("group_id"): return error("Choose ids or group_id, not both")
	var ids: Array = args.get("ids", editor._selection_tools.ids).duplicate()
	if args.has("group_id"):
		if str(args.group_id).is_empty(): return error("group_id must not be empty")
		ids.clear()
		for record in editor._doc.records:
			if record.get("editor_group", "") == args.group_id: ids.append(str(record.uuid))
		if ids.is_empty(): return error("Group not found")
	if ids.size() > Schema.MAX_SELECTION: return error("At most 256 objects per operation")
	for id in ids:
		var record: Dictionary = editor._doc._find(str(id))
		if record.is_empty(): return error("Object not found: " + str(id))
		if not allow_protected and not editor._record_editable(record): return error("Object hidden, locked or outside the active floor: " + str(id))
	return ok({"ids": ids})

func page(items: Array, args: Dictionary) -> Array:
	var start := mini(int(args.get("offset", 0)), items.size())
	return items.slice(start, mini(start + int(args.get("limit", 100)), items.size()))

func assets(query: String = "") -> Array:
	var result: Array = preload("res://scripts/world3d/world_modules.gd").search(query) + editor._assets.search(query)
	for library in editor._shared_assets: result.append_array(library.search(query))
	return result

func asset_id(entry: Dictionary) -> String:
	return preload("res://scripts/world_editor/asset_thumbnails.gd").key_for(entry)

func save_prefab(args: Dictionary) -> Dictionary:
	if str(args.name).strip_edges().is_empty(): return error("Prefab name must not be empty")
	var selected := targets({})
	if not selected.ok or selected.ids.is_empty(): return error("Select editable objects first")
	var pack_root: String = args.pack_root
	if not allowed_path(pack_root) or not Catalog.new().packs().any(func(p): return str(p.root) == pack_root): return error("pack_root must be an available resource pack")
	var destination := pack_root.path_join("assets")
	for path in [destination, destination.path_join("library.json"), destination.path_join("prefabs"), destination.path_join("thumbnails")]:
		if not allowed_path(path): return error("Resource library contains a link outside the allowed storage")
	var records: Array = editor._selection_tools.records()
	var invalid := validate_assets(records)
	if not invalid.is_empty(): return error(invalid)
	var library := Library.new(destination)
	var result := Prefabs.capture(records, library, args.name)
	if not result.ok: return result
	if pack_root == editor._asset_pack_root: editor._assets = library
	else:
		editor._shared_assets = editor._shared_assets.filter(func(old): return old.directory != library.directory)
		editor._shared_assets.append(library)
	editor._refresh_palette()
	if DisplayServer.get_name() != "headless": editor._thumbnails.queue_import(result.entry)
	return ok({"asset_id": asset_id(result.entry), "entry": result.entry})

func place_asset(args: Dictionary) -> Dictionary:
	var entries := assets().filter(func(entry): return asset_id(entry) == args.asset_id)
	if entries.is_empty(): return error("Asset is not in the current or shared library")
	var entry: Dictionary = entries[0]
	var position := xyz(args.position)
	if entry.has("auto_family"): return error("Use paint_auto_tiles for automatic modules")
	var previous_count: int = editor._doc.records.size()
	if entry.has("prefab_path"):
		if not allowed_path(str(entry.prefab_path)): return error("Prefab is outside the allowed content root")
		var loaded := Prefabs.read(entry)
		if not loaded.ok: return loaded
		if loaded.records.size() > Schema.MAX_SELECTION: return error("Prefab has more than 256 components")
		var invalid := validate_assets(loaded.records)
		if not invalid.is_empty(): return error(invalid)
		if not editor._place_prefab(entry, position): return error(editor._status.text)
	else:
		var id := ""
		if entry.has("asset_path"):
			if not allowed_path(str(entry.asset_path)) or not FileAccess.file_exists(str(entry.asset_path)): return error("Asset path unavailable or outside allowed content root")
			id = editor._doc.add_asset(entry, position - Vector3(0, float(entry.get("bounds_position", [0, 0, 0])[1]), 0))
		else:
			var size_: Vector3 = entry.get("size", Vector3.ONE)
			id = editor._doc.add_box(str(entry.surface_id), position + Vector3(0, size_.y * 0.5, 0), size_, entry.get("rotation", Vector3.ZERO))
		editor._dirty = true
		editor._rebuild()
		editor._selection_tools.set_ids([id])
	# Floor isolation can exclude newly placed components from the selection.
	return ok({"ids": editor._doc.records.slice(previous_count).map(func(record): return str(record.uuid))})

func paint(args: Dictionary) -> Dictionary:
	var spacing := float(args.get("cell_size", 4.0))
	var height := float(args.get("height", 0.0))
	var previous := Rules.cell_at(xyz(args.points[0]), spacing)
	var count := 1
	for point in args.points:
		var cell := Rules.cell_at(xyz(point), spacing)
		count += absi(cell.x - previous.x) + absi(cell.y - previous.y)
		previous = cell
	if count > Schema.MAX_PAINT_CELLS: return error("Stroke exceeds 1024 traversed cells; split it into smaller strokes")
	var options := {}
	for field in ["base_height", "rise", "direction", "rail_height"]:
		if args.has(field): options[field] = args[field]
	if args.has("kit_id") and not str(args.kit_id).is_empty():
		var loaded: Dictionary = editor._auto_panel.library.read(args.kit_id)
		if not loaded.ok: return loaded
		options.kit = loaded.kit
	var invalid := Rules.options_error(args.family, height, options)
	if not invalid.is_empty(): return error(invalid)
	editor._auto_stroke.begin(editor._doc, args.family, spacing, height, args.get("erase", false), options)
	if not editor._auto_stroke.active: return error(editor._auto_stroke.error)
	var changed: Array[String] = []
	for point in args.points:
		for id in editor._auto_stroke.paint(xyz(point)):
			if not changed.has(id): changed.append(id)
	editor._refresh_records(changed)
	editor._finish_auto_stroke()
	return ok({"changed_ids": changed, "object_count": editor._doc.records.size()})

func allowed_path(value: String) -> bool:
	return preload("res://scripts/world3d/map_paths.gd").allowed(value)

func validate_assets(records: Array) -> String:
	for record in records:
		if not record is Dictionary: return "Invalid object record"
		if not preload("res://scripts/world3d/building_blueprint.gd").valid_record(record): return "Invalid building component"
		if not preload("res://scripts/world3d/event_templates.gd").valid_record(record): return "Invalid 3D event template"
		if not Rules.valid(record): return "Invalid auto tile or kit outside the allowed content root"
		if not preload("res://scripts/world3d/surface_materials.gd").valid(record): return "Invalid surface material record or texture outside the allowed content root"
		if record.get("kind") == "asset" and not allowed_path(str(record.get("asset_path", ""))): return "Model reference is outside the allowed content root"
	return ""

func validate_map_file(path: String) -> String:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary: return "Invalid glTF document"
	for section in ["buffers", "images"]:
		if not raw.get(section, []) is Array: return "Invalid glTF " + section
		for item in raw.get(section, []):
			if not item is Dictionary: return "Invalid glTF dependency"
			var uri := str(item.get("uri", ""))
			if uri.is_empty() or uri.begins_with("data:"): continue
			var dependency := preload("res://scripts/world3d/gltf_map_io.gd").decode_dependency_uri(uri)
			if dependency.is_empty() or not allowed_path(path.get_base_dir().path_join(dependency)): return "glTF dependency is outside the allowed content root"
	if not raw.get("nodes", []) is Array: return "Invalid glTF nodes"
	for node in raw.get("nodes", []):
		if not node is Dictionary or not node.get("extras", {}) is Dictionary: return "Invalid glTF node"
		var records: Variant = node.get("extras", {}).get("rmmo_records", [])
		if not records is Array: return "Invalid glTF object records"
		var invalid := validate_assets(records)
		if not invalid.is_empty(): return invalid
	return ""
