extends RefCounted
## Theme variations scale together, including controls created by later forms.
## No per-frame traversal or control-local font override is needed.

static func apply(workspace: Control, font_size: int) -> void:
	if workspace.theme == null:
		workspace.theme = preload("res://scripts/world_editor/workspace_theme.gd").build()
	var theme := workspace.theme
	var base := clampi(font_size, 14, 18)
	theme.default_font_size = base
	for variation in ["EditorTitle", "EditorHeading", "EditorCaption"]:
		theme.set_type_variation(variation, "Label")
	theme.set_type_variation("EditorAssetList", "ItemList")
	theme.set_font_size("font_size", "EditorTitle", base + 4)
	theme.set_font_size("font_size", "EditorHeading", base + 2)
	theme.set_font_size("font_size", "EditorCaption", maxi(12, base - 2))
	theme.set_font_size("font_size", "EditorAssetList", maxi(13, base - 1))
