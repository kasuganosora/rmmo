extends RefCounted
## Domain module: inspector field selectors (dir/charset/map/item/shop/switch/audio/face fill+select helpers).

var ctrl
func _init(c):
	ctrl = c

const EventCommands = preload("res://scripts/editor/domain/event_commands.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const ShopCatalog = preload("res://scripts/net/combat/shop_catalog.gd")

func _select_g_charset_opt(id: String) -> void:
	if ctrl._g_charset_opt == null:
		return
	for i in range(ctrl._g_charset_opt.item_count):
		if str(ctrl._g_charset_opt.get_item_metadata(i)) == id:
			ctrl._g_charset_opt.select(i)
			return
	ctrl._g_charset_opt.select(0)



func _on_g_charset_opt(idx: int) -> void:
	if ctrl._g_charset_opt == null or ctrl._g_charset == null:
		return
	var id = str(ctrl._g_charset_opt.get_item_metadata(idx))
	if id != "":
		ctrl._g_charset.text = id
	ctrl._store_graphic()



func _fill_dir(opt: OptionButton) -> void:
	opt.clear()
	opt.add_item("下", 2)
	opt.add_item("左", 4)
	opt.add_item("右", 6)
	opt.add_item("上", 8)
	opt.select(0)



func _select_dir(opt: OptionButton, d: int) -> void:
	for i in range(opt.item_count):
		if opt.get_item_id(i) == d:
			opt.select(i)
			return
	opt.select(0)



func _dir_value(opt: OptionButton) -> int:
	return opt.get_item_id(opt.selected) if opt.item_count > 0 else 2



func _fill_charset_opt() -> void:
	_fill_one_charset_opt(ctrl._charset_opt)
	_fill_one_charset_opt(ctrl._g_charset_opt)



func _fill_one_charset_opt(opt: OptionButton) -> void:
	if opt == null:
		return
	opt.clear()
	opt.add_item("（手填）")
	opt.set_item_metadata(0, "")
	if ctrl.pack == null or not ctrl.pack.has_method("list_assets"):
		return
	for it in ctrl.pack.list_assets("charset"):
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var cid = str(it.get("id", ""))
		opt.add_item(cid)
		opt.set_item_metadata(opt.item_count - 1, cid)



func _select_charset_opt(id: String) -> void:
	if ctrl._charset_opt == null:
		return
	for i in range(ctrl._charset_opt.item_count):
		if str(ctrl._charset_opt.get_item_metadata(i)) == id:
			ctrl._charset_opt.select(i)
			return
	ctrl._charset_opt.select(0)



func _on_charset_opt(idx: int) -> void:
	var id = str(ctrl._charset_opt.get_item_metadata(idx))
	if id != "":
		ctrl._charset.text = id



func _fill_map_opt() -> void:
	_fill_one_map_opt(ctrl._to_map_opt)
	_fill_one_map_opt(ctrl._p_map_opt)



func _fill_one_map_opt(opt: OptionButton) -> void:
	if opt == null:
		return
	opt.clear()
	opt.add_item("（手填）")
	opt.set_item_metadata(0, "")
	if ctrl.pack == null:
		return
	for item in ctrl.pack.map_tree:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var mid = str(item.get("id", ""))
		opt.add_item("%s (%s)" % [str(item.get("name", mid)), mid])
		opt.set_item_metadata(opt.item_count - 1, mid)



func _select_map_opt(id: String) -> void:
	if ctrl._to_map_opt == null:
		return
	for i in range(ctrl._to_map_opt.item_count):
		if str(ctrl._to_map_opt.get_item_metadata(i)) == id:
			ctrl._to_map_opt.select(i)
			return
	ctrl._to_map_opt.select(0)



func _on_map_opt(idx: int) -> void:
	var id = str(ctrl._to_map_opt.get_item_metadata(idx))
	if id != "":
		ctrl._to_map.text = id



func _load_catalogs() -> void:
	var ic = ItemCatalog.new()
	ic.load_catalog()
	ctrl._items = ic.list_all()
	var sc = ShopCatalog.new()
	if sc.has_method("load_catalog"):
		sc.load_catalog()
	if sc.has_method("all_ids"):
		ctrl._shops = sc.all_ids()



func _fill_item_opt(opt: OptionButton, allow_empty: bool = false) -> void:
	opt.clear()
	if allow_empty:
		opt.add_item("（无）")
		opt.set_item_metadata(0, "")
	for it in ctrl._items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var iid = str(it.get("id", ""))
		opt.add_item("%s (%s)" % [str(it.get("name", iid)), iid])
		opt.set_item_metadata(opt.item_count - 1, iid)
	if opt.item_count == 0:
		opt.add_item("potion_hp_small")
		opt.set_item_metadata(0, "potion_hp_small")



func _select_item_opt(id: String) -> void:
	for i in range(ctrl._p_item.item_count):
		if str(ctrl._p_item.get_item_metadata(i)) == id:
			ctrl._p_item.select(i)
			return
	if id != "":
		ctrl._p_item.add_item(id)
		ctrl._p_item.set_item_metadata(ctrl._p_item.item_count - 1, id)
		ctrl._p_item.select(ctrl._p_item.item_count - 1)



func _item_id_of(opt: OptionButton) -> String:
	if opt.item_count == 0 or opt.selected < 0:
		return ""
	return str(opt.get_item_metadata(opt.selected))



func _fill_shop_opt(opt: OptionButton) -> void:
	opt.clear()
	for sid in ctrl._shops:
		opt.add_item(str(sid))
		opt.set_item_metadata(opt.item_count - 1, str(sid))
	if opt.item_count == 0:
		opt.add_item("starter_goods")
		opt.set_item_metadata(0, "starter_goods")



func _select_shop_opt(id: String) -> void:
	for i in range(ctrl._p_shop.item_count):
		if str(ctrl._p_shop.get_item_metadata(i)) == id:
			ctrl._p_shop.select(i)
			return
	if id != "":
		ctrl._p_shop.add_item(id)
		ctrl._p_shop.set_item_metadata(ctrl._p_shop.item_count - 1, id)
		ctrl._p_shop.select(ctrl._p_shop.item_count - 1)



func _shop_id_of(opt: OptionButton) -> String:
	if opt.item_count == 0 or opt.selected < 0:
		return ""
	return str(opt.get_item_metadata(opt.selected))



func _fill_switch_opts() -> void:
	var ids: PackedStringArray = EventCommands.collect_switch_ids(ctrl.pack)
	_fill_id_opt(ctrl._switch_opt, ids)
	_fill_id_opt(ctrl._p_switch_opt, ids)



func _fill_id_opt(opt: OptionButton, ids: PackedStringArray) -> void:
	if opt == null:
		return
	var keep = ""
	if opt.item_count > 0 and opt.selected >= 0:
		keep = str(opt.get_item_metadata(opt.selected))
	opt.clear()
	opt.add_item("（新开关）")
	opt.set_item_metadata(0, "")
	for sid in ids:
		opt.add_item(sid)
		opt.set_item_metadata(opt.item_count - 1, sid)
	_select_switch_opt(opt, keep)



func _select_switch_opt(opt: OptionButton, id: String) -> void:
	if opt == null:
		return
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == id:
			opt.select(i)
			return
	if id.strip_edges() != "":
		opt.add_item(id)
		opt.set_item_metadata(opt.item_count - 1, id)
		opt.select(opt.item_count - 1)
		return
	opt.select(0)



func _on_when_switch_opt(idx: int) -> void:
	if ctrl._switch_opt == null or ctrl._switch_id == null:
		return
	var id = str(ctrl._switch_opt.get_item_metadata(idx))
	if id != "":
		ctrl._switch_id.text = id
	ctrl._store_when()



func _on_cmd_switch_opt(idx: int) -> void:
	if ctrl._p_switch_opt == null or ctrl._p_switch == null:
		return
	var id = str(ctrl._p_switch_opt.get_item_metadata(idx))
	if id != "":
		ctrl._p_switch.text = id
	ctrl._store_params()



func _on_cmd_map_opt(idx: int) -> void:
	if ctrl._p_map_opt == null or ctrl._p_map == null:
		return
	var id = str(ctrl._p_map_opt.get_item_metadata(idx))
	if id != "":
		ctrl._p_map.text = id
	ctrl._store_params()



func _select_cmd_map_opt(id: String) -> void:
	if ctrl._p_map_opt == null:
		return
	for i in range(ctrl._p_map_opt.item_count):
		if str(ctrl._p_map_opt.get_item_metadata(i)) == id:
			ctrl._p_map_opt.select(i)
			return
	ctrl._p_map_opt.select(0)



func _fill_audio_opt(op: String, current: String) -> void:
	if ctrl._p_audio_opt == null:
		return
	var kind = "audio/se"
	match op.strip_edges().to_lower():
		"play_bgm":
			kind = "audio/bgm"
		"play_bgs":
			kind = "audio/bgs"
		"play_me":
			kind = "audio/me"
		_:
			kind = "audio/se"
	ctrl._p_audio_opt.clear()
	ctrl._p_audio_opt.add_item("（手填）")
	ctrl._p_audio_opt.set_item_metadata(0, "")
	if ctrl.pack != null and ctrl.pack.has_method("list_assets"):
		for it in ctrl.pack.list_assets(kind):
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var aid = str(it.get("id", ""))
			ctrl._p_audio_opt.add_item(aid)
			ctrl._p_audio_opt.set_item_metadata(ctrl._p_audio_opt.item_count - 1, aid)
	var picked = 0
	for i in range(ctrl._p_audio_opt.item_count):
		if str(ctrl._p_audio_opt.get_item_metadata(i)) == current:
			picked = i
			break
	ctrl._p_audio_opt.select(picked)



func _on_audio_opt(idx: int) -> void:
	if ctrl._p_audio_opt == null or ctrl._p_audio == null:
		return
	var id = str(ctrl._p_audio_opt.get_item_metadata(idx))
	if id != "":
		ctrl._p_audio.text = id
	ctrl._store_params()



func _fill_face_opt() -> void:
	if ctrl._p_face_opt == null:
		return
	ctrl._p_face_opt.clear()
	ctrl._p_face_opt.add_item("（无）")
	ctrl._p_face_opt.set_item_metadata(0, "")
	if ctrl.pack == null or not ctrl.pack.has_method("list_assets"):
		return
	for it in ctrl.pack.list_assets("faces"):
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var fid = str(it.get("id", ""))
		ctrl._p_face_opt.add_item(fid)
		ctrl._p_face_opt.set_item_metadata(ctrl._p_face_opt.item_count - 1, fid)



func _select_face_opt(id: String) -> void:
	if ctrl._p_face_opt == null:
		return
	for i in range(ctrl._p_face_opt.item_count):
		if str(ctrl._p_face_opt.get_item_metadata(i)) == id:
			ctrl._p_face_opt.select(i)
			return
	if id.strip_edges() != "":
		ctrl._p_face_opt.add_item(id)
		ctrl._p_face_opt.set_item_metadata(ctrl._p_face_opt.item_count - 1, id)
		ctrl._p_face_opt.select(ctrl._p_face_opt.item_count - 1)
		return
	ctrl._p_face_opt.select(0)



func _on_face_opt(_idx: int) -> void:
	ctrl._store_params()



func _face_id_of() -> String:
	if ctrl._p_face_opt == null or ctrl._p_face_opt.item_count == 0 or ctrl._p_face_opt.selected < 0:
		return ""
	return str(ctrl._p_face_opt.get_item_metadata(ctrl._p_face_opt.selected))

