extends RefCounted
## Reusable editable records. Immutable payloads and model dependencies share a pack.
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
const SurfacePaint = preload("res://scripts/world3d/surface_materials.gd")
const MapPaths = preload("res://scripts/world3d/map_paths.gd")


static func capture(records: Array, library, label: String) -> Dictionary:
	if records.is_empty() or label.strip_edges().is_empty(): return {"ok": false, "error": "请选择物件并填写预制件名称"}
	for record in records:
		if not preload("res://scripts/world3d/event_templates.gd").valid_record(record): return {"ok": false, "error": "预制件事件模板无效"}
		if not preload("res://scripts/world3d/wind_response.gd").valid(record): return {"ok":false,"error":"预制件受风配置无效"}
		if not preload("res://scripts/world3d/road_surface.gd").valid(record): return {"ok": false, "error": "预制件表面材质无效"}
		if not preload("res://scripts/world3d/terrain_surface.gd").valid(record): return {"ok":false,"error":"预制件地形损坏"}
		if not SurfacePaint.valid(record): return {"ok": false, "error": "预制件表面材质无效"}
	if not SurfacePaint.missing(records).is_empty(): return {"ok": false, "error": "预制件引用的表面贴图缺失"}
	var bounds := Geometry.bounds(records)
	var pivot := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var copies: Array = records.duplicate(true)
	for record in copies:
		preload("res://scripts/world3d/building_fixtures.gd").bake_snapshot(record)
		record.erase("building") # Snapshot prefabs retain meshes, not a live building recipe.
		record.erase("road_source")
		var position := Geometry.vector(record, "position") - pivot
		record.position = [position.x, position.y, position.z]
		for key in ["editor_group", "editor_group_name", "editor_hidden", "editor_locked"]: record.erase(key)
		Rules.detach(record)
		var kit: Dictionary = record.get("tile3d", {}).get("options", {}).get("kit", {})
		for key in kit.get("pieces", {}):
			var source: String = kit.pieces[key]
			if not Rules.Kits.check_model(source).is_empty(): return {"ok": false, "error": "预制件拼接套件模型无效"}
			var destination: String = library.directory.path_join("tile_models").path_join(FileAccess.get_sha256(source) + ".glb")
			if not MapPaths.allowed(destination): return {"ok": false, "error": "预制件拼接套件目录无效"}
			if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK or Rules.Kits.write_immutable(destination, FileAccess.get_file_as_bytes(source)) != OK: return {"ok": false, "error": "预制件拼接模型打包失败"}
			kit.pieces[key] = "tile_models/" + destination.get_file()
		for definition in SurfacePaint.definitions(record):
			for field in SurfacePaint.MAP_FIELDS:
				var source := str(definition.get(field, ""))
				if source.is_empty(): continue
				var destination: String = library.directory.path_join("material_textures").path_join(FileAccess.get_sha256(source) + "." + source.get_extension().to_lower())
				if not MapPaths.allowed(destination) or not MapPaths.allowed(destination + ".previous"): return {"ok": false, "error": "预制件贴图目录无效"}
				var error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
				if error == OK and not FileAccess.file_exists(destination): error = preload("res://scripts/world_editor/surface_material_library.gd")._write(destination, FileAccess.get_file_as_bytes(source))
				if error != OK: return {"ok": false, "error": "预制件贴图打包失败"}
				definition[field] = destination.trim_prefix(library.directory.trim_suffix("/") + "/")
		if record.get("kind") == "asset":
			var original_path := str(record.get("asset_path", ""))
			var imported: Dictionary = library.import_file(original_path)
			if not imported.ok: return imported
			if record.has("surface_paint"):
				var before := Node3D.new(); var after := Node3D.new()
				var old_model: Node3D = library.instantiate_preview(original_path)
				var new_model: Node3D = library.instantiate_preview(str(imported.entry.asset_path))
				if old_model == null or new_model == null:
					if old_model != null: old_model.free()
					if new_model != null: new_model.free()
					before.free(); after.free()
					return {"ok": false, "error": "打包后的模型无法读取"}
				before.add_child(old_model); after.add_child(new_model)
				var mapped := SurfacePaint.remap(record.surface_paint, before, after)
				before.free(); after.free()
				if not mapped.ok: return mapped
				record.surface_paint = mapped.entries
			record.asset_path = str(imported.entry.asset_path).trim_prefix(library.directory.trim_suffix("/") + "/")
			record.erase("thumbnail_path")
	var payload := JSON.stringify({"format": "rmmo_prefab", "version": 1, "records": copies}, "\t")
	var hash := (label + "\n" + payload).sha256_text()
	var path: String = library.directory.path_join("prefabs").path_join(hash + ".json")
	for entry in library.entries:
		if entry.get("prefab_path") == path: return {"ok": true, "entry": entry}
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK: return {"ok": false, "error": "预制件目录创建失败：" + error_string(err)}
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "预制件写入失败"}
	file.store_string(payload)
	file.flush()
	err = file.get_error()
	file.close()
	if err == OK: err = preload("res://scripts/world3d/atomic_file.gd").publish(path + ".tmp", path)
	if err != OK: return {"ok": false, "error": "预制件写入失败：" + error_string(err)}
	var entry := {"label": label.strip_edges(), "category": "预制件", "prefab_path": path,
		"thumbnail_path": library.directory.path_join("thumbnails").path_join(hash + ".png"),
		"part_count": copies.size(), "bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z]}
	library.entries.append(entry)
	err = library.save()
	if err != OK:
		library.entries.pop_back()
		return {"ok": false, "error": "素材库写入失败：" + error_string(err)}
	return {"ok": true, "entry": entry}


static func read(entry: Dictionary) -> Dictionary:
	var path := str(entry.get("prefab_path", ""))
	if not FileAccess.file_exists(path): return {"ok": false, "error": "预制件文件不存在"}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or raw.get("format") != "rmmo_prefab" or raw.get("version") != 1 or not raw.get("records") is Array:
		return {"ok": false, "error": "预制件格式不支持"}
	if raw.records.is_empty() or raw.records.size() > 10000: return {"ok": false, "error": "预制件物件数量不合法"}
	var ids := {}
	for record in raw.records:
		if not record is Dictionary or not Rules.valid(record, true): return {"ok": false, "error": "预制件物件损坏"}
		if not preload("res://scripts/world3d/building_blueprint.gd").valid_record(record): return {"ok":false,"error":"预制件建筑构件损坏"}
		if not preload("res://scripts/world3d/event_templates.gd").valid_record(record): return {"ok": false, "error": "预制件事件模板损坏"}
		if not preload("res://scripts/world3d/wind_response.gd").valid(record): return {"ok":false,"error":"预制件受风配置损坏"}
		if not preload("res://scripts/world3d/road_surface.gd").valid(record): return {"ok": false, "error": "预制件表面材质损坏"}
		if not preload("res://scripts/world3d/terrain_surface.gd").valid(record): return {"ok":false,"error":"预制件地形损坏"}
		if not SurfacePaint.valid(record, true): return {"ok": false, "error": "预制件表面材质损坏"}
		var id := str(record.get("uuid", ""))
		if id.is_empty() or ids.has(id) or not record.get("kind") in ["box", "asset", "npc", "gather", "warp", "seat", "event"]:
			return {"ok": false, "error": "预制件物件标识不合法"}
		ids[id] = true
		var kit: Dictionary = record.get("tile3d", {}).get("options", {}).get("kit", {})
		for key in kit.get("pieces", {}):
			var source: String = kit.pieces[key]
			if not source.is_absolute_path(): source = path.get_base_dir().get_base_dir().path_join(source).simplify_path()
			if not Rules.Kits.check_model(source).is_empty(): return {"ok": false, "error": "预制件拼接模型缺失或路径无效"}
			kit.pieces[key] = source
		for definition in SurfacePaint.definitions(record):
			for field in SurfacePaint.MAP_FIELDS:
				var texture := str(definition.get(field, ""))
				if texture.is_empty(): continue
				if not texture.is_absolute_path(): texture = path.get_base_dir().get_base_dir().path_join(texture).simplify_path()
				if not MapPaths.allowed(texture) or not FileAccess.file_exists(texture): return {"ok": false, "error": "预制件表面贴图缺失或路径无效"}
				definition[field] = texture
		for field in ["position", "rotation", "size"]:
			var values: Variant = record.get(field)
			if not values is Array or values.size() != 3: return {"ok": false, "error": "预制件变换数据损坏"}
			for value in values:
				if not (value is float or value is int) or not is_finite(float(value)) or (field == "size" and value <= 0):
					return {"ok": false, "error": "预制件变换数据损坏"}
		if record.kind == "asset":
			var asset := str(record.get("asset_path", ""))
			if not asset.is_absolute_path(): asset = path.get_base_dir().get_base_dir().path_join(asset).simplify_path()
			if not FileAccess.file_exists(asset): return {"ok": false, "error": "预制件模型缺失：" + asset.get_file()}
			record.asset_path = asset
	return {"ok": true, "records": raw.records}


static func place(doc, entry: Dictionary, position: Vector3) -> Dictionary:
	var loaded := read(entry)
	if not loaded.ok: return loaded
	if not position.is_finite(): return {"ok": false, "error": "放置位置不合法"}
	doc.checkpoint()
	var ids := Geometry.duplicate_records(doc, loaded.records, position, str(entry.get("label", "预制件")))
	return {"ok": true, "ids": ids}


static func preview(entry: Dictionary) -> Node3D:
	var loaded := read(entry)
	if not loaded.ok: return null
	var doc = load("res://scripts/world3d/world_document.gd").new()
	doc.records = loaded.records
	return doc.build()
