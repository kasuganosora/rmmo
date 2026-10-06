extends ConfirmationDialog
signal map_chosen(path: String)
const Catalog = preload("res://scripts/world_editor/resource_pack_catalog.gd")
var catalog = Catalog.new()
var _packs: Array[Dictionary] = []
var _maps: Array[Dictionary] = []
var _pack_list: ItemList
var _map_list: Tree
var _search: LineEdit
var _hint: Label
var _location: Label
var _current := ""

func _ready() -> void:
	title = "资源包地图"
	theme = preload("res://scripts/world_editor/workspace_theme.gd").build()
	ok_button_text = "打开地图"
	cancel_button_text = "取消"
	exclusive = true
	var content := VBoxContainer.new()
	add_child(content)
	var description := Label.new()
	description.text = "资源包包含设置、NPC、地图和素材；默认包全局可用。"
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(description)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索地图名称 / 所属资源包"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text): _fill_maps())
	content.add_child(_search)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(split)
	_pack_list = ItemList.new()
	_pack_list.custom_minimum_size = Vector2(190, 240)
	_pack_list.item_selected.connect(_select_pack)
	split.add_child(_pack_list)
	_map_list = Tree.new()
	_map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_list.columns = 2
	_map_list.hide_root = true
	_map_list.column_titles_visible = true
	_map_list.set_column_title(0, "地图")
	_map_list.set_column_title(1, "所属资源包")
	_map_list.item_selected.connect(func(): get_ok_button().disabled = _map_list.get_selected() == null)
	_map_list.item_activated.connect(_open_selected)
	split.add_child(_map_list)
	_hint = Label.new()
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(_hint)
	_location = Label.new()
	_location.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(_location)
	confirmed.connect(_open_selected)

func show_maps(current_path: String) -> void:
	_current = current_path
	_search.clear()
	_packs = catalog.packs()
	_pack_list.clear()
	for pack in _packs:
		var text: String = pack.name + (" · 全局" if pack.shared else "")
		if pack.version != "": text += " · " + str(pack.version)
		var index := _pack_list.add_item(text)
		_pack_list.set_item_tooltip(index, str(pack.root))
	if _packs.is_empty():
		_maps.clear()
		_fill_maps()
		_location.text = catalog.root
		_hint.text = "没有找到资源包。每个资源包目录必须包含有效的 metadata.json（JSON 对象）。"
		_hint.tooltip_text = _hint.text
	else:
		var index: int = maxi(0, catalog.owner_of(current_path, _packs))
		_pack_list.select(index)
		_select_pack(index)
	popup_centered_clamped(Vector2i(800, 520), 0.9)

func _select_pack(index: int) -> void:
	_maps = catalog.available_maps(_packs[index], _packs)
	_location.text = str(_packs[index].root)
	_location.tooltip_text = _location.text
	_fill_maps()

func _fill_maps() -> void:
	_map_list.clear()
	get_ok_button().disabled = true
	var root_item := _map_list.create_item()
	var count := 0
	for map in _maps:
		if not _search.text.is_empty() and not (str(map.name) + " " + str(map.pack.name)).to_lower().contains(_search.text.to_lower()): continue
		var item := _map_list.create_item(root_item)
		item.set_text(0, str(map.name) + (" · 当前" if map.path == _current else ""))
		item.set_text(1, str(map.pack.name) + (" · 全局" if map.pack.shared else ""))
		item.set_metadata(0, map.path)
		item.set_tooltip_text(0, map.path)
		item.set_tooltip_text(1, str(map.pack.root))
		if map.path == _current: item.select(0)
		count += 1
	_hint.text = "%d 张地图 · 默认资源包的地图在所有资源包中可用，所属包单独标明。" % count if count > 0 else ("没有匹配的地图。" if not _search.text.is_empty() else "此资源包及默认包暂无 3D 地图（maps 下的 glTF）；旧 2D 地图不会在这里打开。")
	_hint.tooltip_text = _hint.text

func _open_selected() -> void:
	var item := _map_list.get_selected()
	if item == null: return
	var path := str(item.get_metadata(0))
	hide()
	map_chosen.emit(path)
