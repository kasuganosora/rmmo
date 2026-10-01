extends RefCounted
const UI = preload("res://scripts/world_editor/placement_panel.gd")

static func show_settings(editor: Node3D) -> void:
	if editor.get_node_or_null("AutosaveSettings") != null: return
	var dialog := AcceptDialog.new()
	dialog.name = "AutosaveSettings"
	dialog.title = "自动草稿"
	dialog.ok_button_text = "应用"
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var enabled := CheckBox.new()
	enabled.name = "AutosaveEnabled"
	enabled.text = "自动保存恢复草稿"
	enabled.button_pressed = editor._safety.enabled
	box.add_child(enabled)
	var interval := SpinBox.new()
	interval.name = "AutosaveInterval"
	interval.min_value = 15
	interval.max_value = 600
	interval.step = 15
	interval.value = editor._safety.interval_seconds
	interval.suffix = "秒"
	box.add_child(interval)
	var note := Label.new()
	note.text = "草稿独立存放，不覆盖正式地图。\n拖动、画笔或文字输入期间暂缓。\n设置只影响当前编辑会话。"
	box.add_child(note)
	dialog.confirmed.connect(func():
		interval.apply()
		editor._safety.configure(enabled.button_pressed, interval.value)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	editor.add_child(dialog)
	dialog.popup_centered(Vector2i(360, 210))

static func show_panel(editor: Node3D) -> void:
	var dialog := AcceptDialog.new()
	dialog.name = "DraftRecoveryDialog"
	dialog.title = "恢复地图草稿"
	dialog.ok_button_text = "关闭"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)
	var note := Label.new()
	note.text = "恢复到编辑器后可检查并保存；正式地图不会立即改变。"
	box.add_child(note)
	var list := ItemList.new()
	list.name = "DraftList"
	list.custom_minimum_size = Vector2(650, 240)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(list)
	var info := Label.new()
	info.name = "DraftDetails"
	info.custom_minimum_size = Vector2(650, 70)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	var page := [0]
	var total := [0]
	var refresh := func():
		var result: Dictionary = editor._safety.store.list_drafts(page[0], 50)
		list.clear()
		total[0] = result.get("total", 0)
		info.text = "共 %d 份草稿 · 当前第 %d 页" % [total[0], page[0] / 50 + 1] if result.ok else str(result.error)
		for draft in result.get("drafts", []):
			var title := "损坏草稿 · " + str(draft.draft_id).right(12)
			if draft.get("recoverable", false):
				title = "%s · %s UTC · %d 件%s" % [str(draft.map_path).get_file(), Time.get_datetime_string_from_unix_time(int(draft.saved_at)).replace("T", " "), draft.object_count, " · 磁盘已变化" if draft.source_changed else ""]
			var index := list.add_item(title)
			list.set_item_metadata(index, draft)
	list.item_selected.connect(func(index: int):
		var draft: Dictionary = list.get_item_metadata(index)
		info.text = str(draft.get("map_path", draft.get("error", "")))
		if draft.get("source_changed", false): info.text += "\n磁盘版本已变化；恢复后需另存为，避免覆盖其他修改。"
	)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	var act := func(remove: bool):
		if list.get_selected_items().is_empty(): info.text = "请先选择一份草稿"; return
		var draft: Dictionary = list.get_item_metadata(list.get_selected_items()[0])
		if not remove and not draft.get("recoverable", false): info.text = str(draft.error); return
		var confirm := ConfirmationDialog.new()
		confirm.name = "DraftActionConfirm"
		confirm.dialog_text = "删除这份草稿及其上一版？当前地图保持不变。" if remove else "恢复这份草稿到编辑器？当前未保存内容会先备份为草稿，正式地图保持不变。"
		confirm.confirmed.connect(func():
			var outcome: Dictionary = editor._safety.discard(draft.draft_id) if remove else editor._safety.restore(draft.draft_id, true)
			if outcome.ok and not remove: dialog.queue_free()
			else:
				refresh.call()
				info.text = "已删除草稿" if outcome.ok else str(outcome.error)
			confirm.queue_free()
		)
		confirm.canceled.connect(confirm.queue_free)
		dialog.add_child(confirm)
		confirm.popup_centered(Vector2i(520, 150))
	UI.button(actions, "恢复所选草稿", act.bind(false), "RestoreDraft")
	UI.button(actions, "删除所选草稿…", act.bind(true), "DiscardDraft")
	UI.button(actions, "刷新", refresh)
	UI.button(actions, "上一页", func(): page[0] = maxi(0, page[0] - 50); refresh.call())
	UI.button(actions, "下一页", func():
		if page[0] + 50 < total[0]: page[0] += 50
		refresh.call()
	)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	editor.add_child(dialog)
	refresh.call()
	dialog.popup_centered(Vector2i(700, 470))
