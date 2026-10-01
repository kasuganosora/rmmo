extends VBoxContainer
## Schema-driven fields shared by the event and environment authoring panels.
var fields := {}

func build(schema: Dictionary, values: Dictionary, labels: Dictionary, choices: Dictionary = {}) -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	fields.clear()
	for key in values:
		var spec: Dictionary = schema.properties[key]
		var label := Label.new(); label.text = labels.get(key, key); add_child(label)
		var control: Control
		if spec.has("enum") or choices.has(key):
			var select := OptionButton.new(); select.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			var options: Array = choices.get(key, spec.get("enum", []))
			for item in options:
				var value: Variant = item.id if item is Dictionary else item
				select.add_item(str(item.name) if item is Dictionary else str(item))
				select.set_item_metadata(select.item_count - 1, value)
				if value == values[key]: select.select(select.item_count - 1)
			if not options.any(func(item): return (item.id if item is Dictionary else item) == values[key]):
				select.add_item(str(values[key])); select.set_item_metadata(select.item_count - 1, values[key]); select.select(select.item_count - 1)
			control = select
		elif spec.type == "boolean":
			var toggle := CheckButton.new(); toggle.text = "启用"; toggle.button_pressed = values[key]; control = toggle
		elif spec.type == "array":
			if key.ends_with("color"):
				var picker := ColorPickerButton.new(); picker.edit_alpha = false; picker.color = Color(values[key][0], values[key][1], values[key][2]); control = picker
			else:
				var row := HBoxContainer.new()
				for axis in 3:
					var spin := number(spec.items, values[key][axis]); spin.prefix = ["X", "Y", "Z"][axis]; spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(spin)
				control = row
		elif spec.type in ["number", "integer"]: control = number(spec, values[key])
		elif key in ["text", "empty_text"]:
			var edit := TextEdit.new(); edit.text = values[key]; edit.custom_minimum_size.y = 80; edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; control = edit
		else:
			var edit := LineEdit.new(); edit.text = values[key]; control = edit
		add_child(control); fields[key] = control

func number(spec: Dictionary, value: float) -> SpinBox:
	var spin := SpinBox.new(); spin.min_value = spec.get("minimum", -100000); spin.max_value = spec.get("maximum", 100000)
	spin.step = 1 if spec.type == "integer" else .001
	spin.value = value
	return spin

func values() -> Dictionary:
	var result := {}
	for key in fields:
		var control: Control = fields[key]
		if control is OptionButton: result[key] = control.get_item_metadata(control.selected)
		elif control is CheckButton: result[key] = control.button_pressed
		elif control is ColorPickerButton: result[key] = [control.color.r, control.color.g, control.color.b]
		elif control is SpinBox: result[key] = control.value
		elif control is HBoxContainer: result[key] = control.get_children().map(func(spin): return spin.value)
		else: result[key] = control.text
	return result
