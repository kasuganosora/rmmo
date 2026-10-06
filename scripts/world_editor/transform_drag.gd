extends RefCounted
## One drag is a transaction: preview in place, snapshot only when committed.
const Gizmo = preload("res://scripts/world_editor/transform_gizmo.gd")
var editor: Node3D
var active := false
var axis := -1
var mode := 0
var uuid := ""
var before: Array = []
var original: Dictionary = {}
var originals: Array = []
var center := Vector3.ZERO
var direction := Vector3.ZERO
var plane := Plane()
var anchor := Vector3.ZERO
var start_screen := Vector2.ZERO
var screen_direction := Vector2.ZERO
var length := 1.0
var last_angle := 0.0
var total_angle := 0.0
var started := false
var building_drag := false
var building_delta := Vector3.ZERO
var building_rotation := Basis.IDENTITY


func begin(owner: Node3D, screen: Vector2, handle: int) -> bool:
	editor = owner
	if editor._load_failed: return false
	uuid = editor._inspector.selection
	original = editor._doc._find(uuid).duplicate(true)
	if original.is_empty(): return false
	originals = editor._selection_tools.records().duplicate(true)
	if originals.any(func(r):return r.get("prefab_locked",false) and (r.has("fortification") or editor._transform_mode==2)):
		editor._status.text="固定预制件不能缩放或拆改城防结构";return false
	building_drag = editor._selection_tools.whole
	building_delta = Vector3.ZERO; building_rotation = Basis.IDENTITY
	if building_drag and (editor._transform_mode==2 or (editor._transform_mode==1 and handle!=1)):
		editor._status.text="整栋建筑使用 XYZ 移动和 Y 轴旋转；尺寸请在建筑参数中修改"
		return false
	if editor._transform_mode == 2 and originals.size() > 1 and handle != 3: return false
	axis = handle
	mode = editor._transform_mode
	center = editor._selection_tools.pivot()
	length = editor._gizmo.world_length()
	start_screen = screen
	last_angle = 0.0
	total_angle = 0.0
	started = false
	if axis < 3:
		direction = editor._gizmo.axes_basis()[axis]
		if mode == 1:
			plane = Plane(direction, center)
		else:
			# The most camera-facing plane containing the selected axis.
			var view: Vector3 = editor._camera.project_ray_normal(screen)
			var normal := view - direction * view.dot(direction)
			if normal.length_squared() < 0.0001: return false
			plane = Plane(normal.normalized(), center)
		var tip: Vector2 = editor._camera.unproject_position(center + direction * length)
		screen_direction = tip - editor._camera.unproject_position(center)
	else:
		plane = Plane(Vector3.UP, center)
	var point: Variant = _intersection(screen)
	if mode == 0 and point == null: return false
	if mode == 1 and (point == null or (point - center).length_squared() < 0.0001): return false
	anchor = point if point != null else center
	before = editor._doc.records.duplicate(true)
	active = true
	editor._gizmo.active = handle
	return true


