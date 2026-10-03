extends Control
const Tools=preload("res://scripts/world_editor/terrain_region_tools.gd")
var editor: Node3D
var active:=false
var rectangle:=false
var dragging:=false
var points: Array[Vector3]=[]
var hover:=Vector3(INF,INF,INF)
var options: Dictionary={}
func setup(value: Node3D) -> void:
	editor=value; mouse_filter=MOUSE_FILTER_IGNORE; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func begin(settings: Dictionary,box: bool) -> Dictionary:
	editor._finish_edits()
	var ready: Dictionary=editor._gameplay.guard()
	if not ready.ok: return ready
	editor._set_mode(1); editor._gizmo.hide(); editor._dock_tabs.current_tab=10
	options=settings.duplicate(true); rectangle=box; points.clear(); active=true
	return {"ok":true}
func cancel() -> void:
	active=false; dragging=false; points.clear(); hover=Vector3(INF,INF,INF); queue_redraw()
func pick(screen: Vector2) -> Vector3:
	if not Rect2(Vector2.ZERO,editor._canvas.size).has_point(screen): return Vector3(INF,INF,INF)
	var origin: Vector3=editor._camera.project_ray_origin(screen); var direction: Vector3=editor._camera.project_ray_normal(screen)
	var hit: Dictionary=editor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+direction*editor._camera.far))
	if not hit.is_empty(): return hit.position
	var at: Variant=Plane(Vector3.UP,0).intersects_ray(origin,direction)
	return at if at!=null else Vector3(INF,INF,INF)
func polygon() -> Array:
	if rectangle and points.size()>0 and hover.is_finite():
		var a:=points[0]; var b:=hover
		return [[minf(a.x,b.x),minf(a.z,b.z)],[maxf(a.x,b.x),minf(a.z,b.z)],[maxf(a.x,b.x),maxf(a.z,b.z)],[minf(a.x,b.x),maxf(a.z,b.z)]]
	var result: Array=[]
	for p in points: result.append([p.x,p.z])
	return result
func submit() -> Dictionary:
	var shape:=polygon()
	if shape.size()<3: return Tools.Paint.fail("请至少圈出三个角点")
	var ids: Array=[]; var rect:=Tools.Data.bounds(Tools.Data.points({"polygon":shape})).grow(options.feather)
	for record in editor._doc.records:
		if not record.has("terrain_mesh"): continue
		var aabb:=Tools.Terrain.transform(record)*Tools.Terrain.bounds(record)
		if rect.intersects(Rect2(Vector2(aabb.position.x,aabb.position.z),Vector2(aabb.size.x,aabb.size.z))): ids.append(record.uuid)
	var args:=options.merged({"id":"ground_%d"%Time.get_ticks_usec(),"terrain_ids":ids,"polygon":shape})
	active=false
	var result:=Tools.apply(editor,args)
	if result.ok: cancel()
	else: active=true
	editor._status.text="地表区域已应用，可撤销" if result.ok else str(result.error)
	return result
func input(event: InputEvent) -> bool:
	if not active: return false
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE: cancel(); editor._status.text="已取消地表区域"; return true
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER]: submit(); return true
		if event.keycode==KEY_BACKSPACE:
			if not points.is_empty(): points.pop_back()
			return true
		# Keep shortcuts from modifying the document during a draft.
		if event.ctrl_pressed or event.keycode==KEY_DELETE: return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed and editor._canvas.get_global_rect().has_point(event.position):
			hover=pick(event.position-editor._canvas.global_position)
			if hover.is_finite():
				if rectangle: points=[hover]; dragging=true
				elif points.size()<64: points.append(hover)
			return true
		if not event.pressed and rectangle and dragging:
			dragging=false; hover=pick(event.position-editor._canvas.global_position)
			if hover.is_finite(): submit()
			return true
		if editor._canvas.get_global_rect().has_point(event.position): return true
	if event is InputEventMouseMotion and (dragging or event.button_mask&MOUSE_BUTTON_MASK_LEFT): return true
	return false
func _process(_delta: float) -> void:
	if active: hover=pick(get_global_mouse_position()-editor._canvas.global_position); queue_redraw()
func _draw() -> void:
	if not active or points.is_empty(): return
	var shape:=polygon(); var line:=PackedVector2Array()
	if not rectangle and hover.is_finite(): shape.append([hover.x,hover.z])
	for p in shape:
		var world:=Vector3(p[0],points[0].y+.05,p[1])
		if editor._camera.is_position_behind(world): return
		line.append(editor._camera.unproject_position(world))
	if line.size()>1:
		line.append(line[0]); draw_polyline(line,Color(1,.78,.2),2.,true)
