extends RefCounted
## UI panel: crafting and gathering.

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const RecipeCatalog = preload("res://scripts/net/combat/recipe_catalog.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

static func _ensure_craft_recipes_loaded(ctrl) -> void:
	if not ctrl._craft_recipes.is_empty():
		return
	var cat = RecipeCatalog.new()
	cat.load_catalog()
	ctrl._craft_recipes = cat.list_all()
	# Prefer live server catalog when available.
	var srv = Net.server()
	if srv != null and srv.get("recipe_catalog") != null and srv.recipe_catalog != null:
		if srv.recipe_catalog.has_method("list_all"):
			var live: Array = srv.recipe_catalog.list_all()
			if not live.is_empty():
				ctrl._craft_recipes = live

static func _build_craft_panel(ctrl) -> void:
	ctrl._craft_panel = PanelContainer.new()
	ctrl._craft_panel.name = "CraftPanel"
	ctrl._craft_panel.set_script(HudDrag)
	ctrl._craft_panel.screen_margin = 4.0
	ctrl._craft_panel.min_size = Vector2(360, 280)
	ctrl._craft_panel.default_size = Vector2(480, 420)
	ctrl._craft_panel.initial_dock = "none"
	ctrl._craft_panel.drag_anywhere = true
	ctrl.add_child(ctrl._craft_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._craft_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "CraftTitle"
	title.text = "制作"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._craft_panel.visible = false)
	head.add_child(close_btn)
	ctrl._craft_body = VBoxContainer.new()
	ctrl._craft_body.name = "CraftBody"
	ctrl._craft_body.add_theme_constant_override("separation", 6)
	ctrl._craft_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(ctrl._craft_body)
	ctrl._craft_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._craft_panel)
	ctrl._ensure_craft_recipes_loaded()
	ctrl._refresh_craft_panel()
	ctrl.call_deferred("_nudge_craft")

static func _nudge_craft(ctrl) -> void:
	if ctrl._craft_panel == null:
		return
	ctrl._craft_panel.size = Vector2(480, 420)
	var vp = ctrl.get_viewport_rect().size
	ctrl._craft_panel.global_position = Vector2(maxi(8, int(vp.x * 0.55 - 240)), 64)

static func _toggle_craft_panel(ctrl, force_open: bool = false) -> void:
	if ctrl._craft_panel == null:
		return
	if force_open:
		ctrl._craft_panel.visible = true
	else:
		ctrl._craft_panel.visible = not ctrl._craft_panel.visible
	if ctrl._craft_panel.visible:
		ctrl._ensure_craft_recipes_loaded()
		ctrl._refresh_craft_panel()
		ctrl._craft_panel.move_to_front()
		ctrl.call_deferred("_nudge_craft")

