extends RefCounted
## UI panel: inventory bag, gold bar, search filter, split/drop.

var ctrl
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const InvSlot = preload("res://scripts/ui/inv_slot.gd")
const Equipment = preload("res://scripts/net/combat/equipment.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const InvSearchUtil = preload("res://scripts/ui/inv_search_util.gd")
const GOLD_FLOAT_DURATION := 1.2
const GRID_SEP := 4
const INV_ROWS := 10

func _inventory_qty(item_id: String) -> int:
	item_id = item_id.strip_edges()
	for it in ctrl._server_inventory:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("id", "")) == item_id:
			return int(it.get("qty", 0))
	return 0



func _apply_inv_slot_compare_tip(cell: PanelContainer, item_id: String, locked: bool, bound: bool = false, enhance: int = 0, durability: int = -1, durability_max: int = 0) -> void:
	item_id = item_id.strip_edges()
	if item_id.is_empty() or cell == null:
		return
	var dname = ctrl._item_rarity_name_line(item_id)
	enhance = clampi(int(enhance), 0, 5)
	if enhance > 0:
		dname = "%s +%d" % [dname, enhance]
	var base: String
	if locked:
		base = "%s\n%s\n已锁定（右键解锁）" % [dname, item_id]
	else:
		base = "%s\n%s\nCtrl+点击拆分 · 右键锁定" % [dname, item_id]
	if enhance > 0:
		base += "\n强化 +%d" % enhance
	if durability_max > 0 and durability >= 0:
		base += "\n耐久：%d/%d" % [maxi(durability, 0), durability_max]
	if bound:
		base += "\n已绑定"
	else:
		var def = ctrl._item_def(item_id)
		var bop = Equipment.is_bind_on_pickup(def)
		var boe = Equipment.is_bind_on_equip(def)
		if bop:
			base += "\n拾取绑定"
		elif boe:
			base += "\n装备后绑定"
	cell.tooltip_text = ctrl._equip_compare_tip(item_id, base, enhance)




func apply_inventory_snapshot(items: Array, gold: int = -1) -> void:
	var prev_qty: Dictionary = _inv_qty_map(ctrl._server_inventory)
	var had_inv: bool = ctrl._inv_qty_known
	ctrl._server_inventory = items.duplicate(true)
	ctrl._inv_qty_known = true
	var prev_gold: int = ctrl._server_gold
	var had_wallet: bool = ctrl._gold_wallet_known
	if gold >= 0:
		ctrl._server_gold = gold
		ctrl._gold_wallet_known = true
	elif Net.server() != null and Net.server().get("inventory") != null:
		var bag = Net.server().inventory
		if bag != null and bag.has_method("get_gold"):
			ctrl._server_gold = int(bag.get_gold())
			ctrl._gold_wallet_known = true
	# Gold-gain float from inventory_update / wallet delta (loot, sell, quest, attendance…).
	# Ignore decreases (spending) and the first seed snapshot.
	if had_wallet and ctrl._server_gold > prev_gold:
		ctrl.show_gold_gain_float(ctrl._server_gold - prev_gold)
	# Item-gain floats: positive qty deltas only; ignore seed + removals.
	if had_inv:
		ctrl._emit_item_gain_floats_from_delta(prev_qty, _inv_qty_map(ctrl._server_inventory))
	_refresh_inventory_gold_label()
	# Refresh open inventory window if present.
	if ctrl._windows.has("inventory") and ctrl._windows["inventory"].visible:
		ctrl._refresh_window_contents()
	# Update hotbar qty / letter avatars for item bindings.
	ctrl._refresh_hotbar_slot_visuals()
	# Keep shop sell list / gold in sync while open.
	if ctrl._shop_panel != null and ctrl._shop_panel.visible:
		ctrl._fill_shop_panel()
	# Refresh craft have/need while open.
	if ctrl._craft_panel != null and ctrl._craft_panel.visible:
		ctrl._refresh_craft_panel()



func _lock_inventory_window(panel: PanelContainer) -> void:
	## Fixed-size bag: no HudDrag edge resize; size locked to base.
	## Gold footer sits below Scroll (outside scroll body).
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(420, 500))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	ctrl._apply_l2_chrome(panel)
	_ensure_inventory_gold_bar(panel)



