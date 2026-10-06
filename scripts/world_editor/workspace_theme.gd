extends RefCounted
## U2U-inspired graphite workspace, scoped to the content editor.

static func panel(color: Color, margin: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("16171c")
	style.set_border_width_all(1)
	style.set_content_margin_all(margin)
	return style


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	for type in ["Label", "Button", "OptionButton", "MenuBar", "PopupMenu", "Tree", "TabContainer", "LineEdit"]:
		theme.set_color("font_color", type, Color("cbd0d8"))
		theme.set_color("font_hover_color", type, Color("ffffff"))
		theme.set_color("font_pressed_color", type, Color("ffffff"))
		theme.set_color("font_selected_color", type, Color("ffffff"))
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, panel(Color("292a31"), 5))
		theme.set_stylebox("hover", type, panel(Color("373a44"), 5))
		var selected := panel(Color("263c48"), 5)
		selected.border_color = Color("31b6df")
		theme.set_stylebox("pressed", type, selected)
		theme.set_stylebox("hover_pressed", type, selected)
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	for type in ["Tree", "ItemList", "LineEdit", "PopupMenu"]:
		theme.set_stylebox("panel" if type != "LineEdit" else "normal", type, panel(Color("1f2026")))
	var selection := panel(Color("263c48"), 2)
	selection.border_color = Color("31b6df")
	theme.set_stylebox("selected", "Tree", selection)
	theme.set_stylebox("selected_focus", "Tree", selection)
	theme.set_stylebox("selected", "ItemList", selection)
	theme.set_stylebox("selected_focus", "ItemList", selection)
	theme.set_stylebox("hovered", "ItemList", panel(Color("353943"), 2))
	theme.set_constant("v_separation", "Tree", 5)
	theme.set_stylebox("panel", "PanelContainer", panel(Color("24252c")))
	theme.set_stylebox("panel", "TabContainer", panel(Color("24252c"), 6))
	theme.set_stylebox("tab_selected", "TabContainer", selection)
	theme.set_stylebox("tab_unselected", "TabContainer", panel(Color("1f2026"), 6))
	theme.set_constant("separation", "HSplitContainer", 5)
	theme.set_constant("separation", "VSplitContainer", 5)
	return theme
