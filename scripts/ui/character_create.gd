extends Control
const Net = preload("res://scripts/net/net.gd")
const MV = preload("res://scripts/char/mv_generator.gd")
const LookCatalog = preload("res://scripts/char/look_catalog.gd")
const CharacterView3D = preload("res://scripts/char/character_view_3d.gd")
const Hairstyles = preload("res://scripts/char/character_hairstyles.gd")
var _view_3d: Node2D
var _portrait_3d: Node2D

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
@onready var skin_color_btn: Button = %SkinColor
@onready var hair_color_btn: Button = %HairColor
@onready var palette_popup: PopupPanel = %PalettePopup
@onready var popup_grid: GridContainer = %PopupGrid
@onready var random_btn: Button = %RandomButton

var _pick_group: String = ""
var _palette_group: String = ""

var _gender: String = LookCatalog.GENDER_FEMALE
var _part_ids: Dictionary = {}
var _custom := Customization.new()
var _female_body_model:="female_base_v2"
var _thumb_token: int = 0
var _recompose_gen: int = 0
var _preview_direction := "front"
var _preview_action := "walk"
var _preview_variant := ""


func _ready() -> void:
	class_option.clear()
	class_option.add_item("冒险者", 0); class_option.set_item_metadata(0, "adventurer")
	class_option.add_item("法师", 1); class_option.set_item_metadata(1, "mage")
	class_option.add_item("战士", 2); class_option.set_item_metadata(2, "warrior")

	gender_option.clear()
	gender_option.add_item("成年女性", 0); gender_option.set_item_metadata(0, LookCatalog.GENDER_FEMALE)
	gender_option.add_item("成年男性", 1); gender_option.set_item_metadata(1, LookCatalog.GENDER_MALE)
	gender_option.add_item("青年男性", 2); gender_option.set_item_metadata(2, LookCatalog.GENDER_YOUNG_MALE)
	gender_option.add_item("青年女性", 3); gender_option.set_item_metadata(3, LookCatalog.GENDER_YOUNG_FEMALE)
	gender_option.select(0)
	_custom.equipment = preload("res://scripts/char/starter_equipment.gd").PARTS.duplicate()
	_setup_animation_controls()
	if CharacterView3D.enabled():
		_view_3d=CharacterView3D.new()
		preview_host.add_child(_view_3d)
		_view_3d.scale=Vector2.ONE*2.6
		_portrait_3d=CharacterView3D.new()
		_portrait_3d.portrait_mode=true
		add_child(_portrait_3d)
		_portrait_3d.display.visible=false
		portrait.texture=_portrait_3d.viewport.get_texture()
		preview.visible=false
		_custom.skin_on=false;_custom.hair_on=true

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
	skin_color_btn.pressed.connect(func(): _open_palette("skin", skin_color_btn))
	hair_color_btn.pressed.connect(func(): _open_palette("hair", hair_color_btn))

	status_label.text = "选体型 / 职业，逐个部件捏脸，可切换方向和动作"
	name_edit.grab_focus()
	_set_gender(LookCatalog.GENDER_FEMALE)
	call_deferred("_center_preview")



func _center_preview() -> void:
	if preview and preview_host:
		preview.position = preview_host.size * 0.5
		if _view_3d!=null:_view_3d.position=preview_host.size*Vector2(.5,.82)


func _on_gender_selected() -> void:
	_set_gender(_current_gender())


func _current_gender() -> String:
	var idx := gender_option.selected
	if idx >= 0:
		return LookCatalog.normalize_gender(str(gender_option.get_item_metadata(idx)))
	return LookCatalog.GENDER_FEMALE


func _set_gender(gender: String) -> void:
	var previous_hair:=int(_part_ids.get("FrontHair1",1))
	if _custom.body_model=="female_base_v2":_female_body_model=_custom.body_model
	_custom.body_model=_female_body_model if gender=="female" else ""
	_gender = gender
	_part_ids = MV.default_parts(gender)
	if CharacterView3D.enabled():_part_ids={"Body":1,"FrontHair1":2 if gender.ends_with("female") else 1,"Eyes":1}
	if CharacterView3D.enabled() and gender in ["male","female"] and previous_hair in [10,11,12,13,14,15]:_part_ids.FrontHair1=previous_hair
	if CharacterView3D.enabled() and _custom.body_model=="female_base_v2":_part_ids.FrontHair1=Hairstyles.initial(gender,_custom.body_model,previous_hair)
	_rebuild_slot_ui()
	_recompose()


# ---- 部件槽位 UI ----