func _ensure_inventory_gold_bar(panel: PanelContainer) -> void:
	if panel == null:
		return
	var existing: Label = panel.get_meta("gold_label", null) if panel.has_meta("gold_label") else null
	if existing != null and is_instance_valid(existing):
		_refresh_inventory_gold_label(panel)
		return
	var scroll = panel.find_child("Scroll", true, false) as ScrollContainer
	if scroll == null:
		return
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 80)
	var vbox = scroll.get_parent() as VBoxContainer
	if vbox == null:
		return
	var row = HBoxContainer.new()
	row.name = "GoldBar"
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad_l = Control.new()
	pad_l.custom_minimum_size = Vector2(48, 0)
	pad_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad_l)
	var tag = Label.new()
	tag.text = "Adena"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	L2Style.style_gold_amount(tag)
	row.add_child(tag)
	var amt = Label.new()
	amt.name = "GoldAmount"
	amt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	L2Style.style_gold_amount(amt)
	row.add_child(amt)
	var pad_r = Control.new()
	pad_r.custom_minimum_size = Vector2(48, 0)
	pad_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad_r)
	vbox.add_child(row)
	panel.set_meta("gold_label", amt)
	_refresh_inventory_gold_label(panel)



func _refresh_inventory_gold_label(panel: PanelContainer = null) -> void:
	if panel == null:
		panel = ctrl._windows.get("inventory") as PanelContainer
	if panel == null:
		return
	var lbl: Label = panel.get_meta("gold_label", null) if panel.has_meta("gold_label") else null
	if lbl == null or not is_instance_valid(lbl):
		return
	lbl.text = str(maxi(ctrl._server_gold, 0))



