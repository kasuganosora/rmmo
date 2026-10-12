extends SceneTree
const Typography = preload("res://scripts/world_editor/workspace_typography.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok: failures += 1
func run() -> void:
	var workspace := VBoxContainer.new()
	root.add_child(workspace)
	var body := Label.new(); workspace.add_child(body)
	var title := Label.new(); title.theme_type_variation = "EditorTitle"; workspace.add_child(title)
	var heading := Label.new(); heading.theme_type_variation = "EditorHeading"; workspace.add_child(heading)
	var caption := Label.new(); caption.theme_type_variation = "EditorCaption"; workspace.add_child(caption)
	var list := ItemList.new(); list.theme_type_variation = "EditorAssetList"; workspace.add_child(list)
	Typography.apply(workspace, 14)
	await process_frame
	await process_frame
	check(body.get_theme_font_size("font_size") == 14, "default remains compact at 14")
	check(title.get_theme_font_size("font_size") == 18 and heading.get_theme_font_size("font_size") == 16, "default heading hierarchy is preserved")
	check(caption.get_theme_font_size("font_size") == 12 and list.get_theme_font_size("font_size") == 13, "default compact caption and asset list are preserved")
	Typography.apply(workspace, 18)
	await process_frame
	await process_frame
	check(body.get_theme_font_size("font_size") == 18, "body follows large type setting")
	check(title.get_theme_font_size("font_size") == 22 and heading.get_theme_font_size("font_size") == 20, "titles remain larger than enlarged body")
	check(caption.get_theme_font_size("font_size") == 16 and list.get_theme_font_size("font_size") == 17, "captions and asset names enlarge with the setting")
	var rebuilt := Label.new(); rebuilt.theme_type_variation = "EditorHeading"; workspace.add_child(rebuilt)
	check(rebuilt.get_theme_font_size("font_size") == 20, "later rebuilt forms inherit current heading size")
	Typography.apply(workspace, 14)
	await process_frame
	await process_frame
	check(rebuilt.get_theme_font_size("font_size") == 16 and caption.get_theme_font_size("font_size") == 12, "return to default updates existing and rebuilt controls")
	workspace.queue_free()
	await process_frame
	print("EDITOR_TYPOGRAPHY_FINISHED failures=", failures)
	quit(failures)