func _rebuild_slot_ui() -> void:
	_thumb_token += 1
	for c in slot_list.get_children():
		c.queue_free()
	if CharacterView3D.enabled():
		var row:=HBoxContainer.new()
		var label:=Label.new();label.text="发型";row.add_child(label)
		if _custom.body_model=="female_base_v2" or preload("res://scripts/char/character_imported_rig.gd").available(_gender):
			var imported_select:=OptionButton.new();imported_select.name="HairstyleSelect"
			imported_select.set_meta("slot_cat","FrontHair1")
			var choices:Dictionary=Hairstyles.options(_gender,_custom.body_model)
			for id in choices:imported_select.add_item(choices[id],id)
			imported_select.select(maxi(0,imported_select.get_item_index(int(_part_ids.get("FrontHair1",1)))))
			imported_select.item_selected.connect(func(i):_part_ids["FrontHair1"]=imported_select.get_item_id(i);_recompose())
			row.add_child(imported_select);slot_list.add_child(row)
			_add_imported_customization_controls()
			return
		var select:=OptionButton.new();select.add_item("短发",1);select.add_item("齐耳发",2)
		select.select(int(_part_ids.get("FrontHair1",1))-1)
		select.item_selected.connect(func(i):_part_ids["FrontHair1"]=i+1;_recompose())
		row.add_child(select);slot_list.add_child(row)
		return

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

func _add_imported_customization_controls()->void:
	var eye_row:=HBoxContainer.new();slot_list.add_child(eye_row)
	var label:=Label.new();label.text="瞳孔颜色";eye_row.add_child(label)
	var picker:=ColorPickerButton.new();picker.name="EyeColor";picker.edit_alpha=false
	picker.custom_minimum_size=Vector2(96,32)
	picker.color=Color.from_string(_custom.eye_color,Color("86a66b"))
	picker.color_changed.connect(func(color):_custom.eye_color="#"+color.to_html(false);_recompose())
	eye_row.add_child(picker)
	var reset:=Button.new();reset.text="原色";eye_row.add_child(reset)
	reset.pressed.connect(func():
		_custom.eye_color="";picker.set_block_signals(true);picker.color=Color("86a66b");picker.set_block_signals(false);_recompose()
	)
	if _gender!="female":return
	if _custom.body_model=="female_base_v2":
		_add_native_shape_controls();return
	var title:=Label.new();title.text="胸部大小";slot_list.add_child(title)
	var row:=HBoxContainer.new();slot_list.add_child(row)
	var slider:=HSlider.new();slider.name="BustSize";slider.min_value=0;slider.max_value=100;slider.step=1
	slider.value=_custom.bust_size*100;slider.custom_minimum_size=Vector2(190,32);slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value:=Label.new();value.text=str(int(slider.value));value.custom_minimum_size.x=34;row.add_child(value)
	slider.value_changed.connect(func(number):_custom.bust_size=number/100.0;value.text=str(int(number));_recompose())
	var restore:=Button.new();restore.text="默认";restore.pressed.connect(func():slider.value=50);row.add_child(restore)

func _add_native_shape_controls()->void:
	var reset_all:=Button.new();reset_all.name="ResetBodyShapes";reset_all.text="重置全部体型参数"
	slot_list.add_child(reset_all)
	reset_all.pressed.connect(func():
		_custom.body_shapes.clear()
		_sync_native_shape_controls()
		_recompose()
	)
	var names:Dictionary={"bust_size":"胸部大小","waist_width":"腰部宽度","hip_size":"臀部大小","nose_width":"鼻部宽度","height":"身高（相对默认）"}
	for key:String in names:
		var label:=Label.new();label.text=names[key];slot_list.add_child(label)
		var row:=HBoxContainer.new();slot_list.add_child(row)
		var slider:=HSlider.new();slider.name="Shape_"+key
		var limits:Vector2=Customization.Shapes.RANGES[key]
		# The original Height morph's positive weight makes the body shorter.
		# Keep source weights in the recipe, but make the UI increase mean taller.
		var direction:float=-1.0 if key=="height" else 1.0
		slider.min_value=limits.x*100;slider.max_value=limits.y*100;slider.step=1
		slider.value=float(_custom.body_shapes.get(key,0.0))*100*direction
		slider.custom_minimum_size=Vector2(170,32);slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(slider)
		var value:=Label.new();value.text=str(int(slider.value));value.custom_minimum_size.x=38;row.add_child(value)
		slider.value_changed.connect(func(number):
			if number==0:_custom.body_shapes.erase(key)
			else:_custom.body_shapes[key]=number/100.0*direction
			value.text=str(int(number));_recompose()
		)
		var reset:=Button.new();reset.text="默认";reset.pressed.connect(func():slider.value=0);row.add_child(reset)


