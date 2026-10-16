extends RefCounted
const Components=preload("res://scripts/world3d/model_components.gd")

static func list_components(editor:Node,id:String)->Dictionary:
	var record:Dictionary=editor._doc._find(id)
	if record.get("kind")!="asset":return {"ok":false,"error":"导入模型不存在"}
	var node:Node=editor._view.get_node_or_null(NodePath(id))
	if node==null:return {"ok":false,"error":"模型尚未加载"}
	var rows:Array=Components.rows(node)
	if record.has("model_building"):
		var settings:Dictionary=preload("res://scripts/world3d/editor_view_settings.gd").resolve(editor._doc.map_meta)
		for row:Dictionary in rows:row.editable=editor._record_editable(record) and preload("res://scripts/world3d/imported_building.gd").floor_in_view(record,row,settings)
	return {"ok":true,"building_id":id,"components":rows}

static func set_open(editor:Node,id:String,component:String,amount:float)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	if not is_finite(amount) or amount<0 or amount>1:return {"ok":false,"error":"开合值必须为 0～1"}
	var record:Dictionary=editor._doc._find(id)
	if not editor._record_editable(record):return {"ok":false,"error":"模型被锁定、隐藏或不可编辑"}
	var found:=list_components(editor,id)
	if not found.ok:return found
	var rows:Array=found.components.filter(func(row):return row.id==component)
	if rows.is_empty():return {"ok":false,"error":"模型中不存在此活动组件"}
	if record.has("model_building"):
		var settings:Dictionary=preload("res://scripts/world3d/editor_view_settings.gd").resolve(editor._doc.map_meta)
		if not preload("res://scripts/world3d/imported_building.gd").floor_in_view(record,rows[0],settings):return {"ok":false,"error":"该活动组件不在当前可编辑楼层"}
	if is_equal_approx(rows[0].open,amount):return {"ok":true,"changed":false}
	editor._doc.checkpoint_recovery()
	var state_key:String="model_building_states" if record.has("model_building") else "model_component_states"
	var states:Dictionary=record.get(state_key,{}).duplicate()
	states[component]=amount;record[state_key]=states
	editor._dirty=true
	var ids:Array[String]=[id];editor._refresh_records(ids)
	editor._selection_tools.invalidate_pivot();editor._selection_tools.refresh()
	return {"ok":true,"changed":true,"building_id":id,"component_id":component,"open":amount}
