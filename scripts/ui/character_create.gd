extends Control
const Net = preload("res://scripts/net/net.gd")
const MV = preload("res://scripts/char/mv_generator.gd")
const LookCatalog = preload("res://scripts/char/look_catalog.gd")

@onready var name_edit: LineEdit = %NewName
@onready var class_option: OptionButton = %ClassOption
@onready var gender_option: OptionButton = %GenderOption
@onready var preview: AnimatedSprite2D = %Preview
@onready var preview_host: Control = %PreviewHost
@onready var preview_label: Label = %PreviewLabel
@onready var portrait: TextureRect = %Portrait
@onready var slot_list: VBoxContainer = %SlotList
@onready var status_label: Label = %Status
@onready var create_btn: Button = %CreateButton
@onready var back_btn: Button = %BackButton

@onready var skin_on: CheckButton = %SkinOn
@onready var hair_on: CheckButton = %HairOn
@onready var cloth_on: CheckButton = %ClothOn
@onready var skin_color_btn: Button = %SkinColor
@onready var hair_color_btn: Button = %HairColor
@onready var cloth_color_btn: Button = %ClothColor
@onready var palette_popup: PopupPanel = %PalettePopup
@onready var popup_grid: GridContainer = %PopupGrid
@onready var random_btn: Button = %RandomButton

var _pick_group: String = ""
var _palette_group: String = ""

var _gender: String = LookCatalog.GENDER_FEMALE
var _part_ids: Dictionary = {}
var _custom := Customization.new()
var _thumb_token: int = 0
var _recompose_gen: int = 0


func _ready() -> void:
	class_option.clear()
	class_option.add_item("冒险者", 0); class_option.set_item_metadata(0, "adventurer")
	class_option.add_item("法师", 1); class_option.set_item_metadata(1, "mage")
	class_option.add_item("战士", 2); class_option.set_item_metadata(2, "warrior")

	gender_option.clear()
	gender_option.add_item("女", 0); gender_option.set_item_metadata(0, LookCatalog.GENDER_FEMALE)
	gender_option.add_item("男", 1); gender_option.set_item_metadata(1, LookCatalog.GENDER_MALE)
	gender_option.add_item("儿童", 2); gender_option.set_item_metadata(2, LookCatalog.GENDER_KID)
	gender_option.select(0)

	create_btn.pressed.connect(_on_create)
	back_btn.pressed.connect(func(): Net.session().go_character_select())
	gender_option.item_selected.connect(func(_i): _on_gender_selected())
	random_btn.pressed.connect(_on_random)
	name_edit.text_submitted.connect(func(_t): _on_create())
	name_edit.text_changed.connect(_on_name_changed)
	Net.server().character_created.connect(_on_created)

	if not preview_host.resized.is_connected(_center_preview):
		preview_host.resized.connect(_center_preview)

	_sync_customization_ui()
	skin_on.toggled.connect(func(on): _custom.skin_on = on; _recompose())
	hair_on.toggled.connect(func(on): _custom.hair_on = on; _recompose())
	cloth_on.toggled.connect(func(on): _custom.cloth_on = on; _recompose())
	skin_color_btn.pressed.connect(func(): _open_palette("skin", skin_color_btn))
	hair_color_btn.pressed.connect(func(): _open_palette("hair", hair_color_btn))
	cloth_color_btn.pressed.connect(func(): _open_palette("cloth", cloth_color_btn))

	status_label.text = "选性别 / 职业，逐个部件捏脸，可实时预览"
	name_edit.grab_focus()
	_set_gender(LookCatalog.GENDER_FEMALE)
	call_deferred("_center_preview")



func _center_preview() -> void:
	if preview and preview_host:
		preview.position = preview_host.size * 0.5


func _on_gender_selected() -> void:
	_set_gender(_current_gender())


func _current_gender() -> String:
	var idx := gender_option.selected
	if idx >= 0:
		return LookCatalog.normalize_gender(str(gender_option.get_item_metadata(idx)))
	return LookCatalog.GENDER_FEMALE


func _set_gender(gender: String) -> void:
	_gender = gender
	_part_ids = MV.default_parts(gender)
	_rebuild_slot_ui()
	_recompose()


# ---- 部件槽位 UI ----

