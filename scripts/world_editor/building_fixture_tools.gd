extends RefCounted
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")

static func list_components(editor: Node, id: String) -> Dictionary:
	if not editor._buildings.instances().has(id): return {"ok":false,"error":"建筑不存在"}
	return {"ok":true,"building_id":id,"components":Fixtures.rows(editor._doc.records,id)}

static func set_open(editor: Node, id: String, component: String, amount: float) -> Dictionary:
	var ready: Dictionary=editor._gameplay.guard()
	if not ready.ok: return ready
	if not is_finite(amount) or amount<0 or amount>1: return {"ok":false,"error":"开合值必须为 0～1"}
	var found:=list_components(editor,id)
	if not found.ok: return found
	var rows: Array=found.components.filter(func(row):return row.id==component)
	if rows.is_empty(): return {"ok":false,"error":"该建筑中不存在此活动组件"}
	var changed:=false
	for uuid in rows[0].members:
		var record: Dictionary=editor._doc._find(uuid)
		if not editor._record_editable(record): return {"ok":false,"error":"门窗组件被锁定、隐藏或处于隔离楼层之外"}
		if not is_equal_approx(record.fixture.open,amount): changed=true
	if not changed: return {"ok":true,"changed":false}
	editor._doc.checkpoint_recovery()
	for uuid in rows[0].members: editor._doc._find(uuid).fixture.open=amount
	var members: Array[String]=[]; members.assign(rows[0].members)
	editor._dirty=true; editor._refresh_records(members)
	editor._selection_tools.invalidate_pivot(); editor._selection_tools.refresh()
	if editor._building_panel!=null: editor._building_panel.refresh_list(id)
	return {"ok":true,"changed":true,"building_id":id,"component_id":component,"open":amount}