func _sync_native_shape_controls()->void:
	for key:String in Customization.Shapes.RANGES:
		var slider:=slot_list.find_child("Shape_"+key,true,false) as HSlider
		if slider==null:continue
		var direction:float=-1.0 if key=="height" else 1.0
		slider.set_value_no_signal(float(_custom.body_shapes.get(key,0))*100*direction)
		var label:=slider.get_parent().get_child(1) as Label
		if label:label.text=str(int(slider.value))

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
	if _view_3d!=null:
		_custom.part_ids=_part_ids.duplicate()
		_view_3d.configure(_gender,_custom.to_dict(),_custom.equipment)
		_portrait_3d.configure(_gender,_custom.to_dict(),_custom.equipment)
		for view in [_view_3d,_portrait_3d]:
			if view.model.imported_rig!=null:view.model.imported_rig.prepare_hair_choices(view.model)
		preview.sprite_frames=CharacterView3D.control_frames()
		_center_preview();_play_preview(false)
		return
	var parts := MV.apply_equipment(_part_ids, _custom.equipment)
	var res := MV.compose_preview(_gender, parts, _custom.colors())
	preview.sprite_frames = res["frames"]
	preview.scale = Vector2(3, 3)
	call_deferred("_center_preview")
	_play_preview()
	portrait.texture = res["portrait"]


func _setup_animation_controls() -> void:
	var row := HBoxContainer.new()
	preview_label.get_parent().add_child(row)
	var direction := OptionButton.new()
	var names := ["正面", "左侧", "右侧", "背面", "左前", "右前", "左后", "右后"]
	for label in names:
		direction.add_item(label)
	direction.item_selected.connect(func(i): _preview_direction = MV.DIRECTIONS[i]; _play_preview())
	row.add_child(direction)
	var action := OptionButton.new()
	for label in ["站立", "走动", "攻击", "冲刺", "施法", "死亡", "坐地", "坐椅子"]:
		action.add_item(label)
	action.select(1)
	var choices:Array=[]
	for id in MV.ACTIONS:choices.append([id,""])
	var library=preload("res://scripts/char/character_animation_library.gd")
	for id in library.ATTACKS:
		action.add_item(library.ATTACKS[id]);choices.append(["attack",id])
	for id in library.CASTS:
		action.add_item(library.CASTS[id]);choices.append(["cast",id])
	action.name="ActionPreview"
	action.item_selected.connect(func(i):
		_preview_action=choices[i][0];_preview_variant=choices[i][1]
		if _preview_variant.begins_with("attack_"):
			_custom.equipment["WeaponMain"]=1 if _preview_variant.begins_with("attack_sword") else null
			_recompose()
		_play_preview()
	)
	row.add_child(action)
	var replay := Button.new()
	replay.text = "重播"
	replay.pressed.connect(_play_preview)
	row.add_child(replay)
	var equipment_row := HBoxContainer.new()
	equipment_row.name = "EquipmentPreview"
	preview_label.get_parent().add_child(equipment_row)
	for entry in [["Clothing1", "上衣"], ["Clothing2", "下装"], ["Boots", "鞋子"], ["Belt", "腰带"]]:
		var toggle := CheckButton.new()
		var category: String = entry[0]
		toggle.text = entry[1]
		toggle.name = category
		toggle.button_pressed = true
		toggle.toggled.connect(func(on):
			_custom.equipment[category] = 1 if on else null
			_recompose()
		)
		equipment_row.add_child(toggle)


func _play_preview(restart:bool=true) -> void:
	if _view_3d!=null:
		_view_3d.play(_preview_action,_preview_direction,restart,_preview_variant)
		_portrait_3d.play("idle","front")
		preview_label.text="3D 人物 · 动作与换装预览"
		return
	if preview.sprite_frames == null:
		return
	var animation := _preview_action + "_" + _preview_direction
	if preview.sprite_frames.has_animation(animation):
		preview.stop()
		preview.play(animation)
		preview_label.text = "八向动作预览"


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
	if CharacterView3D.enabled():
		_custom.mv_sheet=""
		Net.server().create_character(name_edit.text,class_id,"",_gender,_custom.to_dict())
		return
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
		popup_grid.columns=15 if group=="hair" else 14
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
		grid.remove_child(c)
		c.queue_free()
	for e in entries:
		_add_swatch(grid, e as Dictionary, on_pick)


func _add_swatch(grid: GridContainer, entry: Dictionary, on_pick: Callable) -> void:
	var col: Color = entry["color"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(26, 24) if entry.has("label") else Vector2(16,16)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s (#%s)" % [str(entry.get("label","色带 %d"%int(entry["index"]))),col.to_html(false)]
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
	_set_btn_color(skin_color_btn, MV.row_color(_custom.skin_row))
	_set_btn_color(hair_color_btn, MV.row_color(_custom.hair_row))


func _on_random() -> void:
	_custom.randomize_colors()
	if _custom.body_model=="female_base_v2":
		var rng:=RandomNumberGenerator.new();rng.randomize()
		_custom.body_shapes=Customization.Shapes.random_values(rng)
		_sync_native_shape_controls()
	_custom.cloth_on=false
	_part_ids = MV.random_parts(_gender)
	if CharacterView3D.enabled():_part_ids={"Body":1,"FrontHair1":([10,11,12,13,14,15].pick_random() if _gender in ["male","female"] else randi_range(1,2)),"Eyes":1}
	if CharacterView3D.enabled() and _custom.body_model=="female_base_v2":_part_ids.FrontHair1=Hairstyles.random_choice(_gender,_custom.body_model)
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
