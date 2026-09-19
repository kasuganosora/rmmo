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
		body_text = "helloworld"
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
		var link = RichTextLabel.new()
		link.bbcode_enabled = true
		link.fit_content = true
		link.scroll_active = false
		link.mouse_filter = Control.MOUSE_FILTER_STOP
		link.add_theme_font_size_override("normal_font_size", 13)
		link.add_theme_color_override("default_color", L2Style.COL_LINK)
		link.add_theme_color_override("font_url_color", L2Style.COL_LINK)
		link.custom_minimum_size = Vector2(0, 22)
		link.append_text("[center][url][u]%s[/u][/url][/center]" % label)
		var opt_id = ""
		var opt_idx = ctrl._npc_chat_options.get_child_count()
		if typeof(opt) == TYPE_DICTIONARY:
			opt_id = str(opt.get("id", "")).strip_edges()
		link.meta_clicked.connect(_make_dialogue_option_handler(opt_id, opt_idx, label))
		ctrl._npc_chat_options.add_child(link)
	ctrl._npc_chat.visible = true
	ctrl._npc_chat.move_to_front()
	var base: Vector2 = ctrl._npc_chat.get_meta("base_size", Vector2(380, 400))
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