static func _refresh_craft_panel(ctrl) -> void:
	if ctrl._craft_body == null:
		return
	for c in ctrl._craft_body.get_children():
		c.queue_free()
	ctrl._craft_qty_spin = null
	ctrl._ensure_craft_recipes_loaded()
	ctrl._add_label(ctrl._craft_body, "选择配方后点击制作（任意地点）", 11, L2Style.COL_MUTED)
	ctrl._add_label(ctrl._craft_body, "金币 %d" % int(ctrl._server_gold), 12, L2Style.COL_TITLE)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 240)
	ctrl._craft_body.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	if ctrl._craft_recipes.is_empty():
		ctrl._add_label(list, "（暂无配方）", 11, L2Style.COL_MUTED)
	else:
		for rec in ctrl._craft_recipes:
			if typeof(rec) != TYPE_DICTIONARY:
				continue
			var rid = str(rec.get("id", "")).strip_edges()
			if rid.is_empty():
				continue
			var selected = rid == ctrl._craft_selected_id
			var box = VBoxContainer.new()
			box.add_theme_constant_override("separation", 2)
			list.add_child(box)
			var head_btn = Button.new()
			var rname = str(rec.get("name", rid))
			var out_v: Variant = rec.get("output", {})
			var out_id = ""
			var out_q = 1
			if typeof(out_v) == TYPE_DICTIONARY:
				out_id = str(out_v.get("id", "")).strip_edges()
				out_q = maxi(int(out_v.get("qty", 1)), 1)
			var out_label = ctrl._item_label(out_id) if not out_id.is_empty() else "?"
			head_btn.text = ("%s → %s×%d" % [rname, out_label, out_q]) if not selected else ("▸ %s → %s×%d" % [rname, out_label, out_q])
			head_btn.focus_mode = Control.FOCUS_NONE
			head_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			head_btn.pressed.connect(ctrl._on_craft_select.bind(rid))
			box.add_child(head_btn)
			var ings_v: Variant = rec.get("ingredients", [])
			var mats_ok = true
			if typeof(ings_v) == TYPE_ARRAY:
				for ing in ings_v:
					if typeof(ing) != TYPE_DICTIONARY:
						continue
					var iid = str(ing.get("id", "")).strip_edges()
					var need: int = maxi(int(ing.get("qty", 0)), 0)
					if iid.is_empty() or need <= 0:
						continue
					var have: int = ctrl._inv_qty(iid)
					if have < need:
						mats_ok = false
					var col = L2Style.COL_TITLE if have >= need else Color(0.95, 0.45, 0.45)
					ctrl._add_label(box, "  %s  %d / %d" % [ctrl._item_label(iid), have, need], 11, col)
			var gcost: int = maxi(int(rec.get("gold_cost", 0)), 0)
			if gcost > 0:
				var gcol = L2Style.COL_MUTED if int(ctrl._server_gold) >= gcost else Color(0.95, 0.45, 0.45)
				ctrl._add_label(box, "  金币 %d" % gcost, 11, gcol)
				if int(ctrl._server_gold) < gcost:
					mats_ok = false
			if selected:
				var row = HBoxContainer.new()
				row.add_theme_constant_override("separation", 6)
				box.add_child(row)
				ctrl._add_label(row, "数量", 12, L2Style.COL_TEXT)
				ctrl._craft_qty_spin = SpinBox.new()
				ctrl._craft_qty_spin.min_value = 1
				ctrl._craft_qty_spin.max_value = 99
				ctrl._craft_qty_spin.value = 1
				ctrl._craft_qty_spin.custom_minimum_size = Vector2(72, 0)
				row.add_child(ctrl._craft_qty_spin)
				var craft_btn = Button.new()
				craft_btn.text = "制作"
				craft_btn.focus_mode = Control.FOCUS_NONE
				craft_btn.disabled = not mats_ok
				craft_btn.pressed.connect(ctrl._on_craft_pressed.bind(rid))
				row.add_child(craft_btn)

	ctrl._add_label(
		ctrl._craft_body,
		"制作 Lv.%d (%d/%d)" % [ctrl._craft_level, ctrl._craft_xp, ctrl._craft_xp_to_next],
		11,
		L2Style.COL_MUTED
	)

static func _on_craft_select(ctrl, recipe_id: String) -> void:
	ctrl._craft_selected_id = str(recipe_id).strip_edges()
	ctrl._refresh_craft_panel()

static func _on_craft_pressed(ctrl, recipe_id: String) -> void:
	recipe_id = str(recipe_id).strip_edges()
	if recipe_id.is_empty():
		return
	var qty = 1
	if ctrl._craft_qty_spin != null:
		qty = clampi(int(ctrl._craft_qty_spin.value), 1, 99)
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_craft"):
		ctrl._world_combat.request_craft(recipe_id, qty)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_craft"):
		ctrl._apply_craft_result_locally(srv.try_craft(recipe_id, qty))
	else:
		ctrl.append_system("无法制作。")

static func apply_craft_update(ctrl, action: Dictionary) -> void:
	if action.has("craft_level"):
		ctrl._craft_level = maxi(int(action.get("craft_level", 1)), 1)
	if action.has("craft_xp"):
		ctrl._craft_xp = maxi(int(action.get("craft_xp", 0)), 0)
	if action.has("craft_xp_to_next"):
		ctrl._craft_xp_to_next = maxi(int(action.get("craft_xp_to_next", 0)), 0)
	if ctrl._craft_panel != null and ctrl._craft_panel.visible:
		ctrl._refresh_craft_panel()

static func apply_gather_update(ctrl, action: Dictionary) -> void:
	## Profession skill packet (gather_level/xp). Node deplete packets omit these keys.
	if action.has("gather_level"):
		ctrl._gather_level = maxi(int(action.get("gather_level", 1)), 1)
	if action.has("gather_xp"):
		ctrl._gather_xp = maxi(int(action.get("gather_xp", 0)), 0)
	if action.has("gather_xp_to_next"):
		ctrl._gather_xp_to_next = maxi(int(action.get("gather_xp_to_next", 0)), 0)
	if ctrl._gather_level_label != null and is_instance_valid(ctrl._gather_level_label):
		ctrl._gather_level_label.text = "采集 Lv.%d" % ctrl._gather_level

static func _apply_craft_result_locally(ctrl, result: Dictionary) -> void:
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
			"craft_update":
				ctrl.apply_craft_update(action)
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)
	if ctrl._craft_panel != null and ctrl._craft_panel.visible:
		ctrl._refresh_craft_panel()

