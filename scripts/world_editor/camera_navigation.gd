extends Node
## Middle-button navigation owns these keys until release or focus loss.
var editor: Node3D
var held := false
var keys := {}
const MOVEMENT_KEYS = [KEY_W,KEY_A,KEY_S,KEY_D,KEY_UP,KEY_DOWN]

func reset() -> void:
	held=false; keys.clear()

func input(event: InputEvent) -> bool:
	if editor._walk_mode!=null and editor._walk_mode.active:reset();return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_MIDDLE:
		if not event.pressed: reset(); return false
		if editor._canvas.get_global_rect().has_point(event.position) and editor._gameplay.guard().ok:
			var focus=editor.get_viewport().gui_get_focus_owner()
			if focus!=null: focus.release_focus()
			held=true; keys.clear()
		return held
	if event is InputEventKey:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if not event.pressed: keys.erase(key)
		if held and key in MOVEMENT_KEYS:
			if event.pressed: keys[key]=true
			return true
	return false

func _process(delta: float) -> void:
	if not held or keys.is_empty(): return
	if editor.saving() or not editor._gameplay.guard().ok: reset(); return
	var focus=editor.get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: reset(); return
	var right: Vector3=editor._camera.global_basis.x
	right.y=0; right=right.normalized()
	# Derive horizontal forward from right; this also works looking straight down.
	var forward:=Vector3.UP.cross(right)
	var direction:=right*(int(keys.has(KEY_D))-int(keys.has(KEY_A)))+forward*(int(keys.has(KEY_W))-int(keys.has(KEY_S)))
	direction+=Vector3.UP*(int(keys.has(KEY_UP))-int(keys.has(KEY_DOWN)))
	if direction.is_zero_approx(): return
	var span: float=editor._camera.size if editor._camera.projection==Camera3D.PROJECTION_ORTHOGONAL else editor._camera.position.distance_to(editor._orbit_center)
	var speed: float=clampf(span*.35,2.,200.)*(3. if Input.is_key_pressed(KEY_SHIFT) else 1.)
	editor._city.move_camera(direction.normalized()*speed*minf(delta,.05))
