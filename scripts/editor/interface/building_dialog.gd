extends RefCounted
const Generator=preload("res://scripts/editor/domain/building_generator.gd")
const Blit=preload("res://scripts/map/tile_blit.gd")
static func open(editor) -> void:
	if editor.doc==null or editor.pack==null:return
	var kits: Dictionary=editor.pack.tilesets.get(editor.doc.tileset_id,{}).get("buildingKits",{})
	var dialog:=AcceptDialog.new();dialog.title="参数化住宅";dialog.min_size=Vector2i(580,620)
	dialog.dialog_hide_on_ok=false;dialog.get_ok_button().text="生成 / 更新建筑"
	editor.add_child(dialog)
	var box:=VBoxContainer.new();dialog.add_child(box)
	var message:=Label.new();message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if kits.is_empty():
		message.text="当前图块套没有住宅组件。请先导入建筑组件套件。";box.add_child(message)
		dialog.get_ok_button().disabled=true;dialog.popup_centered();dialog.canceled.connect(dialog.queue_free);return
	var kit_ids: Array=kits.keys();var options:=OptionButton.new()
	for id in kit_ids:options.add_item(str(kits[id].get("name",id)))
	box.add_child(options)
	var grid:=GridContainer.new();grid.columns=2;box.add_child(grid)
	var inputs: Dictionary={}
	for row in [["x","位置 X",0,editor.doc.width-1,editor._cursor.x],["y","位置 Y",0,editor.doc.height-1,editor._cursor.y],["bays","立面开间",1,3,1],["floors","楼层",1,3,2]]:
		var label:=Label.new();label.text=str(row[1]);grid.add_child(label)
		var spin:=SpinBox.new();spin.min_value=float(row[2]);spin.max_value=float(row[3]);spin.step=1;spin.value=float(row[4]);grid.add_child(spin);inputs[row[0]]=spin
	var roof:=OptionButton.new();roof.add_item("红瓦屋顶");roof.add_item("蓝灰瓦屋顶");box.add_child(roof)
	var windows:=CheckBox.new();windows.text="显示窗户";windows.button_pressed=true;box.add_child(windows)
	var instance:=LineEdit.new();instance.placeholder_text="实例名称（相同名称更新原建筑）";box.add_child(instance)
	var initial_id: String="house_%d_%d"%[editor._cursor.x,editor._cursor.y]
	instance.text=initial_id
	if editor.doc.building_instances.has(initial_id):
		var saved: Dictionary=editor.doc.building_instances[initial_id].parameters
		inputs.bays.value=int(saved.bays);inputs.floors.value=int(saved.floors)
		roof.select(1 if saved.roof=="slate" else 0);windows.button_pressed=bool(saved.windows)
	var preview:=TextureRect.new();preview.custom_minimum_size=Vector2(400,320)
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;box.add_child(preview);box.add_child(message)
	var sheets: Array=editor.pack._sheets_for(editor.doc)
	var parameters=func() -> Dictionary:
		return {"x":int(inputs.x.value),"y":int(inputs.y.value),"bays":int(inputs.bays.value),"floors":int(inputs.floors.value),"roof":"red" if roof.selected==0 else "slate","windows":windows.button_pressed,"instance_id":instance.text}
	var refresh=func():
		var result: Dictionary=Generator.compose(kits[kit_ids[options.selected]],parameters.call())
		if not result.ok:message.text=str(result.error);return
		var image:=Image.create(int(result.w)*48,int(result.h)*48,false,Image.FORMAT_RGBA8)
		image.fill(Color(0,0,0,0))
		for z in [1,2,3]:
			for cell in result.cells:
				if int(cell.z)==z:Blit.blit_tile(image,int(cell.tile_id),int(cell.x)*48,int(cell.y)*48,sheets)
		preview.texture=ImageTexture.create_from_image(image)
		message.text="%d × %d 格 · 墙体、门窗、屋顶分层；门窗尺寸固定。"%[result.w,result.h]
	for input in inputs.values():input.value_changed.connect(func(_v):refresh.call())
	options.item_selected.connect(func(_v):refresh.call());roof.item_selected.connect(func(_v):refresh.call())
	windows.toggled.connect(func(_v):refresh.call())
	dialog.confirmed.connect(func():
		var result: Dictionary=Generator.place(editor.doc,kits[kit_ids[options.selected]],parameters.call())
		if not result.ok:message.text=str(result.error);return
		editor._refresh_dirty(result.dirty);editor._status.text="已生成分层住宅："+str(result.instance_id)
		dialog.hide();dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);refresh.call();dialog.popup_centered()
