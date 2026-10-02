extends "res://scripts/ui/inv_slot.gd"
## The bag's icon/quantity rendering with selection-only behavior for item workflows.
var item_tooltip := "":
	set(value):
		item_tooltip = value
		tooltip_text = value

func _apply_visual() -> void:
	super._apply_visual()
	if not item_tooltip.is_empty(): tooltip_text = item_tooltip

func _ready() -> void:
	super._ready()
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _gui_input(event: InputEvent) -> void:
	if disabled or item_id.is_empty(): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		activated.emit(item_id)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		activated.emit(item_id)
		accept_event()

func _get_drag_data(_position: Vector2) -> Variant:
	# Shop stock / other players' offers are not owned bag items.
	return null
