extends VBoxContainer
## Shared item selection surface: bag-sized cells, count badges, comparison tooltip,
## selected-item description, bounded scrolling, stable selection after refresh.
signal item_selected(item: Dictionary)
const Cell = preload("res://scripts/ui/item_grid_cell.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
var items: Array = []
var selected_key := ""
var empty_text := "暂无物品"
var minimum_cells := 8
var ctrl
var cells: GridContainer
var scroll: ScrollContainer
var detail: Label
var _restore_scroll := 0
var interaction_locked := false
var search: LineEdit
var category: OptionButton
var _shown_count := 0
var _toolbar: HBoxContainer

static func display_cell(owner_hud, parent: Node, item: Dictionary):
	var id := str(item.get("item_id", item.get("id", "")))
	var cell := Cell.new()
	cell.custom_minimum_size = Vector2(42, 42)
	cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(cell)
	cell.setup(id, int(item.get("qty", 1)), str(item.get("name", owner_hud._item_label(id))), -1, int(item.get("icon_index", owner_hud._item_icon_index(id))), str(item.get("icon_ref", owner_hud._item_icon_ref(id))))
	cell.item_tooltip = owner_hud._equip_compare_tip(id, "%s ×%d%s" % [cell.display_name, cell.qty, "\n" + str(item.hint) if item.has("hint") else ""])
	return cell

static func create(owner_hud, parent: Node, node_name: String, height: float = 100):
	var grid = load("res://scripts/ui/item_grid.gd").new()
	grid.name = node_name
	grid.ctrl = owner_hud
	grid.custom_minimum_size.y = height
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	return grid

func _ready() -> void:
	_restore_scroll = int(ctrl.get_meta("grid_scroll_" + str(name), 0))
	add_theme_constant_override("separation", 4)
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 6)
	add_child(_toolbar)
	search = LineEdit.new()
	search.name = "ItemSearch"
	search.placeholder_text = "搜索物品…"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.x = 60
	_toolbar.add_child(search)
	category = OptionButton.new()
	category.name = "ItemCategory"
	category.custom_minimum_size.x = 66
	category.fit_to_longest_item = false
	for title in ["全部", "消耗", "装备", "材料", "其他"]: category.add_item(title)
	_toolbar.add_child(category)
	_toolbar.visible = str(name) in ["WarehouseBag", "WarehouseStorage", "TradeBag", "BuyCatalog", "SellCatalog", "BuybackCatalog", "MailItemPicker", "AuctionItemPicker", "CraftRecipes"]
	search.text = str(ctrl.get_meta("grid_query_" + str(name), ""))
	category.select(int(ctrl.get_meta("grid_category_" + str(name), 0)))
	search.text_changed.connect(func(_text): _filter_cells(); scroll.scroll_vertical = 0)
	category.item_selected.connect(func(_index): _filter_cells(); scroll.scroll_vertical = 0)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 44
	add_child(scroll)
	cells = GridContainer.new()
	cells.name = "ItemCells"
	cells.columns = 1
	cells.add_theme_constant_override("h_separation", 4)
	cells.add_theme_constant_override("v_separation", 4)
	scroll.add_child(cells)
	detail = Label.new()
	detail.custom_minimum_size.y = 30
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", L2Style.COL_MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.max_lines_visible = 2
	add_child(detail)
	move_child(detail, 1)
	scroll.resized.connect(_fit_columns)
	_update_detail()

func _fit_columns() -> void:
	if cells: cells.columns = maxi(1, int((scroll.size.x - 14) / 46))

func set_items(source: Array) -> void:
	if not items.is_empty(): _restore_scroll = scroll.scroll_vertical
	items.clear()
	for node in cells.get_children():
		cells.remove_child(node)
		node.queue_free()
	for entry in source:
		if not entry is Dictionary: continue
		var item: Dictionary = entry.duplicate(true)
		var id := str(item.get("item_id", item.get("id", "")))
		if id.is_empty() or int(item.get("qty", 1)) <= 0: continue
		item["item_id"] = id
		item["key"] = str(item.get("key", id))
		item["qty"] = int(item.get("qty", 1))
		item["name"] = str(item.get("name", ctrl._item_label(id)))
		items.append(item)
		var cell := Cell.new()
		cell.custom_minimum_size = Vector2(42, 42)
		cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		cell.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		cells.add_child(cell)
		cell.setup(id, item.qty, item.name, -1, int(item.get("icon_index", ctrl._item_icon_index(id))), str(item.get("icon_ref", ctrl._item_icon_ref(id))))
		cell.set_meta("item_key", item.key)
		cell.set_meta("item_type", str(ctrl._item_def(id).get("type", "misc")))
		cell.item_tooltip = ctrl._equip_compare_tip(id, "%s ×%d%s" % [ctrl._item_rarity_name_line(id, item.name), item.qty, "\n" + str(item.hint) if item.has("hint") else ""])
		cell.activated.connect(func(_id): select_key(str(item.key)))
	# Empty cells communicate the same inventory surface even with no stock.
	for i in maxi(0, minimum_cells - items.size()):
		var empty := Cell.new()
		empty.custom_minimum_size = Vector2(42, 42)
		empty.focus_mode = Control.FOCUS_NONE
		cells.add_child(empty)
		empty.focus_mode = Control.FOCUS_NONE
	if selected_item().is_empty(): selected_key = ""
	_refresh_selection()
	_filter_cells()
	_fit_columns()
	scroll.set_deferred("scroll_vertical", _restore_scroll)

