extends RefCounted
## Shared UI helper for item/skill drag previews (MV icon or letter fallback).


static func make_drag_preview(display_name: String, icon_index: int = -1, icon_ref: String = "", size: Vector2 = Vector2(40, 40)) -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var am: Node = tree.root.get_node_or_null("AssetManager")
		if am != null and am.has_method("make_drag_preview"):
			return am.make_drag_preview(display_name, icon_index, icon_ref, size)
	# Offline / no AssetManager: letter-only panel.
	var preview := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.16, 0.15, 0.14, 0.92)
	psb.border_color = Color(0.75, 0.6, 0.3, 1)
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(3)
	psb.set_content_margin_all(4)
	preview.add_theme_stylebox_override("panel", psb)
	preview.custom_minimum_size = size
	var pl := Label.new()
	pl.name = "Letter"
	var nm := display_name.strip_edges()
	pl.text = nm.substr(0, 1) if not nm.is_empty() else "?"
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.add_theme_font_size_override("font_size", 22)
	pl.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(pl)
	return preview
