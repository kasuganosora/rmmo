extends RefCounted
const Settings = preload("res://scripts/world3d/editor_view_settings.gd")
var editor: Node3D
var settings := Settings.defaults()
var picking := false
var marker: MeshInstance3D
var _membership := {}

func refresh() -> void:
	settings = Settings.resolve(editor._doc.map_meta)
	_membership.clear()
	for record in editor._doc.records: _membership[str(record.uuid)] = Settings.contains(record,settings)
	if marker == null:
		marker = MeshInstance3D.new(); marker.name = "PlaytestSpawn"
		var mesh := CylinderMesh.new(); mesh.top_radius = .3; mesh.bottom_radius = .3; mesh.height = .035; marker.mesh = mesh
		var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = Color(.25,1,.5,.7); material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; marker.material_override = material
		editor.add_child(marker)
	marker.position = Vector3(settings.spawn[0],settings.spawn[1]+.025,settings.spawn[2])
	marker.visible = not settings.isolation or (settings.spawn[1] >= settings.base_height-.001 and settings.spawn[1] < settings.base_height+settings.floor_height-.001)
	if editor._view_panel != null: editor._view_panel.refresh()

func includes(record: Dictionary) -> bool:
	var id := str(record.get("uuid",""))
	if _membership.has(id): return bool(_membership[id])
	return Settings.contains(record,settings)

func decorate(record: Dictionary, visual: Node3D) -> void:
	_membership[str(record.uuid)] = Settings.contains(record,settings)
	var inside := includes(record)
	visual.set_meta("editor_floor_excluded",not inside)
	visual.visible = not record.get("editor_hidden",false) and (inside or settings.outside == "dim")
	if not inside and settings.outside == "dim": _dim(visual)

func _dim(node: Node) -> void:
	if node is GeometryInstance3D: node.transparency = maxf(node.transparency,.85)
	for child in node.get_children(): _dim(child)

func set_settings(changes: Dictionary) -> Dictionary:
	var ready: Dictionary = editor._gameplay.guard()
	if not ready.ok: return ready
	if picking: return {"ok":false,"error":"请先完成或取消出生点拾取"}
	var error := Settings.Schema.validate(changes,Settings.schema())
	if not error.is_empty(): return {"ok":false,"error":error}
	var value := Settings.resolve(editor._doc.map_meta); value.merge(changes,true)
	if value == settings: return {"ok":true,"changed":false,"view":value}
	editor._doc.checkpoint_recovery(); editor._doc.map_meta.editor_view = value
	editor._dirty = true
	if changes.has("base_height") and value.isolation: editor._auto_height = value.base_height
	editor._material_tool.clear_target()
	editor._rebuild()
	return {"ok":true,"changed":true,"view":value}

func pick(screen: Vector2) -> Dictionary:
	if not Rect2(Vector2.ZERO,editor._canvas.size).has_point(screen): return {"ok":false,"error":"坐标不在地图画布内"}
	var origin: Vector3 = editor._camera.project_ray_origin(screen)
	var hit: Dictionary = editor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+editor._camera.project_ray_normal(screen)*10000))
	if hit.is_empty() or hit.normal.y < .7: return {"ok":false,"error":"请选择朝上的地面或平台"}
	return set_settings({"spawn":[hit.position.x,hit.position.y,hit.position.z]})

func begin_pick() -> void:
	editor._finish_edits()
	if not editor._gameplay.guard().ok: return
	picking = true; editor._status.text = "点击地面设置试玩出生点 · Esc 取消"

func input(event: InputEvent) -> bool:
	if not picking: return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		picking = false; editor._status.text = "已取消出生点拾取"; return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and editor._canvas.get_global_rect().has_point(event.position):
		picking = false
		var result := pick(event.position-editor._canvas.global_position)
		editor._status.text = "试玩出生点已设置，可撤销" if result.ok else str(result.error)
		return true
	return event is InputEventKey or event is InputEventMouseButton
