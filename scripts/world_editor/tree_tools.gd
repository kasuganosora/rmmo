extends RefCounted
const TreeModel=preload("res://scripts/world3d/parametric_tree.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
static func describe(editor:Node3D,id:String)->Dictionary:
	var record:Dictionary=editor._doc._find(id)
	var root:Node=editor._view.get_node_or_null(NodePath(id)) if editor._view!=null else null
	if root==null:return {"supported":false}
	var settings:=TreeModel.resolved(root,record)
	return {"supported":not settings.is_empty(),"settings":settings,"schema":TreeModel.schema()}
static func apply(editor:Node3D,ids:Array,changes:Dictionary)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	var error:=TreeModel.Schema.validate(changes,TreeModel.schema())
	if not error.is_empty():return {"ok":false,"error":error}
	if ids.is_empty() or ids.size()>32:return {"ok":false,"error":"请选择 1～32 棵参数化树木"}
	var updates:Dictionary={}
	for id in ids:
		if updates.has(id):return {"ok":false,"error":"不能重复选择同一棵树"}
		var record:Dictionary=editor._doc._find(str(id))
		if record.is_empty() or not editor._record_editable(record) or record.get("prefab_locked",false) or record.has("building") or record.get("kind")!="asset":return {"ok":false,"error":"树木不存在、隐藏、锁定或属于固定建筑"}
		var model:=Library.instantiate_preview(str(record.asset_path))
		if model==null:return {"ok":false,"error":"树木资源无法读取"}
		var config:=TreeModel.resolved(model,record)
		if config.is_empty():model.free();return {"ok":false,"error":"请放置参数化松树预制件；普通模型没有枝簇配方"}
		config.merge(changes,true)
		var next:=record.duplicate(true);next.tree_settings=config
		if not TreeModel.valid(next):model.free();return {"ok":false,"error":"裸干长度须小于树高的 80%，参数须在允许范围内"}
		error=TreeModel.apply(model,next)
		if not error.is_empty():model.free();return {"ok":false,"error":error}
		var bounds:=Library.bounds_of(model);model.free()
		next.bounds_position=[bounds.position.x,bounds.position.y,bounds.position.z];next.bounds_size=[bounds.size.x,bounds.size.y,bounds.size.z]
		updates[id]=next
	if updates.values().all(func(r):return r==editor._doc._find(r.uuid)):return {"ok":true,"changed_ids":[]}
	editor._doc.checkpoint()
	for id in updates:
		var record:Dictionary=editor._doc._find(str(id));record.merge(updates[id],true)
	editor._dirty=true;editor._rebuild()
	return {"ok":true,"changed_ids":updates.keys()}
