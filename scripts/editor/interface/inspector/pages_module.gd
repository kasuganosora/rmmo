extends RefCounted
## Domain module: event pages (reload/add/del, when/graphic load+store, current page).

var ctrl
func _init(c):
	ctrl = c

const EventCommands = preload("res://scripts/editor/domain/event_commands.gd")

func _reload_pages() -> void:
	if ctrl._pages.is_empty():
		ctrl._pages = [EventCommands.default_page()]
	ctrl._page_idx = clampi(ctrl._page_idx, 0, ctrl._pages.size() - 1)
	if ctrl._page_opt:
		ctrl._page_opt.clear()
		for i in range(ctrl._pages.size()):
			var p: Dictionary = ctrl._pages[i] if typeof(ctrl._pages[i]) == TYPE_DICTIONARY else {}
			ctrl._page_opt.add_item("%d · %s" % [i + 1, EventCommands.page_when_label(p)])
		ctrl._page_opt.select(ctrl._page_idx)
	_load_when()
	ctrl._reload_cmds()



func _on_page(idx: int) -> void:
	if ctrl._loading:
		return
	_store_when()
	ctrl._store_params()
	ctrl._page_idx = idx
	_load_when()
	ctrl._reload_cmds()



func _add_page() -> void:
	_store_when()
	ctrl._pages.append(EventCommands.default_page())
	ctrl._page_idx = ctrl._pages.size() - 1
	_reload_pages()



func _del_page() -> void:
	if ctrl._pages.size() <= 1:
		return
	ctrl._pages.remove_at(ctrl._page_idx)
	ctrl._page_idx = mini(ctrl._page_idx, ctrl._pages.size() - 1)
	_reload_pages()



func _load_when() -> void:
	var page = _current_page()
	var when_v: Variant = page.get("when", {})
	var when: Dictionary = when_v if typeof(when_v) == TYPE_DICTIONARY else {}
	var ss = str(when.get("self_switch", "")).strip_edges()
	if ctrl._self_sw:
		var sel = 0
		for i in range(ctrl._self_sw.item_count):
			if ctrl._self_sw.get_item_text(i) == ss:
				sel = i
				break
		ctrl._self_sw.select(sel)
	if ctrl._switch_id:
		ctrl._switch_id.text = str(when.get("switch", when.get("switch_id", "")))
	ctrl._select_switch_opt(ctrl._switch_opt, str(when.get("switch", when.get("switch_id", ""))))
	var item_id = ""
	if when.has("item"):
		var iv: Variant = when.get("item")
		if typeof(iv) == TYPE_DICTIONARY:
			item_id = str(iv.get("item_id", iv.get("id", "")))
		else:
			item_id = str(iv)
	if item_id == "":
		item_id = str(when.get("item_id", "")).strip_edges()
	if ctrl._item_when:
		var picked = 0
		for i in range(ctrl._item_when.item_count):
			if str(ctrl._item_when.get_item_metadata(i)) == item_id:
				picked = i
				break
		ctrl._item_when.select(picked)
	var trig = str(page.get("trigger", "")).strip_edges()
	if trig == "":
		trig = ctrl._event_trigger
	ctrl._select_trigger(trig)
	_load_graphic()



func _store_when() -> void:
	if ctrl._loading:
		return
	var page = _current_page()
	var ss = ctrl._self_sw.get_item_text(ctrl._self_sw.selected) if ctrl._self_sw else "无"
	var iid = ""
	if ctrl._item_when and ctrl._item_when.item_count > 0:
		iid = str(ctrl._item_when.get_item_metadata(ctrl._item_when.selected))
	EventCommands.set_page_when(page, ss, ctrl._switch_id.text if ctrl._switch_id else "", iid)
	page["trigger"] = EventCommands.trigger_id_of(ctrl._trigger)
	ctrl._event_trigger = str(page["trigger"])
	if ctrl._page_opt and ctrl._page_idx >= 0 and ctrl._page_idx < ctrl._page_opt.item_count:
		ctrl._page_opt.set_item_text(ctrl._page_idx, "%d · %s" % [ctrl._page_idx + 1, EventCommands.page_when_label(page)])



func _load_graphic() -> void:
	var page = _current_page()
	var g: Dictionary = EventCommands.page_graphic(page)
	var was = ctrl._loading
	ctrl._loading = true
	if ctrl._g_charset:
		ctrl._g_charset.text = str(g.get("charset", ""))
	ctrl._select_g_charset_opt(str(g.get("charset", "")))
	if ctrl._g_index:
		ctrl._g_index.value = int(g.get("index", 0))
	if ctrl._g_dir:
		ctrl._select_dir(ctrl._g_dir, int(g.get("direction", 2)))
	ctrl._loading = was



func _store_graphic() -> void:
	if ctrl._loading:
		return
	var page = _current_page()
	var cs = ctrl._g_charset.text.strip_edges() if ctrl._g_charset else ""
	var idx = int(ctrl._g_index.value) if ctrl._g_index else 0
	var d = ctrl._dir_value(ctrl._g_dir) if ctrl._g_dir else 2
	EventCommands.set_page_graphic(page, cs, idx, d)



func _current_page() -> Dictionary:
	if ctrl._page_idx < 0 or ctrl._page_idx >= ctrl._pages.size():
		ctrl._pages = [EventCommands.default_page()]
		ctrl._page_idx = 0
	if typeof(ctrl._pages[ctrl._page_idx]) != TYPE_DICTIONARY:
		ctrl._pages[ctrl._page_idx] = EventCommands.default_page()
	return ctrl._pages[ctrl._page_idx]



func _page_commands() -> Array:
	var page = _current_page()
	var cv: Variant = page.get("commands", [])
	if typeof(cv) != TYPE_ARRAY:
		cv = []
		page["commands"] = cv
	return cv


