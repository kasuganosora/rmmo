extends RefCounted
## UI panel: NPC dialogue window.

var ctrl
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

func show_npc_dialogue(npc_name: String, body: String, options: Array = [], face: Dictionary = {}) -> void:
	## Open Lineage2-ish NPC Chat panel. options: Array of String or {label, id}.
	ctrl._ensure_npc_chat()
	var title_name = npc_name.strip_edges()
	if title_name == "":
		title_name = "NPC"
	ctrl._npc_chat_name.text = title_name
	_apply_dialogue_face(face)
	var body_text = body.strip_edges()
	if body_text == "":
		body_text = "…"
	ctrl._npc_chat_body.clear()
	var safe = body_text.replace("[", "[lb]")
	ctrl._npc_chat_body.append_text(safe)
	for c in ctrl._npc_chat_options.get_children():
		c.queue_free()
	for opt in options:
		var label = ""
		if typeof(opt) == TYPE_DICTIONARY:
			label = str(opt.get("label", opt.get("text", "")))
		else:
			label = str(opt)
		label = label.strip_edges()
		if label == "":
			continue
		var choice := Button.new()
		choice.text = label
		choice.custom_minimum_size.y = 30
		choice.focus_mode = Control.FOCUS_NONE
		L2Style.style_row_button(choice, false)
		var opt_id := str(opt.get("id", "")) if opt is Dictionary else ""
		var opt_idx: int = ctrl._npc_chat_options.get_child_count()
		choice.pressed.connect(_make_dialogue_option_handler(opt_id, opt_idx, label).bind(null))
		ctrl._npc_chat_options.add_child(choice)
	ctrl._npc_chat.visible = true
	ctrl._npc_chat.move_to_front()
	var base: Vector2 = ctrl._npc_chat.get_meta("base_size", Vector2(380, 320))
	ctrl._npc_chat.size = base
	ctrl.call_deferred("_place_npc_chat")



func _make_dialogue_option_handler(option_id: String, option_index: int, label: String) -> Callable:
	return func(_meta):
		hide_npc_dialogue()
		if ctrl._world_combat != null and ctrl._world_combat.has_method("request_event_choice"):
			ctrl._world_combat.request_event_choice(option_id, option_index)
		else:
			var srv = Net.server()
			if srv != null and srv.has_method("try_event_choice"):
				srv.try_event_choice(option_id, option_index)
			ctrl.append_system("对话选项：%s" % label)



func hide_npc_dialogue() -> void:
	if ctrl._npc_chat != null:
		ctrl._npc_chat.visible = false



func _apply_dialogue_face(face: Dictionary) -> void:
	if ctrl._npc_chat_face == null:
		return
	var fid = str(face.get("id", face.get("face", ""))).strip_edges()
	if fid == "":
		ctrl._npc_chat_face.texture = null
		ctrl._npc_chat_face.visible = false
		return
	var tex: Texture2D = CharsetSheet.make_face_texture(fid, int(face.get("index", 0)), str(face.get("pack_dir", "")))
	ctrl._npc_chat_face.texture = tex
	ctrl._npc_chat_face.visible = tex != null


