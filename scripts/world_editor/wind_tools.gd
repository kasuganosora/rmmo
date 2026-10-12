extends RefCounted
const Response = preload("res://scripts/world3d/wind_response.gd")
var editor: Node3D
var preview_enabled := false

func set_preview(enabled: bool) -> Dictionary:
	var ready: Dictionary=editor._gameplay.guard()
	if not ready.ok: return ready
	preview_enabled=enabled
	apply_preview()
	if editor._environment_panel!=null: editor._environment_panel.refresh()
	return {"ok":true,"enabled":preview_enabled}

func apply_preview() -> void:
	if is_instance_valid(editor._weather) and editor._weather.wind_objects!=null:
		editor._weather.wind_objects.set_enabled(preview_enabled)

func catalog(id: String) -> Array:
	if editor._view == null: return []
	return Response.catalog(editor._view.get_node_or_null(NodePath(id)))

func set_settings(ids: Array, changes: Dictionary) -> Dictionary:
	var ready: Dictionary = editor._gameplay.guard()
	if not ready.ok: return ready
	var error := Response.Schema.validate(changes,Response.schema())
	if not error.is_empty(): return {"ok":false,"error":error}
	if ids.is_empty() or ids.size() > 256: return {"ok":false,"error":"请选择 1～256 个物件"}
	var updates := {}
	for id in ids:
		var record: Dictionary = editor._doc._find(str(id))
		if record.is_empty() or not editor._record_editable(record): return {"ok":false,"error":"物件不存在、隐藏、锁定或不在当前楼层"}
		if record.get("prefab_locked",false):return {"ok":false,"error":"固定预制件不能修改内部网格受风方式"}
		if record.get("kind") not in ["asset","box"] or record.has("building") or record.has("tile3d"): return {"ok":false,"error":"受风用于独立装饰网格；生成建筑、自动地形和角色不能直接设为柔性物件"}
		var config := Response.resolve(record).merged(changes,true)
		if config.profile != "off":
			var root: Node3D = editor._view.get_node_or_null(NodePath(str(id)))
			if root == null: return {"ok":false,"error":"物件视图尚未就绪"}
			error = Response.validate_target(root,config)
			if not error.is_empty(): return {"ok":false,"error":error}
		var imported_default:=false
		if config.profile=="off" and not record.has("wind_response"):
			var view:Node=editor._view.get_node_or_null(NodePath(str(id)))
			if view!=null:imported_default=Response.Paint.meshes(view).any(func(n):return n.get_meta("extras",{}).has("rmmo_wind"))
		if config != Response.resolve(record) or imported_default: updates[id] = config
	if updates.is_empty(): return {"ok":true,"changed_ids":[]}
	editor._doc.checkpoint()
	for id in updates:
		var record: Dictionary = editor._doc._find(str(id))
		# Keep an explicit off override: erasing it would restore authored GLB wind.
		record.wind_response = updates[id]
	editor._dirty = true; editor._rebuild()
	return {"ok":true,"changed_ids":updates.keys()}
