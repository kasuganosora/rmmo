extends RefCounted
## Compact terrain forms keep the existing controls and SettingsForm contract.
## Call after grouping: material names and vector inputs retain the full width.
static func apply(form:VBoxContainer,short_names:Dictionary)->void:
	for key in form.fields:
		var control:Control=form.fields[key]
		if control is HBoxContainer or control is TextEdit or str(key).ends_with("_material_id"):continue
		pair(form._labels[key],control,str(short_names.get(key,form._labels[key].text)))

static func pair(label:Label,control:Control,short_name:String)->void:
	if control.get_parent().get_meta("terrain_compact_row",false):return
	var parent:=label.get_parent(); var index:=label.get_index(); var detail:=label.text
	var row:=HBoxContainer.new(); row.name="FieldRow"; row.set_meta("terrain_compact_row",true); row.add_theme_constant_override("separation",6)
	parent.add_child(row); parent.move_child(row,index)
	label.reparent(row); control.reparent(row)
	label.text=short_name; label.tooltip_text=detail; label.autowrap_mode=TextServer.AUTOWRAP_OFF
	label.clip_text=true; label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if control.tooltip_text.is_empty():control.tooltip_text=detail
	if control is CheckButton:
		label.hide(); control.text=short_name; control.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	else:
		label.custom_minimum_size.x=100; control.custom_minimum_size.x=110

static func show_field(form:VBoxContainer,key:String,shown:bool)->void:
	var control:Control=form.fields[key]; var label:Label=form._labels[key]
	if control.get_parent().get_meta("terrain_compact_row",false):control.get_parent().visible=shown
	control.visible=shown; label.visible=shown and not control is CheckButton