func _rebuild_slot_ui() -> void:
	_thumb_token += 1
	for c in slot_list.get_children():
		c.queue_free()

	for slot: Dictionary in MV.slots_for(_gender):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var lab := Label.new()
		lab.text = slot.label as String
		lab.custom_minimum_size = Vector2(72, 0)
		lab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lab)

		var opt := OptionButton.new()
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opt.custom_minimum_size = Vector2(0, 40)
		opt.expand_icon = true
		opt.add_theme_constant_override("icon_max_width", 40)
		var idx := 0
		var cat: String = slot.cat
		var src: String = slot.src as String
		opt.set_meta("slot_cat", cat)
		opt.set_meta("slot_src", src)
		var cur := int(_part_ids.get(cat, -1))
		var selected := -1
		if slot.optional as bool:
			opt.add_item("无", -1)
			if cur < 0:
				selected = 0
			idx += 1
		var variants := MV.list_variants(src, _gender, cat)
		for v in variants:
			var vid := int(v)
			# 先只塞文字，图标等打开下拉再懒加载（进页不再卡死）
			opt.add_item(str(vid), vid)
			if vid == cur:
				selected = idx
			idx += 1
		if selected >= 0:
			opt.select(selected)
		elif opt.item_count > 0:
			opt.select(0)
		opt.item_selected.connect(func(i): _on_slot(cat, opt.get_item_id(i), opt, src))
		var popup := opt.get_popup()
		popup.about_to_popup.connect(_on_slot_about_to_popup.bind(opt, cat, src, _thumb_token))
		row.add_child(opt)
		slot_list.add_child(row)
	# 选中项图标很少，一次填完；整表缩略图仍等打开下拉再懒加载
	_fill_selected_slot_icons(_thumb_token)


func _fill_selected_slot_icons(token: int) -> void:
	if token != _thumb_token:
		return
	for row in slot_list.get_children():
		if token != _thumb_token:
			return
		if not (row is HBoxContainer) or row.get_child_count() < 2:
			continue
		var opt := row.get_child(1) as OptionButton
		if opt == null:
			continue
		var cat := str(opt.get_meta("slot_cat", ""))
		var src := str(opt.get_meta("slot_src", "Face"))
		if cat.is_empty():
			continue
		var i := opt.selected
		if i < 0:
			continue
		var sid := opt.get_item_id(i)
		if sid >= 0 and opt.get_item_icon(i) == null:
			opt.set_item_icon(i, MV.variant_layer_thumb(src, _gender, cat, sid, 40))


## 打开某槽下拉时，按帧填充该槽所有变体的单层缩略图。
func _on_slot_about_to_popup(opt: OptionButton, cat: String, src: String, token: int) -> void:
	_fill_slot_icons(opt, cat, src, token)


func _fill_slot_icons(opt: OptionButton, cat: String, src: String, token: int) -> void:
	if token != _thumb_token or not is_instance_valid(opt):
		return
	for i in range(opt.item_count):
		if token != _thumb_token or not is_instance_valid(opt):
			return
		var vid := opt.get_item_id(i)
		if vid < 0:
			continue
		if opt.get_item_icon(i) != null:
			continue
		opt.set_item_icon(i, MV.variant_layer_thumb(src, _gender, cat, vid, 40))
		# 每填几张让出一帧，避免展开瞬间卡一下
		if (i % 6) == 5:
			await get_tree().process_frame


func _on_slot(cat: String, variant: int, opt: OptionButton = null, src: String = "Face") -> void:
	if variant < 0:
		_part_ids.erase(cat)
	else:
		_part_ids[cat] = variant
		# 只更新当前按钮显示的图标，不重建整表
		if opt != null and is_instance_valid(opt):
			var i := opt.selected
			if i >= 0 and opt.get_item_icon(i) == null:
				opt.set_item_icon(i, MV.variant_layer_thumb(src, _gender, cat, variant, 40))
	_recompose()


# ---- 预览 ----

## 同帧多次改部件只跑最后一次；用轻量 compose_preview，不切四向。
func _recompose() -> void:
	_recompose_gen += 1
	call_deferred("_recompose_run", _recompose_gen)


func _recompose_run(gen: int) -> void:
	if gen != _recompose_gen:
		return
	var parts := MV.apply_equipment(_part_ids, _custom.equipment)
	var res := MV.compose_preview(_gender, parts, _custom.colors())
	preview.sprite_frames = res["frames"]
	preview.scale = Vector2(3, 3)
	call_deferred("_center_preview")
	if preview.sprite_frames.has_animation("walk_front"):
		preview.play("walk_front")
	preview_label.text = "走动预览"
	portrait.texture = res["portrait"]


# ---- 校验 / 创建 ----

func _validate_name(name: String) -> String:
	var n := name.strip_edges()
	if n.is_empty():
		return "请输入角色名"
	if n.length() > 12:
		return "名字太长（最多 12 字）"
	var chars: Array = Net.session().characters if Net.session() != null else []
	for c in chars:
		if typeof(c) == TYPE_DICTIONARY and str(c.get("name", "")) == n:
			return "名字已被占用"
	return ""


func _on_name_changed(_text: String) -> void:
	if create_btn.disabled:
		return
	var msg := _validate_name(name_edit.text)
	if msg != "":
		status_label.text = msg
		create_btn.disabled = true
	else:
		status_label.text = "选性别 / 职业，逐个部件捏脸，可实时预览"
		create_btn.disabled = false


