extends RefCounted
## UI panel: crafting and gathering.

var ctrl
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const GameWindow = preload("res://scripts/ui/game_window.gd")
const RecipeCatalog = preload("res://scripts/net/combat/recipe_catalog.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

func _ensure_craft_recipes_loaded() -> void:
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



func _build_craft_panel() -> void:
	ctrl._craft_panel = PanelContainer.new()
	ctrl._craft_panel.name = "CraftPanel"
	ctrl._craft_panel.set_script(GameWindow)
	ctrl._craft_panel.screen_margin = 4.0
	ctrl._craft_panel.min_size = Vector2(360, 280)
	ctrl._craft_panel.default_size = Vector2(480, 420)
	ctrl._craft_panel.initial_dock = "none"
	ctrl._craft_panel.drag_anywhere = true
	ctrl.add_child(ctrl._craft_panel)
	var outer = GameWindow.build_body(ctrl._craft_panel, "制作", func(): ctrl._craft_panel.visible = false, "CraftTitle")
	ctrl._craft_body = VBoxContainer.new()
	ctrl._craft_body.name = "CraftBody"
	ctrl._craft_body.add_theme_constant_override("separation", 6)
	ctrl._craft_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(ctrl._craft_body)
	ctrl._craft_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._craft_panel)
	_ensure_craft_recipes_loaded()
	_refresh_craft_panel()
	ctrl.call_deferred("_nudge_craft")



func _nudge_craft() -> void:
	if ctrl._craft_panel == null:
		return
	ctrl._craft_panel.size = Vector2(480, 420)
	var vp = ctrl.get_viewport_rect().size
	ctrl._window_manager_logic.place_at(ctrl._craft_panel, Vector2(maxi(8, int(vp.x * 0.55 - 240)), 64))



func _toggle_craft_panel(force_open: bool = false) -> void:
	if ctrl._craft_panel == null:
		return
	if force_open:
		ctrl._craft_panel.visible = true
	else:
		ctrl._craft_panel.visible = not ctrl._craft_panel.visible
	if ctrl._craft_panel.visible:
		_ensure_craft_recipes_loaded()
		_refresh_craft_panel()
		ctrl._craft_panel.move_to_front()
		ctrl.call_deferred("_nudge_craft")



