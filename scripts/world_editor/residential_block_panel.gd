extends VBoxContainer
## Reuses the single-house form as a row editor; terrain is shared by the queue.
const Block=preload("res://scripts/world_editor/residential_block_tools.gd")
var owner_panel:VBoxContainer
var homes:Array=[]
var choice:OptionButton
var next_id:=1

func setup(value:VBoxContainer)->void:
	owner_panel=value
	owner_panel.note(self,"街区队列（最多 16 栋）：上方编辑一户后加入或更新队列，下方整地供全组共用。按队列顺序选取可行位置和退距，最后逐户复查；整组通过才一次应用。编辑上方表单后需点更新，才能改动已入列的一户。")
	choice=OptionButton.new();choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;add_child(choice)
	var row:=HBoxContainer.new();add_child(row)
	owner_panel.action(row,"加入此户",add_current)
	owner_panel.action(row,"更新选中户",replace_current)
	row=HBoxContainer.new();add_child(row)
	owner_panel.action(row,"载入选中户",load_current)
	owner_panel.action(row,"移除选中户",remove_current)
	row=HBoxContainer.new();add_child(row)
	owner_panel.action(row,"上移",func():move_current(-1))
	owner_panel.action(row,"下移",func():move_current(1))
	refresh()

func refresh(index:int=-1)->void:
	choice.clear()
	for row:Dictionary in homes:
		var p:Dictionary=row.residential
		choice.add_item("%s · %s · (%.3f, %.3f, %.3f) → %s"%[row.id,"迁移" if p.has("building_id") else "新增",p.position[0],p.position[1],p.position[2],p.road_edge_id])
	if not homes.is_empty():choice.select(clampi(index,0,homes.size()-1))

func add_current()->void:
	if homes.size()>=Block.MAX_HOMES:owner_panel.report({"ok":false,"error":"每组最多 16 栋，请分组建设。"});return
	homes.append({"id":"home_%d"%next_id,"residential":owner_panel.house_request()});next_id+=1
	owner_panel.invalidate_preview();refresh(homes.size()-1)

func replace_current()->void:
	if choice.selected<0:return
	var index:=choice.selected;homes[index].residential=owner_panel.house_request()
	owner_panel.invalidate_preview();refresh(index)

func load_current()->void:
	if choice.selected<0:return
	var p:Dictionary=homes[choice.selected].residential.duplicate(true)
	owner_panel.relocation_enabled.button_pressed=p.has("building_id");owner_panel.refresh_catalogs()
	select_value(owner_panel.road_choice,p.road_edge_id)
	if p.has("building_id"):
		select_value(owner_panel.building_choice,p.building_id);select_value(owner_panel.old_access_choice,p.get("old_access","keep"))
	else:select_value(owner_panel.asset_choice,p.asset_id)
	for key in ["road_edge_id","building_id","asset_id","old_access"]:p.erase(key)
	owner_panel.form.update_values(p);owner_panel.invalidate_preview("已载入此户，编辑后点击更新选中户。")

static func select_value(control:OptionButton,id:String)->void:
	control.select(0)
	for i in control.item_count:
		if control.get_item_metadata(i)==id:control.select(i);return

func remove_current()->void:
	if choice.selected<0:return
	var index:=choice.selected;homes.remove_at(index);owner_panel.invalidate_preview();refresh(index)

func move_current(offset:int)->void:
	var index:=choice.selected;var target:=index+offset
	if index<0 or target<0 or target>=homes.size():return
	var row:Dictionary=homes[index];homes.remove_at(index);homes.insert(target,row)
	owner_panel.invalidate_preview();refresh(target)