func _on_create() -> void:
	var class_id := "adventurer"
	var idx := class_option.selected
	if idx >= 0:
		class_id = str(class_option.get_item_metadata(idx))
	_gender = _current_gender()
	var name_msg := _validate_name(name_edit.text)
	if name_msg != "":
		status_label.text = name_msg
		create_btn.disabled = true
		return
	create_btn.disabled = true
	_custom.part_ids = _part_ids.duplicate()
	var res := MV.compose_all(_gender, _custom.effective_part_ids(), _custom.colors())
	var dir := "user://rmmo/mv_chars"
	MV.ensure_dir(dir)
	var sheet_path := "%s/char_%d.png" % [dir, Time.get_ticks_msec()]
	res["sheet"].save_png(sheet_path)
	_custom.mv_sheet = sheet_path
	Net.server().create_character(name_edit.text, class_id, "", _gender, _custom.to_dict())


# ---- MV 官方调色板（读 Generator/gradients.png）----

## 点当前色按钮 -> 在按钮下方弹出该分组的取色浮窗。
func _open_palette(group: String, btn: Button) -> void:
	_pick_group = group
	if _palette_group != group:
		_fill_palette(popup_grid, MV.palette_for(group), _on_pick_swatch)
		_palette_group = group
	var gp := btn.get_global_position()
	palette_popup.position = Vector2i(int(gp.x), int(gp.y + btn.size.y))
	palette_popup.popup()


func _on_pick_swatch(entry: Dictionary) -> void:
	var row := int(entry["index"])
	match _pick_group:
		"skin":
			_custom.skin_row = row
			_custom.skin_on = true
		"hair":
			_custom.hair_row = row
			_custom.hair_on = true
		"cloth":
			_custom.cloth_row = row
			_custom.cloth_on = true
	palette_popup.hide()
	_sync_customization_ui()
	_recompose()


## 把按钮染成当前选中的颜色，作为「当前色」展示。
func _set_btn_color(btn: Button, col: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = col
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = col.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = col.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", pressed)


func _fill_palette(grid: GridContainer, entries: Array, on_pick: Callable) -> void:
	for c in grid.get_children():
		c.queue_free()
	for e in entries:
		_add_swatch(grid, e as Dictionary, on_pick)


func _add_swatch(grid: GridContainer, entry: Dictionary, on_pick: Callable) -> void:
	var col: Color = entry["color"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(16, 16)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "色带 %d (#%s)" % [int(entry["index"]), col.to_html(false)]
	# 注意：flat 按钮不绘制 normal 底色，色块会全隐形，必须用普通按钮 + StyleBox。
	var normal := StyleBoxFlat.new()
	normal.bg_color = col
	b.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = col.lightened(0.2)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = col.darkened(0.2)
	b.add_theme_stylebox_override("pressed", pressed)
	b.pressed.connect(on_pick.bind(entry))
	grid.add_child(b)


func _sync_customization_ui() -> void:
	skin_on.button_pressed = _custom.skin_on
	hair_on.button_pressed = _custom.hair_on
	cloth_on.button_pressed = _custom.cloth_on
	_set_btn_color(skin_color_btn, MV.row_color(_custom.skin_row))
	_set_btn_color(hair_color_btn, MV.row_color(_custom.hair_row))
	_set_btn_color(cloth_color_btn, MV.row_color(_custom.cloth_row))


func _on_random() -> void:
	_custom.randomize_colors()
	_part_ids = MV.random_parts(_gender)
	_sync_customization_ui()
	if slot_list.get_child_count() == 0:
		_rebuild_slot_ui()
	else:
		_sync_slot_selections()
	_recompose()
	status_label.text = "已随机生成捏脸外观"


func _sync_slot_selections() -> void:
	for row in slot_list.get_children():
		if not (row is HBoxContainer) or row.get_child_count() < 2:
			continue
		var opt := row.get_child(1) as OptionButton
		if opt == null:
			continue
		var cat := str(opt.get_meta("slot_cat", ""))
		var src := str(opt.get_meta("slot_src", "Face"))
		var cur := int(_part_ids.get(cat, -1))
		var selected := -1
		for i in range(opt.item_count):
			if opt.get_item_id(i) == cur:
				selected = i
				break
		if selected < 0:
			continue
		opt.select(selected)
		if cur >= 0 and opt.get_item_icon(selected) == null:
			opt.set_item_icon(selected, MV.variant_layer_thumb(src, _gender, cat, cur, 40))


func _on_created(ok: bool, message: String, character: Dictionary) -> void:
	create_btn.disabled = false
	status_label.text = message
	if ok:
		Net.session().pending_select_id = int(character.get("id", -1))
		Net.session().selected_character = character.duplicate(true)
		Net.session().go_character_select()