func _refresh_craft_panel() -> void:
	if ctrl._craft_body == null: return
	for child in ctrl._craft_body.get_children():
		ctrl._craft_body.remove_child(child)
		child.queue_free()
	ctrl._craft_qty_spin = null
	_ensure_craft_recipes_loaded()
	ctrl._add_label(ctrl._craft_body, "制作 Lv.%d · %d/%d    金币 %d" % [ctrl._craft_level, ctrl._craft_xp, ctrl._craft_xp_to_next, ctrl._server_gold], 11, L2Style.COL_MUTED)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	ctrl._craft_body.add_child(columns)
	var recipe_grid = ItemGrid.create(ctrl, columns, "CraftRecipes", 180)
	recipe_grid.custom_minimum_size.x = 150
	recipe_grid.size_flags_stretch_ratio = 0.8
	var recipe_items: Array = []
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	columns.add_child(detail)
	var selected: Dictionary = {}
	for rec in ctrl._craft_recipes:
		if not rec is Dictionary: continue
		var id := str(rec.get("id", ""))
		if id.is_empty(): continue
		if ctrl._craft_selected_id.is_empty(): ctrl._craft_selected_id = id
		var entry: Dictionary = rec.get("output", {}).duplicate(true)
		entry["key"] = id
		entry["name"] = str(rec.get("name", id))
		recipe_items.append(entry)
		if id == ctrl._craft_selected_id: selected = rec
	recipe_grid.set_items(recipe_items)
	recipe_grid.select_key(ctrl._craft_selected_id, false)
	recipe_grid.item_selected.connect(func(item): _on_craft_select(str(item.get("key", ""))))
	if selected.is_empty():
		ctrl._add_label(detail, "暂无可用配方", 12, L2Style.COL_MUTED)
		return
	var output: Dictionary = selected.get("output", {})
	ctrl._add_label(detail, "%s ×%d" % [ctrl._item_label(str(output.get("id", ""))), int(output.get("qty", 1))], 14, L2Style.COL_TITLE)
	ItemGrid.display_cell(ctrl, detail, output)
	detail.add_child(L2Style.hairline())
	ctrl._add_label(detail, "所需材料 · 持有 / 每份", 11, L2Style.COL_MUTED)
	var ingredients: Array = []
	var max_craft := 99
	for ingredient in selected.get("ingredients", []):
		var id := str(ingredient.get("id", ""))
		var need := maxi(1, int(ingredient.get("qty", 1)))
		var have: int = ctrl._inv_qty(id)
		max_craft = mini(max_craft, int(have / need))
		ingredients.append({"id": id, "qty": need, "hint": "持有 %d / 需要 %d%s" % [have, need, " · 不足" if have < need else ""]})
	var material_grid = ItemGrid.create(ctrl, detail, "CraftMaterials", 90)
	material_grid.minimum_cells = 0
	material_grid.set_items(ingredients)
	if not ingredients.is_empty(): material_grid.select_key(str(ingredients[0].id), false)
	var cost := maxi(0, int(selected.get("gold_cost", 0)))
	if cost > 0: max_craft = mini(max_craft, int(ctrl._server_gold / cost))
	ctrl._add_label(detail, "每份 %d 金币" % cost, 11, L2Style.COL_MUTED)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(spacer)
	ctrl._craft_qty_spin = SpinBox.new()
	ctrl._craft_qty_spin.min_value = 1
	ctrl._craft_qty_spin.max_value = maxi(1, max_craft)
	ctrl._craft_qty_spin.editable = max_craft > 0
	GameWindow.field(detail, "制作数量", ctrl._craft_qty_spin)
	var craft := Button.new()
	craft.text = "制作" if max_craft > 0 else "材料或金币不足"
	craft.disabled = max_craft <= 0
	craft.custom_minimum_size.y = 32
	L2Style.style_primary_button(craft)
	craft.pressed.connect(_on_craft_pressed.bind(str(selected.get("id", ""))))
	detail.add_child(craft)


func _on_craft_select(recipe_id: String) -> void:
	ctrl._craft_selected_id = str(recipe_id).strip_edges()
	_refresh_craft_panel()



func _on_craft_pressed(recipe_id: String) -> void:
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
		_apply_craft_result_locally(srv.try_craft(recipe_id, qty))
	else:
		ctrl.append_system("无法制作。")



func apply_craft_update(action: Dictionary) -> void:
	if action.has("craft_level"):
		ctrl._craft_level = maxi(int(action.get("craft_level", 1)), 1)
	if action.has("craft_xp"):
		ctrl._craft_xp = maxi(int(action.get("craft_xp", 0)), 0)
	if action.has("craft_xp_to_next"):
		ctrl._craft_xp_to_next = maxi(int(action.get("craft_xp_to_next", 0)), 0)
	if ctrl._craft_panel != null and ctrl._craft_panel.visible:
		_refresh_craft_panel()



func apply_gather_update(action: Dictionary) -> void:
	## Profession skill packet (gather_level/xp). Node deplete packets omit these keys.
	if action.has("gather_level"):
		ctrl._gather_level = maxi(int(action.get("gather_level", 1)), 1)
	if action.has("gather_xp"):
		ctrl._gather_xp = maxi(int(action.get("gather_xp", 0)), 0)
	if action.has("gather_xp_to_next"):
		ctrl._gather_xp_to_next = maxi(int(action.get("gather_xp_to_next", 0)), 0)
	if ctrl._gather_level_label != null and is_instance_valid(ctrl._gather_level_label):
		ctrl._gather_level_label.text = "采集 Lv.%d" % ctrl._gather_level



func _apply_craft_result_locally(result: Dictionary) -> void:
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
				apply_craft_update(action)
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)
	if ctrl._craft_panel != null and ctrl._craft_panel.visible:
		_refresh_craft_panel()