func _fill_inventory(body: VBoxContainer, _ch: Dictionary) -> void:
	ctrl._sync_equipment_cache()
	## ScrollContainer fills window body; grid alone (no chrome labels). Rows > viewport → scrollbar.
	var panel: PanelContainer = ctrl._windows.get("inventory") as PanelContainer
	var items: Array = ctrl._server_inventory
	if items.is_empty():
		var srv0 = Net.server()
		if srv0 != null and srv0.get("inventory") != null and srv0.inventory.has_method("snapshot"):
			items = srv0.inventory.snapshot()
			ctrl._server_inventory = items.duplicate(true)
	var cell_sz = ctrl._grid_cell_size()
	var cols = ctrl._grid_cols_for(panel)
	var ui_slots = cols * INV_ROWS
	# Soft capacity from server Inventory.max_slots (default MAX_SLOTS=40).
	var capacity = 40
	var srv = Net.server()
	if srv != null and srv.get("inventory") != null:
		capacity = maxi(int(srv.inventory.max_slots), 1)
	# Body is only the grid so ScrollContainer chrome is just title + scroll viewport.
	body.add_theme_constant_override("separation", 4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tools = HBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	body.add_child(tools)
	for spec in [["全部", "all"], ["消耗", "consumable"], ["装备", "equipment"], ["材料", "material"]]:
		var fb = Button.new()
		fb.text = str(spec[0])
		fb.focus_mode = Control.FOCUS_NONE
		fb.custom_minimum_size = Vector2(48, 24)
		var fid = str(spec[1])
		L2Style.style_compact_button(fb)
		if ctrl._inv_filter == fid:
			fb.modulate = Color(1.15, 1.05, 0.7)
		fb.pressed.connect(func():
			ctrl._inv_filter = fid
			ctrl._fill_window("inventory")
		)
		tools.add_child(fb)
	var sort_b = Button.new()
	sort_b.text = "排序"
	sort_b.focus_mode = Control.FOCUS_NONE
	sort_b.custom_minimum_size = Vector2(48, 24)
	sort_b.pressed.connect(func():
		if ctrl._world_combat != null and ctrl._world_combat.has_method("request_inventory_sort"):
			ctrl._world_combat.request_inventory_sort()
		else:
			var srv_s = Net.server()
			if srv_s != null and srv_s.has_method("try_inventory_sort"):
				ctrl._apply_equip_result_locally(srv_s.try_inventory_sort())
	)
	tools.add_child(sort_b)
	var search = LineEdit.new()
	search.name = "InvSearch"
	search.placeholder_text = "搜索物品…"
	search.text = ctrl._inv_search_query
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size = Vector2(0, 28)
	search.focus_mode = Control.FOCUS_CLICK
	search.text_changed.connect(_on_inv_search_text_changed)
	body.add_child(search)
	var grid = GridContainer.new()
	grid.name = "InvGrid"
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", GRID_SEP)
	grid.add_theme_constant_override("v_separation", GRID_SEP)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(grid)
	# Pack occupied stacks into first capacity cells; beyond capacity = disabled gray.
	var packed: Array = []
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var q: int = int(it.get("qty", 0))
		if q <= 0:
			continue
		if not _inv_row_matches_filter(it):
			continue
		packed.append(it)
	for i in range(ui_slots):
		var cell = PanelContainer.new()
		cell.set_script(InvSlot)
		cell.custom_minimum_size = cell_sz
		grid.add_child(cell)
		if i >= capacity:
			cell.clear_slot()
			cell.set_disabled(true)
		elif i < packed.size():
			var it2: Dictionary = packed[i]
			var iid = str(it2.get("id", ""))
			var qty: int = int(it2.get("qty", 0))
			cell.set_disabled(false)
			cell.setup(iid, qty, ctrl._item_label(iid), i, ctrl._item_icon_index(iid), ctrl._item_icon_ref(iid))
			var locked_flag = bool(it2.get("locked", false))
			var bound_flag = bool(it2.get("bound", false))
			var enhance_flag = clampi(int(it2.get("enhance", 0)), 0, 5)
			var dur_flag = int(it2.get("durability", -1))
			var dur_max_flag = int(it2.get("durability_max", 0))
			cell.set_meta("locked", locked_flag)
			cell.set_meta("bound", bound_flag)
			cell.set_meta("enhance", enhance_flag)
			if dur_max_flag > 0:
				cell.set_meta("durability", dur_flag)
				cell.set_meta("durability_max", dur_max_flag)
			_apply_inv_slot_compare_tip(cell, iid, locked_flag, bound_flag, enhance_flag, dur_flag, dur_max_flag)
			if not cell.activated.is_connected(_on_inventory_item_pressed):
				cell.activated.connect(_on_inventory_item_pressed)
			if cell.has_signal("split_requested") and not cell.split_requested.is_connected(_on_inventory_split):
				cell.split_requested.connect(_on_inventory_split)
			if cell.has_signal("lock_toggled") and not cell.lock_toggled.is_connected(_on_inventory_lock):
				cell.lock_toggled.connect(_on_inventory_lock)
		else:
			cell.set_disabled(false)
			cell.clear_slot()
		cell.custom_minimum_size = cell_sz
		# Force STOP so HudDraggable pass-through never swallows InvSlot clicks.
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_inv_search_visibility(grid)
	# Keep fixed window size even after content rebuild.
	if panel != null and bool(panel.get_meta("fixed_size", false)):
		ctrl.call_deferred("_lock_window_size", panel)
	# Sync wallet from MockServer when opening bag (authoritative).
	if srv != null and srv.get("inventory") != null and srv.inventory.has_method("get_gold"):
		ctrl._server_gold = int(srv.inventory.get_gold())
	_ensure_inventory_gold_bar(panel)
	_refresh_inventory_gold_label(panel)



func _inv_row_matches_filter(it: Dictionary) -> bool:
	if ctrl._inv_filter == "all" or ctrl._inv_filter.strip_edges() == "":
		return true
	var t = str(it.get("type", "")).strip_edges().to_lower()
	if t.is_empty():
		var iid = str(it.get("id", ""))
		var srv = Net.server()
		if srv != null and srv.get("item_catalog") != null:
			var def: Dictionary = srv.item_catalog.get_item(iid)
			t = str(def.get("type", "")).to_lower()
	match ctrl._inv_filter:
		"consumable":
			return t in ["consumable", "potion"]
		"equipment":
			return t in ["weapon", "armor", "equipment", "equip"]
		"material":
			return t == "material"
		_:
			return true



func _on_inv_search_text_changed(new_text: String) -> void:
	ctrl._inv_search_query = str(new_text)
	var panel: PanelContainer = ctrl._windows.get("inventory") as PanelContainer
	if panel == null:
		return
	var grid = panel.find_child("InvGrid", true, false) as GridContainer
	if grid != null:
		_apply_inv_search_visibility(grid)



func _apply_inv_search_visibility(grid: GridContainer) -> void:
	## Client-only: hide non-matching filled slots; hide empty/locked while query active.
	if grid == null:
		return
	var q = ctrl._inv_search_query.strip_edges()
	var filtering = not q.is_empty()
	for cell in grid.get_children():
		if cell == null or not is_instance_valid(cell):
			continue
		if not filtering:
			cell.visible = true
			continue
		var iid = ""
		var dname = ""
		if "item_id" in cell:
			iid = str(cell.item_id)
		if "display_name" in cell:
			dname = str(cell.display_name)
		if iid.is_empty():
			# Empty usable or locked/capacity cells — hide while filtering.
			cell.visible = false
			continue
		cell.visible = InvSearchUtil.matches(q, iid, dname)



func _on_inventory_split(item_id: String, qty: int) -> void:
	item_id = item_id.strip_edges()
	if item_id.is_empty() or qty <= 1:
		return
	ctrl._qty_mode = "split"
	ctrl._show_drop_qty_dialog(item_id, qty - 1)
	if ctrl._drop_qty_label != null:
		ctrl._drop_qty_label.text = "拆分：%s（最多 %d）" % [ctrl._item_label(item_id), qty - 1]



func _on_inventory_lock(item_id: String) -> void:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return
	var on = true
	for it in ctrl._server_inventory:
		if typeof(it) == TYPE_DICTIONARY and str(it.get("id", "")) == item_id:
			on = not bool(it.get("locked", false))
			break
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_inventory_lock"):
		ctrl._world_combat.request_inventory_lock(item_id, on)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_inventory_lock"):
			ctrl._apply_equip_result_locally(srv.try_inventory_lock(item_id, on))



func _on_inventory_item_drop(item_id: String) -> void:
	## Drag bag item onto world → if stack>1 ask qty (default 1), else drop 1.
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return
	var have: int = _inventory_qty(item_id)
	if have <= 0:
		# Snapshot may lag; still attempt drop 1.
		have = 1
	if have > 1:
		ctrl._qty_mode = "drop"
		ctrl._show_drop_qty_dialog(item_id, have)
		return
	ctrl._commit_drop_item(item_id, 1)



func _on_inventory_item_pressed(item_id: String) -> void:
	## Double-click from InvSlot: equipment toggles via MockServer.try_use_item → try_toggle_equip;
	## consumables use as before.
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_use_item"):
		ctrl._world_combat.request_use_item(item_id)
	else:
		ctrl.append_system("无法使用：%s" % item_id)



func _build_gold_float() -> void:
	if ctrl._gold_float != null and is_instance_valid(ctrl._gold_float):
		return
	ctrl._gold_float = Label.new()
	ctrl._gold_float.name = "GoldGainFloat"
	ctrl._gold_float.visible = false
	ctrl._gold_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._gold_float.z_index = 75
	ctrl._gold_float.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ctrl._gold_float.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ctrl._gold_float.add_theme_font_size_override("font_size", 14)
	# Yellow/gold — distinct from cyan exp float.
	ctrl._gold_float.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22, 1.0))
	ctrl._gold_float.add_theme_color_override("font_outline_color", Color(0.18, 0.08, 0.0, 0.92))
	ctrl._gold_float.add_theme_constant_override("outline_size", 3)
	ctrl._gold_float.text = "金币 +0"
	ctrl.add_child(ctrl._gold_float)



