extends RefCounted
## UI panel: equipment / paperdoll with compare tips.

var ctrl
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const EquipCompare = preload("res://scripts/ui/equip_compare.gd")
const EquipSlot = preload("res://scripts/ui/equip_slot.gd")
const Equipment = preload("res://scripts/net/combat/equipment.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const PaperdollLook = preload("res://scripts/char/paperdoll_look.gd")

func _is_item_equipped(item_id: String) -> bool:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return false
	for it in ctrl._server_equipment:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("item_id", "")).strip_edges() == item_id:
			return true
	return false



func _equipped_def_for_compare(item_id: String) -> Dictionary:
	var def = ctrl._item_def(item_id)
	var slot_key = EquipCompare.equip_slot_for_item(def)
	if slot_key.is_empty():
		return {}
	var eq_id = EquipCompare.find_equipped_id(slot_key, ctrl._server_equipment)
	if eq_id.is_empty():
		return {}
	return ctrl._item_def(eq_id)



func _equipped_enhance_for_compare(item_id: String) -> int:
	var def = ctrl._item_def(item_id)
	var slot_key = EquipCompare.equip_slot_for_item(def)
	if slot_key.is_empty():
		return 0
	var entry = EquipCompare.find_equipped_entry(slot_key, ctrl._server_equipment)
	return clampi(int(entry.get("enhance", 0)), 0, 5)



func _equip_compare_tip(item_id: String, base_lines: String, item_enhance: int = 0) -> String:
	var def = ctrl._item_def(item_id)
	if not EquipCompare.is_equipment(def):
		return base_lines
	return EquipCompare.format_compare_tip(
		def,
		_equipped_def_for_compare(item_id),
		base_lines,
		item_enhance,
		_equipped_enhance_for_compare(item_id)
	)



func apply_equipment_snapshot(slots: Array, bonuses: Dictionary = {}) -> void:
	ctrl._server_equipment = slots.duplicate(true)
	ctrl._server_equip_bonuses = bonuses.duplicate(true)
	if ctrl._windows.has("character") and ctrl._windows["character"].visible:
		ctrl._refresh_window_contents()
	# Equipped gear may leave bag qty 0 — still show hotbar letter.
	ctrl._refresh_hotbar_slot_visuals()



func _sync_equipment_cache() -> void:
	## Refresh from MockServer when opening / rebuilding character window.
	var srv = Net.server()
	if srv != null and srv.get("equipment") != null and srv.equipment.has_method("snapshot"):
		ctrl._server_equipment = srv.equipment.snapshot()
		if srv.equipment.has_method("total_bonuses"):
			ctrl._server_equip_bonuses = srv.equipment.total_bonuses()



func _equipment_map() -> Dictionary:
	## slot_id -> {item_id, name, durability, durability_max, icon_index?, icon_ref?}
	var m: Dictionary = {}
	for it in ctrl._server_equipment:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var sid = str(it.get("slot", "")).strip_edges()
		if sid.is_empty():
			continue
		m[sid] = {
			"item_id": str(it.get("item_id", "")).strip_edges(),
			"name": str(it.get("name", "")).strip_edges(),
			"durability": int(it.get("durability", -1)),
			"durability_max": int(it.get("durability_max", -1)),
			"icon_index": int(it.get("icon_index", -1)),
			"icon": str(it.get("icon", "")).strip_edges(),
			"icon_ref": str(it.get("icon_ref", "")).strip_edges(),
		}
	return m



