extends "res://tools/test_material_picker_ui.gd"

func review_workspace(editor: Node3D) -> void:
	var resources: MenuButton = editor.find_child("WorkspaceResourcesMenu", true, false)
	var play: MenuButton = editor.find_child("WorkspacePlayMenu", true, false)
	check(resources.get_popup().get_item_text(0) == "导入模型…" and resources.get_popup().get_item_text(1) == "素材管理…", "resource operations are available in the top menu")
	check(play.get_popup().get_item_text(0).contains("F5"), "play menu retains the discoverable F5 shortcut")
	play.get_popup().id_pressed.emit(1)
	check(editor._dock_tabs.current_tab == 7, "play settings menu opens floor and spawn settings")
	var toolbar: Control = editor.find_child("SceneToolbar", true, false)
	var actions: Control = editor.find_child("SceneToolbarActions", true, false)
	await frames()
	check(toolbar.size.x >= root.size.x - 4, "scene tools use the full window width")
	var fits := true
	for control in actions.get_children():
		if control is Control and control.visible:
			fits = fits and control.get_global_rect().end.x <= root.size.x and control.get_global_rect().end.y <= toolbar.get_global_rect().end.y
	check(fits and toolbar.size.y < 45, "scene tools fit one row at 1024 pixels without clipping")
	for index in 3:
		editor._transform_buttons[index].pressed.emit()
		check(editor._transform_mode == index, "relocated transform action %d works" % index)
	check(editor._canvas.global_position.y < 120, "canvas gains vertical space after toolbar consolidation")
	var nav: OptionButton = editor.find_child("WorkspacePanelPicker", true, false)
	check(nav != null and nav.item_count == editor._dock_tabs.get_tab_count(), "every dock is directly discoverable in the panel picker")
	for tab in editor._dock_tabs.get_tab_count():
		nav.select(tab); nav.item_selected.emit(tab)
		await frames(8)
		check(editor._dock_tabs.current_tab == tab, "navigation opens panel %d" % tab)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_usability/after_%d.png" % tab))
	editor._selection_tools.set_ids([]); editor._event_panel.refresh()
	check(editor._event_panel.apply_button.disabled and editor._event_panel.remove_button.disabled, "event actions are disabled without a selected object")
	editor._selection_tools.set_ids([editor._doc.records[0].uuid]); editor._event_panel.refresh()
	check(not editor._event_panel.apply_button.disabled and editor._event_panel.remove_button.disabled, "event removal stays disabled for an object without an event")
	var wind = editor._inspector.wind_panel
	check(not wind.details.visible, "advanced wind settings do not crowd ordinary object transforms")
	var wind_values: Dictionary = wind.form.values()
	wind.toggle.button_pressed = true
	check(wind.form.values() == wind_values, "expanding wind settings keeps existing parameters")
	wind.toggle.button_pressed = false
	var event_values: Dictionary = editor._event_panel.form.values()
	editor._event_panel.form.find_child("Section_conditions", true, false).button_pressed = true
	check(editor._event_panel.form.values() == event_values, "opening event conditions preserves the complete event form")
	editor._dock_tabs.current_tab = 1; await frames(8); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_usability/inspector_selected.png"))
	editor._dock_tabs.current_tab = 8; editor._building_panel.details_toggle.button_pressed = true
	await frames(8); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_usability/building_details.png"))
	editor._dock_tabs.current_tab = 6; await frames()
	check(nav.selected == 6, "toolbar and programmatic navigation update panel picker")
	var form = editor._environment_panel.form
	var before: Dictionary = form.values()
	var light: Button = form.find_child("Section_light", true, false)
	light.button_pressed = true
	check(form.find_child("Fields_light", true, false).visible and form.values() == before, "opening a settings group preserves all values")
	editor._environment_panel.fill(before)
	check(form.find_child("Fields_light", true, false).visible and form.values() == before, "rebuilding the form preserves expanded groups and hidden values")
	var ambient: SpinBox = form.fields.ambient_energy
	ambient.get_line_edit().grab_focus(); ambient.get_line_edit().text = "0.75"
	var values: Dictionary = form.values()
	check(is_equal_approx(values.ambient_energy, 0.75), "Apply reads numeric text that has not lost focus")
	var env_scroll: ScrollContainer = editor._environment_panel.get_parent()
	env_scroll.scroll_vertical = 10000; await frames()
	var apply_button: Button = env_scroll.get_parent().get_child(0)
	check(apply_button.get_global_rect().position.y < 160, "environment apply stays visible while scrolling")
	editor._dock_tabs.current_tab = 10; await frames()
	var terrain = editor._terrain_panel
	check(terrain.tasks.get_tab_count() == 2 and terrain.begin_button.get_global_rect().end.y < 450, "terrain sculpt action comes before creation parameters")
	check(terrain.begin_button.disabled and terrain.choice.text == "暂无可雕刻地形", "missing terrain has an explicit empty state and disabled brush")
	terrain.tasks.current_tab = 1; await frames()
	check(terrain.create_fields.is_visible_in_tree() and not terrain.brush_fields.is_visible_in_tree(), "creation and sculpting use separate task pages")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_usability/terrain_create.png"))