func _layout_gold_float() -> void:
	if ctrl._gold_float == null:
		return
	ctrl._gold_float.reset_size()
	var pos = Vector2(16.0, 136.0)
	var panel = ctrl.get_node_or_null("%StatusPanel") as Control
	if panel != null and is_instance_valid(panel):
		var pr: Rect2 = panel.get_global_rect()
		# Just under exp float band (exp sits at +4 under status).
		pos = Vector2(pr.position.x + 8.0, pr.position.y + pr.size.y + 22.0) - ctrl.global_position
	ctrl._gold_float.position = pos



func _tick_gold_float(delta: float) -> void:
	if ctrl._gold_float_ttl <= 0.0:
		return
	ctrl._gold_float_ttl -= delta
	if ctrl._gold_float != null and is_instance_valid(ctrl._gold_float):
		var a: float = 1.0
		if ctrl._gold_float_ttl < 0.4:
			a = clampf(ctrl._gold_float_ttl / 0.4, 0.0, 1.0)
		ctrl._gold_float.modulate = Color(1, 1, 1, a)
		var rise: float = (GOLD_FLOAT_DURATION - maxf(ctrl._gold_float_ttl, 0.0)) * 10.0
		_layout_gold_float()
		ctrl._gold_float.position.y -= rise
	if ctrl._gold_float_ttl <= 0.0:
		ctrl.hide_gold_gain_float()



func _inv_qty_map(items: Array) -> Dictionary:
	var m: Dictionary = {}
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var iid = str(it.get("id", "")).strip_edges()
		if iid.is_empty():
			continue
		m[iid] = int(m.get(iid, 0)) + maxi(int(it.get("qty", 0)), 0)
	return m



func _inv_qty(item_id: String) -> int:
	item_id = item_id.strip_edges()
	var n = 0
	for it in ctrl._server_inventory:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("id", "")) == item_id:
			n += int(it.get("qty", 0))
	return n