func _build_paperdoll(host: Control, ch: Dictionary) -> void:
	## Slots around the live character (gender + equipped MV layers).
	const CELL := 38
	const CANVAS := Vector2(224, 300)
	var canvas = Control.new()
	canvas.name = "DollCanvas"
	canvas.custom_minimum_size = CANVAS
	canvas.size = CANVAS
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(canvas)
	var sil = TextureRect.new()
	sil.name = "Silhouette"
	sil.texture = _paperdoll_texture(ch)
	sil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sil.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sil.offset_left = 38
	sil.offset_right = -38
	sil.offset_top = 18
	sil.offset_bottom = -6
	canvas.add_child(sil)
	# Left column jewelry/armor, right column weapons/rings, head/feet on the figure.
	var positions: Dictionary = {
		"head": Vector2(93, 4),
		"earring_l": Vector2(4, 16),
		"earring_r": Vector2(182, 16),
		"necklace": Vector2(4, 62),
		"weapon_main": Vector2(182, 62),
		"chest": Vector2(4, 108),
		"weapon_off": Vector2(182, 108),
		"hands": Vector2(4, 154),
		"ring_r": Vector2(182, 154),
		"legs": Vector2(4, 200),
		"ring_l": Vector2(182, 200),
		"feet": Vector2(93, 256),
	}
	var eq_map = _equipment_map()
	for sid in positions.keys():
		var cell = PanelContainer.new()
		cell.set_script(EquipSlot)
		cell.position = positions[sid]
		cell.custom_minimum_size = Vector2(CELL, CELL)
		cell.size = Vector2(CELL, CELL)
		var entry: Dictionary = eq_map.get(sid, {})
		var iid = str(entry.get("item_id", "")).strip_edges()
		var nm = str(entry.get("name", "")).strip_edges()
		if nm.is_empty() and not iid.is_empty():
			nm = ctrl._item_label(iid)
		if not iid.is_empty():
			nm = ctrl._item_rarity_name_line(iid, nm)
		var hint = Equipment.label_zh(sid)
		var iix = ctrl._item_icon_index(iid) if not iid.is_empty() else -1
		var iref = ctrl._item_icon_ref(iid) if not iid.is_empty() else ""
		if not iid.is_empty() and entry.has("icon_index"):
			iix = int(entry.get("icon_index", iix))
		if not iid.is_empty():
			var er = str(entry.get("icon_ref", "")).strip_edges()
			if er.is_empty():
				er = str(entry.get("icon", "")).strip_edges()
				if not er.is_empty() and not er.begins_with("content:"):
					er = "content://icon/%s" % er
			if not er.is_empty():
				iref = er
		var dur = int(entry.get("durability", -1))
		var dur_max = int(entry.get("durability_max", -1))
		cell.setup(sid, iid, nm, hint, iix, iref, dur, dur_max)
		if not iid.is_empty():
			var eq_def = ctrl._item_def(iid)
			var enh_pd = clampi(int(entry.get("enhance", 0)), 0, 5)
			if enh_pd > 0:
				var tip0 = str(cell.tooltip_text)
				if not tip0.is_empty():
					# Prefix display name line with +N when present
					var tip_lines = tip0.split("\n")
					if tip_lines.size() > 0 and not str(tip_lines[0]).strip_edges().is_empty():
						tip_lines[0] = "%s +%d" % [str(tip_lines[0]).strip_edges(), enh_pd]
						cell.tooltip_text = "\n".join(tip_lines)
				cell.tooltip_text = str(cell.tooltip_text) + "\n强化 +%d" % enh_pd
			var bonus_lines = EquipCompare.format_bonus_lines(eq_def, enh_pd)
			if not bonus_lines.is_empty():
				cell.tooltip_text = str(cell.tooltip_text) + "\n" + "\n".join(bonus_lines)
			if bool(entry.get("bound", false)):
				cell.tooltip_text = str(cell.tooltip_text) + "\n已绑定"
		cell.equip_requested.connect(_on_equip_slot_equip)
		cell.unequip_requested.connect(_on_equip_slot_unequip)
		canvas.add_child(cell)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP



func _paperdoll_texture(ch: Dictionary) -> Texture2D:
	var catalog = null
	var srv = Net.server()
	if srv != null:
		catalog = srv.get("item_catalog")
	var tex: Texture2D = PaperdollLook.standing_texture(ch, ctrl._server_equipment, catalog)
	if tex != null:
		return tex
	return L2Style.tex("paperdoll.png")



func _on_equip_slot_equip(item_id: String, slot_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_equip_item"):
		ctrl._world_combat.request_equip_item(item_id, slot_id)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_equip_item"):
			var result: Dictionary = srv.try_equip_item(item_id, slot_id)
			_apply_equip_result_locally(result)
		else:
			ctrl.append_system("无法装备：%s" % item_id)



func _on_equip_slot_unequip(slot_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_unequip_item"):
		ctrl._world_combat.request_unequip_item(slot_id)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_unequip_item"):
			var result: Dictionary = srv.try_unequip_item(slot_id)
			_apply_equip_result_locally(result)
		else:
			ctrl.append_system("无法卸下：%s" % slot_id)



func _on_equip_slot_drop(slot_id: String) -> void:
	## Drag equipped item onto world GroundDropZone.
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_drop_equipped"):
		ctrl._world_combat.request_drop_equipped(slot_id)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_drop_equipped"):
			var result: Dictionary = srv.try_drop_equipped(slot_id)
			_apply_equip_result_locally(result)
		else:
			ctrl.append_system("无法丢弃装备：%s" % slot_id)



func _apply_equip_result_locally(result: Dictionary) -> void:
	## Fallback when world bridge missing: apply action opcodes from try_* result.
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				ctrl.apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"equipment_update":
				var eq_v: Variant = action.get("equipment", [])
				var eq: Array = eq_v if typeof(eq_v) == TYPE_ARRAY else []
				var bon_v: Variant = action.get("bonuses", {})
				var bons: Dictionary = bon_v if typeof(bon_v) == TYPE_DICTIONARY else {}
				apply_equipment_snapshot(eq, bons)
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)



func _on_title_equip(title_id: String) -> void:
	var srv = Net.server()
	if srv != null and srv.has_method("try_title_equip"):
		ctrl._apply_title_result_locally(srv.try_title_equip(title_id))
	else:
		ctrl.append_system("无法装备称号。")