func _exit_tree() -> void:
	if is_instance_valid(ctrl) and not ctrl.is_queued_for_deletion() and is_instance_valid(scroll):
		ctrl.set_meta("grid_scroll_" + str(name), scroll.scroll_vertical)
		ctrl.set_meta("grid_query_" + str(name), search.text)
		ctrl.set_meta("grid_category_" + str(name), category.selected)

func selected_item() -> Dictionary:
	for item in items:
		if item.key == selected_key: return item
	return {}

func select_key(key: String, notify: bool = true) -> void:
	if interaction_locked and notify: return
	selected_key = key
	if selected_item().is_empty(): selected_key = ""
	_refresh_selection()
	if notify: item_selected.emit(selected_item())

func _refresh_selection() -> void:
	for cell in cells.get_children():
		cell.selected = not selected_key.is_empty() and cell.get_meta("item_key", "") == selected_key
		cell.queue_redraw()
	_update_detail()

func _update_detail() -> void:
	var item := selected_item()
	detail.text = (empty_text if items.is_empty() else "选择物品查看详情") if item.is_empty() else "%s ×%d%s" % [item.name, item.qty, " · " + str(item.hint) if item.has("hint") else ""]
	if _toolbar.visible and _shown_count == 0 and not items.is_empty(): detail.text = "没有匹配的物品" if item.is_empty() else "没有匹配项 · 已选：%s ×%d" % [item.name, item.qty]
	detail.tooltip_text = detail.text

func fill_inventory(source: Array) -> void:
	var allowed: Array = []
	for item in source:
		if item is Dictionary and not item.get("locked", false) and not item.get("bound", false): allowed.append(item)
	set_items(allowed)

func sync_quantity(spin: SpinBox) -> void:
	var qty := int(selected_item().get("qty", 0))
	spin.editable = qty > 0
	spin.max_value = maxi(1, qty)


static func show_rewards(owner_hud, parent: Node, reward: Dictionary, fallback: String = "") -> void:
	var parts: PackedStringArray = []
	if int(reward.get("exp", 0)) > 0: parts.append("经验 %d" % int(reward.exp))
	if int(reward.get("gold", 0)) > 0: parts.append("金币 %d" % int(reward.gold))
	if not parts.is_empty(): owner_hud._add_label(parent, " · ".join(parts), 11, L2Style.COL_GOLD)
	var rewards: Array = reward.get("items", [])
	if not rewards.is_empty():
		var grid = create(owner_hud, parent, "RewardItems", 86)
		grid.minimum_cells = 0
		grid.set_items(rewards)
	elif reward.is_empty() and not fallback.is_empty():
		owner_hud._add_label(parent, fallback, 11, L2Style.COL_MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func set_interaction_locked(locked: bool) -> void:
	interaction_locked = locked
	search.editable = not locked
	category.disabled = locked
	for cell in cells.get_children(): cell.mouse_default_cursor_shape = Control.CURSOR_WAIT if locked else Control.CURSOR_ARROW


func _filter_cells() -> void:
	_shown_count = 0
	var query := search.text.strip_edges().to_lower() if _toolbar.visible else ""
	var kind: String = ["", "consumable", "equipment", "material", "misc"][category.selected] if _toolbar.visible else ""
	for cell in cells.get_children():
		if cell.item_id.is_empty():
			cell.visible = query.is_empty() and kind.is_empty()
			continue
		cell.visible = (query.is_empty() or cell.display_name.to_lower().contains(query) or cell.item_id.to_lower().contains(query)) and (kind.is_empty() or cell.get_meta("item_type", "misc") == kind)
		if cell.visible: _shown_count += 1
	_update_detail()
