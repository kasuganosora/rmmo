extends RefCounted
## Menus consume the material panel's published catalog, never scan it again.
## Keep an explicit unavailable selection until the user changes it; applying
## still goes through the shared business validator and cannot silently use a
## different material while a catalog is loading or an entry has been removed.
static func bind_menu(menu:OptionButton,panel:VBoxContainer,label:String,preferred:String="")->void:
	menu.set_meta("material_default_pending",preferred)
	_refresh(menu,panel,label,not panel._entries.is_empty())
	# Each menu needs its own callable identity (static bound methods compare
	# as the same signal target in Godot).
	var refresh:=func():_refresh(menu,panel,label,true)
	panel.catalog_changed.connect(refresh)
	menu.tree_exiting.connect(func():
		if is_instance_valid(panel) and panel.catalog_changed.is_connected(refresh):panel.catalog_changed.disconnect(refresh)
	)
	menu.item_selected.connect(func(_index):menu.remove_meta("material_default_pending"))

static func _refresh(menu:OptionButton,panel:VBoxContainer,label:String,published:bool)->void:
	if not is_instance_valid(menu):return
	var selected:String=str(menu.get_item_metadata(menu.selected)) if menu.selected>=0 else ""
	var desired:=selected
	if desired.is_empty():desired=str(menu.get_meta("material_default_pending",""))
	menu.clear();menu.remove_meta("material_missing_id");menu.add_item(label);menu.set_item_metadata(0,"")
	var found:=false
	for entry in panel._entries:
		menu.add_item(str(entry.material.name));menu.set_item_metadata(menu.item_count-1,entry.material_id)
		if entry.material_id==desired:menu.select(menu.item_count-1);found=true
	if not found and not selected.is_empty():choose(menu,selected)
	# A preferred initial default is applied once, never after a later import
	# over an explicit choice of the plain/unbound material.
	if published:menu.remove_meta("material_default_pending")

static func choose(menu:OptionButton,id:String)->void:
	menu.remove_meta("material_default_pending")
	var missing:String=str(menu.get_meta("material_missing_id",""))
	if not missing.is_empty():
		for i in menu.item_count:
			if menu.get_item_metadata(i)==missing:menu.remove_item(i);break
		menu.remove_meta("material_missing_id")
	for i in menu.item_count:
		if menu.get_item_metadata(i)==id:menu.select(i);return
	menu.add_item("未找到材质："+id);menu.set_item_metadata(menu.item_count-1,id);menu.select(menu.item_count-1)
	menu.set_meta("material_missing_id",id)