func update(screen: Vector2, unsnapped: bool = false) -> void:
	if not active: return
	if not started and screen.distance_to(start_screen) < 3.0: return
	started = true
	var record: Dictionary = editor._doc._find(uuid)
	if record.is_empty(): finish(true); return
	var value := Vector3.ZERO
	var field := "position"
	var group_rotation := Basis.IDENTITY
	var group_scale := 1.0
	var point: Variant = _intersection(screen)
	match mode:
		0:
			if point == null: return
			var step: float = 0.0 if unsnapped else editor._snap
			if axis < 3:
				var distance: float = (point - anchor).dot(direction)
				if step > 0: distance = snappedf(distance, step)
				value = center + direction * distance
			else:
				value = center + point - anchor
				if step > 0:
					value.x = snappedf(value.x, step)
					value.z = snappedf(value.z, step)
		1:
			if point == null or (point - center).length_squared() < 0.0001: return
			field = "rotation"
			var angle: float = (anchor - center).signed_angle_to(point - center, direction)
			total_angle += wrapf(angle - last_angle, -PI, PI)
			last_angle = angle
			var degrees := rad_to_deg(total_angle)
			if not unsnapped and editor._rotation_snap > 0: degrees = snappedf(degrees, editor._rotation_snap)
			var basis := Basis(direction, deg_to_rad(degrees)) * Basis.from_euler(Gizmo.vector(original, "rotation") * PI / 180.0)
			group_rotation = Basis(direction, deg_to_rad(degrees))
			value = basis.get_euler() * 180.0 / PI
		2:
			field = "size"
			var delta := screen - start_screen
			var amount := (delta.x - delta.y) / 120.0 if axis == 3 else delta.dot(screen_direction) / maxf(screen_direction.length_squared(), 1.0)
			var factor := maxf(0.001, 1.0 + amount)
			if not unsnapped and editor._scale_snap > 0: factor = maxf(editor._scale_snap, snappedf(factor, editor._scale_snap))
			group_scale = minf(factor, 1000.0)
			value = Gizmo.vector(original, "size")
			if axis == 3: value *= factor
			else: value[axis] *= factor
			value = value.clamp(Vector3.ONE * 0.001, Vector3.ONE * 100000.0)
	if not value.is_finite(): return
	if building_drag:
		building_delta = value-center if mode==0 else Vector3.ZERO
		building_rotation = group_rotation
	if originals.size() > 1:
		var by_id := {}
		for member in editor._doc.records: by_id[str(member.uuid)]=member
		for previous in originals:
			var member: Dictionary = by_id[str(previous.uuid)]
			var position := Gizmo.vector(previous, "position")
			if mode == 0: position += value - center
			else: position = center + group_rotation * ((position - center) * group_scale)
			var rotation := (group_rotation * Basis.from_euler(Gizmo.vector(previous, "rotation") * PI / 180)).get_euler() * 180 / PI
			var size_ := Gizmo.vector(previous, "size") * group_scale
			member.position = [position.x, position.y, position.z]
			member.rotation = [rotation.x, rotation.y, rotation.z] if mode == 1 and not group_rotation.is_equal_approx(Basis.IDENTITY) else previous.rotation.duplicate()
			member.size = [size_.x, size_.y, size_.z]
	else:
		if value.is_equal_approx(Gizmo.vector(record, field)): return
		record[field] = [value.x, value.y, value.z]
	editor._sync_selected_transform()
	editor._inspector.refresh(false)


func finish(cancel: bool = false) -> void:
	if not active: return
	active = false
	editor._gizmo.active = -1
	var changed := false
	var result := {"ok":true}
	for previous in originals:
		var record: Dictionary = editor._doc._find(str(previous.uuid))
		for field in ["position", "rotation", "size"]:
			if not Gizmo.vector(record, field).is_equal_approx(Gizmo.vector(previous, field)): changed = true
	if cancel or not changed or building_drag:
		for previous in originals:
			var record: Dictionary = editor._doc._find(str(previous.uuid))
			for field in ["position", "rotation", "size"]: record[field] = previous[field].duplicate()
		editor._sync_selected_transform()
		editor._inspector.refresh(false)
		if building_drag and changed and not cancel:
			result = editor._selection_tools.motion.move(building_delta,building_rotation,1.0,center)
	else:
		editor._detach_selected_tile()
		editor._doc.commit_change(before)
		editor._dirty = true
	before.clear()
	original.clear()
	originals.clear()
	if editor._authoring.settings.isolation: editor._rebuild()
	if editor._status != null: editor._status.text = ("已取消变换" if cancel else editor._hint()) if result.ok else result.error


func _intersection(screen: Vector2) -> Variant:
	return plane.intersects_ray(editor._camera.project_ray_origin(screen), editor._camera.project_ray_normal(screen))
